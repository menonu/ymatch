# ADR 0012: Rematch After Reject or Cancel (Reopen PENDING with Prior-History Annotation)

- **Status**: Accepted
- **Date**: 2026-07-18
- **Supersedes**: —
- **Related**: Partially revises the “no rematch” product outcome implied by matcher dedup + unique pair+group index as left **out of scope** in [ADR 0010](0010-inventory-mutual-capacity-invalidation.md) § Out of scope (“Re-matching the same pair+group after `CANCELLED`”). Does **not** reverse ADR 0010 cancel rules, ADR 0001 pair+group scope, or ADR 0002 negotiation semantics. Originating issue: [#474](https://github.com/menonu/ymatch/issues/474).

## Context

[ADR 0001](0001-match-scoped-to-item-group.md) scopes negotiation to **one match per** `(user1, user2, event_id, group_name)`. Multi-item mutual inventory (e.g. 2:2) is negotiated as legs on that **single** match, not as multiple matches.

At decision time:

1. The periodic matcher inserts a `PENDING` match only when **no** `matches` row exists for that pair+group — **status is ignored**.
2. Migration `20260704000000` enforces the same with unique index `idx_matches_unique_pair_group` (canonical pair + event + group), also **status-agnostic**.
3. User reject sets `REJECTED` ([ADR 0002](0002-negotiation-state-machine.md)); system invalidation sets `CANCELLED` ([ADR 0008](0008-merchandise-deletion-semantics.md), [ADR 0010](0010-inventory-mutual-capacity-invalidation.md)). Both are terminal: the row remains.
4. ADR 0010 explicitly left rematch after `CANCELLED` **out of scope**.

**Product problem:** if A and B reject a match, or the system cancels it (e.g. temporary inventory zero-cap), and they later (or still) have mutual TRADE/WANT in the same group, they **never** get a fresh negotiation opportunity. The pair+group is a permanent tombstone.

**Product intent (this ADR):**

- After `REJECTED` or `CANCELLED`, if the pair is mutually matchable again (or still), **rematch**.
- The opportunity should surface again as **`PENDING`** in the Match tab (actionable).
- Participants must see that this is **not** a brand-new first meeting — **prior-history annotation** (e.g. “rejected before”, “cancelled before”).

## Decision

### 1. Rematch is allowed only from terminal non-completion statuses

| Prior status | Eligible for rematch? |
|--------------|------------------------|
| `REJECTED` | **Yes** |
| `CANCELLED` | **Yes** |
| `COMPLETED` | **No** |
| `PENDING` / `OFFERED` / `ACCEPTED` | N/A (already active; do not create a second match) |

`COMPLETED` stays a hard end for that pair+group for this product cycle: inventory apply already moved stock; a new trade relationship would require a separate future decision (not this ADR).

### 2. Rematch reopens the **same** match row (does not insert a second row)

Keep ADR 0001’s **one row per pair+group** and the existing unique index.

When rematch fires:

1. **`status` → `PENDING`**
2. Clear negotiation state: `offered_by = NULL`; delete all `match_items` for the match
3. Ensure apply flags remain unset / irrelevant (`user{1,2}_inventory_applied_at` stay null for non-completed history; do not invent apply state)
4. Preserve **`matches.id`** so chat (`messages`) and history stay on the same thread
5. Record rematch metadata (see §3)
6. Append a **SYSTEM** message to the match thread documenting the rematch (reason category: prior reject vs prior cancel)

Do **not** delete the match row and re-insert. Insert would fight the unique index and would orphan or split chat history.

### 3. Prior-history annotation (required)

Rematch must be **visible**, not silent.

**Stored fields** (names illustrative; exact columns in implementation):

| Concept | Purpose |
|---------|---------|
| `rematch_count` (int, default 0) | Times this pair+group has been reopened; increment on each rematch |
| `last_terminal_status` (`REJECTED` \| `CANCELLED` \| null) | Status immediately before the latest reopen |
| `last_terminal_at` (timestamptz, nullable) | When that terminal status was entered (or when rematch overwrote it — pick one and test-lock it) |

On first-ever create, these stay zero/null. On each rematch, set `last_terminal_status` from the status being left, bump `rematch_count`, update timestamps as specified by implementation tests.

**API / UI contract:**

- List/detail for a rematched `PENDING` match **exposes** enough fields for clients to show a chip or subtitle, e.g.:
  - “Rejected before” when `last_terminal_status = REJECTED`
  - “Cancelled before” when `last_terminal_status = CANCELLED`
  - Optional: rematch count when `rematch_count > 1` (“Rejected before · 2×”)
- Actionable tabs treat the match as normal `PENDING` (Reject / Make Offer).
- Done tab: once rematched, the match **leaves** the terminal Done presentation and returns to Match (same as any other `PENDING`). Historical SYSTEM lines remain in chat.

Localization strings and exact copy are implementation details; the **requirement** is that users can tell a rematch from a first match.

### 4. When rematch is evaluated (eligibility predicate)

Use the **same mutual-capacity idea** as matching / ADR 0010:

```text
cap(A → B) > 0  AND  cap(B → A) > 0
```

over live, trade-enabled merch in the match’s `(event_id, group_name)`, with missing inventory as 0. `HAVE` does not participate.

**When to run the check:**

1. **Primary:** the periodic matching job. On each candidate pair+group that is mutually matchable:
   - no row → **insert** `PENDING` (today’s behavior);
   - row in `REJECTED` or `CANCELLED` → **reopen** per §2–3;
   - row in active or `COMPLETED` → **skip**.
2. **Optional optimization (not required):** inventory upsert paths may call the same reopen helper when caps restore; correctness must not depend on it if the matcher interval is running.

There is **no** requirement that inventory *changed* after the terminal status. If A rejects while still mutual, the next successful matcher pass may reopen the match as `PENDING` with “rejected before.” That is intentional: reject is “not this negotiation,” not “never again with this person in this group,” unless they still fail mutual capacity.

### 5. What rematch does *not* do

- Does not create a second concurrent match for the same pair+group.
- Does not rematch from `COMPLETED`.
- Does not auto-propose legs or restore previous `match_items`.
- Does not delete chat history; prior offers/rejects remain readable via messages / SYSTEM lines.
- Does not change user-driven reject → `REJECTED` or system cancel → `CANCELLED` rules (ADR 0002 / 0008 / 0010).
- Does not require a cooldown between reject and rematch (may be added later as product tuning).

### 6. State machine (extension)

```text
PENDING ──reject──► REJECTED ──rematch (caps mutual)──► PENDING
OFFERED ──reject──► REJECTED ──rematch (caps mutual)──► PENDING

PENDING / OFFERED / ACCEPTED ──system cancel──► CANCELLED
CANCELLED ──rematch (caps mutual)──► PENDING

COMPLETED  (no rematch edge)
```

`REJECTED` and `CANCELLED` remain user- vs system-terminal **until** rematch; they are no longer permanent tombs for the pair+group.

## Consequences

**Positive:**

- Users can try again after reject or after a capacity-driven cancel once lists support mutual trade again (or still).
- One row per pair+group remains (ADR 0001 + unique index); no schema fight.
- Chat continuity + explicit annotation avoid “why did this match reappear?” confusion.
- Aligns reject with “decline this round,” not “block this partner in this group forever.”

**Negative / costs:**

- Matcher logic grows: update-path for terminal rows, not only insert-if-absent.
- Schema/API/proto surface for annotation fields; frontend chip on Match cards.
- Immediate re-appearance after reject (while still mutual) may surprise users; mitigated by annotation and by the existing matcher interval delay. Product may later add cooldown if needed.
- Done-tab history of a cancelled/rejected match is ephemeral for that card once rematched (status is live again); thread SYSTEM messages remain the durable audit trail.

**Follow-up work (implementation, not this ADR body):**

1. Migration: annotation columns + defaults.
2. Matcher: reopen branch + tests (reject → rematch; cancel → rematch; completed → no rematch; active → no duplicate).
3. Proto/API: expose annotation fields on `TradeMatch`.
4. Flutter: Match-tab chip/subtitle for prior history; i18n.
5. SYSTEM message copy for rematch (distinct from merch-delete / capacity-cancel reasons).
6. Docs: [06 — Runtime](../architecture/06-runtime.md) matching flowchart and state diagram.

## Alternatives Considered

- **Keep permanent tombstone (status quo).** Rejected: blocks legitimate second chances after reject or temporary cancel; user explicitly wants rematch.
- **Insert a new match row per rematch; unique index only on “active” statuses.** Partial unique index is viable but splits chat threads, multiplies Done history, and weakens “one negotiation unit per pair+group.” Reopen is simpler and preserves ADR 0001’s single-container model.
- **Delete terminal row so the next matcher insert looks “first time.”** Rejected: loses id continuity, messages, and any annotation unless rebuilt from side tables; needless churn vs UPDATE.
- **Rematch only after inventory change, never while still mutual after reject.** Rejected for v1: harder to define “change,” and users who reject by mistake would need an arbitrary inventory tweak to meet again. Annotation + interval is enough friction for now.
- **Rematch after `COMPLETED` as well.** Rejected for this ADR: completion + apply is a successful trade; rematching completed pairs needs separate product rules (restock, new want, etc.).
- **User-only rematch button (“Try again”) instead of automatic.** Rejected as sole mechanism: system cancel recovery would still need automation; automatic reopen on mutual capacity matches how first matches are created. A manual button could be additive later.
- **Soft annotation only via SYSTEM message, no structured fields.** Rejected as sole mechanism: list cards need structured fields without opening chat; SYSTEM message remains required *in addition* for thread audit.
