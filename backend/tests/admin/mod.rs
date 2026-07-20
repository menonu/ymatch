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
    // #180 / ADR 0008: admin delete always soft-deletes (no hard-delete branch).
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

    let row: Option<(bool, bool)> =
        sqlx::query_as("SELECT is_deleted, trade_enabled FROM merchandise WHERE id = $1")
            .bind(merch_id as i32)
            .fetch_optional(&pool)
            .await
            .unwrap();
    let (is_deleted, trade_enabled) = row.expect("merch row should remain after soft delete");
    assert!(is_deleted, "merch should be soft-deleted");
    assert!(!trade_enabled, "soft-deleted merch must disable trade");
}

#[sqlx::test]
async fn test_admin_delete_merch_soft_deletes_with_inventory(pool: PgPool) {
    // #180: delete_by_id soft-deletes when inventory still references the row.
    let (user_id, event_id) =
        create_test_user_and_event(pool.clone(), "admin-softdel-merch", "Admin SoftDel Merch")
            .await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Soft Del Target", "groupName": "Group A", "creatorId": {}}}"#,
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

    // Seed a HAVE inventory row so delete_by_id takes the soft-delete branch.
    sqlx::query(
        "INSERT INTO inventory (user_id, merch_id, status, quantity)
         VALUES ($1, $2, 'HAVE', 1)
         ON CONFLICT (user_id, merch_id, status) DO UPDATE SET quantity = 1",
    )
    .bind(user_id as i32)
    .bind(merch_id as i32)
    .execute(&pool)
    .await
    .unwrap();

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

    let row: Option<(bool, bool)> =
        sqlx::query_as("SELECT is_deleted, trade_enabled FROM merchandise WHERE id = $1")
            .bind(merch_id as i32)
            .fetch_optional(&pool)
            .await
            .unwrap();
    let (is_deleted, trade_enabled) = row.expect("merch row should remain after soft delete");
    assert!(is_deleted, "merch should be soft-deleted");
    assert!(!trade_enabled, "soft-deleted merch must disable trade");
}

#[sqlx::test]
async fn test_admin_delete_match(pool: PgPool) {
    // #180: admin match delete goes through MatchRepository::delete.
    let (admin_id, event_id) =
        create_test_user_and_event(pool.clone(), "admin-delmatch", "Admin DeleteMatch").await;
    grant_global_role(&pool, admin_id, "admin").await;
    let other = login_guest(&pool, "admin-delmatch-other", "t").await;

    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name, status)
         VALUES ($1, $2, $3, 'G', 'PENDING') RETURNING id",
    )
    .bind(admin_id as i32)
    .bind(other as i32)
    .bind(event_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/matches/{}?user_id={}",
                    match_id, admin_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let still_there: Option<i32> = sqlx::query_scalar("SELECT id FROM matches WHERE id = $1")
        .bind(match_id)
        .fetch_optional(&pool)
        .await
        .unwrap();
    assert!(still_there.is_none(), "match row should be deleted");

    // Idempotent: deleting a missing match is still 200.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/matches/{}?user_id={}",
                    match_id, admin_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
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

// ---------------------------------------------------------------------------
// #432: admin transfer event/group creator + admin event members path
// ---------------------------------------------------------------------------

#[sqlx::test]
async fn test_admin_transfer_event_creator_success(pool: PgPool) {
    let old_creator = login_guest(&pool, "xfer-evt-old", "t").await;
    let event_id = create_event(&pool, "Xfer Event Creator", old_creator).await;
    let new_creator = login_guest(&pool, "xfer-evt-new", "t").await;
    let staff = login_guest(&pool, "xfer-evt-staff", "t").await;
    grant_global_role(&pool, staff, "moderator").await;

    assert!(has_event_role(&pool, old_creator, event_id, "creator").await);
    assert!(!has_event_role(&pool, new_creator, event_id, "creator").await);

    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/creator?user_id={}",
            event_id, staff
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, new_creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK, "transfer should succeed");

    let creator_id: Option<i32> = sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(creator_id, Some(new_creator as i32));
    assert!(
        has_event_role(&pool, new_creator, event_id, "creator").await,
        "new creator must hold event/creator"
    );
    assert!(
        !has_event_role(&pool, old_creator, event_id, "creator").await,
        "previous creator must lose event/creator"
    );
    assert!(
        !has_event_role(&pool, old_creator, event_id, "editor").await,
        "previous creator is not auto-promoted to editor"
    );
}

#[sqlx::test]
async fn test_admin_transfer_event_creator_rbac_and_validation(pool: PgPool) {
    let creator = login_guest(&pool, "xfer-evt-val-c", "t").await;
    let event_id = create_event(&pool, "Xfer Event Val", creator).await;
    let plain = login_guest(&pool, "xfer-evt-val-plain", "t").await;
    let target = login_guest(&pool, "xfer-evt-val-tgt", "t").await;
    let staff = login_guest(&pool, "xfer-evt-val-staff", "t").await;
    grant_global_role(&pool, staff, "admin").await;

    // Plain user → 403.
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/creator?user_id={}",
            event_id, plain
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Missing event → 404.
    let resp = put_json(
        &pool,
        &format!("/api/v1/admin/events/999999/creator?user_id={}", staff),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // Missing target user → 404.
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/creator?user_id={}",
            event_id, staff
        ),
        r#"{"newCreatorId": 999999}"#,
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // Already the creator → 400.
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/creator?user_id={}",
            event_id, staff
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

    // Banned target → 400.
    let banned = login_guest(&pool, "xfer-evt-val-banned", "t").await;
    sqlx::query("UPDATE users SET is_banned = true WHERE id = $1")
        .bind(banned as i32)
        .execute(&pool)
        .await
        .unwrap();
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/creator?user_id={}",
            event_id, staff
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, banned),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

