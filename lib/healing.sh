# shellcheck shell=bash
# Guarded auto-healing (v1.19.0 MVP + v1.19.1 hardening). Default mode is
# monitor-only. Dedicated /etc/erpnext-dev/healing.env uses the same strict
# allowlist parser pattern as health.env. Sourced after lib/dashboard.sh.

[[ -n "${_ERPNEXT_DEV_HEALING_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_HEALING_LOADED=1

: "${HEALTH_HEALING_MODE:=monitor}"
: "${HEALTH_HEALING_MAX_FAILURES:=3}"
: "${HEALTH_HEALING_MAX_ACTIONS:=5}"
: "${HEALTH_HEALING_ACTION_WINDOW_SEC:=3600}"
: "${HEALTH_HEALING_VERIFY_WAIT_SEC:=5}"
# Hermetic / CI / operator simulate: record the action path without restarts.
: "${HEALTH_HEALING_SIMULATE:=0}"

: "${HEALING_ENV_FILE:=/etc/erpnext-dev/healing.env}"
: "${HEALING_ACTION_RESTART_WEB_RUNTIME:=1}"
: "${HEALING_ACTION_RESTART_APP_STACK:=1}"
: "${HEALING_ALERT_ON_LOCKOUT:=1}"
: "${HEALING_AUDIT_MAX_LINES:=500}"
# Set to 1 only for hermetic tests (skip root ownership checks on healing.env).
: "${HEALING_ENV_SKIP_OWNER_CHECK:=0}"

healing_mode_normalized() {
  local mode="${1:-${HEALTH_HEALING_MODE:-monitor}}"
  mode="$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    monitor | safe | advanced) printf '%s' "$mode" ;;
    *) printf 'monitor' ;;
  esac
}

healing_state_file() {
  printf '%s' "${HEALTH_LIB_DIR:-/var/lib/erpnext-dev}/healing/state.json"
}

healing_audit_file() {
  printf '%s' "${HEALTH_LIB_DIR:-/var/lib/erpnext-dev}/healing/audit.jsonl"
}

healing_state_get() {
  local key="$1" file default="${2:-}"
  file="$(healing_state_file)"
  local value=""
  if [[ -f "$file" ]]; then
    value="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" | head -n 1)"
    if [[ -z "$value" ]]; then
      value="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\(true\\|false\\|[0-9][0-9]*\\).*/\\1/p" "$file" | head -n 1)"
    fi
  fi
  printf '%s' "${value:-$default}"
}

healing_is_locked() {
  local locked
  locked="$(healing_state_get locked false)"
  [[ "$locked" == "true" || "$locked" == "1" ]]
}

healing_action_enabled() {
  local action="$1"
  case "$action" in
    restart_web_runtime) [[ "${HEALING_ACTION_RESTART_WEB_RUNTIME:-1}" == "1" ]] ;;
    restart_app_stack) [[ "${HEALING_ACTION_RESTART_APP_STACK:-1}" == "1" ]] ;;
    *) return 1 ;;
  esac
}

