#!/bin/bash
# Deploy ymatch to OCI ARM instance (full stack: production + staging)
# Run this ON the OCI VM after SSH-ing in
#
# Usage: ./scripts/oci_deploy.sh <db_password> [public_ip]
#
# If public_ip is not provided, it auto-detects via metadata service.
#
# Optional env:
#   GH_TOKEN         - GitHub PAT for HTTPS git clone (avoids `gh` CLI auth)
#   GH_SSH_KEY_PATH  - path to SSH deploy key for git clone

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

DB_PASSWORD="${DB_PASSWORD:-${1:?Usage: $0 <db_password> [public_ip]}}"
STAGING_DB_PASSWORD="${STAGING_DB_PASSWORD:-${DB_PASSWORD}}"
PUBLIC_IP="$(oci_detect_public_ip "${2:-}")"

echo "=== ymatch OCI Deploy (full stack) ==="
echo "Public IP: $PUBLIC_IP"
echo "App URL:   https://${PUBLIC_IP}.nip.io"
echo ""

REPO_DIR="$HOME/ymatch"
oci_sync_repo "$REPO_DIR"

# Determine env vars for docker compose
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
oci_write_compose_env "$REPO_DIR" DB_PASSWORD STAGING_DB_PASSWORD PUBLIC_IP GIT_HASH

cd "$REPO_DIR"

# Build and start all services
echo ""
echo "Building and starting containers (this may take 10-20 minutes on first run)..."

docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" build \
  --build-arg API_BASE_URL="https://${PUBLIC_IP}.nip.io" \
  --build-arg GIT_HASH="$GIT_HASH"

# Start services
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" up -d

echo ""
echo "Waiting for services to start..."
sleep 10

# Health check
echo ""
echo "=== Service Status ==="
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" ps

echo ""
echo "=== Health Check ==="
if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Backend is healthy"
else
  echo "⏳ Backend is still starting up (check: docker logs ymatch_backend)"
fi

echo ""
echo "=== Deployment Complete ==="
echo "App URL:     https://${PUBLIC_IP}.nip.io"
echo "API URL:     https://${PUBLIC_IP}.nip.io/api/v1/events"
echo "SSH:         ssh ubuntu@${PUBLIC_IP}"
echo ""
echo "Useful commands:"
echo "  docker compose -f docker-compose.oci.yml logs -f    # Follow all logs"
echo "  docker compose -f docker-compose.oci.yml ps         # Service status"
echo "  docker exec -it ymatch_db psql -U ymatch_user -d ymatch  # DB shell"
