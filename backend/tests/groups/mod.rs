use crate::common::*;

#[sqlx::test]
async fn admin_can_remove_group_and_all_of_its_live_references(pool: PgPool) {
    let (admin_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-removal-admin", "Removal Event").await;
    let merch_id = create_merch(&pool, event_id, "Test Merch", "test-group").await;
    let other_user_id = login_guest(&pool, "group-removal-peer", "token").await;

    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name) \
         VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(admin_id as i32)
    .bind(other_user_id as i32)
    .bind(event_id as i32)
    .bind("test-group")
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
        .bind("test-group")
        .execute(&pool)
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/events/{}/groups/test-group?user_id={}",
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
    .bind("test-group")
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
    .bind("test-group")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(favorite_count, 0);
}

#[sqlx::test]
async fn plain_user_cannot_remove_group(pool: PgPool) {
    // #380: group removal is gated by the global `group.delete` permission
    // (moderator + admin, plus the admin superuser bypass). A demoted plain
    // user must get 403 and leave the group / merch / matches untouched.
    let (actor_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-removal-denied", "Denied Event").await;
    let merch_id = create_merch(&pool, event_id, "Test Merch", "test-group").await;
    let peer_id = login_guest(&pool, "group-removal-denied-peer", "token").await;

    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name) \
         VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(actor_id as i32)
    .bind(peer_id as i32)
    .bind(event_id as i32)
    .bind("test-group")
    .fetch_one(&pool)
    .await
    .unwrap();

    grant_global_role(&pool, actor_id, "user").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/events/{}/groups/test-group?user_id={}",
                    event_id, actor_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    let group_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("test-group")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(group_count, 1, "plain user must not remove the group row");

    let merch_deleted: bool =
        sqlx::query_scalar("SELECT is_deleted FROM merchandise WHERE id = $1")
            .bind(merch_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(
        !merch_deleted,
        "plain user must not soft-delete group merchandise"
    );

    let match_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM matches WHERE id = $1")
        .bind(match_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(match_count, 1, "plain user must not clear group matches");
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
async fn test_group_photo_url_create_update_and_clear(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-photo-creator", "Photo Group Event").await;

    // Create with photo
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Art", "description": "with art", "photoUrl": "https://cdn.example/g1.png"}}"#,
                    event_id, creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(
        group["photoUrl"].as_str().unwrap(),
        "https://cdn.example/g1.png"
    );

    // Replace photo (overwrite)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(&format!("/api/v1/events/{}/groups/Art", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Art", "description": "with art", "photoUrl": "https://cdn.example/g2.png"}}"#,
                    event_id, creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(
        group["photoUrl"].as_str().unwrap(),
        "https://cdn.example/g2.png"
    );

    // Update description only — photo must remain
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(&format!("/api/v1/events/{}/groups/Art", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Art", "description": "updated text only"}}"#,
                    event_id, creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["description"].as_str().unwrap(), "updated text only");
    assert_eq!(
        group["photoUrl"].as_str().unwrap(),
        "https://cdn.example/g2.png"
    );

    // Clear photo with empty string
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(&format!("/api/v1/events/{}/groups/Art", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Art", "description": "updated text only", "photoUrl": ""}}"#,
                    event_id, creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(
        group.get("photoUrl").is_none() || group["photoUrl"].is_null(),
        "cleared photo_url should be absent/null, got {:?}",
        group.get("photoUrl")
    );

    // List includes photo when set again via PUT
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let _ = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(&format!("/api/v1/events/{}/groups/Art", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Art", "description": "d", "photoUrl": "https://cdn.example/g3.png"}}"#,
                    event_id, creator_id
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
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(
        body["groups"][0]["photoUrl"].as_str().unwrap(),
        "https://cdn.example/g3.png"
    );

    // #491: plain users can no longer POST create (would previously hijack
    // description). Re-create as the authorized creator: upsert must NOT
    // clobber an existing photo_url (#404 review).
    let other_id = login_guest(&pool, "group-photo-clobber", "tok").await;
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/groups", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Art", "description": "hostile", "photoUrl": "https://evil.example/x.png"}}"#,
            event_id, other_id
        ),
    )
    .await;
    assert_eq!(
        resp.status(),
        StatusCode::FORBIDDEN,
        "plain user must not create/upsert groups (#491)"
    );

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/groups", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Art", "description": "hostile", "photoUrl": "https://evil.example/x.png"}}"#,
                    event_id, creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(
        group["photoUrl"].as_str().unwrap(),
        "https://cdn.example/g3.png",
        "create upsert must not overwrite photo_url"
    );
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

// --- #425: display_name (cosmetic group label) + can_edit_group gating ---

/// POST a group row as `creator_id` and return immediately (response unused).
async fn create_group_row(pool: &PgPool, event_id: i64, creator_id: i64, name: &str) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/groups", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "{}"}}"#,
                    event_id, creator_id, name
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn creator_can_set_display_name(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-display-creator", "Display Event").await;
    create_group_row(&pool, event_id, creator_id, "Pins").await;

    // Set a display name; the internal group_name key must stay "Pins".
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Pins", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Pins", "description": "d", "displayName": "Enamel Pins!"}}"#,
            event_id, creator_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["groupName"].as_str().unwrap(), "Pins");
    assert_eq!(group["displayName"].as_str().unwrap(), "Enamel Pins!");

    // Persisted: listing reflects the display name, key unchanged.
    let resp = get_request(&pool, &format!("/api/v1/events/{}/groups", event_id)).await;
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["groups"][0]["groupName"].as_str().unwrap(), "Pins");
    assert_eq!(
        body["groups"][0]["displayName"].as_str().unwrap(),
        "Enamel Pins!"
    );
    let key: String =
        sqlx::query_scalar("SELECT group_name FROM merchandise_groups WHERE event_id = $1")
            .bind(event_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(key, "Pins");
}

