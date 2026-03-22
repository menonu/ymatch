use crate::generated::ymatch::*;
use crate::handlers::permissions;
use axum::{extract::Path, extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

#[derive(serde::Deserialize)]
pub struct AdminQuery {
    pub user_id: Option<i32>,
}

async fn require_admin_or_mod(
    pool: &PgPool,
    query_user_id: Option<i32>,
) -> Result<permissions::VerifiedUser, (StatusCode, String)> {
    let uid = query_user_id.ok_or((
        StatusCode::BAD_REQUEST,
        "user_id query parameter required".to_string(),
    ))?;
    let user = permissions::get_verified_user(pool, uid).await?;
    permissions::require_not_banned(&user)?;
    permissions::check_role(&user, &["admin", "moderator"])?;
    Ok(user)
}

pub async fn delete_event(
    State(pool): State<PgPool>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
) -> Result<StatusCode, (StatusCode, String)> {
    require_admin_or_mod(&pool, query.user_id).await?;

    sqlx::query("DELETE FROM events WHERE id = $1")
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    Ok(StatusCode::OK)
}

pub async fn delete_merch(
    State(pool): State<PgPool>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
) -> Result<StatusCode, (StatusCode, String)> {
    require_admin_or_mod(&pool, query.user_id).await?;

    // Soft-delete if inventory exists
    let has_inventory = sqlx::query(
        "SELECT EXISTS(SELECT 1 FROM inventory WHERE merch_id = $1 AND quantity > 0) as has_inv",
    )
    .bind(id)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let has_inv: bool = has_inventory.get("has_inv");

    if has_inv {
        sqlx::query(
            "UPDATE merchandise SET is_deleted = true, trade_enabled = false WHERE id = $1",
        )
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    } else {
        sqlx::query("DELETE FROM merchandise WHERE id = $1")
            .bind(id)
            .execute(&pool)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    Ok(StatusCode::OK)
}

pub async fn delete_match(
    State(pool): State<PgPool>,
    Path(id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
) -> Result<StatusCode, (StatusCode, String)> {
    require_admin_or_mod(&pool, query.user_id).await?;

    sqlx::query("DELETE FROM matches WHERE id = $1")
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    Ok(StatusCode::OK)
}

pub async fn ban_user(
    State(pool): State<PgPool>,
    Path(target_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
    Json(payload): Json<BanUserRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    require_admin_or_mod(&pool, query.user_id).await?;

    let banned_until = payload
        .banned_until
        .as_deref()
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        .map(|dt| dt.with_timezone(&chrono::Utc));

    sqlx::query(
        "UPDATE users SET is_banned = true, ban_reason = $1, banned_until = $2 WHERE id = $3",
    )
    .bind(&payload.reason)
    .bind(banned_until)
    .bind(target_id)
    .execute(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

pub async fn unban_user(
    State(pool): State<PgPool>,
    Path(target_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
) -> Result<StatusCode, (StatusCode, String)> {
    require_admin_or_mod(&pool, query.user_id).await?;

    sqlx::query(
        "UPDATE users SET is_banned = false, ban_reason = NULL, banned_until = NULL WHERE id = $1",
    )
    .bind(target_id)
    .execute(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

pub async fn update_user_role(
    State(pool): State<PgPool>,
    Path(target_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<AdminQuery>,
    Json(payload): Json<UpdateUserRoleRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let uid = query.user_id.ok_or((
        StatusCode::BAD_REQUEST,
        "user_id query parameter required".to_string(),
    ))?;
    let user = permissions::get_verified_user(&pool, uid).await?;
    permissions::require_not_banned(&user)?;
    // Only admin can change roles
    permissions::check_role(&user, &["admin"])?;

    let valid_roles = ["user", "moderator", "admin"];
    if !valid_roles.contains(&payload.role.as_str()) {
        return Err((
            StatusCode::BAD_REQUEST,
            format!("Invalid role. Must be one of: {}", valid_roles.join(", ")),
        ));
    }

    sqlx::query("UPDATE users SET role = $1 WHERE id = $2")
        .bind(&payload.role)
        .bind(target_id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

pub async fn get_user_details(
    State(pool): State<PgPool>,
    Path(target_id): Path<i32>,
) -> Result<Json<User>, (StatusCode, String)> {
    let row = sqlx::query(
        "SELECT id, username, uuid, device_token, created_at, role, is_banned, ban_reason, banned_until FROM users WHERE id = $1",
    )
    .bind(target_id)
    .fetch_optional(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let row = row.ok_or((StatusCode::NOT_FOUND, "User not found".to_string()))?;

    Ok(Json(User {
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
    }))
}
