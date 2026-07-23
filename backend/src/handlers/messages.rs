use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::handlers::common::{UserIdQuery, require_active_query_user};
use crate::routes::AppState;
use axum::{
    Json,
    extract::{Path, Query, State},
};

/// Max UTF-8 length for a chat message body (#491).
const MAX_MESSAGE_CONTENT_LEN: usize = 2000;

/// Client-allowed message types. `SYSTEM` is server-only (lifecycle notices).
fn validate_client_message_type(message_type: Option<&str>) -> Result<(), AppError> {
    match message_type {
        None | Some("TEXT") | Some("LOCATION") => Ok(()),
        Some(other) => Err(AppError::bad_request(format!(
            "unsupported message_type: {other}"
        ))),
    }
}

/// Ensure `user_id` is a participant of `match_id`. Returns 404 if the match
/// is missing (do not leak existence to outsiders via a different code).
async fn require_match_participant(
    state: &AppState,
    match_id: i32,
    user_id: i32,
) -> Result<(), AppError> {
    let snapshot = state
        .matches
        .get_status_snapshot(match_id)
        .await?
        .ok_or_else(|| AppError::not_found("Match not found"))?;
    if user_id != snapshot.user1_id && user_id != snapshot.user2_id {
        return Err(AppError::forbidden("Not part of this match"));
    }
    Ok(())
}

pub async fn list_messages(
    State(state): State<AppState>,
    Path(match_id): Path<i32>,
    Query(query): Query<UserIdQuery>,
) -> Result<Json<Vec<Message>>, AppError> {
    // #491: membership gate (still trusts client-supplied user_id until #373).
    let caller = require_active_query_user(&state, query.user_id).await?;
    require_match_participant(&state, match_id, caller.id).await?;
    let items = state.messages.list_for_match(match_id).await?;
    Ok(Json(items))
}

pub async fn send_message(
    State(state): State<AppState>,
    Path(match_id): Path<i32>,
    Json(payload): Json<SendMessageRequest>,
) -> Result<Json<Message>, AppError> {
    // #491: sender must be an active participant. Until session auth (#373),
    // identity is still body `sender_id`, but outsiders cannot inject into
    // matches they are not part of.
    let sender = state.policy.verify_active(payload.sender_id).await?;
    require_match_participant(&state, match_id, sender.id).await?;

    if payload.content.chars().count() > MAX_MESSAGE_CONTENT_LEN {
        return Err(AppError::bad_request(format!(
            "content exceeds maximum length of {MAX_MESSAGE_CONTENT_LEN}"
        )));
    }
    validate_client_message_type(payload.message_type.as_deref())?;

    let msg = state
        .messages
        .send(
            match_id,
            sender.id,
            &payload.content,
            payload.message_type.as_deref(),
            payload.latitude,
            payload.longitude,
        )
        .await?;
    Ok(Json(msg))
}
