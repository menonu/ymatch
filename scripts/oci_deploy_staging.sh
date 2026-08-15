#!/bin/bash
# Deploy ymatch STAGING to OCI ARM instance
# Run this ON the OCI staging VM after SSH-ing in
#
# Staging is a byte-identical stack to production (same compose file, same
# Caddyfile, same container names); it differs only by VM host, DB password,
# and DOMAIN. See issues #209 and #523.
#
# Usage:
#   DOMAIN=... DUCKDNS_TOKEN=... ./scripts/oci_deploy_staging.sh <db_password> [public_ip]
#
# If public_ip is not provided, it auto-detects via the OCI metadata service.
#
# Required env (or prior ~/ymatch/.env):
#   DOMAIN           - primary FQDN (CI: GitHub variable OCI_DOMAIN_STAGING)
# Optional env:
#   DUCKDNS_SUBDOMAIN - bare subdomain (default: first label of DOMAIN)
#   DUCKDNS_TOKEN    - DuckDNS account token (CI: secret DUCKDNS_TOKEN)
#   GH_TOKEN         - GitHub PAT for HTTPS git clone (avoids `gh` CLI auth)
#   GH_SSH_KEY_PATH  - path to SSH deploy key for git clone
#   DB_PASSWORD      - alternative to first positional argument
#   VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT
#                    - Web Push (#179); CI maps VAPID_*_STAGING secrets here
#   X_PROFILE_URL / DISCORD_INVITE_URL
#                    - Community card (#572); CI maps same-named GitHub secrets

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
  --build-arg X_PROFILE_URL="${X_PROFILE_URL:-}" \
  --build-arg DISCORD_INVITE_URL="${DISCORD_INVITE_URL:-}" \
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
echo "Legacy nip.io: https://${PUBLIC_IP}.nip.io  (redirects to DOMAIN)"
echo "SSH:         ssh ubuntu@${PUBLIC_IP}"

# Configure New Relic log forwarding (containers are running now)
oci_setup_nr_log_forwarding "oci-staging" || echo "⚠️  NR log forwarding setup failed"
