// Migration-level test for 20261104120000_users_uuid_required: every account
// is a guest account, so `users.uuid` becomes NOT NULL and the unused
// `password_hash` column is dropped.
//
// `migrations = false` gives a fresh empty DB so we can stage the schema up to
// (but excluding) the target migration, seed a uuid-less row, then apply it.

use sqlx::PgPool;
use std::borrow::Cow;

/// The version of the migration under test (20261104120000).
const TARGET_VERSION: i64 = 20261104120000;

#[sqlx::test(migrations = false)]
async fn migration_requires_uuid_and_drops_password_hash(pool: PgPool) {
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

    // A legacy row without a uuid must not make the migration fail.
    sqlx::query("INSERT INTO users (username, password_hash) VALUES ('legacy-pw', 'x')")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO users (username, uuid) VALUES ('guest', 'kept-uuid')")
        .execute(&pool)
        .await
        .unwrap();

    full.run(&pool).await.expect("target migration applies");

    // Existing uuids are untouched; a missing one is filled with a fresh v4.
    let kept: String = sqlx::query_scalar("SELECT uuid FROM users WHERE username = 'guest'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(kept, "kept-uuid");
    let filled: String = sqlx::query_scalar("SELECT uuid FROM users WHERE username = 'legacy-pw'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let parsed = uuid::Uuid::try_parse(&filled).expect("filled uuid parses");
    assert_eq!(parsed.get_version(), Some(uuid::Version::Random));

    // New rows must carry a uuid.
    let err = sqlx::query("INSERT INTO users (username) VALUES ('no-uuid')")
        .execute(&pool)
        .await
        .expect_err("uuid is required");
    assert!(err.to_string().contains("null value"), "{err}");

    // password_hash is gone.
    let has_column: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM information_schema.columns \
         WHERE table_name = 'users' AND column_name = 'password_hash')",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!has_column);
}
