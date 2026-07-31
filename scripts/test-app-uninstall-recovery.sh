#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2015,SC2034
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail_case() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
assert_eq() { [[ "$2" == "$3" ]] && pass "$1" || fail_case "$1 (expected $2, got $3)"; }
assert_has() { [[ "$2" == *"$3"* ]] && pass "$1" || fail_case "$1"; }

source lib/common.sh
source lib/ui.sh
source lib/profile.sh
source lib/apps.sh
source lib/inventory.sh
source lib/planner.sh
source lib/removal.sh
NO_COLOR=1 erpnext_dev_init_terminal_colors

INSTALLATION_PROFILE=recommended
DEPLOYMENT_ENGINE=native
PLAN_STACK="native:/srv/bench"
effective_deployment_engine() { printf 'native\n'; }
inventory_collect() { :; }
inventory_records_sorted() {
  printf '%s\n' \
    'STACK|native:/srv/bench|native|development|recommended|managed|clean' \
    'SITE|native:/srv/bench|one.test|known' \
    'SITE|native:/srv/bench|two.test|known' \
    'APP|native:/srv/bench|frappe|available|v16|version-16|aaaaaaaa|https://github.com/frappe/frappe|official|managed|clean' \
    'APP|native:/srv/bench|erpnext|available|v16|version-16|bbbbbbbb|https://github.com/frappe/erpnext|official|managed|clean' \
    'APP|native:/srv/bench|telephony|available|v16|version-16|cccccccc|https://github.com/frappe/telephony|official|managed|clean' \
    'APP|native:/srv/bench|helpdesk|available|v16|version-16|dddddddd|https://github.com/frappe/helpdesk|official|managed|clean' \
    'APP|native:/srv/bench|webshop|available|v16|version-16|eeeeeeee|https://github.com/frappe/webshop|official|managed|clean' \
    'SITE_APP|native:/srv/bench|one.test|frappe|installed' \
    'SITE_APP|native:/srv/bench|one.test|erpnext|installed' \
    'SITE_APP|native:/srv/bench|one.test|telephony|installed' \
    'SITE_APP|native:/srv/bench|one.test|helpdesk|installed' \
    'SITE_APP|native:/srv/bench|one.test|webshop|installed' \
    'SITE_APP|native:/srv/bench|two.test|frappe|installed' \
    'SITE_APP|native:/srv/bench|two.test|erpnext|installed' \
    'SITE_APP|native:/srv/bench|two.test|telephony|installed'
}
planner_inventory_fingerprint() { printf stable; }

REMOVAL_SITES=two.test
removal_build_plan telephony site
assert_eq 'site uninstall retains code' retain "$OPERATION_CODE_DECISION"
assert_eq 'explicit selected site' two.test "$OPERATION_SELECTED_SITES"
assert_eq 'shared sites represented' one.test,two.test "$REMOVAL_ALL_SITES"
assert_eq 'profile retained' recommended "$PLAN_RESULT_PROFILE"
assert_eq 'site-only backup scope' two.test "$OPERATION_BACKUP_TARGETS"

REMOVAL_SITES=one.test
if removal_build_plan telephony remove-unused-code; then fail_case 'dependent blocks shared-code removal'; else pass 'dependent blocks shared-code removal'; fi
assert_has 'safe removal order reported' "$REMOVAL_BLOCKER" 'helpdesk@one.test'

if removal_build_plan frappe site; then fail_case 'Frappe removal accepted'; else pass 'Frappe removal rejected'; fi
if removal_build_plan 'frappe/../x' site; then fail_case 'application traversal accepted'; else pass 'application traversal rejected'; fi

REMOVAL_SITES=two.test
removal_build_plan erpnext erpnext-site
assert_eq 'ERPNext site scope retains code' retain "$OPERATION_CODE_DECISION"
assert_eq 'ERPNext site scope retains recommended profile' recommended "$PLAN_RESULT_PROFILE"

if removal_build_plan erpnext convert-frappe-only; then fail_case 'ERPNext dependent conversion accepted'; else pass 'ERPNext dependent blocks conversion'; fi

# Remove the dependent fixture and prove complete conversion planning.
inventory_records_sorted() {
  printf '%s\n' \
    'STACK|native:/srv/bench|native|development|recommended|managed|clean' \
    'SITE|native:/srv/bench|one.test|known' 'SITE|native:/srv/bench|two.test|known' \
    'APP|native:/srv/bench|frappe|available|v16|version-16|aaaaaaaa|https://github.com/frappe/frappe|official|managed|clean' \
    'APP|native:/srv/bench|erpnext|available|v16|version-16|bbbbbbbb|https://github.com/frappe/erpnext|official|managed|clean' \
    'SITE_APP|native:/srv/bench|one.test|frappe|installed' 'SITE_APP|native:/srv/bench|one.test|erpnext|installed' \
    'SITE_APP|native:/srv/bench|two.test|frappe|installed' 'SITE_APP|native:/srv/bench|two.test|erpnext|installed'
}
removal_build_plan erpnext convert-frappe-only
assert_eq 'conversion selects every ERPNext site' one.test,two.test "$OPERATION_SELECTED_SITES"
assert_eq 'conversion removes shared code' remove "$OPERATION_CODE_DECISION"
assert_eq 'conversion changes profile only as planned' frappe-only "$PLAN_RESULT_PROFILE"
assert_eq 'conversion backs up complete stack' one.test,two.test "$OPERATION_BACKUP_TARGETS"

preview="$(removal_preview)"
assert_has 'preview includes destructive data warning' "$preview" 'Data impact'
assert_has 'preview includes code decision' "$preview" 'Shared code'
assert_has 'preview includes recovery checkpoint' "$preview" 'Recovery'

mutations=0
removal_execute() { mutations=$((mutations + 1)); }
REMOVAL_PREVIEW=1 REMOVAL_SITES=one.test run_app_removal erpnext erpnext-site >/dev/null || rc=$?
assert_eq 'dry-run exit' 11 "${rc:-0}"
assert_eq 'dry-run no mutation' 0 "$mutations"

REMOVAL_PREVIEW=0 ASSUME_YES=1 REMOVAL_DATA_ACK=0
if run_app_removal erpnext erpnext-site >/dev/null 2>&1; then fail_case 'missing data acknowledgement accepted'; else pass 'explicit data acknowledgement required'; fi

commands="$(sed -n '/removal_site_action()/,/^}/p' lib/removal.sh)"
assert_has 'supported Bench uninstall lifecycle used' "$commands" 'uninstall-app'
if [[ "$commands" == *'--force'* ]]; then fail_case 'force bypass present'; else pass 'no force bypass'; fi
if grep -Eq 'rm[[:space:]]+-rf.*apps/' lib/removal.sh; then fail_case 'direct app deletion present'; else pass 'no direct app directory deletion'; fi
assert_has 'Docker immutable candidate path' "$(<lib/removal.sh)" 'removal_docker_prepare_candidate'
assert_has 'Docker deferred manifest promotion' "$(<lib/removal.sh)" 'DOCKER_DEFER_MANIFEST_PROMOTION=1'
assert_has 'per-site journal field' "$(<lib/planner.sh)" 'per_site_state='
assert_has 'recovery rejects unsafe automatic restore' "$(<lib/removal.sh)" 'Automatic restoration is blocked'
assert_has 'update-toolkit remains separate' "$(<erpnext-dev.sh)" 'update-toolkit) update_toolkit'

((failures == 0)) || {
  printf 'app-uninstall recovery tests: %d failure(s)\n' "$failures" >&2
  exit 1
}
printf 'app-uninstall recovery tests: all checks passed\n'
