#!/bin/bash
# Redeploy backend only on OCI
# Run ON the OCI VM
#
# Usage: ./scripts/oci_redeploy_backend.sh

set -euo pipefail

REPO_DIR="$HOME/ymatch"
cd "$REPO_DIR"

echo "=== Rebuilding backend ==="
git pull --ff-only

docker compose -f docker-compose.oci.yml build backend
docker compose -f docker-compose.oci.yml up -d backend

echo "Waiting for backend to restart..."
sleep 5

if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Backend redeployed successfully"
else
  echo "⏳ Backend is still starting (check: docker logs ymatch_backend)"
fi
