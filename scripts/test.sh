#!/usr/bin/env bash
# Unified test runner for ymatch.
# Ensures a PostgreSQL test database is available, runs backend + frontend tests.
#
# Usage:
#   ./scripts/test.sh              # Run all tests (backend + frontend)
#   ./scripts/test.sh backend      # Backend only
#   ./scripts/test.sh frontend     # Frontend only
#   ./scripts/test.sh --ci         # CI mode (stricter: includes lint + fmt checks)
#
# Prerequisites:
#   - Docker Compose running (provides PostgreSQL on localhost:5432)
#   - Rust toolchain with clippy + rustfmt
#   - Flutter SDK
#
# Environment variables (all have defaults for local dev):
#   DATABASE_URL  — Postgres connection string for test DB
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CI_MODE=false
TARGET="all"
for arg in "$@"; do
  case "$arg" in
    --ci) CI_MODE=true ;;
    backend) TARGET="backend" ;;
    frontend) TARGET="frontend" ;;
  esac
done

DB_URL="${DATABASE_URL:-postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch_test}"

fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
pass() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${YELLOW}→ $1${NC}"; }

# ─── Ensure test database exists ─────────────────────────────────────────────
ensure_test_db() {
  info "Checking PostgreSQL connectivity..."
  if ! docker exec ymatch_db pg_isready -U ymatch_user -d ymatch >/dev/null 2>&1; then
    fail "PostgreSQL is not running. Start it with: docker compose up -d db"
  fi

  info "Ensuring ymatch_test database exists..."
  docker exec ymatch_db psql -U ymatch_user -d ymatch -tc \
    "SELECT 1 FROM pg_database WHERE datname = 'ymatch_test'" | grep -q 1 \
    || docker exec ymatch_db psql -U ymatch_user -d ymatch -c \
       "CREATE DATABASE ymatch_test OWNER ymatch_user;"
  pass "Test database ready"
}

# ─── Backend tests ───────────────────────────────────────────────────────────
run_backend() {
  info "Running backend tests..."
  cd backend

  if $CI_MODE; then
    info "  cargo fmt --check"
    cargo fmt -- --check || fail "cargo fmt found formatting issues (run: cargo fmt)"
    info "  cargo clippy"
    cargo clippy -- -D warnings || fail "clippy warnings found"
  fi

  info "  cargo test (--test-threads=1)"
  DATABASE_URL="$DB_URL" cargo test -- --test-threads=1 \
    || fail "Backend tests failed"
  pass "Backend tests passed"
  cd ..
}

# ─── Frontend tests ──────────────────────────────────────────────────────────
run_frontend() {
  info "Running frontend tests..."
  cd frontend
  flutter test --exclude-tags=integration || fail "Frontend tests failed"
  pass "Frontend tests passed"

  if $CI_MODE; then
    info "  flutter build web"
    flutter build web || fail "Frontend build failed"
  fi
  cd ..
}

# ─── Main ────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════"
echo " ymatch test runner  $(if $CI_MODE; then echo '[CI mode]'; fi)"
echo "═══════════════════════════════════════"

if [ "$TARGET" = "all" ] || [ "$TARGET" = "backend" ]; then
  ensure_test_db
  run_backend
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "frontend" ]; then
  run_frontend
fi

echo ""
pass "All tests passed!"
