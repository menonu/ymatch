//! Message aggregate repository.
//!
//! [`MessageRepository`] is the abstract interface for the `messages`
//! table. Powers the chat endpoints
//! `handlers::messages::list_messages` and `handlers::messages::send_message`.

use crate::error::AppError;
use crate::generated::ymatch::Message;
use crate::handlers::mappers::to_rfc3339;
use crate::repositories::RepositoryFuture;
use sqlx::{PgPool, Row};

/// Abstract message repository.
pub trait MessageRepository: Send + Sync {
    /// List all messages in a match, ordered by `created_at ASC`.
    fn list_for_match<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<Message>, AppError>>;

    /// Send a message. `message_type` defaults to "TEXT" if `None`.
    /// `latitude` and `longitude` are optional (used for the LOCATION type).
    fn send<'a>(
        &'a self,
        match_id: i32,
        sender_id: i32,
        content: &'a str,
        message_type: Option<&'a str>,
        latitude: Option<f64>,
        longitude: Option<f64>,
    ) -> RepositoryFuture<'a, Result<Message, AppError>>;
}

/// PostgreSQL implementation of [`MessageRepository`].
pub struct PgMessageRepository {
    pool: PgPool,
}

impl PgMessageRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

fn message_from_row(row: &sqlx::postgres::PgRow) -> Message {
    Message {
        id: row.get("id"),
        match_id: row.get("match_id"),
        sender_id: row.get("sender_id"),
        content: row.get("content"),
        created_at: to_rfc3339(row.get("created_at")),
        message_type: row.get("message_type"),
        latitude: row.get("latitude"),
        longitude: row.get("longitude"),
    }
}

impl MessageRepository for PgMessageRepository {
    fn list_for_match<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<Message>, AppError>> {
        Box::pin(async move {
            let rows = sqlx::query(
                "SELECT id, match_id, sender_id, content, created_at, message_type, latitude, longitude
                 FROM messages WHERE match_id = $1 ORDER BY created_at ASC",
            )
            .bind(match_id)
            .fetch_all(&self.pool)
            .await?;
            Ok(rows.iter().map(message_from_row).collect())
        })
    }

    fn send<'a>(
        &'a self,
        match_id: i32,
        sender_id: i32,
        content: &'a str,
        message_type: Option<&'a str>,
        latitude: Option<f64>,
        longitude: Option<f64>,
    ) -> RepositoryFuture<'a, Result<Message, AppError>> {
        Box::pin(async move {
            let msg_type = message_type.unwrap_or("TEXT");
            let row = sqlx::query(
                "INSERT INTO messages (match_id, sender_id, content, message_type, latitude, longitude)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 RETURNING id, match_id, sender_id, content, created_at, message_type, latitude, longitude",
            )
            .bind(match_id)
            .bind(sender_id)
            .bind(content)
            .bind(msg_type)
            .bind(latitude)
            .bind(longitude)
            .fetch_one(&self.pool)
            .await?;
            Ok(message_from_row(&row))
        })
    }
}
