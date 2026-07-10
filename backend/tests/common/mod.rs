pub use axum::body::Body;
pub use axum::http::{Request, StatusCode};
pub use http_body_util::BodyExt;
pub use sqlx::PgPool;
pub use std::sync::Arc;
pub use tower::ServiceExt;

// Shared test helpers — moved out of the old monolithic api_tests.rs.
// Made `pub` so each per-domain module can pull them in via `use crate::common::*;`.

/// Helper to read an integer from a JSON object, treating a missing
/// proto3-default-zero field as 0.
pub fn json_i64(value: &serde_json::Value, key: &str) -> i64 {
    value.get(key).and_then(|v| v.as_i64()).unwrap_or(0)
}

pub fn test_storage() -> Arc<dyn backend::storage::ImageStorage> {
    Arc::new(backend::storage::LocalFileStorage::new(
        "./test_uploads".to_string(),
    ))
}

pub async fn body_to_string(body: Body) -> String {
    let bytes = body.collect().await.unwrap().to_bytes();
    String::from_utf8(bytes.to_vec()).unwrap()
}

pub async fn create_test_user_and_event(pool: PgPool, uuid: &str, event_name: &str) -> (i64, i64) {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"uuid": "{}"}}"#, uuid)))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // ADR 0004 §4: event creation is moderator/admin-only, so promote the
    // guest before creating the event. The handler auto-assigns the
    // `event/creator` role to the creator.
    grant_global_role(&pool, user_id, "moderator").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "{}", "creatorId": {}}}"#,
                    event_name, user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let event_id = event["id"].as_i64().unwrap();
    (user_id, event_id)
}

pub async fn login_guest(pool: &PgPool, uuid: &str, device_token: &str) -> i64 {
    let body = format!(
        r#"{{"uuid": "{}", "deviceToken": "{}"}}"#,
        uuid, device_token
    );
    let resp = post_json(pool, "/api/v1/auth/guest", &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "guest login failed");
    let v: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    v["id"].as_i64().unwrap()
}

/// Grant `user_id` a *global* role the way the production `set_role` path
/// does (ADR 0006): write the `user_roles` global row in one transaction, so
/// RBAC checks (which read `user_roles`) see the role. (`users.role` was
/// dropped; the proto `User.role` field is derived from this row at read
/// time.) Replaces any prior global role. Used by tests that need an
/// admin/moderator actor and by the event-creation helpers (event creation
/// now requires `event.create`, granted to moderator/admin only).
pub async fn grant_global_role(pool: &PgPool, user_id: i64, role: &str) {
    let mut tx = pool.begin().await.unwrap();
    let role_id: i32 =
        sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'global' AND name = $1")
            .bind(role)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    sqlx::query(
        "DELETE FROM user_roles
         WHERE user_id = $1 AND scope_type = 'global' AND scope_id IS NULL",
    )
    .bind(user_id as i32)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'global', NULL)
         ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
    )
    .bind(user_id as i32)
    .bind(role_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

/// Read `user_id`'s derived global role the way the production read path does
/// (ADR 0006): from `user_roles` (scope_type='global', scope_id=NULL), with
/// precedence `admin > moderator > user`, falling back to `'user'` when the
/// user has no global assignment. Mirrors `USER_COLUMNS` in
/// `backend/src/repositories/user.rs` so tests assert against the same value
/// the API exposes as `User.role` (the `users.role` column was dropped).
pub async fn global_role_of(pool: &PgPool, user_id: i64) -> String {
    sqlx::query_scalar(
        "SELECT COALESCE((
             SELECT r.name FROM user_roles ur
             JOIN roles r ON r.id = ur.role_id
             WHERE ur.user_id = $1
               AND ur.scope_type = 'global' AND ur.scope_id IS NULL
             ORDER BY CASE r.name WHEN 'admin' THEN 0 WHEN 'moderator' THEN 1 ELSE 2 END
             LIMIT 1), 'user')",
    )
    .bind(user_id as i32)
    .fetch_one(pool)
    .await
    .unwrap()
}

