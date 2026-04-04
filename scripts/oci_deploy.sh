#!/bin/bash
# Deploy ymatch to OCI ARM instance
# Run this ON the OCI VM after SSH-ing in
#
# Usage: ./scripts/oci_deploy.sh <db_password> [public_ip]
#
# If public_ip is not provided, it auto-detects via metadata service.

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

echo "=== ymatch OCI Deploy ==="
echo "Public IP: $PUBLIC_IP"
echo "App URL:   https://${PUBLIC_IP}.nip.io"
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

# Build and start all services
echo ""
echo "Building and starting containers (this may take 10-20 minutes on first run)..."
export PUBLIC_IP DB_PASSWORD
export API_BASE_URL="https://${PUBLIC_IP}.nip.io"

# Build with the API_BASE_URL for frontend
docker compose -f docker-compose.oci.yml build \
  --build-arg API_BASE_URL="$API_BASE_URL"

# Start services
docker compose -f docker-compose.oci.yml up -d

echo ""
echo "Waiting for services to start..."
sleep 10

# Health check
echo ""
echo "=== Service Status ==="
docker compose -f docker-compose.oci.yml ps

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
