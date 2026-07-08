# Granting Global Roles

This guide covers `scripts/grant_role.sh`, the operator tool for granting a
**global** role (`user`, `moderator`, or `admin`) to a ymatch user. It is the
per-environment mechanism required by [ADR 0004 §6](../explanation/adr/0004-rbac-permission-model.md)
so that no personal identifier (a username) is ever committed to the public
repo. Event-scoped roles (`creator` / `editor`) are **not** managed here —
`creator` is auto-assigned at event creation, and `editor` is managed via the
event-member API (`POST/DELETE/GET /api/v1/events/:id/members`).

## What it does

`grant_role.sh <username> <role>` writes **both** of these in one atomic
operation, mirroring the production `UserRepository::set_role` path:

- `users.role` — the denormalized mirror read by the proto `User.role` field
  and the frontend admin-dashboard gate.
- `user_roles` (`scope_type='global'`, `scope_id=NULL`) — the authoritative
  global role assignment read by `RbacService`.

Keeping both in one transaction means they cannot drift (ADR 0004 §2). The
script is **idempotent**: re-granting the same role leaves the user's state
unchanged. Granting
`user` **demotes** from `moderator`/`admin` — that is how you revoke an
elevated global role.

## Run it per environment

The script auto-selects its database connection:

- **Default** — `docker exec` into the running `ymatch_db` container. The
  container name `ymatch_db` is identical in `docker-compose.yml` (local dev)
  and `docker-compose.oci.yml` (staging/prod), so the same command works
  everywhere the docker stack is running.
- **Override** — set `DATABASE_URL` (e.g. `postgres://user:pass@host:5432/db`)
  to connect via `psql` directly, useful over an SSH tunnel or where the
  container is not reachable from your shell.

### Local dev

```bash
./scripts/grant_role.sh alice moderator
```

This execs into the local `ymatch_db` container (started by `task db:up`).

### Staging or production

SSH onto the VM (see [OCI Deployment](./oci_deployment.md) for SSH access),
then run the script from the repo checkout on the VM — it will exec into the
VM's `ymatch_db` container, which is that environment's database:

```bash
ssh <vm>
cd ~/ymatch
./scripts/grant_role.sh alice moderator
```

For non-docker access (e.g. a forwarded port over SSH), set `DATABASE_URL`:

```bash
DATABASE_URL="postgres://ymatch_user:<password>@localhost:5432/ymatch" \
  ./scripts/grant_role.sh alice moderator
```

The DB password is a secret — read it from the environment, never hardcode it
(see [Repository Security](../explanation/security.md)).

## Security

- The `<username>` is a **runtime argument**. Never hardcode a username into
  a committed file — that commits a personal identifier to the public repo.
- If you keep a per-env wrapper script for convenience (e.g. one that fills in
  your own username), it **must** be git-ignored. `scripts/*local*` is
  gitignored for this purpose; name your wrapper `scripts/grant_role.local.sh`
  (or any `*local*` name) so it is never tracked.
- The script validates the role (`user|moderator|admin`) and restricts the
  username to `[A-Za-z0-9_.@-]` before interpolating either value into the
  SQL, so neither can contain a quote or SQL metacharacter. The script does
  **not** rely on psql parameter substitution (`:'var`), which cannot be used
  inside a dollar-quoted `DO` body — the charset + role-enum checks are the
  injection guard.
- Granting a role is an admin/operator action — run it only against the
  environment you intend to change. Prefer granting `moderator` over `admin`
  unless full superuser access is required.

## Verification

After granting, confirm both halves of the mirror landed:

```bash
docker exec ymatch_db psql -U ymatch_user -d ymatch -c \
  "SELECT u.username, u.role, r.name AS rbac_role
   FROM users u LEFT JOIN user_roles ur
     ON ur.user_id = u.id AND ur.scope_type = 'global' AND ur.scope_id IS NULL
   LEFT JOIN roles r ON r.id = ur.role_id
   WHERE u.username = 'alice';"
```

Both `role` (the mirror) and `rbac_role` (the authoritative row) should read
`moderator`. If only one is set, the mirror has drifted — re-run the script to
repair it.
