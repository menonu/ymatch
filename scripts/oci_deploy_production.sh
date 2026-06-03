#!/bin/bash
# Deploy ymatch PRODUCTION to OCI ARM instance
# Run this ON the OCI VM after SSH-ing in
#
# Usage: ./scripts/oci_deploy_production.sh <db_password> [public_ip]
#
# If public_ip is not provided, it auto-detects via metadata service.
# Expects a specific git tag/branch to deploy (e.g., release/1.0.0).

set -euo pipefail

DB_PASSWORD="${1:?Usage: $0 <db_password> [public_ip]}"

# Auto-detect public IP from OCI metadata if not provided
if [ -n "${2:-}" ]; then
  PUBLIC_IP="$2"
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

echo "=== ymatch PRODUCTION Deploy ==="
echo "Public IP: $PUBLIC_IP"
echo "Production URL: https://${PUBLIC_IP}.nip.io"
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

# Build and start production services
echo ""
echo "Building and starting production containers..."
export PUBLIC_IP
export DB_PASSWORD
export GIT_HASH=$(git rev-parse --short HEAD)

# Build production frontend with correct API base URL (port 443)
docker compose -f docker-compose.oci.yml build \
  --build-arg API_BASE_URL="https://${PUBLIC_IP}.nip.io" \
  --build-arg GIT_HASH="$GIT_HASH" \
  backend frontend caddy

# Start production services only
docker compose -f docker-compose.oci.yml up -d db backend frontend caddy

echo ""
echo "Waiting for production services to start..."
sleep 10

# Health check
echo ""
echo "=== Production Service Status ==="
docker compose -f docker-compose.oci.yml ps db backend frontend caddy

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
