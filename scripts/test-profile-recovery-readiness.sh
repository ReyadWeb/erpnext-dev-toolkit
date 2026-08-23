#!/usr/bin/env bash
# Hermetic Phase 7.7 profile-aware readiness closure checks.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() { echo "OK: $*"; }
assert_eq() {
  [[ "$2" == "$3" ]] || fail "$1: expected '$2', got '$3'"
  pass "$1"
}

INSTALLATION_PROFILE=recommended
DEPLOYMENT_ENGINE=native
source lib/profile.sh
effective_deployment_engine() { printf '%s\n' "${DEPLOYMENT_ENGINE:-native}"; }
deployment_engine_is_docker() { [[ "$(effective_deployment_engine)" == docker ]]; }
install_state() { printf '%s\n' Installed; }
check_bench_app_installed() { [[ "$1" != erpnext || "${ERPnext_PRESENT:-1}" == 1 ]]; }
site_app_installed() { [[ "$1" != erpnext || "${ERPnext_PRESENT:-1}" == 1 ]]; }

assert_eq 'recommended requires ERPNext' \
  'OK|required apps present: frappe,erpnext' "$(installation_profile_health_pair)"
ERPnext_PRESENT=0
assert_eq 'recommended missing ERPNext is not ready' \
  'WARN|required apps missing or unconfirmed: erpnext' "$(installation_profile_health_pair)"
ERPnext_PRESENT=1

INSTALLATION_PROFILE=frappe-only
assert_eq 'Frappe-only permits ERPNext absence' \
  'OK|required apps present: frappe' "$(installation_profile_health_pair)"

INSTALLATION_PROFILE=advanced
PROFILE_CONTEXT_RECONCILIATION=drift-missing
PROFILE_CONTEXT_DESIRED_APPS=frappe,crm,telephony,helpdesk
PROFILE_CONTEXT_OBSERVED_APPS=frappe,crm
assert_eq 'Native Advanced reports missing resolved applications' \
  'WARN|desired applications missing or unproven: telephony,helpdesk' "$(installation_profile_health_pair)"
PROFILE_CONTEXT_RECONCILIATION=consistent
PROFILE_CONTEXT_OBSERVED_APPS=frappe,crm,telephony,helpdesk
assert_eq 'Native Advanced accepts exact resolved inventory' \
  'OK|desired applications match observed inventory: frappe,crm,telephony,helpdesk' "$(installation_profile_health_pair)"

INSTALLATION_PROFILE=existing
unset PROFILE_CONTEXT_RECONCILIATION PROFILE_CONTEXT_DESIRED_APPS PROFILE_CONTEXT_OBSERVED_APPS
assert_eq 'Existing remains informational' \
  'INFO|Existing installation readiness is deferred; no managed claim is made' "$(installation_profile_health_pair)"

pass 'profile-aware readiness closure matrix'
echo 'test-profile-recovery-readiness: 8 assertions passed'
