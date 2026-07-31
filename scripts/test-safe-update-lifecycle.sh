#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fixture="$(mktemp -d "${ROOT_DIR}/.erpnext-dev-update-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail_case() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
assert_has() { [[ "$2" == *"$3"* ]] && pass "$1" || fail_case "$1"; }

SUDO="" RED="" GREEN="" YELLOW="" BLUE="" RESET=""
ASSUME_YES=1 DOCTOR_FORMAT=human INSTALLATION_PROFILE=recommended DEPLOYMENT_ENGINE=native
SITE_NAME=one.test
BENCH_DIR="$fixture/bench" OPERATION_STATE_DIR="$fixture/operations"
mkdir -p "$BENCH_DIR/apps" "$BENCH_DIR/sites/one.test" "$BENCH_DIR/sites/two.test"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/profile.sh"
source "$ROOT_DIR/lib/apps.sh"
source "$ROOT_DIR/lib/inventory.sh"
source "$ROOT_DIR/lib/planner.sh"
source "$ROOT_DIR/lib/update.sh"
require_sudo() { :; }
effective_deployment_engine() { printf '%s\n' "$DEPLOYMENT_ENGINE"; }
inventory_collect() { :; }
inventory_records_sorted() {
  printf '%s\n' \
    "STACK|native:$BENCH_DIR|native|native|recommended|managed|clean" \
    "APP|native:$BENCH_DIR|frappe|available|16.1.0|version-16|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|https://github.com/frappe/frappe|official|managed|clean" \
    "APP|native:$BENCH_DIR|erpnext|available|16.1.0|version-16|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb|https://github.com/frappe/erpnext|official|managed|clean" \
    "SITE|native:$BENCH_DIR|one.test|known" \
    "SITE|native:$BENCH_DIR|two.test|known" \
    "SITE_APP|native:$BENCH_DIR|one.test|erpnext|installed" \
    "SITE_APP|native:$BENCH_DIR|two.test|erpnext|installed"
}
managed_update_resolve_commit() {
  case "$1" in *frappe/frappe) printf '%040d\n' 1 ;; *frappe/erpnext) printf '%040d\n' 2 ;; *) return 1 ;; esac
}

managed_update_build_plan safe
assert_has "safe plan includes Frappe" "$UPDATE_TARGET_SET" 'frappe@'
assert_has "safe plan includes ERPNext for recommended" "$UPDATE_TARGET_SET" 'erpnext@'
[[ "$UPDATE_AFFECTED_SITES" == one.test,two.test ]] && pass "native multi-site impact deterministic" || fail_case "native multi-site impact"
preview="$(managed_update_preview)"
assert_has "preview shows backup/shared impact" "$preview" 'every affected site is backed up'
assert_has "preview shows recovery checkpoint" "$preview" 'exact revisions or previous image'

INSTALLATION_PROFILE=frappe-only
managed_update_build_plan safe
[[ "$UPDATE_TARGET_SET" != *erpnext@* ]] && pass "safe update preserves Frappe-only profile" || fail_case "safe update added ERPNext"
INSTALLATION_PROFILE=recommended
managed_update_build_plan full
assert_has "full managed-stack preserves managed apps" "$UPDATE_TARGET_SET" 'erpnext@'
managed_update_build_plan app erpnext
[[ "$UPDATE_TARGET_SET" == erpnext@* ]] && pass "individual app updates only requested app" || fail_case "individual app expanded silently"

managed_update_stable_branch version-16 && pass "supported release line accepted" || fail_case "stable line rejected"
if managed_update_stable_branch develop; then fail_case "development branch accepted"; else pass "development branch rejected"; fi
if managed_update_stable_branch nightly; then fail_case "nightly target accepted"; else pass "nightly target rejected"; fi
if managed_update_resolve_commit https://evil.invalid/app version-16; then fail_case "untrusted source accepted"; else pass "untrusted source rejected"; fi
if managed_update_build_plan app 'x;touch bad'; then fail_case "application injection accepted"; else pass "application injection rejected"; fi

MANAGED_UPDATE_PREVIEW=1
mutation_calls=0
planner_record_write() { mutation_calls=$((mutation_calls + 1)); }
set +e
run_managed_update safe >/dev/null
preview_rc=$?
set -e
[[ "$preview_rc" -eq 11 && "$mutation_calls" -eq 0 ]] && pass "dry-run performs no mutation" || fail_case "dry-run mutated"
MANAGED_UPDATE_PREVIEW=0

