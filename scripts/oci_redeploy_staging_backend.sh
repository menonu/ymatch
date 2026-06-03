#!/bin/bash
# Redeploy staging backend only on OCI
# Run ON the OCI VM
#
# Usage: ./scripts/oci_redeploy_staging_backend.sh

set -euo pipefail

REPO_DIR="$HOME/ymatch"
cd "$REPO_DIR"

echo "=== Rebuilding staging backend ==="
git pull --ff-only

docker compose -f docker-compose.oci.yml build staging_backend
docker compose -f docker-compose.oci.yml up -d staging_backend

echo "Waiting for staging backend to restart..."
sleep 5

if curl -sf "http://localhost:3001/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Staging backend redeployed successfully"
else
  echo "⏳ Staging backend is still starting (check: docker logs ymatch_staging_backend)"
fi
