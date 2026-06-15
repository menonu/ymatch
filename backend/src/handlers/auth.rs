use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::repositories::user::UsernameLookup;
use crate::routes::AppState;
use axum::{Json, extract::Path, extract::State};

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

pub async fn list_users(State(state): State<AppState>) -> Result<Json<Vec<User>>, AppError> {
    let all = state.users.list_all().await?;
    Ok(Json(all))
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateUsernameRequest {
    pub user_id: i32,
    pub username: String,
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
