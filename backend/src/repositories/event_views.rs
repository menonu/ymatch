//! EventViews aggregate repository.
//!
//! [`EventViewsRepository`] is the abstract interface for the
//! `event_views` table. Used by the per-event view endpoint and the
//! `unique_views` subquery in the events-with-stats SQL.

use crate::error::AppError;
use crate::repositories::RepositoryFuture;
use sqlx::PgPool;

pub trait EventViewsRepository: Send + Sync {
    /// Register a unique view (idempotent via the table's UNIQUE
    /// constraint on (event_id, user_id)).
    fn register_view<'a>(
        &'a self,
        event_id: i32,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>>;
}

pub struct PgEventViewsRepository {
    pool: PgPool,
}

impl PgEventViewsRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl EventViewsRepository for PgEventViewsRepository {
    fn register_view<'a>(
        &'a self,
        event_id: i32,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            sqlx::query(
                "INSERT INTO event_views (event_id, user_id) VALUES ($1, $2)
                 ON CONFLICT DO NOTHING",
            )
            .bind(event_id)
            .bind(user_id)
            .execute(&self.pool)
            .await?;
            Ok(())
        })
    }
}
