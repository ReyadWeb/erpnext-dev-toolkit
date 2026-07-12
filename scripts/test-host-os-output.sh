#!/usr/bin/env bash
# Unit-style tests for the host-OS-aware host command emitters (v1.9.2).
#
# Verifies that print_host_dns_commands_for_site / print_host_dns_tests_for_site
# and the mkcert install hint emit the correct per-host-OS instructions:
#   - Linux   -> /etc/hosts, GNU sed (no ''), getent, apt
#   - macOS   -> /etc/hosts, BSD sed (-i ''), dscacheutil, brew
#   - Windows -> drivers\etc\hosts, PowerShell, Resolve-DnsName, choco
#   - WSL2    -> maps to 127.0.0.1 (localhost forwarding)
#
# Hermetic: no sudo, no network. VM IP is pinned via the VM_IP env var so the
# emitters do not depend on the runner's interfaces.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
note_fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}
pass() { echo "OK: $*"; }

# Load just the function definitions (no main dispatch). The entry script
# normally defines these guard flags before sourcing libs; set them here so the
# sourced helpers are safe under `set -u`.
export ERPNEXT_DEV_ENTRY_SCRIPT="${ROOT_DIR}/erpnext-dev.sh"
export SITE_NAME="erp.test"
export VM_IP="192.168.122.50"
# config.sh runs load_saved_config_if_available / load_future_domain_config_if_available
# at source time; provide the defaults the entry script normally sets first.
SITE_NAME_ENV_PROVIDED=1
HOST_OS_ENV_PROVIDED=0
SITE_NAME_SOURCE="test"
ASSUME_YES=1
DEPLOYMENT_MODE="development"
PRODUCTION_DOMAIN=""
PRODUCTION_SSL_MODE="planned"
RUNTIME_MODE=""
HOST_OS=""
CONFIG_FILE="/nonexistent/erpnext-dev-test-config.env"
LEGACY_CONFIG_FILE="/nonexistent/erpnext-dev-test-legacy.env"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"
erpnext_dev_init_terminal_colors 2>/dev/null || true
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/config.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/access.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/ssl.sh"

# port_listens lives in lib/service.sh (not needed for output shape); stub it so
# the emitters run without pulling the service module. 443 "not listening" keeps
# the HTTPS test line out, which does not affect the assertions below.
port_listens() { return 1; }

# assert_contains <label> <haystack> <needle>
assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "${label}: contains '${needle}'"
  else
    note_fail "${label}: expected to contain '${needle}'"
    printf '%s\n' "$haystack" | sed 's/^/    /' >&2
  fi
}

# assert_absent <label> <haystack> <needle>
assert_absent() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    note_fail "${label}: expected NOT to contain '${needle}'"
    printf '%s\n' "$haystack" | sed 's/^/    /' >&2
  else
    pass "${label}: absent '${needle}'"
  fi
}

run_case() {
  local host_os="$1"
  export HOST_OS="$host_os"
  local dns tests hint label
  dns="$(print_host_dns_commands_for_site "$SITE_NAME" "$VM_IP")"
  tests="$(print_host_dns_tests_for_site "$SITE_NAME" "$VM_IP")"
  hint="$(host_mkcert_install_hint)"
  label="HOST_OS=${host_os:-<empty>}"

  case "$(normalize_host_os "${host_os:-linux}" 2>/dev/null || echo linux)" in
    linux)
      assert_contains "$label dns" "$dns" "/etc/hosts"
      assert_contains "$label dns" "$dns" 'sudo sed -i "/'
      assert_absent   "$label dns" "$dns" "sed -i ''"
      assert_contains "$label tests" "$tests" "getent hosts"
      assert_contains "$label mkcert" "$hint" "apt"
      ;;
    macos)
      assert_contains "$label dns" "$dns" "/etc/hosts"
      assert_contains "$label dns" "$dns" "sudo sed -i ''"
      assert_contains "$label tests" "$tests" "dscacheutil"
      assert_absent   "$label tests" "$tests" "getent hosts"
      assert_contains "$label mkcert" "$hint" "brew install mkcert"
      ;;
    windows)
      assert_contains "$label dns" "$dns" 'drivers\etc\hosts'
      assert_contains "$label dns" "$dns" "Set-Content"
      assert_contains "$label dns" "$dns" 'VM_IP = "192.168.122.50"'
      assert_contains "$label tests" "$tests" "Resolve-DnsName"
      assert_contains "$label mkcert" "$hint" "choco install mkcert"
      ;;
    windows-wsl)
      assert_contains "$label dns" "$dns" 'drivers\etc\hosts'
      assert_contains "$label dns" "$dns" 'VM_IP = "127.0.0.1"'
      assert_contains "$label tests" "$tests" "Resolve-DnsName"
      ;;
  esac
}

echo "== host-OS output matrix =="
run_case "linux"
run_case "macos"
run_case "windows"
run_case "windows-wsl"

# Empty / unknown host OS must fall back to Linux output.
echo "== unset host OS falls back to linux =="
export HOST_OS=""
fallback_dns="$(print_host_dns_commands_for_site "$SITE_NAME" "$VM_IP")"
assert_contains "unset dns" "$fallback_dns" "/etc/hosts"
assert_absent   "unset dns" "$fallback_dns" 'drivers\etc\hosts'

# Label + normalization helpers.
echo "== label + normalization =="
export HOST_OS="mac"
assert_contains "normalize mac" "$(effective_host_os)" "macos"
assert_contains "label mac" "$(host_os_label)" "macOS"
export HOST_OS="win"
assert_contains "normalize win" "$(effective_host_os)" "windows"

if [[ "$failures" -gt 0 ]]; then
  echo "host-os output tests: ${failures} failure(s)" >&2
  exit 1
fi
echo "host-os output tests: all checks passed"
