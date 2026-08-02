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
source lib/support.sh
path_is_dir() { [[ -d "$1" ]]; }

for pair in \
  recommended:recommended default:recommended erpnext:recommended frappe-erpnext:recommended \
  frappe-only:frappe-only frappe_only:frappe-only frappe:frappe-only \
  advanced:advanced existing:existing; do
  assert_eq "profile normalization ${pair%%:*}" "${pair#*:}" \
    "$(normalize_installation_profile "${pair%%:*}")"
done
bad_profiles=('' unknown '../frappe' 'frappe only' 'advanced;id' ' recommended' 'recommended ' $'ad\tvanced' $'ad\nvanced' $'ad\rvanced' $'existing\001')
for profile in recommended frappe-only advanced existing; do
  bad_profiles+=("${profile:0:1} ${profile:1}")
done
for bad in "${bad_profiles[@]}"; do
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

assess_app_compatibility "$fixture/no-bench" crm "Frappe CRM" main \
  https://github.com/frappe/crm false
assert_eq "absent ERPNext branch is not fabricated" not-installed "$APP_COMPAT_ERPNEXT_BRANCH"
grep -q 'blocked: requires ERPNext through an explicit reviewed plan' lib/apps.sh \
  && pass "App Management explains ERPNext dependency blocking" \
  || fail_case "App Management lacks ERPNext dependency explanation"
grep -q 'shared-code impact preserved' lib/apps.sh \
  && pass "App Management exposes shared-code impact" \
  || fail_case "App Management lacks shared-code impact"

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
printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE= advanced \n' >"$CONFIG_FILE"
if read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1; then
  fail_case "unsafe persisted profile accepted"
else
  assert_eq "unsafe persisted profile incompatible" incompatible "$PROFILE_METADATA_STATUS"
fi
printf 'CONFIG_SCHEMA=99\nINSTALLATION_PROFILE=recommended\n' >"$CONFIG_FILE"
if read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1; then
  fail_case "unknown config schema accepted"
else
  assert_eq "unknown schema incompatible" incompatible "$PROFILE_METADATA_STATUS"
fi

set_inventory() { INVENTORY_RECORDS=("$@"); }
app_record() {
  local stack="$1" app="$2" version="$3" source="$4" state="${5:-clean}" availability="${6:-available}"
  printf 'APP|%s|%s|%s|%s|version-16|%040d|%s|official|managed|%s' \
    "$stack" "$app" "$availability" "$version" 1 "$source" "$state"
}
supported_single_site() {
  local management="${1:-managed}"
  set_inventory \
    'STACK|native:/bench|native|native|recommended|'"$management"'|clean' \
    "$(app_record native:/bench frappe 16.2.0 https://github.com/frappe/frappe)" \
    "$(app_record native:/bench erpnext 16.1.0 https://github.com/frappe/erpnext)" \
    'SITE|native:/bench|one.test|known' \
    'SITE_APP|native:/bench|one.test|frappe|installed' \
    'SITE_APP|native:/bench|one.test|erpnext|installed'
}
assert_reconciliation() {
  local label="$1" expected="$2"
  installation_profile_reconcile
  assert_eq "$label" "$expected" "$PROFILE_PLAN_RECONCILIATION"
}
PROFILE_PLAN_PROFILE=recommended
PROFILE_PLAN_DESIRED_CSV=frappe,erpnext
PROFILE_PLAN_CAPABILITY=supported
PROFILE_PLAN_ENGINE=native
PROFILE_PLAN_ENVIRONMENT=native
PROFILE_METADATA_STATUS=compatible
supported_single_site
assert_reconciliation "trusted v16 single-site reconciliation" consistent
assert_eq "consistent presentation severity" OK "$(installation_profile_reconciliation_status consistent)"
fingerprint_one="$(planner_inventory_fingerprint)"
INVENTORY_RECORDS=("${INVENTORY_RECORDS[@]:3}" "${INVENTORY_RECORDS[@]:0:3}")
fingerprint_two="$(planner_inventory_fingerprint)"
assert_eq "inventory fingerprint ordering invariance" "$fingerprint_one" "$fingerprint_two"
assert_reconciliation "ordering does not alter reconciliation" consistent

supported_single_site
INVENTORY_RECORDS+=("$(app_record native:/bench crm 1.0.0 https://github.com/frappe/crm)" 'SITE_APP|native:/bench|one.test|crm|installed')
assert_reconciliation "reconciliation drift extra" drift-extra
assert_eq "drift-extra presentation severity" INFO "$(installation_profile_reconciliation_status drift-extra)"
supported_single_site
INVENTORY_RECORDS=("${INVENTORY_RECORDS[@]/SITE_APP|native:\/bench|one.test|erpnext|installed/}")
assert_reconciliation "reconciliation drift missing" drift-missing
assert_eq "drift-missing presentation severity" WARN "$(installation_profile_reconciliation_status drift-missing)"
INVENTORY_RECORDS+=('ISSUE|native:/bench|site|discovery|ambiguous')
assert_reconciliation "reconciliation ambiguous" ambiguous
assert_eq "ambiguous presentation severity" WARN "$(installation_profile_reconciliation_status ambiguous)"

