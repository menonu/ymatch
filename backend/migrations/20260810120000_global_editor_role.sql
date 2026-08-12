-- #551: global `editor` role — content management without user/match moderation.
--
-- Hierarchy: user < editor < moderator < admin.
--
-- Granted to global/editor:
--   event.create, event.edit.any, event.delete.any,
--   merch.create.any, merch.edit.any, merch.delete.any,
--   group.edit.any, group.delete
--
-- Not granted (moderator/admin only, or admin only):
--   user.read, user.ban, user.unban, user.role.manage,
--   match.delete, event.creator.transfer, group.creator.transfer,
--   event.member.manage.any, system.kill_switch
--
-- Idempotent: every INSERT uses ON CONFLICT DO NOTHING.

INSERT INTO roles (scope_type, name, description) VALUES
    ('global', 'editor',
     'Create & manage events; edit or remove any event, merch, or group. No ban/unban, match delete, or role manage.')
ON CONFLICT (scope_type, name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('global', 'editor', 'global', 'event.create'),
    ('global', 'editor', 'global', 'event.edit.any'),
    ('global', 'editor', 'global', 'event.delete.any'),
    ('global', 'editor', 'global', 'merch.create.any'),
    ('global', 'editor', 'global', 'merch.edit.any'),
    ('global', 'editor', 'global', 'merch.delete.any'),
    ('global', 'editor', 'global', 'group.edit.any'),
    ('global', 'editor', 'global', 'group.delete')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r       ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
