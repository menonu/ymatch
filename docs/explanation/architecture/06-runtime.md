# 06 — Runtime view

Key runtime scenarios. State machines and permission matrices are defined in
ADRs/reference; this page shows how they execute end-to-end.

Diagrams: [D2](https://d2lang.com/) sources + committed SVG in [`diagrams/`](diagrams/).

## UC overview (product flows)

| ID | Flow | Primary actors |
|----|------|----------------|
| UC-01 | Manage inventory for an event (HAVE / WANT / TRADE) | User |
| UC-02 | System creates a PENDING match from complementary lists | Matching job |
| UC-03 | Negotiate (propose / counter / accept / reject) | Two matched users |
| UC-04 | Complete trade and apply inventory | Users + lifecycle service |
| UC-05 | Chat / share location to meet | Matched users |
| UC-06 | Curate event & merch (RBAC) | Creator / editor / staff |

## Auth and session

![Auth and session](diagrams/06-auth-sequence.svg)

Source: [`diagrams/06-auth-sequence.d2`](diagrams/06-auth-sequence.d2)

- Guest path minimizes signup friction for event-day use.
- `User.role` on the wire is **derived** from global `user_roles` at read time
  ([ADR 0006](../adr/0006-derive-user-role-from-user-roles.md)).

## Matching job

Runs inside the API process on an interval (`MATCHING_INTERVAL_SECONDS`).

![Matching job](diagrams/06-matching-flow.svg)

Source: [`diagrams/06-matching-flow.d2`](diagrams/06-matching-flow.d2)

Matching only creates **PENDING** opportunities. It does not move inventory.
Scope rules: [ADR 0001](../adr/0001-match-scoped-to-item-group.md).

## Trade negotiation and completion

State machine (simplified from [ADR 0002](../adr/0002-negotiation-state-machine.md)):

![Trade negotiation state machine](diagrams/06-negotiation-state.svg)

Source: [`diagrams/06-negotiation-state.d2`](diagrams/06-negotiation-state.d2)

![Negotiate and complete sequence](diagrams/06-negotiation-sequence.svg)

Source: [`diagrams/06-negotiation-sequence.d2`](diagrams/06-negotiation-sequence.d2)

Enforcement highlights:

- Only the **non-proposer** may accept; balance Σ qty each side gives equal and > 0.
- Legs are **absolute** (`giver_user_id`, merch, qty), not offerer-relative.
- Apply is idempotent per user side once marked applied.

## Inventory update (user-driven)

Users edit inventory on event detail / items UI →
`UserInventoryNotifier` / inventory API → `InventoryRepository`.

Statuses used in product logic:

| Status | Meaning |
|--------|---------|
| `HAVE` | Owned (including post-trade storage) |
| `WANT` | Desired; drives matching as demand |
| `TRADE` | Offered into the matching pool as supply |

## Messaging

After a match exists, users open `ChatScreen` → messages API →
`MessageRepository`. Location payloads are message content, not a separate geo
service.

## Privileged operations

![Privileged operations (RBAC)](diagrams/06-rbac-sequence.svg)

Source: [`diagrams/06-rbac-sequence.d2`](diagrams/06-rbac-sequence.d2)

Catalog: [permissions reference](../../reference/permissions.md),
[ADR 0004](../adr/0004-rbac-permission-model.md),
[ADR 0005](../adr/0005-merch-create-permission.md).
