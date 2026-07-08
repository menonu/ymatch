-- ADR 0005 / issue #365: gate merch creation behind a new RBAC permission.
--
-- `create_merch` previously had NO authorization: any active user could add
-- merchandise to any event. Product decision: merch creation is a curated
-- action by the event owner/editors (plus moderator/admin), not open
-- participation. This migration adds the two permission rows and the
-- role->permission grants that express that; the handler check follows in
-- code. See docs/explanation/adr/0005-merch-create-permission.md.
--
-- This SUPPLEMENTS ADR 0004 (does not supersede it): ADR 0004's matrix had no
-- `merch.create` permission; ADR 0005 extends the model with one.
--
-- Two new permissions:
--   * `event/merch.create`       -- event scope; granted to event creator + editor.
--   * `global/merch.create.any`  -- global override (like `event.edit.any`);
--                                   granted to moderator + admin. The admin
--                                   superuser bypass makes admin omnipermissive
--                                   regardless, but the row documents intent,
--                                   matching how 0004 seeds admin's other
--                                   `*.any` rows.
--
-- Idempotent: every INSERT uses ON CONFLICT DO NOTHING, so re-running (e.g. the
-- staging checksum-sync path) is a no-op. No data backfill: existing merch rows
-- are untouched; only future creation is gated.

-- 1. New permission rows -----------------------------------------------------
INSERT INTO permissions (scope_type, name, description) VALUES
    ('event',  'merch.create',      'Create merch in this event.'),
    ('global', 'merch.create.any', 'Create merch in any event (global override of merch.create).')
ON CONFLICT (scope_type, name) DO NOTHING;

-- 2. Role -> permission grants ----------------------------------------------
--    event/creator + event/editor -> event/merch.create
--    global/moderator + global/admin -> global/merch.create.any
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('event',  'creator',   'event',  'merch.create'),
    ('event',  'editor',    'event',  'merch.create'),
    ('global', 'moderator', 'global', 'merch.create.any'),
    ('global', 'admin',     'global', 'merch.create.any')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r        ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p  ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;