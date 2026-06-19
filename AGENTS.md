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

**Test-Driven Development (TDD)**: Follow the **Red → Green → Refactor** cycle for any non-trivial change.

1. **Red** — Write a failing test (unit or integration) that describes the desired behavior. Confirm it actually fails for the right reason.
2. **Green** — Implement the minimum code to make the test pass. No more.
3. **Refactor** — Clean up the implementation while keeping the test green. Re-run the test after each refactor step.

Where tests live:
- **Backend unit tests** — `#[cfg(test)] mod tests` inside the source file under test (e.g. `src/services/match_lifecycle.rs`).
- **Backend integration tests** — `backend/tests/api_tests.rs` (HTTP + DB end-to-end).
- **Frontend unit / widget tests** — `frontend/test/` (collocated by feature).

Exceptions: pure doc / config changes, generated code, and trivial typo fixes do not need new tests, but existing tests must still pass.

1. Create a GitHub Issue (`gh issue create`)
2. Create a feature branch (`feat/xxx` or `fix/xxx`)
3. If protobuf changes needed: edit `proto/models.proto` first, then run `./scripts/generate_protos.sh`
4. Apply the TDD cycle above
5. Run lints and tests: `task test`, `cargo fmt -- --check && cargo clippy -- -D warnings`, `flutter analyze`
6. Commit and push
7. Create PR via `gh pr create`
8. **Review with `/pr-review`.** Before requesting merge, run `/pr-review <PR>` (the user-level skill at `~/.claude/skills/pr-review/`). It reviews the PR in an independent subagent context for correctness against the linked issue, security, and design quality (modularity / abstraction / cohesion / separation of concerns / coupling), and posts findings as a PR comment via `gh`. **Mitigate based on its output:** address every `[critical]` / `[major]` finding (fix the code, or reply in the PR explaining why it does not apply), and resolve `[minor]` / `[nit]` findings or explicitly accept them. Re-run `/pr-review` after non-trivial changes.
9. **Merge is human-only.** Do **not** run `gh pr merge` (or any equivalent) yourself. Either a human merges the PR after CI passes, or wait for an explicit, in-conversation instruction from the user authorizing the merge for that specific PR. OCI deployment triggers automatically once the merge happens.

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
```

### Task Management
- Use GitHub Issues as the primary task tracker
- Use GitHub CLI (`gh`) for issue/PR management
