---
name: dev-up
description: Idempotently bring up the ymatch local dev stack — Postgres (:5432) + backend API (:3000) + Flutter web (:8081) — only starting services that aren't already reachable, so re-running never spawns duplicates. Invoke as /dev-up. Pair with /dev-down (or the dev-down.sh script) to stop the app servers.
allowed-tools: Bash
---

# dev-up

Idempotently launches the full ymatch local development stack so you can run
the app in a browser. Safe to call repeatedly — each service is started only
if it is not already responding, so duplicate processes/containers are never
created.

## What it brings up

| Service   | Address                          | How                                   |
|-----------|----------------------------------|---------------------------------------|
| Postgres  | `localhost:5432` (container `ymatch_db`) | Docker — reuses the existing container if present, else `docker compose up -d db` |
| Backend   | `http://localhost:3000`          | `cargo run --bin backend` (auto-migrates on startup) |
| Flutter web | `http://localhost:8081`         | `flutter run -d web-server --web-port 8081 --release` |

The Flutter app derives its API base URL from the page host
(`{scheme}://{host}:3000`), so serving on `:8081` reaches the backend on
`:3000` automatically — no `--dart-define` needed.

`--release` on the frontend is intentional: it avoids the DWDS injected-client
error (#340) seen in debug web builds.

## Run it

```bash
bash "$(git rev-parse --show-toplevel)/.claude/skills/dev-up/dev-up.sh"
```

The script prints a status table and the URL to open (`http://localhost:8081`).
Logs land in `.claude/.dev-up/{backend,frontend}.log`.

### Idempotence guarantees
- **Postgres:** `docker start ymatch_db` (no-op if already running); container
  is only created when it doesn't exist, so there's never a name conflict.
- **Backend:** skipped if `GET /api/v1/system/status` already answers.
- **Frontend:** skipped if `GET :8081/index.html` already answers.
- Long-running servers are detached with `setsid` so they survive the agent's
  shell exiting; PIDs are recorded in `.claude/.dev-up/*.pid`.

### Optional overrides (env vars)
`POSTGRES_PORT`, `BACKEND_PORT`, `FRONTEND_PORT` — e.g.
`FRONTEND_PORT=8081 bash dev-up.sh`.

## Stop

```bash
bash "$(git rev-parse --show-toplevel)/.claude/skills/dev-up/dev-down.sh"        # stop backend + frontend only
bash "$(git rev-parse --show-toplevel)/.claude/skills/dev-up/dev-down.sh" --db   # also stop the Postgres container
```

`dev-down.sh` reads the PID files written by `dev-up.sh` and stops those
processes; Postgres is left running by default (pass `--db` to stop it too).

## Notes
- First backend compile can take a few minutes; the script waits up to 600s.
- The DB credentials are the dev defaults from `docker-compose.yml`
  (`ymatch_user` / `secure_dev_password` / db `ymatch`).
- This works from any worktree: the script resolves the repo root via
  `git rev-parse --show-toplevel`, so it picks up the correct
  `backend/` and `frontend/` dirs automatically.