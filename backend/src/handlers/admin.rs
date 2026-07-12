use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::repositories::user::VerifiedUser;
use crate::routes::AppState;
use crate::services::rbac::{Permission, Scope};
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};

#[derive(serde::Deserialize)]
pub struct AdminQuery {
    pub user_id: Option<i32>,
}

/// Resolve the caller from the `user_id` query param and require they hold
/// `permission` in the global scope (ADR 0004 §3). This is the RBAC entry
/// point for the admin endpoints: `user.read`, `user.ban`, `user.unban`,
/// `user.role.manage`, `merch.delete.any`, `group.delete`, and
/// `match.delete`. The admin superuser bypass is handled inside
/// [`RbacService::check`].
async fn require_global(
    state: &AppState,
    query_user_id: Option<i32>,
    permission: Permission,
) -> Result<VerifiedUser, AppError> {
    let uid =
        query_user_id.ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify(uid).await?;
    state.policy.require_not_banned(&user)?;
    state
        .rbac_service
        .check(&user, &Scope::Global, permission)
        .await?;
    Ok(user)
}

pub async fn delete_event(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
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
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::MerchDeleteAny).await?;
    // Idempotent: missing merch is still 200 (admin cleanup of stale ids).
    let _ = state.merch.delete_by_id(id).await?;
    Ok(StatusCode::OK)
}

pub async fn delete_match(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
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
) -> Result<Json<Vec<crate::repositories::group::AdminGroup>>, AppError> {
    Ok(Json(state.groups.list_all_for_admin().await?))
}

pub async fn delete_group(
    State(state): State<AppState>,
    Path((event_id, group_name)): Path<(i32, String)>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
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
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
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
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
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
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
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
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
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
