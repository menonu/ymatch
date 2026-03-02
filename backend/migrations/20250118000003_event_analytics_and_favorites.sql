-- Add columns to events for analytics caching
ALTER TABLE events ADD COLUMN unique_views INTEGER DEFAULT 0;

-- (Optional) We could dynamically calculate active_participants, but caching it is faster for large lists.
-- However, for now we will calculate it in the query to avoid complex triggers.
-- Same for unique_views, we could just have an event_views table, but a simple counter is enough for now.

-- Favorites Table (Junction: User <-> Event)
CREATE TABLE IF NOT EXISTS event_favorites (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, event_id)
);
