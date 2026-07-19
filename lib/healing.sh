# shellcheck shell=bash
# Guarded auto-healing MVP (v1.19.0). Default mode is monitor-only; safe/advanced
# execute a small restart ladder with cooldowns, lockout, and recovery verification.
# Sourced by the toolkit entry point after lib/dashboard.sh; do not execute directly.

[[ -n "${_ERPNEXT_DEV_HEALING_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_HEALING_LOADED=1

: "${HEALTH_HEALING_MODE:=monitor}"
: "${HEALTH_HEALING_MAX_FAILURES:=3}"
: "${HEALTH_HEALING_MAX_ACTIONS:=5}"
: "${HEALTH_HEALING_ACTION_WINDOW_SEC:=3600}"
: "${HEALTH_HEALING_VERIFY_WAIT_SEC:=5}"
# Hermetic / CI: record the action path without calling restart helpers.
: "${HEALTH_HEALING_SIMULATE:=0}"

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
  # Recovery succeeds when HTTP leaves CRITICAL (or was never CRITICAL and stays non-CRITICAL).
  if [[ "$(health_status_normalize "$before_http")" == "CRITICAL" ]]; then
    [[ "$(health_status_normalize "$after_http")" != "CRITICAL" ]]
    return $?
  fi
  [[ "$(health_status_normalize "$after_http")" != "CRITICAL" ]]
}

healing_write_state_merge() {
  # Merge healing execute fields into state.json while preserving streak fields
  # written by health_cooldown_tick.
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
}

healing_apply_snapshot_fields() {
  local mode detail
  mode="$(healing_mode_normalized)"
  # Snapshot fields are rendered by lib/dashboard.sh after this module runs.
  # shellcheck disable=SC2034
  SNAPSHOT_HEALING_MODE="$mode"
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

healing_maybe_execute() {
  local mode action now before_http before_overall after_pair after_http after_overall
  local result="skipped" verify_ok=0 restart_ok=0
  local actions_in_window=0 window_started_at=0 fail_streak=0 locked=false lock_reason=""
  local last_action="" last_result="" last_action_at=0

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

  # advanced currently shares the safe ladder (no host reboot in MVP).
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
    locked=true
    lock_reason="max actions (${HEALTH_HEALING_MAX_ACTIONS}) in ${HEALTH_HEALING_ACTION_WINDOW_SEC}s window"
    SNAPSHOT_HEALING_STATE="locked"
    SNAPSHOT_WOULD_HEAL="locked"
    SNAPSHOT_HEALING_DETAIL="AUTO-HEALING LOCKED: ${lock_reason} — run healing-unlock"
    healing_write_state_merge "$now" "$mode" "locked" "${SNAPSHOT_HEALING_DETAIL}" \
      "$(healing_state_get last_action)" "locked" true "$lock_reason" \
      "$actions_in_window" "$window_started_at" "$fail_streak" \
      "$(healing_state_get last_action_at 0)"
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
    if (( fail_streak >= HEALTH_HEALING_MAX_FAILURES )); then
      locked=true
      lock_reason="consecutive action failures (${fail_streak} ≥ ${HEALTH_HEALING_MAX_FAILURES})"
      SNAPSHOT_HEALING_STATE="locked"
      SNAPSHOT_WOULD_HEAL="locked"
      SNAPSHOT_HEALING_DETAIL="AUTO-HEALING LOCKED: ${lock_reason} — run healing-unlock"
    fi
  fi
  last_result="$result"

  healing_record_action_incident "$action" "$result" "$before_http" "$after_http" "$before_overall" "$after_overall" >/dev/null

  if [[ "$locked" == "true" ]]; then
    healing_write_state_merge "$now" "$mode" "locked" "${SNAPSHOT_HEALING_DETAIL}" \
      "$last_action" "$last_result" true "$lock_reason" \
      "$actions_in_window" "$window_started_at" "$fail_streak" "$last_action_at"
  else
    healing_write_state_merge "$now" "$mode" "${SNAPSHOT_HEALING_STATE}" "${SNAPSHOT_HEALING_DETAIL}" \
      "$last_action" "$last_result" false "" \
      "$actions_in_window" "$window_started_at" "$fail_streak" "$last_action_at"
  fi
}

healing_policy_upsert_mode() {
  local mode="$1" file="${HEALTH_ENV_FILE:-/etc/erpnext-dev/health.env}"
  local dir tmp line
  mode="$(healing_mode_normalized "$mode")"
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
      [[ "$line" =~ ^[[:space:]]*HEALTH_HEALING_MODE= ]] && continue
      printf '%s\n' "$line"
    done <"$file" >"$tmp"
  else
    : >"$tmp"
  fi
  printf 'HEALTH_HEALING_MODE=%s\n' "$mode" >>"$tmp"
  if [[ -w "$(dirname "$file")" ]] || [[ -w "$file" ]]; then
    mv "$tmp" "$file"
  else
    if declare -F require_sudo >/dev/null 2>&1; then
      require_sudo
    fi
    ${SUDO:-} mv "$tmp" "$file"
  fi
  ${SUDO:-} chmod 600 "$file" 2>/dev/null || chmod 600 "$file" 2>/dev/null || true
  HEALTH_HEALING_MODE="$mode"
}

show_healing_status() {
  local mode state locked last_action last_result actions fail_streak
  if declare -F health_load_policy >/dev/null 2>&1; then
    health_load_policy || true
  fi
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
    dashboard_info_row "Policy file" "${HEALTH_ENV_FILE:-/etc/erpnext-dev/health.env}"
    dashboard_info_row "State file" "$(healing_state_file)"
    if [[ "$locked" == "true" || "$locked" == "1" ]]; then
      dashboard_info_row "Lock reason" "$(healing_state_get lock_reason)"
    fi
    ui_section_close
    ui_next "$(toolkit_cmd healing-enable-safe 2>/dev/null || echo 'erpnext-dev healing-enable-safe')" \
      "$(toolkit_cmd healing-disable 2>/dev/null || echo 'erpnext-dev healing-disable')" \
      "$(toolkit_cmd healing-unlock 2>/dev/null || echo 'erpnext-dev healing-unlock')"
  else
    printf 'Healing mode=%s state=%s locked=%s last=%s/%s actions=%s/%s fails=%s/%s\n' \
      "$mode" "$state" "$locked" "$last_action" "$last_result" \
      "$actions" "${HEALTH_HEALING_MAX_ACTIONS}" "$fail_streak" "${HEALTH_HEALING_MAX_FAILURES}"
  fi
}

healing_enable_safe() {
  if declare -F require_sudo >/dev/null 2>&1; then
    require_sudo
  fi
  healing_policy_upsert_mode safe
  ok "Healing mode set to safe (component/stack restarts; no host reboot)."
  show_healing_status
}

healing_disable() {
  if declare -F require_sudo >/dev/null 2>&1; then
    require_sudo
  fi
  healing_policy_upsert_mode monitor
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
  now="$(date +%s)"
  mode="$(healing_mode_normalized)"
  health_ensure_lib_dirs
  healing_write_state_merge "$now" "$mode" "armed" "Unlocked by operator; failure/action counters reset" \
    "$(healing_state_get last_action)" "$(healing_state_get last_action_result)" \
    false "" 0 "$now" 0 "$(healing_state_get last_action_at 0)"
  ok "Healing lock cleared."
  show_healing_status
}
