#!/bin/bash
# Redeploy frontend only on OCI
# Run ON the OCI VM
#
# Usage: DOMAIN=... ./scripts/oci_redeploy_frontend.sh [public_ip]
#
# Required env (or prior .env): DOMAIN, DB_PASSWORD
# Optional env:
#   DUCKDNS_SUBDOMAIN / DUCKDNS_TOKEN
#   VAPID_*          - sticky from prior .env if set by CI deploy (#179)
#   X_PROFILE_URL / DISCORD_INVITE_URL - Community card (#572); sticky from .env
#   GH_TOKEN         - GitHub PAT for HTTPS git pull/clone
#   GH_SSH_KEY_PATH  - SSH deploy key for git pull/clone

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=oci_deploy_common.sh
source "$SCRIPT_DIR/oci_deploy_common.sh"

REPO_DIR="$HOME/ymatch"
oci_load_domain_env "$REPO_DIR"
# Redeploy may omit secrets in the shell; restore sticky keys from prior .env.
oci_load_env_keys "$REPO_DIR" DB_PASSWORD \
  VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY VAPID_SUBJECT \
  X_PROFILE_URL DISCORD_INVITE_URL
oci_sync_repo "$REPO_DIR"
cd "$REPO_DIR"

PUBLIC_IP="$(oci_detect_public_ip "${1:-}")"
export PUBLIC_IP
oci_require_domain
export API_BASE_URL="https://${DOMAIN}"

# Regenerate .env from current env vars to ensure consistency.
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD env var required (or run oci_deploy_production.sh first)}"
GIT_HASH="$(oci_get_git_hash "$REPO_DIR")"
export DB_PASSWORD GIT_HASH
oci_write_oci_stack_env "$REPO_DIR"

echo "=== Rebuilding frontend (API_BASE_URL=${API_BASE_URL}) ==="

oci_compose "$REPO_DIR" build \
  --build-arg API_BASE_URL="$API_BASE_URL" \
  --build-arg X_PROFILE_URL="${X_PROFILE_URL:-}" \
  --build-arg DISCORD_INVITE_URL="${DISCORD_INVITE_URL:-}" \
  frontend

oci_compose "$REPO_DIR" up -d frontend

echo "✅ Frontend redeployed"
echo "App: https://${DOMAIN}"
