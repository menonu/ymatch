# ADR 0004: Role-Based Access Control (RBAC) Permission Model

- **Status**: Accepted
- **Date**: 2026-07-05
- **Supersedes**: —

## Context

Before this decision, `ymatch` had an ad-hoc, single-dimension permission model:

- A `users.role` TEXT column (`migration 20250322000000_roles_and_bans.sql`) held
  one global role per user — `user`, `moderator`, or `admin` — with `DEFAULT
  'user'`. A parallel ban system (`is_banned`, `ban_reason`, `banned_until`)
  gated banned users.
- `services::PermissionPolicy` exposed `require_role(&["admin","moderator"])` and
  `require_owner_or_role(owner, &["admin","moderator"])`. Handlers called these
  inline, often hard-coding the role list at each call site
  (admin, events, merch, and groups handlers).
- Event "creator" was **implicit**: `events.creator_id` was an ownership column,
  not a role. There was no `editor` role and no way to delegate event
  management to a second user. `MerchPermissionPolicy` encoded a one-off 3-way
  rule (merch creator OR event creator OR admin/moderator) because the generic
  policy could not express it.

Issue #228 asks for a **structured, extensible permission model** with two
scopes:

- **Global** — `admin` (full access), `moderator` (platform management, ban/unban,
  create & manage events), `user` (standard trading).
- **Event** — `creator` (owns an event, manages `editor` roles for it),
  `editor` (edits event items/details).

The model must accommodate future scopes (e.g. team/organization) and future
roles within existing scopes without breaking current code, and must define how
overlapping roles (e.g. a global `admin` acting on an event) are resolved.

A hard constraint from the team: **introduce the RBAC model only — do not change
the authentication flow.** There are no sessions, tokens, or login changes here;
the caller's `user_id` still arrives in the request payload exactly as today.
RBAC is an authorization concern layered on top of the existing auth identity.

The frontend gates the admin dashboard on `proto.User.role`
(nav scaffold Admin tab, admin dashboard gate), so the `User.role`
proto field and the `users.role` column it reads must keep working through this
change. A group/role **editor UI is explicitly out of scope** for this round and
will be built later; the backend model and API must be ready for it.

## Decision

### 1. Four-table RBAC schema (roles, permissions, role_permissions, user_roles)

A full permission-table model, not a code-enum:

- `roles(id, scope_type, name, description)` — `UNIQUE(scope_type, name)`. The
  catalog of valid roles. Seeded with `global/{admin,moderator,user}` and
  `event/{creator,editor}`.
- `permissions(id, scope_type, name, description)` — `UNIQUE(scope_type, name)`.
  The catalog of granular permissions (e.g. `user.ban`, `event.edit`,
  `merch.delete`).
- `role_permissions(role_id, permission_id)` — many-to-many; a role *grants* a
  set of permissions.
- `user_roles(id, user_id→users CASCADE, role_id→roles CASCADE, scope_type,
  scope_id, created_at)` — `UNIQUE(user_id, role_id, scope_id)`. A user's
  assignment to a role *within a scope*. `scope_type` is `global` or `event`
  (future: `team`); `scope_id` is `NULL` for `global`, the `events.id` for
  `event`.

`scope_id` is a **generic nullable INTEGER with no polymorphic foreign key**.
Postgres cannot express "FK to `events` when `scope_type='event'`, NULL
otherwise" cleanly; rather than add per-scope FK columns that we would have to
reshape when a third scope arrives, `scope_id` is validated in application code
(and by the `event` scope's INSERT path, which always binds a verified
`event_id`). This is the trade-off that buys the extensibility the issue
requires: a new scope is a new `scope_type` literal + new permission names, with
no schema change to `user_roles`.

`user_roles.scope_type` is denormalized from `roles.scope_type` for fast
filtered lookups (`WHERE scope_type='event' AND scope_id=$1`) without a join to
`roles` on every check; it is written only by the assignment code, which always
reads it from the referenced `role`.

### 2. `user_roles` is the source of truth; `users.role` is a denormalized mirror

