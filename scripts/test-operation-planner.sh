#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fixture="$(mktemp -d "${ROOT_DIR}/.erpnext-dev-planner-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail_case() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail_case "$1 (expected $2, got $3)"; fi
}
assert_has() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail_case "$1 (missing $3)"; fi
}

SITE_NAME=one.test
INSTALLATION_PROFILE=recommended
DEPLOYMENT_ENGINE=native
DOCTOR_FORMAT=human
ASSUME_YES=1
SUDO=""
RED="" GREEN="" YELLOW="" BLUE="" RESET=""
CONFIG_FILE="$fixture/config"
OPERATION_STATE_DIR="$fixture/operations"
ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT="$fixture/bench"
ERPNEXT_DEV_INVENTORY_FIXTURE_MANAGEMENT=managed
QUICK_INSTALL_SITE=one.test
QUICK_INSTALL_PREVIEW=0
FRAPPE_BRANCH="version-16"
ERPNEXT_BRANCH="version-16"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/profile.sh"
source "$ROOT_DIR/lib/apps.sh"
effective_deployment_engine() { printf '%s\n' "$DEPLOYMENT_ENGINE"; }
deployment_engine_is_docker() { [[ "$DEPLOYMENT_ENGINE" == docker ]]; }
docker_mode() { printf 'development\n'; }
require_sudo() { :; }
source "$ROOT_DIR/lib/inventory.sh"
source "$ROOT_DIR/lib/planner.sh"

make_app() {
  mkdir -p "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/apps/$1"
  printf 'VERSION=%s\nBRANCH=%s\nCOMMIT=%040d\nSOURCE=%s\nSTATE=%s\n' \
    "${2:-16.0.0}" "${3:-version-16}" 1 "$4" "${5:-clean}" \
    >"$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/apps/$1/.inventory-meta"
}
make_site() {
  local site="$1"
  mkdir -p "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/$site"
  shift
  printf '%s\n' "$@" >"$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/${site}/apps.txt"
}
mkdir -p "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/apps" "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites"
make_app frappe 16.2.0 version-16 https://github.com/frappe/frappe
make_app erpnext 16.1.0 version-16 https://github.com/frappe/erpnext
make_site one.test frappe erpnext

OPERATION_ID_OVERRIDE=deterministic
planner_build helpdesk
first="$(planner_preview)"
planner_build helpdesk
second="$(planner_preview)"
assert_eq "deterministic plan" "$first" "$second"
assert_has "preview target" "$first" "one.test"
assert_has "preview dependency" "$first" "telephony"
assert_has "preview shared impact" "$first" "Other shared sites"
assert_has "preview backup" "$first" "Backup target"
assert_has "preview verification" "$first" "Verification"
assert_eq "trusted catalog resolution" helpdesk "$PLAN_CATALOG_ID"
assert_eq "dependency ordering" telephony "$PLAN_DEPENDENCIES"
assert_eq "missing dependency planned without inventory mutation" 0 "$(inventory_usage_count "$PLAN_STACK" telephony)"

QUICK_INSTALL_PREVIEW=1
rm -rf "$OPERATION_STATE_DIR"
set +e
planner_execute >/dev/null
rc=$?
set -e
assert_eq "preview exit code" 11 "$rc"
if [[ ! -e "$OPERATION_STATE_DIR" ]]; then pass "preview performs no mutation"; else fail_case "preview wrote operation state"; fi
QUICK_INSTALL_PREVIEW=0

set +e
planner_build 'bad;app' >/dev/null
bad_rc=$?
planner_build unknown_app >/dev/null
unknown_rc=$?
set -e
assert_eq "malformed app rejected" 20 "$bad_rc"
assert_eq "unknown app rejected" 20 "$unknown_rc"

make_site two.test frappe erpnext
QUICK_INSTALL_SITE=""
set +e
planner_build hrms >/dev/null
ambiguous_rc=$?
set -e
assert_eq "ambiguous site rejected" 2 "$ambiguous_rc"
QUICK_INSTALL_SITE=one.test
rm -rf "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/two.test"

