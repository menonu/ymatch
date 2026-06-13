//! Match aggregate repository.
//!
//! [`MatchRepository`] is the abstract interface used by handlers and the
//! [`crate::services::match_lifecycle::MatchLifecycleService`] for the
//! trade lifecycle (offer / status / inventory apply).
//!
//! Phase 4 of #163 fixes the N+1 problem in the previous
//! `handlers::matches::list_matches` (1 + 4N queries for N matches) by
//! replacing it with [`MatchRepository::list_for_user`], which runs **4
//! queries total**: matches + other_user via JOIN, haves batched,
//! wants batched, match_items batched. The in-memory join happens
//! inside the repository.
//!
//! **Transactional writes** (`offer`, `change_status`,
//! `apply_inventory`) are still inlined in the
//! [`crate::services::match_lifecycle::MatchLifecycleService`].
//! Issue #174 proposed adding `_in_tx` variants of the SQL to this
//! trait, but the NLL borrow checker holds a future that captures
//! `&mut Transaction` (which has a `Drop` impl) for the whole
//! function scope, so the explicit `tx.commit()` afterwards is
//! rejected. The trait methods were prototyped (see git history)
//! but rolled back; the SQL stays in the service. Follow-up
//! work to land #174 is tracked but unblocked.

use crate::error::AppError;
use crate::generated::ymatch::{MatchItem, NotificationCounts, OfferItem, TradeMatch, User};
use crate::handlers::mappers::to_rfc3339;
use crate::repositories::RepositoryFuture;
use sqlx::{PgPool, Row};
use std::collections::HashMap;

/// Read-only snapshot of a match's status fields. Used by the lifecycle
/// service for the inventory-apply endpoint.
#[derive(Debug, Clone)]
pub struct MatchStatusSnapshot {
    pub user1_id: i32,
    pub user2_id: i32,
    pub status: String,
    pub offered_by: Option<i32>,
    pub user1_applied: bool,
    pub user2_applied: bool,
}

/// Abstract match repository.
///
/// Methods come in two flavors:
///
/// - **Pool methods** (no suffix): own their own connection from the
///   pool. Used by HTTP handlers for one-shot reads.
/// - **`_conn` methods**: take a `&mut PgConnection` so the caller
///   can compose multiple repository calls into a single
///   transaction by passing `&mut *tx`. Used by the lifecycle
///   service. The standard pattern in sqlx: the service opens
///   the transaction, the repo methods are executor-agnostic, and
///   the same `tx` is reused across calls via short-lived reborrows.
///
/// Read methods (no suffix) run on the pool.
pub trait MatchRepository: Send + Sync {
    /// List all matches in the system (admin).
    fn list_all<'a>(&'a self) -> RepositoryFuture<'a, Result<Vec<TradeMatch>, AppError>>;

    /// List matches for a user with all related data pre-loaded. This is
    /// the N+1 fix — see the module-level docs.
    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<TradeMatch>, AppError>>;

    /// Read the snapshot of a match's status fields. Used by the
    /// inventory-apply endpoint.
    fn get_status_snapshot<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<MatchStatusSnapshot>, AppError>>;

    /// List `match_items` joined with `merchandise` for the apply endpoint.
    fn list_match_items<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<MatchItem>, AppError>>;

    /// Notification counts (pending / offers_in / accepted / unread) for a
    /// user. Replaces the 4 separate `query_scalar` calls in the old
    /// `match_notification_counts` handler.
    fn notification_counts<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<NotificationCounts, AppError>>;

    // ---- `_conn` methods: take a `&mut PgConnection` so the caller
    // ---- controls the transaction. Pass `&mut *tx` from inside a
    // ---- `pool.begin()` block.

    /// `SELECT ... FOR UPDATE` on a match row. Returns the snapshot if
    /// the row exists, `None` otherwise. The row lock is held until
    /// the surrounding transaction ends.
    fn lock_for_update_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<MatchStatusSnapshot>, AppError>>;

    /// Set the match's `status` column.
    fn set_status_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
        new_status: &'a str,
    ) -> RepositoryFuture<'a, Result<(), AppError>>;

    /// Set the match's `offered_by` column.
    fn set_offered_by_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>>;

    /// Bulk-insert match_items rows for an offer.
    fn insert_match_items_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
        owner_id: i32,
        items: &'a [OfferItem],
    ) -> RepositoryFuture<'a, Result<(), AppError>>;

    /// Delete all match_items rows for a match. Used when a match is
    /// rejected.
    fn delete_match_items_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>>;

    /// Delete all other PENDING matches between the same pair of
    /// users. Used when a match is accepted.
    fn purge_other_pending_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        skip_match_id: i32,
        user1_id: i32,
        user2_id: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>>;

    /// Set the per-user inventory-applied timestamp. `is_user1` picks
    /// which column to write.
    fn mark_inventory_applied_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
        is_user1: bool,
    ) -> RepositoryFuture<'a, Result<(), AppError>>;
}

