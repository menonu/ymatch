use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use sqlx::PgPool;
use sqlx::postgres::PgPoolOptions;
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

    // Reset all tables to a known-empty state at the start of every
    // test. `TRUNCATE ... RESTART IDENTITY CASCADE` is used in
    // preference to `DELETE FROM ...` because it:
    //   1. Resets SERIAL sequences (so id=1, id=2, ... are guaranteed
    //      to be assigned to the first inserts, regardless of what
    //      tests ran previously).
    //   2. CASCADE handles the dependency ordering automatically
    //      (children → parents) so we don't have to maintain a
    //      manual list.
    //   3. Performs better than per-table DELETE (single statement,
    //      smaller WAL traffic).
    sqlx::query(
        "TRUNCATE TABLE
             messages,
             match_items,
             matches,
             inventory,
             group_favorites,
             merchandise_groups,
             event_favorites,
             event_views,
             merchandise,
             events,
             users
         RESTART IDENTITY CASCADE",
    )
    .execute(&pool)
    .await
    .expect("Failed to TRUNCATE test tables");

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

// --- Phase 5 favorites / views / event publishing (Issue #178 Task 2) ---

#[tokio::test]
async fn test_event_favorite_toggle_inserts_when_absent() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "fav-toggle-user", "Fav Toggle Event").await;

    // No row initially.
    let row = sqlx::query(
        "SELECT 1 as present FROM event_favorites WHERE user_id = $1 AND event_id = $2",
    )
    .bind(user_id as i32)
    .bind(event_id as i32)
    .fetch_optional(&pool)
    .await
    .unwrap();
    assert!(row.is_none(), "no event_favorites row should exist yet");

    // POST toggle → row is inserted.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/favorite", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "is_favorite": true}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let row = sqlx::query(
        "SELECT 1 as present FROM event_favorites WHERE user_id = $1 AND event_id = $2",
    )
    .bind(user_id as i32)
    .bind(event_id as i32)
    .fetch_optional(&pool)
    .await
    .unwrap();
    assert!(row.is_some(), "row should exist after first toggle");
}

#[tokio::test]
async fn test_event_favorite_toggle_removes_when_present() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "fav-remove-user", "Fav Remove Event").await;

    // First toggle → row inserted.
    for _ in 0..2 {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/v1/events/{}/favorite", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"user_id": {}, "is_favorite": true}}"#,
                        user_id
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    // After two toggles, row should be gone (insert → delete).
    let row = sqlx::query(
        "SELECT 1 as present FROM event_favorites WHERE user_id = $1 AND event_id = $2",
    )
    .bind(user_id as i32)
    .bind(event_id as i32)
    .fetch_optional(&pool)
    .await
    .unwrap();
    assert!(row.is_none(), "row should be removed after second toggle");
}

#[tokio::test]
async fn test_event_favorite_per_user_independence() {
    let pool = setup_test_pool().await;
    let (user_a, event_id) =
        create_test_user_and_event(pool.clone(), "fav-iso-a", "Fav Iso Event").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "fav-iso-b"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user_b_json: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_b = user_b_json["id"].as_i64().unwrap();

    // User A favorites the event.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/favorite", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "is_favorite": true}}"#,
                    user_a
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // User B should have no row.
    let row = sqlx::query(
        "SELECT 1 as present FROM event_favorites WHERE user_id = $1 AND event_id = $2",
    )
    .bind(user_b as i32)
    .bind(event_id as i32)
    .fetch_optional(&pool)
    .await
    .unwrap();
    assert!(
        row.is_none(),
        "user B's favorite should be independent of user A's"
    );

    // User A's row should still be there.
    let row = sqlx::query(
        "SELECT 1 as present FROM event_favorites WHERE user_id = $1 AND event_id = $2",
    )
    .bind(user_a as i32)
    .bind(event_id as i32)
    .fetch_optional(&pool)
    .await
    .unwrap();
    assert!(row.is_some(), "user A's row should still be present");
}

#[tokio::test]
async fn test_group_favorite_toggle_and_list() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "gfav-toggle-user", "Group Fav Event").await;

    // Favorite a group in the event.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/favorite_group", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "group_name": "Books", "is_favorite": true}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // List should include it with the event name joined.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/user/{}/favorite_groups", user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let groups: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    assert_eq!(groups.len(), 1, "exactly one favorite group expected");
    assert_eq!(groups[0]["group_name"], "Books");
    assert_eq!(groups[0]["event_id"], event_id);
    assert_eq!(groups[0]["event_name"], "Group Fav Event");
}

