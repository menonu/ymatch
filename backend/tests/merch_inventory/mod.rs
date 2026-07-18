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

    // The soft-deleted row must not occupy the name: re-creating "a" succeeds
    // as a *new* row (ADR 0008: no revival).
    let merch_id2 = create_merch(&pool, event_id, "a", "G").await;
    assert!(merch_id2 > 0);
    assert_ne!(
        merch_id2, merch_id,
        "re-creation must insert a new row, not revive the soft-deleted one"
    );
    let old_still_deleted: bool =
        sqlx::query_scalar("SELECT is_deleted FROM merchandise WHERE id = $1")
            .bind(merch_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(
        old_still_deleted,
        "original soft-deleted row must stay deleted"
    );
    let new_is_live: bool = sqlx::query_scalar("SELECT is_deleted FROM merchandise WHERE id = $1")
        .bind(merch_id2 as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(!new_is_live, "new row must be live");
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
async fn test_soft_delete_merch_without_inventory(pool: PgPool) {
    // ADR 0008: delete is always soft-delete — no inventory is no longer a
    // hard-delete trigger.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "softdel-noinv-user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    grant_global_role(&pool, user_id, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "SoftDel NoInv Event", "creatorId": {}}}"#,
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
                    r#"{{"name": "SoftDel NoInv Item", "groupName": "Test", "creatorId": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let merch: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_id = merch["id"].as_i64().unwrap();

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

    let row = sqlx::query("SELECT is_deleted, trade_enabled FROM merchandise WHERE id = $1")
        .bind(merch_id as i32)
        .fetch_optional(&pool)
        .await
        .unwrap()
        .expect("row must remain after soft-delete");
    assert!(sqlx::Row::get::<bool, _>(&row, "is_deleted"));
    assert!(!sqlx::Row::get::<bool, _>(&row, "trade_enabled"));
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

// --- ADR 0008 / #423: soft-delete cancels active matches + holder visibility ---

/// Seed a match between two users with a match_items leg on `merch_id`.
async fn seed_match_with_item(
    pool: &PgPool,
    user1: i64,
    user2: i64,
    event_id: i64,
    group_name: &str,
    merch_id: i64,
    giver: i64,
    status: &str,
) -> i64 {
    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name, status)
         VALUES ($1, $2, $3, $4, $5) RETURNING id",
    )
    .bind(user1 as i32)
    .bind(user2 as i32)
    .bind(event_id as i32)
    .bind(group_name)
    .bind(status)
    .fetch_one(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO match_items (match_id, giver_user_id, merch_id, quantity)
         VALUES ($1, $2, $3, 1)",
    )
    .bind(match_id)
    .bind(giver as i32)
    .bind(merch_id as i32)
    .execute(pool)
    .await
    .unwrap();
    match_id as i64
}

#[sqlx::test]
async fn test_delete_merch_cancels_active_matches_leaves_completed(pool: PgPool) {
    // ADR 0008: soft-delete moves PENDING/OFFERED/ACCEPTED matches that
    // reference the merch via match_items to CANCELLED; COMPLETED stays;
    // a SYSTEM message is posted per cancelled match.
    // Each match needs a unique (user1, user2, event, group) pair.
    let (creator, event_id) =
        create_test_user_and_event(pool.clone(), "cancel-del-creator", "Cancel Del Event").await;
    let peer1 = login_guest(&pool, "cancel-del-peer1", "t").await;
    let peer2 = login_guest(&pool, "cancel-del-peer2", "t").await;
    let peer3 = login_guest(&pool, "cancel-del-peer3", "t").await;
    let peer4 = login_guest(&pool, "cancel-del-peer4", "t").await;

    let merch_id = create_merch(&pool, event_id, "Cancel Target", "G").await;
    // qty-0 inventory + match_items would FK-fail the old hard-delete path;
    // soft-delete always succeeds.
    sqlx::query(
        "INSERT INTO inventory (user_id, merch_id, status, quantity)
         VALUES ($1, $2, 'HAVE', 0)
         ON CONFLICT (user_id, merch_id, status) DO UPDATE SET quantity = 0",
    )
    .bind(creator as i32)
    .bind(merch_id as i32)
    .execute(&pool)
    .await
    .unwrap();

    let pending = seed_match_with_item(
        &pool, creator, peer1, event_id, "G", merch_id, creator, "PENDING",
    )
    .await;
    let offered = seed_match_with_item(
        &pool, creator, peer2, event_id, "G", merch_id, creator, "OFFERED",
    )
    .await;
    let accepted = seed_match_with_item(
        &pool, creator, peer3, event_id, "G", merch_id, creator, "ACCEPTED",
    )
    .await;
    let completed = seed_match_with_item(
        &pool,
        creator,
        peer4,
        event_id,
        "G",
        merch_id,
        creator,
        "COMPLETED",
    )
    .await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch_id, creator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        resp.status(),
        StatusCode::OK,
        "delete with match_items must succeed"
    );

    for (id, expected) in [
        (pending, "CANCELLED"),
        (offered, "CANCELLED"),
        (accepted, "CANCELLED"),
        (completed, "COMPLETED"),
    ] {
        let s: String = sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
            .bind(id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(s, expected, "match {id} status");
    }

    for id in [pending, offered, accepted] {
        let content: String = sqlx::query_scalar(
            "SELECT content FROM messages
             WHERE match_id = $1 AND message_type = 'SYSTEM'",
        )
        .bind(id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            content, "MERCH_DELETED",
            "cancelled match {id} should post the merch-delete reason code"
        );
    }
    let completed_msgs: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM messages
         WHERE match_id = $1 AND message_type = 'SYSTEM'",
    )
    .bind(completed as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(completed_msgs, 0, "COMPLETED must not get a cancel message");

    // ADR 0010: CANCELLED is returned so the Done tab can show it; REJECTED stays hidden.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/api/v1/matches/user/{}", creator))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let matches: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let statuses: Vec<&str> = matches
        .iter()
        .map(|m| m["status"].as_str().unwrap_or(""))
        .collect();
    assert!(
        statuses.iter().any(|s| *s == "CANCELLED"),
        "CANCELLED must surface in list for Done tab, got {statuses:?}"
    );
    assert!(
        statuses.iter().any(|s| *s == "COMPLETED"),
        "COMPLETED history should still list"
    );
    assert!(
        !statuses.iter().any(|s| *s == "REJECTED"),
        "REJECTED stays hidden, got {statuses:?}"
    );
}

#[sqlx::test]
async fn test_deleted_merch_holder_visibility(pool: PgPool) {
    // ADR 0008: creator + HAVE-holder see deleted merch (marked); others do not.
    // Search excludes deleted even for the holder.
    let (creator, event_id) =
        create_test_user_and_event(pool.clone(), "holder-vis-creator", "Holder Vis Event").await;
    let holder = login_guest(&pool, "holder-vis-holder", "t").await;
    let stranger = login_guest(&pool, "holder-vis-stranger", "t").await;

    let merch_id = create_merch(&pool, event_id, "HolderVis Item", "G").await;
    set_inventory(&pool, holder, merch_id, "HAVE", 2).await;

    // Soft-delete as creator.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch_id, creator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Creator sees it, marked deleted.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/api/v1/events/{}/merch?user_id={}",
                    event_id, creator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let items: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let found = items.iter().find(|m| m["id"].as_i64() == Some(merch_id));
    assert!(found.is_some(), "creator must see deleted merch");
    assert_eq!(found.unwrap()["isDeleted"], true);

    // HAVE-holder sees it marked deleted.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/api/v1/events/{}/merch?user_id={}",
                    event_id, holder
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let items: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let found = items.iter().find(|m| m["id"].as_i64() == Some(merch_id));
    assert!(found.is_some(), "HAVE-holder must see deleted merch");
    assert_eq!(found.unwrap()["isDeleted"], true);

    // Holder inventory marks isDeleted.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/api/v1/user/{}/inventory", holder))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let inv: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let row = inv
        .iter()
        .find(|i| i["merchId"].as_i64() == Some(merch_id))
        .expect("holder inventory must still list deleted merch");
    assert_eq!(row["isDeleted"], true);

    // Stranger does not see it in the event merch list.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/api/v1/events/{}/merch?user_id={}",
                    event_id, stranger
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let items: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(
        items.iter().all(|m| m["id"].as_i64() != Some(merch_id)),
        "non-holder must not see deleted merch"
    );

    // Search is live-only — even the holder cannot find the deleted name.
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/search?q=HolderVis")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let results: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(
        results.iter().all(|r| r["id"].as_i64() != Some(merch_id)),
        "search must exclude soft-deleted merch"
    );
}

