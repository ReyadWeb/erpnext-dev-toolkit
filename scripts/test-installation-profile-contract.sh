#!/usr/bin/env bash
# Hermetic Phase 7.1 profile/parser/planning/reconciliation/non-mutation tests.
# shellcheck disable=SC2034,SC2100
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fixture="$(mktemp -d "${ROOT_DIR}/.erpnext-dev-profile-contract.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail_case() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail_case "$1 (expected '$2', got '$3')"; fi
}
assert_has() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail_case "$1 (missing '$3')"; fi
}

INSTALLATION_PROFILE=recommended
DEPLOYMENT_ENGINE=native
INSTALLATION_PROFILE_ENV_PROVIDED=1
DEPLOYMENT_ENGINE_ENV_PROVIDED=1
SITE_NAME=one.test
SITE_NAME_ENV_PROVIDED=1
SITE_NAME_SOURCE=environment
DEPLOYMENT_MODE=development
PRODUCTION_DOMAIN=""
PRODUCTION_SSL_MODE=planned
RUNTIME_MODE=""
HOST_OS=""
HOST_OS_ENV_PROVIDED=0
DOCKER_PUBLISH_PORT=8080
DOCKER_PUBLISH_PORT_ENV_PROVIDED=0
DOCKER_SITE_NAME=""
DOCKER_MODE=development
DOCKER_MODE_ENV_PROVIDED=0
FRAPPE_USER=frappe
FRAPPE_HOME="$fixture/frappe"
BENCH_PARENT="$fixture/bench-parent"
BENCH_NAME=frappe-bench
BENCH_DIR="$BENCH_PARENT/$BENCH_NAME"
DOCTOR_FORMAT=human
CONFIG_FILE="$fixture/config"
LEGACY_CONFIG_FILE="$fixture/legacy"
ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT="$fixture/bench"
ERPNEXT_DEV_INVENTORY_FIXTURE_MANAGEMENT=managed
FRAPPE_BRANCH=version-16
ERPNEXT_BRANCH=version-16
SUDO=""

source lib/common.sh
source lib/profile.sh
source lib/config.sh
source lib/apps.sh
effective_deployment_engine() { printf '%s\n' "$DEPLOYMENT_ENGINE"; }
deployment_engine_is_docker() { [[ "$DEPLOYMENT_ENGINE" == docker ]]; }
docker_mode() { printf '%s\n' "${TEST_DOCKER_MODE:-development}"; }
require_sudo() { :; }
source lib/inventory.sh
source lib/planner.sh

for pair in \
  recommended:recommended default:recommended erpnext:recommended frappe-erpnext:recommended \
  frappe-only:frappe-only frappe_only:frappe-only frappe:frappe-only \
  advanced:advanced existing:existing; do
  assert_eq "profile normalization ${pair%%:*}" "${pair#*:}" \
    "$(normalize_installation_profile "${pair%%:*}")"
done
for bad in '' unknown '../frappe' 'frappe only' 'advanced;id' $'existing\001'; do
  if normalize_installation_profile "$bad" >/dev/null 2>&1; then
    fail_case "malformed profile accepted"
  else
    pass "malformed profile rejected"
  fi
done

valid_inputs=(erpnext 'helpdesk,crm' 'crm,helpdesk')
for value in "${valid_inputs[@]}"; do
  profile_plan_parse_requested_apps "$value" || fail_case "valid app input rejected: $value"
done
profile_plan_parse_requested_apps 'helpdesk,crm'
first="$PROFILE_PLAN_REQUESTED_CSV"
profile_plan_parse_requested_apps 'crm,helpdesk'
assert_eq "requested ordering normalization" "$first" "$PROFILE_PLAN_REQUESTED_CSV"
assert_eq "catalog ordering is deterministic" 'crm,helpdesk' "$PROFILE_PLAN_REQUESTED_CSV"

