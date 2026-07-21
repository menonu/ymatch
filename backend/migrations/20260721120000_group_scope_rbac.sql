-- #443: introduce group-scoped RBAC (`scope_type = 'group'`).
--
-- Mirrors the event-scope creator/editor model (ADR 0004 / #442) for a single
-- merchandise group. `scope_id` is `merchandise_groups.id` (the table already
-- has a serial primary key; natural key `(event_id, group_name)` stays for
-- routes). No schema change to `user_roles` — only catalog rows + backfill.
--
-- Roles:
--   * group/creator — owns the item group; can transfer creator; manages editors
--   * group/editor  — co-manages the group (group.edit + member manage); cannot
--                     transfer creator
--
-- Permissions (group scope):
--   * group.edit           — edit this group's metadata (info panel)
--   * group.member.manage  — list/assign/revoke group editors (not creator)
--
-- Sync rule: `merchandise_groups.created_by` and the group-scoped `creator`
-- user_roles row must stay consistent (same spirit as events.creator_id).
-- Backfill seeds group/creator for every existing row with non-null created_by.
--
-- Idempotent: ON CONFLICT DO NOTHING throughout.

-- 1. Roles -------------------------------------------------------------------
INSERT INTO roles (scope_type, name, description) VALUES
    ('group', 'creator', 'Owner of a specific item group; manages group editors; can transfer creator.'),
    ('group', 'editor',  'Co-manages a specific item group (edit info, manage editors); cannot transfer creator.')
ON CONFLICT (scope_type, name) DO NOTHING;

-- 2. Permissions -------------------------------------------------------------
INSERT INTO permissions (scope_type, name, description) VALUES
    ('group', 'group.edit',          'Edit this item group''s metadata. Distinct from event-scoped group.edit (event creator/editor).'),
    ('group', 'group.member.manage', 'List/assign/revoke group editors for this item group. Does not transfer creator.')
ON CONFLICT (scope_type, name) DO NOTHING;

-- 3. Role -> permission grants -----------------------------------------------
-- Both creator and editor get group.edit + group.member.manage.
-- Creator transfer is ownership-based (created_by), not a permission grant.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('group', 'creator', 'group', 'group.edit'),
    ('group', 'creator', 'group', 'group.member.manage'),
    ('group', 'editor',  'group', 'group.edit'),
    ('group', 'editor',  'group', 'group.member.manage')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r       ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 4. Backfill group/creator from merchandise_groups.created_by ---------------
INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
SELECT mg.created_by, r.id, 'group', mg.id
FROM merchandise_groups mg
JOIN roles r ON r.scope_type = 'group' AND r.name = 'creator'
WHERE mg.created_by IS NOT NULL
ON CONFLICT (user_id, role_id, scope_id) DO NOTHING;