#[sqlx::test]
async fn test_offer_rejects_soft_deleted_merch(pool: PgPool) {
    // ADR 0008: proposing a soft-deleted merch id must fail.
    // ADR 0010: legs-less PENDING whose only capacity was the deleted item
    // is cancelled on delete; keep a second live merch so mutual capacity
    // remains and the match stays PENDING for the offer-rejection check.
    let (creator, event_id) =
        create_test_user_and_event(pool.clone(), "offer-del-creator", "Offer Del Event").await;
    let peer = login_guest(&pool, "offer-del-peer", "t").await;

    let merch_id = create_merch(&pool, event_id, "OfferDel Item", "G").await;
    let merch_live = create_merch(&pool, event_id, "OfferDel Live", "G").await;
    // Mutual capacity via live item (both directions) + the soon-deleted item.
    set_inventory(&pool, creator, merch_id, "TRADE", 2).await;
    set_inventory(&pool, peer, merch_id, "WANT", 2).await;
    set_inventory(&pool, creator, merch_live, "TRADE", 1).await;
    set_inventory(&pool, peer, merch_live, "WANT", 1).await;
    set_inventory(&pool, peer, merch_live, "TRADE", 1).await;
    set_inventory(&pool, creator, merch_live, "WANT", 1).await;

    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name, status)
         VALUES ($1, $2, $3, 'G', 'PENDING') RETURNING id",
    )
    .bind(creator as i32)
    .bind(peer as i32)
    .bind(event_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();

    // Soft-delete one merch; capacity via live item remains → match stays PENDING.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch_id, creator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let status: String = sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
        .bind(match_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        status, "PENDING",
        "PENDING with remaining mutual capacity stays active"
    );

    // Offer of the deleted merch must be rejected.
    let body = format!(
        r#"{{"userId": {}, "items": [{{"merchId": {}, "giverUserId": {}, "quantity": 1}}]}}"#,
        creator, merch_id, creator
    );
    let resp = post_json(&pool, &format!("/api/v1/matches/{}/offer", match_id), &body).await;
    assert_eq!(
        resp.status(),
        StatusCode::BAD_REQUEST,
        "offer of soft-deleted merch must fail"
    );
}