#[tokio::test]
async fn test_group_favorite_toggle_removes() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "gfav-remove-user", "Group Fav Remove Event")
            .await;

    // Toggle twice (insert, then delete).
    for _ in 0..2 {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/v1/events/{}/favorite_group", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"user_id": {}, "group_name": "Music", "is_favorite": true}}"#,
                        user_id
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    // List should be empty.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/user/{}/favorite_groups", user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let groups: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    assert!(groups.is_empty(), "list should be empty after toggle-off");
}

#[tokio::test]
async fn test_event_view_register_inserts() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "view-register-user", "View Register Event").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/view", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let row =
        sqlx::query("SELECT 1 as present FROM event_views WHERE user_id = $1 AND event_id = $2")
            .bind(user_id as i32)
            .bind(event_id as i32)
            .fetch_optional(&pool)
            .await
            .unwrap();
    assert!(
        row.is_some(),
        "event_view row should exist after first view"
    );
}

#[tokio::test]
async fn test_event_view_register_is_idempotent() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "view-idem-user", "View Idem Event").await;

    // Call the view endpoint three times.
    for _ in 0..3 {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/v1/events/{}/view", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(r#"{{"user_id": {}}}"#, user_id)))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    // Should still be exactly one row (UNIQUE constraint on (event_id, user_id)).
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM event_views WHERE user_id = $1 AND event_id = $2")
            .bind(user_id as i32)
            .bind(event_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(count, 1, "duplicate views must collapse to one row");
}

#[tokio::test]
async fn test_event_view_per_user_and_per_event() {
    let pool = setup_test_pool().await;
    let (user_a, event_a) =
        create_test_user_and_event(pool.clone(), "view-iso-a", "View Iso A").await;

    // Create a second user and a second event.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "view-iso-b"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user_b: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "View Iso B", "creator_id": {}}}"#,
                    user_b
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event_b: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    // User A views event A.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/view", event_a))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user_a)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // User B views event B.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/view", event_b))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user_b)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Two distinct rows.
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM event_views")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 2, "two distinct views must produce two rows");
}

#[tokio::test]
async fn test_update_event_owner_succeeds() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "update-event-owner", "Update Event").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "name": "Updated Name"}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let event: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(event["name"], "Updated Name");
}

#[tokio::test]
async fn test_update_event_non_owner_forbidden() {
    let pool = setup_test_pool().await;
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "update-event-creator", "Locked Event").await;

    // Create a different user.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "update-event-intruder"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let intruder_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();
    assert_ne!(intruder_id, creator_id);

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "name": "Pwned"}}"#,
                    intruder_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_publish_event_owner_succeeds() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "publish-event-owner", "Publish Event").await;

    // Initial status is 'published' (default; the helper does not pass status).
    let row: (String,) = sqlx::query_as("SELECT status FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(row.0, "published");

    // The publish endpoint is idempotent: calling it on an already-published
    // event still returns 200 and the status stays 'published'.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/publish", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let row: (String,) = sqlx::query_as("SELECT status FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(row.0, "published");
}

#[tokio::test]
async fn test_publish_draft_event_transitions_to_published() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "publish-draft-creator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    // Create a DRAFT event explicitly.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Draft Publish Event", "creator_id": {}, "status": "draft"}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();
    assert_eq!(event["status"], "draft");

    // Owner publishes it.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/publish", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, user_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let row: (String,) = sqlx::query_as("SELECT status FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(row.0, "published");
}

