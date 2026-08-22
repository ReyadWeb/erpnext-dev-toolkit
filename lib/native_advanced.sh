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
NATIVE_ADVANCED_RECORDS_BASE=""
NATIVE_ADVANCED_PDF_CAPABILITY="unknown"
NATIVE_ADVANCED_STARTED_EPOCH=0

# Run every Phase 7.4 Frappe command in one bounded environment. The caller
# supplies only a trusted working directory and a script on stdin. "bootstrap"
# is used only while nvm itself is being installed; all later calls require and
# activate the configured Node version before the caller's script runs.
native_advanced_frappe_login_bash() {
  local clean_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  if [[ "${EUID}" -eq 0 ]]; then
    command -v runuser >/dev/null || return 1
    runuser --user "$FRAPPE_USER" -- /usr/bin/env -i HOME="$FRAPPE_HOME" USER="$FRAPPE_USER" \
      LOGNAME="$FRAPPE_USER" SHELL=/bin/bash PATH="$clean_path" /bin/bash --noprofile --norc
  else
    sudo -H -u "$FRAPPE_USER" env -i HOME="$FRAPPE_HOME" USER="$FRAPPE_USER" LOGNAME="$FRAPPE_USER" \
      SHELL=/bin/bash PATH="$clean_path" /bin/bash --noprofile --norc
  fi
}

native_advanced_frappe_bash() {
  local workdir="${1:-}" mode="${2:-runtime}"
  [[ "$workdir" == "$FRAPPE_HOME" || "$workdir" == "$FRAPPE_HOME/"* ]] || return 1
  [[ "$workdir" != *$'\n'* && "$workdir" != *$'\r'* ]] || return 1
  [[ "$mode" == runtime || "$mode" == bootstrap ]] || return 1

  {
    printf '%s\n' 'set -Eeuo pipefail'
    printf 'export HOME=%q\n' "$FRAPPE_HOME"
    printf 'export USER=%q LOGNAME=%q\n' "$FRAPPE_USER" "$FRAPPE_USER"
    printf '%s\n' 'export SHELL=/bin/bash'
    cat <<'EOF_NATIVE_ADVANCED_ENV'
unset CDPATH ENV BASH_ENV
unset NODE_PATH NODE_OPTIONS COREPACK_HOME
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
unset NPM_CONFIG_USERCONFIG NPM_CONFIG_CACHE npm_config_userconfig npm_config_cache npm_config_prefix
unset YARN_RC_FILENAME YARN_CACHE_FOLDER YARN_GLOBAL_FOLDER YARN_CONFIG_DIR
unset PYTHONHOME PYTHONPATH PYTHONUSERBASE PIP_CONFIG_FILE PIP_CACHE_DIR
unset UV_CONFIG_FILE UV_CACHE_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR UV_PYTHON_BIN_DIR UV_INSTALL_DIR UV_UNMANAGED_INSTALL
unset GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL GIT_CONFIG_COUNT
while IFS='=' read -r inherited_name _; do
  case "$inherited_name" in
    NPM_CONFIG_*|npm_config_*|YARN_*|PYTHON*|PIP_*|UV_*|GIT_CONFIG_*) unset "$inherited_name" 2>/dev/null || true ;;
  esac
done < <(env)
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
export UV_NO_CONFIG=1
export UV_NO_SYSTEM_CONFIG=1
export UV_NO_ENV_FILE=1
export UV_NO_MODIFY_PATH=1
export UV_INSTALL_DIR="$HOME/.local/bin"
export UV_CACHE_DIR="$XDG_CACHE_HOME/uv"
export UV_TOOL_DIR="$XDG_DATA_HOME/uv/tools"
export UV_PYTHON_INSTALL_DIR="$XDG_DATA_HOME/uv/python"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL=/dev/null
export NVM_DIR="$HOME/.nvm"
umask 077
mkdir -p "$HOME/.local/bin" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" \
  "$XDG_CONFIG_HOME/npm" "$XDG_CONFIG_HOME/yarn" "$XDG_CONFIG_HOME/pip" "$XDG_CONFIG_HOME/uv" \
  "$NPM_CONFIG_CACHE" "$YARN_CACHE_FOLDER" "$YARN_GLOBAL_FOLDER" "$PIP_CACHE_DIR" "$UV_CACHE_DIR" \
  "$UV_TOOL_DIR" "$UV_PYTHON_INSTALL_DIR" "$PYTHONUSERBASE"
for private_dir in "$HOME/.local/bin" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" \
  "$XDG_CONFIG_HOME/npm" "$XDG_CONFIG_HOME/yarn" "$XDG_CONFIG_HOME/pip" "$XDG_CONFIG_HOME/uv" \
  "$NPM_CONFIG_CACHE" "$YARN_CACHE_FOLDER" "$YARN_GLOBAL_FOLDER" "$PIP_CACHE_DIR" "$UV_CACHE_DIR" \
  "$UV_TOOL_DIR" "$UV_PYTHON_INSTALL_DIR" "$PYTHONUSERBASE"; do
  [[ -d "$private_dir" && ! -L "$private_dir" && -O "$private_dir" ]]
  chmod 0700 "$private_dir"
done
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
  } | native_advanced_frappe_login_bash
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

