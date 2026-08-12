# ADR 0016: Global `editor` Role

- **Status**: Accepted
- **Date**: 2026-08-10
- **Supersedes**: —

## Context

[ADR 0004](0004-rbac-permission-model.md) seeded three global roles —
`user`, `moderator`, and `admin` — and separate **event-scoped** `creator` /
`editor` roles for per-event content management. Over time, platform staff
needed a middle tier: people who create and curate catalog content across
events, but must not ban users, delete matches, reassign ownership, or manage
global roles.

Until this decision, that work required `moderator`, which also grants user
moderation and match deletion. Event-scoped `editor` cannot fill the gap
because it is limited to a single event and must be assigned per event.

Issue #551 asks for a new **global** role named `editor` with content-only
powers, ordered as:

```
user  <  editor  <  moderator  <  admin
```

Constraints:

- Reuse the existing permission catalog (`*.any` overrides, `event.create`,
  `group.delete`); do not invent parallel permission names.
- Do not change event-scoped or group-scoped `editor` semantics (those names
  remain scope-local).
- Only `admin` continues to grant/revoke global roles (`user.role.manage`).

## Decision

### 1. Seed `global/editor` in the roles catalog

Add a `roles` row: `scope_type = 'global'`, `name = 'editor'`. Assignments use
the same `user_roles` path as other global roles (`scope_id NULL`), and
`User.role` continues to be derived from that row at read time
([ADR 0006](0006-derive-user-role-from-user-roles.md)).

### 2. Content-only permission set

`global/editor` is granted:

| Permission | Purpose |
|---|---|
| `event.create` | Create events platform-wide |
| `event.edit.any` | Edit any event |
| `event.delete.any` | Remove any event |
| `merch.create.any` | Create merch on any event |
| `merch.edit.any` | Edit any merch |
| `merch.delete.any` | Remove any merch |
| `group.edit.any` | Edit any group |
| `group.delete` | Remove any group |

It is **not** granted: `user.read`, `user.ban`, `user.unban`,
`user.role.manage`, `match.delete`, `event.creator.transfer`,
`group.creator.transfer`, `event.member.manage.any`, `system.kill_switch`.

Moderator remains “editor powers + user/match staff powers”; admin remains
superuser + role management.

### 3. Operator and admin API surfaces accept `editor`

- Admin `update_user_role` validates `user|editor|moderator|admin`.
- `scripts/grant_role.sh` accepts the same set.
- Frontend staff navigation and admin dashboard entry include `editor` so
  content tabs (events / groups / items) that already gate on the permissions
  above are reachable; ban, role-manage, and match-moderation actions remain
  backend-denied for editors and are hidden from the user menu where the
  caller lacks those powers.

## Consequences

- Content operators can be granted least privilege without full moderation.
- Catalog list endpoints that reuse delete permissions (#491) become available
  to global editors for merch and groups; the matches list stays
  moderator/admin-only (`match.delete`).
- The name `editor` is overloaded across scopes (`global` / `event` / `group`).
  Call sites and docs must always qualify by scope; RBAC rows already key on
  `(scope_type, name)`.
- Event- and group-scoped editors are unchanged; global editor does **not**
  automatically grant public event/group member-management on events the user
  does not own (no `event.member.manage` / `event.member.manage.any`).

## Alternatives Considered

- **Reuse `moderator` and document “content-only moderators”** — rejected:
  cannot express least privilege in the catalog; over-grants ban/match delete.
- **Only event-scoped editors, assigned to many events** — rejected: does not
  cover create-event or platform-wide delete without per-event assignment
  churn.
- **New permissions (e.g. `content.manage`)** — rejected: existing `*.any`
  overrides already model “any event” content work; a parallel catalog would
  duplicate enforcement sites.
