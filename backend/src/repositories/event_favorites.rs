//! EventFavorites aggregate repository.
//!
//! [`EventFavoritesRepository`] owns the `event_favorites` table operations.
//! Powers the toggle endpoint `handlers::events::toggle_favorite`.
//!
//! Phase B-2 of #191: migrated from the previous
//! `trait EventFavoritesRepository + PgEventFavoritesRepository` two-type
//! pattern to a single concrete struct, matching the Phase A shape.

use crate::error::AppError;
use sqlx::PgPool;

pub struct EventFavoritesRepository {
    pool: PgPool,
}

impl EventFavoritesRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Toggle: if the row exists, remove it; otherwise insert it. Returns
    /// the new state (`true` = favorited, `false` = unfavorited).
    pub async fn toggle(&self, user_id: i32, event_id: i32) -> Result<bool, AppError> {
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
    }
}
