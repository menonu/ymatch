//! Inventory aggregate repository.
//!
//! [`InventoryRepository`] owns the `inventory` table operations. It powers:
//!
//! - the user inventory list endpoint (`handlers::inventory::get_user_inventory`)
//! - the inventory upsert endpoint (`handlers::inventory::update_inventory`)
//! - the trade-apply endpoint via
//!   [`crate::services::match_lifecycle::MatchLifecycleService`]
//!
//! Phase B-6 of #191: migrated from the previous
//! `trait InventoryRepository + PgInventoryRepository` two-type pattern to
//! a single concrete struct, matching the Phase A shape.

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
    /// caller's transaction. Decrements the TRADE row by
    /// `delta_trade` (clamped at 0) and upserts the HAVE row by
    /// `delta_have`. Either delta may be 0 to skip that side.
    ///
    /// The `_conn` suffix is preserved on the method name to signal
    /// "this takes a connection / tx from the caller" — Phase B-9
    /// (match.rs) will lift this suffix and switch the parameter to
    /// a generic `Executor` once the lifecycle service is updated.
    pub async fn apply_trade_delta_conn(
        &self,
        conn: &mut sqlx::PgConnection,
        user_id: i32,
        merch_id: i32,
        delta_trade: i32,
        delta_have: i32,
    ) -> Result<(), AppError> {
        if delta_trade != 0 {
            sqlx::query(
                "UPDATE inventory SET quantity = GREATEST(quantity - $1, 0)
                 WHERE user_id = $2 AND merch_id = $3 AND status = 'TRADE'",
            )
            .bind(delta_trade)
            .bind(user_id)
            .bind(merch_id)
            .execute(&mut *conn)
            .await?;
        }
        if delta_have != 0 {
            sqlx::query(
                r#"INSERT INTO inventory (user_id, merch_id, status, quantity)
                   VALUES ($1, $2, 'HAVE', $3)
                   ON CONFLICT (user_id, merch_id, status)
                   DO UPDATE SET quantity = inventory.quantity + $3"#,
            )
            .bind(user_id)
            .bind(merch_id)
            .bind(delta_have)
            .execute(&mut *conn)
            .await?;
        }
        Ok(())
    }
}
