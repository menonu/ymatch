use crate::generated::ymatch::*;
use axum::{extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

pub async fn guest_login(
    State(pool): State<PgPool>,
    Json(payload): Json<GuestLoginRequest>,
) -> Result<Json<User>, (StatusCode, String)> {
    let row = sqlx::query(
        "SELECT id, username, uuid, device_token, created_at FROM users WHERE uuid = $1",
    )
    .bind(&payload.uuid)
    .fetch_optional(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    if let Some(row) = row {
        let mut device_token: Option<String> = row.get("device_token");
        if let Some(ref token) = payload.device_token {
            sqlx::query("UPDATE users SET device_token = $1 WHERE id = $2")
                .bind(token)
                .bind(row.get::<i32, _>("id"))
                .execute(&pool)
                .await
                .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
            device_token = Some(token.clone());
        }

        return Ok(Json(User {
            id: row.get("id"),
            username: row.get("username"),
            uuid: row.get("uuid"),
            device_token,
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
        }));
    }

    let suffix_len = std::cmp::min(8, payload.uuid.len());
    let uuid_suffix = &payload.uuid[payload.uuid.len() - suffix_len..];
    let unique_id = uuid::Uuid::new_v4().to_string()[..6].to_string();
    let new_username = format!("Guest_{}_{}", uuid_suffix, unique_id);
    let row = sqlx::query(
        "INSERT INTO users (username, uuid, device_token) VALUES ($1, $2, $3) RETURNING id, username, uuid, device_token, created_at"
    )
    .bind(new_username)
    .bind(&payload.uuid)
    .bind(&payload.device_token)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(User {
        id: row.get("id"),
        username: row.get("username"),
        uuid: row.get("uuid"),
        device_token: row.get("device_token"),
        created_at: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
    }))
}

pub async fn login(
    State(pool): State<PgPool>,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<User>, (StatusCode, String)> {
    let row = sqlx::query("SELECT id, username, uuid, device_token, created_at, password_hash FROM users WHERE username = $1")
        .bind(&payload.username)
        .fetch_optional(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    if let Some(row) = row {
        let password_hash: Option<String> = row.get("password_hash");
        // Simple plaintext check for MVP
        if password_hash.as_deref() == Some(&payload.password) {
            Ok(Json(User {
                id: row.get("id"),
                username: row.get("username"),
                uuid: row.get("uuid"),
                device_token: row.get("device_token"),
                created_at: row
                    .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                    .map(|dt| dt.to_rfc3339()),
            }))
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
    let row = sqlx::query(
        "INSERT INTO users (username, password_hash, device_token) VALUES ($1, $2, $3) RETURNING id, username, uuid, device_token, created_at"
    )
    .bind(&payload.username)
    .bind(&payload.password)
    .bind(&payload.device_token)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(User {
        id: row.get("id"),
        username: row.get("username"),
        uuid: row.get("uuid"),
        device_token: row.get("device_token"),
        created_at: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
    }))
}

pub async fn list_users(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<User>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, username, uuid, device_token, created_at FROM users")
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let users = rows
        .into_iter()
        .map(|row| User {
            id: row.get("id"),
            username: row.get("username"),
            uuid: row.get("uuid"),
            device_token: row.get("device_token"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
        })
        .collect();

    Ok(Json(users))
}
