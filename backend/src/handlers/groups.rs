//! Handlers for the `merchandise_groups` endpoints introduced in Issue #128.
//!
//! Thin HTTP layer: parse/validate, authz gates, map responses.
//! Multi-step create/transfer transactions live in
//! [`crate::services::group::GroupService`]; single-statement SQL lives in
//! [`crate::repositories::group::MerchandiseGroupRepository`]. Group-scoped
//! RBAC member APIs are #443.

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::handlers::common::{TransferCreatorRequest, UserIdQuery};
use crate::routes::AppState;
use crate::services::group::TransferCaller;
use crate::services::rbac::{Permission, Scope};
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
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
    // #491: group create was open and assigned group/creator from body
    // user_id. Require active caller + event-scoped merch.create (same
    // family as catalog curation / add-merch). Ownership is forced to the
    // verified caller — never trust an arbitrary body user_id for the role.
    let user = state.policy.verify_active(payload.user_id).await?;
    // 404 before 403 so a missing event is not leaked as Forbidden.
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    state
        .rbac_service
        .check(&user, &Scope::Event(event_id), Permission::MerchCreate)
        .await?;

    // Force created_by / creator role onto the verified caller.
    let mut owned = payload;
    owned.user_id = user.id;

    // #443: GroupService owns group row + group/creator role in one
    // transaction. On upsert conflict, created_by is preserved; the service
    // still ensures a group/creator row exists for the actual created_by.
    let group = state.group_service.create(&owned).await?;
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
    // #370 / #443: ownership short-circuit for the group owner; else event-
    // scoped `group.edit` (event creator/editor / moderator *.any / admin) or
    // group-scoped `group.edit` (group creator role / group editor).
    if group_creator_id != Some(user.id) {
        let event_ok = state
            .rbac_service
            .check(&user, &Scope::Event(event_id), Permission::GroupEdit)
            .await
            .is_ok();
        if !event_ok {
            state
                .rbac_service
                .check(&user, &Scope::Group(group.id), Permission::GroupEdit)
                .await?;
        }
    }

    let updated = state
        .groups
        .update(payload)
        .await?
        .ok_or_else(|| AppError::not_found("Group disappeared mid-update"))?;
    Ok(Json(updated))
}

/// Resolve the caller and require `group.member.manage` on the group (#443).
/// Confirms the group exists (404) **before** the RBAC check.
async fn require_group_member_manage(
    state: &AppState,
    caller_user_id: Option<i32>,
    event_id: i32,
    group_name: &str,
) -> Result<MerchandiseGroup, AppError> {
    let uid =
        caller_user_id.ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify_active(uid).await?;
    let group = state
        .groups
        .get(event_id, group_name)
        .await?
        .ok_or_else(|| AppError::not_found("Group not found"))?;
    state
        .rbac_service
        .check(
            &user,
            &Scope::Group(group.id),
            Permission::GroupMemberManage,
        )
        .await?;
    Ok(group)
}

/// Assign the `group/editor` role (`POST …/groups/:name/members/:target_id`).
/// Guarded by `group.member.manage` + admin bypass. Idempotent (#443).
pub async fn assign_group_member(
    State(state): State<AppState>,
    Path((event_id, group_name, target_id)): Path<(i32, String, i32)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    let group = require_group_member_manage(&state, query.user_id, event_id, &group_name).await?;
    // Target must exist (404) — checked after the RBAC guard so an
    // unauthorized caller cannot probe user ids.
    state
        .users
        .get_by_id(target_id)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;
    state.rbac.assign_group_editor(target_id, group.id).await?;
    Ok(StatusCode::OK)
}

/// Revoke the `group/editor` role (`DELETE …/groups/:name/members/:target_id`).
/// Never removes the group `creator` role (#443).
pub async fn revoke_group_member(
    State(state): State<AppState>,
    Path((event_id, group_name, target_id)): Path<(i32, String, i32)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    let group = require_group_member_manage(&state, query.user_id, event_id, &group_name).await?;
    state.rbac.revoke_group_editor(target_id, group.id).await?;
    Ok(StatusCode::OK)
}

