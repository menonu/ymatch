//! Handlers for merchandise (merch) operations.
//!
//! These handlers are intentionally thin: they parse + validate the request,
//! delegate to [`MerchandiseRepository`] (and, where needed, the policy
//! services), and format the response. All SQL lives in the repository.
//!
//! Phase 3 of #163 also absorbs the `merchandise_groups` work from Issue #128
//! backend (originally PR #162). The `group_description` field on each
//! `Merchandise` response is auto-populated by the repository's LEFT JOIN.

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::routes::AppState;
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};

#[derive(serde::Deserialize)]
pub struct ListMerchQuery {
    pub user_id: Option<i32>,
}

pub async fn list_all_merch(
    State(state): State<AppState>,
) -> Result<Json<Vec<Merchandise>>, AppError> {
    let items = state.merch.list_all().await?;
    Ok(Json(items))
}

pub async fn list_merch(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<ListMerchQuery>,
) -> Result<Json<Vec<Merchandise>>, AppError> {
    let items = state.merch.list_for_event(event_id, query.user_id).await?;
    Ok(Json(items))
}

pub async fn create_merch(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateMerchRequest>,
) -> Result<Json<Merchandise>, AppError> {
    if let Some(creator_id) = payload.creator_id {
        state.policy.verify_active(creator_id).await?;
    }
    let item = state.merch.create(event_id, payload).await?;
    Ok(Json(item))
}

pub async fn update_merch(
    State(state): State<AppState>,
    Path((event_id, merch_id)): Path<(i32, i32)>,
    Json(payload): Json<UpdateMerchRequest>,
) -> Result<Json<Merchandise>, AppError> {
    let user = state.policy.verify_active(payload.user_id).await?;
    let creator = state
        .merch
        .get_creator(event_id, merch_id)
        .await?
        .ok_or_else(|| AppError::not_found("Merchandise not found"))?
        .unwrap_or(-1);
    state
        .policy
        .require_owner_or_role(&user, creator, &["admin", "moderator"])?;
    let item = state
        .merch
        .update(event_id, merch_id, payload)
        .await?
        .ok_or_else(|| AppError::not_found("Merchandise not found"))?;
    Ok(Json(item))
}

pub async fn publish_merch(
    State(state): State<AppState>,
    Path((event_id, merch_id)): Path<(i32, i32)>,
    Json(payload): Json<UserActionRequest>,
) -> Result<StatusCode, AppError> {
    let user = state.policy.verify_active(payload.user_id).await?;
    let creator = state
        .merch
        .get_creator(event_id, merch_id)
        .await?
        .ok_or_else(|| AppError::not_found("Merchandise not found"))?
        .unwrap_or(-1);
    state
        .policy
        .require_owner_or_role(&user, creator, &["admin", "moderator"])?;
    state.merch.publish(event_id, merch_id).await?;
    Ok(StatusCode::OK)
}

pub async fn delete_merch_by_creator(
    State(state): State<AppState>,
    Path((event_id, merch_id)): Path<(i32, i32)>,
    axum::extract::Query(query): axum::extract::Query<ListMerchQuery>,
) -> Result<StatusCode, AppError> {
    let requester_id = query
        .user_id
        .ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;

    // 3-way permission check (merch creator OR event creator OR admin/moderator).
    // The event_creator_id comes from a quick pool query — Phase 5 will lift
    // this into EventRepository. For now we keep the raw SQL here because it
    // is one read of a single column and EventRepository is scheduled for
    // Phase 5.
    let event_creator_id: Option<i32> =
        sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
            .bind(event_id)
            .fetch_optional(&state.pool)
            .await?;

    state
        .merch_policy
        .require_can_modify(requester_id, event_id, merch_id, event_creator_id)
        .await?;

    state.merch.delete_merch(event_id, merch_id).await?;
    Ok(StatusCode::OK)
}

pub async fn update_merch_sort_order(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    Json(payload): Json<UpdateMerchSortOrderRequest>,
) -> Result<StatusCode, AppError> {
    if payload.event_id != event_id {
        return Err(AppError::bad_request("Event ID mismatch"));
    }
    state
        .merch
        .update_sort_orders(event_id, payload.sort_orders)
        .await?;
    Ok(StatusCode::OK)
}
