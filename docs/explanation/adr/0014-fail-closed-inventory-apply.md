# ADR 0014: Fail-Closed TRADE Capacity (HAVE Optional)

- **Status**: Accepted
- **Date**: 2026-07-22
- **Supersedes**: Partial supersession of [ADR 0009](0009-apply-inventory-decrements-giver-have.md) Consequences (insufficient **TRADE** clamp) only
- **Related**: [Issue #493](https://github.com/menonu/ymatch/issues/493)

## Context

ADR 0009 defined default apply deltas (giver TRADE− and HAVE−; receiver HAVE+) and documented that insufficient stock was **clamped at 0** via `GREATEST(…, 0)`, with hard-fail left as a separate decision.

In parallel, offer/accept only capped legs by the **receiver's WANT** (`validate_legs`). They did not require the **giver** to still hold enough **TRADE**. Combined with silent TRADE clamp, an oversubscribed proposal could complete and under-decrement TRADE while the receiver still received full HAVE+, producing asymmetric trade inventory.

**HAVE** is optional user bookkeeping for ownership convenience. It is **not** required to negotiate or complete a trade. Default apply still *tries* to decrement HAVE when present (ADR 0009), but short or missing HAVE must not block trade validity.

## Decision

1. **Offer and accept** re-check giver **TRADE** for each positive leg, aggregated per `(giver, merch_id)`:
   - Giver `TRADE ≥ qty` (missing rows count as 0).
   - Fail with **400** and do not mutate match state.
   - **HAVE is not checked** at offer or accept.

2. **Apply** fail-closed for **TRADE only**:
   - TRADE decrement requires `quantity >= delta` on an existing TRADE row; otherwise **400**, transaction rolls back.
   - HAVE decrement (when not skipped) remains **best-effort**: clamp at 0 if short/missing. Short HAVE never fails apply.
   - Receiver HAVE increments and `skip_have_decrement` are unchanged.

3. Silent under-decrement of **TRADE** is **not** supported. Soft clamp of **HAVE** is intentional because HAVE is convenience, not a trade pool.

## Consequences

**Positive:**

- Agreed trade quantities match TRADE inventory after successful apply.
- Oversubscribed TRADE offers/accepts fail early; apply is a second gate if TRADE changes after accept.
- Users can trade with TRADE only; HAVE remains optional.

**Negative / costs:**

- Default apply may leave HAVE out of sync with physical reality if the user never tracked HAVE (or under-tracked it). That is accepted for a convenience field.
- Clients that relied on silent TRADE clamp now see 400 on oversubscription.

## Alternatives Considered

- **Fail-closed on HAVE as well.** Rejected: HAVE is not required for trade; forcing it would break TRADE-only inventories.
- **Keep silent TRADE clamp; document partial apply.** Rejected: asymmetric TRADE vs agreed legs is incorrect domain behavior.
- **Check TRADE only at apply.** Rejected as sole gate: worse UX; accept would still admit impossible trades. Apply remains fail-closed *in addition* to offer/accept.
