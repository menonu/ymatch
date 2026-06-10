//! Match aggregate repository.
//!
//! [`MatchRepository`] is the abstract interface used by handlers and the
//! [`crate::services::match_lifecycle::MatchLifecycleService`] for the
//! trade lifecycle (offer / status / inventory apply).
//!
//! Phase 4 of #163 fixes the N+1 problem in the previous
//! `handlers::matches::list_matches` (1 + 4N queries for N matches) by
//! replacing it with [`MatchRepository::list_for_user`], which runs **3
//! queries total**: matches + other_user via JOIN, haves batched by
//! match-user-id, match_items batched by match id. The in-memory join
//! happens inside the repository.
//!
//! Transactions are **not** part of this trait. The lifecycle service
//! opens its own `pool.begin()` blocks and calls multiple repository
//! methods within them. Repositories stay single-statement.

use crate::error::AppError;
use crate::generated::ymatch::{MatchItem, NotificationCounts, TradeMatch, User};
use crate::handlers::mappers::to_rfc3339;
use crate::repositories::RepositoryFuture;
use sqlx::{PgPool, Row};
use std::collections::HashMap;

/// Snapshot of a `matches` row inside a `FOR UPDATE` lock. Used by
/// [`crate::services::match_lifecycle::MatchLifecycleService`] to make
/// state-machine decisions without an extra round-trip.
#[derive(Debug, Clone)]
pub struct LockedMatch {
    pub user1_id: i32,
    pub user2_id: i32,
    pub status: String,
    pub offered_by: Option<i32>,
}

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
pub trait MatchRepository: Send + Sync {
    /// List all matches in the system (admin).
    fn list_all<'a>(&'a self) -> RepositoryFuture<'a, Result<Vec<TradeMatch>, AppError>>;

    /// List matches for a user with all related data pre-loaded. This is
    /// the N+1 fix — see the module-level docs.
    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<TradeMatch>, AppError>>;

    /// Insert a new PENDING match between two users. Used by the
    /// background `matching::run_matching_algorithm` job (which is
    /// **not** part of Phase 4 — see docs/explanation/refactoring_phase_4.md).
    /// Returns the new match id.
    fn insert_pending<'a>(
        &'a self,
        user1_id: i32,
        user2_id: i32,
    ) -> RepositoryFuture<'a, Result<i32, AppError>>;

    /// Lock a match row for update inside an existing transaction. Returns
    /// `None` if the match does not exist.
    fn lock_for_update<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<LockedMatch>, AppError>>;

    /// Update a match's `status` column.
    fn set_status<'a>(
        &'a self,
        match_id: i32,
        status: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Mark a match OFFERED and set `offered_by`.
    fn mark_offered<'a>(
        &'a self,
        match_id: i32,
        offered_by: i32,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Set the `user{1,2}_inventory_applied_at` timestamp for the given side.
    fn set_user_inventory_applied<'a>(
        &'a self,
        match_id: i32,
        is_user1: bool,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Delete all PENDING matches between the same two users, excluding
    /// `exclude_match_id`. Called when a match transitions to ACCEPTED.
    fn purge_other_pending<'a>(
        &'a self,
        exclude_match_id: i32,
        user1_id: i32,
        user2_id: i32,
    ) -> RepositoryFuture<'a, Result<u64, AppError>>;

    /// Read the snapshot of a match's status fields. Used by the
    /// inventory-apply endpoint before the FOR UPDATE-style flow.
    fn get_status_snapshot<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<MatchStatusSnapshot>, AppError>>;

    /// Insert a single `match_items` row. Used by the offer endpoint loop.
    fn insert_match_item<'a>(
        &'a self,
        match_id: i32,
        merch_id: i32,
        owner_id: i32,
        direction: &'a str,
        quantity: i32,
    ) -> RepositoryFuture<'a, Result<MatchItem, AppError>>;

    /// Delete all `match_items` rows for a match. Called on REJECTED.
    fn delete_match_items<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<u64, AppError>>;

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
            // Query 1: matches joined to the "other user" (the participant
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

            // Collect all match ids and the (other_user_id) per match in
            // a single pass — used by the next two queries.
            let match_ids: Vec<i32> = match_rows.iter().map(|r| r.get::<i32, _>("id")).collect();

            // Query 2: haves — the requesting user's TRADE items that
            // match some WANT of the other participant. Batched: a
            // single IN clause over the (user_id, peer_id) pairs is
            // approximated by selecting the user's TRADE rows and
            // filtering on peer-user WANTs via a single EXISTS check
            // against a temp list. We use unnest() for the peer list.
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

    fn insert_pending<'a>(
        &'a self,
        user1_id: i32,
        user2_id: i32,
    ) -> RepositoryFuture<'a, Result<i32, AppError>> {
        Box::pin(async move {
            let row: (i32,) = sqlx::query_as(
                "INSERT INTO matches (user1_id, user2_id, status, created_at)
                 VALUES ($1, $2, 'PENDING', NOW()) RETURNING id",
            )
            .bind(user1_id)
            .bind(user2_id)
            .fetch_one(&self.pool)
            .await?;
            Ok(row.0)
        })
    }

    fn lock_for_update<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<LockedMatch>, AppError>> {
        Box::pin(async move {
            let row = sqlx::query(
                "SELECT user1_id, user2_id, status, offered_by FROM matches WHERE id = $1 FOR UPDATE",
            )
            .bind(match_id)
            .fetch_optional(&self.pool)
            .await?;
            Ok(row.map(|r| LockedMatch {
                user1_id: r.get("user1_id"),
                user2_id: r.get("user2_id"),
                status: r.get("status"),
                offered_by: r.get("offered_by"),
            }))
        })
    }

    fn set_status<'a>(
        &'a self,
        match_id: i32,
        status: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>> {
        Box::pin(async move {
            let affected = sqlx::query("UPDATE matches SET status = $1 WHERE id = $2")
                .bind(status)
                .bind(match_id)
                .execute(&self.pool)
                .await?
                .rows_affected();
            if affected == 0 {
                Ok(None)
            } else {
                Ok(Some(()))
            }
        })
    }

    fn mark_offered<'a>(
        &'a self,
        match_id: i32,
        offered_by: i32,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>> {
        Box::pin(async move {
            let affected =
                sqlx::query("UPDATE matches SET status = 'OFFERED', offered_by = $1 WHERE id = $2")
                    .bind(offered_by)
                    .bind(match_id)
                    .execute(&self.pool)
                    .await?
                    .rows_affected();
            if affected == 0 {
                Ok(None)
            } else {
                Ok(Some(()))
            }
        })
    }

    fn set_user_inventory_applied<'a>(
        &'a self,
        match_id: i32,
        is_user1: bool,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>> {
        let col = if is_user1 {
            "user1_inventory_applied_at"
        } else {
            "user2_inventory_applied_at"
        };
        let sql = format!("UPDATE matches SET {} = NOW() WHERE id = $1", col);
        Box::pin(async move {
            let affected = sqlx::query(&sql)
                .bind(match_id)
                .execute(&self.pool)
                .await?
                .rows_affected();
            if affected == 0 {
                Ok(None)
            } else {
                Ok(Some(()))
            }
        })
    }

    fn purge_other_pending<'a>(
        &'a self,
        exclude_match_id: i32,
        user1_id: i32,
        user2_id: i32,
    ) -> RepositoryFuture<'a, Result<u64, AppError>> {
        Box::pin(async move {
            let n = sqlx::query(
                "DELETE FROM matches WHERE status = 'PENDING' AND id != $1
                 AND ((user1_id = $2 AND user2_id = $3) OR (user1_id = $3 AND user2_id = $2))",
            )
            .bind(exclude_match_id)
            .bind(user1_id)
            .bind(user2_id)
            .execute(&self.pool)
            .await?
            .rows_affected();
            Ok(n)
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

    fn insert_match_item<'a>(
        &'a self,
        match_id: i32,
        merch_id: i32,
        owner_id: i32,
        direction: &'a str,
        quantity: i32,
    ) -> RepositoryFuture<'a, Result<MatchItem, AppError>> {
        Box::pin(async move {
            let row = sqlx::query(
                "INSERT INTO match_items (match_id, merch_id, owner_id, direction, quantity)
                 VALUES ($1, $2, $3, $4, $5) RETURNING id",
            )
            .bind(match_id)
            .bind(merch_id)
            .bind(owner_id)
            .bind(direction)
            .bind(quantity)
            .fetch_one(&self.pool)
            .await?;
            Ok(MatchItem {
                id: row.get("id"),
                match_id,
                merch_id,
                owner_id,
                direction: direction.to_string(),
                quantity,
                merch_name: None,
                photo_url: None,
            })
        })
    }

    fn delete_match_items<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<u64, AppError>> {
        Box::pin(async move {
            let n = sqlx::query("DELETE FROM match_items WHERE match_id = $1")
                .bind(match_id)
                .execute(&self.pool)
                .await?
                .rows_affected();
            Ok(n)
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
            let pending: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM matches
                 WHERE (user1_id = $1 OR user2_id = $1) AND status = 'PENDING'",
            )
            .bind(user_id)
            .fetch_one(&self.pool)
            .await?;

            let offers_in: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM matches
                 WHERE (user1_id = $1 OR user2_id = $1)
                   AND status = 'OFFERED' AND offered_by != $1",
            )
            .bind(user_id)
            .fetch_one(&self.pool)
            .await?;

            let accepted: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM matches
                 WHERE (user1_id = $1 OR user2_id = $1) AND status = 'ACCEPTED'",
            )
            .bind(user_id)
            .fetch_one(&self.pool)
            .await?;

            let unread: i64 = sqlx::query_scalar(
                r#"SELECT COUNT(*) FROM messages msg
                   JOIN matches m ON msg.match_id = m.id
                   WHERE (m.user1_id = $1 OR m.user2_id = $1)
                     AND m.status IN ('PENDING', 'OFFERED', 'ACCEPTED')
                     AND msg.sender_id != $1
                     AND msg.created_at > COALESCE(
                       (SELECT matches_read_at FROM users WHERE id = $1),
                       '1970-01-01'::timestamptz
                     )"#,
            )
            .bind(user_id)
            .fetch_one(&self.pool)
            .await?;

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
}