PROFILE_PLAN_PROFILE=frappe-only
PROFILE_PLAN_DESIRED_CSV=frappe
set_inventory \
  'STACK|native:/bench|native|native|frappe-only|managed|clean' \
  "$(app_record native:/bench frappe 16.2.0 https://github.com/frappe/frappe)" \
  'SITE|native:/bench|one.test|known' \
  'SITE_APP|native:/bench|one.test|frappe|installed'
assert_reconciliation "Frappe-only is consistent without ERPNext" consistent
PROFILE_CONTEXT_DESIRED_APPS=frappe
if installation_profile_context_requires_app erpnext; then
  fail_case "Frappe-only incorrectly requires ERPNext"
else
  pass "Frappe-only ERPNext absence is optional"
fi
INVENTORY_RECORDS+=("$(app_record native:/bench erpnext 16.1.0 https://github.com/frappe/erpnext)" 'SITE_APP|native:/bench|one.test|erpnext|installed')
assert_reconciliation "Frappe-only preserves ERPNext as drift-extra" drift-extra

PROFILE_PLAN_PROFILE=advanced
PROFILE_PLAN_DESIRED_CSV=frappe,telephony,helpdesk
supported_single_site
assert_reconciliation "advanced desired apps missing" drift-missing
PROFILE_CONTEXT_DESIRED_APPS=frappe,erpnext,webshop
installation_profile_context_requires_app erpnext \
  && pass "advanced dependency closure requires ERPNext" \
  || fail_case "advanced dependency closure lost ERPNext requirement"

supported_single_site
INVENTORY_RECORDS[1]="$(app_record native:/bench frappe 17.0.0 https://github.com/frappe/frappe)"
assert_reconciliation "unsupported Frappe major" incompatible
supported_single_site
INVENTORY_RECORDS[2]="$(app_record native:/bench erpnext 17.0.0 https://github.com/frappe/erpnext)"
assert_reconciliation "unsupported ERPNext major" incompatible
supported_single_site
INVENTORY_RECORDS[2]="$(app_record native:/bench erpnext 16.1.0 https://example.invalid/erpnext)"
assert_reconciliation "known catalog source mismatch" incompatible
mismatch_fingerprint="$(planner_inventory_fingerprint)"
[[ "$mismatch_fingerprint" != "$fingerprint_one" ]] \
  && pass "source trust classification changes fingerprint" \
  || fail_case "source trust change did not alter fingerprint"
supported_single_site
INVENTORY_RECORDS[1]="$(app_record native:/bench frappe 16.2.0 unknown)"
assert_reconciliation "unknown source is ambiguous" ambiguous
supported_single_site
INVENTORY_RECORDS[1]="$(app_record native:/bench frappe 16.2.0 https://github.com/frappe/frappe dirty)"
assert_reconciliation "dirty code is ambiguous" ambiguous
supported_single_site
INVENTORY_RECORDS[1]='APP|native:/bench|frappe|missing|unknown|unknown|unknown|unknown|official|managed|missing'
assert_reconciliation "missing desired code is not consistent" ambiguous

supported_single_site
INVENTORY_RECORDS+=('STACK|native:/other|native|native|recommended|supported-unadopted|clean')
assert_reconciliation "two stacks are ambiguous" ambiguous
supported_single_site
INVENTORY_RECORDS+=('SITE|native:/bench|two.test|known' 'SITE_APP|native:/bench|two.test|frappe|installed')
assert_reconciliation "two sites are ambiguous" ambiguous
supported_single_site
INVENTORY_RECORDS=("${INVENTORY_RECORDS[@]:0:3}"
  'SITE|native:/bench|one.test|known' 'SITE|native:/bench|two.test|known'
  'SITE_APP|native:/bench|one.test|frappe|installed' 'SITE_APP|native:/bench|two.test|erpnext|installed')
assert_reconciliation "applications split across sites" ambiguous

PROFILE_PLAN_PROFILE=existing
PROFILE_PLAN_DESIRED_CSV=""
supported_single_site supported-unadopted
assert_reconciliation "one compatible existing candidate" unmanaged
INVENTORY_RECORDS+=('STACK|native:/other|native|native|recommended|supported-unadopted|clean')
assert_reconciliation "multiple existing candidates" ambiguous
supported_single_site supported-unadopted
INVENTORY_RECORDS[1]="$(app_record native:/bench frappe 17.0.0 https://github.com/frappe/frappe)"
assert_reconciliation "incompatible existing candidate" incompatible
assert_eq "incompatible presentation severity" FAIL "$(installation_profile_reconciliation_status incompatible)"

PROFILE_PLAN_PROFILE=recommended
PROFILE_PLAN_DESIRED_CSV=frappe,erpnext
PROFILE_METADATA_STATUS=incompatible
assert_reconciliation "configuration reconciliation incompatible" incompatible
PROFILE_METADATA_STATUS=compatible