#[sqlx::test]
async fn editor_can_edit_display_name(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-display-creator2", "Display Event 2").await;
    create_group_row(&pool, event_id, creator_id, "Stickers").await;

    // A second user is made an event editor (event/editor grants group.edit).
    let editor_id = login_guest(&pool, "group-display-editor", "tok").await;
    assign_event_role(&pool, editor_id, event_id, "editor").await;

    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Stickers", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Stickers", "description": "d", "displayName": "Vinyl Stickers"}}"#,
            event_id, editor_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["displayName"].as_str().unwrap(), "Vinyl Stickers");
}

#[sqlx::test]
async fn admin_and_moderator_can_edit_any_group_via_global_role(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-display-creator3", "Display Event 3").await;
    create_group_row(&pool, event_id, creator_id, "Lanyards").await;

    // Admin (superuser bypass) — not the creator, not an event member.
    let admin_id = login_guest(&pool, "group-display-admin", "tok").await;
    grant_global_role(&pool, admin_id, "admin").await;
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Lanyards", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Lanyards", "description": "d", "displayName": "Admin Renamed"}}"#,
            event_id, admin_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["displayName"].as_str().unwrap(), "Admin Renamed");

    // Moderator (group.edit.any satisfies group.edit).
    let mod_id = login_guest(&pool, "group-display-mod", "tok").await;
    grant_global_role(&pool, mod_id, "moderator").await;
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Lanyards", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Lanyards", "description": "d", "displayName": "Mod Renamed"}}"#,
            event_id, mod_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(group["displayName"].as_str().unwrap(), "Mod Renamed");
}

#[sqlx::test]
async fn non_creator_non_editor_display_name_forbidden(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-display-creator4", "Display Event 4").await;
    create_group_row(&pool, event_id, creator_id, "Buttons").await;

    // Seed a display name as the creator so the no-op assertion below is
    // load-bearing (a NULL→NULL result would not prove the forbidden edit was
    // a no-op).
    let _ = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Buttons", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Buttons", "description": "d", "displayName": "Creator Set"}}"#,
            event_id, creator_id
        ),
    )
    .await;

    // A plain viewer (no event role, no global override) cannot edit.
    let other_id = login_guest(&pool, "group-display-other", "tok").await;
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Buttons", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Buttons", "description": "d", "displayName": "Hostile"}}"#,
            event_id, other_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // display_name must be unchanged by the forbidden edit.
    let display: Option<String> = sqlx::query_scalar(
        "SELECT display_name FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("Buttons")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        display.as_deref(),
        Some("Creator Set"),
        "forbidden edit must not change display_name"
    );
}

#[sqlx::test]
async fn edit_missing_group_display_name_404(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-display-creator5", "Display Event 5").await;
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Nope", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Nope", "description": "d", "displayName": "X"}}"#,
            event_id, creator_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn empty_display_name_clears_it(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-display-creator6", "Display Event 6").await;
    create_group_row(&pool, event_id, creator_id, "Patches").await;

    // Set, then clear with an empty string.
    let _ = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Patches", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Patches", "description": "d", "displayName": "Iron-On Patches"}}"#,
            event_id, creator_id
        ),
    )
    .await;
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Patches", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Patches", "description": "d", "displayName": ""}}"#,
            event_id, creator_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let group: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(
        group.get("displayName").is_none() || group["displayName"].is_null(),
        "cleared display_name should be absent/null, got {:?}",
        group.get("displayName")
    );
    let display: Option<String> = sqlx::query_scalar(
        "SELECT display_name FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("Patches")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(
        display.is_none(),
        "display_name column must be NULL after clear"
    );
}

