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
# Run all tests (backend + frontend)
task test

# Full CI pipeline (lint + build + test)
task ci

# Individual targets
task backend:test       # Backend integration tests (auto-starts DB)
task backend:lint       # cargo fmt --check + clippy
task frontend:test      # Flutter unit/widget tests
task frontend:build     # Flutter web build

# Dev servers
task dev:backend        # Rust/Axum on :3000
task dev:frontend       # Flutter web on :8081

# List all available tasks
task --list
```

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

See [OCI Deployment Guide](./docs/oci_deployment.md) for full details.

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

See [Monitoring Guide](./docs/monitoring.md) for full details.

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
- [Requirements](./docs/requirements.md)
- [Use Cases](./docs/use_cases.md)
- [UI Specs](./docs/ui_specs.md)
- [Architecture & Actors](./docs/architecture.md)
- [API Specification](./docs/api_spec.md)
- [Database Schema](./docs/db_schema.md)
- [Cloud Deployment (GCP)](./docs/cloud_deployment.md)
- [Cloud Deployment (OCI)](./docs/oci_deployment.md)
- [Monitoring](./docs/monitoring.md)
- [Initial Idea](./docs/initial.md)
