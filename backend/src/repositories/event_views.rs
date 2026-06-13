//! EventViews aggregate repository.
//!
//! [`EventViewsRepository`] owns the `event_views` table operations. The
//! struct holds a `PgPool` and exposes a plain `async fn` method (no
//! `RepositoryFuture` boxing, no trait) so it can be stored in
//! `Arc<EventViewsRepository>` in `AppState` and called from handlers.
//!
//! Phase B-1 of #191: migrated from the previous `trait EventViewsRepository +
//! PgEventViewsRepository` two-type pattern to a single concrete struct,
//! matching the Phase A shape on `MerchandiseRepository`.

use crate::error::AppError;
use sqlx::PgPool;

pub struct EventViewsRepository {
    pool: PgPool,
}

impl EventViewsRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Register a unique view (idempotent via the table's UNIQUE
    /// constraint on (event_id, user_id)).
    pub async fn register_view(&self, event_id: i32, user_id: i32) -> Result<(), AppError> {
        sqlx::query(
            "INSERT INTO event_views (event_id, user_id) VALUES ($1, $2)
             ON CONFLICT DO NOTHING",
        )
        .bind(event_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}
