// Migration-level test for the hardening of migration 20260627000000 (issue #327).
//
// The original migration created the partial unique index on
// (event_id, group_name, name) WHERE is_deleted = false with NO dedup step, so
// it failed with 23505 on prod data that had already accumulated duplicate live
// name pairs, crashing the backend at startup. This reproduces the pre-fix prod
// state (duplicate live merch rows + inventory + match_items referencing both
// the survivor and the duplicate) and asserts the hardened migration collapses
// the duplicates before adding the index.
//
// `migrations = false` gives a fresh empty DB so we can stage the schema up to
// (but excluding) the target migration, seed the dirty state, then apply it.

use sqlx::PgPool;
use std::borrow::Cow;

/// The version of the migration under test (20260627000000).
const TARGET_VERSION: i64 = 20260627000000;

#[sqlx::test(migrations = false)]
async fn migration_dedups_duplicate_live_merch_names_before_unique_index(pool: PgPool) {
    // 1. Apply every migration EXCEPT the target, so the unique index is absent
    //    and we can seed duplicate live merch rows (the app rejects them, so we
    //    insert directly via SQL).
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

    // 2. Seed: two users, an event, and two LIVE merch rows colliding on
    //    (event_id, group_name='G', name='a'). Lowest id is the survivor.
    sqlx::query("INSERT INTO users (username, password_hash) VALUES ('dedup-user', 'x')")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO users (username, password_hash) VALUES ('dedup-peer', 'x')")
        .execute(&pool)
        .await
        .unwrap();
    let user_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'dedup-user'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let peer_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'dedup-peer'")
        .fetch_one(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO events (name, creator_id) VALUES ('Dedup Event', $1)")
        .bind(user_id)
        .execute(&pool)
        .await
        .unwrap();
    let event_id: i32 = sqlx::query_scalar("SELECT id FROM events WHERE name = 'Dedup Event'")
        .fetch_one(&pool)
        .await
        .unwrap();

    sqlx::query("INSERT INTO merchandise (event_id, name, group_name) VALUES ($1, 'a', 'G')")
        .bind(event_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO merchandise (event_id, name, group_name) VALUES ($1, 'a', 'G')")
        .bind(event_id)
        .execute(&pool)
        .await
        .unwrap();
    let merch_ids: Vec<i32> = sqlx::query_scalar(
        "SELECT id FROM merchandise \
         WHERE event_id = $1 AND name = 'a' AND group_name = 'G' \
         ORDER BY id",
    )
    .bind(event_id)
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(merch_ids.len(), 2, "expected 2 duplicate live rows seeded");
    let survivor = merch_ids[0];
    let dup = merch_ids[1];

    // Inventory: survivor and dup both HAVE (must sum after dedup); the dup
    // also has WANT (must repoint onto survivor).
    sqlx::query(
        "INSERT INTO inventory (user_id, merch_id, status, quantity) \
         VALUES ($1, $2, 'HAVE', 3)",
    )
    .bind(user_id)
    .bind(survivor)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO inventory (user_id, merch_id, status, quantity) \
         VALUES ($1, $2, 'HAVE', 5)",
    )
    .bind(user_id)
    .bind(dup)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO inventory (user_id, merch_id, status, quantity) \
         VALUES ($1, $2, 'WANT', 2)",
    )
    .bind(user_id)
    .bind(dup)
    .execute(&pool)
    .await
    .unwrap();

    // match_items: a pending match referencing both survivor and dup by the same
    // giver (collides after repoint -> must sum), plus a non-colliding leg on
    // the dup by the peer (plain repoint).
    sqlx::query("INSERT INTO matches (user1_id, user2_id) VALUES ($1, $2)")
        .bind(user_id)
        .bind(peer_id)
        .execute(&pool)
        .await
        .unwrap();
    let match_id: i32 = sqlx::query_scalar("SELECT max(id) FROM matches")
        .fetch_one(&pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO match_items (match_id, giver_user_id, merch_id, quantity) \
         VALUES ($1, $2, $3, 4)",
    )
    .bind(match_id)
    .bind(user_id)
    .bind(survivor)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO match_items (match_id, giver_user_id, merch_id, quantity) \
         VALUES ($1, $2, $3, 6)",
    )
    .bind(match_id)
    .bind(user_id)
    .bind(dup)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO match_items (match_id, giver_user_id, merch_id, quantity) \
         VALUES ($1, $2, $3, 1)",
    )
    .bind(match_id)
    .bind(peer_id)
    .bind(dup)
    .execute(&pool)
    .await
    .unwrap();

    // Two LIVE merch rows with group_name = NULL and the same name 'b'. NULLs
    // are distinct under the partial unique index, so these must NOT be deduped.
    for _ in 0..2 {
        sqlx::query("INSERT INTO merchandise (event_id, name, group_name) VALUES ($1, 'b', NULL)")
            .bind(event_id)
            .execute(&pool)
            .await
            .unwrap();
    }

    // Three LIVE merch rows colliding on (event_id, group_name='H', name='c')
    // (S2 + D2a + D2b). This exercises two cases the 'a'/'G' group does not:
    //   - >2 dups in one group, and
    //   - a dup-only collision (no inventory on the survivor itself): both dups
    //     carry HAVE for the same user, the survivor carries none, so the sum
    //     must land on a repointed row -> survivor HAVE = 20 + 30 = 50.
    for _ in 0..3 {
        sqlx::query("INSERT INTO merchandise (event_id, name, group_name) VALUES ($1, 'c', 'H')")
            .bind(event_id)
            .execute(&pool)
            .await
            .unwrap();
    }
    let group_h_ids: Vec<i32> = sqlx::query_scalar(
        "SELECT id FROM merchandise \
         WHERE event_id = $1 AND name = 'c' AND group_name = 'H' \
         ORDER BY id",
    )
    .bind(event_id)
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(
        group_h_ids.len(),
        3,
        "expected 3 duplicate live rows seeded in H"
    );
    let survivor_h = group_h_ids[0];
    let dup_h_a = group_h_ids[1];
    let dup_h_b = group_h_ids[2];
    sqlx::query(
        "INSERT INTO inventory (user_id, merch_id, status, quantity) \
         VALUES ($1, $2, 'HAVE', 20)",
    )
    .bind(user_id)
    .bind(dup_h_a)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO inventory (user_id, merch_id, status, quantity) \
         VALUES ($1, $2, 'HAVE', 30)",
    )
    .bind(user_id)
    .bind(dup_h_b)
    .execute(&pool)
    .await
    .unwrap();

    // 3. Apply the target migration (the one under test).
    full.run(&pool).await.expect("target migration applies");

    // 4. Assert the dedup state.
    let live_a: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM merchandise \
         WHERE event_id = $1 AND name = 'a' AND group_name = 'G' AND is_deleted = false",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        live_a, 1,
        "duplicate live 'a' rows must collapse to one survivor"
    );

    let live_b: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM merchandise \
         WHERE event_id = $1 AND name = 'b' AND group_name IS NULL AND is_deleted = false",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(live_b, 2, "NULL group_name rows must not be deduped");

    let dup_count: i64 = sqlx::query_scalar("SELECT count(*) FROM merchandise WHERE id = $1")
        .bind(dup)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(dup_count, 0, "duplicate merch row must be hard-deleted");

    // Inventory: survivor holds HAVE = 3 + 5 = 8 and WANT = 2; nothing on dup.
    let have_qty: i32 = sqlx::query_scalar(
        "SELECT quantity FROM inventory \
         WHERE user_id = $1 AND merch_id = $2 AND status = 'HAVE'",
    )
    .bind(user_id)
    .bind(survivor)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(have_qty, 8, "HAVE inventory must sum onto the survivor");

    let want_qty: i32 = sqlx::query_scalar(
        "SELECT quantity FROM inventory \
         WHERE user_id = $1 AND merch_id = $2 AND status = 'WANT'",
    )
    .bind(user_id)
    .bind(survivor)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(want_qty, 2, "WANT inventory must repoint onto the survivor");

    let inv_on_dup: i64 = sqlx::query_scalar("SELECT count(*) FROM inventory WHERE merch_id = $1")
        .bind(dup)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        inv_on_dup, 0,
        "no inventory may reference the hard-deleted duplicate"
    );

    // match_items: the two user legs summed (4 + 6 = 10); the peer leg repointed;
    // nothing on dup.
    let user_leg_qty: i32 = sqlx::query_scalar(
        "SELECT quantity FROM match_items \
         WHERE match_id = $1 AND giver_user_id = $2 AND merch_id = $3",
    )
    .bind(match_id)
    .bind(user_id)
    .bind(survivor)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        user_leg_qty, 10,
        "colliding match_items legs must sum onto the survivor"
    );

    let peer_leg_qty: i32 = sqlx::query_scalar(
        "SELECT quantity FROM match_items \
         WHERE match_id = $1 AND giver_user_id = $2 AND merch_id = $3",
    )
    .bind(match_id)
    .bind(peer_id)
    .bind(survivor)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        peer_leg_qty, 1,
        "non-colliding match_items leg must repoint onto the survivor"
    );

    let mi_on_dup: i64 = sqlx::query_scalar("SELECT count(*) FROM match_items WHERE merch_id = $1")
        .bind(dup)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        mi_on_dup, 0,
        "no match_items may reference the hard-deleted duplicate"
    );

    // Group H: >2 dups collapsed to one survivor; the dup-only collision (no
    // inventory on the survivor) summed onto the survivor; both dups hard-deleted.
    let live_c: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM merchandise \
         WHERE event_id = $1 AND name = 'c' AND group_name = 'H' AND is_deleted = false",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        live_c, 1,
        "three duplicate live 'c' rows must collapse to one survivor"
    );
    let have_h_qty: i32 = sqlx::query_scalar(
        "SELECT quantity FROM inventory \
         WHERE user_id = $1 AND merch_id = $2 AND status = 'HAVE'",
    )
    .bind(user_id)
    .bind(survivor_h)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        have_h_qty, 50,
        "dup-only HAVE inventory must sum (20 + 30) onto the survivor with no own inventory"
    );
    let h_dups_gone: i64 =
        sqlx::query_scalar("SELECT count(*) FROM merchandise WHERE id IN ($1, $2)")
            .bind(dup_h_a)
            .bind(dup_h_b)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        h_dups_gone, 0,
        "both group-H duplicate rows must be hard-deleted"
    );
    let inv_on_h_dups: i64 =
        sqlx::query_scalar("SELECT count(*) FROM inventory WHERE merch_id IN ($1, $2)")
            .bind(dup_h_a)
            .bind(dup_h_b)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        inv_on_h_dups, 0,
        "no inventory may reference the hard-deleted group-H duplicates"
    );

    // The partial unique index now blocks a new live duplicate in group 'G'.
    let insert_dup =
        sqlx::query("INSERT INTO merchandise (event_id, name, group_name) VALUES ($1, 'a', 'G')")
            .bind(event_id)
            .execute(&pool)
            .await;
    assert!(
        insert_dup.is_err(),
        "the unique index must reject a new live duplicate name in the same group"
    );

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
    let live_a_again: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM merchandise \
         WHERE event_id = $1 AND name = 'a' AND group_name = 'G' AND is_deleted = false",
    )
    .bind(event_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        live_a_again, 1,
        "idempotent re-run must not change the dedup state"
    );
}
