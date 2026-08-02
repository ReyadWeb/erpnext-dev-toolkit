#!/usr/bin/env bash
# Hermetic PTY coverage for native restore prompts and nested tee logging.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail_case() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
assert_contains() {
  local file="$1"
  local expected="$2"
  local label="$3"
  grep -Fq "$expected" "$file" && pass "$label" || fail_case "$label"
}
assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  local label="$3"
  if grep -Fq "$unexpected" "$file"; then fail_case "$label"; else pass "$label"; fi
}

tmp="$(mktemp -d /tmp/erpnext-dev-restore-pty.XXXXXX)"
cleanup() {
  [[ "${RESTORE_TEST_KEEP_TMP:-0}" == 1 ]] || rm -rf "$tmp"
}
trap cleanup EXIT

touch "$tmp/database.sql.gz" "$tmp/files.tar" "$tmp/private-files.tar"

cat >"$tmp/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -Eeuo pipefail
cd "$RESTORE_TEST_ROOT"
source lib/common.sh
source lib/backup.sh

SITE_NAME=fixture.test
FRAPPE_HOME="$RESTORE_TEST_TMP/no-credentials"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-}"
ASSUME_YES="${RESTORE_TEST_ASSUME_YES:-0}"
LOG_FILE="$RESTORE_TEST_TMP/internal.log"
FORCE_NO_COLOR=1
NO_COLOR=1
: "${YELLOW:=}" "${RESET:=}" "${GREEN:=}" "${RED:=}" "${BLUE:=}" "${BOLD:=}"

require_sudo() { :; }
deployment_engine_is_docker() { return 1; }
require_site_environment() { printf '%s\n' "$RESTORE_TEST_TMP/bench"; }
list_site_backups() { :; }
site_backup_dir() { printf '%s\n' "$RESTORE_TEST_TMP"; }
backup_latest_set_paths() {
  printf '%s\n' \
    "$RESTORE_TEST_TMP/complete-set" \
    "$RESTORE_TEST_TMP/database.sql.gz" \
    "$RESTORE_TEST_TMP/files.tar" \
    "$RESTORE_TEST_TMP/private-files.tar" \
    "$RESTORE_TEST_TMP/site_config_backup.json" \
    complete
}
status_line() { :; }
path_is_file() { [[ -f "$1" ]]; }
run_as_frappe() {
  : >"$RESTORE_TEST_TMP/MUTATION"
  return 99
}
stop_erpnext_service() {
  : >"$RESTORE_TEST_TMP/MUTATION"
  return 99
}
run_post_restore_maintenance() {
  : >"$RESTORE_TEST_TMP/MUTATION"
  return 99
}

# Production logging shape: the toolkit redirects both output streams through
# its own tee before the caller adds another tee around this process.
exec > >(tee -a "$LOG_FILE") 2>&1
if [[ "${RESTORE_TEST_CLOSE_STDIN:-0}" == 1 ]]; then
  exec </dev/null
fi

case "$RESTORE_TEST_MODE" in
  full) restore_site_full ;;
  db) restore_site_database ;;
  legacy)
    legacy_reply=""
    read -r -p "Legacy inherited-stream prompt: " legacy_reply
    ;;
  *) exit 99 ;;
esac
HARNESS
chmod +x "$tmp/harness.sh"

