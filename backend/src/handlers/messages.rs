use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::repositories::message::MessageRepository;
use axum::{
    Json,
    extract::{Path, State},
};
use std::sync::Arc;

pub async fn list_messages(
    State(messages): State<Arc<dyn MessageRepository>>,
    Path(match_id): Path<i32>,
) -> Result<Json<Vec<Message>>, AppError> {
    let items = messages.list_for_match(match_id).await?;
    Ok(Json(items))
}

pub async fn send_message(
    State(messages): State<Arc<dyn MessageRepository>>,
    Path(match_id): Path<i32>,
    Json(payload): Json<SendMessageRequest>,
) -> Result<Json<Message>, AppError> {
    let msg = messages
        .send(
            match_id,
            payload.sender_id,
            &payload.content,
            payload.message_type.as_deref(),
            payload.latitude,
            payload.longitude,
        )
        .await?;
    Ok(Json(msg))
}
