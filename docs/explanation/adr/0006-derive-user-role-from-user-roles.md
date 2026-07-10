# ADR 0006: Derive `User.role` from `user_roles` at Read Time (drop the `users.role` mirror)

- **Status**: Accepted
- **Date**: 2026-07-10
- **Supersedes**: —
- **Supplements**: [ADR 0004](0004-rbac-permission-model.md)

## Context

ADR 0004 §2 kept the `users.role` TEXT column as a **denormalized mirror** of the
global role so the proto `User.role` field and the frontend admin-dashboard gate
survived the RBAC rollout without a breaking change. `user_roles` (scope_type
`global`, scope_id `NULL`) was made the authoritative source — `RbacService::check`
reads it; the mirror was written in the same transaction as the `user_roles` row
so the two could not drift.

Two prerequisites flagged in #371 have since landed:

- **#370** unified the last authz paths on `RbacService` and removed the old
  `PermissionPolicy::require_role` / `require_owner_or_role` checks. **No
  authorization path reads `users.role` anymore** — `RbacService::check` uses
  only the user's `id` against `user_roles`.
- **#366** added `GET /events/:id/my-role` and gated the frontend Add-Merch
  button on it, giving the frontend a non-`User.role` way to learn an event
  role. (It did not rework the admin gate, which still reads `User.role`.)

With both done, `users.role` is redundant. It is also **lossy**: it holds one
global role per user, while `user_roles` can express multiple global roles plus
event-scoped roles. Maintaining two representations of "the user's global role"
is a divergence risk, and it already caused a real incident — the E2E suite was
red from #362 to #369 because a seed set `users.role` but not `user_roles`, and
RBAC correctly ignored the mirror.

The frontend still reads `currentUser.role` (the logged-in `User` proto) in two
places: `scaffold_with_nav_bar.dart` (Admin nav tab) and
`admin_dashboard_screen.dart` (dashboard gate + per-user role badge). So the
`User.role` proto field must keep working — only the storage behind it changes.

## Decision

Drop the `users.role` column and **derive `User.role` from `user_roles` at read
time** (proto-compatible: the `User.role` field stays, its value is computed
on fetch). This is **Option 1** of the two shapes #371 weighed.

Concretely:

- **Migration** `20260710000000_drop_users_role.sql` does
  `ALTER TABLE users DROP COLUMN IF EXISTS role`. No backfill is needed:
  `user_roles` is already authoritative (the RBAC migration backfilled every
  pre-existing `users.role` into a `user_roles` global row).
- The standard `users` SELECT list (`USER_COLUMNS` in
  `backend/src/repositories/user.rs`) replaces the literal `role` column with a
  correlated subquery that reads the user's global role from `user_roles`:

  ```sql
  COALESCE((SELECT r.name FROM user_roles ur
            JOIN roles r ON r.id = ur.role_id
            WHERE ur.user_id = users.id
              AND ur.scope_type = 'global' AND ur.scope_id IS NULL
            ORDER BY CASE r.name WHEN 'admin' THEN 0
                                 WHEN 'moderator' THEN 1
                                 ELSE 2 END
            LIMIT 1), 'user') AS role
  ```

  Aliased as `role`, so `user_from_row` is unchanged and every read path
  (`get_by_id`, `get_by_username`, `get_by_uuid`, `create_guest`,
  `create_with_password`, `list_all`, `update_username`) inherits the
  derivation through the shared `USER_COLUMNS` constant.
- **Precedence `admin > moderator > user`** (the `ORDER BY CASE`) makes the
  derivation deterministic in the theoretical case where a user holds more than
  one global role. `set_role` itself enforces at most one global role
  (delete-then-insert), so the precedence is defensive — but it pins the answer
  rather than leaving it to `LIMIT 1` row order, which is the bug class the lossy
  mirror invited.
- **`COALESCE(..., 'user')`** preserves the old `DEFAULT 'user'` column
  semantics: a guest with no `user_roles` global row derives `role = 'user'`.
