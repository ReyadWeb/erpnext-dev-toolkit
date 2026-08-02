#!/usr/bin/env bash
# Hermetic Phase 2 inventory/compatibility regression matrix.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fixture="$(mktemp -d "${ROOT_DIR}/.erpnext-dev-inventory-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

failures=0
fail_case() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}
pass() { echo "OK: $*"; }
assert_contains() {
  local label="$1" value="$2" expected="$3"
  if [[ "$value" == *"$expected"* ]]; then pass "$label"; else fail_case "$label (missing ${expected})"; fi
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$label"; else fail_case "$label (expected ${expected}, got ${actual})"; fi
}
assert_process_gone() {
  local label="$1" pid="$2" state
  for _ in {1..40}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      pass "$label"
      return 0
    fi
    state="$(ps -o stat= -p "$pid" 2>/dev/null || true)"
    if [[ "$state" == Z* ]]; then
      pass "$label"
      return 0
    fi
    sleep 0.05
  done
  fail_case "$label (PID ${pid} survived the timeout)"
}

SITE_NAME="one.test"
INSTALLATION_PROFILE="recommended"
DEPLOYMENT_ENGINE="native"
DOCKER_MODE="development"
DOCTOR_FORMAT="human"
FRAPPE_BRANCH="version-16"
ERPNEXT_BRANCH="version-16"
SUDO=""

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/profile.sh"
source "$ROOT_DIR/lib/apps.sh"
effective_deployment_engine() { printf '%s\n' "$DEPLOYMENT_ENGINE"; }
deployment_engine_is_docker() { [[ "$DEPLOYMENT_ENGINE" == docker ]]; }
docker_mode() { printf '%s\n' "$DOCKER_MODE"; }
active_bench_dir() { printf '%s\n' "$fixture"; }
source "$ROOT_DIR/lib/inventory.sh"

# A root-run toolkit must inspect an app repository as its filesystem owner,
# not suppress Git's dubious-ownership safeguard. Mock the account boundary so
# this regression remains hermetic on both root and non-root CI runners.
owner_bin="$fixture/owner-bin"
owner_repo="$fixture/owner-repo"
owner_probe_log="$fixture/owner-probe.log"
owner_real_stat="$(command -v stat)"
owner_real_getent="$(command -v getent)"
mkdir -p "$owner_bin" "$owner_repo/.git"
cat >"$owner_bin/stat" <<'EOF_OWNER_STAT'
#!/usr/bin/env bash
if [[ "$*" == *"%u"* && "${*: -1}" == "$ERPNEXT_TEST_OWNER_REPO" ]]; then
  printf '4242\n'
else
  exec "$ERPNEXT_TEST_REAL_STAT" "$@"
fi
EOF_OWNER_STAT
cat >"$owner_bin/getent" <<'EOF_OWNER_GETENT'
#!/usr/bin/env bash
if [[ "${1:-}" == passwd && "${2:-}" == 4242 ]]; then
  printf 'frappe:x:4242:4242::/home/frappe:/bin/bash\n'
else
  exec "$ERPNEXT_TEST_REAL_GETENT" "$@"
fi
EOF_OWNER_GETENT
cat >"$owner_bin/runuser" <<'EOF_OWNER_RUNUSER'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$ERPNEXT_TEST_OWNER_LOG"
printf '\n' >>"$ERPNEXT_TEST_OWNER_LOG"
[[ "${1:-}" == -u && "${2:-}" == frappe && "${3:-}" == -- ]] || exit 64
shift 3
exec "$@"
EOF_OWNER_RUNUSER
cat >"$owner_bin/git" <<'EOF_OWNER_GIT'
#!/usr/bin/env bash
case " $* " in
  *" symbolic-ref "*) printf 'version-16\n' ;;
  *" rev-parse --quiet --verify MERGE_HEAD "*) exit 1 ;;
  *" rev-parse --quiet --verify CHERRY_PICK_HEAD "*) printf '3333333333333333333333333333333333333333\n' ;;
  *" rev-parse "*) printf '2222222222222222222222222222222222222222\n' ;;
  *" remote get-url origin "*) exit 2 ;;
  *" remote get-url upstream "*) printf 'https://github.com/frappe/erpnext\n' ;;
  *" status "*) printf ' M banking/yarn.lock\n' ;;
  *) exit 1 ;;
