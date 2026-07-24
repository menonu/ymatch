//! ADR 0010 mutual capacity evaluation and system cancel.

use super::{ActiveMatchScope, MatchRepository, capacity_requires_cancel};
use crate::error::AppError;
use sqlx::Row;

impl MatchRepository {
    // ---- ADR 0010: mutual capacity + system cancel ----

    /// Active match scopes for capacity re-evaluation (ADR 0010).
    /// Status ∈ {PENDING, OFFERED, ACCEPTED}.
    pub async fn list_active_scopes_for_user<'c, E>(
        &self,
        exec: E,
        user_id: i32,
    ) -> Result<Vec<ActiveMatchScope>, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let rows = sqlx::query(
            r#"SELECT id, user1_id, user2_id, event_id, group_name
               FROM matches
               WHERE (user1_id = $1 OR user2_id = $1)
                 AND status IN ('PENDING', 'OFFERED', 'ACCEPTED')"#,
        )
        .bind(user_id)
        .fetch_all(exec)
        .await?;
        Ok(rows
            .iter()
            .map(|r| ActiveMatchScope {
                id: r.get("id"),
                user1_id: r.get("user1_id"),
                user2_id: r.get("user2_id"),
                event_id: r.get("event_id"),
                group_name: r.get("group_name"),
            })
            .collect())
    }

    /// Active match scopes in a single event+group (ADR 0010 / merch delete).
    pub async fn list_active_scopes_for_group<'c, E>(
        &self,
        exec: E,
        event_id: i32,
        group_name: &str,
    ) -> Result<Vec<ActiveMatchScope>, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let rows = sqlx::query(
            r#"SELECT id, user1_id, user2_id, event_id, group_name
               FROM matches
               WHERE event_id = $1 AND group_name = $2
                 AND status IN ('PENDING', 'OFFERED', 'ACCEPTED')"#,
        )
        .bind(event_id)
        .bind(group_name)
        .fetch_all(exec)
        .await?;
        Ok(rows
            .iter()
            .map(|r| ActiveMatchScope {
                id: r.get("id"),
                user1_id: r.get("user1_id"),
                user2_id: r.get("user2_id"),
                event_id: r.get("event_id"),
                group_name: r.get("group_name"),
            })
            .collect())
    }

    /// Match ids that reference `merch_id` via `match_items` and are still active.
    pub async fn list_active_ids_referencing_merch<'c, E>(
        &self,
        exec: E,
        merch_id: i32,
    ) -> Result<Vec<i32>, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let rows = sqlx::query_scalar(
            r#"SELECT m.id
               FROM matches m
               WHERE m.status IN ('PENDING', 'OFFERED', 'ACCEPTED')
                 AND EXISTS (
                   SELECT 1 FROM match_items mi
                   WHERE mi.match_id = m.id AND mi.merch_id = $1
                 )"#,
        )
        .bind(merch_id)
        .fetch_all(exec)
        .await?;
        Ok(rows)
    }

    /// ADR 0010 mutual capacity in one direction:
    /// `Σ LEAST(giver.TRADE, receiver.WANT)` over live merch in the match group.
    pub async fn mutual_capacity<'c, E>(
        &self,
        exec: E,
        giver_user_id: i32,
        receiver_user_id: i32,
        event_id: i32,
        group_name: &str,
    ) -> Result<i32, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let cap: i64 = sqlx::query_scalar(
            r#"
            SELECT COALESCE(SUM(LEAST(t.quantity, w.quantity)), 0)
            FROM inventory t
            JOIN inventory w
              ON w.merch_id = t.merch_id
             AND w.user_id = $2
             AND w.status = 'WANT'
             AND w.quantity > 0
            JOIN merchandise m ON m.id = t.merch_id
            WHERE t.user_id = $1
              AND t.status = 'TRADE'
              AND t.quantity > 0
              AND m.event_id = $3
              AND m.group_name = $4
              AND m.is_deleted = false
              AND m.trade_enabled = true
            "#,
        )
        .bind(giver_user_id)
        .bind(receiver_user_id)
        .bind(event_id)
        .bind(group_name)
        .fetch_one(exec)
        .await?;
        Ok(cap as i32)
    }

    /// System-cancel active matches and post one SYSTEM message each.
    ///
    /// Only rows still in `PENDING`/`OFFERED`/`ACCEPTED` are updated (idempotent
    /// if an id was already terminal). `reason` is a stable code
    /// ([`CANCEL_REASON_INVENTORY_CAPACITY`] / [`CANCEL_REASON_MERCH_DELETED`])
    /// stored in `messages.content` for client-side i18n — not display prose.
    pub async fn system_cancel_matches<'c, E>(
        &self,
        exec: E,
        match_ids: &[i32],
        reason: &str,
    ) -> Result<i64, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        if match_ids.is_empty() {
            return Ok(0);
        }
        let row: (i64,) = sqlx::query_as(
            r#"
            WITH cancelled AS (
                UPDATE matches
                SET status = 'CANCELLED'
                WHERE id = ANY($1)
                  AND status IN ('PENDING', 'OFFERED', 'ACCEPTED')
                RETURNING id, user1_id
            ),
            msgs AS (
                INSERT INTO messages (match_id, sender_id, content, message_type)
                SELECT id, user1_id, $2, 'SYSTEM'
                FROM cancelled
                RETURNING 1
            )
            SELECT COUNT(*)::bigint FROM cancelled
            "#,
        )
        .bind(match_ids)
        .bind(reason)
        .fetch_one(exec)
        .await?;
        Ok(row.0)
    }

    /// Whether either mutual capacity is zero (ADR 0010 cancel predicate).
    pub async fn scope_requires_cancel(
        &self,
        conn: &mut sqlx::PgConnection,
        scope: &ActiveMatchScope,
    ) -> Result<bool, AppError> {
        let cap1 = self
            .mutual_capacity(
                &mut *conn,
                scope.user1_id,
                scope.user2_id,
                scope.event_id,
                &scope.group_name,
            )
            .await?;
        let cap2 = self
            .mutual_capacity(
                &mut *conn,
                scope.user2_id,
                scope.user1_id,
                scope.event_id,
                &scope.group_name,
            )
            .await?;
        Ok(capacity_requires_cancel(cap1, cap2))
    }

    /// After merch soft-delete: cancel matches that reference the item via
    /// `match_items` (ADR 0008) **or** that now have zero mutual capacity in
    /// the item's group (ADR 0010 — covers legs-less `PENDING`).
    pub async fn cancel_after_merch_delete(
        &self,
        conn: &mut sqlx::PgConnection,
        merch_id: i32,
        event_id: i32,
        group_name: Option<&str>,
        reason: &str,
    ) -> Result<(), AppError> {
        use std::collections::HashSet;

        let mut ids: HashSet<i32> = self
            .list_active_ids_referencing_merch(&mut *conn, merch_id)
            .await?
            .into_iter()
            .collect();

        if let Some(group) = group_name {
            let scopes = self
                .list_active_scopes_for_group(&mut *conn, event_id, group)
                .await?;
            for scope in &scopes {
                if ids.contains(&scope.id) {
                    continue;
                }
                if self.scope_requires_cancel(&mut *conn, scope).await? {
                    ids.insert(scope.id);
                }
            }
        }

        if !ids.is_empty() {
            let list: Vec<i32> = ids.into_iter().collect();
            self.system_cancel_matches(&mut *conn, &list, reason)
                .await?;
        }
        Ok(())
    }
}
