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
- Docker & Docker Compose, Rust (cargo), Flutter SDK

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
# Backend
cd backend && DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch cargo run --bin backend
# Frontend
cd frontend && flutter run -d web-server --web-port 8081
# Backend tests
cd backend && DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch_test cargo test -- --test-threads=1
# Frontend tests
cd frontend && flutter test
# Lint
cd backend && cargo clippy -- -D warnings && cargo fmt -- --check
cd frontend && flutter analyze
```

## GCP Production Deployment

See [Cloud Deployment Guide](./docs/cloud_deployment.md) for full details.

### Quick Reference
| Component | Service | URL |
|-----------|---------|-----|
| Frontend | Firebase Hosting | https://ymatch-app.web.app |
| Backend | Cloud Run (us-west1) | https://ymatch-backend-xbtg3vdbmq-uw.a.run.app |
| Database | e2-micro VM (no external IP) | 10.0.0.2 (internal VPC) |

### Redeploy Backend
```bash
export PATH="/home/ubuntu/google-cloud-sdk/bin:$PATH"
docker build --platform linux/amd64 -t us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest -f backend.Dockerfile.prod .
docker push us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest
gcloud run services update ymatch-backend --region us-west1 --image us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest --project tangential-map-491113-b4
```

### Redeploy Frontend
```bash
cd frontend && flutter build web --dart-define=API_BASE_URL=https://ymatch-backend-xbtg3vdbmq-uw.a.run.app --release
cd .. && firebase deploy --only hosting --project tangential-map-491113-b4
```

### DB Access (via IAP tunnel, no external IP)
```bash
gcloud compute ssh ymatch-db-vm --zone us-west1-b --tunnel-through-iap
docker exec -it postgres psql -U ymatch_user -d ymatch_db
```

## Development Guidelines
- **Redeploy scripts**: Use `./scripts/redeploy_backend.sh` / `./scripts/redeploy_frontend.sh` after code changes.
- **Smoke tests**: Run `./scripts/smoke_test.sh` after every backend redeploy.
- **Process management**: Use `netstat` to verify ports. Use PID files (`backend.pid`, `flutter.pid`). Do NOT use `lsof` to kill processes.
- **Protobuf first**: Edit `proto/models.proto` first, then update `backend/src/generated/ymatch.rs`.

## How to Manage Tasks
- **Task Tracking**: Use GitHub Issues as the primary task tracker for the project.
- The GitHub CLI (`gh`) is installed and should be used to manage, fetch, and create issues directly from the workspace.
- **Git Authentication**: Use the GitHub CLI (`gh`) authentication for `git` operations. Ensure the remote is set to HTTPS and run `gh auth setup-git` to allow `git push` without requiring SSH keys.

## Documentation
- [Requirements](./docs/requirements.md)
- [Use Cases](./docs/use_cases.md)
- [UI Specs](./docs/ui_specs.md)
- [Architecture & Actors](./docs/architecture.md)
- [API Specification](./docs/api_spec.md)
- [Database Schema](./docs/db_schema.md)
- [Cloud Deployment](./docs/cloud_deployment.md)
- [Initial Idea](./docs/initial.md)
