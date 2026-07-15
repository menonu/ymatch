-- #425: cosmetic display name for merchandise groups.
-- `group_name` is the immutable internal key referenced (as plain TEXT, no FK)
-- by merchandise / matches / group_favorites, so it must not be mutated to
-- "rename" a group. `display_name` is an editable label shown in the UI
-- instead; NULL means fall back to `group_name`. Not uniqueness-constrained.
ALTER TABLE merchandise_groups
    ADD COLUMN IF NOT EXISTS display_name TEXT;