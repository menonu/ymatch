-- ADR 0004 / #228: introduce a structured RBAC permission model.
--
-- Replaces the ad-hoc single `users.role` column (which only carried one
-- global role per user) with a four-table model: roles, permissions,
-- role_permissions, and scoped user_roles assignments. This adds event-scoped
-- roles (creator/editor) for the first time and makes permissions data so that
-- grant changes are migration rows, not code releases. See
-- docs/explanation/adr/0004-rbac-permission-model.md.
--
-- Key shapes:
--   * `user_roles` is the source of truth for every role a user holds. The
--     `global` scope (scope_id NULL) holds admin/moderator/user; the `event`
--     scope (scope_id = events.id) holds creator/editor.
--   * `users.role` is KEPT as a denormalized mirror of the global role so the
--     proto `User.role` field and the frontend admin gate keep working. It is
--     written in the same transaction as the `user_roles` global row by the
--     role-mutation code; this migration backfills the existing values.
--   * `scope_id` is a generic nullable INTEGER with NO polymorphic foreign key
--     (Postgres cannot express "FK to events only when scope_type='event'"
--     cleanly). It is validated in application code. This is the trade-off that
--     lets a future scope (team/org) be added as a new scope_type literal with
--     no schema change to user_roles.
--   * `UNIQUE ... NULLS NOT DISTINCT` on (user_id, role_id, scope_id) so that
--     the global scope (scope_id NULL) still enforces one row per
--     (user, role) and ON CONFLICT works for global backfill/re-grants.
--
-- Idempotent: every CREATE uses IF NOT EXISTS and every seed/backfill INSERT
-- uses ON CONFLICT DO NOTHING, so re-running (e.g. the staging checksum-sync
-- path) is a no-op.

-- 1. Roles catalog -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS roles (
    id          SERIAL PRIMARY KEY,
    scope_type  TEXT NOT NULL,
    name        TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(scope_type, name)
);

INSERT INTO roles (scope_type, name, description) VALUES
    ('global', 'admin',      'Full access / all permissions. Superuser bypass.'),
    ('global', 'moderator',  'Platform management: ban/unban, create & manage events.'),
    ('global', 'user',       'Standard trading. No elevated permissions (ownership-checked).'),
    ('event',  'creator',    'Owner of a specific event; manages event editors.'),
    ('event',  'editor',     'Contributor: edits event items and details.')
ON CONFLICT (scope_type, name) DO NOTHING;

-- 2. Permissions catalog -----------------------------------------------------
CREATE TABLE IF NOT EXISTS permissions (
    id          SERIAL PRIMARY KEY,
    scope_type  TEXT NOT NULL,
    name        TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(scope_type, name)
);

INSERT INTO permissions (scope_type, name, description) VALUES
    ('global', 'user.ban',           'Ban a user.'),
    ('global', 'user.unban',         'Lift a ban.'),
    ('global', 'user.role.manage',   'Change a users global role.'),
    ('global', 'event.create',       'Create a new event.'),
    ('global', 'event.edit.any',     'Edit any event (global override of event.edit).'),
    ('global', 'event.delete.any',   'Delete any event (global override of event.delete).'),
    ('global', 'merch.delete.any',   'Delete any merch (global override of merch.delete).'),
    ('global', 'system.kill_switch', 'Toggle service kill-switches.'),
    ('event',  'event.edit',         'Edit this event (rename, publish).'),
    ('event',  'event.delete',       'Delete this event.'),
    ('event',  'event.member.manage','Manage editor roles for this event.'),
    ('event',  'merch.delete',       'Delete merch in this event.')
ON CONFLICT (scope_type, name) DO NOTHING;

-- 3. Role -> permission mapping ---------------------------------------------
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id       INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Admin holds every global permission (the superuser bypass in code makes it
-- omnipermissive regardless, but the rows document the intent and keep the
-- catalog self-describing).
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('global','admin','global','user.ban'),
    ('global','admin','global','user.unban'),
    ('global','admin','global','user.role.manage'),
    ('global','admin','global','event.create'),
    ('global','admin','global','event.edit.any'),
    ('global','admin','global','event.delete.any'),
    ('global','admin','global','merch.delete.any'),
    ('global','admin','global','system.kill_switch'),
    ('global','moderator','global','user.ban'),
    ('global','moderator','global','user.unban'),
    ('global','moderator','global','event.create'),
    ('global','moderator','global','event.edit.any'),
    ('global','moderator','global','event.delete.any'),
    ('global','moderator','global','merch.delete.any'),
    ('event','creator','event','event.edit'),
    ('event','creator','event','event.delete'),
    ('event','creator','event','event.member.manage'),
    ('event','creator','event','merch.delete'),
    ('event','editor','event','event.edit'),
    ('event','editor','event','merch.delete')
) AS v(r_scope, r_name, p_scope, p_name)
JOIN roles r        ON r.scope_type = v.r_scope AND r.name = v.r_name
JOIN permissions p  ON p.scope_type = v.p_scope AND p.name = v.p_name
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- The `user` global role intentionally has NO permission rows: ordinary
-- trading is gated by ownership checks in handlers, not by RBAC rows.

-- 4. Scoped user role assignments ------------------------------------------
CREATE TABLE IF NOT EXISTS user_roles (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id    INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    -- Denormalized from roles.scope_type for fast filtered lookups
    -- (WHERE scope_type='event' AND scope_id=$1) without a join per check.
    -- Written only by the assignment code, which reads it from the role.
    scope_type TEXT NOT NULL,
    -- NULL for the global scope; events.id for the event scope. No FK: see ADR.
    scope_id   INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- NULLS NOT DISTINCT so the global scope (scope_id NULL) still enforces
    -- one row per (user, role) and ON CONFLICT can dedupe global re-grants.
    UNIQUE NULLS NOT DISTINCT (user_id, role_id, scope_id)
);

CREATE INDEX IF NOT EXISTS idx_user_roles_scope ON user_roles (scope_type, scope_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_user  ON user_roles (user_id);

-- 5. Backfill existing data --------------------------------------------------
--    Every user's current users.role becomes a global user_roles assignment;
--    every event's creator_id becomes an event/creator assignment. users.role
--    is left untouched (it is the denormalized mirror going forward). Users
--    whose users.role does not match a known role are skipped (the JOIN drops
--    them); they fall back to the implicit 'user' default at check time.

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
SELECT u.id, r.id, 'global', NULL
FROM users u
JOIN roles r ON r.scope_type = 'global' AND r.name = u.role
ON CONFLICT (user_id, role_id, scope_id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
SELECT e.creator_id, r.id, 'event', e.id
FROM events e
JOIN roles r ON r.scope_type = 'event' AND r.name = 'creator'
WHERE e.creator_id IS NOT NULL
ON CONFLICT (user_id, role_id, scope_id) DO NOTHING;