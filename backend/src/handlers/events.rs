use crate::generated::ymatch::*;
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
    let rows = sqlx::query(
        r#"
        SELECT 
            e.id, 
            e.name, 
            e.creator_id, 
            e.created_at,
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
        ORDER BY e.created_at DESC
        "#
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
    let row = sqlx::query(
        "INSERT INTO events (name, creator_id) VALUES ($1, $2) RETURNING id, name, creator_id, created_at"
    )
    .bind(payload.name)
    .bind(payload.creator_id)
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
    }))
}
