# AGENTS.md

## Source Code Structure
- **`backend/`**: Rust (Axum, SQLx) REST API backend.
- **`frontend/`**: Flutter (Mobile/Web) frontend application.
- **`proto/`**: Protobuf definitions for data models shared across boundaries.
- **`docs/`**: Project documentation, specifications, and architecture.
- **`scripts/`**: Utility scripts (e.g., protobuf generation, deployment).
- **`vm/`**: Development container (devcontainer) environment setup.

## Build & Test

### Prerequisites
- Docker & Docker Compose, Rust (cargo), Flutter SDK, [Task](https://taskfile.dev/) (go-task)

### Infrastructure
```bash
docker compose up -d
# First time only
docker exec ymatch_db psql -U ymatch_user -d ymatch -c "CREATE DATABASE ymatch_test OWNER ymatch_user;"
```
DB: `ymatch_user:secure_dev_password@localhost:5432/ymatch` | pgAdmin: `http://localhost:5050` (admin@ymatch.com / admin)

### Ports
| Service     | Port | Description            |
|-------------|------|------------------------|
| PostgreSQL  | 5432 | Database (Docker)      |
| pgAdmin     | 5050 | DB admin UI (Docker)   |
| Backend API | 3000 | Rust/Axum REST API     |
| Frontend    | 8081 | Flutter Web dev server |

### Commands
```bash
# Testing (via Taskfile — handles DB setup automatically)
task test               # Run all tests (backend + frontend)
task backend:test       # Backend integration tests (auto-starts DB)
task frontend:test      # Flutter unit/widget tests

# Lint (run directly — not part of Taskfile)
cd backend && cargo fmt -- --check && cargo clippy -- -D warnings
cd frontend && flutter analyze

# Build
cd backend && cargo build
cd frontend && flutter build web

# Dev servers
cd backend && DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch cargo run --bin backend
cd frontend && flutter run -d web-server --web-port 8081

# List available test tasks
task --list
```

### Test Strategy

**Backend** (`backend/tests/api_tests.rs`): 24 integration tests against PostgreSQL.
- Each test calls `setup_test_pool()` which resets the database (DELETE all rows, re-run migrations).
- Tests are fully isolated — no ordering dependencies, deterministic UUIDs.
- **Must run with `--test-threads=1`** (shared database, sequential execution required).
- `Taskfile.yml` handles DB container startup and test database creation idempotently.

**Frontend** (`frontend/test/`): 24 unit/widget tests + 4 integration tests.
- Unit/widget tests use `MockClient` — no external dependencies.
- Integration tests (`test/integration/`) are tagged `@Tags(['integration'])` and excluded from CI.
- Integration tests require a running backend at `localhost:3000`.

**CI** (`.github/workflows/ci.yml`): Mirrors local test execution.
- Backend: PostgreSQL service container → fmt → clippy → build → test (`--test-threads=1`).
- Frontend: pub get → test (`--exclude-tags=integration`) → build web.

## GCP (Backup Only)

GCP production services (Cloud Run, Compute Engine, Firebase Hosting) have been **stopped**.
GCP is now used only for:
- **Database backup storage**: GCS bucket `tangential-map-491113-b4-db-backups`
- **Budget monitoring**: $1/month alert via Cloud Billing

### Database Backup
Automated via GitHub Actions (`.github/workflows/db-backup.yml`):
- **Daily** at 03:00 JST → `daily/` prefix (kept 7 days, max 7 backups)
- **Weekly** on Sundays → `weekly/` prefix (kept 28 days, max 4 backups)
- **Monthly** on 1st → `monthly/` prefix (kept 90 days, max 3 backups)
- Total: up to **14 backups** at any time
- Backup events reported to New Relic

```bash
# Manual backup trigger (all types)
gh workflow run db-backup.yml --field backup_type=all

# Restore from backup
gcloud storage cp gs://tangential-map-491113-b4-db-backups/daily/ymatch-YYYY-MM-DD.sql.gz .
gunzip ymatch-YYYY-MM-DD.sql.gz
ssh -i ~/.ssh/oci_ymatch ubuntu@161.33.17.247 \
  "docker exec -i ymatch_db psql -U ymatch_user ymatch" < ymatch-YYYY-MM-DD.sql
```

## OCI Production Deployment (Always Free ARM)

See [OCI Deployment Guide](./docs/how_to/oci_deployment.md) for full details.

### Quick Reference
| Component | Service | URL |
|-----------|---------|-----|
| Full Stack | ARM A1 VM + Docker Compose | `https://<PUBLIC_IP>.nip.io` |

### Deploy / Redeploy
```bash
# Provision infrastructure
cd terraform/oci && terraform init && terraform apply

# SSH into VM and deploy
ssh ubuntu@<PUBLIC_IP>
./scripts/oci_deploy.sh <db_password>

# Redeploy backend/frontend
./scripts/oci_redeploy_backend.sh
./scripts/oci_redeploy_frontend.sh
```

## Development Guidelines

### Branching Strategy: Trunk-Based Development
- **`main`** is the single trunk branch. Production is always deployed from `main`.
- All changes go through **Pull Requests** (PRs) targeting `main`.
- PRs must pass **CI** (`Backend Build & Test` + `Frontend Build & Test`) before merging.
- Use **short-lived feature branches** (e.g., `feat/xxx`, `fix/xxx`). Merge promptly after CI passes.
- **Do NOT push directly to `main`** — always create a PR.
- After merge to `main`, the `deploy-oci` workflow automatically deploys to production.

### Other Guidelines
- **Redeploy scripts**: Use `./scripts/redeploy_backend.sh` / `./scripts/redeploy_frontend.sh` after code changes.
- **Smoke tests**: Run `./scripts/smoke_test.sh` after every backend redeploy.
- **Process management**: Use `netstat` to verify ports. Use PID files (`backend.pid`, `flutter.pid`). Do NOT use `lsof` to kill processes.
- **Protobuf first**: Edit `proto/models.proto` first, then update `backend/src/generated/ymatch.rs`.

## How to Manage Tasks
- **Task Tracking**: Use GitHub Issues as the primary task tracker for the project.
- The GitHub CLI (`gh`) is installed and should be used to manage, fetch, and create issues directly from the workspace.
- **Git Authentication**: Use the GitHub CLI (`gh`) authentication for `git` operations. Ensure the remote is set to HTTPS and run `gh auth setup-git` to allow `git push` without requiring SSH keys.

## Monitoring

See [Monitoring Guide](./docs/how_to/monitoring_setup.md) for full details.

- **New Relic** (Free tier): Infrastructure agent on OCI VM, Synthetic monitors, alert policies with Discord notifications
- **Dashboard**: `ymatch Production Overview` in New Relic
- **GitHub Actions**: Telemetry exported via `newrelic-exporter.yml` workflow
- **Billing Alerts**: OCI budget ($1/month), GCP budget ($1/month) — native cloud alerts

### Key Commands
```bash
# Agent status on OCI VM
ssh -i ~/.ssh/oci_ymatch ubuntu@<VM_IP> 'sudo systemctl status newrelic-infra'

# Reinstall agent
ssh -i ~/.ssh/oci_ymatch ubuntu@<VM_IP>
NEW_RELIC_LICENSE_KEY=<key> ./ymatch/scripts/setup_newrelic_agent.sh
```

## Documentation
See the [Documentation Index](./docs/README.md) for full details.
- [Requirements](./docs/explanation/requirements.md)
- [Use Cases](./docs/explanation/use_cases.md)
- [UI Specs](./docs/reference/ui_specs.md)
- [Architecture & Actors](./docs/explanation/architecture.md)
- [API Specification](./docs/reference/api_spec.md)
- [Database Schema](./docs/reference/db_schema.md)
- [Development Workflow](./docs/how_to/development_workflow.md)
- [Cloud Deployment (GCP)](./docs/how_to/cloud_deployment.md)
- [Cloud Deployment (OCI)](./docs/how_to/oci_deployment.md)
- [Monitoring](./docs/how_to/monitoring_setup.md)
- [Initial Idea](./docs/explanation/initial_concept.md)
