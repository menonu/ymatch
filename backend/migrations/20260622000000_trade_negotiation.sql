-- #297: trade negotiation state machine.
-- Convert match_items from offerer-relative legs (owner_id + direction) to
-- absolute legs (giver_user_id). A leg now reads "user G gives merch M qty Q"
-- with no direction relative to an offerer. This supports accumulating
-- counter-offers: each (match_id, giver_user_id, merch_id) is unique, so a
-- proposal is upserted per leg and unspecified legs persist across turns.

-- 1. Add the absolute giver column and backfill from the old columns.
ALTER TABLE match_items ADD COLUMN IF NOT EXISTS giver_user_id INTEGER;
UPDATE match_items mi
SET giver_user_id = CASE
  WHEN mi.direction = 'GIVE' THEN mi.owner_id
  ELSE (CASE WHEN m.user1_id = mi.owner_id THEN m.user2_id ELSE m.user1_id END)
END
FROM matches m
WHERE m.id = mi.match_id
  AND mi.giver_user_id IS NULL;

ALTER TABLE match_items ALTER COLUMN giver_user_id SET NOT NULL;
ALTER TABLE match_items
  ADD CONSTRAINT match_items_giver_fk FOREIGN KEY (giver_user_id)
  REFERENCES users(id);

-- 2. Drop the offerer-relative columns (and the direction CHECK on the column).
ALTER TABLE match_items DROP COLUMN IF EXISTS owner_id;
ALTER TABLE match_items DROP COLUMN IF EXISTS direction;

-- 3. One row per (match, giver, merch) so partial upserts accumulate.
ALTER TABLE match_items
  DROP CONSTRAINT IF EXISTS match_items_leg_unique;
ALTER TABLE match_items
  ADD CONSTRAINT match_items_leg_unique UNIQUE (match_id, giver_user_id, merch_id);

-- 4. Index for the giver-merch lookup used by matching/apply paths.
DROP INDEX IF EXISTS idx_match_items_owner_merch;
CREATE INDEX IF NOT EXISTS idx_match_items_giver_merch
  ON match_items(giver_user_id, merch_id);