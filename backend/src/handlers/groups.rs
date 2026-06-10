//! Handlers for the `merchandise_groups` endpoints introduced in Issue #128.
//!
//! These handlers are intentionally thin: they parse + validate the request,
//! delegate to [`MerchandiseGroupRepository`], and format the response.
//! All SQL lives in the repository.

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::routes::AppState;
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

    // Permission check: group creator or elevated role.
    let group = state
        .groups
        .get(event_id, &group_name)
        .await?
        .ok_or_else(|| AppError::not_found("Group not found. Create it first via POST /groups"))?;
    let group_creator = group.created_by;
    let user = state.policy.verify_active(payload.user_id).await?;
    let allowed = group_creator == Some(user.id)
        || state
            .policy
            .require_role(&user, &["admin", "moderator"])
            .is_ok();
    if !allowed {
        return Err(AppError::forbidden(
            "Only the group creator or an admin/moderator can edit this group",
        ));
    }

    let updated = state
        .groups
        .update(payload)
        .await?
        .ok_or_else(|| AppError::not_found("Group disappeared mid-update"))?;
    Ok(Json(updated))
}
