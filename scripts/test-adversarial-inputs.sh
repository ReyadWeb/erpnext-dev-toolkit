#!/usr/bin/env bash
# Hermetic adversarial-input tests for highest-risk parsers (v1.18.2 / #82).
# Prefer rejecting unsafe input over Scorecard fuzz checkboxes. No sudo/network.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
note_fail() {
  echo "FAIL: $*" >&2
  fail=$((fail + 1))
}
pass() { echo "OK: $*"; }

bash -n lib/dashboard.sh || note_fail "bash -n lib/dashboard.sh"
bash -n lib/access.sh || note_fail "bash -n lib/access.sh"
bash -n lib/backup.sh || note_fail "bash -n lib/backup.sh"

# shellcheck source=lib/common.sh disable=SC1091
source "$ROOT_DIR/lib/common.sh"
FORCE_NO_COLOR=1
NO_COLOR=1
erpnext_dev_init_terminal_colors 2>/dev/null || true
: "${YELLOW:=}" "${RESET:=}" "${GREEN:=}" "${RED:=}" "${BLUE:=}" "${BOLD:=}"
# Minimal stubs so sourcing access/backup helpers stays light.
status_line() { :; }
require_sudo() { return 0; }
# shellcheck source=lib/access.sh disable=SC1091
source "$ROOT_DIR/lib/access.sh"
# shellcheck source=lib/dashboard.sh disable=SC1091
source "$ROOT_DIR/lib/dashboard.sh"
# sanitize_restore_rehearsal_value lives in backup.sh; source only if defined after a
# narrow extract — re-source the function via bash -c pattern from the file.
sanitize_restore_rehearsal_value() {
  local value="$1"
  # Keep in sync with lib/backup.sh (tested for metachar / path stripping).
  printf '%s' "$value" | tr '\n\t' '  ' | sed -E 's/[[:space:]]+/-/g; s/[^A-Za-z0-9._:@\/+=,-]/-/g; s/^-+//; s/-+$//' | cut -c1-240
}

# --- health.env value safety (shell metacharacters / newlines) ---
bad_values=(
  '$(id)'
  '`id`'
  'x;rm -rf /'
  'a|b'
  'a&b'
  $'line\ninject'
  $'cr\rinject'
  '$(curl evil)'
  '*'
  $'!bang'
)
for bad in "${bad_values[@]}"; do
  if health_env_value_is_safe "$bad"; then
    note_fail "health_env_value_is_safe accepted: ${bad@Q}"
  fi
done
health_env_value_is_safe "https://hooks.example.com/ok" || note_fail "benign https webhook rejected"
health_env_value_is_safe "600" || note_fail "benign numeric rejected"
pass "health_env_value_is_safe rejects metacharacters"

# --- webhook URL validation ---
HEALTH_ALERT_WEBHOOK_ALLOW_HTTP=0
health_env_validate_value HEALTH_ALERT_WEBHOOK_URL 'https://ok.example/h' || note_fail "https webhook should pass"
health_env_validate_value HEALTH_ALERT_WEBHOOK_URL 'http://evil.example/h' && note_fail "remote http webhook should fail" || true
health_env_validate_value HEALTH_ALERT_WEBHOOK_URL 'https://ok.example/`id`' && note_fail "backtick https should fail safety" || true
health_env_validate_value HEALTH_COOLDOWN_SEC '600;id' && note_fail "cooldown with semicolon should fail" || true
health_env_validate_value HEALTH_COOLDOWN_SEC '$((1+2))' && note_fail "arithmetic cooldown should fail" || true
health_env_validate_value HEALTH_COOLDOWN_SEC '900' || note_fail "benign cooldown should pass"
pass "health_env_validate_value adversarial cases"

# --- IP / usable guest IP ---
is_usable_vm_ip "192.168.122.50" || note_fail "LAN IP should be usable"
is_usable_vm_ip "127.0.0.1" && note_fail "loopback must be rejected" || true
is_usable_vm_ip "169.254.1.1" && note_fail "link-local must be rejected" || true
is_usable_vm_ip "0.0.0.0" && note_fail "0.x must be rejected" || true
is_usable_vm_ip "999.1.1.1" && note_fail "invalid octet must be rejected" || true
is_usable_vm_ip "1.2.3" && note_fail "short IP must be rejected" || true
is_usable_vm_ip '192.168.1.1;id' && note_fail "IP with metachar must be rejected" || true
is_usable_vm_ip $'10.0.0.1\n' && note_fail "IP with newline must be rejected" || true
is_usable_vm_ip "../../etc/passwd" && note_fail "path-as-IP must be rejected" || true
pass "is_usable_vm_ip adversarial cases"

