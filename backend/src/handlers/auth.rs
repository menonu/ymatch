use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::handlers::common::UserIdQuery;
use crate::handlers::mappers::{credential_free_user_view, directory_user_view};
use crate::repositories::user::UsernameLookup;
use crate::routes::AppState;
use crate::services::rbac::{Permission, Scope};
use axum::{Json, extract::Path, extract::Query, extract::State};

pub async fn guest_login(
    State(state): State<AppState>,
    Json(payload): Json<GuestLoginRequest>,
) -> Result<Json<User>, AppError> {
    if let Some(user) = state.users.get_by_uuid(&payload.uuid).await? {
        if user.is_banned.unwrap_or(false) {
            return Err(AppError::forbidden("User is banned"));
        }

        if let Some(ref token) = payload.device_token {
            state
                .users
                .update_device_token(user.id, Some(token))
                .await?;
        }

        let mut user = user;
        if payload.device_token.is_some() {
            user.device_token = payload.device_token;
        }
        return Ok(Json(user));
    }

    // The uuid is the account's only credential: a new guest must present a
    // random (v4) UUID. Existing accounts above keep logging in as-is.
    if !is_canonical_uuid_v4(&payload.uuid) {
        return Err(AppError::bad_request("uuid must be a UUID v4"));
    }

    let suffix_len = std::cmp::min(8, payload.uuid.len());
    let uuid_suffix = &payload.uuid[payload.uuid.len() - suffix_len..];
    let unique_id = uuid::Uuid::new_v4().to_string()[..6].to_string();
    let new_username = format!("Guest_{}_{}", uuid_suffix, unique_id);
    let user = state
        .users
        .create_guest(
            &new_username,
            &payload.uuid,
            payload.device_token.as_deref(),
        )
        .await?;
    Ok(Json(user))
}

/// True for a hyphenated (8-4-4-4-12) RFC 4122 version-4 UUID, any case.
fn is_canonical_uuid_v4(s: &str) -> bool {
    s.len() == 36
        && uuid::Uuid::try_parse(s).is_ok_and(|u| {
            u.get_version() == Some(uuid::Version::Random)
                && u.get_variant() == uuid::Variant::RFC4122
        })
}

pub async fn login(
    State(state): State<AppState>,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<User>, AppError> {
    let (user, password_hash) = state
        .users
        .get_by_username(&payload.username, UsernameLookup::WithPassword)
        .await?
        .ok_or_else(|| AppError::unauthorized("Invalid credentials"))?;

    if password_hash.as_deref() != Some(&payload.password) {
        return Err(AppError::unauthorized("Invalid credentials"));
    }

    if user.is_banned.unwrap_or(false) {
        return Err(AppError::forbidden("User is banned"));
    }

    Ok(Json(user))
}

pub async fn signup(
    State(state): State<AppState>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<Json<User>, AppError> {
    let user = state
        .users
        .create_with_password(
            &payload.username,
            &payload.password,
            payload.device_token.as_deref(),
        )
        .await?;
    Ok(Json(user))
}

/// List users for member pickers and the admin users tab (#491).
///
/// Requires an active caller via `?user_id=`.
/// - Callers with global `user.read` (moderator/admin) get the full admin
///   directory fields (role, ban state) but **never** `device_token` or
///   `uuid` (restore key) on this list. `GET /admin/users/:id` keeps
///   `device_token` for detail inspection; `uuid` is returned only by the
///   auth endpoints.
/// - Other active users get a **lean directory** (`id` + `username` only)
///   for self-service member pickers.
pub async fn list_users(
    State(state): State<AppState>,
    Query(query): Query<UserIdQuery>,
) -> Result<Json<Vec<User>>, AppError> {
    let uid = query
        .user_id
        .ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let caller = state.policy.verify_active(uid).await?;

    let all = state.users.list_all().await?;
    // #491 review: do not treat Internal as "not staff" via `.is_ok()` —
    // Forbidden means lean directory; other errors must propagate.
    let is_staff = match state
        .rbac_service
        .check(&caller, &Scope::Global, Permission::UserRead)
        .await
    {
        Ok(()) => true,
        Err(AppError::Forbidden(_)) => false,
        Err(e) => return Err(e),
    };

    if is_staff {
        // Even staff lists carry no secrets; the detail endpoint keeps
        // `device_token` (see `staff_user_view`).
        let staff_view = all.into_iter().map(credential_free_user_view).collect();
        return Ok(Json(staff_view));
    }

    Ok(Json(all.into_iter().map(directory_user_view).collect()))
}

pub async fn update_username(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    Json(payload): Json<UpdateUsernameRequest>,
) -> Result<Json<User>, AppError> {
    if payload.user_id != id {
        return Err(AppError::forbidden("You can only update your own username"));
    }
    let username = payload.username.trim().to_string();
    if username.is_empty() {
        return Err(AppError::bad_request("Username cannot be empty"));
    }
    let user = state
        .users
        .update_username(id, &username)
        .await?
        .ok_or_else(|| AppError::not_found("User not found"))?;
    Ok(Json(credential_free_user_view(user)))
}

#[cfg(test)]
mod tests {
    use super::is_canonical_uuid_v4;

    #[test]
    fn accepts_hyphenated_v4_in_any_case() {
        assert!(is_canonical_uuid_v4("550e8400-e29b-41d4-a716-446655440000"));
        assert!(is_canonical_uuid_v4("550E8400-E29B-41D4-A716-446655440000"));
    }

    #[test]
    fn rejects_other_versions_variants_and_forms() {
        for bad in [
            "",
            "test-uuid-1234",
            // version 1
            "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
            // v4 nibble but non-RFC4122 variant
            "550e8400-e29b-41d4-c716-446655440000",
            // simple / braced / urn forms of a v4
            "550e8400e29b41d4a716446655440000",
            "{550e8400-e29b-41d4-a716-446655440000}",
            "urn:uuid:550e8400-e29b-41d4-a716-446655440000",
            // nil
            "00000000-0000-0000-0000-000000000000",
        ] {
            assert!(!is_canonical_uuid_v4(bad), "{bad}");
        }
    }
}
