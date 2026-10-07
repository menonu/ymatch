-- Per-user completion: each participant moves an ACCEPTED match to Done
-- themselves. The first completion still flips matches.status to
-- COMPLETED (freezing the match against cancel / rematch); these columns
-- record which participant(s) have completed on their own side.
ALTER TABLE matches ADD COLUMN IF NOT EXISTS user1_completed_at TIMESTAMPTZ;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS user2_completed_at TIMESTAMPTZ;

-- Existing COMPLETED matches were completed for both users under the old
-- shared semantics. No completion timestamp was recorded, so use each
-- user's inventory-apply time when present, else NOW().
UPDATE matches
   SET user1_completed_at = COALESCE(user1_inventory_applied_at, NOW()),
       user2_completed_at = COALESCE(user2_inventory_applied_at, NOW())
 WHERE status = 'COMPLETED';
