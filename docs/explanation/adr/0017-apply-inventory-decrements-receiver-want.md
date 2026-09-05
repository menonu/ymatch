# ADR 0017: Apply Inventory Decrements Receiver WANT

- **Status**: Accepted
- **Date**: 2026-09-05
- **Supersedes**: Partial supersession of [ADR 0009](0009-apply-inventory-decrements-giver-have.md) (receiver apply deltas only; giver TRADE/HAVE and `skipHaveDecrement` unchanged)

## Context

ADR 0009 defined persist-on-apply as giver `TRADE −qty` / `HAVE −qty` and receiver `HAVE +qty`. **WANT was not written.** That matched an early model where WANT was only a matching/offer cap (demand pool), not something settlement was supposed to consume.

In use, that gap is wrong. After a physical hand-off the receiver no longer wants the units they just got; leftover WANT keeps them matchable for the same merch ([ADR 0010](0010-inventory-mutual-capacity-invalidation.md) mutual cap still sees demand). Projected inventory (#427) already showed receiver `WANT −qty` as display-only, so Detailed view dropped from `1(0)` to `1` after apply — HAVE and TRADE stuck, WANT bounced back.

Issue [#579](https://github.com/menonu/ymatch/issues/579) reports this as a product bug: 在庫を更新 updates 所持 and 譲 but not 求.

WANT is still a trade-capacity field (unlike HAVE). Offer/accept already require receiver `WANT ≥ qty`. After `COMPLETED`, though, the exchange has happened; a user who lowered WANT in the meantime must still be able to apply.

## Decision

1. **Receiver apply:** for each leg where the requesting user is the receiver, decrement **WANT** by `qty` in addition to incrementing HAVE. Giver WANT is unchanged.

2. **Clamp, do not fail-close:** insufficient or missing WANT clamps at 0 and never returns 400. Missing WANT is a no-op (no synthetic row). This matches HAVE's best-effort clamp, not TRADE's fail-closed gate ([ADR 0014](0014-fail-closed-inventory-apply.md)). Physical settlement must not be blocked by post-complete demand edits.

3. **No skip flag.** HAVE remains the only apply-time opt-out (`skipHaveDecrement`). WANT is the matching demand pool; leaving it after receiving is not a supported inventory style.

4. **Capacity re-evaluation:** a successful WANT decrement re-evaluates the applying user's other active matches in the same transaction ([ADR 0010](0010-inventory-mutual-capacity-invalidation.md)), same as TRADE decrement.

5. **Projection:** receiver WANT− is the same rule as apply, not display-only. #427 projected quantities continue to use default apply (HAVE skip still apply-time only).

## Consequences

**Positive:**

- Post-apply inventory matches physical settlement for HAVE, TRADE, and WANT.
- Projected `1(0)` on WANT becomes `0` after apply instead of snapping back to `1`.
- Remaining demand no longer keeps the user matchable for merch they already received.

**Negative / costs:**

- Apply may leave WANT at 0 when the user still wants more copies than this trade delivered only if they had exactly `qty` listed; users who under-listed WANT relative to what they received clamp to 0 (accepted; same class of drift as short HAVE).
- Existing clients that applied without expecting WANT mutation now see WANT drop. That is the intended default; there is no compatibility flag.

## Alternatives Considered

- **Keep WANT display-only forever.** Rejected: contradicts user expectation after 在庫を更新 and leaves stale demand in the matcher.
- **Fail-closed WANT at apply (TRADE-style).** Rejected: `COMPLETED` means the hand-off already happened; a 400 because the user edited WANT afterward would strand inventory apply.
- **Skip-WANT checkbox (HAVE-style).** Rejected: WANT is matching demand, not optional bookkeeping. Users who still want more copies should raise WANT after apply, not skip the decrement.
- **Decrement WANT at accept/complete instead of apply.** Rejected: apply remains the deliberate inventory write; projection already previews the decrement.
