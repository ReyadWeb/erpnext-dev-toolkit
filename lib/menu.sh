# shellcheck shell=bash
# Main-menu rendering: polished status strip + responsive two-column layout.
# Reads cached health metrics only (never runs slow probes). See lib/ui.sh.

[[ -n "${_ERPNEXT_DEV_MENU_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_MENU_LOADED=1

# number|label
MAIN_MENU_ITEMS=(
  "1|Start here"
  "2|Production setup"
  "3|Local VM setup"
  "4|Status"
  "5|Start service"
  "6|Stop service"
  "7|Verify access"
  "8|Local HTTPS"
  "9|Local network"
  "10|Production HTTPS"
  "11|Security"
  "12|Backups"
  "13|Apps"
  "14|Advanced"
  "15|Final QA"
  "16|Dashboard"
  "17|Production ops"
  "18|Help"
)

menu_json_string_field() {
  # Best-effort extract of a top-level or nested "key": "value" from a small JSON file.
  # Avoids a jq dependency so the menu stays hermetic on minimal hosts.
  local file="$1" key="$2"
  [[ -f "$file" && -r "$file" ]] || return 1
  sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" 2>/dev/null | head -n 1
}

menu_map_local_https_word() {
  # Prefer recognizing mkcert / self-signed from snapshot detail on local VMs.
  local status="${1:-}" detail="${2:-}"
  local n d
  n="$(printf '%s' "$status" | tr '[:lower:]' '[:upper:]')"
  d="$(printf '%s' "$detail" | tr '[:upper:]' '[:lower:]')"
  case "$n" in
    ""|UNKNOWN|INFO)
      printf 'None'
      return 0
      ;;
  esac
  if [[ "$d" == *mkcert* ]]; then
    printf 'mkcert'
    return 0
  fi
  if [[ "$d" == *self-signed* ]]; then
    printf 'Self-signed'
    return 0
  fi
  case "$n" in
    HEALTHY|OK) printf 'OK' ;;
    DEGRADED|WARN) printf 'Warn' ;;
    CRITICAL|FAIL) printf 'Fail' ;;
    *) printf '%s' "$status" ;;
  esac
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
  local overall https https_detail backup offvm restore runtime site

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
    https_detail="$(menu_json_string_field "$metrics" https_detail || true)"
    backup="$(menu_json_string_field "$metrics" backup || true)"
    offvm="$(menu_json_string_field "$metrics" offsite || true)"
    restore="$(menu_json_string_field "$metrics" restore_rehearsal || true)"
    runtime="$(menu_json_string_field "$metrics" runtime_state || true)"
    [[ -n "$overall" ]] && MENU_STATUS_HEALTH="$(menu_map_health_word health "$overall")"
    if [[ -n "$https" ]]; then
      if [[ "${MENU_STATUS_MODE}" == "local" ]]; then
        MENU_STATUS_HTTPS="$(menu_map_local_https_word "$https" "$https_detail")"
      else
        MENU_STATUS_HTTPS="$(menu_map_health_word https "$https")"
      fi
    fi
    [[ -n "$backup" ]] && MENU_STATUS_BACKUPS="$(menu_map_health_word backup "$backup")"
    [[ -n "$offvm" ]] && MENU_STATUS_OFFVM="$(menu_map_health_word offvm "$offvm")"
    [[ -n "$restore" ]] && MENU_STATUS_RESTORE="$(menu_map_health_word restore "$restore")"
    [[ -n "$runtime" ]] && MENU_STATUS_RUNTIME="$(menu_map_health_word runtime "$runtime")"
  fi

  # Local HTTPS: light file/cert check when snapshot cache is missing or still Unknown.
  if [[ "${MENU_STATUS_MODE}" == "local" ]] && [[ "${MENU_STATUS_HTTPS}" == "Unknown" ]]; then
    if declare -F ssl_local_https_menu_badge >/dev/null 2>&1; then
      MENU_STATUS_HTTPS="$(ssl_local_https_menu_badge 2>/dev/null || echo None)"
    else
      MENU_STATUS_HTTPS="None"
    fi
  fi

  # Go-live record is a tiny env file — safe and fast.
  # Local VMs do not use production go-live sign-off; show Local instead of Unknown.
  if declare -F go_live_recorded_ok >/dev/null 2>&1 && go_live_recorded_ok 2>/dev/null; then
    MENU_STATUS_GOLIVE="Recorded"
  elif [[ -n "${GO_LIVE_RECORD_FILE:-}" && -r "${GO_LIVE_RECORD_FILE}" ]]; then
    MENU_STATUS_GOLIVE="Partial"
  elif [[ "${MENU_STATUS_MODE}" == "local" ]]; then
    MENU_STATUS_GOLIVE="Local"
  fi
}