#[tokio::test]
async fn test_publish_event_non_owner_forbidden() {
    let pool = setup_test_pool().await;
    let (_creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "publish-event-creator", "Locked Publish").await;

    // Different user attempts publish.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "publish-event-intruder"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let intruder_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/publish", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"user_id": {}}}"#, intruder_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Status should be unchanged.
    let row: (String,) = sqlx::query_as("SELECT status FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(row.0, "published");
}

// --- Image upload / delete (Issue #178 Task 3) ---

/// Build a minimal but valid `multipart/form-data` body for a single file
/// field. The handler only ever looks at the "file" field; tests that want
/// to exercise other paths pass a different `field_name`.
fn multipart_image_body(
    boundary: &str,
    field_name: &str,
    filename: &str,
    content_type: &str,
    bytes: &[u8],
) -> Vec<u8> {
    let mut body = Vec::new();
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!(
            "Content-Disposition: form-data; name=\"{field_name}\"; filename=\"{filename}\"\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(format!("Content-Type: {content_type}\r\n\r\n").as_bytes());
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

/// Minimal PNG signature so the storage path is exercised even though
/// the handler does not decode the image.
fn minimal_png_bytes() -> Vec<u8> {
    vec![
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
        0x52,
    ]
}

#[tokio::test]
async fn test_upload_image_png_succeeds() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "TESTBOUNDARY";
    let body = multipart_image_body(
        boundary,
        "file",
        "tiny.png",
        "image/png",
        &minimal_png_bytes(),
    );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/images/upload")
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_text = body_to_string(resp.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body_text).unwrap();
    let url = json["url"].as_str().expect("response must include url");
    assert!(
        url.ends_with(".png"),
        "URL should keep the original extension: {url}"
    );
    // LocalFileStorage writes to ./test_uploads/<unique>.png — confirm.
    let filename = url.rsplit('/').next().unwrap();
    let path = std::path::Path::new("./test_uploads").join(filename);
    assert!(
        path.exists(),
        "uploaded file should exist on disk at {path:?}"
    );
    let _ = std::fs::remove_file(&path);
}

#[tokio::test]
async fn test_upload_image_jpg_succeeds() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "JPGBOUNDARY";
    // Real JPG SOI marker so the bytes look like a JPG.
    let bytes = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
    let body = multipart_image_body(boundary, "file", "pic.jpg", "image/jpeg", &bytes);

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/images/upload")
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_text = body_to_string(resp.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body_text).unwrap();
    let url = json["url"].as_str().expect("response must include url");
    assert!(url.ends_with(".jpg"));
    let filename = url.rsplit('/').next().unwrap();
    let path = std::path::Path::new("./test_uploads").join(filename);
    let _ = std::fs::remove_file(&path);
}

#[tokio::test]
async fn test_upload_image_wrong_content_type_rejected() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "TXTBOUNDARY";
    let body = multipart_image_body(boundary, "file", "doc.txt", "text/plain", b"hello world");

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/images/upload")
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_upload_image_too_large_rejected() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "BIGBOUNDARY";
    // 1.5 MB to exceed the 1 MiB cap.
    let big = vec![0u8; 1_572_864];
    let body = multipart_image_body(boundary, "file", "huge.png", "image/png", &big);

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/images/upload")
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_upload_image_no_file_field_rejected() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "NOFILEBOUNDARY";
    // Use a different field name; handler expects "file".
    let body = multipart_image_body(
        boundary,
        "attachment",
        "tiny.png",
        "image/png",
        &minimal_png_bytes(),
    );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/images/upload")
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_delete_image_succeeds() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "DELBOUNDARY";
    // Upload first.
    let body = multipart_image_body(
        boundary,
        "file",
        "todelete.png",
        "image/png",
        &minimal_png_bytes(),
    );
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/images/upload")
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_text = body_to_string(resp.into_body()).await;
    let url = serde_json::from_str::<serde_json::Value>(&body_text).unwrap()["url"]
        .as_str()
        .unwrap()
        .to_string();
    let filename = url.rsplit('/').next().unwrap().to_string();
    let path = std::path::Path::new("./test_uploads").join(&filename);
    assert!(path.exists());

    // Now delete via a fresh router.
    let pool2 = setup_test_pool().await;
    let app2 = backend::routes::create_router(pool2, test_storage());
    let resp = app2
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/api/v1/images/{}", filename))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_text = body_to_string(resp.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body_text).unwrap();
    assert_eq!(json["status"], "deleted");
    assert!(!path.exists(), "file should be gone after DELETE");
}

#[tokio::test]
async fn test_delete_image_nonexistent_is_idempotent() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());

    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/api/v1/images/does-not-exist.png")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    // LocalFileStorage::delete silently returns Ok for missing files.
    assert_eq!(resp.status(), StatusCode::OK);
}

// --- Admin endpoints (Issue #178 Task 3) ---

#[tokio::test]
async fn test_admin_get_user_details_returns_user() {
    let pool = setup_test_pool().await;
    let (user_id, _event_id) =
        create_test_user_and_event(pool.clone(), "admin-getuser", "Admin GetUser Event").await;

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/admin/users/{}", user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let user: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(user["id"], user_id);
    assert!(user["username"].as_str().is_some());
}

