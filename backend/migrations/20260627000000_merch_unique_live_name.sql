-- Enforce per-group uniqueness of merchandise.name among live rows, with a
-- dedup step that collapses any pre-existing duplicate live rows BEFORE the
-- unique index is created (issue #327).
--
-- Issue #299: two merch rows with an identical name could be created in the
-- same (event_id, group_name), e.g. "a" and "a", producing indistinguishable
-- items in the HAVE/WANT inventory and match lists. Mirroring the
-- merchandise_groups model (UNIQUE (event_id, group_name)), the per-item name
-- only needs to be distinct within its group.
--
-- The index is a PARTIAL unique index scoped to non-deleted rows, so:
--   - soft-deleted rows (is_deleted = true) free their name and can be
--     re-created, and
--   - drafts count toward uniqueness too (the predicate keys on is_deleted,
--     not status), so two drafts named "a" in one group are also rejected.
-- The same name IS allowed in a different group of the same event.
--
-- Issue #327: the original migration created the unique index directly, which
-- failed (23505) on prod data that had accumulated 2 duplicate live
-- (event_id, group_name, name) pairs, crashing the backend at startup
-- (sqlx::migrate!() panicked -> Caddy 502). This hardens the migration by first
-- collapsing duplicates (merge + hard-delete), mirroring the
-- dedup-before-constraint pattern from migration 20260622000000.
--
-- Dedup strategy (merge + hard-delete): for each set of live merch rows sharing
-- (event_id, group_name, name), the lowest-id row is the survivor. Inventory
-- and match_items rows on the duplicates are repointed onto the survivor,
-- summing quantities on (user_id, status) / (match_id, giver_user_id) conflicts
-- (respecting the inventory (user_id, merch_id, status) and match_items
-- (match_id, giver_user_id, merch_id) unique constraints), and the now-
-- unreferenced duplicate merch rows are hard-deleted. group_name NULL rows never
-- collide under the partial unique index (NULLs are distinct), so they are
-- left untouched.
--
-- Idempotent: on a DB with no duplicates every step below is a no-op, and
-- CREATE UNIQUE INDEX IF NOT EXISTS is a no-op when the index already exists,
-- so re-running (e.g. the staging checksum-sync path) is safe.

-- 1. Build the dup -> survivor map. Only non-null group_name can collide under
--    the partial unique index; the lowest id per live (event_id, group_name,
--    name) group is the survivor, every other row in the group is a dup.
CREATE TEMP TABLE merch_dedup_map ON COMMIT DROP AS
WITH live_dups AS (
    SELECT id,
           event_id, group_name, name,
           MIN(id) OVER w AS survivor_id
    FROM merchandise
    WHERE is_deleted = false AND group_name IS NOT NULL
    WINDOW w AS (PARTITION BY event_id, group_name, name)
)
SELECT id AS dup_id, survivor_id
FROM live_dups
WHERE id <> survivor_id;

-- merch_redirect maps every merch id to its survivor (self for survivors and
-- non-dups). Used to compute the "effective" merch key after remapping.
CREATE TEMP TABLE merch_redirect ON COMMIT DROP AS
SELECT m.id AS merch_id, COALESCE(d.survivor_id, m.id) AS survivor_id
FROM merchandise m
LEFT JOIN merch_dedup_map d ON d.dup_id = m.id;

-- 2. Repoint inventory onto survivors, merging quantity on (user_id, status)
--    conflicts (inventory unique (user_id, merch_id, status)). Mirror the
--    20260622000000 set / dedup / repoint pattern on the effective key
--    (user_id, survivor_id, status):
--      a. set every colliding row's quantity to the group total, then
--      b. keep one row per effective key (lowest ctid), then
--      c. repoint the surviving dup-referencing rows to the survivor.
UPDATE inventory i
SET quantity = g.qty
FROM (
    SELECT i2.user_id, mr.survivor_id, i2.status, SUM(i2.quantity) AS qty
    FROM inventory i2
    JOIN merch_redirect mr ON mr.merch_id = i2.merch_id
    GROUP BY i2.user_id, mr.survivor_id, i2.status
    HAVING COUNT(*) > 1
) g,
     merch_redirect mr
WHERE mr.merch_id = i.merch_id
  AND i.user_id = g.user_id
  AND i.status = g.status
  AND mr.survivor_id = g.survivor_id;

DELETE FROM inventory i
USING merch_redirect mr,
     inventory i2,
     merch_redirect mr2
WHERE mr.merch_id = i.merch_id
  AND mr2.merch_id = i2.merch_id
  AND i.user_id = i2.user_id
  AND i.status = i2.status
  AND mr.survivor_id = mr2.survivor_id
  AND i2.ctid < i.ctid;

UPDATE inventory i
SET merch_id = mr.survivor_id
FROM merch_redirect mr
WHERE mr.merch_id = i.merch_id
  AND mr.survivor_id <> i.merch_id;

-- 3. Repoint match_items onto survivors, merging quantity on
--    (match_id, giver_user_id) conflicts (match_items unique
--    (match_id, giver_user_id, merch_id)). Same set / dedup / repoint pattern
--    on the effective key (match_id, giver_user_id, survivor_id).
UPDATE match_items mi
SET quantity = g.qty
FROM (
    SELECT mi2.match_id, mi2.giver_user_id, mr.survivor_id, SUM(mi2.quantity) AS qty
    FROM match_items mi2
    JOIN merch_redirect mr ON mr.merch_id = mi2.merch_id
    GROUP BY mi2.match_id, mi2.giver_user_id, mr.survivor_id
    HAVING COUNT(*) > 1
) g,
     merch_redirect mr
WHERE mr.merch_id = mi.merch_id
  AND mi.match_id = g.match_id
  AND mi.giver_user_id = g.giver_user_id
  AND mr.survivor_id = g.survivor_id;

DELETE FROM match_items mi
USING merch_redirect mr,
     match_items mi2,
     merch_redirect mr2
WHERE mr.merch_id = mi.merch_id
  AND mr2.merch_id = mi2.merch_id
  AND mi.match_id = mi2.match_id
  AND mi.giver_user_id = mi2.giver_user_id
  AND mr.survivor_id = mr2.survivor_id
  AND mi2.ctid < mi.ctid;

UPDATE match_items mi
SET merch_id = mr.survivor_id
FROM merch_redirect mr
WHERE mr.merch_id = mi.merch_id
  AND mr.survivor_id <> mi.merch_id;

-- 4. Hard-delete the now-unreferenced duplicate merch rows, then add the index.
DELETE FROM merchandise m
WHERE m.id IN (SELECT dup_id FROM merch_dedup_map);

CREATE UNIQUE INDEX IF NOT EXISTS uq_merchandise_live_name_per_group
    ON merchandise (event_id, group_name, name)
    WHERE is_deleted = false;