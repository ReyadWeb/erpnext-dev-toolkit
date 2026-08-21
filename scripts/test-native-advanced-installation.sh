#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ASSERTIONS=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
pass() {
  ASSERTIONS=$((ASSERTIONS + 1))
  printf 'OK: %s\n' "$1"
}
assert_eq() {
  [[ "$2" == "$3" ]] || fail "$1: got [$2], expected [$3]"
  pass "$1"
}
assert_has() {
  grep -Fq -- "$3" <<<"$2" || fail "$1: missing [$3]"
  pass "$1"
}
assert_lacks() {
  ! grep -Fq -- "$3" <<<"$2" || fail "$1: unexpectedly contained [$3]"
  pass "$1"
}

source "$ROOT_DIR/lib/apps.sh"
source "$ROOT_DIR/lib/profile.sh"
source "$ROOT_DIR/lib/native_advanced.sh"

SUDO=""
FRAPPE_USER=frappe
FRAPPE_HOME="$WORK/home/frappe"
BENCH_PARENT="$FRAPPE_HOME/frappe"
BENCH_NAME=frappe-bench
BENCH_DIR="$BENCH_PARENT/$BENCH_NAME"
CONFIG_FILE="$WORK/etc/config.env"
LEGACY_CONFIG_FILE="$WORK/home/frappe/legacy.env"
NATIVE_ADVANCED_STATE_DIR="$WORK/state"
DEPLOYMENT_MODE=development
INSTALLATION_PROFILE=advanced
INSTALLATION_PROFILE_OPTION_PROVIDED=1
QUICK_INSTALL_PREVIEW=0
ASSUME_YES=1
NVM_VERSION=0.40.3 NODE_VERSION=24 UV_VERSION=0.11.28 PYTHON_VERSION=3.14 BENCH_VERSION=5.31.0 FRAPPE_BRANCH=version-16
ERPNEXT_DEV_NATIVE_ADVANCED_TEST=1
export ERPNEXT_DEV_NATIVE_ADVANCED_TEST
err() { printf 'ERROR: %s\n' "$*" >&2; }
ok() { printf 'OK: %s\n' "$*"; }
planner_timestamp() { printf '2026-08-20T12:00:00Z\n'; }
planner_exit_code() {
  case "$1" in success) return 0 ;; preview) return 11 ;; cancelled) return 12 ;; invalid-input) return 20 ;; ambiguous-target) return 21 ;; incompatible) return 22 ;; unsupported) return 23 ;; mutation-failed) return 31 ;; verification-failed) return 32 ;; recovery-required) return 33 ;; conflict) return 34 ;; esac
}
effective_deployment_engine() { printf '%s\n' "${TEST_ENGINE:-native}"; }
validate_site_name_value() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ && "$1" != *..* ]]; }
require_sudo() { :; }

MUTATION_LOG="$WORK/mutations"
phase_log() { printf '%s\n' "$1" >>"$MUTATION_LOG"; }
native_advanced_prerequisites() { phase_log prerequisites; }
native_advanced_user_setup() { phase_log frappe-user; }
native_advanced_toolchain_setup() { phase_log frappe-environment; }
native_advanced_bench_create() {
  phase_log bench-created
  mkdir -p "$BENCH_DIR/apps/frappe"
  native_advanced_ledger_add bench
}
native_advanced_site_create() {
  phase_log site-created
  mkdir -p "$BENCH_DIR/sites/$SITE_NAME"
  NATIVE_ADVANCED_SITE_CREATED=1
  native_advanced_ledger_add site
}
native_advanced_baseline_backup() {
  phase_log baseline-backup
  NATIVE_ADVANCED_BACKUP=verified-baseline
  native_advanced_ledger_add baseline-backup
}
native_advanced_get_app() {
  phase_log "get-app:$1"
  mkdir -p "$BENCH_DIR/apps/$1"
  native_advanced_ledger_add "code:$1"
}
native_advanced_install_app() {
  phase_log "install-app:$1"
  native_advanced_ledger_add "site-app:$1"
}
native_advanced_migrate() { phase_log migration; }
native_advanced_assets() { phase_log assets; }
native_advanced_services() { phase_log services; }
native_advanced_readiness() { phase_log readiness; }
native_advanced_verify() { phase_log inventory; }
native_advanced_post_reconcile() {
  phase_log post-promotion-reconciliation
  grep -Fq 'INSTALLATION_PROFILE=advanced' "$CONFIG_FILE"
}

