# shellcheck shell=bash
[[ -n "${_ERPNEXT_DEV_NATIVE_ADVANCED_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_NATIVE_ADVANCED_LOADED=1

NATIVE_ADVANCED_STATE_DIR="${NATIVE_ADVANCED_STATE_DIR:-${OPERATION_STATE_DIR:-/var/lib/erpnext-dev/operations}}"
NATIVE_ADVANCED_OPERATION_FILE=""
NATIVE_ADVANCED_OPERATION_ID=""
NATIVE_ADVANCED_STATUS=""
NATIVE_ADVANCED_CHECKPOINT=""
NATIVE_ADVANCED_RESULT=""
NATIVE_ADVANCED_RECOVERY=""
NATIVE_ADVANCED_PREFLIGHT=""
NATIVE_ADVANCED_REQUESTED=""
NATIVE_ADVANCED_RESOLVED=""
NATIVE_ADVANCED_LEDGER=""
NATIVE_ADVANCED_BACKUP="none"
NATIVE_ADVANCED_CONFIG_BASE=""
NATIVE_ADVANCED_SITE_CREATED=0
NATIVE_ADVANCED_STAGED_CONFIG=""

# Run every Phase 7.4 Frappe command in one bounded environment. The caller
# supplies only a trusted working directory and a script on stdin. "bootstrap"
# is used only while nvm itself is being installed; all later calls require and
# activate the configured Node version before the caller's script runs.
native_advanced_frappe_bash() {
  local workdir="${1:-}" mode="${2:-runtime}"
  [[ "$workdir" == "$FRAPPE_HOME" || "$workdir" == "$FRAPPE_HOME/"* ]] || return 1
  [[ "$workdir" != *$'\n'* && "$workdir" != *$'\r'* ]] || return 1
  [[ "$mode" == runtime || "$mode" == bootstrap ]] || return 1

  {
    printf '%s\n' 'set -Eeuo pipefail'
    printf 'export HOME=%q\n' "$FRAPPE_HOME"
    cat <<'EOF_NATIVE_ADVANCED_ENV'
unset CDPATH ENV BASH_ENV
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
unset NPM_CONFIG_USERCONFIG NPM_CONFIG_CACHE npm_config_userconfig npm_config_cache npm_config_prefix
unset YARN_RC_FILENAME YARN_CACHE_FOLDER YARN_GLOBAL_FOLDER YARN_CONFIG_DIR
unset PYTHONHOME PYTHONPATH PYTHONUSERBASE PIP_CONFIG_FILE PIP_CACHE_DIR
unset UV_CONFIG_FILE UV_CACHE_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR
unset GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL GIT_CONFIG_COUNT
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export YARN_RC_FILENAME="$XDG_CONFIG_HOME/yarn/yarnrc"
export YARN_CACHE_FOLDER="$XDG_CACHE_HOME/yarn"
export YARN_GLOBAL_FOLDER="$XDG_DATA_HOME/yarn"
export YARN_CONFIG_DIR="$XDG_CONFIG_HOME/yarn"
export PYTHONUSERBASE="$XDG_DATA_HOME/python"
export PIP_CONFIG_FILE="$XDG_CONFIG_HOME/pip/pip.conf"
export PIP_CACHE_DIR="$XDG_CACHE_HOME/pip"
export UV_CONFIG_FILE="$XDG_CONFIG_HOME/uv/uv.toml"
export UV_CACHE_DIR="$XDG_CACHE_HOME/uv"
export UV_TOOL_DIR="$XDG_DATA_HOME/uv/tools"
export UV_PYTHON_INSTALL_DIR="$XDG_DATA_HOME/uv/python"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL=/dev/null
export NVM_DIR="$HOME/.nvm"
mkdir -p "$XDG_CONFIG_HOME/npm" "$XDG_CONFIG_HOME/yarn" "$XDG_CONFIG_HOME/pip" "$XDG_CONFIG_HOME/uv" \
  "$NPM_CONFIG_CACHE" "$YARN_CACHE_FOLDER" "$YARN_GLOBAL_FOLDER" "$PIP_CACHE_DIR" "$UV_CACHE_DIR" \
  "$UV_TOOL_DIR" "$UV_PYTHON_INSTALL_DIR" "$PYTHONUSERBASE"
EOF_NATIVE_ADVANCED_ENV
    printf 'cd %q\n' "$workdir"
    if [[ "$mode" == runtime ]]; then
      cat <<EOF_NATIVE_ADVANCED_NVM
[[ -s "\$NVM_DIR/nvm.sh" ]] || { echo 'ERROR: verified nvm.sh is unavailable.' >&2; exit 1; }
# shellcheck disable=SC1090
source "\$NVM_DIR/nvm.sh"
nvm use --silent "${NODE_VERSION}" >/dev/null
command -v node >/dev/null
command -v npm >/dev/null
command -v yarn >/dev/null
EOF_NATIVE_ADVANCED_NVM
    fi
    cat
  } | frappe_login_bash
}

native_advanced_safe_directory() {
  local path="$1" owner expected_owner
  [[ -d "$path" && ! -L "$path" ]] || return 1
  [[ "$path" == "$FRAPPE_HOME" || "$path" == "$FRAPPE_HOME/"* ]] || return 1
  [[ "${ERPNEXT_DEV_NATIVE_ADVANCED_TEST:-0}" == 1 ]] && return 0
  owner="$(${SUDO:-} stat -c '%u' "$path" 2>/dev/null)" || return 1
  expected_owner="$(id -u "$FRAPPE_USER" 2>/dev/null)" || return 1
  [[ "$owner" == "$expected_owner" ]]
}

native_advanced_safe_regular_file() {
  local path="$1" owner expected_owner
  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$path" == "$FRAPPE_HOME/"* ]] || return 1
  [[ "${ERPNEXT_DEV_NATIVE_ADVANCED_TEST:-0}" == 1 ]] && return 0
  owner="$(${SUDO:-} stat -c '%u' "$path" 2>/dev/null)" || return 1
  expected_owner="$(id -u "$FRAPPE_USER" 2>/dev/null)" || return 1
  [[ "$owner" == "$expected_owner" ]]
}

native_advanced_safe_field() {
  [[ "${1:-}" =~ ^[\ A-Za-z0-9._,:@/+-]*$ && "${1:-}" != *$'\n'* && "${1:-}" != *$'\r'* ]]
}

native_advanced_state_prepare() {
  if [[ -L "$NATIVE_ADVANCED_STATE_DIR" || (-e "$NATIVE_ADVANCED_STATE_DIR" && ! -d "$NATIVE_ADVANCED_STATE_DIR") ]]; then
    err "Unsafe advanced-install operation-state directory."
    return 1
  fi
  ${SUDO:-} mkdir -p "$NATIVE_ADVANCED_STATE_DIR" || return 1
  ${SUDO:-} chmod 0700 "$NATIVE_ADVANCED_STATE_DIR" || return 1
  local mode owner
  mode="$(${SUDO:-} stat -c '%a' "$NATIVE_ADVANCED_STATE_DIR" 2>/dev/null)" || return 1
  owner="$(${SUDO:-} stat -c '%u' "$NATIVE_ADVANCED_STATE_DIR" 2>/dev/null)" || return 1
  [[ "$mode" == 700 ]] || return 1
  [[ "$owner" == 0 || "${ERPNEXT_DEV_NATIVE_ADVANCED_TEST:-0}" == 1 ]] || return 1
}

native_advanced_record_write() {
  local temp="${NATIVE_ADVANCED_OPERATION_FILE}.tmp.$$" value mode owner
  native_advanced_state_prepare || return 1
  [[ "$NATIVE_ADVANCED_OPERATION_FILE" == "$NATIVE_ADVANCED_STATE_DIR/"*.state ]] || return 1
  [[ ! -L "$NATIVE_ADVANCED_OPERATION_FILE" && ! -e "$temp" ]] || return 1
  if [[ -e "$NATIVE_ADVANCED_OPERATION_FILE" ]]; then
    [[ -f "$NATIVE_ADVANCED_OPERATION_FILE" && ! -L "$NATIVE_ADVANCED_OPERATION_FILE" ]] || return 1
    mode="$(${SUDO:-} stat -c '%a' "$NATIVE_ADVANCED_OPERATION_FILE" 2>/dev/null)" || return 1
    owner="$(${SUDO:-} stat -c '%u' "$NATIVE_ADVANCED_OPERATION_FILE" 2>/dev/null)" || return 1
    [[ "$mode" == 600 && ("$owner" == 0 || "${ERPNEXT_DEV_NATIVE_ADVANCED_TEST:-0}" == 1) ]] || return 1
  fi
  for value in "$NATIVE_ADVANCED_OPERATION_ID" "$SITE_NAME" "$NATIVE_ADVANCED_REQUESTED" "$NATIVE_ADVANCED_RESOLVED" \
    "$NATIVE_ADVANCED_STATUS" "$NATIVE_ADVANCED_CHECKPOINT" "$NATIVE_ADVANCED_RESULT" "$NATIVE_ADVANCED_RECOVERY" \
    "$NATIVE_ADVANCED_PREFLIGHT" "$NATIVE_ADVANCED_LEDGER" "$NATIVE_ADVANCED_BACKUP"; do
    native_advanced_safe_field "$value" || return 1
  done
  umask 077
  {
    printf 'schema=1\noperation_id=%s\noperation_type=native-advanced-installation\n' "$NATIVE_ADVANCED_OPERATION_ID"
    printf 'site=%s\nrequested_apps=%s\nresolved_apps=%s\n' "$SITE_NAME" "$NATIVE_ADVANCED_REQUESTED" "$NATIVE_ADVANCED_RESOLVED"
    printf 'status=%s\ncheckpoint=%s\nresult=%s\n' "$NATIVE_ADVANCED_STATUS" "$NATIVE_ADVANCED_CHECKPOINT" "$NATIVE_ADVANCED_RESULT"
    printf 'preflight_absence_fingerprint=%s\nartifact_ledger=%s\nbaseline_backup=%s\n' "$NATIVE_ADVANCED_PREFLIGHT" "$NATIVE_ADVANCED_LEDGER" "$NATIVE_ADVANCED_BACKUP"
    printf 'verification=exact-site-app-source-branch-runtime-inventory\nrecovery=%s\nupdated_at=%s\n' "$NATIVE_ADVANCED_RECOVERY" "$(planner_timestamp)"
  } >"$temp" || return 1
  ${SUDO:-} chmod 0600 "$temp" || return 1
  ${SUDO:-} mv -f "$temp" "$NATIVE_ADVANCED_OPERATION_FILE" || return 1
}

native_advanced_checkpoint() {
  NATIVE_ADVANCED_STATUS="$1"
  NATIVE_ADVANCED_CHECKPOINT="$2"
  NATIVE_ADVANCED_RESULT="${3:-pending}"
  native_advanced_record_write
}

native_advanced_ledger_add() {
  local artifact="$1"
  [[ ",${NATIVE_ADVANCED_LEDGER}," == *",${artifact},"* ]] || NATIVE_ADVANCED_LEDGER="${NATIVE_ADVANCED_LEDGER:+${NATIVE_ADVANCED_LEDGER},}${artifact}"
}

native_advanced_config_digest() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then printf 'absent\n'; return 0; fi
  [[ -f "$path" && ! -L "$path" ]] || return 1
  ${SUDO:-} sha256sum "$path" | awk '{print $1}'
}

native_advanced_config_snapshot() {
  local config legacy
  config="$(native_advanced_config_digest "$CONFIG_FILE")" || return 1
  legacy="$(native_advanced_config_digest "$LEGACY_CONFIG_FILE")" || return 1
  printf '%s' "$config|$legacy" | sha256sum | awk '{print $1}'
}

native_advanced_absence_fingerprint() {
  local config legacy
  config="$(native_advanced_config_digest "$CONFIG_FILE")" || return 1
  legacy="$(native_advanced_config_digest "$LEGACY_CONFIG_FILE")" || return 1
  [[ ! -e "$BENCH_PARENT" && ! -L "$BENCH_PARENT" && ! -e "$BENCH_DIR" && ! -L "$BENCH_DIR" ]] || return 1
  printf '%s' "native|$SITE_NAME|$BENCH_PARENT|$config|$legacy" | sha256sum | awk '{print $1}'
}

native_advanced_preflight() {
  [[ "$(effective_deployment_engine)" == native ]] || return 23
  validate_site_name_value "$SITE_NAME" || return 20
  [[ "$SITE_NAME" == "$QUICK_INSTALL_SITE" ]] || return 20
  [[ ! -e "$BENCH_PARENT" && ! -L "$BENCH_PARENT" ]] || return 21
  [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" && ! -e "$LEGACY_CONFIG_FILE" && ! -L "$LEGACY_CONFIG_FILE" ]] || return 21
  if [[ -d "$NATIVE_ADVANCED_STATE_DIR" ]]; then
    local existing
    existing="$(${SUDO:-} find "$NATIVE_ADVANCED_STATE_DIR" -maxdepth 1 -type f -name 'native-advanced-*.state' -print -quit 2>/dev/null || true)"
    [[ -z "$existing" ]] || return 34
  fi
  NATIVE_ADVANCED_PREFLIGHT="$(native_advanced_absence_fingerprint)" || return 21
  NATIVE_ADVANCED_CONFIG_BASE="$(native_advanced_config_snapshot)" || return 21
}

native_advanced_catalog_rows() {
  local app
  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    [[ "$app" == frappe ]] && continue
    load_validated_app_catalog_record "$app" || return 1
    printf '%s|%s|%s\n' "$LIB_APP_ID" "$LIB_APP_REPO" "${LIB_APP_BRANCH:-default}"
  done
}

native_advanced_plan() {
  local app
  printf 'Native Advanced Installation Plan\n'
  printf 'Profile: advanced\nEngine: native\nExact site: %s\n' "$SITE_NAME"
  printf 'Requested applications: %s\nResolved dependency closure: %s\n' "$NATIVE_ADVANCED_REQUESTED" "$NATIVE_ADVANCED_RESOLVED"
  printf 'Application installation order: %s\n' "$NATIVE_ADVANCED_RESOLVED"
  printf 'Catalog acquisition records:\n'
  while IFS='|' read -r app repo branch; do printf '  %s repository=%s ref=%s\n' "$app" "$repo" "$branch"; done < <(native_advanced_catalog_rows)
  printf 'Checkpoints: preflight,prerequisites,frappe-user,bench-created,site-created,baseline-backup,app-acquisition,app-installation,migration,assets,services,readiness,inventory,configuration-promotion,post-promotion-reconciliation\n'
  printf 'Creates: Frappe user/home, Bench, exact site, curated app code, Native service, private operation record, promoted configuration\n'
  printf 'Baseline backup: after site creation and before any application acquisition; creation and verification are mandatory\n'
  printf 'Configuration promotion: only after exact runtime, source, branch, and inventory verification\n'
  printf 'Verification: exact site, Frappe, resolved apps, source/ref, migrate, assets, Native services, readiness, inventory reconciliation\n'
  printf 'Failure/recovery: pre-site failures preserve the last checkpoint; post-site failures are recovery-required and retain all evidence\n'
  printf 'No adoption, custom repositories, Docker mutation, automatic resume, or broad cleanup is included.\n'
}

native_advanced_confirm() {
  local reply
  [[ "${ASSUME_YES:-0}" -eq 1 ]] && return 0
  [[ -t 0 || "${ERPNEXT_DEV_TEST_INTERACTIVE:-0}" == 1 ]] || return 1
  read -r -p "Execute this exact Native advanced plan? [y/N]: " reply || return 1
  [[ "${reply,,}" == y || "${reply,,}" == yes ]]
}

native_advanced_phase() {
  local checkpoint="$1" function="$2" rc phase_status=mutation-in-progress
  shift 2
  NATIVE_ADVANCED_CHECKPOINT="$checkpoint"
  case "$checkpoint" in
    readiness|inventory|post-promotion-reconciliation) phase_status=verification ;;
  esac
  native_advanced_checkpoint "$phase_status" "$checkpoint" pending || return 31
  if [[ "${NATIVE_ADVANCED_FAIL_AT:-}" == "$checkpoint" ]]; then rc=1; else "$function" "$@" || rc=$?; fi
  if [[ "${rc:-0}" -ne 0 ]]; then
    NATIVE_ADVANCED_RESULT=failed
    if [[ "$NATIVE_ADVANCED_SITE_CREATED" -eq 1 ]]; then
      NATIVE_ADVANCED_STATUS=recovery-required
      NATIVE_ADVANCED_RECOVERY="inspect-record,verify-backup,repair-from-${checkpoint}"
      native_advanced_record_write || true
      return 33
    fi
    NATIVE_ADVANCED_STATUS=failed
    NATIVE_ADVANCED_RECOVERY="inspect-record,correct-${checkpoint},restart-fresh-only-if-target-absent"
    native_advanced_record_write || true
    return 31
  fi
  return 0
}

native_advanced_prerequisites() {
  install_self_for_reuse && check_os && check_internet && verify_clock_and_repository_readiness \
    && check_resources && install_system_packages && configure_sysctl_for_redis
}

native_advanced_user_setup() {
  prepare_passwords
  create_frappe_user && create_mariadb_admin_user && fix_frappe_ownership
}

native_advanced_toolchain_setup() {
  local rc=0
  if native_advanced_frappe_bash "$FRAPPE_HOME" bootstrap <<EOF_NATIVE_ADVANCED_TOOLCHAIN
if [[ ! -s "\$NVM_DIR/nvm.sh" ]]; then
  git clone --depth 1 --branch "v${NVM_VERSION}" https://github.com/nvm-sh/nvm.git "\$NVM_DIR"
fi
[[ -s "\$NVM_DIR/nvm.sh" ]]
source "\$NVM_DIR/nvm.sh"
nvm install "${NODE_VERSION}"
nvm use "${NODE_VERSION}"
nvm alias default "${NODE_VERSION}"
npm install -g yarn
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
fi
export PATH="\$HOME/.local/bin:\$PATH"
uv python install "${PYTHON_VERSION}" --default
if [[ -n "${BENCH_VERSION}" ]]; then uv tool install "frappe-bench==${BENCH_VERSION}" --force; else uv tool install frappe-bench --force; fi
EOF_NATIVE_ADVANCED_TOOLCHAIN
  then
    :
  else
    rc=$?
    return "$rc"
  fi
  # Prove availability in a new noninteractive Frappe process. This cannot
  # inherit the bootstrap shell's PATH or sourced nvm functions.
  native_advanced_frappe_bash "$FRAPPE_HOME" <<EOF_NATIVE_ADVANCED_TOOLCHAIN_VERIFY
node_version="\$(node --version)"
[[ "\${node_version#v}" == "${NODE_VERSION}".* || "\${node_version#v}" == "${NODE_VERSION}" ]]
npm --version
yarn --version
uv --version
python_version="\$(python3 --version)"
[[ "\${python_version#Python }" == "${PYTHON_VERSION}".* || "\${python_version#Python }" == "${PYTHON_VERSION}" ]]
bench_version="\$(bench --version)"
[[ -n "\$bench_version" ]]
EOF_NATIVE_ADVANCED_TOOLCHAIN_VERIFY
}

native_advanced_bench_create() {
  local rc=0
  if native_advanced_frappe_bash "$FRAPPE_HOME" <<EOF_NATIVE_ADVANCED_BENCH
mkdir -p "${BENCH_PARENT}"
cd "${BENCH_PARENT}"
bench init "${BENCH_NAME}" --frappe-branch "${FRAPPE_BRANCH}"
EOF_NATIVE_ADVANCED_BENCH
  then
    :
  else
    rc=$?
    [[ ! -e "$BENCH_DIR" && ! -L "$BENCH_DIR" ]] || native_advanced_ledger_add partial-bench
    return "$rc"
  fi
  native_advanced_safe_directory "$BENCH_DIR" || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_safe_directory "$BENCH_DIR/apps/frappe" || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_safe_directory "$BENCH_DIR/env" || { native_advanced_ledger_add partial-bench; return 1; }
  [[ -f "$BENCH_DIR/env/bin/python" && -x "$BENCH_DIR/env/bin/python" ]] || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_safe_directory "$BENCH_DIR/sites" || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_safe_regular_file "$BENCH_DIR/sites/apps.txt" || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_safe_regular_file "$BENCH_DIR/sites/common_site_config.json" || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_safe_regular_file "$BENCH_DIR/Procfile" || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_frappe_bash "$BENCH_DIR" <<'EOF_NATIVE_ADVANCED_BENCH_VERIFY' || { native_advanced_ledger_add partial-bench; return 1; }
bench --version
bench version
./env/bin/python --version
EOF_NATIVE_ADVANCED_BENCH_VERIFY
  native_advanced_ledger_add bench
}

native_advanced_site_create() {
  local old_xtrace=0 rc=0
  [[ $- == *x* ]] && old_xtrace=1 && set +x
  if native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_SITE_CREATE
bench new-site "${SITE_NAME}" --admin-password "${ADMIN_PASSWORD}" --db-root-username "${DB_ADMIN_USER}" --db-root-password "${DB_ADMIN_PASSWORD}"
EOF_NATIVE_ADVANCED_SITE_CREATE
  then
    :
  else
    rc=$?
    [[ ! -e "$BENCH_DIR/sites/$SITE_NAME" && ! -L "$BENCH_DIR/sites/$SITE_NAME" ]] || native_advanced_ledger_add partial-site
    ((old_xtrace == 0)) || set -x
    return "$rc"
  fi
  native_advanced_safe_directory "$BENCH_DIR/sites/$SITE_NAME" || { native_advanced_ledger_add partial-site; ((old_xtrace == 0)) || set -x; return 1; }
  native_advanced_safe_regular_file "$BENCH_DIR/sites/$SITE_NAME/site_config.json" || { native_advanced_ledger_add partial-site; ((old_xtrace == 0)) || set -x; return 1; }
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_SITE_VERIFY || { native_advanced_ledger_add partial-site; ((old_xtrace == 0)) || set -x; return 1; }
bench --site "${SITE_NAME}" show-config >/dev/null
EOF_NATIVE_ADVANCED_SITE_VERIFY
  NATIVE_ADVANCED_SITE_CREATED=1
  native_advanced_ledger_add site
  if native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_SITE_CONFIG
bench use "${SITE_NAME}"
bench set-config -g default_site "${SITE_NAME}"
bench set-config -g serve_default_site true
EOF_NATIVE_ADVANCED_SITE_CONFIG
  then
    :
  else
    rc=$?
    ((old_xtrace == 0)) || set -x
    return "$rc"
  fi
  ((old_xtrace == 0)) || set -x
}

native_advanced_baseline_backup() {
  local latest prefix db_file public_file private_file config_file completeness
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_BACKUP || return 1
bench --site "${SITE_NAME}" backup --with-files
EOF_NATIVE_ADVANCED_BACKUP
  latest="$(backup_latest_set_paths 2>/dev/null)" || return 1
  prefix="$(sed -n '1p' <<<"$latest")"
  db_file="$(sed -n '2p' <<<"$latest")"
  public_file="$(sed -n '3p' <<<"$latest")"
  private_file="$(sed -n '4p' <<<"$latest")"
  config_file="$(sed -n '5p' <<<"$latest")"
  completeness="$(sed -n '6p' <<<"$latest")"
  [[ -n "$prefix" && "$completeness" == complete ]] || return 1
  {
    printf 'db_file=%q\npublic_file=%q\nprivate_file=%q\nconfig_file=%q\n' "$db_file" "$public_file" "$private_file" "$config_file"
    cat <<'EOF_NATIVE_ADVANCED_BACKUP_VERIFY'
gzip -t "$db_file"
tar -tf "$public_file" >/dev/null
tar -tf "$private_file" >/dev/null
python3 -m json.tool "$config_file" >/dev/null
EOF_NATIVE_ADVANCED_BACKUP_VERIFY
  } | native_advanced_frappe_bash "$BENCH_DIR" || return 1
  NATIVE_ADVANCED_BACKUP="verified-baseline"
  native_advanced_ledger_add baseline-backup
}

native_advanced_get_app() {
  local app="$1" repo branch
  load_validated_app_catalog_record "$app" || return 1
  [[ "$LIB_APP_ID" == "$app" && "$app" != frappe ]] || return 1
  repo="$LIB_APP_REPO"; branch="$LIB_APP_BRANCH"
  if [[ -n "$branch" ]]; then
    native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_GET
bench get-app --branch "${branch}" "${app}" "${repo}"
EOF_NATIVE_ADVANCED_GET
  else
    native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_GET_DEFAULT
bench get-app "${app}" "${repo}"
EOF_NATIVE_ADVANCED_GET_DEFAULT
  fi
  native_advanced_safe_directory "$BENCH_DIR/apps/$app" || return 1
  native_advanced_ledger_add "code:$app"
}

native_advanced_install_app() {
  local app="$1" installed
  [[ "$app" != frappe ]] || return 0
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_INSTALL
bench --site "${SITE_NAME}" install-app "${app}"
EOF_NATIVE_ADVANCED_INSTALL
  installed="$(native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_INSTALL_VERIFY
bench --site "${SITE_NAME}" list-apps
EOF_NATIVE_ADVANCED_INSTALL_VERIFY
  )" || return 1
  awk '{print $1}' <<<"$installed" | grep -Fxq "$app" || return 1
  native_advanced_ledger_add "site-app:$app"
}

