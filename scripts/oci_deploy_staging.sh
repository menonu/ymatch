#!/bin/bash
# Deploy ymatch STAGING to OCI ARM instance
# Run this ON the OCI VM after SSH-ing in
#
# Usage:
#   ./scripts/oci_deploy_staging.sh <staging_db_password> <production_db_password> [public_ip]
#
# The production_db_password is required because docker-compose validates
# all service env vars (DB_PASSWORD is also referenced by production services).
#
# Optional env:
#   GH_TOKEN         - GitHub PAT for HTTPS git clone
#   GH_SSH_KEY_PATH  - SSH deploy key for git clone
#   STAGING_DB_PASSWORD / DB_PASSWORD / PROD_DB_PASSWORD - alternative to args

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

STAGING_DB_PASSWORD="${STAGING_DB_PASSWORD:-${1:?Usage: $0 <staging_db_password> <production_db_password> [public_ip]}}"
# Accept DB_PASSWORD as a fallback for PROD_DB_PASSWORD (the latter name is
# clearer in scripts that take both passwords as args; the former is the
# conventional name used in the CI workflows).
PROD_DB_PASSWORD="${PROD_DB_PASSWORD:-${DB_PASSWORD:-${2:?Usage: $0 <staging_db_password> <production_db_password> [public_ip]}}}"
PUBLIC_IP="$(oci_detect_public_ip "${3:-}")"

echo "=== ymatch STAGING Deploy ==="
echo "Public IP: $PUBLIC_IP"
echo "Staging URL: http://${PUBLIC_IP}:8080"
echo ""

REPO_DIR="$HOME/ymatch"
oci_sync_repo "$REPO_DIR"

# Determine env vars for docker compose.
# DB_PASSWORD is the production DB password; the compose file requires it
# because it references both production and staging services.
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
oci_write_compose_env "$REPO_DIR" DB_PASSWORD STAGING_DB_PASSWORD PUBLIC_IP GIT_HASH

# Also expose for docker compose substitution
cd "$REPO_DIR"
DB_PASSWORD="$PROD_DB_PASSWORD"
STAGING_DB_PASSWORD="$STAGING_DB_PASSWORD"
oci_write_compose_env "$REPO_DIR" DB_PASSWORD STAGING_DB_PASSWORD PUBLIC_IP GIT_HASH

# Build and start staging services
echo ""
echo "Building and starting staging containers..."

# Build staging frontend with correct API base URL (port 8443)
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" build \
  --build-arg API_BASE_URL="https://${PUBLIC_IP}.nip.io:8443" \
  --build-arg GIT_HASH="$GIT_HASH" \
  staging_backend staging_frontend staging_caddy

# Start staging services only
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" up -d \
  staging_db staging_backend staging_frontend staging_caddy

echo ""
echo "Waiting for staging services to start..."
sleep 10

# Health check
echo ""
echo "=== Staging Service Status ==="
docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-compose.oci.yml" ps \
  staging_db staging_backend staging_frontend staging_caddy

echo ""
echo "=== Staging Health Check ==="
if curl -sf "http://localhost:3001/api/v1/events" > /dev/null 2>&1; then
  echo "✅ Staging backend is healthy"
elif curl -sf "http://localhost:8080/" > /dev/null 2>&1; then
  echo "✅ Staging frontend is reachable"
else
  echo "⏳ Staging is still starting up (check: docker logs ymatch_staging_backend)"
fi

echo ""
echo "=== Staging Deployment Complete ==="
echo "Staging URL: http://${PUBLIC_IP}:8080"
echo "Staging API: http://${PUBLIC_IP}:8080/api/v1/events"
echo "SSH:         ssh ubuntu@${PUBLIC_IP}"
