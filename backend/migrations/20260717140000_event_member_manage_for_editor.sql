-- #442: grant event.member.manage to event/editor so editors can list/assign/
-- revoke other editors on the public members API (creator retains the grant).
-- Creator transfer stays creator-only via ownership check on
-- PUT /events/:id/creator (not this permission).
--
-- Idempotent: ON CONFLICT DO NOTHING.

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('event', 'editor', 'event', 'event.member.manage')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r       ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
