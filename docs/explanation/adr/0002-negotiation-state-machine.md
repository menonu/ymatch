# ADR 0002: Balanced Negotiation State Machine

- **Status**: Superseded in part by [ADR 0009](0009-apply-inventory-decrements-giver-have.md) (apply-inventory giver HAVE delta only; negotiation state machine unchanged)
- **Date**: 2026-06-29
- **Supersedes**: —

## Context

Before this decision, a match (`matches` table, migration
`20250405000000_trade_lifecycle.sql`) had a one-shot offer flow:

```
PENDING ──offer──► OFFERED ──accept──► ACCEPTED ──complete──► COMPLETED
   └──reject──► REJECTED    └──reject──► REJECTED
```

One party made a single offer; the other could only accept or reject. There was
no way to negotiate — to respond to an offer with a modified proposal — so the
first offer was effectively take-it-or-leave-it. Two gaps made this worse:

1. **No balance enforcement.** The receiver could accept an offer whose legs did
   not represent an equal exchange. Issue #294 had added a per-item want-quantity
   cap, but nothing required the give and receive sides of a trade to be equal.
2. **Offerer-relative legs.** `match_items` stored each leg relative to the
   offerer: `(match_id, owner_id, merch_id, direction, quantity)`, where
   `direction` was `GIVE` or `RECEIVE` *from the offerer's perspective*. A
   counter-offer — where the *other* party now edits the proposal — has no
   natural "offerer" to be relative to, so the schema could not express an
   alternating-proposal negotiation cleanly.

The desired behavior, captured in issue #297, was a **negotiation state machine**:
the two parties alternate proposals until a *balanced* trade is accepted, with
counter-offers. A trade can only complete when the total quantity each side gives
is equal (and positive).

## Decision

1. **Replace the one-shot offer with an alternating-proposal state machine.**
   The lifecycle becomes
   ```
   PENDING ──propose──► OFFERED ──counter──► OFFERED ── …
      │                   │
      │                   ├─accept (non-proposer + balanced)──► ACCEPTED
      │                   └─reject──────────────────────────► REJECTED
      └──reject──► REJECTED
   ACCEPTED ──complete──► COMPLETED
   ```
   The `OFFERED` status is reused as the single "proposal on the table" state; a
   counter-offer transitions `OFFERED → OFFERED`. `matches.offered_by` (not
   renamed) records the **last proposer** — i.e. whose turn it now is to act.

2. **Either party may propose from PENDING; only the non-proposer may
   counter-offer from OFFERED; only the non-proposer may accept, and only when
   the proposal is balanced.** Either party may reject from PENDING or OFFERED at
   any time. This prevents self-acceptance and makes balance a hard gate at
   accept, enforced by the backend (a proposer's accept or an unbalanced accept
   returns `400`).

3. **Balance is defined as Σ quantity each side gives being equal *and* > 0.**
   Items may differ between the two sides; only the per-side quantity totals
   must match. Balance is checked by the pure helper `is_balanced(legs,
   user1_id, user2_id)` and required at the accept transition.

4. **Legs accumulate by partial upsert.** A counter-offer is the same `propose`
   operation applied again while in `OFFERED`. Specified legs are upserted (a
   leg submitted with quantity `0` is removed); *unspecified* legs persist
   unchanged. This lets a party add only their-give or only their-receive to move
   the proposal toward balance without re-submitting the whole proposal.

5. **Convert `match_items` from offerer-relative to absolute legs.** The schema
   becomes `(match_id, giver_user_id, merch_id, quantity)` — a leg reads "user G
   gives merch M qty Q" with no direction relative to any offerer. The old
   `owner_id` and `direction` columns are dropped. `giver_user_id` is
   `NOT NULL` with a foreign key to `users`, and `(match_id, giver_user_id,
   merch_id)` is `UNIQUE` so partial upserts accumulate onto one row per leg
   (migration `20260622000000_trade_negotiation.sql`). Existing rows are
   backfilled: `giver_user_id = owner_id` where the old `direction` was `GIVE`,
   else the *other* participant in the match.

6. **Inventory apply is rewritten to giver-absolute deltas.** For each leg, the
   giver takes `−qty TRADE` and the other participant gets `+qty HAVE`. The
   per-user applied flag (`user{1,2}_inventory_applied_at`) is retained so the
   apply step remains idempotent. The apply runs only after `COMPLETED`.

