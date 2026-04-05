-- Per-user inventory tracking: each user applies their own inventory independently
ALTER TABLE matches ADD COLUMN IF NOT EXISTS user1_inventory_applied_at TIMESTAMPTZ;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS user2_inventory_applied_at TIMESTAMPTZ;
ALTER TABLE matches DROP COLUMN IF EXISTS inventory_applied_at;