# Native lifecycle ordering and all-site gates with adapter mocks.
planner_record_write() { :; }
planner_inventory_fingerprint() { printf 'stable\n'; }
PLAN_INVENTORY_FINGERPRINT=stable
UPDATE_AFFECTED_SITES=one.test,two.test
UPDATE_TARGET_SET='frappe@1111111111111111111111111111111111111111'
UPDATE_CURRENT_SET='frappe@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
PLAN_BENCH="$BENCH_DIR"
backups="" migrations="" stage_fail=""
managed_update_native_preflight() { [[ "$stage_fail" != preflight ]]; }
create_site_backup() {
  backups+="${backups:+,}${SITE_NAME}"
  [[ "$stage_fail" != "backup:${SITE_NAME}" ]]
}
verify_latest_backup_set() { [[ "$stage_fail" != verify-backup ]]; }
run_as_frappe() { [[ "$stage_fail" != code ]]; }
run_as_frappe_quiet() {
  case "$1" in
    'enter maintenance') [[ "$stage_fail" != maintenance ]] ;;
    update\ migrate*)
      migrations+="${migrations:+,}${1##* }"
      [[ "$stage_fail" != migrate ]]
      ;;
    'update assets') [[ "$stage_fail" != assets ]] ;;
    'leave maintenance') [[ "$stage_fail" != services ]] ;;
    *) return 0 ;;
  esac
}
restart_erpnext_service() { [[ "$stage_fail" != services ]]; }
wait_for_erpnext_ready() { [[ "$stage_fail" != health ]]; }
stage_fail='backup:two.test'
set +e
managed_update_execute_native
rc=$?
set -e
[[ "$rc" -eq 30 ]] && pass "one-site backup failure blocks update" || fail_case "backup failure code"
stage_fail="" backups="" migrations=""
managed_update_execute_native
[[ "$backups" == one.test,two.test ]] && pass "every affected site backed up" || fail_case "site backups incomplete"
[[ "$migrations" == one.test,two.test ]] && pass "every affected site migrated" || fail_case "site migrations incomplete"
assert_has "native previous revisions retained" "$OPERATION_PREVIOUS_REVISIONS" 'frappe@aaaaaaaa'

PLAN_INVENTORY_FINGERPRINT=old
set +e
managed_update_execute_native
rc=$?
set -e
[[ "$rc" -eq 34 ]] && pass "inventory change after preview rejected" || fail_case "stale plan accepted"

DEPLOYMENT_ENGINE=docker DOCKER_MODE=development
DOCKER_APP_MANIFEST_FILE="$fixture/manifest"
DOCKER_ERPNEXT_IMAGE=development:current
DOCKER_ERPNEXT_IMAGE_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
DOCKER_PROJECT_NAME=erpnext-dev
docker_mode() { printf '%s\n' "$DOCKER_MODE"; }
docker_collect_desired_app_profiles() { printf 'crm\n'; }
docker_write_apps_json() { :; }
planner_prepare_state_dir() { :; }
planner_checkpoint() { :; }
docker_build_custom_image() { return 1; }
set +e
managed_update_execute_docker >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 31 ]] && pass "Docker development uses managed-image lifecycle" || fail_case "Docker development durability classification"
DOCKER_MODE=production
printf 'invalid\n' >"$DOCKER_APP_MANIFEST_FILE"
docker_validate_app_manifest() { return 1; }
set +e
managed_update_execute_docker >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 25 ]] && pass "tampered Docker manifest blocks update" || fail_case "tampered manifest accepted"

grep -q 'update-toolkit) update_toolkit' erpnext-dev.sh && pass "update-toolkit dispatcher unchanged" || fail_case "update-toolkit regression"
grep -q 'app update APP' erpnext-dev.sh && pass "managed update help exposed" || fail_case "managed update help missing"
if grep -qE '\bgit (reset|stash)\b' <(sed -n '/# Phase 5 managed update lifecycle/,$p' lib/update.sh); then
  fail_case "Phase 5 overwrites or stashes local work"
else
  pass "Phase 5 never resets or stashes local work"
fi

if ((failures)); then
  printf 'safe-update lifecycle tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'safe-update lifecycle tests: all checks passed\n'
