# Developer Quickstart Tutorial

This tutorial guides you through setting up a local development environment for `ymatch`, running the test suites, and starting the backend and frontend development servers.

---

## Prerequisites

Before starting, ensure you have the following tools installed on your local machine:
- **Docker & Docker Compose**: For running the PostgreSQL database.
- **Rust Toolchain**: `rustup`, `cargo`, etc. (for the backend).
- **Flutter SDK**: For running the mobile/web frontend.
- **Task (go-task)**: A task runner for running tests and setup scripts easily. See [taskfile.dev](https://taskfile.dev/) for installation.

---

## Step 1: Spin Up the Database

`ymatch` uses PostgreSQL for data persistence. We provide a pre-configured Docker Compose file to run the database.

1. Start the PostgreSQL and pgAdmin containers in the background:
   ```bash
   docker compose up -d
   ```

2. (First-time only) Create the test database required for running the backend integration tests:
   ```bash
   docker exec ymatch_db psql -U ymatch_user -d ymatch -c "CREATE DATABASE ymatch_test OWNER ymatch_user;"
   ```

### Database Connection Reference
* **URL**: `postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch`
* **pgAdmin UI**: [http://localhost:5050](http://localhost:5050)
  * **Email**: `admin@ymatch.com`
  * **Password**: `admin`

---

## Step 2: Run the Test Suites

To verify your environment is correctly configured, run the automated tests.

### Run All Tests
Use `task` (go-task) to automatically start the database containers (if not already running) and execute both backend and frontend test suites:
```bash
task test
```

### Run Service-Specific Tests
- **Backend integration tests**:
  ```bash
  task backend:test
  ```
  *(Note: Backend tests are run with `--test-threads=1` because they share a database instance and execute sequential setups).*

- **Frontend unit and widget tests**:
  ```bash
  task frontend:test
  ```

### Coverage reports

Both stacks write HTML + LCOV under each package’s `coverage/` directory.
Post-merge CI also runs these on `main` (see `.github/workflows/coverage.yml`
and `coverage-frontend.yml`); PR CI does not gate on coverage (#279). For
**risky** PRs you can still run the same workflows on a branch before merge
via `workflow_dispatch` — see
[Development Workflow Step 7a](../how_to/development_workflow.md#step-7a-optional-pre-merge-e2e-and-coverage-risky-prs).

```bash
task backend:coverage    # cargo-llvm-cov; ignores generated/
task frontend:coverage   # flutter test --coverage + filter script
```

**Frontend filtering (#453):** `scripts/frontend_coverage_report.sh` drops
generated sources from the headline number so it reflects hand-written app
code only:

| Excluded path | Why |
|---------------|-----|
| `lib/generated/**` | protobuf bindings (`scripts/proto-gen.sh`) |
| `lib/l10n/app_localizations*.dart` | `flutter gen-l10n` output |

- Raw Flutter output: `frontend/coverage/lcov.info`
- Filtered report (what CI gates on): `frontend/coverage/lcov.filtered.info`
- Optional HTML (needs `genhtml` from the `lcov` package):
  `frontend/coverage/html/index.html`

CI floor on the **filtered** line % is currently **68%** (baseline on main
after exclusion was ~71.5%; headroom so only real drops fail). Run the same
check locally:

```bash
# after task frontend:coverage, or after flutter test --coverage
scripts/frontend_coverage_report.sh frontend/coverage/lcov.info --threshold 68
```

---

## Step 3: Start Development Servers

To run the application locally, you must launch both the backend API server and the Flutter web frontend.

### 1. Launch the Backend API
Navigate to the `backend/` directory and run the API server under Axum:
```bash
cd backend
DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch cargo run --bin backend
```
The backend API server will start on port `3000`.

### 2. Launch the Frontend Web Server
Open a new terminal session, navigate to the `frontend/` directory, and launch the Flutter development server:
```bash
cd frontend
flutter run -d web-server --web-port 8081
```
The Flutter app will be available in your browser at `http://localhost:8081`.

### Multi-tab guest sessions (debug builds only)

To exercise two accounts at once (e.g. offer/accept a trade), open a second
browser tab as a different guest. **This only works in Flutter debug builds**
(`flutter run`); production/release builds ignore the override (#499).

**Option A — Admin Debug tab**

1. Sign in as an admin or moderator.
2. Open **Admin → Debug**.
3. Click **Open New Guest Session in Browser**. A new tab loads with a fresh
   guest UUID via `?dev_user=…` (hash route).

**Option B — URL by hand**

```text
http://localhost:8081/#/?dev_user=<uuid>
```

Use any UUID (or generate one). The tab logs in as that guest without writing
to `SharedPreferences`, so each tab keeps an independent session.

**Production note:** release builds never honor `dev_user` and never show the
Admin Debug tab. Do not rely on shareable query params for real sessions
(guest UUID is already a bearer secret; see also #373 for the planned
session-token model).

---

## Step 4: Run Linting and Code Style Checks

Before contributing, run the following code analysis checks to ensure your changes adhere to standard guidelines.

### Backend Linting (Rust)
```bash
cd backend
cargo fmt -- --check
cargo clippy -- -D warnings
```

### Frontend Linting (Flutter)
```bash
cd frontend
flutter analyze
```

---

## Next Steps

Now that you have your development environment up and running:
- Check out the [Architecture (arc42)](../explanation/architecture/README.md) to understand the project structure (C4 context, building blocks, deployment).
- Read the [API Specification](../reference/api_spec.md) to see available endpoints.
- Read [How to Deploy to OCI](../how_to/oci_deployment.md) when you are ready to prepare a release.
