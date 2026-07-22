# ADR 0009: Apply Inventory Decrements Giver HAVE by Default

- **Status**: Accepted (insufficient-stock clamp superseded in part by [ADR 0014](0014-fail-closed-inventory-apply.md))
- **Date**: 2026-07-15
- **Supersedes**: Partial supersession of [ADR 0002](0002-negotiation-state-machine.md) § Decision point 6 (apply-inventory deltas only)

## Context

ADR 0002 defined inventory apply after `COMPLETED` as giver-absolute leg deltas: for each leg `(giver, merch, qty)`, the **giver's TRADE decreases by qty** and the **receiver's HAVE increases by qty**. The giver's **HAVE was left unchanged**.

That matched an early model where TRADE was the only "pool" that leave-the-table quantities lived in. In practice users also track **owned (HAVE)** as physical possession. After a real hand-off, both "available to trade" and "owned" for the given item should drop for the giver. Leaving HAVE untouched made post-trade inventory feel wrong (e.g. HAVE=2, TRADE=1, give 1 → TRADE=0 but HAVE still 2).

Some users still want the old behavior when they manage HAVE separately from TRADE. That must remain available as an explicit opt-out, not the default.

## Decision

1. **Default apply (giver):** for each leg where the requesting user is the giver, decrement **both** `TRADE` and `HAVE` by `qty` (each clamped at 0). Receiver still gets `HAVE + qty` only.

2. **Opt-out:** `ApplyInventoryRequest.skip_have_decrement` (proto3 JSON: `skipHaveDecrement`). When `true`, the giver's HAVE is left unchanged (ADR 0002 behavior). Default is `false`.

3. **UI:** the Done-tab "Update Inventory" flow presents a confirmation dialog with an unchecked checkbox labeled so the user can opt out of HAVE updates before apply.

4. **Repository:** `apply_trade_delta` accepts a **signed** `delta_have` (positive = increment, negative = decrement, zero = skip) so one code path covers giver HAVE− and receiver HAVE+.

5. Projected inventory display (#427) follows this **default** rule only; the skip flag is apply-time and is not reflected in always-on projected quantities.

## Consequences

**Positive:**

- Post-trade inventory matches physical ownership for the common case.
- Legacy TRADE-only decrement remains available without a separate API.
- Signed HAVE delta keeps the repository API small.

**Negative / costs:**

- Existing clients that call apply without the new field get the **new** default (HAVE decreases). That is intentional.
- Insufficient HAVE no longer blocks apply (clamped at 0), same as TRADE; hard-fail would be a separate decision.
- ADR 0002's apply wording is no longer the full truth for HAVE; this ADR owns the current policy.

## Alternatives Considered

- **Keep TRADE-only decrement forever.** Rejected: mismatches user expectation of ownership after a hand-off.
- **Always decrement HAVE with no opt-out.** Rejected: some inventories treat HAVE and TRADE as independently managed.
- **Separate endpoints for "full apply" vs "trade-only apply".** Rejected: one flag on the existing apply endpoint is enough.
- **Decrement HAVE at offer/accept time instead of apply.** Rejected: apply remains the deliberate inventory write; soft-reserve / projected display is #427.