esac
EOF_OWNER_GIT
chmod +x "$owner_bin"/*

owner_records="$({
  PATH="$owner_bin:$PATH"
  ERPNEXT_TEST_OWNER_REPO="$owner_repo"
  ERPNEXT_TEST_OWNER_LOG="$owner_probe_log"
  ERPNEXT_TEST_REAL_STAT="$owner_real_stat"
  ERPNEXT_TEST_REAL_GETENT="$owner_real_getent"
  export PATH ERPNEXT_TEST_OWNER_REPO ERPNEXT_TEST_OWNER_LOG ERPNEXT_TEST_REAL_STAT ERPNEXT_TEST_REAL_GETENT
  inventory_current_uid() { printf '0\n'; }
  INVENTORY_RECORDS=()
  inventory_emit_app "native:$fixture" erpnext "$owner_repo" 0
  inventory_records_sorted
  inventory_git_ref_absent "$owner_repo" MERGE_HEAD && printf 'REF_ABSENT\n'
  if ! inventory_git_ref_absent "$owner_repo" CHERRY_PICK_HEAD; then
    printf 'REF_PRESENT_REJECTED\n'
  fi
})"
assert_contains "owner-aware Git probe reports genuine dirty state" "$owner_records" "|version-16|2222222222222222222222222222222222222222|https://github.com/frappe/erpnext|official|managed|dirty"
assert_contains "owner-aware Git probe switches to repository owner" "$(<"$owner_probe_log")" "-u frappe -- env -u"
assert_contains "owner-aware Git probe uses repository owner home" "$(<"$owner_probe_log")" "HOME=/home/frappe"
assert_contains "upstream remote is accepted when origin is absent" "$owner_records" "|https://github.com/frappe/erpnext|"
assert_contains "absent Git operation ref passes preflight" "$owner_records" "REF_ABSENT"
assert_contains "present Git operation ref blocks preflight" "$owner_records" "REF_PRESENT_REJECTED"

slow_bin="$fixture/slow-bin"
slow_repo="$fixture/slow-repo"
slow_pid_file="$fixture/slow-probe.pid"
slow_db_pid_file="$fixture/slow-db.pid"
slow_site="$fixture/slow-site"
mkdir -p "$slow_bin" "$slow_repo/.git"
cat >"$slow_bin/git" <<'EOF_SLOW_GIT'
#!/usr/bin/env bash
case " $* " in
  *" status "*)
    sleep 300 &
    child=$!
    printf '%s\n' "$child" >"$ERPNEXT_TEST_PID_FILE"
    wait "$child"
    ;;
  *" symbolic-ref "*) printf 'version-16\n' ;;
  *" rev-parse "*) printf '1111111111111111111111111111111111111111\n' ;;
  *" remote get-url "*) printf 'https://github.com/frappe/frappe\n' ;;
  *) exit 1 ;;
esac
EOF_SLOW_GIT
chmod +x "$slow_bin/git"
cat >"$slow_bin/mariadb" <<'EOF_SLOW_DB'
#!/usr/bin/env bash
sleep 300 &
child=$!
printf '%s\n' "$child" >"$ERPNEXT_TEST_PID_FILE"
wait "$child"
EOF_SLOW_DB
chmod +x "$slow_bin/mariadb"

INVENTORY_RECORDS=()
started_at="$(date +%s)"
original_path="$PATH"
PATH="$slow_bin:$PATH"
ERPNEXT_TEST_PID_FILE="$slow_pid_file"
ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT=1
export PATH ERPNEXT_TEST_PID_FILE ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT
inventory_emit_app "native:$fixture" frappe "$slow_repo" 0
elapsed=$(($(date +%s) - started_at))
assert_contains "timed-out Git state is ambiguous" "$(inventory_records_sorted)" "|managed|ambiguous"
if ((elapsed <= 4)); then pass "Git inventory probe is bounded"; else fail_case "Git inventory probe exceeded its deadline"; fi
[[ -s "$slow_pid_file" ]] \
  && assert_process_gone "Git timeout leaves no child process" "$(<"$slow_pid_file")" \
  || fail_case "slow Git probe did not record its child PID"

mkdir -p "$slow_site"
printf '{\n  "db_name": "fixture_db",\n  "db_password": "fixture_password"\n}\n' >"$slow_site/site_config.json"
ERPNEXT_TEST_PID_FILE="$slow_db_pid_file"
export ERPNEXT_TEST_PID_FILE
set +e
inventory_native_site_db_apps "$slow_site" >/dev/null 2>&1
slow_db_rc=$?
set -e
assert_eq "timed-out database inventory is ambiguous" 2 "$slow_db_rc"
[[ -s "$slow_db_pid_file" ]] \
  && assert_process_gone "database timeout leaves no child process" "$(<"$slow_db_pid_file")" \
  || fail_case "slow database probe did not record its child PID"

PATH="$original_path"
unset ERPNEXT_TEST_PID_FILE ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT
export PATH

set +e
ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT=invalid
export ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT
inventory_run_probe true >/dev/null 2>&1
invalid_timeout_rc=$?
set -e
unset ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT
assert_eq "invalid probe timeout fails closed" 125 "$invalid_timeout_rc"

make_app() {
  local app="$1" version="$2" branch="$3" source="$4" state="${5:-clean}"
  mkdir -p "$fixture/apps/$app"
  printf 'VERSION=%s\nBRANCH=%s\nCOMMIT=%040d\nSOURCE=%s\nSTATE=%s\n' \
    "$version" "$branch" 1 "$source" "$state" >"$fixture/apps/$app/.inventory-meta"
}
make_site() {
  local site="$1"
  shift
  mkdir -p "$fixture/sites/$site"
  printf '%s\n' "$@" >"$fixture/sites/$site/apps.txt"
}

mkdir -p "$fixture/apps" "$fixture/sites"
make_app frappe 16.2.0 version-16 https://github.com/frappe/frappe
make_app erpnext 16.1.0 version-16 https://github.com/frappe/erpnext
make_app hrms 16.0.0 version-16 https://github.com/frappe/hrms clean
make_app custom_app 1.0.0 main https://example.invalid/custom dirty
make_app unused_app 1.0.0 main https://example.invalid/unused
make_site one.test frappe erpnext hrms custom_app ghost_app

export ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT="$fixture"
fixture_stack="native:${fixture}"
inventory_collect
records="$(inventory_records_sorted)"
assert_contains "native single-site stack" "$records" "STACK|native:"
assert_contains "code availability separate record" "$records" "|hrms|available|"
assert_contains "site installation separate record" "$records" "SITE_APP|native:"
assert_eq "single-site usage" 1 "$(inventory_usage_count "$fixture_stack" hrms)"
assert_contains "known curated classification" "$records" "|hrms|available|16.0.0|version-16|"
assert_contains "unknown custom classification" "$records" "|unknown|unmanaged|"
assert_contains "dirty repository state" "$records" "|unmanaged|dirty"
assert_eq "available code can be unused" 0 "$(inventory_usage_count "$fixture_stack" unused_app)"
assert_contains "site app with missing code" "$records" "|ghost_app|missing|"

make_site two.test frappe erpnext hrms
inventory_collect
assert_eq "native multi-site shared usage" 2 "$(inventory_usage_count "$fixture_stack" hrms)"
sites_out="$(inventory_show_sites)"
assert_contains "native multi-site first" "$sites_out" "one.test"
assert_contains "native multi-site second" "$sites_out" "two.test"

DEPLOYMENT_ENGINE="docker"
DOCKER_MODE="development"
inventory_collect
assert_contains "Docker development adapter" "$(inventory_records_sorted)" "|docker|development|"
DOCKER_MODE="production"
inventory_collect
assert_contains "Docker production adapter" "$(inventory_records_sorted)" "|docker|production|"

# Exercise the live Docker adapter with hermetic command mocks. This validates
# its backend/image-scope and database/site-scope normalization without Docker.
DOCKER_PROJECT_NAME="fixture-project"
DOCKER_ERPNEXT_IMAGE="frappe/erpnext:v16.1.0"
docker_compose_available() { return 0; }
inventory_docker_read() {
  case "$*" in
    "find sites "*) printf 'one.test\n' ;;
    "find apps "*) printf 'erpnext\nfrappe\n' ;;
    *) return 1 ;;
  esac
}
inventory_docker_site_apps() { printf 'frappe\nerpnext\n'; }
INVENTORY_RECORDS=()
DOCKER_MODE="development"
inventory_collect_docker_live
assert_contains "Docker live code-scope probe" "$(inventory_records_sorted)" "APP|docker:fixture-project|frappe|available|v16.1.0"
assert_contains "Docker live site-scope probe" "$(inventory_records_sorted)" "SITE_APP|docker:fixture-project|one.test|erpnext|installed"
INVENTORY_RECORDS=()
DOCKER_MODE="production"
inventory_collect_docker_live
assert_contains "Docker live production identity" "$(inventory_records_sorted)" "STACK|docker:fixture-project|docker|production|"

DEPLOYMENT_ENGINE="native"
DOCKER_MODE="development"
INSTALLATION_PROFILE="recommended"
inventory_collect
inventory_compatibility_evaluate hrms || fail_case "known compatible app rejected"
assert_eq "known curated compatible" COMPATIBLE "$INVENTORY_COMPAT_STATUS"

make_app webshop 16.0.0 develop https://github.com/frappe/webshop
inventory_collect
inventory_compatibility_evaluate erpnext || fail_case "ERPNext compatibility rejected"
assert_contains "dependents evaluated" "$INVENTORY_COMPAT_DEPENDENTS" "webshop"

printf 'VERSION=16.0.0\nBRANCH=version-16\nCOMMIT=%040d\nSOURCE=https://example.invalid/hrms\nSTATE=clean\n' \
  1 >"$fixture/apps/hrms/.inventory-meta"
inventory_collect
set +e
inventory_compatibility_evaluate hrms
rc=$?
set -e
assert_eq "untrusted source mismatch unknown" 2 "$rc"
printf 'VERSION=16.0.0\nBRANCH=version-16\nCOMMIT=%040d\nSOURCE=https://github.com/frappe/hrms\nSTATE=clean\n' \
  1 >"$fixture/apps/hrms/.inventory-meta"

set +e
inventory_compatibility_evaluate custom_app
rc=$?
set -e
assert_eq "unknown app fails safely" 2 "$rc"
assert_eq "unknown app status" UNKNOWN "$INVENTORY_COMPAT_STATUS"

inventory_collect
set +e
inventory_compatibility_evaluate helpdesk
rc=$?
set -e
assert_eq "missing dependency incompatible" 1 "$rc"
assert_contains "missing dependency detail" "$INVENTORY_COMPAT_DETAIL" "telephony"
if inventory_dependency_rules_evaluate "" "erpnext"; then
  fail_case "available conflicting application accepted"
else
  assert_contains "conflict rule evaluated" "$INVENTORY_COMPAT_DETAIL" "erpnext"
fi

printf 'VERSION=17.0.0\nBRANCH=version-17\nCOMMIT=%040d\nSOURCE=https://github.com/frappe/frappe\nSTATE=clean\n' \
  1 >"$fixture/apps/frappe/.inventory-meta"
inventory_collect
set +e
inventory_compatibility_evaluate hrms
rc=$?
set -e
assert_eq "incompatible platform version" 1 "$rc"
printf 'VERSION=16.2.0\nBRANCH=version-16\nCOMMIT=%040d\nSOURCE=https://github.com/frappe/frappe\nSTATE=clean\n' \
  1 >"$fixture/apps/frappe/.inventory-meta"

DEPLOYMENT_ENGINE="docker"
DOCKER_MODE="production"
inventory_collect
inventory_deployment_supported docker production supported supported custom-image \
  || fail_case "supported Docker production strategy rejected"
if inventory_deployment_supported docker production supported supported unsupported; then
  fail_case "unsupported deployment method accepted"
else
  pass "unsupported deployment method"
fi

DEPLOYMENT_ENGINE="native"
INSTALLATION_PROFILE="frappe-only"
inventory_collect
set +e
inventory_compatibility_evaluate webshop
rc=$?
set -e
assert_eq "Frappe-only ERPNext dependency blocked" 1 "$rc"
INSTALLATION_PROFILE="recommended"

mkdir -p "$fixture/sites/bad!site" "$fixture/apps/bad!app"
inventory_collect
assert_contains "malformed site rejected" "$(inventory_records_sorted)" "|site|invalid-name|malformed"
assert_contains "malformed app rejected" "$(inventory_records_sorted)" "|app|invalid-name|malformed"

rm -rf "$fixture/sites/bad!site" "$fixture/apps/bad!app"
rm -f "$fixture/sites/two.test/apps.txt"
inventory_collect
assert_contains "ambiguous site explicit" "$(inventory_records_sorted)" "|two.test|ambiguous"
if inventory_has_ambiguous_state; then
  pass "ambiguous inventory state is detected"
else
  fail_case "ambiguous inventory state was accepted"
fi
set +e
inventory_compatibility_evaluate hrms
rc=$?
set -e
assert_eq "ambiguous multi-site impact fails safely" 2 "$rc"
make_site two.test frappe erpnext hrms

ERPNEXT_DEV_INVENTORY_FIXTURE_MANAGEMENT="supported-unadopted"
inventory_collect
assert_contains "existing stack not silently adopted" "$(inventory_records_sorted)" "|supported-unadopted|"
unset ERPNEXT_DEV_INVENTORY_FIXTURE_MANAGEMENT

for id in $(app_catalog_ids); do
  load_validated_app_catalog_record "$id" || fail_case "catalog record invalid: $id"
done
pass "all catalog records validate"

before="$(find "$fixture/apps" "$fixture/sites" -type f -print0 | sort -z | xargs -0 sha256sum)"
first="$(inventory_show_apps)"
second="$(inventory_show_apps)"
assert_eq "deterministic automation output" "$first" "$second"

DOCTOR_FORMAT=json
json="$(inventory_show_apps)"
assert_contains "machine schema version" "$json" '"schema_version":1'
assert_contains "machine read-only contract" "$json" '"read_only":true'
DOCTOR_FORMAT=human

run_cli() {
  LOG_DIR="$fixture/runtime-log" LOCK_DIR="$fixture/runtime-lock" CONFIG_FILE="$fixture/config" \
    LEGACY_CONFIG_FILE="$fixture/legacy" ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT="$fixture" \
    DEPLOYMENT_ENGINE=native INSTALLATION_PROFILE=recommended \
    bash "$ROOT_DIR/erpnext-dev.sh" "$@"
}
cli_apps="$(run_cli app list)" || fail_case "app list CLI failed"
cli_sites="$(run_cli site list)" || fail_case "site list CLI failed"
cli_status="$(run_cli app status)" || fail_case "app status CLI failed"
cli_compat="$(run_cli app compatibility hrms)" || fail_case "app compatibility CLI failed"
set +e
invalid_cli="$(run_cli app compatibility 'bad;app' 2>&1)"
invalid_rc=$?
extra_cli="$(run_cli site list unexpected 2>&1)"
extra_rc=$?
set -e
assert_eq "malformed CLI input rejected" 1 "$invalid_rc"
assert_contains "malformed CLI diagnostic" "$invalid_cli" "Invalid application identifier"
assert_eq "extra CLI input rejected" 1 "$extra_rc"
assert_contains "extra CLI diagnostic" "$extra_cli" "Usage:"
assert_contains "app list CLI contract" "$cli_apps" "APPLICATION"
assert_contains "site list CLI contract" "$cli_sites" "SITE"
assert_contains "app status CLI contract" "$cli_status" "STACK"
assert_contains "app compatibility CLI contract" "$cli_compat" "COMPATIBLE"
run_cli version >/dev/null 2>&1 || fail_case "existing version command regressed"
pass "existing command regression"

after="$(find "$fixture/apps" "$fixture/sites" -type f -print0 | sort -z | xargs -0 sha256sum)"
assert_eq "inventory commands do not mutate managed stack" "$before" "$after"
if grep -Eq 'bench[[:space:]]+(get-app|install-app|list-apps|migrate|update)|docker_compose[[:space:]]+(up|down|restart|build)' \
  "$ROOT_DIR/lib/inventory.sh"; then
  fail_case "inventory adapter contains mutating or app-executing commands"
else
  pass "inventory adapters invoke no Bench app code or mutation verbs"
fi
if grep -E -- '^[[:space:]]+-e "' "$ROOT_DIR/lib/inventory.sh" | grep -Evi 'SELECT ' >/dev/null; then
  fail_case "inventory database adapter contains a non-SELECT statement"
else
  pass "inventory database probes are SELECT-only"
fi

if ((failures > 0)); then
  echo "inventory-compatibility tests: ${failures} failure(s)" >&2
  exit 1
fi
echo "inventory-compatibility tests: all checks passed"
