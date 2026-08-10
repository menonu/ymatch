//! Integration tests for Web Push subscription API (#179 / ADR 0015 part 2).
//!
//! Storage + register/unregister + VAPID public-key exposure only.
//! Actual Web Push send is a later PR.

use crate::common::*;

#[sqlx::test]
async fn vapid_public_key_returns_404_when_unset(pool: PgPool) {
    // create_router reads VAPID_PUBLIC_KEY once; CI/local default is unset.
    let resp = get_request(&pool, "/api/v1/push/vapid-public-key").await;
    assert_eq!(
        resp.status(),
        StatusCode::NOT_FOUND,
        "without VAPID_PUBLIC_KEY the key endpoint must 404"
    );
}

#[sqlx::test]
async fn upsert_requires_user_id(pool: PgPool) {
    let resp = put_json(
        &pool,
        "/api/v1/push/subscriptions",
        r#"{
            "endpoint": "https://push.example/ep",
            "keys": { "p256dh": "k", "auth": "a" }
        }"#,
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn upsert_and_delete_subscription(pool: PgPool) {
    let user_id = login_guest(&pool, "push-api-user", "tok").await;
    let endpoint = "https://push.example/api-ep-1";

    let resp = put_json(
        &pool,
        &format!("/api/v1/push/subscriptions?user_id={user_id}"),
        &format!(
            r#"{{
                "endpoint": "{endpoint}",
                "keys": {{ "p256dh": "p256-public", "auth": "auth-secret" }},
                "userAgent": "IntegrationTest/1"
            }}"#
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK, "upsert should succeed");
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["userId"], user_id as i64);
    assert_eq!(body["endpoint"], endpoint);
    assert!(body["id"].as_i64().unwrap() > 0);

    // Row persisted.
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM push_subscriptions WHERE user_id = $1 AND endpoint = $2",
    )
    .bind(user_id as i32)
    .bind(endpoint)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count, 1);

    // Re-upsert updates keys in place.
    let resp = put_json(
        &pool,
        &format!("/api/v1/push/subscriptions?user_id={user_id}"),
        &format!(
            r#"{{
                "endpoint": "{endpoint}",
                "keys": {{ "p256dh": "p256-updated", "auth": "auth-updated" }}
            }}"#
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let p256dh: String =
        sqlx::query_scalar("SELECT p256dh FROM push_subscriptions WHERE endpoint = $1")
            .bind(endpoint)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(p256dh, "p256-updated");

    // Delete.
    let resp = delete_json(
        &pool,
        &format!("/api/v1/push/subscriptions?user_id={user_id}"),
        &format!(r#"{{"endpoint": "{endpoint}"}}"#),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["deleted"], true);

    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM push_subscriptions WHERE endpoint = $1")
            .bind(endpoint)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(count, 0);

    // Idempotent delete.
    let resp = delete_json(
        &pool,
        &format!("/api/v1/push/subscriptions?user_id={user_id}"),
        &format!(r#"{{"endpoint": "{endpoint}"}}"#),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["deleted"], false);
}

#[sqlx::test]
async fn delete_does_not_remove_other_users_subscription(pool: PgPool) {
    let owner = login_guest(&pool, "push-owner", "tok-o").await;
    let other = login_guest(&pool, "push-other", "tok-x").await;
    let endpoint = "https://push.example/owner-only";

    let resp = put_json(
        &pool,
        &format!("/api/v1/push/subscriptions?user_id={owner}"),
        &format!(
            r#"{{
                "endpoint": "{endpoint}",
                "keys": {{ "p256dh": "k", "auth": "a" }}
            }}"#
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    let resp = delete_json(
        &pool,
        &format!("/api/v1/push/subscriptions?user_id={other}"),
        &format!(r#"{{"endpoint": "{endpoint}"}}"#),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["deleted"], false);

    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM push_subscriptions WHERE endpoint = $1")
            .bind(endpoint)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(count, 1, "owner row must remain");
}

#[sqlx::test]
async fn upsert_rejects_missing_keys(pool: PgPool) {
    let user_id = login_guest(&pool, "push-bad-body", "tok").await;
    let resp = put_json(
        &pool,
        &format!("/api/v1/push/subscriptions?user_id={user_id}"),
        r#"{"endpoint": "https://push.example/x", "keys": { "p256dh": "", "auth": "a" }}"#,
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}
