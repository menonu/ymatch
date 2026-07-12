use crate::common::*;

#[sqlx::test]
async fn test_admin_get_user_details_returns_user(pool: PgPool) {
    // create_test_user_and_event grants global/moderator, which holds user.read.
    let (caller_id, _event_id) =
        create_test_user_and_event(pool.clone(), "admin-getuser", "Admin GetUser Event").await;
    let target = login_guest(&pool, "admin-getuser-target", "t").await;

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/api/v1/admin/users/{}?user_id={}",
                    target, caller_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let user: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(user["id"], target);
    assert!(user["username"].as_str().is_some());
}

#[sqlx::test]
async fn test_admin_get_user_details_nonexistent_returns_404(pool: PgPool) {
    let (admin_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-getuser-404", "GetUser 404 Event").await;
    grant_global_role(&pool, admin_id, "admin").await;

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/admin/users/999999?user_id={}", admin_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

/// #376: plain callers must not read another user's details (device_token
/// exposure). Moderator and admin both hold `user.read` and get 200.
#[sqlx::test]
async fn test_admin_get_user_details_rbac_boundary(pool: PgPool) {
    let target = login_guest(&pool, "getuser-rbac-target", "tok-target").await;

    // Plain caller → 403.
    let plain = login_guest(&pool, "getuser-rbac-plain", "tok-plain").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/admin/users/{}?user_id={}", target, plain))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        resp.status(),
        StatusCode::FORBIDDEN,
        "plain user must not read user details"
    );

    // Missing user_id query param → 400.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/admin/users/{}", target))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

    // Moderator → 200.
    let moderator = login_guest(&pool, "getuser-rbac-mod", "tok-mod").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/api/v1/admin/users/{}?user_id={}",
                    target, moderator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let user: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(user["id"], target);

    // Admin → 200 (superuser bypass + explicit grant).
    let admin = login_guest(&pool, "getuser-rbac-admin", "tok-admin").await;
    grant_global_role(&pool, admin, "admin").await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/admin/users/{}?user_id={}", target, admin))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_admin_update_user_role_invalid_role_rejected(pool: PgPool) {
    // Use an admin to make the role change.
    let (admin_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-admin", "Admin Role Event").await;
    grant_global_role(&pool, admin_id, "admin").await;

    // Create a target user.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-role-target"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target_id, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "hacker"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn test_admin_update_user_role_moderator_forbidden(pool: PgPool) {
    // Create two users: a "moderator" trying to change roles, and a target.
    let (mod_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-mod", "Admin Mod Event").await;
    grant_global_role(&pool, mod_id, "moderator").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-role-target-2"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target_id, mod_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "moderator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_admin_update_user_role_succeeds(pool: PgPool) {
    let (admin_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-ok", "Admin Role Ok").await;
    grant_global_role(&pool, admin_id, "admin").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-role-promote"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
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

    // Verify the role was actually changed. ADR 0006: the role lives in
    // user_roles (users.role was dropped), so derive it the way the API does.
    assert_eq!(global_role_of(&pool, target_id).await, "moderator");
}

#[sqlx::test]
async fn test_admin_update_user_role_nonexistent_returns_404(pool: PgPool) {
    // ADR 0006: set_role detects a non-existent target via an explicit
    // existence check (the delete-then-insert row counts can't, since a real
    // user may have no prior global row) and returns Ok(None) → 404. Exercise
    // that branch: a valid role on a user id that does not exist must 404,
    // not 500 (FK violation) and not 200.
    let (admin_id, _eid) =
        create_test_user_and_event(pool.clone(), "admin-role-404", "Admin Role 404").await;
    grant_global_role(&pool, admin_id, "admin").await;

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    999_999, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "moderator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn test_admin_list_all_merch_returns_array(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "admin-listmerch", "Admin ListMerch").await;
    // Add one piece of merch so the list is non-empty.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Listed Merch", "groupName": "Group A", "creatorId": {}}}"#,
                    user_id
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
                .method("GET")
                .uri("/api/v1/admin/merch")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let items: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    assert!(!items.is_empty(), "list should be non-empty");
}

#[sqlx::test]
async fn test_admin_list_all_matches_returns_array(pool: PgPool) {
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/v1/admin/matches")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let items: Vec<serde_json::Value> = serde_json::from_str(&body).unwrap();
    // Just verify it returns a valid array (content may be empty or populated).
    let _ = items.len();
}

#[sqlx::test]
async fn test_admin_delete_merch_succeeds(pool: PgPool) {
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "admin-deleterch", "Admin DeleteMerch").await;

    // Create one piece of merch.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "To Delete", "groupName": "Group A", "creatorId": {}}}"#,
                    user_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let merch_id: i64 =
        serde_json::from_str::<serde_json::Value>(&body_to_string(resp.into_body()).await).unwrap()
            ["id"]
            .as_i64()
            .unwrap();

    // Promote user to admin for the delete.
    grant_global_role(&pool, user_id, "admin").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/merch/{}?user_id={}",
                    merch_id, user_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify the merch row is gone.
    let row: Option<(i32,)> = sqlx::query_as("SELECT id FROM merchandise WHERE id = $1")
        .bind(merch_id as i32)
        .fetch_optional(&pool)
        .await
        .unwrap();
    assert!(row.is_none(), "merch should be deleted");
}

#[sqlx::test]
async fn test_admin_ban_unban_user(pool: PgPool) {
    // Create admin user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "admin-ban-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let admin: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let admin_id = admin["id"].as_i64().unwrap();
    grant_global_role(&pool, admin_id, "admin").await;

    // Create target user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "target-ban-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let target: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let target_id = target["id"].as_i64().unwrap();

    // Ban the target
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!(
                    "/api/v1/admin/users/{}/ban?user_id={}",
                    target_id, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"reason": "Bad behavior"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify user is banned
    let row = sqlx::query("SELECT is_banned, ban_reason FROM users WHERE id = $1")
        .bind(target_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(sqlx::Row::get::<bool, _>(&row, "is_banned"));
    assert_eq!(
        sqlx::Row::get::<Option<String>, _>(&row, "ban_reason"),
        Some("Bad behavior".to_string())
    );

    // Unban the target
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!(
                    "/api/v1/admin/users/{}/unban?user_id={}",
                    target_id, admin_id
                ))
                .header("content-type", "application/json")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Verify user is unbanned
    let row = sqlx::query("SELECT is_banned FROM users WHERE id = $1")
        .bind(target_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(!sqlx::Row::get::<bool, _>(&row, "is_banned"));
}

/// #266: a malformed `banned_until` must be 400, not a silent permanent ban.
#[sqlx::test]
async fn test_ban_user_invalid_banned_until_returns_400(pool: PgPool) {
    let admin = login_guest(&pool, "admin-ban-until-266", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let target = login_guest(&pool, "target-ban-until-266", "t").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/ban?user_id={}",
                    target, admin
                ))
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"reason": "temp", "bannedUntil": "not-a-date"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let body = body_to_string(resp.into_body()).await;
    assert!(
        body.contains("banned_until") || body.contains("invalid"),
        "expected invalid banned_until message, got: {body}"
    );

    // User must NOT have been banned (parse failed before set_ban).
    let row = sqlx::query("SELECT is_banned FROM users WHERE id = $1")
        .bind(target as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(
        !sqlx::Row::get::<bool, _>(&row, "is_banned"),
        "malformed banned_until must not ban the user"
    );
}

/// #266: a valid RFC3339 `banned_until` is accepted and stored.
#[sqlx::test]
async fn test_ban_user_valid_banned_until_stored(pool: PgPool) {
    let admin = login_guest(&pool, "admin-ban-until-ok-266", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let target = login_guest(&pool, "target-ban-until-ok-266", "t").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/ban?user_id={}",
                    target, admin
                ))
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"reason": "temp", "bannedUntil": "2030-01-01T00:00:00Z"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let row = sqlx::query("SELECT is_banned, banned_until FROM users WHERE id = $1")
        .bind(target as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(sqlx::Row::get::<bool, _>(&row, "is_banned"));
    let until: Option<chrono::DateTime<chrono::Utc>> = sqlx::Row::get(&row, "banned_until");
    assert!(until.is_some(), "banned_until must be stored");
}

#[sqlx::test]
async fn test_non_admin_cannot_ban(pool: PgPool) {
    // Create regular user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "nonadmin-ban-test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let user: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let user_id = user["id"].as_i64().unwrap();

    // Try to ban someone (should fail - not admin)
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/admin/users/999/ban?user_id={}", user_id))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"reason": "test"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}
