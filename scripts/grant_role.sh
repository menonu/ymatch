#!/bin/bash
# scripts/grant_role.sh — idempotently grant a GLOBAL role to a ymatch user.
#
# ADR 0004 §6 / #228 PR4. This is the per-environment operator tool for
# granting the global `user` / `moderator` / `admin` role. It mirrors the
# production `UserRepository::set_role` path (backend/src/repositories/user.rs):
# it writes `users.role` AND the `user_roles` global row in one atomic
# operation so the denormalized `users.role` mirror and the authoritative
# `user_roles` table cannot drift (ADR 0004 §2). Re-running with the same
# (username, role) leaves the user's state unchanged.
#
# Usage:
#   ./scripts/grant_role.sh <username> <role>
#
#   <username>  an existing ymatch username
#   <role>       one of: user, moderator, admin
#
# Database connection (auto-selected):
#   * Default: `docker exec` into the running `ymatch_db` container. The
#     container name `ymatch_db` is identical in docker-compose.yml (local
#     dev) and docker-compose.oci.yml (staging/prod), so the same command
#     works on local dev, the staging VM, and the prod VM.
#   * Override: set `DATABASE_URL` (e.g. `postgres://user:pass@host:5432/db`)
#     to use `psql` directly — useful over an SSH tunnel or where the docker
#     container is not reachable from the caller. The script fails fast if
#     the required binary (`docker` or `psql`) is missing.
#
# Security (see docs/explanation/security.md): the username is a RUNTIME
# argument. Never hardcode a username into a committed file — that would
# commit a personal identifier to the public repo. If you keep a per-env
# wrapper script for convenience, it MUST be git-ignored; `scripts/*local*`
# is gitignored for this purpose. Granting a role is an admin/operator action;
# run it only against the environment you intend to change.
#
# Idempotent: re-granting the same role leaves the user's state unchanged.
# Granting `user` DEMOTES
# from moderator/admin (mirrors `set_role`), which is how you revoke an
# elevated global role.

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <username> <role>
  <username>  existing ymatch username (chars: [A-Za-z0-9_.@-])
  <role>      one of: user, moderator, admin

Env:
  DATABASE_URL  if set, connect via psql to this URL instead of docker exec
EOF
  exit 2
}

[ $# -eq 2 ] || usage
USERNAME="$1"
ROLE="$2"

# Role must be one of the known global roles. This is the first line of
# defense against SQL injection and against granting a nonexistent role;
# the SQL also looks the role id up defensively.
case "$ROLE" in
  user|moderator|admin) ;;
  *) echo "error: <role> must be one of: user, moderator, admin (got '$ROLE')" >&2; usage ;;
esac

# Username charset guard: psql :'var' quoting does not escape embedded
# single quotes, so restrict the username to a safe charset to make
# injection impossible. (ymatch usernames are already this shape.)
if ! [[ "$USERNAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
  echo "error: <username> contains characters outside [A-Za-z0-9_.@-]" >&2
  exit 2
fi

# Select the psql invocation. Default: docker exec into ymatch_db. If
# DATABASE_URL is set, use psql directly against it.
if [ -n "${DATABASE_URL:-}" ]; then
  if ! command -v psql >/dev/null 2>&1; then
    echo "error: DATABASE_URL is set but 'psql' is not on PATH" >&2
    exit 1
  fi
  PSQL=(psql "$DATABASE_URL")
else
  if ! command -v docker >/dev/null 2>&1; then
    echo "error: 'docker' not found and DATABASE_URL not set — cannot reach the DB" >&2
    exit 1
  fi
  PSQL=(docker exec -i ymatch_db psql -U ymatch_user -d ymatch)
fi

echo "Granting global role '$ROLE' to user '$USERNAME'..."

# Single atomic DO block: look up user + role, mirror-write users.role and
# the user_roles global row. The values are interpolated by bash directly into
# the SQL rather than via psql `:'var` variables, because psql does NOT
# interpolate variables inside a dollar-quoted (`$$ ... $$`) body — it treats
# the body as a string literal. This is safe ONLY because of the validation
# above: <role> is one of three literals, and <username> matched
# [A-Za-z0-9_.@-], so neither can contain a quote or other SQL metacharacter
# that could break out of the string literals below. The heredoc is unquoted so
# bash expands ${USERNAME}/${ROLE}, and `$$` is escaped as `\$\$` so bash does
# not expand it to its PID. ON_ERROR_STOP makes psql exit non-zero if the DO
# block raises (user/role not found), which `set -e` surfaces as a failure.
"${PSQL[@]}" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
DECLARE
  uid INTEGER;
  rid INTEGER;
BEGIN
  SELECT id INTO uid FROM users WHERE username = '${USERNAME}';
  IF uid IS NULL THEN
    RAISE EXCEPTION 'user not found: ${USERNAME}';
  END IF;
  SELECT id INTO rid FROM roles WHERE scope_type = 'global' AND name = '${ROLE}';
  IF rid IS NULL THEN
    RAISE EXCEPTION 'role not found (global/${ROLE}); catalog not seeded?';
  END IF;
  -- 1. Update the denormalized mirror (proto User.role / frontend admin gate).
  UPDATE users SET role = '${ROLE}' WHERE id = uid;
  -- 2. Replace the authoritative user_roles global row. A user holds at most
  --    one global role, so delete-then-insert is correct; the insert is
  --    idempotent via ON CONFLICT (re-grant / demote both land here).
  DELETE FROM user_roles WHERE user_id = uid AND scope_type = 'global' AND scope_id IS NULL;
  INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
    VALUES (uid, rid, 'global', NULL)
    ON CONFLICT (user_id, role_id, scope_id) DO NOTHING;
END
\$\$;
SQL

echo "Done. '$USERNAME' now holds the global '$ROLE' role (users.role + user_roles mirrored)."
