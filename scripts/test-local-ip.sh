#!/usr/bin/env bash
# Hermetic tests for lib/local_ip.sh (no sudo, no real Netplan apply).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${label}: expected '${expected}' got '${actual}'" >&2
    fail=$((fail + 1))
  else
    echo "OK: ${label}"
  fi
}

tmpdir="$(mktemp -d /tmp/erpnext-dev-local-ip.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

export LOCAL_IP_DRY_RUN=1
export LOCAL_IP_STATE_FILE="${tmpdir}/local-ip.state"
export LOCAL_IP_NETPLAN_DIR="${tmpdir}/netplan"
export LOCAL_IP_BACKUP_DIR="${tmpdir}/backups"
export LOCAL_IP_DETECT_IP="192.168.122.50"
export LOCAL_IP_DETECT_IFACE="eth0"
export LOCAL_IP_DETECT_GATEWAY="192.168.122.1"
export SITE_NAME="erp.test"
export SUDO=""
export APP_NAME="ERPNext Developer Toolkit"
export SCRIPT_VERSION="test"
mkdir -p "${LOCAL_IP_NETPLAN_DIR}"

# Minimal stubs used by local_ip.sh
is_usable_vm_ip() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  case "$ip" in 127.*|169.254.*|0.*) return 1 ;; esac
  return 0
}
require_sudo() { return 0; }
fail() { echo "FAIL: $*" >&2; exit 1; }
status_line() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }
warn() { echo "WARN: $*" >&2; }
toolkit_cmd() { printf 'erpnext-dev %s' "$1"; }
ui_box_start() { echo "=== $1 ==="; }
ui_box_end() { echo "=== end ==="; }
confirm() { return 0; }
print_host_dns_commands_for_site() { echo "HOSTS ${1} ${2}"; }
get_vm_ip() { printf '%s\n' "${LOCAL_IP_DETECT_IP}"; }
get_primary_interface() { printf '%s\n' "${LOCAL_IP_DETECT_IFACE}"; }
get_default_gateway() { printf '%s\n' "${LOCAL_IP_DETECT_GATEWAY}"; }
get_primary_mac() { printf 'aa:bb:cc:dd:ee:ff\n'; }
effective_host_os() { printf 'linux\n'; }

# shellcheck source=lib/local_ip.sh disable=SC1091
source "${ROOT_DIR}/lib/local_ip.sh"

# DHCP signal from a cloud-init style file
cat >"${LOCAL_IP_NETPLAN_DIR}/50-cloud-init.yaml" <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
assert_eq "detect dhcp" "dhcp" "$(local_ip_detect_method)"

# Save mapping
local_ip_save_mapping >/dev/null
assert_eq "saved ip" "192.168.122.50" "$(local_ip_read_state_key SAVED_IP)"
assert_eq "saved site" "erp.test" "$(local_ip_read_state_key SITE_NAME)"

# Drift match
if run_local_ip_drift_check >/dev/null; then
  echo "OK: drift match exit 0"
else
  echo "FAIL: drift match should exit 0" >&2
  fail=$((fail + 1))
fi

# Drift mismatch
LOCAL_IP_DETECT_IP="192.168.122.99"
set +e
run_local_ip_drift_check >/dev/null
drift_rc=$?
set -e
assert_eq "drift mismatch exit" "1" "$drift_rc"
LOCAL_IP_DETECT_IP="192.168.122.50"

# Wizard dry-run: backup + write static netplan + save
run_local_static_ip_wizard >/dev/null
[[ -f "$(local_ip_netplan_path)" ]] || {
  echo "FAIL: netplan file not written" >&2
  fail=$((fail + 1))
}
grep -q 'dhcp4: false' "$(local_ip_netplan_path)" || {
  echo "FAIL: static netplan missing dhcp4:false" >&2
  fail=$((fail + 1))
}
assert_eq "method after wizard" "static" "$(local_ip_detect_method)"
backup="$(local_ip_read_state_key NETPLAN_BACKUP)"
[[ -d "$backup" ]] || {
  echo "FAIL: backup dir missing: ${backup}" >&2
  fail=$((fail + 1))
}
echo "OK: wizard wrote static netplan and backup"

# Rollback restores prior dhcp file presence from backup
run_local_static_ip_rollback >/dev/null
[[ -f "${LOCAL_IP_NETPLAN_DIR}/50-cloud-init.yaml" ]] || {
  echo "FAIL: rollback did not restore cloud-init netplan" >&2
  fail=$((fail + 1))
}
echo "OK: rollback restored backup contents"

# Menu mapper smoke: status/plan are non-fatal
show_local_ip_status >/dev/null
show_local_ip_plan >/dev/null
echo "OK: status/plan render"

if ((fail > 0)); then
  echo "test-local-ip: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-local-ip: all checks passed"
