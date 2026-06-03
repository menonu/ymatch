#!/bin/bash
# Deploy ymatch STAGING to OCI ARM instance
# Run this ON the OCI VM after SSH-ing in
#
# Usage: ./scripts/oci_deploy_staging.sh <staging_db_password> <production_db_password> [public_ip]
#
# production_db_password is required because docker-compose validates all service env vars.

set -euo pipefail

STAGING_DB_PASSWORD="${1:?Usage: $0 <staging_db_password> <production_db_password> [public_ip]}"
PROD_DB_PASSWORD="${2:?Usage: $0 <staging_db_password> <production_db_password> [public_ip]}"

# Auto-detect public IP from OCI metadata if not provided
if [ -n "${3:-}" ]; then
  PUBLIC_IP="$3"
else
  PUBLIC_IP=$(curl -sf -H "Authorization: Bearer Oracle" \
    http://169.254.169.254/opc/v2/vnics/ | \
    python3 -c "import sys,json; print(json.load(sys.stdin)[0]['publicIp'])" 2>/dev/null || \
    curl -sf http://checkip.amazonaws.com || \
    echo "")

  if [ -z "$PUBLIC_IP" ]; then
    echo "ERROR: Could not auto-detect public IP. Pass it as second argument."
    exit 1
  fi
fi

echo "=== ymatch STAGING Deploy ==="
echo "Public IP: $PUBLIC_IP"
echo "Staging URL: http://${PUBLIC_IP}:8080"
echo ""

REPO_DIR="$HOME/ymatch"

# Clone or pull the repo
if [ -d "$REPO_DIR" ]; then
  echo "Updating existing repo..."
  cd "$REPO_DIR"
  git pull --ff-only
else
  echo "Cloning repo..."
  cd "$HOME"
  gh repo clone menonu/ymatch ymatch
  cd "$REPO_DIR"
fi

# Build and start staging services
echo ""
echo "Building and starting staging containers..."
export PUBLIC_IP
export DB_PASSWORD="$PROD_DB_PASSWORD"
export STAGING_DB_PASSWORD="$STAGING_DB_PASSWORD"
export GIT_HASH=$(git rev-parse --short HEAD)

# Build staging frontend with correct API base URL (port 8080)
docker compose -f docker-compose.oci.yml build \
  --build-arg API_BASE_URL="https://${PUBLIC_IP}.nip.io:8443" \
  --build-arg GIT_HASH="$GIT_HASH" \
  staging_backend staging_frontend staging_caddy

# Start staging services only
docker compose -f docker-compose.oci.yml up -d staging_db staging_backend staging_frontend staging_caddy

echo ""
echo "Waiting for staging services to start..."
sleep 10

# Health check
echo ""
echo "=== Staging Service Status ==="
docker compose -f docker-compose.oci.yml ps staging_db staging_backend staging_frontend staging_caddy

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
