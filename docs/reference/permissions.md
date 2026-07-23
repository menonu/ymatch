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
- **Scopes:** `global` (`scope_id NULL`), `event` (`scope_id = events.id`), and
  `group` (`scope_id = merchandise_groups.id`, #443 / [ADR 0013](../explanation/adr/0013-group-scope-rbac.md)).
  A check in the `event` or `group` scope consults the user's global roles
  *plus* their roles in that scope.
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
| `event` | `creator` | Owns an event; manages its editors; can transfer creator; edits the event, its merch, and its groups. |
| `event` | `editor` | Edits an event's merch and groups; can assign/remove other editors; cannot delete the event or transfer creator. |
| `group` | `creator` | Owns a specific item group; manages group editors; can transfer group creator; edits group metadata (#443). |
| `group` | `editor` | Co-manages a specific item group (edit metadata, assign/remove group editors); cannot transfer group creator (#443). |

## Global permissions

Granted in the `global` scope; checked with `Scope::Global` (except the `*.any`
overrides, which are *held* globally but *satisfy* an event-scope check).

| Permission | Granted to | Satisfies | Enforced by |
|---|---|---|---|
| `user.read` | admin, moderator | `user.read` | `admin::get_user_details` (`GET /admin/users/:id`); also unlocks full (non-secret) fields on `GET /users?user_id=` (#491) |

| `user.ban` | admin, moderator | `user.ban` | `admin::ban_user` (`POST /admin/users/:id/ban`) |
| `user.unban` | admin, moderator | `user.unban` | `admin::unban_user` (`POST /admin/users/:id/unban`) |
| `user.role.manage` | admin | `user.role.manage` | `admin::update_user_role` (`PUT /admin/users/:id/role`) |
| `event.create` | admin, moderator | `event.create` | `events::create_event` (`POST /events`) |
| `event.edit.any` | admin, moderator | `event.edit` (the event-scope check) | — (override; satisfies `event.edit`) |
| `event.delete.any` | admin, moderator | `event.delete` (the event-scope check) | — (override; satisfies `event.delete` on `DELETE /admin/events/:id`) |
| `merch.delete.any` | admin, moderator | `merch.delete` (the event-scope check) | `admin::delete_merch` (`DELETE /admin/merch/:id`); `merch::list_all_merch` (`GET /admin/merch?user_id=`) (#491) |

| `merch.create.any` | admin, moderator | `merch.create` (the event-scope check) | — (override; satisfies `merch.create`) |
| `merch.edit.any` | admin, moderator | `merch.edit` (the event-scope check) | — (override; satisfies `merch.edit`) |
| `group.edit.any` | admin, moderator | `group.edit` (the event-scope check) | — (override; satisfies `group.edit`) |
| `group.delete` | admin, moderator | `group.delete` | `admin::delete_group` (`DELETE /admin/events/:id/groups/:name`); `admin::list_groups` (`GET /admin/groups?user_id=`) (#491) |
| `match.delete` | admin, moderator | `match.delete` | `admin::delete_match` (`DELETE /admin/matches/:id`); `matches::list_all_matches` (`GET /admin/matches?user_id=`) (#491) |

| `event.creator.transfer` | admin, moderator | `event.creator.transfer` | `admin::transfer_event_creator` (`PUT /admin/events/:id/creator`) |
| `group.creator.transfer` | admin, moderator | `group.creator.transfer` | `admin::transfer_group_creator` (`PUT /admin/events/:id/groups/:name/creator`) |
| `event.member.manage.any` | admin, moderator | `event.member.manage.any` | Admin members path (`GET/POST/DELETE /admin/events/:id/members…`). **Not** an override of `event.member.manage` — the public members API stays creator/editor + admin-bypass only (#432 / #442). |
| `system.kill_switch` | admin | `system.kill_switch` | — (defined; no consumer wired yet) |

## Event-scope permissions

Granted in the `event` scope (to `event/creator` and/or `event/editor`); checked
with `Scope::Event(event_id)`. A global `*.any` override (held by moderator/admin)
also satisfies each event-scope check.

| Permission | Granted to (event roles) | `*.any` override | Enforced by |
|---|---|---|---|
| `event.edit` | creator, editor | `event.edit.any` | `events::update_event` (`PUT /events/:id`), `events::publish_event` (`POST /events/:id/publish`) |
| `event.delete` | creator | `event.delete.any` | `admin::delete_event` (`DELETE /admin/events/:id`) — event-scope check (#233) |
| `event.member.manage` | creator, editor | *(none by design)* | event-member API (`POST/DELETE/GET /events/:id/members`) (#442 grants editor) |
| `merch.delete` | creator, editor | `merch.delete.any` | `merch::delete_merch_by_creator` (`DELETE /events/:id/merch/:id`) |
| `merch.create` | creator, editor | `merch.create.any` | `merch::create_merch` (`POST /events/:id/merch`); `groups::create_event_group` (`POST /events/:id/groups`) (#491) |
| `merch.edit` | creator, editor | `merch.edit.any` | `merch::update_merch` (`PUT /events/:id/merch/:id`), `merch::publish_merch` (`POST /events/:id/merch/:id/publish`) |
| `group.edit` | creator, editor | `group.edit.any` | `groups::update_event_group` (`PUT /events/:id/groups/:name`) — also satisfied by group-scoped `group.edit` (#443) |

## Group-scope permissions

Granted in the `group` scope (to `group/creator` and/or `group/editor`); checked
with `Scope::Group(merchandise_groups.id)` (#443 / ADR 0013). Global
`group.edit.any` still satisfies `group.edit` when global roles are loaded.
`group.member.manage` has **no** `*.any` form.

| Permission | Granted to (group roles) | `*.any` override | Enforced by |
|---|---|---|---|
| `group.edit` | creator, editor | `group.edit.any` | `groups::update_event_group` (after ownership + event-scope checks fail) |
| `group.member.manage` | creator, editor | *(none by design)* | group-member API (`GET/POST/DELETE /events/:id/groups/:name/members…`) |

> **Event editor ≠ group editor.** Event-scoped roles grant event-wide
> `group.edit` for any group in the event. Group-scoped roles grant powers only
> for that item group.
>
> The **merch creator** and **group owner** (`created_by`) pass `merch.edit` /
> `group.edit` checks via an ownership short-circuit at the handler when the
> column equals the caller. Group owner also holds `group/creator` after
> backfill/create (#443).

## Granting roles

- **Event `creator`** is auto-assigned at event creation (inside the event-insert
  transaction). The public members API never removes it. The current creator may
  self-service transfer via `PUT /events/:id/creator` (ownership check, #442);
  global staff reassign via `PUT /admin/events/:id/creator`
  (`event.creator.transfer`) (#432). Neither path auto-promotes the previous
  creator to `editor`.
- **Event `editor`** is assigned/revoked via the event-member API, guarded by
  `event.member.manage` (event **creator** or **editor**, #442), **or** via the
  admin members path (`event.member.manage.any`) for moderators/admins (#432).
- **Group `created_by`** is set at group creation (ownership short-circuit for
  `group.edit`) and a matching `group/creator` role is assigned in the same
  transaction (#443). Self-service transfer:
  `PUT /events/:id/groups/:name/creator` (current owner only). Global staff
  reassign via `PUT /admin/events/:id/groups/:name/creator`
  (`group.creator.transfer`) (#432) — both paths keep `created_by` and
  `user_roles` in sync.
- **Group `editor`** is assigned/revoked via the group-member API, guarded by
  `group.member.manage` (group **creator** or **editor**, #443).
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
- [ADR 0013 — Group-Scoped RBAC](../explanation/adr/0013-group-scope-rbac.md)
- [Granting Global Roles](../how_to/grant_roles.md)
- [API Specification](api_spec.md) · [Database Schema](db_schema.md)