`user_roles` (with `scope_type='global'`, `scope_id=NULL`) is the authoritative
global role. `users.role` is **kept** as a denormalized mirror of that global
role, written in the same transaction whenever the global role changes
(`set_role` / `update_user_role`), so:

- the `proto.User.role` field and the frontend admin-dashboard gate keep working
  unchanged, and
- existing `get_verified` / `VerifiedUser.role` reads (used by current handlers
  until they are migrated to `RbacService`) keep working.

A user with **no `user_roles` global row is treated as having the `user` global
role.** This lets signup / guest-login stay untouched (no auth changes): new
users simply have no global assignment and fall back to the default `user` role,
whose permission set is empty (ordinary trading is ownership-checked, not
role-checked). The data migration backfills an explicit `global/user` row for
every pre-existing user, but new users rely on the implicit default.

### 3. Permission matrix and overlap resolution

Permissions are split into **global** permissions (some of which are `*.any`
"any event" overrides) and **event**-scoped permissions:

| Permission | Scope | Granted to |
|---|---|---|
| `user.ban`, `user.unban` | global | `admin`, `moderator` |
| `user.role.manage` | global | `admin` |
| `event.create` | global | `admin`, `moderator` |
| `event.edit.any` | global | `admin`, `moderator` |
| `event.delete.any` | global | `admin`, `moderator` |
| `merch.delete.any` | global | `admin`, `moderator` |
| `system.kill_switch` | global | `admin` |
| `event.edit` | event | `creator`, `editor` |
| `event.delete` | event | `creator` |
| `event.member.manage` | event | `creator` |
| `merch.delete` | event | `creator`, `editor` |

**Resolution rule.** A check `check(user, scope, permission)` passes if **any**
of:

1. **Admin superuser bypass** — the user holds the global `admin` role. `admin`
   is "full access/all permissions"; the bypass is a single short-circuit that
   makes every check pass without enumerating admin's permission rows.
2. The user holds a role (across `global` **plus** the relevant `event` scope,
   when checking an event permission) whose `role_permissions` include the
   requested permission, **or** include the corresponding `*.any` global
   permission (e.g. `event.edit.any` satisfies an `event.edit` check; this is
   how a `moderator` can edit any event without an event-scoped role).

This models overlap without wildcard permission strings: a global moderator's
`event.edit.any` is a concrete permission row that the check code treats as
satisfying the event-scoped `event.edit`. `admin` additionally gets every global
permission row for clarity, but the bypass is what makes admin omnipermissive.

### 4. Event creation is restricted to `moderator` / `admin`

Per the issue text, `event.create` is granted only to `moderator` and `admin`
(not `user`). `events::create_event` will check `event.create` via
`RbacService`. This is a **behavior change**: users who could previously create
events as ordinary active users can no longer do so. Existing events and their
creators are preserved by the backfill (each event's `creator_id` becomes an
`event/creator` assignment); only *new* event creation is gated.

### 5. Event-scoped roles are managed via a new member API

New endpoints (`POST/DELETE/GET /api/v1/events/:id/members`) assign/list/remove
`editor` roles for an event, guarded by the `event.member.manage` permission
(the event `creator`) or the admin bypass. The event `creator` role itself is
assigned automatically at event creation and is not removable via this API
(only the admin bypass can revoke it). Proto messages for these requests are
added in the same PR that wires the endpoints. The **frontend UI for managing
members is deferred** to a later issue; the backend is ready for it.

### 6. Moderator grant is a per-environment script, not a migration

The migration builds the schema and backfills existing roles only. Granting a
specific person a global role (`user`, `moderator`, or `admin`) is done with
**`scripts/grant_role.sh <username> <role>`** — an idempotent, per-environment
operator tool run against each environment's `ymatch_db`. It mirrors the
production `set_role` path (`users.role` + the `user_roles` global row in one
transaction) so the denormalized mirror and the authoritative assignment
cannot drift. The script is a generic, parameterized tool that takes the
username as a **runtime argument**, so no personal identifier is committed to
the public repo (per the repository security policy); any per-env wrapper an
operator keeps for convenience is git-ignored (`scripts/*local*`). See
[Granting Global Roles](../../how_to/grant_roles.md) for usage.

