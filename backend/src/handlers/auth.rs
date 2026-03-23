use crate::generated::ymatch::*;
use axum::{extract::Path, extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

fn user_from_row(row: &sqlx::postgres::PgRow) -> User {
    User {
        id: row.get("id"),
        username: row.get("username"),
        uuid: row.get("uuid"),
        device_token: row.get("device_token"),
        created_at: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
        role: Some(row.get("role")),
        is_banned: Some(row.get("is_banned")),
        ban_reason: row.get("ban_reason"),
        banned_until: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("banned_until")
            .map(|dt| dt.to_rfc3339()),
    }
}

const USER_COLUMNS: &str =
    "id, username, uuid, device_token, created_at, role, is_banned, ban_reason, banned_until";

pub async fn guest_login(
    State(pool): State<PgPool>,
    Json(payload): Json<GuestLoginRequest>,
) -> Result<Json<User>, (StatusCode, String)> {
    let row = sqlx::query(&format!(
        "SELECT {} FROM users WHERE uuid = $1",
        USER_COLUMNS
    ))
    .bind(&payload.uuid)
    .fetch_optional(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    if let Some(row) = row {
        let is_banned: bool = row.get("is_banned");
        if is_banned {
            return Err((StatusCode::FORBIDDEN, "User is banned".to_string()));
        }

        if let Some(ref token) = payload.device_token {
            sqlx::query("UPDATE users SET device_token = $1 WHERE id = $2")
                .bind(token)
                .bind(row.get::<i32, _>("id"))
                .execute(&pool)
                .await
                .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        }

        let mut user = user_from_row(&row);
        if payload.device_token.is_some() {
            user.device_token = payload.device_token;
        }
        return Ok(Json(user));
    }

    let suffix_len = std::cmp::min(8, payload.uuid.len());
    let uuid_suffix = &payload.uuid[payload.uuid.len() - suffix_len..];
    let unique_id = uuid::Uuid::new_v4().to_string()[..6].to_string();
    let new_username = format!("Guest_{}_{}", uuid_suffix, unique_id);
    let row = sqlx::query(&format!(
        "INSERT INTO users (username, uuid, device_token) VALUES ($1, $2, $3) RETURNING {}",
        USER_COLUMNS
    ))
    .bind(new_username)
    .bind(&payload.uuid)
    .bind(&payload.device_token)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(user_from_row(&row)))
}

pub async fn login(
    State(pool): State<PgPool>,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<User>, (StatusCode, String)> {
    let row = sqlx::query(&format!(
        "SELECT {}, password_hash FROM users WHERE username = $1",
        USER_COLUMNS
    ))
    .bind(&payload.username)
    .fetch_optional(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    if let Some(row) = row {
        let password_hash: Option<String> = row.get("password_hash");
        if password_hash.as_deref() == Some(&payload.password) {
            let is_banned: bool = row.get("is_banned");
            if is_banned {
                return Err((StatusCode::FORBIDDEN, "User is banned".to_string()));
            }
            Ok(Json(user_from_row(&row)))
        } else {
            Err((StatusCode::UNAUTHORIZED, "Invalid credentials".to_string()))
        }
    } else {
        Err((StatusCode::UNAUTHORIZED, "Invalid credentials".to_string()))
    }
}

pub async fn signup(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<Json<User>, (StatusCode, String)> {
    let row = sqlx::query(&format!(
        "INSERT INTO users (username, password_hash, device_token) VALUES ($1, $2, $3) RETURNING {}",
        USER_COLUMNS
    ))
    .bind(&payload.username)
    .bind(&payload.password)
    .bind(&payload.device_token)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(user_from_row(&row)))
}

pub async fn list_users(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<User>>, (StatusCode, String)> {
    let rows = sqlx::query(&format!("SELECT {} FROM users", USER_COLUMNS))
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let users = rows.iter().map(user_from_row).collect();
    Ok(Json(users))
}

#[derive(serde::Deserialize)]
pub struct UpdateUsernameRequest {
    pub user_id: i32,
    pub username: String,
}

pub async fn update_username(
    State(pool): State<PgPool>,
    Path(id): Path<i32>,
    Json(payload): Json<UpdateUsernameRequest>,
) -> Result<Json<User>, (StatusCode, String)> {
    if payload.user_id != id {
        return Err((StatusCode::FORBIDDEN, "You can only update your own username".to_string()));
    }
    let username = payload.username.trim().to_string();
    if username.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "Username cannot be empty".to_string()));
    }
    let row = sqlx::query(&format!(
        "UPDATE users SET username = $1 WHERE id = $2 RETURNING {}",
        USER_COLUMNS
    ))
    .bind(&username)
    .bind(id)
    .fetch_optional(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
    .ok_or_else(|| (StatusCode::NOT_FOUND, "User not found".to_string()))?;

    Ok(Json(user_from_row(&row)))
}
