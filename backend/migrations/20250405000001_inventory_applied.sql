-- Track whether inventory was already applied for a completed trade
ALTER TABLE matches ADD COLUMN IF NOT EXISTS inventory_applied_at TIMESTAMPTZ;