## Consequences

**Positive:**

- Permissions are data: adding a permission or role is a migration seed row, and
  granting a permission to a role is a `role_permissions` insert — no handler
  code change for pure grant changes.
- New scopes (team/org) are a new `scope_type` literal + new permission names;
  `user_roles` needs no schema change, satisfying the issue's extensibility
  requirement.
- Overlap (global moderator/admin acting on events) is expressed by concrete
  `*.any` permission rows plus the admin bypass — no wildcard string matching,
  no per-handler special-casing.
- Event delegation (`editor`) becomes possible for the first time, and the
  one-off `MerchPermissionPolicy` 3-way rule can be expressed in the same model
  as everything else.
- The auth flow, proto `User.role` field, and frontend admin gate are
  undisturbed, so this lands in reviewable, non-breaking PRs.

**Negative / costs:**

- Four new tables and a join path (`user_roles` → `role_permissions` →
  `permissions`) per authorization decision. Mitigated by loading the
  role/permission/`role_permissions` catalog into an in-memory
  `PermissionCatalog` at startup (the catalog is static between migrations), so
  a check is one `user_roles` query plus in-memory map lookups.
- `scope_id` has no foreign key; a buggy assignment could reference a
  non-existent `events.id`. Constrained to the assignment code path, which
  validates the event exists before inserting.
- `users.role` is now a denormalized mirror and can drift from `user_roles` if
  some code path writes one without the other. The role-mutation methods write
  both in one transaction, and a future hardening step can add a trigger or
  drop `users.role` once the frontend reads roles from a new endpoint.
- Restricting event creation to moderator/admin is a behavior change that
  affects existing users; it is deliberate (issue #228) but must be
  communicated.
- The `user` global role has an empty permission set, so "what a regular user
  can do" is implicit (ownership checks in handlers, not RBAC rows). This keeps
  ordinary trading out of the permission table but means the RBAC model alone
  does not describe the full access surface for non-elevated users.

**Follow-up work:**

- Group/role editor UI (deferred; separate issue).
- Frontend reading roles from an RBAC endpoint and dropping the `users.role`
  mirror (separate issue, after the UI).
- `system.kill_switch` is defined and granted to `admin` but has no consumer
  yet; wiring a kill-switch is a separate feature.

## Alternatives Considered

- **Permissions as a code enum with a static role→permission map, plus a
  `role_definitions` catalog table only.** Rejected: the issue text calls for
  "Roles, Permissions, Scopes, and Assignments" as schema, and a future
  role/permission management UI needs permissions to be data. The code-enum
  option is simpler and fewer joins, but moves grant changes back into code
  releases; we chose the data model now to avoid a later migration of the
  permission representation.

- **Keep `users.role` as the sole global-role store; add `user_roles` for event
  scope only.** Rejected: global and event roles would live in different
  places, and a third scope (team/org) would need a third home. The unified
  `user_roles` table is the source of truth for all scopes; `users.role` is
  retained only as a backward-compat mirror for the proto field.

- **Drop `users.role` entirely and have `proto.User.role` read from
  `user_roles`.** Rejected for this round: it forces a proto/frontend change and
  a new "get my roles" endpoint, expanding the blast radius past the
  "RBAC, not auth" boundary the team set. The mirror keeps the field working;
  dropping it is a follow-up.

- **Wildcard permission strings (`event.*`) granted to `admin`.** Rejected:
  wildcard matching adds parsing/semantics complexity and makes the permission
  set non-enumerable. Concrete `*.any` global permissions plus an admin
  superuser bypass express the same intent without wildcards.

- **Hardcode admin as the only override (no `*.any` permissions).** Rejected:
  it would not let a `moderator` edit any event — a current capability — without
  giving moderator the admin bypass or an event-scoped role on every event. The
  `*.any` rows let moderator keep its current cross-event powers within the
  permission model.

- **Make event creation a `user` capability (preserve current behavior).**
  Rejected: the issue text explicitly assigns event creation to `moderator`.
  The behavior change is intentional and tracked in this ADR.
