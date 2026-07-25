#!/bin/bash
# Deploy ymatch STAGING to OCI ARM instance
# Run this ON the OCI staging VM after SSH-ing in
#
# Staging is a byte-identical stack to production (same compose file, same
# Caddyfile, same container names); it differs only by VM host, DB password,
# and DuckDNS subdomain. See issues #209 and #523.
#
# Usage:
#   ./scripts/oci_deploy_staging.sh <db_password> [public_ip]
#
# If public_ip is not provided, it auto-detects via the OCI metadata service.
#
# Optional env:
#   DOMAIN           - primary FQDN (default: ymatch-staging.duckdns.org)
#   DUCKDNS_SUBDOMAIN - bare subdomain for updater (default: ymatch-staging)
#   DUCKDNS_TOKEN    - DuckDNS account token (enables DNS update + ddns profile)
#   GH_TOKEN         - GitHub PAT for HTTPS git clone (avoids `gh` CLI auth)
#   GH_SSH_KEY_PATH  - path to SSH deploy key for git clone
#   DB_PASSWORD      - alternative to first positional argument

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

REPO_DIR="$HOME/ymatch"
oci_load_compose_env "$REPO_DIR"

DB_PASSWORD="${DB_PASSWORD:-${1:?Usage: $0 <db_password> [public_ip]}}"
PUBLIC_IP="$(oci_detect_public_ip "${2:-}")"
DOMAIN="$(oci_resolve_domain "ymatch-staging.duckdns.org")"
DUCKDNS_SUBDOMAIN="${DUCKDNS_SUBDOMAIN:-ymatch-staging}"
export DB_PASSWORD PUBLIC_IP DOMAIN DUCKDNS_SUBDOMAIN

echo "=== ymatch STAGING Deploy ==="
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

# Build and start staging services (same stack as production).
echo ""
echo "Building and starting staging containers..."

oci_compose "$REPO_DIR" build \
  --build-arg API_BASE_URL="https://${DOMAIN}" \
  --build-arg GIT_HASH="$GIT_HASH" \
  db backend frontend caddy

oci_compose_up_stack "$REPO_DIR"

echo ""
echo "Waiting for staging services to start..."
sleep 10

# Health check
echo ""
echo "=== Staging Service Status ==="
oci_compose "$REPO_DIR" ps db backend frontend caddy || true

echo ""
echo "=== Staging Health Check ==="
if curl -sf "http://localhost:3000/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Staging backend is healthy"
else
  echo "⏳ Staging is still starting up (check: docker logs ymatch_backend)"
fi

echo ""
echo "=== Staging Deployment Complete ==="
echo "Staging URL: https://${DOMAIN}"
echo "Staging API: https://${DOMAIN}/api/v1/events"
echo "Legacy nip.io: https://${PUBLIC_IP}.nip.io  (redirects to DuckDNS)"
echo "SSH:         ssh ubuntu@${PUBLIC_IP}"

# Configure New Relic log forwarding (containers are running now)
oci_setup_nr_log_forwarding "oci-staging" || echo "⚠️  NR log forwarding setup failed"
