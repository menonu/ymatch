use crate::common::*;

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
