use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use sqlx::{PgPool, Row};
use crate::generated::ymatch::*;

// --- Auth ---
pub async fn guest_login(
    State(pool): State<PgPool>,
    Json(payload): Json<GuestLoginRequest>,
) -> Result<Json<User>, (StatusCode, String)> {
    // 1. Try to find existing user by UUID
    let row = sqlx::query("SELECT id, username, uuid, device_token, created_at FROM users WHERE uuid = $1")
        .bind(&payload.uuid)
        .fetch_optional(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    if let Some(row) = row {
        return Ok(Json(User {
            id: row.get("id"),
            username: row.get("username"),
            uuid: row.get("uuid"),
            device_token: row.get("device_token"),
            created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
        }));
    }

    // 2. Create new Guest User
    // Use the last 8 characters of the UUID for the username, or fallback to the whole string if it's too short.
    let suffix_len = std::cmp::min(8, payload.uuid.len());
    let uuid_suffix = &payload.uuid[payload.uuid.len() - suffix_len..];
    // Use standard uuid to guarantee uniqueness to avoid database constraint violations during rapid smoke testing
    let unique_id = uuid::Uuid::new_v4().to_string()[..6].to_string();
    let new_username = format!("Guest_{}_{}", uuid_suffix, unique_id);
    let row = sqlx::query(
        "INSERT INTO users (username, uuid) VALUES ($1, $2) RETURNING id, username, uuid, device_token, created_at"
    )
    .bind(new_username)
    .bind(&payload.uuid)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(User {
        id: row.get("id"),
        username: row.get("username"),
        uuid: row.get("uuid"),
        device_token: row.get("device_token"),
        created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
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
                created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
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
        created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
    }))
}

pub async fn list_users(State(pool): State<PgPool>) -> Result<Json<Vec<User>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, username, uuid, device_token, created_at FROM users")
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let users = rows.into_iter().map(|row| User {
        id: row.get("id"),
        username: row.get("username"),
        uuid: row.get("uuid"),
        device_token: row.get("device_token"),
        created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
    }).collect();

    Ok(Json(users))
}

#[derive(serde::Deserialize)]
pub struct ListEventsQuery {
    pub user_id: Option<i32>,
}

// --- Events ---
pub async fn list_events(
    State(pool): State<PgPool>,
    axum::extract::Query(query): axum::extract::Query<ListEventsQuery>,
) -> Result<Json<Vec<Event>>, (StatusCode, String)> {
    // We calculate active_participants as the number of distinct users who have inventory (HAVE or WANT) for merchandise in this event.
    // If user_id is provided, we join with event_favorites to set is_favorite.
    let rows = sqlx::query(
        r#"
        SELECT 
            e.id, 
            e.name, 
            e.creator_id, 
            e.created_at,
            e.unique_views,
            (
                SELECT COUNT(DISTINCT i.user_id)
                FROM inventory i
                JOIN merchandise m ON m.id = i.merch_id
                WHERE m.event_id = e.id AND i.quantity > 0
            ) as active_participants,
            EXISTS(SELECT 1 FROM event_favorites f WHERE f.event_id = e.id AND f.user_id = $1) as is_favorite
        FROM events e 
        ORDER BY e.created_at DESC
        "#
    )
        .bind(query.user_id)
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let events = rows.into_iter().map(|row| {
        let active_participants: i64 = row.get("active_participants");
        let unique_views: Option<i32> = row.get("unique_views");
        let is_favorite: bool = row.get("is_favorite");
        
        Event {
            id: row.get("id"),
            name: row.get("name"),
            creator_id: row.get("creator_id"),
            created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            unique_views,
            active_participants: Some(active_participants as i32),
            is_favorite: Some(is_favorite),
        }
    }).collect();

    Ok(Json(events))
}

#[derive(serde::Deserialize)]
pub struct ToggleFavoriteRequest {
    pub user_id: i32,
    pub is_favorite: bool,
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
        created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
        unique_views: Some(0),
        active_participants: Some(0),
        is_favorite: Some(false),
    }))
}

// --- Merchandise ---
pub async fn list_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
) -> Result<Json<Vec<Merchandise>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, event_id, name, photo_url, group_name, sort_order FROM merchandise WHERE event_id = $1 ORDER BY sort_order ASC, id ASC")
        .bind(event_id)
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let merch = rows.into_iter().map(|row| Merchandise {
        id: row.get("id"),
        event_id: row.get("event_id"),
        name: row.get("name"),
        photo_url: row.get("photo_url"),
        group_name: row.get("group_name"),
        sort_order: Some(row.get("sort_order")),
    }).collect();

    Ok(Json(merch))
}