render_main_status_panel() {
  local width runtime_color layout
  width="$(ui_panel_width)"
  runtime_color="$(ui_status_color "$MENU_STATUS_RUNTIME")"
  layout="$(ui_layout_mode)"

  ui_box_line top "$width"

  if [[ "$layout" == "wide" ]]; then
    # Wide: one-line identity strip.
    ui_row_begin
    ui_row_add_colored cyan "Toolkit:"
    ui_row_add " "
    ui_row_add "$(printf '%-8s' "v${SCRIPT_VERSION:-unknown}")"
    ui_row_add " "
    ui_row_add "$UI_DIV"
    ui_row_add " "
    ui_row_add_colored cyan "Site:"
    ui_row_add " "
    ui_row_add "$(printf '%-20s' "${MENU_STATUS_SITE:0:20}")"
    ui_row_add " "
    ui_row_add "$UI_DIV"
    ui_row_add " "
    ui_row_add_colored cyan "Mode:"
    ui_row_add " "
    ui_row_add "$(printf '%-10s' "${MENU_STATUS_MODE:0:10}")"
    ui_row_add " "
    ui_row_add "$UI_DIV"
    ui_row_add " "
    ui_row_add_colored cyan "Runtime:"
    ui_row_add " "
    ui_row_add_colored "$runtime_color" "$MENU_STATUS_RUNTIME"
    ui_row_end
  else
    # Ordinary SSH terminals: two calm rows instead of cramming the runtime
    # against the right border.
    ui_row_begin
    ui_row_add_colored cyan "Toolkit:"
    ui_row_add " "
    ui_row_add "v${SCRIPT_VERSION:-unknown}"
    ui_row_add "  "
    ui_row_add "$UI_DIV"
    ui_row_add "  "
    ui_row_add_colored cyan "Site:"
    ui_row_add " "
    ui_row_add "${MENU_STATUS_SITE:0:28}"
    ui_row_end
    ui_row_begin
    ui_row_add_colored cyan "Mode:"
    ui_row_add " "
    ui_row_add "${MENU_STATUS_MODE:0:16}"
    ui_row_add "  "
    ui_row_add "$UI_DIV"
    ui_row_add "  "
    ui_row_add_colored cyan "Runtime:"
    ui_row_add " "
    ui_row_add_colored "$runtime_color" "$MENU_STATUS_RUNTIME"
    ui_row_end
  fi

  ui_box_line mid "$width"

  # Badge rows: never a single long strip (Go-live was overflowing the border).
  if [[ "$layout" == "compact" ]]; then
    ui_row_begin
    ui_row_add_badge "Health" "$MENU_STATUS_HEALTH"
    ui_row_add "  "
    ui_row_add_badge "HTTPS" "$MENU_STATUS_HTTPS"
    ui_row_add "  "
    ui_row_add_badge "Backups" "$MENU_STATUS_BACKUPS"
    ui_row_end
  else
    ui_row_begin
    ui_row_add_badge "HTTPS" "$MENU_STATUS_HTTPS"
    ui_row_add "  "
    ui_row_add_badge "Backups" "$MENU_STATUS_BACKUPS"
    ui_row_add "  "
    ui_row_add_badge "Off-VM" "$MENU_STATUS_OFFVM"
    ui_row_add "  "
    ui_row_add_badge "Restore" "$MENU_STATUS_RESTORE"
    ui_row_end
    ui_row_begin
    ui_row_add_badge "Health" "$MENU_STATUS_HEALTH"
    ui_row_add "  "
    ui_row_add_badge "Go-live" "$MENU_STATUS_GOLIVE"
    ui_row_end
  fi

  ui_box_line bot "$width"
}

render_main_menu_options() {
  ui_render_boxed_menu "${MAIN_MENU_ITEMS[@]}"
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
  render_main_menu_options

  printf '\n'
  ui_text cyan "[q]"
  printf ' Quit\n\n'
}

show_menu() {
  local choice
  while true; do
    ui_clear_screen
    render_main_menu_screen
    ui_prompt "Choose an option: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      ui_clear_screen
    fi

    case "$choice" in
      1) run_first_run_wizard ;;
      2) run_public_vm_guided_setup; pause_after_screen "Press Enter to return to Main menu..." ;;
      3) run_local_dev_quickstart; pause_after_screen "Press Enter to return to Main menu..." ;;
      4) show_status_menu ;;
      5) run_start; pause_after_screen "Press Enter to return to Main menu..." ;;
      6) run_stop; pause_after_screen "Press Enter to return to Main menu..." ;;
      7) verify_access; pause_after_screen "Press Enter to return to Main menu..." ;;
      8) show_local_ssl_menu ;;
      9) show_local_ip_menu ;;
      10) show_production_ssl_menu ;;
      11) security_hardening_wizard ;;
      12) run_backup_maintenance_menu ;;
      13) show_app_library_menu ;;
      14) show_advanced_menu ;;
      15) final_qa_wizard ;;
      16) run_operations_dashboard; pause_after_screen "Press Enter to return to Main menu..." ;;
      17) production_ops_wizard ;;
      18) show_help; pause_after_screen "Press Enter to return to Main menu..." ;;
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