#[tokio::test]
async fn test_admin_get_user_details_nonexistent_returns_404() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/v1/admin/users/999999")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_admin_update_user_role_invalid_role_rejected() {
    let pool = setup_test_pool().await;
    // Use an admin to make the role change.
    let (admin_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-admin", "Admin Role Event").await;
    sqlx::query("UPDATE users SET role = 'admin' WHERE id = $1")
        .bind(admin_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    // Create a target user.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-role-target"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target_id, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "hacker"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_admin_update_user_role_moderator_forbidden() {
    let pool = setup_test_pool().await;
    // Create two users: a "moderator" trying to change roles, and a target.
    let (mod_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-mod", "Admin Mod Event").await;
    sqlx::query("UPDATE users SET role = 'moderator' WHERE id = $1")
        .bind(mod_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-role-target-2"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target_id, mod_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "moderator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_admin_update_user_role_succeeds() {
    let pool = setup_test_pool().await;
    let (admin_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-ok", "Admin Role Ok").await;
    sqlx::query("UPDATE users SET role = 'admin' WHERE id = $1")
        .bind(admin_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-role-promote"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
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

    // Verify the role was actually changed in the DB.
    let row: (String,) = sqlx::query_as("SELECT role FROM users WHERE id = $1")
        .bind(target_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(row.0, "moderator");
}

#[tokio::test]
async fn test_admin_list_all_merch_returns_array() {
    let pool = setup_test_pool().await;
    let (_user_id, event_id) =
        create_test_user_and_event(pool.clone(), "admin-listmerch", "Admin ListMerch").await;
    // Add one piece of merch so the list is non-empty.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"name": "Listed Merch", "group_name": "Group A"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/v1/admin/merch")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let items: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    assert!(!items.is_empty(), "list should be non-empty");
}

#[tokio::test]
async fn test_admin_list_all_matches_returns_array() {
    let pool = setup_test_pool().await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/v1/admin/matches")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let items: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    // Just verify it returns a valid array (content may be empty or populated).
    let _ = items.len();
}

#[tokio::test]
async fn test_admin_delete_merch_succeeds() {
    let pool = setup_test_pool().await;
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "admin-deleterch", "Admin DeleteMerch").await;

    // Create one piece of merch.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"name": "To Delete", "group_name": "Group A"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    // Promote user to admin for the delete.
    sqlx::query("UPDATE users SET role = 'admin' WHERE id = $1")
        .bind(user_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/merch/{}?user_id={}",
                    merch_id, user_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify the merch row is gone.
    let row: Option<(i32,)> = sqlx::query_as("SELECT id FROM merchandise WHERE id = $1")
        .bind(merch_id as i32)
        .fetch_optional(&pool)
        .await
        .unwrap();
    assert!(row.is_none(), "merch should be deleted");
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
    assert!(
        results
            .iter()
            .any(|r| r["title"] == "Searchable Convention")
    );
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

// --- Repository _conn methods (Issue #174) ---
//
// These tests exercise the new `_conn` repository methods
// directly. The key change from earlier failed attempts: the
// methods take `&mut sqlx::PgConnection`, NOT `&mut
// sqlx::Transaction`. The service / test opens the transaction
// and passes `&mut *tx` (a short-lived reborrow of `&mut
// PgConnection`); each future captures the reborrow, drops at end
// of await, and the next `&mut *tx` reborrow works cleanly. This
// is the standard sqlx pattern (see the issue's reference impl).

use backend::repositories::inventory::InventoryRepository as _InventoryRepoTrait;
use backend::repositories::match_::MatchRepository as _MatchRepoTrait;

/// Build a 2-user, 1-event, 1-PENDING-match setup. Returns
/// (user1_id, user2_id, match_id, merch_id_for_u1,
/// merch_id_for_u2). Each user also has a TRADE inventory row of
/// quantity 5 for their merch, so inventory deltas are exercisable.
async fn setup_pending_match_with_merch(pool: &PgPool) -> (i64, i64, i64, i32, i32) {
    // Create two users and an event.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "u1-conn"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let u1: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "u2-conn"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let u2: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Conn Event", "creator_id": {}}}"#,
                    u1
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    // One merch per user + a TRADE inventory row of qty 5.
    let mut merch_ids = Vec::new();
    for creator in [u1, u2] {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/v1/events/{}/merch", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"name": "M{creator}", "group_name": "G"}}"#
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let merch_id: i64 =
            serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await)
                .unwrap()["id"]
                .as_i64()
                .unwrap();
        sqlx::query(
            "INSERT INTO inventory (user_id, merch_id, status, quantity) VALUES ($1, $2, 'TRADE', 5)",
        )
        .bind(creator as i32)
        .bind(merch_id as i32)
        .execute(pool)
        .await
        .unwrap();
        merch_ids.push(merch_id as i32);
    }

    // Insert a PENDING match between the two users.
    let row: (i32,) = sqlx::query_as(
        "INSERT INTO matches (user1_id, user2_id, status) VALUES ($1, $2, 'PENDING') RETURNING id",
    )
    .bind(u1 as i32)
    .bind(u2 as i32)
    .fetch_one(pool)
    .await
    .unwrap();

    (u1, u2, row.0 as i64, merch_ids[0], merch_ids[1])
}

#[tokio::test]
async fn test_match_lock_for_update_returns_snapshot() {
    let pool = setup_test_pool().await;
    let (u1, u2, match_id, _, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    let snap = matches
        .lock_for_update(&mut *tx, match_id as i32)
        .await
        .unwrap()
        .expect("snapshot should exist for the seeded match");
    assert_eq!(snap.user1_id, u1 as i32);
    assert_eq!(snap.user2_id, u2 as i32);
    assert_eq!(snap.status, "PENDING");
    // tx.rollback() is called implicitly when `tx` drops.
}

#[tokio::test]
async fn test_match_lock_for_update_returns_none_for_missing() {
    let pool = setup_test_pool().await;
    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    let snap = matches
        .lock_for_update(&mut *tx, 999_999)
        .await
        .unwrap();
    assert!(snap.is_none());
}

#[tokio::test]
async fn test_match_set_status_writes_status() {
    let pool = setup_test_pool().await;
    let (_, _, match_id, _, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    matches
        .set_status(&mut *tx, match_id as i32, "OFFERED")
        .await
        .unwrap();
    let row: (String,) = sqlx::query_as("SELECT status FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    assert_eq!(row.0, "OFFERED");
}

#[tokio::test]
async fn test_match_set_offered_by_writes_column() {
    let pool = setup_test_pool().await;
    let (u1, _, match_id, _, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    matches
        .set_offered_by(&mut *tx, match_id as i32, u1 as i32)
        .await
        .unwrap();
    let row: (Option<i32>,) = sqlx::query_as("SELECT offered_by FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    assert_eq!(row.0, Some(u1 as i32));
}

#[tokio::test]
async fn test_match_insert_match_items_inserts_rows() {
    use backend::generated::ymatch::OfferItem;

    let pool = setup_test_pool().await;
    let (u1, _, match_id, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    let items = vec![
        OfferItem {
            merch_id: merch_for_u1,
            direction: "GIVE".to_string(),
            quantity: 2,
        },
        OfferItem {
            merch_id: merch_for_u1,
            direction: "RECEIVE".to_string(),
            quantity: 1,
        },
    ];
    matches
        .insert_match_items(&mut *tx, match_id as i32, u1 as i32, &items)
        .await
        .unwrap();
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM match_items WHERE match_id = $1")
        .bind(match_id as i32)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    assert_eq!(count.0, 2);
}

#[tokio::test]
async fn test_match_delete_match_items_removes_all() {
    let pool = setup_test_pool().await;
    let (u1, _, match_id, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    // Pre-seed two match_items rows.
    sqlx::query("INSERT INTO match_items (match_id, merch_id, owner_id, direction, quantity) VALUES ($1, $2, $3, 'GIVE', 1), ($1, $2, $3, 'RECEIVE', 2)")
        .bind(match_id as i32)
        .bind(merch_for_u1)
        .bind(u1 as i32)
        .execute(&pool)
        .await
        .unwrap();

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    matches
        .delete_match_items(&mut *tx, match_id as i32)
        .await
        .unwrap();
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM match_items WHERE match_id = $1")
        .bind(match_id as i32)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    assert_eq!(count.0, 0);
}

#[tokio::test]
async fn test_match_purge_other_pending_keeps_unrelated() {
    let pool = setup_test_pool().await;
    let (u1, u2, match_id, _, _) = setup_pending_match_with_merch(&pool).await;

    // Seed two extra PENDING matches between the same pair.
    sqlx::query("INSERT INTO matches (user1_id, user2_id, status) VALUES ($1, $2, 'PENDING'), ($1, $2, 'PENDING')")
        .bind(u1 as i32)
        .bind(u2 as i32)
        .execute(&pool)
        .await
        .unwrap();

    // Plus one unrelated PENDING match (must create the users too —
    // matches has a FK to users).
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "unrelated-user-a"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let u_a: i32 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap() as i32;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "unrelated-user-b"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let u_b: i32 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap() as i32;
    sqlx::query("INSERT INTO matches (user1_id, user2_id, status) VALUES ($1, $2, 'PENDING')")
        .bind(u_a)
        .bind(u_b)
        .execute(&pool)
        .await
        .unwrap();

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    matches
        .purge_other_pending(&mut *tx, match_id as i32, u1 as i32, u2 as i32)
        .await
        .unwrap();
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM matches WHERE status = 'PENDING'")
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    // The original (u1, u2) PENDING match AND the unrelated (u_a,
    // u_b) PENDING match should survive. The two extra (u1, u2)
    // matches were purged.
    assert_eq!(count.0, 2);
}

#[tokio::test]
async fn test_match_mark_inventory_applied_sets_user1_column() {
    let pool = setup_test_pool().await;
    let (_, _, match_id, _, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    matches
        .mark_inventory_applied(&mut *tx, match_id as i32, true)
        .await
        .unwrap();
    let row: (Option<chrono::DateTime<chrono::Utc>>,) =
        sqlx::query_as("SELECT user1_inventory_applied_at FROM matches WHERE id = $1")
            .bind(match_id as i32)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    assert!(row.0.is_some());
    let row: (Option<chrono::DateTime<chrono::Utc>>,) =
        sqlx::query_as("SELECT user2_inventory_applied_at FROM matches WHERE id = $1")
            .bind(match_id as i32)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    assert!(row.0.is_none());
}

#[tokio::test]
async fn test_match_mark_inventory_applied_errors_if_match_vanished() {
    let pool = setup_test_pool().await;

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    let result = matches
        .mark_inventory_applied(&mut *tx, 999_999, true)
        .await;
    assert!(result.is_err(), "mark should fail if match_id is missing");
    // tx will be rolled back when it drops.
}

#[tokio::test]
async fn test_inventory_apply_trade_delta_conn_decrement_only() {
    let pool = setup_test_pool().await;
    let (u1, _, _, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let inv = backend::repositories::inventory::InventoryRepository::new(pool.clone());
    inv.apply_trade_delta_conn(&mut *tx, u1 as i32, merch_for_u1, 2, 0)
        .await
        .unwrap();
    let qty: (i32,) = sqlx::query_as(
        "SELECT quantity FROM inventory WHERE user_id = $1 AND merch_id = $2 AND status = 'TRADE'",
    )
    .bind(u1 as i32)
    .bind(merch_for_u1)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    assert_eq!(qty.0, 3, "started at 5, decremented by 2");
    // No HAVE row created.
    let count: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM inventory WHERE user_id = $1 AND merch_id = $2 AND status = 'HAVE'",
    )
    .bind(u1 as i32)
    .bind(merch_for_u1)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    assert_eq!(count.0, 0);
}

#[tokio::test]
async fn test_inventory_apply_trade_delta_conn_increment_only() {
    let pool = setup_test_pool().await;
    let (u1, _, _, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let inv = backend::repositories::inventory::InventoryRepository::new(pool.clone());
    inv.apply_trade_delta_conn(&mut *tx, u1 as i32, merch_for_u1, 0, 4)
        .await
        .unwrap();
    let qty: (i32,) = sqlx::query_as(
        "SELECT quantity FROM inventory WHERE user_id = $1 AND merch_id = $2 AND status = 'HAVE'",
    )
    .bind(u1 as i32)
    .bind(merch_for_u1)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    assert_eq!(qty.0, 4);
    // TRADE row unchanged.
    let qty: (i32,) = sqlx::query_as(
        "SELECT quantity FROM inventory WHERE user_id = $1 AND merch_id = $2 AND status = 'TRADE'",
    )
    .bind(u1 as i32)
    .bind(merch_for_u1)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    assert_eq!(qty.0, 5);
}

#[tokio::test]
async fn test_multiple_conn_calls_share_one_transaction() {
    // This is the key test for the `&mut PgConnection` pattern:
    // several repo calls sharing one `tx` must each release their
    // borrow before the next call, and `tx.commit()` must work at
    // the end. If the future's borrow leaked past the call (the
    // NLL/Drop issue we hit earlier), this test would fail.
    let pool = setup_test_pool().await;
    let (u1, u2, match_id, _, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());

    matches
        .set_status(&mut *tx, match_id as i32, "OFFERED")
        .await
        .unwrap();
    matches
        .set_offered_by(&mut *tx, match_id as i32, u1 as i32)
        .await
        .unwrap();
    matches
        .set_status(&mut *tx, match_id as i32, "ACCEPTED")
        .await
        .unwrap();
    matches
        .purge_other_pending(&mut *tx, match_id as i32, u1 as i32, u2 as i32)
        .await
        .unwrap();

    // The call above would have failed to compile if the
    // `_conn` methods held the borrow past their `await` —
    // `&mut *tx` would be unusable for the next call.
    tx.commit()
        .await
        .expect("commit must succeed; if it doesn't, the future's borrow leaked");

    // Verify the post-state.
    let row: (String, Option<i32>) =
        sqlx::query_as("SELECT status, offered_by FROM matches WHERE id = $1")
            .bind(match_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(row.0, "ACCEPTED");
    assert_eq!(row.1, Some(u1 as i32));
}

// --- Trade Lifecycle E2E ---

// The test below (`test_trade_lifecycle_offer_accept_complete_apply`)
// is the behavioral contract for #174's repository refactor. It
// exercises every new `_in_tx` method transitively through
// `MatchLifecycleService`: offer -> set_status + insert_match_items
// -> set_offered_by; accept -> set_status + purge_other_pending;
// complete -> set_status; apply -> get_status_snapshot (read) +
// list_match_items (read) + apply_trade_delta_in_tx + mark_inventory_applied_in_tx.
// Direct unit-style tests for the new methods hit a known NLL /
// `Transaction: Drop` interaction in the borrow checker, so the
// E2E test is the safety net until that interaction is fixed
// (either by a stable `AsyncFnOnce` or a boxed-future pattern that
// cooperates with `Drop` types).

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

// --- Merchandise Groups (Issue #128, Phase 3) ---

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

// --- Issue #173 follow-up: extra tests for notification_counts and upsert shape ---

#[tokio::test]
async fn test_notification_counts_values() {
    // Set up: 2 users, 1 event, 2 merch items ("Card A", "Card B").
    // We'll create three matches in different states and verify the
    // counts endpoint returns the correct values for each side.
    let pool = setup_test_pool().await;
    let (u1, event_id) =
        create_test_user_and_event(pool.clone(), "notif-user-1", "Notif Event").await;
    let (u2, _) = create_test_user_and_event(pool.clone(), "notif-user-2", "Notif Event 2").await;

    // Create merch for each user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Card A", "group_name": "cards", "creator_id": {}}}"#,
                    u1
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let m_a: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let m_a_id = m_a["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Card B", "group_name": "cards", "creator_id": {}}}"#,
                    u2
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let m_b: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let m_b_id = m_b["id"].as_i64().unwrap();

    // Each user puts the other's card as WANT and their own as TRADE
    for (user_id, merch_id) in [(u1, m_b_id), (u2, m_a_id)] {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let _ = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(&format!("/api/v1/user/{}/inventory", user_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"user_id": {}, "merch_id": {}, "status": "WANT", "quantity": 1}}"#,
                        user_id, merch_id
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let _ = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(&format!("/api/v1/user/{}/inventory", user_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"user_id": {}, "merch_id": {}, "status": "TRADE", "quantity": 1}}"#,
                        user_id,
                        if user_id == u1 { m_a_id } else { m_b_id }
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
    }

    // Insert match directly (the matching algorithm is out of scope for
    // integration tests; it runs in a background task).
    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, status) VALUES ($1, $2, 'PENDING') RETURNING id",
    )
    .bind(u1)
    .bind(u2)
    .fetch_one(&pool)
    .await
    .unwrap();

    // ---- Query counts: 1 PENDING match exists, 0 messages ----
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u1))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["pending_matches"].as_i64().unwrap(), 1);
    assert_eq!(body["offers_in"].as_i64().unwrap(), 0);
    assert_eq!(body["accepted"].as_i64().unwrap(), 0);
    assert_eq!(body["unread_messages"].as_i64().unwrap(), 0);
    assert_eq!(body["total"].as_i64().unwrap(), 1);

    // User2 should also see pending=1 (they are a participant)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u2))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["pending_matches"].as_i64().unwrap(), 1);

    // ---- Transition to OFFERED via u1; send a message from u2 (unread for u1) ----
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "items": [{{"merch_id": {}, "direction": "GIVE", "quantity": 1}}]}}"#,
                    u1, m_a_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // u2 sends a message (unread for u1)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/messages", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"match_id": {}, "sender_id": {}, "content": "hi", "message_type": "TEXT"}}"#,
                    match_id, u2
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Query counts for u1 (the offerer): pending=0, offers_in=0 (u1 is the
    // offerer — they don't see "offers in" for their own offers),
    // unread=1 (u2 just sent a message that u1 hasn't read yet)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u1))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["pending_matches"].as_i64().unwrap(), 0);
    assert_eq!(body["offers_in"].as_i64().unwrap(), 0);
    assert_eq!(body["accepted"].as_i64().unwrap(), 0);
    assert_eq!(body["unread_messages"].as_i64().unwrap(), 1);
    assert_eq!(body["total"].as_i64().unwrap(), 1);

    // Query counts for u2 (the non-offerer): pending=0, offers_in=1 (u2 sees
    // u1's offer as an incoming offer), unread=0 (u2 sent the message; doesn't
    // count as unread for themselves)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u2))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["pending_matches"].as_i64().unwrap(), 0);
    assert_eq!(body["offers_in"].as_i64().unwrap(), 1);
    assert_eq!(body["accepted"].as_i64().unwrap(), 0);
    assert_eq!(body["unread_messages"].as_i64().unwrap(), 0);
    assert_eq!(body["total"].as_i64().unwrap(), 1);

    // ---- u1 marks their matches_read_at = NOW; unread should drop to 0 ----
    let _ = sqlx::query("UPDATE users SET matches_read_at = NOW() WHERE id = $1")
        .bind(u1)
        .execute(&pool)
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u1))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["unread_messages"].as_i64().unwrap(), 0);
    assert_eq!(body["total"].as_i64().unwrap(), 0); // all zeros for u1 now

    // ---- Transition OFFERED -> ACCEPTED: counts should change again ----
    // Note: the offer's "offeree" is u2; for ACCEPTED, the user_id in
    // the body is the offeree accepting.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let _ = app
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

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u2))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["pending_matches"].as_i64().unwrap(), 0);
    assert_eq!(body["offers_in"].as_i64().unwrap(), 0);
    assert_eq!(body["accepted"].as_i64().unwrap(), 1);
    assert_eq!(body["total"].as_i64().unwrap(), 1);
}

#[tokio::test]
async fn test_upsert_response_shape_preserved() {
    // Issue #173 item #5: the upsert response body should retain the
    // pre-Phase-4 shape: merch_name = Some("") (not None). The frontend
    // re-fetches via get_user_inventory (which joins merch) before
    // display, so the empty string never reaches the user; this
    // preserves the historical shape.
    let pool = setup_test_pool().await;
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "upsert-shape-creator", "Upsert Shape").await;

    // Create merch (so the inventory row's merch_id is valid)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Sticker", "group_name": "stickers", "creator_id": {}}}"#,
                    creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_id = merch["id"].as_i64().unwrap();

    // Now upsert inventory (this is the post-Phase-4 InventoryRepository
    // path that previously returned merch_name: None)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/user/inventory")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"user_id": {}, "merch_id": {}, "status": "HAVE", "quantity": 2}}"#,
                    creator_id, merch_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();

    // Verify the shape: merch_name must be present, equal to "",
    // and photo_url + group_name must be absent (consistent with old
    // behavior).
    // Verify the shape:
    // - merch_name must be present and equal to "" (not null, not missing)
    // - photo_url and group_name are optional fields; when None, the proto3
    //   JSON encoding omits them from the response body (not serialized as
    //   null). So `body.get("photo_url")` returns Value::Null and the key
    //   is absent — both shapes are acceptable per the test.
    assert!(
        body.get("merch_name").is_some(),
        "merch_name must be present"
    );
    assert_eq!(
        body["merch_name"].as_str().unwrap(),
        "",
        "merch_name must be Some(\"\") not null"
    );
    let photo_url = body.get("photo_url");
    assert!(
        photo_url.is_none() || photo_url.and_then(|v| v.as_str()).is_none(),
        "photo_url must be absent or null, got: {:?}",
        photo_url
    );
    let group_name = body.get("group_name");
    assert!(
        group_name.is_none() || group_name.and_then(|v| v.as_str()).is_none(),
        "group_name must be absent or null, got: {:?}",
        group_name
    );
    // After the TRUNCATE ... RESTART IDENTITY in setup_test_pool, the
    // first inserted inventory row gets id=1.
    assert_eq!(body["id"].as_i64().unwrap(), 1);
    assert_eq!(body["user_id"].as_i64().unwrap(), creator_id);
    assert_eq!(body["merch_id"].as_i64().unwrap(), merch_id);
    assert_eq!(body["status"].as_str().unwrap(), "HAVE");
    assert_eq!(body["quantity"].as_i64().unwrap(), 2);
}
