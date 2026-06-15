# Test Suite Strategy (Phase 1 — #185)

**Scope:** Backend (Rust) + Frontend (Flutter) test framework, target distribution, and the highest-leverage gaps to close.
**Companion issue:** #185 — the issue tracks the **live data** (current test counts, current coverage). This document holds the **strategy** (the framework, the target shape, the gap list, the rationale). When the numbers change, update the issue, not the doc.

## 1. Framework: how to categorize a test

Tests are categorized into four layers adapted from the **Practical Test Pyramid** (Mike Cohn) and **The Testing Trophy** (Kent C. Dodds):

| Layer | Definition | Speed | Cost | Scope |
|---|---|---|---|---|
| **Unit** | Pure logic; no I/O; mocks/stubs only | <1 ms | Low | One function / module |
| **Integration** | Talks to one or more real dependencies (DB, HTTP) but not the full system | <1 s | Medium | Module or service boundary |
| **E2E** | Drives the system as a real client would, end-to-end through the deployed stack | seconds-minutes | High | Whole system |
| **Static** | Compile-time checks, lints, type checks | seconds | Very low | Whole codebase |

For the Rust backend, **Integration** includes any test that uses the real `PgPool` (including direct service-level tests that hit the DB). **E2E** is reserved for tests that drive the full HTTP stack **and** through a real frontend client.

## 2. Target distribution

### Backend → **Practical Test Pyramid**

The backend is a service with a stable HTTP contract. Most bugs are at module boundaries (handlers, services, repositories). A pyramid distribution — many focused unit tests, fewer integration tests at the boundary, very few E2E — is a good fit.

**Target proportions: ~50% unit, ~45% integration, ~5% E2E.** (Achieving 5% E2E means adding ~5 frontend-driven tests once the E2E workflow lands — see #213.)

### Frontend → **Testing Trophy**

The frontend is mostly UI + state. The Testing Trophy emphasizes **integration tests** (which in Flutter means widget tests + provider tests) over isolated unit tests, because most bugs live at the seam between widgets, providers, and async data.

**Target proportions: ~30% unit (models, validators, pure functions), ~50% integration (widget + provider), ~20% E2E (scenarios).**

### Why the different recommendations

- The backend's value comes from correctness of business logic under many input combinations. Unit tests pin that down cheaply.
- The frontend's value comes from user-facing flows. A pure unit test of a Riverpod provider can verify state transitions, but a widget test verifies that the provider's state is actually reflected in the UI — that's where the real risk is.

## 3. Highest-leverage gaps

| # | Gap | Codebase | Target layer | Why this first |
|---|---|---|---|---|
| 1 | State-machine unit tests for `MatchLifecycleService::offer` / `change_status` | Backend | Unit | Cheap to write, covers the highest-risk logic |
| 2 | Rate-limiter test | Backend | Unit | One-time fix for 0% coverage of `routes.rs` |
| 3 | Frontend E2E that exercises the real wire contract | Frontend | E2E | Closes the #202 gap permanently (#213) |
| 4 | Provider tests for each `lib/providers/*.dart` | Frontend | Integration | Highest-leverage gap in the frontend |
| 5 | Widget tests for the 5 most-used screens | Frontend | Integration | Catches render regressions |
| 6 | Model / validation tests | Frontend | Unit | Cheap, catches a real class of bugs |

For the **current** data behind these gaps (which tests exist today, current coverage %), see the data snapshot on issue #185.

## 4. Open questions for Phase 2

1. **#213 implementation order:** Should the frontend E2E (#213) be set up before or after the provider tests (#4)? The E2E requires a running backend in CI (#213 acceptance criteria), which is a non-trivial infra change. Starting #213 first means the infrastructure is ready for provider tests too.
2. **Frontend coverage threshold (#184):** Once coverage is wired up, what % should the gate be set to? The strategy says we want to push toward the trophy shape (~50% integration), so starting low (~30%) to avoid blocking the existing scenario tests, then ratcheting up, is a reasonable path.
3. **Test data setup for #213:** Should the E2E tests use a separate database with seeded data, or reset between tests with `TRUNCATE`? Current backend integration tests use the latter.

## 5. Process

- **Live data (test counts, coverage %) lives on the issue (#185).** A snapshot is posted as a Phase 1 deliverable comment. As test additions land, the snapshot is regenerated; the issue, not this doc, gets the update.
- **Strategy lives here.** Framework, target proportions, gap list, rationale, open questions. Update only when the strategy changes (e.g., a new framework is adopted, a gap is re-prioritized, a target is revised).
- **Each gap becomes its own issue or PR.** Gap #1 → unit tests for `MatchLifecycleService`. Gap #3 → #213 (already filed). Gaps #4-6 → future issues.

## 6. References

- Mike Cohn, *Succeeding with Agile* (2009).
- Kent C. Dodds, [The Testing Trophy and Testing Classifications](https://kentcdodds.com/blog/the-testing-trophy-and-testing-classifications).
- Backend coverage workflow: #178, current threshold in `coverage.yml`.
- Frontend coverage workflow: #184 (not yet implemented).
- E2E test motivation: #202 (the trade offer 422 bug), #213 (the E2E work).
- Live data snapshot: #185.
