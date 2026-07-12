# 03 — Context and scope (C4)

This section uses the **C4 model** System Context (level 1) and Container
(level 2) views to show what is inside the ymatch boundary and what sits outside.

## System context (C4 level 1)

People and external systems that interact with **ymatch** as a whole.

```mermaid
C4Context
title System Context — ymatch

Person(fan, "Fan / trader", "Manages inventory, negotiates trades, chats at events")
Person(curator, "Event creator / editor", "Curates events, groups, and merch catalog")
Person(staff, "Moderator / admin", "Bans, elevated ops, admin dashboard")
Person(ops, "Operator", "Deploys, backs up, monitors, recovers")

System(ymatch, "ymatch", "Merchandise trading platform: catalog, inventory, matching, negotiation, messaging")

System_Ext(browser, "Web browser", "Serves Flutter web UI to fans and staff")
System_Ext(github, "GitHub", "Source, CI/CD, Secrets, container packages (GHCR)")
System_Ext(oci, "Oracle Cloud (OCI)", "VMs, networking, Object Storage for DB backups & Terraform state")
System_Ext(nr, "New Relic", "APM / infra metrics and alerts (optional operator tooling)")
System_Ext(discord, "Discord", "Alert webhook relay (optional operator tooling)")

Rel(fan, ymatch, "Uses over HTTPS", "JSON REST + static assets")
Rel(curator, ymatch, "Uses over HTTPS")
Rel(staff, ymatch, "Uses over HTTPS")
Rel(ops, ymatch, "SSH / deploy / terraform", "not end-user API")
Rel(ops, oci, "Provisions & operates")
Rel(ops, github, "Merges PRs, runs workflows")
Rel(ymatch, oci, "Runs on VMs; stores backups")
Rel(github, ymatch, "Builds & deploys images/workflows")
Rel(ymatch, nr, "Telemetry (when configured)")
Rel(nr, discord, "Alert notifications (when configured)")
Rel(fan, browser, "Opens")
Rel(browser, ymatch, "Loads UI & calls API")
```

### In scope

- Event / group / merch catalog
- Per-user inventory (HAVE / WANT / TRADE)
- Background matching within a group
- Trade negotiation state machine and inventory apply
- Match-scoped messaging and location hints
- Guest and account auth, RBAC
- Admin/moderator surfaces
- Image upload serving (local volume in OCI)

### Out of scope (external or not productized)

- Physical logistics of the meetup
- Production push providers (FCM/APNs) — notification module logs only
- Third-party payment rails
- Multi-region active-active failover

## Containers (C4 level 2)

Major deployable / runtime units **inside** the ymatch system boundary.

```mermaid
C4Container
title Container diagram — ymatch

Person(user, "User", "Fan, curator, or staff in a browser/app")

System_Boundary(ymatch, "ymatch") {
    Container(web, "Flutter Web UI", "Flutter, Riverpod, GoRouter", "SPA: inventory, matches, chat, admin")
    Container(api, "Backend API", "Rust, Axum, SQLx", "REST /api/v1, auth, lifecycle, matching loop, image upload")
    ContainerDb(db, "PostgreSQL", "PostgreSQL 16", "Users, catalog, inventory, matches, messages, RBAC")
    Container(proxy, "Edge proxy", "Caddy", "TLS (nip.io), reverse proxy /api, /uploads, static UI")
    Container(fe_static, "Frontend static host", "Nginx (container)", "Serves built Flutter web assets")
}

System_Ext(ghcr, "GHCR", "Container images")
System_Ext(backup, "OCI Object Storage", "DB backup objects")

Rel(user, proxy, "HTTPS", "443")
Rel(proxy, fe_static, "/*")
Rel(proxy, api, "/api/*, /uploads/*")
Rel(api, db, "SQL", "SQLx")
Rel(web, proxy, "Same origin or configured API base")
Rel(api, backup, "pg_dump uploads (scheduled ops)", "when backup jobs run")
Rel(ghcr, proxy, "Image pulls on deploy")
```

### Container responsibilities

| Container | Responsibility |
|-----------|----------------|
| **Flutter Web UI** | Presentation, client state, calls REST via `ApiClient` / protobuf JSON. |
| **Backend API** | Auth, RBAC checks, domain services, repositories, periodic matcher, image storage adapter. |
| **PostgreSQL** | System of record. |
| **Caddy** | Public HTTPS termination and path routing (prod/staging). |
| **Nginx (frontend container)** | Serves compiled Flutter assets only. |

Local development collapses edge routing: Flutter dev server (:8081) talks to API (:3000) with Postgres from `docker compose` (:5432). See [07 — Deployment](07-deployment.md).

## External interfaces (summary)

| Interface | Protocol | Notes |
|-----------|----------|--------|
| Browser ↔ API | HTTPS JSON REST | Base path `/api/v1`; see [API spec](../../reference/api_spec.md). |
| Browser ↔ images | HTTPS | `/uploads/*` via API static files when `IMAGE_STORAGE=local`. |
| API ↔ Postgres | TCP SQL | Connection string from env (`DATABASE_URL`). |
| CI ↔ VM | SSH + Docker | GitHub Actions deploy workflows. |
| Ops ↔ OCI | OCI API / Terraform | Infra and Object Storage; secrets never in git. |
