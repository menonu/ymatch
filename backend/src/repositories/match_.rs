//! Match aggregate repository.
//!
//! [`MatchRepository`] owns the `matches` and `match_items` tables. It is
//! used by:
//!
//! - HTTP handlers (read-only paths: list, get, snapshot, items, counts)
//! - [`crate::services::match_lifecycle::MatchLifecycleService`]
//!   (transactional writes: offer, change_status, apply_inventory)
//!
//! Phase 4 of #163 fixes the N+1 problem in the previous
//! `handlers::matches::list_matches` (1 + 4N queries for N matches) by
//! replacing it with [`MatchRepository::list_for_user`], which runs **4
//! queries total**: matches + other_user via JOIN, haves batched,
//! wants batched, match_items batched. The in-memory join happens
//! inside the repository.
//!
//! ## Transactional writes
//!
//! Methods that participate in a transaction take `&mut PgConnection`
//! from the caller. This is the standard sqlx pattern: the service
//! opens a transaction (`let mut tx = self.pool.begin().await?;`) and
//! the repository methods are passed `&mut *tx` (re-borrowed from
//! `tx: Transaction`). The method re-borrows the connection on each
//! internal `.execute()` call (NLL releases the reborrow at the end of
//! each `await`).
//!
//! Phase B-9 of #191: migrated from the previous
//! `trait MatchRepository + PgMatchRepository` two-type pattern to a
//! single concrete struct. The `_conn` suffix on the transactional
//! methods was dropped — the `&mut PgConnection` parameter is the
//! signal that the method needs a connection / tx from the caller.
//!
//! (We explored a generic `Executor<'c, Database = Postgres>` parameter
//! form to drop the `&mut PgConnection` concrete dependency, but it
//! doesn't compose with the loop inside `insert_match_items` because
//! sqlx 0.7 has no blanket `&mut E: Executor` impl — `Executor` is
//! consumed by `.execute()`. For multi-statement methods the
//! concrete `&mut PgConnection` form remains the natural pattern.)

use crate::error::AppError;
use crate::generated::ymatch::{MatchItem, NotificationCounts, OfferItem, TradeMatch, User};
use crate::handlers::mappers::to_rfc3339;
use sqlx::{PgConnection, PgPool, Row};
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

pub struct MatchRepository {
    pool: PgPool,
}

