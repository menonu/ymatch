//! GroupFavorites aggregate repository.
//!
//! [`GroupFavoritesRepository`] is the abstract interface for the
//! `group_favorites` table. Powers the toggle endpoint
//! `handlers::events::toggle_favorite_group` and the list endpoint
//! `handlers::events::list_favorite_groups`.

use crate::error::AppError;
use crate::generated::ymatch::FavoriteGroup;
use crate::repositories::RepositoryFuture;
use sqlx::{PgPool, Row};

pub trait GroupFavoritesRepository: Send + Sync {
    /// Toggle: if the row exists, remove it; otherwise insert it. Returns
    /// the new state (`true` = favorited, `false` = unfavorited).
    fn toggle<'a>(
        &'a self,
        user_id: i32,
        event_id: i32,
        group_name: &'a str,
    ) -> RepositoryFuture<'a, Result<bool, AppError>>;

    /// List a user's favorite groups joined to the event name.
    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<FavoriteGroup>, AppError>>;
}

pub struct PgGroupFavoritesRepository {
    pool: PgPool,
}

impl PgGroupFavoritesRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl GroupFavoritesRepository for PgGroupFavoritesRepository {
    fn toggle<'a>(
        &'a self,
        user_id: i32,
        event_id: i32,
        group_name: &'a str,
    ) -> RepositoryFuture<'a, Result<bool, AppError>> {
        Box::pin(async move {
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
        })
    }

    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<FavoriteGroup>, AppError>> {
        Box::pin(async move {
            let rows = sqlx::query(
                r#"SELECT gf.user_id, gf.event_id, gf.group_name, e.name as event_name
                   FROM group_favorites gf
                   JOIN events e ON gf.event_id = e.id
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
                })
                .collect())
        })
    }
}