bad_apps=(
  '' 'crm,crm' ',crm' 'crm,' 'crm,,helpdesk' ' crm' 'crm ' 'crm, helpdesk'
  '../crm' 'crm/helpdesk' 'crm;id' 'crm$(id)' 'https://example.invalid/app'
  'git@github.com:owner/app' 'crm@main' 'frappe' 'unknown_app'
)
bad_apps+=("$(printf 'crm\001')")
for value in "${bad_apps[@]}"; do
  if profile_plan_parse_requested_apps "$value" >/dev/null 2>&1; then
    fail_case "unsafe app input accepted"
  else
    pass "unsafe app input rejected"
  fi
done

profile_plan_parse_requested_apps helpdesk
profile_plan_resolve_apps advanced || fail_case "dependency plan rejected"
assert_eq "transitive dependency order" 'frappe,telephony,helpdesk' "$PROFILE_PLAN_DESIRED_CSV"

# Inject catalog-policy faults without changing production catalog records.
eval "$(declare -f app_profile_defaults | sed '1s/app_profile_defaults/app_profile_defaults_original/')"
app_profile_defaults() {
  app_profile_defaults_original "$1" || return 1
  case "${TEST_CATALOG_FAULT:-}:$1" in
    missing:crm) LIB_APP_REQUIRES=missing_app ;;
    cycle:crm) LIB_APP_REQUIRES=builder ;;
    cycle:builder) LIB_APP_REQUIRES=crm ;;
    conflict:crm) LIB_APP_CONFLICTS=builder ;;
  esac
}
for fault in missing cycle conflict; do
  TEST_CATALOG_FAULT="$fault"
  if [[ "$fault" == conflict ]]; then
    profile_plan_parse_requested_apps 'crm,builder'
  else
    profile_plan_parse_requested_apps crm
  fi
  if profile_plan_resolve_apps advanced >/dev/null 2>&1; then
    fail_case "catalog ${fault} accepted"
  else
    pass "catalog ${fault} rejected"
  fi
done
TEST_CATALOG_FAULT=""

profile_plan_parse_requested_apps crm
profile_plan_resolve_apps advanced
for matrix in \
  native:native:preview-only:false \
  docker:development:preview-only:false \
  docker:production:durable-image-required:true; do
  IFS=: read -r engine environment expected durable <<<"$matrix"
  installation_profile_capability_evaluate advanced "$engine" "$environment" \
    || fail_case "capability matrix rejected $engine/$environment"
  assert_eq "capability $engine/$environment" "$expected" "$PROFILE_PLAN_CAPABILITY"
  assert_eq "durable image $engine/$environment" "$durable" "$PROFILE_PLAN_DURABLE_IMAGE"
done
installation_profile_capability_evaluate existing native native
assert_eq "existing remains preview only" preview-only "$PROFILE_PLAN_CAPABILITY"
if installation_profile_capability_evaluate advanced docker unsupported >/dev/null 2>&1; then
  fail_case "unsupported environment accepted"
else
  pass "unsupported environment rejected"
fi

printf 'SITE_NAME=legacy.test\n' >"$CONFIG_FILE"
before="$(sha256sum "$CONFIG_FILE")"
read_installation_profile_metadata "$CONFIG_FILE"
assert_eq "legacy profile default" recommended "$PROFILE_METADATA_PROFILE"
assert_eq "legacy schema" legacy "$PROFILE_METADATA_SCHEMA"
assert_eq "legacy config read only" "$before" "$(sha256sum "$CONFIG_FILE")"

printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=advanced\nINSTALLATION_PROFILE_APPS=crm,helpdesk\n' >"$CONFIG_FILE"
read_installation_profile_metadata "$CONFIG_FILE"
assert_eq "schema 2 profile" advanced "$PROFILE_METADATA_PROFILE"
assert_eq "schema 2 apps" crm,helpdesk "$PROFILE_METADATA_APPS"
printf 'CONFIG_SCHEMA=99\nINSTALLATION_PROFILE=recommended\n' >"$CONFIG_FILE"
if read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1; then
  fail_case "unknown config schema accepted"
else
  assert_eq "unknown schema incompatible" incompatible "$PROFILE_METADATA_STATUS"
fi