run_pty_case() {
  local name="$1"
  local mode="$2"
  local assume_yes="$3"
  shift 3
  local transcript="$tmp/${name}.transcript"
  local outer="$tmp/${name}.outer.log"
  local status_file="$tmp/${name}.status"

  rm -f "$tmp/internal.log" "$tmp/MUTATION" "$transcript" "$outer" "$status_file"
  RESTORE_TEST_ROOT="$ROOT_DIR" \
    RESTORE_TEST_TMP="$tmp" \
    RESTORE_TEST_MODE="$mode" \
    RESTORE_TEST_ASSUME_YES="$assume_yes" \
    RESTORE_TEST_CLOSE_STDIN="$([[ "$name" == legacy ]] && printf 1 || printf 0)" \
    RESTORE_TEST_HARNESS="$tmp/harness.sh" \
    RESTORE_TEST_OUTER="$outer" \
    RESTORE_TEST_STATUS="$status_file" \
    python3 - "$transcript" "$@" <<'PY'
import os
import pty
import select
import sys
import time

transcript = sys.argv[1]
pairs = [arg.split("=", 1) for arg in sys.argv[2:]]
pid, fd = pty.fork()
if pid == 0:
    command = (
        'set -o pipefail; "$RESTORE_TEST_HARNESS" 2>&1 | tee "$RESTORE_TEST_OUTER"; '
        'rc=${PIPESTATUS[0]}; printf "%s\\n" "$rc" >"$RESTORE_TEST_STATUS"; exit "$rc"'
    )
    os.execvpe("bash", ["bash", "-c", command], os.environ)

output = bytearray()
deadline = time.monotonic() + 10
for prompt, answer in pairs:
    marker = prompt.encode()
    while marker not in output:
        if time.monotonic() >= deadline:
            raise SystemExit(f"timed out waiting for prompt: {prompt}")
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                output.extend(os.read(fd, 4096))
            except OSError as error:
                with open(transcript, "wb") as handle:
                    handle.write(output)
                raise SystemExit(f"PTY closed while waiting for {prompt}: {error}; output={output!r}")
    if answer == "<EOF>":
        os.write(fd, b"\x04")
    else:
        os.write(fd, answer.encode().replace(b"\\n", b"\n"))

while True:
    if time.monotonic() >= deadline:
        os.kill(pid, 9)
        raise SystemExit("timed out waiting for restore harness")
    ready, _, _ = select.select([fd], [], [], 0.1)
    if ready:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        output.extend(chunk)
    waited, _ = os.waitpid(pid, os.WNOHANG)
    if waited == pid:
        while True:
            try:
                output.extend(os.read(fd, 4096))
            except OSError:
                break
        break

with open(transcript, "wb") as handle:
    handle.write(output)
PY
}

status_for() { tr -d '[:space:]' <"$tmp/$1.status"; }
assert_no_mutation() {
  local label="$1"
  if [[ -e "$tmp/MUTATION" ]]; then fail_case "$label"; else pass "$label"; fi
}

# Reproduce the rejected inherited-stream design under a real controlling PTY:
# when inherited stdin becomes unreadable, read -p emits no visible prompt and
# errexit returns a silent status 1 despite /dev/tty remaining available.
run_pty_case legacy legacy 0
[[ "$(status_for legacy)" == 1 ]] || fail_case 'legacy inherited-stream reproduction did not return status 1'
assert_not_contains "$tmp/legacy.transcript" 'Legacy inherited-stream prompt:' 'legacy prompt disappears when inherited stdin is unreadable'
assert_no_mutation 'legacy inherited-stream reproduction performs zero mutation'

run_pty_case y full 0 \
  'Use this latest complete backup set? [Y/n]: =y\n' \
  'Enter database admin user [frappe_db_admin]: =\n' \
  'Database admin password: =pty-secret-password\n' \
  'Type RESTORE to continue: =cancel\n'
assert_contains "$tmp/y.transcript" 'Use this latest complete backup set? [Y/n]:' 'latest-set prompt visible through nested tee PTY'
assert_contains "$tmp/y.transcript" 'Enter database admin user [frappe_db_admin]:' 'Y advances to database username prompt'
if [[ "$(status_for y)" == 20 ]]; then
  pass 'caller tee preserves restore command status 20'
else
  fail_case 'Y case preserves restore command status 20 through caller tee'
fi
assert_no_mutation 'Y pre-confirmation cancellation performs zero mutation'

run_pty_case enter full 0 \
  'Use this latest complete backup set? [Y/n]: =\n' \
  'Enter database admin user [frappe_db_admin]: =\n' \
  'Database admin password: =enter-secret-password\n' \
  'Type RESTORE to continue: =cancel\n'
assert_contains "$tmp/enter.transcript" 'Enter database admin user [frappe_db_admin]:' 'Enter accepts documented latest-set default'
[[ "$(status_for enter)" == 20 ]] || fail_case 'Enter case returns documented input failure status'
assert_no_mutation 'Enter pre-confirmation cancellation performs zero mutation'

