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
    let new_username = format!("Guest_{}", &payload.uuid[..8]);
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

// --- Events ---
pub async fn list_events(State(pool): State<PgPool>) -> Result<Json<Vec<Event>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, name, creator_id, created_at FROM events ORDER BY created_at DESC")
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let events = rows.into_iter().map(|row| Event {
        id: row.get("id"),
        name: row.get("name"),
        creator_id: row.get("creator_id"),
        created_at: row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
    }).collect();

    Ok(Json(events))
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
    }))
}

// --- Merchandise ---
pub async fn list_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
) -> Result<Json<Vec<Merchandise>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, event_id, name, photo_url FROM merchandise WHERE event_id = $1")
        .bind(event_id)
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let merch = rows.into_iter().map(|row| Merchandise {
        id: row.get("id"),
        event_id: row.get("event_id"),
        name: row.get("name"),
        photo_url: row.get("photo_url"),
    }).collect();

    Ok(Json(merch))
}

pub async fn create_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateMerchRequest>,
) -> Result<Json<Merchandise>, (StatusCode, String)> {
    let row = sqlx::query(
        "INSERT INTO merchandise (event_id, name, photo_url) VALUES ($1, $2, $3) RETURNING id, event_id, name, photo_url"
    )
    .bind(event_id)
    .bind(payload.name)
    .bind(payload.photo_url)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(Merchandise {
        id: row.get("id"),
        event_id: row.get("event_id"),
        name: row.get("name"),
        photo_url: row.get("photo_url"),
    }))
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
            m.name as merch_name, m.photo_url
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
        merch_name: row.get("merch_name"),
        photo_url: row.get("photo_url"),
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
