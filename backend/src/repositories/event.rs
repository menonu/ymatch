//! Event aggregate repository.
//!
//! [`EventRepository`] is the abstract interface for the `events` table
//! and the related stats (event_views / event_favorites / inventory
//! participation) that the `Event` proto message exposes.
//!
//! Phase 5 of #163 lifts the fat SELECT in `events.rs::list_events`
//! (which uses 3 subqueries: unique_views, active_participants,
//! is_favorite, is_joined) into the repository without changing the
//! SQL.

use crate::error::AppError;
use crate::generated::ymatch::Event;
use crate::handlers::mappers::to_rfc3339;
use crate::repositories::RepositoryFuture;
use sqlx::{PgPool, Row};

/// Abstract event repository.
pub trait EventRepository: Send + Sync {
    /// List events with all the stats subqueries populated. The
    /// `viewer_id` (optional) controls which drafts are visible
    /// (creator's own drafts are visible only to themselves) and the
    /// `is_favorite` / `is_joined` flags. The 3-subquery SELECT is kept
    /// as-is — it's the only complex piece and is exercised by the
    /// existing integration tests.
    fn list_with_stats<'a>(
        &'a self,
        viewer_id: Option<i32>,
    ) -> RepositoryFuture<'a, Result<Vec<Event>, AppError>>;

    /// Get a single event with stats by id. Returns `None` if the event
    /// does not exist.
    fn get_with_stats<'a>(
        &'a self,
        event_id: i32,
        viewer_id: Option<i32>,
    ) -> RepositoryFuture<'a, Result<Option<Event>, AppError>>;

    /// Create a new event. `status` defaults to `"published"` if `None`.
    fn create<'a>(
        &'a self,
        name: &'a str,
        creator_id: i32,
        status: Option<&'a str>,
    ) -> RepositoryFuture<'a, Result<Event, AppError>>;

    /// Update an event's name. Returns `None` if the event does not exist.
    fn update_name<'a>(
        &'a self,
        event_id: i32,
        name: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<Event>, AppError>>;

    /// Publish a draft event (status -> 'published'). Returns `None` if
    /// the event does not exist.
    fn publish<'a>(&'a self, event_id: i32) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Delete an event outright. Used by the admin path.
    fn delete<'a>(&'a self, event_id: i32) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Look up the `creator_id` for permission checks. Returns `None` if
    /// the event does not exist.
    fn get_creator<'a>(
        &'a self,
        event_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<Option<i32>>, AppError>>;

    /// Search events by name (case-insensitive). Returns at most `limit`
    /// results, all of which are published.
    fn search<'a>(
        &'a self,
        search_term: &'a str,
        limit: i32,
    ) -> RepositoryFuture<'a, Result<Vec<(i32, String)>, AppError>>;
}

/// PostgreSQL implementation of [`EventRepository`].
pub struct PgEventRepository {
    pool: PgPool,
}

impl PgEventRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

fn event_from_row(row: &sqlx::postgres::PgRow) -> Event {
    Event {
        id: row.get("id"),
        name: row.get("name"),
        creator_id: row.get("creator_id"),
        created_at: to_rfc3339(row.get("created_at")),
        unique_views: row.get::<Option<i64>, _>("unique_views").map(|v| v as i32),
        active_participants: Some(row.get::<i64, _>("active_participants") as i32),
        is_favorite: Some(row.get("is_favorite")),
        is_joined: Some(row.get("is_joined")),
        status: Some(row.get("status")),
    }
}