reset_case() {
  rm -rf "${WORK:?}/home" "${WORK:?}/etc" "${WORK:?}/state" "$MUTATION_LOG"
  mkdir -p "$WORK"
  NATIVE_ADVANCED_OPERATION_FILE="" NATIVE_ADVANCED_OPERATION_ID="" NATIVE_ADVANCED_STATUS="" NATIVE_ADVANCED_CHECKPOINT=""
  NATIVE_ADVANCED_RESULT="" NATIVE_ADVANCED_RECOVERY="" NATIVE_ADVANCED_PREFLIGHT="" NATIVE_ADVANCED_LEDGER=""
  NATIVE_ADVANCED_BACKUP=none NATIVE_ADVANCED_CONFIG_BASE="" NATIVE_ADVANCED_SITE_CREATED=0
  NATIVE_ADVANCED_FAIL_AT="" TEST_ENGINE=native ASSUME_YES=1 QUICK_INSTALL_PREVIEW=0
  SITE_NAME=erp.test QUICK_INSTALL_SITE=erp.test INSTALLATION_PROFILE_APPS_RAW=crm
  NATIVE_ADVANCED_OPERATION_ID_OVERRIDE="test"
}

# Pure catalog behavior.
profile_plan_parse_requested_apps crm
profile_plan_resolve_apps advanced
assert_eq 'ERPNext-free requested set' "$PROFILE_PLAN_REQUESTED_CSV" crm
assert_eq 'Frappe implicit in closure' "$PROFILE_PLAN_DESIRED_CSV" frappe,crm
profile_plan_parse_requested_apps helpdesk,crm
profile_plan_resolve_apps advanced
assert_eq 'deterministic requested order' "$PROFILE_PLAN_REQUESTED_CSV" crm,helpdesk
assert_eq 'dependency order' "$PROFILE_PLAN_DESIRED_CSV" frappe,crm,telephony,helpdesk
profile_plan_parse_requested_apps webshop
profile_plan_resolve_apps advanced
assert_eq 'ERPNext dependency inclusion' "$PROFILE_PLAN_DESIRED_CSV" frappe,erpnext,webshop
for bad in frappe unknown crm,crm ../crm 'crm;id' CRM ''; do
  if profile_plan_parse_requested_apps "$bad" >/dev/null 2>&1; then fail "unsafe app accepted: $bad"; fi
  pass "reject app selection ${bad:-empty}"
done

# Exercise the real entrypoint and dispatcher, with every writable/protected
# path isolated. Platform executables are poisoned so a preview cannot pass by
# silently invoking a real host command.
ENTRY_WORK="$WORK/entrypoint"
mkdir -p "$ENTRY_WORK/bin" "$ENTRY_WORK/log"
PLATFORM_LOG="$ENTRY_WORK/platform.log"
for platform_command in apt apt-get bench docker git mysql mariadb npm systemctl useradd; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$(basename "$0")" >>"$PLATFORM_LOG"\nexit 99\n' \
    >"$ENTRY_WORK/bin/$platform_command"
  chmod +x "$ENTRY_WORK/bin/$platform_command"
done
ENTRY_ENV=(
  "PATH=$ENTRY_WORK/bin:$PATH"
  "PLATFORM_LOG=$PLATFORM_LOG"
  "LOG_DIR=$ENTRY_WORK/log"
  "CONFIG_FILE=$ENTRY_WORK/config.env"
  "LEGACY_CONFIG_FILE=$ENTRY_WORK/legacy.env"
  "BENCH_PARENT=$ENTRY_WORK/bench-parent"
  "NATIVE_ADVANCED_STATE_DIR=$ENTRY_WORK/operations"
  "LOCK_DIR=$ENTRY_WORK/lock"
  "NO_COLOR=1"
)
run_entrypoint() {
  local output_file="$1"
  shift
  set +e
  env "${ENTRY_ENV[@]}" "$ROOT_DIR/erpnext-dev.sh" "$@" >"$output_file" 2>&1
  ENTRY_RC=$?
  set -e
}

