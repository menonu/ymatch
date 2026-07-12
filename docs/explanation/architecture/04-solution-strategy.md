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
HTTP handlers  →  services (PermissionPolicy, MatchLifecycleService, RbacService)
               →  repositories (SQL, concrete structs + generic Executor)
               →  PostgreSQL
```

- **Handlers** parse input, call services/repos, map errors — no business SQL.
- **Repositories** own SQL for their tables (concrete structs; generic
  `Executor` for transactional methods — evolved from the earlier trait/`dyn`
  shape in #163 / #191).
- **Services** own multi-step domain rules and transactions:
  `PermissionPolicy` (active/ban gate), `RbacService` (permissions),
  `MatchLifecycleService` (trade state machine).

### Frontend layering

```
Screens / widgets  →  Riverpod providers & controllers  →  ApiClient  →  Backend
```

- Generated models under `lib/models/` (from protobuf).
- Controllers encapsulate mutations; `FutureProvider`s load lists.

### Domain strategies (see ADRs)

| Topic | Strategy | ADR |
|-------|----------|-----|
| Match scope | One match = one item group within an event | [0001](../adr/0001-match-scoped-to-item-group.md) |
| Negotiation | Alternating propose/counter; accept only if balanced | [0002](../adr/0002-negotiation-state-machine.md) |
| JP font size | Subset WOFF2 committed; avoid full TTF download friction | [0003](../adr/0003-subset-woff2-japanese-font.md) |
| Authorization | RBAC roles/permissions global + event scopes | [0004](../adr/0004-rbac-permission-model.md) |
| Merch create | Gated by `merch.create` (curated catalog) | [0005](../adr/0005-merch-create-permission.md) |
| User.role field | Derived from `user_roles` at read time | [0006](../adr/0006-derive-user-role-from-user-roles.md) |

## Matching strategy

A **background task** in the API process (`MATCHING_INTERVAL_SECONDS`) runs
`matching::run_matching_algorithm`:

1. Scan **WANT** rows (active merch, non-banned users, non-null group).
2. Find partners with **TRADE** on the wanted merch.
3. Require reciprocal **TRADE/WANT** inside the **same (event_id, group_name)**.
4. Insert a **PENDING** match when none already covers the pair in that group.

Negotiation and inventory effects are **not** in the matcher — they live in
`MatchLifecycleService` after users act (see [06 — Runtime](06-runtime.md)).

## Image strategy

`ImageStorage` trait with runtime selection:

| `IMAGE_STORAGE` | Backend | Used for |
|-----------------|---------|----------|
| `local` (default on OCI compose) | Files under `UPLOAD_DIR`, served as `/uploads/...` | Dev + current prod/staging |
| Firebase/GCS implementation | Object upload via Google APIs | Optional / legacy path |

## Auth strategy

There is **no JWT / bearer session** today. Identity is **client-asserted**:

- **Guest sessions** via device UUID (`POST /api/v1/auth/guest`) return a `User`
  JSON body (low-friction entry).
- **Registered users** sign up / log in with password; handlers also return
  `User` JSON only (`handlers/auth.rs`).
- The Flutter client stores the user (e.g. local preferences) and passes
  **`user_id`** (body or query) on subsequent mutations/reads.
- Handlers typically call `PermissionPolicy::verify_active(user_id)` (ban /
  existence gate), then `RbacService::check` for privileged permissions.
- Admin UI is gated on an elevated global role derived for the wire `User.role`
  field ([ADR 0006](../adr/0006-derive-user-role-from-user-roles.md)).

This is **not** cryptographic session authentication: any client that can guess
or supply another user's id can attempt their actions until RBAC/ban checks
reject them. Treat stronger authn as a future hardening item if the threat model
requires it. Wire shapes: [API spec](../../reference/api_spec.md).