- **`set_role` becomes a single `user_roles` write.** The dual-write to
  `users.role` is removed; the transaction keeps only the `roles`-catalog lookup
  and the delete-then-insert of the `user_roles` global row.
- **`grant_role.sh` and `scripts/e2e-seed.sql`** drop their `UPDATE users SET
  role` / `role`-in-`INSERT` steps. Only the `user_roles` assignment remains,
  which is what RBAC (and now the derivation) reads.
- **`VerifiedUser.role` is removed.** It was populated by `get_verified` from
  the column, but no authorization path read it (`RbacService::check` uses only
  `user.id`); it was dead. Removing it makes "no authz path reads `users.role`"
  literally true at the type level.

This **supplements** ADR 0004 (it reverses the §2 "keep the mirror" decision
without rewriting 0004's body, per the append-only ADR rules). 0004's record of
*why* the mirror was kept stands; this ADR records *why* it is now removed.

## Consequences

**Positive:**

- `user_roles` is the single source of truth for the global role. There is no
  mirror to drift; the #362–#369 class of bug (set one, forget the other) is
  impossible by construction.
- The proto `User.role` contract, the frontend admin gate, and the frontend
  Add-Merch gate (via #366) all keep working unchanged — no proto regeneration,
  no Dart change, no breaking change for any client.
- The lossy-multiple-global-role case now has a deterministic answer
  (`admin` wins) instead of an undefined one.
- `set_role` and `grant_role.sh` are simpler (one write, not two).

**Negative / costs:**

- Every `User` fetch runs a correlated subquery against `user_roles`. The cost
  is one indexed lookup on `user_roles(user_id)` (the `idx_user_roles_user`
  index from the RBAC migration), on paths that are not per-request hot: login,
  guest-login, and the admin user-list. Per-request authorization checks are
  unaffected — `RbacService::check` already queries `user_roles` directly and
  does not go through `User` / `USER_COLUMNS`.
- The admin user-list (`SELECT ... FROM users`) runs one subquery per row. For
  the current user volume this is immaterial; if it ever matters, a `LEFT JOIN`
  variant can replace it without changing the `role` alias `user_from_row`
  reads.
- `User.role` is a *derived projection* of `user_roles`, not stored state. Code
  that writes a global role must write `user_roles` (which `set_role` /
  `grant_role.sh` do); nothing writes a derived field directly.

**Follow-up work:**

- None blocked by this ADR. #376 (gate `GET /admin/users/:id`) remains open and
  separate. A future "multiple global roles per user" product change would be
  expressed as multiple `user_roles` rows; the precedence rule here already
  defines what `User.role` reports in that case.

## Alternatives Considered

- **Role-awareness endpoint (Option 2): drop `User.role` from the proto; expose
  the caller's global role via a new endpoint; rework the frontend admin gate
  to consume it.** Rejected: it is a breaking proto change (any out-of-tree
  client reading `User.role` breaks), requires a new global-role endpoint (the
  #366 `my-role` endpoint is event-scoped and does not report the global role),
  and forces a frontend provider + rework of the admin gate and the admin
  user-list (which displays each user's role and would lose that data without a
  bulk-roles endpoint). #366 already retired the only *behavioral* frontend
  dependence on a role endpoint (Add-Merch); what remains is the admin gate,
  which a derived field satisfies trivially. The endpoint option's larger blast
  radius buys nothing over the derivation for the gates that exist today.

- **Keep `users.role` as the sole global-role store.** Rejected — that is the
  pre-ADR-0004 model, already reversed by 0004's "unified `user_roles` is the
  source of truth" decision.

- **Derive with a `LEFT JOIN` instead of a correlated subquery.** Equivalent
  for correctness; the subquery was chosen because it slots into the existing
  `USER_COLUMNS` constant (a flat column list) without restructuring the read
  queries. A `LEFT JOIN` is the natural escalation if the user-list ever needs
  it.