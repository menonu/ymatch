# 03 — Context and scope (C4)

This section uses the **C4 model System Context** (level 1) view: people and
external systems that interact with **ymatch** as a black box, plus what is in
or out of product scope.

Internal decomposition starts at **C4 level 2 (Containers)** in
[05 — Building blocks](05-building-blocks.md). How containers are placed on
machines is in [07 — Deployment](07-deployment.md).

C4 structural diagrams are authored in [D2](https://d2lang.com/) and committed
as SVG under [`diagrams/`](diagrams/) (GitHub does not reliably render Mermaid
C4). Sequences and simple flowcharts elsewhere use Mermaid.

## System context (C4 level 1)

![System Context — ymatch](diagrams/03-system-context.svg)

Source: [`diagrams/03-system-context.d2`](diagrams/03-system-context.d2)

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

## External interfaces (summary)

| Interface | Protocol | Notes |
|-----------|----------|--------|
| Browser ↔ API | HTTPS JSON REST | Base path `/api/v1`; see [API spec](../../reference/api_spec.md). |
| Browser ↔ images | HTTPS | `/uploads/*` via API static files (`UPLOAD_DIR`). |
| API ↔ Postgres | TCP SQL | Connection string from env (`DATABASE_URL`). |
| CI ↔ VM | SSH + Docker | GitHub Actions deploy workflows. |
| Ops ↔ OCI | OCI API / Terraform | Infra and Object Storage; secrets never in git. |

Container-level wiring (Caddy paths, compose services) is detailed in
[05 — Building blocks](05-building-blocks.md) and
[07 — Deployment](07-deployment.md).
