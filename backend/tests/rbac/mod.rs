use crate::common::*;

#[sqlx::test]
async fn test_rbac_event_create_requires_moderator_or_admin(pool: PgPool) {
    let plain = login_guest(&pool, "rbac-create-plain", "t").await;

    // Plain user cannot create an event (ADR 0004 §4).
    let resp = post_json(
        &pool,
        "/api/v1/events",
        &format!(r#"{{"name": "Plain Event", "creatorId": {}}}"#, plain),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Moderator can.
    grant_global_role(&pool, plain, "moderator").await;
    let resp = post_json(
        &pool,
        "/api/v1/events",
        &format!(r#"{{"name": "Mod Event", "creatorId": {}}}"#, plain),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    // Admin can.
    let admin = login_guest(&pool, "rbac-create-admin", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let resp = post_json(
        &pool,
        "/api/v1/events",
        &format!(r#"{{"name": "Admin Event", "creatorId": {}}}"#, admin),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_rbac_event_create_auto_assigns_creator_role(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-auto-creator", "Auto Creator Event").await;

    // The creator is auto-assigned the event/creator role scoped to the new
    // event (ADR 0004 §5), so they pass EventEdit on their own event.
    let row: Option<(i32,)> = sqlx::query_as(
        "SELECT 1 FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND r.scope_type = 'event' AND r.name = 'creator'
           AND ur.scope_type = 'event' AND ur.scope_id = $2",
    )
    .bind(creator_id as i32)
    .bind(event_id as i32)
    .fetch_optional(&pool)
    .await
    .unwrap();
    assert!(row.is_some(), "event/creator role was not auto-assigned");

    // And the creator can publish (EventEdit) their own draft event.
    sqlx::query("UPDATE events SET status = 'draft' WHERE id = $1")
        .bind(event_id as i32)
        .execute(&pool)
        .await
        .unwrap();
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/publish", event_id),
        &format!(r#"{{"userId": {}}}"#, creator_id),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_rbac_event_update_editor_succeeds_plain_user_forbidden(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-upd-creator", "Editor Event").await;

    // An editor (event-scoped editor role) can update the event.
    let editor = login_guest(&pool, "rbac-upd-editor", "t").await;
    assign_event_role(&pool, editor, event_id, "editor").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "name": "Editor Renamed"}}"#,
                    editor
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A plain user (no event role, not moderator) is denied.
    let plain = login_guest(&pool, "rbac-upd-plain", "t").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "name": "Pwned"}}"#,
                    plain
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // The creator (event/creator) can also update.
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "name": "Creator Renamed"}}"#,
                    creator_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_rbac_admin_delete_event_permission(pool: PgPool) {
    let (_creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-del-creator", "To Be Deleted").await;

    // A separate moderator can delete any event via event.delete.any.
    let moderator = login_guest(&pool, "rbac-del-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/events/{}?user_id={}",
                    event_id, moderator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A plain user cannot delete an event they did not create.
    let (_creator2_id, event2_id) =
        create_test_user_and_event(pool.clone(), "rbac-del-creator2", "To Be Deleted 2").await;
    let plain = login_guest(&pool, "rbac-del-plain", "t").await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/events/{}?user_id={}",
                    event2_id, plain
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

/// #233: the event creator keeps `event.delete` via the event-scoped
/// `creator` role even after losing the global moderator role (and thus
/// `event.delete.any`). The delete handler must check `EventDelete` in
/// `Scope::Event`, not only `EventDeleteAny` in `Scope::Global`.
#[sqlx::test]
async fn test_rbac_event_creator_can_delete_own_event(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-del-own-creator", "Own Event To Delete")
            .await;

    // Demote to global `user` — strips event.delete.any but leaves the
    // event/creator role (and event.delete) on this event.
    grant_global_role(&pool, creator_id, "user").await;

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/events/{}?user_id={}",
                    event_id, creator_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        resp.status(),
        StatusCode::OK,
        "event creator must be able to delete their own event (#233)"
    );

    // Event is gone.
    let remaining: Option<(i32,)> = sqlx::query_as("SELECT id FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_optional(&pool)
        .await
        .unwrap();
    assert!(remaining.is_none(), "event row should be deleted");
}

#[sqlx::test]
async fn test_rbac_ban_unban_permission(pool: PgPool) {
    let moderator = login_guest(&pool, "rbac-ban-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let target = login_guest(&pool, "rbac-ban-target", "t").await;

    // Moderator can ban.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/ban?user_id={}",
                    target, moderator
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"reason": "spam"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Moderator can unban.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/unban?user_id={}",
                    target, moderator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A plain user cannot ban.
    let plain = login_guest(&pool, "rbac-ban-plain", "t").await;
    let other = login_guest(&pool, "rbac-ban-other", "t").await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/ban?user_id={}",
                    other, plain
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"reason": "nope"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_rbac_update_user_role_admin_only_and_single_source(pool: PgPool) {
    let admin = login_guest(&pool, "rbac-role-admin", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let target = login_guest(&pool, "rbac-role-target", "t").await;

    // Admin can change a role.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target, admin
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "moderator"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // ADR 0006: user_roles is the single source of truth for the global role
    // (users.role was dropped). The derived role the API exposes as
    // User.role must reflect the new role, and exactly one global row exists.
    assert_eq!(global_role_of(&pool, target).await, "moderator");
    let has_row: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND r.scope_type = 'global' AND r.name = 'moderator'
           AND ur.scope_type = 'global' AND ur.scope_id IS NULL",
    )
    .bind(target as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(has_row, 1, "user_roles global/moderator row must exist");

    // Demotion path: set_role must remove the prior elevated global row when
    // the role changes (delete-then-insert in one tx), so a demoted user
    // cannot retain elevated RBAC access via a stale user_roles row.
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    target, admin
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "user"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(global_role_of(&pool, target).await, "user");
    let elevated: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND r.scope_type = 'global'
           AND ur.scope_type = 'global' AND ur.scope_id IS NULL
           AND r.name IN ('moderator', 'admin')",
    )
    .bind(target as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(elevated, 0, "demotion must remove the elevated global row");

    // A moderator cannot change roles (user.role.manage is admin-only).
    let moderator = login_guest(&pool, "rbac-role-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let other = login_guest(&pool, "rbac-role-other", "t").await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/v1/admin/users/{}/role?user_id={}",
                    other, moderator
                ))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"role": "admin"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_rbac_delete_merch_ownership_and_roles(pool: PgPool) {
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "rbac-merch-creator", "Merch RBAC Event").await;

    // Insert a merch row directly with a controlled creator_id. This test
    // exercises DELETE authorization (ownership vs RBAC roles), not the ADR
    // 0005 create gate (which requires the caller to be an authorized
    // creator/editor/mod/admin); seeding via SQL lets a plain user own a
    // merch row, which the gated create endpoint can no longer produce.
    async fn insert_merch(
        pool: &PgPool,
        event_id: i64,
        name: &str,
        creator_id: Option<i64>,
    ) -> i64 {
        let row: (i32,) = sqlx::query_as(
            "INSERT INTO merchandise (event_id, name, photo_url, group_name, creator_id, status)
             VALUES ($1, $2, NULL, 'G', $3, 'published') RETURNING id",
        )
        .bind(event_id as i32)
        .bind(name)
        .bind(creator_id.map(|v| v as i32))
        .fetch_one(pool)
        .await
        .unwrap();
        row.0 as i64
    }

    // merch1: owned by a plain user -> ownership delete path.
    let merch_creator = login_guest(&pool, "rbac-merch-owner", "t").await;
    let merch_id = insert_merch(&pool, event_id, "Pin", Some(merch_creator)).await;

    // Merch creator can delete their own merch (ownership short-circuit).
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch_id, merch_creator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // merch2: owned by nobody (creator_id NULL) -> RBAC paths.
    let merch2 = insert_merch(&pool, event_id, "Sticker", None).await;

    // Plain non-owner cannot delete.
    let plain = login_guest(&pool, "rbac-merch-plain", "t").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch2, plain
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Event editor can delete (merch.delete, event scope).
    let editor = login_guest(&pool, "rbac-merch-editor", "t").await;
    assign_event_role(&pool, editor, event_id, "editor").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch2, editor
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // A third merch: a moderator can delete via merch.delete.any.
    let merch3 = insert_merch(&pool, event_id, "Poster", None).await;
    let moderator = login_guest(&pool, "rbac-merch-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch3, moderator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // The event creator (event/creator) can also delete merch.
    let merch4 = insert_merch(&pool, event_id, "Banner", None).await;
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/events/{}/merch/{}?user_id={}",
                    event_id, merch4, creator_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_rbac_create_merch_roles(pool: PgPool) {
    // ADR 0005: merch creation is gated by `merch.create` (event scope),
    // granted to the event creator + editor, plus the admin superuser bypass
    // and `merch.create.any` (moderator) global override.
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "merch-create-creator", "Merch Create Event")
            .await;

    // The event creator (event/creator) can create merch.
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        &format!(
            r#"{{"name": "By Creator", "groupName": "G", "creatorId": {}}}"#,
            creator_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    // An event editor can create merch (event/merch.create).
    let editor = login_guest(&pool, "merch-create-editor", "t").await;
    assign_event_role(&pool, editor, event_id, "editor").await;
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        &format!(
            r#"{{"name": "By Editor", "groupName": "G", "creatorId": {}}}"#,
            editor
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    // A plain non-member user is denied (no event role, no global override).
    let plain = login_guest(&pool, "merch-create-plain", "t").await;
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        &format!(
            r#"{{"name": "By Plain", "groupName": "G", "creatorId": {}}}"#,
            plain
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // A moderator can create merch in any event via merch.create.any.
    let moderator = login_guest(&pool, "merch-create-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        &format!(
            r#"{{"name": "By Mod", "groupName": "G", "creatorId": {}}}"#,
            moderator
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    // An admin can create merch via the superuser bypass.
    let admin = login_guest(&pool, "merch-create-admin", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        &format!(
            r#"{{"name": "By Admin", "groupName": "G", "creatorId": {}}}"#,
            admin
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    // A banned user is rejected by verify_active before the RBAC check.
    let banned = login_guest(&pool, "merch-create-banned", "t").await;
    sqlx::query("UPDATE users SET is_banned = true WHERE id = $1")
        .bind(banned as i32)
        .execute(&pool)
        .await
        .unwrap();
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        &format!(
            r#"{{"name": "By Banned", "groupName": "G", "creatorId": {}}}"#,
            banned
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // A missing event is 404 (reported before the RBAC check, not leaked as 403).
    let resp = post_json(
        &pool,
        "/api/v1/events/999999/merch",
        &format!(
            r#"{{"name": "No Event", "groupName": "G", "creatorId": {}}}"#,
            creator_id
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // Omitting creator_id is a 400 (it is the caller identity the gate requires).
    let resp = post_json(
        &pool,
        &format!("/api/v1/events/{}/merch", event_id),
        r#"{"name": "No Caller", "groupName": "G"}"#,
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn test_rbac_update_and_publish_merch_roles(pool: PgPool) {
    // #370: update_merch / publish_merch are gated by ownership (the merch
    // creator) OR `merch.edit` (event scope; event creator + editor), with the
    // admin superuser bypass and `merch.edit.any` (moderator) overlap resolved
    // inside RbacService::check. Merch is seeded via SQL so a plain user can
    // own a row (the gated create endpoint can no longer produce that).
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "merch-edit-creator", "Merch Edit Event").await;

    async fn insert_merch(
        pool: &PgPool,
        event_id: i64,
        name: &str,
        creator_id: Option<i64>,
    ) -> i64 {
        let row: (i32,) = sqlx::query_as(
            "INSERT INTO merchandise (event_id, name, photo_url, group_name, creator_id, status)
             VALUES ($1, $2, NULL, 'G', $3, 'draft') RETURNING id",
        )
        .bind(event_id as i32)
        .bind(name)
        .bind(creator_id.map(|v| v as i32))
        .fetch_one(pool)
        .await
        .unwrap();
        row.0 as i64
    }

    async fn update_merch(pool: &PgPool, event_id: i64, merch_id: i64, user_id: i64) -> StatusCode {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/api/v1/events/{}/merch/{}", event_id, merch_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"userId": {}, "photoUrl": "https://updated"}}"#,
                        user_id
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        resp.status()
    }

    async fn publish_merch(
        pool: &PgPool,
        event_id: i64,
        merch_id: i64,
        user_id: i64,
    ) -> StatusCode {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!(
                        "/api/v1/events/{}/merch/{}/publish",
                        event_id, merch_id
                    ))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(r#"{{"userId": {}}}"#, user_id)))
                    .unwrap(),
            )
            .await
            .unwrap();
        resp.status()
    }

    // The merch creator (a plain user who owns the row via SQL) can update +
    // publish via the ownership short-circuit, with no event/global role.
    let owner = login_guest(&pool, "merch-edit-owner", "t").await;
    let m = insert_merch(&pool, event_id, "Owner Pin", Some(owner)).await;
    assert_eq!(
        update_merch(&pool, event_id, m, owner).await,
        StatusCode::OK
    );
    assert_eq!(
        publish_merch(&pool, event_id, m, owner).await,
        StatusCode::OK
    );

    // An event editor can update + publish merch they do not own (event/merch.edit).
    let editor = login_guest(&pool, "merch-edit-editor", "t").await;
    assign_event_role(&pool, editor, event_id, "editor").await;
    let m = insert_merch(&pool, event_id, "Editor Pin", None).await;
    assert_eq!(
        update_merch(&pool, event_id, m, editor).await,
        StatusCode::OK
    );
    assert_eq!(
        publish_merch(&pool, event_id, m, editor).await,
        StatusCode::OK
    );

    // The event creator can update + publish (event/merch.edit).
    let m = insert_merch(&pool, event_id, "Creator Pin", None).await;
    assert_eq!(
        update_merch(&pool, event_id, m, creator_id).await,
        StatusCode::OK
    );

    // A plain non-owner non-editor is denied.
    let plain = login_guest(&pool, "merch-edit-plain", "t").await;
    let m = insert_merch(&pool, event_id, "Plain Pin", None).await;
    assert_eq!(
        update_merch(&pool, event_id, m, plain).await,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        publish_merch(&pool, event_id, m, plain).await,
        StatusCode::FORBIDDEN
    );

    // A moderator can update + publish any merch via merch.edit.any.
    let moderator = login_guest(&pool, "merch-edit-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let m = insert_merch(&pool, event_id, "Mod Pin", None).await;
    assert_eq!(
        update_merch(&pool, event_id, m, moderator).await,
        StatusCode::OK
    );
    assert_eq!(
        publish_merch(&pool, event_id, m, moderator).await,
        StatusCode::OK
    );

    // An admin can update + publish via the superuser bypass.
    let admin = login_guest(&pool, "merch-edit-admin", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let m = insert_merch(&pool, event_id, "Admin Pin", None).await;
    assert_eq!(
        update_merch(&pool, event_id, m, admin).await,
        StatusCode::OK
    );

    // 404-before-403: a missing merch is 404 even for a caller who lacks the
    // event role (not leaked as 403).
    assert_eq!(
        update_merch(&pool, event_id, 999999, plain).await,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        publish_merch(&pool, event_id, 999999, plain).await,
        StatusCode::NOT_FOUND
    );
}

#[sqlx::test]
async fn test_rbac_update_group_roles(pool: PgPool) {
    // #370: group update is gated by ownership (the group creator) OR
    // `group.edit` (event scope; event creator + editor), with the admin bypass
    // and `group.edit.any` (moderator) overlap. Mirrors the merch model.
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "group-edit-creator", "Group Edit Event").await;

    // Group creation is not gated, so a plain user can create a group and own
    // it (created_by = user_id).
    let owner = login_guest(&pool, "group-edit-owner", "t").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/events/{}/groups", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Pins", "description": "orig"}}"#,
                    event_id, owner
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    async fn update_group(pool: &PgPool, event_id: i64, user_id: i64, desc: &str) -> StatusCode {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let resp = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/api/v1/events/{}/groups/Pins", event_id))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"eventId": {}, "userId": {}, "groupName": "Pins", "description": "{}"}}"#,
                        event_id, user_id, desc
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        resp.status()
    }

    // The group creator (owner) can update via the ownership short-circuit.
    assert_eq!(
        update_group(&pool, event_id, owner, "by owner").await,
        StatusCode::OK
    );

    // An event editor can update a group they did not create (event/group.edit).
    let editor = login_guest(&pool, "group-edit-editor", "t").await;
    assign_event_role(&pool, editor, event_id, "editor").await;
    assert_eq!(
        update_group(&pool, event_id, editor, "by editor").await,
        StatusCode::OK
    );

    // The event creator can update (event/group.edit).
    assert_eq!(
        update_group(&pool, event_id, creator_id, "by creator").await,
        StatusCode::OK
    );

    // A plain non-owner non-editor is denied.
    let plain = login_guest(&pool, "group-edit-plain", "t").await;
    assert_eq!(
        update_group(&pool, event_id, plain, "hostile").await,
        StatusCode::FORBIDDEN
    );

    // A moderator can update any group via group.edit.any.
    let moderator = login_guest(&pool, "group-edit-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    assert_eq!(
        update_group(&pool, event_id, moderator, "by mod").await,
        StatusCode::OK
    );

    // An admin can update via the superuser bypass.
    let admin = login_guest(&pool, "group-edit-admin", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    assert_eq!(
        update_group(&pool, event_id, admin, "by admin").await,
        StatusCode::OK
    );

    // 404-before-403: updating a missing group is 404 even for a plain user
    // (the existence check runs before the RBAC check).
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/events/{}/groups/Missing", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"eventId": {}, "userId": {}, "groupName": "Missing", "description": "x"}}"#,
                    event_id, plain
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn test_rbac_delete_match_permission(pool: PgPool) {
    // #370: admin match deletion is gated by the global `match.delete`
    // permission (granted to moderator + admin, plus the admin superuser
    // bypass), replacing the old require_admin_or_mod role-list check.
    let (creator_id, event_id) =
        create_test_user_and_event(pool.clone(), "match-del-creator", "Match Del Event").await;
    // A second user so we can seed a real matches row (user1_id != user2_id).
    let other = login_guest(&pool, "match-del-other", "t").await;

    async fn seed_match(pool: &PgPool, event_id: i64, u1: i64, u2: i64) -> i64 {
        let m: (i32,) = sqlx::query_as(
            "INSERT INTO matches (user1_id, user2_id, event_id, group_name, status)
             VALUES ($1, $2, $3, 'G', 'PENDING') RETURNING id",
        )
        .bind(u1 as i32)
        .bind(u2 as i32)
        .bind(event_id as i32)
        .fetch_one(pool)
        .await
        .unwrap();
        m.0 as i64
    }

    async fn row_exists(pool: &PgPool, match_id: i64) -> bool {
        sqlx::query_scalar::<_, Option<i32>>("SELECT id FROM matches WHERE id = $1")
            .bind(match_id as i32)
            .fetch_optional(pool)
            .await
            .unwrap()
            .is_some()
    }

    // A plain user (creator_id is a moderator here, so demote it to a plain
    // user first) cannot delete a match.
    grant_global_role(&pool, creator_id, "user").await;
    let match_id = seed_match(&pool, event_id, creator_id, other).await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/matches/{}?user_id={}",
                    match_id, creator_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    assert!(
        row_exists(&pool, match_id).await,
        "plain user must not delete the match"
    );

    // A moderator can delete (global/match.delete).
    let moderator = login_guest(&pool, "match-del-mod", "t").await;
    grant_global_role(&pool, moderator, "moderator").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/matches/{}?user_id={}",
                    match_id, moderator
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(
        !row_exists(&pool, match_id).await,
        "moderator should have deleted the match"
    );

    // An admin can delete via the superuser bypass (seed a fresh row: the
    // prior one is gone, so the canonical-pair unique index does not collide).
    let match_id2 = seed_match(&pool, event_id, creator_id, other).await;
    let admin = login_guest(&pool, "match-del-admin", "t").await;
    grant_global_role(&pool, admin, "admin").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/api/v1/admin/matches/{}?user_id={}",
                    match_id2, admin
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(
        !row_exists(&pool, match_id2).await,
        "admin should have deleted the match"
    );
}
