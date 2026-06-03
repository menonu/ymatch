#!/bin/bash
# Redeploy staging frontend only on OCI
# Run ON the OCI VM
#
# Usage: ./scripts/oci_redeploy_staging_frontend.sh [public_ip]

set -euo pipefail

REPO_DIR="$HOME/ymatch"
cd "$REPO_DIR"

# Auto-detect public IP
if [ -n "${1:-}" ]; then
  PUBLIC_IP="$1"
else
  PUBLIC_IP=$(curl -sf -H "Authorization: Bearer Oracle" \
    http://169.254.169.254/opc/v2/vnics/ | \
    python3 -c "import sys,json; print(json.load(sys.stdin)[0]['publicIp'])" 2>/dev/null || \
    curl -sf http://checkip.amazonaws.com || \
    echo "")
fi

if [ -z "$PUBLIC_IP" ]; then
  echo "ERROR: Could not detect public IP. Pass it as argument."
  exit 1
fi

export PUBLIC_IP
export API_BASE_URL="https://${PUBLIC_IP}.nip.io:8443"

echo "=== Rebuilding staging frontend (API_BASE_URL=${API_BASE_URL}) ==="
git pull --ff-only

docker compose -f docker-compose.oci.yml build \
  --build-arg API_BASE_URL="$API_BASE_URL" \
  staging_frontend

docker compose -f docker-compose.oci.yml up -d staging_frontend

echo "✅ Staging frontend redeployed"
echo "Staging: http://${PUBLIC_IP}:8080"
