# ADR 0018: Per-User Match Completion

- **Status**: Accepted
- **Date**: 2026-10-07
- **Supersedes**: None (extends the `ACCEPTED → COMPLETED` step of [ADR 0002](0002-negotiation-state-machine.md))

## Context

A match had a single shared `status`. When either participant pressed "Mark complete", `ACCEPTED → COMPLETED` moved the card from In progress to Done **for both users at once**. The counterpart lost the card from their In progress list without acting, often before they had finished or confirmed the hand-off, which caused confusion.

Inventory apply was already per-user (`user{1,2}_inventory_applied_at`); completion was the one remaining shared step at the end of the lifecycle.

## Decision

1. **Per-user completion flags.** `matches` gains `user1_completed_at` / `user2_completed_at`. Each participant completes on their own side; a repeat by the same user returns `409 Conflict`, and a non-participant gets `403`.

2. **The first completion still freezes the match.** The first participant to complete flips the shared `status` from `ACCEPTED` to `COMPLETED` and stamps only their own flag. The second participant's completion stamps their flag and leaves `status` as `COMPLETED`. A physical exchange has happened once either side completes, so system cancel ([ADR 0010](0010-inventory-mutual-capacity-invalidation.md)) and rematch ([ADR 0012](0012-rematch-after-reject-or-cancel.md)) must not touch the row; keeping `COMPLETED` as the shared status preserves those guards unchanged.

3. **Clients route tabs on the caller's own flag.** `TradeMatch` carries `completed_by_me` and `counterpart_completed` (scoped to the listing caller, like `inventory_applied`). In progress = `ACCEPTED`, or `COMPLETED` and not `completed_by_me`; Done = `COMPLETED` and `completed_by_me` (plus `CANCELLED`). The in-progress notification count follows the same rule.

4. **Apply requires the caller's own completion.** Inventory apply returns `400` until the requesting user has completed on their side, so "apply" always follows that user's own "complete".

5. **Backfill.** Existing `COMPLETED` rows are marked completed for both users (the old shared semantics), using each user's apply time when present, else the migration time.

## Consequences

**Positive:**

- Each user decides when the trade is done for them; the counterpart's list no longer changes under them.
- Cancel, rematch, projection (#427) and matcher queries keep keying on the shared `status`, so no other lifecycle rule changes.

**Negative / costs:**

- `status = 'COMPLETED'` no longer means "done for both". Code that needs the viewer's perspective must read the per-user flags (tab routing, in-progress counts).
- One extra step for the second user: they must press complete before they can apply inventory.

## Alternatives Considered

- **Keep `ACCEPTED` until both complete.** Rejected: a half-completed match would stay cancellable by system capacity re-evaluation, including the re-evaluation triggered by the first user's own apply (TRADE/WANT decrement), which would cancel a trade that physically happened. Guarding that would have to touch cancel, rematch, projection and matcher queries.
- **New intermediate status (e.g. `PARTIALLY_COMPLETED`).** Rejected: every status filter (cancel, rematch, projection, matcher, counts, clients) would need to learn it, for no behavior the per-user flags don't already give.
- **Client-only "hide" flag.** Rejected: state would not survive devices, and the badge count would still be wrong.
