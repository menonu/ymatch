# RBAC Permissions Reference

The catalog of roles and permissions in the `ymatch` role-based access control
(RBAC) model: what each permission is, which scope it lives in, which roles
grant it, and which handler enforces it. This is the **reference** for the
current permission set; the *why* behind the model lives in
[ADR 0004](../explanation/adr/0004-rbac-permission-model.md) and
[ADR 0005](../explanation/adr/0005-merch-create-permission.md).

## Model summary

- **Source of truth:** `user_roles` (one row per `(user_id, role_id, scope_type,
  scope_id)`). `users.role` is a denormalized mirror kept only for the proto
  `User.role` field / frontend admin gate; RBAC checks never read it.
- **Scopes:** `global` (`scope_id NULL`) and `event` (`scope_id = events.id`).
  A check in the `event` scope consults the user's global roles *plus* their
  roles on that event.
- **Decision rule** (`RbacService::check`, ADR 0004 §3): a check passes if
  **any** of:
  1. **Admin superuser bypass** — the user holds the `global/admin` role.
  2. The user holds a role (across the relevant scopes) whose
     `role_permissions` include the requested permission **or** the
     corresponding global `*.any` override (e.g. `event.edit.any` satisfies an
     `event.edit` check).
- **Ownership short-circuits** are *not* permissions: a resource's creator
  passes the handler's check directly (an ownership comparison), then the RBAC
  permission is consulted only for non-owners. This applies to merch
  update/publish/delete (the merch creator) and group update (the group
  creator).
- **`*.any` overlap** is encoded in `Permission::satisfying_names`, not in the
  catalog, so adding a new `*.any` permission is a catalog row, not a code
  change. `event.member.manage` and `match.delete` have **no** `*.any` form by
  design.

The typed handle at handler call sites is `Permission` (in
`backend/src/services/rbac.rs`); the string stored in the `permissions.name`
column is `Permission::as_str`.

## Roles

| Scope | Role | Description |
|---|---|---|
| `global` | `admin` | Full access / all permissions. Superuser bypass. |
| `global` | `moderator` | Platform management: read user details, ban/unban, create & manage events, edit or remove any event/merch/group, delete matches. |
| `global` | `user` | Standard trading. No elevated permissions (ordinary trading is ownership-checked). |
| `event` | `creator` | Owns an event; manages its editors; edits the event, its merch, and its groups. |
| `event` | `editor` | Edits an event's merch and groups; cannot delete the event or manage editors. |

## Global permissions

Granted in the `global` scope; checked with `Scope::Global` (except the `*.any`
overrides, which are *held* globally but *satisfy* an event-scope check).

| Permission | Granted to | Satisfies | Enforced by |
|---|---|---|---|
| `user.read` | admin, moderator | `user.read` | `admin::get_user_details` (`GET /admin/users/:id`) |
| `user.ban` | admin, moderator | `user.ban` | `admin::ban_user` (`POST /admin/users/:id/ban`) |
| `user.unban` | admin, moderator | `user.unban` | `admin::unban_user` (`POST /admin/users/:id/unban`) |
| `user.role.manage` | admin | `user.role.manage` | `admin::update_user_role` (`PUT /admin/users/:id/role`) |
| `event.create` | admin, moderator | `event.create` | `events::create_event` (`POST /events`) |
| `event.edit.any` | admin, moderator | `event.edit` (the event-scope check) | — (override; satisfies `event.edit`) |
| `event.delete.any` | admin, moderator | `event.delete` (the event-scope check) | — (override; satisfies `event.delete` on `DELETE /admin/events/:id`) |
| `merch.delete.any` | admin, moderator | `merch.delete` (the event-scope check) | `admin::delete_merch` (`DELETE /admin/merch/:id`) |
| `merch.create.any` | admin, moderator | `merch.create` (the event-scope check) | — (override; satisfies `merch.create`) |
| `merch.edit.any` | admin, moderator | `merch.edit` (the event-scope check) | — (override; satisfies `merch.edit`) |
| `group.edit.any` | admin, moderator | `group.edit` (the event-scope check) | — (override; satisfies `group.edit`) |
| `group.delete` | admin, moderator | `group.delete` | `admin::delete_group` (`DELETE /admin/events/:id/groups/:name`) |
| `match.delete` | admin, moderator | `match.delete` | `admin::delete_match` (`DELETE /admin/matches/:id`) |
| `system.kill_switch` | admin | `system.kill_switch` | — (defined; no consumer wired yet) |

