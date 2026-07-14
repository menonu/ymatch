# ADR 0008: Merchandise Deletion Semantics and the `CANCELLED` Match Status

- **Status**: Accepted
- **Date**: 2026-07-14
- **Supersedes**: —

## Context

Merchandise (`merchandise` table) carries soft-delete and trade-control columns
`is_deleted` and `trade_enabled` (migration `20250322000001_draft_and_soft_delete.sql`).
Until this decision, deletion was governed by a single heuristic in
`MerchandiseRepository::delete_by_id` (`src/repositories/merch.rs:365-399`), the
funnel for both the creator path (`DELETE /api/v1/events/:id/merch/:id` →
`delete_merch_by_creator`) and the admin path (`DELETE /api/v1/admin/merch/:id`):

- if any `inventory` row with `quantity > 0` referenced the merch → **soft-delete**
  (`is_deleted = true, trade_enabled = false`);
- otherwise → **hard delete** (`DELETE FROM merchandise`).

New matching skips soft-deleted / trade-disabled merch
(`src/matching.rs:15`: `m.is_deleted = false AND m.trade_enabled = true`), and
group removal (`src/repositories/group.rs:81-121`) already soft-deletes a group's
merch while hard-deleting its matches, messages, and favorites — its comment
states the rationale: "so inventory history remains valid."

This left several gaps, all documented in issue #421:

1. **Hard delete can raise an unhandled FK violation.** Both `inventory.merch_id`
   and `match_items.merch_id` are `REFERENCES merchandise(id)` with no `ON DELETE`
   clause (→ RESTRICT; `20250101000000_initial_schema.sql:30`,
   `20250405000000_trade_lifecycle.sql:15`). `delete_by_id` only checks
   `inventory.quantity > 0`, not `match_items`. A merch with zero positive
   inventory that still has `match_items` rows (an `OFFERED`/`ACCEPTED` match, or
   a `COMPLETED` match whose items persist — `match_items` are only deleted on the
   `REJECTED` transition, `src/services/match_lifecycle.rs:255`) makes
   `DELETE FROM merchandise` raise FK violation 23503 → HTTP 500. A lingering
   `quantity = 0` inventory row triggers the same violation for the same reason.

2. **Deleting an item does not stop existing matches that reference it.** The
   matching algorithm excludes soft-deleted merch from *new* matches, but nothing
   invalidates `PENDING`/`OFFERED`/`ACCEPTED` matches already pointing at the
   item. A match can therefore persist against an item the counterparty can no
   longer trade; accept/complete behavior on a deleted item was undefined.