run_entrypoint "$ENTRY_WORK/preview-1.out" install \
  --profile advanced \
  --apps crm,helpdesk \
  --site erp.test \
  --preview
assert_eq 'entrypoint executable preview exit' "$ENTRY_RC" 11
entry_preview="$(<"$ENTRY_WORK/preview-1.out")"
assert_has 'entrypoint dedicated plan' "$entry_preview" 'Native Advanced Installation Plan'
assert_has 'entrypoint exact site' "$entry_preview" 'Exact site: erp.test'
assert_has 'entrypoint requested apps' "$entry_preview" 'Requested applications: crm,helpdesk'
assert_has 'entrypoint resolved apps' "$entry_preview" 'Resolved dependency closure: frappe,crm,telephony,helpdesk'
assert_has 'entrypoint dependency order' "$entry_preview" 'Application installation order: frappe,crm,telephony,helpdesk'
assert_lacks 'entrypoint excludes ERPNext' "$entry_preview" 'erpnext'
assert_lacks 'entrypoint excludes preview-only capability' "$entry_preview" 'Capability: preview-only'
assert_lacks 'entrypoint excludes deferred adapter warning' "$entry_preview" 'installation adapter is intentionally deferred'
assert_lacks 'entrypoint excludes ambiguous reconciliation' "$entry_preview" 'Reconciliation: ambiguous'
[[ ! -e "$ENTRY_WORK/config.env" && ! -e "$ENTRY_WORK/legacy.env" &&
  ! -e "$ENTRY_WORK/operations" && ! -e "$ENTRY_WORK/lock" &&
  ! -e "$ENTRY_WORK/bench-parent" && ! -e "$PLATFORM_LOG" ]] \
  || fail 'entrypoint preview mutated state or invoked a platform command'
pass 'entrypoint executable preview is mutation-free'
run_entrypoint "$ENTRY_WORK/preview-2.out" install --profile advanced --apps crm,helpdesk --site erp.test --preview
assert_eq 'repeated entrypoint preview exit' "$ENTRY_RC" 11
assert_eq 'repeated entrypoint preview deterministic' "$(<"$ENTRY_WORK/preview-1.out")" "$(<"$ENTRY_WORK/preview-2.out")"

run_entrypoint "$ENTRY_WORK/site-less.out" install --profile advanced --apps crm,helpdesk --preview
assert_eq 'site-less preview compatibility exit' "$ENTRY_RC" 0
assert_has 'site-less preview schema 1' "$(<"$ENTRY_WORK/site-less.out")" 'Installation Profile Plan (schema 1)'
run_entrypoint "$ENTRY_WORK/existing.out" install --profile existing --preview
assert_eq 'existing preview compatibility exit' "$ENTRY_RC" 0
assert_has 'existing remains preview-only' "$(<"$ENTRY_WORK/existing.out")" 'Capability: preview-only'
for profile in recommended frappe-only; do
  run_entrypoint "$ENTRY_WORK/$profile.out" install --profile "$profile" --preview
  assert_eq "$profile preview compatibility exit" "$ENTRY_RC" 0
  assert_has "$profile preview schema 1" "$(<"$ENTRY_WORK/$profile.out")" 'Installation Profile Plan (schema 1)'
done

set +e
printf 'n\n' | env "${ENTRY_ENV[@]}" ERPNEXT_DEV_TEST_INTERACTIVE=1 \
  "$ROOT_DIR/erpnext-dev.sh" install --profile advanced --apps crm,helpdesk --site erp.test \
  >"$ENTRY_WORK/cancel.out" 2>&1
ENTRY_RC=${PIPESTATUS[1]}
set -e
assert_eq 'interactive dispatcher cancellation exit' "$ENTRY_RC" 12
assert_has 'interactive dispatcher reaches dedicated plan' "$(<"$ENTRY_WORK/cancel.out")" 'Native Advanced Installation Plan'
assert_has 'interactive cancellation is explicit' "$(<"$ENTRY_WORK/cancel.out")" 'Installation cancelled before mutation.'
[[ ! -e "$ENTRY_WORK/config.env" && ! -e "$ENTRY_WORK/operations" && ! -e "$PLATFORM_LOG" ]] \
  || fail 'entrypoint cancellation mutated state or invoked a platform command'
