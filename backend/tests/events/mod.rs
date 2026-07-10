use crate::common::*;

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