native_advanced_record_field() {
  local file="$1" key="$2"
  ${SUDO:-} awk -F= -v key="$key" '$1 == key { count++; value=$0; sub(/^[^=]*=/, "", value) } END { if (count == 1) print value; else exit 1 }' "$file" 2>/dev/null
}

native_advanced_record_is_safe_prerequisite_failure() {
  local file="$1" mode owner expected_owner key value operation_id fingerprint verification recovery updated_at
  [[ "$file" == "$NATIVE_ADVANCED_STATE_DIR/"native-advanced-*.state ]] || return 1
  [[ -f "$file" && ! -L "$file" ]] || return 1
  mode="$(${SUDO:-} stat -c '%a' "$file" 2>/dev/null)" || return 1
  owner="$(${SUDO:-} stat -c '%u' "$file" 2>/dev/null)" || return 1
  expected_owner=0
  [[ "${ERPNEXT_DEV_NATIVE_ADVANCED_TEST:-0}" != 1 ]] || expected_owner="$(id -u)"
  [[ "$mode" == 600 && "$owner" == "$expected_owner" ]] || return 1

  ${SUDO:-} awk -F= '
    BEGIN {
      allowed["schema"]; allowed["operation_id"]; allowed["operation_type"]; allowed["site"]
      allowed["requested_apps"]; allowed["resolved_apps"]; allowed["status"]; allowed["checkpoint"]
      allowed["result"]; allowed["preflight_absence_fingerprint"]; allowed["artifact_ledger"]
      allowed["baseline_backup"]; allowed["verification"]; allowed["recovery"]; allowed["updated_at"]
    }
    NF < 2 || !($1 in allowed) || seen[$1]++ { exit 1 }
    END { if (NR != 15) exit 1; for (key in allowed) if (seen[key] != 1) exit 1 }
  ' "$file" || return 1

  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || return 1
    native_advanced_safe_field "$value" || return 1
  done < <(${SUDO:-} cat "$file")

  [[ "$(native_advanced_record_field "$file" schema)" == 1 ]] || return 1
  [[ "$(native_advanced_record_field "$file" operation_type)" == native-advanced-installation ]] || return 1
  operation_id="$(native_advanced_record_field "$file" operation_id)" || return 1
  [[ "$(basename "$file")" == "${operation_id}.state" ]] || return 1
  [[ "$(native_advanced_record_field "$file" status)" == failed ]] || return 1
  [[ "$(native_advanced_record_field "$file" checkpoint)" == prerequisites ]] || return 1
  [[ "$(native_advanced_record_field "$file" result)" == failed ]] || return 1
  [[ -z "$(native_advanced_record_field "$file" artifact_ledger)" ]] || return 1
  [[ "$(native_advanced_record_field "$file" baseline_backup)" == none ]] || return 1
  [[ "$(native_advanced_record_field "$file" site)" == "$SITE_NAME" ]] || return 1
  [[ "$(native_advanced_record_field "$file" requested_apps)" == "$NATIVE_ADVANCED_REQUESTED" ]] || return 1
  [[ "$(native_advanced_record_field "$file" resolved_apps)" == "$NATIVE_ADVANCED_RESOLVED" ]] || return 1
  fingerprint="$(native_advanced_record_field "$file" preflight_absence_fingerprint)" || return 1
  verification="$(native_advanced_record_field "$file" verification)" || return 1
  recovery="$(native_advanced_record_field "$file" recovery)" || return 1
  updated_at="$(native_advanced_record_field "$file" updated_at)" || return 1
  [[ "$fingerprint" =~ ^[a-f0-9]{64}$ ]] || return 1
  [[ "$verification" == exact-site-app-source-branch-runtime-inventory ]] || return 1
  [[ "$recovery" == inspect-record,correct-prerequisites,restart-fresh-only-if-target-absent ]] || return 1
  [[ "$updated_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
}

native_advanced_state_directory_safe_readonly() {
  local mode owner expected_owner
  [[ -d "$NATIVE_ADVANCED_STATE_DIR" && ! -L "$NATIVE_ADVANCED_STATE_DIR" ]] || return 1
  mode="$(${SUDO:-} stat -c '%a' "$NATIVE_ADVANCED_STATE_DIR" 2>/dev/null)" || return 1
  owner="$(${SUDO:-} stat -c '%u' "$NATIVE_ADVANCED_STATE_DIR" 2>/dev/null)" || return 1
  expected_owner=0
  [[ "${ERPNEXT_DEV_NATIVE_ADVANCED_TEST:-0}" != 1 ]] || expected_owner="$(id -u)"
  [[ "$mode" == 700 && "$owner" == "$expected_owner" ]]
}

native_advanced_retry_records_validate() {
  local path found=0
  [[ -e "$NATIVE_ADVANCED_STATE_DIR" || -L "$NATIVE_ADVANCED_STATE_DIR" ]] || return 0
  native_advanced_state_directory_safe_readonly || return 1
  shopt -s nullglob
  for path in "$NATIVE_ADVANCED_STATE_DIR"/native-advanced-*; do
    found=1
    [[ "$(basename "$path")" =~ ^native-advanced-[A-Za-z0-9._+-]+\.state$ ]] || { shopt -u nullglob; return 1; }
    native_advanced_record_is_safe_prerequisite_failure "$path" || { shopt -u nullglob; return 1; }
  done
  shopt -u nullglob
  [[ "$found" -eq 1 ]] || return 0
  [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" && ! -e "$LEGACY_CONFIG_FILE" && ! -L "$LEGACY_CONFIG_FILE" ]] || return 1
  [[ ! -e "$BENCH_PARENT" && ! -L "$BENCH_PARENT" && ! -e "$BENCH_DIR" && ! -L "$BENCH_DIR" ]] || return 1
}

native_advanced_records_snapshot() {
  local path found=0
  [[ -d "$NATIVE_ADVANCED_STATE_DIR" && ! -L "$NATIVE_ADVANCED_STATE_DIR" ]] || { printf 'absent\n'; return 0; }
  shopt -s nullglob
  for path in "$NATIVE_ADVANCED_STATE_DIR"/native-advanced-*.state; do
    found=1
    printf '%s ' "$(basename "$path")"
    ${SUDO:-} sha256sum "$path" | awk '{print $1}'
  done
  shopt -u nullglob
  [[ "$found" -eq 1 ]] || printf 'empty\n'
}

native_advanced_print_prerequisite_retry() {
  validate_site_name_value "$SITE_NAME" || return 1
  [[ "$NATIVE_ADVANCED_REQUESTED" =~ ^[a-z][a-z0-9_]*(,[a-z][a-z0-9_]*)*$ ]] || return 1
  echo "Correct system time, network, and APT repository readiness, then rerun this exact Native advanced request:" >&2
  printf '  sudo erpnext-dev install --profile advanced --apps %s --site %s\n' "$NATIVE_ADVANCED_REQUESTED" "$SITE_NAME" >&2
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
  native_advanced_retry_records_validate || return 34
  [[ ! -e "$BENCH_PARENT" && ! -L "$BENCH_PARENT" ]] || return 21
  [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" && ! -e "$LEGACY_CONFIG_FILE" && ! -L "$LEGACY_CONFIG_FILE" ]] || return 21
  NATIVE_ADVANCED_RECORDS_BASE="$(native_advanced_records_snapshot)" || return 34
  NATIVE_ADVANCED_PREFLIGHT="$(native_advanced_absence_fingerprint)" || return 21
  NATIVE_ADVANCED_CONFIG_BASE="$(native_advanced_config_snapshot)" || return 21
}

native_advanced_catalog_rows() {
  local app
  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    [[ "$app" == frappe ]] && continue
    load_validated_app_catalog_record "$app" || return 1
    printf '%s|%s|%s|%s\n' "$LIB_APP_ID" "$LIB_APP_REPO" "${LIB_APP_BRANCH:-default}" "$LIB_APP_COMMIT"
  done
}

native_advanced_catalog_validate_runtime() {
  local app frappe_major
  [[ "$FRAPPE_BRANCH" =~ ^version-([0-9]+)$ ]] || return 1
  frappe_major="${BASH_REMATCH[1]}"
  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    load_validated_app_catalog_record "$app" || return 1
    [[ "$LIB_APP_NATIVE_SUPPORT" == supported ]] || return 1
    [[ -n "$LIB_APP_REPO" && -n "$LIB_APP_BRANCH" ]] || return 1
    [[ "$LIB_APP_COMMIT" =~ ^[a-f0-9]{40}$ ]] || return 1
    [[ ",${LIB_APP_SUPPORTED_FRAPPE}," == *",${frappe_major},"* ]] || return 1
    [[ "$app" == frappe || "$LIB_APP_QUICK_INSTALL" == supported ]] || return 1
  done
}

native_advanced_remote_pin_matches() {
  local app="$1" remote
  load_validated_app_catalog_record "$app" || return 1
  remote="$(env -i HOME=/nonexistent XDG_CONFIG_HOME=/nonexistent PATH=/usr/local/bin:/usr/bin:/bin \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null \
    git ls-remote "$LIB_APP_REPO" "refs/heads/$LIB_APP_BRANCH" 2>/dev/null | awk 'NR == 1 { print $1 }')" || return 1
  [[ "$remote" == "$LIB_APP_COMMIT" ]]
}

native_advanced_verify_upstream_pins() {
  local app
  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    native_advanced_remote_pin_matches "$app" || return 1
  done
}

native_advanced_runtime_coordinates_validate() {
  [[ "$FRAPPE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
  if [[ "${ERPNEXT_DEV_NATIVE_ADVANCED_TEST:-0}" == 1 ]]; then
    [[ "$FRAPPE_HOME" == */home/"$FRAPPE_USER" ]] || return 1
  else
    [[ "$FRAPPE_HOME" == "/home/$FRAPPE_USER" ]] || return 1
  fi
  [[ "$BENCH_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "$BENCH_PARENT" == "$FRAPPE_HOME/"* && "$BENCH_DIR" == "$BENCH_PARENT/$BENCH_NAME" ]] || return 1
  [[ "$NODE_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || return 1
  [[ "$YARN_VERSION" =~ ^1\.22\.[0-9]+$ ]] || return 1
  [[ "$PYTHON_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || return 1
  [[ "$NVM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$NVM_COMMIT" =~ ^[a-f0-9]{40}$ ]] || return 1
  [[ "$UV_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$PYTHON_PATCH_VERSION" =~ ^3\.14\.[0-9]+$ ]] || return 1
  [[ -z "$BENCH_VERSION" || "$BENCH_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
}

native_advanced_plan() {
  local app commit
  printf 'Native Advanced Installation Plan\n'
  printf 'Profile: advanced\nEngine: native\nExact site: %s\n' "$SITE_NAME"
  printf 'Requested applications: %s\nResolved dependency closure: %s\n' "$NATIVE_ADVANCED_REQUESTED" "$NATIVE_ADVANCED_RESOLVED"
  printf 'Application installation order: %s\n' "$NATIVE_ADVANCED_RESOLVED"
  printf 'Catalog acquisition records:\n'
  while IFS='|' read -r app repo branch commit; do printf '  %s repository=%s ref=%s commit=%s\n' "$app" "$repo" "$branch" "$commit"; done < <(native_advanced_catalog_rows)
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
      NATIVE_ADVANCED_STATUS="recovery-required"
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
  (check_os) || { native_advanced_print_prerequisite_retry; return 1; }
  if ! (check_internet) >/dev/null 2>&1; then
    err "Network readiness could not be verified."
    native_advanced_print_prerequisite_retry
    return 1
  fi
  INSTALL_READINESS_CONTEXT=native-advanced verify_clock_and_repository_readiness || return 1
  (check_resources) || { native_advanced_print_prerequisite_retry; return 1; }
  native_advanced_verify_upstream_pins || { err "A reviewed upstream application ref moved or is unavailable."; return 1; }
  native_advanced_ledger_add toolkit-reuse
  install_self_for_reuse || return 1
  native_advanced_ledger_add system-packages
  install_system_packages || return 1
  native_advanced_verify_os_runtime || return 1
  native_advanced_pdf_capability_check
  native_advanced_ledger_add redis-sysctl
  configure_sysctl_for_redis || return 1
}

native_advanced_verify_os_runtime() {
  local mariadb_version redis_version
  mariadb_version="$(mariadb --version 2>/dev/null)" || return 1
  [[ "$mariadb_version" =~ (^|[^0-9])11\.8\.[0-9]+([^0-9]|$) ]] || {
    err "Frappe v16 requires MariaDB 11.8; the installed server does not match."
    return 1
  }
  redis_version="$(redis-server --version 2>/dev/null)" || return 1
  [[ "$redis_version" =~ v=([0-9]+)\. ]] || { err "Redis runtime version could not be verified."; return 1; }
  ((BASH_REMATCH[1] >= 6)) || { err "Frappe v16 requires Redis or Valkey 6 or newer."; return 1; }
  systemctl is-enabled --quiet mariadb || { err "MariaDB is not enabled."; return 1; }
  systemctl is-active --quiet mariadb || { err "MariaDB is not active."; return 1; }
  systemctl is-enabled --quiet redis-server || { err "Redis is not enabled."; return 1; }
  systemctl is-active --quiet redis-server || { err "Redis is not active."; return 1; }
  mariadb-admin ping --silent >/dev/null 2>&1 || { err "MariaDB did not answer its local readiness probe."; return 1; }
  [[ "$(redis-cli ping 2>/dev/null)" == PONG ]] || { err "Redis did not answer its local readiness probe."; return 1; }
  command -v cc >/dev/null || { err "The required C compiler is unavailable."; return 1; }
  command -v pkg-config >/dev/null || { err "pkg-config is unavailable."; return 1; }
  command -v fc-list >/dev/null || { err "The fontconfig fc-list runtime is unavailable."; return 1; }
  pkg-config --exists libmariadb || { err "MariaDB development metadata is unavailable to pkg-config."; return 1; }
  systemctl is-enabled --quiet cron || { err "Cron is not enabled."; return 1; }
}

native_advanced_pdf_capability_check() {
  local version=""
  if command -v wkhtmltopdf >/dev/null 2>&1; then
    version="$(wkhtmltopdf --version 2>/dev/null || true)"
  fi
  if [[ "$version" == *'0.12.6'* && "$version" == *'patched qt'* ]]; then
    NATIVE_ADVANCED_PDF_CAPABILITY=available
    native_advanced_ledger_add pdf-capability:available
    return 0
  fi
  NATIVE_ADVANCED_PDF_CAPABILITY=unavailable
  native_advanced_ledger_add pdf-capability:unavailable
  warn "PDF generation unavailable: wkhtmltopdf 0.12.6 with patched Qt was not verified."
  warn "Installation will continue without claiming PDF capability; see the Phase 7.4 remediation documentation."
}

native_advanced_user_setup() {
  prepare_passwords
  [[ "$DB_ADMIN_USER" =~ ^[A-Za-z0-9_]+$ ]] || return 1
  [[ "$DB_ADMIN_PASSWORD" =~ ^[A-Za-z0-9]{1,128}$ && "$ADMIN_PASSWORD" =~ ^[A-Za-z0-9]{1,128}$ ]] || return 1
  native_advanced_ledger_add frappe-user
  create_frappe_user || return 1
  native_advanced_ledger_add mariadb-admin
  create_mariadb_admin_user || return 1
  fix_frappe_ownership || return 1
}

native_advanced_toolchain_setup() {
  local rc=0
  native_advanced_ledger_add frappe-toolchain
  if native_advanced_frappe_bash "$FRAPPE_HOME" bootstrap <<EOF_NATIVE_ADVANCED_TOOLCHAIN
if [[ ! -s "\$NVM_DIR/nvm.sh" ]]; then
  if [[ -e "\$NVM_DIR" || -L "\$NVM_DIR" ]]; then
    [[ -d "\$NVM_DIR" && ! -L "\$NVM_DIR" && -O "\$NVM_DIR" ]]
    [[ -z "\$(find "\$NVM_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]
  fi
  echo 'INFO: installing reviewed NVM source'
  git init "\$NVM_DIR"
  git -C "\$NVM_DIR" remote add origin https://github.com/nvm-sh/nvm.git
  git -C "\$NVM_DIR" fetch --depth 1 origin "refs/tags/v${NVM_VERSION}"
  git -C "\$NVM_DIR" checkout --detach FETCH_HEAD
fi
[[ -s "\$NVM_DIR/nvm.sh" ]]
[[ "\$(git -C "\$NVM_DIR" rev-parse HEAD)" == "${NVM_COMMIT}" ]]
echo 'INFO: verified reviewed NVM commit'
source "\$NVM_DIR/nvm.sh"
nvm install "${NODE_VERSION}"
nvm use "${NODE_VERSION}"
nvm alias default "${NODE_VERSION}"
echo 'INFO: verified Node activation'
npm install -g --ignore-scripts "yarn@${YARN_VERSION}"
if ! command -v uv >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -LsSf "https://releases.astral.sh/github/uv/releases/download/${UV_VERSION}/uv-installer.sh" | sh
fi
export PATH="\$HOME/.local/bin:\$PATH"
[[ "\$(command -v uv)" == "\$HOME/.local/bin/uv" && -x "\$HOME/.local/bin/uv" ]]
[[ "\$(uv --version)" == "uv ${UV_VERSION}" ]]
echo 'INFO: verified uv executable'
uv python install "${PYTHON_PATCH_VERSION}" --default
if [[ -n "${BENCH_VERSION}" ]]; then uv tool install "frappe-bench==${BENCH_VERSION}" --force; else uv tool install frappe-bench --force; fi
echo 'INFO: installed pinned Python and Bench toolchain'
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
[[ "\$(command -v node)" == "\$NVM_DIR/versions/node/"*/bin/node ]]
npm --version
[[ "\$(npm prefix -g)" == "\$NVM_DIR/versions/node/"* ]]
yarn --version
[[ "\$(yarn --version)" == "${YARN_VERSION}" ]]
uv_version="\$(uv --version)"
[[ "\${uv_version#uv }" == "${UV_VERSION}" ]]
[[ "\$(command -v uv)" == "\$HOME/.local/bin/uv" && -x "\$HOME/.local/bin/uv" && -O "\$HOME/.local/bin/uv" ]]
python_version="\$(python3 --version)"
[[ "\${python_version#Python }" == "${PYTHON_PATCH_VERSION}" ]]
bench_version="\$(bench --version)"
if [[ -n "${BENCH_VERSION}" ]]; then [[ "\$bench_version" == "${BENCH_VERSION}" ]]; else [[ -n "\$bench_version" ]]; fi
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
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_BENCH_VERIFY || { native_advanced_ledger_add partial-bench; return 1; }
bench --version
bench version
[[ "\$(./env/bin/python --version)" == "Python ${PYTHON_PATCH_VERSION}" ]]
pip_version="\$(./env/bin/python -m pip --version)"
[[ "\$pip_version" == 'pip 25.3 '* || "\$pip_version" == 'pip 25.3.'* ]]
EOF_NATIVE_ADVANCED_BENCH_VERIFY
  load_validated_app_catalog_record frappe || { native_advanced_ledger_add partial-bench; return 1; }
  [[ "$(native_advanced_frappe_bash "$BENCH_DIR" <<'EOF_NATIVE_ADVANCED_FRAPPE_HEAD'
git -C apps/frappe rev-parse HEAD
EOF_NATIVE_ADVANCED_FRAPPE_HEAD
  )" == "$LIB_APP_COMMIT" ]] || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_remote_pin_matches frappe || { native_advanced_ledger_add partial-bench; return 1; }
  native_advanced_ledger_add bench
  native_advanced_ledger_add "source:frappe@$LIB_APP_COMMIT"
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
  local latest prefix db_file public_file private_file config_file completeness backup_dir before_db_files
  backup_dir="$(site_backup_dir)" || return 1
  before_db_files="$(${SUDO:-} find "$backup_dir" -maxdepth 1 -type f \( -name '*-database.sql.gz' -o -name '*.sql.gz' \) -print 2>/dev/null || true)"
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
  ! grep -Fxq "$db_file" <<<"$before_db_files" || return 1
  [[ -s "$db_file" && -s "$public_file" && -s "$private_file" && -s "$config_file" ]] || return 1
  [[ "$(stat -c %Y "$db_file")" -ge "$NATIVE_ADVANCED_STARTED_EPOCH" \
    && "$(stat -c %Y "$public_file")" -ge "$NATIVE_ADVANCED_STARTED_EPOCH" \
    && "$(stat -c %Y "$private_file")" -ge "$NATIVE_ADVANCED_STARTED_EPOCH" \
    && "$(stat -c %Y "$config_file")" -ge "$NATIVE_ADVANCED_STARTED_EPOCH" ]] || return 1
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
  local app="$1" repo branch commit rc=0 actual_commit
  load_validated_app_catalog_record "$app" || return 1
  [[ "$LIB_APP_ID" == "$app" && "$app" != frappe ]] || return 1
  repo="$LIB_APP_REPO"; branch="$LIB_APP_BRANCH"; commit="$LIB_APP_COMMIT"
  native_advanced_remote_pin_matches "$app" || return 1
  if [[ -n "$branch" ]]; then
    native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_GET || rc=$?
bench get-app --branch "${branch}" "${app}" "${repo}"
EOF_NATIVE_ADVANCED_GET
  else
    native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_GET_DEFAULT || rc=$?
bench get-app "${app}" "${repo}"
EOF_NATIVE_ADVANCED_GET_DEFAULT
  fi
  if [[ "$rc" -ne 0 ]]; then
    [[ ! -e "$BENCH_DIR/apps/$app" && ! -L "$BENCH_DIR/apps/$app" ]] || native_advanced_ledger_add "partial-code:$app"
    return "$rc"
  fi
  native_advanced_safe_directory "$BENCH_DIR/apps/$app" || { native_advanced_ledger_add "partial-code:$app"; return 1; }
  actual_commit="$(native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_GET_HEAD
git -C "apps/${app}" rev-parse HEAD
EOF_NATIVE_ADVANCED_GET_HEAD
  )" || { native_advanced_ledger_add "partial-code:$app"; return 1; }
  [[ "$actual_commit" == "$commit" ]] || { native_advanced_ledger_add "partial-code:$app"; return 1; }
  native_advanced_remote_pin_matches "$app" || { native_advanced_ledger_add "partial-code:$app"; return 1; }
  native_advanced_ledger_add "code:$app"
  native_advanced_ledger_add "source:$app@$commit"
}

native_advanced_install_app() {
  local app="$1" installed rc=0
  [[ "$app" != frappe ]] || return 0
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_INSTALL || rc=$?
bench --site "${SITE_NAME}" install-app "${app}"
EOF_NATIVE_ADVANCED_INSTALL
  if [[ "$rc" -ne 0 ]]; then
    native_advanced_ledger_add "partial-site-app:$app"
    return "$rc"
  fi
  installed="$(native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_INSTALL_VERIFY
bench --site "${SITE_NAME}" list-apps
EOF_NATIVE_ADVANCED_INSTALL_VERIFY
  )" || return 1
  awk '{print $1}' <<<"$installed" | grep -Fxq "$app" || return 1
  native_advanced_ledger_add "site-app:$app"
}

native_advanced_migrate() {
  native_advanced_ledger_add migration-attempt
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_MIGRATE
bench --site "${SITE_NAME}" migrate
EOF_NATIVE_ADVANCED_MIGRATE
}
native_advanced_assets() {
  native_advanced_ledger_add assets-attempt
  native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_ASSETS
bench build
bench --site "${SITE_NAME}" clear-cache
bench --site "${SITE_NAME}" clear-website-cache
EOF_NATIVE_ADVANCED_ASSETS
}
native_advanced_services() {
  native_advanced_ledger_add services-attempt
  create_start_helper && create_erpnext_service && enable_autostart_service && start_erpnext_service
}
native_advanced_readiness() {
  wait_for_erpnext_ready && settle_stack_after_install
}

native_advanced_verify() {
  local app repo branch commit actual_repo actual_branch actual_commit installed expected
  [[ -d "$BENCH_DIR/sites/$SITE_NAME" && -d "$BENCH_DIR/apps/frappe" ]] || return 1
  installed="$(native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_INVENTORY
bench --site "${SITE_NAME}" list-apps
EOF_NATIVE_ADVANCED_INVENTORY
  )" || return 1
  installed="$(awk '{print $1}' <<<"$installed")"
  expected="$(printf '%s\n' "${PROFILE_PLAN_DESIRED_APPS[@]}")"
  [[ "$(printf '%s\n' "$installed" | sed '/^$/d' | sort -u)" == "$(printf '%s\n' "$expected" | sort -u)" ]] || return 1
  [[ "$(printf '%s\n' "$installed" | sed '/^$/d' | wc -l)" -eq "${#PROFILE_PLAN_DESIRED_APPS[@]}" ]] || return 1
  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    grep -Fxq "$app" <<<"$installed" || return 1
    [[ -d "$BENCH_DIR/apps/$app" ]] || return 1
    load_validated_app_catalog_record "$app" || return 1
    repo="${LIB_APP_REPO%/}"; branch="$LIB_APP_BRANCH"; commit="$LIB_APP_COMMIT"
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
    actual_commit="$(native_advanced_frappe_bash "$BENCH_DIR" <<EOF_NATIVE_ADVANCED_GIT_COMMIT
git -C "apps/${app}" rev-parse HEAD
EOF_NATIVE_ADVANCED_GIT_COMMIT
    )" || return 1
    [[ "$actual_commit" == "$commit" ]] || return 1
  done
}

native_advanced_stage_config() {
  [[ "$(native_advanced_config_snapshot)" == "$NATIVE_ADVANCED_CONFIG_BASE" ]] || return 1
  NATIVE_ADVANCED_STAGED_CONFIG="$NATIVE_ADVANCED_STATE_DIR/${NATIVE_ADVANCED_OPERATION_ID}.config"
  [[ ! -e "$NATIVE_ADVANCED_STAGED_CONFIG" && ! -L "$NATIVE_ADVANCED_STAGED_CONFIG" ]] || return 1
  umask 077
  if ! {
    printf '# ERPNext Developer Toolkit schema-2 configuration\nCONFIG_SCHEMA=2\n'
    printf 'SITE_NAME=%s\nDEPLOYMENT_MODE=%s\nDEPLOYMENT_ENGINE=native\n' "$SITE_NAME" "${DEPLOYMENT_MODE:-development}"
    printf 'INSTALLATION_PROFILE=advanced\nINSTALLATION_PROFILE_APPS=%s\n' "$NATIVE_ADVANCED_REQUESTED"
    printf 'PDF_CAPABILITY=%s\n' "$NATIVE_ADVANCED_PDF_CAPABILITY"
    printf 'FRAPPE_USER=%s\nBENCH_PARENT=%s\nBENCH_NAME=%s\nBENCH_DIR=%s\n' "$FRAPPE_USER" "$BENCH_PARENT" "$BENCH_NAME" "$BENCH_DIR"
  } >"$NATIVE_ADVANCED_STAGED_CONFIG"; then
    native_advanced_ledger_add partial-staged-config
    return 1
  fi
  chmod 0600 "$NATIVE_ADVANCED_STAGED_CONFIG" || { native_advanced_ledger_add partial-staged-config; return 1; }
  native_advanced_ledger_add staged-config
}

native_advanced_promote_config() {
  local current primary_tmp legacy_tmp
  current="$(native_advanced_config_snapshot)" || return 1
  [[ "$current" == "$NATIVE_ADVANCED_CONFIG_BASE" ]] || return 1
  [[ -f "$NATIVE_ADVANCED_STAGED_CONFIG" && ! -L "$NATIVE_ADVANCED_STAGED_CONFIG" ]] || return 1
  native_advanced_ledger_add configuration-promotion-attempt
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
    && native_advanced_verify && native_advanced_readiness
}

native_advanced_install() {
  local rc app original_fingerprint
  SITE_NAME="$QUICK_INSTALL_SITE"
  validate_site_name_value "$SITE_NAME" || { planner_exit_code invalid-input; return $?; }
  profile_plan_parse_requested_apps "$INSTALLATION_PROFILE_APPS_RAW" || { err "$PROFILE_PLAN_ERROR"; planner_exit_code invalid-input; return $?; }
  profile_plan_resolve_apps advanced || { err "$PROFILE_PLAN_ERROR"; planner_exit_code incompatible; return $?; }
  native_advanced_catalog_validate_runtime || { err "The resolved Native advanced application/ref plan is unsupported."; planner_exit_code incompatible; return $?; }
  native_advanced_runtime_coordinates_validate || { err "The Native advanced runtime coordinates are invalid."; planner_exit_code invalid-input; return $?; }
  NATIVE_ADVANCED_REQUESTED="$PROFILE_PLAN_REQUESTED_CSV"
  NATIVE_ADVANCED_RESOLVED="$PROFILE_PLAN_DESIRED_CSV"
  if [[ "$(effective_deployment_engine)" == docker ]]; then
    err "Native advanced installation is unsupported for Docker; Phase 7.5 is deferred."
    planner_exit_code unsupported; return $?
  fi
  if native_advanced_preflight; then
    :
  else
    rc=$?
    case "$rc" in
      34) return 34 ;;
      23) return 23 ;;
      *) return 21 ;;
    esac
  fi
  original_fingerprint="$NATIVE_ADVANCED_PREFLIGHT"
  native_advanced_plan
  if [[ "${QUICK_INSTALL_PREVIEW:-0}" -eq 1 ]]; then planner_exit_code preview; return $?; fi
  native_advanced_confirm || { echo "Installation cancelled before mutation."; planner_exit_code cancelled; return $?; }
  require_sudo
  [[ "$(native_advanced_absence_fingerprint)" == "$original_fingerprint" \
    && "$(native_advanced_records_snapshot)" == "$NATIVE_ADVANCED_RECORDS_BASE" ]] \
    || { err "Target, configuration, or operation records changed after confirmation; refusing mutation."; planner_exit_code conflict; return $?; }

  NATIVE_ADVANCED_OPERATION_ID="native-advanced-${NATIVE_ADVANCED_OPERATION_ID_OVERRIDE:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
  NATIVE_ADVANCED_STARTED_EPOCH="$(date -u +%s)"
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
    NATIVE_ADVANCED_STATUS="recovery-required"
    NATIVE_ADVANCED_RECOVERY="inspect-record,verify-baseline-backup,resume-manually-from-${NATIVE_ADVANCED_CHECKPOINT}"
  else
    NATIVE_ADVANCED_STATUS=failed
    NATIVE_ADVANCED_RECOVERY="inspect-record,remove-only-proven-private-staging,retry-if-target-absent"
  fi
  native_advanced_record_write || true
  trap - INT TERM
  return 130
}
