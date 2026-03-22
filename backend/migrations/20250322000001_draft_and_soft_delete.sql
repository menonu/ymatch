-- Add draft/publish status to events and merchandise
ALTER TABLE events ADD COLUMN status TEXT NOT NULL DEFAULT 'published';
ALTER TABLE merchandise ADD COLUMN status TEXT NOT NULL DEFAULT 'published';

-- Add soft-delete and trade control to merchandise
ALTER TABLE merchandise ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE merchandise ADD COLUMN trade_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- Track who created each merchandise item
ALTER TABLE merchandise ADD COLUMN creator_id INTEGER REFERENCES users(id);
