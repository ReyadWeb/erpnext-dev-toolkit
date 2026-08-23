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
wait_for_file_text() {
  local file="$1" expected="$2" attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -Fq -- "$expected" "$file" 2>/dev/null && return 0
    sleep 0.02
  done
  return 1
}

source "$ROOT_DIR/lib/apps.sh"
source "$ROOT_DIR/lib/profile.sh"
source "$ROOT_DIR/lib/install.sh"
source "$ROOT_DIR/lib/access.sh"
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
NVM_VERSION=0.40.3 NVM_COMMIT=977563e97ddc66facf3a8e31c6cff01d236f09bd
NODE_VERSION=24 YARN_VERSION=1.22.22 UV_VERSION=0.11.28
PYTHON_VERSION=3.14 PYTHON_PATCH_VERSION=3.14.6 BENCH_VERSION=5.31.0
FRAPPE_BRANCH=version-16 FRAPPE_COMMIT=6a329d068416768ec47ccd3326b9cc95a8d7bf99
CRM_COMMIT=49d98d61e7d42c3bfc97ea65725c68d632c6b849
TELEPHONY_COMMIT=039cf39f245d6818ead03cf94eea6ce7f9c1e1f7
HELPDESK_COMMIT=480486287b2b7179dd42a09c2a62fca9cc89c26d
export NVM_COMMIT FRAPPE_COMMIT CRM_COMMIT TELEPHONY_COMMIT HELPDESK_COMMIT
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

# Live Phase 7.4 regression: real implementation, separate Frappe shells, an
# NVM-only toolchain, hostile inherited configuration, and a partial bench.
RUNTIME_WORK="$WORK/runtime-regression"
RUNTIME_HOME="$RUNTIME_WORK/home/frappe"
RUNTIME_NODE_BIN="$RUNTIME_HOME/.nvm/versions/node/v24.19.0/bin"
RUNTIME_LOG="$RUNTIME_WORK/commands.log"
mkdir -p "$RUNTIME_NODE_BIN" "$RUNTIME_HOME/.local/bin" "$RUNTIME_WORK/invoker" "$RUNTIME_WORK/state"
chmod 0111 "$RUNTIME_WORK/invoker"
printf '%s\n' \
  'nvm() {' \
  '  case "$1" in install) [[ "${NVM_STUB_FAIL_INSTALL:-0}" == 0 ]] || return 46; export PATH="$NVM_DIR/versions/node/v24.19.0/bin:$HOME/.local/bin:/usr/bin:/bin" ;; use) export PATH="$NVM_DIR/versions/node/v24.19.0/bin:$HOME/.local/bin:/usr/bin:/bin" ;; alias) : ;; *) return 1 ;; esac' \
  '}' >"$RUNTIME_HOME/.nvm/nvm.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "v24.19.0\n"' >"$RUNTIME_NODE_BIN/node"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "npm|HOME=%s|USER=%s|PWD=%s|config=%s|cache=%s\n" "$HOME" "$USER" "$PWD" "$NPM_CONFIG_USERCONFIG" "$NPM_CONFIG_CACHE" >>"$RUNTIME_LOG"' \
  '[[ "$HOME" != /home/test && "$USER" == frappe && "$NPM_CONFIG_USERCONFIG" == "$HOME/.config/npm/npmrc" && "$NPM_CONFIG_CACHE" == "$HOME/.cache/npm" ]]' \
  'if [[ "${1:-}" == --version ]]; then printf "11.5.1\n"; elif [[ "${1:-} ${2:-}" == "prefix -g" ]]; then dirname "$(dirname "$0")"; fi' >"$RUNTIME_NODE_BIN/npm"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "yarn|HOME=%s|PWD=%s|XDG=%s|npm=%s|yarn=%s\n" "$HOME" "$PWD" "$XDG_CONFIG_HOME" "$NPM_CONFIG_USERCONFIG" "$YARN_RC_FILENAME" >>"$RUNTIME_LOG"' \
  '[[ "$HOME" != /home/test && "$PWD" != /home/test* && "$XDG_CONFIG_HOME" == "$HOME/.config" && "$NPM_CONFIG_USERCONFIG" == "$HOME/.config/npm/npmrc" && "$YARN_RC_FILENAME" == "$HOME/.config/yarn/yarnrc" ]]' \
  'printf "1.22.22\n"' >"$RUNTIME_NODE_BIN/yarn"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "uv|HOME=%s|PWD=%s|no_config=%s|config=%s\n" "$HOME" "$PWD" "${UV_NO_CONFIG:-}" "${UV_CONFIG_FILE:-unset}" >>"$RUNTIME_LOG"' \
  '[[ "${UV_NO_CONFIG:-}" == 1 && -z "${UV_CONFIG_FILE:-}" ]]' \
  '[[ "${1:-}" == --version ]] && printf "uv 0.11.28 (x86_64-unknown-linux-gnu)\n" || :' >"$RUNTIME_HOME/.local/bin/uv"
