# 04 — Solution strategy

High-level technology and design choices. Decisions with lasting impact are
recorded as ADRs; this page is the map, not the full rationale.

## Technology choices

| Layer | Choice | Why (short) |
|-------|--------|-------------|
| Backend language | **Rust** (Axum, SQLx, Tokio) | Strong typing, async performance, safe concurrency for a small API service. |
| Database | **PostgreSQL 16** | Relational integrity for inventory, matches, RBAC; mature ops story. |
| API style | **JSON REST** + **protobuf** models | Simple HTTP for Flutter; shared schema via `proto/models.proto`. |
| Frontend | **Flutter** (Riverpod, GoRouter) | One codebase for web (prod) and mobile targets; reactive UI state. |
| Edge / TLS | **Caddy** + nip.io | Automatic HTTPS on Always Free VMs without a separate cert pipeline. |
| Packaging | **Docker Compose** on one VM | Matches operational capacity; identical prod/staging stacks. |
| IaC | **Terraform** (OCI + New Relic modules) | Reproducible VMs/network; secrets via TF_VAR / gitignored tfvars. |

## Architectural patterns

### Backend layering

```
HTTP handlers  →  access control + domain services (e.g. trade lifecycle)
               →  domain persistence (SQL)
               →  PostgreSQL
```

**Target shape** (most product paths):

- **Handlers** parse input, apply entry gates, map results — prefer no domain SQL.
- **Persistence** owns SQL per domain (concrete repository modules; transactional
  methods use a shared executor pattern).
- **Services** own multi-step rules (active/ban gate, RBAC checks, trade
  negotiation and inventory apply).

**Known exceptions on `main`:** group create/transfer still open transactions
in handlers; the background **matching job** also issues raw SQL rather than
going through repositories. Treat those as follow-up cleanup (#497), not the
target. (Event create/transfer transactions live in `EventService`; global
search merch SQL lives in `MerchandiseRepository::search`.)

See [05 — Building blocks](05-building-blocks.md) for the conceptual module map
(not a source-tree listing).

### Frontend layering

```
Screens / navigation  →  app state  →  API client  →  Backend
```

- **App state** holds session and async catalog/trade data and drives mutations.
- **API client** speaks HTTPS JSON using shared protobuf wire shapes.

### Domain strategies (see ADRs)

| Topic | Strategy | ADR |
|-------|----------|-----|
| Match scope | One match = one item group within an event | [0001](../adr/0001-match-scoped-to-item-group.md) |
| Negotiation | Alternating propose/counter; accept only if balanced | [0002](../adr/0002-negotiation-state-machine.md) |
| JP font size | Subset WOFF2 committed; avoid full TTF download friction | [0003](../adr/0003-subset-woff2-japanese-font.md) |
| Authorization | RBAC roles/permissions global + event scopes | [0004](../adr/0004-rbac-permission-model.md) |
| Merch create | Gated by `merch.create` (curated catalog) | [0005](../adr/0005-merch-create-permission.md) |
| User.role field | Derived from `user_roles` at read time | [0006](../adr/0006-derive-user-role-from-user-roles.md) |
| Apply HAVE | Default: giver HAVE− on apply; opt-out flag | [0009](../adr/0009-apply-inventory-decrements-giver-have.md) |
| Capacity cancel | Zero mutual TRADE∩WANT → system CANCELLED | [0010](../adr/0010-inventory-mutual-capacity-invalidation.md) |
| Trade capacity | Giver TRADE gates offer/accept/apply; HAVE optional | [0014](../adr/0014-fail-closed-inventory-apply.md) |

Canonical narrative for **HAVE / WANT / TRADE** roles and gates:
[06 — Runtime → Inventory status semantics](06-runtime.md#inventory-status-semantics).

## Matching strategy

A **background task** in the API process (`MATCHING_INTERVAL_SECONDS`) runs
`matching::run_matching_algorithm`:

1. Scan **WANT** rows (active merch, non-banned users, non-null group).
2. Find partners with **TRADE** on the wanted merch.
3. Require reciprocal **TRADE/WANT** inside the **same (event_id, group_name)**.
4. Insert a **PENDING** match when none already covers the pair in that group.

Only **TRADE** and **WANT** participate in matching. **HAVE** is ignored by the
matcher (optional ownership bookkeeping — see [inventory semantics](06-runtime.md#inventory-status-semantics)).

Negotiation and inventory effects are **not** in the matcher — they live in
`MatchLifecycleService` after users act (see [06 — Runtime](06-runtime.md)).

## Image strategy

`ImageStorage` trait with a single supported backend today:

| Backend | Implementation | Used for |
|---------|----------------|----------|
| Local files (only) | Files under `UPLOAD_DIR`, served as `/uploads/...` | Dev + current prod/staging |

A former Firebase/GCS path was removed (#458). The trait is kept so a future
object-store backend can plug in without changing the image HTTP API.

## Auth strategy

There is **no JWT / bearer session** today. Identity is **client-asserted**:

- **Guest sessions** via device UUID (`POST /api/v1/auth/guest`) return a `User`
  JSON body (low-friction entry).
- **Registered users** sign up / log in with password; handlers also return
  `User` JSON only.
- The Flutter client stores the user (e.g. local preferences) and passes
  **`user_id`** (body or query) on subsequent mutations/reads.
- **Privileged catalog/admin paths** (events, merch, groups, admin, …) typically
  call the active/ban gate then RBAC permission checks.
- **Trade / inventory paths** usually gate on **match participation** or ownership
  inside the lifecycle/persistence logic, not the full ban+RBAC sequence on every
  call.
- Admin UI is gated on an elevated global role derived for the wire `User.role`
  field ([ADR 0006](../adr/0006-derive-user-role-from-user-roles.md)).

This is **not** cryptographic session authentication: any client that can guess
or supply another user's id can attempt their actions until participation/RBAC/ban
checks reject them. Treat stronger authn as a future hardening item if the threat
model requires it. Wire shapes: [API spec](../../reference/api_spec.md).
