# ADR 0014: Fail-Closed Inventory Apply (No Silent Clamp)

- **Status**: Accepted
- **Date**: 2026-07-22
- **Supersedes**: Partial supersession of [ADR 0009](0009-apply-inventory-decrements-giver-have.md) Consequences (insufficient TRADE/HAVE clamp) only
- **Related**: [Issue #493](https://github.com/menonu/ymatch/issues/493)

## Context

ADR 0009 defined default apply deltas (giver TRADE− and HAVE−; receiver HAVE+) and documented that insufficient stock was **clamped at 0** via `GREATEST(…, 0)`, with hard-fail left as a separate decision.

In parallel, offer/accept only capped legs by the **receiver's WANT** (`validate_legs`). They did not require the **giver** to still hold enough TRADE (or HAVE for default apply). Combined with silent clamp, an oversubscribed proposal could complete and under-decrement one side while the other still received full HAVE+, producing asymmetric inventory.

## Decision

1. **Offer and accept** re-check giver supply for each positive leg, aggregated per `(giver, merch_id)`:
   - Giver `TRADE ≥ qty` always.
   - Giver `HAVE ≥ qty` as well (default apply decrements HAVE per ADR 0009). Missing rows count as 0.
   - Fail with **400** and do not mutate match state.

2. **Apply** is **fail-closed**:
   - TRADE decrement requires `quantity >= delta` on an existing TRADE row.
   - HAVE decrement (when not skipped) requires `quantity >= |delta|` on an existing HAVE row.
   - On failure: **400**, no partial inventory write (transaction rolls back). No `GREATEST` clamp on decrements.
   - Receiver HAVE increments and `skip_have_decrement` TRADE-only apply are unchanged.

3. Partial-apply / silent under-decrement is **not** a supported product policy.

## Consequences

**Positive:**

- Completed trades that successfully apply leave inventory consistent with agreed leg quantities.
- Oversubscribed offers are rejected early (UX); accept is a second gate if inventory changes mid-negotiation.
- Apply remains the hard safety net if state raced after accept.

**Negative / costs:**

- Users who track TRADE without HAVE must either set HAVE for default apply or use `skip_have_decrement` at apply (and still need sufficient TRADE). Negotiation requires HAVE under the default path.
- Existing clients that relied on silent clamp will now see 400 on oversubscription.

## Alternatives Considered

- **Keep silent clamp; document partial apply.** Rejected: asymmetric inventory is incorrect domain behavior, not a deliberate partial-fulfillment feature.
- **Check only at apply.** Rejected as sole gate: worse UX; accept would still admit impossible trades. Apply remains fail-closed *in addition* to offer/accept.
- **Hard-reserve inventory at offer.** Rejected for this issue: larger product change; soft projection remains separate (#427).
