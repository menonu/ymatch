-- #376: gate GET /api/v1/admin/users/:id (get_user_details).
-- The endpoint returned the full User proto (including device_token) with no
-- authorization. Model inspection as the global `user.read` permission,
-- granted to moderator + admin (plus the admin superuser bypass).
--
-- Idempotent: every INSERT uses ON CONFLICT DO NOTHING.

INSERT INTO permissions (scope_type, name, description) VALUES
    ('global', 'user.read', 'Read detailed user records (admin inspection; includes sensitive fields).')
ON CONFLICT (scope_type, name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('global', 'moderator', 'global', 'user.read'),
    ('global', 'admin',     'global', 'user.read')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
