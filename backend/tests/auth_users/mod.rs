use crate::common::*;

#[sqlx::test]
async fn test_guest_login_creates_user(pool: PgPool) {
    let app = backend::routes::create_router(pool, test_storage());

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"uuid": "{}", "deviceToken": "tok123"}}"#,
                    guest_uuid("test-uuid-1234")
                )))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert!(json["id"].as_i64().unwrap() > 0);
    assert!(json["username"].as_str().unwrap().contains("Guest_"));
    assert_eq!(json["uuid"].as_str().unwrap(), guest_uuid("test-uuid-1234"));
}

#[sqlx::test]
async fn test_guest_login_returns_existing_user(pool: PgPool) {
    let app1 = backend::routes::create_router(pool.clone(), test_storage());

    let resp1 = app1
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("reuse-uuid-5678")))
                .unwrap(),
        )
        .await
        .unwrap();
    let body1 = body_to_string(resp1.into_body()).await;
    let user1: serde_json::Value = serde_json::from_str(&body1).unwrap();

    let app2 = backend::routes::create_router(pool, test_storage());
    let resp2 = app2
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("reuse-uuid-5678")))
                .unwrap(),
        )
        .await
        .unwrap();
    let body2 = body_to_string(resp2.into_body()).await;
    let user2: serde_json::Value = serde_json::from_str(&body2).unwrap();

    assert_eq!(user1["id"], user2["id"]);
    assert_eq!(user1["username"], user2["username"]);
}

#[sqlx::test]
async fn test_password_auth_routes_are_removed(pool: PgPool) {
    // Accounts are guest-only: no route may create a user without a uuid.
    for uri in ["/api/v1/auth/signup", "/api/v1/auth/login"] {
        let resp = post_json(
            &pool,
            uri,
            r#"{"username": "pw-user", "password": "pass123"}"#,
        )
        .await;
        assert_eq!(resp.status(), StatusCode::NOT_FOUND, "{uri}");
    }
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0);
}

#[sqlx::test]
async fn test_list_users(pool: PgPool) {
    // Create a user first
    let caller = login_guest(&pool, "list-users-test", "tok").await;
    // Seed a second user so the directory has more than the caller.
    let _other = login_guest(&pool, "list-users-other", "tok").await;

    // #491: missing user_id rejected.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/users")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    // Plain active user gets lean directory (id + username only).
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .uri(format!("/api/v1/users?user_id={}", caller))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    let users: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    assert!(users.len() >= 2);
    let sample = &users[0];
    assert!(sample.get("id").is_some());
    assert!(sample.get("username").is_some());
    // Secrets and ban metadata must not appear on the lean path.
    assert!(
        sample.get("deviceToken").is_none() || sample["deviceToken"].is_null(),
        "device_token must be stripped from directory: {sample}"
    );
    assert!(
        sample.get("uuid").is_none() || sample["uuid"].is_null(),
        "uuid restore key must be stripped from directory: {sample}"
    );
    assert!(
        sample.get("isBanned").is_none() || sample["isBanned"].is_null(),
        "ban metadata not for lean directory: {sample}"
    );

    // Staff with user.read get role/ban fields (still no secrets).
    grant_global_role(&pool, caller, "moderator").await;
    let app = backend::routes::create_router(pool, test_storage());
    let response = app
        .oneshot(
            Request::builder()
                .uri(format!("/api/v1/users?user_id={}", caller))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    let users: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    let me = users
        .iter()
        .find(|u| u["id"].as_i64() == Some(caller))
        .expect("caller in list");
    assert_eq!(me["role"].as_str().unwrap(), "moderator");
    assert!(
        me.get("deviceToken").is_none() || me["deviceToken"].is_null(),
        "staff list still strips device_token"
    );
    assert!(me.get("uuid").is_none() || me["uuid"].is_null());
}

#[sqlx::test]
async fn test_banned_user_cannot_login(pool: PgPool) {
    // Create user via guest login
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("ban-test-uuid")))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Ban the user
    sqlx::query("UPDATE users SET is_banned = true, ban_reason = 'test ban' WHERE id = $1")
        .bind(user_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    // Try guest login again - should be forbidden
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("ban-test-uuid")))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_update_user_role(pool: PgPool) {
    // Create admin
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("role-admin-test")))
                .unwrap(),
        )
        .await
        .unwrap();
    let admin: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let admin_id = admin["id"].as_i64().unwrap();
    grant_global_role(&pool, admin_id, "admin").await;

    // Create target
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("role-target-test")))
                .unwrap(),
        )
        .await
        .unwrap();
    let target: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let target_id = target["id"].as_i64().unwrap();

    // Promote to moderator
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target_id, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "moderator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // ADR 0006: the role lives in user_roles (users.role was dropped), so
    // derive it the way the API does rather than reading a dropped column.
    assert_eq!(global_role_of(&pool, target_id).await, "moderator");

    // The derivation must also flow through the actual `User` payload the
    // frontend admin gate reads. Re-guest-login the target (idempotent on
    // uuid) and assert the returned `User.role` reflects the promotion.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("role-target-test")))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(user["id"].as_i64().unwrap(), target_id);
    assert_eq!(user["role"].as_str().unwrap(), "moderator");
}