set_inventory() { INVENTORY_RECORDS=("$@"); }
PROFILE_PLAN_PROFILE=recommended
PROFILE_PLAN_DESIRED_CSV=frappe,erpnext
PROFILE_PLAN_CAPABILITY=supported
PROFILE_METADATA_STATUS=compatible
set_inventory \
  'STACK|native:/bench|native|native|recommended|managed|clean' \
  'SITE|native:/bench|one.test|known' \
  'SITE_APP|native:/bench|one.test|frappe|installed' \
  'SITE_APP|native:/bench|one.test|erpnext|installed'
installation_profile_reconcile
assert_eq "reconciliation consistent" consistent "$PROFILE_PLAN_RECONCILIATION"
fingerprint_one="$(planner_inventory_fingerprint)"
set_inventory \
  'SITE_APP|native:/bench|one.test|erpnext|installed' \
  'SITE|native:/bench|one.test|known' \
  'STACK|native:/bench|native|native|recommended|managed|clean' \
  'SITE_APP|native:/bench|one.test|frappe|installed'
fingerprint_two="$(planner_inventory_fingerprint)"
assert_eq "inventory fingerprint ordering invariance" "$fingerprint_one" "$fingerprint_two"
installation_profile_reconcile
assert_eq "ordering does not alter reconciliation" consistent "$PROFILE_PLAN_RECONCILIATION"

INVENTORY_RECORDS+=('SITE_APP|native:/bench|one.test|crm|installed')
installation_profile_reconcile
assert_eq "reconciliation drift extra" drift-extra "$PROFILE_PLAN_RECONCILIATION"
set_inventory \
  'STACK|native:/bench|native|native|recommended|managed|clean' \
  'SITE|native:/bench|one.test|known' \
  'SITE_APP|native:/bench|one.test|frappe|installed'
installation_profile_reconcile
assert_eq "reconciliation drift missing" drift-missing "$PROFILE_PLAN_RECONCILIATION"
INVENTORY_RECORDS+=('ISSUE|native:/bench|site|discovery|ambiguous')
installation_profile_reconcile
assert_eq "reconciliation ambiguous" ambiguous "$PROFILE_PLAN_RECONCILIATION"
set_inventory 'STACK|native:/bench|native|native|recommended|supported-unadopted|clean'
installation_profile_reconcile
assert_eq "reconciliation unmanaged" unmanaged "$PROFILE_PLAN_RECONCILIATION"
PROFILE_METADATA_STATUS=incompatible
installation_profile_reconcile
assert_eq "reconciliation incompatible" incompatible "$PROFILE_PLAN_RECONCILIATION"

# End-to-end CLI preview fixture. It must not lock, configure, journal, mutate
# inventory, or invoke any Bench/Docker mutation command.
mkdir -p "$fixture/cli-bench/apps/frappe" "$fixture/cli-bench/apps/telephony" \
  "$fixture/cli-bench/apps/helpdesk" "$fixture/cli-bench/sites/one.test"
for app in frappe telephony helpdesk; do
  case "$app" in
    frappe) repo=https://github.com/frappe/frappe ;;
    telephony) repo=https://github.com/frappe/telephony ;;
    helpdesk) repo=https://github.com/frappe/helpdesk ;;
  esac
  printf 'VERSION=16.0.0\nBRANCH=version-16\nCOMMIT=%040d\nSOURCE=%s\nSTATE=clean\n' \
    1 "$repo" >"$fixture/cli-bench/apps/$app/.inventory-meta"
