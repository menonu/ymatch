-- Merchandise groups: first-class entity for event groups with description and creator
-- A group is uniquely identified by (event_id, group_name).
-- The group row is created either:
--   (a) explicitly by the NewGroupDialog (sets created_by = dialog opener), or
--   (b) implicitly when the first merch row is POSTed in a previously-unknown group
--       (sets created_by = merch.creator_id).
-- A group's description can be updated only by the group creator or an admin/moderator.

CREATE TABLE IF NOT EXISTS merchandise_groups (
    id SERIAL PRIMARY KEY,
    event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    group_name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (event_id, group_name)
);

CREATE INDEX IF NOT EXISTS idx_merchandise_groups_event_id
    ON merchandise_groups (event_id);

CREATE INDEX IF NOT EXISTS idx_merchandise_groups_created_by
    ON merchandise_groups (created_by);
