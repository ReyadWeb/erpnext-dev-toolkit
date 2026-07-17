# shellcheck shell=bash
# Main-menu rendering: polished status strip + responsive two-column layout.
# Reads cached health metrics only (never runs slow probes). See lib/ui.sh.

[[ -n "${_ERPNEXT_DEV_MENU_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_MENU_LOADED=1

# number|label
MAIN_MENU_ITEMS=(
  "1|Start here / setup wizard"
  "2|Public VM quickstart"
  "3|Local VM quickstart"
  "4|Status"
  "5|Start service"
  "6|Stop service"
  "7|Verify access"
  "8|Local VM HTTPS / SSL"
  "9|Production HTTPS / SSL"
  "10|Security profiles"
  "11|Backup / maintenance"
  "12|Optional apps"
  "13|Advanced"
  "14|Final QA"
  "15|Operations dashboard"
  "16|Production operations"
  "17|Help"
)

menu_json_string_field() {
  # Best-effort extract of a top-level or nested "key": "value" from a small JSON file.
  # Avoids a jq dependency so the menu stays hermetic on minimal hosts.
  local file="$1" key="$2"
  [[ -f "$file" && -r "$file" ]] || return 1
  sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" 2>/dev/null | head -n 1
}

menu_map_health_word() {
  # Map canonical HEALTHY/DEGRADED/CRITICAL (or legacy OK/WARN/FAIL) to short badge words.
  local kind="$1" raw="$2"
  local n
  n="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')"
  case "$n" in
    ""|UNKNOWN|INFO) printf 'Unknown'; return 0 ;;
  esac
  case "$kind" in
    health)
      case "$n" in
        HEALTHY|OK) printf 'Active' ;;
        DEGRADED|WARN) printf 'Degraded' ;;
        CRITICAL|FAIL) printf 'Critical' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    https|backup)
      case "$n" in
        HEALTHY|OK) printf 'OK' ;;
        DEGRADED|WARN) printf 'Warn' ;;
        CRITICAL|FAIL) printf 'Fail' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    offvm)
      case "$n" in
        HEALTHY|OK) printf 'Verified' ;;
        DEGRADED|WARN) printf 'Warn' ;;
        CRITICAL|FAIL) printf 'Fail' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    restore)
      case "$n" in
        HEALTHY|OK) printf 'Rehearsed' ;;
        DEGRADED|WARN) printf 'Due' ;;
        CRITICAL|FAIL) printf 'Missing' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    runtime)
      case "$n" in
        RUNNING*|HEALTHY|OK) printf 'Running' ;;
        STOPPED*|FAIL|CRITICAL) printf 'Stopped' ;;
        DEGRADED|WARN) printf 'Degraded' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

