//! Handlers for match-related operations.
//!
//! Phase 4 of #163 splits this file into:
//! - thin handlers in this file (parse + delegate)
//! - [`crate::repositories::match_::MatchRepository`] (SQL)
//! - [`crate::services::match_lifecycle::MatchLifecycleService`]
//!   (the state-machine transactions)
//!
//! The N+1 in the old `list_matches` is gone — see
//! [`crate::repositories::match_::MatchRepository::list_for_user`].

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::repositories::match_::MatchRepository;
use crate::routes::AppState;
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use std::sync::Arc;

pub async fn list_all_matches(
    State(matches): State<Arc<MatchRepository>>,
) -> Result<Json<Vec<TradeMatch>>, AppError> {
    let items = matches.list_all().await?;
    Ok(Json(items))
}

pub async fn list_matches(
    State(matches): State<Arc<MatchRepository>>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<TradeMatch>>, AppError> {
    let items = matches.list_for_user(user_id).await?;
    Ok(Json(items))
}

/// Submit an offer: transition PENDING → OFFERED, insert match_items.
pub async fn offer_trade(
    State(state): State<AppState>,
    Path(match_id): Path<i32>,
    Json(payload): Json<OfferTradeRequest>,
) -> Result<StatusCode, AppError> {
    state.match_lifecycle.offer(match_id, payload).await?;
    Ok(StatusCode::OK)
}

pub async fn update_match_status(
    State(state): State<AppState>,
    Path(match_id): Path<i32>,
    Json(payload): Json<UpdateMatchStatusRequest>,
) -> Result<StatusCode, AppError> {
    state
        .match_lifecycle
        .change_status(match_id, &payload.status)
        .await?;
    Ok(StatusCode::OK)
}

/// Post-complete: apply inventory changes for the requesting user only.
pub async fn apply_trade_inventory(
    State(state): State<AppState>,
    Path(match_id): Path<i32>,
    Json(payload): Json<ApplyInventoryRequest>,
) -> Result<StatusCode, AppError> {
    state
        .match_lifecycle
        .apply_inventory(match_id, payload.user_id)
        .await?;
    Ok(StatusCode::OK)
}

pub async fn match_notification_counts(
    State(matches): State<Arc<MatchRepository>>,
    Path(user_id): Path<i32>,
) -> Result<Json<NotificationCounts>, AppError> {
    let counts = matches.notification_counts(user_id).await?;
    Ok(Json(counts))
}
