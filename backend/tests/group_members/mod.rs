//! Group-scoped member management + self-service creator transfer (#443).

use crate::common::*;

/// Helper: create an event + a group via the public groups API as `creator`.
async fn create_group(pool: &PgPool, event_id: i64, creator: i64, group_name: &str) -> i64 {
    let body = format!(
        r#"{{"eventId": {}, "userId": {}, "groupName": "{}"}}"#,
        event_id, creator, group_name
    );
    let resp = post_json(pool, &format!("/api/v1/events/{}/groups", event_id), &body).await;
    assert_eq!(resp.status(), StatusCode::OK, "create group failed");
    let v: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    v["id"].as_i64().unwrap()
}

async fn has_group_role(pool: &PgPool, user_id: i64, group_id: i64, role_name: &str) -> bool {
    let n: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND ur.scope_type = 'group' AND ur.scope_id = $2
           AND r.name = $3",
    )
    .bind(user_id as i32)
    .bind(group_id as i32)
    .bind(role_name)
    .fetch_one(pool)
    .await
    .unwrap();
    n > 0
}

async fn assign_group_role(pool: &PgPool, user_id: i64, group_id: i64, role_name: &str) {
    let role_id: i32 =
        sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'group' AND name = $1")
            .bind(role_name)
            .fetch_one(pool)
            .await
            .unwrap();
    sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'group', $3)
         ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
    )
    .bind(user_id as i32)
    .bind(role_id)
    .bind(group_id as i32)
    .execute(pool)
    .await
    .unwrap();
}

#[sqlx::test]
async fn test_group_create_assigns_group_creator(pool: PgPool) {
    let creator = login_guest(&pool, "gcreate-creator", "tok").await;
    let event_id = create_event(&pool, "GCreate Event", creator).await;
    let group_id = create_group(&pool, event_id, creator, "Pens").await;

    assert!(
        has_group_role(&pool, creator, group_id, "creator").await,
        "group creation must assign group/creator"
    );
    let created_by: Option<i32> =
        sqlx::query_scalar("SELECT created_by FROM merchandise_groups WHERE id = $1")
            .bind(group_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(created_by, Some(creator as i32));
}

#[sqlx::test]
async fn test_group_member_assign_editor(pool: PgPool) {
    let creator = login_guest(&pool, "gmem-assign-c", "tok").await;
    let event_id = create_event(&pool, "GMem Assign Event", creator).await;
    let group_id = create_group(&pool, event_id, creator, "Badges").await;
    let target = login_guest(&pool, "gmem-assign-t", "tok").await;

    assert!(!has_group_role(&pool, target, group_id, "editor").await);

    let resp = post_json(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Badges/members/{}?user_id={}",
            event_id, target, creator
        ),
        "",
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK, "assign group editor failed");
    assert!(has_group_role(&pool, target, group_id, "editor").await);

    // Editor can update group info via group-scoped group.edit.
    let resp = put_json(
        &pool,
        &format!("/api/v1/events/{}/groups/Badges", event_id),
        &format!(
            r#"{{"eventId": {}, "userId": {}, "groupName": "Badges", "description": "by editor"}}"#,
            event_id, target
        ),
    )
    .await;
    assert_eq!(
        resp.status(),
        StatusCode::OK,
        "group editor should edit group info"
    );

    // GET members lists creator + editor.
    let resp = get_request(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Badges/members?user_id={}",
            event_id, creator
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let members = body["members"].as_array().unwrap();
    assert_eq!(members.len(), 2);
    let roles: Vec<&str> = members
        .iter()
        .map(|m| m["role"].as_str().unwrap())
        .collect();
    assert!(roles.contains(&"creator"));
    assert!(roles.contains(&"editor"));
}

#[sqlx::test]
async fn test_group_member_assign_permission_boundary(pool: PgPool) {
    let creator = login_guest(&pool, "gmem-bound-c", "tok").await;
    let event_id = create_event(&pool, "GMem Bound Event", creator).await;
    let group_id = create_group(&pool, event_id, creator, "Cards").await;

    let plain = login_guest(&pool, "gmem-bound-plain", "tok").await;
    let editor = login_guest(&pool, "gmem-bound-ed", "tok").await;
    let moderator = login_guest(&pool, "gmem-bound-mod", "tok").await;
    let admin = login_guest(&pool, "gmem-bound-adm", "tok").await;
    let target = login_guest(&pool, "gmem-bound-tgt", "tok").await;

    grant_global_role(&pool, moderator, "moderator").await;
    grant_global_role(&pool, admin, "admin").await;
    assign_group_role(&pool, editor, group_id, "editor").await;

    let assign = |caller: i64| {
        let pool = pool.clone();
        async move {
            post_json(
                &pool,
                &format!(
                    "/api/v1/events/{}/groups/Cards/members/{}?user_id={}",
                    event_id, target, caller
                ),
                "",
            )
            .await
        }
    };

    // Event-scoped editor is not a group editor (#443 product rule).
    let event_editor = login_guest(&pool, "gmem-bound-ev-ed", "tok").await;
    assign_event_role(&pool, event_editor, event_id, "editor").await;
    assert_eq!(assign(event_editor).await.status(), StatusCode::FORBIDDEN);
    let list_as_event_editor = get_request(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Cards/members?user_id={}",
            event_id, event_editor
        ),
    )
    .await;
    assert_eq!(list_as_event_editor.status(), StatusCode::FORBIDDEN);

    // Plain user and global moderator are denied (no *.any for group.member.manage).
    assert_eq!(assign(plain).await.status(), StatusCode::FORBIDDEN);
    assert_eq!(assign(moderator).await.status(), StatusCode::FORBIDDEN);
    // Group editor, creator, and admin bypass may assign.
    assert_eq!(assign(editor).await.status(), StatusCode::OK);
    assert_eq!(assign(admin).await.status(), StatusCode::OK);
    assert_eq!(assign(creator).await.status(), StatusCode::OK);

    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = $1 AND ur.scope_type = 'group' AND ur.scope_id = $2
           AND r.name = 'editor'",
    )
    .bind(target as i32)
    .bind(group_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count, 1, "idempotent assign leaves one editor row");
}

