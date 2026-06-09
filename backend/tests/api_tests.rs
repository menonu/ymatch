use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;

async fn setup_test_pool() -> PgPool {
    let db_url = std::env::var("DATABASE_URL").unwrap_or_else(|_| {
        "postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch_test".to_string()
    });

    let pool = PgPoolOptions::new()
        .max_connections(2)
        .connect(&db_url)
        .await
        .expect("Failed to connect to test database");

    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    // Clean up test data
    sqlx::query("DELETE FROM messages")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM match_items")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM matches").execute(&pool).await.ok();
    sqlx::query("DELETE FROM inventory")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM group_favorites")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM merchandise_groups")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM event_favorites")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM event_views")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM merchandise")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM events").execute(&pool).await.ok();
    sqlx::query("DELETE FROM users").execute(&pool).await.ok();

    pool
}

fn test_storage() -> Arc<dyn backend::storage::ImageStorage> {
    Arc::new(backend::storage::LocalFileStorage::new(
        "./test_uploads".to_string(),
    ))
}

async fn body_to_string(body: Body) -> String {
    let bytes = body.collect().await.unwrap().to_bytes();
    String::from_utf8(bytes.to_vec()).unwrap()
}

// --- Root ---

#[tokio::test]
async fn test_root_endpoint() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());

    let response = app
        .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    assert_eq!(body, "Hello from ymatch Rust Backend!");
}

// --- System ---

#[tokio::test]
async fn test_system_status() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());

    let response = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/system/status")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert!(json.get("backend_version").is_some());
    assert!(json.get("resources").is_some());
}

// --- Auth ---

#[tokio::test]
async fn test_guest_login_creates_user() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"uuid": "test-uuid-1234", "device_token": "tok123"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert!(json["id"].as_i64().unwrap() > 0);
    assert!(json["username"].as_str().unwrap().contains("Guest_"));
    assert_eq!(json["uuid"].as_str().unwrap(), "test-uuid-1234");
}

#[tokio::test]
async fn test_guest_login_returns_existing_user() {
    let pool = setup_test_pool().await;
    let app1 = backend::routes::create_router(pool.clone(), test_storage());

    let resp1 = app1
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "reuse-uuid-5678"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let body1 = body_to_string(resp1.into_body()).await;
    let user1: serde_json::Value = serde_json::from_str(&body1).unwrap();

    let app2 = backend::routes::create_router(pool, test_storage());
    let resp2 = app2
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "reuse-uuid-5678"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let body2 = body_to_string(resp2.into_body()).await;
    let user2: serde_json::Value = serde_json::from_str(&body2).unwrap();

    assert_eq!(user1["id"], user2["id"]);
    assert_eq!(user1["username"], user2["username"]);
}

