#!/bin/bash
# Deploy ymatch PRODUCTION to OCI ARM instance
# Run this ON the OCI VM after SSH-ing in
#
# Usage:
#   DOMAIN=... DUCKDNS_TOKEN=... ./scripts/oci_deploy_production.sh <db_password> [public_ip]
#
# If public_ip is not provided, it auto-detects via the OCI metadata service.
#
# Required env (or prior ~/ymatch/.env):
#   DOMAIN           - primary FQDN (CI: GitHub variable OCI_DOMAIN)
# Optional env:
#   DUCKDNS_SUBDOMAIN - bare subdomain (default: first label of DOMAIN)
#   DUCKDNS_TOKEN    - DuckDNS account token (CI: secret DUCKDNS_TOKEN)
#   GH_TOKEN         - GitHub PAT for HTTPS git clone (avoids `gh` CLI auth)
#   GH_SSH_KEY_PATH  - path to SSH deploy key for git clone
#   DB_PASSWORD      - alternative to first positional argument

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

echo "=== ymatch PRODUCTION Deploy ==="
echo "Public IP: $PUBLIC_IP"
echo "Domain:    https://${DOMAIN}"
echo "Legacy:    https://${PUBLIC_IP}.nip.io  (→ redirect to Domain)"
echo ""

oci_sync_repo "$REPO_DIR"

# Determine env vars for docker compose.
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
export GIT_HASH
oci_update_duckdns
oci_write_oci_stack_env "$REPO_DIR"

cd "$REPO_DIR"

# Build and start production services
echo ""
echo "Building and starting production containers..."

# Build production frontend with correct API base URL (HTTPS via configured DOMAIN).
oci_compose "$REPO_DIR" build \
  --build-arg API_BASE_URL="https://${DOMAIN}" \
  --build-arg GIT_HASH="$GIT_HASH" \
  backend frontend caddy

oci_compose_up_stack "$REPO_DIR"

echo ""
echo "Waiting for production services to start..."
sleep 10

# Health check
echo ""
echo "=== Production Service Status ==="
oci_compose "$REPO_DIR" ps db backend frontend caddy || true

echo ""
echo "=== Production Health Check ==="
if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Production backend is healthy"
else
  echo "⏳ Production is still starting up (check: docker logs ymatch_backend)"
fi

echo ""
echo "=== Production Deployment Complete ==="
echo "Production URL: https://${DOMAIN}"
echo "Production API: https://${DOMAIN}/api/v1/events"
echo "Legacy nip.io:  https://${PUBLIC_IP}.nip.io  (redirects to DOMAIN)"
echo "SSH:            ssh ubuntu@${PUBLIC_IP}"

# Configure New Relic log forwarding (containers are running now)
oci_setup_nr_log_forwarding "oci-production" || echo "⚠️  NR log forwarding setup failed"
