#!/usr/bin/env bash
# Stop the ymatch local dev app servers launched by dev-up.sh
# (backend on :3000, Flutter web on :8081). Postgres is left running by
# default — pass --db to also stop the `ymatch_db` container.
#
# Usage:  bash .claude/skills/dev-up/dev-down.sh [--db]

set -u
STOP_DB=0
[ "${1:-}" = "--db" ] && STOP_DB=1

REPO="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO" ]; then
  echo "ERROR: not inside a ymatch git worktree/repo." >&2
  exit 1
fi
LOGDIR="$REPO/.claude/.dev-up"

# Kill a recorded PID (if any), then fall back to matching the listening port.
kill_pidfile() {
  local pidfile="$1" label="$2"
  if [ -f "$pidfile" ]; then
    local pid; pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      printf "  ✓ %s stopped (pid %s)\n" "$label" "$pid"
      rm -f "$pidfile"
      return 0
    fi
    rm -f "$pidfile"
  fi
  return 1
}

echo "ymatch dev stack — stop"

kill_pidfile "$LOGDIR/backend.pid"  "backend"  || printf "  - backend: no recorded pid (already stopped)\n"
kill_pidfile "$LOGDIR/frontend.pid" "frontend" || printf "  - frontend: no recorded pid (already stopped)\n"

if [ "$STOP_DB" -eq 1 ]; then
  if command -v docker >/dev/null 2>&1 && docker inspect ymatch_db >/dev/null 2>&1; then
    docker stop ymatch_db >/dev/null 2>&1 && printf "  ✓ ymatch_db container stopped\n"
  else
    printf "  - ymatch_db: not present\n"
  fi
else
  printf "  - postgres left running (use --db to stop the container)\n"
fi
echo "done."