use crate::common::*;

#[sqlx::test]
async fn admin_can_remove_group_and_all_of_its_live_references(pool: PgPool) {
    let (admin_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-removal-admin", "Removal Event").await;
    let merch_id = create_merch(&pool, event_id, "Acrylic stand", "アクスタ").await;
    let other_user_id = login_guest(&pool, "group-removal-peer", "token").await;

    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name) \
         VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(admin_id as i32)
    .bind(other_user_id as i32)
    .bind(event_id as i32)
    .bind("アクスタ")
    .fetch_one(&pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO messages (match_id, sender_id, content) VALUES ($1, $2, 'hello')")
        .bind(match_id)
        .bind(admin_id as i32)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO group_favorites (user_id, event_id, group_name) VALUES ($1, $2, $3)")
        .bind(admin_id as i32)
        .bind(event_id as i32)
        .bind("アクスタ")
        .execute(&pool)
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/events/{}/groups/%E3%82%A2%E3%82%AF%E3%82%B9%E3%82%BF?user_id={}",
                    event_id, admin_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let group_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("アクスタ")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(group_count, 0);
    let merch_deleted: bool =
        sqlx::query_scalar("SELECT is_deleted FROM merchandise WHERE id = $1")
            .bind(merch_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(merch_deleted);
    let match_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM matches WHERE id = $1")
        .bind(match_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(match_count, 0);
    let favorite_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM group_favorites WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("アクスタ")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(favorite_count, 0);
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