impl MatchRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    // ---- Read methods (use the pool directly) ----

    /// List all matches in the system (admin).
    pub async fn list_all(&self) -> Result<Vec<TradeMatch>, AppError> {
        let sql = format!(
            "SELECT {} FROM matches ORDER BY created_at DESC",
            MATCH_COLUMNS
        );
        let rows = sqlx::query(&sql).fetch_all(&self.pool).await?;
        Ok(rows.iter().map(match_from_row).collect())
    }

    /// List matches for a user with all related data pre-loaded. This is
    /// the N+1 fix — see the module-level docs.
    pub async fn list_for_user(&self, user_id: i32) -> Result<Vec<TradeMatch>, AppError> {
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

        let match_ids: Vec<i32> = match_rows.iter().map(|r| r.get::<i32, _>("id")).collect();

        // Query 2: haves — the requesting user's TRADE items that
        // match some WANT of any peer.
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

        let mut haves_by_peer: HashMap<i32, Vec<crate::generated::ymatch::InventoryItem>> =
            HashMap::new();
        for r in &have_rows {
            let peer: i32 = r.get("peer_user_id");
            haves_by_peer
                .entry(peer)
                .or_default()
                .push(crate::generated::ymatch::InventoryItem {
                    id: r.get("id"),
                    user_id: r.get("user_id"),
                    merch_id: r.get("merch_id"),
                    status: r.get("status"),
                    quantity: r.get("quantity"),
                    merch_name: Some(r.get("merch_name")),
                    photo_url: r.get("photo_url"),
                    group_name: None,
                });
        }
        let mut wants_by_peer: HashMap<i32, Vec<crate::generated::ymatch::InventoryItem>> =
            HashMap::new();
        for r in &want_rows {
            let peer: i32 = r.get("peer_user_id");
            wants_by_peer
                .entry(peer)
                .or_default()
                .push(crate::generated::ymatch::InventoryItem {
                    id: r.get("id"),
                    user_id: r.get("user_id"),
                    merch_id: r.get("merch_id"),
                    status: r.get("status"),
                    quantity: r.get("quantity"),
                    merch_name: Some(r.get("merch_name")),
                    photo_url: r.get("photo_url"),
                    group_name: None,
                });
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
            m.inventory_applied = if m.user1_id == user_id {
                row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("user1_inventory_applied_at")
                    .is_some()
            } else {
                row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("user2_inventory_applied_at")
                    .is_some()
            };
            out.push(m);
        }
        Ok(out)
    }

    /// Read the snapshot of a match's status fields. Used by the
    /// inventory-apply endpoint.
    pub async fn get_status_snapshot(
        &self,
        match_id: i32,
    ) -> Result<Option<MatchStatusSnapshot>, AppError> {
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
    }

    /// List `match_items` joined with `merchandise` for the apply endpoint.
    pub async fn list_match_items(&self, match_id: i32) -> Result<Vec<MatchItem>, AppError> {
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
    }

    /// Notification counts (pending / offers_in / accepted / unread) for a
    /// user.
    pub async fn notification_counts(&self, user_id: i32) -> Result<NotificationCounts, AppError> {
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
    }

    // ---- Transactional methods (take &mut PgConnection) ----

    /// `SELECT ... FOR UPDATE` on a match row. Returns the snapshot if
    /// the row exists, `None` otherwise. The row lock is held until
    /// the surrounding transaction ends.
    pub async fn lock_for_update(
        &self,
        conn: &mut PgConnection,
        match_id: i32,
    ) -> Result<Option<MatchStatusSnapshot>, AppError> {
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
    }

    /// Set the match's `status` column.
    pub async fn set_status(
        &self,
        conn: &mut PgConnection,
        match_id: i32,
        new_status: &str,
    ) -> Result<(), AppError> {
        sqlx::query("UPDATE matches SET status = $1 WHERE id = $2")
            .bind(new_status)
            .bind(match_id)
            .execute(&mut *conn)
            .await?;
        Ok(())
    }

    /// Set the match's `offered_by` column.
    pub async fn set_offered_by(
        &self,
        conn: &mut PgConnection,
        match_id: i32,
        user_id: i32,
    ) -> Result<(), AppError> {
        sqlx::query("UPDATE matches SET offered_by = $1 WHERE id = $2")
            .bind(user_id)
            .bind(match_id)
            .execute(&mut *conn)
            .await?;
        Ok(())
    }

    /// Bulk-insert match_items rows for an offer.
    pub async fn insert_match_items(
        &self,
        conn: &mut PgConnection,
        match_id: i32,
        owner_id: i32,
        items: &[OfferItem],
    ) -> Result<(), AppError> {
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
    }

    /// Delete all match_items rows for a match. Used when a match is
    /// rejected.
    pub async fn delete_match_items(
        &self,
        conn: &mut PgConnection,
        match_id: i32,
    ) -> Result<(), AppError> {
        sqlx::query("DELETE FROM match_items WHERE match_id = $1")
            .bind(match_id)
            .execute(&mut *conn)
            .await?;
        Ok(())
    }

    /// Delete all other PENDING matches between the same pair of
    /// users. Used when a match is accepted.
    pub async fn purge_other_pending(
        &self,
        conn: &mut PgConnection,
        skip_match_id: i32,
        user1_id: i32,
        user2_id: i32,
    ) -> Result<(), AppError> {
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
    }

    /// Set the per-user inventory-applied timestamp. `is_user1` picks
    /// which column to write.
    pub async fn mark_inventory_applied(
        &self,
        conn: &mut PgConnection,
        match_id: i32,
        is_user1: bool,
    ) -> Result<(), AppError> {
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
    }
}

const MATCH_COLUMNS: &str = "id, user1_id, user2_id, status, offered_by, user1_inventory_applied_at, user2_inventory_applied_at, created_at";

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