pass 'entrypoint cancellation is mutation-free'

run_entrypoint "$ENTRY_WORK/noninteractive.out" install --profile advanced --apps crm,helpdesk --site erp.test --yes
assert_eq 'noninteractive dispatcher reaches sudo transaction gate' "$ENTRY_RC" 1
assert_has 'noninteractive dispatcher reaches dedicated plan' "$(<"$ENTRY_WORK/noninteractive.out")" 'Native Advanced Installation Plan'
assert_has 'noninteractive transaction requires privilege' "$(<"$ENTRY_WORK/noninteractive.out")" 'must be run with sudo'

for docker_mode in preview mutation; do
  docker_args=(install --profile advanced --apps 'crm,helpdesk' --site erp.test)
  [[ "$docker_mode" == mutation ]] || docker_args+=(--preview)
  set +e
  env "${ENTRY_ENV[@]}" DEPLOYMENT_ENGINE=docker "$ROOT_DIR/erpnext-dev.sh" "${docker_args[@]}" \
    >"$ENTRY_WORK/docker-$docker_mode.out" 2>&1
  ENTRY_RC=$?
  set -e
  assert_eq "Docker advanced $docker_mode unsupported exit" "$ENTRY_RC" 23
  assert_has "Docker advanced $docker_mode message" "$(<"$ENTRY_WORK/docker-$docker_mode.out")" 'unsupported for Docker'
  [[ ! -e "$PLATFORM_LOG" ]] || fail "Docker command executed during advanced $docker_mode"
  pass "Docker advanced $docker_mode executes no platform command"
done

reset_case
profile_plan_parse_requested_apps helpdesk
profile_plan_resolve_apps advanced
NATIVE_ADVANCED_REQUESTED="$PROFILE_PLAN_REQUESTED_CSV" NATIVE_ADVANCED_RESOLVED="$PROFILE_PLAN_DESIRED_CSV" SITE_NAME=erp.test
plan1="$(native_advanced_plan)"
plan2="$(native_advanced_plan)"
assert_eq 'deterministic repeated plan' "$plan1" "$plan2"
assert_has 'catalog repository exact' "$plan1" 'telephony repository=https://github.com/frappe/telephony ref=develop'
assert_has 'catalog branch exact' "$plan1" 'helpdesk repository=https://github.com/frappe/helpdesk ref=main'
assert_has 'backup boundary in plan' "$plan1" 'after site creation and before any application acquisition'
assert_has 'recovery model in plan' "$plan1" 'post-site failures are recovery-required'

for site in '' localhost 'bad site' '../erp.test' 'http://erp.test' 'erp.test:8000' '-bad.test' 'bad..test' 'bad/test'; do
  if validate_site_name_value "$site" >/dev/null 2>&1; then fail "hostile site accepted: $site"; fi
  pass "reject site ${site:-empty}"
done

# Preview and cancellation are mutation-free.
reset_case
QUICK_INSTALL_PREVIEW=1
set +e
native_advanced_install >"$WORK/preview.out" 2>"$WORK/preview.err"
rc=$?
set -e
assert_eq 'preview exit' "$rc" 11
[[ ! -e "$MUTATION_LOG" && ! -e "$NATIVE_ADVANCED_STATE_DIR" && ! -e "$CONFIG_FILE" ]] || fail 'preview mutated state'
pass 'preview zero mutation'
reset_case
ASSUME_YES=0
native_advanced_confirm() { return 1; }
set +e
native_advanced_install >"$WORK/cancel.out" 2>"$WORK/cancel.err"
rc=$?
set -e
assert_eq 'cancellation exit' "$rc" 12
[[ ! -e "$MUTATION_LOG" && ! -e "$NATIVE_ADVANCED_STATE_DIR" && ! -e "$CONFIG_FILE" ]] || fail 'cancellation mutated state'
pass 'cancellation zero mutation'
unset -f native_advanced_confirm
eval 'native_advanced_confirm() { [[ "${ASSUME_YES:-0}" -eq 1 ]]; }'