# Operational surfaces consume the same metadata/plan/inventory context and do
# not rewrite configuration while doing so.
eval "$(declare -f inventory_collect | sed '1s/inventory_collect/inventory_collect_original/')"
inventory_collect() {
  supported_single_site
  if [[ "${PROFILE_PLAN_PROFILE:-recommended}" == frappe-only ]]; then
    INVENTORY_RECORDS=("${INVENTORY_RECORDS[@]/APP|native:\/bench|erpnext|available|16.1.0|version-16|0000000000000000000000000000000000000001|https:\/\/github.com\/frappe\/erpnext|official|managed|clean/}")
    INVENTORY_RECORDS=("${INVENTORY_RECORDS[@]/SITE_APP|native:\/bench|one.test|erpnext|installed/}")
  fi
}
for context_profile in recommended frappe-only; do
  printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=%s\n' "$context_profile" >"$CONFIG_FILE"
  context_before="$(sha256sum "$CONFIG_FILE")"
  installation_profile_operational_context_collect "$CONFIG_FILE" || fail_case "operational context rejected ${context_profile}"
  assert_eq "operational context profile ${context_profile}" "$context_profile" "$PROFILE_CONTEXT_PROFILE"
  assert_eq "operational context reconciliation ${context_profile}" consistent "$PROFILE_CONTEXT_RECONCILIATION"
  assert_eq "operational context is read only ${context_profile}" "$context_before" "$(sha256sum "$CONFIG_FILE")"
done
unset -f inventory_collect
eval "$(declare -f inventory_collect_original | sed '1s/inventory_collect_original/inventory_collect/')"
unset -f inventory_collect_original

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

unsafe_cli_profiles=(' advanced' 'advanced ' 'a d v a n c e d' $'ad\tvanced' $'ad\nvanced' $'ad\rvanced' $'ad\001vanced')
for bad in "${unsafe_cli_profiles[@]}"; do
  set +e
  bad_profile_json="$(run_cli install --profile "$bad" --preview --json --no-color 2>"$fixture/bad-profile.err")"
  bad_profile_rc=$?
  set -e
  [[ "$bad_profile_rc" -ne 0 ]] && pass "unsafe CLI profile rejected" || fail_case "unsafe CLI profile accepted"
  assert_has "unsafe CLI profile keeps JSON contract" "$bad_profile_json" '"valid":false'
  assert_has "unsafe CLI profile declares non-mutation" "$bad_profile_json" '"mutation_performed":false'
  [[ "$bad_profile_json" != *"$bad"* ]] && pass "unsafe CLI profile not reflected" || fail_case "unsafe CLI profile leaked"
done

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

# Doctor v2 is a deterministic, safe-to-share view of the same context.
doctor_collect() {
  DOCTOR_GENERATED_AT=2026-08-02T00:00:00Z
  DOCTOR_HOSTNAME=fixture-host
  DOCTOR_CURRENT_USER=fixture-user
  DOCTOR_VM_IP=192.0.2.10
  DOCTOR_BENCH_DIR=/redacted/bench
  DOCTOR_BENCH_VERSION=16.0.0
  DOCTOR_INSTALL_STATE=Installed
  DOCTOR_RUNTIME_STATE=Running
  DOCTOR_SERVICE_STATE=Running
  DOCTOR_AUTOSTART_STATE=Enabled
  DOCTOR_SSL_STATE='not configured'
  DOCTOR_PROFILE=frappe-only
  DOCTOR_RECONCILIATION=consistent
  DOCTOR_DESIRED_APPS=frappe
  DOCTOR_OBSERVED_APPS=frappe
  PROFILE_CONTEXT_FINGERPRINT=fixture-fingerprint
  DOCTOR_CHECK_NAMES=('Installation profile' 'Profile reconciliation')
  DOCTOR_CHECK_STATUSES=(INFO OK)
  DOCTOR_CHECK_DETAILS=(frappe-only consistent)
  DOCTOR_OPTIONAL_APPS=()
  DOCTOR_OPTIONAL_LABELS=()
  DOCTOR_OPTIONAL_DETAILS=()
}
APP_NAME='ERPNext Developer Toolkit'
SCRIPT_VERSION=1.20.4
ERPNEXT_SERVICE_NAME=erpnext-dev.service
SITE_NAME_SOURCE=fixture
doctor_json="$(run_doctor_json)"
printf '%s' "$doctor_json" | python3 -m json.tool >/dev/null \
  && pass "Doctor v2 JSON is valid" \
  || fail_case "Doctor v2 JSON is invalid"
assert_has "Doctor schema version" "$doctor_json" '"schema_version": "2"'
assert_has "Doctor profile context" "$doctor_json" '"profile": "frappe-only"'
assert_has "Doctor reconciliation context" "$doctor_json" '"reconciliation": "consistent"'
[[ "$doctor_json" != *$'\033'* ]] && pass "Doctor JSON has no ANSI" || fail_case "Doctor JSON contains ANSI"

if ((failures > 0)); then
  printf 'installation profile contract tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'installation profile contract tests: all checks passed\n'
