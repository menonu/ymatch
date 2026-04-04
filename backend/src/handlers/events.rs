use crate::generated::ymatch::*;
use crate::handlers::permissions;
use axum::{extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

#[derive(serde::Deserialize)]
pub struct ListEventsQuery {
    pub user_id: Option<i32>,
}

#[derive(serde::Deserialize)]
pub struct RegisterViewRequest {
    pub user_id: i32,
}

#[derive(serde::Deserialize)]
pub struct ToggleFavoriteRequest {
    pub user_id: i32,
    pub is_favorite: bool,
}

#[derive(serde::Deserialize)]
pub struct ToggleFavoriteGroupRequest {
    pub user_id: i32,
    pub group_name: String,
    pub is_favorite: bool,
}

pub async fn register_event_view(
    State(pool): State<PgPool>,
    axum::extract::Path(event_id): axum::extract::Path<i32>,
    Json(payload): Json<RegisterViewRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    sqlx::query(
        "INSERT INTO event_views (event_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
    )
    .bind(event_id)
    .bind(payload.user_id)
    .execute(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

pub async fn list_events(
    State(pool): State<PgPool>,
    axum::extract::Query(query): axum::extract::Query<ListEventsQuery>,
) -> Result<Json<Vec<Event>>, (StatusCode, String)> {
    // Show published events + user's own drafts
    let rows = sqlx::query(
        r#"
        SELECT 
            e.id, 
            e.name, 
            e.creator_id, 
            e.created_at,
            e.status,
            (SELECT COUNT(*) FROM event_views v WHERE v.event_id = e.id) as unique_views,
            (
                SELECT COUNT(DISTINCT i.user_id)
                FROM inventory i
                JOIN merchandise m ON m.id = i.merch_id
                WHERE m.event_id = e.id AND i.quantity > 0
            ) as active_participants,
            EXISTS(SELECT 1 FROM event_favorites f WHERE f.event_id = e.id AND f.user_id = $1) as is_favorite,
            EXISTS(
                SELECT 1 FROM inventory i 
                JOIN merchandise m ON m.id = i.merch_id 
                WHERE m.event_id = e.id AND i.user_id = $1 AND i.quantity > 0
            ) as is_joined
        FROM events e 
        WHERE e.status = 'published' OR e.creator_id = $1
        ORDER BY e.created_at DESC
        "#,
    )
    .bind(query.user_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let events = rows
        .into_iter()
        .map(|row| {
            let active_participants: i64 = row.get("active_participants");
            let unique_views: Option<i64> = row.get("unique_views");
            let is_favorite: bool = row.get("is_favorite");
            let is_joined: bool = row.get("is_joined");

            Event {
                id: row.get("id"),
                name: row.get("name"),
                creator_id: row.get("creator_id"),
                created_at: row
                    .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                    .map(|dt| dt.to_rfc3339()),
                unique_views: unique_views.map(|v| v as i32),
                active_participants: Some(active_participants as i32),
                is_favorite: Some(is_favorite),
                is_joined: Some(is_joined),
                status: Some(row.get("status")),
            }
        })
        .collect();

    Ok(Json(events))
}

pub async fn toggle_favorite_group(
    State(pool): State<PgPool>,
    axum::extract::Path(event_id): axum::extract::Path<i32>,
    Json(payload): Json<ToggleFavoriteGroupRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    if payload.is_favorite {
        sqlx::query("INSERT INTO group_favorites (user_id, event_id, group_name) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING")
            .bind(payload.user_id)
            .bind(event_id)
            .bind(&payload.group_name)
            .execute(&pool)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    } else {
        sqlx::query(
            "DELETE FROM group_favorites WHERE user_id = $1 AND event_id = $2 AND group_name = $3",
        )
        .bind(payload.user_id)
        .bind(event_id)
        .bind(&payload.group_name)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }
    Ok(StatusCode::OK)
}

pub async fn list_favorite_groups(
    State(pool): State<PgPool>,
    axum::extract::Path(user_id): axum::extract::Path<i32>,
) -> Result<Json<Vec<FavoriteGroup>>, (StatusCode, String)> {
    let rows = sqlx::query(
        r#"
        SELECT gf.user_id, gf.event_id, gf.group_name, e.name as event_name
        FROM group_favorites gf
        JOIN events e ON gf.event_id = e.id
        WHERE gf.user_id = $1
        ORDER BY gf.created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let groups = rows
        .into_iter()
        .map(|row| FavoriteGroup {
            user_id: row.get("user_id"),
            event_id: row.get("event_id"),
            group_name: row.get("group_name"),
            event_name: Some(row.get("event_name")),
        })
        .collect();

    Ok(Json(groups))
}

pub async fn toggle_favorite(
    State(pool): State<PgPool>,
    axum::extract::Path(event_id): axum::extract::Path<i32>,
    Json(payload): Json<ToggleFavoriteRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    if payload.is_favorite {
        sqlx::query("INSERT INTO event_favorites (user_id, event_id) VALUES ($1, $2) ON CONFLICT DO NOTHING")
            .bind(payload.user_id)
            .bind(event_id)
            .execute(&pool)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    } else {
        sqlx::query("DELETE FROM event_favorites WHERE user_id = $1 AND event_id = $2")
            .bind(payload.user_id)
            .bind(event_id)
            .execute(&pool)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }
    Ok(StatusCode::OK)
}

pub async fn create_event(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateEventRequest>,
) -> Result<Json<Event>, (StatusCode, String)> {
    let user = permissions::get_verified_user(&pool, payload.creator_id).await?;
    permissions::require_not_banned(&user)?;

    let status = payload.status.as_deref().unwrap_or("published");

    let row = sqlx::query(
        "INSERT INTO events (name, creator_id, status) VALUES ($1, $2, $3) RETURNING id, name, creator_id, created_at, status",
    )
    .bind(&payload.name)
    .bind(payload.creator_id)
    .bind(status)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(Event {
        id: row.get("id"),
        name: row.get("name"),
        creator_id: row.get("creator_id"),
        created_at: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
        unique_views: Some(0),
        active_participants: Some(0),
        is_favorite: Some(false),
        is_joined: Some(false),
        status: Some(row.get("status")),
    }))
}

pub async fn update_event(
    State(pool): State<PgPool>,
    axum::extract::Path(event_id): axum::extract::Path<i32>,
    Json(payload): Json<UpdateEventRequest>,
) -> Result<Json<Event>, (StatusCode, String)> {
    let user = permissions::get_verified_user(&pool, payload.user_id).await?;
    permissions::require_not_banned(&user)?;

    let row = sqlx::query("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let row = row.ok_or((StatusCode::NOT_FOUND, "Event not found".to_string()))?;
    let creator_id: Option<i32> = row.get("creator_id");

    permissions::check_ownership_or_role(&user, creator_id.unwrap_or(-1), &["admin", "moderator"])?;

    let name = payload
        .name
        .ok_or((StatusCode::BAD_REQUEST, "name is required".to_string()))?;

    sqlx::query("UPDATE events SET name = $1 WHERE id = $2")
        .bind(&name)
        .bind(event_id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // Return the updated event with stats
    let updated = sqlx::query(
        r#"SELECT e.id, e.name, e.creator_id, e.created_at, e.status,
           (SELECT COUNT(*) FROM event_views v WHERE v.event_id = e.id) as unique_views,
           (SELECT COUNT(DISTINCT i.user_id) FROM inventory i JOIN merchandise m ON m.id = i.merch_id WHERE m.event_id = e.id AND i.quantity > 0) as active_participants
           FROM events e WHERE e.id = $1"#
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(Event {
        id: updated.get("id"),
        name: updated.get("name"),
        creator_id: updated.get("creator_id"),
        created_at: updated
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
        unique_views: updated
            .get::<Option<i64>, _>("unique_views")
            .map(|v| v as i32),
        active_participants: Some(updated.get::<i64, _>("active_participants") as i32),
        is_favorite: Some(false),
        is_joined: Some(false),
        status: Some(updated.get("status")),
    }))
}

pub async fn publish_event(
    State(pool): State<PgPool>,
    axum::extract::Path(event_id): axum::extract::Path<i32>,
    Json(payload): Json<UserActionRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let user = permissions::get_verified_user(&pool, payload.user_id).await?;
    permissions::require_not_banned(&user)?;

    let row = sqlx::query("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let row = row.ok_or((StatusCode::NOT_FOUND, "Event not found".to_string()))?;
    let creator_id: Option<i32> = row.get("creator_id");

    permissions::check_ownership_or_role(&user, creator_id.unwrap_or(-1), &["admin", "moderator"])?;

    sqlx::query("UPDATE events SET status = 'published' WHERE id = $1")
        .bind(event_id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}
