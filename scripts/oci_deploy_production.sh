#!/bin/bash
# Deploy ymatch PRODUCTION to OCI ARM instance
# Run this ON the OCI VM after SSH-ing in
#
# Usage:
#   ./scripts/oci_deploy_production.sh <db_password> [public_ip]
#
# If public_ip is not provided, it auto-detects via the OCI metadata service.
#
# Optional env:
#   GH_TOKEN         - GitHub PAT for HTTPS git clone (avoids `gh` CLI auth)
#   GH_SSH_KEY_PATH  - path to SSH deploy key for git clone
#   DB_PASSWORD      - alternative to first positional argument

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

DB_PASSWORD="${DB_PASSWORD:-${1:?Usage: $0 <db_password> [public_ip]}}"
PUBLIC_IP="$(oci_detect_public_ip "${2:-}")"

echo "=== ymatch PRODUCTION Deploy ==="
echo "Public IP: $PUBLIC_IP"
echo "Production URL: https://${PUBLIC_IP}.nip.io"
echo ""

REPO_DIR="$HOME/ymatch"
oci_sync_repo "$REPO_DIR"

# Determine env vars for docker compose.
# `STAGING_DB_PASSWORD` is also required because docker-compose.oci.yml
# validates all services; default to DB_PASSWORD if not set.
STAGING_DB_PASSWORD="${STAGING_DB_PASSWORD:-$DB_PASSWORD}"
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
oci_write_compose_env "$REPO_DIR" DB_PASSWORD STAGING_DB_PASSWORD PUBLIC_IP GIT_HASH

cd "$REPO_DIR"

# Build and start production services
echo ""
echo "Building and starting production containers..."

# Build production frontend with correct API base URL (port 443)
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" build \
  --build-arg API_BASE_URL="https://${PUBLIC_IP}.nip.io" \
  --build-arg GIT_HASH="$GIT_HASH" \
  backend frontend caddy

# Start production services only
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" up -d \
  db backend frontend caddy

echo ""
echo "Waiting for production services to start..."
sleep 10

# Health check
echo ""
echo "=== Production Service Status ==="
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" ps \
  db backend frontend caddy

echo ""
echo "=== Production Health Check ==="
if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Production backend is healthy"
else
  echo "⏳ Production is still starting up (check: docker logs ymatch_backend)"
fi

echo ""
echo "=== Production Deployment Complete ==="
echo "Production URL: https://${PUBLIC_IP}.nip.io"
echo "Production API: https://${PUBLIC_IP}.nip.io/api/v1/events"
echo "SSH:            ssh ubuntu@${PUBLIC_IP}"

# Configure New Relic log forwarding (containers are running now)
oci_setup_nr_log_forwarding "oci-production" || echo "⚠️  NR log forwarding setup failed"
