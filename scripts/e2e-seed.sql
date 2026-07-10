-- E2E bootstrap: seed an admin and a moderator for the frontend E2E stack.
--
-- The RBAC rollout (#228) gates event creation (`event.create`), merch
-- creation (`merch.create`, #365), and admin endpoints behind RBAC roles, but
-- the E2E stack provisions a fresh backend + DB with no privileged user and
-- the E2E tests have API access only (no DB). Without these seeds, every E2E
-- test that creates an event / merch or calls an admin endpoint 403s.
--
-- RBAC authorization reads the `user_roles` table (RbacService::check) — and
-- since ADR 0006 / #371 dropped the `users.role` column, `user_roles` is the
-- sole source of truth for the global role (the proto `User.role` field the
-- frontend admin gate reads is derived from it at read time). So each seed
-- inserts the `users` row AND the `user_roles` global row; the role is no
-- longer a column on `users`.
--
-- Run after the backend is up (migrations applied), so the `roles` table is
-- populated. Idempotent: re-running (e.g. `task e2e:up` on a persistent stack)
-- is a no-op. The fixed uuids let the E2E tests "log in" as these users via
-- `POST /api/v1/auth/guest`, which is idempotent on uuid.
--
-- E2E-only: never run against staging/prod (the E2E DB is on tmpfs and wiped
-- on `down -v`).

-- 1. Admin ---------------------------------------------------------------
INSERT INTO users (username, uuid, device_token)
VALUES ('e2e-bootstrap-admin', 'e2e-bootstrap-admin', 'e2e-bootstrap')
ON CONFLICT (uuid) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
SELECT u.id, r.id, 'global', NULL
FROM users u
JOIN roles r ON r.scope_type = 'global' AND r.name = 'admin'
WHERE u.uuid = 'e2e-bootstrap-admin'
ON CONFLICT (user_id, role_id, scope_id) DO NOTHING;

-- 2. Moderator ----------------------------------------------------------
INSERT INTO users (username, uuid, device_token)
VALUES (
    'e2e-bootstrap-moderator',
    'e2e-bootstrap-moderator',
    'e2e-bootstrap'
)
ON CONFLICT (uuid) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
SELECT u.id, r.id, 'global', NULL
FROM users u
JOIN roles r ON r.scope_type = 'global' AND r.name = 'moderator'
WHERE u.uuid = 'e2e-bootstrap-moderator'
ON CONFLICT (user_id, role_id, scope_id) DO NOTHING;
