#!/usr/bin/env bash
# OS package/security updates for the OCI VMs (#592).
#
# Runs ON the VM as root. The OS Update workflow pipes it over SSH so the VM
# never depends on a stale repo checkout:
#   ssh ubuntu@HOST "sudo bash -s -- --mode full --reboot if-required" < scripts/oci_os_update.sh
#
# Modes:
#   check     list pending upgrades only; refreshes package lists, but no config
#             write, no upgrade, no reboot
#   security  refresh managed unattended-upgrades config, apply security updates now
#   full      refresh managed config, apt-get full-upgrade (incl. Docker Engine)
#
# Reboot policy (--reboot): if-required (default) | never | always.
# A reboot is scheduled ~10s out via systemd-run so the SSH session exits
# cleanly before the host goes down.
#
# Final stdout lines are machine-readable KEY=value pairs (OS_UPDATE_*),
# parsed by the workflow for the job summary.
#
# Test: scripts/test_oci_os_update.sh (all system commands mocked).

set -euo pipefail

APT_CONF_DIR="${APT_CONF_DIR:-/etc/apt/apt.conf.d}"
REBOOT_REQUIRED_FILE="${REBOOT_REQUIRED_FILE:-/var/run/reboot-required}"
# Emitted so the workflow can prove a scheduled reboot actually happened.
BOOT_ID_FILE="${BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
APT_LOCK_TIMEOUT="${APT_LOCK_TIMEOUT:-600}"

# Docker Engine restarts dockerd (and every app container) on upgrade, so it is
# only upgraded by the supervised `full` run, never by unattended-upgrades.
DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

APT_OPTS=(
  -o "DPkg::Lock::Timeout=${APT_LOCK_TIMEOUT}"
  -o "Dpkg::Options::=--force-confdef"
  -o "Dpkg::Options::=--force-confold"
)

log() {
  echo "[os-update] $*"
}

die() {
  echo "[os-update] ERROR: $*" >&2
  exit 1
}

usage() {
  echo "Usage: $0 --mode check|security|full [--reboot if-required|never|always]" >&2
}

# Wait for apt-daily / cloud-init / a concurrent apt run to release dpkg.
wait_for_apt_lock() {
  if ! command -v fuser >/dev/null 2>&1; then
    log "fuser not found; relying on DPkg::Lock::Timeout"
    return 0
  fi
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
    [ "$waited" -lt "$APT_LOCK_TIMEOUT" ] || die "apt lock still held after ${APT_LOCK_TIMEOUT}s"
    log "waiting for apt lock..."
    sleep 5
    waited=$((waited + 5))
  done
}

write_unattended_config() {
  mkdir -p "$APT_CONF_DIR"

  cat >"$APT_CONF_DIR/20auto-upgrades" <<'EOF'
// Managed by ymatch scripts/oci_os_update.sh (#592) — overwritten on each run.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

  # Loaded after Ubuntu's 50unattended-upgrades, whose Allowed-Origins
  # (security + ESM pockets only) are kept as-is. Lists here are additive.
  {
    echo '// Managed by ymatch scripts/oci_os_update.sh (#592) — overwritten on each run.'
    echo 'Unattended-Upgrade::Package-Blacklist {'
    local pkg
    for pkg in "${DOCKER_PACKAGES[@]}"; do
      echo "    \"^${pkg//./\\.}\$\";"
    done
    echo '};'
    echo 'Unattended-Upgrade::Automatic-Reboot "false";'
    echo 'Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";'
    echo 'Unattended-Upgrade::Remove-New-Unused-Dependencies "true";'
    echo 'Unattended-Upgrade::Remove-Unused-Dependencies "true";'
  } >"$APT_CONF_DIR/52ymatch-unattended-upgrades"

  log "unattended-upgrades config written to $APT_CONF_DIR"
}

ensure_unattended_upgrades() {
  if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
    log "installing unattended-upgrades"
    apt-get "${APT_OPTS[@]}" install -y unattended-upgrades
  fi
  write_unattended_config
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
}

# Prints simulated "Inst ..." lines for every pending upgrade.
pending_upgrades() {
  apt-get -s -o Debug::NoLocking=1 full-upgrade 2>/dev/null | grep '^Inst ' || true
}

main() {
  local mode="" reboot="if-required"
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode)
        mode="${2:-}"
        shift 2 || { usage; exit 2; }
        ;;
      --reboot)
        reboot="${2:-}"
        shift 2 || { usage; exit 2; }
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage
        die "unknown argument: $1"
        ;;
    esac
  done

  case "$mode" in
    check | security | full) ;;
    *) usage; die "invalid --mode '$mode'" ;;
  esac
  case "$reboot" in
    if-required | never | always) ;;
    *) usage; die "invalid --reboot '$reboot'" ;;
  esac

  if [ "${OCI_OS_UPDATE_SKIP_ROOT_CHECK:-0}" != "1" ] && [ "$(id -u)" -ne 0 ]; then
    die "must run as root (pipe through 'sudo bash -s')"
  fi

  log "mode=$mode reboot=$reboot host=$(hostname 2>/dev/null || echo unknown)"

  wait_for_apt_lock
  apt-get "${APT_OPTS[@]}" update -q

  local pending
  pending="$(pending_upgrades)"
  if [ -n "$pending" ]; then
    log "pending upgrades:"
    echo "$pending"
  else
    log "no pending upgrades"
  fi
  local pending_count security_count
  pending_count="$(printf '%s' "$pending" | grep -c '^Inst ' || true)"
  # Heuristic: Inst lines whose candidate comes from a *-security pocket.
  security_count="$(printf '%s' "$pending" | grep -c -- '-security' || true)"

  case "$mode" in
    check)
      # Read-only: never reboot, whatever --reboot says.
      reboot="never"
      ;;
    security)
      ensure_unattended_upgrades
      log "applying security updates (unattended-upgrade)"
      # unattended-upgrade ignores DPkg::Lock::Timeout; re-check right before
      # it in case the apt timers enabled above just started.
      wait_for_apt_lock
      unattended-upgrade -v
      ;;
    full)
      ensure_unattended_upgrades
      log "applying full upgrade"
      apt-get "${APT_OPTS[@]}" full-upgrade -y
      apt-get "${APT_OPTS[@]}" autoremove -y --purge
      apt-get "${APT_OPTS[@]}" autoclean -y
      ;;
  esac

  local reboot_required="no" reboot_scheduled="no"
  [ -f "$REBOOT_REQUIRED_FILE" ] && reboot_required="yes"
  if [ "$reboot" = "always" ] || { [ "$reboot" = "if-required" ] && [ "$reboot_required" = "yes" ]; }; then
    log "scheduling reboot in 10s"
    systemd-run --on-active=10 --timer-property=AccuracySec=1s /bin/systemctl reboot
    reboot_scheduled="yes"
  elif [ "$reboot_required" = "yes" ]; then
    log "reboot required but not scheduled (--reboot $reboot)"
  fi

  echo "OS_UPDATE_MODE=$mode"
  echo "OS_UPDATE_PENDING=$pending_count"
  echo "OS_UPDATE_PENDING_SECURITY=$security_count"
  echo "OS_UPDATE_REBOOT_REQUIRED=$reboot_required"
  echo "OS_UPDATE_REBOOT_SCHEDULED=$reboot_scheduled"
  echo "OS_UPDATE_BOOT_ID=$(cat "$BOOT_ID_FILE" 2>/dev/null || echo unknown)"
}

main "$@"
