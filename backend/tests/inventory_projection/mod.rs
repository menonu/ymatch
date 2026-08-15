//! HTTP tests for #427 projected inventory on GET /api/v1/user/:id/inventory.

use crate::common::*;

fn find_row<'a>(
    inv: &'a [serde_json::Value],
    merch_id: i64,
    status: &str,
) -> Option<&'a serde_json::Value> {
    inv.iter()
        .find(|i| i["merchId"] == merch_id && i["status"] == status)
}

fn qty(inv: &[serde_json::Value], merch_id: i64, status: &str) -> i64 {
    find_row(inv, merch_id, status)
        .and_then(|i| i.get("quantity").and_then(|v| v.as_i64()))
        .unwrap_or(0)
}

fn projected(inv: &[serde_json::Value], merch_id: i64, status: &str) -> i64 {
    find_row(inv, merch_id, status)
        .and_then(|i| i.get("projectedQuantity").and_then(|v| v.as_i64()))
        .unwrap_or_else(|| qty(inv, merch_id, status))
}

async fn list_inventory(pool: &PgPool, user_id: i64) -> Vec<serde_json::Value> {
    let resp = get_request(pool, &format!("/api/v1/user/{user_id}/inventory")).await;
    assert_eq!(resp.status(), StatusCode::OK, "list inventory failed");
    serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap()
}

async fn offer_balanced_1(
    pool: &PgPool,
    match_id: i64,
    proposer: i64,
    merch_give: i64,
    merch_recv: i64,
    other: i64,
    qty: i32,
) {
    let body = format!(
        r#"{{"userId": {proposer}, "items": [
            {{"merchId": {merch_give}, "giverUserId": {proposer}, "quantity": {qty}}},
            {{"merchId": {merch_recv}, "giverUserId": {other}, "quantity": {qty}}}
        ]}}"#
    );
    let resp = post_json(pool, &format!("/api/v1/matches/{match_id}/offer"), &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "offer failed");
}

