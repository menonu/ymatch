# AGENTS.md

## Project Overview

**ymatch** — Merchandise trading platform for managing inventory (HAVE/WANT) and executing physical exchanges based on system matches at events.

| Component | Technology |
|-----------|-----------|
| Backend | Rust (Axum 0.7, SQLx 0.7) |
| Frontend | Flutter (Riverpod, GoRouter) |
| Database | PostgreSQL 16 |
| Proto | Protocol Buffers (prost / protobuf) |

## Directory Structure

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
├── docs/              # Documentation (Diátaxis framework)
├── scripts/           # Utility scripts
├── terraform/         # OCI infrastructure
└── vm/                # Dev container setup
```

## Documentation Structure (Diátaxis Framework)

All project documentation lives under `docs/` and follows the [Diátaxis framework](https://diataxis.fr/):

| Genre | Purpose | Location |
|-------|---------|----------|
| **Tutorials** | Learning-oriented walkthroughs | `docs/tutorials/` |
| **How-To Guides** | Task-oriented instructions | `docs/how_to/` |
| **Reference** | Information-oriented specifications | `docs/reference/` |
| **Explanation** | Understanding-oriented concepts | `docs/explanation/` |

See [Documentation Index](./docs/README.md) for the full file listing.

## Development Workflow

**Trunk-Based Development**: All work goes through PRs targeting `main`. Never push directly to `main`.

1. Create a GitHub Issue (`gh issue create`)
2. Create a feature branch (`feat/xxx` or `fix/xxx`)
3. If protobuf changes needed: edit `proto/models.proto` first, then run `./scripts/generate_protos.sh`
4. Implement changes
5. Run lints and tests: `task test`, `cargo fmt -- --check && cargo clippy -- -D warnings`, `flutter analyze`
6. Commit and push
7. Create PR via `gh pr create`
8. Merge after CI passes — OCI deployment triggers automatically

See [Development Workflow Guide](./docs/how_to/development_workflow.md) for full details.

## Quick Reference

### Ports
| Service | Port |
|---------|------|
| PostgreSQL | 5432 |
| Backend API | 3000 |
| Frontend | 8081 |

### Commands
```bash
task test                    # Run all tests
task backend:test            # Backend integration tests
task frontend:test           # Flutter unit/widget tests
cd backend && cargo fmt -- --check && cargo clippy -- -D warnings
cd frontend && flutter analyze
```

### Task Management
- Use GitHub Issues as the primary task tracker
- Use GitHub CLI (`gh`) for issue/PR management