# Docker and pre-existing targets refuse before mutation.
reset_case
TEST_ENGINE=docker
set +e
native_advanced_install >/dev/null 2>"$WORK/docker.err"
rc=$?
set -e
assert_eq 'Docker advanced unsupported' "$rc" 23
[[ ! -e "$MUTATION_LOG" ]] || fail 'Docker execution occurred'
pass 'Docker zero mutation'
reset_case
mkdir -p "$BENCH_PARENT"
set +e
native_advanced_install >/dev/null 2>&1
rc=$?
set -e
assert_eq 'existing bench refusal' "$rc" 21
[[ ! -e "$MUTATION_LOG" ]] || fail 'existing bench mutated'
pass 'existing bench zero mutation'
reset_case
mkdir -p "$(dirname "$CONFIG_FILE")"
printf 'CONFIG_SCHEMA=2\n' >"$CONFIG_FILE"
set +e
native_advanced_install >/dev/null 2>&1
rc=$?
set -e
assert_eq 'existing config refusal' "$rc" 21

# Complete transaction and exact promotion.
reset_case
INSTALLATION_PROFILE_APPS_RAW=helpdesk,crm
native_advanced_install >"$WORK/success.out" 2>"$WORK/success.err"
state="$NATIVE_ADVANCED_OPERATION_FILE"
assert_has 'completed record' "$(<"$state")" 'status=completed'
assert_has 'operation type' "$(<"$state")" 'operation_type=native-advanced-installation'
assert_has 'requested intent exact' "$(<"$state")" 'requested_apps=crm,helpdesk'
assert_has 'resolved apps exact' "$(<"$state")" 'resolved_apps=frappe,crm,telephony,helpdesk'
assert_has 'baseline backup recorded' "$(<"$state")" 'baseline_backup=verified-baseline'
assert_has 'promoted schema' "$(<"$CONFIG_FILE")" 'CONFIG_SCHEMA=2'
assert_has 'promoted profile' "$(<"$CONFIG_FILE")" 'INSTALLATION_PROFILE=advanced'
assert_has 'requested apps survive promotion' "$(<"$CONFIG_FILE")" 'INSTALLATION_PROFILE_APPS=crm,helpdesk'
assert_eq 'operation directory mode' "$(stat -c %a "$NATIVE_ADVANCED_STATE_DIR")" 700
assert_eq 'operation file mode' "$(stat -c %a "$state")" 600
order="$(<"$MUTATION_LOG")"
assert_has 'dependency acquired first' "$order" $'get-app:telephony\nget-app:helpdesk'
assert_has 'dependency installed first' "$order" $'install-app:telephony\ninstall-app:helpdesk'

# Fault injection: every meaningful checkpoint, config unchanged until promotion,
# and post-site failures preserve recovery evidence.
checkpoints=(prerequisites frappe-user frappe-environment bench-created site-created baseline-backup configuration-staging get-app:crm install-app:crm migration assets services readiness inventory configuration-promotion post-promotion-reconciliation)
for checkpoint in "${checkpoints[@]}"; do
  reset_case
  NATIVE_ADVANCED_FAIL_AT="$checkpoint"
  set +e
  native_advanced_install >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" == 31 || "$rc" == 33 ]] || fail "$checkpoint returned $rc"
  record="$(<"$NATIVE_ADVANCED_OPERATION_FILE")"
  assert_has "fault checkpoint $checkpoint" "$record" "checkpoint=$checkpoint"
  if [[ "$checkpoint" == prerequisites || "$checkpoint" == frappe-user || "$checkpoint" == frappe-environment || "$checkpoint" == bench-created || "$checkpoint" == site-created ]]; then
    [[ "$record" == *'status=failed'* || "$record" == *'status=recovery-required'* ]] || fail "$checkpoint state"
  else
    assert_has "post-site recovery $checkpoint" "$record" 'status=recovery-required'
  fi
  if [[ "$checkpoint" != configuration-promotion && "$checkpoint" != post-promotion-reconciliation ]]; then
    [[ ! -e "$CONFIG_FILE" ]] || fail "$checkpoint promoted config early"
    pass "config unchanged at $checkpoint"
  fi
  if [[ "$checkpoint" == baseline-backup ]]; then
    ! grep -q '^get-app:' "$MUTATION_LOG" || fail 'app acquisition followed backup failure'
    pass 'backup failure blocks app acquisition'
  fi
