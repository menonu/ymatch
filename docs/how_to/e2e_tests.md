# Running the Frontend-Driven End-to-End Tests

This guide covers the E2E test suite introduced in [Issue #213](https://github.com/menonu/ymatch/issues/213). These tests drive the real `ApiClient` and protobuf-generated types against a live backend, exercising the wire contract that issue #202 broke (the trade-offer 422).

## What the E2E test covers

The single scenario test in `frontend/test/e2e/trade_lifecycle_e2e_test.dart` walks the full trade lifecycle:

1. Two users guest-login.
2. They create an event and two pieces of merch.
3. They set up cross-trade inventory (`TRADE` Card A, `WANT` Card B for one user, vice versa for the other).
4. Wait for the auto-matcher to produce a `PENDING` match.
5. Submit an offer using `OfferTradeRequest.toProto3Json()` (camelCase) — the exact request body the Flutter app sends.
6. The other user accepts the offer; both mark the trade `COMPLETED`; one user applies the inventory delta.

The critical assertion is **step 5**: the request body uses proto3-camelCase keys (`merchId`, `direction`, `quantity`). A 422 here means the #202 regression has returned.

The test takes ~40 s end-to-end locally (most of that is the 60 s matcher interval, plus a small startup buffer).

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Docker | 23+ | BuildKit default in 23+; the backend Dockerfile uses `--mount=type=cache` |
| Flutter | matches `frontend/pubspec.yaml` `environment.sdk` | tested with 3.38.5 |
| Rust | 1.85+ | only needed if you want to rebuild `ymatch-e2e_backend` from scratch |
| ~3 GB free disk | | the backend image is ~1.5 GB; postgres image ~250 MB |
| Ports `3000` and `5432` free | | see "Conflicts with the dev DB" below |

## Conflicts with the dev DB

The e2e stack and the local dev stack **both bind host port 5432** (postgres) and **3000** (backend). They cannot run at the same time. Always stop one before starting the other:

```bash
# Stop the dev stack before starting the e2e stack
docker compose down

# Or vice versa (stop the e2e stack before starting dev)
docker compose -f docker-compose.e2e.yml down -v
```

If you see `Bind for 0.0.0.0:5432 failed: port is already allocated`, the other stack is still running. The error message lists the conflicting container name.

## Reproducible local run (exact commands)

This is the canonical sequence. Every step has a verification so you know if it succeeded.

### 1. Stop any conflicting containers

```bash
# Stop the local dev stack (if running)
docker compose down

# Stop any leftover e2e stack (if a previous run didn't clean up)
docker compose -f docker-compose.e2e.yml down -v

# Sanity: nothing should be listening on 3000 or 5432
ss -ltn '( sport = :3000 or sport = :5432 )' || true
# (no output = ports are free)
```

### 2. Build the e2e backend image

The first run takes ~3 min (compiles Rust on ARM). Subsequent runs are fast because of the BuildKit cache mounts in `backend.Dockerfile.prod` for `/usr/local/cargo/registry` + `/usr/local/cargo/git`.

```bash
# Build with cache. Use --no-cache only if you suspect the cache is stale
# (e.g. the backend panicked on startup with code from an old build).
docker compose -f docker-compose.e2e.yml build e2e_backend
```

### 3. Start the stack

```bash
docker compose -f docker-compose.e2e.yml up -d e2e_db e2e_backend
```

This starts postgres (with tmpfs — no persistence) and the backend (which runs `sqlx::migrate!` on startup).

### 4. Wait for the backend to be healthy

```bash
# Up to 60s. Exits 0 on success, 1 on timeout.
for i in $(seq 1 60); do
  if curl -sf http://localhost:3000/api/v1/system/status > /dev/null; then
    echo "Backend healthy after ${i}s"
    exit 0
  fi
  sleep 1
done
echo "Backend did not become healthy in 60s"
docker compose -f docker-compose.e2e.yml logs e2e_backend
exit 1
```

Expected healthy response:

```json
{"backend_version":"e2e","resources":{...}}
```

### 5. Get Flutter dependencies

Only needs to run once per `pubspec.yaml` change:

```bash
cd frontend
flutter pub get
```

### 6. Run the test

```bash
cd frontend
E2E_API_URL=http://localhost:3000 flutter test test/e2e/
```

Expected: `+1: All tests passed!` after ~40 s.

### 7. Tear down

```bash
# Always use -v to wipe the tmpfs-backed DB. If you skip -v, the
# e2e_db volume persists, which can confuse the next run.
docker compose -f docker-compose.e2e.yml down -v
```

### All-in-one (copy-paste)

```bash
docker compose down && \
  docker compose -f docker-compose.e2e.yml down -v && \
  docker compose -f docker-compose.e2e.yml build e2e_backend && \
  docker compose -f docker-compose.e2e.yml up -d e2e_db e2e_backend && \
  ( for i in $(seq 1 60); do \
      curl -sf http://localhost:3000/api/v1/system/status > /dev/null && \
        { echo "Backend up after ${i}s"; break; } || sleep 1; \
    done ) && \
  ( cd frontend && flutter pub get && \
    E2E_API_URL=http://localhost:3000 flutter test test/e2e/ ) && \
  docker compose -f docker-compose.e2e.yml down -v
```

## Taskfile shortcuts

`Taskfile.yml` wraps the above into three tasks. They are equivalent to the manual sequence:

| Task | What it does |
|---|---|
| `task e2e:up` | `docker compose -f docker-compose.e2e.yml up -d --build` + wait for health |
| `task e2e:test` | `flutter pub get` + `flutter test test/e2e/` (with `E2E_API_URL`) |
| `task e2e:down` | `docker compose -f docker-compose.e2e.yml down -v` |

```bash
task e2e:up
task e2e:test
task e2e:down
```

`e2e:test` depends on `e2e:up` (declared in `Taskfile.yml`), so `task e2e:test` alone starts the stack, runs the test, and tears down — but it does **not** run `e2e:down` afterward. Run it explicitly to free the ports.

## Rebuilding the backend image

`docker compose up -d --build` re-uses the cached image if nothing has changed. For the e2e stack, this means:

| Change | Rebuild needed? |
|---|---|
| `frontend/lib/**` | No (the test is run from your local checkout, not the container) |
| `frontend/test/e2e/**` | No |
| `backend/src/**` | Yes — run `docker compose -f docker-compose.e2e.yml build e2e_backend` |
| `backend/migrations/**` | Yes — same as above (migrations run on backend startup) |
| `proto/**` | Yes — the backend binary embeds the generated Rust types |
| `backend.Dockerfile.prod` | Yes — same as above |

If you see a 422 from `/api/v1/matches/:id/offer` with a message about an "unknown field", or a backend panic with `UnexpectedNullError`, the running container has stale code. Force a rebuild:

```bash
docker compose -f docker-compose.e2e.yml down -v
docker compose -f docker-compose.e2e.yml build --no-cache e2e_backend
docker compose -f docker-compose.e2e.yml up -d e2e_db e2e_backend
```

## Inspecting the DB during a test run

Useful when a test fails and you need to see what state the DB is in:

```bash
# List matches
docker exec ymatch_e2e_db psql -U ymatch_user -d ymatch_e2e \
  -c "SELECT id, user1_id, user2_id, status, offered_by FROM matches;"

# List inventory rows
docker exec ymatch_e2e_db psql -U ymatch_user -d ymatch_e2e \
  -c "SELECT id, user_id, merch_id, status, quantity FROM inventory;"

# List merch
docker exec ymatch_e2e_db psql -U ymatch_user -d ymatch_e2e \
  -c "SELECT id, name, event_id FROM merchandise;"

# Tail backend logs in real time
docker logs -f ymatch_e2e_backend
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Bind for 0.0.0.0:5432 failed: port is already allocated` | The local dev stack is still running | `docker compose down` |
| `Bind for 0.0.0.0:3000 failed` | Another process (or the dev stack) is on 3000 | `docker compose down` or `lsof -i :3000` |
| `failed to lookup address information: Temporary failure in name resolution` (backend panic) | The compose default network wasn't created (e.g. previous run left orphaned containers) | `docker compose -f docker-compose.e2e.yml down -v` then re-`up -d` |
| Backend starts but `/api/v1/system/status` returns 404 | Stale image (older backend build) | `docker compose -f docker-compose.e2e.yml build --no-cache e2e_backend` |
| `Backend service unavailable` (during test) | Backend panicked (check `docker logs ymatch_e2e_backend`) | Usually a code regression; see the panic in the logs |
| `42x API Error: unknown field` | Stale image with old proto / request schema | Rebuild: `docker compose -f docker-compose.e2e.yml build --no-cache e2e_backend` |
| `Warning: A tag was used that wasn't specified in dart_test.yaml. e2e was used in the suite itself` | Expected; the test uses the `@Tags(['e2e'])` library annotation which `dart_test.yaml` doesn't list. Harmless. | None |
| Test hangs at "No PENDING match" | The matcher hasn't run yet (60 s interval) | Default timeout is 90 s; if a fresh DB has no inventory, the matcher creates a match within 60 s. Check inventory rows if it still hangs. |
| `flutter test` reports the test as "skipped" | `dart_test.yaml` skips the `integration` tag (not `e2e`); the test uses `e2e` so it runs | None — the test runs normally |

## How the stack is structured

`docker-compose.e2e.yml` is intentionally minimal:

| Service | Image | Port | Notes |
|---|---|---|---|
| `e2e_db` | `postgres:16-alpine` | 5432 | tmpfs-backed (no persistence between runs) |
| `e2e_backend` | built from `backend.Dockerfile.prod` | 3000 | runs `sqlx::migrate!` on startup |

No Caddy, no frontend container. The test is pure Dart that talks HTTP to `http://localhost:3000`. The flutter SDK and `frontend/.dart_tool/` are mounted from your local checkout — the test code runs locally, not inside the container.

## CI run

`.github/workflows/ci-e2e.yml` runs on every push to `main` and on every PR. It:

1. Builds the e2e_backend image with a buildx cache keyed on `backend/Cargo.lock` and `backend.Dockerfile.prod`.
2. Starts the stack via `docker compose -f docker-compose.e2e.yml up -d db backend`.
3. Waits up to 60 s for `GET /api/v1/system/status` to return 200.
4. Runs `flutter test test/e2e/` with `E2E_API_URL=http://localhost:3000`.
5. Dumps backend + db logs on failure.
6. Tears down with `down -v`.

Total CI time: ~5-8 min cold, ~2-3 min warm.

## Adding a new E2E scenario

1. Add a new test in `frontend/test/e2e/<name>_e2e_test.dart`. Use `@Tags(['e2e'])` at the library level (the `@integration` tag is unconditionally skipped by `frontend/dart_test.yaml`; the `@e2e` tag is what makes the test runnable by both the regular CI and the e2e workflow).
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
