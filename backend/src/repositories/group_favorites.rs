//! GroupFavorites aggregate repository.
//!
//! [`GroupFavoritesRepository`] owns the `group_favorites` table operations.
//! Powers the toggle endpoint `handlers::events::toggle_favorite_group` and
//! the list endpoint `handlers::events::list_favorite_groups`.
//!
//! Phase B-4 of #191: migrated from the previous
//! `trait GroupFavoritesRepository + PgGroupFavoritesRepository` two-type
//! pattern to a single concrete struct, matching the Phase A shape.

use crate::error::AppError;
use crate::generated::ymatch::FavoriteGroup;
use sqlx::{PgPool, Row};

pub struct GroupFavoritesRepository {
    pool: PgPool,
}

impl GroupFavoritesRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Toggle: if the row exists, remove it; otherwise insert it. Returns
    /// the new state (`true` = favorited, `false` = unfavorited).
    pub async fn toggle(
        &self,
        user_id: i32,
        event_id: i32,
        group_name: &str,
    ) -> Result<bool, AppError> {
        let affected = sqlx::query(
            "DELETE FROM group_favorites WHERE user_id = $1 AND event_id = $2 AND group_name = $3",
        )
        .bind(user_id)
        .bind(event_id)
        .bind(group_name)
        .execute(&self.pool)
        .await?
        .rows_affected();
        if affected > 0 {
            return Ok(false);
        }
        sqlx::query(
            "INSERT INTO group_favorites (user_id, event_id, group_name) VALUES ($1, $2, $3)
             ON CONFLICT DO NOTHING",
        )
        .bind(user_id)
        .bind(event_id)
        .bind(group_name)
        .execute(&self.pool)
        .await?;
        Ok(true)
    }

    /// List a user's favorite groups joined to the event name and optional
    /// cosmetic `display_name` (#466).
    pub async fn list_for_user(&self, user_id: i32) -> Result<Vec<FavoriteGroup>, AppError> {
        let rows = sqlx::query(
            r#"SELECT gf.user_id, gf.event_id, gf.group_name, e.name as event_name,
                      mg.display_name AS display_name
               FROM group_favorites gf
               JOIN events e ON gf.event_id = e.id
               LEFT JOIN merchandise_groups mg
                 ON mg.event_id = gf.event_id AND mg.group_name = gf.group_name
               WHERE gf.user_id = $1
               ORDER BY gf.created_at DESC"#,
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .iter()
            .map(|row| FavoriteGroup {
                user_id: row.get("user_id"),
                event_id: row.get("event_id"),
                group_name: row.get("group_name"),
                event_name: Some(row.get("event_name")),
                // NULL / empty → omit so the UI falls back to group_name (#466).
                display_name: row
                    .get::<Option<String>, _>("display_name")
                    .filter(|s| !s.is_empty()),
            })
            .collect())
    }
}