printf '%s\n' '#!/usr/bin/env bash' 'printf "Python 3.14.6\n"' >"$RUNTIME_HOME/.local/bin/python3"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "bench|%s|HOME=%s|PWD=%s|XDG=%s\n" "$*" "$HOME" "$PWD" "$XDG_CONFIG_HOME" >>"$RUNTIME_LOG"' \
  'case "${1:-}" in' \
  '  --version) printf "5.31.0\n" ;;' \
  '  version) printf "frappe 16.0.0\n" ;;' \
  '  init)' \
  '    target="$2"; mkdir -p "$target/apps/frappe"' \
  '    [[ "${BENCH_STUB_MODE:-}" != fail ]] || exit 47' \
  '    mkdir -p "$target/env/bin" "$target/sites" "$target/config"; printf "#!/usr/bin/env bash\nif [[ \\\"\$1 \$2\\\" == \\\"-m pip\\\" ]]; then printf \\\"pip 26.0.1 from fixture\\\\n\\\"; else printf \\\"Python 3.14.6\\\\n\\\"; fi\n" >"$target/env/bin/python"; chmod +x "$target/env/bin/python"; printf frappe >"$target/sites/apps.txt"; printf "{}\n" >"$target/sites/common_site_config.json"; printf "web: bench serve\n" >"$target/Procfile"; printf "port 13000\n" >"$target/config/redis_cache.conf"; printf "port 11000\n" >"$target/config/redis_queue.conf"' \
  '    [[ "${BENCH_STUB_MODE:-}" != missing-apps ]] || rm -f "$target/sites/apps.txt" ;;' \
  '  new-site)' \
  '    mkdir -p "sites/$2"' \
  '    [[ "${BENCH_STUB_MODE:-}" != site-fail ]] || exit 48' \
  '    if [[ "${BENCH_STUB_MODE:-}" == tty-attempt ]]; then if { exec 8</dev/tty; } 2>/dev/null; then exit 62; fi; fi' \
  '    if [[ "${BENCH_STUB_MODE:-}" == credential-check || "${BENCH_STUB_MODE:-}" == tty-attempt ]]; then' \
  '      IFS= read -r db_secret || exit 60; IFS= read -r admin_secret || exit 61' \
  '      [[ "$db_secret" == fixture-db-password && "$admin_secret" == fixture-admin ]] || exit 63' \
  '    fi' \
  '    printf "{}\n" >"sites/$2/site_config.json" ;;' \
  '  get-app) app="${@: -2:1}"; mkdir -p "apps/$app"; [[ "${BENCH_STUB_MODE:-}" != get-fail ]] || exit 49 ;;' \
  '  --site)' \
  '    case "${3:-}" in' \
  '      list-apps) case "${BENCH_STUB_MODE:-}" in inventory-extra) printf "frappe\ncrm\nrogue\n" ;; inventory-missing) printf "frappe\n" ;; *) printf "frappe\ncrm\n" ;; esac ;;' \
  '      install-app) [[ "${BENCH_STUB_MODE:-}" != install-fail ]] || exit 50 ;;' \
  '      migrate) [[ "${BENCH_STUB_MODE:-}" != migrate-fail ]] || exit 51 ;;' \
  '      backup) [[ "${BENCH_STUB_MODE:-}" != backup-fail ]] || exit 53 ;;' \
  '      show-config|clear-cache|clear-website-cache) : ;; esac ;;' \
  '  build) [[ "${BENCH_STUB_MODE:-}" != build-fail ]] || exit 52 ;;' \
  '  use|set-config) : ;;' \
  'esac' >"$RUNTIME_HOME/.local/bin/bench"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "git|HOME=%s|USER=%s|PWD=%s|global=%s|system=%s|%s\n" "$HOME" "$USER" "$PWD" "$GIT_CONFIG_GLOBAL" "$GIT_CONFIG_SYSTEM" "$*" >>"$RUNTIME_LOG"' \
  '[[ "$HOME" != /home/test && "$USER" == frappe && "$GIT_CONFIG_GLOBAL" == /dev/null && "$GIT_CONFIG_SYSTEM" == /dev/null ]]' \
  'app="${2#apps/}"' \
  'case "${3:-}" in remote) [[ "$app" == frappe ]] && printf "https://github.com/frappe/frappe\n" || printf "https://github.com/frappe/crm\n" ;; symbolic-ref) [[ "${GIT_STUB_BAD_FRAPPE_REF:-0}" == 1 && "$app" == frappe ]] && printf "wrong\n" || { [[ "$app" == frappe ]] && printf "version-16\n" || printf "main\n"; } ;; rev-parse) if [[ "$2" == */.nvm ]]; then printf "%s\n" "$NVM_COMMIT"; elif [[ "$app" == frappe ]]; then printf "%s\n" "$FRAPPE_COMMIT"; else printf "%s\n" "$CRM_COMMIT"; fi ;; esac' >"$RUNTIME_HOME/.local/bin/git"
chmod +x "$RUNTIME_NODE_BIN/node" "$RUNTIME_NODE_BIN/npm" "$RUNTIME_NODE_BIN/yarn" \
  "$RUNTIME_HOME/.local/bin/uv" "$RUNTIME_HOME/.local/bin/python3" "$RUNTIME_HOME/.local/bin/bench" "$RUNTIME_HOME/.local/bin/git"
printf '%s\n' '#!/usr/bin/env bash' 'port="$(awk '\''$1 == "port" { print $2 }'\'' "$1")"' 'touch "$HOME/.redis-$port"' >"$RUNTIME_HOME/.local/bin/redis-server"
printf '%s\n' '#!/usr/bin/env bash' 'while [[ $# -gt 0 ]]; do case "$1" in -h) shift 2 ;; -p) port="$2"; shift 2 ;; ping|shutdown) command="$1"; break ;; *) shift ;; esac; done' 'if [[ "$command" == ping && -f "$HOME/.redis-$port" ]]; then echo PONG; elif [[ "$command" == shutdown ]]; then rm -f "$HOME/.redis-$port"; else exit 1; fi' >"$RUNTIME_HOME/.local/bin/redis-cli"
chmod +x "$RUNTIME_HOME/.local/bin/redis-server" "$RUNTIME_HOME/.local/bin/redis-cli"

FRAPPE_HOME="$RUNTIME_HOME" FRAPPE_USER=frappe BENCH_PARENT="$RUNTIME_HOME/frappe" BENCH_NAME=frappe-bench
BENCH_DIR="$BENCH_PARENT/$BENCH_NAME" SITE_NAME=erp.test NODE_VERSION=24 PYTHON_VERSION=3.14
NVM_VERSION=0.40.3 NVM_COMMIT=977563e97ddc66facf3a8e31c6cff01d236f09bd
YARN_VERSION=1.22.22 UV_VERSION=0.11.28 PYTHON_PATCH_VERSION=3.14.6 BENCH_VERSION=5.31.0 FRAPPE_BRANCH=version-16
ADMIN_PASSWORD=fixture-admin DB_ADMIN_USER=fixture-db-admin DB_ADMIN_PASSWORD=fixture-db-password
export RUNTIME_LOG
FRAPPE_SHELL_COUNT=0
native_advanced_frappe_login_bash() {
  FRAPPE_SHELL_COUNT=$((FRAPPE_SHELL_COUNT + 1))
  printf 'shell=%s\n' "$FRAPPE_SHELL_COUNT" >>"$RUNTIME_LOG"
  bash --noprofile --norc
}
# Keep this boundary hermetic; dedicated pin tests below exercise mismatch
# handling without contacting upstream repositories.
native_advanced_remote_pin_matches() { [[ "${REMOTE_PIN_STUB_FAIL:-}" != "$1" ]]; }
export HOME=/home/test XDG_CONFIG_HOME=/home/test/.config XDG_DATA_HOME=/root/.local/share XDG_STATE_HOME=/home/test/.state XDG_CACHE_HOME=/root/.cache
export NPM_CONFIG_USERCONFIG=/home/test/.npmrc NPM_CONFIG_CACHE=/home/test/.npm YARN_RC_FILENAME=/home/test/.yarnrc YARN_CACHE_FOLDER=/root/.yarn
export PYTHONHOME=/home/test/python PYTHONPATH=/root/python UV_CONFIG_FILE=/home/test/uv.toml GIT_CONFIG_GLOBAL=/home/test/.gitconfig GIT_CONFIG_SYSTEM=/root/gitconfig
export USER=test LOGNAME=test npm_config_registry=file:///home/test/registry YARN_NPM_AUTH_TOKEN=host-secret PYTHONSTARTUP=/home/test/pythonrc GIT_CONFIG_COUNT=1
cd "$RUNTIME_WORK/invoker"
# Real functions are sourced above; fixture overrides follow later.
NVM_STUB_FAIL_INSTALL=1
export NVM_STUB_FAIL_INSTALL
set +e
# shellcheck disable=SC2218
native_advanced_toolchain_setup
rc=$?
set -e
assert_eq 'toolchain setup exact failure propagates' "$rc" 46
unset NVM_STUB_FAIL_INSTALL
# shellcheck disable=SC2218
native_advanced_toolchain_setup
cd "$WORK"
[[ "$(grep -c '^shell=' "$RUNTIME_LOG")" -ge 2 ]] || fail 'toolchain verification reused bootstrap shell'
pass 'toolchain setup exits and separate verification shell succeeds'
assert_has 'NVM activation exposes Yarn' "$(<"$RUNTIME_LOG")" 'yarn|HOME='
assert_has 'UV uses supported no-config isolation' "$(<"$RUNTIME_LOG")" 'no_config=1|config=unset'
assert_lacks 'hostile user path excluded from tool execution' "$(<"$RUNTIME_LOG")" '/home/test'
assert_lacks 'root path excluded from tool execution' "$(<"$RUNTIME_LOG")" '/root'
assert_has 'controlled Frappe working directory used' "$(<"$RUNTIME_LOG")" "PWD=$RUNTIME_HOME"

