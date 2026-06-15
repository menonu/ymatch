# Running the Frontend-Driven E2E Tests

The test in `frontend/test/e2e/trade_lifecycle_e2e_test.dart` walks the full trade lifecycle through the real `ApiClient`. The critical assertion is the `toProto3Json()` body in step 5 — a 422 there means the [#202](https://github.com/menonu/ymatch/issues/202) regression has returned.

## Prerequisites

- Docker 23+ (BuildKit default), Flutter SDK matching `frontend/pubspec.yaml`, ~3 GB free disk
- Ports `3000` and `5432` free (the e2e stack and the dev stack both bind them)

## Run

```bash
# 1. Stop the dev stack (it also uses ports 3000/5432)
docker compose down

# 2. Start the e2e stack and wait for the backend to be healthy
docker compose -f docker-compose.e2e.yml up -d --build
for i in $(seq 1 60); do
  curl -sf http://localhost:3000/api/v1/system/status > /dev/null && \
    { echo "Backend up after ${i}s"; break; } || sleep 1
done

# 3. Run the test
cd frontend
flutter pub get
E2E_API_URL=http://localhost:3000 flutter test test/e2e/

# 4. Tear down (always use -v to wipe the tmpfs DB)
docker compose -f docker-compose.e2e.yml down -v
```

Or use the Taskfile shortcuts (same thing):

```bash
task e2e:up
task e2e:test
task e2e:down
```

`task e2e:test` depends on `e2e:up`; it does **not** run `e2e:down` automatically.

## When to rebuild the image

`docker compose up -d` re-uses the cached image. Rebuild (`docker compose -f docker-compose.e2e.yml build e2e_backend`) when you change:

- `backend/src/**` or `backend/migrations/**`
- `proto/**` (the backend embeds the generated Rust types)
- `backend.Dockerfile.prod`

Add `--no-cache` if the running container has stale code (e.g. a 422 with "unknown field" or a backend panic with `UnexpectedNullError`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `port is already allocated` (3000 or 5432) | `docker compose down` (the dev stack is running) |
| `failed to lookup address information` (backend panic at startup) | `docker compose -f docker-compose.e2e.yml down -v` then re-`up -d` (orphaned containers from a previous run) |
| Test gets 422 / unknown field | Rebuild: `docker compose -f docker-compose.e2e.yml build --no-cache e2e_backend` |
| Test hangs at "No PENDING match" | The auto-matcher runs every 60 s. The test waits up to 90 s. Check inventory rows: `docker exec ymatch_e2e_db psql -U ymatch_user -d ymatch_e2e -c "SELECT * FROM inventory;"` |

For more detail (stack structure, CI workflow, adding a new scenario), see the git history or ask in #213.
