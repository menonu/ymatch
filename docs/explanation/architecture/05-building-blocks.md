# 05 — Building block view (C4)

Structural decomposition **inside** the ymatch system boundary, following the
C4 hierarchy:

| C4 level | View | Where |
|----------|------|--------|
| 1 — System Context | Black-box system + people/external systems | [03 — Context](03-context.md) |
| **2 — Containers** | Deployable / runtime units | **this section** |
| **3 — Components** | Major modules inside the largest containers | **this section** |

C4 diagrams: [D2](https://d2lang.com/) → SVG in [`diagrams/`](diagrams/).
Simple data-flow uses Mermaid below. Placement on hosts is
[07 — Deployment](07-deployment.md).

## Containers (C4 level 2)

Major deployable / runtime units inside the system boundary.

![Container diagram — ymatch](diagrams/05-containers.svg)

Source: [`diagrams/05-containers.d2`](diagrams/05-containers.d2)

### Container responsibilities

| Container | Responsibility | Primary codebase / config |
|-----------|----------------|---------------------------|
| **Flutter Web UI** | Presentation, client state, REST via `ApiClient` / protobuf JSON | `frontend/` (built assets) |
| **Backend API** | Auth, RBAC, domain services, repositories, periodic matcher, image storage | `backend/` |
| **PostgreSQL** | System of record | `backend/migrations/` (+ runtime data) |
| **Caddy** | Public HTTPS termination and path routing (prod/staging) | `Caddyfile.oci` |
| **Nginx (frontend container)** | Serves compiled Flutter assets only | `frontend.Dockerfile.prod` |

Local development collapses edge routing: Flutter dev server (:8081) talks to API
(:3000) with Postgres from `docker compose` (:5432). See
[07 — Deployment](07-deployment.md).

## Backend components (C4 level 3)

Decomposition of the **Backend API** container.

![Component diagram — Backend API](diagrams/05-backend-components.svg)

Source: [`diagrams/05-backend-components.d2`](diagrams/05-backend-components.d2)

### Backend module map

| Area | Path | Role |
|------|------|------|
| Entry | `main.rs`, `lib.rs` | Boot pool, spawn matcher, serve |
| Routes / state | `routes.rs` | `AppState`, middleware (incl. governor rate limit) |
| Handlers | `handlers/` | Auth, events, merch, inventory, matches, messages, admin, images, search, system |
| Match lifecycle | `services/match_lifecycle.rs` | Negotiation + inventory apply |
| RBAC | `services/rbac.rs`, `repositories/rbac.rs` | Permission model |
| Permissions catalog | `services/permission_catalog.rs` | Permission/role seed definitions |
| Repositories | `repositories/` | user, event, merch, group, inventory, match_, message, favorites, views, rbac |
| Matching | `matching.rs` | Background mutual-trade discovery |
| Notifications | `notifications.rs` | Log-only push stub |
| Storage | `storage/` | `ImageStorage` trait + local / Firebase |
| Errors | `error.rs` | `AppError` → HTTP |

### Repository list (SQL ownership)

| Repository | Domain tables (approx.) |
|------------|-------------------------|
| `UserRepository` | `users` (+ role derivation) |
| `EventRepository` | `events` |
| `MerchandiseRepository` | `merchandise` |
| `MerchandiseGroupRepository` | `merchandise_groups` |
| `InventoryRepository` | `inventory` |
| `MatchRepository` | `matches`, `match_items` |
| `MessageRepository` | `messages` |
| `EventFavoritesRepository` / `GroupFavoritesRepository` / `EventViewsRepository` | favorites & views |
| `RbacRepository` | `roles`, `permissions`, `role_permissions`, `user_roles` |

Exact columns: [DB schema reference](../../reference/db_schema.md).

## Frontend components (C4 level 3)

Decomposition of the **Flutter Web UI** container (client-side modules; static
files are served by the Nginx container in prod).

![Component diagram — Flutter client](diagrams/05-frontend-components.svg)

Source: [`diagrams/05-frontend-components.d2`](diagrams/05-frontend-components.d2)

### Primary screens

| Screen | User-facing role |
|--------|------------------|
| `LoginScreen` | Guest start / restore / login |
| `HomeScreen` | **Items** tab — event list |
| `EventDetailScreen` | Merch + inventory for one event |
| `AddMerchScreen` | Create merch (RBAC-gated) |
| `TradeListScreen` | **Matches** tab — negotiate & complete |
| `ChatScreen` | Per-match messages / location |
| `ProfileScreen` | Account, how-to, system status |
| `AdminDashboardScreen` | Elevated admin/mod tools |

Identifiers and EN/JA labels: [UI components](../../reference/ui_components.md),
[UI specs](../../reference/ui_specs.md).

## Cross-container data

```mermaid
flowchart LR
  subgraph Client
    UI[Screens]
    P[Providers]
    AC[ApiClient]
  end
  subgraph API
    H[Handlers]
    S[Services]
    R[Repos]
  end
  DB[(PostgreSQL)]

  UI --> P --> AC -->|proto3 JSON| H --> S --> R --> DB
  H --> R
```

Shared **contract**: `proto/models.proto` → Rust `backend/src/generated` and
Dart `frontend/lib/models` via `scripts/proto-gen.sh`.