#[tokio::test]
async fn test_signup_and_login() {
    let pool = setup_test_pool().await;

    // Signup
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/signup")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"username": "testuser_api", "password": "pass123"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    let user: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(user["username"].as_str().unwrap(), "testuser_api");

    // Login with correct password
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"username": "testuser_api", "password": "pass123"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // Login with wrong password
    let app = backend::routes::create_router(pool, test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"username": "testuser_api", "password": "wrong"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_list_users() {
    let pool = setup_test_pool().await;

    // Create a user first
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("POST")
            .uri("/api/v1/auth/guest")
            .header("content-type", "application/json")
            .body(Body::from(r#"{"uuid": "list-users-test"}"#))
            .unwrap(),
    )
    .await
    .unwrap();

    let app = backend::routes::create_router(pool, test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/users")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    let users: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    assert!(!users.is_empty());
}

// --- Events ---

#[tokio::test]
async fn test_create_and_list_events() {
    let pool = setup_test_pool().await;

    // Create a user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "event-test-user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let body = body_to_string(resp.into_body()).await;
    let user: serde_json::Value = serde_json::from_str(&body).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Create event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Test Event", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let event: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(event["name"].as_str().unwrap(), "Test Event");
    assert_eq!(event["active_participants"].as_i64().unwrap(), 0);

    // List events
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/events")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let events: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    assert!(events.iter().any(|e| e["name"] == "Test Event"));
}

// --- Merchandise ---

#[tokio::test]
async fn test_create_and_list_merch() {
    let pool = setup_test_pool().await;

    // Create user + event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "merch-test-user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Merch Event", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();

    // Create merchandise
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"name": "Test Item", "group_name": "Group A"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(merch["name"].as_str().unwrap(), "Test Item");
    assert_eq!(merch["event_id"].as_i64().unwrap(), event_id);

    // List merchandise
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let items: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["name"].as_str().unwrap(), "Test Item");
}

// --- Inventory ---

#[tokio::test]
async fn test_inventory_upsert() {
    let pool = setup_test_pool().await;

    // Create user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "inv-test-user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Create event + merch
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Inv Event", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"name": "Inv Item", "group_name": "Test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_id = merch["id"].as_i64().unwrap();

    // Set inventory HAVE=2
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/user/inventory")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "merch_id": {}, "status": "HAVE", "quantity": 2}}"#,
                    user_id, merch_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let inv: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(inv["quantity"].as_i64().unwrap(), 2);
    assert_eq!(inv["status"].as_str().unwrap(), "HAVE");

    // Update to HAVE=5 (upsert)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/user/inventory")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "merch_id": {}, "status": "HAVE", "quantity": 5}}"#,
                    user_id, merch_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let inv: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(inv["quantity"].as_i64().unwrap(), 5);

    // Get user inventory
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/user/{}/inventory", user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let items: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["quantity"].as_i64().unwrap(), 5);
}

// --- Matches ---

#[tokio::test]
async fn test_update_match_status_validation() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/matches/999/status")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"status": "INVALID"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

// --- Search ---

#[tokio::test]
async fn test_search_returns_results() {
    let pool = setup_test_pool().await;

    // Create user + event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "search-test-user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("POST")
            .uri("/api/v1/events")
            .header("content-type", "application/json")
            .body(Body::from(format!(
                r#"{{"name": "Searchable Convention", "creator_id": {}}}"#,
                user_id
            )))
            .unwrap(),
    )
    .await
    .unwrap();

    // Search
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/search?q=Searchable")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let results: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(results
        .iter()
        .any(|r| r["title"] == "Searchable Convention"));
}

#[tokio::test]
async fn test_search_excludes_draft_events() {
    let pool = setup_test_pool().await;

    // Create user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "search-draft-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Create a draft event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("POST")
            .uri("/api/v1/events")
            .header("content-type", "application/json")
            .body(Body::from(format!(
                r#"{{"name": "DraftSearchTest Event", "creator_id": {}, "status": "draft"}}"#,
                user_id
            )))
            .unwrap(),
    )
    .await
    .unwrap();

    // Search should NOT find the draft event
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/search?q=DraftSearchTest")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let results: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(
        !results
            .iter()
            .any(|r| r["title"] == "DraftSearchTest Event"),
        "Draft events should not appear in search results"
    );
}

// --- Admin ---

