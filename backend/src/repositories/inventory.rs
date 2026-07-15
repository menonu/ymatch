//! Inventory aggregate repository.
//!
//! [`InventoryRepository`] owns the `inventory` table operations. It powers:
//!
//! - the user inventory list endpoint (`handlers::inventory::get_user_inventory`)
//! - the inventory upsert endpoint (`handlers::inventory::update_inventory`)
//! - the trade-apply endpoint via
//!   [`crate::services::match_lifecycle::MatchLifecycleService`]
//!
//! Phase B-6 + B-9 of #191: migrated from the previous
//! `trait InventoryRepository + PgInventoryRepository` two-type pattern
//! to a single concrete struct, and lifted the `apply_trade_delta`
//! transaction parameter from `&mut PgConnection` to a generic
//! `E: Executor<'c, Database = Postgres>`. The two conditional
//! statements are collapsed into a single CTE so the generic
//! executor (consumed by `.execute()`) can satisfy the method
//! signature without a loop.

use crate::error::AppError;
use crate::generated::ymatch::InventoryItem;
use sqlx::{PgPool, Row};

pub struct InventoryRepository {
    pool: PgPool,
}

impl InventoryRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Upsert a single inventory row keyed by `(user_id, merch_id, status)`.
    /// Returns the resulting row.
    pub async fn upsert(
        &self,
        user_id: i32,
        merch_id: i32,
        status: &str,
        quantity: i32,
    ) -> Result<InventoryItem, AppError> {
        let row = sqlx::query(
            r#"INSERT INTO inventory (user_id, merch_id, status, quantity)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (user_id, merch_id, status)
               DO UPDATE SET quantity = EXCLUDED.quantity, updated_at = NOW()
               RETURNING id, user_id, merch_id, status, quantity"#,
        )
        .bind(user_id)
        .bind(merch_id)
        .bind(status)
        .bind(quantity)
        .fetch_one(&self.pool)
        .await?;
        Ok(InventoryItem {
            id: row.get("id"),
            user_id: row.get("user_id"),
            merch_id: row.get("merch_id"),
            status: row.get("status"),
            quantity: row.get("quantity"),
            // Preserved from the pre-Phase-4 handler behavior: an
            // upserted row has no joined merch data, so we set
            // merch_name to Some("") to match the old default.
            // The frontend re-fetches via list_for_user (which
            // joins) before display, so the empty string never
            // reaches the user; this preserves the historical
            // shape of the upsert response (see #173 item #5).
            merch_name: Some("".to_string()),
            photo_url: None,
            group_name: None,
        })
    }

    /// List all inventory rows for a user, joined to `merchandise` for
    /// `merch_name` / `photo_url` / `group_name`.
    pub async fn list_for_user(&self, user_id: i32) -> Result<Vec<InventoryItem>, AppError> {
        let rows = sqlx::query(
            r#"SELECT
                   i.id, i.user_id, i.merch_id, i.status, i.quantity,
                   m.name as merch_name, m.photo_url, m.group_name
               FROM inventory i
               JOIN merchandise m ON i.merch_id = m.id
               WHERE i.user_id = $1"#,
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .iter()
            .map(|row| InventoryItem {
                id: row.get("id"),
                user_id: row.get("user_id"),
                merch_id: row.get("merch_id"),
                status: row.get("status"),
                quantity: row.get("quantity"),
                merch_name: Some(row.get("merch_name")),
                photo_url: row.get("photo_url"),
                group_name: row.get("group_name"),
            })
            .collect())
    }

    /// Apply a trade-delta to a user's inventory inside the
    /// caller's transaction.
    ///
    /// - `delta_trade` (> 0): decrement the TRADE row by that amount
    ///   (clamped at 0). `<= 0` skips TRADE.
    /// - `delta_have` (signed, #429):
    ///   - `> 0`: upsert/increment the HAVE row by that amount
    ///   - `< 0`: decrement the HAVE row by `|delta_have|` (clamped at 0)
    ///   - `0`: skip HAVE
    ///
    /// Implemented as a single CTE so the generic `Executor` parameter
    /// (consumed by `.execute()`) is used exactly once per call. The
    /// `$1 > 0` / `$4 > 0` / `$4 < 0` predicates short-circuit unused
    /// branches.
    pub async fn apply_trade_delta<'c, E>(
        &self,
        exec: E,
        user_id: i32,
        merch_id: i32,
        delta_trade: i32,
        delta_have: i32,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        sqlx::query(
            r#"
            WITH trade_update AS (
                UPDATE inventory
                SET quantity = GREATEST(quantity - $1, 0)
                WHERE user_id = $2 AND merch_id = $3 AND status = 'TRADE' AND $1 > 0
                RETURNING 1
            ),
            have_inc AS (
                INSERT INTO inventory (user_id, merch_id, status, quantity)
                SELECT $2, $3, 'HAVE', $4
                WHERE $4 > 0
                ON CONFLICT (user_id, merch_id, status)
                DO UPDATE SET quantity = inventory.quantity + $4
                RETURNING 1
            ),
            have_dec AS (
                UPDATE inventory
                SET quantity = GREATEST(quantity + $4, 0)
                WHERE user_id = $2 AND merch_id = $3 AND status = 'HAVE' AND $4 < 0
                RETURNING 1
            )
            SELECT 1
            "#,
        )
        .bind(delta_trade)
        .bind(user_id)
        .bind(merch_id)
        .bind(delta_have)
        .execute(exec)
        .await?;
        Ok(())
    }

    /// Fetch a user's WANT quantities for the given merch_ids as a
    /// `merch_id -> quantity` map. Used by the offer-quantity cap in
    /// [`crate::services::match_lifecycle::MatchLifecycleService::offer`]
    /// to enforce that an offered quantity never exceeds the receiving
    /// side's WANT quantity (issue #294). Runs on the supplied executor
    /// so the read participates in the offer transaction's snapshot.
    pub async fn want_quantities<'c, E>(
        &self,
        exec: E,
        user_id: i32,
        merch_ids: &[i32],
    ) -> Result<std::collections::HashMap<i32, i32>, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        if merch_ids.is_empty() {
            return Ok(std::collections::HashMap::new());
        }
        let rows = sqlx::query(
            "SELECT merch_id, quantity FROM inventory \
             WHERE user_id = $1 AND status = 'WANT' AND merch_id = ANY($2)",
        )
        .bind(user_id)
        .bind(merch_ids)
        .fetch_all(exec)
        .await?;
        let mut map = std::collections::HashMap::with_capacity(rows.len());
        for r in rows {
            map.insert(r.get::<i32, _>("merch_id"), r.get::<i32, _>("quantity"));
        }
        Ok(map)
    }
}