// --- ADR 0010 / #452: inventory mutual-capacity invalidation ---

/// Two users + two merch in group G with mutual TRADE/WANT of `qty` each way.
/// Inserts a match at `status` (no match_items). Returns (u1, u2, event, m_a, m_b, match_id).
async fn seed_mutual_capacity_match(
    pool: &PgPool,
    label: &str,
    status: &str,
    qty: i32,
) -> (i64, i64, i64, i64, i64, i32) {
    let (u1, event_id) =
        create_test_user_and_event(pool.clone(), &format!("{label}-u1"), &format!("{label} Ev"))
            .await;
    let u2 = login_guest(pool, &format!("{label}-u2"), "t").await;
    let m_a = create_merch(pool, event_id, &format!("{label} A"), "G").await;
    let m_b = create_merch(pool, event_id, &format!("{label} B"), "G").await;
    // u1 TRADEST A, WANTS B; u2 TRADEST B, WANTS A
    set_inventory(pool, u1, m_a, "TRADE", qty).await;
    set_inventory(pool, u1, m_b, "WANT", qty).await;
    set_inventory(pool, u2, m_b, "TRADE", qty).await;
    set_inventory(pool, u2, m_a, "WANT", qty).await;

    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name, status)
         VALUES ($1, $2, $3, 'G', $4) RETURNING id",
    )
    .bind(u1 as i32)
    .bind(u2 as i32)
    .bind(event_id as i32)
    .bind(status)
    .fetch_one(pool)
    .await
    .unwrap();
    (u1, u2, event_id, m_a, m_b, match_id)
}

