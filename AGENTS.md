# AGENTS.md

## Project Overview

**ymatch** — Merchandise trading platform for managing inventory (HAVE/WANT) and executing physical exchanges based on system matches at events.

## Directory Structure

```
ymatch/
├── backend/           # Rust REST API (Axum, SQLx)
│   ├── src/
│   ├── migrations/    # SQLx database migrations
│   └── tests/         # Integration tests
├── frontend/          # Flutter web/mobile app
│   ├── lib/
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

**Test-Driven Development (TDD)**: Follow the **Red → Green → Refactor** cycle for any non-trivial change.

Where tests live:
- **Backend unit tests** — `#[cfg(test)] mod tests` inside the source file under test (e.g. `src/services/match_lifecycle.rs`).
- **Backend integration tests** — `backend/tests/api_tests.rs` (HTTP + DB end-to-end).
- **Frontend unit / widget tests** — `frontend/test/` (collocated by feature).

**Issue-Driven**: Every change starts with a GitHub Issue — create it **first**, before any branch or code. The issue is the single source of truth for the goal and acceptance criteria; track its status throughout

1. **Issue**: `gh issue create` (Must be first)
2. **Branch**: Create `feat/xxx` or `fix/xxx`
3. **TDD**: Follow Red -> Green -> Refactor
4. **Lint**: Run `cargo fmt -- --check && cargo clippy -- -D warnings` and `flutter analyze`
5. **Push & PR**: Commit, push, and run `gh pr create`
6. **CI Test**: Verify all CI checks pass successfully
7. **Review**: Run `/pr-review <PR>`
   * Fix or explain `[critical]` / `[major]` findings.
   * Resolve or accept `[minor]` / `[nit]` findings.
   * Re-run after changes.
8. **Report & Wait**: Report the PR URL to the user and stop. **Do not merge.** Wait for human merge or explicit authorization.

See [Development Workflow Guide](./docs/how_to/development_workflow.md) for full details.

## Security

The repository is operated as a **public repo with restrictive controls**, so anything committed (including history) is public. **Never commit secrets, credentials, host-specific absolute paths, personal identifiers, or terraform state.** Secrets come from GitHub Secrets / gitignored env files, not hardcoded defaults. See [Repository Security](./docs/explanation/security.md) for the full policy and pre-commit checklist.

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
task backend:coverage        # Backend tests + coverage (HTML + lcov.info)
cd backend && cargo fmt -- --check && cargo clippy -- -D warnings
cd frontend && flutter analyze
gh # for github related operation
```

### protobuf
edit `proto/models.proto` first, then run `./scripts/generate_protos.sh`
