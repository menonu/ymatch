use crate::common::*;

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
    // ADR 0005: merch creation is gated by `merch.create` (event scope). u1 is
    // the event creator (authorized); grant u2 the event/editor role so it can
    // create its own merch (creator_id = u2) for the match fixture below.
    assign_event_role(&pool, u2, event_id, "editor").await;
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
                        r#"{{"name": "M{creator}", "groupName": "G", "creatorId": {creator}}}"#
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
async fn test_inventory_apply_trade_delta_have_decrement(pool: PgPool) {
    let (u1, _, _, merch_for_u1, _) = setup_pending_match_with_merch(&pool).await;

    // Seed a HAVE row of 5, then decrement by 2 via signed delta_have.
    let mut tx = pool.begin().await.unwrap();
    sqlx::query(
        "INSERT INTO inventory (user_id, merch_id, status, quantity) VALUES ($1, $2, 'HAVE', 5)",
    )
    .bind(u1 as i32)
    .bind(merch_for_u1)
    .execute(&mut *tx)
    .await
    .unwrap();

    let inv = backend::repositories::inventory::InventoryRepository::new(pool.clone());
    inv.apply_trade_delta(&mut *tx, u1 as i32, merch_for_u1, 0, -2)
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
    assert_eq!(qty.0, 3, "HAVE started at 5, decremented by 2");

    // Over-decrement clamps at 0.
    inv.apply_trade_delta(&mut *tx, u1 as i32, merch_for_u1, 0, -10)
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
    assert_eq!(qty.0, 0, "HAVE decrement clamps at 0");
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
