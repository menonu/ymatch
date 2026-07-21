# ADR 0013: Group-Scoped RBAC (`scope_type = 'group'`)

- **Status**: Accepted
- **Date**: 2026-07-21
- **Supersedes**: —

## Context

ADR 0004 introduced a four-table RBAC model with two scopes: `global` and
`event`. `user_roles.scope_id` was left intentionally untyped so a third scope
could be added as a new `scope_type` literal without reshaping the assignment
table.

Item groups (`merchandise_groups`) already had ownership via `created_by`
(short-circuit for `group.edit`) and admin reassignment via
`group.creator.transfer` (#432). There was **no** group-scoped role catalog, no
group `editor` role, and no self-service member API — only event creator/editor
(and staff) could co-manage groups through event-scoped `group.edit`.

Issue #443 requires co-management of a **single** item group: a group creator
can transfer ownership and manage group editors; a group editor can
assign/remove other group editors but cannot transfer creator. This is the same
product matrix as event-scope self-service (#442), applied one level down.

Constraints:

- Do not replace event-scoped `group.edit` for event editors (#425 behavior stays).
- Keep admin #432 transfer path; make it keep `created_by` and the new role row
  in sync.
- Routes stay event+name keyed for URL stability; scope id uses the existing
  `merchandise_groups.id` primary key.

## Decision

### 1. New scope: `group`

- **`scope_type = 'group'`**
- **`scope_id = merchandise_groups.id`**

No `user_roles` schema change. Validation remains application-side (same
trade-off as event scope in ADR 0004).

### 2. Roles and permissions

| Scope | Role | Grants |
|---|---|---|
| `group` | `creator` | `group.edit`, `group.member.manage` |
| `group` | `editor` | `group.edit`, `group.member.manage` |

| Permission | Scope | Notes |
|---|---|---|
| `group.edit` | `group` | Edit this group's metadata. Same **name** as event-scoped `group.edit`; the check scope selects which role rows are loaded. Global `group.edit.any` still satisfies both when global roles are in the loaded set. |
| `group.member.manage` | `group` | List/assign/revoke **group** editors only. **No** `*.any` override (mirrors `event.member.manage`). |

Creator **transfer** is ownership-based (`created_by`), not a permission grant —
same pattern as event self-service transfer (#442).

### 3. Sync rule for ownership + role

`merchandise_groups.created_by` and the group-scoped `creator` `user_roles` row
must stay consistent in one transaction on:

- group creation (API and merch auto-create paths),
- self-service transfer (`PUT /events/:id/groups/:name/creator`),
- admin transfer (`PUT /admin/events/:id/groups/:name/creator`).

Neither transfer path auto-promotes the previous creator to `editor`.

Backfill: every existing group with non-null `created_by` gets a
`group/creator` assignment.

### 4. Public API (self-service)

- `GET /events/:id/groups/:group_name/members`
- `POST /events/:id/groups/:group_name/members/:user_id` — assign editor
- `DELETE /events/:id/groups/:group_name/members/:user_id` — revoke editor only
- `PUT /events/:id/groups/:group_name/creator` — current creator only
- `GET /events/:id/groups/:group_name/my-role` — capability flags for UI gates

404-before-403 for missing groups. Editor revoke never removes creator.

### 5. Relationship to event-scope

- Event `creator` / `editor` continue to edit groups via event-scoped
  `group.edit` (and staff via `group.edit.any` / admin bypass).
- Group-scope roles are an **additional** co-management layer for one item
  group, not a replacement for event roles.
- **Event editor ≠ group editor.**

`RbacService::check` gains `Scope::Group(group_id)` so handlers can evaluate
group-scoped grants without loading event roles (and vice versa).

## Consequences

**Positive:**

- Group co-management without elevating users to event editor.
- Extends ADR 0004's extensibility claim with a real third scope.
- Same product matrix and UI patterns as #442, reducing cognitive load.

**Negative / costs:**

- Two permissions share the name `group.edit` across scopes; callers must pass
  the correct `Scope` or dual-check (event then group) as `update_event_group`
  does.
- Orphaned `user_roles` if a group is deleted without cleanup — mitigated by
  deleting group-scoped roles in the admin group-removal transaction.
- Merch create/edit remains event-scoped for now; group editors get group
  metadata + member management, not automatic merch.create on the event.

**Follow-up:**

- Optional admin path for group members (staff today use creator transfer only).
- Whether group editors should gain group-scoped merch permissions.

## Alternatives Considered

- **Only extend event-scoped roles with per-group grants.** Rejected: would
  require a different assignment model and confuse event-wide editor power with
  single-group co-management.
- **Permissions as ownership flags only (no group roles).** Rejected: cannot
  express multiple editors or self-service assign/remove without a role table.
- **Separate permission names (`group.scoped.edit`).** Rejected: doubles the
  catalog and complicates `satisfying_names`; shared names with scope-selected
  role loading are enough and match how global `*.any` already overlaps.
