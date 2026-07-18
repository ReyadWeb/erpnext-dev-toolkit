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

# CPU / iowait sample (shape)
cpu_out="$(health_probe_cpu_iowait)"
IFS='|' read -r c_status _ c_pct c_io <<<"$cpu_out"
case "$c_status" in
  HEALTHY | DEGRADED | CRITICAL | UNKNOWN) echo "OK: cpu/iowait status ${c_status}" ;;
  *)
    echo "FAIL: cpu/iowait bad status ${c_status}" >&2
    fail=$((fail + 1))
    ;;
esac
[[ "$c_pct" =~ ^[0-9]+$ ]] || {
  echo "FAIL: cpu percent not numeric: ${c_pct}" >&2
  fail=$((fail + 1))
}
[[ "$c_io" =~ ^[0-9]+$ ]] || {
  echo "FAIL: iowait percent not numeric: ${c_io}" >&2
  fail=$((fail + 1))
}

# Cert days remaining against a short-lived self-signed cert
tmpdir_cert="$(mktemp -d /tmp/erpnext-dev-cert-test.XXXXXX)"
openssl req -x509 -newkey rsa:2048 -keyout "${tmpdir_cert}/key.pem" -out "${tmpdir_cert}/cert.pem" \
  -days 3 -nodes -subj "/CN=health-test.local" >/dev/null 2>&1 || true
if [[ -f "${tmpdir_cert}/cert.pem" ]]; then
  days="$(health_cert_days_remaining "${tmpdir_cert}/cert.pem")"
  if [[ "$days" =~ ^[0-9]+$ ]] && ((days <= 3 && days >= 0)); then
    echo "OK: cert days remaining ${days}"
  else
    echo "FAIL: cert days unexpected: ${days}" >&2
    fail=$((fail + 1))
  fi
else
  echo "FAIL: could not generate test certificate" >&2
  fail=$((fail + 1))
fi
rm -rf "$tmpdir_cert"

# Disk probe against real / (shape only)
disk_out="$(health_probe_disk)"
IFS='|' read -r d_status d_detail d_pct <<<"$disk_out"
case "$d_status" in
  HEALTHY | DEGRADED | CRITICAL | UNKNOWN) echo "OK: disk probe status ${d_status}" ;;
  *)
    echo "FAIL: disk probe bad status ${d_status}" >&2
    fail=$((fail + 1))
    ;;
esac
[[ "$d_pct" =~ ^[0-9]+$ ]] || {
  echo "FAIL: disk percent not numeric: ${d_pct}" >&2
  fail=$((fail + 1))
}

mem_out="$(health_probe_memory)"
IFS='|' read -r m_status _ <<<"$mem_out"
case "$m_status" in
  HEALTHY | DEGRADED | CRITICAL | UNKNOWN) echo "OK: memory probe status ${m_status}" ;;
  *)
    echo "FAIL: memory probe bad status ${m_status}" >&2
    fail=$((fail + 1))
    ;;
esac

# Incident + history persistence (hermetic tmpdir)
HEALTH_LIB_DIR="$(mktemp -d /tmp/erpnext-dev-health-test.XXXXXX)"
trap 'rm -rf "${HEALTH_LIB_DIR}"' EXIT
SNAPSHOT_GENERATED_AT="2026-07-16T12:00:00Z"
SNAPSHOT_SITE="erp.test"
SNAPSHOT_OVERALL="CRITICAL"
SNAPSHOT_HOST_STATUS="HEALTHY"
SNAPSHOT_APP_STATUS="CRITICAL"
SNAPSHOT_HTTP_STATUS="CRITICAL"
SNAPSHOT_HTTP_DETAIL="HTTP 000"
SNAPSHOT_PROTECTION_STATUS="HEALTHY"
SNAPSHOT_WOULD_HEAL="restart_web_runtime"
SNAPSHOT_DISK_PERCENT=42
SNAPSHOT_MEM_AVAIL_PCT=55
SNAPSHOT_HTTP_MS=12
health_history_append
[[ -f "${HEALTH_LIB_DIR}/metrics/history.jsonl" ]] || {
  echo "FAIL: history not written" >&2
  fail=$((fail + 1))
}
health_record_incident "HEALTHY" "CRITICAL"
incident_count="$(find "${HEALTH_LIB_DIR}/incidents" -name '*.json' ! -name latest.json 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "incident created on CRITICAL transition" "1" "$incident_count"
health_record_incident "CRITICAL" "CRITICAL"
incident_count2="$(find "${HEALTH_LIB_DIR}/incidents" -name '*.json' ! -name latest.json 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "no duplicate incident when status unchanged" "1" "$incident_count2"
health_record_incident "CRITICAL" "HEALTHY"
incident_count3="$(find "${HEALTH_LIB_DIR}/incidents" -name '*.json' ! -name latest.json 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "recovery incident recorded" "2" "$incident_count3"

# Cooldown dry-run streaks
SNAPSHOT_HTTP_STATUS="CRITICAL"
SNAPSHOT_OVERALL="CRITICAL"
health_cooldown_tick
assert_eq "http streak after 1 fail" "1" "${SNAPSHOT_HTTP_FAIL_STREAK}"
health_cooldown_tick
health_cooldown_tick
assert_eq "would_heal after threshold" "restart_web_runtime" "${SNAPSHOT_WOULD_HEAL}"

if ((fail > 0)); then
  echo "test-health-snapshot: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-health-snapshot: all checks passed"
