//! Shared handler request DTOs and authz entry helpers used by more than one
//! handler module.
//!
//! Keep types here when both public and admin (or other) routes need the same
//! query/body shape so public handlers do not depend on the admin module (#447).
//! Shared RBAC gates live here so merch/matches/images can require privileges
//! without importing the admin module (#491).

use crate::error::AppError;
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