toolchain_body="$(sed -n '/^native_advanced_toolchain_setup()/,/^}/p' "$ROOT_DIR/lib/native_advanced.sh")"
assert_has 'safe empty NVM directory is accepted' "$toolchain_body" '-z "\$(find "\$NVM_DIR" -mindepth 1 -maxdepth 1 -print -quit)"'
assert_has 'nonempty or unsafe NVM directory remains rejected' "$toolchain_body" '-O "\$NVM_DIR"'
transport_body="$(sed -n '/^native_advanced_frappe_login_bash()/,/^}/p' "$ROOT_DIR/lib/native_advanced.sh")"
assert_has 'production Frappe transport clears inherited environment' "$transport_body" '/usr/bin/env -i HOME='
assert_has 'identity switch precedes environment clearing' "$transport_body" 'sudo -H -u "$FRAPPE_USER" /usr/bin/env -i'
assert_has 'production Frappe transport skips startup files' "$transport_body" '/bin/bash --noprofile --norc'
assert_lacks 'production Frappe transport avoids login shell' "$transport_body" 'su - '
user_body="$(sed -n '/^native_advanced_create_frappe_user()/,/^}/p' "$ROOT_DIR/lib/native_advanced.sh")"
assert_has 'Native advanced user uses an isolated empty skeleton' "$user_body" 'useradd --create-home --skel "$empty_skel"'
assert_has 'empty skeleton ownership and mode are verified' "$user_body" "stat -c '%u:%g:%a'"
assert_has 'empty skeleton contents are verified' "$user_body" 'find "$empty_skel" -mindepth 1 -maxdepth 1'
assert_lacks 'Native advanced user never imports the host skeleton' "$user_body" '/etc/skel'

# Bench fault tests use command stubs; immutable Git staging is exercised with
# real local repositories in a separate block below.
native_advanced_stage_source() {
  local stage="$FRAPPE_HOME/.local/state/erpnext-dev/sources/$1"
  mkdir -p "$stage"
  NATIVE_ADVANCED_SOURCE_STAGE="$stage"
}

BENCH_STUB_MODE=fail
export BENCH_STUB_MODE
set +e
# shellcheck disable=SC2218
native_advanced_bench_create
rc=$?
set -e
assert_eq 'bench init exact failure propagates' "$rc" 47
[[ -d "$BENCH_DIR/apps/frappe" ]] || fail 'bench failure fixture did not leave partial apps/frappe'
assert_has 'partial Bench ledger recorded' "$NATIVE_ADVANCED_LEDGER" partial-bench
rm -rf "$BENCH_PARENT"
NATIVE_ADVANCED_LEDGER="" NATIVE_ADVANCED_BACKUP=none NATIVE_ADVANCED_SITE_CREATED=0
NATIVE_ADVANCED_STATE_DIR="$RUNTIME_WORK/state"
NATIVE_ADVANCED_OPERATION_ID=runtime-failure NATIVE_ADVANCED_OPERATION_FILE="$RUNTIME_WORK/state/runtime-failure.state"
NATIVE_ADVANCED_REQUESTED=crm,helpdesk NATIVE_ADVANCED_RESOLVED=frappe,crm,telephony,helpdesk NATIVE_ADVANCED_PREFLIGHT=fixture
set +e
native_advanced_phase bench-created native_advanced_bench_create
rc=$?
set -e
assert_eq 'failed partial Bench transaction exit' "$rc" 31
runtime_record="$(<"$NATIVE_ADVANCED_OPERATION_FILE")"
assert_has 'failed Bench record status' "$runtime_record" 'status=failed'
assert_has 'failed Bench record checkpoint' "$runtime_record" 'checkpoint=bench-created'
assert_has 'failed Bench record result' "$runtime_record" 'result=failed'
assert_has 'failed Bench has no baseline' "$runtime_record" 'baseline_backup=none'
assert_has 'failed Bench record ledger' "$runtime_record" 'artifact_ledger=partial-bench'
assert_has 'failed Bench recovery names checkpoint' "$runtime_record" 'correct-bench-created'
assert_lacks 'failed Bench never invokes site creation' "$(<"$RUNTIME_LOG")" 'new-site'
assert_lacks 'failed Bench never invokes backup' "$(<"$RUNTIME_LOG")" ' backup'
[[ ! -e "$CONFIG_FILE" ]] || fail 'failed Bench promoted configuration'
pass 'failed Bench blocks site backup apps and promotion'

