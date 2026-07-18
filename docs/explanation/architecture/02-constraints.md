# 02 — Constraints

## Technical constraints

| Constraint | Implication |
|------------|-------------|
| **Single shared PostgreSQL** per environment | All durable domain state lives in one DB; matching and lifecycle use SQL transactions. |
| **JSON REST + protobuf models** | Wire bodies are proto3 JSON; Rust/Dart types are generated from `proto/models.proto` via `scripts/proto-gen.sh`. |
| **Flutter client** | UI and client state are Riverpod + GoRouter; browser and mobile share one codebase. |
| **Image storage via `ImageStorage` trait** | Current backend is local files (`UPLOAD_DIR`, served as `/uploads/*`); the trait remains for a future object-store backend. |
| **Always Free–friendly hosting** | Production/staging target OCI Ampere A1 VMs with Docker Compose — not a multi-region k8s mesh. |
| **Public GitHub repository** | Secrets, host paths, and PII must never be committed ([security.md](../security.md)). |

## Organizational constraints

| Constraint | Implication |
|------------|-------------|
| **Trunk-based development** | All work via PRs to `main`; issue-driven workflow. |
| **Small maintainer set** | Prefer simple operational model (one compose stack per VM) over complex orchestration. |
| **Documentation genres (Diátaxis)** | Architecture explains shape; how-tos carry steps; reference carries catalogs. |

## Conventions that act as constraints

- **ADRs are append-only** — reverse a decision with a new ADR, do not rewrite history ([adr/README](../adr/README.md)).
- **Authorization through RBAC + participation rules** — privileged catalog/admin
  paths check permissions; ownership and match-participation short-circuits are
  explicit where documented ([ADR 0004](../adr/0004-rbac-permission-model.md),
  [permissions reference](../../reference/permissions.md)).
- **SQL ownership toward repositories** — target is handlers parse/delegate and
  multi-statement flows in services; some admin/search/matching SQL remains outside
  that ideal (documented in [04](04-solution-strategy.md) / [05](05-building-blocks.md)).
