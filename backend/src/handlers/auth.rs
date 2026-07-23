use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::handlers::common::UserIdQuery;
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
///   `uuid` (restore key) on this list — use `GET /admin/users/:id` for
///   detail inspection.
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
    let is_staff = state
        .rbac_service
        .check(&caller, &Scope::Global, Permission::UserRead)
        .await
        .is_ok();

    if is_staff {
        let staff_view = all
            .into_iter()
            .map(|mut u| {
                // Strip secrets even for staff list; detail endpoint retains them.
                u.device_token = None;
                u.uuid = None;
                u
            })
            .collect();
        return Ok(Json(staff_view));
    }

    let lean = all
        .into_iter()
        .map(|u| User {
            id: u.id,
            username: u.username,
            uuid: None,
            device_token: None,
            created_at: None,
            role: None,
            is_banned: None,
            ban_reason: None,
            banned_until: None,
        })
        .collect();
    Ok(Json(lean))
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
    Ok(Json(user))
}
