# Test Suite Audit (Phase 1 — #185)

**Date:** 2026-06-15
**Scope:** Backend (Rust) + Frontend (Flutter) test inventory and distribution analysis.
**Goal:** Categorize every test, compute current proportions, recommend a target, and identify the highest-leverage gaps before any new tests are written.

## 1. Methodology

Tests are categorized into four layers adapted from the **Practical Test Pyramid** (Mike Cohn) and **The Testing Trophy** (Kent C. Dodds):

| Layer | Definition | Speed | Cost | Scope |
|---|---|---|---|---|
| **Unit** | Pure logic; no I/O; mocks/stubs only | <1 ms | Low | One function / module |
| **Integration** | Talks to one or more real dependencies (DB, HTTP) but not the full system | <1 s | Medium | Module or service boundary |
| **E2E** | Drives the system as a real client would, end-to-end through the deployed stack | seconds-minutes | High | Whole system |
| **Static** | Compile-time checks, lints, type checks | seconds | Very low | Whole codebase |

For this audit, **Integration** in the Rust backend includes any test that uses the real `PgPool` (including direct service-level tests that hit the DB). **E2E** is reserved for tests that drive the full HTTP stack AND through a real frontend client.

## 2. Backend inventory (Rust)

Test command: `cd backend && cargo test`

### 2.1 Counts

| Layer | Count | % of total |
|---|---|---|
| Unit (`#[cfg(test)] mod tests` inside `src/`) | 25 | 25% |
| Integration (`backend/tests/api_tests.rs`) | 74 | 75% |
| E2E | 0 | 0% |
| **Total** | **99** | **100%** |

### 2.2 Unit test distribution

| File | Test count | Subject |
|---|---|---|
| `src/error.rs` | 9 | `AppError` HTTP status mapping |
| `src/services/permissions.rs` | 7 | `PermissionPolicy` decision matrix |
| `src/services/match_lifecycle.rs` | 5 | `MatchLifecycleService` helpers (state-machine pieces) |
| `src/handlers/matches.rs` | 1 | Match handler status codes |
| `src/handlers/mappers.rs` | 3 | DTO ↔ proto mappers |

### 2.3 Integration test distribution

All 74 integration tests live in a single file: `backend/tests/api_tests.rs`. The mix is dominated by HTTP + DB scenarios:

- Auth (guest login, JWT issuance): ~8 tests
- Events CRUD: ~12 tests
- Merchandise CRUD: ~10 tests
- Inventory (HAVE/WANT/TRADE): ~9 tests
- Matches (creation, filtering, status changes): ~12 tests
- Trade lifecycle (PENDING → OFFERED → ACCEPTED → COMPLETED → APPLIED): 1 monolith test + 11 small helpers
- Images / file storage: 4 tests
- Admin / permissions: 6 tests
- Favorites / event views: 8 tests
- Misc edge cases: 4 tests

### 2.4 Coverage (line %, per `cargo llvm-cov`)

As of PR #190 (commit `a5656f1`):

| Module | Line % | Note |
|---|---|---|
| `services/match_lifecycle.rs` | 90.5% | State machine is covered mostly by **one** big integration test |
| `matching.rs` | 96.6% | Auto-matcher tested in a single integration scenario |
| `routes.rs` rate limiter (governor) | 0% | **No test at all** |
| Other | mostly 80-100% | (full report at `coverage/lcov.info`) |

### 2.5 Gaps identified

1. **`MatchLifecycleService` state machine is untested in isolation.** The PENDING → OFFERED → ACCEPTED → COMPLETED → APPLIED transitions are exercised by exactly one integration test (`test_trade_lifecycle_offer_accept_complete_apply`). The other 11 small integration tests only check the surface (HTTP 200 / 422). If the state machine has a bug, the failure is opaque.
2. **Rate limiter is completely untested.** `governor` is configured in `routes.rs` but no test asserts a 429 is returned under load, or that whitelisted paths bypass it.
3. **No backend E2E test exists** that drives a request through a real HTTP client that uses the wire format a real client would (e.g. proto3 JSON with camelCase keys). This is exactly the gap that #202 slipped through.

## 3. Frontend inventory (Flutter)

Test command: `cd frontend && flutter test` (or `flutter test integration_test/` for E2E).

### 3.1 Counts

| Layer | Count | % of total |
|---|---|---|
| Unit (`test()`) | 15 | 45% |
| Widget (`testWidgets()`) | 4 | 12% |
| Scenario / E2E (`integration_test/`) | 14 | 42% |
| **Total** | **33** | **100%** |

### 3.2 Per-file breakdown

