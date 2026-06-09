use crate::generated::ymatch::*;
use crate::handlers::permissions;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use sqlx::{PgPool, Row};

const GROUP_COLUMNS: &str =
    "id, event_id, group_name, description, created_by, created_at, updated_at";

fn group_from_row(row: &sqlx::postgres::PgRow) -> MerchandiseGroup {
    let description: String = row.get("description");
    MerchandiseGroup {
        id: row.get("id"),
        event_id: row.get("event_id"),
        group_name: row.get("group_name"),
        description: if description.is_empty() {
            None
        } else {
            Some(description)
        },
        created_by: row.get("created_by"),
        created_at: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
        updated_at: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("updated_at")
            .map(|dt| dt.to_rfc3339()),
    }
}

fn ensure_group_name(name: &str) -> Result<&str, (StatusCode, String)> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        Err((
            StatusCode::BAD_REQUEST,
            "group_name is required".to_string(),
        ))
    } else {
        Ok(trimmed)
    }
}

pub async fn list_event_groups(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
) -> Result<Json<ListGroupsResponse>, (StatusCode, String)> {
    let rows = sqlx::query(&format!(
        "SELECT {} FROM merchandise_groups WHERE event_id = $1 ORDER BY group_name ASC",
        GROUP_COLUMNS
    ))
    .bind(event_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let groups: Vec<MerchandiseGroup> = rows.iter().map(group_from_row).collect();
    Ok(Json(ListGroupsResponse { groups }))
}

pub async fn create_event_group(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateGroupRequest>,
) -> Result<Json<MerchandiseGroup>, (StatusCode, String)> {
    if payload.event_id != event_id {
        return Err((
            StatusCode::BAD_REQUEST,
            "event_id in path and body must match".to_string(),
        ));
    }

    let group_name = ensure_group_name(&payload.group_name)?.to_string();
    let user = permissions::get_verified_user(&pool, payload.user_id).await?;
    permissions::require_not_banned(&user)?;

    // Verify event exists
    let event_exists: Option<i32> = sqlx::query_scalar("SELECT id FROM events WHERE id = $1")
        .bind(event_id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    if event_exists.is_none() {
        return Err((StatusCode::NOT_FOUND, "Event not found".to_string()));
    }

    let description = payload.description.unwrap_or_default();

    let row = sqlx::query(&format!(
        r#"INSERT INTO merchandise_groups (event_id, group_name, description, created_by)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (event_id, group_name) DO UPDATE
             SET description = EXCLUDED.description,
                 updated_at = NOW()
           RETURNING {}"#,
        GROUP_COLUMNS
    ))
    .bind(event_id)
    .bind(&group_name)
    .bind(&description)
    .bind(payload.user_id)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(group_from_row(&row)))
}

pub async fn update_event_group(
    State(pool): State<PgPool>,
    Path((event_id, group_name)): Path<(i32, String)>,
    Json(payload): Json<UpdateGroupRequest>,
) -> Result<Json<MerchandiseGroup>, (StatusCode, String)> {
    if payload.event_id != event_id {
        return Err((
            StatusCode::BAD_REQUEST,
            "event_id in path and body must match".to_string(),
        ));
    }
    let path_group = ensure_group_name(&group_name)?.to_string();
    let body_group = ensure_group_name(&payload.group_name)?.to_string();
    if path_group != body_group {
        return Err((
            StatusCode::BAD_REQUEST,
            "group_name in path and body must match".to_string(),
        ));
    }

    let user = permissions::get_verified_user(&pool, payload.user_id).await?;
    permissions::require_not_banned(&user)?;

    let row = sqlx::query(&format!(
        "SELECT {} FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
        GROUP_COLUMNS
    ))
    .bind(event_id)
    .bind(&path_group)
    .fetch_optional(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let row = row.ok_or((
        StatusCode::NOT_FOUND,
        "Group not found. Create it first via POST /groups".to_string(),
    ))?;

    let created_by: Option<i32> = row.get("created_by");
    permissions::check_ownership_or_role(&user, created_by.unwrap_or(-1), &["admin", "moderator"])?;

    if payload.description.is_none() {
        // Nothing to update
        return Ok(Json(group_from_row(&row)));
    }

    let description = payload.description.unwrap_or_default();

    let updated = sqlx::query(&format!(
        r#"UPDATE merchandise_groups
           SET description = $1, updated_at = NOW()
           WHERE event_id = $2 AND group_name = $3
           RETURNING {}"#,
        GROUP_COLUMNS
    ))
    .bind(&description)
    .bind(event_id)
    .bind(&path_group)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(group_from_row(&updated)))
}
