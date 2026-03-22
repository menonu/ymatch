use crate::generated::ymatch::*;
use axum::{extract::Path, extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

pub async fn list_messages(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
) -> Result<Json<Vec<Message>>, (StatusCode, String)> {
    let rows = sqlx::query(
        "SELECT id, match_id, sender_id, content, created_at, message_type, latitude, longitude FROM messages WHERE match_id = $1 ORDER BY created_at ASC"
    )
    .bind(match_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let messages = rows
        .into_iter()
        .map(|row| Message {
            id: row.get("id"),
            match_id: row.get("match_id"),
            sender_id: row.get("sender_id"),
            content: row.get("content"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            message_type: row.get("message_type"),
            latitude: row.get("latitude"),
            longitude: row.get("longitude"),
        })
        .collect();

    Ok(Json(messages))
}

pub async fn send_message(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<SendMessageRequest>,
) -> Result<Json<Message>, (StatusCode, String)> {
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
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(Message {
        id: row.get("id"),
        match_id: row.get("match_id"),
        sender_id: row.get("sender_id"),
        content: row.get("content"),
        created_at: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
        message_type: row.get("message_type"),
        latitude: row.get("latitude"),
        longitude: row.get("longitude"),
    }))
}
