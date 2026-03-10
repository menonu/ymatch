use crate::generated::ymatch::*;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use sqlx::{PgPool, Row};

// --- System ---
pub async fn get_system_status() -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let rev = option_env!("GIT_HASH").unwrap_or("unknown");

    // Create a new System object to fetch current stats
    let mut sys = sysinfo::System::new_all();
    sys.refresh_all();

    let total_memory = sys.total_memory();
    let used_memory = sys.used_memory();
    let cpu_usage: f32 = sys.cpus().iter().map(|cpu| cpu.cpu_usage()).sum::<f32>()
        / (sys.cpus().len() as f32).max(1.0);
    let uptime = sysinfo::System::uptime();

    Ok(Json(serde_json::json!({
        "backend_version": rev,
        "resources": {
            "total_memory_bytes": total_memory,
            "used_memory_bytes": used_memory,
            "cpu_usage_percent": cpu_usage,
            "uptime_seconds": uptime,
            "os_name": sysinfo::System::name().unwrap_or_else(|| "Unknown".to_string()),
            "os_version": sysinfo::System::os_version().unwrap_or_else(|| "Unknown".to_string()),
        }
    })))
}

// --- Auth ---
pub async fn guest_login(
    State(pool): State<PgPool>,
    Json(payload): Json<GuestLoginRequest>,
) -> Result<Json<User>, (StatusCode, String)> {
    // 1. Try to find existing user by UUID
    let row = sqlx::query(
        "SELECT id, username, uuid, device_token, created_at FROM users WHERE uuid = $1",
    )
    .bind(&payload.uuid)
    .fetch_optional(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    if let Some(row) = row {
        let mut device_token: Option<String> = row.get("device_token");
        // Update device_token if provided
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

    // 2. Create new Guest User
    // Use the last 8 characters of the UUID for the username, or fallback to the whole string if it's too short.
    let suffix_len = std::cmp::min(8, payload.uuid.len());
    let uuid_suffix = &payload.uuid[payload.uuid.len() - suffix_len..];
    // Use standard uuid to guarantee uniqueness to avoid database constraint violations during rapid smoke testing
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

#[derive(serde::Deserialize)]
pub struct ListEventsQuery {
    pub user_id: Option<i32>,
}

#[derive(serde::Deserialize)]
pub struct RegisterViewRequest {
    pub user_id: i32,
}

pub async fn register_event_view(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
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

// --- Events ---
#[derive(serde::Deserialize)]
pub struct SearchQuery {
    pub q: String,
}

pub async fn global_search(
    State(pool): State<PgPool>,
    axum::extract::Query(query): axum::extract::Query<SearchQuery>,
) -> Result<Json<Vec<SearchResult>>, (StatusCode, String)> {
    let search_term = format!("%{}%", query.q);
    let mut results = Vec::new();

    // 1. Search Events
    let event_rows = sqlx::query("SELECT id, name FROM events WHERE name ILIKE $1 LIMIT 10")
        .bind(&search_term)
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    for row in event_rows {
        results.push(SearchResult {
            r#type: "event".to_string(),
            id: row.get("id"),
            title: row.get("name"),
            subtitle: None,
            photo_url: None,
            event_id: row.get("id"),
        });
    }

    // 2. Search Merchandise Items
    let merch_rows = sqlx::query(
        "SELECT m.id, m.name, m.group_name, m.photo_url, m.event_id, e.name as event_name 
         FROM merchandise m 
         JOIN events e ON m.event_id = e.id 
         WHERE m.name ILIKE $1 OR m.group_name ILIKE $1 LIMIT 20",
    )
    .bind(&search_term)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    for row in merch_rows {
        let group_name: Option<String> = row.get("group_name");
        let event_name: String = row.get("event_name");

        // If the match was clearly the group name, we could categorize it as "group",
        // but for now returning it as an item or group is fine. Let's just return items.
        let subtitle = if let Some(gn) = group_name {
            format!("{} > {}", event_name, gn)
        } else {
            event_name
        };

        results.push(SearchResult {
            r#type: "item".to_string(),
            id: row.get("id"),
            title: row.get("name"),
            subtitle: Some(subtitle),
            photo_url: row.get("photo_url"),
            event_id: row.get("event_id"),
        });
    }

    Ok(Json(results))
}

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

// --- Merchandise ---
pub async fn list_all_merch(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<Merchandise>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, event_id, name, photo_url, group_name, sort_order FROM merchandise ORDER BY id ASC")
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let merch = rows
        .into_iter()
        .map(|row| Merchandise {
            id: row.get("id"),
            event_id: row.get("event_id"),
            name: row.get("name"),
            photo_url: row.get("photo_url"),
            group_name: row.get("group_name"),
            sort_order: row.get::<Option<i32>, _>("sort_order"),
        })
        .collect();

    Ok(Json(merch))
}

pub async fn list_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
) -> Result<Json<Vec<Merchandise>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, event_id, name, photo_url, group_name, sort_order FROM merchandise WHERE event_id = $1 ORDER BY sort_order ASC, id ASC")
        .bind(event_id)
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let merch = rows
        .into_iter()
        .map(|row| Merchandise {
            id: row.get("id"),
            event_id: row.get("event_id"),
            name: row.get("name"),
            photo_url: row.get("photo_url"),
            group_name: row.get("group_name"),
            sort_order: Some(row.get("sort_order")),
        })
        .collect();

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

    let mut tx = pool
        .begin()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    for (merch_id, sort_order) in payload.sort_orders {
        sqlx::query("UPDATE merchandise SET sort_order = $1 WHERE id = $2 AND event_id = $3")
            .bind(sort_order)
            .bind(merch_id)
            .bind(event_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    tx.commit()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

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
        "#,
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
        "#,
    )
    .bind(user_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let items = rows
        .into_iter()
        .map(|row| InventoryItem {
            id: row.get("id"),
            user_id: row.get("user_id"),
            merch_id: row.get("merch_id"),
            status: row.get("status"),
            quantity: row.get("quantity"),
            merch_name: Some(row.get("merch_name")),
            photo_url: row.get("photo_url"),
            group_name: row.get("group_name"),
        })
        .collect();

    Ok(Json(items))
}

// --- Matches ---
pub async fn list_all_matches(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<TradeMatch>>, (StatusCode, String)> {
    let rows = sqlx::query(
        "SELECT id, user1_id, user2_id, status, created_at FROM matches ORDER BY created_at DESC",
    )
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let mut matches = Vec::new();
    for row in rows {
        let match_id: i32 = row.get("id");
        let trade_match = TradeMatch {
            id: match_id,
            user1_id: row.get("user1_id"),
            user2_id: row.get("user2_id"),
            status: row.get("status"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            other_user: None,
            user_haves: vec![],
            user_wants: vec![],
        };

        matches.push(trade_match);
    }

    Ok(Json(matches))
}

pub async fn delete_event(
    State(pool): State<PgPool>,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
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
) -> Result<StatusCode, (StatusCode, String)> {
    sqlx::query("DELETE FROM merchandise WHERE id = $1")
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    Ok(StatusCode::OK)
}

pub async fn delete_match(
    State(pool): State<PgPool>,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
    sqlx::query("DELETE FROM matches WHERE id = $1")
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    Ok(StatusCode::OK)
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

    let mut matches = Vec::new();
    for row in rows {
        let match_id: i32 = row.get("id");
        let u1: i32 = row.get("user1_id");
        let u2: i32 = row.get("user2_id");
        let other_user_id = if u1 == user_id { u2 } else { u1 };

        // Fetch other user info
        let other_user_row = sqlx::query("SELECT id, username FROM users WHERE id = $1")
            .bind(other_user_id)
            .fetch_one(&pool)
            .await
            .ok();

        let other_user = other_user_row.map(|r| User {
            id: r.get("id"),
            username: r.get("username"),
            uuid: None,
            device_token: None,
            created_at: None,
        });

        // Fetch what the current user is TRADING that the other user WANTS
        let haves_rows = sqlx::query(
            r#"
            SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.name as merch_name, m.photo_url
            FROM inventory i
            JOIN merchandise m ON i.merch_id = m.id
            WHERE i.user_id = $1 AND i.status = 'TRADE' AND i.quantity > 0
            AND EXISTS (
                SELECT 1 FROM inventory w WHERE w.user_id = $2 AND w.merch_id = i.merch_id AND w.status = 'WANT' AND w.quantity > 0
            )
            "#
        )
        .bind(user_id)
        .bind(other_user_id)
        .fetch_all(&pool)
        .await
        .unwrap_or_default();

        let user_haves = haves_rows
            .into_iter()
            .map(|r| InventoryItem {
                id: r.get("id"),
                user_id: r.get("user_id"),
                merch_id: r.get("merch_id"),
                status: r.get("status"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                photo_url: r.get("photo_url"),
                group_name: None,
            })
            .collect();

        // Fetch what the other user is TRADING that the current user WANTS
        let wants_rows = sqlx::query(
            r#"
            SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.name as merch_name, m.photo_url
            FROM inventory i
            JOIN merchandise m ON i.merch_id = m.id
            WHERE i.user_id = $2 AND i.status = 'TRADE' AND i.quantity > 0
            AND EXISTS (
                SELECT 1 FROM inventory w WHERE w.user_id = $1 AND w.merch_id = i.merch_id AND w.status = 'WANT' AND w.quantity > 0
            )
            "#
        )
        .bind(user_id)
        .bind(other_user_id)
        .fetch_all(&pool)
        .await
        .unwrap_or_default();

        let user_wants = wants_rows
            .into_iter()
            .map(|r| InventoryItem {
                id: r.get("id"),
                user_id: r.get("user_id"),
                merch_id: r.get("merch_id"),
                status: r.get("status"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                photo_url: r.get("photo_url"),
                group_name: None,
            })
            .collect();

        matches.push(TradeMatch {
            id: match_id,
            user1_id: u1,
            user2_id: u2,
            status: row.get("status"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            other_user,
            user_haves,
            user_wants,
        });
    }

    Ok(Json(matches))
}

pub async fn update_match_status(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<UpdateMatchStatusRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    // Basic validation of status
    let valid_statuses = ["ACCEPTED", "REJECTED", "COMPLETED"];
    if !valid_statuses.contains(&payload.status.as_str()) {
        return Err((StatusCode::BAD_REQUEST, "Invalid status".to_string()));
    }

    let mut tx = pool
        .begin()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // Update the status of this match
    sqlx::query("UPDATE matches SET status = $1 WHERE id = $2")
        .bind(&payload.status)
        .bind(match_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // If accepting, delete competing PENDING matches for the same users to prevent double-booking
    if payload.status == "ACCEPTED" {
        // Fetch the users involved in this match
        let match_row = sqlx::query("SELECT user1_id, user2_id FROM matches WHERE id = $1")
            .bind(match_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

        let u1: i32 = match_row.get("user1_id");
        let u2: i32 = match_row.get("user2_id");

        // Delete any PENDING matches that involve either user to clear out competing proposals.
        // NOTE: A more complex system might only delete matches involving the EXACT SAME items,
        // but since we only have user-level matching right now, we clear other pending matches between them.
        sqlx::query("DELETE FROM matches WHERE status = 'PENDING' AND id != $1 AND ((user1_id = $2 AND user2_id = $3) OR (user1_id = $3 AND user2_id = $2))")
            .bind(match_id)
            .bind(u1)
            .bind(u2)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    tx.commit()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

// --- Messages ---

pub async fn list_messages(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
) -> Result<Json<Vec<Message>>, (StatusCode, String)> {
    let rows = sqlx::query(
        "SELECT id, match_id, sender_id, content, created_at, message_type, latitude, longitude FROM messages WHERE match_id = $1 ORDER BY created_at ASC"
    )
    .bind(match_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let messages = rows
        .into_iter()
        .map(|row| Message {
            id: row.get("id"),
            match_id: row.get("match_id"),
            sender_id: row.get("sender_id"),
            content: row.get("content"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            message_type: row.get("message_type"),
            latitude: row.get("latitude"),
            longitude: row.get("longitude"),
        })
        .collect();

    Ok(Json(messages))
}

pub async fn send_message(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<SendMessageRequest>,
) -> Result<Json<Message>, (StatusCode, String)> {
    let row = sqlx::query(
        "INSERT INTO messages (match_id, sender_id, content, message_type, latitude, longitude) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, match_id, sender_id, content, created_at, message_type, latitude, longitude"
    )
    .bind(match_id)
    .bind(payload.sender_id)
    .bind(payload.content)
    .bind(payload.message_type.unwrap_or_else(|| "TEXT".to_string()))
    .bind(payload.latitude)
    .bind(payload.longitude)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(Message {
        id: row.get("id"),
        match_id: row.get("match_id"),
        sender_id: row.get("sender_id"),
        content: row.get("content"),
        created_at: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
            .map(|dt| dt.to_rfc3339()),
        message_type: row.get("message_type"),
        latitude: row.get("latitude"),
        longitude: row.get("longitude"),
    }))
}