rm -rf "$BENCH_PARENT"
NATIVE_ADVANCED_LEDGER="" BENCH_STUB_MODE='missing-apps'
export BENCH_STUB_MODE
# shellcheck disable=SC2218
if native_advanced_bench_create; then fail 'Bench without sites/apps.txt accepted'; fi
assert_has 'missing apps.txt remains partial' "$NATIVE_ADVANCED_LEDGER" partial-bench
rm -rf "$BENCH_PARENT"
NATIVE_ADVANCED_LEDGER="" BENCH_STUB_MODE=success
export BENCH_STUB_MODE
# shellcheck disable=SC2218
native_advanced_bench_create
assert_has 'successful Bench accepted' "$NATIVE_ADVANCED_LEDGER" bench
bench_body="$(sed -n '/^native_advanced_bench_create()/,/^}/p' "$ROOT_DIR/lib/native_advanced.sh")"
assert_has 'Bench acceptance adds only a missing official Frappe origin' "$bench_body" 'git -C apps/frappe remote add origin "${frappe_repo}"'
assert_has 'Bench acceptance rejects conflicting Frappe origin' "$bench_body" 'remote get-url origin)" == "${frappe_repo}"'
BENCH_STUB_MODE='site-fail'
export BENCH_STUB_MODE
set +e
# shellcheck disable=SC2218
native_advanced_site_create
rc=$?
set -e
assert_eq 'bench new-site exact failure propagates' "$rc" 48
assert_has 'partial site ledger recorded' "$NATIVE_ADVANCED_LEDGER" partial-site
rm -rf "$BENCH_DIR/sites/$SITE_NAME"
NATIVE_ADVANCED_LEDGER=bench BENCH_STUB_MODE=success
export BENCH_STUB_MODE
[[ ! -e "$FRAPPE_HOME/erpnext-dev-credentials.txt" ]] || fail 'credential file exists before verified site creation'
pass 'no credential file before verified site creation'
# shellcheck disable=SC2218
native_advanced_site_create
assert_has 'verified exact site accepted' "$NATIVE_ADVANCED_LEDGER" site
site_body="$(sed -n '/^native_advanced_site_create()/,/^native_advanced_baseline_backup()/p' "$ROOT_DIR/lib/native_advanced.sh")"
assert_has 'site secrets use the pinned noninteractive prompt order' "$site_body" 'printf '\''%s\n'\'' "${DB_ADMIN_PASSWORD}" "${ADMIN_PASSWORD}"'
assert_has 'site command runs in a session without a controlling terminal' "$site_body" 'setsid --wait bench new-site'
assert_has 'site child signals target the detached process group' "$site_body" 'kill -"\$signal" -- "-\$site_child"'
assert_has 'site command preserves its exact exit status' "$site_body" 'if wait "\$site_child"; then rc=0; else rc=\$?; fi'
assert_lacks 'database password is absent from site command argv' "$site_body" '--db-root-password'
assert_lacks 'administrator password is absent from site command argv' "$site_body" '--admin-password'
rm -rf "$BENCH_DIR/sites/$SITE_NAME"
BENCH_STUB_MODE=tty-attempt
export BENCH_STUB_MODE
# shellcheck disable=SC2218
native_advanced_site_create
pass 'Bench cannot open caller controlling terminal and consumes protected input'
rm -rf "$BENCH_DIR/sites/$SITE_NAME"
BENCH_STUB_MODE=credential-check
export BENCH_STUB_MODE
# shellcheck disable=SC2218
native_advanced_site_create
pass 'database and Administrator credentials use pinned order'
rm -rf "$BENCH_DIR/sites/$SITE_NAME"
saved_db_input="$DB_ADMIN_PASSWORD" saved_admin_input="$ADMIN_PASSWORD"
DB_ADMIN_PASSWORD="$saved_admin_input" ADMIN_PASSWORD="$saved_db_input"
set +e
# shellcheck disable=SC2218
native_advanced_site_create
rc=$?
set -e
assert_eq 'reversed site credentials fail exactly' "$rc" 63
rm -rf "$BENCH_DIR/sites/$SITE_NAME"
DB_ADMIN_PASSWORD="$saved_db_input" ADMIN_PASSWORD=""
set +e
# shellcheck disable=SC2218
native_advanced_site_create
rc=$?
set -e
assert_eq 'short site credential input fails exactly' "$rc" 63
DB_ADMIN_PASSWORD="$saved_db_input" ADMIN_PASSWORD="$saved_admin_input" BENCH_STUB_MODE=success
export DB_ADMIN_PASSWORD ADMIN_PASSWORD BENCH_STUB_MODE
# shellcheck disable=SC2218
native_advanced_credentials_persist
credentials_path="$FRAPPE_HOME/erpnext-dev-credentials.txt"
[[ -f "$credentials_path" && ! -L "$credentials_path" ]] || fail 'credentials artifact is not a safe regular file'
assert_eq 'credentials file mode' "$(stat -c %a "$credentials_path")" 600
assert_eq 'credentials file test owner' "$(stat -c %u "$credentials_path")" "$(id -u)"
assert_has 'credentials success ledger' "$NATIVE_ADVANCED_LEDGER" credentials-file
credentials_digest="$(sha256sum "$credentials_path" | awk '{print $1}')"
BENCH_STUB_MODE=migrate-fail
native_advanced_migrate >/dev/null 2>&1 || true
assert_eq 'later failure preserves verified credentials' "$(sha256sum "$credentials_path" | awk '{print $1}')" "$credentials_digest"
BENCH_STUB_MODE=success
export BENCH_STUB_MODE
rm -f "$credentials_path"
ln -s "$WORK/unsafe-credential-target" "$credentials_path"
set +e
# shellcheck disable=SC2218
native_advanced_credentials_persist >/dev/null 2>&1
rc=$?
set -e
assert_eq 'unsafe credential target fails closed' "$rc" 1
if credentials_file_contract "$credentials_path" validate >/dev/null 2>&1; then fail 'credential reader followed a symlink'; fi
pass 'credential reader rejects a symlinked final component'
assert_has 'credential write attempt is ledgered' "$NATIVE_ADVANCED_LEDGER" credentials-file-attempt
rm -f "$credentials_path"
credential_contract_body="$(sed -n '/^credentials_file_contract()/,/^}/p' "$ROOT_DIR/lib/access.sh")"
credential_secure_body="$(sed -n '/^credentials_secure()/,/^}/p' "$ROOT_DIR/lib/access.sh")"
credential_show_body="$(sed -n '/^credentials_show()/,/^}/p' "$ROOT_DIR/lib/access.sh")"
assert_has 'credential contract opens final component without following symlinks' "$credential_contract_body" 'os.O_NOFOLLOW'
assert_has 'credential contract compares opened and linked inode identity' "$credential_contract_body" '(opened.st_dev, opened.st_ino) != (linked.st_dev, linked.st_ino)'
assert_lacks 'credentials-secure performs no privileged chown' "$credential_secure_body" 'chown'
assert_lacks 'credentials-secure performs no privileged chmod' "$credential_secure_body" 'chmod'
assert_has 'credentials-show reads only through validated opened descriptor' "$credential_show_body" 'credentials_file_contract "$cred_file" read'
# shellcheck disable=SC2218
native_advanced_get_app crm
get_app_body="$(sed -n '/^native_advanced_get_app()/,/^}/p' "$ROOT_DIR/lib/native_advanced.sh")"
assert_has 'app acquisition adds only a missing official origin' "$get_app_body" 'remote add origin "${repo}"'
assert_has 'app acquisition rejects a conflicting origin' "$get_app_body" 'remote get-url origin)" == "${repo}"'
# shellcheck disable=SC2218
native_advanced_install_app crm
# shellcheck disable=SC2218
native_advanced_migrate
assert_has 'successful migration verifies temporary Redis cleanup' "$NATIVE_ADVANCED_LEDGER" migration-redis-cleanup-verified
[[ ! -e "$RUNTIME_HOME/.redis-13000" && ! -e "$RUNTIME_HOME/.redis-11000" ]] || fail 'temporary migration Redis survived success'
pass 'temporary migration Redis stops after success'
# shellcheck disable=SC2218
native_advanced_assets
assert_lacks 'later Bench shells exclude hostile HOME' "$(<"$RUNTIME_LOG")" '/home/test'
pass 'get-app install migrate and build retain isolated runtime'

rm -rf "$BENCH_DIR/apps/crm"
NATIVE_ADVANCED_LEDGER=bench,site BENCH_STUB_MODE=get-fail
export BENCH_STUB_MODE
set +e
# shellcheck disable=SC2218
native_advanced_get_app crm
rc=$?
set -e
assert_eq 'get-app exact failure propagates despite partial directory' "$rc" 49
assert_has 'failed get-app records partial code' "$NATIVE_ADVANCED_LEDGER" 'partial-code:crm'
BENCH_STUB_MODE=install-fail
export BENCH_STUB_MODE
set +e
# shellcheck disable=SC2218
native_advanced_install_app crm
rc=$?
set -e
assert_eq 'install-app exact failure propagates' "$rc" 50
assert_has 'failed install-app records uncertain site mutation' "$NATIVE_ADVANCED_LEDGER" 'partial-site-app:crm'
for boundary in migrate-fail build-fail; do
  BENCH_STUB_MODE="$boundary"
  export BENCH_STUB_MODE
  set +e
  if [[ "$boundary" == migrate-fail ]]; then native_advanced_migrate; else native_advanced_assets; fi
  rc=$?
  set -e
  [[ "$boundary" == migrate-fail ]] && assert_eq 'migration exact failure propagates' "$rc" 51 || assert_eq 'asset build exact failure propagates' "$rc" 52
  if [[ "$boundary" == migrate-fail ]]; then
    assert_has 'failed migration records Redis cleanup attempt' "$NATIVE_ADVANCED_LEDGER" migration-redis-cleanup-attempted
    [[ ! -e "$RUNTIME_HOME/.redis-13000" && ! -e "$RUNTIME_HOME/.redis-11000" ]] || fail 'temporary migration Redis survived failure'
    pass 'temporary migration Redis stops after failure'
  fi