native_advanced_migrate() {
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_MIGRATE
bench --site "${SITE_NAME}" migrate
EOF_NATIVE_ADVANCED_MIGRATE
}
native_advanced_assets() {
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_ASSETS
bench build
bench --site "${SITE_NAME}" clear-cache
bench --site "${SITE_NAME}" clear-website-cache
EOF_NATIVE_ADVANCED_ASSETS
}
native_advanced_services() {
  create_start_helper && create_erpnext_service && enable_autostart_service && start_erpnext_service
}
native_advanced_readiness() {
  wait_for_erpnext_ready && settle_stack_after_install
}

native_advanced_verify() {
  local app repo branch actual_repo actual_branch installed
  [[ -d "$BENCH_DIR/sites/$SITE_NAME" && -d "$BENCH_DIR/apps/frappe" ]] || return 1
  installed="$(native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_INVENTORY
bench --site "${SITE_NAME}" list-apps
EOF_NATIVE_ADVANCED_INVENTORY
  )" || return 1
  installed="$(awk '{print $1}' <<<"$installed")"
  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    grep -Fxq "$app" <<<"$installed" || return 1
    [[ -d "$BENCH_DIR/apps/$app" ]] || return 1
    [[ "$app" == frappe ]] && continue
    load_validated_app_catalog_record "$app" || return 1
    repo="${LIB_APP_REPO%/}"; branch="$LIB_APP_BRANCH"
    actual_repo="$(native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_GIT_REMOTE
