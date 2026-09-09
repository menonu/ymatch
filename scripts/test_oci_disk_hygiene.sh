#!/usr/bin/env bash
# Regression guard for OCI disk hygiene (#581):
#   - oci_prune_build_cache invokes docker builder prune with --keep-storage
#   - deploy/redeploy scripts call the helper around builds
#   - docker-compose.oci.yml caps json-file logs (max-size 10m, max-file 3)
#
# Run: scripts/test_oci_disk_hygiene.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON="$SCRIPT_DIR/oci_deploy_common.sh"
COMPOSE="$REPO_ROOT/docker-compose.oci.yml"

fail() {
  echo "❌ $*" >&2
  exit 1
}

pass() {
  echo "✅ $*"
}

[ -f "$COMMON" ] || fail "missing $COMMON"
[ -f "$COMPOSE" ] || fail "missing $COMPOSE"

# ---------------------------------------------------------------------------
# 1. oci_prune_build_cache (mocked docker)
# ---------------------------------------------------------------------------
DOCKER_LOG="$(mktemp)"
DOCKER_RC=0
docker() {
  printf '%s\n' "$*" >>"$DOCKER_LOG"
  return "$DOCKER_RC"
}

# shellcheck source=oci_deploy_common.sh
source "$COMMON"

type oci_prune_build_cache >/dev/null 2>&1 \
  || fail "oci_prune_build_cache is not defined in oci_deploy_common.sh"

: >"$DOCKER_LOG"
DOCKER_RC=0
oci_prune_build_cache
cmd="$(cat "$DOCKER_LOG")"
[[ "$cmd" == *"builder prune"* ]] || fail "expected 'builder prune', got: $cmd"
[[ "$cmd" == *"--all"* ]] || fail "expected --all, got: $cmd"
[[ "$cmd" == *"--force"* ]] || fail "expected --force, got: $cmd"
[[ "$cmd" == *"--keep-storage=8GB"* ]] || fail "expected --keep-storage=8GB, got: $cmd"
pass "default prune: docker builder prune --all --force --keep-storage=8GB"

: >"$DOCKER_LOG"
OCI_BUILD_CACHE_KEEP=4GB oci_prune_build_cache
cmd="$(cat "$DOCKER_LOG")"
[[ "$cmd" == *"--keep-storage=4GB"* ]] || fail "OCI_BUILD_CACHE_KEEP ignored, got: $cmd"
pass "OCI_BUILD_CACHE_KEEP overrides keep-storage"

: >"$DOCKER_LOG"
DOCKER_RC=1
if ! oci_prune_build_cache; then
  fail "oci_prune_build_cache must warn-and-continue when docker prune fails"
fi
pass "prune failure is non-fatal"

rm -f "$DOCKER_LOG"
unset -f docker
DOCKER_RC=0

# ---------------------------------------------------------------------------
# 2. Deploy / redeploy scripts call the helper around builds
# ---------------------------------------------------------------------------
FULL_STACK_SCRIPTS=(
  "$SCRIPT_DIR/oci_deploy_production.sh"
  "$SCRIPT_DIR/oci_deploy_staging.sh"
  "$SCRIPT_DIR/oci_deploy.sh"
)
REDEPLOY_SCRIPTS=(
  "$SCRIPT_DIR/oci_redeploy_backend.sh"
  "$SCRIPT_DIR/oci_redeploy_frontend.sh"
  "$SCRIPT_DIR/oci_redeploy_staging_backend.sh"
  "$SCRIPT_DIR/oci_redeploy_staging_frontend.sh"
)

assert_prune_around_build() {
  local f="$1"
  python3 - "$f" <<'PY' || return 1
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
lines = []
for raw in path.read_text(encoding="utf-8").splitlines():
    stripped = raw.split("#", 1)[0].strip()
    if stripped:
        lines.append(stripped)

prune = [i for i, l in enumerate(lines) if l == "oci_prune_build_cache" or l.startswith("oci_prune_build_cache ")]
build = [i for i, l in enumerate(lines) if re.search(r"\bbuild\b", l) and "oci_compose" in l]
up = [
    i
    for i, l in enumerate(lines)
    if "oci_compose_up_stack" in l or re.search(r"\bup\b", l) and "oci_compose" in l
]
if len(prune) < 2:
    raise SystemExit(f"{path.name}: need >=2 oci_prune_build_cache calls, found {len(prune)}")
if not build:
    raise SystemExit(f"{path.name}: no oci_compose build call found")
if not up:
    raise SystemExit(f"{path.name}: no oci_compose up / oci_compose_up_stack call found")
if prune[0] >= build[0]:
    raise SystemExit(f"{path.name}: first oci_prune_build_cache must be before build")
if prune[-1] <= up[-1]:
    raise SystemExit(f"{path.name}: last oci_prune_build_cache must be after up")
print(f"{path.name}: prune around build/up ({len(prune)} calls)")
PY
}

for f in "${FULL_STACK_SCRIPTS[@]}" "${REDEPLOY_SCRIPTS[@]}"; do
  [ -f "$f" ] || fail "missing $f"
  out="$(assert_prune_around_build "$f" 2>&1)" || fail "$out"
  pass "$out"
done

# ---------------------------------------------------------------------------
# 3. Compose json-file log rotation on every service
# ---------------------------------------------------------------------------
python3 - "$COMPOSE" <<'PY'
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Service names are keys indented 2 spaces under `services:`.
services_block = re.search(r"(?m)^services:\n(.*?)(?=\n(?:networks|volumes):|\Z)", text, re.S)
if not services_block:
    raise SystemExit("could not find services: block")
names = re.findall(r"(?m)^  ([a-zA-Z0-9_-]+):", services_block.group(1))
if not names:
    raise SystemExit("no services found")

missing = []
for name in names:
    # Slice from this service key to the next 2-space key or end of services.
    pat = rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [a-zA-Z0-9_-]+:|\Z)"
    m = re.search(pat, services_block.group(1))
    if not m:
        missing.append(f"{name} (unparsed)")
        continue
    body = m.group(1)
    has_logging = bool(re.search(r"(?m)^    logging:", body))
    has_max_size = "max-size: \"10m\"" in body or "max-size: '10m'" in body or "*default-logging" in body
    has_max_file = "max-file: \"3\"" in body or "max-file: '3'" in body or "*default-logging" in body
    if not (has_logging and has_max_size and has_max_file):
        missing.append(name)

if "*default-logging" in text:
    if 'max-size: "10m"' not in text and "max-size: '10m'" not in text:
        raise SystemExit("logging anchor missing max-size: \"10m\"")
    if 'max-file: "3"' not in text and "max-file: '3'" not in text:
        raise SystemExit("logging anchor missing max-file: \"3\"")

if missing:
    raise SystemExit(
        "services missing json-file log caps (max-size 10m, max-file 3): "
        + ", ".join(missing)
    )
print("services with log caps: " + ", ".join(names))
PY
pass "docker-compose.oci.yml caps json-file logs on every service"

echo
echo "All OCI disk hygiene checks passed."