done

BENCH_STUB_MODE=success
export BENCH_STUB_MODE
mkdir -p "$BENCH_DIR/apps/frappe" "$BENCH_DIR/apps/crm" "$BENCH_DIR/sites/$SITE_NAME"
profile_plan_parse_requested_apps crm
profile_plan_resolve_apps advanced
# shellcheck disable=SC2218
native_advanced_verify
BENCH_STUB_MODE=inventory-extra
export BENCH_STUB_MODE
if native_advanced_verify; then fail 'extra installed app accepted by exact inventory'; fi
pass 'exact inventory rejects extra installed app'
BENCH_STUB_MODE=inventory-missing
export BENCH_STUB_MODE
if native_advanced_verify; then fail 'missing installed app accepted by exact inventory'; fi
pass 'exact inventory rejects missing installed app'
BENCH_STUB_MODE=success GIT_STUB_BAD_FRAPPE_REF=1
export BENCH_STUB_MODE GIT_STUB_BAD_FRAPPE_REF
if native_advanced_verify; then fail 'incorrect Frappe ref accepted'; fi
pass 'inventory verifies Frappe source and ref'
unset GIT_STUB_BAD_FRAPPE_REF
chmod 700 "$RUNTIME_WORK/invoker"

# Ubuntu 26.04 reports MariaDB as "mariadb from 11.8.x-MariaDB" rather than
# using the older "Distrib" token. Verify the installed runtime contract against
# that real format before prerequisite tests replace host probes with fixtures.
(
  mariadb() { printf 'mariadb from 11.8.6-MariaDB, client 15.2 for debian-linux-gnu\n'; }
  redis-server() { printf 'Redis server v=8.0.5 sha=00000000:1 malloc=jemalloc bits=64\n'; }
  systemctl() { return 0; }
  mariadb-admin() { return 0; }
  redis-cli() { printf 'PONG\n'; }
  pkg-config() { return 0; }
  native_advanced_verify_os_runtime
) || fail 'Ubuntu 26.04 MariaDB/Redis runtime format rejected'
pass 'Ubuntu 26.04 MariaDB 11.8 runtime accepted'
grep -Eq '^[[:space:]]+xvfb fontconfig$' "$ROOT_DIR/lib/install.sh" \
  || fail 'fontconfig executable provider is not a required system package'
pass 'fontconfig executable provider is required'

# Real prerequisite failure handling: Chrony cannot prove a large correction,
# then APT reports future-dated Release metadata. No mutation helper may run.
PREREQ_MUTATIONS="$RUNTIME_WORK/prerequisite-mutations"
check_os() { printf 'check-os\n' >>"$RUNTIME_LOG"; }
check_internet() { printf 'check-internet\n' >>"$RUNTIME_LOG"; }
check_resources() { printf 'check-resources\n' >>"$RUNTIME_LOG"; }
install_self_for_reuse() {
  printf 'install-self\n' >>"$PREREQ_MUTATIONS"
  return "${PREREQ_INSTALL_SELF_FAIL:-0}"
}
install_system_packages() {
  printf 'packages\n' >>"$PREREQ_MUTATIONS"
  return "${PREREQ_PACKAGES_FAIL:-0}"
}
configure_sysctl_for_redis() {
  printf 'sysctl\n' >>"$PREREQ_MUTATIONS"
  return "${PREREQ_SYSCTL_FAIL:-0}"
}
systemctl() { [[ "$*" == 'is-active --quiet chrony' ]]; }
timedatectl() {
  [[ "$1" == show ]] && printf '%s\n' "${PREREQ_SYNCED:-no}"
}
chronyc() { return 1; }
system_clock_sources_consistent() { [[ "${PREREQ_SYNCED:-no}" == yes ]]; }
native_advanced_verify_os_runtime() { printf 'runtime-verified\n' >>"$PREREQ_MUTATIONS"; }
native_advanced_verify_pdf_capability() { NATIVE_ADVANCED_PDF_CAPABILITY=unavailable; }
apt-get() {
  [[ "${PREREQ_APT_FAIL:-1}" == 1 ]] || return 0
  printf 'E: Release file for repository is not valid yet (invalid for another 23d)\n' >&2
  return 100
}
sleep() { :; }

run_real_prerequisite_failure() {
  local label="$1"
  NATIVE_ADVANCED_STATE_DIR="$RUNTIME_WORK/${label}-state"
  NATIVE_ADVANCED_OPERATION_ID="native-advanced-${label}"
  NATIVE_ADVANCED_OPERATION_FILE="$NATIVE_ADVANCED_STATE_DIR/${NATIVE_ADVANCED_OPERATION_ID}.state"
  NATIVE_ADVANCED_REQUESTED=crm,helpdesk NATIVE_ADVANCED_RESOLVED=frappe,crm,telephony,helpdesk
  NATIVE_ADVANCED_PREFLIGHT=fixture NATIVE_ADVANCED_LEDGER="" NATIVE_ADVANCED_BACKUP=none NATIVE_ADVANCED_SITE_CREATED=0
  SITE_NAME=erp.test
  set +e
  native_advanced_phase prerequisites native_advanced_prerequisites >"$RUNTIME_WORK/${label}.out" 2>&1
  PREREQ_RC=$?
  set -e
}

PREREQ_SYNCED=no
PREREQ_APT_FAIL=1
run_real_prerequisite_failure clock-behind
assert_eq 'far-behind clock exit class' "$PREREQ_RC" 31
clock_output="$(<"$RUNTIME_WORK/clock-behind.out")"
assert_has 'clock failure identifies Chrony' "$clock_output" 'detected provider: chrony'
assert_has 'clock failure provides UTC verification' "$clock_output" 'date -u'
assert_has 'clock failure provides timedatectl verification' "$clock_output" 'timedatectl status'
assert_has 'clock failure provides provider verification' "$clock_output" 'chronyc tracking'
assert_has 'clock recovery prints exact advanced request' "$clock_output" 'sudo erpnext-dev install --profile advanced --apps crm,helpdesk --site erp.test'
assert_lacks 'clock recovery never recommends first-run' "$clock_output" 'first-run'
[[ ! -e "$PREREQ_MUTATIONS" ]] || fail 'clock failure executed a mutation helper'
clock_record="$(<"$NATIVE_ADVANCED_OPERATION_FILE")"
assert_has 'clock record remains prerequisites' "$clock_record" 'checkpoint=prerequisites'
assert_has 'clock record terminal failed' "$clock_record" 'status=failed'
assert_has 'clock record result failed' "$clock_record" 'result=failed'
assert_has 'clock record ledger empty' "$clock_record" 'artifact_ledger='
assert_has 'clock record baseline absent' "$clock_record" 'baseline_backup=none'

