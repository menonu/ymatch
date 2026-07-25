#!/bin/bash
# Redeploy backend only on OCI
# Run ON the OCI VM
#
# Usage: ./scripts/oci_redeploy_backend.sh
#
# Optional env:
#   DOMAIN / DUCKDNS_SUBDOMAIN / DUCKDNS_TOKEN
#   GH_TOKEN         - GitHub PAT for HTTPS git pull/clone
#   GH_SSH_KEY_PATH  - SSH deploy key for git pull/clone
#   DB_PASSWORD      - reused from a previous deploy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

REPO_DIR="$HOME/ymatch"
oci_load_compose_env "$REPO_DIR"
oci_sync_repo "$REPO_DIR"
cd "$REPO_DIR"

# Always regenerate the .env file from current env vars to ensure it's
# consistent with this VM's deploy.
PUBLIC_IP="$(oci_detect_public_ip)"
DOMAIN="$(oci_resolve_domain "ymatch.duckdns.org")"
DUCKDNS_SUBDOMAIN="${DUCKDNS_SUBDOMAIN:-ymatch}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD env var required (or run oci_deploy_production.sh first)}"
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
export PUBLIC_IP DOMAIN DUCKDNS_SUBDOMAIN DB_PASSWORD GIT_HASH
oci_write_oci_stack_env "$REPO_DIR"

echo "=== Rebuilding backend ==="
oci_compose "$REPO_DIR" build backend
oci_compose "$REPO_DIR" up -d backend

echo "Waiting for backend to restart..."
sleep 5

if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Backend redeployed successfully"
else
  echo "⏳ Backend is still starting (check: docker logs ymatch_backend)"
fi
