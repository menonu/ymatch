use axum::http::StatusCode;
use sqlx::{PgPool, Row};

pub struct VerifiedUser {
    pub id: i32,
    pub role: String,
    pub is_banned: bool,
}

/// Fetch a user and verify they exist and are not banned.
pub async fn get_verified_user(
    pool: &PgPool,
    user_id: i32,
) -> Result<VerifiedUser, (StatusCode, String)> {
    let row = sqlx::query("SELECT id, role, is_banned, banned_until FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let row = row.ok_or((StatusCode::NOT_FOUND, "User not found".to_string()))?;

    let is_banned: bool = row.get("is_banned");
    let banned_until: Option<chrono::DateTime<chrono::Utc>> = row.get("banned_until");

    // Check if temporary ban has expired
    let effectively_banned = if is_banned {
        match banned_until {
            Some(until) => chrono::Utc::now() < until,
            None => true, // permanent ban
        }
    } else {
        false
    };

    Ok(VerifiedUser {
        id: row.get("id"),
        role: row.get("role"),
        is_banned: effectively_banned,
    })
}

/// Require that the user is not banned. Returns error if banned.
pub fn require_not_banned(user: &VerifiedUser) -> Result<(), (StatusCode, String)> {
    if user.is_banned {
        return Err((StatusCode::FORBIDDEN, "User is banned".to_string()));
    }
    Ok(())
}

/// Check if the user has one of the required roles.
pub fn check_role(user: &VerifiedUser, allowed_roles: &[&str]) -> Result<(), (StatusCode, String)> {
    if allowed_roles.contains(&user.role.as_str()) {
        Ok(())
    } else {
        Err((
            StatusCode::FORBIDDEN,
            format!("Requires role: {}", allowed_roles.join(" or ")),
        ))
    }
}

/// Check if user is the owner OR has an elevated role.
pub fn check_ownership_or_role(
    user: &VerifiedUser,
    owner_id: i32,
    elevated_roles: &[&str],
) -> Result<(), (StatusCode, String)> {
    if user.id == owner_id {
        return Ok(());
    }
    check_role(user, elevated_roles)
}