| File | Tests | Layer | Notes |
|---|---|---|---|
| `test/services/api_client_test.dart` | 15 | Unit | HTTP client, request/response mapping, no UI |
| `test/integration/image_upload_test.dart` | 4 | Scenario | Multipart upload; mocks the server |
| `test/scenarios/user_journey_test.dart` | 2 | E2E | Full user flow with widget tree |
| `test/scenarios/admin_journey_test.dart` | 3 | E2E | Admin actions |
| `test/screens/login_screen_test.dart` | 2 | Widget | Login form rendering |
| `integration_test/admin_permissions_test.dart` | 3 | E2E | Real backend (via `integration_test` package) |
| `integration_test/search_filter_test.dart` | 1 | E2E | Real backend |
| `integration_test/app_test.dart` | 1 | E2E | Real backend smoke |
| `test/chat_location_test.dart` | 1 | Unit | Chat message location field |
| `test/widget_test.dart` | 1 | Widget | Default app smoke |

### 3.3 Coverage (per `flutter test --coverage`)

Frontend coverage workflow does not yet exist (see #184). Line coverage is unknown.

### 3.4 Gaps identified

1. **Riverpod providers (`lib/providers/`) are entirely untested.** State transitions, async loading, error handling — none of this has a unit test. The scenario tests cover the happy path implicitly, but a bug in a provider surfaces as a hard-to-debug scenario failure.
2. **Data models (`lib/models/`) with non-trivial validation are untested.** A failing validation in a model is currently caught only at the UI layer.
3. **20+ screens have no widget test.** Of those, the most-used ones (event list, event detail, match detail, profile, settings) are the highest-leverage targets.
4. **No frontend test would have caught #202.** The scenario tests use the real `ApiClient` and proto3 JSON, but the failing case (`POST /matches` with a body that uses `merchId` instead of `merch_id`) was never asserted.

## 4. Current proportions

### 4.1 By test count

| Codebase | Unit | Integration | E2E |
|---|---|---|---|
| Backend | 25% | 75% | 0% |
| Frontend | 45% | 12% | 42% |

### 4.2 By lines of test code (rough)

| Codebase | LoC of test | LoC of `lib/` or `src/` | Ratio |
|---|---|---|---|
| Backend | ~4,800 (in `tests/` + `#[cfg(test)]`) | ~14,000 | 0.34 |
| Frontend | ~2,500 | ~10,300 | 0.24 |

## 5. Recommendation: target framework

### Backend → **Practical Test Pyramid**

The backend is a service with a stable HTTP contract. Most bugs are at module boundaries (handlers, services, repositories). A pyramid distribution — many focused unit tests, fewer integration tests at the boundary, very few E2E — is a good fit. **Target proportions: ~50% unit, ~45% integration, ~5% E2E.** (Achieving 5% E2E means adding ~5 frontend-driven tests once #213 lands.)

### Frontend → **Testing Trophy**

The frontend is mostly UI + state. The Testing Trophy emphasizes **integration tests** (which in Flutter means widget tests + provider tests) over isolated unit tests, because most bugs live at the seam between widgets, providers, and async data. **Target proportions: ~30% unit (models, validators, pure functions), ~50% integration (widget + provider), ~20% E2E (scenarios).**

### Why the different recommendations

- The backend's value comes from correctness of business logic under many input combinations. Unit tests pin that down cheaply.
- The frontend's value comes from user-facing flows. A pure unit test of a Riverpod provider can verify state transitions, but a widget test verifies that the provider's state is actually reflected in the UI — that's where the real risk is.

## 6. Highest-leverage gaps (proposed Phase 2+ work)

| # | Gap | Codebase | Target layer | Why this first |
|---|---|---|---|---|
| 1 | State-machine unit tests for `MatchLifecycleService::offer` / `change_status` | Backend | Unit | Cheap to write, covers the highest-risk logic |
| 2 | Rate-limiter test | Backend | Unit | One-time fix for 0% coverage of `routes.rs` |
| 3 | Frontend E2E that exercises the real wire contract | Frontend | E2E | Closes the #202 gap permanently |
| 4 | Provider tests for each `lib/providers/*.dart` | Frontend | Integration | Highest-leverage gap in the frontend |
| 5 | Widget tests for the 5 most-used screens | Frontend | Integration | Catches render regressions |
| 6 | Model / validation tests | Frontend | Unit | Cheap, catches a real class of bugs |

## 7. Open questions for Phase 2

1. **#213 implementation order:** Should the frontend E2E (#213) be set up before or after the provider tests (#4)? The E2E requires a running backend in CI (#213 acceptance criteria), which is a non-trivial infra change. Starting #213 first means the infrastructure is ready for provider tests too.
2. **Frontend coverage threshold (#184):** Once coverage is wired up, what % should the gate be set to? The audit suggests starting low (~30%) to avoid blocking the existing scenario tests, then ratcheting up.
3. **Test data setup for #213:** Should the E2E tests use a separate database with seeded data, or reset between tests with `TRUNCATE`? Current backend integration tests use the latter.

## 8. References

- Mike Cohn, *Succeeding with Agile* (2009).
- Kent C. Dodds, [The Testing Trophy and Testing Classifications](https://kentcdodds.com/blog/the-testing-trophy-and-testing-classifications).
- Backend coverage workflow: #178, current threshold 70% (post-#190).
- Frontend coverage workflow: #184 (not yet implemented).
- E2E test motivation: #202 (the trade offer 422 bug).
- Issue: #185.
