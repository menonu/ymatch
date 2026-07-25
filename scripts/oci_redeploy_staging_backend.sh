#!/bin/bash
# Redeploy staging backend only on OCI
# Run ON the OCI staging VM (staging now uses the same stack as production; see
# issue #209 — same compose file, same container names).
#
# Usage: ./scripts/oci_redeploy_staging_backend.sh
#
# Optional env:
#   DOMAIN / DUCKDNS_SUBDOMAIN / DUCKDNS_TOKEN
#   GH_TOKEN         - GitHub PAT for HTTPS git pull/clone
#   GH_SSH_KEY_PATH  - SSH deploy key for git pull/clone
#   DB_PASSWORD      - reused from a previous deploy (the staging DB password)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

REPO_DIR="$HOME/ymatch"
oci_load_compose_env "$REPO_DIR"
oci_sync_repo "$REPO_DIR"
cd "$REPO_DIR"

# Regenerate .env from current env vars to ensure consistency.
PUBLIC_IP="$(oci_detect_public_ip)"
DOMAIN="$(oci_resolve_domain "ymatch-staging.duckdns.org")"
DUCKDNS_SUBDOMAIN="${DUCKDNS_SUBDOMAIN:-ymatch-staging}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD env var required (or run oci_deploy_staging.sh first)}"
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
export PUBLIC_IP DOMAIN DUCKDNS_SUBDOMAIN DB_PASSWORD GIT_HASH
oci_write_oci_stack_env "$REPO_DIR"

echo "=== Rebuilding staging backend ==="

oci_compose "$REPO_DIR" build backend
oci_compose "$REPO_DIR" up -d backend

echo "Waiting for staging backend to restart..."
sleep 5

if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Staging backend redeployed successfully"
else
  echo "⏳ Staging backend is still starting (check: docker logs ymatch_backend)"
fi
