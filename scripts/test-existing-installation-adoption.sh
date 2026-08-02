#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
assert() {
  local label="$1"
  shift
  if "$@"; then printf 'OK: %s\n' "$label"; else
    printf 'FAIL: %s\n' "$label"
    failures=$((failures + 1))
  fi
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  assert "$label" test "$expected" = "$actual"
}
assert_has() {
  local label="$1" file="$2" text="$3"
  assert "$label" grep -Fq -- "$text" "$file"
}

SUDO=""
CONFIG_FILE="$tmp/config"
LEGACY_CONFIG_FILE="$tmp/legacy"
OPERATION_STATE_DIR="$tmp/operations"
ADOPTION_RECOVERY_DIR="$tmp/recovery"
LOCK_FILE="$tmp/locks/toolkit.lock"
BENCH_PARENT="$tmp"
BENCH_NAME=default-bench
BENCH_DIR="$BENCH_PARENT/$BENCH_NAME"
FRAPPE_USER="$(id -un)"
DEPLOYMENT_ENGINE=native
DOCKER_MODE=development
INSTALLATION_PROFILE=existing
INSTALLATION_PROFILE_APPS=""
SITE_NAME=site.test
SITE_NAME_ENV_PROVIDED=1
SITE_NAME_SOURCE="test"
HOST_OS_ENV_PROVIDED=1
HOST_OS=linux
DOCKER_SITE_NAME=site.test
DOCKER_PROJECT_NAME=erpnext-dev
DOCKER_WORKDIR="$tmp/docker"
DOCTOR_FORMAT=human
ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT=2
ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES=1

# shellcheck source=../lib/common.sh
set +u
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/profile.sh
source "$ROOT_DIR/lib/profile.sh"
# shellcheck source=../lib/config.sh
source "$ROOT_DIR/lib/config.sh"
# shellcheck source=../lib/apps.sh
source "$ROOT_DIR/lib/apps.sh"
# shellcheck source=../lib/inventory.sh
source "$ROOT_DIR/lib/inventory.sh"
# shellcheck source=../lib/planner.sh
source "$ROOT_DIR/lib/planner.sh"
# shellcheck source=../lib/adoption.sh
source "$ROOT_DIR/lib/adoption.sh"
set -u
GREEN=""
RESET=""

make_native() {
  local bench="$1" site="$2" version="${3:-16.0.0}" remote="${4:-https://github.com/frappe/frappe.git}"
  mkdir -p "$bench/apps/frappe/frappe" "$bench/apps/custom_app" "$bench/sites/$site"
  printf '__version__ = "%s"\n' "$version" >"$bench/apps/frappe/frappe/__init__.py"
  printf 'frappe\ncustom_app\n' >"$bench/sites/$site/apps.txt"
  git -C "$bench/apps/frappe" init -q
  git -C "$bench/apps/frappe" config user.email test@example.invalid
  git -C "$bench/apps/frappe" config user.name Test
  git -C "$bench/apps/frappe" add .
  git -C "$bench/apps/frappe" commit -qm initial
  git -C "$bench/apps/frappe" remote add origin "$remote"
  chmod -R go-w "$bench"
}

ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$tmp/absent"
adoption_discover
assert_eq "zero candidates" 0 "${#ADOPTION_CANDIDATES[@]}"

native="$tmp/native-bench"
make_native "$native" site.test
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native"
adoption_discover
assert_eq "one Native candidate" 1 "${#ADOPTION_CANDIDATES[@]}"
record="${ADOPTION_CANDIDATES[0]}"
IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$record"
selector="$engine:$id:$site"
assert_eq "Native engine" native "$engine"
assert_eq "Native environment" development "$mode"
assert_eq "exact site" site.test "$site"
assert_eq "supported major" 16 "$major"
assert_eq "compatible candidate" compatible "$compatibility"
assert "unknown app preserved" grep -Eq '(^|,)custom_app(,|$)' <<<"$apps"
assert "Frappe preserved" grep -Eq '(^|,)frappe(,|$)' <<<"$apps"
assert "sanitized identity" grep -Eq '^n-[a-f0-9]{20}$' <<<"$id"
assert "secret-free fingerprint" grep -Eq '^[a-f0-9]{64}$' <<<"$fingerprint"
assert "exact selector accepted" adoption_select_exact "$selector"
if adoption_select_exact '' 2>/dev/null; then
  failures=$((failures + 1))
  printf 'FAIL: implicit selector rejected\n'
else printf 'OK: implicit selector rejected\n'; fi
if adoption_select_exact 'native:n-00000000000000000000:site.test' 2>/dev/null; then
  failures=$((failures + 1))
  printf 'FAIL: stale selector rejected\n'
else printf 'OK: stale selector rejected\n'; fi
if adoption_select_exact $'native:n-00000000000000000000:bad\nsite' 2>/dev/null; then
  failures=$((failures + 1))
  printf 'FAIL: hostile selector rejected\n'