git -C "apps/${app}" remote get-url origin
EOF_NATIVE_ADVANCED_GIT_REMOTE
    )" || return 1
    [[ "${actual_repo%.git}" == "${repo%.git}" ]] || return 1
    if [[ -n "$branch" ]]; then
      actual_branch="$(native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_GIT_BRANCH
git -C "apps/${app}" symbolic-ref --short HEAD
EOF_NATIVE_ADVANCED_GIT_BRANCH
      )" || return 1
      [[ "$actual_branch" == "$branch" ]] || return 1
    fi
  done
}

native_advanced_stage_config() {
  [[ "$(native_advanced_config_snapshot)" == "$NATIVE_ADVANCED_CONFIG_BASE" ]] || return 1
  NATIVE_ADVANCED_STAGED_CONFIG="$NATIVE_ADVANCED_STATE_DIR/${NATIVE_ADVANCED_OPERATION_ID}.config"
  [[ ! -e "$NATIVE_ADVANCED_STAGED_CONFIG" && ! -L "$NATIVE_ADVANCED_STAGED_CONFIG" ]] || return 1
  umask 077
  {
    printf '# ERPNext Developer Toolkit schema-2 configuration\nCONFIG_SCHEMA=2\n'
    printf 'SITE_NAME=%s\nDEPLOYMENT_MODE=%s\nDEPLOYMENT_ENGINE=native\n' "$SITE_NAME" "${DEPLOYMENT_MODE:-development}"
    printf 'INSTALLATION_PROFILE=advanced\nINSTALLATION_PROFILE_APPS=%s\n' "$NATIVE_ADVANCED_REQUESTED"
    printf 'FRAPPE_USER=%s\nBENCH_PARENT=%s\nBENCH_NAME=%s\nBENCH_DIR=%s\n' "$FRAPPE_USER" "$BENCH_PARENT" "$BENCH_NAME" "$BENCH_DIR"
  } >"$NATIVE_ADVANCED_STAGED_CONFIG"
  chmod 0600 "$NATIVE_ADVANCED_STAGED_CONFIG"
  native_advanced_ledger_add staged-config
}