run_pty_case no full 0 'Use this latest complete backup set? [Y/n]: =no\n'
[[ "$(status_for no)" == 0 ]] || fail_case 'N/no cancellation is successful'
assert_contains "$tmp/no.outer.log" 'Restore cancelled before any changes were made.' 'N/no cancellation is explicit'
assert_no_mutation 'N/no cancellation performs zero mutation'

run_pty_case invalid full 0 'Use this latest complete backup set? [Y/n]: =maybe\n'
[[ "$(status_for invalid)" == 20 ]] || fail_case 'invalid latest-set input returns status 20'
assert_contains "$tmp/invalid.outer.log" 'Restore latest-backup selection validation failed' 'invalid input identifies failed phase'
assert_contains "$tmp/invalid.outer.log" 'No restoration began' 'invalid input confirms no restoration began'
assert_no_mutation 'invalid latest-set input performs zero mutation'

run_pty_case eof full 0 'Use this latest complete backup set? [Y/n]: =<EOF>'
[[ "$(status_for eof)" == 20 ]] || fail_case 'controlling-terminal EOF returns status 20'
assert_contains "$tmp/eof.outer.log" 'Restore latest-backup selection input failed' 'controlling-terminal EOF identifies failed phase'
assert_no_mutation 'controlling-terminal EOF performs zero mutation'

assert_not_contains "$tmp/internal.log" 'enter-secret-password' 'password absent from toolkit log'
assert_not_contains "$tmp/enter.outer.log" 'enter-secret-password' 'password absent from caller tee log'
assert_not_contains "$tmp/enter.transcript" 'enter-secret-password' 'password hidden by terminal echo suppression'

run_pty_case db db 0 \
  'Enter database backup filename or full path: =database.sql.gz\n' \
  'Enter database admin user [frappe_db_admin]: =\n' \
  'Database admin password: =db-secret-password\n' \
  'Type RESTORE to continue: =cancel\n'
assert_contains "$tmp/db.transcript" 'Enter database backup filename or full path:' 'restore-db uses shared controlling-terminal prompt'
assert_not_contains "$tmp/db.outer.log" 'db-secret-password' 'restore-db password absent from caller tee log'
[[ "$(status_for db)" == 20 ]] || fail_case 'restore-db authorization failure returns status 20'
assert_no_mutation 'restore-db pre-confirmation failure performs zero mutation'

rm -f "$tmp/MUTATION" "$tmp/internal.log"
set +e
RESTORE_TEST_ROOT="$ROOT_DIR" RESTORE_TEST_TMP="$tmp" RESTORE_TEST_MODE=full RESTORE_TEST_ASSUME_YES=0 \
  "$tmp/harness.sh" </dev/null >"$tmp/no-tty.out" 2>&1
no_tty_rc=$?
set -e
[[ "$no_tty_rc" == 20 ]] || fail_case "no controlling terminal returned ${no_tty_rc}, expected 20"
assert_contains "$tmp/no-tty.out" 'no usable controlling terminal is available' 'missing controlling terminal is actionable'
assert_contains "$tmp/no-tty.out" 'No restoration began' 'missing controlling terminal confirms no restoration began'
assert_no_mutation 'missing controlling terminal performs zero mutation'

# Preserve the existing CI contract: -y selects only the complete latest set,
# while the exact destructive token still arrives on stdin and is not bypassed.
rm -f "$tmp/MUTATION" "$tmp/internal.log"
set +e
printf 'RESTORE\n' \
  | RESTORE_TEST_ROOT="$ROOT_DIR" RESTORE_TEST_TMP="$tmp" RESTORE_TEST_MODE=full RESTORE_TEST_ASSUME_YES=1 \
    DB_ADMIN_PASSWORD=fixture-password "$tmp/harness.sh" >"$tmp/yes.out" 2>&1
yes_rc=$?
set -e
[[ "$yes_rc" == 99 ]] || fail_case "-y RESTORE token did not reach mutation sentinel (status ${yes_rc})"
[[ -e "$tmp/MUTATION" ]] && pass '-y preserves exact RESTORE authorization contract' \
  || fail_case '-y bypassed or failed before explicit RESTORE authorization'

((failures == 0)) || {
  printf 'restore input tests: %d failure(s)\n' "$failures" >&2
  exit 1
}
printf 'restore input tests: all checks passed\n'
