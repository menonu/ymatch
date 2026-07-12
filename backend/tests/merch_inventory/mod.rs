use crate::common::*;

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
                .body(Body::from(format!(
                    r#"{{"name": "Test Item", "groupName": "Group A", "creatorId": {}}}"#,
                    user_id
                )))
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

#[sqlx::test]
async fn test_create_merch_duplicate_name_in_same_group_rejected(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "dup-name-user", "Dup Name Event").await;

    // First "a" in group G succeeds.
    let _ = create_merch(&pool, event_id, "a", "G").await;

    // Second "a" in the SAME group G must be rejected with 400. Post as the
    // event creator so the ADR 0005 create gate passes and the rejection is
    // the duplicate-name error (not the creator_id-required 400).
    let body = format!(
        r#"{{"name": "a", "groupName": "G", "creatorId": {}}}"#,
        user_id
    );
    let resp = post_json(&pool, &format!("/api/v1/events/{}/merch", event_id), &body).await;
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
                .body(Body::from(format!(
                    r#"{{"name": "Inv Item", "groupName": "Test", "creatorId": {}}}"#,
                    user_id
                )))
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

/// #395 / #266: a real Postgres CHECK violation over HTTP must map to 400
/// with a safe body (defense-in-depth for `From<sqlx::Error>` wire-up).
///
/// Inventory has `CHECK (status IN ('HAVE', 'WANT', 'TRADE'))`. An invalid
/// status is not pre-validated in the handler, so the DB constraint is what
/// rejects the write — this is the blanket CHECK → 400 path.
#[sqlx::test]
async fn test_inventory_check_violation_returns_400_safe_body(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "check-inv-user", "Check Inv Event").await;

    let merch_id = create_merch(&pool, event_id, "Check Item", "G").await;

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/user/inventory")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "merchId": {}, "status": "NOT_A_STATUS", "quantity": 1}}"#,
                    user_id, merch_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let body = body_to_string(resp.into_body()).await;
    // Mapped message from From<sqlx::Error> CHECK handling — never raw SQL.
    assert!(
        body.contains("Invalid request data"),
        "expected safe CHECK mapping body, got: {body}"
    );
    assert!(
        !body.contains("check constraint")
            && !body.contains("inventory_status_check")
            && !body.contains("23514"),
        "client body must not leak SQL/CHECK detail, got: {body}"
    );
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
