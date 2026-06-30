-- ADR 0001 / #341: scope matches to a single item group.
--
-- A match now belongs to exactly one (event_id, group_name). New matches are
-- created per (user1, user2, group) instead of per user pair, and NULL-grouped
-- merchandise is no longer matchable. See docs/explanation/adr/0001-*.md.
--
-- Group reference mirrors `merchandise`'s soft-reference style (event_id +
-- group_name TEXT, not a merchandise_groups FK) for consistency with the rest
-- of the codebase, which keys merchandise by group_name.

ALTER TABLE matches ADD COLUMN IF NOT EXISTS event_id INTEGER REFERENCES events(id) ON DELETE CASCADE;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS group_name TEXT;

-- Backfill the group for matches whose `match_items` legs all agree on exactly
-- one non-null (event_id, group_name). Under the pre-ADR matcher, legs were
-- produced within a single group, so most leg-bearing matches backfill cleanly.
-- (Plain aggregates, not window functions — Postgres does not support
-- DISTINCT inside window aggregates.)
CREATE TEMP TABLE _match_group_stats AS
SELECT mi.match_id,
       COUNT(DISTINCT (m.event_id, m.group_name)) AS distinct_groups,
       COUNT(*) FILTER (WHERE m.group_name IS NULL) AS null_legs
FROM match_items mi
JOIN merchandise m ON m.id = mi.merch_id
GROUP BY mi.match_id;

CREATE TEMP TABLE _determinable AS
SELECT s.match_id, MIN(m.event_id) AS event_id, MIN(m.group_name) AS group_name
FROM _match_group_stats s
JOIN match_items mi ON mi.match_id = s.match_id
JOIN merchandise m ON m.id = mi.merch_id
WHERE s.distinct_groups = 1 AND s.null_legs = 0 AND m.group_name IS NOT NULL
GROUP BY s.match_id;

UPDATE matches m
SET event_id = d.event_id, group_name = d.group_name
FROM _determinable d
WHERE m.id = d.match_id;

-- Undeterminable matches (no legs, or legs spanning multiple groups, or legs
-- with a NULL group) cannot satisfy the invariant and are deleted (#341
-- decision). prod DB was wiped 2026-06-27 so little live data is affected.
-- `match_items` is ON DELETE CASCADE and clears with the match; `messages`
-- has no ON DELETE clause to matches, so clear them first.
DELETE FROM messages msg
WHERE NOT EXISTS (SELECT 1 FROM _determinable d WHERE d.match_id = msg.match_id);
DELETE FROM matches m
WHERE NOT EXISTS (SELECT 1 FROM _determinable d WHERE d.match_id = m.id);
DROP TABLE _determinable;
DROP TABLE _match_group_stats;

ALTER TABLE matches ALTER COLUMN event_id SET NOT NULL;
ALTER TABLE matches ALTER COLUMN group_name SET NOT NULL;

-- Supports the per-(pair, group) "already matched" dedup in matching.rs.
CREATE INDEX IF NOT EXISTS idx_matches_group ON matches (event_id, group_name);