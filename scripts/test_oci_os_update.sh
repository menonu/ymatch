#!/usr/bin/env bash
# Regression guard for OCI OS package/security updates (#592):
#   - argument validation (mode / reboot policy)
#   - unattended-upgrades config: security-only, Docker blacklisted, no auto-reboot
#   - check mode is read-only (no config write, no upgrade, never reboots)
#   - security mode runs unattended-upgrade; full mode runs apt-get full-upgrade
#   - reboot policy honours /var/run/reboot-required
#
# All system commands are mocked; nothing touches the host.
# Run: scripts/test_oci_os_update.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE="$SCRIPT_DIR/oci_os_update.sh"

fail() {
  echo "❌ $*" >&2
  exit 1
}

pass() {
  echo "✅ $*"
}

[ -f "$UPDATE" ] || fail "missing $UPDATE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "11111111-2222-3333-4444-555555555555" >"$WORK/boot_id"

# ---------------------------------------------------------------------------
# Mocks: every system command appends its argv to $CMD_LOG.
# ---------------------------------------------------------------------------
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
for cmd in apt-get unattended-upgrade systemctl systemd-run fuser dpkg; do
  cat >"$MOCK_BIN/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >>"\$CMD_LOG"
case "$cmd \$*" in
  "apt-get -s"*) printf 'Inst libfoo [1.0] (1.1 Ubuntu:24.04/noble-security [arm64])\nInst bar [2.0] (2.1 Ubuntu:24.04/noble-updates [arm64])\n' ;;
  "fuser"*) exit 1 ;;  # lock is free
esac
exit 0
EOF
  chmod +x "$MOCK_BIN/$cmd"
done

# run_update <case-name> [args...] — runs the script with a fresh fake root.
# Sets OUT (stdout+stderr), RC, and CMDS (mocked command log).
run_update() {
  local name="$1"
  shift
  CASE_DIR="$WORK/$name"
  mkdir -p "$CASE_DIR/apt.conf.d"
  : >"$CASE_DIR/cmd.log"
  set +e
  OUT="$(
    PATH="$MOCK_BIN:$PATH" \
      CMD_LOG="$CASE_DIR/cmd.log" \
      APT_CONF_DIR="$CASE_DIR/apt.conf.d" \
      REBOOT_REQUIRED_FILE="$CASE_DIR/reboot-required" \
      BOOT_ID_FILE="$WORK/boot_id" \
      OCI_OS_UPDATE_SKIP_ROOT_CHECK=1 \
      bash "$UPDATE" "$@" 2>&1
  )"
  RC=$?
  set -e
  CMDS="$(cat "$CASE_DIR/cmd.log")"
}

# ---------------------------------------------------------------------------
# 1. Argument validation
# ---------------------------------------------------------------------------
run_update bad-mode --mode yolo
[ "$RC" -ne 0 ] || fail "invalid --mode should fail"
[[ "$OUT" == *"invalid --mode"* ]] || fail "expected 'invalid --mode' error, got: $OUT"

run_update bad-reboot --mode full --reboot sometimes
[ "$RC" -ne 0 ] || fail "invalid --reboot should fail"
[[ "$OUT" == *"invalid --reboot"* ]] || fail "expected 'invalid --reboot' error, got: $OUT"
pass "rejects invalid --mode / --reboot"

# ---------------------------------------------------------------------------
# 2. check mode: read-only, never reboots
# ---------------------------------------------------------------------------
run_update check --mode check --reboot always
[ "$RC" -eq 0 ] || fail "check mode failed: $OUT"
[ -z "$(ls -A "$CASE_DIR/apt.conf.d")" ] || fail "check mode must not write apt config"
[[ "$CMDS" != *"full-upgrade -y"* && "$CMDS" != *"unattended-upgrade"* ]] \
  || fail "check mode must not upgrade, got: $CMDS"
[[ "$CMDS" != *"systemd-run"* ]] || fail "check mode must never reboot, got: $CMDS"
[[ "$OUT" == *"OS_UPDATE_PENDING=2"* ]] || fail "expected OS_UPDATE_PENDING=2, got: $OUT"
[[ "$OUT" == *"OS_UPDATE_PENDING_SECURITY=1"* ]] || fail "expected OS_UPDATE_PENDING_SECURITY=1, got: $OUT"
[[ "$OUT" == *"OS_UPDATE_REBOOT_SCHEDULED=no"* ]] || fail "expected REBOOT_SCHEDULED=no, got: $OUT"
[[ "$OUT" == *"OS_UPDATE_BOOT_ID=11111111-2222-3333-4444-555555555555"* ]] \
  || fail "expected OS_UPDATE_BOOT_ID from boot_id file, got: $OUT"
pass "check mode is read-only and reports pending counts"

