#!/usr/bin/env bash
# Hermetic stdin-driven coverage for fresh-install mode/profile integration.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() { echo "OK: $*"; }
assert_contains() { grep -Fq "$2" "$1" || fail "$3"; }
assert_eq() {
  [[ "$2" == "$3" ]] || fail "$1: expected '$2', got '$3'"
  pass "$1"
}

tmp="$(mktemp -d /tmp/erpnext-dev-interactive-profile.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
ASSUME_YES=0 ERPNEXT_DEV_TEST_INTERACTIVE=1
SITE_NAME=erp.test SITE_NAME_SOURCE=default SITE_NAME_ENV_PROVIDED=0
HOST_OS="" HOST_OS_ENV_PROVIDED=0
DEPLOYMENT_ENGINE="" DEPLOYMENT_ENGINE_ENV_PROVIDED=0 DEPLOYMENT_ENGINE_SESSION_CHOSEN=0
INSTALLATION_PROFILE="" INSTALLATION_PROFILE_ENV_PROVIDED=0 INSTALLATION_PROFILE_SESSION_CHOSEN=0 INSTALLATION_MODE=""
DEPLOYMENT_MODE=development PRODUCTION_DOMAIN="" PRODUCTION_SSL_MODE=planned RUNTIME_MODE=""
DOCKER_MODE=development DOCKER_MODE_ENV_PROVIDED=0 DOCKER_PUBLISH_PORT=8080 DOCKER_SITE_NAME="" DOCKER_WORKDIR="$tmp/no-docker"
FRAPPE_USER=frappe FRAPPE_HOME="$tmp/frappe" BENCH_PARENT="$tmp/no-bench" BENCH_NAME=frappe-bench BENCH_DIR="$BENCH_PARENT/$BENCH_NAME"
CONFIG_FILE="$tmp/config" LEGACY_CONFIG_FILE="$tmp/legacy" SUDO="" LOG_FILE="$tmp/log"

source lib/profile.sh
source lib/config.sh
source lib/engine.sh
source lib/install.sh

require_sudo() { :; }
warn() { printf 'WARN: %s\n' "$*"; }
ok() { printf 'OK: %s\n' "$*"; }
confirm() {
  local reply
  read -r reply || return 1
  [[ "${reply:-N}" =~ ^[Yy]$ ]]
}
install_self_for_reuse() { printf 'install-self\n' >>"$tmp/mutations"; }
ui_box_start() { printf '\n%s\n' "$1"; }
ui_box_end() { :; }
ui_next() { :; }
status_line() { printf '%s: %s\n' "$1" "$3"; }
toolkit_cmd() { printf 'erpnext-dev %s' "$*"; }
host_os_label() { printf '%s\n' "${1:-${HOST_OS:-linux}}"; }
active_bench_dir() { printf '%s\n' "$BENCH_DIR"; }
local_guided_stable_ip_checkpoint() { printf 'stable-ip\n' >>"$tmp/mutations"; }
run_guided_setup() { printf 'native:%s\n' "$(effective_installation_profile)" >>"$tmp/installer"; }
docker_guided_install() { printf 'docker:%s:%s\n' "${DOCKER_MODE}" "$(effective_installation_profile)" >>"$tmp/installer"; }
docker_mode_label() {
  case "$DOCKER_MODE" in
    production) printf 'Production\n' ;;
    *) printf 'Development\n' ;;
  esac
}
write_dev_config_file() {
  local out="${CONFIG_FILE}.tmp.$$"
  printf 'SITE_NAME=%s\nDEPLOYMENT_MODE=%s\nDEPLOYMENT_ENGINE=%s\nINSTALLATION_PROFILE=%s\nDOCKER_MODE=%s\n' \
    "$SITE_NAME" "$DEPLOYMENT_MODE" "$(effective_deployment_engine)" "$(effective_installation_profile)" "$DOCKER_MODE" >"$out"
  mv "$out" "$CONFIG_FILE"
}
reset_case() {
  rm -f "$CONFIG_FILE" "$LEGACY_CONFIG_FILE" "$tmp/installer" "$tmp/mutations"
  SITE_NAME=erp.test SITE_NAME_SOURCE=default SITE_NAME_ENV_PROVIDED=0 HOST_OS="" HOST_OS_ENV_PROVIDED=0
  DEPLOYMENT_ENGINE="" DEPLOYMENT_ENGINE_ENV_PROVIDED=0 DEPLOYMENT_ENGINE_SESSION_CHOSEN=0
  INSTALLATION_PROFILE="" INSTALLATION_PROFILE_ENV_PROVIDED=0 INSTALLATION_PROFILE_SESSION_CHOSEN=0
  INSTALLATION_MODE="" DEPLOYMENT_MODE=development PRODUCTION_DOMAIN="" DOCKER_MODE=development
}

