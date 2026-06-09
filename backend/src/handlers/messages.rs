use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::handlers::mappers::to_rfc3339;
use axum::{
    Json,
    extract::{Path, State},
};
use sqlx::{PgPool, Row};

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

pub async fn list_messages(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
) -> Result<Json<Vec<Message>>, AppError> {
    let rows = sqlx::query(
        "SELECT id, match_id, sender_id, content, created_at, message_type, latitude, longitude FROM messages WHERE match_id = $1 ORDER BY created_at ASC"
    )
    .bind(match_id)
    .fetch_all(&pool)
    .await?;

    let messages: Vec<Message> = rows.iter().map(message_from_row).collect();
    Ok(Json(messages))
}

pub async fn send_message(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<SendMessageRequest>,
) -> Result<Json<Message>, AppError> {
    let row = sqlx::query(
        "INSERT INTO messages (match_id, sender_id, content, message_type, latitude, longitude) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, match_id, sender_id, content, created_at, message_type, latitude, longitude"
    )
    .bind(match_id)
    .bind(payload.sender_id)
    .bind(payload.content)
    .bind(payload.message_type.unwrap_or_else(|| "TEXT".to_string()))
    .bind(payload.latitude)
    .bind(payload.longitude)
    .fetch_one(&pool)
    .await?;

    Ok(Json(message_from_row(&row)))
}
