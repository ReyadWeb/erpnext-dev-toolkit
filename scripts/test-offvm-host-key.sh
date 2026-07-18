#!/usr/bin/env bash
# Hermetic tests for off-VM SSH host-key policy helpers (v1.18.0 / #67).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
note_fail() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }
pass() { echo "OK: $*"; }

bash -n lib/backup.sh || note_fail "bash -n lib/backup.sh"
bash -n lib/docker.sh || note_fail "bash -n lib/docker.sh"

# shellcheck source=lib/common.sh disable=SC1091
source "$ROOT_DIR/lib/common.sh"
FORCE_NO_COLOR=1
NO_COLOR=1
erpnext_dev_init_terminal_colors 2>/dev/null || true
: "${YELLOW:=}" "${RESET:=}" "${GREEN:=}" "${RED:=}" "${BLUE:=}" "${BOLD:=}"
# Minimal stubs used by sourced backup helpers.
SITE_NAME="${SITE_NAME:-erp.test}"
SUDO=""
ASSUME_YES=1
OFF_VM_BACKUP_CONFIG_FILE="$(mktemp /tmp/erpnext-dev-offvm-cfg.XXXXXX)"
OFF_VM_BACKUP_STATE_FILE="$(mktemp /tmp/erpnext-dev-offvm-state.XXXXXX)"
OFF_VM_KNOWN_HOSTS_FILE="$(mktemp /tmp/erpnext-dev-offvm-known.XXXXXX)"
rm -f "$OFF_VM_BACKUP_CONFIG_FILE" "$OFF_VM_BACKUP_STATE_FILE"
: >"$OFF_VM_KNOWN_HOSTS_FILE"
OFF_VM_STRICT_HOST_KEY=false
OFF_VM_BACKUP_TARGET="backup@203.0.113.10:/backups/erp.test/"
OFF_VM_BACKUP_SSH_IDENTITY=""
OFF_VM_BACKUP_RSYNC_DELETE=false

cleanup() {
  rm -f "$OFF_VM_BACKUP_CONFIG_FILE" "$OFF_VM_BACKUP_STATE_FILE" "$OFF_VM_KNOWN_HOSTS_FILE"
}
trap cleanup EXIT

# shellcheck source=lib/backup.sh disable=SC1091
source "$ROOT_DIR/lib/backup.sh"

host="$(off_vm_backup_target_host "$OFF_VM_BACKUP_TARGET")" || note_fail "target host parse failed"
[[ "$host" == "203.0.113.10" ]] || note_fail "expected 203.0.113.10 got ${host}"
pass "target host parse"

cmd="$(off_vm_backup_ssh_command_string)"
[[ "$cmd" == *"StrictHostKeyChecking=accept-new"* ]] || note_fail "default should be accept-new: $cmd"
[[ "$cmd" == *"UserKnownHostsFile=${OFF_VM_KNOWN_HOSTS_FILE}"* ]] || note_fail "missing UserKnownHostsFile: $cmd"
[[ "$cmd" == *"GlobalKnownHostsFile=/dev/null"* ]] || note_fail "missing GlobalKnownHostsFile isolation"
pass "default accept-new ssh options"

OFF_VM_STRICT_HOST_KEY=true
cmd="$(off_vm_backup_ssh_command_string)"
[[ "$cmd" == *"StrictHostKeyChecking=yes"* ]] || note_fail "strict mode should set yes: $cmd"
[[ "$cmd" != *"accept-new"* ]] || note_fail "strict mode must not use accept-new"
pass "strict mode ssh options"

# docker helper nameref (no eval)
# shellcheck source=lib/docker.sh disable=SC1091
source "$ROOT_DIR/lib/docker.sh"
OFF_VM_STRICT_HOST_KEY=true
docker_offvm_ssh_cmd DOCKER_OFFVM_SSH_CMD
joined="${DOCKER_OFFVM_SSH_CMD[*]}"
[[ "$joined" == ssh\ * ]] || note_fail "docker ssh cmd should start with ssh"
[[ "$joined" == *"StrictHostKeyChecking=yes"* ]] || note_fail "docker ssh cmd missing strict yes"
pass "docker_offvm_ssh_cmd nameref (no eval)"

# Mock ssh-keyscan for trust helper (no network).
mockbin="$(mktemp -d /tmp/erpnext-dev-mockbin.XXXXXX)"
cat >"$mockbin/ssh-keyscan" <<'EOF'
#!/usr/bin/env bash
echo "# fake key for test"
echo "|1|faketest|AAAA test-key"
EOF
chmod +x "$mockbin/ssh-keyscan"
# Avoid require_sudo failures in hermetic mode.
require_sudo() { return 0; }
ui_box_start() { :; }
ui_box_end() { :; }
ui_next() { :; }
status_line() { :; }
toolkit_cmd() { printf '%s' "erpnext-dev $1"; }

PATH="$mockbin:$PATH"
OFF_VM_STRICT_HOST_KEY=false
: >"$OFF_VM_KNOWN_HOSTS_FILE"
off_vm_trust_host_key
grep -q 'test-key' "$OFF_VM_KNOWN_HOSTS_FILE" || note_fail "trust did not write known_hosts"
pass "trust host key writes known_hosts via ssh-keyscan"

rm -rf "$mockbin"

if (( fail > 0 )); then
  echo "test-offvm-host-key: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-offvm-host-key: all checks passed"