done

# Concurrent configuration creation before promotion fails closed.
reset_case
native_advanced_verify() {
  phase_log inventory
  mkdir -p "$(dirname "$CONFIG_FILE")"
  printf 'CONCURRENT=1\n' >"$CONFIG_FILE"
}
set +e
native_advanced_install >/dev/null 2>&1
rc=$?
set -e
assert_eq 'concurrent config change recovery exit' "$rc" 33
grep -Fxq 'CONCURRENT=1' "$CONFIG_FILE" || fail 'concurrent config overwritten'
pass 'concurrent config preserved'

# Operation-state attacks fail closed.
reset_case
mkdir -p "$WORK/attack"
ln -s "$WORK/attack" "$NATIVE_ADVANCED_STATE_DIR"
NATIVE_ADVANCED_OPERATION_ID=x NATIVE_ADVANCED_OPERATION_FILE="$NATIVE_ADVANCED_STATE_DIR/x.state" SITE_NAME=erp.test
if native_advanced_record_write 2>/dev/null; then fail 'symlink state dir accepted'; fi
pass 'symlink state dir rejected'
rm -f "$NATIVE_ADVANCED_STATE_DIR"
printf x >"$NATIVE_ADVANCED_STATE_DIR"
if native_advanced_record_write 2>/dev/null; then fail 'regular state dir accepted'; fi
pass 'unexpected state type rejected'
rm -f "$NATIVE_ADVANCED_STATE_DIR"
mkdir -m 0777 "$NATIVE_ADVANCED_STATE_DIR"
printf x >"$NATIVE_ADVANCED_STATE_DIR/x.state"
chmod 0666 "$NATIVE_ADVANCED_STATE_DIR/x.state"
if native_advanced_record_write 2>/dev/null; then fail 'unsafe state file accepted'; fi
pass 'unsafe state permissions rejected'

# Static execution guards and secret exclusion.
! grep -Eq '(^|[^A-Za-z])eval[[:space:]]' "$ROOT_DIR/lib/native_advanced.sh" || fail 'eval in implementation'
pass 'no eval'
! grep -Eq 'bench get-app.*\$\{?INSTALLATION_PROFILE_APPS_RAW' "$ROOT_DIR/lib/native_advanced.sh" || fail 'raw apps reach command'
pass 'raw app input excluded from execution'
for marker in password secret token private.example $'\033'; do
  ! grep -R -Fiq -- "$marker" "$WORK/state" 2>/dev/null || fail "secret/control marker in record: $marker"
done
pass 'record excludes secret private URL ANSI and controls'

# Signal checkpoint semantics are deterministic without sending a real signal.
reset_case
mkdir -p "$BENCH_DIR/sites/erp.test"
NATIVE_ADVANCED_SITE_CREATED=1
NATIVE_ADVANCED_OPERATION_ID=signal NATIVE_ADVANCED_OPERATION_FILE="$NATIVE_ADVANCED_STATE_DIR/signal.state" SITE_NAME=erp.test
NATIVE_ADVANCED_REQUESTED=crm NATIVE_ADVANCED_RESOLVED=frappe,crm NATIVE_ADVANCED_PREFLIGHT=abc NATIVE_ADVANCED_CHECKPOINT=assets
set +e
native_advanced_signal TERM
rc=$?
set -e
assert_eq 'signal return' "$rc" 130
assert_has 'signal recovery state' "$(<"$NATIVE_ADVANCED_OPERATION_FILE")" 'status=recovery-required'
assert_has 'signal durable checkpoint' "$(<"$NATIVE_ADVANCED_OPERATION_FILE")" 'checkpoint=assets'

printf 'test-native-advanced-installation: %s assertions passed\n' "$ASSERTIONS"