else printf 'OK: hostile selector rejected\n'; fi

DOCTOR_FORMAT=json
adoption_render_preview >"$tmp/preview.json"
assert_has "JSON preview schema" "$tmp/preview.json" '"schema_version":2'
assert_has "JSON preview read-only" "$tmp/preview.json" '"read_only":true'
assert_has "JSON preview non-mutation" "$tmp/preview.json" '"mutation":false'
assert_has "preview shows applications" "$tmp/preview.json" custom_app
assert_has "preview shows fingerprint" "$tmp/preview.json" "$fingerprint"
assert "preview writes no config" test ! -e "$CONFIG_FILE"
assert "preview creates no journal" test ! -e "$OPERATION_STATE_DIR"
assert "preview acquires no lock" test ! -e "$LOCK_FILE"

second="$tmp/second-bench"
make_native "$second" other.test
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native:$second"
adoption_discover
assert_eq "multiple benches remain multiple" 2 "${#ADOPTION_CANDIDATES[@]}"
first_order="$(printf '%s\n' "${ADOPTION_CANDIDATES[@]}")"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$second:$native"
adoption_discover
assert_eq "deterministic candidate ordering" "$first_order" "$(printf '%s\n' "${ADOPTION_CANDIDATES[@]}")"

ln -s "$native" "$tmp/symlink-bench"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$tmp/symlink-bench"
adoption_discover
assert_eq "symlinked Bench rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
chmod 777 "$second"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$second"
adoption_discover
assert_eq "unsafe permissions rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
chmod 755 "$second"

old="$tmp/old-bench"
make_native "$old" old.test 13.0.0
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$old"
adoption_discover
assert_eq "unsupported major rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
wrong="$tmp/wrong-bench"
make_native "$wrong" wrong.test 16.0.0 https://example.invalid/frappe.git
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$wrong"
adoption_discover
assert_eq "incorrect core remote rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
printf '# dirty\n' >>"$native/apps/frappe/frappe/__init__.py"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native"
adoption_discover
assert_eq "dirty core rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
git -C "$native/apps/frappe" checkout -q -- frappe/__init__.py
mv "$native/sites/site.test/apps.txt" "$native/sites/site.test/apps.missing"
adoption_discover
assert_eq "incomplete site inventory rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
mv "$native/sites/site.test/apps.missing" "$native/sites/site.test/apps.txt"

docker_dev="$tmp/docker-dev"
mkdir -p "$docker_dev"
touch "$docker_dev/compose.yaml"
printf 'ENGINE=docker\nMODE=development\nPROJECT=dev-project\nSITE=dev.test\nFRAPPE_MAJOR=16\nIMAGE_DIGEST=sha256:%064d\nAPPS=frappe,custom_app\nRECONSTRUCTIBLE=false\n' 0 >"$docker_dev/.toolkit-adoption-fixture"
chmod -R go-w "$docker_dev"
ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES=1
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$docker_dev"
adoption_discover
assert_eq "one Docker development candidate" 1 "${#ADOPTION_CANDIDATES[@]}"
docker_prod="$tmp/docker-prod"
mkdir -p "$docker_prod"
touch "$docker_prod/compose.yaml"
printf 'ENGINE=docker\nMODE=production\nPROJECT=prod-project\nSITE=prod.test\nFRAPPE_MAJOR=16\nIMAGE_DIGEST=sha256:%064d\nAPPS=frappe,erpnext\nRECONSTRUCTIBLE=true\n' 1 >"$docker_prod/.toolkit-adoption-fixture"
chmod -R go-w "$docker_prod"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$docker_prod"
adoption_discover
assert_eq "one Docker production candidate" 1 "${#ADOPTION_CANDIDATES[@]}"
sed -i 's/RECONSTRUCTIBLE=true/RECONSTRUCTIBLE=false/' "$docker_prod/.toolkit-adoption-fixture"
adoption_discover
assert_eq "production reconstructibility required" 0 "${#ADOPTION_CANDIDATES[@]}"
unset ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES
adoption_discover
assert_eq "test descriptor disabled in production" 0 "${#ADOPTION_CANDIDATES[@]}"

printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=recommended\nKEEP_SETTING=value\nPASSWORD=must-not-copy\n' >"$CONFIG_FILE"
stage="$tmp/stage"
adoption_stage_config "$CONFIG_FILE" "$stage" native development n-00000000000000000000 site.test "$(printf x | sha256sum | awk '{print $1}')" "$native" ""
assert_has "schema-2 written" "$stage" CONFIG_SCHEMA=2
assert_has "existing intent written" "$stage" INSTALLATION_PROFILE=existing
assert_has "existing app intent empty" "$stage" INSTALLATION_PROFILE_APPS=
assert_has "unrelated setting preserved" "$stage" KEEP_SETTING=value
assert "secret setting absent" test "$(grep -c PASSWORD "$stage")" -eq 0
assert_has "exact Bench persisted" "$stage" "BENCH_DIR=$native"
assert_has "adoption target persisted" "$stage" ADOPTION_TARGET_ID=n-00000000000000000000
assert "candidate configuration is data" bash -c "sed -n '/^adoption_stage_config()/,/^}/p' '$ROOT_DIR/lib/adoption.sh' | grep -Eq '(^|[[:space:]])(source|\.)[[:space:]]' && exit 1 || exit 0"