async fn match_status(pool: &PgPool, match_id: i32) -> String {
    sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
        .bind(match_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[sqlx::test]
async fn test_inventory_cap_partial_reduction_keeps_pending(pool: PgPool) {
    // 2:2 → 2:1 still both sides positive → keep
    let (u1, _u2, _e, m_a, _m_b, match_id) =
        seed_mutual_capacity_match(&pool, "cap-keep", "PENDING", 2).await;

    set_inventory(&pool, u1, m_a, "TRADE", 1).await; // cap(u1→u2) becomes 1; other side still 2

    assert_eq!(
        match_status(&pool, match_id).await,
        "PENDING",
        "2:2 → 2:1 must keep the match"
    );
}

#[sqlx::test]
async fn test_inventory_cap_zero_cancels_pending_offered_accepted(pool: PgPool) {
    for status in ["PENDING", "OFFERED", "ACCEPTED"] {
        let label = format!("cap-z-{status}");
        let (u1, _u2, _e, m_a, _m_b, match_id) =
            seed_mutual_capacity_match(&pool, &label, status, 2).await;

        // Zero u1's TRADE of A → cap(u1→u2)=0 → cancel
        set_inventory(&pool, u1, m_a, "TRADE", 0).await;

        assert_eq!(
            match_status(&pool, match_id).await,
            "CANCELLED",
            "{status} must cancel when either cap hits 0"
        );

        let msg: String = sqlx::query_scalar(
            "SELECT content FROM messages WHERE match_id = $1 AND message_type = 'SYSTEM'",
        )
        .bind(match_id)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            msg, "INVENTORY_CAPACITY",
            "SYSTEM message should be the stable inventory cancel reason code, got {msg}"
        );
    }
}

#[sqlx::test]
async fn test_inventory_cap_zero_leaves_completed(pool: PgPool) {
    let (u1, _u2, _e, m_a, _m_b, match_id) =
        seed_mutual_capacity_match(&pool, "cap-done", "COMPLETED", 2).await;

    set_inventory(&pool, u1, m_a, "TRADE", 0).await;

    assert_eq!(
        match_status(&pool, match_id).await,
        "COMPLETED",
        "COMPLETED is historical and must not be cancelled"
    );
}

#[sqlx::test]
async fn test_list_includes_cancelled_after_inventory_cap_zero(pool: PgPool) {
    let (u1, _u2, _e, m_a, _m_b, match_id) =
        seed_mutual_capacity_match(&pool, "cap-list", "PENDING", 1).await;

    set_inventory(&pool, u1, m_a, "TRADE", 0).await;
    assert_eq!(match_status(&pool, match_id).await, "CANCELLED");

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/api/v1/matches/user/{}", u1))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let matches: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(
        matches
            .iter()
            .any(|m| m["id"].as_i64() == Some(match_id as i64) && m["status"] == "CANCELLED"),
        "list_for_user must return CANCELLED match, got {matches:?}"
    );
}

#[sqlx::test]
async fn test_delete_merch_cancels_legsless_pending_when_cap_zero(pool: PgPool) {
    // ADR 0010 closes ADR 0008 gap: PENDING without match_items is cancelled
    // when soft-delete removes a direction of mutual capacity.
    // Setup: cap(u1→u2) only via m_a; cap(u2→u1) only via m_b.
    // Deleting m_a zeros cap(u1→u2) → CANCELLED even with no match_items.
    let (u1, _u2, event_id, m_a, _m_b, match_id) =
        seed_mutual_capacity_match(&pool, "cap-del-pending", "PENDING", 1).await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, m_a, u1
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    assert_eq!(
        match_status(&pool, match_id).await,
        "CANCELLED",
        "legs-less PENDING must cancel when capacity is gone after delete"
    );
}
