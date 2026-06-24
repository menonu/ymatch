#!/bin/bash
# Deploy ymatch STAGING to OCI ARM instance
# Run this ON the OCI staging VM after SSH-ing in
#
# Staging is a byte-identical stack to production (same compose file, same
# Caddyfile, same container names); it differs only by VM host and DB password.
# See issue #209.
#
# Usage:
#   ./scripts/oci_deploy_staging.sh <db_password> [public_ip]
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

echo "=== ymatch STAGING Deploy ==="
echo "Public IP: $PUBLIC_IP"
echo "Staging URL: https://${PUBLIC_IP}.nip.io"
echo ""

REPO_DIR="$HOME/ymatch"
oci_sync_repo "$REPO_DIR"

# Determine env vars for docker compose.
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
oci_write_compose_env "$REPO_DIR" DB_PASSWORD PUBLIC_IP GIT_HASH

cd "$REPO_DIR"

# Build and start staging services (same stack as production).
echo ""
echo "Building and starting staging containers..."

# Build frontend with correct API base URL (same-origin over HTTPS via nip.io).
# Baking the full nip.io URL (no explicit port) makes API calls same-origin,
# which fixes the previous staging "backend connection error" caused by the
# frontend targeting https://<ip>:8443 while Caddy only served HTTP on :80.
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" build \
  --build-arg API_BASE_URL="https://${PUBLIC_IP}.nip.io" \
  --build-arg GIT_HASH="$GIT_HASH" \
  db backend frontend caddy

# Start all services
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" up -d \
  db backend frontend caddy

echo ""
echo "Waiting for staging services to start..."
sleep 10

# Health check
echo ""
echo "=== Staging Service Status ==="
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" ps \
  db backend frontend caddy

echo ""
echo "=== Staging Health Check ==="
if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Staging backend is healthy"
else
  echo "⏳ Staging is still starting up (check: docker logs ymatch_backend)"
fi

echo ""
echo "=== Staging Deployment Complete ==="
echo "Staging URL: https://${PUBLIC_IP}.nip.io"
echo "Staging API: https://${PUBLIC_IP}.nip.io/api/v1/events"
echo "SSH:         ssh ubuntu@${PUBLIC_IP}"

# Configure New Relic log forwarding (containers are running now)
oci_setup_nr_log_forwarding "oci-staging" || echo "⚠️  NR log forwarding setup failed"
