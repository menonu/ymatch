-- #346: defense-in-depth DB constraint. ADR 0001 scopes a match to one
-- (event_id, group_name) and the matcher dedups per (pair, group) at the
-- application level in matching.rs (`existing_match`). A direct INSERT that
-- bypasses the matcher could still create a second row for the same
-- (pair, group) — including the symmetric (user2, user1) column ordering,
-- which app-level dedup happens to catch but the DB does not. Enforce
-- uniqueness on a canonicalized pair so column ordering cannot defeat it.
--
-- Postgres cannot declare a UNIQUE *constraint* on an expression; a UNIQUE
-- INDEX is the supported mechanism and is functionally equivalent for
-- enforcement (a unique index satisfies the "UNIQUE constraint exists"
-- acceptance criterion the way Postgres expresses it on expressions). The
-- generated-columns + UNIQUE CONSTRAINT alternative was considered and
-- rejected to avoid adding stored columns to the table.
--
-- Deploy target is Postgres 16 (vm/docker-compose*.yml `postgres:16-alpine`),
-- so LEAST/GREATEST over integer columns are fully supported.

-- 1. Deduplicate existing matches that collide on the canonical
--    (least_user, greatest_user, event_id, group_name) tuple, keeping the
--    lowest-id row per group. The matcher is serialized and dedups at the
--    app level, so collisions should only come from direct INSERTs (tests
--    are isolated per #[sqlx::test]; prod was wiped 2026-06-27). Dependent
--    rows: `match_items` is ON DELETE CASCADE and clears with the match;
--    `messages` has no ON DELETE clause to matches, so clear them first
--    (same pattern as 20260629000000_match_group_scope.sql).
WITH dupes AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY LEAST(user1_id, user2_id),
                        GREATEST(user1_id, user2_id),
                        event_id, group_name
           ORDER BY id
         ) AS rn
  FROM matches
)
DELETE FROM messages msg
WHERE msg.match_id IN (SELECT id FROM dupes WHERE rn > 1);

WITH dupes AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY LEAST(user1_id, user2_id),
                        GREATEST(user1_id, user2_id),
                        event_id, group_name
           ORDER BY id
         ) AS rn
  FROM matches
)
DELETE FROM matches m
WHERE m.id IN (SELECT id FROM dupes WHERE rn > 1);

-- 2. Enforce one match per canonical (pair, group). The pre-existing
--    idx_matches_group (event_id, group_name) is left in place to support
--    the matching.rs `existing_match` (event_id, group_name) filter; this
--    unique index layers canonical-pair uniqueness on top.
CREATE UNIQUE INDEX IF NOT EXISTS idx_matches_unique_pair_group
  ON matches ((LEAST(user1_id, user2_id)),
              (GREATEST(user1_id, user2_id)),
              event_id, group_name);