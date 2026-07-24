//! Lifecycle write paths for matches (lock, status, legs, delete, applied flags).

use super::{MatchRepository, MatchStatusSnapshot, match_status_snapshot_from_row};
use crate::error::AppError;
use crate::generated::ymatch::OfferItem;

impl MatchRepository {
    /// `SELECT ... FOR UPDATE` on a match row. Returns the snapshot if
    /// the row exists, `None` otherwise. The row lock is held until
    /// the surrounding transaction ends.
    pub async fn lock_for_update<'c, E>(
        &self,
        exec: E,
        match_id: i32,
    ) -> Result<Option<MatchStatusSnapshot>, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let row = sqlx::query(
            "SELECT user1_id, user2_id, status, offered_by, event_id, group_name,
                    user1_inventory_applied_at, user2_inventory_applied_at
             FROM matches WHERE id = $1 FOR UPDATE",
        )
        .bind(match_id)
        .fetch_optional(exec)
        .await?;
        Ok(row.map(match_status_snapshot_from_row))
    }

    /// Set the match's `status` column.
    pub async fn set_status<'c, E>(
        &self,
        exec: E,
        match_id: i32,
        new_status: &str,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        sqlx::query("UPDATE matches SET status = $1 WHERE id = $2")
            .bind(new_status)
            .bind(match_id)
            .execute(exec)
            .await?;
        Ok(())
    }

    /// Set the match's `offered_by` column.
    pub async fn set_offered_by<'c, E>(
        &self,
        exec: E,
        match_id: i32,
        user_id: i32,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        sqlx::query("UPDATE matches SET offered_by = $1 WHERE id = $2")
            .bind(user_id)
            .bind(match_id)
            .execute(exec)
            .await?;
        Ok(())
    }

    /// Count how many of the given merch ids belong to a given group
    /// (ADR 0001) **and are live / tradeable** (ADR 0008). Used by the
    /// offer/counter-offer path to validate that every proposed leg is within
    /// the match's group and is not soft-deleted before upserting.
    pub async fn count_merch_in_group<'c, E>(
        &self,
        exec: E,
        merch_ids: &[i32],
        event_id: i32,
        group_name: &str,
    ) -> Result<i64, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let row: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM merchandise
             WHERE id = ANY($1) AND event_id = $2 AND group_name = $3
               AND is_deleted = false AND trade_enabled = true",
        )
        .bind(merch_ids)
        .bind(event_id)
        .bind(group_name)
        .fetch_one(exec)
        .await?;
        Ok(row.0)
    }

    /// Upsert the positive-quantity legs of a proposal (#297).
    ///
    /// Each `OfferItem` is an absolute leg `(giver_user_id, merch_id, quantity)`;
    /// legs with `quantity > 0` are upserted on the key `(match_id, giver_user_id,
    /// merch_id)` (the unique constraint lets `ON CONFLICT … DO UPDATE` set the
    /// new quantity). Zero-quantity legs are removed by [`remove_legs`]. Legs
    /// not mentioned in `items` are untouched, so counter-offers accumulate: a
    /// non-proposer can add only their-give (or only their receive) to move
    /// toward balance. Single statement so the generic `Executor` is consumed
    /// once; the caller (service) reborrow `&mut *tx` per call.
    ///
    /// **Ordering contract:** the service calls [`upsert_legs`] *before*
    /// [`remove_legs`] within one transaction. They touch disjoint leg sets
    /// (positive vs zero quantity), so the order does not change the final
    /// rows, but the pair is one logical "apply these legs" step — keep them
    /// adjacent and in this order. (A future single `apply_legs` that
    /// partitions internally would remove this contract.)
    pub async fn upsert_legs<'c, E>(
        &self,
        exec: E,
        match_id: i32,
        items: &[OfferItem],
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let upsert: Vec<(i32, i32, i32)> = items
            .iter()
            .filter(|i| i.quantity > 0)
            .map(|i| (i.giver_user_id, i.merch_id, i.quantity))
            .collect();
        if upsert.is_empty() {
            return Ok(());
        }
        let givers: Vec<i32> = upsert.iter().map(|t| t.0).collect();
        let merch: Vec<i32> = upsert.iter().map(|t| t.1).collect();
        let qty: Vec<i32> = upsert.iter().map(|t| t.2).collect();
        sqlx::query(
            r#"INSERT INTO match_items (match_id, giver_user_id, merch_id, quantity)
               SELECT $1, giver_user_id, merch_id, quantity
               FROM UNNEST($2::int[], $3::int[], $4::int[])
                 AS t(giver_user_id, merch_id, quantity)
               ON CONFLICT (match_id, giver_user_id, merch_id)
               DO UPDATE SET quantity = EXCLUDED.quantity"#,
        )
        .bind(match_id)
        .bind(&givers)
        .bind(&merch)
        .bind(&qty)
        .execute(exec)
        .await?;
        Ok(())
    }

    /// Remove the zero-quantity legs of a proposal (#297) — the proposer
    /// explicitly dropped them. Single statement; the caller reborrow
    /// `&mut *tx` per call. See [`upsert_legs`] for the **ordering contract**
    /// (upsert before remove, within one transaction).
    pub async fn remove_legs<'c, E>(
        &self,
        exec: E,
        match_id: i32,
        items: &[OfferItem],
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let del: Vec<(i32, i32)> = items
            .iter()
            .filter(|i| i.quantity == 0)
            .map(|i| (i.giver_user_id, i.merch_id))
            .collect();
        if del.is_empty() {
            return Ok(());
        }
        let givers: Vec<i32> = del.iter().map(|t| t.0).collect();
        let merch: Vec<i32> = del.iter().map(|t| t.1).collect();
        sqlx::query(
            r#"DELETE FROM match_items
               WHERE match_id = $1
                 AND (giver_user_id, merch_id) IN (
                   SELECT giver_user_id, merch_id
                   FROM UNNEST($2::int[], $3::int[]) AS t(giver_user_id, merch_id)
                 )"#,
        )
        .bind(match_id)
        .bind(&givers)
        .bind(&merch)
        .execute(exec)
        .await?;
        Ok(())
    }

    /// Delete all match_items rows for a match. Used when a match is
    /// rejected.
    pub async fn delete_match_items<'c, E>(&self, exec: E, match_id: i32) -> Result<(), AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        sqlx::query("DELETE FROM match_items WHERE match_id = $1")
            .bind(match_id)
            .execute(exec)
            .await?;
        Ok(())
    }

    /// Delete a match row by primary key. Used by the admin path
    /// (`DELETE /admin/matches/:id`). Returns `true` if a row was deleted.
    ///
    /// `match_items` cascade via FK; `messages` do not — callers that need
    /// to wipe a match with messages must clear those first (or accept the
    /// FK error). Admin deletes of empty/pending matches are the common case.
    pub async fn delete(&self, match_id: i32) -> Result<bool, AppError> {
        let affected = sqlx::query("DELETE FROM matches WHERE id = $1")
            .bind(match_id)
            .execute(&self.pool)
            .await?
            .rows_affected();
        Ok(affected > 0)
    }

    /// Set the per-user inventory-applied timestamp. `is_user1` picks
    /// which column to write.
    ///
    /// The update is conditional on the column still being NULL so a
    /// concurrent apply cannot stamp the flag twice (#492). When
    /// `rows_affected == 0` (already applied, or match missing), returns
    /// [`AppError::Conflict`] (HTTP 409). Callers that hold
    /// [`Self::lock_for_update`] should still pre-check the flag under
    /// the lock so they never apply inventory deltas before discovering
    /// the conflict.
    pub async fn mark_inventory_applied<'c, E>(
        &self,
        exec: E,
        match_id: i32,
        is_user1: bool,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let col = if is_user1 {
            "user1_inventory_applied_at"
        } else {
            "user2_inventory_applied_at"
        };
        // Conditional mark: only the first writer wins. Column name is
        // one of two fixed literals above, not user input.
        let sql = format!("UPDATE matches SET {col} = NOW() WHERE id = $1 AND {col} IS NULL");
        let affected = sqlx::query(&sql)
            .bind(match_id)
            .execute(exec)
            .await?
            .rows_affected();
        if affected == 0 {
            return Err(AppError::conflict(
                "Inventory already applied for this user",
            ));
        }
        Ok(())
    }
}
