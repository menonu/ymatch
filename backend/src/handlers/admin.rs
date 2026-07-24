use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::handlers::common::{TransferCreatorRequest, UserIdQuery, require_global};
use crate::routes::AppState;
use crate::services::rbac::{Permission, Scope};
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};

pub async fn delete_event(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    // #233: creators hold `event.delete` via the event-scoped `creator`
    // role; moderators/admins hold `event.delete.any`. Both satisfy
    // `Permission::EventDelete` in `Scope::Event` (see
    // `Permission::satisfying_names`). Checking only `EventDeleteAny` in
    // the global scope blocked legitimate creators.
    let uid = query
        .user_id
        .ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify(uid).await?;
    state.policy.require_not_banned(&user)?;
    // 404 before 403 so a missing event is not leaked as Forbidden.
    let _ = state
        .events
        .get_creator(id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    state
        .rbac_service
        .check(&user, &Scope::Event(id), Permission::EventDelete)
        .await?;
    state.events.delete(id).await?;
    Ok(StatusCode::OK)
}

pub async fn delete_merch(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::MerchDeleteAny).await?;
    // Idempotent: missing merch is still 200 (admin cleanup of stale ids).
    let _ = state.merch.delete_by_id(id).await?;
    Ok(StatusCode::OK)
}

pub async fn delete_match(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    // #370: match deletion is now modeled as the global `match.delete`
    // permission (granted to moderator + admin, plus the admin superuser
    // bypass), replacing the old `require_admin_or_mod` role-list check.
    require_global(&state, query.user_id, Permission::MatchDelete).await?;
    // Idempotent: missing match is still 200.
    let _ = state.matches.delete(id).await?;
    Ok(StatusCode::OK)
}

pub async fn list_groups(
    State(state): State<AppState>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<Json<Vec<crate::repositories::group::AdminGroup>>, AppError> {
    // #491: same staff gate as group delete (admin + moderator).
    require_global(&state, query.user_id, Permission::GroupDelete).await?;
    Ok(Json(state.groups.list_all_for_admin().await?))
}

pub async fn delete_group(
    State(state): State<AppState>,
    Path((event_id, group_name)): Path<(i32, String)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::GroupDelete).await?;
    if state.groups.remove_for_admin(event_id, &group_name).await? {
        Ok(StatusCode::OK)
    } else {
        Err(AppError::not_found("Group not found"))
    }
}

pub async fn ban_user(
    State(state): State<AppState>,
    Path(target_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
    Json(payload): Json<BanUserRequest>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::UserBan).await?;

    // #266: malformed banned_until must be a 400, not a silent permanent ban.
    let banned_until = match payload.banned_until.as_deref() {
        None => None,
        Some(s) => Some(
            chrono::DateTime::parse_from_rfc3339(s)
                .map_err(|e| AppError::bad_request(format!("invalid banned_until: {e}")))?
                .with_timezone(&chrono::Utc),
        ),
    };

    state
        .users
        .set_ban(target_id, true, payload.reason.as_deref(), banned_until)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;

    Ok(StatusCode::OK)
}

pub async fn unban_user(
    State(state): State<AppState>,
    Path(target_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::UserUnban).await?;

    state
        .users
        .set_ban(target_id, false, None, None)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;

    Ok(StatusCode::OK)
}

