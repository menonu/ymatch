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

## CI: post-merge on `main` + optional pre-merge dispatch

The GitHub workflow [`.github/workflows/ci-e2e.yml`](../../.github/workflows/ci-e2e.yml) (**Frontend E2E**) runs:

- **Automatically** on every push to `main` (post-merge gate; see #279)
- **Manually** via `workflow_dispatch` on any branch (risky pre-merge check)

PR validation does **not** include this job by default — `ci.yml` stays fast. A wire-contract regression can therefore land on `main` and need a follow-up; for high-risk changes, run E2E on the PR branch before merge.

### When to dispatch pre-merge

Run E2E on the PR branch when the change affects:

- **Proto / JSON wire contract** — `proto/**`, generated bindings, request bodies that use `toProto3Json()` (the #202 class of bug)
- **Match / trade lifecycle** — offer, accept, apply, cancel, matcher scheduling
- **E2E stack / compose** — `docker-compose.e2e.yml`, `backend.Dockerfile.prod`, e2e test sources under `frontend/test/e2e/`

Also consider backend/frontend **coverage** workflows for migrations, RBAC, or large refactors — full commands and “attach results on the PR” steps live in [Development Workflow — Step 7a](./development_workflow.md#step-7a-optional-pre-merge-e2e-and-coverage-risky-prs).

### Dispatch commands

```bash
BRANCH="$(git branch --show-current)"   # must be pushed to origin

gh workflow run ci-e2e.yml --ref "$BRANCH"

# Inspect / share the run (pin id so concurrent coverage runs do not mix)
RUN_ID="$(gh run list --workflow=ci-e2e.yml --branch "$BRANCH" --limit 1 --json databaseId -q '.[0].databaseId')"
gh run view "$RUN_ID" --web
```

Paste the run URL into the PR (description or comment) so reviewers can open the log without hunting Actions. Same pattern for coverage:

```bash
gh workflow run coverage.yml --ref "$BRANCH"
gh workflow run coverage-frontend.yml --ref "$BRANCH"
```

These dispatches are **optional**; do not block every PR on them unless the project later changes policy.

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

For more detail (stack structure, adding a new scenario), see the git history or #213. Pre-merge vs post-merge CI policy: #279, #456, and [development workflow Step 7a](./development_workflow.md#step-7a-optional-pre-merge-e2e-and-coverage-risky-prs).
