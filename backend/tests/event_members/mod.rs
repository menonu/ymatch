use crate::common::*;

#[sqlx::test]
async fn test_event_member_assign_editor(pool: PgPool) {
    let creator = login_guest(&pool, "mem-assign-creator", "tok").await;
    let event_id = create_event(&pool, "Member Assign Event", creator).await;
    let target = login_guest(&pool, "mem-assign-target", "tok").await;

    // Target starts with no event role.
    assert!(!has_event_role(&pool, target, event_id, "editor").await);

    let resp = post_json(
        &pool,
        &format!(
            "/api/v1/events/{}/members/{}?user_id={}",
            event_id, target, creator
        ),
        "",
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK, "assign editor failed");

    // The editor role landed in user_roles...
    assert!(has_event_role(&pool, target, event_id, "editor").await);
    // ...and the target can now edit the event (event.edit granted to editor).
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}", event_id),
        &format!(r#"{{"userId": {}, "name": "Renamed By Editor"}}"#, target),
    )
    .await;
    assert_eq!(
        resp.status(),
        StatusCode::OK,
        "editor should be able to update event"
    );

    // GET members lists both the creator and the editor.
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/members?user_id={}", event_id, creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let members = body["members"].as_array().unwrap();
    assert_eq!(members.len(), 2, "creator + editor expected");
    let roles: Vec<&str> = members
        .iter()
        .map(|m| m["role"].as_str().unwrap())
        .collect();
    assert!(roles.contains(&"creator"));
    assert!(roles.contains(&"editor"));
}

#[sqlx::test]
async fn test_event_member_assign_permission_boundary(pool: PgPool) {
    let creator = login_guest(&pool, "mem-bound-creator", "tok").await;
    let event_id = create_event(&pool, "Member Boundary Event", creator).await;

    let plain = login_guest(&pool, "mem-bound-plain", "tok").await;
    let editor = login_guest(&pool, "mem-bound-editor", "tok").await;
    let moderator = login_guest(&pool, "mem-bound-mod", "tok").await;
    let admin = login_guest(&pool, "mem-bound-admin", "tok").await;
    let target = login_guest(&pool, "mem-bound-target", "tok").await;

    grant_global_role(&pool, moderator, "moderator").await;
    grant_global_role(&pool, admin, "admin").await;
    // `editor` is a real event editor (#442: can manage members).
    assign_event_role(&pool, editor, event_id, "editor").await;

    let assign = |caller: i64| {
        let pool = pool.clone();
        async move {
            post_json(
                &pool,
                &format!(
                    "/api/v1/events/{}/members/{}?user_id={}",
                    event_id, target, caller
                ),
                "",
            )
            .await
        }
    };

    // Plain user and global moderator are denied — there is no `*.any`
    // override for event.member.manage on the public path (#432).
    assert_eq!(assign(plain).await.status(), StatusCode::FORBIDDEN);
    assert_eq!(assign(moderator).await.status(), StatusCode::FORBIDDEN);
    // #442: event editor may assign editors; creator and admin bypass too.
    assert_eq!(assign(editor).await.status(), StatusCode::OK);
    assert_eq!(assign(admin).await.status(), StatusCode::OK);
    assert_eq!(assign(creator).await.status(), StatusCode::OK);

    // No duplicate editor row despite three successful assigns.
    assert_eq!(event_role_count(&pool, target, event_id).await, 1);
}

