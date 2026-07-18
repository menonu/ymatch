use crate::common::*;

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
    // No merchandise_groups row yet → display_name absent/null (#466).
    assert!(
        groups[0].get("displayName").is_none() || groups[0]["displayName"].is_null(),
        "unset display_name must be absent/null, got {:?}",
        groups[0].get("displayName")
    );
}

/// #466: favorite-group list joins merchandise_groups.display_name so home
/// chips can show the cosmetic label without a second request.
#[sqlx::test]
async fn test_group_favorite_list_includes_display_name(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "gfav-display-user", "Group Fav Display Event")
            .await;

    // Create a formal group row with a cosmetic display_name.
    sqlx::query(
        "INSERT INTO merchandise_groups (event_id, group_name, display_name, created_by)
         VALUES ($1, 'Pins', 'Enamel Pins!', $2)",
    )
    .bind(event_id as i32)
    .bind(user_id as i32)
    .execute(&pool)
    .await
    .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/favorite_group", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "groupName": "Pins", "isFavorite": true}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

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
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0]["groupName"], "Pins");
    assert_eq!(groups[0]["displayName"].as_str().unwrap(), "Enamel Pins!");
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
