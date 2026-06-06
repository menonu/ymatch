#!/bin/bash
# Redeploy staging frontend only on OCI
# Run ON the OCI VM
#
# Usage: ./scripts/oci_redeploy_staging_frontend.sh [public_ip]
#
# Optional env:
#   GH_TOKEN         - GitHub PAT for HTTPS git pull/clone
#   GH_SSH_KEY_PATH  - SSH deploy key for git pull/clone

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

REPO_DIR="$HOME/ymatch"
oci_sync_repo "$REPO_DIR"
cd "$REPO_DIR"

PUBLIC_IP="$(oci_detect_public_ip "${1:-}")"
export PUBLIC_IP
export API_BASE_URL="https://${PUBLIC_IP}.nip.io:8443"

echo "=== Rebuilding staging frontend (API_BASE_URL=${API_BASE_URL}) ==="

docker compose -f "$REPO_DIR/docker-compose.oci.yml" build \
  --build-arg API_BASE_URL="$API_BASE_URL" \
  staging_frontend

docker compose -f "$REPO_DIR/docker-compose.oci.yml" up -d staging_frontend

echo "✅ Staging frontend redeployed"
echo "Staging: http://${PUBLIC_IP}:8080"