#[sqlx::test]
async fn test_event_member_revoke_editor(pool: PgPool) {
    let creator = login_guest(&pool, "mem-revoke-creator", "tok").await;
    let event_id = create_event(&pool, "Member Revoke Event", creator).await;
    let target = login_guest(&pool, "mem-revoke-target", "tok").await;

    // Assign via the API, then revoke.
    let resp = post_json(
        &pool,
        &format!(
            "/api/v1/events/{}/members/{}?user_id={}",
            event_id, target, creator
        ),
        "",
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK, "assign editor failed");
    assert!(has_event_role(&pool, target, event_id, "editor").await);

    let resp = delete_request(
        &pool,
        &format!(
            "/api/v1/events/{}/members/{}?user_id={}",
            event_id, target, creator
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK, "revoke editor failed");
    assert!(!has_event_role(&pool, target, event_id, "editor").await);

    // Target can no longer edit the event.
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}", event_id),
        &format!(r#"{{"userId": {}, "name": "Renamed Again"}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Idempotent: re-revoke is a no-op 200.
    let resp = delete_request(
        &pool,
        &format!(
            "/api/v1/events/{}/members/{}?user_id={}",
            event_id, target, creator
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
}

#[sqlx::test]
async fn test_event_member_revoke_preserves_creator(pool: PgPool) {
    let creator = login_guest(&pool, "mem-preserve-creator", "tok").await;
    let event_id = create_event(&pool, "Member Preserve Event", creator).await;

    // The creator's own role is the `event/creator` row auto-assigned at event
    // creation; revoke (which targets only `editor`) must never remove it.
    assert!(has_event_role(&pool, creator, event_id, "creator").await);
    let resp = delete_request(
        &pool,
        &format!(
            "/api/v1/events/{}/members/{}?user_id={}",
            event_id, creator, creator
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(
        has_event_role(&pool, creator, event_id, "creator").await,
        "creator role must survive an editor-revoke"
    );

    // Assign an editor, revoke them, and confirm the creator is still the only
    // member listed.
    let target = login_guest(&pool, "mem-preserve-target", "tok").await;
    post_json(
        &pool,
        &format!(
            "/api/v1/events/{}/members/{}?user_id={}",
            event_id, target, creator
        ),
        "",
    )
    .await;
    delete_request(
        &pool,
        &format!(
            "/api/v1/events/{}/members/{}?user_id={}",
            event_id, target, creator
        ),
    )
    .await;

    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/members?user_id={}", event_id, creator),
    )
    .await;
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let members = body["members"].as_array().unwrap();
    assert_eq!(members.len(), 1, "only the creator should remain");
    assert_eq!(members[0]["role"], "creator");
}

#[sqlx::test]
async fn test_event_member_list_requires_member_manage(pool: PgPool) {
    let creator = login_guest(&pool, "mem-list-creator", "tok").await;
    let event_id = create_event(&pool, "Member List Event", creator).await;
    let plain = login_guest(&pool, "mem-list-plain", "tok").await;
    let editor = login_guest(&pool, "mem-list-editor", "tok").await;
    assign_event_role(&pool, editor, event_id, "editor").await;

    // A plain viewer (no event.member.manage) is denied the member list.
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/members?user_id={}", event_id, plain),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // #442: event editor may list members.
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/members?user_id={}", event_id, editor),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let members = body["members"].as_array().unwrap();
    assert_eq!(members.len(), 2, "creator + editor");

    // The creator sees the list.
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/members?user_id={}", event_id, creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let members = body["members"].as_array().unwrap();
    assert_eq!(members.len(), 2);
}

#[sqlx::test]
async fn test_event_member_editor_can_revoke_editor(pool: PgPool) {
    // #442: editors may revoke other editors (never creator).
    let creator = login_guest(&pool, "mem-ed-rev-creator", "tok").await;
    let event_id = create_event(&pool, "Editor Revoke Event", creator).await;
    let editor = login_guest(&pool, "mem-ed-rev-editor", "tok").await;
    let target = login_guest(&pool, "mem-ed-rev-target", "tok").await;
    assign_event_role(&pool, editor, event_id, "editor").await;
    assign_event_role(&pool, target, event_id, "editor").await;

    let resp = delete_request(
        &pool,
        &format!(
            "/api/v1/events/{}/members/{}?user_id={}",
            event_id, target, editor
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(!has_event_role(&pool, target, event_id, "editor").await);
    assert!(has_event_role(&pool, creator, event_id, "creator").await);
}

#[sqlx::test]
async fn test_event_member_assign_404_missing_event(pool: PgPool) {
    // Admin (so the RBAC guard would pass) targets a nonexistent event.
    let admin = login_guest(&pool, "mem-404-admin", "tok").await;
    grant_global_role(&pool, admin, "admin").await;
    let target = login_guest(&pool, "mem-404-target", "tok").await;

    let resp = post_json(
        &pool,
        &format!("/api/v1/events/999999/members/{}?user_id={}", target, admin),
        "",
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn test_event_member_assign_404_missing_target(pool: PgPool) {
    let creator = login_guest(&pool, "mem-404t-creator", "tok").await;
    let event_id = create_event(&pool, "Member 404 Target Event", creator).await;

    // Creator is authorized, but the target user does not exist -> 404.
    let resp = post_json(
        &pool,
        &format!(
            "/api/v1/events/{}/members/999999?user_id={}",
            event_id, creator
        ),
        "",
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

// --- GET /api/v1/events/:id/my-role (#366 / #442) -------------------------
//
// Unlike the members list (gated by event.member.manage), `my-role` is
// readable by any active caller — it is the per-viewer gate the frontend uses
// to show/hide Add Merch and member-management UI. `can_create_merch` is the
// exact `merch.create` decision the `create_merch` handler enforces; `role` is
// the caller's event-scoped membership; `global_override` is true when a
// global admin/moderator role is in effect. #442 adds `can_manage_editors`
// and `can_transfer_creator`.
//
// NOTE: `create_event` grants the creator the global `moderator` role (event
// creation requires `event.create`), so the creator legitimately reports
// `global_override = true` — matching production, where event creators are
// always moderators/admins.

/// Fetch `my-role` as the caller and return the parsed JSON body.
async fn my_role(pool: &PgPool, event_id: i64, caller: i64) -> serde_json::Value {
    let resp = get_request(
        pool,
        &format!("/api/v1/events/{}/my-role?user_id={}", event_id, caller),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK, "my-role should be 200");
    serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap()
}

/// Read a proto3 bool field, treating an absent field (proto3 omits
/// default-valued scalars, so `false` is not serialized) as `false`.
fn bool_field(body: &serde_json::Value, key: &str) -> bool {
    body[key].as_bool().unwrap_or(false)
}

#[sqlx::test]
async fn test_my_role_creator(pool: PgPool) {
    let creator = login_guest(&pool, "myrole-creator", "tok").await;
    let event_id = create_event(&pool, "My Role Creator Event", creator).await;

    // The creator is the event's `creator` member AND a global moderator (via
    // the create_event helper), so they can create merch both ways.
    let body = my_role(&pool, event_id, creator).await;
    assert_eq!(body["role"], "creator");
    assert!(bool_field(&body, "globalOverride"));
    assert!(bool_field(&body, "canCreateMerch"));
    assert!(bool_field(&body, "canManageEditors"));
    assert!(bool_field(&body, "canTransferCreator"));
}

#[sqlx::test]
async fn test_my_role_editor(pool: PgPool) {
    let creator = login_guest(&pool, "myrole-ed-creator", "tok").await;
    let event_id = create_event(&pool, "My Role Editor Event", creator).await;
    // A pure editor: only an event-scoped editor role, no global role.
    let editor = login_guest(&pool, "myrole-editor", "tok").await;
    assign_event_role(&pool, editor, event_id, "editor").await;

    let body = my_role(&pool, event_id, editor).await;
    assert_eq!(body["role"], "editor");
    assert!(!bool_field(&body, "globalOverride"));
    assert!(bool_field(&body, "canCreateMerch"));
    // #442: editors manage editors but cannot transfer creator.
    assert!(bool_field(&body, "canManageEditors"));
    assert!(!bool_field(&body, "canTransferCreator"));
}

#[sqlx::test]
async fn test_my_role_plain_viewer(pool: PgPool) {
    let creator = login_guest(&pool, "myrole-pv-creator", "tok").await;
    let event_id = create_event(&pool, "My Role Plain Event", creator).await;
    // A viewer with no role on the event and no global role.
    let viewer = login_guest(&pool, "myrole-viewer", "tok").await;

    let body = my_role(&pool, event_id, viewer).await;
    assert_eq!(body["role"], "none");
    assert!(!bool_field(&body, "globalOverride"));
    assert!(!bool_field(&body, "canCreateMerch"));
    assert!(!bool_field(&body, "canManageEditors"));
    assert!(!bool_field(&body, "canTransferCreator"));
}

#[sqlx::test]
async fn test_my_role_moderator_global_override(pool: PgPool) {
    let creator = login_guest(&pool, "myrole-mod-creator", "tok").await;
    let event_id = create_event(&pool, "My Role Mod Event", creator).await;
    // A global moderator who is NOT a member of the event: power comes from
    // `merch.create.any`, so role is "none" but can_create_merch is true.
    // Moderators do NOT get event.member.manage on the public path.
    let moderator = login_guest(&pool, "myrole-mod", "tok").await;
    grant_global_role(&pool, moderator, "moderator").await;

    let body = my_role(&pool, event_id, moderator).await;
    assert_eq!(body["role"], "none");
    assert!(bool_field(&body, "globalOverride"));
    assert!(bool_field(&body, "canCreateMerch"));
    assert!(!bool_field(&body, "canManageEditors"));
    assert!(!bool_field(&body, "canTransferCreator"));
}

#[sqlx::test]
async fn test_my_role_admin_bypass(pool: PgPool) {
    let creator = login_guest(&pool, "myrole-adm-creator", "tok").await;
    let event_id = create_event(&pool, "My Role Admin Event", creator).await;
    // A global admin who is NOT a member: the superuser bypass grants every
    // permission, including merch.create and event.member.manage. Transfer is
    // still ownership-only on the self-service path.
    let admin = login_guest(&pool, "myrole-admin", "tok").await;
    grant_global_role(&pool, admin, "admin").await;

    let body = my_role(&pool, event_id, admin).await;
    assert_eq!(body["role"], "none");
    assert!(bool_field(&body, "globalOverride"));
    assert!(bool_field(&body, "canCreateMerch"));
    assert!(bool_field(&body, "canManageEditors"));
    assert!(!bool_field(&body, "canTransferCreator"));
}

// --- PUT /api/v1/events/:id/creator (#442 self-service) -------------------

#[sqlx::test]
async fn test_self_transfer_event_creator_success(pool: PgPool) {
    let old_creator = login_guest(&pool, "self-xfer-old", "tok").await;
    let event_id = create_event(&pool, "Self Xfer Event", old_creator).await;
    let new_creator = login_guest(&pool, "self-xfer-new", "tok").await;

    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/events/{}/creator?user_id={}",
            event_id, old_creator
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, new_creator),
    )
    .await;
    assert_eq!(
        resp.status(),
        StatusCode::OK,
        "self transfer should succeed"
    );

    let creator_id: Option<i32> = sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(creator_id, Some(new_creator as i32));
    assert!(has_event_role(&pool, new_creator, event_id, "creator").await);
    assert!(!has_event_role(&pool, old_creator, event_id, "creator").await);
    assert!(
        !has_event_role(&pool, old_creator, event_id, "editor").await,
        "previous creator is not auto-promoted to editor"
    );
}

#[sqlx::test]
async fn test_self_transfer_event_creator_rbac_and_validation(pool: PgPool) {
    let creator = login_guest(&pool, "self-xfer-val-c", "tok").await;
    let event_id = create_event(&pool, "Self Xfer Val", creator).await;
    let editor = login_guest(&pool, "self-xfer-val-ed", "tok").await;
    let plain = login_guest(&pool, "self-xfer-val-plain", "tok").await;
    let target = login_guest(&pool, "self-xfer-val-tgt", "tok").await;
    assign_event_role(&pool, editor, event_id, "editor").await;

    // Editor cannot transfer (has member.manage but not ownership).
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/creator?user_id={}", event_id, editor),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Plain user → 403.
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/creator?user_id={}", event_id, plain),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Missing event → 404.
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/999999/creator?user_id={}", creator),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // Missing target → 404.
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/creator?user_id={}", event_id, creator),
        r#"{"newCreatorId": 999999}"#,
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // Already creator → 400.
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/creator?user_id={}", event_id, creator),
        &format!(r#"{{"newCreatorId": {}}}"#, creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

    // Banned target → 400.
    let banned = login_guest(&pool, "self-xfer-val-banned", "tok").await;
    sqlx::query("UPDATE users SET is_banned = true WHERE id = $1")
        .bind(banned as i32)
        .execute(&pool)
        .await
        .unwrap();
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/creator?user_id={}", event_id, creator),
        &format!(r#"{{"newCreatorId": {}}}"#, banned),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

/// #445: after ownership has already moved, a second self-transfer by the
/// former creator must fail (403) and must not leave a second `event/creator`
/// role row.
#[sqlx::test]
async fn test_self_transfer_event_creator_stale_ownership(pool: PgPool) {
    let old_creator = login_guest(&pool, "self-xfer-stale-old", "tok").await;
    let event_id = create_event(&pool, "Self Xfer Stale", old_creator).await;
    let mid = login_guest(&pool, "self-xfer-stale-mid", "tok").await;
    let third = login_guest(&pool, "self-xfer-stale-third", "tok").await;

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

    // Former creator tries again after ownership moved (stale client / race).
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/events/{}/creator?user_id={}",
            event_id, old_creator
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, third),
    )
    .await;
    assert_eq!(
        resp.status(),
        StatusCode::FORBIDDEN,
        "stale self-transfer must not succeed"
    );

    let creator_id: Option<i32> = sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(creator_id, Some(mid as i32));
    assert_eq!(
        count_event_creator_roles(&pool, event_id).await,
        1,
        "must keep exactly one event/creator role"
    );
    assert!(has_event_role(&pool, mid, event_id, "creator").await);
    assert!(!has_event_role(&pool, old_creator, event_id, "creator").await);
    assert!(!has_event_role(&pool, third, event_id, "creator").await);
}

/// #445: two concurrent self-transfers by the same creator must leave exactly
/// one live `event/creator` assignment (one OK, one 403 under the row lock).
#[sqlx::test]
async fn test_self_transfer_event_creator_concurrent_single_winner(pool: PgPool) {
    let old_creator = login_guest(&pool, "self-xfer-race-old", "tok").await;
    let event_id = create_event(&pool, "Self Xfer Race", old_creator).await;
    let target_b = login_guest(&pool, "self-xfer-race-b", "tok").await;
    let target_c = login_guest(&pool, "self-xfer-race-c", "tok").await;

    let pool_b = pool.clone();
    let pool_c = pool.clone();
    let uri_b = format!(
        "/api/v1/events/{}/creator?user_id={}",
        event_id, old_creator
    );
    let uri_c = uri_b.clone();
    let body_b = format!(r#"{{"newCreatorId": {}}}"#, target_b);
    let body_c = format!(r#"{{"newCreatorId": {}}}"#, target_c);

    let (resp_b, resp_c) = tokio::join!(
        put_json(&pool_b, &uri_b, &body_b),
        put_json(&pool_c, &uri_c, &body_c),
    );
    let status_b = resp_b.status();
    let status_c = resp_c.status();

    assert!(
        (status_b == StatusCode::OK && status_c == StatusCode::FORBIDDEN)
            || (status_b == StatusCode::FORBIDDEN && status_c == StatusCode::OK),
        "expected one OK and one FORBIDDEN, got {status_b:?} and {status_c:?}"
    );

    let winner = if status_b == StatusCode::OK {
        target_b
    } else {
        target_c
    };
    let loser = if status_b == StatusCode::OK {
        target_c
    } else {
        target_b
    };

    let creator_id: Option<i32> = sqlx::query_scalar("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(creator_id, Some(winner as i32));
    assert_eq!(
        count_event_creator_roles(&pool, event_id).await,
        1,
        "concurrent transfers must not leave two event/creator roles"
    );
    assert!(has_event_role(&pool, winner, event_id, "creator").await);
    assert!(!has_event_role(&pool, loser, event_id, "creator").await);
    assert!(!has_event_role(&pool, old_creator, event_id, "creator").await);
}

/// Count live `event/creator` role rows for `event_id` (#445 race invariants).
async fn count_event_creator_roles(pool: &PgPool, event_id: i64) -> i64 {
    sqlx::query_scalar(
        "SELECT COUNT(*)::bigint
         FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.scope_type = 'event'
           AND ur.scope_id = $1
           AND r.scope_type = 'event'
           AND r.name = 'creator'",
    )
    .bind(event_id as i32)
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test]
async fn test_my_role_404_missing_event(pool: PgPool) {
    let viewer = login_guest(&pool, "myrole-404-viewer", "tok").await;
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/999999/my-role?user_id={}", viewer),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn test_my_role_400_missing_user_id(pool: PgPool) {
    let creator = login_guest(&pool, "myrole-400-creator", "tok").await;
    let event_id = create_event(&pool, "My Role 400 Event", creator).await;

    let resp = get_request(&pool, &format!("/api/v1/events/{}/my-role", event_id)).await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}