load_menu_status_fast() {
  # Populate MENU_STATUS_* from cached snapshot / light files only.
  local metrics="${HEALTH_LIB_DIR:-/var/lib/erpnext-dev}/metrics/current.json"
  local overall https backup offvm restore runtime site

  MENU_STATUS_SITE="${PRODUCTION_DOMAIN:-${SITE_NAME:-unknown}}"
  if declare -F is_public_vm_workflow >/dev/null 2>&1 && is_public_vm_workflow 2>/dev/null; then
    MENU_STATUS_MODE="public-vm"
  else
    case "${DEPLOYMENT_MODE:-development}" in
      production|public|public-vm) MENU_STATUS_MODE="public-vm" ;;
      *) MENU_STATUS_MODE="local" ;;
    esac
  fi

  MENU_STATUS_RUNTIME="Unknown"
  MENU_STATUS_HTTPS="Unknown"
  MENU_STATUS_BACKUPS="Unknown"
  MENU_STATUS_OFFVM="Unknown"
  MENU_STATUS_RESTORE="Unknown"
  MENU_STATUS_HEALTH="Unknown"
  MENU_STATUS_GOLIVE="Unknown"

  if [[ -f "$metrics" && -r "$metrics" ]]; then
    site="$(menu_json_string_field "$metrics" site || true)"
    [[ -n "$site" ]] && MENU_STATUS_SITE="$site"
    overall="$(menu_json_string_field "$metrics" overall_status || true)"
    https="$(menu_json_string_field "$metrics" https || true)"
    backup="$(menu_json_string_field "$metrics" backup || true)"
    offvm="$(menu_json_string_field "$metrics" offsite || true)"
    restore="$(menu_json_string_field "$metrics" restore_rehearsal || true)"
    runtime="$(menu_json_string_field "$metrics" runtime_state || true)"
    [[ -n "$overall" ]] && MENU_STATUS_HEALTH="$(menu_map_health_word health "$overall")"
    [[ -n "$https" ]] && MENU_STATUS_HTTPS="$(menu_map_health_word https "$https")"
    [[ -n "$backup" ]] && MENU_STATUS_BACKUPS="$(menu_map_health_word backup "$backup")"
    [[ -n "$offvm" ]] && MENU_STATUS_OFFVM="$(menu_map_health_word offvm "$offvm")"
    [[ -n "$restore" ]] && MENU_STATUS_RESTORE="$(menu_map_health_word restore "$restore")"
    [[ -n "$runtime" ]] && MENU_STATUS_RUNTIME="$(menu_map_health_word runtime "$runtime")"
  fi

  # Go-live record is a tiny env file — safe and fast.
  if declare -F go_live_recorded_ok >/dev/null 2>&1 && go_live_recorded_ok 2>/dev/null; then
    MENU_STATUS_GOLIVE="Recorded"
  elif [[ -n "${GO_LIVE_RECORD_FILE:-}" && -r "${GO_LIVE_RECORD_FILE}" ]]; then
    MENU_STATUS_GOLIVE="Partial"
  fi
}

render_main_status_panel() {
  local width
  width="$(ui_panel_width)"

  ui_box_line top "$width"

  # Line 1: toolkit / site / mode / runtime
  printf '%s ' "$UI_V"
  ui_text cyan "Toolkit:"
  printf ' %-8s ' "v${SCRIPT_VERSION:-unknown}"
  printf '%s ' "$UI_DIV"
  ui_text cyan "Site:"
  printf ' %-20s ' "${MENU_STATUS_SITE:0:20}"
  printf '%s ' "$UI_DIV"
  ui_text cyan "Mode:"
  printf ' %-10s ' "${MENU_STATUS_MODE:0:10}"
  printf '%s ' "$UI_DIV"
  ui_text cyan "Runtime:"
  printf ' '
  ui_text "$(ui_status_color "$MENU_STATUS_RUNTIME")" "$MENU_STATUS_RUNTIME"
  printf ' %s\n' "$UI_V"

  ui_box_line mid "$width"

  # Line 2: badge strip (wraps visually on narrow panels via truncation of spacing)
  printf '%s ' "$UI_V"
  if [[ "$(ui_layout_mode)" == "compact" ]]; then
    ui_status_badge "Health" "$MENU_STATUS_HEALTH"
    printf '  '
    ui_status_badge "HTTPS" "$MENU_STATUS_HTTPS"
    printf '  '
    ui_status_badge "Backups" "$MENU_STATUS_BACKUPS"
  else
    ui_status_badge "HTTPS" "$MENU_STATUS_HTTPS"
    printf '  '
    ui_status_badge "Backups" "$MENU_STATUS_BACKUPS"
    printf '  '
    ui_status_badge "Off-VM" "$MENU_STATUS_OFFVM"
    printf '  '
    ui_status_badge "Restore" "$MENU_STATUS_RESTORE"
    printf '  '
    ui_status_badge "Health" "$MENU_STATUS_HEALTH"
    printf '  '
    ui_status_badge "Go-live" "$MENU_STATUS_GOLIVE"
  fi
  printf ' %s\n' "$UI_V"

  ui_box_line bot "$width"
}