PREREQ_SYNCED=yes
run_real_prerequisite_failure apt-future
assert_eq 'future APT metadata exit class' "$PREREQ_RC" 31
apt_output="$(<"$RUNTIME_WORK/apt-future.out")"
assert_has 'APT future metadata diagnosed' "$apt_output" 'APT repository metadata is not valid yet'
assert_has 'APT recovery prints exact advanced request' "$apt_output" 'sudo erpnext-dev install --profile advanced --apps crm,helpdesk --site erp.test'
assert_lacks 'APT recovery never recommends first-run' "$apt_output" 'first-run'
assert_lacks 'APT recovery suppresses repository details' "$apt_output" 'repository is not valid'
[[ ! -e "$PREREQ_MUTATIONS" ]] || fail 'APT failure executed a mutation helper'
pass 'clock and APT failures execute no package or deployment mutation'

rm -f "$PREREQ_MUTATIONS"
PREREQ_APT_FAIL=0 PREREQ_INSTALL_SELF_FAIL=1
run_real_prerequisite_failure toolkit-failure
assert_eq 'post-readiness Toolkit failure exit class' "$PREREQ_RC" 31
toolkit_record="$(<"$NATIVE_ADVANCED_OPERATION_FILE")"
assert_has 'Toolkit mutation boundary is ledgered' "$toolkit_record" 'artifact_ledger=toolkit-reuse'
assert_lacks 'package installation blocked after Toolkit failure' "$(<"$PREREQ_MUTATIONS")" 'packages'
pass 'prerequisite mutation begins only after readiness and is recorded'
unset PREREQ_INSTALL_SELF_FAIL

for failed_boundary in packages sysctl; do
  rm -f "$PREREQ_MUTATIONS"
  PREREQ_PACKAGES_FAIL=0 PREREQ_SYSCTL_FAIL=0
  [[ "$failed_boundary" == packages ]] && PREREQ_PACKAGES_FAIL=54 || PREREQ_SYSCTL_FAIL=55
  run_real_prerequisite_failure "$failed_boundary-failure"
  assert_eq "$failed_boundary failure remains mutation-failed" "$PREREQ_RC" 31
  [[ "$failed_boundary" != packages ]] || assert_lacks 'package failure blocks sysctl' "$(<"$PREREQ_MUTATIONS")" 'sysctl'
done
unset PREREQ_PACKAGES_FAIL PREREQ_SYSCTL_FAIL

unset -f check_os check_internet check_resources install_self_for_reuse install_system_packages configure_sysctl_for_redis
unset -f systemctl timedatectl chronyc apt-get sleep

# Restore the ordinary transaction fixture paths used below.
FRAPPE_HOME="$WORK/home/frappe"
BENCH_PARENT="$FRAPPE_HOME/frappe"
BENCH_NAME=frappe-bench
BENCH_DIR="$BENCH_PARENT/$BENCH_NAME"
CONFIG_FILE="$WORK/etc/config.env"
LEGACY_CONFIG_FILE="$WORK/home/frappe/legacy.env"
NATIVE_ADVANCED_STATE_DIR="$WORK/state"
unset BENCH_STUB_MODE

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
native_advanced_credentials_persist() {
  phase_log credentials-persisted
  native_advanced_ledger_add credentials-file
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
  grep -Fq 'INSTALLATION_PROFILE=advanced' "$CONFIG_FILE" && native_advanced_verify && native_advanced_readiness
}

reset_case() {
  rm -rf "${WORK:?}/home" "${WORK:?}/etc" "${WORK:?}/state" "$MUTATION_LOG"
  mkdir -p "$WORK"
  NATIVE_ADVANCED_OPERATION_FILE="" NATIVE_ADVANCED_OPERATION_ID="" NATIVE_ADVANCED_STATUS="" NATIVE_ADVANCED_CHECKPOINT=""
  NATIVE_ADVANCED_RESULT="" NATIVE_ADVANCED_RECOVERY="" NATIVE_ADVANCED_PREFLIGHT="" NATIVE_ADVANCED_LEDGER=""
  NATIVE_ADVANCED_BACKUP=none NATIVE_ADVANCED_CONFIG_BASE="" NATIVE_ADVANCED_RECORDS_BASE="" NATIVE_ADVANCED_SITE_CREATED=0
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
  "BENCH_PARENT=/home/frappe/frappe-entrypoint-hermetic"
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
run_entrypoint_without_privilege() {
  local output_file="$1" env_bin bash_bin entrypoint_root="$ROOT_DIR"
  local unprivileged_uid="${SUDO_UID:-65534}" unprivileged_gid="${SUDO_GID:-65534}"
  shift
  set +e
  if [[ "$EUID" -eq 0 ]]; then
    command -v setpriv >/dev/null || fail 'root test execution requires setpriv for the non-root privilege case'
    chmod 0755 "$WORK" "$ENTRY_WORK"
    chmod 0777 "$ENTRY_WORK/log"
    # A root-owned checkout can sit below a non-traversable home directory.
    # Exercise the exact entrypoint/module bytes from a bounded readable fixture
    # instead of making assumptions about the caller's repository parents.
    entrypoint_root="$WORK/unprivileged-toolkit"
    mkdir -p "$entrypoint_root"
    cp -a "$ROOT_DIR/erpnext-dev.sh" "$ROOT_DIR/VERSION" "$ROOT_DIR/lib" "$entrypoint_root/"
    chmod -R a+rX "$entrypoint_root"
    env_bin="$(command -v env)"
    bash_bin="$(command -v bash)"
    [[ "$unprivileged_uid" =~ ^[0-9]+$ && "$unprivileged_gid" =~ ^[0-9]+$ && "$unprivileged_uid" -ne 0 ]] \
      || {
        unprivileged_uid=65534
        unprivileged_gid=65534
      }
    setpriv --reuid="$unprivileged_uid" --regid="$unprivileged_gid" --clear-groups \
      "$env_bin" "${ENTRY_ENV[@]}" "$bash_bin" "$entrypoint_root/erpnext-dev.sh" "$@" >"$output_file" 2>&1
  else
    env "${ENTRY_ENV[@]}" "$ROOT_DIR/erpnext-dev.sh" "$@" >"$output_file" 2>&1
  fi
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

run_entrypoint_without_privilege "$ENTRY_WORK/noninteractive.out" install --profile advanced --apps crm,helpdesk --site erp.test --yes
if [[ "$ENTRY_RC" -ne 1 ]] || ! wait_for_file_text "$ENTRY_WORK/noninteractive.out" 'must be run with sudo'; then
  sed -n '1,12p' "$ENTRY_WORK/noninteractive.out" >&2
fi
assert_eq 'noninteractive dispatcher reaches sudo transaction gate' "$ENTRY_RC" 1
assert_has 'noninteractive dispatcher reaches dedicated plan' "$(<"$ENTRY_WORK/noninteractive.out")" 'Native Advanced Installation Plan'
assert_has 'noninteractive transaction requires privilege' "$(<"$ENTRY_WORK/noninteractive.out")" 'must be run with sudo'
if [[ "$EUID" -eq 0 ]]; then
  run_entrypoint "$ENTRY_WORK/root-transaction.out" install --profile advanced --apps crm,helpdesk --site erp.test --yes
  assert_eq 'root dispatcher passes privilege gate and reaches bounded transaction failure' "$ENTRY_RC" 31
  assert_lacks 'root dispatcher does not report a missing privilege' "$(<"$ENTRY_WORK/root-transaction.out")" 'must be run with sudo'
fi

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

reset_case
FRAPPE_BRANCH=main
set +e
native_advanced_install >/dev/null 2>&1
rc=$?
set -e
assert_eq 'unsupported Frappe branch fails before mutation' "$rc" 22
[[ ! -e "$MUTATION_LOG" && ! -e "$NATIVE_ADVANCED_STATE_DIR" ]] || fail 'unsupported branch mutated state'
FRAPPE_BRANCH='version-16'
pass 'unsupported runtime plan is mutation-free'

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

# A protected, exact, artifact-free prerequisite failure may be retried without
# deleting or rewriting its evidence. Every deviation remains a conflict.
create_safe_prerequisite_record() {
  reset_case
  profile_plan_parse_requested_apps crm
  profile_plan_resolve_apps advanced
  NATIVE_ADVANCED_REQUESTED="$PROFILE_PLAN_REQUESTED_CSV"
  NATIVE_ADVANCED_RESOLVED="$PROFILE_PLAN_DESIRED_CSV"
  SITE_NAME=erp.test
  NATIVE_ADVANCED_OPERATION_ID=native-advanced-prior
  NATIVE_ADVANCED_OPERATION_FILE="$NATIVE_ADVANCED_STATE_DIR/native-advanced-prior.state"
  NATIVE_ADVANCED_STATUS=failed NATIVE_ADVANCED_CHECKPOINT=prerequisites NATIVE_ADVANCED_RESULT=failed
  NATIVE_ADVANCED_PREFLIGHT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa NATIVE_ADVANCED_LEDGER="" NATIVE_ADVANCED_BACKUP=none
  NATIVE_ADVANCED_RECOVERY=inspect-record,correct-prerequisites,restart-fresh-only-if-target-absent
  native_advanced_record_write
  PRIOR_RECORD="$NATIVE_ADVANCED_OPERATION_FILE"
}

replace_record_field() {
  local field="$1" value="$2"
  sed -i "s/^${field}=.*/${field}=${value}/" "$PRIOR_RECORD"
}

expect_retry_conflict() {
  local retry_rc
  if native_advanced_install >"$WORK/retry-conflict.out" 2>&1; then
    retry_rc=0
  else
    retry_rc=$?
  fi
  [[ "$retry_rc" == 34 ]] || sed -n '1,120p' "$WORK/retry-conflict.out" >&2
  assert_eq "$1" "$retry_rc" 34
}

create_safe_prerequisite_record
prior_digest="$(sha256sum "$PRIOR_RECORD" | awk '{print $1}')"
NATIVE_ADVANCED_OPERATION_ID_OVERRIDE=retry
native_advanced_install >/dev/null 2>&1
assert_eq 'safe retry preserves prior record bytes' "$(sha256sum "$PRIOR_RECORD" | awk '{print $1}')" "$prior_digest"
[[ -f "$NATIVE_ADVANCED_STATE_DIR/native-advanced-retry.state" ]] || fail 'safe retry did not create a new attempt record'
pass 'safe exact prerequisite retry creates a separate attempt'

create_safe_prerequisite_record
INSTALLATION_PROFILE_APPS_RAW=helpdesk
expect_retry_conflict 'retry with different applications conflicts'
create_safe_prerequisite_record
QUICK_INSTALL_SITE=other.test
expect_retry_conflict 'retry with different site conflicts'

for mutation in active later-checkpoint ledger recovery malformed unsafe-mode; do
  create_safe_prerequisite_record
  case "$mutation" in
    active) replace_record_field status mutation-in-progress ;;
    later-checkpoint) replace_record_field checkpoint bench-created ;;
    ledger) replace_record_field artifact_ledger bench ;;
    recovery) replace_record_field status recovery-required ;;
    malformed) printf 'status=failed\n' >>"$PRIOR_RECORD" ;;
    unsafe-mode) chmod 0666 "$PRIOR_RECORD" ;;
  esac
  expect_retry_conflict "retry rejects $mutation record"
