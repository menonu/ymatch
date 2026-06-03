# ymatch

A merchandise trading platform for managing inventory (HAVE/WANT) and executing physical exchanges based on system matches at events.

## Architecture

| Component   | Technology               |
|------------|--------------------------|
| Backend    | Rust (Axum 0.7, SQLx 0.7) |
| Frontend   | Flutter (Riverpod, GoRouter) |
| Database   | PostgreSQL 16            |
| Proto      | Protocol Buffers (prost / protobuf) |

## Quick Start

### Prerequisites

- [Docker & Docker Compose](https://docs.docker.com/get-docker/)
- [Rust](https://rustup.rs/) (1.80+)
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable)

### 1. Start Infrastructure

```bash
# Start PostgreSQL (port 5432) and pgAdmin (port 5050)
docker compose up -d

# Create test database (first time only)
docker exec ymatch_db psql -U ymatch_user -d ymatch \
  -c "CREATE DATABASE ymatch_test OWNER ymatch_user;"
```

### 2. Start Backend API (port 3000)

```bash
cd backend
DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch \
  cargo run --bin backend
```

The API will be available at `http://localhost:3000`.

### 3. Start Frontend (port 8081)

```bash
cd frontend
flutter run -d web-server --web-port 8081
```

The web app will be available at `http://localhost:8081`.

## Service Ports

| Service      | Port  | URL                          |
|-------------|-------|-------------------------------|
| PostgreSQL  | 5432  | `localhost:5432`              |
| pgAdmin     | 5050  | http://localhost:5050          |
| Backend API | 3000  | http://localhost:3000          |
| Frontend    | 8081  | http://localhost:8081          |

### pgAdmin Credentials

- Email: `admin@ymatch.com`
- Password: `admin`

### Database Credentials

- User: `ymatch_user`
- Password: `secure_dev_password`
- Database: `ymatch` (main) / `ymatch_test` (tests)

## Development

### Dev Server Management

Use the provided scripts to restart dev servers cleanly:

```bash
./scripts/redeploy_backend.sh    # Rebuild & restart backend
./scripts/redeploy_frontend.sh   # Rebuild & restart frontend
./scripts/smoke_test.sh          # Run API smoke tests
```

### Running Tests

```bash
# Backend integration tests (requires ymatch_test DB)
cd backend
DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch_test \
  cargo test -- --test-threads=1

# Frontend unit/widget tests
cd frontend
flutter test

# Frontend integration tests (requires running app)
cd frontend
flutter test integration_test/
```

### Code Quality

```bash
# Backend
cd backend
cargo clippy -- -D warnings
cargo fmt -- --check

# Frontend
cd frontend
flutter analyze
```

## Project Structure

```
ymatch/
├── backend/           # Rust REST API (Axum, SQLx)
│   ├── src/
│   │   ├── handlers/  # Route handlers by domain
│   │   ├── generated/ # Prost-generated protobuf types
│   │   ├── routes.rs  # Route definitions
│   │   └── main.rs    # Entry point
│   ├── migrations/    # SQLx database migrations
│   └── tests/         # Integration tests
├── frontend/          # Flutter web/mobile app
│   ├── lib/
│   │   ├── generated/ # Protobuf-generated Dart types
│   │   ├── providers/ # Riverpod state management
│   │   ├── screens/   # UI screens
│   │   └── services/  # API client
│   ├── test/          # Unit/widget tests
│   └── integration_test/ # E2E tests
├── proto/             # Protobuf definitions
├── docs/              # Documentation
├── scripts/           # Utility scripts
└── docker-compose.yml # PostgreSQL + pgAdmin
```

## Documentation

See the [Documentation Index](./docs/README.md) for full details.
- [API Specification](./docs/reference/api_spec.md)
- [Database Schema](./docs/reference/db_schema.md)
- [Requirements](./docs/explanation/requirements.md)
- [Architecture](./docs/explanation/architecture.md)
- [UI Specs](./docs/reference/ui_specs.md)
- [Use Cases](./docs/explanation/use_cases.md)

## Permission System

| Role       | Capabilities                                        |
|-----------|-----------------------------------------------------|
| `user`    | Create events, manage own items, trade              |
| `moderator` | + Ban/unban users, admin delete operations        |
| `admin`   | + Change user roles, full system access             |

Banned users are blocked from all write operations. Temporary bans are supported via `banned_until`.