/// #445: admin transfer after a concurrent/prior self-service transfer must
/// revoke whoever currently holds `event/creator` (not a stale snapshot) and
/// leave exactly one creator role row.
#[sqlx::test]
async fn test_admin_transfer_event_creator_after_self_transfer(pool: PgPool) {
    let old_creator = login_guest(&pool, "xfer-evt-after-old", "t").await;
    let event_id = create_event(&pool, "Xfer Event After Self", old_creator).await;
    let mid = login_guest(&pool, "xfer-evt-after-mid", "t").await;
    let final_creator = login_guest(&pool, "xfer-evt-after-final", "t").await;
    let staff = login_guest(&pool, "xfer-evt-after-staff", "t").await;
    grant_global_role(&pool, staff, "moderator").await;

    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/events/{}/creator?user_id={}",
            event_id, old_creator
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, mid),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/creator?user_id={}",
            event_id, staff
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, final_creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    let creator_id: Option<i32> = sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(creator_id, Some(final_creator as i32));

    let creator_roles: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::bigint
         FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.scope_type = 'event'
           AND ur.scope_id = $1
           AND r.scope_type = 'event'
           AND r.name = 'creator'",
    )
    .bind(event_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        creator_roles, 1,
        "must leave exactly one event/creator role"
    );
    assert!(has_event_role(&pool, final_creator, event_id, "creator").await);
    assert!(!has_event_role(&pool, mid, event_id, "creator").await);
    assert!(!has_event_role(&pool, old_creator, event_id, "creator").await);
}

#[sqlx::test]
async fn test_admin_transfer_group_creator_success(pool: PgPool) {
    let creator = login_guest(&pool, "xfer-grp-old", "t").await;
    let event_id = create_event(&pool, "Xfer Group Creator Event", creator).await;
    // create_merch inserts the group with created_by = event creator.
    let _merch = create_merch(&pool, event_id, "Item A", "group-a").await;
    let new_creator = login_guest(&pool, "xfer-grp-new", "t").await;
    let staff = login_guest(&pool, "xfer-grp-staff", "t").await;
    grant_global_role(&pool, staff, "moderator").await;

    let before: Option<i32> = sqlx::query_scalar(
        "SELECT created_by FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("group-a")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(before, Some(creator as i32));

    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/groups/group-a/creator?user_id={}",
            event_id, staff
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, new_creator),
    )
    .await;
    assert_eq!(
        resp.status(),
        StatusCode::OK,
        "group transfer should succeed"
    );

    let after: Option<i32> = sqlx::query_scalar(
        "SELECT created_by FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("group-a")
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(after, Some(new_creator as i32));

    // Admin groups list surfaces creatorUsername.
    let expected_username: String = sqlx::query_scalar("SELECT username FROM users WHERE id = $1")
        .bind(new_creator as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    let resp = get_request(&pool, "/api/v1/admin/groups").await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let groups = body.as_array().unwrap();
    let g = groups
        .iter()
        .find(|g| g["groupName"] == "group-a")
        .expect("group-a in admin list");
    assert_eq!(g["creatorId"], new_creator);
    assert_eq!(g["creatorUsername"].as_str().unwrap(), expected_username);
}

#[sqlx::test]
async fn test_admin_transfer_group_creator_rbac(pool: PgPool) {
    let creator = login_guest(&pool, "xfer-grp-rbac-c", "t").await;
    let event_id = create_event(&pool, "Xfer Group Rbac Event", creator).await;
    let _merch = create_merch(&pool, event_id, "Item B", "group-b").await;
    let plain = login_guest(&pool, "xfer-grp-rbac-plain", "t").await;
    let target = login_guest(&pool, "xfer-grp-rbac-tgt", "t").await;

    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/groups/group-b/creator?user_id={}",
            event_id, plain
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Missing group → 404 (with staff auth).
    let staff = login_guest(&pool, "xfer-grp-rbac-staff", "t").await;
    grant_global_role(&pool, staff, "admin").await;
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/groups/no-such/creator?user_id={}",
            event_id, staff
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn test_admin_event_members_path(pool: PgPool) {
    let creator = login_guest(&pool, "adm-mem-creator", "t").await;
    let event_id = create_event(&pool, "Admin Members Event", creator).await;
    let editor = login_guest(&pool, "adm-mem-editor", "t").await;
    let staff = login_guest(&pool, "adm-mem-staff", "t").await;
    let plain = login_guest(&pool, "adm-mem-plain", "t").await;
    grant_global_role(&pool, staff, "moderator").await;

    // Moderator can list via admin path (unlike /events/:id/members).
    let resp = get_request(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/members?user_id={}",
            event_id, staff
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(body["members"].as_array().unwrap().len(), 1);

    // Plain user cannot.
    let resp = get_request(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/members?user_id={}",
            event_id, plain
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Moderator can assign editor.
    let resp = post_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/members/{}?user_id={}",
            event_id, editor, staff
        ),
        "",
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(has_event_role(&pool, editor, event_id, "editor").await);

    // Moderator can revoke editor; creator role is untouched.
    let resp = delete_request(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/members/{}?user_id={}",
            event_id, editor, staff
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(!has_event_role(&pool, editor, event_id, "editor").await);

    let resp = delete_request(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/members/{}?user_id={}",
            event_id, creator, staff
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(
        has_event_role(&pool, creator, event_id, "creator").await,
        "revoking editor must never remove creator"
    );
}
