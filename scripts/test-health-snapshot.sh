#!/usr/bin/env bash
# Hermetic tests for the canonical health status model (no ERPNext install required).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Minimal stubs so sourcing dashboard.sh does not require the full toolkit.
APP_NAME="ERPNext Developer Toolkit"
SCRIPT_VERSION="test"
SUDO=""
SITE_NAME="erp.test"
_ERPNEXT_DEV_ROOT="$ROOT_DIR"

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/support.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/dashboard.sh"

fail=0
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${label}: expected '${expected}' got '${actual}'" >&2
    fail=$((fail + 1))
  else
    echo "OK: ${label}"
  fi
}

assert_eq "normalize OK→HEALTHY" "HEALTHY" "$(health_status_normalize OK)"
assert_eq "normalize WARN→DEGRADED" "DEGRADED" "$(health_status_normalize WARN)"
assert_eq "normalize FAIL→CRITICAL" "CRITICAL" "$(health_status_normalize FAIL)"
assert_eq "normalize unknown→UNKNOWN" "UNKNOWN" "$(health_status_normalize weird)"

assert_eq "worst HEALTHY+DEGRADED" "DEGRADED" "$(health_status_worst HEALTHY DEGRADED)"
assert_eq "worst DEGRADED+CRITICAL" "CRITICAL" "$(health_status_worst DEGRADED CRITICAL)"
assert_eq "worst UNKNOWN+HEALTHY" "UNKNOWN" "$(health_status_worst UNKNOWN HEALTHY)"
assert_eq "worst CRITICAL+UNKNOWN" "CRITICAL" "$(health_status_worst CRITICAL UNKNOWN)"

assert_eq "rank CRITICAL" "3" "$(health_status_rank CRITICAL)"
assert_eq "rank HEALTHY" "0" "$(health_status_rank HEALTHY)"

assert_eq "legacy CRITICAL→FAIL" "FAIL" "$(health_legacy_ok_warn CRITICAL)"
assert_eq "legacy HEALTHY→OK" "OK" "$(health_legacy_ok_warn HEALTHY)"

# Disk probe against real / (shape only)
disk_out="$(health_probe_disk)"
IFS='|' read -r d_status d_detail d_pct <<<"$disk_out"
case "$d_status" in
  HEALTHY|DEGRADED|CRITICAL|UNKNOWN) echo "OK: disk probe status ${d_status}" ;;
  *) echo "FAIL: disk probe bad status ${d_status}" >&2; fail=$((fail + 1)) ;;
esac
[[ "$d_pct" =~ ^[0-9]+$ ]] || { echo "FAIL: disk percent not numeric: ${d_pct}" >&2; fail=$((fail + 1)); }

mem_out="$(health_probe_memory)"
IFS='|' read -r m_status _ <<<"$mem_out"
case "$m_status" in
  HEALTHY|DEGRADED|CRITICAL|UNKNOWN) echo "OK: memory probe status ${m_status}" ;;
  *) echo "FAIL: memory probe bad status ${m_status}" >&2; fail=$((fail + 1)) ;;
esac

if (( fail > 0 )); then
  echo "test-health-snapshot: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-health-snapshot: all checks passed"
