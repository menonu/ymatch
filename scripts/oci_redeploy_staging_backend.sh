#!/bin/bash
# Redeploy staging backend only on OCI
# Run ON the OCI VM
#
# Usage: ./scripts/oci_redeploy_staging_backend.sh
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

echo "=== Rebuilding staging backend ==="

docker compose -f "$REPO_DIR/docker-compose.oci.yml" build staging_backend
docker compose -f "$REPO_DIR/docker-compose.oci.yml" up -d staging_backend

echo "Waiting for staging backend to restart..."
sleep 5

if curl -sf "http://localhost:3001/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Staging backend redeployed successfully"
else
  echo "⏳ Staging backend is still starting (check: docker logs ymatch_staging_backend)"
fi
