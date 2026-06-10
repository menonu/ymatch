//! EventFavorites aggregate repository.
//!
//! [`EventFavoritesRepository`] is the abstract interface for the
//! `event_favorites` table. Powers the toggle endpoint
//! `handlers::events::toggle_favorite`.

use crate::error::AppError;
use crate::repositories::RepositoryFuture;
use sqlx::PgPool;

pub trait EventFavoritesRepository: Send + Sync {
    /// Toggle: if the row exists, remove it; otherwise insert it. Returns
    /// the new state (`true` = favorited, `false` = unfavorited).
    fn toggle<'a>(
        &'a self,
        user_id: i32,
        event_id: i32,
    ) -> RepositoryFuture<'a, Result<bool, AppError>>;
}

pub struct PgEventFavoritesRepository {
    pool: PgPool,
}

impl PgEventFavoritesRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl EventFavoritesRepository for PgEventFavoritesRepository {
    fn toggle<'a>(
        &'a self,
        user_id: i32,
        event_id: i32,
    ) -> RepositoryFuture<'a, Result<bool, AppError>> {
        Box::pin(async move {
            // Try to delete first; if nothing was deleted, insert.
            let affected =
                sqlx::query("DELETE FROM event_favorites WHERE user_id = $1 AND event_id = $2")
                    .bind(user_id)
                    .bind(event_id)
                    .execute(&self.pool)
                    .await?
                    .rows_affected();
            if affected > 0 {
                return Ok(false);
            }
            sqlx::query(
                "INSERT INTO event_favorites (user_id, event_id) VALUES ($1, $2)
                 ON CONFLICT DO NOTHING",
            )
            .bind(user_id)
            .bind(event_id)
            .execute(&self.pool)
            .await?;
            Ok(true)
        })
    }
}
