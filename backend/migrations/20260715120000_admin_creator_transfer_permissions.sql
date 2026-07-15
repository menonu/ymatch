-- #432: admin transfer of event/group creators + admin-path event member
-- management for global moderators (without changing the creator-only
-- `event.member.manage` path on `/events/:id/members`).
--
-- New global permissions (granted to moderator + admin):
--   * `event.creator.transfer`     — reassign events.creator_id + event/creator role
--   * `group.creator.transfer`     — reassign merchandise_groups.created_by
--   * `event.member.manage.any`    — list/assign/revoke event editors via admin
--                                    endpoints. Deliberately NOT wired into
--                                    Permission::EventMemberManage::satisfying_names
--                                    so the public members API stays creator-only
--                                    (+ admin superuser bypass).
--
-- Idempotent: every INSERT uses ON CONFLICT DO NOTHING.

INSERT INTO permissions (scope_type, name, description) VALUES
    ('global', 'event.creator.transfer',
     'Transfer event ownership (events.creator_id + event/creator role). Admin staff path.'),
    ('global', 'group.creator.transfer',
     'Transfer item-group ownership (merchandise_groups.created_by). Admin staff path.'),
    ('global', 'event.member.manage.any',
     'List/assign/revoke event editors via admin endpoints (not the creator-only members API).')
ON CONFLICT (scope_type, name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('global', 'moderator', 'global', 'event.creator.transfer'),
    ('global', 'admin',     'global', 'event.creator.transfer'),
    ('global', 'moderator', 'global', 'group.creator.transfer'),
    ('global', 'admin',     'global', 'group.creator.transfer'),
    ('global', 'moderator', 'global', 'event.member.manage.any'),
    ('global', 'admin',     'global', 'event.member.manage.any')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r       ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
