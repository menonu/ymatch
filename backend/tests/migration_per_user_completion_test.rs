// Migration-level test for migration 20261007120000 (per-user completion).
//
// The migration adds `user{1,2}_completed_at` and backfills existing
// COMPLETED matches as completed by both users (the old shared semantics),
// preferring each user's inventory-apply time. Non-COMPLETED matches stay
// NULL on both sides.
//
// `migrations = false` gives a fresh empty DB so we can stage the schema up to
// (but excluding) the target migration, seed rows, then apply it.

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use std::borrow::Cow;

/// The version of the migration under test (20261007120000).
const TARGET_VERSION: i64 = 20261007120000;

#[sqlx::test(migrations = false)]
async fn migration_backfills_completed_matches_for_both_users(pool: PgPool) {
    let full = sqlx::migrate!("./migrations");
    let prior = sqlx::migrate::Migrator {
        migrations: Cow::Owned(
            full.migrations
                .iter()
                .filter(|m| m.version != TARGET_VERSION)
                .cloned()
                .collect(),
        ),
        ..sqlx::migrate::Migrator::DEFAULT
    };
    prior.run(&pool).await.expect("prior migrations apply");

    for name in ["done-u1", "done-u2"] {
        sqlx::query("INSERT INTO users (username, password_hash) VALUES ($1, 'x')")
            .bind(name)
            .execute(&pool)
            .await
            .unwrap();
    }
    let u1: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'done-u1'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let u2: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'done-u2'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let event_id: i32 = sqlx::query_scalar(
        "INSERT INTO events (name, creator_id) VALUES ('Done Event', $1) RETURNING id",
    )
    .bind(u1)
    .fetch_one(&pool)
    .await
    .unwrap();

    // COMPLETED where user1 already applied inventory at a known time.
    let applied_at: DateTime<Utc> = "2026-01-02T03:04:05Z".parse().unwrap();
    let completed_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name,
                              user1_inventory_applied_at)
         VALUES ($1, $2, 'COMPLETED', $3, 'G1', $4) RETURNING id",
    )
    .bind(u1)
    .bind(u2)
    .bind(event_id)
    .bind(applied_at)
    .fetch_one(&pool)
    .await
    .unwrap();
    let accepted_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name)
         VALUES ($1, $2, 'ACCEPTED', $3, 'G2') RETURNING id",
    )
    .bind(u1)
    .bind(u2)
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    full.run(&pool).await.expect("target migration applies");

    let completed_at = |id: i32| {
        let pool = pool.clone();
        async move {
            sqlx::query_as::<_, (Option<DateTime<Utc>>, Option<DateTime<Utc>>)>(
                "SELECT user1_completed_at, user2_completed_at FROM matches WHERE id = $1",
            )
            .bind(id)
            .fetch_one(&pool)
            .await
            .unwrap()
        }
    };

    let (c1, c2) = completed_at(completed_id).await;
    assert_eq!(c1, Some(applied_at), "user1 backfilled from apply time");
    assert!(c2.is_some(), "user2 backfilled (no apply time → NOW())");

    let (a1, a2) = completed_at(accepted_id).await;
    assert_eq!((a1, a2), (None, None), "non-COMPLETED stays uncompleted");
}
