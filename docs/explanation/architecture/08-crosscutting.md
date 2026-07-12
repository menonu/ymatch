# 08 — Cross-cutting concepts

## Security

| Concern | Approach |
|---------|----------|
| Public repository | Never commit secrets, PEM keys, host absolute paths, PII, tfstate — [security.md](../security.md). |
| Transport | HTTPS at Caddy in staging/prod; local HTTP is dev-only. |
| Authn | **Client-asserted identity**: guest/login return `User` JSON; client stores the user and sends `user_id` on later requests. No JWT/session token layer today. |
| Authz | `PermissionPolicy::verify_active` (ban/existence) then `RbacService` + permission catalog; admin superuser bypass in ADR 0004. |
| Rate limiting | Governor middleware on most `/api/v1` routes (`routes.rs`). |
| Image upload | **Unauthenticated** `POST /api/v1/images/upload` and `DELETE /api/v1/images/:filename` (content-type + 1MB size checks only); files via `ImageStorage`. Known gap — see [09 — Quality](09-quality.md). |

## RBAC

- **Scopes:** `global` and `event`.
- **Source of truth:** `user_roles` (+ role/permission tables).
- **Reference catalog:** [permissions.md](../../reference/permissions.md).
- **Decisions:** [ADR 0004](../adr/0004-rbac-permission-model.md),
  [ADR 0005](../adr/0005-merch-create-permission.md),
  [ADR 0006](../adr/0006-derive-user-role-from-user-roles.md).
- **Operator grant:** [grant_roles.md](../../how_to/grant_roles.md) —
  `scripts/grant_role.sh` (username never committed).

## Internationalization

- Flutter `gen-l10n` from ARB files (`frontend/l10n.yaml`).
- English and Japanese supported.
- Japanese font strategy: subset WOFF2 in-repo — [ADR 0003](../adr/0003-subset-woff2-japanese-font.md).

## Error handling

- Backend: central `AppError` with `IntoResponse` mapping (validation vs
  not-found vs forbidden vs internal).
- Prefer stable client-facing messages; avoid leaking raw DB errors to clients
  (ongoing hygiene; see open error-handling issues if any remain).

## Observability

- Structured tracing logs on the API (`RUST_LOG`).
- Optional New Relic + Discord alert path for operators —
  [monitoring_setup](../../how_to/monitoring_setup.md).
- System status endpoint for basic health/version surfaces in the Profile UI.

## Configuration

| Variable (examples) | Purpose |
|---------------------|---------|
| `DATABASE_URL` | Postgres connection |
| `PORT` | API listen port (default 3000) |
| `IMAGE_STORAGE` / `UPLOAD_DIR` | Image backend |
| `MATCHING_INTERVAL_SECONDS` | Matcher cadence |
| `RATE_LIMIT_*` (if set) | Governor rate-limit tuning (see `routes.rs` defaults) |

Templates: `backend/.env.example` (gitignored real `.env`). No JWT/signing secret
env vars exist in the current API.

## Protocol / codegen

- Edit `proto/models.proto` first.
- Run `scripts/proto-gen.sh` (Docker) to regenerate Rust + Dart bindings.
- Do not hand-edit generated model files.
