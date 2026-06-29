# ADR 0001: Matches Are Scoped to a Single Item Group

- **Status**: Accepted
- **Date**: 2026-06-29

## Context

`ymatch` organizes tradeable merchandise into **item groups** (a.k.a. merchandise
groups). A group is the first-class entity `merchandise_groups`, uniquely identified
by `(event_id, group_name)` (see migration `20250609000000_merchandise_groups.sql`).
Each `merchandise` row carries a `group_name` (migration `20250118000004_merch_item_groups.sql`)
that places it in exactly one group within its event.

A **match** is the unit of negotiation between two users: it is the entity on which
an offer, a counter-offer, and an acceptance can be performed. Its lifecycle is
`PENDING → OFFERED → ACCEPTED → COMPLETED` (or `REJECTED`), tracked on the `matches`
table with `offered_by` recording who made the current offer (migration
`20250405000000_trade_lifecycle.sql`). The concrete legs of a proposed exchange are
stored in `match_items`, one row per merchandise leg a user gives.

The question this ADR answers is: *what is the scope of a single match?* Specifically,
may one match span merchandise from more than one group?

Consider two groups, **G1** and **F1**, and two users:

- **U1** — G1: `g1`=WANT, `g2`=GIVE ; F1: `f1`=WANT, `f2`=GIVE
- **U2** — G1: `g1`=GIVE, `g2`=WANT ; F1: `f1`=GIVE, `f2`=WANT

U1 and U2 hold reciprocal HAVE/WANT inventory in *both* G1 and F1. The desired
behavior is that **two separate matches** are created — one scoped to G1
(negotiating the `g1`/`g2` exchange) and one scoped to F1 (negotiating the
`f1`/`f2` exchange) — rather than a single match bundling all four items across two
groups. Each match is then an independent offer/counter-offer/acceptance unit.

### Current state (as of this decision)

This is a **target invariant**, not a description of the current code. Today the
`matches` table carries no group reference — only `user1_id`, `user2_id`,
`status`, `offered_by` — and `backend/src/matching.rs` creates **one match per
user pair**, deduplicating purely on `(user1_id, user2_id)`. The same-group
constraint is enforced only at *candidate generation* time (reciprocal WANT/TRADE
pairs must share `group_name`), so a second reciprocal pair in a different group
for the same two users does **not** produce a second match today. Achieving the
invariant in this ADR therefore requires schema and algorithm changes (see
Consequences). `group_name` is also currently `NULL`-able; this ADR additionally
rules that `NULL`-grouped merchandise does not participate in matching at all.

## Decision

1. **A match is strictly scoped to a single item group.** Every match belongs to
   exactly one `(event_id, group_name)`. All merchandise legs ever attached to a
   match — the reciprocal inventory that triggered it and every `match_items` row
   proposed in an offer, counter-offer, or acceptance — must belong to that same
   group.

2. **One match per `(user1, user2, group)` tuple, not per user pair.** When two
   users hold reciprocal inventory across multiple shared groups, one independent
   match is created per shared group. The U1/U2 example above therefore yields two
   matches (G1 and F1), each negotiable independently.

3. **The boundary is exceptionless and universal.** No feature may create or extend
   a match across a group boundary. All other subsystems — matching, offer,
   counter-offer, acceptance, inventory apply, notifications, and messages — may
   assume without re-checking that any match they touch is wholly within one group.

4. **`NULL`-grouped merchandise is not matchable.** Merchandise with
   `group_name IS NULL` does not participate in matching. (This implies grouping
   must be assigned before an item is eligible to match.)

5. Because offers and counter-offers can only be made *within* a match, and a match
   is group-scoped, the items selectable in an offer/counter-offer are confined to
   the match's group **by construction**. The offer/counter-offer endpoints must
   nonetheless validate that every selected `match_items` leg belongs to the
   match's group, so that the invariant cannot be violated by a direct API call.

## Consequences

**Positive:**

- Negotiation is decomposed per group, so a multi-group relationship between two
  users does not force one monolithic offer. Users can accept the G1 exchange while
  still negotiating the F1 exchange.
- Each match has a single, unambiguous group context, which simplifies UI grouping,
  messaging scope, notifications, and per-group unread/read tracking.
- Downstream features get a hard invariant they can rely on without re-checking
  group membership in every query.

**Negative / costs:**

- The `matches` table must gain a group reference (e.g. `event_id` + `group_name`,
  or a `merchandise_groups` foreign key), and the unique/dedup logic in
  `backend/src/matching.rs` must move from `(user1_id, user2_id)` to
  `(user1_id, user2_id, group)`. This is a schema migration plus algorithm change
  and is **not yet implemented**; it will be tracked in a separate issue/PR.
- Existing `matches` rows (per-pair, no group) have no recorded group. A migration
  strategy is required: either backfill the group from the surviving `match_items`
  rows, or treat un-migrated rows as legacy and prevent new cross-group activity on
  them. This is left to the migration issue.
- The offer/counter-offer endpoints must add group-membership validation for
  selected items (a new check that does not exist today).
- `NULL`-grouped merchandise being non-matchable is a stricter rule than the
  current `matching.rs` behavior (which treats `NULL` as its own bucket and
  matches `NULL` to `NULL`). Inventory or merchandise creation flows must ensure a
  group is assigned for an item to be matchable; otherwise it is silently inert.
- Match uniqueness and the "already-matched" guard in `matching.rs` must be
  reworked, since a user pair may now legitimately coexist in multiple active
  matches (one per group).

**Required follow-up (out of scope for this ADR):**

- Implementation tracked in #341.
- Migration adding group scoping to `matches` and a backfill/cutover plan.
- Rewrite of `matching.rs` dedup to `(user1, user2, group)` and removal of the
  `NULL`-to-`NULL` matching branch.
- Group-membership validation in the offer/counter-offer handlers.

## Alternatives Considered

- **One match per user pair, spanning any shared groups (current behavior).**
  Rejected: it forces all cross-group negotiation into a single offer, so accepting
  one group's exchange is coupled to the other group's terms. It also leaves a
  match with no well-defined group context, complicating UI, messaging, and
  per-group read tracking.

- **One match per individual item pair (finer than group).** Rejected: it would
  explode the number of matches and lose the natural grouping of items that users
  intend to trade together within a group. The group is the meaningful
  negotiation unit, not the individual item.

- **Allow cross-group matches with per-leg group tagging.** Rejected: it removes
  the single-group context that downstream features rely on and breaks the
  "exceptionless boundary" property this ADR establishes, forcing every consumer to
  re-check group consistency per leg.