native_advanced_promote_config() {
  local current primary_tmp legacy_tmp
  current="$(native_advanced_config_snapshot)" || return 1
  [[ "$current" == "$NATIVE_ADVANCED_CONFIG_BASE" ]] || return 1
  [[ -f "$NATIVE_ADVANCED_STAGED_CONFIG" && ! -L "$NATIVE_ADVANCED_STAGED_CONFIG" ]] || return 1
  ${SUDO:-} mkdir -p "$(dirname "$CONFIG_FILE")" "$(dirname "$LEGACY_CONFIG_FILE")" || return 1
  primary_tmp="$(${SUDO:-} mktemp "${CONFIG_FILE}.tmp.XXXXXX")" || return 1
  ${SUDO:-} cp "$NATIVE_ADVANCED_STAGED_CONFIG" "$primary_tmp" || return 1
  ${SUDO:-} chown root:root "$primary_tmp" 2>/dev/null || true
  ${SUDO:-} chmod 0600 "$primary_tmp" || return 1
  ${SUDO:-} mv -f "$primary_tmp" "$CONFIG_FILE" || return 1
  if [[ "$LEGACY_CONFIG_FILE" != "$CONFIG_FILE" ]]; then
    legacy_tmp="$(${SUDO:-} mktemp "${LEGACY_CONFIG_FILE}.tmp.XXXXXX")" || return 1
    ${SUDO:-} cp "$NATIVE_ADVANCED_STAGED_CONFIG" "$legacy_tmp" || return 1
    ${SUDO:-} chmod 0600 "$legacy_tmp" || return 1
    ${SUDO:-} mv -f "$legacy_tmp" "$LEGACY_CONFIG_FILE" || return 1
  fi
  native_advanced_ledger_add active-config
}

