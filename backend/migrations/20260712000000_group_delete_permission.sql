-- #380: group removal is a global moderation action because it removes all
-- merchandise visibility and group-scoped matches for an event/group pair.
INSERT INTO permissions (scope_type, name, description) VALUES
    ('global', 'group.delete', 'Remove a group and its live references from any event.')
ON CONFLICT (scope_type, name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('global', 'moderator', 'global', 'group.delete'),
    ('global', 'admin',     'global', 'group.delete')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