#[sqlx::test]
async fn test_user_response_includes_role(pool: PgPool) {
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("role-check-uuid")))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(user["role"].as_str().unwrap(), "user");
    assert_eq!(user["isBanned"].as_bool().unwrap(), false);
}

#[sqlx::test]
async fn test_banned_user_cannot_create_event(pool: PgPool) {
    // Create user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(guest_body("ban-create-test")))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Promote to moderator so the user would otherwise pass the new
    // `event.create` permission check (ADR 0004 §4). This isolates the ban
    // check: the 403 below must come from being banned, not from lacking
    // event.create.
    grant_global_role(&pool, user_id, "moderator").await;

    // Ban the user
    sqlx::query("UPDATE users SET is_banned = true WHERE id = $1")
        .bind(user_id as i32)
        .execute(&pool)
        .await
        .unwrap();

    // Try to create event
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/events")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Banned Event", "creatorId": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_update_username_response_omits_credentials(pool: PgPool) {
    let user_id = login_guest(&pool, "rename-self", "tok").await;
    let resp = put_json(
        &pool,
        &format!("/api/v1/users/{user_id}"),
        &format!(r#"{{"userId": {user_id}, "username": "renamed-self"}}"#),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(user["username"], "renamed-self");
    // Only the login endpoints hand back the UUID (the login credential).
    assert!(
        user.get("uuid").is_none_or(|v| v.is_null()),
        "uuid must not be returned: {user}"
    );
    // The push token is not needed to confirm a rename.
    assert!(
        user.get("deviceToken").is_none_or(|v| v.is_null()),
        "device_token must not be returned: {user}"
    );
}

#[sqlx::test]
async fn test_new_guest_requires_uuid_v4(pool: PgPool) {
    for bad in [
        "short",
        "test-uuid-1234",
        // A valid UUID, but version 1 (time-based) rather than random.
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        // v4, but not in the canonical hyphenated form.
        "4b2f3a8e9c1d4e7fa0b1c2d3e4f5a6b7",
        "{4b2f3a8e-9c1d-4e7f-a0b1-c2d3e4f5a6b7}",
    ] {
        let resp = post_json(
            &pool,
            "/api/v1/auth/guest",
            &format!(r#"{{"uuid": "{bad}"}}"#),
        )
        .await;
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST, "{bad}");
    }
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0, "no account may be created for a rejected uuid");
}

#[sqlx::test]
async fn test_new_guest_rejects_uppercase_uuid_v4(pool: PgPool) {
    // Uuids are matched as exact text, so only the lowercase form may create
    // an account; otherwise one UUID value could map to two accounts.
    let upper = guest_uuid("upper-case").to_uppercase();
    let resp = post_json(
        &pool,
        "/api/v1/auth/guest",
        &format!(r#"{{"uuid": "{upper}"}}"#),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn test_existing_non_v4_uuid_account_can_still_log_in(pool: PgPool) {
    // Accounts created before v4 was required keep their stored uuid.
    sqlx::query("INSERT INTO users (username, uuid) VALUES ('legacy', 'legacy-key')")
        .execute(&pool)
        .await
        .unwrap();
    let resp = post_json(&pool, "/api/v1/auth/guest", r#"{"uuid": "legacy-key"}"#).await;
    assert_eq!(resp.status(), StatusCode::OK);
    let json: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(json["username"], "legacy");
}

#[sqlx::test]
async fn test_existing_only_unknown_uuid_is_not_found(pool: PgPool) {
    // Account restore must never create an account from a mistyped key.
    let uuid = guest_uuid("restore-unknown");
    let resp = post_json(
        &pool,
        "/api/v1/auth/guest",
        &format!(r#"{{"uuid": "{uuid}", "existingOnly": true}}"#),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0, "restore must not create an account");
}

#[sqlx::test]
async fn test_existing_only_logs_in_to_existing_account(pool: PgPool) {
    let uuid = guest_uuid("restore-existing");
    let created = post_json(&pool, "/api/v1/auth/guest", &guest_body("restore-existing")).await;
    assert_eq!(created.status(), StatusCode::OK);
    let created: serde_json::Value =
        serde_json::from_str(&body_to_string(created.into_body()).await).unwrap();

    let resp = post_json(
        &pool,
        "/api/v1/auth/guest",
        &format!(r#"{{"uuid": "{uuid}", "existingOnly": true}}"#),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let json: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(json["id"], created["id"]);
}