DEPLOYMENT_ENGINE=docker
planner_build hrms >/dev/null || fail_case "Docker operation plan rejected"
assert_eq "Docker operation plan uses shared planner" docker "$PLAN_ENGINE"
DEPLOYMENT_ENGINE=native

mutation_log="$fixture/mutations"
backup_fail=0
verify_backup_fail=0
backup_target_wrong=0
health_fail=0
fail_action=""
create_site_backup() { [[ "$backup_fail" -eq 0 ]]; }
verify_latest_backup_set() { [[ "$verify_backup_fail" -eq 0 ]]; }
backup_latest_set_paths() { printf 'backup-one.test\n'; }
planner_verify_backup_target() {
  [[ "$verify_backup_fail" -eq 0 && "$backup_target_wrong" -eq 0 ]] || return 1
  OPERATION_BACKUP_REFERENCE="${PLAN_SITE}:backup-one.test"
}
site_app_installed() { grep -Fxq "$1" "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/$SITE_NAME/apps.txt"; }
restart_erpnext_service() {
  printf 'restart\n' >>"$mutation_log"
  [[ "$fail_action" != restart ]]
}
runtime_state() { printf 'Running\n'; }
port_listens() { [[ "$health_fail" -eq 0 ]]; }
bench_http_ready() { [[ "$health_fail" -eq 0 ]]; }
bench_static_assets_ready() { [[ "$health_fail" -eq 0 ]]; }
write_dev_config_file() { printf 'INSTALLATION_PROFILE=%s\n' "$INSTALLATION_PROFILE" >"$CONFIG_FILE"; }
planner_run_native_action() {
  printf '%s:%s\n' "$1" "$2" >>"$mutation_log"
  [[ "$1" != "$fail_action" ]] || return 1
  case "$1" in
    acquire) make_app "$2" 16.0.0 version-16 "$PLAN_REPO" ;;
    install)
      grep -Fxq "$2" "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/$PLAN_SITE/apps.txt" \
        || printf '%s\n' "$2" >>"$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/$PLAN_SITE/apps.txt"
      ;;
  esac
}

rm -f "$mutation_log"
planner_build helpdesk
planner_preview >/dev/null
planner_execute
assert_eq "native curated install completed" completed "$OPERATION_STATUS"
assert_has "dependency installed" "$(cat "$mutation_log")" "install:telephony"
assert_has "selected app installed" "$(cat "$mutation_log")" "install:helpdesk"
assert_has "asset action" "$(cat "$mutation_log")" "build:helpdesk"
assert_has "service action" "$(cat "$mutation_log")" "restart"
assert_has "verified backup retained" "$OPERATION_BACKUP_REFERENCE" "one.test:backup-one.test"
assert_has "durable completed record" "$(cat "$OPERATION_FILE")" "status=completed"

planner_build helpdesk
set +e
planner_execute >/dev/null
already_rc=$?
set -e
assert_eq "idempotent re-execution" 10 "$already_rc"

sed -i '/^erpnext$/d;/^helpdesk$/d;/^telephony$/d' "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/one.test/apps.txt"
rm -rf "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/apps/erpnext" "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/apps/helpdesk"
INSTALLATION_PROFILE=frappe-only
OPERATION_ID_OVERRIDE=erpnext-transition
planner_build erpnext
assert_eq "ERPNext resulting profile" recommended "$PLAN_RESULT_PROFILE"
planner_execute
assert_has "ERPNext installed after Frappe-only" \
  "$(cat "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/one.test/apps.txt")" erpnext
assert_has "profile transitions after verification" "$(cat "$CONFIG_FILE")" "recommended"

