# 05 — Building block view (C4)

Structural decomposition inside the system. Uses **C4 Container** (recap) and
**C4 Component** views for the two largest codebases.

## Containers (recap)

See [03 — Context](03-context.md) for the full container diagram. Code maps to
containers as:

| Container | Primary codebase |
|-----------|------------------|
| Flutter Web UI | `frontend/` |
| Backend API | `backend/` |
| PostgreSQL | `backend/migrations/` (+ runtime data) |
| Caddy / Nginx | `Caddyfile.oci`, `frontend.Dockerfile.prod` |

## Backend components (C4 level 3)

```mermaid
C4Component
title Component diagram — Backend API

Container_Boundary(api, "Backend API") {
    Component(routes, "Router & middleware", "Axum", "Route table, rate limit, CORS, AppState")
    Component(handlers, "HTTP handlers", "handlers/*", "Parse request, authorize hooks, delegate")
    Component(lifecycle, "MatchLifecycleService", "services/match_lifecycle.rs", "Propose/counter/accept/complete/apply transactions")
    Component(rbac, "RbacService", "services/rbac.rs", "Permission checks over user_roles")
    Component(repos, "Repositories", "repositories/*", "SQL access; concrete structs + Executor")
    Component(matching, "Matching job", "matching.rs", "Periodic WANT/TRADE mutual match creation")
    Component(storage, "ImageStorage", "storage/*", "Local or Firebase/GCS adapter")
    Component(proto, "Generated models", "generated/*", "prost types from proto/")
}

ContainerDb(db, "PostgreSQL", "PostgreSQL 16", "System of record")
Container_Ext(client, "Flutter client", "HTTPS JSON")

Rel(client, routes, "REST /api/v1")
Rel(routes, handlers, "Dispatch")
Rel(handlers, lifecycle, "Trade mutations")
Rel(handlers, rbac, "check(permission)")
Rel(handlers, repos, "CRUD reads/writes")
Rel(lifecycle, repos, "Transactional SQL")
Rel(rbac, repos, "Load roles/permissions")
Rel(matching, db, "Direct SQL for match discovery")
Rel(repos, db, "SQLx")
Rel(handlers, storage, "Upload/delete images")
Rel(handlers, proto, "Serialize responses")
```

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

```mermaid
C4Component
title Component diagram — Flutter client

Container_Boundary(fe, "Flutter Web UI") {
    Component(screens, "Screens", "lib/screens/*", "Login, Items, Event detail, Matches, Chat, Profile, Admin")
    Component(widgets, "Shared widgets", "lib/widgets/*", "Cards, dialogs, chrome")
    Component(providers, "Providers & controllers", "lib/providers/providers.dart", "Auth, events, merch, inventory, matches, admin, search")
    Component(api, "ApiClient", "lib/services/api_client.dart", "HTTP + auth headers + proto3 JSON")
    Component(models, "Models", "lib/models/*", "Generated protobuf Dart types")
    Component(router, "Router", "GoRouter", "Deep links / tab navigation")
    Component(l10n, "Localization", "lib/l10n/*", "EN + JA ARB → AppLocalizations")
}

Container_Ext(api_ext, "Backend API", "REST")

Rel(screens, providers, "watch / read")
Rel(screens, widgets, "compose")
Rel(screens, router, "navigate")
Rel(providers, api, "mutations & fetches")
Rel(api, models, "encode/decode")
Rel(api, api_ext, "HTTPS JSON")
Rel(screens, l10n, "strings")
```

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