done

for artifact in bench site config application credentials staged-config; do
  create_safe_prerequisite_record
  case "$artifact" in
    bench) mkdir -p "$BENCH_DIR" ;;
    site) mkdir -p "$BENCH_DIR/sites/$SITE_NAME" ;;
    config)
      mkdir -p "$(dirname "$CONFIG_FILE")"
      printf 'CONFIG_SCHEMA=2\n' >"$CONFIG_FILE"
      ;;
    application) mkdir -p "$BENCH_DIR/apps/crm" ;;
    credentials)
      mkdir -p "$FRAPPE_HOME"
      printf 'protected-existing-evidence\n' >"$FRAPPE_HOME/erpnext-dev-credentials.txt"
      ;;
    staged-config) printf 'staged\n' >"$NATIVE_ADVANCED_STATE_DIR/native-advanced-stale.config" ;;
  esac
  expect_retry_conflict "retry rejects existing $artifact artifact"
done

create_safe_prerequisite_record
safe_record_copy="$WORK/safe-record-copy"
cp "$PRIOR_RECORD" "$safe_record_copy"
rm -f "$PRIOR_RECORD"
ln -s "$safe_record_copy" "$PRIOR_RECORD"
expect_retry_conflict 'retry rejects symlinked record'

SITE_NAME=erp.test NATIVE_ADVANCED_REQUESTED='crm;host-secret'
if native_advanced_print_prerequisite_retry >"$WORK/unsafe-retry.out" 2>&1; then fail 'unsafe recovery identifiers rendered'; fi
[[ ! -s "$WORK/unsafe-retry.out" ]] || fail 'unsafe recovery output was emitted'
pass 'advanced recovery renders only validated identifiers'

prerequisite_body="$(sed -n '/^native_advanced_prerequisites()/,/^}/p' "$ROOT_DIR/lib/native_advanced.sh")"
readiness_line="$(grep -n 'verify_clock_and_repository_readiness' <<<"$prerequisite_body" | cut -d: -f1)"
toolkit_line="$(grep -n 'install_self_for_reuse' <<<"$prerequisite_body" | cut -d: -f1)"
packages_line="$(grep -n 'install_system_packages' <<<"$prerequisite_body" | cut -d: -f1)"
[[ "$readiness_line" -lt "$toolkit_line" && "$readiness_line" -lt "$packages_line" ]] || fail 'advanced mutation precedes readiness gate'
pass 'advanced readiness gate precedes Toolkit and package mutation'

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
assert_eq 'readiness is proven before and after promotion' "$(grep -c '^readiness$' "$MUTATION_LOG")" 2

# Fault injection: every meaningful checkpoint, config unchanged until promotion,
# and post-site failures preserve recovery evidence.
checkpoints=(prerequisites frappe-user frappe-environment bench-created site-created credentials-persisted baseline-backup configuration-staging get-app:crm install-app:crm migration assets services readiness inventory configuration-promotion post-promotion-reconciliation)
for checkpoint in "${checkpoints[@]}"; do
  reset_case
  NATIVE_ADVANCED_FAIL_AT="$checkpoint"
  set +e
  native_advanced_install >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" == 31 || "$rc" == 33 ]] || fail "$checkpoint returned $rc"
  record="$(<"$NATIVE_ADVANCED_OPERATION_FILE")"
  mutations="$(test ! -f "$MUTATION_LOG" || cat "$MUTATION_LOG")"
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
  case "$checkpoint" in
    prerequisites | frappe-user | frappe-environment | bench-created) assert_lacks "failure at $checkpoint blocks site" "$mutations" 'site-created' ;;
    site-created | credentials-persisted) assert_lacks 'site or credential failure blocks baseline backup' "$mutations" 'baseline-backup' ;;
    baseline-backup | configuration-staging | get-app:crm) assert_lacks "failure at $checkpoint blocks app installation" "$mutations" 'install-app:' ;;
    install-app:crm) assert_lacks 'app installation failure blocks migration' "$mutations" 'migration' ;;
    migration) assert_lacks 'migration failure blocks assets' "$mutations" 'assets' ;;
    assets) assert_lacks 'asset failure blocks services' "$mutations" 'services' ;;
    services) assert_lacks 'service failure blocks readiness' "$mutations" 'readiness' ;;
    readiness) assert_lacks 'readiness failure blocks inventory' "$mutations" 'inventory' ;;
    inventory | configuration-promotion) assert_lacks "failure at $checkpoint blocks post-promotion reconciliation" "$mutations" 'post-promotion-reconciliation' ;;
  esac
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