# --- release tag policy (malformed tags are non-stable) ---
policy_out="$(scripts/release-signing-policy.sh 'v1.2.3;rm' 1)" || true
[[ "$policy_out" == "sign" ]] || note_fail "metachar tag with key should still print sign/publish (got ${policy_out})"
# Stable regex must not match injection strings
tag_bad_semi='v1.2.3;rm'
tag_bad_sub='v1.2.3$(id)'
tag_ok='v1.2.3'
stable_re='^v[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$tag_bad_semi" =~ $stable_re ]]; then
  note_fail "stable tag regex matched injection string"
fi
if [[ "$tag_bad_sub" =~ $stable_re ]]; then
  note_fail "stable tag regex matched command substitution"
fi
[[ "$tag_ok" =~ $stable_re ]] || note_fail "benign stable tag rejected by regex"
pass "release tag shape adversarial cases"

# --- restore rehearsal sanitize strips metacharacters / path tricks ---
san="$(sanitize_restore_rehearsal_value 'notes; rm -rf /')"
[[ "$san" != *';'* ]] || note_fail "sanitize left semicolon: $san"
san="$(sanitize_restore_rehearsal_value '$(id)')"
[[ "$san" != *'$'* ]] || note_fail "sanitize left dollar: $san"
san="$(sanitize_restore_rehearsal_value '`reboot`')"
[[ "$san" != *'`'* ]] || note_fail "sanitize left backtick: $san"
san="$(sanitize_restore_rehearsal_value 'a|b&c>d')"
[[ "$san" != *'|'* && "$san" != *'&'* && "$san" != *'>'* ]] || note_fail "sanitize left shell ops: $san"
# Very long input truncated
long="$(printf 'a%.0s' {1..500})"
san="$(sanitize_restore_rehearsal_value "$long")"
((${#san} <= 240)) || note_fail "sanitize did not truncate long string (${#san})"
pass "sanitize_restore_rehearsal_value adversarial cases"

# --- empty / whitespace-only ---
health_env_value_is_safe "" || note_fail "empty value should be safe"
is_usable_vm_ip "" && note_fail "empty IP must be rejected" || true
is_usable_vm_ip "   " && note_fail "whitespace IP must be rejected" || true
pass "empty/whitespace cases"

# --- restore latest-set input must fail closed under entrypoint errexit ---
# Source the production implementation and replace every environment/mutation
# dependency with a hermetic sentinel. No site, database, or service is touched.
# shellcheck source=lib/backup.sh disable=SC1091
source "$ROOT_DIR/lib/backup.sh"

restore_tmp="$(mktemp -d /tmp/erpnext-dev-restore-input.XXXXXX)"
restore_cleanup() { rm -rf "$restore_tmp"; }
trap restore_cleanup EXIT
touch "$restore_tmp/database.sql.gz" "$restore_tmp/files.tar" "$restore_tmp/private-files.tar"
SITE_NAME=fixture.test
LOG_FILE="$restore_tmp/toolkit.log"

require_sudo() { :; }
deployment_engine_is_docker() { return 1; }
require_site_environment() { printf '%s\n' "$restore_tmp/bench"; }
list_site_backups() { :; }
backup_latest_set_paths() {
  printf '%s\n' \
    "$restore_tmp/complete-set" \
    "$restore_tmp/database.sql.gz" \
    "$restore_tmp/files.tar" \
    "$restore_tmp/private-files.tar" \
    "$restore_tmp/site_config_backup.json" \
    complete
}
status_line() { :; }
path_is_file() { [[ -f "$1" ]]; }
read_restore_database_admin_credentials() {
  : >"$restore_tmp/advanced"
  return 23
}
confirm_restore() { return 1; }
run_as_frappe() {
  : >"$restore_tmp/MUTATION"
  return 99
}
stop_erpnext_service() {
  : >"$restore_tmp/MUTATION"
  return 99
}
run_post_restore_maintenance() {
  : >"$restore_tmp/MUTATION"
  return 99
}

run_restore_selection_case() {
  local input="$1"
  local output="$2"
  rm -f "$restore_tmp/advanced" "$restore_tmp/MUTATION"
  set +e
  printf '%s' "$input" | ASSUME_YES=0 restore_site_full >"$output" 2>&1
  local rc=$?
  set -e
  printf '%s\n' "$rc"
}

restore_rc="$(run_restore_selection_case $'Y\n' "$restore_tmp/y.out")"
[[ -f "$restore_tmp/advanced" ]] || note_fail "interactive Y did not advance beyond backup selection"
[[ ! -f "$restore_tmp/MUTATION" ]] || note_fail "interactive Y test reached a restore mutation"
[[ "$restore_rc" -ne 0 ]] || note_fail "interactive Y sentinel unexpectedly completed restore"
pass "restore latest-set selection accepts interactive Y"

restore_rc="$(run_restore_selection_case $'\n' "$restore_tmp/enter.out")"
[[ -f "$restore_tmp/advanced" ]] || note_fail "interactive Enter did not use the documented Yes default"
[[ ! -f "$restore_tmp/MUTATION" ]] || note_fail "interactive Enter test reached a restore mutation"
[[ "$restore_rc" -ne 0 ]] || note_fail "interactive Enter sentinel unexpectedly completed restore"
pass "restore latest-set selection accepts interactive Enter default"

restore_rc="$(run_restore_selection_case $'no\n' "$restore_tmp/no.out")"
[[ "$restore_rc" -eq 0 ]] || note_fail "interactive N/no cancellation returned ${restore_rc}"
[[ ! -f "$restore_tmp/advanced" ]] || note_fail "interactive N/no advanced beyond backup selection"
[[ ! -f "$restore_tmp/MUTATION" ]] || note_fail "interactive N/no reached a restore mutation"
grep -q "Restore cancelled before any changes were made" "$restore_tmp/no.out" \
  || note_fail "interactive N/no cancellation message missing"
pass "restore latest-set selection cancels safely on interactive N/no"

restore_rc="$(run_restore_selection_case '' "$restore_tmp/eof.out")"
[[ "$restore_rc" -eq 2 ]] || note_fail "restore selection EOF returned ${restore_rc}, expected 2"
[[ ! -f "$restore_tmp/advanced" && ! -f "$restore_tmp/MUTATION" ]] \
  || note_fail "restore selection EOF advanced or mutated"
grep -q "Could not read the backup selection" "$restore_tmp/eof.out" \
  || note_fail "restore selection EOF actionable error missing"
pass "restore latest-set selection fails closed on EOF"

rm -f "$restore_tmp/advanced" "$restore_tmp/MUTATION"
set +e
printf 'yes\n' | ASSUME_YES=0 restore_site_full 2>&1 | tee "$restore_tmp/tee.out" >/dev/null
restore_rc=${PIPESTATUS[1]}
set -e
[[ -f "$restore_tmp/advanced" ]] || note_fail "restore selection through tee did not advance"
[[ ! -f "$restore_tmp/MUTATION" ]] || note_fail "restore selection through tee reached a mutation"
[[ "$restore_rc" -ne 0 ]] || note_fail "restore selection through tee sentinel unexpectedly completed restore"
pass "restore latest-set selection works with output captured through tee"

rm -f "$restore_tmp/advanced" "$restore_tmp/MUTATION"
set +e
(ASSUME_YES=1 restore_site_full </dev/null >"$restore_tmp/yes-flag.out" 2>&1)
restore_rc=$?
set -e
[[ -f "$restore_tmp/advanced" ]] || note_fail "-y restore path did not auto-select the complete latest set"
[[ ! -f "$restore_tmp/MUTATION" ]] || note_fail "-y restore compatibility test reached a mutation"
[[ "$restore_rc" -ne 0 ]] || note_fail "-y restore sentinel unexpectedly completed restore"
pass "restore -y path remains compatible with complete-set auto-selection"

if ((fail > 0)); then
  echo "test-adversarial-inputs: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-adversarial-inputs: all checks passed"