/// Assign an event-scoped role (`creator` or `editor`) to `user_id` for
/// `event_id` directly, mirroring what the (deferred) event-member API will
/// do for `editor` and what `RbacRepository::assign_event_creator` does for
/// `creator`. Used by the RBAC boundary tests to set up event-scoped actors
/// without the member API.
pub async fn assign_event_role(pool: &PgPool, user_id: i64, event_id: i64, role_name: &str) {
    let role_id: i32 =
        sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'event' AND name = $1")
            .bind(role_name)
            .fetch_one(pool)
            .await
            .unwrap();
    sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'event', $3)
         ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
    )
    .bind(user_id as i32)
    .bind(role_id)
    .bind(event_id as i32)
    .execute(pool)
    .await
    .unwrap();
}

pub async fn create_event(pool: &PgPool, name: &str, creator_id: i64) -> i64 {
    // ADR 0004 §4: event creation requires `event.create` (moderator/admin).
    // The helpers' callers pass a freshly-logged-in guest, so promote them
    // to moderator for the create to pass; the handler then auto-assigns the
    // `event/creator` role.
    grant_global_role(pool, creator_id, "moderator").await;
    let body = format!(r#"{{"name": "{}", "creatorId": {}}}"#, name, creator_id);
    let resp = post_json(pool, "/api/v1/events", &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "create event failed");
    let v: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    v["id"].as_i64().unwrap()
}

pub async fn create_merch(pool: &PgPool, event_id: i64, name: &str, group_name: &str) -> i64 {
    // ADR 0005: merch creation is gated by `merch.create` (event scope). The
    // event creator (event/creator role) satisfies it, so post as them —
    // resolve the event's creator_id from the DB. Note: NO photoUrl, so
    // photo_url stays NULL — this is the exact scenario that triggered the
    // #224 panic.
    let creator_id: Option<i32> = sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(pool)
        .await
        .unwrap();
    let creator_id = creator_id.expect("test event must have a creator to create merch");
    let body = format!(
        r#"{{"name": "{}", "groupName": "{}", "creatorId": {}}}"#,
        name, group_name, creator_id
    );
    let resp = post_json(pool, &format!("/api/v1/events/{}/merch", event_id), &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "create merch failed");
    let v: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    v["id"].as_i64().unwrap()
}

pub async fn set_inventory(
    pool: &PgPool,
    user_id: i64,
    merch_id: i64,
    status: &str,
    quantity: i32,
) {
    let body = format!(
        r#"{{"userId": {}, "merchId": {}, "status": "{}", "quantity": {}}}"#,
        user_id, merch_id, status, quantity
    );
    let resp = post_json(pool, "/api/v1/user/inventory", &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "set inventory failed");
}

pub async fn post_json(pool: &PgPool, uri: &str, body: &str) -> axum::response::Response {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap(),
    )
    .await
    .unwrap()
}

pub async fn put_json(pool: &PgPool, uri: &str, body: &str) -> axum::response::Response {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("PUT")
            .uri(uri)
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap(),
    )
    .await
    .unwrap()
}

pub async fn get_request(pool: &PgPool, uri: &str) -> axum::response::Response {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("GET")
            .uri(uri)
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap()
}

pub async fn delete_request(pool: &PgPool, uri: &str) -> axum::response::Response {
    let app = backend::routes::create_router(pool.clone(), test_storage());
    app.oneshot(
        Request::builder()
            .method("DELETE")
            .uri(uri)
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap()
}

/// Count a user's event-scoped role rows for `event_id` (any role). Used to
/// assert assign/revoke landed in `user_roles`.
pub async fn event_role_count(pool: &PgPool, user_id: i64, event_id: i64) -> i64 {
    sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_roles
         WHERE user_id = $1 AND scope_type = 'event' AND scope_id = $2",
    )
    .bind(user_id as i32)
    .bind(event_id as i32)
    .fetch_one(pool)
    .await
    .unwrap()
}

/// True if `user_id` holds the `event/editor` role for `event_id`.
pub async fn has_event_role(pool: &PgPool, user_id: i64, event_id: i64, role_name: &str) -> bool {
    let n: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND ur.scope_type = 'event' AND ur.scope_id = $2
           AND r.name = $3",
    )
    .bind(user_id as i32)
    .bind(event_id as i32)
    .bind(role_name)
    .fetch_one(pool)
    .await
    .unwrap();
    n > 0
}