healing_env_is_known_key() {
  case "${1:-}" in
    HEALING_MODE|HEALING_MAX_FAILURES|HEALING_MAX_ACTIONS|\
    HEALING_ACTION_WINDOW_SEC|HEALING_VERIFY_WAIT_SEC|\
    HEALING_ACTION_RESTART_WEB_RUNTIME|HEALING_ACTION_RESTART_APP_STACK|\
    HEALING_SIMULATE|HEALING_ALERT_ON_LOCKOUT|HEALING_AUDIT_MAX_LINES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

healing_env_validate_value() {
  local key="$1" value="$2"
  if declare -F health_env_value_is_safe >/dev/null 2>&1; then
    health_env_value_is_safe "$value" || return 1
  else
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
    [[ ! "$value" =~ [\$\`\;\|\&\>\<\(\)\{\}\*\!] ]] || return 1
  fi
  case "$key" in
    HEALING_MODE)
      case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
        monitor | safe | advanced) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    HEALING_ACTION_RESTART_WEB_RUNTIME|HEALING_ACTION_RESTART_APP_STACK|\
    HEALING_SIMULATE|HEALING_ALERT_ON_LOCKOUT)
      [[ "$value" == "0" || "$value" == "1" ]] || return 1
      ;;
    HEALING_MAX_FAILURES|HEALING_MAX_ACTIONS|HEALING_ACTION_WINDOW_SEC|\
    HEALING_VERIFY_WAIT_SEC|HEALING_AUDIT_MAX_LINES)
      [[ "$value" =~ ^[0-9]+$ ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

healing_env_apply_assignment() {
  local key="$1" value="$2"
  healing_env_is_known_key "$key" || return 1
  healing_env_validate_value "$key" "$value" || return 1
  case "$key" in
    HEALING_MODE)
      HEALTH_HEALING_MODE="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
      ;;
    HEALING_MAX_FAILURES) HEALTH_HEALING_MAX_FAILURES="$value" ;;
    HEALING_MAX_ACTIONS) HEALTH_HEALING_MAX_ACTIONS="$value" ;;
    HEALING_ACTION_WINDOW_SEC) HEALTH_HEALING_ACTION_WINDOW_SEC="$value" ;;
    HEALING_VERIFY_WAIT_SEC) HEALTH_HEALING_VERIFY_WAIT_SEC="$value" ;;
    HEALING_ACTION_RESTART_WEB_RUNTIME) HEALING_ACTION_RESTART_WEB_RUNTIME="$value" ;;
    HEALING_ACTION_RESTART_APP_STACK) HEALING_ACTION_RESTART_APP_STACK="$value" ;;
    HEALING_SIMULATE)
      HEALTH_HEALING_SIMULATE="$value"
      ;;
    HEALING_ALERT_ON_LOCKOUT) HEALING_ALERT_ON_LOCKOUT="$value" ;;
    HEALING_AUDIT_MAX_LINES) HEALING_AUDIT_MAX_LINES="$value" ;;
    *) return 1 ;;
  esac
  return 0
}

healing_env_file_perms_ok() {
  local file="$1"
  if [[ "${HEALING_ENV_SKIP_OWNER_CHECK}" == "1" || "${HEALTH_ENV_SKIP_OWNER_CHECK:-0}" == "1" ]]; then
    [[ -f "$file" && -r "$file" ]]
    return $?
  fi
  if declare -F health_env_file_perms_ok >/dev/null 2>&1; then
    health_env_file_perms_ok "$file"
    return $?
  fi
  [[ -f "$file" && -r "$file" ]]
}

# Strict allowlist parser for /etc/erpnext-dev/healing.env (never source as shell).
healing_load_policy() {
  local file="${HEALING_ENV_FILE}"
  local line key value stripped
  [[ -f "$file" ]] || return 0
  if ! healing_env_file_perms_ok "$file"; then
    if declare -F warn >/dev/null 2>&1; then
      warn "Ignoring healing policy ${file}: unsafe ownership or permissions (want root-owned 600/640)."
    else
      echo "WARN: Ignoring healing policy ${file}: unsafe ownership or permissions" >&2
    fi
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    stripped="${line%%#*}"
    stripped="${stripped#"${stripped%%[![:space:]]*}"}"
    stripped="${stripped%"${stripped##*[![:space:]]}"}"
    [[ -z "$stripped" ]] && continue
    [[ "$stripped" == *=* ]] || continue
    key="${stripped%%=*}"
    value="${stripped#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    # Strip optional matching quotes.
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    healing_env_is_known_key "$key" || continue
    healing_env_apply_assignment "$key" "$value" || continue
  done <"$file"
  return 0
}

healing_actions_window_reset_needed() {
  local now="$1" window_started actions
  window_started="$(healing_state_get window_started_at 0)"
  actions="$(healing_state_get actions_in_window 0)"
  [[ "$window_started" =~ ^[0-9]+$ ]] || window_started=0
  [[ "$actions" =~ ^[0-9]+$ ]] || actions=0
  if (( window_started == 0 )); then
    return 0
  fi
  if (( now - window_started >= HEALTH_HEALING_ACTION_WINDOW_SEC )); then
    return 0
  fi
  return 1
}

healing_audit_append() {
  local event="$1" action="${2:-}" result="${3:-}" detail="${4:-}"
  local audit tmp lines
  health_ensure_lib_dirs
  audit="$(healing_audit_file)"
  {
    printf '{'
    printf '"t":' ; json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)" ; printf ','
    printf '"event":' ; json_escape "$event" ; printf ','
    printf '"action":' ; json_escape "$action" ; printf ','
    printf '"result":' ; json_escape "$result" ; printf ','
    printf '"mode":' ; json_escape "$(healing_mode_normalized)" ; printf ','
    printf '"site":' ; json_escape "${SNAPSHOT_SITE:-}" ; printf ','
    printf '"detail":' ; json_escape "$detail"
    printf '}\n'
  } >>"$audit"
  chmod 600 "$audit" 2>/dev/null || true
  if [[ -f "$audit" ]]; then
    lines="$(wc -l <"$audit" | tr -d ' ')"
    if [[ "$lines" =~ ^[0-9]+$ && "$lines" -gt "${HEALING_AUDIT_MAX_LINES}" ]]; then
      tmp="$(mktemp)"
      tail -n "${HEALING_AUDIT_MAX_LINES}" "$audit" >"$tmp" && mv "$tmp" "$audit"
      chmod 600 "$audit" 2>/dev/null || true
    fi
  fi
}

healing_alert() {
  local kind="$1" action="${2:-}" result="${3:-}" detail="${4:-}"
  local msg
  msg="erpnext-dev healing ${kind} action=${action:-none} result=${result:-none} site=${SNAPSHOT_SITE:-unknown} detail=${detail}"
  if command -v logger >/dev/null 2>&1; then
    logger -t erpnext-dev-healing "$msg" 2>/dev/null || true
  fi
  echo "ALERT: $msg" >&2
  if [[ -n "${HEALTH_ALERT_WEBHOOK_URL:-}" ]] && command -v curl >/dev/null 2>&1; then
    curl -sS -o /dev/null \
      --connect-timeout "${HEALTH_ALERT_WEBHOOK_TIMEOUT_SEC:-5}" \
      --max-time "${HEALTH_ALERT_WEBHOOK_TIMEOUT_SEC:-5}" \
      -X POST \
      -H 'Content-Type: application/json' \
      --data "{\"text\":$(json_escape "$msg"),\"kind\":$(json_escape "$kind"),\"action\":$(json_escape "${action:-}"),\"result\":$(json_escape "${result:-}"),\"site\":$(json_escape "${SNAPSHOT_SITE:-}")}" \
      "${HEALTH_ALERT_WEBHOOK_URL}" 2>/dev/null || true
  fi
}

healing_record_action_incident() {
  local action="$1" result="$2" before_http="$3" after_http="$4" before_overall="$5" after_overall="$6"
  local id path detail
  health_ensure_lib_dirs
  id="$(date -u +%Y%m%dT%H%M%S%NZ 2>/dev/null || printf '%sZ-%s' "$(date -u +%Y%m%dT%H%M%S)" "${RANDOM}")-heal-$$"
  path="${HEALTH_LIB_DIR}/incidents/${id}.json"
  detail="healing action=${action} result=${result}"
  {
    printf '{\n'
    printf '  "id": ' ; json_escape "$id" ; printf ',\n'
    printf '  "kind": "healing_action",\n'
    printf '  "timestamp": ' ; json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)" ; printf ',\n'
    printf '  "previous_status": ' ; json_escape "$before_overall" ; printf ',\n'
    printf '  "status": ' ; json_escape "$after_overall" ; printf ',\n'
    printf '  "site": ' ; json_escape "${SNAPSHOT_SITE:-}" ; printf ',\n'
    printf '  "action": ' ; json_escape "$action" ; printf ',\n'
    printf '  "result": ' ; json_escape "$result" ; printf ',\n'
    printf '  "before_http": ' ; json_escape "$before_http" ; printf ',\n'
    printf '  "after_http": ' ; json_escape "$after_http" ; printf ',\n'
    printf '  "before_overall": ' ; json_escape "$before_overall" ; printf ',\n'
    printf '  "after_overall": ' ; json_escape "$after_overall" ; printf ',\n'
    printf '  "detail": ' ; json_escape "$detail" ; printf ',\n'
    printf '  "would_heal": ' ; json_escape "$action" ; printf '\n'
    printf '}\n'
  } >"$path"
  chmod 600 "$path" 2>/dev/null || true
  ln -sfn "$path" "${HEALTH_LIB_DIR}/incidents/latest.json" 2>/dev/null || cp -f "$path" "${HEALTH_LIB_DIR}/incidents/latest.json" 2>/dev/null || true
  # Consumed by dashboard / alert path after heal executes.
  # shellcheck disable=SC2034
  SNAPSHOT_LAST_INCIDENT_ID="$id"
  printf '%s' "$id"
}

healing_execute_restart() {
  local action="$1"
  if [[ "${HEALTH_HEALING_SIMULATE}" == "1" ]]; then
    case "${HEALTH_HEALING_SIMULATE_RESTART:-ok}" in
      fail | 0) return 1 ;;
      *) return 0 ;;
    esac
  fi
  if ! declare -F restart_erpnext_service >/dev/null 2>&1; then
    return 1
  fi
  case "$action" in
    restart_web_runtime | restart_app_stack)
      restart_erpnext_service
      ;;
    *)
      return 1
      ;;
  esac
}

healing_verify_recovery() {
  local before_http="$1" after_http after_overall pair
  if [[ "${HEALTH_HEALING_SIMULATE}" == "1" ]]; then
    after_http="${HEALTH_HEALING_SIMULATE_AFTER_HTTP:-HEALTHY}"
    after_overall="${HEALTH_HEALING_SIMULATE_AFTER_OVERALL:-HEALTHY}"
    printf '%s|%s' "$after_http" "$after_overall"
    [[ "$(health_status_normalize "$after_http")" != "CRITICAL" ]]
    return $?
  fi

  if [[ "${HEALTH_HEALING_VERIFY_WAIT_SEC}" =~ ^[0-9]+$ ]] && (( HEALTH_HEALING_VERIFY_WAIT_SEC > 0 )); then
    sleep "${HEALTH_HEALING_VERIFY_WAIT_SEC}" || true
  fi

  if declare -F health_probe_http >/dev/null 2>&1; then
    pair="$(health_probe_http)"
    after_http="${pair%%|*}"
  else
    after_http="UNKNOWN"
  fi
  after_overall="${SNAPSHOT_OVERALL:-UNKNOWN}"
  if [[ "$(health_status_normalize "$after_http")" != "CRITICAL" ]]; then
    after_overall="HEALTHY"
  fi
  printf '%s|%s' "$after_http" "$after_overall"
  if [[ "$(health_status_normalize "$before_http")" == "CRITICAL" ]]; then
    [[ "$(health_status_normalize "$after_http")" != "CRITICAL" ]]
    return $?
  fi
  [[ "$(health_status_normalize "$after_http")" != "CRITICAL" ]]
}

healing_write_state_merge() {
  local now="$1" mode="$2" state="$3" detail="$4"
  local last_action="${5:-}" last_result="${6:-}" locked="${7:-false}" lock_reason="${8:-}"
  local actions_in_window="${9:-0}" window_started_at="${10:-0}" fail_streak="${11:-0}"
  local last_action_at="${12:-0}"
  local state_file http_streak overall_streak would_heal last_would_heal_at cooldown_sec
  state_file="$(healing_state_file)"
  health_ensure_lib_dirs

  http_streak="${SNAPSHOT_HTTP_FAIL_STREAK:-0}"
  overall_streak="${SNAPSHOT_OVERALL_FAIL_STREAK:-0}"
  would_heal="${SNAPSHOT_WOULD_HEAL:-none}"
  last_would_heal_at="$(healing_state_get last_would_heal_at 0)"
  [[ "$last_would_heal_at" =~ ^[0-9]+$ ]] || last_would_heal_at=0
  if [[ -f "$state_file" ]]; then
    local tmp
    tmp="$(sed -n 's/.*"last_would_heal_at"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$state_file" | head -n 1)"
    [[ "$tmp" =~ ^[0-9]+$ ]] && last_would_heal_at="$tmp"
  fi
  cooldown_sec="${HEALTH_COOLDOWN_SEC:-600}"

  {
    printf '{\n'
    printf '  "updated_at": %s,\n' "$now"
    printf '  "mode": ' ; json_escape "$mode" ; printf ',\n'
    printf '  "state": ' ; json_escape "$state" ; printf ',\n'
    printf '  "detail": ' ; json_escape "$detail" ; printf ',\n'
    printf '  "http_fail_streak": %s,\n' "$http_streak"
    printf '  "overall_fail_streak": %s,\n' "$overall_streak"
    printf '  "would_heal": ' ; json_escape "$would_heal" ; printf ',\n'
    printf '  "last_would_heal_at": %s,\n' "$last_would_heal_at"
    printf '  "last_action": ' ; json_escape "$last_action" ; printf ',\n'
    printf '  "last_action_result": ' ; json_escape "$last_result" ; printf ',\n'
    printf '  "last_action_at": %s,\n' "$last_action_at"
    printf '  "actions_in_window": %s,\n' "$actions_in_window"
    printf '  "window_started_at": %s,\n' "$window_started_at"
    printf '  "consecutive_action_failures": %s,\n' "$fail_streak"
    printf '  "locked": %s,\n' "$locked"
    printf '  "lock_reason": ' ; json_escape "$lock_reason" ; printf ',\n'
    printf '  "cooldown_sec": %s\n' "$cooldown_sec"
    printf '}\n'
  } >"$state_file"
  chmod 600 "$state_file" 2>/dev/null || true

  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_LAST_ACTION="$last_action"
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_LAST_RESULT="$last_result"
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_LOCKED="$locked"
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_LOCK_REASON="$lock_reason"
}

healing_apply_snapshot_fields() {
  local mode detail
  mode="$(healing_mode_normalized)"
  # Snapshot fields are rendered by lib/dashboard.sh after this module runs.
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_MODE="$mode"
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_LAST_ACTION="$(healing_state_get last_action)"
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_LAST_RESULT="$(healing_state_get last_action_result)"
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_LOCKED="$(healing_state_get locked false)"
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_LOCK_REASON="$(healing_state_get lock_reason)"
  if healing_is_locked; then
    # shellcheck disable=SC2034
    SNAPSHOT_HEALING_STATE="locked"
    SNAPSHOT_HEALING_DETAIL="AUTO-HEALING LOCKED: $(healing_state_get lock_reason 'manual review required') — run healing-unlock"
    return 0
  fi
  case "$mode" in
    monitor)
      SNAPSHOT_HEALING_STATE="observing"
      ;;
    safe | advanced)
      SNAPSHOT_HEALING_STATE="armed"
      ;;
  esac
  detail="${SNAPSHOT_HEALING_DETAIL:-}"
  if [[ "$mode" == "monitor" ]]; then
    case "${SNAPSHOT_WOULD_HEAL:-none}" in
      restart_web_runtime | restart_app_stack)
        SNAPSHOT_HEALING_DETAIL="Would heal (dry-run): ${SNAPSHOT_WOULD_HEAL} — enable with healing-enable-safe"
        ;;
      cooldown)
        SNAPSHOT_HEALING_DETAIL="Cooldown active; next suggestion after ${HEALTH_COOLDOWN_SEC}s"
        ;;
      *)
        SNAPSHOT_HEALING_DETAIL="Monitoring active (healing disabled); streaks http=${SNAPSHOT_HTTP_FAIL_STREAK:-0} overall=${SNAPSHOT_OVERALL_FAIL_STREAK:-0}"
        ;;
    esac
  elif [[ -z "$detail" || "$detail" == *"deferred"* || "$detail" == *"Candidate action"* ]]; then
    SNAPSHOT_HEALING_DETAIL="Healing mode=${mode}; streaks http=${SNAPSHOT_HTTP_FAIL_STREAK:-0} overall=${SNAPSHOT_OVERALL_FAIL_STREAK:-0}"
  fi
}

healing_enter_lockout() {
  local now="$1" mode="$2" lock_reason="$3" actions_in_window="$4" window_started_at="$5" fail_streak="$6"
  local last_action="${7:-}" last_result="${8:-locked}" last_action_at="${9:-0}"
  SNAPSHOT_HEALING_STATE="locked"
  SNAPSHOT_WOULD_HEAL="locked"
  SNAPSHOT_HEALING_DETAIL="AUTO-HEALING LOCKED: ${lock_reason} — run healing-unlock"
  healing_write_state_merge "$now" "$mode" "locked" "${SNAPSHOT_HEALING_DETAIL}" \
    "$last_action" "$last_result" true "$lock_reason" \
    "$actions_in_window" "$window_started_at" "$fail_streak" "$last_action_at"
  healing_audit_append "lockout" "$last_action" "locked" "$lock_reason"
  if [[ "${HEALING_ALERT_ON_LOCKOUT:-1}" == "1" ]]; then
    healing_alert "lockout" "$last_action" "locked" "$lock_reason"
  fi
}

healing_maybe_execute() {
  local mode action now before_http before_overall after_pair after_http after_overall
  local result="skipped" verify_ok=0 restart_ok=0
  local actions_in_window=0 window_started_at=0 fail_streak=0 locked=false lock_reason=""
  local last_action="" last_result="" last_action_at=0

  healing_load_policy || true
  mode="$(healing_mode_normalized)"
  healing_apply_snapshot_fields
  now="$(date +%s)"

  if healing_is_locked; then
    SNAPSHOT_HEALING_STATE="locked"
    SNAPSHOT_WOULD_HEAL="locked"
    healing_write_state_merge "$now" "$mode" "locked" "${SNAPSHOT_HEALING_DETAIL}" \
      "$(healing_state_get last_action)" "$(healing_state_get last_action_result)" \
      true "$(healing_state_get lock_reason 'locked')" \
      "$(healing_state_get actions_in_window 0)" "$(healing_state_get window_started_at 0)" \
      "$(healing_state_get consecutive_action_failures 0)" \
      "$(healing_state_get last_action_at 0)"
    return 0
  fi

  if [[ "$mode" == "monitor" ]]; then
    healing_write_state_merge "$now" "$mode" "observing" "${SNAPSHOT_HEALING_DETAIL}" \
      "$(healing_state_get last_action)" "$(healing_state_get last_action_result)" \
      false "" \
      "$(healing_state_get actions_in_window 0)" "$(healing_state_get window_started_at 0)" \
      "$(healing_state_get consecutive_action_failures 0)" \
      "$(healing_state_get last_action_at 0)"
    return 0
  fi

  # advanced currently shares the safe ladder (no host reboot in v1.19.x).
  action="${SNAPSHOT_WOULD_HEAL:-none}"
  case "$action" in
    restart_web_runtime | restart_app_stack) ;;
    *)
      SNAPSHOT_HEALING_STATE="armed"
      healing_write_state_merge "$now" "$mode" "armed" "${SNAPSHOT_HEALING_DETAIL}" \
        "$(healing_state_get last_action)" "$(healing_state_get last_action_result)" \
        false "" \
        "$(healing_state_get actions_in_window 0)" "$(healing_state_get window_started_at 0)" \
        "$(healing_state_get consecutive_action_failures 0)" \
        "$(healing_state_get last_action_at 0)"
      return 0
      ;;
  esac

  if ! healing_action_enabled "$action"; then
    SNAPSHOT_HEALING_STATE="armed"
    SNAPSHOT_HEALING_DETAIL="Candidate ${action} disabled by healing policy"
    healing_audit_append "skip" "$action" "disabled" "per-action switch off"
    healing_write_state_merge "$now" "$mode" "armed" "${SNAPSHOT_HEALING_DETAIL}" \
      "$(healing_state_get last_action)" "$(healing_state_get last_action_result)" \
      false "" \
      "$(healing_state_get actions_in_window 0)" "$(healing_state_get window_started_at 0)" \
      "$(healing_state_get consecutive_action_failures 0)" \
      "$(healing_state_get last_action_at 0)"
    return 0
  fi

  actions_in_window="$(healing_state_get actions_in_window 0)"
  window_started_at="$(healing_state_get window_started_at 0)"
  fail_streak="$(healing_state_get consecutive_action_failures 0)"
  [[ "$actions_in_window" =~ ^[0-9]+$ ]] || actions_in_window=0
  [[ "$window_started_at" =~ ^[0-9]+$ ]] || window_started_at=0
  [[ "$fail_streak" =~ ^[0-9]+$ ]] || fail_streak=0

  if healing_actions_window_reset_needed "$now"; then
    actions_in_window=0
    window_started_at="$now"
  fi

  if (( actions_in_window >= HEALTH_HEALING_MAX_ACTIONS )); then
    healing_enter_lockout "$now" "$mode" \
      "max actions (${HEALTH_HEALING_MAX_ACTIONS}) in ${HEALTH_HEALING_ACTION_WINDOW_SEC}s window" \
      "$actions_in_window" "$window_started_at" "$fail_streak" \
      "$(healing_state_get last_action)" "locked" "$(healing_state_get last_action_at 0)"
    return 0
  fi

  before_http="${SNAPSHOT_HTTP_STATUS:-UNKNOWN}"
  before_overall="${SNAPSHOT_OVERALL:-UNKNOWN}"
  last_action="$action"
  last_action_at="$now"
  actions_in_window=$((actions_in_window + 1))
  (( window_started_at == 0 )) && window_started_at="$now"

  if healing_execute_restart "$action"; then
    restart_ok=1
  else
    restart_ok=0
  fi

  set +e
  after_pair="$(healing_verify_recovery "$before_http")"
  verify_ok=$?
  set -e
  after_http="${after_pair%%|*}"
  after_overall="${after_pair#*|}"
  [[ -n "$after_http" ]] || after_http="UNKNOWN"
  [[ -n "$after_overall" ]] || after_overall="UNKNOWN"

  if (( restart_ok == 1 && verify_ok == 0 )); then
    result="success"
    fail_streak=0
    SNAPSHOT_HEALING_DETAIL="Healed via ${action}; recovery verified (http ${before_http}→${after_http})"
    SNAPSHOT_HEALING_STATE="recovered"
  else
    result="failed"
    fail_streak=$((fail_streak + 1))
    SNAPSHOT_HEALING_DETAIL="Healing ${action} failed (restart=${restart_ok} verify=${verify_ok}); http ${before_http}→${after_http}"
    SNAPSHOT_HEALING_STATE="failed"
  fi
  last_result="$result"

  healing_record_action_incident "$action" "$result" "$before_http" "$after_http" "$before_overall" "$after_overall" >/dev/null
  healing_audit_append "action" "$action" "$result" "http ${before_http}->${after_http}"
  healing_alert "action" "$action" "$result" "${SNAPSHOT_HEALING_DETAIL}"

  if (( fail_streak >= HEALTH_HEALING_MAX_FAILURES )); then
    healing_enter_lockout "$now" "$mode" \
      "consecutive action failures (${fail_streak} ≥ ${HEALTH_HEALING_MAX_FAILURES})" \
      "$actions_in_window" "$window_started_at" "$fail_streak" \
      "$last_action" "$last_result" "$last_action_at"
    return 0
  fi

  healing_write_state_merge "$now" "$mode" "${SNAPSHOT_HEALING_STATE}" "${SNAPSHOT_HEALING_DETAIL}" \
    "$last_action" "$last_result" false "" \
    "$actions_in_window" "$window_started_at" "$fail_streak" "$last_action_at"
}

healing_policy_upsert_assignment() {
  local key="$1" value="$2" file="${HEALING_ENV_FILE:-/etc/erpnext-dev/healing.env}"
  local dir tmp line
  healing_env_is_known_key "$key" || return 1
  healing_env_validate_value "$key" "$value" || return 1
  dir="$(dirname "$file")"
  if [[ ! -d "$dir" ]]; then
    if declare -F require_sudo >/dev/null 2>&1; then
      require_sudo
    fi
    ${SUDO:-} mkdir -p "$dir"
  fi
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*${key}= ]] && continue
      # Drop legacy HEALTH_HEALING_MODE lines if migrating into dedicated file.
      [[ "$key" == "HEALING_MODE" && "$line" =~ ^[[:space:]]*HEALTH_HEALING_MODE= ]] && continue
      printf '%s\n' "$line"
    done <"$file" >"$tmp"
  else
    : >"$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  if [[ -w "$(dirname "$file")" ]] || [[ -w "$file" ]]; then
    mv "$tmp" "$file"
  else
    if declare -F require_sudo >/dev/null 2>&1; then
      require_sudo
    fi
    ${SUDO:-} mv "$tmp" "$file"
  fi
  ${SUDO:-} chmod 600 "$file" 2>/dev/null || chmod 600 "$file" 2>/dev/null || true
  healing_env_apply_assignment "$key" "$value" || true
}

healing_policy_upsert_mode() {
  local mode
  mode="$(healing_mode_normalized "$1")"
  healing_policy_upsert_assignment HEALING_MODE "$mode"
  HEALTH_HEALING_MODE="$mode"
}

show_healing_status() {
  local mode state locked last_action last_result actions fail_streak
  if declare -F health_load_policy >/dev/null 2>&1; then
    health_load_policy || true
  fi
  healing_load_policy || true
  mode="$(healing_mode_normalized)"
  state="$(healing_state_get state observing)"
  locked="$(healing_state_get locked false)"
  last_action="$(healing_state_get last_action none)"
  last_result="$(healing_state_get last_action_result none)"
  actions="$(healing_state_get actions_in_window 0)"
  fail_streak="$(healing_state_get consecutive_action_failures 0)"

  if declare -F ui_section_open >/dev/null 2>&1; then
    ui_section_open "Guarded auto-healing"
    dashboard_info_row "Mode" "$mode"
    dashboard_info_row "State" "$state"
    dashboard_info_row "Locked" "$locked"
    dashboard_info_row "Would heal" "${SNAPSHOT_WOULD_HEAL:-$(healing_state_get would_heal none)}"
    dashboard_info_row "Last action" "${last_action} (${last_result})"
    dashboard_info_row "Actions in window" "${actions} / ${HEALTH_HEALING_MAX_ACTIONS}"
    dashboard_info_row "Failure streak" "${fail_streak} / ${HEALTH_HEALING_MAX_FAILURES}"
    dashboard_info_row "restart_web_runtime" "$([[ "${HEALING_ACTION_RESTART_WEB_RUNTIME}" == "1" ]] && echo enabled || echo disabled)"
    dashboard_info_row "restart_app_stack" "$([[ "${HEALING_ACTION_RESTART_APP_STACK}" == "1" ]] && echo enabled || echo disabled)"
    dashboard_info_row "Simulate" "${HEALTH_HEALING_SIMULATE}"
    dashboard_info_row "Policy file" "${HEALING_ENV_FILE}"
    dashboard_info_row "State file" "$(healing_state_file)"
    dashboard_info_row "Audit log" "$(healing_audit_file)"
    if [[ "$locked" == "true" || "$locked" == "1" ]]; then
      dashboard_info_row "Lock reason" "$(healing_state_get lock_reason)"
    fi
    ui_section_close
    ui_next "$(toolkit_cmd healing-policy 2>/dev/null || echo 'erpnext-dev healing-policy')" \
      "$(toolkit_cmd healing-history 2>/dev/null || echo 'erpnext-dev healing-history')" \
      "$(toolkit_cmd healing-disable 2>/dev/null || echo 'erpnext-dev healing-disable')"
  else
    printf 'Healing mode=%s state=%s locked=%s last=%s/%s actions=%s/%s fails=%s/%s policy=%s\n' \
      "$mode" "$state" "$locked" "$last_action" "$last_result" \
      "$actions" "${HEALTH_HEALING_MAX_ACTIONS}" "$fail_streak" "${HEALTH_HEALING_MAX_FAILURES}" \
      "${HEALING_ENV_FILE}"
  fi
}

show_healing_policy() {
  if declare -F health_load_policy >/dev/null 2>&1; then
    health_load_policy || true
  fi
  healing_load_policy || true
  if declare -F ui_section_open >/dev/null 2>&1; then
    ui_section_open "Healing policy"
    dashboard_info_row "File" "${HEALING_ENV_FILE}"
    if [[ -f "${HEALING_ENV_FILE}" ]]; then
      dashboard_info_row "Present" "yes"
    else
      dashboard_info_row "Present" "no (defaults in effect)"
    fi
    dashboard_info_row "HEALING_MODE" "$(healing_mode_normalized)"
    dashboard_info_row "MAX_FAILURES" "${HEALTH_HEALING_MAX_FAILURES}"
    dashboard_info_row "MAX_ACTIONS" "${HEALTH_HEALING_MAX_ACTIONS}"
    dashboard_info_row "ACTION_WINDOW_SEC" "${HEALTH_HEALING_ACTION_WINDOW_SEC}"
    dashboard_info_row "VERIFY_WAIT_SEC" "${HEALTH_HEALING_VERIFY_WAIT_SEC}"
    dashboard_info_row "RESTART_WEB_RUNTIME" "${HEALING_ACTION_RESTART_WEB_RUNTIME}"
    dashboard_info_row "RESTART_APP_STACK" "${HEALING_ACTION_RESTART_APP_STACK}"
    dashboard_info_row "SIMULATE" "${HEALTH_HEALING_SIMULATE}"
    dashboard_info_row "ALERT_ON_LOCKOUT" "${HEALING_ALERT_ON_LOCKOUT}"
    ui_section_close
    if [[ -f "${HEALING_ENV_FILE}" ]]; then
      ui_row_plain "--- ${HEALING_ENV_FILE} ---"
      # Show raw allowlisted lines only (never suggest sourcing).
      grep -E '^[A-Z0-9_]+=' "${HEALING_ENV_FILE}" 2>/dev/null | head -n 40 || true
    fi
    ui_next "$(toolkit_cmd healing-disable 2>/dev/null || echo 'erpnext-dev healing-disable')" \
      "$(toolkit_cmd healing-enable-safe 2>/dev/null || echo 'erpnext-dev healing-enable-safe')" \
      "$(toolkit_cmd healing-status 2>/dev/null || echo 'erpnext-dev healing-status')"
  else
    printf 'policy_file=%s mode=%s web=%s stack=%s simulate=%s\n' \
      "${HEALING_ENV_FILE}" "$(healing_mode_normalized)" \
      "${HEALING_ACTION_RESTART_WEB_RUNTIME}" "${HEALING_ACTION_RESTART_APP_STACK}" \
      "${HEALTH_HEALING_SIMULATE}"
  fi
}

show_healing_history() {
  local n="${1:-20}" audit line t event action result detail
  if declare -F require_sudo >/dev/null 2>&1 && [[ "${HEALING_ENV_SKIP_OWNER_CHECK:-0}" != "1" ]]; then
    require_sudo
  fi
  audit="$(healing_audit_file)"
  if declare -F ui_box_start >/dev/null 2>&1; then
    ui_box_start "Healing audit (last ${n})"
  else
    printf 'Healing audit (last %s)\n' "$n"
  fi
  if [[ ! -f "$audit" ]]; then
    if declare -F status_line >/dev/null 2>&1; then
      status_line "Audit" "INFO" "empty — no healing events yet"
    else
      echo "empty — no healing events yet"
    fi
  else
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      t="$(sed -n 's/.*"t":"\([^"]*\)".*/\1/p' <<<"$line")"
      event="$(sed -n 's/.*"event":"\([^"]*\)".*/\1/p' <<<"$line")"
      action="$(sed -n 's/.*"action":"\([^"]*\)".*/\1/p' <<<"$line")"
      result="$(sed -n 's/.*"result":"\([^"]*\)".*/\1/p' <<<"$line")"
      detail="$(sed -n 's/.*"detail":"\([^"]*\)".*/\1/p' <<<"$line")"
      if declare -F status_line >/dev/null 2>&1; then
        status_line "${t:-unknown}" "INFO" "${event:-?} ${action:--} → ${result:--} ${detail}"
      else
        printf '%s %s %s -> %s %s\n' "${t:-?}" "${event:-?}" "${action:--}" "${result:--}" "${detail}"
      fi
    done < <(tail -n "$n" "$audit")
  fi
  if declare -F ui_box_end >/dev/null 2>&1; then
    ui_box_end
    ui_next "$(toolkit_cmd healing-status)" "$(toolkit_cmd healing-policy)" "$(toolkit_cmd incidents)"
  fi
}

healing_enable_safe() {
  if declare -F require_sudo >/dev/null 2>&1; then
    require_sudo
  fi
  healing_policy_upsert_mode safe
  healing_audit_append "policy" "" "safe" "healing-enable-safe"
  ok "Healing mode set to safe (component/stack restarts; no host reboot)."
  show_healing_status
}

healing_disable() {
  if declare -F require_sudo >/dev/null 2>&1; then
    require_sudo
  fi
  healing_policy_upsert_mode monitor
  healing_audit_append "policy" "" "monitor" "healing-disable"
  ok "Healing disabled (monitor-only)."
  show_healing_status
}

healing_unlock() {
  local now mode
  if declare -F require_sudo >/dev/null 2>&1; then
    require_sudo
  fi
  if declare -F health_load_policy >/dev/null 2>&1; then
    health_load_policy || true
  fi
  healing_load_policy || true
  now="$(date +%s)"
  mode="$(healing_mode_normalized)"
  health_ensure_lib_dirs
  healing_write_state_merge "$now" "$mode" "armed" "Unlocked by operator; failure/action counters reset" \
    "$(healing_state_get last_action)" "$(healing_state_get last_action_result)" \
    false "" 0 "$now" 0 "$(healing_state_get last_action_at 0)"
  healing_audit_append "unlock" "" "ok" "operator cleared lockout"
  ok "Healing lock cleared."
  show_healing_status
}
