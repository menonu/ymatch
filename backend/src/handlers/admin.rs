use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::repositories::user::VerifiedUser;
use crate::routes::AppState;
use crate::services::permissions::PermissionPolicy;
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

/// Resolve the caller from the `user_id` query param and confirm they are an
/// active (non-banned) `admin` or `moderator`. Used for the admin endpoints
/// whose permission the ADR 0004 matrix does not model as an RBAC permission
/// (today: only `delete_match`, which has no `match.*` permission in the
/// catalog). RBAC-gated admin endpoints use [`require_global`] instead.
async fn require_admin_or_mod(
    policy: &PermissionPolicy,
    query_user_id: Option<i32>,
) -> Result<VerifiedUser, AppError> {
    let uid =
        query_user_id.ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = policy.verify(uid).await?;
    policy.require_not_banned(&user)?;
    policy.require_role(&user, &["admin", "moderator"])?;
    Ok(user)
}

/// Resolve the caller from the `user_id` query param and require they hold
/// `permission` in the global scope (ADR 0004 §3). This is the RBAC entry
/// point for the admin endpoints whose permission is in the catalog:
/// `event.delete.any`, `merch.delete.any`, `user.ban`, `user.unban`,
/// `user.role.manage`. The admin superuser bypass is handled inside
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
    require_global(&state, query.user_id, Permission::EventDeleteAny).await?;
    state.events.delete(id).await?;
    Ok(StatusCode::OK)
}

pub async fn delete_merch(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::MerchDeleteAny).await?;

    // The merch_id is also the only thing we have. The repository needs
    // (event_id, merch_id) to construct its SQL, so we look up the event
    // id from the merch row first. This is the one place that bridges
    // the old admin path and the new repository; once MerchandiseRepository
    // grows a `delete_by_id` method this lookup can move there.
    let event_id: Option<i32> =
        sqlx::query_scalar("SELECT event_id FROM merchandise WHERE id = $1")
            .bind(id)
            .fetch_optional(&state.pool)
            .await?;

    let Some(event_id) = event_id else {
        return Ok(StatusCode::OK);
    };

    state.merch.delete_merch(event_id, id).await?;
    Ok(StatusCode::OK)
}

pub async fn delete_match(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
) -> Result<StatusCode, AppError> {
    // No `match.*` permission in the ADR 0004 catalog; match deletion stays
    // an admin/moderator moderation action via the role-based check.
    require_admin_or_mod(&state.policy, query.user_id).await?;

    // The matches table is owned by `MatchRepository` in Phase 4, but
    // the admin path here is the only consumer of a "delete" method on
    // matches. We add it via a direct SQL because the trade lifecycle
    // service has no public delete endpoint; this is a 1-line query.
    sqlx::query("DELETE FROM matches WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await?;
    Ok(StatusCode::OK)
}

pub async fn ban_user(
    State(state): State<AppState>,
    Path(target_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
    Json(payload): Json<BanUserRequest>,
) -> Result<StatusCode, AppError> {
    require_global(&state, query.user_id, Permission::UserBan).await?;

    let banned_until = payload
        .banned_until
        .as_deref()
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        .map(|dt| dt.with_timezone(&chrono::Utc));

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
) -> Result<Json<User>, AppError> {
    let user = state
        .users
        .get_by_id(target_id)
        .await?
        .ok_or_else(|| AppError::not_found("User not found"))?;
    Ok(Json(user))
}
