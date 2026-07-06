use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;

/// Helper to read an integer from a JSON object, treating a missing
/// proto3-default-zero field as 0.
fn json_i64(value: &serde_json::Value, key: &str) -> i64 {
    value.get(key).and_then(|v| v.as_i64()).unwrap_or(0)
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

#[sqlx::test]
async fn test_root_endpoint(pool: PgPool) {
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

#[sqlx::test]
async fn test_system_status(pool: PgPool) {
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

#[sqlx::test]
async fn test_guest_login_creates_user(pool: PgPool) {
    let app = backend::routes::create_router(pool, test_storage());

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"uuid": "test-uuid-1234", "deviceToken": "tok123"}"#,
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

#[sqlx::test]
async fn test_guest_login_returns_existing_user(pool: PgPool) {
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

#[sqlx::test]
async fn test_signup_and_login(pool: PgPool) {
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

#[sqlx::test]
async fn test_list_users(pool: PgPool) {
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

#[sqlx::test]
async fn test_create_and_list_events(pool: PgPool) {
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

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;

    // Create event
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Test Event", "creatorId": {}}}"#,
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
    assert_eq!(event["activeParticipants"].as_i64().unwrap(), 0);

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

#[sqlx::test]
async fn test_event_favorite_toggle_inserts_when_absent(pool: PgPool) {
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
                    r#"{{"userId": {}, "isFavorite": true}}"#,
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

#[sqlx::test]
async fn test_event_favorite_toggle_removes_when_present(pool: PgPool) {
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
                        r#"{{"userId": {}, "isFavorite": true}}"#,
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

#[sqlx::test]
async fn test_event_favorite_per_user_independence(pool: PgPool) {
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
                    r#"{{"userId": {}, "isFavorite": true}}"#,
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

#[sqlx::test]
async fn test_group_favorite_toggle_and_list(pool: PgPool) {
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
                    r#"{{"userId": {}, "groupName": "Books", "isFavorite": true}}"#,
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
    assert_eq!(groups[0]["groupName"], "Books");
    assert_eq!(groups[0]["eventId"], event_id);
    assert_eq!(groups[0]["eventName"], "Group Fav Event");
}

#[sqlx::test]
async fn test_group_favorite_toggle_removes(pool: PgPool) {
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
                        r#"{{"userId": {}, "groupName": "Music", "isFavorite": true}}"#,
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

#[sqlx::test]
async fn test_event_view_register_inserts(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "view-register-user", "View Register Event").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/view", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user_id)))
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

#[sqlx::test]
async fn test_event_view_register_is_idempotent(pool: PgPool) {
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
                    .body(Body::from(format!(r#"{{"userId": {}}}"#, user_id)))
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

#[sqlx::test]
async fn test_event_view_per_user_and_per_event(pool: PgPool) {
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

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_b, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "View Iso B", "creatorId": {}}}"#,
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user_a)))
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user_b)))
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

#[sqlx::test]
async fn test_update_event_owner_succeeds(pool: PgPool) {
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
                    r#"{{"userId": {}, "name": "Updated Name"}}"#,
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

#[sqlx::test]
async fn test_update_event_non_owner_forbidden(pool: PgPool) {
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
                    r#"{{"userId": {}, "name": "Pwned"}}"#,
                    intruder_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_publish_event_owner_succeeds(pool: PgPool) {
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user_id)))
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

#[sqlx::test]
async fn test_publish_draft_event_transitions_to_published(pool: PgPool) {
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

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;

    // Create a DRAFT event explicitly.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Draft Publish Event", "creatorId": {}, "status": "draft"}}"#,
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user_id)))
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

#[sqlx::test]
async fn test_publish_event_non_owner_forbidden(pool: PgPool) {
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, intruder_id)))
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

#[sqlx::test]
async fn test_upload_image_png_succeeds(pool: PgPool) {
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

#[sqlx::test]
async fn test_upload_image_jpg_succeeds(pool: PgPool) {
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

#[sqlx::test]
async fn test_upload_image_wrong_content_type_rejected(pool: PgPool) {
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

#[sqlx::test]
async fn test_upload_image_too_large_rejected(pool: PgPool) {
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

#[sqlx::test]
async fn test_upload_image_no_file_field_rejected(pool: PgPool) {
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

#[sqlx::test]
async fn test_delete_image_succeeds(pool: PgPool) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
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
    let pool2 = pool.clone();
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

#[sqlx::test]
async fn test_delete_image_nonexistent_is_idempotent(pool: PgPool) {
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

#[sqlx::test]
async fn test_admin_get_user_details_returns_user(pool: PgPool) {
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

#[sqlx::test]
async fn test_admin_get_user_details_nonexistent_returns_404(pool: PgPool) {
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

#[sqlx::test]
async fn test_admin_update_user_role_invalid_role_rejected(pool: PgPool) {
    // Use an admin to make the role change.
    let (admin_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-admin", "Admin Role Event").await;
    grant_global_role(&pool, admin_id, "admin").await;

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

#[sqlx::test]
async fn test_admin_update_user_role_moderator_forbidden(pool: PgPool) {
    // Create two users: a "moderator" trying to change roles, and a target.
    let (mod_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-mod", "Admin Mod Event").await;
    grant_global_role(&pool, mod_id, "moderator").await;

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

#[sqlx::test]
async fn test_admin_update_user_role_succeeds(pool: PgPool) {
    let (admin_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-ok", "Admin Role Ok").await;
    grant_global_role(&pool, admin_id, "admin").await;

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

#[sqlx::test]
async fn test_admin_list_all_merch_returns_array(pool: PgPool) {
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
                    r#"{"name": "Listed Merch", "groupName": "Group A"}"#,
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

#[sqlx::test]
async fn test_admin_list_all_matches_returns_array(pool: PgPool) {
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

#[sqlx::test]
async fn test_admin_delete_merch_succeeds(pool: PgPool) {
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
                    r#"{"name": "To Delete", "groupName": "Group A"}"#,
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
    grant_global_role(&pool, user_id, "admin").await;

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

#[sqlx::test]
async fn test_create_and_list_merch(pool: PgPool) {
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

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Merch Event", "creatorId": {}}}"#,
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
                    r#"{"name": "Test Item", "groupName": "Group A"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(merch["name"].as_str().unwrap(), "Test Item");
    assert_eq!(merch["eventId"].as_i64().unwrap(), event_id);

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

// --- Merchandise name uniqueness (Issue #299) ---

#[sqlx::test]
async fn test_create_merch_duplicate_name_in_same_group_rejected(pool: PgPool) {
    let (_user_id, event_id) =
        create_test_user_and_event(pool.clone(), "dup-name-user", "Dup Name Event").await;

    // First "a" in group G succeeds.
    let _ = create_merch(&pool, event_id, "a", "G").await;

    // Second "a" in the SAME group G must be rejected with 400.
    let body = r#"{"name": "a", "groupName": "G"}"#;
    let resp = post_json(&pool, &format!("/api/v1/events/{}/merch", event_id), body).await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let msg = body_to_string(resp.into_body()).await;
    assert!(
        msg.contains("already exists"),
        "expected duplicate-name message, got: {msg}"
    );
}

#[sqlx::test]
async fn test_create_merch_same_name_across_different_groups_succeeds(pool: PgPool) {
    let (_user_id, event_id) =
        create_test_user_and_event(pool.clone(), "cross-group-user", "Cross Group Event").await;

    // "a" in group G1 succeeds.
    let _ = create_merch(&pool, event_id, "a", "G1").await;

    // The same name "a" in a DIFFERENT group G2 must also succeed.
    let merch_id = create_merch(&pool, event_id, "a", "G2").await;
    assert!(merch_id > 0);
}

#[sqlx::test]
async fn test_create_merch_duplicate_name_after_soft_delete_reusable(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "softdel-reuse-user", "SoftDel Reuse Event").await;

    // Create "a" (owned by the user so we can later manage it).
    let body = format!(
        r#"{{"name": "a", "groupName": "G", "creatorId": {}}}"#,
        user_id
    );
    let resp = post_json(&pool, &format!("/api/v1/events/{}/merch", event_id), &body).await;
    assert_eq!(resp.status(), StatusCode::OK);
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_id = merch["id"].as_i64().unwrap();

    // Add inventory so delete takes the soft-delete branch (is_deleted = true).
    set_inventory(&pool, user_id, merch_id, "HAVE", 1).await;

    // Soft-delete the merch.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch_id, user_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // The soft-deleted row must not occupy the name: re-creating "a" succeeds.
    let merch_id2 = create_merch(&pool, event_id, "a", "G").await;
    assert!(merch_id2 > 0);
}

#[sqlx::test]
async fn test_update_merch_rename_to_existing_name_rejected(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "rename-user", "Rename Event").await;

    // Create "a" and "b" in the same group, both owned by the user so the
    // update-merch ownership check passes.
    for name in ["a", "b"] {
        let body = format!(
            r#"{{"name": "{}", "groupName": "G", "creatorId": {}}}"#,
            name, user_id
        );
        let resp = post_json(&pool, &format!("/api/v1/events/{}/merch", event_id), &body).await;
        assert_eq!(resp.status(), StatusCode::OK, "create {name} failed");
    }

    // List to find the merch id for "b".
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!(
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
    let b_id = items
        .iter()
        .find(|m| m["name"].as_str() == Some("b"))
        .expect("item 'b' should exist")["id"]
        .as_i64()
        .unwrap();

    // Rename "b" → "a" (collides with the existing "a" in group G) → 400.
    let body = format!(r#"{{"userId": {}, "name": "a"}}"#, user_id);
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}/merch/{}", event_id, b_id))
                .header("content-type", "application/json")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let msg = body_to_string(resp.into_body()).await;
    assert!(
        msg.contains("already exists"),
        "expected duplicate-name message, got: {msg}"
    );
}

// --- Inventory ---

#[sqlx::test]
async fn test_inventory_upsert(pool: PgPool) {
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
    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Inv Event", "creatorId": {}}}"#,
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
                .body(Body::from(r#"{"name": "Inv Item", "groupName": "Test"}"#))
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
                    r#"{{"userId": {}, "merchId": {}, "status": "HAVE", "quantity": 2}}"#,
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
                    r#"{{"userId": {}, "merchId": {}, "status": "HAVE", "quantity": 5}}"#,
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

#[sqlx::test]
async fn test_update_match_status_validation(pool: PgPool) {
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

#[sqlx::test]
async fn test_search_returns_results(pool: PgPool) {
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

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("POST")
            .uri("/api/v1/events")
            .header("content-type", "application/json")
            .body(Body::from(format!(
                r#"{{"name": "Searchable Convention", "creatorId": {}}}"#,
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

#[sqlx::test]
async fn test_search_excludes_draft_events(pool: PgPool) {
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
    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("POST")
            .uri("/api/v1/events")
            .header("content-type", "application/json")
            .body(Body::from(format!(
                r#"{{"name": "DraftSearchTest Event", "creatorId": {}, "status": "draft"}}"#,
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

#[sqlx::test]
async fn test_admin_delete_event(pool: PgPool) {
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
    grant_global_role(&pool, user_id, "admin").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Delete Me", "creatorId": {}}}"#,
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

#[sqlx::test]
async fn test_messages_empty_list(pool: PgPool) {
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

    // Insert match directly. ADR 0001: matches carry (event_id, group_name).
    let event_row: (i32,) = sqlx::query_as(
        "INSERT INTO events (name, creator_id) VALUES ('Match Msg Event', $1) RETURNING id",
    )
    .bind(u1_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    let match_row = sqlx::query(
        "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name)
         VALUES ($1, $2, 'PENDING', $3, 'MsgGroup') RETURNING id",
    )
    .bind(u1_id as i32)
    .bind(u2_id as i32)
    .bind(event_row.0)
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
                    r#"{{"matchId": {}, "senderId": {}, "content": "Hello!"}}"#,
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

#[sqlx::test]
async fn test_banned_user_cannot_login(pool: PgPool) {
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

#[sqlx::test]
async fn test_admin_ban_unban_user(pool: PgPool) {
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
    grant_global_role(&pool, admin_id, "admin").await;

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

#[sqlx::test]
async fn test_non_admin_cannot_ban(pool: PgPool) {
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

#[sqlx::test]
async fn test_update_user_role(pool: PgPool) {
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
    grant_global_role(&pool, admin_id, "admin").await;

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

#[sqlx::test]
async fn test_draft_event_visibility(pool: PgPool) {
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
    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, creator_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Draft Event", "creatorId": {}, "status": "draft"}}"#,
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, creator_id)))
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

#[sqlx::test]
async fn test_draft_merch_visibility(pool: PgPool) {
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
    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Merch Draft Event", "creatorId": {}}}"#,
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
                    r#"{{"name": "Draft Item", "groupName": "Test", "creatorId": {}, "status": "draft"}}"#,
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

// --- Soft Delete Tests ---

#[sqlx::test]
async fn test_soft_delete_merch_with_inventory(pool: PgPool) {
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
    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "SoftDel Event", "creatorId": {}}}"#,
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
                    r#"{{"name": "SoftDel Item", "groupName": "Test", "creatorId": {}}}"#,
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
                r#"{{"userId": {}, "merchId": {}, "status": "HAVE", "quantity": 3}}"#,
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

#[sqlx::test]
async fn test_hard_delete_merch_without_inventory(pool: PgPool) {
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

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "HardDel Event", "creatorId": {}}}"#,
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
                    r#"{{"name": "HardDel Item", "groupName": "Test", "creatorId": {}}}"#,
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

#[sqlx::test]
async fn test_user_response_includes_role(pool: PgPool) {
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
    assert_eq!(user["isBanned"].as_bool().unwrap(), false);
}

#[sqlx::test]
async fn test_banned_user_cannot_create_event(pool: PgPool) {
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

    // Promote to moderator so the user would otherwise pass the new
    // `event.create` permission check (ADR 0004 §4). This isolates the ban
    // check: the 403 below must come from being banned, not from lacking
    // event.create.
    grant_global_role(&pool, user_id, "moderator").await;

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
                    r#"{{"name": "Banned Event", "creatorId": {}}}"#,
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

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, u1, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Conn Event", "creatorId": {}}}"#,
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
                        r#"{{"name": "M{creator}", "groupName": "G"}}"#
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

    // Insert a PENDING match between the two users. ADR 0001: scope to the
    // group the merch belongs to ("G", same event_id as the merch above).
    let row: (i32,) = sqlx::query_as(
        "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name)
         VALUES ($1, $2, 'PENDING', $3, 'G') RETURNING id",
    )
    .bind(u1 as i32)
    .bind(u2 as i32)
    .bind(event_id as i32)
    .fetch_one(pool)
    .await
    .unwrap();

    (u1, u2, row.0 as i64, merch_ids[0], merch_ids[1])
}

#[sqlx::test]
async fn test_match_lock_for_update_returns_snapshot(pool: PgPool) {
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

#[sqlx::test]
async fn test_match_lock_for_update_returns_none_for_missing(pool: PgPool) {
    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    let snap = matches.lock_for_update(&mut *tx, 999_999).await.unwrap();
    assert!(snap.is_none());
}

#[sqlx::test]
async fn test_match_set_status_writes_status(pool: PgPool) {
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

#[sqlx::test]
async fn test_match_set_offered_by_writes_column(pool: PgPool) {
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

#[sqlx::test]
async fn test_match_upsert_legs_inserts_and_updates_rows(pool: PgPool) {
    use backend::generated::ymatch::OfferItem;

    let (u1, u2, match_id, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    // Two absolute legs with different givers — distinct rows under the
    // (match_id, giver_user_id, merch_id) unique key.
    let items = vec![
        OfferItem {
            merch_id: merch_for_u1,
            giver_user_id: u1 as i32,
            quantity: 2,
        },
        OfferItem {
            merch_id: merch_for_u1,
            giver_user_id: u2 as i32,
            quantity: 1,
        },
    ];
    matches
        .upsert_legs(&mut *tx, match_id as i32, &items)
        .await
        .unwrap();
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM match_items WHERE match_id = $1")
        .bind(match_id as i32)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    assert_eq!(count.0, 2);

    // Re-submitting an existing (giver, merch) leg upserts — no new row.
    let update = vec![OfferItem {
        merch_id: merch_for_u1,
        giver_user_id: u1 as i32,
        quantity: 5,
    }];
    matches
        .upsert_legs(&mut *tx, match_id as i32, &update)
        .await
        .unwrap();
    let count2: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM match_items WHERE match_id = $1")
        .bind(match_id as i32)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    assert_eq!(count2.0, 2);
    let qty: (i32,) = sqlx::query_as(
        "SELECT quantity FROM match_items WHERE match_id = $1 AND giver_user_id = $2",
    )
    .bind(match_id as i32)
    .bind(u1 as i32)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    assert_eq!(qty.0, 5);
}

#[sqlx::test]
async fn test_match_delete_match_items_removes_all(pool: PgPool) {
    let (u1, u2, match_id, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    // Pre-seed two match_items legs (absolute: giver_user_id).
    sqlx::query(
        "INSERT INTO match_items (match_id, merch_id, giver_user_id, quantity) \
         VALUES ($1, $2, $3, 1), ($1, $2, $4, 2)",
    )
    .bind(match_id as i32)
    .bind(merch_for_u1)
    .bind(u1 as i32)
    .bind(u2 as i32)
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

#[sqlx::test]
async fn test_match_mark_inventory_applied_sets_user1_column(pool: PgPool) {
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

#[sqlx::test]
async fn test_match_mark_inventory_applied_errors_if_match_vanished(pool: PgPool) {
    let mut tx = pool.begin().await.unwrap();
    let matches = backend::repositories::match_::MatchRepository::new(pool.clone());
    let result = matches
        .mark_inventory_applied(&mut *tx, 999_999, true)
        .await;
    assert!(result.is_err(), "mark should fail if match_id is missing");
    // tx will be rolled back when it drops.
}

#[sqlx::test]
async fn test_inventory_apply_trade_delta_decrement_only(pool: PgPool) {
    let (u1, _, _, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let inv = backend::repositories::inventory::InventoryRepository::new(pool.clone());
    inv.apply_trade_delta(&mut *tx, u1 as i32, merch_for_u1, 2, 0)
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

#[sqlx::test]
async fn test_inventory_apply_trade_delta_increment_only(pool: PgPool) {
    let (u1, _, _, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    let mut tx = pool.begin().await.unwrap();
    let inv = backend::repositories::inventory::InventoryRepository::new(pool.clone());
    inv.apply_trade_delta(&mut *tx, u1 as i32, merch_for_u1, 0, 4)
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

#[sqlx::test]
async fn test_multiple_conn_calls_share_one_transaction(pool: PgPool) {
    // This is the key test for the `&mut PgConnection` pattern:
    // several repo calls sharing one `tx` must each release their
    // borrow before the next call, and `tx.commit()` must work at
    // the end. If the future's borrow leaked past the call (the
    // NLL/Drop issue we hit earlier), this test would fail.
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
        .delete_match_items(&mut *tx, match_id as i32)
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
// -> set_offered_by; accept -> set_status; complete -> set_status; apply
// -> get_status_snapshot (read) +
// list_match_items (read) + apply_trade_delta_in_tx + mark_inventory_applied_in_tx.
// Direct unit-style tests for the new methods hit a known NLL /
// `Transaction: Drop` interaction in the borrow checker, so the
// E2E test is the safety net until that interaction is fixed
// (either by a stable `AsyncFnOnce` or a boxed-future pattern that
// cooperates with `Drop` types).

#[sqlx::test]
async fn test_trade_lifecycle_offer_accept_complete_apply(pool: PgPool) {
    // 1. Create two users
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"uuid": "user1-lifecycle-test", "deviceToken": "tok1"}"#,
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
                    r#"{"uuid": "user2-lifecycle-test", "deviceToken": "tok2"}"#,
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
    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user1_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Trade Test Event", "creatorId": {}}}"#,
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
                .body(Body::from(
                    r#"{"name": "Card A", "photoUrl": "", "groupName": "Cards"}"#,
                ))
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
                .body(Body::from(
                    r#"{"name": "Card B", "photoUrl": "", "groupName": "Cards"}"#,
                ))
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
                        r#"{{"userId": {}, "merchId": {}, "status": "{}", "quantity": 1}}"#,
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
        matches[0]["inventoryApplied"].is_null() || matches[0]["inventoryApplied"] == false,
        "inventory_applied should be false/null for new match"
    );

    // 6. User1 proposes: give Card A (giver=user1), receive Card B (giver=user2).
    //    1:1 legs → balanced.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "items": [
                        {{"merchId": {}, "giverUserId": {}, "quantity": 1}},
                        {{"merchId": {}, "giverUserId": {}, "quantity": 1}}
                    ]}}"#,
                    user1_id, merch_a_id, user1_id, merch_b_id, user2_id
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
    assert_eq!(matches[0]["offeredBy"], user1_id);

    // 7. User2 (non-proposer) accepts the balanced proposal
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/status", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"status": "ACCEPTED", "userId": {}}}"#,
                    user2_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // 8. Complete (either participant may complete)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/status", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"status": "COMPLETED", "userId": {}}}"#,
                    user1_id
                )))
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user1_id)))
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
        .find(|i| i["merchId"] == merch_a_id && i["status"] == "TRADE");
    assert!(
        u1_trade_a
            .as_ref()
            .and_then(|i| i.get("quantity").and_then(|v| v.as_i64()))
            .unwrap_or(0)
            == 0,
        "User1 TRADE Card A should be 0"
    );
    let u1_have_b = inv1
        .iter()
        .find(|i| i["merchId"] == merch_b_id && i["status"] == "HAVE");
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
        .find(|i| i["merchId"] == merch_b_id && i["status"] == "TRADE");
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
    assert_eq!(matches[0]["inventoryApplied"], true);

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
        matches2[0]["inventoryApplied"].is_null() || matches2[0]["inventoryApplied"] == false,
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user1_id)))
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user2_id)))
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
        .find(|i| i["merchId"] == merch_b_id && i["status"] == "TRADE");
    assert!(
        u2_trade_b
            .as_ref()
            .and_then(|i| i.get("quantity").and_then(|v| v.as_i64()))
            .unwrap_or(0)
            == 0,
        "User2 TRADE Card B should be 0"
    );
    let u2_have_a = inv2
        .iter()
        .find(|i| i["merchId"] == merch_a_id && i["status"] == "HAVE");
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
                .body(Body::from(format!(r#"{{"userId": {}}}"#, user2_id)))
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

#[sqlx::test]
async fn test_offer_on_non_pending_match_rejected(pool: PgPool) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/matches/99999/offer")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"userId": 1, "items": [{"merchId": 1, "giverUserId": 1, "quantity": 1}]}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    // 422 because JSON parsing precedes the route match for typed extractors,
    // or 404 if the route doesn't match - either way, not 200
    assert_ne!(resp.status(), StatusCode::OK);
}

/// Create two users, an event, two merch items, matching inventory, and run the
/// matcher so the users have a PENDING match. Returns
/// (match_id, user1_id, user2_id, merch_a_id, merch_b_id).
async fn setup_pending_trade_match(pool: PgPool) -> (i64, i64, i64, i64, i64) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"uuid": "user1-camelcase-test", "deviceToken": "tok1"}"#,
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
                    r#"{"uuid": "user2-camelcase-test", "deviceToken": "tok2"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let user2: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user2_id = user2["id"].as_i64().unwrap();

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user1_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "CamelCase Trade Event", "creatorId": {}}}"#,
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

    async fn create_merch(pool: &PgPool, event_id: i64, name: &str) -> i64 {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(&format!("/api/v1/events/{}/merch", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"name": "{}", "photoUrl": "", "groupName": "Cards"}}"#,
                        name
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let merch: serde_json::Value =
            serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
        merch["id"].as_i64().unwrap()
    }

    let merch_a_id = create_merch(&pool, event_id, "Card A").await;
    let merch_b_id = create_merch(&pool, event_id, "Card B").await;

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
                        r#"{{"userId": {}, "merchId": {}, "status": "{}", "quantity": 1}}"#,
                        uid, mid, status
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    let matches_created = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("Matching algorithm failed");
    assert!(matches_created >= 1, "Should create at least 1 match");

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

    (match_id, user1_id, user2_id, merch_a_id, merch_b_id)
}

#[sqlx::test]
async fn test_offer_with_frontend_proto3_json(pool: PgPool) {
    let (match_id, user1_id, user2_id, merch_a_id, merch_b_id) =
        setup_pending_trade_match(pool.clone()).await;

    // Frontend sends proto3 JSON (camelCase) from OfferTradeRequest.toProto3Json().
    // GIVE Card A (giver=user1) + RECEIVE Card B (giver=user2) → balanced 1:1.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "items": [
                        {{"merchId": {}, "giverUserId": {}, "quantity": 1}},
                        {{"merchId": {}, "giverUserId": {}, "quantity": 1}}
                    ]}}"#,
                    user1_id, merch_a_id, user1_id, merch_b_id, user2_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let app = backend::routes::create_router(pool, test_storage());
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
    assert_eq!(matches[0]["offeredBy"], user1_id);
}

/// Like [`setup_pending_trade_match`] but lets the caller pick the inventory
/// quantities, so a trade side can hold more units than the other side wants
/// (the precondition for the over-quantity cap test, issue #294).
///
/// Layout (mirrors `setup_pending_trade_match`):
///   user1: TRADE Card A (qty `u1_trade`), WANT Card B (qty `u1_want`)
///   user2: TRADE Card B (qty `u2_trade`), WANT Card A (qty `u2_want`)
async fn setup_pending_trade_match_quantities(
    pool: PgPool,
    u1_trade: i32,
    u1_want: i32,
    u2_trade: i32,
    u2_want: i32,
) -> (i64, i64, i64, i64, i64) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"uuid": "user1-qty-cap-test", "deviceToken": "tok1"}"#,
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
                    r#"{"uuid": "user2-qty-cap-test", "deviceToken": "tok2"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let user2: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user2_id = user2["id"].as_i64().unwrap();

    // ADR 0004 §4: event creation is moderator/admin-only.
    grant_global_role(&pool, user1_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Qty Cap Trade Event", "creatorId": {}}}"#,
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

    async fn create_merch(pool: &PgPool, event_id: i64, name: &str) -> i64 {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(&format!("/api/v1/events/{}/merch", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"name": "{}", "photoUrl": "", "groupName": "Cards"}}"#,
                        name
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let merch: serde_json::Value =
            serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
        merch["id"].as_i64().unwrap()
    }

    let merch_a_id = create_merch(&pool, event_id, "Card A").await;
    let merch_b_id = create_merch(&pool, event_id, "Card B").await;

    for (uid, mid, status, qty) in [
        (user1_id, merch_a_id, "TRADE", u1_trade),
        (user1_id, merch_b_id, "WANT", u1_want),
        (user2_id, merch_b_id, "TRADE", u2_trade),
        (user2_id, merch_a_id, "WANT", u2_want),
    ] {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/user/inventory")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"userId": {}, "merchId": {}, "status": "{}", "quantity": {}}}"#,
                        uid, mid, status, qty
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    let matches_created = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("Matching algorithm failed");
    assert!(matches_created >= 1, "Should create at least 1 match");

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

    (match_id, user1_id, user2_id, merch_a_id, merch_b_id)
}

/// Issue #294: an offer whose per-leg quantity exceeds the matched/wanted
/// quantity on the receiving side must be rejected (400), while an offer at
/// or under the want quantity still succeeds. Legs are absolute (#297): the
/// receiver of a leg is the non-giver, so GIVE is capped by the opponent's
/// want and RECEIVE (giver=opponent) is capped by the requester's own want.
#[sqlx::test]
async fn test_offer_over_want_quantity_rejected(pool: PgPool) {
    // user1 TRADE Card A x2, WANT Card B x1
    // user2 TRADE Card B x2, WANT Card A x1
    // Both want quantities are 1, so any offer of 2 units must be capped.
    let (match_id, user1_id, user2_id, merch_a_id, merch_b_id) =
        setup_pending_trade_match_quantities(pool.clone(), 2, 1, 2, 1).await;

    // The match listing must surface the capped (LEAST of trade and want)
    // quantities so the offer dialog cannot even present more than the
    // receiving side wants. userHaves: user1 TRADE Card A (2) capped by
    // user2 WANT (1) -> 1. userWants: user2 TRADE Card B (2) capped by
    // user1 WANT (1) -> 1 (now populated — #295 fixed in this PR).
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
    let haves = matches[0]["userHaves"].as_array().unwrap();
    let have_a = haves
        .iter()
        .find(|i| i["merchId"].as_i64() == Some(merch_a_id))
        .unwrap();
    assert_eq!(have_a["quantity"].as_i64().unwrap(), 1);
    let wants = matches[0]["userWants"].as_array().unwrap();
    let want_b = wants
        .iter()
        .find(|i| i["merchId"].as_i64() == Some(merch_b_id))
        .unwrap();
    assert_eq!(want_b["quantity"].as_i64().unwrap(), 1);

    // GIVE Card A x2 (giver=user1) exceeds user2's WANT of Card A (x1) -> 400.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "items": [
                        {{"merchId": {}, "giverUserId": {}, "quantity": 2}}
                    ]}}"#,
                    user1_id, merch_a_id, user1_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

    // Match must still be PENDING after a rejected offer (no state mutation).
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
    assert_eq!(matches[0]["status"], "PENDING");

    // RECEIVE Card B x2 (giver=user2) exceeds user1's WANT of Card B (x1) -> 400.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "items": [
                        {{"merchId": {}, "giverUserId": {}, "quantity": 2}}
                    ]}}"#,
                    user1_id, merch_b_id, user2_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

    // An offer capped to the want quantity (1 each) still succeeds and is
    // balanced (user1 gives A x1, user2 gives B x1).
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "items": [
                        {{"merchId": {}, "giverUserId": {}, "quantity": 1}},
                        {{"merchId": {}, "giverUserId": {}, "quantity": 1}}
                    ]}}"#,
                    user1_id, merch_a_id, user1_id, merch_b_id, user2_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let app = backend::routes::create_router(pool, test_storage());
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
}

/// Issue #297: the negotiation state machine. A give-only opening proposal is
/// unbalanced and cannot be accepted; the proposer cannot accept or counter
/// their own; the non-proposer counter-offers to add the complementary leg
/// (accumulating), making it balanced, and then the (new) non-proposer accepts.
#[sqlx::test]
async fn test_trade_negotiation_counter_offer_and_balance(pool: PgPool) {
    // user1 TRADE A WANT B; user2 TRADE B WANT A.
    let (match_id, user1_id, user2_id, merch_a_id, merch_b_id) =
        setup_pending_trade_match(pool.clone()).await;

    let post_offer = |pool: &PgPool, uid: i64, items: &str| {
        let pool = pool.clone();
        let body = format!(r#"{{"userId": {}, "items": [{}]}}"#, uid, items);
        async move {
            let app = backend::routes::create_router(pool, test_storage());
            app.oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/v1/matches/{}/offer", match_id))
                    .header("content-type", "application/json")
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap()
        }
    };
    let post_status = |pool: &PgPool, uid: i64, status: &str| {
        let pool = pool.clone();
        let body = format!(r#"{{"status": "{}", "userId": {}}}"#, status, uid);
        async move {
            let app = backend::routes::create_router(pool, test_storage());
            app.oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/v1/matches/{}/status", match_id))
                    .header("content-type", "application/json")
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap()
        }
    };
    let fetch_matches = |pool: &PgPool, uid: i64| {
        let pool = pool.clone();
        async move {
            let app = backend::routes::create_router(pool, test_storage());
            let resp = app
                .oneshot(
                    Request::builder()
                        .uri(format!("/api/v1/matches/user/{}", uid))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            let matches: Vec<serde_json::Value> =
                serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
            matches[0].clone()
        }
    };

    // 1. user1 opens give-only (unbalanced): give A x1. -> OFFERED, offeredBy=user1.
    let give_a = format!(
        r#"{{"merchId": {}, "giverUserId": {}, "quantity": 1}}"#,
        merch_a_id, user1_id
    );
    assert_eq!(
        post_offer(&pool, user1_id, &give_a).await.status(),
        StatusCode::OK
    );
    let m = fetch_matches(&pool, user1_id).await;
    assert_eq!(m["status"], "OFFERED");
    assert_eq!(m["offeredBy"], user1_id);

    // 2. user2 accept while unbalanced -> 400 (Cannot accept an unbalanced proposal).
    assert_eq!(
        post_status(&pool, user2_id, "ACCEPTED").await.status(),
        StatusCode::BAD_REQUEST
    );

    // 3. user1 (proposer) accept own -> 400 (Cannot accept your own proposal).
    assert_eq!(
        post_status(&pool, user1_id, "ACCEPTED").await.status(),
        StatusCode::BAD_REQUEST
    );

    // 4. user1 counter their own proposal -> 400 (Cannot counter your own proposal).
    assert_eq!(
        post_offer(&pool, user1_id, &give_a).await.status(),
        StatusCode::BAD_REQUEST
    );

    // 5. user2 counter-offer: add give B x1 (giver=user2). Legs accumulate
    //    -> (u1:A1) + (u2:B1) balanced. -> OFFERED, offeredBy=user2.
    let give_b = format!(
        r#"{{"merchId": {}, "giverUserId": {}, "quantity": 1}}"#,
        merch_b_id, user2_id
    );
    assert_eq!(
        post_offer(&pool, user2_id, &give_b).await.status(),
        StatusCode::OK
    );
    let m = fetch_matches(&pool, user1_id).await;
    assert_eq!(m["status"], "OFFERED");
    assert_eq!(m["offeredBy"], user2_id);

    // 6. user1 (non-proposer now) accepts the balanced proposal -> ACCEPTED.
    assert_eq!(
        post_status(&pool, user1_id, "ACCEPTED").await.status(),
        StatusCode::OK
    );
    let m = fetch_matches(&pool, user1_id).await;
    assert_eq!(m["status"], "ACCEPTED");
}

/// #322 / ADR 0001: a match is scoped to one (event_id, group_name), and the
/// match card shows `event:group` once. The listing must surface the match's
/// `groupName`/`eventName` on the TradeMatch (not per item). The setup helper
/// creates the merch under event "Qty Cap Trade Event" with group "Cards", so
/// the match must carry those.
#[sqlx::test]
async fn test_match_carries_event_group_context(pool: PgPool) {
    let (_match_id, user1_id, _user2_id, _merch_a_id, _merch_b_id) =
        setup_pending_trade_match_quantities(pool.clone(), 2, 2, 2, 2).await;

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

    // The match-level context the card renders.
    assert_eq!(matches[0]["groupName"].as_str().unwrap(), "Cards");
    assert_eq!(
        matches[0]["eventName"].as_str().unwrap(),
        "Qty Cap Trade Event",
    );
}

/// #346: defense-in-depth DB constraint. ADR 0001 scopes a match to one
/// (event_id, group_name) and the matcher dedups per (pair, group) at the
/// application level (`matching.rs` `existing_match`). A direct INSERT that
/// bypasses the matcher must still be rejected by the DB when it would create
/// a second row for the same canonical (pair, group) — including the symmetric
/// `(user2, user1)` ordering, which the canonicalization (`LEAST`/`GREATEST`)
/// must collapse. A separate group for the same pair remains allowed.
#[sqlx::test]
async fn test_match_unique_canonical_pair_group_enforced_by_db(pool: PgPool) {
    let (u1,): (i32,) = sqlx::query_as(
        "INSERT INTO users (username, password_hash) VALUES ('uniq-u1', 'x') RETURNING id",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let (u2,): (i32,) = sqlx::query_as(
        "INSERT INTO users (username, password_hash) VALUES ('uniq-u2', 'x') RETURNING id",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let (event_id,): (i32,) = sqlx::query_as(
        "INSERT INTO events (name, creator_id) VALUES ('Uniq Pair Event', $1) RETURNING id",
    )
    .bind(u1)
    .fetch_one(&pool)
    .await
    .unwrap();

    let insert_match = |ua: i32, ub: i32, group: &'static str| {
        sqlx::query(
            "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name)
             VALUES ($1, $2, 'PENDING', $3, $4)",
        )
        .bind(ua)
        .bind(ub)
        .bind(event_id)
        .bind(group)
        .execute(&pool)
    };

    // Baseline: one match for (u1, u2) in "Cards".
    insert_match(u1, u2, "Cards").await.unwrap();

    // Same pair, swapped column ordering, same group -> canonical collision.
    let dup = insert_match(u2, u1, "Cards").await;
    assert!(
        dup.is_err(),
        "DB must reject a duplicate (canonical pair, group) match, got: {dup:?}",
    );

    // Same pair, different group -> allowed (ADR 0001: one match per group).
    insert_match(u2, u1, "Stickers").await.unwrap();

    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM matches WHERE event_id = $1 AND group_name IN ('Cards', 'Stickers')",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count, 2, "expected one match per group, got {count}");
}

/// The accept gate re-validates the FULL accumulated leg set against the
/// receiver's CURRENT want quantity (#297 review). A leg that was within
/// the cap when proposed can become over-capacity if the receiver lowers
/// their WANT mid-negotiation; accept must then be rejected with 400 even
/// though the proposal is balanced — otherwise `apply_inventory` would
/// over-deliver. The proposer can then counter the leg down to the new
/// cap and the non-proposer can accept.
#[sqlx::test]
async fn test_accept_rejected_when_leg_exceeds_current_want(pool: PgPool) {
    // WANT x2 on both sides so a 2:2 balanced proposal fits the cap
    // initially. user1: TRADE A x2 / WANT B x2; user2: TRADE B x2 / WANT A x2.
    let (match_id, user1_id, user2_id, merch_a_id, merch_b_id) =
        setup_pending_trade_match_quantities(pool.clone(), 2, 2, 2, 2).await;

    let post_offer = |pool: &PgPool, uid: i64, items: &str| {
        let pool = pool.clone();
        let body = format!(r#"{{"userId": {}, "items": [{}]}}"#, uid, items);
        async move {
            let app = backend::routes::create_router(pool, test_storage());
            app.oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/v1/matches/{}/offer", match_id))
                    .header("content-type", "application/json")
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap()
        }
    };
    let post_status = |pool: &PgPool, uid: i64, status: &str| {
        let pool = pool.clone();
        let body = format!(r#"{{"status": "{}", "userId": {}}}"#, status, uid);
        async move {
            let app = backend::routes::create_router(pool, test_storage());
            app.oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/v1/matches/{}/status", match_id))
                    .header("content-type", "application/json")
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap()
        }
    };
    // Lower user2's WANT of Card A from 2 to `qty` (the inventory upsert
    // overwrites quantity on conflict, so this is a real mid-negotiation
    // change to the cap on user1's give-of-A leg).
    let lower_want = |pool: &PgPool, uid: i64, merch: i64, qty: i32| {
        let pool = pool.clone();
        async move {
            let app = backend::routes::create_router(pool, test_storage());
            app.oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/user/inventory")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"userId": {}, "merchId": {}, "status": "WANT", "quantity": {}}}"#,
                        uid, merch, qty
                    )))
                    .unwrap(),
            )
            .await
            .unwrap()
        }
    };

    // 1. user1 opens a balanced 2:2 proposal: give A x2 (giver=u1) +
    //    receive B x2 (giver=u2). Both legs within cap (WANT x2). -> OFFERED.
    let items = format!(
        r#"{{"merchId": {}, "giverUserId": {}, "quantity": 2}}, {{"merchId": {}, "giverUserId": {}, "quantity": 2}}"#,
        merch_a_id, user1_id, merch_b_id, user2_id
    );
    assert_eq!(
        post_offer(&pool, user1_id, &items).await.status(),
        StatusCode::OK
    );

    // 2. user2 lowers their WANT of Card A from 2 to 1. user1's persisted
    //    give-of-A x2 leg now exceeds the receiver's WANT (1). The
    //    proposal is still balanced (2:2), so only the cap gate should
    //    block accept.
    assert_eq!(
        lower_want(&pool, user2_id, merch_a_id, 1).await.status(),
        StatusCode::OK
    );

    // 3. user2 (non-proposer) accepts -> 400 (over-cap, despite balanced).
    assert_eq!(
        post_status(&pool, user2_id, "ACCEPTED").await.status(),
        StatusCode::BAD_REQUEST
    );

    // 4. user2 counters the A leg down to 1 (giver=u1, the editor's
    //    receive) and the B leg down to 1 (giver=u2). Now balanced 1:1 and
    //    within the new cap. -> OFFERED, offeredBy=user2.
    let items = format!(
        r#"{{"merchId": {}, "giverUserId": {}, "quantity": 1}}, {{"merchId": {}, "giverUserId": {}, "quantity": 1}}"#,
        merch_a_id, user1_id, merch_b_id, user2_id
    );
    assert_eq!(
        post_offer(&pool, user2_id, &items).await.status(),
        StatusCode::OK
    );

    // 5. user1 (non-proposer now) accepts the within-cap balanced proposal.
    assert_eq!(
        post_status(&pool, user1_id, "ACCEPTED").await.status(),
        StatusCode::OK
    );
}

#[sqlx::test]
async fn test_apply_inventory_on_non_completed_rejected(pool: PgPool) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/matches/99999/apply-inventory")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"userId": 1}"#))
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

    // ADR 0004 §4: event creation is moderator/admin-only, so promote the
    // guest before creating the event. The handler auto-assigns the
    // `event/creator` role to the creator.
    grant_global_role(&pool, user_id, "moderator").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "{}", "creatorId": {}}}"#,
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

#[sqlx::test]
async fn test_create_group_via_dialog(pool: PgPool) {
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
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Keychains", "description": "Handmade keychains only"}}"#,
                    event_id, user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["groupName"].as_str().unwrap(), "Keychains");
    assert_eq!(
        group["description"].as_str().unwrap(),
        "Handmade keychains only"
    );
    assert_eq!(group["createdBy"].as_i64().unwrap(), user_id);
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
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Keychains", "description": "Updated"}}"#,
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
    assert_eq!(group["createdBy"].as_i64().unwrap(), user_id);

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
    assert_eq!(groups[0]["groupName"].as_str().unwrap(), "Keychains");
}

#[sqlx::test]
async fn test_update_group_description(pool: PgPool) {
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
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Pins", "description": "original"}}"#,
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
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Pins", "description": "updated by creator"}}"#,
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

    // Non-creator cannot update. Use a plain guest (not the
    // `create_test_user_and_event` helper, which now promotes its user to
    // moderator so they can create the event — that moderator role would
    // satisfy the group-update admin/mod check and mask the 403).
    let other_id = login_guest(&pool, "group-updater-other", "tok").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(&format!("/api/v1/events/{}/groups/Pins", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Pins", "description": "hostile update"}}"#,
                    event_id, other_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_implicit_group_via_first_merch(pool: PgPool) {
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
    assert_eq!(
        body.get("groups")
            .and_then(|v| v.as_array())
            .map_or(0, |g| g.len()),
        0
    );

    // Create first merch in a new group — should auto-create the group row
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "First item", "groupName": "Auto Group", "creatorId": {}}}"#,
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
    assert!(merch["groupDescription"].is_null());

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
    assert_eq!(groups[0]["groupName"].as_str().unwrap(), "Auto Group");
    assert_eq!(groups[0]["createdBy"].as_i64().unwrap(), user_id);
}

#[sqlx::test]
async fn test_merch_includes_group_description(pool: PgPool) {
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
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Stickers", "description": "Vinyl stickers"}}"#,
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
                    r#"{{"name": "Cat sticker", "groupName": "Stickers", "creatorId": {}}}"#,
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
        merch["groupDescription"].as_str().unwrap(),
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
        items[0]["groupDescription"].as_str().unwrap(),
        "Vinyl stickers"
    );
}

// --- Issue #173 follow-up: extra tests for notification_counts and upsert shape ---

#[sqlx::test]
async fn test_notification_counts_values(pool: PgPool) {
    // Set up: 2 users, 1 event, 2 merch items ("Card A", "Card B").
    // We'll create three matches in different states and verify the
    // counts endpoint returns the correct values for each side.
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
                    r#"{{"name": "Card A", "groupName": "cards", "creatorId": {}}}"#,
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
                    r#"{{"name": "Card B", "groupName": "cards", "creatorId": {}}}"#,
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
                    .uri("/api/v1/user/inventory")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"userId": {}, "merchId": {}, "status": "WANT", "quantity": 1}}"#,
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
                    .uri("/api/v1/user/inventory")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"userId": {}, "merchId": {}, "status": "TRADE", "quantity": 1}}"#,
                        user_id,
                        if user_id == u1 { m_a_id } else { m_b_id }
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
    }

    // Insert match directly (the matching algorithm is out of scope for
    // integration tests; it runs in a background task). ADR 0001: scope the
    // match to the "cards" group of the merch above.
    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name)
         VALUES ($1, $2, 'PENDING', $3, 'cards') RETURNING id",
    )
    .bind(u1)
    .bind(u2)
    .bind(event_id as i32)
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
    assert_eq!(json_i64(&body, "pendingMatches"), 1);
    assert_eq!(json_i64(&body, "offersIn"), 0);
    assert_eq!(json_i64(&body, "accepted"), 0);
    assert_eq!(json_i64(&body, "unreadMessages"), 0);
    assert_eq!(json_i64(&body, "total"), 1);

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
    assert_eq!(json_i64(&body, "pendingMatches"), 1);

    // ---- Transition to OFFERED via u1 (balanced: give m_a, receive m_b);
    //      send a message from u2 (unread for u1) ----
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "items": [{{"merchId": {}, "giverUserId": {}, "quantity": 1}}, {{"merchId": {}, "giverUserId": {}, "quantity": 1}}]}}"#,
                    u1, m_a_id, u1, m_b_id, u2
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
                    r#"{{"matchId": {}, "senderId": {}, "content": "hi", "messageType": "TEXT"}}"#,
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
    assert_eq!(json_i64(&body, "pendingMatches"), 0);
    assert_eq!(json_i64(&body, "offersIn"), 0);
    assert_eq!(json_i64(&body, "accepted"), 0);
    assert_eq!(json_i64(&body, "unreadMessages"), 1);
    assert_eq!(json_i64(&body, "total"), 1);

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
    assert_eq!(json_i64(&body, "pendingMatches"), 0);
    assert_eq!(json_i64(&body, "offersIn"), 1);
    assert_eq!(json_i64(&body, "accepted"), 0);
    assert_eq!(json_i64(&body, "unreadMessages"), 0);
    assert_eq!(json_i64(&body, "total"), 1);

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
    assert_eq!(json_i64(&body, "unreadMessages"), 0);
    assert_eq!(json_i64(&body, "total"), 0); // all zeros for u1 now

    // ---- Transition OFFERED -> ACCEPTED: counts should change again ----
    // Note: the offer's "offeree" is u2; for ACCEPTED, the user_id in
    // the body is the non-proposer accepting (u2).
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let _ = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/status", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"status": "ACCEPTED", "userId": {}}}"#,
                    u2
                )))
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
    assert_eq!(json_i64(&body, "pendingMatches"), 0);
    assert_eq!(json_i64(&body, "offersIn"), 0);
    assert_eq!(json_i64(&body, "accepted"), 1);
    assert_eq!(json_i64(&body, "total"), 1);
}

#[sqlx::test]
async fn test_upsert_response_shape_preserved(pool: PgPool) {
    // Issue #173 item #5: the upsert response body should retain the
    // pre-Phase-4 shape: merch_name = Some("") (not None). The frontend
    // re-fetches via get_user_inventory (which joins merch) before
    // display, so the empty string never reaches the user; this
    // preserves the historical shape.
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
                    r#"{{"name": "Sticker", "groupName": "stickers", "creatorId": {}}}"#,
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
                    r#"{{"userId": {}, "merchId": {}, "status": "HAVE", "quantity": 2}}"#,
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
    //   null). So `body.get("photoUrl")` returns Value::Null and the key
    //   is absent — both shapes are acceptable per the test.
    assert!(
        body.get("merchName").is_some(),
        "merch_name must be present"
    );
    assert_eq!(
        body["merchName"].as_str().unwrap(),
        "",
        "merch_name must be Some(\"\") not null"
    );
    let photo_url = body.get("photoUrl");
    assert!(
        photo_url.is_none() || photo_url.and_then(|v| v.as_str()).is_none(),
        "photo_url must be absent or null, got: {:?}",
        photo_url
    );
    let group_name = body.get("groupName");
    assert!(
        group_name.is_none() || group_name.and_then(|v| v.as_str()).is_none(),
        "group_name must be absent or null, got: {:?}",
        group_name
    );
    // With #[sqlx::test] each test gets a fresh, migrated database, so
    // sequences start at 1 and the first inserted inventory row gets id=1.
    assert_eq!(body["id"].as_i64().unwrap(), 1);
    assert_eq!(body["userId"].as_i64().unwrap(), creator_id);
    assert_eq!(body["merchId"].as_i64().unwrap(), merch_id);
    assert_eq!(body["status"].as_str().unwrap(), "HAVE");
    assert_eq!(body["quantity"].as_i64().unwrap(), 2);
}

// Regression test for #224: apply_inventory panicked with
// `UnexpectedNullError` when a match contained merch with a NULL
// `photo_url`. The match_items SQL in `backend/src/repositories/match_.rs`
// decoded `m.photo_url` as a non-nullable `String`, which cannot
// accept NULL. The fix decodes as `Option<String>` (matching the
// proto's `optional string photo_url`).
//
// This test walks the full lifecycle (PENDING -> OFFERED -> ACCEPTED
// -> COMPLETED -> apply-inventory) for two users whose merch has no
// photo_url, and asserts that apply-inventory returns 200 (i.e. does
// not panic the worker thread, which previously would have produced
// an empty 502/503 response).
#[sqlx::test]
async fn test_apply_inventory_handles_null_photo_url(pool: PgPool) {
    // 1. Create two users
    let user1_id = login_guest(&pool, "u1-photo-null", "tok1").await;
    let user2_id = login_guest(&pool, "u2-photo-null", "tok2").await;

    // 2. Create event
    let event_id = create_event(&pool, "Photo Null Event", user1_id).await;

    // 3. Create merch WITHOUT a photo_url. This is the trigger for
    //    #224 — the panic only happens when photo_url IS NULL.
    //    Both items share a group so the auto-matcher pairs them.
    let card_a = create_merch(&pool, event_id, "Card A", "photo-null-group").await;
    let card_b = create_merch(&pool, event_id, "Card B", "photo-null-group").await;

    // Sanity check: photo_url is NULL.
    let row: (Option<String>,) = sqlx::query_as("SELECT photo_url FROM merchandise WHERE id = $1")
        .bind(card_a)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(
        row.0.is_none(),
        "test setup: card_a.photo_url should be NULL, got {:?}",
        row.0
    );

    // 4. Set cross-trade inventory: user1 TRADES Card A + WANTs Card B;
    //    user2 TRADES Card B + WANTs Card A.
    set_inventory(&pool, user1_id, card_a, "TRADE", 1).await;
    set_inventory(&pool, user1_id, card_b, "WANT", 1).await;
    set_inventory(&pool, user2_id, card_b, "TRADE", 1).await;
    set_inventory(&pool, user2_id, card_a, "WANT", 1).await;

    // 5. Run the matcher directly (don't wait 60s for the periodic run).
    backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matcher should run");

    // 6. Find the PENDING match
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/matches/user/{}", user1_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let matches = body.as_array().expect("matches is an array");
    let match_id = matches
        .iter()
        .find(|m| m["status"].as_str() == Some("PENDING"))
        .expect("at least one PENDING match should exist")["id"]
        .as_i64()
        .unwrap();

    // 7. Walk the lifecycle (balanced: user1 gives A, user2 gives B)
    let offer_body = format!(
        r#"{{"userId": {}, "items": [{{"merchId": {}, "giverUserId": {}, "quantity": 1}}, {{"merchId": {}, "giverUserId": {}, "quantity": 1}}]}}"#,
        user1_id, card_a, user1_id, card_b, user2_id
    );
    assert_eq!(
        post_json(
            &pool,
            &format!("/api/v1/matches/{}/offer", match_id),
            &offer_body
        )
        .await
        .status(),
        StatusCode::OK,
        "offer should succeed"
    );
    assert_eq!(
        post_json(
            &pool,
            &format!("/api/v1/matches/{}/status", match_id),
            &format!(r#"{{"status": "ACCEPTED", "userId": {}}}"#, user2_id)
        )
        .await
        .status(),
        StatusCode::OK,
        "accept should succeed"
    );
    assert_eq!(
        post_json(
            &pool,
            &format!("/api/v1/matches/{}/status", match_id),
            &format!(r#"{{"status": "COMPLETED", "userId": {}}}"#, user1_id)
        )
        .await
        .status(),
        StatusCode::OK,
        "complete should succeed"
    );

    // 8. THE REGRESSION CHECK: apply-inventory used to panic with
    //    `UnexpectedNullError` (the match_items query decoded
    //    `m.photo_url` as a non-nullable `String`). After the fix
    //    (decoding as `Option<String>`), this returns 200.
    let apply_body = format!(r#"{{"userId": {}}}"#, user1_id);
    let resp = post_json(
        &pool,
        &format!("/api/v1/matches/{}/apply-inventory", match_id),
        &apply_body,
    )
    .await;
    assert_eq!(
        resp.status(),
        StatusCode::OK,
        "apply-inventory must not panic on NULL photo_url (issue #224)"
    );
}

// --- Test helpers used by `test_apply_inventory_handles_null_photo_url` ---

// ADR 0001 / #341: two users with reciprocal inventory in TWO shared groups
// get two independent matches, one per group (not one per user pair).
#[sqlx::test]
async fn test_matching_creates_one_match_per_shared_group(pool: PgPool) {
    let u1 = login_guest(&pool, "adr0001-u1", "t1").await;
    let u2 = login_guest(&pool, "adr0001-u2", "t2").await;
    let event_id = create_event(&pool, "ADR0001 Event", u1).await;

    // Group G1: u1 TRADE g1 / WANT g2 ; u2 TRADE g2 / WANT g1.
    let g1 = create_merch(&pool, event_id, "g1", "G1").await;
    let g2 = create_merch(&pool, event_id, "g2", "G1").await;
    // Group F1: u1 TRADE f1 / WANT f2 ; u2 TRADE f2 / WANT f1.
    let f1 = create_merch(&pool, event_id, "f1", "F1").await;
    let f2 = create_merch(&pool, event_id, "f2", "F1").await;

    for (uid, mid, status) in [
        (u1, g1, "TRADE"),
        (u1, g2, "WANT"),
        (u2, g2, "TRADE"),
        (u2, g1, "WANT"),
        (u1, f1, "TRADE"),
        (u1, f2, "WANT"),
        (u2, f2, "TRADE"),
        (u2, f1, "WANT"),
    ] {
        set_inventory(&pool, uid, mid, status, 1).await;
    }

    let created = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matching failed");
    assert_eq!(
        created, 2,
        "expected exactly 2 matches (one per shared group)"
    );

    // Two PENDING matches between u1 and u2, scoped to distinct groups.
    let rows: Vec<(String,)> = sqlx::query_as(
        "SELECT group_name FROM matches
         WHERE (user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1)
         ORDER BY group_name",
    )
    .bind(u1 as i32)
    .bind(u2 as i32)
    .fetch_all(&pool)
    .await
    .unwrap();
    let groups: Vec<String> = rows.into_iter().map(|r| r.0).collect();
    assert_eq!(groups, vec!["F1".to_string(), "G1".to_string()]);
}

// ADR 0001 / #341: NULL-grouped merchandise does not participate in matching.
#[sqlx::test]
async fn test_matching_skips_null_grouped_merch(pool: PgPool) {
    let u1 = login_guest(&pool, "adr0001-null-u1", "t1").await;
    let u2 = login_guest(&pool, "adr0001-null-u2", "t2").await;
    let event_id = create_event(&pool, "ADR0001 Null Group Event", u1).await;

    // Two merch rows left without a group (NULL group_name) by inserting
    // directly, bypassing the group-required merch API.
    let a: (i32,) = sqlx::query_as(
        "INSERT INTO merchandise (event_id, name) VALUES ($1, 'null-a') RETURNING id",
    )
    .bind(event_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    let b: (i32,) = sqlx::query_as(
        "INSERT INTO merchandise (event_id, name) VALUES ($1, 'null-b') RETURNING id",
    )
    .bind(event_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    for (uid, mid, status) in [
        (u1, a.0 as i64, "TRADE"),
        (u1, b.0 as i64, "WANT"),
        (u2, b.0 as i64, "TRADE"),
        (u2, a.0 as i64, "WANT"),
    ] {
        set_inventory(&pool, uid, mid, status, 1).await;
    }

    let created = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matching failed");
    assert_eq!(created, 0, "NULL-grouped merch must not match");

    let count: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM matches
         WHERE (user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1)",
    )
    .bind(u1 as i32)
    .bind(u2 as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count.0, 0);
}

// ADR 0001 / #341: an offer leg whose merch is outside the match's group is
// rejected (400), so the invariant cannot be violated via the API.
#[sqlx::test]
async fn test_offer_rejects_leg_outside_match_group(pool: PgPool) {
    let u1 = login_guest(&pool, "adr0001-offer-u1", "t1").await;
    let u2 = login_guest(&pool, "adr0001-offer-u2", "t2").await;
    let event_id = create_event(&pool, "ADR0001 Offer Event", u1).await;

    // G1: reciprocal → a PENDING match scoped to G1.
    let g1a = create_merch(&pool, event_id, "g1a", "G1").await;
    let g1b = create_merch(&pool, event_id, "g1b", "G1").await;
    // G2: a single merch that u1 TRADES but which is NOT in the match's group.
    let g2c = create_merch(&pool, event_id, "g2c", "G2").await;

    for (uid, mid, status) in [
        (u1, g1a, "TRADE"),
        (u1, g1b, "WANT"),
        (u2, g1b, "TRADE"),
        (u2, g1a, "WANT"),
        (u1, g2c, "TRADE"),
    ] {
        set_inventory(&pool, uid, mid, status, 1).await;
    }

    backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matching failed");

    // Find the G1 match between u1 and u2.
    let match_row: (i32,) = sqlx::query_as(
        "SELECT id FROM matches
         WHERE group_name = 'G1'
           AND ((user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1))",
    )
    .bind(u1 as i32)
    .bind(u2 as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    let match_id = match_row.0 as i64;

    // Offer a leg whose merch (g2c) belongs to G2, not the match's G1.
    let body = format!(
        r#"{{"userId": {}, "items": [{{"merchId": {}, "giverUserId": {}, "quantity": 1}}]}}"#,
        u1, g2c, u1
    );
    let resp = post_json(&pool, &format!("/api/v1/matches/{}/offer", match_id), &body).await;
    assert_eq!(
        resp.status(),
        StatusCode::BAD_REQUEST,
        "out-of-group offer leg must be rejected"
    );
}

// ADR 0001 / #348: `list_for_user` must scope each match's pre-loaded
// `user_haves`/`user_wants` to the match's group. For a pair with matches in
// two groups, the G1 match must list only G1 candidate items (and F1 only F1),
// and each item's `group_name` must be populated (no longer null).
#[sqlx::test]
async fn test_list_for_user_scopes_haves_wants_to_match_group(pool: PgPool) {
    let u1 = login_guest(&pool, "adr0001-list-u1", "t1").await;
    let u2 = login_guest(&pool, "adr0001-list-u2", "t2").await;
    let event_id = create_event(&pool, "ADR0001 List Event", u1).await;

    // Group G1: u1 TRADE g1 / WANT g2 ; u2 TRADE g2 / WANT g1.
    let g1 = create_merch(&pool, event_id, "g1", "G1").await;
    let g2 = create_merch(&pool, event_id, "g2", "G1").await;
    // Group F1: u1 TRADE f1 / WANT f2 ; u2 TRADE f2 / WANT f1.
    let f1 = create_merch(&pool, event_id, "f1", "F1").await;
    let f2 = create_merch(&pool, event_id, "f2", "F1").await;

    for (uid, mid, status) in [
        (u1, g1, "TRADE"),
        (u1, g2, "WANT"),
        (u2, g2, "TRADE"),
        (u2, g1, "WANT"),
        (u1, f1, "TRADE"),
        (u1, f2, "WANT"),
        (u2, f2, "TRADE"),
        (u2, f1, "WANT"),
    ] {
        set_inventory(&pool, uid, mid, status, 1).await;
    }

    backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matching failed");

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/user/{}", u1))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let matches: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(matches.len(), 2, "expected one match per shared group");

    fn group_of(m: &serde_json::Value) -> String {
        // The match's group is not on the TradeMatch proto; derive it from the
        // group shared by every leg's candidate item.
        let haves = m["userHaves"].as_array().unwrap();
        haves
            .iter()
            .map(|i| i["groupName"].as_str().unwrap().to_string())
            .next()
            .unwrap()
    }

    let by_group: std::collections::HashMap<String, &serde_json::Value> =
        matches.iter().map(|m| (group_of(m), m)).collect();
    assert_eq!(by_group.len(), 2, "expected both G1 and F1 matches");
    let g1_match = by_group["G1"];
    let f1_match = by_group["F1"];

    // G1 match: userHaves (u1 TRADEs) must be only G1 items; userWants (peer
    // TRADEs) only G1 items. Each item's groupName must be populated.
    let g1_haves = g1_match["userHaves"].as_array().unwrap();
    assert_eq!(g1_haves.len(), 1, "G1 match should have one have");
    assert_eq!(g1_haves[0]["merchId"].as_i64().unwrap(), g1);
    assert_eq!(g1_haves[0]["groupName"].as_str().unwrap(), "G1");
    let g1_wants = g1_match["userWants"].as_array().unwrap();
    assert_eq!(g1_wants.len(), 1, "G1 match should have one want");
    assert_eq!(g1_wants[0]["merchId"].as_i64().unwrap(), g2);
    assert_eq!(g1_wants[0]["groupName"].as_str().unwrap(), "G1");

    // F1 match: only F1 items.
    let f1_haves = f1_match["userHaves"].as_array().unwrap();
    assert_eq!(f1_haves.len(), 1, "F1 match should have one have");
    assert_eq!(f1_haves[0]["merchId"].as_i64().unwrap(), f1);
    assert_eq!(f1_haves[0]["groupName"].as_str().unwrap(), "F1");
    let f1_wants = f1_match["userWants"].as_array().unwrap();
    assert_eq!(f1_wants.len(), 1, "F1 match should have one want");
    assert_eq!(f1_wants[0]["merchId"].as_i64().unwrap(), f2);
    assert_eq!(f1_wants[0]["groupName"].as_str().unwrap(), "F1");
}

// --- RBAC wiring (ADR 0004, #228 PR3a) ---
//
// These tests pin the authorization boundaries that PR3a wires through
// RbacService: event.create (mod/admin only), event.edit (event creator +
// editor + admin bypass + moderator via event.edit.any), the admin
// moderation permissions, the merch-delete ownership-or-RBAC rule, and the
// users.role <-> user_roles mirror sync.

#[sqlx::test]
async fn test_rbac_event_create_requires_moderator_or_admin(pool: PgPool) {
    let plain = login_guest(&pool, "rbac-create-plain", "t").await;

    // Plain user cannot create an event (ADR 0004 §4).
    let resp = post_json(
        &pool,
        "/api/v1/events",
        &format!(r#"{{"name": "Plain Event", "creatorId": {}}}"#, plain),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Moderator can.
    grant_global_role(&pool, plain, "moderator").await;
    let resp = post_json(
        &pool,
        "/api/v1/events",
        &format!(r#"{{"name": "Mod Event", "creatorId": {}}}"#, plain),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    // Admin can.
    let admin = login_guest(&pool, "rbac-create-admin", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let resp = post_json(
        &pool,
        "/api/v1/events",
        &format!(r#"{{"name": "Admin Event", "creatorId": {}}}"#, admin),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_rbac_event_create_auto_assigns_creator_role(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-auto-creator", "Auto Creator Event").await;

    // The creator is auto-assigned the event/creator role scoped to the new
    // event (ADR 0004 §5), so they pass EventEdit on their own event.
    let row: Option<(i32,)> = sqlx::query_as(
        "SELECT 1 FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND r.scope_type = 'event' AND r.name = 'creator'
           AND ur.scope_type = 'event' AND ur.scope_id = $2",
    )
    .bind(creator_id as i32)
    .bind(event_id as i32)
    .fetch_optional(&pool)
    .await
    .unwrap();
    assert!(row.is_some(), "event/creator role was not auto-assigned");

    // And the creator can publish (EventEdit) their own draft event.
    sqlx::query("UPDATE events SET status = 'draft' WHERE id = $1")
        .bind(event_id as i32)
        .execute(&pool)
        .await
        .unwrap();
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/publish", event_id),
        &format!(r#"{{"userId": {}}}"#, creator_id),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_rbac_event_update_editor_succeeds_plain_user_forbidden(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-upd-creator", "Editor Event").await;

    // An editor (event-scoped editor role) can update the event.
    let editor = login_guest(&pool, "rbac-upd-editor", "t").await;
    assign_event_role(&pool, editor, event_id, "editor").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "name": "Editor Renamed"}}"#,
                    editor
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A plain user (no event role, not moderator) is denied.
    let plain = login_guest(&pool, "rbac-upd-plain", "t").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "name": "Pwned"}}"#,
                    plain
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // The creator (event/creator) can also update.
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "name": "Creator Renamed"}}"#,
                    creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_rbac_admin_delete_event_permission(pool: PgPool) {
    let (_creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-del-creator", "To Be Deleted").await;

    // A separate moderator can delete any event via event.delete.any.
    let moderator = login_guest(&pool, "rbac-del-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/events/{}?user_id={}",
                    event_id, moderator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A plain user cannot delete an event.
    let (_creator2_id, event2_id) =
        create_test_user_and_event(pool.clone(), "rbac-del-creator2", "To Be Deleted 2").await;
    let plain = login_guest(&pool, "rbac-del-plain", "t").await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/events/{}?user_id={}",
                    event2_id, plain
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_rbac_ban_unban_permission(pool: PgPool) {
    let moderator = login_guest(&pool, "rbac-ban-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let target = login_guest(&pool, "rbac-ban-target", "t").await;

    // Moderator can ban.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/ban?user_id={}",
                    target, moderator
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"reason": "spam"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Moderator can unban.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/unban?user_id={}",
                    target, moderator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A plain user cannot ban.
    let plain = login_guest(&pool, "rbac-ban-plain", "t").await;
    let other = login_guest(&pool, "rbac-ban-other", "t").await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/ban?user_id={}",
                    other, plain
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"reason": "nope"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_rbac_update_user_role_admin_only_and_mirror_sync(pool: PgPool) {
    let admin = login_guest(&pool, "rbac-role-admin", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let target = login_guest(&pool, "rbac-role-target", "t").await;

    // Admin can change a role.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target, admin
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "moderator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // ADR 0004 §2 mirror sync: users.role AND the user_roles global row both
    // reflect the new role.
    let role: String = sqlx::query_scalar("SELECT role FROM users WHERE id = $1")
        .bind(target as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(role, "moderator");
    let has_row: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND r.scope_type = 'global' AND r.name = 'moderator'
           AND ur.scope_type = 'global' AND ur.scope_id IS NULL",
    )
    .bind(target as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(has_row, 1, "user_roles global/moderator row must exist");

    // Demotion path: set_role must remove the prior elevated global row when
    // the role changes (delete-then-insert in one tx), so a demoted user
    // cannot retain elevated RBAC access via a stale user_roles row.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target, admin
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let role: String = sqlx::query_scalar("SELECT role FROM users WHERE id = $1")
        .bind(target as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(role, "user");
    let elevated: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND r.scope_type = 'global'
           AND ur.scope_type = 'global' AND ur.scope_id IS NULL
           AND r.name IN ('moderator', 'admin')",
    )
    .bind(target as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(elevated, 0, "demotion must remove the elevated global row");

    // A moderator cannot change roles (user.role.manage is admin-only).
    let moderator = login_guest(&pool, "rbac-role-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let other = login_guest(&pool, "rbac-role-other", "t").await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    other, moderator
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "admin"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_rbac_delete_merch_ownership_and_roles(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-merch-creator", "Merch RBAC Event").await;

    // Create a merch row owned by a plain user (the merch creator).
    let merch_creator = login_guest(&pool, "rbac-merch-owner", "t").await;
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        &format!(
            r#"{{"name": "Pin", "groupName": "G", "creatorId": {}}}"#,
            merch_creator
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let merch_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    // Merch creator can delete their own merch (ownership short-circuit).
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch_id, merch_creator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A second merch, owned by nobody (creator_id NULL), to exercise the
    // RBAC paths.
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        r#"{"name": "Sticker", "groupName": "G"}"#,
    )
    .await;
    let merch2: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    // Plain non-owner cannot delete.
    let plain = login_guest(&pool, "rbac-merch-plain", "t").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch2, plain
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Event editor can delete (merch.delete, event scope).
    let editor = login_guest(&pool, "rbac-merch-editor", "t").await;
    assign_event_role(&pool, editor, event_id, "editor").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch2, editor
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A third merch: a moderator can delete via merch.delete.any.
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        r#"{"name": "Poster", "groupName": "G"}"#,
    )
    .await;
    let merch3: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();
    let moderator = login_guest(&pool, "rbac-merch-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch3, moderator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // The event creator (event/creator) can also delete merch.
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        r#"{"name": "Banner", "groupName": "G"}"#,
    )
    .await;
    let merch4: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch4, creator_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

async fn login_guest(pool: &PgPool, uuid: &str, device_token: &str) -> i64 {
    let body = format!(
        r#"{{"uuid": "{}", "deviceToken": "{}"}}"#,
        uuid, device_token
    );
    let resp = post_json(pool, "/api/v1/auth/guest", &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "guest login failed");
    let v: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    v["id"].as_i64().unwrap()
}

/// Grant `user_id` a *global* role the way the production `set_role` path
/// does (ADR 0004 §2): write `users.role` **and** the `user_roles` global
/// row in one transaction, so RBAC checks (which read `user_roles`) see the
/// role. Replaces any prior global role. Used by tests that need an
/// admin/moderator actor and by the event-creation helpers (event creation
/// now requires `event.create`, granted to moderator/admin only).
async fn grant_global_role(pool: &PgPool, user_id: i64, role: &str) {
    let mut tx = pool.begin().await.unwrap();
    sqlx::query("UPDATE users SET role = $1 WHERE id = $2")
        .bind(role)
        .bind(user_id as i32)
        .execute(&mut *tx)
        .await
        .unwrap();
    let role_id: i32 =
        sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'global' AND name = $1")
            .bind(role)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    sqlx::query(
        "DELETE FROM user_roles
         WHERE user_id = $1 AND scope_type = 'global' AND scope_id IS NULL",
    )
    .bind(user_id as i32)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'global', NULL)
         ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
    )
    .bind(user_id as i32)
    .bind(role_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

/// Assign an event-scoped role (`creator` or `editor`) to `user_id` for
/// `event_id` directly, mirroring what the (deferred) event-member API will
/// do for `editor` and what `RbacRepository::assign_event_creator` does for
/// `creator`. Used by the RBAC boundary tests to set up event-scoped actors
/// without the member API.
async fn assign_event_role(pool: &PgPool, user_id: i64, event_id: i64, role_name: &str) {
    let role_id: i32 =
        sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'event' AND name = $1")
            .bind(role_name)
            .fetch_one(pool)
            .await
            .unwrap();
    sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'event', $3)
         ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
    )
    .bind(user_id as i32)
    .bind(role_id)
    .bind(event_id as i32)
    .execute(pool)
    .await
    .unwrap();
}

async fn create_event(pool: &PgPool, name: &str, creator_id: i64) -> i64 {
    // ADR 0004 §4: event creation requires `event.create` (moderator/admin).
    // The helpers' callers pass a freshly-logged-in guest, so promote them
    // to moderator for the create to pass; the handler then auto-assigns the
    // `event/creator` role.
    grant_global_role(pool, creator_id, "moderator").await;
    let body = format!(r#"{{"name": "{}", "creatorId": {}}}"#, name, creator_id);
    let resp = post_json(pool, "/api/v1/events", &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "create event failed");
    let v: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    v["id"].as_i64().unwrap()
}

async fn create_merch(pool: &PgPool, event_id: i64, name: &str, group_name: &str) -> i64 {
    // Note: NO photoUrl, so photo_url stays NULL — this is the
    // exact scenario that triggered the #224 panic.
    let body = format!(r#"{{"name": "{}", "groupName": "{}"}}"#, name, group_name);
    let resp = post_json(pool, &format!("/api/v1/events/{}/merch", event_id), &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "create merch failed");
    let v: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    v["id"].as_i64().unwrap()
}

async fn set_inventory(pool: &PgPool, user_id: i64, merch_id: i64, status: &str, quantity: i32) {
    let body = format!(
        r#"{{"userId": {}, "merchId": {}, "status": "{}", "quantity": {}}}"#,
        user_id, merch_id, status, quantity
    );
    let resp = post_json(pool, "/api/v1/user/inventory", &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "set inventory failed");
}

async fn post_json(pool: &PgPool, uri: &str, body: &str) -> axum::response::Response {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap(),
    )
    .await
    .unwrap()
}
