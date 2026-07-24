//! Periodic matcher scan steps, PENDING insert, and ADR 0012 rematch reopen.
//!
//! Walk order (see `matching.rs`):
//! 1. list_matchable_wants
//! 2. list_users_trading_merch
//! 3. list_user_trade_merch_ids_in_group
//! 4. user_wants_live_merch
//! 5. find_for_pair_group → insert_pending | reopen_terminal

use super::{MatchRepository, MatchableWant};
use crate::error::AppError;
use sqlx::Row;

impl MatchRepository {
    // ---- Matcher scan steps / insert / rematch (#497) ----
    //
    // The periodic matcher walks these in order (see `matching.rs`):
    //   1. list_matchable_wants
    //   2. list_users_trading_merch
    //   3. list_user_trade_merch_ids_in_group
    //   4. user_wants_live_merch
    //   5. find_for_pair_group → insert_pending | reopen_terminal
    // Each method is intentionally small so a filter change is one place.

    /// Step 1 — WANT rows that may seed a match.
    ///
    /// Filters (same as pre-#497 matcher):
    /// - status WANT, quantity > 0 (ADR 0010 / 0012)
    /// - merch live + trade-enabled
    /// - non-null, non-empty group (ADR 0001)
    /// - user not banned
    /// - merch not locked in OFFERED/ACCEPTED for this user
    ///
    /// Ordered by `inventory.updated_at ASC` for stable fairness.
    pub async fn list_matchable_wants(&self) -> Result<Vec<MatchableWant>, AppError> {
        let rows = sqlx::query(
            r#"
            SELECT i.user_id, i.merch_id, m.event_id, m.group_name
            FROM inventory i
            JOIN merchandise m ON i.merch_id = m.id
            JOIN users u ON i.user_id = u.id
            WHERE i.status = 'WANT'
              AND i.quantity > 0
              AND m.is_deleted = false AND m.trade_enabled = true
              AND m.group_name IS NOT NULL AND m.group_name <> ''
              AND u.is_banned = false
              AND NOT EXISTS (
                SELECT 1 FROM match_items mi
                JOIN matches mat ON mi.match_id = mat.id
                WHERE mi.merch_id = i.merch_id
                  AND mat.status IN ('OFFERED', 'ACCEPTED')
                  AND (mat.user1_id = i.user_id OR mat.user2_id = i.user_id)
              )
            ORDER BY i.updated_at ASC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .iter()
            .map(|r| MatchableWant {
                user_id: r.get("user_id"),
                merch_id: r.get("merch_id"),
                event_id: r.get("event_id"),
                group_name: r.get("group_name"),
            })
            .collect())
    }

    /// Step 2 — users who TRADE `merch_id` (potential partners for a WANT).
    ///
    /// Excludes `exclude_user_id` (the wanter). Same liveness / ban / locked
    /// filters as step 1.
    pub async fn list_users_trading_merch(
        &self,
        merch_id: i32,
        exclude_user_id: i32,
    ) -> Result<Vec<i32>, AppError> {
        let rows = sqlx::query(
            r#"
            SELECT i.user_id
            FROM inventory i
            JOIN users u ON i.user_id = u.id
            JOIN merchandise m ON m.id = i.merch_id
            WHERE i.merch_id = $1
              AND i.status = 'TRADE'
              AND i.user_id != $2
              AND i.quantity > 0
              AND m.is_deleted = false AND m.trade_enabled = true
              AND u.is_banned = false
              AND NOT EXISTS (
                SELECT 1 FROM match_items mi
                JOIN matches mat ON mi.match_id = mat.id
                WHERE mi.merch_id = i.merch_id
                  AND mat.status IN ('OFFERED', 'ACCEPTED')
                  AND (mat.user1_id = i.user_id OR mat.user2_id = i.user_id)
              )
            "#,
        )
        .bind(merch_id)
        .bind(exclude_user_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.iter().map(|r| r.get("user_id")).collect())
    }