pub async fn create_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateMerchRequest>,
) -> Result<Json<Merchandise>, (StatusCode, String)> {
    let row = sqlx::query(
        "INSERT INTO merchandise (event_id, name, photo_url, group_name) VALUES ($1, $2, $3, $4) RETURNING id, event_id, name, photo_url, group_name, sort_order"
    )
    .bind(event_id)
    .bind(payload.name)
    .bind(payload.photo_url)
    .bind(payload.group_name)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(Merchandise {
        id: row.get("id"),
        event_id: row.get("event_id"),
        name: row.get("name"),
        photo_url: row.get("photo_url"),
        group_name: row.get("group_name"),
        sort_order: Some(row.get("sort_order")),
    }))
}

pub async fn update_merch_sort_order(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<UpdateMerchSortOrderRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    if payload.event_id != event_id {
        return Err((StatusCode::BAD_REQUEST, "Event ID mismatch".to_string()));
    }

    let mut tx = pool.begin().await.map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    for (merch_id, sort_order) in payload.sort_orders {
        sqlx::query("UPDATE merchandise SET sort_order = $1 WHERE id = $2 AND event_id = $3")
            .bind(sort_order)
            .bind(merch_id)
            .bind(event_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }
    
    tx.commit().await.map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

// --- Inventory ---
pub async fn update_inventory(
    State(pool): State<PgPool>,
    Json(payload): Json<UpdateInventoryRequest>,
) -> Result<Json<InventoryItem>, (StatusCode, String)> {
    // Upsert logic
    let row = sqlx::query(
        r#"
        INSERT INTO inventory (user_id, merch_id, status, quantity)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id, merch_id, status)
        DO UPDATE SET quantity = EXCLUDED.quantity, updated_at = NOW()
        RETURNING id, user_id, merch_id, status, quantity
        "#
    )
    .bind(payload.user_id)
    .bind(payload.merch_id)
    .bind(payload.status)
    .bind(payload.quantity)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(InventoryItem {
        id: row.get("id"),
        user_id: row.get("user_id"),
        merch_id: row.get("merch_id"),
        status: row.get("status"),
        quantity: row.get("quantity"),
        merch_name: Some("".to_string()), // Filled in details handler
        photo_url: None,
        group_name: None,
    }))
}

pub async fn get_user_inventory(
    State(pool): State<PgPool>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<InventoryItem>>, (StatusCode, String)> {
    let rows = sqlx::query(
        r#"
        SELECT 
            i.id, i.user_id, i.merch_id, i.status, i.quantity,
            m.name as merch_name, m.photo_url, m.group_name
        FROM inventory i
        JOIN merchandise m ON i.merch_id = m.id
        WHERE i.user_id = $1
        "#
    )
    .bind(user_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let items = rows.into_iter().map(|row| InventoryItem {
        id: row.get("id"),
        user_id: row.get("user_id"),
        merch_id: row.get("merch_id"),
        status: row.get("status"),
        quantity: row.get("quantity"),
        merch_name: Some(row.get("merch_name")),
        photo_url: row.get("photo_url"),
        group_name: row.get("group_name"),
    }).collect();

    Ok(Json(items))
}

// --- Matches ---
pub async fn trigger_matching(State(pool): State<PgPool>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let count = crate::matching::run_matching_algorithm(&pool).await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    Ok(Json(serde_json::json!({ "matches_created": count })))
}

pub async fn list_matches(
    State(pool): State<PgPool>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<TradeMatch>>, (StatusCode, String)> {
    let rows = sqlx::query(
        "SELECT id, user1_id, user2_id, status, created_at FROM matches WHERE user1_id = $1 OR user2_id = $1 ORDER BY created_at DESC"
    )
    .bind(user_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let matches = rows.into_iter().map(|row| TradeMatch {
        id: row.get("id"),
        user1_id: row.get("user1_id"),
        user2_id: row.get("user2_id"),
        status: row.get("status"),
        created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
        other_user: None,
        user_haves: vec![],
        user_wants: vec![],
    }).collect();

    Ok(Json(matches))
}
