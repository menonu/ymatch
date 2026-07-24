//! Shared handler request DTOs and authz entry helpers used by more than one
//! handler module.
//!
//! Keep types here when both public and admin (or other) routes need the same
//! query/body shape so public handlers do not depend on the admin module (#447).
//! Shared RBAC gates live here so merch/matches/images can require privileges
//! without importing the admin module (#491), and so event/group member-manage
//! gates share one shape (#497 finding 5).

use crate::error::AppError;
use crate::generated::ymatch::MerchandiseGroup;
use crate::repositories::user::VerifiedUser;
use crate::routes::AppState;
use crate::services::rbac::{Permission, Scope};

/// Query wrapper for the ubiquitous `?user_id=` caller identity param.
#[derive(serde::Deserialize)]
pub struct UserIdQuery {
    pub user_id: Option<i32>,
}

/// Body for event/group creator-transfer endpoints (admin #432 and self-service #442).
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferCreatorRequest {
    pub new_creator_id: i32,
}

/// Resolve `?user_id=`, require an active (exists + not banned) user, then
/// require `permission` in `scope`. Shared shape for global/event/group gates
/// (#491 / #497).
async fn require_active_permission(
    state: &AppState,
    query_user_id: Option<i32>,
    scope: &Scope,
    permission: Permission,
) -> Result<VerifiedUser, AppError> {
    let user = require_active_query_user(state, query_user_id).await?;
    state.rbac_service.check(&user, scope, permission).await?;
    Ok(user)
}

/// Resolve the caller from `user_id` query param, reject banned users, and
/// require `permission` in the **global** scope (ADR 0004 §3).
///
/// Used by admin list/mutation endpoints and other global-privileged paths
/// (#491 gates admin catalog lists). Admin superuser bypass is inside
/// [`crate::services::rbac::RbacService::check`].
pub async fn require_global(
    state: &AppState,
    query_user_id: Option<i32>,
    permission: Permission,
) -> Result<VerifiedUser, AppError> {
    require_active_permission(state, query_user_id, &Scope::Global, permission).await
}

/// Resolve the caller from `user_id` query param and require an active
/// (exists + not banned) user. Does not check RBAC — for surfaces open to any
/// logged-in actor after identity binding (#491 images, lean user directory).
pub async fn require_active_query_user(
    state: &AppState,
    query_user_id: Option<i32>,
) -> Result<VerifiedUser, AppError> {
    let uid =
        query_user_id.ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    state.policy.verify_active(uid).await
}

/// Resolve the caller from `?user_id=` and require `event.member.manage` on
/// `event_id` (ADR 0004 §5 / #442): the event `creator` or `editor`, or the
/// admin superuser bypass. There is deliberately no `*.any` override for this
/// permission, so a global moderator cannot use the public members API (they
/// use the admin path with `event.member.manage.any` instead, #432).
///
/// The event's existence is confirmed (404) **before** the RBAC check, so a
/// missing event is reported as 404 rather than leaked as a 403 to a caller
/// who lacks the event role — matches `update_event`'s convention.
pub async fn require_event_member_manage(
    state: &AppState,
    caller_user_id: Option<i32>,
    event_id: i32,
) -> Result<VerifiedUser, AppError> {
    let user = require_active_query_user(state, caller_user_id).await?;
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    state
        .rbac_service
        .check(
            &user,
            &Scope::Event(event_id),
            Permission::EventMemberManage,
        )
        .await?;
    Ok(user)
}

/// Resolve the caller and require `group.member.manage` on the group (#443).
/// Confirms the group exists (404) **before** the RBAC check.
pub async fn require_group_member_manage(
    state: &AppState,
    caller_user_id: Option<i32>,
    event_id: i32,
    group_name: &str,
) -> Result<MerchandiseGroup, AppError> {
    let user = require_active_query_user(state, caller_user_id).await?;
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