reset_case
printf 'quick.test\n1\n1\ny\n' | run_local_dev_quickstart >"$tmp/local-quick.out"
assert_contains "$tmp/local-quick.out" "Choose Installation Mode" "local Quick mode prompt missing"
assert_contains "$tmp/local-quick.out" "Installation profile: Recommended (Frappe + ERPNext)" "local Quick confirmation profile missing"
assert_contains "$tmp/local-quick.out" "ERPNext: Will be installed" "local Quick ERPNext decision missing"
assert_contains "$CONFIG_FILE" "INSTALLATION_PROFILE=recommended" "local Quick did not save recommended"
assert_contains "$tmp/installer" "native:recommended" "local Quick installer did not receive recommended"
pass "fresh Local VM Quick Native profile reaches installer"

reset_case
printf 'frappe.test\n1\n2\n2\n1\ny\n' | run_local_dev_quickstart >"$tmp/local-native-frappe.out"
assert_contains "$tmp/local-native-frappe.out" "Choose Installation Profile" "Advanced profile prompt missing"
assert_contains "$tmp/local-native-frappe.out" "ERPNext: Will not be installed" "Frappe-only confirmation inaccurate"
assert_contains "$CONFIG_FILE" "INSTALLATION_PROFILE=frappe-only" "Frappe-only profile not saved"
assert_contains "$tmp/installer" "native:frappe-only" "native installer did not receive Frappe-only"
pass "fresh Local VM Advanced Native Frappe-only"

for profile_choice in 1 2; do
  reset_case
  printf 'docker.test\n1\n2\n%s\n2\ny\n' "$profile_choice" | run_local_dev_quickstart >"$tmp/local-docker-${profile_choice}.out"
  expected=recommended
  [[ "$profile_choice" == 2 ]] && expected=frappe-only
  assert_contains "$tmp/installer" "docker:development:${expected}" "Docker development installer profile mismatch"
  assert_contains "$CONFIG_FILE" "INSTALLATION_PROFILE=${expected}" "Docker development saved profile mismatch"
done
pass "fresh Local VM Advanced Docker profile matrix"

public_vm_guided_step() { printf '\nStep %s: %s\n' "$1" "$2"; }
get_vm_ip() { printf '192.0.2.10\n'; }
show_production_domain_plan() { :; }
show_public_vm_readiness() { :; }
public_vm_guided_require_dns_ready() { :; }
public_vm_guided_external_gate() { :; }
public_vm_guided_install_core() { printf '%s:%s\n' "$(effective_deployment_engine)" "$(effective_installation_profile)" >>"$tmp/installer"; }
public_vm_guided_production_runtime() { :; }
public_vm_guided_backup_checkpoint() { :; }
public_vm_guided_configure_https() { :; }
public_vm_guided_credentials_checkpoint() { :; }
public_vm_guided_security_profile() { :; }
public_vm_guided_backups_and_operations() { :; }
public_vm_guided_optional_apps() { :; }
public_vm_guided_final_qa() { :; }
prompt_open_main_menu_after_install() { :; }

reset_case
printf 'y\nerp.example.com\n\n1\ny\n' | run_public_vm_guided_setup >"$tmp/public-quick.out"
assert_contains "$tmp/public-quick.out" "Installation mode: Quick" "public Quick mode missing"
assert_contains "$tmp/public-quick.out" "ERPNext: Will be installed" "public Quick ERPNext decision missing"
assert_contains "$CONFIG_FILE" "SITE_NAME=erp.example.com" "public domain was not preserved"
assert_contains "$tmp/installer" "native:recommended" "public Quick installer profile mismatch"
pass "Public VM Quick confirms recommended"

reset_case
printf 'y\nfrappe.example.com\n\n2\n2\n2\ny\n' | run_public_vm_guided_setup >"$tmp/public-advanced.out"
assert_contains "$tmp/public-advanced.out" "Installation profile: Frappe only" "public Advanced profile missing"
assert_contains "$tmp/public-advanced.out" "ERPNext: Will not be installed" "public Frappe-only decision missing"
assert_contains "$tmp/public-advanced.out" "Docker environment: Production" "public Docker environment missing"
assert_contains "$tmp/installer" "docker:frappe-only" "public Docker installer profile mismatch"
pass "Public VM Advanced Frappe-only preserves production path"