#[tokio::test]
async fn test_admin_delete_event() {
    let pool = setup_test_pool().await;

    // Create user + event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-del-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Promote user to admin
    sqlx::query("UPDATE users SET role = 'admin' WHERE id = $1")
        .bind(user_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Delete Me", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();

    // Delete event (with admin user_id)
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(&format!(
                    "/api/v1/admin/events/{}?user_id={}",
                    event_id, user_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

// --- Messages ---

#[tokio::test]
async fn test_messages_empty_list() {
    let pool = setup_test_pool().await;

    // Create two users and a match
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "msg-user-1"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let u1: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let u1_id = u1["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "msg-user-2"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let u2: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let u2_id = u2["id"].as_i64().unwrap();

    // Insert match directly
    let match_row = sqlx::query(
        "INSERT INTO matches (user1_id, user2_id, status) VALUES ($1, $2, 'PENDING') RETURNING id",
    )
    .bind(u1_id as i32)
    .bind(u2_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    let match_id: i32 = sqlx::Row::get(&match_row, "id");

    // Send a message
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/messages", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"match_id": {}, "sender_id": {}, "content": "Hello!"}}"#,
                    match_id, u1_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // List messages
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/{}/messages", match_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let messages: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0]["content"].as_str().unwrap(), "Hello!");
}

// --- Permission System Tests ---

#[tokio::test]
async fn test_banned_user_cannot_login() {
    let pool = setup_test_pool().await;

    // Create user via guest login
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "ban-test-uuid"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Ban the user
    sqlx::query("UPDATE users SET is_banned = true, ban_reason = 'test ban' WHERE id = $1")
        .bind(user_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    // Try guest login again - should be forbidden
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "ban-test-uuid"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_admin_ban_unban_user() {
    let pool = setup_test_pool().await;

    // Create admin user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-ban-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let admin: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let admin_id = admin["id"].as_i64().unwrap();
    sqlx::query("UPDATE users SET role = 'admin' WHERE id = $1")
        .bind(admin_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    // Create target user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "target-ban-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let target_id = target["id"].as_i64().unwrap();

    // Ban the target
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!(
                    "/api/v1/admin/users/{}/ban?user_id={}",
                    target_id, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"reason": "Bad behavior"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify user is banned
    let row = sqlx::query("SELECT is_banned, ban_reason FROM users WHERE id = $1")
        .bind(target_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(sqlx::Row::get::<bool, _>(&row, "is_banned"));
    assert_eq!(
        sqlx::Row::get::<Option<String>, _>(&row, "ban_reason"),
        Some("Bad behavior".to_string())
    );

    // Unban the target
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!(
                    "/api/v1/admin/users/{}/unban?user_id={}",
                    target_id, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify user is unbanned
    let row = sqlx::query("SELECT is_banned FROM users WHERE id = $1")
        .bind(target_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(!sqlx::Row::get::<bool, _>(&row, "is_banned"));
}

#[tokio::test]
async fn test_non_admin_cannot_ban() {
    let pool = setup_test_pool().await;

    // Create regular user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "nonadmin-ban-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Try to ban someone (should fail - not admin)
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/admin/users/999/ban?user_id={}", user_id))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"reason": "test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_update_user_role() {
    let pool = setup_test_pool().await;

    // Create admin
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "role-admin-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let admin: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let admin_id = admin["id"].as_i64().unwrap();
    sqlx::query("UPDATE users SET role = 'admin' WHERE id = $1")
        .bind(admin_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    // Create target
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "role-target-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let target_id = target["id"].as_i64().unwrap();

    // Promote to moderator
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target_id, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "moderator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let row = sqlx::query("SELECT role FROM users WHERE id = $1")
        .bind(target_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(sqlx::Row::get::<String, _>(&row, "role"), "moderator");
}

// --- Draft/Publish Tests ---

#[tokio::test]
async fn test_draft_event_visibility() {
    let pool = setup_test_pool().await;

    // Create two users
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "draft-creator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let creator: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let creator_id = creator["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "draft-viewer"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let viewer: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let viewer_id = viewer["id"].as_i64().unwrap();

    // Create draft event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Draft Event", "creator_id": {}, "status": "draft"}}"#,
                    creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(event["status"].as_str().unwrap(), "draft");
    let event_id = event["id"].as_i64().unwrap();

    // Creator can see draft
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/events?user_id={}", creator_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let events: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(events.iter().any(|e| e["name"] == "Draft Event"));

    // Other user cannot see draft
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/events?user_id={}", viewer_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let events: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(!events.iter().any(|e| e["name"] == "Draft Event"));

    // Publish event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/publish", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, creator_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Now other user can see it
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/events?user_id={}", viewer_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let events: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(events.iter().any(|e| e["name"] == "Draft Event"));
}

#[tokio::test]
async fn test_draft_merch_visibility() {
    let pool = setup_test_pool().await;

    // Create user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "draft-merch-user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Create event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Merch Draft Event", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();

    // Create draft merch
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Draft Item", "group_name": "Test", "creator_id": {}, "status": "draft"}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(merch["status"].as_str().unwrap(), "draft");
    let merch_id = merch["id"].as_i64().unwrap();

    // Creator can see draft merch
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!(
                    "/api/v1/events/{}/merch?user_id={}",
                    event_id, user_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let items: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(items.iter().any(|i| i["name"] == "Draft Item"));

    // Publish merch
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!(
                    "/api/v1/events/{}/merch/{}/publish",
                    event_id, merch_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

// --- Soft Delete Tests ---

#[tokio::test]
async fn test_soft_delete_merch_with_inventory() {
    let pool = setup_test_pool().await;

    // Create user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "softdel-user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Create event + merch
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "SoftDel Event", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "SoftDel Item", "group_name": "Test", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_id = merch["id"].as_i64().unwrap();

    // Add inventory for this merch
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("POST")
            .uri("/api/v1/user/inventory")
            .header("content-type", "application/json")
            .body(Body::from(format!(
                r#"{{"user_id": {}, "merch_id": {}, "status": "HAVE", "quantity": 3}}"#,
                user_id, merch_id
            )))
            .unwrap(),
    )
    .await
    .unwrap();

    // Delete merch (should soft-delete since inventory exists)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(&format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch_id, user_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify merch is soft-deleted
    let row = sqlx::query("SELECT is_deleted, trade_enabled FROM merchandise WHERE id = $1")
        .bind(merch_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(sqlx::Row::get::<bool, _>(&row, "is_deleted"));
    assert!(!sqlx::Row::get::<bool, _>(&row, "trade_enabled"));

    // Inventory still accessible
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/user/{}/inventory", user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let items: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(!items.is_empty());
}

#[tokio::test]
async fn test_hard_delete_merch_without_inventory() {
    let pool = setup_test_pool().await;

    // Create user + event + merch
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "harddel-user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "HardDel Event", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "HardDel Item", "group_name": "Test", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_id = merch["id"].as_i64().unwrap();

    // Delete merch (no inventory → hard delete)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(&format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch_id, user_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify merch is completely gone
    let row = sqlx::query("SELECT id FROM merchandise WHERE id = $1")
        .bind(merch_id as i32)
        .fetch_optional(&pool)
        .await
        .unwrap();
    assert!(row.is_none());
}

#[tokio::test]
async fn test_user_response_includes_role() {
    let pool = setup_test_pool().await;

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "role-check-uuid"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(user["role"].as_str().unwrap(), "user");
    assert_eq!(user["is_banned"].as_bool().unwrap(), false);
}

#[tokio::test]
async fn test_banned_user_cannot_create_event() {
    let pool = setup_test_pool().await;

    // Create user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "ban-create-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Ban the user
    sqlx::query("UPDATE users SET is_banned = true WHERE id = $1")
        .bind(user_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    // Try to create event
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Banned Event", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// --- Trade Lifecycle E2E ---

#[tokio::test]
async fn test_trade_lifecycle_offer_accept_complete_apply() {
    let pool = setup_test_pool().await;

    // 1. Create two users
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"uuid": "user1-lifecycle-test", "device_token": "tok1"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let user1: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user1_id = user1["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"uuid": "user2-lifecycle-test", "device_token": "tok2"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let user2: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user2_id = user2["id"].as_i64().unwrap();

    // 2. Create event + 2 merch items
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Trade Test Event", "creator_id": {}}}"#,
                    user1_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"event_id": {}, "name": "Card A", "photo_url": "", "group_name": "Cards"}}"#,
                    event_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch_a: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_a_id = merch_a["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"event_id": {}, "name": "Card B", "photo_url": "", "group_name": "Cards"}}"#,
                    event_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch_b: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_b_id = merch_b["id"].as_i64().unwrap();

    // 3. User1: TRADE Card A, WANT Card B; User2: TRADE Card B, WANT Card A
    for (uid, mid, status) in [
        (user1_id, merch_a_id, "TRADE"),
        (user1_id, merch_b_id, "WANT"),
        (user2_id, merch_b_id, "TRADE"),
        (user2_id, merch_a_id, "WANT"),
    ] {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/user/inventory")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"user_id": {}, "merch_id": {}, "status": "{}", "quantity": 1}}"#,
                        uid, mid, status
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    // 4. Run matching algorithm directly
    let matches_created = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("Matching algorithm failed");
    assert!(matches_created >= 1, "Should create at least 1 match");

    // 5. Get match for user1
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/user/{}", user1_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let matches: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(!matches.is_empty());
    let match_id = matches[0]["id"].as_i64().unwrap();
    assert_eq!(matches[0]["status"], "PENDING");
    // inventory_applied defaults to false; prost may omit it (null) or emit false
    assert!(
        matches[0]["inventory_applied"].is_null() || matches[0]["inventory_applied"] == false,
        "inventory_applied should be false/null for new match"
    );

    // 6. User1 offers: GIVE Card A, RECEIVE Card B
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "items": [
                        {{"merch_id": {}, "direction": "GIVE", "quantity": 1}},
                        {{"merch_id": {}, "direction": "RECEIVE", "quantity": 1}}
                    ]}}"#,
                    user1_id, merch_a_id, merch_b_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify OFFERED + offeredBy
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/user/{}", user1_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let matches: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(matches[0]["status"], "OFFERED");
    assert_eq!(matches[0]["offered_by"], user1_id);

    // 7. User2 accepts
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/status", match_id))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"status": "ACCEPTED"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // 8. Complete
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/status", match_id))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"status": "COMPLETED"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // 9. User1 applies inventory (only User1's inventory should change)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/apply-inventory", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user1_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // 10. Verify User1: gave Card A (TRADE=0), received Card B (HAVE=1)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/user/{}/inventory", user1_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let inv1: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let u1_trade_a = inv1
        .iter()
        .find(|i| i["merch_id"] == merch_a_id && i["status"] == "TRADE");
    assert!(
        u1_trade_a.is_none() || u1_trade_a.unwrap()["quantity"].as_i64().unwrap() == 0,
        "User1 TRADE Card A should be 0"
    );
    let u1_have_b = inv1
        .iter()
        .find(|i| i["merch_id"] == merch_b_id && i["status"] == "HAVE");
    assert!(u1_have_b.is_some(), "User1 should HAVE Card B");
    assert_eq!(u1_have_b.unwrap()["quantity"].as_i64().unwrap(), 1);

    // Verify User2's inventory is NOT yet changed (User2 hasn't applied)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/user/{}/inventory", user2_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let inv2_before: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let u2_trade_b_before = inv2_before
        .iter()
        .find(|i| i["merch_id"] == merch_b_id && i["status"] == "TRADE");
    assert!(
        u2_trade_b_before.is_some()
            && u2_trade_b_before.unwrap()["quantity"].as_i64().unwrap() == 1,
        "User2 TRADE Card B should still be 1 (not yet applied)"
    );

    // 11. inventory_applied: true for User1, false for User2
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/user/{}", user1_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let matches: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(matches[0]["inventory_applied"], true);

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/user/{}", user2_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let matches2: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(
        matches2[0]["inventory_applied"].is_null() || matches2[0]["inventory_applied"] == false,
        "User2 inventory_applied should still be false"
    );

    // 12. Double-apply for User1 → 409 Conflict
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/apply-inventory", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user1_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CONFLICT);

    // 13. User2 applies inventory
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/apply-inventory", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user2_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify User2: gave Card B (TRADE=0), received Card A (HAVE=1)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/user/{}/inventory", user2_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let inv2: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let u2_trade_b = inv2
        .iter()
        .find(|i| i["merch_id"] == merch_b_id && i["status"] == "TRADE");
    assert!(
        u2_trade_b.is_none() || u2_trade_b.unwrap()["quantity"].as_i64().unwrap() == 0,
        "User2 TRADE Card B should be 0"
    );
    let u2_have_a = inv2
        .iter()
        .find(|i| i["merch_id"] == merch_a_id && i["status"] == "HAVE");
    assert!(u2_have_a.is_some(), "User2 should HAVE Card A");
    assert_eq!(u2_have_a.unwrap()["quantity"].as_i64().unwrap(), 1);

    // 14. Double-apply for User2 → 409 Conflict
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/apply-inventory", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user2_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CONFLICT);

    // 15. Notification counts
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/user/{}/counts", user1_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_offer_on_non_pending_match_rejected() {
    let pool = setup_test_pool().await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/matches/99999/offer")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"user_id": 1, "items": [{"merch_id": 1, "direction": "GIVE", "quantity": 1}]}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    // 422 because JSON parsing precedes the route match for typed extractors,
    // or 404 if the route doesn't match - either way, not 200
    assert_ne!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_apply_inventory_on_non_completed_rejected() {
    let pool = setup_test_pool().await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/matches/99999/apply-inventory")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"user_id": 1}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_ne!(resp.status(), StatusCode::OK);
}

// --- Merchandise Groups (Issue #128) ---

async fn create_test_user_and_event(pool: PgPool, uuid: &str, event_name: &str) -> (i64, i64) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"uuid": "{}"}}"#, uuid)))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "{}", "creator_id": {}}}"#,
                    event_name, user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();
    (user_id, event_id)
}

#[tokio::test]
async fn test_create_group_via_dialog() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-dialog-user", "Group Event").await;

    // Create group with description
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"event_id": {}, "user_id": {}, "group_name": "Keychains", "description": "Handmade keychains only"}}"#,
                    event_id, user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["group_name"].as_str().unwrap(), "Keychains");
    assert_eq!(
        group["description"].as_str().unwrap(),
        "Handmade keychains only"
    );
    assert_eq!(group["created_by"].as_i64().unwrap(), user_id);
    assert!(group["id"].as_i64().is_some());

    // Re-creating same group is idempotent (upsert); description can be updated.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"event_id": {}, "user_id": {}, "group_name": "Keychains", "description": "Updated"}}"#,
                    event_id, user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["description"].as_str().unwrap(), "Updated");
    assert_eq!(group["created_by"].as_i64().unwrap(), user_id);

    // List groups for event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let groups = body["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0]["group_name"].as_str().unwrap(), "Keychains");
}

#[tokio::test]
async fn test_update_group_description() {
    let pool = setup_test_pool().await;
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-updater-creator", "Updater Event").await;

    // Create group as creator
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"event_id": {}, "user_id": {}, "group_name": "Pins", "description": "original"}}"#,
                    event_id, creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Update description as creator
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(&format!("/api/v1/events/{}/groups/Pins", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"event_id": {}, "user_id": {}, "group_name": "Pins", "description": "updated by creator"}}"#,
                    event_id, creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["description"].as_str().unwrap(), "updated by creator");

    // Non-creator cannot update
    let (other_id, _) =
        create_test_user_and_event(pool.clone(), "group-updater-other", "Other").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(&format!("/api/v1/events/{}/groups/Pins", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"event_id": {}, "user_id": {}, "group_name": "Pins", "description": "hostile update"}}"#,
                    event_id, other_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_implicit_group_via_first_merch() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "implicit-group-user", "Implicit Group Event")
            .await;

    // No group row yet
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["groups"].as_array().unwrap().len(), 0);

    // Create first merch in a new group — should auto-create the group row
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "First item", "group_name": "Auto Group", "creator_id": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    // No description set yet
    assert!(merch["group_description"].is_null());

    // List groups — should now show "Auto Group" with this user as creator
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let groups = body["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0]["group_name"].as_str().unwrap(), "Auto Group");
    assert_eq!(groups[0]["created_by"].as_i64().unwrap(), user_id);
}

#[tokio::test]
async fn test_merch_includes_group_description() {
    let pool = setup_test_pool().await;
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-desc-merch", "Merch Desc Event").await;

    // Pre-create the group with a description
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"event_id": {}, "user_id": {}, "group_name": "Stickers", "description": "Vinyl stickers"}}"#,
                    event_id, creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Create merch in that group
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Cat sticker", "group_name": "Stickers", "creator_id": {}}}"#,
                    creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(
        merch["group_description"].as_str().unwrap(),
        "Vinyl stickers"
    );

    // List merch should also include description
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(
        items[0]["group_description"].as_str().unwrap(),
        "Vinyl stickers"
    );
}
