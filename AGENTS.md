# AGENTS.md

This document serves as the main entry point and guide for the `ymatch` merchandise trading platform project.

## About the Project
`ymatch` is a merchandise trading platform system designed to help users manage inventory (HAVE/WANT) and execute physical exchanges based on system matches, particularly at events.

## Source Code Structure
- **`backend/`**: Rust (Axum, SQLx) REST API backend.
- **`frontend/`**: Flutter (Mobile/Web) frontend application.
- **`proto/`**: Protobuf definitions for data models shared across boundaries.
- **`docs/`**: Project documentation, specifications, and architecture.
- **`scripts/`**: Utility scripts (e.g., protobuf generation, deployment).
- **`vm/`**: Development container (devcontainer) environment setup and configurations.

## How to Build and Test

### Prerequisites
- Docker & Docker Compose
- Rust (cargo)
- Flutter SDK

### Start Infrastructure (Database)
```bash
# Start PostgreSQL (port 5432) and pgAdmin (port 5050)
docker compose up -d

# Create test database (first time only)
docker exec ymatch_db psql -U ymatch_user -d ymatch -c "CREATE DATABASE ymatch_test OWNER ymatch_user;"
```

Database credentials: `ymatch_user:secure_dev_password@localhost:5432/ymatch`
pgAdmin: `http://localhost:5050` (admin@ymatch.com / admin)

### Service Ports
| Service      | Port  | Description                     |
|-------------|-------|---------------------------------|
| PostgreSQL  | 5432  | Database (via Docker)           |
| pgAdmin     | 5050  | Database admin UI (via Docker)  |
| Backend API | 3000  | Rust/Axum REST API              |
| Frontend    | 8081  | Flutter Web dev server          |

### Commands
```bash
# Run Backend (port 3000)
cd backend
DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch cargo run --bin backend

# Run Frontend (port 8081)
cd frontend
flutter run -d web-server --web-port 8081

# Run Backend Tests (requires ymatch_test DB)
cd backend
DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch_test cargo test -- --test-threads=1

# Run Frontend Tests
cd frontend
flutter test

# Code Quality
cd backend && cargo clippy -- -D warnings && cargo fmt -- --check
cd frontend && flutter analyze
```

### Development Guidelines
- **Always Rebuild and Restart**: Before testing any changes, ensure the application (Backend/Frontend) is rebuilt and restarted to apply the latest code.
- **Verify Version**: Confirm that the version/build being tested reflects the most recent changes before proceeding with verification.
- **Verify Process and Port Status**: Before test, confirm that backend and frontend is working by checking process alive and port is opened (e.g., using `netstat`). Do NOT use `lsof` to kill processes as it may accidentally terminate SSH connections or workspace extensions in this environment. Manage background processes manually using PID files (`backend.pid`, `flutter.pid`).
- **Keep Environment Running**: Maintain a running instance of the backend (`cargo run`) and frontend (`flutter run -d web-server --web-port 8081`) in the background during development to facilitate continuous UI/UX verification. **You must re-deploy (restart) the dev servers after making any codebase changes.**
  - **To reliably restart the servers and avoid caching or port binding issues, YOU MUST USE THESE SCRIPTS:**
    - For Frontend: Run `./scripts/redeploy_frontend.sh`
    - For Backend: Run `./scripts/redeploy_backend.sh`
- **Smoke Tests Mandatory**: After re-deploying the backend, you must run the API smoke tests to verify the core endpoints are not broken. Run `./scripts/smoke_test.sh` from the project root.
- **Protobuf First**: Any changes to data structures must be applied to `proto/models.proto` first, then manually update `backend/src/generated/ymatch.rs` to match.

## Permission System
- **Roles**: `user` (default), `moderator`, `admin`
- **Banned users** are blocked from write operations and login
- **Moderators** can ban/unban users and perform admin delete operations
- **Admins** can do everything moderators can, plus change user roles
- Ownership checks: event creators can manage their events; merch creators can manage their items

## How to Manage Tasks
- **Task Tracking**: Use GitHub Issues as the primary task tracker for the project.
- The GitHub CLI (`gh`) is installed and should be used to manage, fetch, and create issues directly from the workspace.
- **Git Authentication**: Use the GitHub CLI (`gh`) authentication for `git` operations. Ensure the remote is set to HTTPS and run `gh auth setup-git` to allow `git push` without requiring SSH keys.

## Docs Structures
For detailed information regarding specific aspects of the system, refer to the documents linked below:
- [Requirements](./docs/requirements.md): Core system requirements.
- [Use Cases](./docs/use_cases.md): User workflows and use cases.
- [UI Specs](./docs/ui_specs.md): UI/UX specifications.
- [Architecture & Actors](./docs/architecture.md): System architecture, technical stack, and actors.
- [API Specification](./docs/api_spec.md): Available REST API endpoints and data payloads.
- [Database Schema](./docs/db_schema.md): Database entity-relationship mapping and SQL schema.
- [Cloud Deployment](./docs/cloud_deployment.md): GCP cloud deployment strategy.
- [Initial Idea](./docs/initial.md): The raw initial project idea.