native_advanced_post_reconcile() {
  grep -Fxq 'CONFIG_SCHEMA=2' "$CONFIG_FILE" && grep -Fxq 'INSTALLATION_PROFILE=advanced' "$CONFIG_FILE" \
    && grep -Fxq "INSTALLATION_PROFILE_APPS=$NATIVE_ADVANCED_REQUESTED" "$CONFIG_FILE" \
    && native_advanced_verify
}

native_advanced_install() {
  local rc app original_fingerprint
  SITE_NAME="$QUICK_INSTALL_SITE"
  validate_site_name_value "$SITE_NAME" || { planner_exit_code invalid-input; return $?; }
  profile_plan_parse_requested_apps "$INSTALLATION_PROFILE_APPS_RAW" || { err "$PROFILE_PLAN_ERROR"; planner_exit_code invalid-input; return $?; }
  profile_plan_resolve_apps advanced || { err "$PROFILE_PLAN_ERROR"; planner_exit_code incompatible; return $?; }
  NATIVE_ADVANCED_REQUESTED="$PROFILE_PLAN_REQUESTED_CSV"
  NATIVE_ADVANCED_RESOLVED="$PROFILE_PLAN_DESIRED_CSV"
  if [[ "$(effective_deployment_engine)" == docker ]]; then
    err "Native advanced installation is unsupported for Docker; Phase 7.5 is deferred."
    planner_exit_code unsupported; return $?
  fi
  native_advanced_preflight || { rc=$?; planner_exit_code "$([[ $rc == 34 ]] && echo conflict || [[ $rc == 23 ]] && echo unsupported || echo ambiguous-target)"; return $?; }
  original_fingerprint="$NATIVE_ADVANCED_PREFLIGHT"
  native_advanced_plan
  if [[ "${QUICK_INSTALL_PREVIEW:-0}" -eq 1 ]]; then planner_exit_code preview; return $?; fi
  native_advanced_confirm || { echo "Installation cancelled before mutation."; planner_exit_code cancelled; return $?; }
  require_sudo
  [[ "$(native_advanced_absence_fingerprint)" == "$original_fingerprint" ]] || { err "Target or configuration changed after confirmation; refusing mutation."; planner_exit_code conflict; return $?; }

  NATIVE_ADVANCED_OPERATION_ID="native-advanced-${NATIVE_ADVANCED_OPERATION_ID_OVERRIDE:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
  NATIVE_ADVANCED_OPERATION_FILE="$NATIVE_ADVANCED_STATE_DIR/${NATIVE_ADVANCED_OPERATION_ID}.state"
  NATIVE_ADVANCED_STATUS=started; NATIVE_ADVANCED_CHECKPOINT=preflight; NATIVE_ADVANCED_RESULT=pending
  NATIVE_ADVANCED_RECOVERY="inspect-record,retry-only-if-target-absent"
  native_advanced_record_write || { planner_exit_code mutation-failed; return $?; }
  trap 'native_advanced_signal INT; exit 130' INT
  trap 'native_advanced_signal TERM; exit 130' TERM

  native_advanced_phase prerequisites native_advanced_prerequisites || return $?
  native_advanced_phase frappe-user native_advanced_user_setup || return $?
  native_advanced_phase frappe-environment native_advanced_toolchain_setup || return $?
  native_advanced_phase bench-created native_advanced_bench_create || return $?
  native_advanced_phase site-created native_advanced_site_create || return $?
  native_advanced_phase baseline-backup native_advanced_baseline_backup || return $?
  native_advanced_phase configuration-staging native_advanced_stage_config || return $?
  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    [[ "$app" == frappe ]] && continue
    native_advanced_phase "get-app:$app" native_advanced_get_app "$app" || return $?
  done
  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    [[ "$app" == frappe ]] && continue
    native_advanced_phase "install-app:$app" native_advanced_install_app "$app" || return $?
  done
  native_advanced_phase migration native_advanced_migrate || return $?
  native_advanced_phase assets native_advanced_assets || return $?
  native_advanced_phase services native_advanced_services || return $?
  native_advanced_phase readiness native_advanced_readiness || return $?
  native_advanced_phase inventory native_advanced_verify || return $?
  native_advanced_phase configuration-promotion native_advanced_promote_config || return $?
  native_advanced_phase post-promotion-reconciliation native_advanced_post_reconcile || return $?
  NATIVE_ADVANCED_STATUS=completed; NATIVE_ADVANCED_CHECKPOINT=completed; NATIVE_ADVANCED_RESULT=success
  NATIVE_ADVANCED_RECOVERY="baseline-backup-verified,no-recovery-required"
  native_advanced_record_write || { planner_exit_code recovery-required; return $?; }
  trap - INT TERM
  ok "Native advanced installation completed and reconciled."
}

native_advanced_signal() {
  local signal="$1"
  NATIVE_ADVANCED_RESULT="interrupted-$signal"
  if [[ "$NATIVE_ADVANCED_SITE_CREATED" -eq 1 ]]; then
    NATIVE_ADVANCED_STATUS=recovery-required
    NATIVE_ADVANCED_RECOVERY="inspect-record,verify-baseline-backup,resume-manually-from-${NATIVE_ADVANCED_CHECKPOINT}"
  else
    NATIVE_ADVANCED_STATUS=failed
    NATIVE_ADVANCED_RECOVERY="inspect-record,remove-only-proven-private-staging,retry-if-target-absent"
  fi
  native_advanced_record_write || true
  trap - INT TERM
  return 130
}
