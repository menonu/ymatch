# ADR 0010: Inventory Mutual-Capacity Invalidation and Visible `CANCELLED`

- **Status**: Accepted
- **Date**: 2026-07-17
- **Supersedes**: —
- **Related**: Partially revises the UI contract of [ADR 0008](0008-merchandise-deletion-semantics.md) Decision 3 (`CANCELLED` was UI-hidden). Does not reverse merch soft-delete semantics or `CANCELLED` as a system-only match status. Originating issue: [#450](https://github.com/menonu/ymatch/issues/450).

## Context

Matches are created by the periodic matcher when two users have **mutual** complementary inventory in the same event+group: each side has at least one positive `TRADE` that the other `WANT`s (see [06 — Runtime](../architecture/06-runtime.md)).

At decision time:

1. **`POST /api/v1/user/inventory` only upserts** (`InventoryRepository::upsert`). It does not re-evaluate or cancel existing matches.
2. The matching job **only inserts** new `PENDING` rows; it never invalidates stale ones.
3. System cancel exists only for **merch soft-delete** ([ADR 0008](0008-merchandise-deletion-semantics.md)), and only for matches that already have `match_items` rows referencing the deleted merch — pure `PENDING` matches with no legs are left alive.
4. List/UI treat `CANCELLED` as non-active and **hidden** (ADR 0008 Decision 3; `list_for_user` excludes `CANCELLED`; `TradeListScreen` filters it out).

Result: after a match exists, if one party zeros out WANT/TRADE so the pair is no longer mutually tradable (e.g. capacity 2:0 or 1:0), the match row can remain `PENDING` / `OFFERED` / `ACCEPTED` with empty or one-sided candidate lists — a zombie match.

Product intent:

- Invalidate when mutual capacity collapses to **zero on either side**.
- **Allow** unbalanced but still positive capacity (e.g. 2:2 → 2:1).
- Apply to **`PENDING`, `OFFERED`, and `ACCEPTED`**.
- Make **`CANCELLED` visible** so participants understand why a trade left the active lists — without adding a sixth primary tab.

## Decision

### 1. Mutual capacity (cap) definition

For a match between `user1` and `user2` scoped to `(event_id, group_name)` ([ADR 0001](0001-match-scoped-to-item-group.md)), over live merchandise in that group (`is_deleted = false` and `trade_enabled = true`):

```text
cap(userA → userB) = Σ_merch  LEAST( userA.TRADE_qty(merch), userB.WANT_qty(merch) )
                     (missing inventory rows count as 0)

cap₁ = cap(user1 → user2)
cap₂ = cap(user2 → user1)
```

Only `TRADE` and `WANT` participate; `HAVE` does not.

For non-negative integer quantities, `cap(direction) > 0` is equivalent to “there exists at least one merch with positive TRADE∩WANT on that direction.” Cap is the **specified** formulation because it matches the product language (2:1 vs 2:0) and leaves room for future quantity-aware UI or leg trim without changing the cancel predicate. An implementation may use an `EXISTS` form if proven identical and cheaper, as long as tests lock the product rule.

### 2. Invalidation rule

After inventory changes that can affect capacity, re-evaluate each active match involving the acting user:

| Condition | Action |
|-----------|--------|
| `cap₁ > 0` **and** `cap₂ > 0` | Keep match (including 2:2 → 2:1) |
| `cap₁ = 0` **or** `cap₂ = 0` | System-transition to `CANCELLED` |
| Match status ∈ {`COMPLETED`, `REJECTED`, `CANCELLED`} | No-op |

**In-scope statuses for cancel:** `PENDING`, `OFFERED`, `ACCEPTED`.

This is the same transition family as ADR 0008, with an additional cancel cause:

```text
PENDING  ──cancel (system, inventory cap=0)──► CANCELLED
OFFERED  ──cancel (system, inventory cap=0)──► CANCELLED
ACCEPTED ──cancel (system, inventory cap=0)──► CANCELLED
```

`CANCELLED` remains **system-only** (not reachable via user `change_status`). User reject stays `REJECTED`.

Invalidation does **not** require existing `match_items`. A pure `PENDING` match with no legs is cancelled when either cap is zero.

### 3. When to re-evaluate

Run re-evaluation in the **same transaction** as a successful inventory write that can change `WANT` or `TRADE` quantities (including setting quantity to 0), for the upserting `user_id`:

1. Load that user's active matches (`PENDING` / `OFFERED` / `ACCEPTED`).
2. For each, compute `cap₁` / `cap₂` under the post-write inventory snapshot.
3. Cancel those with either cap 0.

`HAVE`-only upserts need not trigger re-evaluation (optional optimization). Merch soft-delete ([ADR 0008](0008-merchandise-deletion-semantics.md)) must remain capable of cancelling matches; align it so **PENDING without legs** that depended on the deleted merch also cancel (either by extending delete cancel beyond `match_items`, or by running the same cap check after delete). Exact merge of delete path vs cap path is an implementation detail as long as both product invariants hold.

### 4. Side effects on cancel

Mirror ADR 0008:

- Set `status = 'CANCELLED'` in the same transaction as the inventory write (or merch delete).
- Insert a **SYSTEM** `messages` row into the match thread so both parties can see why it left the active lists (copy distinct from merch-delete cancel, e.g. an inventory-capacity reason).

Do **not** auto-trim or rewrite `match_items` on partial capacity reduction. If the match is kept but existing legs exceed current WANT, existing propose/accept validation (#294 / [ADR 0002](0002-negotiation-state-machine.md)) continues to reject over-cap accepts.

### 5. UI: make `CANCELLED` visible without a new tab

**Revise ADR 0008 Decision 3** for product surfaces as follows:

| Surface | Behavior |
|---------|----------|
| Match / Offer Out / Offer In / Active | Exclude `CANCELLED` (actionable tabs only) |
| **Done** | Include **`COMPLETED` + `CANCELLED`** |
| Badges / “needs action” counts | Do **not** count `CANCELLED` as actionable |
| New 6th tab | **Do not add** |

`CANCELLED` cards: muted styling, status chip, short reason (inventory vs merch delete if distinguishable), no offer/accept/complete/apply actions. Chat/history may remain open for context (same spirit as historical match detail in ADR 0008).

Optional later rename of Done → History is allowed but not required by this decision.

### 6. API list contract

`MatchRepository::list_for_user` (and any active-count helpers that feed the Done tab) must **return `CANCELLED`** matches for the user. Continue excluding `REJECTED` from the default user list unless a separate decision says otherwise.

Admin list behavior is unchanged unless it already shows all statuses.

## Consequences

**Positive:**

- Zombie matches (one-sided or zero mutual capacity) no longer linger in negotiation states.
- Partial inventory edits that still leave a tradable mutual core (e.g. 2:1) do not force a renegotiation restart.
- `CANCELLED` remains a single system terminal status for both merch delete and inventory invalidation.
- Users can see cancelled history under Done without growing the tab bar.

**Negative / costs:**

- Every WANT/TRADE inventory write must load and re-score active matches (bounded by matches per user; more work than today's upsert).
- ADR 0008's “hide `CANCELLED`” UI contract is **intentionally revised**; frontend and list filters must change in lockstep with the backend.
- Cancelling `ACCEPTED` on inventory change can surprise users who already planned a meetup — accepted as consistent with ADR 0008 item-delete behavior and with “cannot actually trade.”

**Follow-up work required (implementation; not this ADR doc PR):**

- Cap helper + cancel path on the inventory write path; unit tests for 2:1 keep / 2:0 cancel / both-zero cancel.
- Integration tests: upsert WANT/TRADE → cancel `PENDING`/`OFFERED`/`ACCEPTED`; leave `COMPLETED`; SYSTEM message present.
- `list_for_user` includes `CANCELLED`; actionable tabs/filters still exclude it.
- Frontend Done tab renders `CANCELLED`; no new tab; badges unchanged for actionable counts.
- Align merch-delete cancel with legs-less `PENDING` if still a gap.

## Alternatives Considered

- **Boolean mutual path only (`EXISTS` TRADE∩WANT each way).** Equivalent to `cap > 0` for non-negative integer quantities; rejected as the *named* rule because product language is quantity-shaped (2:1 vs 2:0) and cap is a better extension point. Implementation may use `EXISTS` if proven identical and cheaper, as long as tests lock the product rule.

- **Cancel only `PENDING`.** Rejected: `OFFERED`/`ACCEPTED` can be equally untradeable after inventory collapse; leaving them active is more harmful.

- **Cancel on any imbalance (require `cap₁ == cap₂`).** Rejected: forbids legitimate 2:1 residual capacity and fights partial inventory edits.

- **User-driven only (force reject / no system cancel).** Rejected: the counterparty cannot clear the other user's zombie match.

- **Reuse `REJECTED` instead of `CANCELLED`.** Rejected (same as ADR 0008): `REJECTED` is user reject; system invalidation must stay distinct.

- **Sixth tab “Cancelled”.** Rejected: five tabs already scroll on mobile; cancelled is terminal history, not an action queue. Done + chip is enough; split later only if volume warrants.

- **Show `CANCELLED` inside Match/Offer/Active as greyed cards.** Rejected: pollutes actionable tabs and invites confusion with live negotiation.

- **Re-evaluate only on matching job interval.** Rejected: up to ~60s of zombie state and weaker transactional coupling with the write that broke capacity.

## Out of scope

- Auto-adjusting `match_items` quantities when capacity shrinks but stays positive.
- Re-matching the same pair+group after `CANCELLED` (matcher dedup against any existing row remains as today unless separately changed).
- Provisional inventory display for in-progress trades (#427).
- Push notifications beyond the in-thread SYSTEM message.
