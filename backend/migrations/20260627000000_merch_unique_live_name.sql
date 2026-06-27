-- Enforce per-group uniqueness of merchandise.name among live rows.
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

CREATE UNIQUE INDEX IF NOT EXISTS uq_merchandise_live_name_per_group
    ON merchandise (event_id, group_name, name)
    WHERE is_deleted = false;
