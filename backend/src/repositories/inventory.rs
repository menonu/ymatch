//! Inventory aggregate repository.
//!
//! [`InventoryRepository`] is the abstract interface for the `inventory`
//! table. It powers:
//!
//! - the user inventory list endpoint (`handlers::inventory::get_user_inventory`)
//! - the inventory upsert endpoint (`handlers::inventory::update_inventory`)
//! - the trade-apply endpoint via
//!   [`crate::services::match_lifecycle::MatchLifecycleService`]

use crate::error::AppError;
use crate::generated::ymatch::InventoryItem;
use crate::repositories::RepositoryFuture;
use sqlx::{PgPool, Row};

/// Abstract inventory repository.
pub trait InventoryRepository: Send + Sync {
    /// Upsert a single inventory row keyed by `(user_id, merch_id, status)`.
    /// Returns the resulting row.
    fn upsert<'a>(
        &'a self,
        user_id: i32,
        merch_id: i32,
        status: &'a str,
        quantity: i32,
    ) -> RepositoryFuture<'a, Result<InventoryItem, AppError>>;

    /// List all inventory rows for a user, joined to `merchandise` for
    /// `merch_name` / `photo_url` / `group_name`.
    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<InventoryItem>, AppError>>;

    /// Apply a single trade delta. Either `delta_trade` is non-zero (the
    /// user's TRADE row is decremented, clamped to 0) or `delta_have` is
    /// non-zero (a HAVE row is upserted with the new total). This is the
    /// primitive used by the lifecycle service when applying the
    /// consequences of a completed match.
    fn apply_trade_delta<'a>(
        &'a self,
        user_id: i32,
        merch_id: i32,
        delta_trade: i32,
        delta_have: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>>;
}

/// PostgreSQL implementation of [`InventoryRepository`].
pub struct PgInventoryRepository {
    pool: PgPool,
}

impl PgInventoryRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl InventoryRepository for PgInventoryRepository {
    fn upsert<'a>(
        &'a self,
        user_id: i32,
        merch_id: i32,
        status: &'a str,
        quantity: i32,
    ) -> RepositoryFuture<'a, Result<InventoryItem, AppError>> {
        Box::pin(async move {
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
                merch_name: None,
                photo_url: None,
                group_name: None,
            })
        })
    }

    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<InventoryItem>, AppError>> {
        Box::pin(async move {
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
        })
    }

    fn apply_trade_delta<'a>(
        &'a self,
        user_id: i32,
        merch_id: i32,
        delta_trade: i32,
        delta_have: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            if delta_trade != 0 {
                // Decrement the user's TRADE row, clamped at 0.
                sqlx::query(
                    "UPDATE inventory SET quantity = GREATEST(quantity - $1, 0)
                     WHERE user_id = $2 AND merch_id = $3 AND status = 'TRADE'",
                )
                .bind(delta_trade)
                .bind(user_id)
                .bind(merch_id)
                .execute(&self.pool)
                .await?;
            }
            if delta_have != 0 {
                // Upsert: the user gains this item. We use ON CONFLICT to
                // sum the new quantity onto any existing HAVE row.
                sqlx::query(
                    r#"INSERT INTO inventory (user_id, merch_id, status, quantity)
                       VALUES ($1, $2, 'HAVE', $3)
                       ON CONFLICT (user_id, merch_id, status)
                       DO UPDATE SET quantity = inventory.quantity + $3"#,
                )
                .bind(user_id)
                .bind(merch_id)
                .bind(delta_have)
                .execute(&self.pool)
                .await?;
            }
            Ok(())
        })
    }
}
