#!/usr/bin/env bash
# Hermetic checks for profile-neutral Frappe lifecycle semantics and preflight.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() { echo "OK: $*"; }

INSTALLATION_PROFILE=frappe-only DEPLOYMENT_ENGINE=native SUDO="" ASSUME_YES=1
source lib/profile.sh
source lib/install.sh
source lib/storage.sh

systemctl() {
  case "$*" in
    "is-active --quiet chrony") return "${TEST_CHRONY_ACTIVE:-1}" ;;
    "is-active --quiet systemd-timesyncd") return "${TEST_TIMESYNCD_ACTIVE:-1}" ;;
    *) return 1 ;;
  esac
}
timedatectl() {
  case "$1" in
    show) printf '%s\n' "${TEST_SYNCED:-yes}" ;;
    set-ntp) TEST_SYNCED=yes ;;
  esac
}
chronyc() { TEST_SYNCED=yes; }
apt-get() {
  [[ "${TEST_APT_FAIL:-0}" == 0 ]] && return 0
  echo "Release file is not valid yet" >&2
  return 100
}
toolkit_cmd() { printf 'sudo erpnext-dev %s' "$1"; }
sleep() { :; }
log() { :; }
ok() { :; }
err() { printf '%s\n' "$*" >&2; }

TEST_SYNCED=yes TEST_CHRONY_ACTIVE=0 TEST_TIMESYNCD_ACTIVE=1
[[ "$(detect_time_sync_provider)" == chrony ]] || fail "active Chrony was not detected"
pass "active Chrony provider detected"
TEST_CHRONY_ACTIVE=1 TEST_TIMESYNCD_ACTIVE=0
[[ "$(detect_time_sync_provider)" == systemd-timesyncd ]] || fail "active timesyncd was not detected"
pass "active systemd-timesyncd provider detected"

TEST_SYNCED=yes TEST_APT_FAIL=0 verify_clock_and_repository_readiness >/dev/null \
  || fail "synchronized repository preflight failed"
pass "synchronized clock and repository accepted"

preflight_out="$(mktemp /tmp/frappe-platform-preflight.XXXXXX)"
set +e
TEST_SYNCED=yes TEST_APT_FAIL=1 verify_clock_and_repository_readiness >"$preflight_out" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "future repository metadata was accepted"
grep -q "not valid yet" "$preflight_out" || fail "clock-skew diagnostic missing"
grep -q "first-run" "$preflight_out" || fail "recommended/Frappe-only prerequisite recovery changed"
pass "future repository metadata rejected"

install_body="$(sed -n '/^run_install()/,/^}/p' lib/install.sh)"
preflight_line="$(grep -n 'verify_clock_and_repository_readiness' <<<"$install_body" | head -1 | cut -d: -f1)"
storage_line="$(grep -n 'maybe_offer_root_storage_expansion' <<<"$install_body" | head -1 | cut -d: -f1)"
[[ "$preflight_line" -lt "$storage_line" ]] || fail "repository preflight does not precede storage mutation"
pass "repository preflight precedes storage expansion"

tmp="$(mktemp -d "${ROOT_DIR}/.frappe-platform-lifecycle.XXXXXX")"
trap 'rm -rf "$tmp" "$preflight_out"' EXIT
lvextend() {
  if [[ -e /proc/${BASHPID}/fd/200 ]]; then
    echo leaked >"$tmp/fd-result"
    return 1
  fi
  echo closed >"$tmp/fd-result"
}
exec 200>"$tmp/parent-lock"
run_lvm_extend_root /dev/mock/root || fail "LVM wrapper failed"
[[ -e /proc/$$/fd/200 ]] || fail "parent lost lifecycle lock descriptor"
[[ "$(<"$tmp/fd-result")" == closed ]] || fail "LVM child inherited descriptor 200"
pass "LVM child closes descriptor 200 while parent retains it"

for bad in "Creating ERPNext service" "ERPNext autostart" "Starting ERPNext service" \
  "Restarting ERPNext service" "ERPNext is ready" "ERPNext Administrator"; do
  if rg -n -F "$bad" lib/service.sh lib/install.sh lib/status.sh lib/config.sh lib/backup.sh >/dev/null; then
    fail "shared lifecycle wording remains: $bad"
  fi
done
pass "shared lifecycle transcript uses Frappe terminology"

grep -q 'installation_profile_context_erpnext_pair' lib/status.sh \
  || fail "profile-aware status policy missing"
grep -q 'installation_profile_context_erpnext_pair' lib/support.sh \
  || fail "profile-aware doctor policy missing"
if grep -q 'absent by design for Frappe-only profile' lib/status.sh lib/support.sh; then
  fail "status or Doctor still uses profile-specific absence wording"
fi
pass "ERPNext absence is derived from canonical intent and reconciliation"

echo "frappe platform lifecycle tests: all checks passed"