    /// Step 3 — merch ids user `user_id` is TRADING in `(event_id, group_name)`.
    ///
    /// Used to find reciprocal inventory: something the partner might WANT
    /// in the same ADR 0001 group.
    pub async fn list_user_trade_merch_ids_in_group(
        &self,
        user_id: i32,
        event_id: i32,
        group_name: &str,
    ) -> Result<Vec<i32>, AppError> {
        let rows = sqlx::query(
            r#"
            SELECT i.merch_id
            FROM inventory i
            JOIN merchandise m ON i.merch_id = m.id
            WHERE i.user_id = $1
              AND i.status = 'TRADE'
              AND i.quantity > 0
              AND m.event_id = $2
              AND m.group_name = $3
              AND m.is_deleted = false
              AND m.trade_enabled = true
            "#,
        )
        .bind(user_id)
        .bind(event_id)
        .bind(group_name)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.iter().map(|r| r.get("merch_id")).collect())
    }

    /// Step 4 — whether `user_id` has a live WANT for `merch_id` (qty > 0).
    pub async fn user_wants_live_merch(
        &self,
        user_id: i32,
        merch_id: i32,
    ) -> Result<bool, AppError> {
        let row = sqlx::query(
            r#"
            SELECT i.id
            FROM inventory i
            JOIN merchandise m ON m.id = i.merch_id
            WHERE i.user_id = $1
              AND i.merch_id = $2
              AND i.status = 'WANT'
              AND i.quantity > 0
              AND m.is_deleted = false
              AND m.trade_enabled = true
            "#,
        )
        .bind(user_id)
        .bind(merch_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.is_some())
    }

    /// Step 5a — existing match for an unordered pair in one group.
    ///
    /// Returns `(match_id, status)` if a row exists. Pair order does not
    /// matter (`user1`/`user2` either way).
    pub async fn find_for_pair_group(
        &self,
        user_a: i32,
        user_b: i32,
        event_id: i32,
        group_name: &str,
    ) -> Result<Option<(i32, String)>, AppError> {
        let row = sqlx::query(
            "SELECT id, status FROM matches
             WHERE event_id = $3 AND group_name = $4
               AND ((user1_id = $1 AND user2_id = $2)
                 OR (user1_id = $2 AND user2_id = $1))",
        )
        .bind(user_a)
        .bind(user_b)
        .bind(event_id)
        .bind(group_name)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| (r.get("id"), r.get("status"))))
    }

    /// Step 5b — insert a new PENDING match for a rediscovered mutual edge.
    ///
    /// `user1_id` / `user2_id` are stored as given (matcher uses WANT user as
    /// user1 and TRADE partner as user2).
    pub async fn insert_pending(
        &self,
        user1_id: i32,
        user2_id: i32,
        event_id: i32,
        group_name: &str,
    ) -> Result<(), AppError> {
        sqlx::query(
            "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name, created_at)
             VALUES ($1, $2, 'PENDING', $3, $4, NOW())",
        )
        .bind(user1_id)
        .bind(user2_id)
        .bind(event_id)
        .bind(group_name)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Step 5c — ADR 0012 rematch: reopen REJECTED/CANCELLED → PENDING.
    ///
    /// One transaction: status + rematch annotation, clear legs, SYSTEM
    /// message with `reason`. Returns `true` if the row was still terminal
    /// and was reopened.
    pub async fn reopen_terminal(
        &self,
        match_id: i32,
        prior_status: &str,
        reason: &str,
    ) -> Result<bool, AppError> {
        let mut tx = self.pool.begin().await?;

        let updated = sqlx::query(
            r#"
            UPDATE matches
            SET status = 'PENDING',
                offered_by = NULL,
                rematch_count = rematch_count + 1,
                last_terminal_status = $2,
                last_terminal_at = NOW()
            WHERE id = $1
              AND status IN ('REJECTED', 'CANCELLED')
            RETURNING id, user1_id
            "#,
        )
        .bind(match_id)
        .bind(prior_status)
        .fetch_optional(&mut *tx)
        .await?;

        let Some(row) = updated else {
            tx.rollback().await?;
            return Ok(false);
        };

        let user1_id: i32 = row.get("user1_id");
        self.delete_match_items(&mut *tx, match_id).await?;

        sqlx::query(
            r#"
            INSERT INTO messages (match_id, sender_id, content, message_type)
            VALUES ($1, $2, $3, 'SYSTEM')
            "#,
        )
        .bind(match_id)
        .bind(user1_id)
        .bind(reason)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(true)
    }
}
