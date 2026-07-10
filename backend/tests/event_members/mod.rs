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
    // `editor` is a real event editor (can edit, but not manage members).
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

    // Plain user, event editor, and global moderator are all denied — there is
    // no `*.any` override for event.member.manage.
    assert_eq!(assign(plain).await.status(), StatusCode::FORBIDDEN);
    assert_eq!(assign(editor).await.status(), StatusCode::FORBIDDEN);
    assert_eq!(assign(moderator).await.status(), StatusCode::FORBIDDEN);
    // Admin superuser bypass and the event creator both pass.
    assert_eq!(assign(admin).await.status(), StatusCode::OK);
    assert_eq!(assign(creator).await.status(), StatusCode::OK);

    // No duplicate editor row despite two successful assigns.
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
async fn test_event_member_list_requires_creator(pool: PgPool) {
    let creator = login_guest(&pool, "mem-list-creator", "tok").await;
    let event_id = create_event(&pool, "Member List Event", creator).await;
    let plain = login_guest(&pool, "mem-list-plain", "tok").await;

    // A non-creator (no event.member.manage) is denied the member list.
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/members?user_id={}", event_id, plain),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // The creator sees the list (just themselves at this point).
    let resp = get_request(
        &pool,
        &format!("/api/v1/events/{}/members?user_id={}", event_id, creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let members = body["members"].as_array().unwrap();
    assert_eq!(members.len(), 1);
    assert_eq!(members[0]["role"], "creator");
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
