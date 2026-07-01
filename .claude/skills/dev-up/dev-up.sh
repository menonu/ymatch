#!/usr/bin/env bash
# Idempotently bring up the ymatch local dev stack:
#   - Postgres       on :5432  (Docker container `ymatch_db`)
#   - Backend API    on :3000  (`cargo run --bin backend`)
#   - Flutter web     on :8081  (`flutter run -d web-server --release`)
#
# Re-running this script is safe: each service is only started if it is not
# already reachable, so it never spawns duplicates and never fails because a
# service is already up. Long-running servers are detached with `setsid` so
# they survive the agent's shell exiting.
#
# Usage:  bash .claude/skills/dev-up/dev-up.sh
# Env:    none required (all defaults baked in). PORTS below may be overridden.

set -u

POSTGRES_PORT="${POSTGRES_PORT:-5432}"
BACKEND_PORT="${BACKEND_PORT:-3000}"
FRONTEND_PORT="${FRONTEND_PORT:-8081}"
DB_URL="postgres://ymatch_user:secure_dev_password@localhost:${POSTGRES_PORT}/ymatch"

REPO="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO" ]; then
  echo "ERROR: not inside a ymatch git worktree/repo." >&2
  exit 1
fi
LOGDIR="$REPO/.claude/.dev-up"
mkdir -p "$LOGDIR"

c_ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
c_warn() { printf "  \033[33m↻\033[0m %s\n" "$1"; }
c_fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; }

# Wait until `curl` succeeds against $1, up to $2 seconds (label $3).
wait_http() {
  local url="$1" timeout="$2" label="$3" i=0
  while [ "$i" -lt "$timeout" ]; do
    if curl -sf -o /dev/null "$url" 2>/dev/null; then
      return 0
    fi
    sleep 2
    i=$((i + 2))
    [ "$((i % 20))" -eq 0 ] && printf "      ...waiting for %s (%ds)\n" "$label" "$i"
  done
  return 1
}

echo "ymatch dev stack — idempotent launch"
echo "repo: $REPO"
echo

# ---------------------------------------------------------------------------
# 1. Postgres (Docker container `ymatch_db`)
# ---------------------------------------------------------------------------
echo "[1/3] Postgres on :${POSTGRES_PORT}"
if ! command -v docker >/dev/null 2>&1; then
  c_fail "docker not found on PATH"; exit 1
fi

if docker inspect ymatch_db >/dev/null 2>&1; then
  # Container exists — just ensure it's running (no-op if already up).
  docker start ymatch_db >/dev/null 2>&1
  c_ok "container ymatch_db started (or already running)"
else
  # First-time creation. Run from the repo root so the compose project name
  # matches the main repo and the `ymatch_db` container name is consistent.
  (cd "$REPO" && docker compose up -d db >/dev/null 2>&1) \
    && c_ok "created + started ymatch_db via docker compose" \
    || { c_fail "could not create ymatch_db"; exit 1; }
fi

# Wait for Postgres to accept connections.
if ! docker exec ymatch_db pg_isready -U ymatch_user -d ymatch >/dev/null 2>&1; then
  printf "      ...waiting for Postgres to accept connections\n"
  for i in $(seq 1 30); do
    docker exec ymatch_db pg_isready -U ymatch_user -d ymatch >/dev/null 2>&1 && break
    sleep 1
  done
fi
if docker exec ymatch_db pg_isready -U ymatch_user -d ymatch >/dev/null 2>&1; then
  c_ok "Postgres ready"
else
  c_fail "Postgres not ready after 30s"; exit 1
fi
echo

# ---------------------------------------------------------------------------
# 2. Backend API on :3000
# ---------------------------------------------------------------------------
echo "[2/3] Backend API on :${BACKEND_PORT}"
if curl -sf -o /dev/null "http://localhost:${BACKEND_PORT}/api/v1/system/status" 2>/dev/null; then
  c_ok "already up — skipping"
else
  c_warn "not running — launching (first compile can take a few minutes)…"
  setsid bash -c \
    "cd '$REPO/backend' && DATABASE_URL='$DB_URL' RUST_LOG=info cargo run --bin backend" \
    >"$LOGDIR/backend.log" 2>&1 < /dev/null &
  echo $! > "$LOGDIR/backend.pid"
  if wait_http "http://localhost:${BACKEND_PORT}/api/v1/system/status" 600 "backend"; then
    c_ok "backend up (log: $LOGDIR/backend.log)"
  else
    c_fail "backend did not come up in 600s — see $LOGDIR/backend.log"; exit 1
  fi
fi
echo

# ---------------------------------------------------------------------------
# 3. Flutter web on :8081  (--release avoids the DWDS injected-client error, #340)
# ---------------------------------------------------------------------------
echo "[3/3] Flutter web on :${FRONTEND_PORT}"
if curl -sf -o /dev/null "http://localhost:${FRONTEND_PORT}/index.html" 2>/dev/null; then
  c_ok "already up — skipping"
else
  c_warn "not running — launching (--release)…"
  setsid bash -c \
    "cd '$REPO/frontend' && flutter run -d web-server --web-port ${FRONTEND_PORT} --release" \
    >"$LOGDIR/frontend.log" 2>&1 < /dev/null &
  echo $! > "$LOGDIR/frontend.pid"
  if wait_http "http://localhost:${FRONTEND_PORT}/index.html" 300 "frontend"; then
    c_ok "frontend up (log: $LOGDIR/frontend.log)"
  else
    c_fail "frontend did not come up in 300s — see $LOGDIR/frontend.log"; exit 1
  fi
fi
echo

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "────────────────────────────────────────"
printf "  Postgres :  localhost:%s (container ymatch_db)\n" "$POSTGRES_PORT"
printf "  Backend  :  http://localhost:%s/api/v1/system/status\n" "$BACKEND_PORT"
printf "  Web app  :  http://localhost:%s  (open in browser)\n" "$FRONTEND_PORT"
echo "────────────────────────────────────────"
echo "Logs: $LOGDIR/{backend,frontend}.log"
echo
echo "To stop:  bash $REPO/.claude/skills/dev-up/dev-down.sh"