INSTALLATION_PROFILE=recommended
make_app erpnext 16.1.0 version-16 https://github.com/frappe/erpnext
make_site one.test frappe erpnext
rm -f "$mutation_log"
backup_fail=1
OPERATION_ID_OVERRIDE=backup-command-failure
planner_build hrms
set +e
planner_execute >/dev/null
backup_rc=$?
set -e
assert_eq "backup command failure exit" 30 "$backup_rc"
if [[ ! -s "$mutation_log" ]]; then pass "no mutation after backup command failure"; else fail_case "mutation followed backup failure"; fi
backup_fail=0
verify_backup_fail=1
OPERATION_ID_OVERRIDE=backup-verify-failure
planner_build hrms
set +e
planner_execute >/dev/null
verify_backup_rc=$?
set -e
assert_eq "backup verification failure exit" 30 "$verify_backup_rc"
if [[ ! -s "$mutation_log" ]]; then pass "no mutation after backup verification failure"; else fail_case "mutation followed verify failure"; fi
verify_backup_fail=0
backup_target_wrong=1
OPERATION_ID_OVERRIDE=backup-target-failure
planner_build hrms
set +e
planner_execute >/dev/null
target_backup_rc=$?
set -e
assert_eq "incorrect backup target exit" 30 "$target_backup_rc"
if [[ ! -s "$mutation_log" ]]; then pass "no mutation after incorrect backup target"; else fail_case "mutation followed wrong backup target"; fi
backup_target_wrong=0

health_fail=1
OPERATION_ID_OVERRIDE=health-failure
planner_build hrms
set +e
planner_execute >/dev/null
health_rc=$?
set -e
assert_eq "health verification failure exit" 32 "$health_rc"
assert_has "failure checkpoint accurate" "$OPERATION_CHECKPOINTS" "mutation-complete"
assert_has "recovery backup retained" "$OPERATION_BACKUP_REFERENCE" "backup-one.test"
assert_has "actionable recovery" "$OPERATION_RECOVERY" "inspect Bench health"
assert_eq "no false completed state" recovery-required "$OPERATION_STATUS"
health_fail=0

for failure_case in acquire install migrate build restart; do
  sed -i '/^crm$/d' "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/one.test/apps.txt"
  rm -rf "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/apps/crm"
  rm -f "$mutation_log"
  fail_action="$failure_case"
  OPERATION_ID_OVERRIDE="failure-${failure_case}"
  planner_build crm
  set +e
  planner_execute >/dev/null
  failure_rc=$?
  set -e
  assert_eq "${failure_case} failure exit" 31 "$failure_rc"
  assert_eq "${failure_case} recovery state" recovery-required "$OPERATION_STATUS"
  assert_has "${failure_case} backup retained" "$OPERATION_BACKUP_REFERENCE" "backup-one.test"
done
fail_action=""

sed -i '/^crm$/d' "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT/sites/one.test/apps.txt"
planner_build crm
PLAN_INVENTORY_FINGERPRINT=changed
OPERATION_ID_OVERRIDE=toctou
set +e
planner_execute >/dev/null
toctou_rc=$?
set -e
assert_eq "state change blocks mutation" 34 "$toctou_rc"

QUICK_INSTALL_SITE='../escape'
set +e
planner_build crm >/dev/null
path_rc=$?
set -e
assert_eq "path traversal site rejected" 1 "$path_rc"
QUICK_INSTALL_SITE=one.test
load_validated_app_catalog_record crm
LIB_APP_REPO='https://evil.invalid/app'
if validate_app_catalog_record; then
  fail_case "catalog source tampering accepted"
else
  pass "catalog source tampering rejected"
fi
if grep -Eq 'ACTION_ARG:-.*install.*QUICK_INSTALL_PREVIEW' "$ROOT_DIR/erpnext-dev.sh"; then
  pass "Quick mutation uses established toolkit lock"
else
  fail_case "Quick mutation lock routing missing"
fi

redaction_marker='synthetic-sensitive-value'
if grep -R -F -q -- "$redaction_marker" "$OPERATION_STATE_DIR" 2>/dev/null; then
  fail_case "secret appeared in operation records"
else
  pass "operation records contain no injected secret"
fi
mkdir -p "$fixture/real-state"
rm -rf "$fixture/symlink-state"
ln -s "$fixture/real-state" "$fixture/symlink-state"
OPERATION_STATE_DIR="$fixture/symlink-state"
OPERATION_FILE="$OPERATION_STATE_DIR/refuse.state"
set +e
planner_record_write >/dev/null 2>&1
symlink_rc=$?
set -e
if [[ "$symlink_rc" -ne 0 ]]; then pass "symlinked state directory rejected"; else fail_case "symlinked state directory accepted"; fi

if ((failures)); then
  printf 'operation-planner tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'operation-planner tests: all checks passed\n'
