//! Handlers for the `merchandise_groups` endpoints introduced in Issue #128.
//!
//! These handlers are intentionally thin: they parse + validate the request,
//! delegate to [`MerchandiseGroupRepository`], and format the response.
//! All SQL lives in the repository.

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::routes::AppState;
use crate::services::rbac::{Permission, Scope};
use axum::{
    Json,
    extract::{Path, State},
};

pub async fn list_event_groups(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
) -> Result<Json<ListGroupsResponse>, AppError> {
    let response = state.groups.list_for_event(event_id).await?;
    Ok(Json(response))
}

pub async fn create_event_group(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateGroupRequest>,
) -> Result<Json<MerchandiseGroup>, AppError> {
    if payload.event_id != event_id {
        return Err(AppError::bad_request(
            "event_id in path and body must match",
        ));
    }
    let group = state.groups.create(payload).await?;
    Ok(Json(group))
}

pub async fn update_event_group(
    State(state): State<AppState>,
    Path((event_id, group_name)): Path<(i32, String)>,
    Json(payload): Json<UpdateGroupRequest>,
) -> Result<Json<MerchandiseGroup>, AppError> {
    if payload.event_id != event_id {
        return Err(AppError::bad_request(
            "event_id in path and body must match",
        ));
    }
    if payload.group_name != group_name {
        return Err(AppError::bad_request(
            "group_name in path and body must match",
        ));
    }

    // Verify the caller first, then confirm the group exists (404) before the
    // RBAC check, so a missing group is not leaked as a 403 to a caller who
    // lacks the event role — the `verify_active`-then-404 ordering used by
    // `update_event` / `create_merch`.
    let user = state.policy.verify_active(payload.user_id).await?;
    let group = state
        .groups
        .get(event_id, &group_name)
        .await?
        .ok_or_else(|| AppError::not_found("Group not found. Create it first via POST /groups"))?;
    let group_creator_id = group.created_by;
    // #370: the prior `group_creator OR require_role(&["admin","moderator"])`
    // is now ownership + RBAC. The group creator is an ownership check; the
    // event creator / editor / admin / moderator path is the `group.edit`
    // permission (event scope), with the admin bypass and `group.edit.any`
    // (moderator) overlap resolved inside `RbacService::check`.
    if group_creator_id != Some(user.id) {
        state
            .rbac_service
            .check(&user, &Scope::Event(event_id), Permission::GroupEdit)
            .await?;
    }

    let updated = state
        .groups
        .update(payload)
        .await?
        .ok_or_else(|| AppError::not_found("Group disappeared mid-update"))?;
    Ok(Json(updated))
}