7. **Per-leg want-quantity caps (#294) are enforced on every `propose`**, carried
   over from the prior single-offer flow, in the pure helper `validate_legs`.

## Consequences

**Positive:**

- Negotiation is now possible: parties can iterate toward a mutually acceptable,
  balanced trade instead of a take-it-or-leave-it first offer.
- Balance is enforced as a hard backend invariant at accept, so an unbalanced
  trade can never complete regardless of client behavior.
- The absolute-leg schema is direction-agnostic, which makes the
   alternating-proposal model expressible at all — the same row shape serves the
   opening offer and every counter-offer.
- The accumulating-partial-upsert model means a counter-offer is literally the
  same `propose` endpoint re-entered, so there is one negotiation code path
  rather than separate offer/counter handlers.

**Negative / costs:**

- The `OFFERED` status now serves two roles (opening proposal *and* counter
  proposal), distinguished only by whose turn it is via `offered_by`. Consumers
  must read `offered_by` to know who may act; the status alone no longer tells
  you. This is a minor loss of self-describing state.
- Accumulating partial upserts mean the on-table proposal is the *union* of
  every party's submitted legs across turns. A party cannot implicitly "clear"
  the other side's legs; removal is explicit only (qty 0 on a leg that party now
  controls). This is deliberate but can surprise a reader of the schema.
- The schema migration is irreversible at the column level (`owner_id` /
  `direction` dropped). The backfill is a best-effort reconstruction from the
  old `direction`; any pre-migration rows whose `direction` was ambiguous are
  mapped by the documented rule, and duplicate `(match_id, giver_user_id,
  merch_id)` rows that arise from the old schema's lack of a unique constraint
  are deduplicated by summing quantities into one surviving row before the new
  unique constraint is added.

**Follow-up that occurred after this decision:**

- Issue #303 / PR #306 subsequently **removed the three-mode offer UI** that #297
  had specified (`give-only` / `receive-only` / `both`), keeping only the `both`
  mode plus an in-dialog balance explanation. The accumulating partial-upsert
  *backend* semantics (Decision 4) are unchanged — the three-mode switcher was
  a UI surface over that mechanism, judged more confusing than valuable. This
  ADR records the architectural decisions (state machine, balance, accumulating
  legs, absolute schema); the single-mode UI is the surviving user-facing shape.
- The `userWants` display bug (#295) — a dependency for surfacing receive-side
  candidates — was tracked separately.

## Alternatives Considered

- **Keep the one-shot offer flow (current behavior before #297).** Rejected: it
  allowed no negotiation and enforced no balance, so the first offer was
  take-it-or-leave-it and could complete an unequal trade.

- **Add counter-offers while keeping offerer-relative legs (`owner_id` +
  `direction`).** Rejected: a counter-offer has no natural "offerer" to be
  relative to. Supporting it would have required either re-deriving a synthetic
  offerer per turn or special-casing the meaning of `direction` per state,
  both of which obscure the data model. Absolute legs make a leg self-describing
  ("user G gives merch M qty Q") regardless of who proposed it.

- **Enforce balance by construction (reject unbalanced `propose` calls), not
  only at accept.** Rejected: a counter-offer that is *intentionally* one-sided
  (a party adding only their-give to move toward balance) is a legitimate
  intermediate state. Gating at `propose` would forbid the partial steps that the
  accumulating model exists to support. Balance is therefore required only at
  `accept`, the point where an exchange actually commits.

- **Introduce a distinct `PROPOSED` status separate from `OFFERED`.** Rejected:
  a counter-offer is the same operation as an opening proposal, so a separate
  status would add a state without adding a behavior. Reusing `OFFERED` (with
  `offered_by` indicating the active party) keeps the machine to the minimum
  states that express the behavior.

- **Three user-facing offer modes (`give-only` / `receive-only` / `both`) as a
  first-class UI control.** Initially built in #298, then removed in #306: the
  modes were an implementation detail of the accumulating partial-upsert
  mechanism, not a feature worth a segmented control. Surfacing them confused
  users without enabling anything the `both` view could not. Reverted; recorded
  here so the reversal is not mistaken for an undo of the underlying state
  machine.