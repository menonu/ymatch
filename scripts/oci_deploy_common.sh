#!/bin/bash
# Common functions for OCI deploy scripts.
# Source this file from other deploy scripts.
#
# Provides:
#   oci_detect_public_ip [<ip>]      - auto-detect or pass-through
#   oci_sync_repo <repo_dir>         - git pull / clone (handles non-git, GH_TOKEN, etc.)
#   oci_get_git_hash <repo_dir>      - rev-parse or "manual"
#   oci_write_compose_env <dir> <vars...>  - write .env file for docker compose
#
# Required env (set by caller): DB_PASSWORD, STAGING_DB_PASSWORD, PUBLIC_IP, GIT_HASH
# Optional env:
#   GH_TOKEN            - GitHub PAT for HTTPS clone (preferred)
#   GH_SSH_KEY_PATH     - path to SSH key for git clone (alternative)

set -euo pipefail

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