# Immutable-source contract with real local Git history.
unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null
GIT_FIXTURE="$WORK/git-fixture"
GIT_REMOTE="$WORK/approved.git"
mkdir -p "$GIT_FIXTURE"
git -C "$GIT_FIXTURE" init -q
git -C "$GIT_FIXTURE" config user.name fixture
git -C "$GIT_FIXTURE" config user.email fixture@example.invalid
printf 'A\n' >"$GIT_FIXTURE/source.txt"
git -C "$GIT_FIXTURE" add source.txt
git -C "$GIT_FIXTURE" commit -qm A
PIN_A="$(git -C "$GIT_FIXTURE" rev-parse HEAD)"
git -C "$GIT_FIXTURE" branch -M main
git clone -q --bare "$GIT_FIXTURE" "$GIT_REMOTE"
TEST_SOURCE_REPO="$GIT_REMOTE" TEST_SOURCE_COMMIT="$PIN_A" TEST_SOURCE_HOME="$WORK/immutable/home/frappe"
export TEST_SOURCE_REPO TEST_SOURCE_COMMIT TEST_SOURCE_HOME
(
  unset _ERPNEXT_DEV_NATIVE_ADVANCED_LOADED
  # shellcheck source=../lib/native_advanced.sh
  source "$ROOT_DIR/lib/native_advanced.sh"
  FRAPPE_HOME="$TEST_SOURCE_HOME" FRAPPE_USER=frappe
  mkdir -p "$FRAPPE_HOME"
  load_validated_app_catalog_record() {
    LIB_APP_ID=crm LIB_APP_REPO="$TEST_SOURCE_REPO" LIB_APP_BRANCH=main LIB_APP_COMMIT="$TEST_SOURCE_COMMIT"
  }
  native_advanced_frappe_bash() { bash --noprofile --norc; }
  native_advanced_ledger_add() { :; }
  native_advanced_remote_pin_matches crm
  native_advanced_stage_source crm
  staged="$NATIVE_ADVANCED_SOURCE_STAGE"
  [[ "$(git -C "$staged" rev-parse HEAD)" == "$TEST_SOURCE_COMMIT" ]]
)
pass 'branch at pinned commit installs the exact immutable commit'
printf 'B\n' >>"$GIT_FIXTURE/source.txt"
git -C "$GIT_FIXTURE" commit -qam B
git -C "$GIT_FIXTURE" push -q "$GIT_REMOTE" main
assert_eq 'staged immutable checkout is unchanged after upstream movement' \
  "$(git -C "$TEST_SOURCE_HOME/.local/state/erpnext-dev/sources/crm" rev-parse HEAD)" "$PIN_A"
(
  unset _ERPNEXT_DEV_NATIVE_ADVANCED_LOADED
  source "$ROOT_DIR/lib/native_advanced.sh"
  load_validated_app_catalog_record() {
    LIB_APP_ID=crm LIB_APP_REPO="$TEST_SOURCE_REPO" LIB_APP_BRANCH=main LIB_APP_COMMIT="$TEST_SOURCE_COMMIT"
  }
  native_advanced_remote_pin_matches crm
)
pass 'normal branch advancement preserves the reviewed ancestor pin'
git -C "$GIT_FIXTURE" checkout -q --orphan unrelated
git -C "$GIT_FIXTURE" rm -q -rf .
printf 'unrelated\n' >"$GIT_FIXTURE/unrelated.txt"
git -C "$GIT_FIXTURE" add unrelated.txt
git -C "$GIT_FIXTURE" commit -qm unrelated
UNRELATED="$(git -C "$GIT_FIXTURE" rev-parse HEAD)"
TEST_SOURCE_COMMIT="$UNRELATED"
export TEST_SOURCE_COMMIT
set +e
(
  unset _ERPNEXT_DEV_NATIVE_ADVANCED_LOADED
  source "$ROOT_DIR/lib/native_advanced.sh"
  load_validated_app_catalog_record() {
    LIB_APP_ID=crm LIB_APP_REPO="$TEST_SOURCE_REPO" LIB_APP_BRANCH=main LIB_APP_COMMIT="$TEST_SOURCE_COMMIT"
  }
  native_advanced_remote_pin_matches crm
)
rc=$?
set -e
assert_eq 'unrelated pin is rejected before mutation' "$rc" 1

workflow="$(<"$ROOT_DIR/.github/workflows/ci.yml")"
assert_lacks 'real jobs contain no unguarded PR-only checkout' "$workflow" 'ref: ${{ github.event.pull_request.head.sha }}'
assert_has 'real jobs select PR head or triggering SHA' "$workflow" "EXPECTED_SHA: \${{ github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha }}"
assert_has 'real jobs reject an empty expected SHA' "$workflow" 'test -n "$EXPECTED_SHA"'
assert_has 'real install compares credentials-show with protected record' "$workflow" 'assert f"ERPNext Password: {admin}" in shown'
assert_has 'post-restart performs deep baseline backup verification' "$workflow" 'erpnext-dev.sh backup-verify'
assert_has 'post-restart verifies exact installed application set' "$workflow" 'printf "%s\\n" crm frappe helpdesk telephony'
assert_has 'CI exercises focused dispatcher regression as root' "$workflow" 'sudo --preserve-env=PATH scripts/test-native-advanced-installation.sh'

service_source="$(<"$ROOT_DIR/lib/service.sh")"
start_helper_source="$(sed -n '/^create_start_helper()/,/^}/p' "$ROOT_DIR/lib/install.sh")"
assert_has 'service orders after database and Redis' "$service_source" 'After=network-online.target mariadb.service redis-server.service'
assert_has 'service pulls database and Redis dependencies' "$service_source" 'Wants=network-online.target mariadb.service redis-server.service'
assert_has 'service has bounded restart delay' "$service_source" 'RestartSec=10'
assert_has 'service only restarts on failure' "$service_source" 'Restart=on-failure'
assert_has 'service kills the complete control group' "$service_source" 'KillMode=control-group'
assert_has 'fresh service process activates pinned NVM runtime' "$start_helper_source" 'nvm use --silent "${NODE_VERSION}"'
assert_has 'fresh service process isolates Git system configuration' "$start_helper_source" 'export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null'
assert_has 'fresh service process uses exact Bench working directory' "$start_helper_source" 'cd "${bench_dir}"'

printf 'test-native-advanced-installation: %s assertions passed\n' "$ASSERTIONS"
