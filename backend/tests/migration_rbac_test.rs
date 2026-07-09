// Migration-level test for migration 20260705000000 (ADR 0004 / issue #228).
//
// The migration introduces the four-table RBAC model (roles, permissions,
// role_permissions, scoped user_roles), seeds the role/permission catalog and
// the role->permission matrix, and backfills existing `users.role` (global) and
// `events.creator_id` (event/creator) into `user_roles`. No code reads the new
// tables yet, so this test is the regression guard for the migration itself.
//
// Mirrors migration_match_dedup_test.rs: `migrations = false` gives a fresh
// empty DB so we can stage the schema up to (but excluding) the target
// migration, seed known users/events, then apply it and assert the catalog,
// the backfill, the `UNIQUE NULLS NOT DISTINCT` global dedup, the
// `scope_type`/`scope_id` invariant CHECK, and idempotency.

use sqlx::PgPool;
use std::borrow::Cow;

/// The version of the migration under test (20260705000000).
const TARGET_VERSION: i64 = 20260705000000;

#[sqlx::test(migrations = false)]
async fn migration_builds_rbac_catalog_and_backfills_assignments(pool: PgPool) {
    // 1. Apply every migration BEFORE the target, so the RBAC tables are absent
    //    and we can seed users/events with arbitrary roles directly via SQL.
    //    Only strictly-prior versions are applied here (not later migrations
    //    such as 20260708000000_merch_create_permission, which depend on the
    //    RBAC tables the target creates); the target and all later migrations
    //    are applied together by `full.run` below.
    let full = sqlx::migrate!("./migrations");
    let prior = sqlx::migrate::Migrator {
        migrations: Cow::Owned(
            full.migrations
                .iter()
                .filter(|m| m.version < TARGET_VERSION)
                .cloned()
                .collect(),
        ),
        ..sqlx::migrate::Migrator::DEFAULT
    };
    prior.run(&pool).await.expect("prior migrations apply");

    // 2. Seed users with a mix of global roles, including one bogus value
    //    ('superuser') that must be silently dropped by the backfill JOIN, and
    //    one user left on the DEFAULT 'user' role.
    for (name, role) in [
        ("rbac-admin", "admin"),
        ("rbac-mod", "moderator"),
        ("rbac-user", "user"),
        ("rbac-default", "user"),
        ("rbac-bogus", "superuser"),
    ] {
        sqlx::query("INSERT INTO users (username, role) VALUES ($1, $2)")
            .bind(name)
            .bind(role)
            .execute(&pool)
            .await
            .unwrap();
    }
    let admin_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'rbac-admin'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let mod_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'rbac-mod'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let user_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'rbac-user'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let bogus_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'rbac-bogus'")
        .fetch_one(&pool)
        .await
        .unwrap();

    // Seed two events: one with a creator (must get an event/creator row) and
    // one with a NULL creator_id (must get none).
    sqlx::query("INSERT INTO events (name, creator_id) VALUES ('Owned Event', $1)")
        .bind(admin_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO events (name, creator_id) VALUES ('Orphan Event', NULL)")
        .execute(&pool)
        .await
        .unwrap();
    let owned_event_id: i32 =
        sqlx::query_scalar("SELECT id FROM events WHERE name = 'Owned Event'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let orphan_event_id: i32 =
        sqlx::query_scalar("SELECT id FROM events WHERE name = 'Orphan Event'")
            .fetch_one(&pool)
            .await
            .unwrap();

    // 3. Apply the target migration (the one under test).
    full.run(&pool).await.expect("target migration applies");

    // 4. Assert the seeded catalog.
    let roles: i64 = sqlx::query_scalar("SELECT count(*) FROM roles")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(roles, 5, "expected exactly 5 roles (3 global + 2 event)");

    let perms: i64 = sqlx::query_scalar("SELECT count(*) FROM permissions")
        .fetch_one(&pool)
        .await
        .unwrap();
    // 19 = 14 from ADR 0004/0005 (9 global + 5 event) + 5 from #370
    // (merch.edit event + merch.edit.any global, group.edit event +
    // group.edit.any global, match.delete global).
    assert_eq!(
        perms, 19,
        "expected exactly 19 permissions (12 global + 7 event)"
    );

    let rp: i64 = sqlx::query_scalar("SELECT count(*) FROM role_permissions")
        .fetch_one(&pool)
        .await
        .unwrap();
    // 34 = 24 from ADR 0004/0005 (9 admin + 7 moderator + 5 creator + 3 editor)
    // + 10 from #370 (creator+editor -> merch.edit, group.edit; moderator+admin
    // -> merch.edit.any, group.edit.any, match.delete).
    assert_eq!(
        rp, 34,
        "expected exactly 34 role->permission rows (12 admin + 10 moderator + 7 creator + 5 editor)"
    );

    // ADR 0005: the two new permissions and their four role grants exist.
    for (scope_type, name) in [("event", "merch.create"), ("global", "merch.create.any")] {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM permissions WHERE scope_type = $1 AND name = $2)",
        )
        .bind(scope_type)
        .bind(name)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert!(exists, "ADR 0005 must seed permission {scope_type}/{name}");
    }
    for (r_scope, r_name, p_scope, p_name) in [
        ("event", "creator", "event", "merch.create"),
        ("event", "editor", "event", "merch.create"),
        ("global", "moderator", "global", "merch.create.any"),
        ("global", "admin", "global", "merch.create.any"),
    ] {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(
                SELECT 1 FROM role_permissions rp
                JOIN roles r ON r.id = rp.role_id
                JOIN permissions p ON p.id = rp.permission_id
                WHERE r.scope_type = $1 AND r.name = $2
                  AND p.scope_type = $3 AND p.name = $4)",
        )
        .bind(r_scope)
        .bind(r_name)
        .bind(p_scope)
        .bind(p_name)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert!(
            exists,
            "ADR 0005 must grant {r_scope}/{r_name} -> {p_scope}/{p_name}"
        );
    }

    // #370: the five new permissions and their ten role grants exist.
    for (scope_type, name) in [
        ("event", "merch.edit"),
        ("global", "merch.edit.any"),
        ("event", "group.edit"),
        ("global", "group.edit.any"),
        ("global", "match.delete"),
    ] {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM permissions WHERE scope_type = $1 AND name = $2)",
        )
        .bind(scope_type)
        .bind(name)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert!(exists, "#370 must seed permission {scope_type}/{name}");
    }
    for (r_scope, r_name, p_scope, p_name) in [
        ("event", "creator", "event", "merch.edit"),
        ("event", "editor", "event", "merch.edit"),
        ("event", "creator", "event", "group.edit"),
        ("event", "editor", "event", "group.edit"),
        ("global", "moderator", "global", "merch.edit.any"),
        ("global", "admin", "global", "merch.edit.any"),
        ("global", "moderator", "global", "group.edit.any"),
        ("global", "admin", "global", "group.edit.any"),
        ("global", "moderator", "global", "match.delete"),
        ("global", "admin", "global", "match.delete"),
    ] {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(
                SELECT 1 FROM role_permissions rp
                JOIN roles r ON r.id = rp.role_id
                JOIN permissions p ON p.id = rp.permission_id
                WHERE r.scope_type = $1 AND r.name = $2
                  AND p.scope_type = $3 AND p.name = $4)",
        )
        .bind(r_scope)
        .bind(r_name)
        .bind(p_scope)
        .bind(p_name)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert!(
            exists,
            "#370 must grant {r_scope}/{r_name} -> {p_scope}/{p_name}"
        );
    }

    // The `user` global role has NO permission rows.
    let user_role_perms: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM role_permissions rp
         JOIN roles r ON r.id = rp.role_id
         WHERE r.scope_type = 'global' AND r.name = 'user'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        user_role_perms, 0,
        "the 'user' global role must have no permission rows"
    );

    // 5. Assert the global backfill: each known-role user has exactly one global
    //    user_roles row, and the bogus-role user has none.
    for (uid, role_name) in [
        (admin_id, "admin"),
        (mod_id, "moderator"),
        (user_id, "user"),
    ] {
        let n: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM user_roles ur
             JOIN roles r ON r.id = ur.role_id
             WHERE ur.user_id = $1 AND r.scope_type = 'global' AND r.name = $2
               AND ur.scope_type = 'global' AND ur.scope_id IS NULL",
        )
        .bind(uid)
        .bind(role_name)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            n, 1,
            "user with role {role_name} must have one global user_roles row"
        );
    }

    let bogus_rows: i64 = sqlx::query_scalar("SELECT count(*) FROM user_roles WHERE user_id = $1")
        .bind(bogus_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        bogus_rows, 0,
        "a user whose users.role is not a known role must get no user_roles row"
    );

    // 6. Assert the event backfill: the owned event's creator got an
    //    event/creator row; the orphan event (NULL creator_id) got none.
    let creator_rows: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM user_roles ur
         JOIN roles r ON r.id = ur.role_id
         WHERE ur.scope_type = 'event' AND ur.scope_id = $1
           AND r.scope_type = 'event' AND r.name = 'creator'",
    )
    .bind(owned_event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        creator_rows, 1,
        "the owned event's creator must get one event/creator assignment"
    );

    let orphan_rows: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM user_roles WHERE scope_type = 'event' AND scope_id = $1",
    )
    .bind(orphan_event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        orphan_rows, 0,
        "an event with a NULL creator_id must get no event-scoped assignment"
    );

    // 7. The UNIQUE NULLS NOT DISTINCT constraint rejects a duplicate global
    //    (user, role, NULL) row -- the whole point of NULLS NOT DISTINCT, since
    //    plain UNIQUE treats NULLs as distinct and would allow the dup.
    let admin_role_id: i32 =
        sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'global' AND name = 'admin'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let dup = sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'global', NULL)",
    )
    .bind(admin_id)
    .bind(admin_role_id)
    .execute(&pool)
    .await;
    assert!(
        dup.is_err(),
        "UNIQUE NULLS NOT DISTINCT must reject a duplicate global (user, role, NULL) row"
    );

    // 8. The invariant CHECK: global scope MUST have NULL scope_id; event scope
    //    MUST have a non-NULL scope_id.
    let bad_global = sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'global', 123)",
    )
    .bind(mod_id)
    .bind(admin_role_id)
    .execute(&pool)
    .await;
    assert!(
        bad_global.is_err(),
        "CHECK must reject a global-scope row with a non-NULL scope_id"
    );

    let editor_role_id: i32 =
        sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'event' AND name = 'editor'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let bad_event = sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'event', NULL)",
    )
    .bind(mod_id)
    .bind(editor_role_id)
    .execute(&pool)
    .await;
    assert!(
        bad_event.is_err(),
        "CHECK must reject an event-scope row with a NULL scope_id"
    );

    // A valid event/editor assignment is still allowed.
    sqlx::query(
        "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
         VALUES ($1, $2, 'event', $3)",
    )
    .bind(mod_id)
    .bind(editor_role_id)
    .bind(owned_event_id)
    .execute(&pool)
    .await
    .expect("a valid event/editor assignment must be accepted");

    // 9. Idempotency: re-running each migration's SQL on the now-populated DB is
    //    a no-op (the staging checksum-sync path). Counts must be unchanged.
    let target = full
        .migrations
        .iter()
        .find(|m| m.version == TARGET_VERSION)
        .expect("target migration present");
    sqlx::raw_sql(target.sql.as_ref())
        .execute(&pool)
        .await
        .expect("re-running the target migration is idempotent");
    // Also re-run the ADR 0005 merch-create migration (20260708000000).
    let merch_create = full
        .migrations
        .iter()
        .find(|m| m.version == 20260708000000)
        .expect("ADR 0005 migration present");
    sqlx::raw_sql(merch_create.sql.as_ref())
        .execute(&pool)
        .await
        .expect("re-running the ADR 0005 migration is idempotent");
    // And re-run the #370 merch-edit/group-edit/match-delete migration
    // (20260709000000).
    let merch_edit = full
        .migrations
        .iter()
        .find(|m| m.version == 20260709000000)
        .expect("#370 migration present");
    sqlx::raw_sql(merch_edit.sql.as_ref())
        .execute(&pool)
        .await
        .expect("re-running the #370 migration is idempotent");

    let roles_again: i64 = sqlx::query_scalar("SELECT count(*) FROM roles")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(roles_again, 5, "idempotent re-run must not add roles");
    let perms_again: i64 = sqlx::query_scalar("SELECT count(*) FROM permissions")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        perms_again, 19,
        "idempotent re-run must not add permissions"
    );
    let rp_again: i64 = sqlx::query_scalar("SELECT count(*) FROM role_permissions")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        rp_again, 34,
        "idempotent re-run must not add role->permission rows"
    );
    // 5 seeded users -> 4 known-role backfills (bogus dropped) + 1 editor grant
    // above; plus 1 event/creator. = 6.
    let ur_again: i64 = sqlx::query_scalar("SELECT count(*) FROM user_roles")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        ur_again, 6,
        "idempotent re-run must not duplicate user_roles rows (4 global + 1 creator + 1 editor)"
    );
}
