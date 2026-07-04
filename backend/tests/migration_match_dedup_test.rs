// Migration-level test for migration 20260704000000 (issue #346).
//
// The migration adds a UNIQUE index on the canonicalized
// (LEAST(user1_id, user2_id), GREATEST(user1_id, user2_id), event_id,
// group_name) tuple so a direct INSERT cannot create a second match for the
// same (pair, group) — including the symmetric (user2, user1) column ordering
// that app-level dedup in matching.rs catches but the DB previously did not.
//
// Like 20260622000000 did for match_items, the migration must dedup existing
// rows BEFORE adding the unique index, or it would fail with 23505 on a DB
// that already accumulated collisions (direct INSERTs bypassing the matcher).
// This reproduces that dirty state (duplicate matches on the same canonical
// (pair, group), including the symmetric ordering and a >2-dup case, with
// dependent messages + match_items on the doomed rows) and asserts the
// migration collapses them to one survivor before the index goes in.
//
// `migrations = false` gives a fresh empty DB so we can stage the schema up to
// (but excluding) the target migration, seed the dirty state, then apply it.

use sqlx::PgPool;
use std::borrow::Cow;

/// The version of the migration under test (20260704000000).
const TARGET_VERSION: i64 = 20260704000000;

#[sqlx::test(migrations = false)]
async fn migration_dedups_duplicate_matches_before_unique_index(pool: PgPool) {
    // 1. Apply every migration EXCEPT the target, so the unique index is absent
    //    and we can seed duplicate (pair, group) matches directly via SQL.
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

    // 2. Seed: two users, an event, and a merch row (for match_items legs).
    sqlx::query("INSERT INTO users (username, password_hash) VALUES ('dedup-u1', 'x')")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO users (username, password_hash) VALUES ('dedup-u2', 'x')")
        .execute(&pool)
        .await
        .unwrap();
    let u1: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'dedup-u1'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let u2: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'dedup-u2'")
        .fetch_one(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO events (name, creator_id) VALUES ('Dedup Match Event', $1)")
        .bind(u1)
        .execute(&pool)
        .await
        .unwrap();
    let event_id: i32 =
        sqlx::query_scalar("SELECT id FROM events WHERE name = 'Dedup Match Event'")
            .fetch_one(&pool)
            .await
            .unwrap();
    sqlx::query("INSERT INTO merchandise (event_id, name, group_name) VALUES ($1, 'm', 'Cards')")
        .bind(event_id)
        .execute(&pool)
        .await
        .unwrap();
    let merch_id: i32 = sqlx::query_scalar(
        "SELECT id FROM merchandise WHERE event_id = $1 AND name = 'm' AND group_name = 'Cards'",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    // Three matches on the same canonical (u1, u2) pair in group 'Cards':
    //   - survivor (lowest id): (u1, u2)
    //   - doomed dup A: (u2, u1) — symmetric column ordering
    //   - doomed dup B: (u1, u2) — same ordering, third row
    // The matcher would never create these (it dedups), so insert directly.
    sqlx::query("INSERT INTO matches (user1_id, user2_id, event_id, group_name) VALUES ($1, $2, $3, 'Cards')")
        .bind(u1).bind(u2).bind(event_id).execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO matches (user1_id, user2_id, event_id, group_name) VALUES ($1, $2, $3, 'Cards')")
        .bind(u2).bind(u1).bind(event_id).execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO matches (user1_id, user2_id, event_id, group_name) VALUES ($1, $2, $3, 'Cards')")
        .bind(u1).bind(u2).bind(event_id).execute(&pool).await.unwrap();

    let card_ids: Vec<i32> = sqlx::query_scalar(
        "SELECT id FROM matches WHERE event_id = $1 AND group_name = 'Cards' ORDER BY id",
    )
    .bind(event_id)
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(
        card_ids.len(),
        3,
        "expected 3 duplicate (pair, group) matches seeded"
    );
    let survivor = card_ids[0];
    let doomed_a = card_ids[1];
    let doomed_b = card_ids[2];

    // A match in a different group for the same pair must NOT be deduped.
    sqlx::query("INSERT INTO matches (user1_id, user2_id, event_id, group_name) VALUES ($1, $2, $3, 'Stickers')")
        .bind(u2).bind(u1).bind(event_id).execute(&pool).await.unwrap();
    let sticker_id: i32 = sqlx::query_scalar(
        "SELECT id FROM matches WHERE event_id = $1 AND group_name = 'Stickers'",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    // Dependent rows on the doomed matches: messages (no ON DELETE clause to
    // matches, so the migration must clear them) and match_items (ON DELETE
    // CASCADE, so they go with the match). Seed one of each on doomed_a.
    sqlx::query("INSERT INTO messages (match_id, sender_id, content) VALUES ($1, $2, 'hi')")
        .bind(doomed_a)
        .bind(u1)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO match_items (match_id, giver_user_id, merch_id, quantity) VALUES ($1, $2, $3, 2)")
        .bind(doomed_a)
        .bind(u1)
        .bind(merch_id)
        .execute(&pool)
        .await
        .unwrap();

    // 3. Apply the target migration (the one under test).
    full.run(&pool).await.expect("target migration applies");

    // 4. Assert the dedup state.
    let cards_left: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM matches WHERE event_id = $1 AND group_name = 'Cards'",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        cards_left, 1,
        "three duplicate 'Cards' matches must collapse to one survivor"
    );

    let survivor_alive: i64 = sqlx::query_scalar("SELECT count(*) FROM matches WHERE id = $1")
        .bind(survivor)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(survivor_alive, 1, "lowest-id survivor must be retained");

    let doomed_gone: i64 = sqlx::query_scalar("SELECT count(*) FROM matches WHERE id IN ($1, $2)")
        .bind(doomed_a)
        .bind(doomed_b)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(doomed_gone, 0, "duplicate matches must be hard-deleted");

    let stickers_left: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM matches WHERE event_id = $1 AND group_name = 'Stickers'",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        stickers_left, 1,
        "a different-group match for the same pair must not be deduped"
    );
    let sticker_alive: i64 = sqlx::query_scalar("SELECT count(*) FROM matches WHERE id = $1")
        .bind(sticker_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        sticker_alive, 1,
        "the different-group match row must be retained"
    );

    // messages on the doomed match were cleared (no ON DELETE clause).
    let msgs_on_doomed: i64 =
        sqlx::query_scalar("SELECT count(*) FROM messages WHERE match_id = $1")
            .bind(doomed_a)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        msgs_on_doomed, 0,
        "messages on a doomed match must be cleared before deletion"
    );

    // match_items cascaded with the doomed match.
    let items_on_doomed: i64 =
        sqlx::query_scalar("SELECT count(*) FROM match_items WHERE match_id = $1")
            .bind(doomed_a)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        items_on_doomed, 0,
        "match_items on a doomed match must cascade-delete"
    );

    // The unique index now blocks a new duplicate in 'Cards' (symmetric ordering).
    let dup = sqlx::query(
        "INSERT INTO matches (user1_id, user2_id, event_id, group_name) VALUES ($1, $2, $3, 'Cards')",
    )
    .bind(u2)
    .bind(u1)
    .bind(event_id)
    .execute(&pool)
    .await;
    assert!(
        dup.is_err(),
        "the unique index must reject a new symmetric duplicate (pair, group) match"
    );

    // A new match in a fresh group for the same pair is still allowed.
    sqlx::query("INSERT INTO matches (user1_id, user2_id, event_id, group_name) VALUES ($1, $2, $3, 'Posters')")
        .bind(u1)
        .bind(u2)
        .bind(event_id)
        .execute(&pool)
        .await
        .expect("a new group for the same pair must be allowed");

    // 5. Idempotency: re-running the migration SQL on the now-clean DB is a
    //    no-op (the staging checksum-sync path). State must be unchanged.
    let target = full
        .migrations
        .iter()
        .find(|m| m.version == TARGET_VERSION)
        .expect("target migration present");
    sqlx::raw_sql(target.sql.as_ref())
        .execute(&pool)
        .await
        .expect("re-running the migration is idempotent");
    let cards_again: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM matches WHERE event_id = $1 AND group_name = 'Cards'",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        cards_again, 1,
        "idempotent re-run must not change the dedup state"
    );
}
