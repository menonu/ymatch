#!/bin/bash
# Common functions for OCI deploy scripts.
# Source this file from other deploy scripts.
#
# Provides:
#   oci_detect_public_ip [<ip>]      - auto-detect or pass-through
#   oci_load_compose_env <dir>       - source prior .env without overriding set vars
#   oci_resolve_domain <default>     - DOMAIN env or default FQDN
#   oci_compose_profile_args         - echo --profile ddns when DuckDNS token set
#   oci_update_duckdns               - one-shot DuckDNS A update (no-op if unset)
#   oci_sync_repo <repo_dir>         - git pull / clone (handles non-git, GH_TOKEN, etc.)
#   oci_get_git_hash <repo_dir>      - rev-parse or "manual"
#   oci_write_compose_env <dir> <vars...>  - write .env file for docker compose
#
# Required env (set by caller): DB_PASSWORD, PUBLIC_IP, DOMAIN, GIT_HASH
#   DOMAIN — public FQDN (e.g. from GitHub Actions var OCI_DOMAIN / OCI_DOMAIN_STAGING,
#            or the previous compose .env). No hardcoded hostname defaults in scripts.
# Optional env:
#   DUCKDNS_SUBDOMAIN   - bare DuckDNS name; default: first label of DOMAIN
#   DUCKDNS_TOKEN       - enable DNS keep-alive + one-shot update
#   GH_TOKEN            - GitHub PAT for HTTPS clone (preferred)
#   GH_SSH_KEY_PATH     - path to SSH key for git clone (alternative)

set -euo pipefail

# Directory of this common library (stable even when sourced).
_OCI_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-detect public IP from OCI metadata service
oci_detect_public_ip() {
  local ip="${1:-}"
  if [ -n "$ip" ]; then
    echo "$ip"
    return
  fi

  curl -sf -H "Authorization: Bearer Oracle" \
    http://169.254.169.254/opc/v2/vnics/ | \
    python3 -c "import sys,json; print(json.load(sys.stdin)[0]['publicIp'])" 2>/dev/null || \
    curl -sf http://checkip.amazonaws.com || \
    { echo "ERROR: Could not auto-detect public IP. Pass it as argument." >&2; return 1; }
}

