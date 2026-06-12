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
}