#[sqlx::test]
async fn test_group_member_revoke_preserves_creator(pool: PgPool) {
    let creator = login_guest(&pool, "gmem-preserve-c", "tok").await;
    let event_id = create_event(&pool, "GMem Preserve Event", creator).await;
    let group_id = create_group(&pool, event_id, creator, "Pins").await;

    assert!(has_group_role(&pool, creator, group_id, "creator").await);
    let resp = delete_request(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Pins/members/{}?user_id={}",
            event_id, creator, creator
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(
        has_group_role(&pool, creator, group_id, "creator").await,
        "creator role must survive editor-revoke"
    );

    let target = login_guest(&pool, "gmem-preserve-t", "tok").await;
    post_json(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Pins/members/{}?user_id={}",
            event_id, target, creator
        ),
        "",
    )
    .await;
    assert!(has_group_role(&pool, target, group_id, "editor").await);

    let resp = delete_request(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Pins/members/{}?user_id={}",
            event_id, target, creator
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(!has_group_role(&pool, target, group_id, "editor").await);
}

#[sqlx::test]
async fn test_group_members_404_before_403(pool: PgPool) {
    let plain = login_guest(&pool, "gmem-404-plain", "tok").await;
    // Missing group as outsider → 404, not 403.
    let resp = get_request(
        &pool,
        &format!(
            "/api/v1/events/999999/groups/NoSuch/members?user_id={}",
            plain
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    let creator = login_guest(&pool, "gmem-404-c", "tok").await;
    let event_id = create_event(&pool, "GMem 404 Event", creator).await;
    let _group_id = create_group(&pool, event_id, creator, "Exists").await;

    let resp = get_request(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Missing/members?user_id={}",
            event_id, plain
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // Existing group, outsider → 403.
    let resp = get_request(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Exists/members?user_id={}",
            event_id, plain
        ),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn test_self_transfer_group_creator_success(pool: PgPool) {
    let creator = login_guest(&pool, "gself-xfer-old", "tok").await;
    let event_id = create_event(&pool, "GSelf Xfer Event", creator).await;
    let group_id = create_group(&pool, event_id, creator, "Stickers").await;
    let new_creator = login_guest(&pool, "gself-xfer-new", "tok").await;

    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Stickers/creator?user_id={}",
            event_id, creator
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, new_creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);

    let created_by: Option<i32> =
        sqlx::query_scalar("SELECT created_by FROM merchandise_groups WHERE id = $1")
            .bind(group_id as i32)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(created_by, Some(new_creator as i32));
    assert!(has_group_role(&pool, new_creator, group_id, "creator").await);
    assert!(!has_group_role(&pool, creator, group_id, "creator").await);
    // Previous creator is NOT auto-promoted to editor.
    assert!(!has_group_role(&pool, creator, group_id, "editor").await);
}

#[sqlx::test]
async fn test_self_transfer_group_creator_rbac(pool: PgPool) {
    let creator = login_guest(&pool, "gself-rbac-c", "tok").await;
    let event_id = create_event(&pool, "GSelf Rbac Event", creator).await;
    let group_id = create_group(&pool, event_id, creator, "Tapes").await;
    let editor = login_guest(&pool, "gself-rbac-ed", "tok").await;
    let plain = login_guest(&pool, "gself-rbac-plain", "tok").await;
    let target = login_guest(&pool, "gself-rbac-tgt", "tok").await;
    assign_group_role(&pool, editor, group_id, "editor").await;

    // Editor cannot transfer creator.
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Tapes/creator?user_id={}",
            event_id, editor
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Plain outsider cannot transfer.
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Tapes/creator?user_id={}",
            event_id, plain
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, target),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Already creator.
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Tapes/creator?user_id={}",
            event_id, creator
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

    // Missing target.
    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/events/{}/groups/Tapes/creator?user_id={}",
            event_id, creator
        ),
        r#"{"newCreatorId": 999999}"#,
    )
    .await;
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn test_my_group_role_gates(pool: PgPool) {
    let creator = login_guest(&pool, "gmyrole-c", "tok").await;
    let event_id = create_event(&pool, "GMyRole Event", creator).await;
    let group_id = create_group(&pool, event_id, creator, "Keychains").await;
    let editor = login_guest(&pool, "gmyrole-ed", "tok").await;
    let plain = login_guest(&pool, "gmyrole-plain", "tok").await;
    assign_group_role(&pool, editor, group_id, "editor").await;

    let fetch = |caller: i64| {
        let pool = pool.clone();
        async move {
            let resp = get_request(
                &pool,
                &format!(
                    "/api/v1/events/{}/groups/Keychains/my-role?user_id={}",
                    event_id, caller
                ),
            )
            .await;
            assert_eq!(resp.status(), StatusCode::OK);
            let body: serde_json::Value =
                serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
            body
        }
    };

    // ProtoJSON omits false bools; treat missing as false (same as event my-role).
    let bool_field = |body: &serde_json::Value, key: &str| body[key].as_bool().unwrap_or(false);

    let c = fetch(creator).await;
    assert_eq!(c["role"], "creator");
    assert!(bool_field(&c, "canManageEditors"));
    assert!(bool_field(&c, "canTransferCreator"));
    assert!(bool_field(&c, "canEditGroup"));

    let e = fetch(editor).await;
    assert_eq!(e["role"], "editor");
    assert!(bool_field(&e, "canManageEditors"));
    assert!(!bool_field(&e, "canTransferCreator"));
    assert!(bool_field(&e, "canEditGroup"));

    let p = fetch(plain).await;
    assert_eq!(p["role"], "none");
    assert!(!bool_field(&p, "canManageEditors"));
    assert!(!bool_field(&p, "canTransferCreator"));
    assert!(!bool_field(&p, "canEditGroup"));
}

#[sqlx::test]
async fn test_admin_group_transfer_syncs_role(pool: PgPool) {
    let creator = login_guest(&pool, "gadmin-xfer-old", "tok").await;
    let event_id = create_event(&pool, "GAdmin Xfer Event", creator).await;
    let group_id = create_group(&pool, event_id, creator, "Posters").await;
    let new_creator = login_guest(&pool, "gadmin-xfer-new", "tok").await;
    let staff = login_guest(&pool, "gadmin-xfer-staff", "tok").await;
    grant_global_role(&pool, staff, "moderator").await;

    assert!(has_group_role(&pool, creator, group_id, "creator").await);

    let resp = put_json(
        &pool,
        &format!(
            "/api/v1/admin/events/{}/groups/Posters/creator?user_id={}",
            event_id, staff
        ),
        &format!(r#"{{"newCreatorId": {}}}"#, new_creator),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(has_group_role(&pool, new_creator, group_id, "creator").await);
    assert!(!has_group_role(&pool, creator, group_id, "creator").await);
}

#[sqlx::test]
async fn test_merch_create_assigns_group_creator(pool: PgPool) {
    let creator = login_guest(&pool, "gmerch-c", "tok").await;
    let event_id = create_event(&pool, "GMerch Event", creator).await;
    let _merch = create_merch(&pool, event_id, "Item1", "AutoGroup").await;

    let group_id: i32 = sqlx::query_scalar(
        "SELECT id FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
    )
    .bind(event_id as i32)
    .bind("AutoGroup")
    .fetch_one(&pool)
    .await
    .unwrap();

    assert!(
        has_group_role(&pool, creator, group_id as i64, "creator").await,
        "merch create path must assign group/creator"
    );
}