cp "$stage" "$CONFIG_FILE"
read_installation_profile_metadata "$CONFIG_FILE"
assert_eq "adoption metadata valid" true "$PROFILE_METADATA_ADOPTION_VALID"
assert_eq "adoption metadata site" site.test "$PROFILE_METADATA_ADOPTION_SITE"
printf 'CONFIG_SCHEMA=99\nINSTALLATION_PROFILE=existing\n' >"$CONFIG_FILE"
if read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1; then
  failures=$((failures + 1))
  printf 'FAIL: unknown schema fails closed\n'
else printf 'OK: unknown schema fails closed\n'; fi

# Exercise the real journal/config-only transaction with every protected path
# redirected into the hermetic fixture.
require_sudo() { :; }
lock_count=0
acquire_toolkit_lock() {
  lock_count=$((lock_count + 1))
  mkdir -p "$(dirname "$LOCK_FILE")"
  : >"$LOCK_FILE"
}
printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=recommended\nKEEP_SETTING=value\n' >"$CONFIG_FILE"
cp "$CONFIG_FILE" "$LEGACY_CONFIG_FILE"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native"
ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES=1
adoption_discover
native_selector="native:n-$(printf '%s' "$native" | sha256sum | cut -c1-20):site.test"
adoption_select_exact "$native_selector"
deployment_before="$(sha256sum "$native/sites/site.test/apps.txt" "$native/apps/frappe/frappe/__init__.py")"
adoption_transaction
assert_eq "lock acquired for confirmed transaction" 1 "$lock_count"
assert_has "transaction adopted existing profile" "$CONFIG_FILE" INSTALLATION_PROFILE=existing
assert "primary and legacy mirrors match" cmp -s "$CONFIG_FILE" "$LEGACY_CONFIG_FILE"
assert "prior primary retained" test -n "$(find "$ADOPTION_RECOVERY_DIR" -name 'prior-*.conf' -type f -print -quit)"
assert "prior legacy retained" test -n "$(find "$ADOPTION_RECOVERY_DIR" -name '*.legacy' -type f -print -quit)"
assert "prior artifacts private" bash -c "find '$ADOPTION_RECOVERY_DIR' -type f ! -perm 600 | grep -q . && exit 1 || exit 0"
assert "adoption journal complete" grep -Rq '^status=complete$' "$OPERATION_STATE_DIR"
assert "journal operation type" grep -Rq '^operation_type=existing-adoption$' "$OPERATION_STATE_DIR"
assert "journal records config fingerprints" grep -Rq '^candidate_config_fingerprint=[a-f0-9]\{64\}$' "$OPERATION_STATE_DIR"
assert_eq "deployment inventory unchanged" "$deployment_before" "$(sha256sum "$native/sites/site.test/apps.txt" "$native/apps/frappe/frappe/__init__.py")"
config_after="$(sha256sum "$CONFIG_FILE")"
adoption_select_exact "$native_selector"
adoption_transaction
assert_eq "idempotent re-adoption does not rewrite" "$config_after" "$(sha256sum "$CONFIG_FILE")"

assert "no Bench mutation command" bash -c "! grep -Eq 'bench[[:space:]].*(install|migrate|new-site|uninstall|update)' '$ROOT_DIR/lib/adoption.sh'"
assert "no Docker mutation command" bash -c "! grep -Eq 'docker[[:space:]]+(pull|build|restart|stop|rm)|docker[[:space:]]+compose.*[[:space:]](up|down|restart|stop|rm)' '$ROOT_DIR/lib/adoption.sh'"
assert "no service mutation command" bash -c "! grep -Eq 'systemctl[[:space:]]+(start|stop|restart|enable|reload)' '$ROOT_DIR/lib/adoption.sh'"
assert "no package mutation command" bash -c "! grep -Eq '(apt|dnf|yum|pip|npm)[[:space:]].*(install|remove)' '$ROOT_DIR/lib/adoption.sh'"
assert "no candidate shell sourcing" bash -c "! grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*\$' '$ROOT_DIR/lib/adoption.sh'"
assert "no deployment backup invocation" bash -c "! grep -Eq '(backup_site|docker_backup|run_backup)' '$ROOT_DIR/lib/adoption.sh'"

printf 'existing-installation adoption tests: %s assertions, %s failure(s)\n' 66 "$failures"
((failures == 0))