done
printf 'frappe\ntelephony\nhelpdesk\n' >"$fixture/cli-bench/sites/one.test/apps.txt"
printf 'SITE_NAME=one.test\nINSTALLATION_PROFILE=frappe-only\n' >"$fixture/cli-config"
cli_before="$(find "$fixture/cli-bench" "$fixture/cli-config" -type f -print0 | sort -z | xargs -0 sha256sum)"
run_cli() {
  LOG_DIR="$fixture/logs" LOCK_DIR="$fixture/locks" CONFIG_FILE="$fixture/cli-config" \
    LEGACY_CONFIG_FILE="$fixture/no-legacy" ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT="$fixture/cli-bench" \
    ERPNEXT_DEV_INVENTORY_FIXTURE_MANAGEMENT=managed DEPLOYMENT_ENGINE=native \
    bash "$ROOT_DIR/erpnext-dev.sh" "$@"
}
json_one="$(run_cli install --profile advanced --apps helpdesk --preview --json --no-color)"
json_two="$(run_cli --no-color --json --apps=helpdesk --profile=advanced --preview install)"
assert_eq "option ordering byte stability" "$json_one" "$json_two"
assert_has "JSON schema" "$json_one" '"schema_version":1'
assert_has "JSON desired apps" "$json_one" '"desired_applications":["frappe","telephony","helpdesk"]'
assert_has "JSON reconciliation" "$json_one" '"reconciliation":"consistent"'
assert_has "stale metadata is reported, not authoritative" "$json_one" '"metadata_state":"stale"'
assert_has "JSON non-mutation declaration" "$json_one" '"mutation_performed":false'
[[ "$json_one" != *$'\033'* ]] && pass "JSON has no ANSI" || fail_case "JSON contains ANSI"
human_one="$(run_cli install --profile advanced --apps helpdesk --preview --no-color)"
human_two="$(run_cli --apps helpdesk --preview --profile advanced setup --no-color)"
assert_eq "human preview deterministic" "$human_one" "$human_two"
assert_has "human non-mutation declaration" "$human_one" 'NO DEPLOYMENT MUTATION OCCURRED.'
cli_after="$(find "$fixture/cli-bench" "$fixture/cli-config" -type f -print0 | sort -z | xargs -0 sha256sum)"
assert_eq "preview leaves deployment/config unchanged" "$cli_before" "$cli_after"
[[ ! -e "$fixture/locks/toolkit.lock" ]] && pass "preview does not acquire mutation lock" || fail_case "preview acquired lock"
[[ ! -e "$fixture/operations" ]] && pass "preview creates no operation journal" || fail_case "preview created journal"

set +e
bad_json="$(run_cli install --profile advanced --apps 'crm;id' --preview --json --no-color 2>"$fixture/bad.err")"
bad_rc=$?
set -e
[[ "$bad_rc" -ne 0 ]] && pass "invalid preview returns failure" || fail_case "invalid preview succeeded"
assert_has "invalid JSON remains valid contract" "$bad_json" '"valid":false'
[[ "$bad_json" != *'crm;id'* ]] && pass "unsafe raw input not reflected" || fail_case "unsafe input leaked"
[[ ! -s "$fixture/bad.err" ]] && pass "semantic JSON failure keeps diagnostics in JSON" || fail_case "unexpected stderr"

set +e
bad_profile_json="$(run_cli install --profile '../advanced' --preview --json --no-color 2>"$fixture/bad-profile.err")"
bad_profile_rc=$?
set -e
[[ "$bad_profile_rc" -ne 0 ]] && pass "invalid profile preview returns failure" || fail_case "invalid profile preview succeeded"
assert_has "invalid profile JSON contract" "$bad_profile_json" '"valid":false'
[[ "$bad_profile_json" != *'../advanced'* ]] && pass "unsafe profile not reflected" || fail_case "unsafe profile leaked"

printf 'CONFIG_SCHEMA=99\nINSTALLATION_PROFILE=recommended\n' >"$fixture/cli-config"
set +e
schema_json="$(run_cli install --profile recommended --preview --json --no-color)"
schema_rc=$?
set -e
[[ "$schema_rc" -ne 0 ]] && pass "incompatible schema blocks planning" || fail_case "incompatible schema succeeded"
assert_has "incompatible schema JSON" "$schema_json" '"reconciliation":"incompatible"'
assert_has "incompatible schema validation" "$schema_json" '"valid":false'
printf 'SITE_NAME=one.test\nINSTALLATION_PROFILE=frappe-only\n' >"$fixture/cli-config"

for args in \
  'help --profile advanced --preview' \
  'install --apps crm --preview' \
  'install --profile advanced --apps crm' \
  'install --profile advanced --profile advanced --apps crm --preview' \
  'install --profile advanced --apps crm --apps crm --preview'; do
  set +e
  # shellcheck disable=SC2086 # deliberate argument-vector fixture
  run_cli $args >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] && pass "invalid option scope rejected" || fail_case "invalid option scope accepted"
done

if ((failures > 0)); then
  printf 'installation profile contract tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'installation profile contract tests: all checks passed\n'