pub async fn update_user_role(
    State(state): State<AppState>,
    Path(target_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
    Json(payload): Json<UpdateUserRoleRequest>,
) -> Result<StatusCode, AppError> {
    // Only admin can change roles (ADR 0004: `user.role.manage` -> admin).
    require_global(&state, query.user_id, Permission::UserRoleManage).await?;

    let valid_roles = ["user", "moderator", "admin"];
    if !valid_roles.contains(&payload.role.as_str()) {
        return Err(AppError::bad_request(format!(
            "Invalid role. Must be one of: {}",
            valid_roles.join(", ")
        )));
    }

    state
        .users
        .set_role(target_id, &payload.role)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;

    Ok(StatusCode::OK)
}

pub async fn get_user_details(
    State(state): State<AppState>,
    Path(target_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<Json<User>, AppError> {
    // #376: the full User proto includes sensitive fields (device_token,
    // ban state, role). Gate on the global `user.read` permission so a
    // plain caller cannot enumerate device tokens by sequential id.
    require_global(&state, query.user_id, Permission::UserRead).await?;

    let user = state
        .users
        .get_by_id(target_id)
        .await?
        .ok_or_else(|| AppError::not_found("User not found"))?;
    Ok(Json(user))
}

/// Validate that `new_creator_id` exists and is not banned (#432).
async fn require_active_target_user(state: &AppState, new_creator_id: i32) -> Result<(), AppError> {
    let target = state
        .users
        .get_by_id(new_creator_id)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;
    if target.is_banned.unwrap_or(false) {
        return Err(AppError::bad_request("Target user is banned"));
    }
    Ok(())
}

/// Transfer event ownership (`PUT /api/v1/admin/events/:id/creator`).
/// Atomically updates `events.creator_id` and swaps the event-scoped
/// `creator` role. Does **not** auto-promote the previous creator to
/// `editor` (#432).
///
/// The prior creator is re-read under `SELECT … FOR UPDATE` so the role
/// swap always revokes whoever currently holds ownership, even when a
/// concurrent self-service or admin transfer races this request (#445).
pub async fn transfer_event_creator(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
    Json(payload): Json<TransferCreatorRequest>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::EventCreatorTransfer).await?;

    // 404 before probing target so a missing event is not leaked as a
    // target-user 404 to an authorized caller with a bad id.
    let previous = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;

    if previous == Some(payload.new_creator_id) {
        return Err(AppError::bad_request("User is already the event creator"));
    }

    require_active_target_user(&state, payload.new_creator_id).await?;

    // EventService owns the row lock + creator_id + role swap so concurrent
    // transfers cannot leave two live `event/creator` assignments (#445).
    state
        .event_service
        .transfer_creator(event_id, payload.new_creator_id, None)
        .await?;
    Ok(StatusCode::OK)
}

/// Transfer item-group ownership (`PUT /api/v1/admin/events/:id/groups/:name/creator`).
/// Atomically updates `merchandise_groups.created_by` and swaps the
/// group-scoped `creator` role (#432 / #443). Does **not** auto-promote the
/// previous creator to `editor`.
pub async fn transfer_group_creator(
    State(state): State<AppState>,
    Path((event_id, group_name)): Path<(i32, String)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
    Json(payload): Json<TransferCreatorRequest>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::GroupCreatorTransfer).await?;

    let current = state
        .groups
        .get_creator(event_id, &group_name)
        .await?
        .ok_or_else(|| AppError::not_found("Group not found"))?;

    if current == Some(payload.new_creator_id) {
        return Err(AppError::bad_request("User is already the group creator"));
    }

    require_active_target_user(&state, payload.new_creator_id).await?;

    let mut tx = state.pool.begin().await?;
    let locked = state
        .groups
        .lock_for_update(&mut *tx, event_id, &group_name)
        .await?
        .ok_or_else(|| AppError::not_found("Group not found"))?;
    let (group_id, locked_previous) = locked;

    if locked_previous == Some(payload.new_creator_id) {
        return Err(AppError::bad_request("User is already the group creator"));
    }

    let updated = state
        .groups
        .set_creator(&mut *tx, event_id, &group_name, payload.new_creator_id)
        .await?;
    if !updated {
        return Err(AppError::not_found("Group not found"));
    }
    state
        .rbac
        .transfer_group_creator_role(&mut tx, group_id, locked_previous, payload.new_creator_id)
        .await?;
    tx.commit().await?;
    Ok(StatusCode::OK)
}

/// List event members via the admin path
/// (`GET /api/v1/admin/events/:id/members`). Gated by
/// `event.member.manage.any` so global moderators can inspect membership
/// without holding `event.member.manage` (creator + editor; no `*.any`
/// override — moderators use this admin path, #432 / #442).
pub async fn admin_list_event_members(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<Json<ListEventMembersResponse>, AppError> {
    require_global(&state, query.user_id, Permission::EventMemberManageAny).await?;
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    let members = state.rbac.list_event_members(event_id).await?;
    Ok(Json(ListEventMembersResponse { members }))
}

/// Assign an event editor via the admin path
/// (`POST /api/v1/admin/events/:id/members/:target_id`) (#432).
pub async fn admin_assign_event_member(
    State(state): State<AppState>,
    Path((event_id, target_id)): Path<(i32, i32)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::EventMemberManageAny).await?;
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    state
        .users
        .get_by_id(target_id)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;
    state.rbac.assign_event_editor(target_id, event_id).await?;
    Ok(StatusCode::OK)
}

/// Revoke an event editor via the admin path
/// (`DELETE /api/v1/admin/events/:id/members/:target_id`). Never removes
/// the event `creator` role — the SQL filters to `editor` only (#432).
pub async fn admin_revoke_event_member(
    State(state): State<AppState>,
    Path((event_id, target_id)): Path<(i32, i32)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::EventMemberManageAny).await?;
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    state.rbac.revoke_event_editor(target_id, event_id).await?;
    Ok(StatusCode::OK)
}
