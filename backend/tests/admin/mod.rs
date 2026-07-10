use crate::common::*;

#[sqlx::test]
async fn test_admin_get_user_details_returns_user(pool: PgPool) {
    let (user_id, _event_id) =
        create_test_user_and_event(pool.clone(), "admin-getuser", "Admin GetUser Event").await;

    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/api/v1/admin/users/{}", user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_string(resp.into_body()).await;
    let user: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert_eq!(user["id"], user_id);
    assert!(user["username"].as_str().is_some());
}

#[sqlx::test]
async fn test_admin_get_user_details_nonexistent_returns_404(pool: PgPool) {
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/v1/admin/users/999999")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
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
