use crate::common::*;

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
                .body(Body::from(format!(
                    r#"{{"name": "Card A", "photoUrl": "", "groupName": "Cards", "creatorId": {}}}"#,
                    user1_id
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
                    r#"{{"name": "Card B", "photoUrl": "", "groupName": "Cards", "creatorId": {}}}"#,
                    user1_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch_b: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let merch_b_id = merch_b["id"].as_i64().unwrap();

    // 3. User1: TRADE+HAVE Card A, WANT Card B; User2: TRADE+HAVE Card B, WANT Card A.
    // HAVE is seeded so default apply (#429) can assert giver HAVE decrement.
    for (uid, mid, status, qty) in [
        (user1_id, merch_a_id, "TRADE", 1),
        (user1_id, merch_a_id, "HAVE", 2),
        (user1_id, merch_b_id, "WANT", 1),
        (user2_id, merch_b_id, "TRADE", 1),
        (user2_id, merch_b_id, "HAVE", 2),
        (user2_id, merch_a_id, "WANT", 1),
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

    // 10. Verify User1: gave Card A (TRADE=0, HAVE 2→1), received Card B (HAVE=1)
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
    let u1_have_a = inv1
        .iter()
        .find(|i| i["merchId"] == merch_a_id && i["status"] == "HAVE");
    assert_eq!(
        u1_have_a
            .and_then(|i| i.get("quantity").and_then(|v| v.as_i64()))
            .unwrap_or(-1),
        1,
        "User1 HAVE Card A should decrement 2→1 by default (#429)"
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

    // Verify User2: gave Card B (TRADE=0, HAVE 2→1), received Card A (HAVE=1)
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
    let u2_have_b = inv2
        .iter()
        .find(|i| i["merchId"] == merch_b_id && i["status"] == "HAVE");
    assert_eq!(
        u2_have_b
            .and_then(|i| i.get("quantity").and_then(|v| v.as_i64()))
            .unwrap_or(-1),
        1,
        "User2 HAVE Card B should decrement 2→1 by default (#429)"
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

/// #429: `skipHaveDecrement: true` leaves giver HAVE unchanged (legacy).
#[sqlx::test]
async fn test_apply_inventory_skip_have_decrement(pool: PgPool) {
    let user1_id = login_guest(&pool, "u1-skip-have", "tok1").await;
    let user2_id = login_guest(&pool, "u2-skip-have", "tok2").await;
    let event_id = create_event(&pool, "Skip HAVE Event", user1_id).await;
    let card_a = create_merch(&pool, event_id, "Skip A", "skip-group").await;
    let card_b = create_merch(&pool, event_id, "Skip B", "skip-group").await;

    set_inventory(&pool, user1_id, card_a, "TRADE", 1).await;
    set_inventory(&pool, user1_id, card_a, "HAVE", 2).await;
    set_inventory(&pool, user1_id, card_b, "WANT", 1).await;
    set_inventory(&pool, user2_id, card_b, "TRADE", 1).await;
    set_inventory(&pool, user2_id, card_b, "HAVE", 2).await;
    set_inventory(&pool, user2_id, card_a, "WANT", 1).await;

    backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matcher");

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
    let match_id = matches[0]["id"].as_i64().unwrap();

    let offer_body = format!(
        r#"{{"userId": {}, "items": [
            {{"merchId": {}, "giverUserId": {}, "quantity": 1}},
            {{"merchId": {}, "giverUserId": {}, "quantity": 1}}
        ]}}"#,
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
        StatusCode::OK
    );
    assert_eq!(
        post_json(
            &pool,
            &format!("/api/v1/matches/{}/status", match_id),
            &format!(r#"{{"status": "ACCEPTED", "userId": {}}}"#, user2_id)
        )
        .await
        .status(),
        StatusCode::OK
    );
    assert_eq!(
        post_json(
            &pool,
            &format!("/api/v1/matches/{}/status", match_id),
            &format!(r#"{{"status": "COMPLETED", "userId": {}}}"#, user1_id)
        )
        .await
        .status(),
        StatusCode::OK
    );

    // Apply with skipHaveDecrement for user1 (giver of Card A).
    assert_eq!(
        post_json(
            &pool,
            &format!("/api/v1/matches/{}/apply-inventory", match_id),
            &format!(r#"{{"userId": {}, "skipHaveDecrement": true}}"#, user1_id)
        )
        .await
        .status(),
        StatusCode::OK
    );

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
    let inv1: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    // quantity may be omitted when 0 (proto3 JSON default); use json_i64.
    let trade_a = inv1
        .iter()
        .find(|i| json_i64(i, "merchId") == card_a && i["status"] == "TRADE")
        .map(|i| json_i64(i, "quantity"))
        .unwrap_or(-1);
    let have_a = inv1
        .iter()
        .find(|i| json_i64(i, "merchId") == card_a && i["status"] == "HAVE")
        .map(|i| json_i64(i, "quantity"))
        .unwrap_or(-1);
    assert_eq!(trade_a, 0, "TRADE still decrements with skip flag");
    assert_eq!(
        have_a, 2,
        "HAVE must remain 2 when skipHaveDecrement is true"
    );
    let have_b = inv1
        .iter()
        .find(|i| json_i64(i, "merchId") == card_b && i["status"] == "HAVE")
        .map(|i| json_i64(i, "quantity"))
        .unwrap_or(-1);
    assert_eq!(have_b, 1, "receiver HAVE still increments");
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
        // ADR 0005: merch creation is gated by `merch.create` (event scope);
        // post as the event creator (event/creator role), resolved from the DB.
        let creator_id: Option<i32> =
            sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
                .bind(event_id as i32)
                .fetch_one(pool)
                .await
                .unwrap();
        let creator_id = creator_id.expect("test event must have a creator to create merch");
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(&format!("/api/v1/events/{}/merch", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"name": "{}", "photoUrl": "", "groupName": "Cards", "creatorId": {}}}"#,
                        name, creator_id
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
        // ADR 0005: merch creation is gated by `merch.create` (event scope);
        // post as the event creator (event/creator role), resolved from the DB.
        let creator_id: Option<i32> =
            sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
                .bind(event_id as i32)
                .fetch_one(pool)
                .await
                .unwrap();
        let creator_id = creator_id.expect("test event must have a creator to create merch");
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(&format!("/api/v1/events/{}/merch", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"name": "{}", "photoUrl": "", "groupName": "Cards", "creatorId": {}}}"#,
                        name, creator_id
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
    // No display_name set on the group → groupDisplayName absent/null (#466).
    assert!(
        matches[0].get("groupDisplayName").is_none() || matches[0]["groupDisplayName"].is_null(),
        "unset groupDisplayName must be absent/null, got {:?}",
        matches[0].get("groupDisplayName")
    );
}

/// #466: match list joins merchandise_groups.display_name so the trade card
/// can show the cosmetic label while keeping group_name as the key.
#[sqlx::test]
async fn test_match_carries_group_display_name(pool: PgPool) {
    let (_match_id, user1_id, _user2_id, _merch_a_id, _merch_b_id) =
        setup_pending_trade_match_quantities(pool.clone(), 2, 2, 2, 2).await;

    // Resolve the match's event_id so we can set display_name on its group.
    let (event_id,): (i32,) =
        sqlx::query_as("SELECT event_id FROM matches WHERE user1_id = $1 OR user2_id = $1 LIMIT 1")
            .bind(user1_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();

    sqlx::query(
        "INSERT INTO merchandise_groups (event_id, group_name, display_name)
         VALUES ($1, 'Cards', 'Trading Cards')
         ON CONFLICT (event_id, group_name)
         DO UPDATE SET display_name = EXCLUDED.display_name",
    )
    .bind(event_id)
    .execute(&pool)
    .await
    .unwrap();

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
    assert_eq!(matches[0]["groupName"].as_str().unwrap(), "Cards");
    assert_eq!(
        matches[0]["groupDisplayName"].as_str().unwrap(),
        "Trading Cards"
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

// --- ADR 0012 / #477: rematch after REJECTED / CANCELLED ---

async fn list_user_matches(pool: &PgPool, user_id: i64) -> Vec<serde_json::Value> {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/user/{}", user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap()
}

async fn reject_match(pool: &PgPool, match_id: i64, user_id: i64) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/status", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "status": "REJECTED"}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK, "reject should succeed");
}

#[sqlx::test]
async fn test_rematch_after_reject_reopens_same_row(pool: PgPool) {
    let (match_id, user1_id, user2_id, merch_a_id, merch_b_id) =
        setup_pending_trade_match(pool.clone()).await;

    // Put legs on the table so rematch must clear them (reject also deletes
    // items; rematch must leave legs empty either way).
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

    reject_match(&pool, match_id, user1_id).await;

    let status: String = sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(status, "REJECTED");
    // REJECTED is hidden from list.
    let listed = list_user_matches(&pool, user1_id).await;
    assert!(
        !listed.iter().any(|m| m["id"].as_i64() == Some(match_id)),
        "REJECTED must stay hidden before rematch"
    );

    let rematched = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matcher after reject");
    assert!(rematched >= 1, "matcher should reopen rejected match");

    let status: String = sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(status, "PENDING", "same row reopened to PENDING");

    let rematch_count: i32 = sqlx::query_scalar("SELECT rematch_count FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(rematch_count, 1);

    let last_terminal: String =
        sqlx::query_scalar("SELECT last_terminal_status FROM matches WHERE id = $1")
            .bind(match_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(last_terminal, "REJECTED");

    let last_terminal_at: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("SELECT last_terminal_at FROM matches WHERE id = $1")
            .bind(match_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(
        last_terminal_at.is_some(),
        "last_terminal_at set on rematch"
    );

    let legs: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM match_items WHERE match_id = $1")
            .bind(match_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(legs, 0, "rematch clears match_items");

    let offered_by: Option<i32> =
        sqlx::query_scalar("SELECT offered_by FROM matches WHERE id = $1")
            .bind(match_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(offered_by.is_none(), "rematch clears offered_by");

    let msg: String = sqlx::query_scalar(
        "SELECT content FROM messages WHERE match_id = $1 AND message_type = 'SYSTEM'
         ORDER BY id DESC LIMIT 1",
    )
    .bind(match_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(msg, "REMATCH_AFTER_REJECTED");

    // Only one row for the pair+group.
    let row_count: i64 = sqlx::query_scalar("SELECT COUNT(*)::bigint FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(row_count, 1);

    let listed = list_user_matches(&pool, user1_id).await;
    let m = listed
        .iter()
        .find(|m| m["id"].as_i64() == Some(match_id))
        .expect("rematched PENDING must surface in list");
    assert_eq!(m["status"], "PENDING");
    assert_eq!(m["rematchCount"].as_i64(), Some(1));
    assert_eq!(m["lastTerminalStatus"].as_str(), Some("REJECTED"));
    assert!(m["lastTerminalAt"].as_str().is_some());
}

#[sqlx::test]
async fn test_rematch_after_cancel_when_capacity_restored(pool: PgPool) {
    let (match_id, user1_id, _user2_id, merch_a_id, _merch_b_id) =
        setup_pending_trade_match(pool.clone()).await;

    // Zero TRADE → ADR 0010 CANCELLED.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/user/inventory")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "merchId": {}, "status": "TRADE", "quantity": 0}}"#,
                    user1_id, merch_a_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let status: String = sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(status, "CANCELLED");

    // Restore mutual capacity.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/user/inventory")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "merchId": {}, "status": "TRADE", "quantity": 1}}"#,
                    user1_id, merch_a_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let rematched = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matcher after cancel restore");
    assert!(rematched >= 1, "matcher should reopen cancelled match");

    let status: String = sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(status, "PENDING");

    let last_terminal: String =
        sqlx::query_scalar("SELECT last_terminal_status FROM matches WHERE id = $1")
            .bind(match_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(last_terminal, "CANCELLED");

    let msg: String = sqlx::query_scalar(
        "SELECT content FROM messages WHERE match_id = $1 AND message_type = 'SYSTEM'
         AND content = 'REMATCH_AFTER_CANCELLED' LIMIT 1",
    )
    .bind(match_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(msg, "REMATCH_AFTER_CANCELLED");

    let listed = list_user_matches(&pool, user1_id).await;
    let m = listed
        .iter()
        .find(|m| m["id"].as_i64() == Some(match_id))
        .expect("rematched after cancel must list as PENDING");
    assert_eq!(m["status"], "PENDING");
    assert_eq!(m["lastTerminalStatus"].as_str(), Some("CANCELLED"));
    assert_eq!(m["rematchCount"].as_i64(), Some(1));
}

#[sqlx::test]
async fn test_rematch_skips_completed(pool: PgPool) {
    let (match_id, _user1_id, _user2_id, _a, _b) = setup_pending_trade_match(pool.clone()).await;

    sqlx::query("UPDATE matches SET status = 'COMPLETED' WHERE id = $1")
        .bind(match_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    let created = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matcher");
    assert_eq!(created, 0, "COMPLETED must not rematch or insert");

    let status: String = sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(status, "COMPLETED");

    let rematch_count: i32 = sqlx::query_scalar("SELECT rematch_count FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(rematch_count, 0);
}

#[sqlx::test]
async fn test_matcher_does_not_duplicate_active_pending(pool: PgPool) {
    let (match_id, _user1_id, _user2_id, _a, _b) = setup_pending_trade_match(pool.clone()).await;

    let created = backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("second matcher pass");
    assert_eq!(created, 0, "active PENDING must not rematch or insert");

    let total: i64 = sqlx::query_scalar("SELECT COUNT(*)::bigint FROM matches")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total, 1);

    let status: String = sqlx::query_scalar("SELECT status FROM matches WHERE id = $1")
        .bind(match_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(status, "PENDING");
}