impl EventRepository for PgEventRepository {
    fn list_with_stats<'a>(
        &'a self,
        viewer_id: Option<i32>,
    ) -> RepositoryFuture<'a, Result<Vec<Event>, AppError>> {
        Box::pin(async move {
            let sql = r#"
                SELECT
                    e.id,
                    e.name,
                    e.creator_id,
                    e.created_at,
                    e.status,
                    (SELECT COUNT(*) FROM event_views v WHERE v.event_id = e.id) as unique_views,
                    (
                        SELECT COUNT(DISTINCT i.user_id)
                        FROM inventory i
                        JOIN merchandise m ON m.id = i.merch_id
                        WHERE m.event_id = e.id AND i.quantity > 0
                    ) as active_participants,
                    EXISTS(SELECT 1 FROM event_favorites f WHERE f.event_id = e.id AND f.user_id = $1) as is_favorite,
                    EXISTS(
                        SELECT 1 FROM inventory i
                        JOIN merchandise m ON m.id = i.merch_id
                        WHERE m.event_id = e.id AND i.user_id = $1 AND i.quantity > 0
                    ) as is_joined
                FROM events e
                WHERE e.status = 'published' OR e.creator_id = $1
                ORDER BY e.created_at DESC
                "#;
            let rows = sqlx::query(sql)
                .bind(viewer_id)
                .fetch_all(&self.pool)
                .await?;
            Ok(rows.iter().map(event_from_row).collect())
        })
    }

    fn get_with_stats<'a>(
        &'a self,
        event_id: i32,
        _viewer_id: Option<i32>,
    ) -> RepositoryFuture<'a, Result<Option<Event>, AppError>> {
        Box::pin(async move {
            let sql = r#"SELECT e.id, e.name, e.creator_id, e.created_at, e.status,
                          (SELECT COUNT(*) FROM event_views v WHERE v.event_id = e.id) as unique_views,
                          (SELECT COUNT(DISTINCT i.user_id) FROM inventory i JOIN merchandise m ON m.id = i.merch_id WHERE m.event_id = e.id AND i.quantity > 0) as active_participants
                   FROM events e WHERE e.id = $1"#;
            let row = sqlx::query(sql)
                .bind(event_id)
                .fetch_optional(&self.pool)
                .await?;
            let Some(row) = row else {
                return Ok(None);
            };
            // For get_with_stats, the is_favorite / is_joined flags default
            // to false (the caller is typically the event detail page; the
            // frontend re-fetches the user's favorite status from
            // /api/v1/user/:id/favorite_groups when needed).
            Ok(Some(Event {
                id: row.get("id"),
                name: row.get("name"),
                creator_id: row.get("creator_id"),
                created_at: to_rfc3339(row.get("created_at")),
                unique_views: row.get::<Option<i64>, _>("unique_views").map(|v| v as i32),
                active_participants: Some(row.get::<i64, _>("active_participants") as i32),
                is_favorite: Some(false),
                is_joined: Some(false),
                status: Some(row.get("status")),
            }))
        })
    }

    fn create<'a>(
        &'a self,
        name: &'a str,
        creator_id: i32,
        status: Option<&'a str>,
    ) -> RepositoryFuture<'a, Result<Event, AppError>> {
        let status = status.unwrap_or("published");
        Box::pin(async move {
            let row = sqlx::query(
                "INSERT INTO events (name, creator_id, status) VALUES ($1, $2, $3)
                 RETURNING id, name, creator_id, created_at, status",
            )
            .bind(name)
            .bind(creator_id)
            .bind(status)
            .fetch_one(&self.pool)
            .await?;
            // The create path returns a default-shaped Event; the
            // caller (handler) does not depend on stats here.
            Ok(Event {
                id: row.get("id"),
                name: row.get("name"),
                creator_id: row.get("creator_id"),
                created_at: to_rfc3339(row.get("created_at")),
                unique_views: Some(0),
                active_participants: Some(0),
                is_favorite: Some(false),
                is_joined: Some(false),
                status: Some(row.get("status")),
            })
        })
    }

    fn update_name<'a>(
        &'a self,
        event_id: i32,
        name: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<Event>, AppError>> {
        Box::pin(async move {
            let row = sqlx::query(
                "UPDATE events SET name = $1 WHERE id = $2
                 RETURNING id, name, creator_id, created_at, status",
            )
            .bind(name)
            .bind(event_id)
            .fetch_optional(&self.pool)
            .await?;
            Ok(row.map(|r| Event {
                id: r.get("id"),
                name: r.get("name"),
                creator_id: r.get("creator_id"),
                created_at: to_rfc3339(r.get("created_at")),
                unique_views: Some(0),
                active_participants: Some(0),
                is_favorite: Some(false),
                is_joined: Some(false),
                status: Some(r.get("status")),
            }))
        })
    }

    fn publish<'a>(&'a self, event_id: i32) -> RepositoryFuture<'a, Result<Option<()>, AppError>> {
        Box::pin(async move {
            let affected = sqlx::query("UPDATE events SET status = 'published' WHERE id = $1")
                .bind(event_id)
                .execute(&self.pool)
                .await?
                .rows_affected();
            if affected == 0 {
                Ok(None)
            } else {
                Ok(Some(()))
            }
        })
    }

    fn delete<'a>(&'a self, event_id: i32) -> RepositoryFuture<'a, Result<Option<()>, AppError>> {
        Box::pin(async move {
            let affected = sqlx::query("DELETE FROM events WHERE id = $1")
                .bind(event_id)
                .execute(&self.pool)
                .await?
                .rows_affected();
            if affected == 0 {
                Ok(None)
            } else {
                Ok(Some(()))
            }
        })
    }

    fn get_creator<'a>(
        &'a self,
        event_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<Option<i32>>, AppError>> {
        Box::pin(async move {
            let row = sqlx::query("SELECT creator_id FROM events WHERE id = $1")
                .bind(event_id)
                .fetch_optional(&self.pool)
                .await?;
            Ok(row.map(|r| r.get::<Option<i32>, _>("creator_id")))
        })
    }

    fn search<'a>(
        &'a self,
        search_term: &'a str,
        limit: i32,
    ) -> RepositoryFuture<'a, Result<Vec<(i32, String)>, AppError>> {
        Box::pin(async move {
            let rows = sqlx::query(
                "SELECT id, name FROM events WHERE name ILIKE $1 AND status = 'published' LIMIT $2",
            )
            .bind(search_term)
            .bind(limit)
            .fetch_all(&self.pool)
            .await?;
            Ok(rows.iter().map(|r| (r.get("id"), r.get("name"))).collect())
        })
    }
}
