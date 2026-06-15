# Running the Frontend-Driven End-to-End Tests

This guide covers the E2E test suite introduced in [Issue #213](https://github.com/menonu/ymatch/issues/213). These tests drive the real `ApiClient` and protobuf-generated types against a live backend, exercising the wire contract that issue #202 broke (the trade-offer 422).

## What the E2E test covers

The single scenario test in `frontend/test/e2e/trade_lifecycle_e2e_test.dart` walks the full trade lifecycle:

1. Two users guest-login.
2. They create an event and two pieces of merch.
3. They set up cross-trade inventory (`HAVE` Card A, `WANT` Card B for one user, vice versa for the other).
4. Wait for the auto-matcher to produce a `PENDING` match.
5. Submit an offer using `OfferTradeRequest.toProto3Json()` (camelCase) — the exact request body the Flutter app sends.
6. The other user accepts the offer; both mark the trade `COMPLETED`; one user applies the inventory delta.

The critical assertion is **step 5**: the request body uses proto3-camelCase keys (`merchId`, `direction`, `quantity`). A 422 here means the #202 regression has returned.

## Prerequisites

- Docker (for the e2e stack)
- Flutter SDK (matches `frontend/pubspec.yaml` `environment.sdk`)
- ~10 GB free disk (the e2e backend image is built from `backend.Dockerfile.prod`)

## Local run

```bash
# Start the stack
task e2e:up

# Run the test
task e2e:test

# Tear down (wipes the e2e DB)
task e2e:down
```

Or, manually:

```bash
docker compose -f docker-compose.e2e.yml up -d --build
flutter test frontend/test/e2e/
docker compose -f docker-compose.e2e.yml down -v
```

The first run takes ~3-5 minutes (Rust compilation in the backend image). Subsequent runs are faster thanks to the BuildKit cache mounts in `backend.Dockerfile.prod`.

## CI run

`.github/workflows/ci-e2e.yml` runs on every push to `main` and on every PR. It:
1. Spins up the e2e stack via docker compose.
2. Waits up to 60 s for `GET /api/v1/system/status` to return 200.
3. Runs `flutter test test/e2e/`.
4. Dumps backend logs on failure.
5. Tears down the stack with `down -v`.

Total CI time: ~5-8 minutes on a warm cache.

## How the stack is structured

`docker-compose.e2e.yml` is intentionally minimal:

| Service | Image | Port | Notes |
|---|---|---|---|
| `e2e_db` | `postgres:16-alpine` | 5432 | tmpfs-backed (no persistence) |
| `e2e_backend` | built from `backend.Dockerfile.prod` | 3000 | runs `sqlx::migrate!` on startup |

No Caddy, no frontend container. The test is pure Dart that talks HTTP to `http://localhost:3000`.

## Adding a new E2E scenario

1. Add a new test in `frontend/test/e2e/<name>_e2e_test.dart`. Use the helpers from `trade_lifecycle_e2e_test.dart` (`_apiClient`, `_waitForBackend`, `_guestLogin`, etc.) if useful — consider extracting them to a shared helper file in a follow-up.
2. Use `ApiClient` directly, **not** the widget tree. The point of E2E is the wire contract.
3. Use `toProto3Json()` on protobuf messages instead of hand-writing JSON.
4. Use the `E2E_API_URL` env var (or default to `http://localhost:3000`).
5. The test database is wiped between runs (`down -v`), so do not rely on state from a previous test.

## Why this is separate from `flutter test integration_test/`

`integration_test/` is for on-device tests (driving a real Flutter app on an emulator). The E2E tests in `test/e2e/` are pure HTTP tests run by `flutter test` against a real backend — closer to an API contract test. The two are not the same.

## Related

- #202 — the trade offer 422 bug this test was created to prevent.
- #213 — the issue for adding these tests.
- #185 — the broader test suite audit (Phase 1 doc at `docs/explanation/test_audit.md`).