const MATCH_COLUMNS: &str = "id, user1_id, user2_id, status, offered_by, user1_inventory_applied_at, user2_inventory_applied_at, created_at";

/// PostgreSQL implementation of [`MatchRepository`].
pub struct PgMatchRepository {
    pool: PgPool,
}

impl PgMatchRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

/// Helper: parse a `matches` row into a partial `TradeMatch` (no related data).
fn match_from_row(row: &sqlx::postgres::PgRow) -> TradeMatch {
    TradeMatch {
        id: row.get("id"),
        user1_id: row.get("user1_id"),
        user2_id: row.get("user2_id"),
        status: row.get("status"),
        created_at: to_rfc3339(row.get("created_at")),
        offered_by: row.get("offered_by"),
        inventory_applied: false,
        other_user: None,
        user_haves: vec![],
        user_wants: vec![],
        selected_items: vec![],
    }
}

// We use `fn ... -> impl Future` instead of `async fn` here
// because the trait method's return type is `impl Future + 'b`
// (single lifetime, tied to the tx borrow, not the trait's `'a`).
// `async fn` in an impl block can introduce its own lifetime
// parameters and the resulting signature does not always match
// the trait's. The explicit `impl Future` is the simpler, more
// predictable form for this use case.
#[allow(clippy::manual_async_fn)]
impl MatchRepository for PgMatchRepository {
    fn list_all<'a>(&'a self) -> RepositoryFuture<'a, Result<Vec<TradeMatch>, AppError>> {
        Box::pin(async move {
            let sql = format!(
                "SELECT {} FROM matches ORDER BY created_at DESC",
                MATCH_COLUMNS
            );
            let rows = sqlx::query(&sql).fetch_all(&self.pool).await?;
            Ok(rows.iter().map(match_from_row).collect())
        })
    }

    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<TradeMatch>, AppError>> {
        Box::pin(async move {
            // Query 1 of 4: matches joined to the "other user" (the participant
            // who is not the requesting user). The CASE picks u.id and
            // u.username without a subquery — single round trip.
            let match_sql = r#"SELECT m.id, m.user1_id, m.user2_id, m.status, m.offered_by,
                          m.user1_inventory_applied_at, m.user2_inventory_applied_at,
                          m.created_at,
                          CASE WHEN m.user1_id = $1 THEN m.user2_id ELSE m.user1_id END AS other_id,
                          u.username AS other_username
                   FROM matches m
                   JOIN users u
                     ON u.id = (CASE WHEN m.user1_id = $1 THEN m.user2_id ELSE m.user1_id END)
                   WHERE (m.user1_id = $1 OR m.user2_id = $1) AND m.status != 'REJECTED'
                   ORDER BY m.created_at DESC"#;
            let match_rows = sqlx::query(match_sql)
                .bind(user_id)
                .fetch_all(&self.pool)
                .await?;

            if match_rows.is_empty() {
                return Ok(vec![]);
            }

            // Collect all match ids in a single pass — used by query 4
            // (the `match_items` batched query below). The haves and
            // wants queries (2 and 3) do not need this list because they
            // filter by the user's own user_id and any peer's WANT, not
            // by match id.
            let match_ids: Vec<i32> = match_rows.iter().map(|r| r.get::<i32, _>("id")).collect();

            // Query 2: haves — the requesting user's TRADE items that
            // match some WANT of any peer.
            // (See #173 item #6 / #7: this is not a regression — the old
            // handler also fetched by-peer-not-by-match.)
            //
            // The current implementation in handlers::matches::list_matches
            // runs this query once per match; we instead run it ONCE for
            // the whole user.
            let have_sql = r#"
                SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity,
                       m.name AS merch_name, m.photo_url,
                       w.user_id AS peer_user_id
                FROM inventory i
                JOIN merchandise m ON m.id = i.merch_id
                JOIN inventory w
                  ON w.merch_id = i.merch_id
                 AND w.status = 'WANT' AND w.quantity > 0
                WHERE i.user_id = $1
                  AND i.status = 'TRADE' AND i.quantity > 0
                  AND w.user_id <> $1
            "#;
            let have_rows = sqlx::query(have_sql)
                .bind(user_id)
                .fetch_all(&self.pool)
                .await?;

            // Query 3: wants — the mirror of haves, single query.
            let want_sql = r#"
                SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity,
                       m.name AS merch_name, m.photo_url,
                       w.user_id AS peer_user_id
                FROM inventory i
                JOIN merchandise m ON m.id = i.merch_id
                JOIN inventory w
                  ON w.merch_id = i.merch_id
                 AND w.status = 'WANT' AND w.quantity > 0
                WHERE i.user_id <> $1
                  AND i.status = 'TRADE' AND i.quantity > 0
                  AND w.user_id = $1
            "#;
            let want_rows = sqlx::query(want_sql)
                .bind(user_id)
                .fetch_all(&self.pool)
                .await?;

            // Query 4: match_items for the matches we care about, batched.
            let items_sql = r#"
                SELECT mi.id, mi.match_id, mi.merch_id, mi.owner_id, mi.direction, mi.quantity,
                       m.name AS merch_name, m.photo_url
                FROM match_items mi
                JOIN merchandise m ON m.id = mi.merch_id
                WHERE mi.match_id = ANY($1)
                ORDER BY mi.direction, mi.id
            "#;
            let item_rows = sqlx::query(items_sql)
                .bind(&match_ids)
                .fetch_all(&self.pool)
                .await?;

            // Now the in-memory join. Build per-match maps.
            //
            // For each match, `other_id` is the non-`user_id` participant.
            // We bucket haves/wants by peer_user_id (the other user).
            let mut haves_by_peer: HashMap<i32, Vec<crate::generated::ymatch::InventoryItem>> =
                HashMap::new();
            for r in &have_rows {
                let peer: i32 = r.get("peer_user_id");
                haves_by_peer.entry(peer).or_default().push(
                    crate::generated::ymatch::InventoryItem {
                        id: r.get("id"),
                        user_id: r.get("user_id"),
                        merch_id: r.get("merch_id"),
                        status: r.get("status"),
                        quantity: r.get("quantity"),
                        merch_name: Some(r.get("merch_name")),
                        photo_url: r.get("photo_url"),
                        group_name: None,
                    },
                );
            }
            let mut wants_by_peer: HashMap<i32, Vec<crate::generated::ymatch::InventoryItem>> =
                HashMap::new();
            for r in &want_rows {
                let peer: i32 = r.get("peer_user_id");
                wants_by_peer.entry(peer).or_default().push(
                    crate::generated::ymatch::InventoryItem {
                        id: r.get("id"),
                        user_id: r.get("user_id"),
                        merch_id: r.get("merch_id"),
                        status: r.get("status"),
                        quantity: r.get("quantity"),
                        merch_name: Some(r.get("merch_name")),
                        photo_url: r.get("photo_url"),
                        group_name: None,
                    },
                );
            }
            let mut items_by_match: HashMap<i32, Vec<MatchItem>> = HashMap::new();
            for r in &item_rows {
                let mid: i32 = r.get("match_id");
                items_by_match.entry(mid).or_default().push(MatchItem {
                    id: r.get("id"),
                    match_id: mid,
                    merch_id: r.get("merch_id"),
                    owner_id: r.get("owner_id"),
                    direction: r.get("direction"),
                    quantity: r.get("quantity"),
                    merch_name: Some(r.get("merch_name")),
                    photo_url: r.get("photo_url"),
                });
            }

            // Compose final matches.
            let mut out: Vec<TradeMatch> = Vec::with_capacity(match_rows.len());
            for row in &match_rows {
                let mut m = match_from_row(row);
                let other_id: i32 = row.get("other_id");
                let other_username: String = row.get("other_username");
                m.other_user = Some(User {
                    id: other_id,
                    username: other_username,
                    uuid: None,
                    device_token: None,
                    created_at: None,
                    role: None,
                    is_banned: None,
                    ban_reason: None,
                    banned_until: None,
                });
                m.user_haves = haves_by_peer.get(&other_id).cloned().unwrap_or_default();
                m.user_wants = wants_by_peer.get(&other_id).cloned().unwrap_or_default();
                m.selected_items = items_by_match.get(&m.id).cloned().unwrap_or_default();
                // inventory_applied for THIS user
                m.inventory_applied = if m.user1_id == user_id {
                    row.get::<Option<chrono::DateTime<chrono::Utc>>, _>(
                        "user1_inventory_applied_at",
                    )
                    .is_some()
                } else {
                    row.get::<Option<chrono::DateTime<chrono::Utc>>, _>(
                        "user2_inventory_applied_at",
                    )
                    .is_some()
                };
                out.push(m);
            }
            Ok(out)
        })
    }

    fn list_match_items<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<MatchItem>, AppError>> {
        Box::pin(async move {
            let rows = sqlx::query(
                r#"SELECT mi.id, mi.match_id, mi.merch_id, mi.owner_id, mi.direction, mi.quantity,
                          m.name AS merch_name, m.photo_url
                   FROM match_items mi
                   JOIN merchandise m ON m.id = mi.merch_id
                   WHERE mi.match_id = $1
                   ORDER BY mi.direction, mi.id"#,
            )
            .bind(match_id)
            .fetch_all(&self.pool)
            .await?;
            Ok(rows
                .iter()
                .map(|r| MatchItem {
                    id: r.get("id"),
                    match_id: r.get("match_id"),
                    merch_id: r.get("merch_id"),
                    owner_id: r.get("owner_id"),
                    direction: r.get("direction"),
                    quantity: r.get("quantity"),
                    merch_name: Some(r.get("merch_name")),
                    photo_url: Some(r.get("photo_url")),
                })
                .collect())
        })
    }

    fn notification_counts<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<NotificationCounts, AppError>> {
        Box::pin(async move {
            // Single query with 4 sub-selects. Replaces the previous
            // 4 sequential `SELECT COUNT(*)` calls (#173 item #4).
            let row = sqlx::query(
                r#"SELECT
                       (SELECT COUNT(*) FROM matches
                        WHERE (user1_id = $1 OR user2_id = $1) AND status = 'PENDING') AS pending,
                       (SELECT COUNT(*) FROM matches
                        WHERE (user1_id = $1 OR user2_id = $1)
                          AND status = 'OFFERED' AND offered_by != $1) AS offers_in,
                       (SELECT COUNT(*) FROM matches
                        WHERE (user1_id = $1 OR user2_id = $1) AND status = 'ACCEPTED') AS accepted,
                       (SELECT COUNT(*) FROM messages msg
                        JOIN matches m ON msg.match_id = m.id
                        WHERE (m.user1_id = $1 OR m.user2_id = $1)
                          AND m.status IN ('PENDING', 'OFFERED', 'ACCEPTED')
                          AND msg.sender_id != $1
                          AND msg.created_at > COALESCE(
                            (SELECT matches_read_at FROM users WHERE id = $1),
                            '1970-01-01'::timestamptz
                          )) AS unread
                   "#,
            )
            .bind(user_id)
            .fetch_one(&self.pool)
            .await?;

            let pending: i64 = row.get("pending");
            let offers_in: i64 = row.get("offers_in");
            let accepted: i64 = row.get("accepted");
            let unread: i64 = row.get("unread");
            let total = pending + offers_in + accepted + unread;
            Ok(NotificationCounts {
                pending_matches: pending as i32,
                offers_in: offers_in as i32,
                accepted: accepted as i32,
                unread_messages: unread as i32,
                total: total as i32,
            })
        })
    }

    fn get_status_snapshot<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<MatchStatusSnapshot>, AppError>> {
        Box::pin(async move {
            let row = sqlx::query(
                "SELECT user1_id, user2_id, status, offered_by,
                        user1_inventory_applied_at, user2_inventory_applied_at
                 FROM matches WHERE id = $1",
            )
            .bind(match_id)
            .fetch_optional(&self.pool)
            .await?;
            Ok(row.map(|r| MatchStatusSnapshot {
                user1_id: r.get("user1_id"),
                user2_id: r.get("user2_id"),
                status: r.get("status"),
                offered_by: r.get("offered_by"),
                user1_applied: r
                    .get::<Option<chrono::DateTime<chrono::Utc>>, _>("user1_inventory_applied_at")
                    .is_some(),
                user2_applied: r
                    .get::<Option<chrono::DateTime<chrono::Utc>>, _>("user2_inventory_applied_at")
                    .is_some(),
            }))
        })
    }

    fn lock_for_update_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<MatchStatusSnapshot>, AppError>> {
        Box::pin(async move {
            let row = sqlx::query(
                "SELECT user1_id, user2_id, status, offered_by,
                        user1_inventory_applied_at, user2_inventory_applied_at
                 FROM matches WHERE id = $1 FOR UPDATE",
            )
            .bind(match_id)
            .fetch_optional(&mut *conn)
            .await?;
            Ok(row.map(|r| MatchStatusSnapshot {
                user1_id: r.get("user1_id"),
                user2_id: r.get("user2_id"),
                status: r.get("status"),
                offered_by: r.get("offered_by"),
                user1_applied: r
                    .get::<Option<chrono::DateTime<chrono::Utc>>, _>("user1_inventory_applied_at")
                    .is_some(),
                user2_applied: r
                    .get::<Option<chrono::DateTime<chrono::Utc>>, _>("user2_inventory_applied_at")
                    .is_some(),
            }))
        })
    }

    fn set_status_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
        new_status: &'a str,
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            sqlx::query("UPDATE matches SET status = $1 WHERE id = $2")
                .bind(new_status)
                .bind(match_id)
                .execute(&mut *conn)
                .await?;
            Ok(())
        })
    }

    fn set_offered_by_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            sqlx::query("UPDATE matches SET offered_by = $1 WHERE id = $2")
                .bind(user_id)
                .bind(match_id)
                .execute(&mut *conn)
                .await?;
            Ok(())
        })
    }

    fn insert_match_items_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
        owner_id: i32,
        items: &'a [OfferItem],
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            for item in items {
                sqlx::query(
                    "INSERT INTO match_items (match_id, merch_id, owner_id, direction, quantity)
                     VALUES ($1, $2, $3, $4, $5)",
                )
                .bind(match_id)
                .bind(item.merch_id)
                .bind(owner_id)
                .bind(&item.direction)
                .bind(item.quantity)
                .execute(&mut *conn)
                .await?;
            }
            Ok(())
        })
    }

    fn delete_match_items_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            sqlx::query("DELETE FROM match_items WHERE match_id = $1")
                .bind(match_id)
                .execute(&mut *conn)
                .await?;
            Ok(())
        })
    }

    fn purge_other_pending_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        skip_match_id: i32,
        user1_id: i32,
        user2_id: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            sqlx::query(
                "DELETE FROM matches WHERE status = 'PENDING' AND id != $1
                 AND ((user1_id = $2 AND user2_id = $3) OR (user1_id = $3 AND user2_id = $2))",
            )
            .bind(skip_match_id)
            .bind(user1_id)
            .bind(user2_id)
            .execute(&mut *conn)
            .await?;
            Ok(())
        })
    }

    fn mark_inventory_applied_conn<'a>(
        &'a self,
        conn: &'a mut sqlx::PgConnection,
        match_id: i32,
        is_user1: bool,
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            let col = if is_user1 {
                "user1_inventory_applied_at"
            } else {
                "user2_inventory_applied_at"
            };
            let sql = format!("UPDATE matches SET {} = NOW() WHERE id = $1", col);
            let affected = sqlx::query(&sql)
                .bind(match_id)
                .execute(&mut *conn)
                .await?
                .rows_affected();
            if affected == 0 {
                return Err(AppError::not_found("Match disappeared mid-apply"));
            }
            Ok(())
        })
    }
}