3. **Deleted items were fully hidden, including from their own holder.** The event
   merch list and search filter `is_deleted = false`
   (`src/repositories/merch.rs`, `src/handlers/search.rs:46`). A holder could not
   see that an item they owned had been deleted. (`inventory.list_for_user`,
   `src/repositories/inventory.rs:75`, was already inconsistent — it returns the
   holder's rows with no `is_deleted` filter, but without marking them deleted.)

4. **"Existing item" re-creation semantics were undefined.** Soft-deleted rows
   keep `is_deleted = true`; the per-group live-name unique index
   `uq_merchandise_live_name_per_group` is a *partial* index scoped to
   `WHERE is_deleted = false` (migration `20260627000000`), so a soft-deleted row
   frees its name. Whether re-creating that name revived the old row or made a new
   one was unspecified, and there was no restore path.

The framing that drives this decision: **merchandise deletion is a rare,
corrective action** — it happens only for trouble cases (wrong items, duplicates,
etc.), never as part of normal trading flow. That makes row accumulation a
non-issue and lets us prioritize a clean, uniform contract over an optimized
delete path.

## Decision

1. **Soft-delete only; drop the hard-delete branch.** `delete_by_id` always
   performs `UPDATE merchandise SET is_deleted = true, trade_enabled = false
   WHERE id = $1` (scoped by `event_id` on the creator path). `DELETE FROM
   merchandise` is no longer issued by the delete API. This eliminates gap #1
   entirely — the RESTRICT FKs on `inventory.merch_id` / `match_items.merch_id`
   never fire on the delete path, because the merch row is never removed — and
   unifies item deletion with `group.rs:remove_for_admin`, which already
   soft-deletes merch.

2. **Introduce a `CANCELLED` terminal match status; deleting an item cancels
   every match that references it.** The `matches.status` domain gains
   `CANCELLED` (migration extending `matches_status_check`). When a merch is
   deleted, every `PENDING`, `OFFERED`, or `ACCEPTED` match that references it
   (via `match_items.merch_id`, on either the give or the receive side) transitions
   to `CANCELLED` in the same transaction as the soft-delete. `COMPLETED` matches
   are left untouched — their inventory deltas are already applied and cannot be
   undone; they remain as historical record. `REJECTED` remains the user-driven
   reject path; `CANCELLED` is reserved for this system-driven invalidation.

   The state machine from ADR 0002 gains one transition family:
   ```
   PENDING  ──cancel (system, item deleted)──► CANCELLED
   OFFERED  ──cancel (system, item deleted)──► CANCELLED
   ACCEPTED ──cancel (system, item deleted)──► CANCELLED
   ```
   `CANCELLED → <anything>` is terminal. This **extends** ADR 0002; it does not
   reverse any transition defined there.

3. **`CANCELLED` is not shown in the UI.** The frontend treats `CANCELLED` as a
   non-active state: cancelled matches are excluded from active-match lists and
   badge/counts, and there is no user-facing "cancelled" view. The status exists
   to preserve referential history and to stop further lifecycle actions, not to
   surface a new screen. (Implementation: the match-list queries that currently
   filter `status != 'REJECTED'` are extended to also exclude `CANCELLED` where
   they surface active matches; the status is retained in the row for history.)

4. **Deleted items remain listed, explicitly marked deleted, and are visible only
   to their holder.** A "holder" is any user with a `HAVE` inventory row for the
   merch, plus the merch `creator_id` (who owns the catalog entry and performs the
   delete). Deleted items are excluded from other users' views — the event merch
   list, search, and match-candidate surfaces filter `is_deleted = false` for
   non-holders, and additionally include `is_deleted = true` rows marked as
   deleted for holders. The proto `Merchandise.is_deleted` field is the API marker;
   the frontend renders a "deleted" badge and disables offer/edit/trade actions on
   such rows. `trade_enabled` is always `false` when `is_deleted` is `true`; it
   remains as the matchability flag consumed by `src/matching.rs` but has no
   independent meaning for a deleted row.

5. **Re-creation of a soft-deleted name creates a new row; there is no revival.**
   Re-creating an item with the same name as a soft-deleted one inserts a fresh
   `merchandise` row with a new `id`. This is safe because uniqueness is enforced
   by the *partial* index `uq_merchandise_live_name_per_group`
   (`WHERE is_deleted = false`): the soft-deleted row is excluded, so there is
   still exactly one *live* row per `(event_id, group_name, name)`. The deleted row
   keeps its own `id`, so `inventory` and `match_items` rows belonging to the old
   row never cross-link to the new one. A holder may therefore see two entries —
   the old one marked deleted and the new live one — which is the intended shape.

6. **Delete + cancel is one transaction.** The soft-delete of the merch and the
   `CANCELLED` transition of all referencing matches occur in a single Postgres
   transaction, mirroring `group.rs:remove_for_admin`. This preserves the
   invariant that no `PENDING`/`OFFERED`/`ACCEPTED` match can outlive a deleted
   item it references.

7. **Historical match detail is exempt from the holder-only rule.** A `COMPLETED`
   or `CANCELLED` match still renders the deleted merch's name to *both*
   participants in that match's detail view, because the match is a historical
   record of an exchange (or attempted one). The holder-only visibility rule
   (Decision 4) governs *catalog* surfaces (merch list, search, inventory);
   match history shows what was agreed regardless of subsequent deletion.

### Settled minor points

- **Notification on forced cancel.** When a match is moved to `CANCELLED` because
  the counterparty deleted an item, a system `messages` row is posted into the
  match thread so the affected participant learns why the match disappeared from
  their active list (the row's `message_type` distinguishes it from user text).
- **Search is live-items-only.** Deleted items are excluded from search even for
  the holder; the holder sees their deleted items in their inventory list and the
  event merch list (holder-filtered), not via search. This keeps search a
  live-catalog surface.
- **WANT rows for a deleted merch.** A `WANT` row is not "having" the item, so a
  `WANT`-er is not a holder and does not see the deleted merch in catalog
  surfaces. Their `WANT` row is left inert (filtered out of matching by
  `m.is_deleted = false` already); a follow-up may clean up or hide such orphaned
  WANT rows, out of scope for this decision.

## Consequences

**Positive:**

- The FK 23503 failure mode is gone: deletion never removes a `merchandise` row,
  so the RESTRICT FKs from `inventory` and `match_items` cannot fire on the delete
  path.
- No `PENDING`/`OFFERED`/`ACCEPTED` match can outlive a deleted item it
  references — the invariant is enforced transactionally, so a user can never
  accept or complete a trade against an item the other side can no longer trade.
- Holders retain visibility of items they own after deletion (marked deleted),
  fixing the current behavior where a holder's item silently vanishes from their
  own view.
- Re-creation is unambiguous and safe: a new live row, no name collision, no
  cross-linked inventory/match history.
- The semantics are uniform across item deletion and group removal (both
  soft-delete merch), reducing special cases.

**Negative / costs:**

- A new match status (`CANCELLED`) widens the `matches.status` domain and the
  state machine. Every consumer of match status must treat `CANCELLED` as a
  terminal, non-active state. The frontend must explicitly exclude it from active
  views; failure to do so would surface cancelled matches as if active (Decision 3
  makes this a UI contract, not just a backend filter).
- `merchandise` rows accumulate over time (soft-deleted rows are never removed).
  Accepted: deletion is rare and corrective, and retaining the row is what makes
  holder visibility, historical match detail, and referential integrity work. If
  this ever becomes a concern, a separate retention/garbage-collection decision
  would be required — out of scope here.
- `trade_enabled` now has overlapping meaning with `is_deleted` (a deleted row is
  always `trade_enabled = false`). The column is retained because it predates this
  decision and is consumed by `src/matching.rs`, but readers must understand that
  `is_deleted = true` implies `trade_enabled = false`.
- The holder-only rule adds a per-viewer filter to the merch-list and search
  queries (join/union against the viewer's `HAVE` inventory rows), a small
  complexity and query cost on those endpoints.

**Follow-up work required:**

- Migration extending `matches_status_check` to include `CANCELLED`, and
  state-machine extension in `src/services/match_lifecycle.rs` (a
  `STATUS_CANCELLED` const and transition rules for `PENDING/OFFERED/ACCEPTED →
  CANCELLED`).
- Rewrite `delete_by_id` to always-soft-delete and to cancel referencing matches
  in one transaction (new repository/service method to find and cancel matches by
  `merch_id`).
- Update `list_merch`, `list_for_user`, and `search` for holder-visible deleted
  items; mark `is_deleted` in the API and add the frontend badge + disabled
  actions.
- Update match-list/active-count queries to exclude `CANCELLED` from active
  surfaces.
- Integration and unit tests covering: always-soft-delete; cancellation of
  `PENDING`/`OFFERED`/`ACCEPTED` matches on delete; `COMPLETED` left as history;
  holder-only visibility of deleted items (hidden from non-holders); re-creation
  of a soft-deleted name (new row, no collision, no cross-link).
- Decide whether `group.rs:remove_for_admin` should also move matches to
  `CANCELLED` instead of hard-deleting them, for consistency with Decision 2.
  Today it hard-deletes the group's matches; that remains valid but is
  inconsistent with the item-level rule. Left as a separate follow-up.

## Alternatives Considered

- **Keep the conditional hard-delete (current behavior).** Rejected: it is the
  source of gap #1 (FK 23503 on `match_items` / qty-0 `inventory`), and the
  `quantity > 0` guard is the wrong signal for "is it safe to remove the row" —
  it ignores `match_items` entirely. Patching the guard to also check `match_items`
  would preserve a second delete mode for no benefit, since deletion is rare and
  keeping the row is desirable for history and holder visibility.

- **Add `ON DELETE CASCADE` / `SET NULL` to the FKs and keep hard delete.**
  Rejected: cascading would silently destroy `match_items` (and `inventory`)
  history, breaking historical match detail and the holder-visibility goal. The
  point of keeping the row is to preserve that history; changing the FK policy
  works against the decision.

- **Stop matches by reusing `REJECTED` instead of adding `CANCELLED`.** Rejected:
  `REJECTED` is the user-driven "I decline this offer" path and is reachable only
  from `PENDING`/`OFFERED` (`src/services/match_lifecycle.rs:485`), so it cannot
  express invalidation of an `ACCEPTED` match without loosening that guard and
  overloading the status with a second meaning (user reject vs. system
  invalidation). A distinct `CANCELLED` keeps the two causes separate and lets
  the UI hide only the system-invalidated ones (Decision 3) while still showing
  user rejects as before.

- **Block the delete while an `ACCEPTED` match references the item.** Rejected:
  it would force the admin/creator to wait for or manually resolve an accepted
  match before correcting a wrong/duplicate item, which fights the "rare,
  corrective" framing. The delete should succeed and invalidate the match.

- **Revive the soft-deleted row on re-creation instead of inserting a new one.**
  Rejected: revival would re-enable `trade_enabled` on a row whose
  inventory/match history may belong to a prior, different intent, and would
  require a restore API and conflict-resolution rules. A new row is simpler and
  self-contained, and the partial unique index already permits it safely.

- **Hide deleted items from everyone, including the holder (status quo).**
  Rejected: a holder losing sight of an item they own — with no indication it was
  deleted — is the behavior this decision exists to fix. Holder visibility with a
  clear "deleted" marker is the agreed requirement.