#!/usr/bin/env bash
# Regression guard for #586: deploys must not depend on the DuckDNS API.
#   - deploy scripts do not run a one-shot DuckDNS update
#   - the ddns sidecar (compose profile) still keeps the A record fresh
#   - scripts/duckdns_update.sh stays (Terraform null_resource.duckdns_* uses it)
#
# Run: scripts/test_oci_deploy_dns.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE="$REPO_ROOT/docker-compose.oci.yml"

fail() {
  echo "❌ $*" >&2
  exit 1
}

pass() {
  echo "✅ $*"
}

# Every OCI deploy / redeploy entry point plus the shared library.
shopt -s nullglob
deploy_scripts=("$SCRIPT_DIR"/oci_deploy*.sh "$SCRIPT_DIR"/oci_redeploy*.sh)
shopt -u nullglob
[ "${#deploy_scripts[@]}" -ge 4 ] || fail "expected OCI deploy scripts under $SCRIPT_DIR"
for path in "${deploy_scripts[@]}"; do
  f="$(basename "$path")"
  if grep -nE 'oci_update_duckdns|duckdns_update\.sh|DUCKDNS_OPTIONAL' "$path"; then
    fail "$f still runs a deploy-time DuckDNS update; DNS errors must not block deploys"
  fi
done
pass "deploy scripts make no deploy-time DuckDNS API call"

grep -qE '^  duckdns:' "$COMPOSE" || fail "docker-compose.oci.yml lost the duckdns sidecar"
grep -q 'profiles: \["ddns"\]' "$COMPOSE" || fail "duckdns sidecar is not on the ddns profile"
grep -q 'services+=(duckdns)' "$SCRIPT_DIR/oci_deploy_common.sh" \
  || fail "oci_compose_up_stack no longer starts the duckdns sidecar"
pass "duckdns sidecar still started with the stack"

[ -x "$SCRIPT_DIR/duckdns_update.sh" ] || fail "scripts/duckdns_update.sh missing (Terraform uses it)"
pass "duckdns_update.sh kept for Terraform"

echo
echo "All OCI deploy DNS checks passed."