# ---------------------------------------------------------------------------
# 3. security mode: managed unattended-upgrades config + immediate run
# ---------------------------------------------------------------------------
run_update security --mode security --reboot never
[ "$RC" -eq 0 ] || fail "security mode failed: $OUT"
UU="$CASE_DIR/apt.conf.d/52ymatch-unattended-upgrades"
AUTO="$CASE_DIR/apt.conf.d/20auto-upgrades"
[ -f "$UU" ] || fail "missing $UU"
[ -f "$AUTO" ] || fail "missing $AUTO"
grep -q 'Automatic-Reboot "false"' "$UU" || fail "auto-reboot must be disabled"
for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  grep -qF "\"^${pkg//./\\.}\$\";" "$UU" || fail "Docker package $pkg must be blacklisted"
done
grep -q 'Remove-Unused-Kernel-Packages "true"' "$UU" || fail "unused kernels must be removed"
grep -q 'APT::Periodic::Unattended-Upgrade "1"' "$AUTO" || fail "daily unattended-upgrade must be enabled"
grep -q 'APT::Periodic::Update-Package-Lists "1"' "$AUTO" || fail "daily list refresh must be enabled"
[[ "$CMDS" == *"unattended-upgrade -v"* ]] || fail "security mode must run unattended-upgrade, got: $CMDS"
[[ "$CMDS" != *"full-upgrade -y"* ]] || fail "security mode must not full-upgrade, got: $CMDS"
[[ "$CMDS" == *"systemctl enable --now apt-daily.timer apt-daily-upgrade.timer"* ]] \
  || fail "apt timers must be enabled, got: $CMDS"
# unattended-upgrade ignores DPkg::Lock::Timeout, so the lock must be
# re-checked immediately before it (apt timers may have just started).
before_uu="$(grep -B1 '^unattended-upgrade -v' "$CASE_DIR/cmd.log" | head -1)"
[[ "$before_uu" == fuser* ]] || fail "must wait for apt lock right before unattended-upgrade, got: $before_uu"
pass "security mode installs managed config and runs unattended-upgrade"

# Idempotent: a second run produces byte-identical config.
cp "$UU" "$WORK/uu.first"
OCI_OS_UPDATE_SKIP_ROOT_CHECK=1 PATH="$MOCK_BIN:$PATH" CMD_LOG="$CASE_DIR/cmd.log" \
  APT_CONF_DIR="$CASE_DIR/apt.conf.d" REBOOT_REQUIRED_FILE="$CASE_DIR/reboot-required" \
  bash "$UPDATE" --mode security --reboot never >/dev/null 2>&1
cmp -s "$UU" "$WORK/uu.first" || fail "config must be idempotent"
pass "config write is idempotent"

# ---------------------------------------------------------------------------
# 4. full mode: non-interactive full-upgrade keeping existing conffiles
# ---------------------------------------------------------------------------
run_update full --mode full --reboot never
[ "$RC" -eq 0 ] || fail "full mode failed: $OUT"
[[ "$CMDS" == *"apt-get"*"Dpkg::Options::=--force-confold"*"full-upgrade -y"* ]] \
  || fail "full mode must full-upgrade with --force-confold, got: $CMDS"
[[ "$CMDS" == *"DPkg::Lock::Timeout="* ]] || fail "apt-get must wait for the dpkg lock, got: $CMDS"
[[ "$CMDS" == *"autoremove -y --purge"* ]] || fail "full mode must autoremove, got: $CMDS"
[ -f "$CASE_DIR/apt.conf.d/52ymatch-unattended-upgrades" ] || fail "full mode must also refresh config"
pass "full mode runs non-interactive full-upgrade + autoremove"

# ---------------------------------------------------------------------------
# 5. Reboot policy
# ---------------------------------------------------------------------------
run_update reboot-not-needed --mode full --reboot if-required
[[ "$CMDS" != *"systemd-run"* ]] || fail "if-required must not reboot without marker, got: $CMDS"
[[ "$OUT" == *"OS_UPDATE_REBOOT_REQUIRED=no"* ]] || fail "expected REBOOT_REQUIRED=no, got: $OUT"
[[ "$OUT" == *"OS_UPDATE_REBOOT_SCHEDULED=no"* ]] || fail "expected REBOOT_SCHEDULED=no, got: $OUT"

CASE_DIR="$WORK/reboot-needed"
mkdir -p "$CASE_DIR"
touch "$CASE_DIR/reboot-required"
# run_update recreates dirs but keeps the marker file.
run_update reboot-needed --mode full --reboot if-required
[[ "$CMDS" == *"systemd-run"*"systemctl reboot"* ]] || fail "if-required must reboot with marker, got: $CMDS"
[[ "$OUT" == *"OS_UPDATE_REBOOT_REQUIRED=yes"* ]] || fail "expected REBOOT_REQUIRED=yes, got: $OUT"
[[ "$OUT" == *"OS_UPDATE_REBOOT_SCHEDULED=yes"* ]] || fail "expected REBOOT_SCHEDULED=yes, got: $OUT"

run_update reboot-needed --mode full --reboot never
[[ "$CMDS" != *"systemd-run"* ]] || fail "never must not reboot even with marker, got: $CMDS"
[[ "$OUT" == *"OS_UPDATE_REBOOT_REQUIRED=yes"* ]] || fail "never should still report REBOOT_REQUIRED=yes"

run_update reboot-always --mode security --reboot always
[[ "$CMDS" == *"systemd-run"*"systemctl reboot"* ]] || fail "always must reboot, got: $CMDS"
pass "reboot policy honours if-required / never / always"

echo "All OCI OS update checks passed."
