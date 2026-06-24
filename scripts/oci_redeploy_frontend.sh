#!/bin/bash
# Redeploy frontend only on OCI
# Run ON the OCI VM
#
# Usage: ./scripts/oci_redeploy_frontend.sh [public_ip]
#
# Optional env:
#   GH_TOKEN         - GitHub PAT for HTTPS git pull/clone
#   GH_SSH_KEY_PATH  - SSH deploy key for git pull/clone
#   DB_PASSWORD      - reused from a previous deploy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

REPO_DIR="$HOME/ymatch"
oci_sync_repo "$REPO_DIR"
cd "$REPO_DIR"

PUBLIC_IP="$(oci_detect_public_ip "${1:-}")"
export PUBLIC_IP
export API_BASE_URL="https://${PUBLIC_IP}.nip.io"

# Regenerate .env from current env vars to ensure consistency.
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD env var required (or run oci_deploy_production.sh first)}"
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
oci_write_compose_env "$REPO_DIR" DB_PASSWORD PUBLIC_IP GIT_HASH

echo "=== Rebuilding frontend (API_BASE_URL=${API_BASE_URL}) ==="

docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" build \
  --build-arg API_BASE_URL="$API_BASE_URL" \
  frontend

docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" up -d frontend

echo "✅ Frontend redeployed"
echo "App: https://${PUBLIC_IP}.nip.io"