# Source an existing compose .env so redeploys keep DOMAIN / DuckDNS settings
# when the caller did not re-export them. Does not override already-set env.
oci_load_compose_env() {
  local dir="${1:-$HOME/ymatch}"
  local env_file="$dir/.env"
  if [ ! -f "$env_file" ]; then
    return 0
  fi
  # Export only keys that are currently unset/empty.
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip blanks and comments.
    case "$line" in
      ''|\#*) continue ;;
    esac
    local key="${line%%=*}"
    local val="${line#*=}"
    # Strip matching single/double quotes from shlex.quote output.
    if [[ "$val" == \'*\' ]]; then
      val="${val:1:-1}"
    elif [[ "$val" == \"*\" ]]; then
      val="${val:1:-1}"
    fi
    if [ -z "${!key:-}" ]; then
      export "$key=$val"
    fi
  done < "$env_file"
}

# Require DOMAIN (from env, CI var, or prior .env). Derive DUCKDNS_SUBDOMAIN
# when unset as the first DNS label of DOMAIN (ymatch.example.org → ymatch).
# Call after oci_load_compose_env. Exports DOMAIN and DUCKDNS_SUBDOMAIN.
oci_require_domain() {
  if [ -z "${DOMAIN:-}" ]; then
    echo "ERROR: DOMAIN is required (set env DOMAIN, GitHub variable OCI_DOMAIN / OCI_DOMAIN_STAGING, or a prior .env)." >&2
    return 1
  fi
  if [ -z "${DUCKDNS_SUBDOMAIN:-}" ]; then
    DUCKDNS_SUBDOMAIN="${DOMAIN%%.*}"
  fi
  if [ -z "$DUCKDNS_SUBDOMAIN" ] || [ "$DUCKDNS_SUBDOMAIN" = "$DOMAIN" ]; then
    echo "ERROR: could not derive DUCKDNS_SUBDOMAIN from DOMAIN='$DOMAIN'; set DUCKDNS_SUBDOMAIN explicitly." >&2
    return 1
  fi
  export DOMAIN DUCKDNS_SUBDOMAIN
}

# True when DuckDNS keep-alive can be enabled for this deploy.
oci_duckdns_enabled() {
  [ -n "${DUCKDNS_TOKEN:-}" ] && [ -n "${DUCKDNS_SUBDOMAIN:-}" ]
}

# Run docker compose against docker-compose.oci.yml with the right --profile.
# Usage: oci_compose <repo_dir> <compose args...>
oci_compose() {
  local dir="${1:?repo dir required}"
  shift
  local profile_args=()
  if oci_duckdns_enabled; then
    profile_args=(--profile ddns)
  fi
  docker compose --env-file "$dir/.env" "${profile_args[@]}" \
    -f "$dir/docker-compose.oci.yml" "$@"
}

# One-shot DuckDNS update using PUBLIC_IP. No-op (with notice) when unset.
oci_update_duckdns() {
  if ! oci_duckdns_enabled; then
    echo "DuckDNS token/subdomain not set; skipping one-shot DNS update"
    return 0
  fi
  if [ -z "${PUBLIC_IP:-}" ]; then
    echo "PUBLIC_IP not set; skipping one-shot DNS update" >&2
    return 0
  fi
  DUCKDNS_DOMAIN="$DUCKDNS_SUBDOMAIN" \
    DUCKDNS_TOKEN="$DUCKDNS_TOKEN" \
    DUCKDNS_IP="$PUBLIC_IP" \
    "$_OCI_COMMON_DIR/duckdns_update.sh" \
    || echo "⚠️  DuckDNS one-shot update failed (sidecar may still heal)"
}

# Start the standard OCI stack; include duckdns when token is present.
oci_compose_up_stack() {
  local dir="${1:?repo dir required}"
  local services=(db backend frontend caddy)
  if oci_duckdns_enabled; then
    services+=(duckdns)
  fi
  oci_compose "$dir" up -d "${services[@]}"
}

# Sync the repo to the latest version.
# Handles three cases:
#   1. $repo_dir/.git exists  -> git pull --ff-only
#   2. $repo_dir exists but no .git  -> skip (e.g. deployed via rsync)
#   3. $repo_dir does not exist  -> clone via GH_TOKEN, SSH key, or gh CLI
oci_sync_repo() {
  local repo_dir="${1:-$HOME/ymatch}"

  if [ -d "$repo_dir/.git" ]; then
    echo "Updating existing repo..."
    (cd "$repo_dir" && git pull --ff-only)
  elif [ -d "$repo_dir" ]; then
    echo "Repo exists at $repo_dir but is not a git working tree, skipping update."
  else
    echo "Cloning repo..."
    if [ -n "${GH_TOKEN:-}" ]; then
      git clone "https://x-access-token:${GH_TOKEN}@github.com/menonu/ymatch.git" "$repo_dir"
    elif [ -n "${GH_SSH_KEY_PATH:-}" ]; then
      GIT_SSH_COMMAND="ssh -i ${GH_SSH_KEY_PATH} -o StrictHostKeyChecking=no" \
        git clone git@github.com:menonu/ymatch.git "$repo_dir"
    else
      gh repo clone menonu/ymatch ymatch
    fi
  fi
}

# Get current git short hash; "manual" if not a git repo.
oci_get_git_hash() {
  local repo_dir="${1:-$HOME/ymatch}"
  (cd "$repo_dir" && git rev-parse --short HEAD 2>/dev/null) || echo "manual"
}

# Configure New Relic log forwarding for the ymatch containers.
# Generates /etc/newrelic-infra/logging.d/docker-logs.yml and restarts the agent.
# Containers must already be running.
#
# Args (all optional):
#   $1 = environment label (default: "oci-production", e.g. "oci-staging")
oci_setup_nr_log_forwarding() {
  local env_label="${1:-oci-production}"
  local logging_dir="/etc/newrelic-infra/logging.d"
  local config_file="$logging_dir/docker-logs.yml"

  # Ensure logging.d exists with permissive permissions
  sudo mkdir -p "$logging_dir"

  # Find running container IDs by service name
  local backend_id caddy_id db_id
  backend_id=$(docker inspect --format='{{.Id}}' ymatch_backend 2>/dev/null || echo "")
  caddy_id=$(docker inspect --format='{{.Id}}' ymatch_caddy 2>/dev/null || echo "")
  db_id=$(docker inspect --format='{{.Id}}' ymatch_db 2>/dev/null || echo "")

  # Build a YAML block with whichever containers are present
  local logs_block=""
  if [ -n "$backend_id" ]; then
    logs_block="${logs_block}  - name: ymatch-backend
    file: /var/lib/docker/containers/${backend_id}/${backend_id}-json.log
    attributes:
      logtype: ymatch-backend
      service: backend
      environment: ${env_label}
"
  fi
  if [ -n "$caddy_id" ]; then
    logs_block="${logs_block}  - name: ymatch-caddy
    file: /var/lib/docker/containers/${caddy_id}/${caddy_id}-json.log
    attributes:
      logtype: ymatch-caddy
      service: caddy
      environment: ${env_label}
"
  fi
  if [ -n "$db_id" ]; then
    logs_block="${logs_block}  - name: ymatch-db
    file: /var/lib/docker/containers/${db_id}/${db_id}-json.log
    attributes:
      logtype: ymatch-db
      service: postgresql
      environment: ${env_label}
"
  fi

  if [ -z "$logs_block" ]; then
    echo "⚠️  No ymatch containers found; skipping NR log forwarding setup"
    return 0
  fi

  # Write config and restart agent (requires sudo).
  # The heredoc terminator (EOFLOGS) must be on its own line, so we
  # expand ${logs_block} via a separate printf and then append.
  {
    printf 'logs:\n%s' "$logs_block"
  } | sudo tee "$config_file" > /dev/null

  echo "✓ Wrote NR log forwarding config to $config_file"
  sudo systemctl restart newrelic-infra
  echo "✓ Restarted newrelic-infra"
}

# Write a .env file under <dir> for docker compose to consume.
# Reads variable names from the args and writes them in KEY=VALUE form.
# This avoids leaking secrets through `export ...` in the parent shell.
#
# Uses Python for shell-safe quoting so it works the same in bash and zsh.
oci_write_compose_env() {
  local dir="$1"
  shift
  local env_file="$dir/.env"

  : > "$env_file"
  for var in "$@"; do
    # Indirect expansion (POSIX-portable).
    local value
    value=$(eval "printf '%s' \"\${$var:-}\"")
    if [ -n "$value" ]; then
      # shellcheck disable=SC2016
      KEY="$var" VALUE="$value" python3 -c '
import os, shlex
key = os.environ["KEY"]
value = os.environ["VALUE"]
# shlex.quote produces a value safe to source from sh/bash/zsh.
print(f"{key}={shlex.quote(value)}")
' >> "$env_file"
    fi
  done
  echo "Wrote $(wc -l < "$env_file") env vars to $env_file"
}

# Standard env keys written for docker-compose.oci.yml (issue #523).
# Call after PUBLIC_IP / DOMAIN / DUCKDNS_* are set.
oci_write_oci_stack_env() {
  local dir="$1"
  oci_write_compose_env "$dir" \
    DB_PASSWORD PUBLIC_IP DOMAIN GIT_HASH \
    DUCKDNS_TOKEN DUCKDNS_SUBDOMAIN
}
