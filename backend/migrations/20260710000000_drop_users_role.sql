-- ADR 0006 / #371: drop the `users.role` denormalized mirror.
--
-- `user_roles` (scope_type='global', scope_id=NULL) has been the authoritative
-- global role since ADR 0004; #370 removed the last authorization path that read
-- `users.role`, and `User.role` is now derived from `user_roles` at read time
-- (USER_COLUMNS in backend/src/repositories/user.rs). The column is no longer
-- read by any code path, so it is dropped.
--
-- No backfill is needed: the RBAC migration (20260705000000) already backfilled
-- every pre-existing `users.role` value into a `user_roles` global row. No
-- views, indexes, or foreign keys reference `users.role` (it is a plain TEXT
-- column). Idempotent via IF EXISTS (re-running, e.g. the staging checksum-sync
-- path, is a no-op once the column is gone).

ALTER TABLE users DROP COLUMN IF EXISTS role;