async fn set_match_status(pool: &PgPool, match_id: i64, user_id: i64, status: &str) {
    let body = format!(r#"{{"status": "{status}", "userId": {user_id}}}"#);
    let resp = post_json(pool, &format!("/api/v1/matches/{match_id}/status"), &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "status {status} failed");
}

async fn apply_inventory(pool: &PgPool, match_id: i64, user_id: i64) {
    let body = format!(r#"{{"userId": {user_id}}}"#);
    let resp = post_json(
        pool,
        &format!("/api/v1/matches/{match_id}/apply-inventory"),
        &body,
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK, "apply failed");
}

/// PENDING matches (no legs) do not move projected off current qty.
#[sqlx::test]
async fn test_pending_excluded_from_projection(pool: PgPool) {
    let (fx, _match_id) = setup_pending_mutual_match(
        &pool,
        "proj-pending",
        MutualTradeOptions {
            have_qty: Some(2),
            ..MutualTradeOptions::default()
        },
    )
    .await;

    let inv = list_inventory(&pool, fx.user1_id).await;
    assert_eq!(qty(&inv, fx.merch_a_id, "TRADE"), 1);
    assert_eq!(projected(&inv, fx.merch_a_id, "TRADE"), 1);
    assert_eq!(qty(&inv, fx.merch_a_id, "HAVE"), 2);
    assert_eq!(projected(&inv, fx.merch_a_id, "HAVE"), 2);
    assert_eq!(qty(&inv, fx.merch_b_id, "WANT"), 1);
    assert_eq!(projected(&inv, fx.merch_b_id, "WANT"), 1);
}

/// OFFERED uses current on-table legs: giver HAVE−/TRADE−, receiver HAVE+/WANT−.
#[sqlx::test]
async fn test_offered_projects_giver_and_receiver(pool: PgPool) {
    let (fx, match_id) = setup_pending_mutual_match(
        &pool,
        "proj-offered",
        MutualTradeOptions {
            have_qty: Some(2),
            ..MutualTradeOptions::default()
        },
    )
    .await;

    offer_balanced_1(
        &pool,
        match_id,
        fx.user1_id,
        fx.merch_a_id,
        fx.merch_b_id,
        fx.user2_id,
        1,
    )
    .await;

    let u1 = list_inventory(&pool, fx.user1_id).await;
    assert_eq!(qty(&u1, fx.merch_a_id, "HAVE"), 2);
    assert_eq!(projected(&u1, fx.merch_a_id, "HAVE"), 1);
    assert_eq!(qty(&u1, fx.merch_a_id, "TRADE"), 1);
    assert_eq!(projected(&u1, fx.merch_a_id, "TRADE"), 0);
    assert_eq!(qty(&u1, fx.merch_b_id, "WANT"), 1);
    assert_eq!(projected(&u1, fx.merch_b_id, "WANT"), 0);
    // Receiver HAVE of B: no current row → synthetic 0(1).
    assert_eq!(qty(&u1, fx.merch_b_id, "HAVE"), 0);
    assert_eq!(projected(&u1, fx.merch_b_id, "HAVE"), 1);

    let u2 = list_inventory(&pool, fx.user2_id).await;
    assert_eq!(qty(&u2, fx.merch_b_id, "HAVE"), 2);
    assert_eq!(projected(&u2, fx.merch_b_id, "HAVE"), 1);
    assert_eq!(qty(&u2, fx.merch_b_id, "TRADE"), 1);
    assert_eq!(projected(&u2, fx.merch_b_id, "TRADE"), 0);
    assert_eq!(qty(&u2, fx.merch_a_id, "WANT"), 1);
    assert_eq!(projected(&u2, fx.merch_a_id, "WANT"), 0);
    assert_eq!(qty(&u2, fx.merch_a_id, "HAVE"), 0);
    assert_eq!(projected(&u2, fx.merch_a_id, "HAVE"), 1);
}

/// ACCEPTED keeps the same on-table legs as the accepted offer.
#[sqlx::test]
async fn test_accepted_same_projection_as_offered(pool: PgPool) {
    let (fx, match_id) = setup_pending_mutual_match(
        &pool,
        "proj-accepted",
        MutualTradeOptions {
            have_qty: Some(2),
            ..MutualTradeOptions::default()
        },
    )
    .await;
    offer_balanced_1(
        &pool,
        match_id,
        fx.user1_id,
        fx.merch_a_id,
        fx.merch_b_id,
        fx.user2_id,
        1,
    )
    .await;
    set_match_status(&pool, match_id, fx.user2_id, "ACCEPTED").await;

    let u1 = list_inventory(&pool, fx.user1_id).await;
    assert_eq!(projected(&u1, fx.merch_a_id, "TRADE"), 0);
    assert_eq!(projected(&u1, fx.merch_a_id, "HAVE"), 1);
    assert_eq!(projected(&u1, fx.merch_b_id, "WANT"), 0);
    assert_eq!(projected(&u1, fx.merch_b_id, "HAVE"), 1);
}

/// COMPLETED still projects until this user applies; apply drops that side.
#[sqlx::test]
async fn test_completed_unapplied_then_excluded_after_apply(pool: PgPool) {
    let (fx, match_id) = setup_pending_mutual_match(
        &pool,
        "proj-completed",
        MutualTradeOptions {
            have_qty: Some(2),
            ..MutualTradeOptions::default()
        },
    )
    .await;
    offer_balanced_1(
        &pool,
        match_id,
        fx.user1_id,
        fx.merch_a_id,
        fx.merch_b_id,
        fx.user2_id,
        1,
    )
    .await;
    set_match_status(&pool, match_id, fx.user2_id, "ACCEPTED").await;
    set_match_status(&pool, match_id, fx.user1_id, "COMPLETED").await;

    let u1_before = list_inventory(&pool, fx.user1_id).await;
    assert_eq!(qty(&u1_before, fx.merch_a_id, "TRADE"), 1);
    assert_eq!(projected(&u1_before, fx.merch_a_id, "TRADE"), 0);
    assert_eq!(qty(&u1_before, fx.merch_a_id, "HAVE"), 2);
    assert_eq!(projected(&u1_before, fx.merch_a_id, "HAVE"), 1);

    apply_inventory(&pool, match_id, fx.user1_id).await;

    let u1_after = list_inventory(&pool, fx.user1_id).await;
    assert_eq!(qty(&u1_after, fx.merch_a_id, "TRADE"), 0);
    assert_eq!(projected(&u1_after, fx.merch_a_id, "TRADE"), 0);
    assert_eq!(qty(&u1_after, fx.merch_a_id, "HAVE"), 1);
    assert_eq!(projected(&u1_after, fx.merch_a_id, "HAVE"), 1);
    // Receiver HAVE of B is now real (applied); no leftover projection.
    assert_eq!(qty(&u1_after, fx.merch_b_id, "HAVE"), 1);
    assert_eq!(projected(&u1_after, fx.merch_b_id, "HAVE"), 1);
    // Apply does not change WANT; match is excluded so parens disappear.
    assert_eq!(qty(&u1_after, fx.merch_b_id, "WANT"), 1);
    assert_eq!(projected(&u1_after, fx.merch_b_id, "WANT"), 1);

    // User2 has not applied: still projected.
    let u2 = list_inventory(&pool, fx.user2_id).await;
    assert_eq!(qty(&u2, fx.merch_b_id, "TRADE"), 1);
    assert_eq!(projected(&u2, fx.merch_b_id, "TRADE"), 0);
}

/// Two OFFERED matches for the same merch sum on the giver.
#[sqlx::test]
async fn test_multi_match_aggregation(pool: PgPool) {
    let user1 = login_guest(&pool, "proj-multi-u1", "t1").await;
    let user2 = login_guest(&pool, "proj-multi-u2", "t2").await;
    let user3 = login_guest(&pool, "proj-multi-u3", "t3").await;
    let event_id = create_event(&pool, "proj-multi Event", user1).await;
    let merch_a = create_merch(&pool, event_id, "A", "Cards").await;
    let merch_b = create_merch(&pool, event_id, "B", "Cards").await;
    let merch_c = create_merch(&pool, event_id, "C", "Cards").await;

    set_inventory(&pool, user1, merch_a, "TRADE", 2).await;
    set_inventory(&pool, user1, merch_a, "HAVE", 2).await;
    set_inventory(&pool, user1, merch_b, "WANT", 1).await;
    set_inventory(&pool, user1, merch_c, "WANT", 1).await;
    set_inventory(&pool, user2, merch_b, "TRADE", 1).await;
    set_inventory(&pool, user2, merch_a, "WANT", 1).await;
    set_inventory(&pool, user3, merch_c, "TRADE", 1).await;
    set_inventory(&pool, user3, merch_a, "WANT", 1).await;

    backend::matching::run_matching_algorithm(&pool)
        .await
        .expect("matcher");
    let matches = list_user_matches(&pool, user1).await;
    assert_eq!(matches.len(), 2, "expected two PENDING matches");

    for m in &matches {
        let match_id = m["id"].as_i64().unwrap();
        let other = if m["user1Id"] == user1 {
            m["user2Id"].as_i64().unwrap()
        } else {
            m["user1Id"].as_i64().unwrap()
        };
        let recv = if other == user2 { merch_b } else { merch_c };
        offer_balanced_1(&pool, match_id, user1, merch_a, recv, other, 1).await;
    }

    let inv = list_inventory(&pool, user1).await;
    assert_eq!(qty(&inv, merch_a, "TRADE"), 2);
    assert_eq!(projected(&inv, merch_a, "TRADE"), 0);
    assert_eq!(qty(&inv, merch_a, "HAVE"), 2);
    assert_eq!(projected(&inv, merch_a, "HAVE"), 0);
}

/// Over-commit is returned as a negative projected value (not clamped).
#[sqlx::test]
async fn test_negative_projected_have_not_clamped(pool: PgPool) {
    let (fx, match_id) = setup_pending_mutual_match(
        &pool,
        "proj-neg",
        MutualTradeOptions {
            u1_trade: 2,
            u1_want: 2,
            u2_trade: 2,
            u2_want: 2,
            have_qty: Some(1),
            ..MutualTradeOptions::default()
        },
    )
    .await;
    offer_balanced_1(
        &pool,
        match_id,
        fx.user1_id,
        fx.merch_a_id,
        fx.merch_b_id,
        fx.user2_id,
        2,
    )
    .await;

    let u1 = list_inventory(&pool, fx.user1_id).await;
    assert_eq!(qty(&u1, fx.merch_a_id, "HAVE"), 1);
    assert_eq!(projected(&u1, fx.merch_a_id, "HAVE"), -1);
    assert_eq!(qty(&u1, fx.merch_a_id, "TRADE"), 2);
    assert_eq!(projected(&u1, fx.merch_a_id, "TRADE"), 0);
}

/// REJECTED matches drop out of projection.
#[sqlx::test]
async fn test_rejected_excluded_from_projection(pool: PgPool) {
    let (fx, match_id) = setup_pending_mutual_match(
        &pool,
        "proj-reject",
        MutualTradeOptions {
            have_qty: Some(2),
            ..MutualTradeOptions::default()
        },
    )
    .await;
    offer_balanced_1(
        &pool,
        match_id,
        fx.user1_id,
        fx.merch_a_id,
        fx.merch_b_id,
        fx.user2_id,
        1,
    )
    .await;
    set_match_status(&pool, match_id, fx.user2_id, "REJECTED").await;

    let u1 = list_inventory(&pool, fx.user1_id).await;
    assert_eq!(qty(&u1, fx.merch_a_id, "TRADE"), 1);
    assert_eq!(projected(&u1, fx.merch_a_id, "TRADE"), 1);
    assert_eq!(qty(&u1, fx.merch_a_id, "HAVE"), 2);
    assert_eq!(projected(&u1, fx.merch_a_id, "HAVE"), 2);
}

/// Upsert response omits projectedQuantity (absent = same as quantity).
#[sqlx::test]
async fn test_upsert_omits_projected_quantity(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "proj-upsert", "proj-upsert Event").await;
    let merch_id = create_merch(&pool, event_id, "Item", "G").await;
    let body = format!(
        r#"{{"userId": {user_id}, "merchId": {merch_id}, "status": "HAVE", "quantity": 3}}"#
    );
    let resp = post_json(&pool, "/api/v1/user/inventory", &body).await;
    assert_eq!(resp.status(), StatusCode::OK);
    let inv: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert!(
        inv.get("projectedQuantity").is_none(),
        "upsert must omit projectedQuantity, got {inv}"
    );
}
