//! Event aggregate repository.
//!
//! [`EventRepository`] owns the `events` table and the related stats
//! (event_views / event_favorites / inventory participation) that the
//! `Event` proto message exposes.
//!
//! Phase B-7 of #191: migrated from the previous
//! `trait EventRepository + PgEventRepository` two-type pattern to a
//! single concrete struct, matching the Phase A shape.

use crate::error::AppError;
use crate::generated::ymatch::Event;
use crate::handlers::mappers::to_rfc3339;
use sqlx::{PgPool, Row};

pub struct EventRepository {
    pool: PgPool,
}

impl EventRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// List events with all the stats subqueries populated. The
    /// `viewer_id` (optional) controls which drafts are visible
    /// (creator's own drafts are visible only to themselves) and the
    /// `is_favorite` / `is_joined` flags. The 3-subquery SELECT is kept
    /// as-is — it's the only complex piece and is exercised by the
    /// existing integration tests.
    pub async fn list_with_stats(&self, viewer_id: Option<i32>) -> Result<Vec<Event>, AppError> {
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
    }

    /// Get a single event with stats by id. Returns `None` if the event
    /// does not exist.
    pub async fn get_with_stats(
        &self,
        event_id: i32,
        _viewer_id: Option<i32>,
    ) -> Result<Option<Event>, AppError> {
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
    }

    /// Create a new event. `status` defaults to `"published"` if `None`.
    ///
    /// Takes a generic [`sqlx::Executor`] so the caller can run the insert
    /// inside an open transaction ([`crate::services::event::EventService`]
    /// does this so the event row and the auto-assigned `event/creator`
    /// `user_roles` row commit atomically — ADR 0004 §5).
    pub async fn create<'c, E>(
        &self,
        exec: E,
        name: &str,
        creator_id: i32,
        status: Option<&str>,
    ) -> Result<Event, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let status = status.unwrap_or("published");
        let row = sqlx::query(
            "INSERT INTO events (name, creator_id, status) VALUES ($1, $2, $3)
             RETURNING id, name, creator_id, created_at, status",
        )
        .bind(name)
        .bind(creator_id)
        .bind(status)
        .fetch_one(exec)
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
    }

    /// Update an event's name. Returns `None` if the event does not exist.
    pub async fn update_name(&self, event_id: i32, name: &str) -> Result<Option<Event>, AppError> {
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
    }

    /// Publish a draft event (status -> 'published'). Returns `None` if
    /// the event does not exist.
    pub async fn publish(&self, event_id: i32) -> Result<Option<()>, AppError> {
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
    }

    /// Delete an event outright. Used by the admin path.
    pub async fn delete(&self, event_id: i32) -> Result<Option<()>, AppError> {
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
    }

    /// Look up the `creator_id` for permission checks. Returns `None` if
    /// the event does not exist.
    pub async fn get_creator(&self, event_id: i32) -> Result<Option<Option<i32>>, AppError> {
        let row = sqlx::query("SELECT creator_id FROM events WHERE id = $1")
            .bind(event_id)
            .fetch_optional(&self.pool)
            .await?;
        Ok(row.map(|r| r.get::<Option<i32>, _>("creator_id")))
    }

    /// `SELECT creator_id … FOR UPDATE` on the event row. Returns `None` if
    /// the event is missing; otherwise `Some(creator_id)` (which may itself
    /// be `None`). The row lock is held until the surrounding transaction
    /// ends so concurrent creator transfers serialize on this row (#445).
    pub async fn lock_creator_for_update<'c, E>(
        &self,
        exec: E,
        event_id: i32,
    ) -> Result<Option<Option<i32>>, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let row = sqlx::query("SELECT creator_id FROM events WHERE id = $1 FOR UPDATE")
            .bind(event_id)
            .fetch_optional(exec)
            .await?;
        Ok(row.map(|r| r.get::<Option<i32>, _>("creator_id")))
    }

    /// Set `events.creator_id` for admin ownership transfer (#432).
    /// Runs on the caller's open transaction so it commits with the
    /// matching `user_roles` swap. Returns `false` if the event is missing.
    pub async fn set_creator<'c, E>(
        &self,
        exec: E,
        event_id: i32,
        new_creator_id: i32,
    ) -> Result<bool, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let affected = sqlx::query("UPDATE events SET creator_id = $1 WHERE id = $2")
            .bind(new_creator_id)
            .bind(event_id)
            .execute(exec)
            .await?
            .rows_affected();
        Ok(affected > 0)
    }

    /// Search events by name (case-insensitive). Returns at most `limit`
    /// results, all of which are published.
    pub async fn search(
        &self,
        search_term: &str,
        limit: i32,
    ) -> Result<Vec<(i32, String)>, AppError> {
        let rows = sqlx::query(
            "SELECT id, name FROM events WHERE name ILIKE $1 AND status = 'published' LIMIT $2",
        )
        .bind(search_term)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows.iter().map(|r| (r.get("id"), r.get("name"))).collect())
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
