#!/usr/bin/env bash
# Hermetic regression coverage for Phase 1 platform/install profiles.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  [[ "$expected" == "$actual" ]] || fail "${label}: expected '${expected}', got '${actual}'"
  echo "OK: ${label}"
}

INSTALLATION_PROFILE=""
DEPLOYMENT_ENGINE=""
source "${ROOT_DIR}/lib/profile.sh"
effective_deployment_engine() { printf '%s\n' "${DEPLOYMENT_ENGINE:-native}"; }
deployment_engine_is_docker() { [[ "$(effective_deployment_engine)" == docker ]]; }
err() { :; }

assert_eq "compatibility default" recommended "$(effective_installation_profile)"
assert_eq "recommended alias" recommended "$(normalize_installation_profile erpnext)"
assert_eq "frappe-only alias" frappe-only "$(normalize_installation_profile frappe_only)"
assert_eq "advanced canonical profile" advanced "$(normalize_installation_profile advanced)"
assert_eq "existing canonical profile" existing "$(normalize_installation_profile existing)"
if normalize_installation_profile invalid >/dev/null 2>&1; then
  fail "invalid profile accepted"
fi
echo "OK: invalid profile rejected"

INSTALLATION_PROFILE=recommended
assert_eq "recommended required apps" $'frappe\nerpnext' "$(installation_profile_required_apps)"
assert_eq "recommended asset policy" frappe-and-erpnext "$(installation_profile_asset_policy)"
INSTALLATION_PROFILE=frappe-only
assert_eq "Frappe-only required apps" frappe "$(installation_profile_required_apps)"
assert_eq "Frappe-only asset policy" frappe-only "$(installation_profile_asset_policy)"

DEPLOYMENT_ENGINE=native
validate_platform_profile_combination || fail "native Frappe-only rejected"
DEPLOYMENT_ENGINE=docker
validate_platform_profile_combination || fail "Docker Frappe-only rejected during Phase 4"
echo "OK: Docker Frappe-only profile accepted"

declare -A bench_apps=([frappe]=1 [erpnext]=0)
declare -A site_apps=([frappe]=1 [erpnext]=0)
check_bench_app_installed() { [[ "${bench_apps[$1]:-0}" -eq 1 ]]; }
site_app_installed() { [[ "${site_apps[$1]:-0}" -eq 1 ]]; }
install_state() { printf 'Installed\n'; }
DEPLOYMENT_ENGINE=native
INSTALLATION_PROFILE=frappe-only
assert_eq "Frappe-only health policy" "OK|required apps present: frappe" "$(installation_profile_health_pair)"
INSTALLATION_PROFILE=recommended
assert_eq "recommended health requires ERPNext" "WARN|required apps missing or unconfirmed: erpnext" "$(installation_profile_health_pair)"
bench_apps[erpnext]=1
site_apps[erpnext]=1
assert_eq "recommended health complete" "OK|required apps present: frappe,erpnext" "$(installation_profile_health_pair)"

tmp="$(mktemp -d "${ROOT_DIR}/.erpnext-dev-profile-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
set +e
LOG_DIR="$tmp/log" LOCK_DIR="$tmp/lock" CONFIG_FILE="$tmp/config" \
  LEGACY_CONFIG_FILE="$tmp/legacy" INSTALLATION_PROFILE=bogus \
  bash "${ROOT_DIR}/erpnext-dev.sh" install --yes >"$tmp/out" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "invalid CLI profile succeeded"
grep -q "Invalid installation profile" "$tmp/out" || fail "invalid CLI profile lacked diagnostic"
[[ ! -e "$tmp/lock/toolkit.lock" ]] || fail "invalid profile acquired the mutation lock"
echo "OK: invalid CLI profile rejected before mutation lock"

LOG_DIR="$tmp/valid-log" LOCK_DIR="$tmp/valid-lock" CONFIG_FILE="$tmp/valid-config" \
  LEGACY_CONFIG_FILE="$tmp/valid-legacy" DEPLOYMENT_ENGINE=native \
  bash "${ROOT_DIR}/erpnext-dev.sh" help >"$tmp/valid-out" 2>&1 \
  || fail "existing help command regressed"
grep -q -- '--profile PROFILE' "$tmp/valid-out" || fail "profile CLI help missing"
echo "OK: existing help behavior preserved without explicit profile options"

grep -q 'INSTALLATION_PROFILE="$(effective_installation_profile)"' lib/install.sh \
  || fail "native installer does not pass the selected profile"
grep -q 'Frappe-only profile selected; ERPNext will not be downloaded or installed' lib/install.sh \
  || fail "native Frappe-only install path missing"
echo "OK: native installer contains profile-aware app selection"

echo "platform-profile tests: all checks passed"
