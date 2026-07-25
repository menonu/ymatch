#!/bin/bash
# Deploy ymatch to an OCI ARM instance (the full stack for whichever VM this
# runs on — production or staging, which now use identical stacks on separate
# VMs; see issue #209). Prefer oci_deploy_production.sh / oci_deploy_staging.sh
# with DOMAIN set from the matching GitHub variable (issue #523).
# Run this ON the OCI VM after SSH-ing in
#
# Usage: DOMAIN=... ./scripts/oci_deploy.sh <db_password> [public_ip]
#
# If public_ip is not provided, it auto-detects via metadata service.
#
# Required env (or prior .env): DOMAIN
# Optional env: DUCKDNS_SUBDOMAIN / DUCKDNS_TOKEN — see oci_deploy_common.sh
#   GH_TOKEN         - GitHub PAT for HTTPS git clone (avoids `gh` CLI auth)
#   GH_SSH_KEY_PATH  - path to SSH deploy key for git clone

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

REPO_DIR="$HOME/ymatch"

# Resolve password before domain .env load so a positional arg is never
# overridden by a sticky DB_PASSWORD from a previous deploy.
if [ -n "${1:-}" ]; then
  DB_PASSWORD="$1"
fi
DB_PASSWORD="${DB_PASSWORD:?Usage: DOMAIN=... $0 <db_password> [public_ip] (or set DB_PASSWORD)}"
PUBLIC_IP="$(oci_detect_public_ip "${2:-}")"
export DB_PASSWORD PUBLIC_IP

oci_load_domain_env "$REPO_DIR"
oci_require_domain

echo "=== ymatch OCI Deploy (full stack) ==="
echo "Public IP: $PUBLIC_IP"
echo "Domain:    https://${DOMAIN}"
echo "Legacy:    https://${PUBLIC_IP}.nip.io  (→ redirect to Domain)"
echo ""

oci_sync_repo "$REPO_DIR"

# Determine env vars for docker compose
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
export GIT_HASH
oci_update_duckdns
oci_write_oci_stack_env "$REPO_DIR"

cd "$REPO_DIR"

# Build and start all services
echo ""
echo "Building and starting containers (this may take 10-20 minutes on first run)..."

oci_compose "$REPO_DIR" build \
  --build-arg API_BASE_URL="https://${DOMAIN}" \
  --build-arg GIT_HASH="$GIT_HASH"

oci_compose "$REPO_DIR" up -d

echo ""
echo "Waiting for services to start..."
sleep 10

# Health check
echo ""
echo "=== Service Status ==="
oci_compose "$REPO_DIR" ps

echo ""
echo "=== Health Check ==="
if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Backend is healthy"
else
  echo "⏳ Backend is still starting up (check: docker logs ymatch_backend)"
fi

echo ""
echo "=== Deployment Complete ==="
echo "App URL:     https://${DOMAIN}"
echo "API URL:     https://${DOMAIN}/api/v1/events"
echo "Legacy:      https://${PUBLIC_IP}.nip.io  (redirects to DOMAIN)"
echo "SSH:         ssh ubuntu@${PUBLIC_IP}"
echo ""
echo "Useful commands:"
echo "  docker compose -f docker-compose.oci.yml logs -f    # Follow all logs"
echo "  docker compose -f docker-compose.oci.yml ps         # Service status"
echo "  docker exec -it ymatch_db psql -U ymatch_user -d ymatch  # DB shell"