/// List group-scoped role assignments (`GET …/groups/:name/members`) (#443).
pub async fn list_group_members(
    State(state): State<AppState>,
    Path((event_id, group_name)): Path<(i32, String)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<Json<ListGroupMembersResponse>, AppError> {
    let group = require_group_member_manage(&state, query.user_id, event_id, &group_name).await?;
    let members = state.rbac.list_group_members(group.id).await?;
    Ok(Json(ListGroupMembersResponse { members }))
}

/// Self-service group creator transfer
/// (`PUT /events/:id/groups/:name/creator`). Callable only by the **current**
/// group creator (`created_by`). Editors with `group.member.manage` cannot
/// transfer. Global staff use the admin path (`group.creator.transfer`, #432).
/// Does **not** auto-promote the previous creator to `editor` (#443).
pub async fn self_transfer_group_creator(
    State(state): State<AppState>,
    Path((event_id, group_name)): Path<(i32, String)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
    Json(payload): Json<TransferCreatorRequest>,
) -> Result<StatusCode, AppError> {
    let uid = query
        .user_id
        .ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify_active(uid).await?;

    let previous = state
        .groups
        .get_creator(event_id, &group_name)
        .await?
        .ok_or_else(|| AppError::not_found("Group not found"))?;

    if previous != Some(user.id) {
        return Err(AppError::forbidden(
            "Only the group creator can transfer ownership",
        ));
    }

    if previous == Some(payload.new_creator_id) {
        return Err(AppError::bad_request("User is already the group creator"));
    }

    let target = state
        .users
        .get_by_id(payload.new_creator_id)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;
    if target.is_banned.unwrap_or(false) {
        return Err(AppError::bad_request("Target user is banned"));
    }

    // Ownership is re-checked under `SELECT … FOR UPDATE` inside the service
    // so concurrent transfers cannot leave multiple live `group/creator` rows.
    state
        .group_service
        .transfer_creator(
            event_id,
            &group_name,
            payload.new_creator_id,
            TransferCaller::SelfService {
                expected_creator_id: user.id,
            },
        )
        .await?;
    Ok(StatusCode::OK)
}

/// Report the caller's effective standing on a single item group
/// (`GET /events/:id/groups/:name/my-role`). Any active caller may read their
/// own role (no 403 for a plain viewer) so the frontend can gate Manage Group
/// Members without a 403 on open (#443).
pub async fn get_my_group_role(
    State(state): State<AppState>,
    Path((event_id, group_name)): Path<(i32, String)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<Json<MyGroupRoleResponse>, AppError> {
    let uid = query
        .user_id
        .ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify_active(uid).await?;
    let group = state
        .groups
        .get(event_id, &group_name)
        .await?
        .ok_or_else(|| AppError::not_found("Group not found"))?;

    let role = state
        .rbac
        .group_role_name(user.id, group.id)
        .await?
        .unwrap_or_else(|| "none".to_string());
    let global_override = matches!(
        state.rbac.global_role_name(user.id).await?,
        Some(ref g) if g == "admin" || g == "moderator"
    );

    // Edit: ownership, event-scoped group.edit, or group-scoped group.edit.
    let can_edit_group = group.created_by == Some(user.id)
        || state
            .rbac_service
            .check(&user, &Scope::Event(event_id), Permission::GroupEdit)
            .await
            .is_ok()
        || state
            .rbac_service
            .check(&user, &Scope::Group(group.id), Permission::GroupEdit)
            .await
            .is_ok();

    let can_manage_editors = state
        .rbac_service
        .check(
            &user,
            &Scope::Group(group.id),
            Permission::GroupMemberManage,
        )
        .await
        .is_ok();
    // Self-service transfer is ownership-based, not permission-based.
    let can_transfer_creator = group.created_by == Some(user.id);

    Ok(Json(MyGroupRoleResponse {
        role,
        global_override,
        can_edit_group,
        can_manage_editors,
        can_transfer_creator,
    }))
}