#[sqlx::test]
async fn display_name_edit_does_not_touch_merch_or_matches(pool: PgPool) {
    // The whole point of the display_name approach: the internal group_name
    // key — and every soft reference to it — is unchanged by a "rename".
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-display-creator7", "Display Event 7").await;
    let merch_id = create_merch(&pool, event_id, "Test Merch", "Keychains").await;
    let peer_id = login_guest(&pool, "group-display-peer", "tok").await;
    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name) \
         VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(creator_id as i32)
    .bind(peer_id as i32)
    .bind(event_id as i32)
    .bind("Keychains")
    .fetch_one(&pool)
    .await
    .unwrap();

    // "Rename" by setting a display name.
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Keychains", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Keychains", "description": "d", "displayName": "Collector Keychains"}}"#,
            event_id, creator_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    // Internal key + soft references are all still "Keychains".
    let merch_group: String =
        sqlx::query_scalar("SELECT group_name FROM merchandise WHERE id = $1")
            .bind(merch_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(merch_group, "Keychains");
    let match_group: String = sqlx::query_scalar("SELECT group_name FROM matches WHERE id = $1")
        .bind(match_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(match_group, "Keychains");
    let group_key: String = sqlx::query_scalar(
        "SELECT group_name FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("Keychains")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(group_key, "Keychains");
}

#[sqlx::test]
async fn my_event_role_reports_can_edit_group(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-display-creator8", "Display Event 8").await;

    // A plain viewer (no roles) cannot edit groups on this event.
    let viewer_id = login_guest(&pool, "group-display-viewer", "tok").await;
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/my-role?user_id={}", event_id, viewer_id),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let role: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    // proto3 omits default-false bools, so an absent canEditGroup means false.
    assert_eq!(role["canEditGroup"].as_bool().unwrap_or(false), false);

    // An event editor can.
    let editor_id = login_guest(&pool, "group-display-editor2", "tok").await;
    assign_event_role(&pool, editor_id, event_id, "editor").await;
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/my-role?user_id={}", event_id, editor_id),
    )
    .await;
    let role: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(role["canEditGroup"].as_bool().unwrap_or(false), true);

    // The event creator (event/creator grants group.edit) can too.
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/my-role?user_id={}", event_id, creator_id),
    )
    .await;
    let role: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(role["canEditGroup"].as_bool().unwrap_or(false), true);
}

// --- #430: admin dashboard list includes display_name ---

#[sqlx::test]
async fn admin_groups_list_includes_display_name_with_fallback(pool: PgPool) {
    // Two groups under one event: one with a cosmetic label, one without.
    // GET /api/v1/admin/groups must surface displayName when set and omit it
    // (or leave it null/absent) when unset so the dashboard can fall back to
    // the immutable group_name key.
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "admin-list-display", "Admin List Event").await;
    create_group_row(&pool, event_id, creator_id, "Pins").await;
    create_group_row(&pool, event_id, creator_id, "Stickers").await;

    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Pins", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Pins", "description": "d", "displayName": "Enamel Pins!"}}"#,
            event_id, creator_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    // #491: admin groups list requires staff + user_id.
    // create_test_user_and_event grants moderator to creator_id.
    let resp = get_request(
        &pool,
        &format!("/api/v1/admin/groups?user_id={}", creator_id),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let groups = body.as_array().expect("admin groups list is an array");

    let pins = groups
        .iter()
        .find(|g| g["groupName"].as_str() == Some("Pins"))
        .expect("Pins group present");
    assert_eq!(pins["eventId"].as_i64().unwrap(), event_id);
    assert_eq!(pins["groupName"].as_str().unwrap(), "Pins");
    assert_eq!(pins["displayName"].as_str().unwrap(), "Enamel Pins!");

    let stickers = groups
        .iter()
        .find(|g| g["groupName"].as_str() == Some("Stickers"))
        .expect("Stickers group present");
    assert_eq!(stickers["groupName"].as_str().unwrap(), "Stickers");
    assert!(
        stickers.get("displayName").is_none() || stickers["displayName"].is_null(),
        "unset display_name must be absent/null so UI falls back to group_name, got {:?}",
        stickers.get("displayName")
    );
}

// --- #491: group create requires active caller + merch.create ---

#[sqlx::test]
async fn test_create_group_rejects_plain_user(pool: PgPool) {
    let (_moderator, event_id) =
        create_test_user_and_event(pool.clone(), "grp-create-mod", "Gate Event").await;
    let plain = login_guest(&pool, "grp-create-plain", "t").await;

    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/groups", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Hijack", "description": "nope"}}"#,
            event_id, plain
        ),
    )
    .await;
    assert_eq!(
        resp.status(),
        StatusCode::FORBIDDEN,
        "plain user must not create groups / claim creator"
    );
}

#[sqlx::test]
async fn test_create_group_rejects_missing_event(pool: PgPool) {
    let plain = login_guest(&pool, "grp-create-missing-ev", "t").await;
    grant_global_role(&pool, plain, "moderator").await;

    let resp = post_json(
        &pool,
        "/api/v1/events/999999/groups",
        &format!(
            r#"{{"eventId": 999999, "userId": {}, "groupName": "Ghost", "description": "x"}}"#,
            plain
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}
