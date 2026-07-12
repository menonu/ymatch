# 01 — Introduction and goals

## What ymatch is

**ymatch** is a merchandise trading platform that helps fans **manage event
merch inventory** (what they own and what they want) and **execute physical
exchanges** with other users when the system finds compatible trades.

Physical exchange is first-class: matching only identifies partners; users still
meet (or ship) offline. In-app **messaging** and optional **location sharing**
exist so partners can coordinate the hand-off.

## Goals

| ID | Goal |
|----|------|
| G1 | Let users organize merch around **events** and **item groups** (e.g. photo sets for a live show). |
| G2 | Let users track personal inventory as **HAVE / WANT / TRADE** quantities per merch item. |
| G3 | Automatically **discover mutual trade opportunities** within a single item group ([ADR 0001](../adr/0001-match-scoped-to-item-group.md)). |
| G4 | Support **balanced negotiation** (propose / counter / accept) before a trade is finalized ([ADR 0002](../adr/0002-negotiation-state-machine.md)). |
| G5 | Provide a simple client (Flutter web + mobile targets) against one central backend. |
| G6 | Run affordably in production (OCI Always Free–oriented stack) and fully offline-local for development. |

## Non-goals (current)

- Real-time multiplayer or live auction mechanics.
- Payment / escrow for money; trades are inventory-for-inventory.
- Multi-tenant SaaS isolation beyond a single shared deployment per environment.

## Stakeholders

| Stakeholder | Interest |
|-------------|----------|
| **End user (fan)** | Find trades, manage inventory, chat with partners at events. |
| **Event creator / editor** | Curate events, groups, and merch catalog for an event ([ADR 0005](../adr/0005-merch-create-permission.md)). |
| **Moderator / admin** | Platform safety (bans, elevated deletes, admin dashboard). |
| **Operator / maintainer** | Deploy, backup, monitor, recover the OCI stack. |
| **Contributor** | Change code safely via trunk-based PRs and tests. |

## Top-level requirements (summary)

Absorbed from early product notes; detail lives in ADRs and reference docs where
behavior is precise.

### Functional

| ID | Requirement |
|----|-------------|
| FR-01 | Users can create and browse **events**. |
| FR-02 | Merchandise is catalogued per event, optionally with photos, and belongs to an **item group**. |
| FR-03 | Users manage **inventory** per merch item (quantities and HAVE / WANT / TRADE). |
| FR-04 | The system **matches** complementary TRADE/WANT pairs within the same group. |
| FR-05 | Matched users **negotiate** a balanced multi-leg trade, then mark complete and apply inventory. |
| FR-06 | Matched users can **message** and share location to coordinate physical exchange. |
| FR-07 | Platform roles (user / moderator / admin) and event roles (creator / editor) gate privileged actions via **RBAC** ([ADR 0004](../adr/0004-rbac-permission-model.md)). |

### Quality attributes (summary)

| ID | Attribute | Target (pragmatic) |
|----|-----------|-------------------|
| QA-01 | Multi-platform client | Flutter (web primary in prod; iOS/Android capable). |
| QA-02 | Deployability | Local Docker + single-VM OCI compose for staging/prod. |
| QA-03 | Correctness of trades | State machine + DB transactions; unit + integration + e2e coverage. |
| QA-04 | Public-repo safety | No secrets in git; see [security.md](../security.md). |
| QA-05 | i18n | English and Japanese UI strings. |

See [09 — Quality](09-quality.md) for testing and gates.
