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
use crate::services::rbac::{Permission, Scope};
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
    // ADR 0005: `creator_id` is the caller identity (the merch creator = the
    // caller) and is required for authorization. Previously creation was open
    // to any active user; it is now a curated action gated by `merch.create`
    // (event scope), granted to the event creator + editor, with the admin
    // superuser bypass and `merch.create.any` (moderator) overlap resolved
    // inside RbacService::check.
    let creator_id = payload
        .creator_id
        .ok_or_else(|| AppError::bad_request("creator_id is required"))?;
    let user = state.policy.verify_active(creator_id).await?;
    // Confirm the event exists (404) before the RBAC check so a missing event
    // is not leaked as a 403 to a caller who lacks the event role — matches
    // `update_event`'s convention.
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    state
        .rbac_service
        .check(&user, &Scope::Event(event_id), Permission::MerchCreate)
        .await?;
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

    let user = state.policy.verify_active(requester_id).await?;

    // ADR 0004: the prior 3-way rule (merch creator OR event creator OR
    // admin/moderator) is now expressed as ownership + RBAC. The merch
    // creator is an ownership check (ordinary trading is ownership-checked,
    // not role-checked); the event creator / editor / admin / moderator path
    // is the `merch.delete` permission (event scope), with the admin bypass
    // and `merch.delete.any` (moderator) overlap resolved inside
    // RbacService::check.
    let merch_creator_id: Option<i32> = state
        .merch
        .get_creator(event_id, merch_id)
        .await?
        .ok_or_else(|| AppError::not_found("Merchandise not found"))?;
    if Some(user.id) == merch_creator_id {
        state.merch.delete_merch(event_id, merch_id).await?;
        return Ok(StatusCode::OK);
    }
    state
        .rbac_service
        .check(&user, &Scope::Event(event_id), Permission::MerchDelete)
        .await?;

    state.merch.delete_merch(event_id, merch_id).await?;
    Ok(StatusCode::OK)
}