reset_case
printf 'KEEP=unchanged\nINSTALLATION_PROFILE=frappe-only\n' >"$CONFIG_FILE"
cp "$CONFIG_FILE" "$tmp/config.before"
printf 'cancel.test\n1\n2\n1\n1\nq\n' | run_local_dev_quickstart >"$tmp/cancel.out"
cmp -s "$CONFIG_FILE" "$tmp/config.before" || fail "cancellation replaced existing config"
[[ ! -e "$tmp/installer" && ! -e "$tmp/mutations" ]] || fail "cancellation performed installation mutation"
assert_contains "$tmp/cancel.out" "cancelled before configuration or deployment changes" "cancellation output not truthful"
pass "Back/Quit boundary is non-mutating"

for explicit_profile in recommended frappe-only; do
  reset_case
  INSTALLATION_PROFILE="$explicit_profile" INSTALLATION_PROFILE_ENV_PROVIDED=1
  printf 'explicit.test\n1\n1\ny\n' | run_local_dev_quickstart >"$tmp/explicit.out"
  grep -Fq "Choose Installation Profile" "$tmp/explicit.out" && fail "explicit profile caused unnecessary profile prompt"
  assert_contains "$tmp/installer" "native:${explicit_profile}" "explicit CLI profile precedence lost"
done
pass "explicit recommended and Frappe-only precedence"

reset_case
mkdir -p "$BENCH_DIR/sites/existing.test"
INSTALLATION_PROFILE=frappe-only
printf '' | run_local_dev_quickstart >"$tmp/existing.out"
assert_contains "$tmp/existing.out" "Existing Installation Detected" "existing deployment not detected"
grep -Fq "Choose Installation Mode" "$tmp/existing.out" && fail "existing deployment entered fresh profile workflow"
[[ ! -e "$CONFIG_FILE" ]] || fail "existing maintenance path rewrote config"
rm -rf "$BENCH_DIR"
pass "existing deployment profile is not rewritten"

reset_case
printf 'SITE_NAME=legacy.test\nDEPLOYMENT_ENGINE=native\n' >"$LEGACY_CONFIG_FILE"
legacy_before="$(sha256sum "$LEGACY_CONFIG_FILE" | awk '{print $1}')"
load_future_domain_config_if_available
assert_eq "legacy profile compatibility" recommended "$(effective_installation_profile)"
legacy_after="$(sha256sum "$LEGACY_CONFIG_FILE" | awk '{print $1}')"
assert_eq "legacy config remains read-only" "$legacy_before" "$legacy_after"

# Exercise the actual first-run dispatcher choice and corrected quickstart.
pause_after_screen() { :; }
menu_read_choice() { read -r "$1"; }
ui_submenu_header() { :; }
ui_submenu_footer() { :; }
print_two_column_menu() { :; }
show_menu() { :; }
show_config_summary() { :; }
show_setup_lifecycle_plan() { :; }
show_setup_effort_guide() { :; }
show_ssl_mode_guide() { :; }
reset_case
printf '1\nfirst.test\n1\n1\nn\nb\n' | run_first_run_wizard >"$tmp/first-run.out"
assert_contains "$tmp/first-run.out" "Choose Installation Mode" "first-run did not reach corrected local wizard"
pass "first-run dispatches corrected local wizard"

for bad in bogus '../frappe' 'frappe;id' $'frappe\001only'; do
  reset_case
  INSTALLATION_PROFILE="$bad" INSTALLATION_PROFILE_ENV_PROVIDED=1
  if (choose_installation_mode_for_setup </dev/null >"$tmp/bad.out" 2>&1); then
    fail "unsafe profile accepted"
  fi
  [[ ! -e "$CONFIG_FILE" ]] || fail "invalid profile wrote config"
done
pass "unsafe profile input rejected before mutation"

INSTALLATION_PROFILE=frappe-only
assert_eq "Frappe-only planned apps" frappe "$(installation_profile_required_apps)"
INSTALLATION_PROFILE=recommended
assert_eq "Recommended planned apps" $'frappe\nerpnext' "$(installation_profile_required_apps)"
echo "interactive installation-profile tests: all checks passed"