render_main_menu_wide() {
  local width left_width right_width i left right ln lt rn rt
  local total="${#MAIN_MENU_ITEMS[@]}"
  local half=$(( (total + 1) / 2 ))
  width="$(ui_panel_width)"
  left_width=$(( width / 2 - 4 ))
  right_width=$(( width - left_width - 7 ))
  (( left_width < 24 )) && left_width=24
  (( right_width < 24 )) && right_width=24

  ui_box_line top "$width"
  for (( i = 0; i < half; i++ )); do
    left="${MAIN_MENU_ITEMS[$i]:-}"
    right="${MAIN_MENU_ITEMS[$((i + half))]:-}"
    ln="${left%%|*}"
    lt="${left#*|}"
    # Truncate labels that would overflow the column on ~80-col terminals.
    if (( ${#lt} > left_width - 5 )); then
      lt="${lt:0:$((left_width - 8))}..."
    fi
    printf '%s ' "$UI_V"
    ui_text cyan "[${ln}]"
    printf ' %-*s ' "$((left_width - 5))" "$lt"
    printf '%s ' "$UI_DIV"
    if [[ -n "$right" ]]; then
      rn="${right%%|*}"
      rt="${right#*|}"
      if (( ${#rt} > right_width - 5 )); then
        rt="${rt:0:$((right_width - 8))}..."
      fi
      ui_text cyan "[${rn}]"
      printf ' %-*s' "$((right_width - 5))" "$rt"
    else
      printf '%-*s' "$right_width" ""
    fi
    printf ' %s\n' "$UI_V"
  done
  ui_box_line bot "$width"
}

render_main_menu_compact() {
  local item number label
  for item in "${MAIN_MENU_ITEMS[@]}"; do
    number="${item%%|*}"
    label="${item#*|}"
    ui_text cyan "[${number}]"
    printf ' %s\n' "$label"
  done
}

render_main_menu_screen() {
  ui_init
  load_menu_status_fast

  ui_text cyan "${APP_NAME:-ERPNext Developer Toolkit}"
  printf ' '
  ui_text muted "v${SCRIPT_VERSION:-unknown}"
  if [[ "$(ui_layout_mode)" != "compact" ]]; then
    printf '    '
    ui_text muted "Type number + Enter"
  fi
  printf '\n\n'

  render_main_status_panel
  printf '\n'

  case "$(ui_layout_mode)" in
    wide|medium) render_main_menu_wide ;;
    *) render_main_menu_compact ;;
  esac

  printf '\n'
  ui_text cyan "[q]"
  printf ' Quit\n\n'
}

show_menu() {
  local choice
  while true; do
    if [[ -t 1 && "${MENU_NO_CLEAR:-0}" != "1" ]]; then
      clear 2>/dev/null || true
    fi
    render_main_menu_screen
    ui_prompt "Choose an option: " choice

    case "$choice" in
      1) run_first_run_wizard ;;
      2) run_public_vm_guided_setup ;;
      3) run_local_dev_quickstart ;;
      4) show_status_menu ;;
      5) run_start ;;
      6) run_stop ;;
      7) verify_access ;;
      8) show_local_ssl_menu ;;
      9) show_production_ssl_menu ;;
      10) security_hardening_wizard ;;
      11) run_backup_maintenance_menu ;;
      12) show_app_library_menu ;;
      13) show_advanced_menu ;;
      14) final_qa_wizard ;;
      15) run_operations_dashboard ;;
      16) production_ops_wizard ;;
      17) show_help ;;
      q|Q) exit 0 ;;
      *)
        warn "Invalid option"
        sleep 0.6 2>/dev/null || true
        ;;
    esac
  done
}

# Non-interactive render for CI (no clear, no read).
menu_render_test() {
  FORCE_NO_COLOR=1
  NO_COLOR=1
  export FORCE_NO_COLOR NO_COLOR
  MENU_NO_CLEAR=1
  MENU_FORCE_ONE_COLUMN="${MENU_FORCE_ONE_COLUMN:-false}"
  UI_FORCE_ASCII="${UI_FORCE_ASCII:-0}"
  render_main_menu_screen
  ui_text cyan "Choose an option:"
  printf ' \n'
}
