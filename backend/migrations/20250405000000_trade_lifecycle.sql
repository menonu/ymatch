-- Trade lifecycle: OFFERED status, match_items table, offered_by tracking

-- 1. Drop and re-add status constraint to include OFFERED
ALTER TABLE matches DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE matches ADD CONSTRAINT matches_status_check
  CHECK (status IN ('PENDING', 'OFFERED', 'ACCEPTED', 'COMPLETED', 'REJECTED'));

-- 2. Track who made the offer
ALTER TABLE matches ADD COLUMN IF NOT EXISTS offered_by INTEGER REFERENCES users(id);

-- 3. Items selected for a trade
CREATE TABLE IF NOT EXISTS match_items (
    id SERIAL PRIMARY KEY,
    match_id INTEGER NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    merch_id INTEGER NOT NULL REFERENCES merchandise(id),
    owner_id INTEGER NOT NULL REFERENCES users(id),
    direction TEXT NOT NULL CHECK (direction IN ('GIVE', 'RECEIVE')),
    quantity INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_match_items_match_id ON match_items(match_id);
CREATE INDEX IF NOT EXISTS idx_match_items_owner_merch ON match_items(owner_id, merch_id);

-- 4. Notification tracking: last time user viewed matches
ALTER TABLE users ADD COLUMN IF NOT EXISTS matches_read_at TIMESTAMPTZ;
