use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
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
    sqlx::query("DELETE FROM matches").execute(&pool).await.ok();
    sqlx::query("DELETE FROM inventory")
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM group_favorites")
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

async fn body_to_string(body: Body) -> String {
    let bytes = body.collect().await.unwrap().to_bytes();
    String::from_utf8(bytes.to_vec()).unwrap()
}

// --- Root ---

#[tokio::test]
async fn test_root_endpoint() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool);

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
    let app = backend::routes::create_router(pool);

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
    let app = backend::routes::create_router(pool);

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
    let app1 = backend::routes::create_router(pool.clone());

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

    let app2 = backend::routes::create_router(pool);
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
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool);
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
    let app = backend::routes::create_router(pool.clone());
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

    let app = backend::routes::create_router(pool);
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
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool);
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
    let app = backend::routes::create_router(pool.clone());
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

    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool);
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
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool.clone());
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

    let app = backend::routes::create_router(pool.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"name": "Inv Item"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_id = merch["id"].as_i64().unwrap();

    // Set inventory HAVE=2
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool);
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
    let app = backend::routes::create_router(pool);

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
    let app = backend::routes::create_router(pool.clone());
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

    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool);
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

// --- Admin ---

#[tokio::test]
async fn test_admin_delete_event() {
    let pool = setup_test_pool().await;

    // Create user + event
    let app = backend::routes::create_router(pool.clone());
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

    let app = backend::routes::create_router(pool.clone());
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

    // Delete event
    let app = backend::routes::create_router(pool);
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(&format!("/api/v1/admin/events/{}", event_id))
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
    let app = backend::routes::create_router(pool.clone());
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

    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool.clone());
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
    let app = backend::routes::create_router(pool);
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
