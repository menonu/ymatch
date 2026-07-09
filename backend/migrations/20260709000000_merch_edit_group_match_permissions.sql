-- #370: unify authz on RBAC. Adds the permissions that let the remaining
-- `PermissionPolicy::require_role` / `require_owner_or_role` call sites
-- (`update_merch`, `publish_merch`, group update, `delete_match`) move to
-- `RbacService::check`, retiring the old role-list policy.
--
-- This SUPPLEMENTS ADR 0004 / ADR 0005 (does not supersede them): their
-- matrices had no `merch.edit`, `group.edit`, or `match.delete` permission;
-- this migration extends the model with them.
--
-- New permissions:
--   * `event/merch.edit`      -- event scope; granted to event creator + editor.
--                                 The merch *creator* passes via an ownership
--                                 short-circuit in the handler, not this row.
--   * `global/merch.edit.any` -- global override (like `merch.delete.any`);
--                                 granted to moderator + admin.
--   * `event/group.edit`      -- event scope; granted to event creator + editor.
--                                 The group *creator* passes via an ownership
--                                 short-circuit in the handler, not this row.
--   * `global/group.edit.any` -- global override; granted to moderator + admin.
--   * `global/match.delete`  -- global moderation action; granted to
--                                 moderator + admin. No `*.any` form: it is
--                                 itself the global-scope permission.
--
-- Idempotent: every INSERT uses ON CONFLICT DO NOTHING, so re-running (e.g. the
-- staging checksum-sync path) is a no-op. No data backfill.

-- 1. New permission rows -----------------------------------------------------
INSERT INTO permissions (scope_type, name, description) VALUES
    ('event',  'merch.edit',     'Edit merch in this event (update, publish). The merch creator passes via an ownership short-circuit, not this permission.'),
    ('global', 'merch.edit.any', 'Edit merch in any event (global override of merch.edit).'),
    ('event',  'group.edit',     'Edit a group in this event. The group creator passes via an ownership short-circuit, not this permission.'),
    ('global', 'group.edit.any', 'Edit any group in any event (global override of group.edit).'),
    ('global', 'match.delete',   'Delete a match (global moderation action).')
ON CONFLICT (scope_type, name) DO NOTHING;

-- 2. Role -> permission grants ----------------------------------------------
--    event/creator + event/editor -> event/merch.edit, event/group.edit
--    global/moderator + global/admin -> global/merch.edit.any, global/group.edit.any,
--                                        global/match.delete
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('event',  'creator',   'event',  'merch.edit'),
    ('event',  'editor',    'event',  'merch.edit'),
    ('event',  'creator',   'event',  'group.edit'),
    ('event',  'editor',    'event',  'group.edit'),
    ('global', 'moderator', 'global', 'merch.edit.any'),
    ('global', 'admin',     'global', 'merch.edit.any'),
    ('global', 'moderator', 'global', 'group.edit.any'),
    ('global', 'admin',     'global', 'group.edit.any'),
    ('global', 'moderator', 'global', 'match.delete'),
    ('global', 'admin',     'global', 'match.delete')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r        ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p  ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;