## Event-scope permissions

Granted in the `event` scope (to `event/creator` and/or `event/editor`); checked
with `Scope::Event(event_id)`. A global `*.any` override (held by moderator/admin)
also satisfies each event-scope check.

| Permission | Granted to (event roles) | `*.any` override | Enforced by |
|---|---|---|---|
| `event.edit` | creator, editor | `event.edit.any` | `events::update_event` (`PUT /events/:id`), `events::publish_event` (`POST /events/:id/publish`) |
| `event.delete` | creator | `event.delete.any` | `admin::delete_event` (`DELETE /admin/events/:id`) — event-scope check (#233) |
| `event.member.manage` | creator | *(none by design)* | event-member API (`POST/DELETE/GET /events/:id/members`) |
| `merch.delete` | creator, editor | `merch.delete.any` | `merch::delete_merch_by_creator` (`DELETE /events/:id/merch/:id`) |
| `merch.create` | creator, editor | `merch.create.any` | `merch::create_merch` (`POST /events/:id/merch`) |
| `merch.edit` | creator, editor | `merch.edit.any` | `merch::update_merch` (`PUT /events/:id/merch/:id`), `merch::publish_merch` (`POST /events/:id/merch/:id/publish`) |
| `group.edit` | creator, editor | `group.edit.any` | `groups::update_event_group` (`PUT /events/:id/groups/:name`) |

> The **merch creator** and **group creator** pass `merch.edit` / `group.edit`
> checks via an ownership short-circuit at the handler (the `created_by` /
> `creator_id` column equals the caller), so they do not need the event role.
> The RBAC permission is consulted only for non-owners.

## Granting roles

- **Event `creator`** is auto-assigned at event creation (inside the event-insert
  transaction) and is not removable via the API (only the admin bypass can
  revoke it).
- **Event `editor`** is assigned/revoked via the event-member API, guarded by
  `event.member.manage` (the creator).
- **Global `user`/`moderator`/`admin`** are granted per-environment with
  [`scripts/grant_role.sh <username> <role>`](../how_to/grant_roles.md), which
  writes `users.role` and the `user_roles` global row in one transaction so the
  mirror and the authoritative assignment cannot drift.

## Adding a permission

1. Add a `Permission` variant (and its `*.any` form, if it has one) in
   `backend/src/services/rbac.rs`: `as_str` + `satisfying_names`.
2. Add a migration under `backend/migrations/` seeding the `permissions` row(s)
   and the `role_permissions` grants (idempotent `ON CONFLICT DO NOTHING`,
   mirroring `20260708000000_merch_create_permission.sql` /
   `20260709000000_merch_edit_group_match_permissions.sql`).
3. Wire the handler to `RbacService::check(&user, &scope, Permission::…)`,
   keeping the 404-before-403 convention (confirm the resource exists before
   the RBAC check, so a missing resource is not leaked as a 403).
4. Add a `#[cfg(test)]` catalog/`satisfying_names` entry and an integration
   boundary test.
5. Update the tables in this document.

## See also

- [ADR 0004 — RBAC Permission Model](../explanation/adr/0004-rbac-permission-model.md)
- [ADR 0005 — Gate Merch Creation Behind `merch.create`](../explanation/adr/0005-merch-create-permission.md)
- [Granting Global Roles](../how_to/grant_roles.md)
- [API Specification](api_spec.md) · [Database Schema](db_schema.md)
