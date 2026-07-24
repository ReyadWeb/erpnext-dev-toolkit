# shellcheck shell=bash
# Main-menu rendering: polished status strip + responsive two-column layout.
# Reads cached health metrics only (never runs slow probes). See lib/ui.sh.

[[ -n "${_ERPNEXT_DEV_MENU_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_MENU_LOADED=1

# number|label
MAIN_MENU_ITEMS=(
  "1|Start here"
  "2|Local development"
  "3|Production setup"
  "4|Status"
  "5|Network & access"
  "6|HTTPS & domains"
  "7|Apps"
  "8|Security"
  "9|Backups & restore"
  "10|Operations"
  "11|Advanced"
  "12|Help"
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
    "" | UNKNOWN | INFO)
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
    HEALTHY | OK) printf 'OK' ;;
    DEGRADED | WARN) printf 'Warn' ;;
    CRITICAL | FAIL) printf 'Fail' ;;
    *) printf '%s' "$status" ;;
  esac
}

menu_map_health_word() {
  # Map canonical HEALTHY/DEGRADED/CRITICAL (or legacy OK/WARN/FAIL) to short badge words.
  local kind="$1" raw="$2"
  local n
  n="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')"
  case "$n" in
    "" | UNKNOWN | INFO)
      printf 'Unknown'
      return 0
      ;;
  esac
  case "$kind" in
    health)
      case "$n" in
        HEALTHY | OK) printf 'Active' ;;
        DEGRADED | WARN) printf 'Degraded' ;;
        CRITICAL | FAIL) printf 'Critical' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    https | backup)
      case "$n" in
        HEALTHY | OK) printf 'OK' ;;
        DEGRADED | WARN) printf 'Warn' ;;
        CRITICAL | FAIL) printf 'Fail' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    offvm)
      case "$n" in
        HEALTHY | OK) printf 'Verified' ;;
        DEGRADED | WARN) printf 'Warn' ;;
        CRITICAL | FAIL) printf 'Fail' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    restore)
      case "$n" in
        HEALTHY | OK) printf 'Rehearsed' ;;
        DEGRADED | WARN) printf 'Due' ;;
        CRITICAL | FAIL) printf 'Missing' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    runtime)
      case "$n" in
        RUNNING* | HEALTHY | OK) printf 'Running' ;;
        STOPPED* | FAIL | CRITICAL) printf 'Stopped' ;;
        DEGRADED | WARN) printf 'Degraded' ;;
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
      production | public | public-vm) MENU_STATUS_MODE="public-vm" ;;
      *) MENU_STATUS_MODE="local" ;;
    esac
  fi

  if declare -F effective_deployment_engine >/dev/null 2>&1; then
    case "$(effective_deployment_engine 2>/dev/null || echo native)" in
      docker) MENU_STATUS_ENGINE="Docker" ;;
      *) MENU_STATUS_ENGINE="Native" ;;
    esac
  else
    case "${DEPLOYMENT_ENGINE:-native}" in
      docker) MENU_STATUS_ENGINE="Docker" ;;
      *) MENU_STATUS_ENGINE="Native" ;;
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

menu_metric_percent_color() {
  local kind="${1:-generic}" pct="${2:-0}" warn_at=70 critical_at=85
  [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
  case "$kind" in
    disk)
      warn_at=75
      critical_at=90
      ;;
    cpu | ram)
      warn_at=70
      critical_at=85
      ;;
  esac
  if ((pct >= critical_at)); then
    printf 'red'
  elif ((pct >= warn_at)); then
    printf 'orange'
  else
    printf 'green'
  fi
}

menu_metric_gib() {
  local kib="${1:-0}"
  awk -v kib="$kib" 'BEGIN { printf "%.1f", kib / 1024 / 1024 }'
}

menu_metric_cpu_percent() {
  local user1 nice1 sys1 idle1 iowait1 irq1 softirq1 steal1
  local user2 nice2 sys2 idle2 iowait2 irq2 softirq2 steal2
  local total1 total2 idle_all1 idle_all2 delta_total delta_idle busy

  IFS=$' \t' read -r _ user1 nice1 sys1 idle1 iowait1 irq1 softirq1 steal1 _ </proc/stat 2>/dev/null || {
    printf '0'
    return 0
  }
  sleep "${MENU_CPU_SAMPLE_SEC:-0.08}"
  IFS=$' \t' read -r _ user2 nice2 sys2 idle2 iowait2 irq2 softirq2 steal2 _ </proc/stat 2>/dev/null || {
    printf '0'
    return 0
  }

  total1=$((user1 + nice1 + sys1 + idle1 + iowait1 + irq1 + softirq1 + steal1))
  total2=$((user2 + nice2 + sys2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
  idle_all1=$((idle1 + iowait1))
  idle_all2=$((idle2 + iowait2))
  delta_total=$((total2 - total1))
  delta_idle=$((idle_all2 - idle_all1))
  if ((delta_total <= 0)); then
    printf '0'
    return 0
  fi
  busy=$(((100 * (delta_total - delta_idle)) / delta_total))
  ((busy < 0)) && busy=0
  ((busy > 100)) && busy=100
  printf '%s' "$busy"
}

menu_metric_uptime_short() {
  local seconds days hours minutes
  seconds="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
  [[ "$seconds" =~ ^[0-9]+$ ]] || seconds=0
  days=$((seconds / 86400))
  hours=$(((seconds % 86400) / 3600))
  minutes=$(((seconds % 3600) / 60))
  if ((days > 0)); then
    printf '%sd %sh' "$days" "$hours"
  elif ((hours > 0)); then
    printf '%sh %sm' "$hours" "$minutes"
  else
    printf '%sm' "$minutes"
  fi
}

load_menu_system_metrics_fast() {
  # Lightweight host-only metrics. No Docker, Bench, DNS, HTTP, certificate, or
  # backup probes are allowed here; the main menu must remain effectively instant.
  local mem_total mem_available mem_used
  local disk_used disk_total disk_pct_raw disk_line
  local load_line tasks

  MENU_METRIC_CPU_PCT="$(menu_metric_cpu_percent)"

  mem_total="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
  mem_available="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
  [[ "$mem_total" =~ ^[0-9]+$ ]] || mem_total=0
  [[ "$mem_available" =~ ^[0-9]+$ ]] || mem_available=0
  mem_used=$((mem_total - mem_available))
  ((mem_used < 0)) && mem_used=0
  if ((mem_total > 0)); then
    MENU_METRIC_RAM_PCT=$(((mem_used * 100) / mem_total))
  else
    MENU_METRIC_RAM_PCT=0
  fi
  MENU_METRIC_RAM_USED_GIB="$(menu_metric_gib "$mem_used")"
  MENU_METRIC_RAM_TOTAL_GIB="$(menu_metric_gib "$mem_total")"

  # Root filesystem metrics from the final POSIX df data row. Using the
  # complete row avoids fragile field filtering and works with long device names.
  disk_line="$(LC_ALL=C command df -Pk / 2>/dev/null | tail -n 1 || true)"
  disk_total=0
  disk_used=0
  disk_pct_raw=""
  IFS=$' \t' read -r _ disk_total disk_used _ disk_pct_raw _ <<<"$disk_line" || true
  [[ "$disk_total" =~ ^[0-9]+$ ]] || disk_total=0
  [[ "$disk_used" =~ ^[0-9]+$ ]] || disk_used=0
  if [[ "$disk_pct_raw" =~ ^([0-9]+)%$ ]]; then
    MENU_METRIC_DISK_PCT="${BASH_REMATCH[1]}"
  elif ((disk_total > 0)); then
    MENU_METRIC_DISK_PCT=$(((disk_used * 100) / disk_total))
  else
    MENU_METRIC_DISK_PCT=0
  fi
  MENU_METRIC_DISK_USED_GIB="$(menu_metric_gib "$disk_used")"
  MENU_METRIC_DISK_TOTAL_GIB="$(menu_metric_gib "$disk_total")"

  load_line="$(cat /proc/loadavg 2>/dev/null || true)"
  MENU_METRIC_LOAD_1="$(awk '{print $1}' <<<"$load_line")"
  MENU_METRIC_LOAD_5="$(awk '{print $2}' <<<"$load_line")"
  MENU_METRIC_LOAD_15="$(awk '{print $3}' <<<"$load_line")"
  tasks="$(awk '{print $4}' <<<"$load_line")"
  MENU_METRIC_TASKS_RUNNING="${tasks%%/*}"
  MENU_METRIC_TASKS_TOTAL="${tasks##*/}"
  [[ "$MENU_METRIC_TASKS_RUNNING" =~ ^[0-9]+$ ]] || MENU_METRIC_TASKS_RUNNING=0
  [[ "$MENU_METRIC_TASKS_TOTAL" =~ ^[0-9]+$ ]] || MENU_METRIC_TASKS_TOTAL=0
  MENU_METRIC_UPTIME="$(menu_metric_uptime_short)"
}

render_main_resources_panel() {
  local width mode cpu_color ram_color disk_color
  width="$(ui_panel_width)"
  mode="$(ui_dashboard_layout_mode)"
  cpu_color="$(menu_metric_percent_color cpu "$MENU_METRIC_CPU_PCT")"
  ram_color="$(menu_metric_percent_color ram "$MENU_METRIC_RAM_PCT")"
  disk_color="$(menu_metric_percent_color disk "$MENU_METRIC_DISK_PCT")"

  ui_box_titled_top "System Overview" "$width"

  if [[ "$mode" == "wide" ]]; then
    ui_row_begin
    ui_row_add_colored cyan "CPU"
    ui_row_add "  "
    ui_row_add_colored "$cpu_color" "${MENU_METRIC_CPU_PCT}%"
    ui_row_add " "
    ui_row_add_percent_bar "$cpu_color" "$MENU_METRIC_CPU_PCT" 10
    ui_row_add "      "
    ui_row_add_colored cyan "RAM"
    ui_row_add "  "
    ui_row_add_colored "$ram_color" "${MENU_METRIC_RAM_PCT}%"
    ui_row_add " "
    ui_row_add_percent_bar "$ram_color" "$MENU_METRIC_RAM_PCT" 10
    ui_row_add " ${MENU_METRIC_RAM_USED_GIB}/${MENU_METRIC_RAM_TOTAL_GIB}G"
    ui_row_end

    ui_row_begin
    ui_row_add_colored cyan "Disk"
    ui_row_add " "
    ui_row_add_colored "$disk_color" "${MENU_METRIC_DISK_PCT}%"
    ui_row_add " "
    ui_row_add_percent_bar "$disk_color" "$MENU_METRIC_DISK_PCT" 10
    ui_row_add " ${MENU_METRIC_DISK_USED_GIB}/${MENU_METRIC_DISK_TOTAL_GIB}G"
    ui_row_add "      "
    ui_row_add_colored cyan "Tasks"
    ui_row_add " ${MENU_METRIC_TASKS_RUNNING} running / ${MENU_METRIC_TASKS_TOTAL} total"
    ui_row_end

    ui_row_begin
    ui_row_add_colored cyan "Load"
    ui_row_add " ${MENU_METRIC_LOAD_1:-0.00}/${MENU_METRIC_LOAD_5:-0.00}/${MENU_METRIC_LOAD_15:-0.00}"
    ui_row_add "      "
    ui_row_add_colored cyan "Up"
    ui_row_add " ${MENU_METRIC_UPTIME}"
    ui_row_end
  elif [[ "$mode" == "compact" ]]; then
    ui_row_begin
    ui_row_add_colored cyan "CPU"
    ui_row_add " "
    ui_row_add_colored "$cpu_color" "${MENU_METRIC_CPU_PCT}%"
    ui_row_add "   "
    ui_row_add_colored cyan "RAM"
    ui_row_add " "
    ui_row_add_colored "$ram_color" "${MENU_METRIC_RAM_PCT}%"
    ui_row_add " ${MENU_METRIC_RAM_USED_GIB}/${MENU_METRIC_RAM_TOTAL_GIB}G"
    ui_row_add "   "
    ui_row_add_colored cyan "Disk"
    ui_row_add " "
    ui_row_add_colored "$disk_color" "${MENU_METRIC_DISK_PCT}%"
    ui_row_end

    ui_row_begin
    ui_row_add_colored cyan "Tasks"
    ui_row_add " ${MENU_METRIC_TASKS_RUNNING}/${MENU_METRIC_TASKS_TOTAL}"
    ui_row_add "   "
    ui_row_add_colored cyan "Load"
    ui_row_add " ${MENU_METRIC_LOAD_1:-0.00}/${MENU_METRIC_LOAD_5:-0.00}/${MENU_METRIC_LOAD_15:-0.00}"
    ui_row_add "   "
    ui_row_add_colored cyan "Up"
    ui_row_add " ${MENU_METRIC_UPTIME}"
    ui_row_end
  else
    ui_row_begin
    ui_row_add_colored cyan "CPU"
    ui_row_add " "
    ui_row_add_colored "$cpu_color" "${MENU_METRIC_CPU_PCT}%"
    ui_row_add "   "
    ui_row_add_colored cyan "RAM"
    ui_row_add " "
    ui_row_add_colored "$ram_color" "${MENU_METRIC_RAM_PCT}%"
    ui_row_add "   "
    ui_row_add_colored cyan "Disk"
    ui_row_add " "
    ui_row_add_colored "$disk_color" "${MENU_METRIC_DISK_PCT}%"
    ui_row_end

    ui_row_begin
    ui_row_add_colored cyan "Tasks"
    ui_row_add " ${MENU_METRIC_TASKS_RUNNING}/${MENU_METRIC_TASKS_TOTAL}"
    ui_row_add "   "
    ui_row_add_colored cyan "Up"
    ui_row_add " ${MENU_METRIC_UPTIME}"
    ui_row_end

    ui_row_begin
    ui_row_add_colored cyan "Load"
    ui_row_add " ${MENU_METRIC_LOAD_1:-0.00}/${MENU_METRIC_LOAD_5:-0.00}/${MENU_METRIC_LOAD_15:-0.00}"
    ui_row_end
  fi

  ui_box_line bot "$width"
}

menu_status_indicator_color() {
  local value="${1:-unknown}"
  value="${value,,}"

  case "$value" in
    *failed* | *failure* | *error* | *critical* | *broken* | *unhealthy*)
      printf 'red'
      ;;
    *warn* | *attention* | *overdue* | *stale* | *degraded* | *partial* | *required*)
      printf 'orange'
      ;;
    unknown | none | local | n/a | na | never | disabled | *not\ set* | *not\ configured* | *not\ applicable*)
      printf 'muted'
      ;;
    *ok* | *active* | *running* | *enabled* | *verified* | *rehearsed* | *recorded* | *ready* | *healthy* | *configured* | *complete* | *trusted*)
      printf 'green'
      ;;
    *)
      printf 'orange'
      ;;
  esac
}

menu_status_indicator_symbol() {
  local color="${1:-muted}"

  if [[ -n "${NO_COLOR:-}" || "${FORCE_NO_COLOR:-0}" == "1" ]]; then
    case "$color" in
      green) printf '+' ;;
      orange) printf '!' ;;
      red) printf 'x' ;;
      *) printf '-' ;;
    esac
    return 0
  fi

  if ((${UI_UNICODE:-0} == 1)); then
    case "$color" in
      muted) printf '○' ;;
      *) printf '●' ;;
    esac
  else
    case "$color" in
      green) printf '+' ;;
      orange) printf '!' ;;
      red) printf 'x' ;;
      *) printf '-' ;;
    esac
  fi
}

ui_row_add_status_indicator() {
  local label="$1" value="$2" color symbol
  color="$(menu_status_indicator_color "$value")"
  symbol="$(menu_status_indicator_symbol "$color")"

  ui_row_add_colored cyan "$label"
  ui_row_add " "
  ui_row_add_colored "$color" "$symbol"
}

render_main_status_panel() {
  local width runtime_color layout
  width="$(ui_panel_width)"
  runtime_color="$(ui_status_color "$MENU_STATUS_RUNTIME")"
  layout="$(ui_dashboard_layout_mode)"

  ui_box_line top "$width"

  if [[ "$layout" == "wide" ]]; then
    ui_row_begin
    ui_row_add_colored cyan "Site:"
    ui_row_add " "
    ui_row_add "$(printf '%-24s' "${MENU_STATUS_SITE:0:24}")"
    ui_row_add " "
    ui_row_add_colored muted "$UI_DIV"
    ui_row_add " "
    ui_row_add_colored cyan "Mode:"
    ui_row_add " ${MENU_STATUS_MODE:0:12}"
    ui_row_add " "
    ui_row_add_colored muted "$UI_DIV"
    ui_row_add " "
    ui_row_add_colored cyan "Engine:"
    ui_row_add " ${MENU_STATUS_ENGINE}"
    ui_row_add " "
    ui_row_add_colored muted "$UI_DIV"
    ui_row_add " "
    ui_row_add_colored cyan "Runtime:"
    ui_row_add " "
    ui_row_add_colored "$runtime_color" "$MENU_STATUS_RUNTIME"
    ui_row_end
  elif [[ "$layout" == "compact" ]]; then
    ui_row_begin
    ui_row_add_colored cyan "Site:"
    ui_row_add " ${MENU_STATUS_SITE:0:32}"
    ui_row_add "  "
    ui_row_add_colored muted "$UI_DIV"
    ui_row_add "  "
    ui_row_add_colored cyan "Runtime:"
    ui_row_add " "
    ui_row_add_colored "$runtime_color" "$MENU_STATUS_RUNTIME"
    ui_row_end
    ui_row_begin
    ui_row_add_colored cyan "Mode:"
    ui_row_add " ${MENU_STATUS_MODE:0:16}"
    ui_row_add "  "
    ui_row_add_colored muted "$UI_DIV"
    ui_row_add "  "
    ui_row_add_colored cyan "Engine:"
    ui_row_add " ${MENU_STATUS_ENGINE}"
    ui_row_end
  else
    ui_row_begin
    ui_row_add_colored cyan "Site:"
    ui_row_add " ${MENU_STATUS_SITE:0:40}"
    ui_row_end
    ui_row_begin
    ui_row_add_colored cyan "Mode:"
    ui_row_add " ${MENU_STATUS_MODE:0:14}"
    ui_row_add "  "
    ui_row_add_colored cyan "Engine:"
    ui_row_add " ${MENU_STATUS_ENGINE}"
    ui_row_end
    ui_row_begin
    ui_row_add_colored cyan "Runtime:"
    ui_row_add " "
    ui_row_add_colored "$runtime_color" "$MENU_STATUS_RUNTIME"
    ui_row_end
  fi

  ui_box_line mid "$width"

  if ((width < 70)); then
    ui_row_begin
    ui_row_add_status_indicator "HTTPS" "$MENU_STATUS_HTTPS"
    ui_row_add "   "
    ui_row_add_status_indicator "Backups" "$MENU_STATUS_BACKUPS"
    ui_row_add "   "
    ui_row_add_status_indicator "Off-VM" "$MENU_STATUS_OFFVM"
    ui_row_end

    ui_row_begin
    ui_row_add_status_indicator "Restore" "$MENU_STATUS_RESTORE"
    ui_row_add "   "
    ui_row_add_status_indicator "Health" "$MENU_STATUS_HEALTH"
    ui_row_add "   "
    ui_row_add_status_indicator "Go-live" "$MENU_STATUS_GOLIVE"
    ui_row_end
  else
    ui_row_begin
    ui_row_add_status_indicator "HTTPS" "$MENU_STATUS_HTTPS"
    ui_row_add "   "
    ui_row_add_status_indicator "Backups" "$MENU_STATUS_BACKUPS"
    ui_row_add "   "
    ui_row_add_status_indicator "Off-VM" "$MENU_STATUS_OFFVM"
    ui_row_add "   "
    ui_row_add_status_indicator "Restore" "$MENU_STATUS_RESTORE"
    ui_row_add "   "
    ui_row_add_status_indicator "Health" "$MENU_STATUS_HEALTH"
    ui_row_add "   "
    ui_row_add_status_indicator "Go-live" "$MENU_STATUS_GOLIVE"
    ui_row_end
  fi

  ui_box_line bot "$width"
}

render_main_menu_options() {
  local width mode total half i left right parsed
  local ln lt rn rt content_width left_cell_width left_target

  width="$(ui_panel_width)"
  mode="$(ui_dashboard_layout_mode)"
  total="${#MAIN_MENU_ITEMS[@]}"
  half=$(((total + 1) / 2))

  ui_box_line top "$width"

  if [[ "$mode" == "narrow" ]]; then
    for left in "${MAIN_MENU_ITEMS[@]}"; do
      parsed="$(ui_menu_item_parts "$left" || true)"
      ln="${parsed%%|*}"
      lt="${parsed#*|}"
      ui_row_begin
      ui_row_add_colored cyan "[${ln}]"
      ui_row_add " ${lt}"
      ui_row_end
    done
    ui_box_line mid "$width"
    ui_row_begin
    ui_row_add_colored cyan "[D]"
    ui_row_add " Dashboard"
    ui_row_end
    ui_row_begin
    ui_row_add_colored cyan "[L]"
    ui_row_add " Logs"
    ui_row_end
    ui_box_line bot "$width"
    return 0
  fi

  # The row builder owns the outer borders. Split only the remaining content
  # area into two equal cells around a fixed " divider " segment. Padding to an
  # exact visible column avoids the previous off-by-one drift caused by [7]
  # and [10] having different widths.
  content_width=$((width - 6))
  left_cell_width=$((content_width / 2))
  left_target=$((1 + left_cell_width))

  for ((i = 0; i < half; i++)); do
    left="${MAIN_MENU_ITEMS[$i]:-}"
    right="${MAIN_MENU_ITEMS[$((i + half))]:-}"

    parsed="$(ui_menu_item_parts "$left" || true)"
    ln="${parsed%%|*}"
    lt="${parsed#*|}"
    parsed="$(ui_menu_item_parts "$right" || true)"
    rn="${parsed%%|*}"
    rt="${parsed#*|}"

    ui_row_begin
    ui_row_add_colored cyan "[${ln}]"
    ui_row_add " ${lt}"
    ui_row_pad_to "$left_target"
    ui_row_add " "
    ui_row_add_colored muted "$UI_DIV"
    ui_row_add " "
    ui_row_add_colored cyan "[${rn}]"
    ui_row_add " ${rt}"
    ui_row_end
  done

  ui_box_line mid "$width"
  ui_row_begin
  ui_row_add_colored cyan "[D]"
  ui_row_add " Dashboard"
  ui_row_pad_to "$left_target"
  ui_row_add " "
  ui_row_add_colored muted "$UI_DIV"
  ui_row_add " "
  ui_row_add_colored cyan "[L]"
  ui_row_add " Logs"
  ui_row_end
  ui_box_line bot "$width"
}

render_main_menu_screen() {
  ui_init
  load_menu_status_fast
  load_menu_system_metrics_fast

  ui_text cyan "${APP_NAME:-ERPNext Developer Toolkit}"
  printf '  '
  ui_text muted "v${SCRIPT_VERSION:-unknown}"
  if [[ "$(ui_dashboard_layout_mode)" != "narrow" ]]; then
    printf '  '
    ui_text cyan "Main Menu"
  fi
  printf '\n'

  render_main_status_panel
  printf '\n'
  render_main_menu_options
  printf '\n'
  render_main_resources_panel
  printf '\n'
  ui_text orange "Q."
  printf ' Quit\n\n'
}

show_local_development_menu() {
  while true; do
    ui_submenu_header "Local Development" \
      "Guided setup and the day-to-day tools for a local ERPNext VM"
    print_two_column_menu \
      "1) Guided local setup" \
      "2) Status & health" \
      "3) Service controls" \
      "4) Access & networking" \
      "5) HTTPS & domains" \
      "6) Apps" \
      "7) Credentials" \
      "8) Environment check" \
      "9) Setup lifecycle guide"
    ui_submenu_footer
    local choice=""
    menu_read_choice choice

    case "$choice" in
      1)
        run_local_dev_quickstart
        pause_after_screen "Press Enter to return to Local Development..."
        ;;
      2) show_status_menu ;;
      3) show_service_menu ;;
      4) show_access_menu ;;
      5) show_https_domains_menu ;;
      6) show_app_library_menu ;;
      7) show_credentials_menu ;;
      8)
        show_environment_check
        pause_after_screen "Press Enter to return to Local Development..."
        ;;
      9)
        show_setup_lifecycle_plan
        show_setup_effort_guide
        pause_after_screen "Press Enter to return to Local Development..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_production_setup_menu() {
  while true; do
    ui_submenu_header "Production Setup" \
      "Guided deployment, readiness, security, backup, and go-live"
    print_two_column_menu \
      "1) Guided end-to-end setup" \
      "2) Step-by-step setup menu" \
      "3) Production readiness" \
      "4) HTTPS & domains" \
      "5) Security" \
      "6) Backup & recovery" \
      "7) Production operations" \
      "8) Final QA" \
      "9) Setup lifecycle guide"
    ui_submenu_footer
    local choice=""
    menu_read_choice choice

    case "$choice" in
      1)
        run_public_vm_guided_setup
        pause_after_screen "Press Enter to return to Production Setup..."
        ;;
      2) run_public_vm_quickstart ;;
      3)
        show_production_readiness
        show_public_vm_readiness
        pause_after_screen "Press Enter to return to Production Setup..."
        ;;
      4) show_https_domains_menu ;;
      5) security_hardening_wizard ;;
      6) run_backup_maintenance_menu ;;
      7) production_ops_wizard ;;
      8)
        final_qa_wizard
        pause_after_screen "Press Enter to return to Production Setup..."
        ;;
      9)
        show_setup_lifecycle_plan
        show_setup_effort_guide
        pause_after_screen "Press Enter to return to Production Setup..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

https_domains_menu_render_option() {
  local key="$1"
  local label="$2"

  ui_row_add_colored cyan "[$key]"
  ui_row_add " $label"
}

https_domains_menu_render_pair() {
  local width="$1"
  local left_key="$2"
  local left_label="$3"
  local right_key="${4:-}"
  local right_label="${5:-}"
  local second_column

  second_column=$((width / 2))

  ui_row_begin
  https_domains_menu_render_option "$left_key" "$left_label"

  if [[ -n "$right_key" ]]; then
    ui_row_pad_to "$second_column"
    https_domains_menu_render_option "$right_key" "$right_label"
  fi

  ui_row_end
}

render_https_domains_menu_options() {
  local width

  width="$(ui_panel_width)"

  ui_box_line top "$width"

  if ((width >= 80)); then
    https_domains_menu_render_pair \
      "$width" "1" "Local HTTPS" \
      "5" "Local domain / DNS status"

    https_domains_menu_render_pair \
      "$width" "2" "Production HTTPS" \
      "6" "SSL / HTTPS roadmap"

    https_domains_menu_render_pair \
      "$width" "3" "Domain configuration" \
      "7" "SSL mode status & guide"

    https_domains_menu_render_pair \
      "$width" "4" "Change local domain" \
      "8" "Production readiness"
  else
    https_domains_menu_render_pair "$width" "1" "Local HTTPS"
    https_domains_menu_render_pair "$width" "2" "Production HTTPS"
    https_domains_menu_render_pair "$width" "3" "Domain configuration"
    https_domains_menu_render_pair "$width" "4" "Change local domain"
    https_domains_menu_render_pair "$width" "5" "Local domain / DNS status"
    https_domains_menu_render_pair "$width" "6" "SSL / HTTPS roadmap"
    https_domains_menu_render_pair "$width" "7" "SSL mode status & guide"
    https_domains_menu_render_pair "$width" "8" "Production readiness"
  fi

  ui_box_line bot "$width"
}

show_https_domains_menu() {
  while true; do

    ui_submenu_header "HTTPS & Domains" \
      "Local trust, production certificates, domains, and SSL guidance"

    render_https_domains_menu_options

    ui_submenu_footer
    local choice=""
    menu_read_choice choice

    case "$choice" in
      1) show_local_ssl_menu ;;
      2) show_production_ssl_menu ;;
      3)
        show_domain_config
        pause_after_screen "Press Enter to return to HTTPS & Domains..."
        ;;
      4)
        change_local_domain_wizard
        pause_after_screen "Press Enter to return to HTTPS & Domains..."
        ;;
      5)
        show_local_domain_status
        pause_after_screen "Press Enter to return to HTTPS & Domains..."
        ;;
      6)
        show_ssl_roadmap_guide
        pause_after_screen "Press Enter to return to HTTPS & Domains..."
        ;;
      7)
        show_ssl_mode_status
        show_ssl_mode_guide
        pause_after_screen "Press Enter to return to HTTPS & Domains..."
        ;;
      8)
        show_production_readiness
        pause_after_screen "Press Enter to return to HTTPS & Domains..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

operations_menu_render_option() {
  local key="$1"
  local label="$2"

  ui_row_add_colored cyan "[$key]"
  ui_row_add " $label"
}

operations_menu_render_pair() {
  local width="$1"
  local left_key="$2"
  local left_label="$3"
  local right_key="${4:-}"
  local right_label="${5:-}"
  local second_column

  second_column=$((width / 2))

  ui_row_begin
  operations_menu_render_option "$left_key" "$left_label"

  if [[ -n "$right_key" ]]; then
    ui_row_pad_to "$second_column"
    operations_menu_render_option "$right_key" "$right_label"
  fi

  ui_row_end
}

render_operations_menu_options() {
  local width

  width="$(ui_panel_width)"

  ui_box_line top "$width"

  if ((width >= 80)); then
    operations_menu_render_pair "$width" "1" "Dashboard" "4" "Updates"
    operations_menu_render_pair "$width" "2" "Services" "5" "Production"
    operations_menu_render_pair "$width" "3" "Maintenance" "6" "Recovery plan"

    ui_box_line mid "$width"

    operations_menu_render_pair "$width" "F" "Final QA" "N" "Next step"
  else
    operations_menu_render_pair "$width" "1" "Dashboard"
    operations_menu_render_pair "$width" "2" "Services"
    operations_menu_render_pair "$width" "3" "Maintenance"
    operations_menu_render_pair "$width" "4" "Updates"
    operations_menu_render_pair "$width" "5" "Production"
    operations_menu_render_pair "$width" "6" "Recovery plan"

    ui_box_line mid "$width"

    operations_menu_render_pair "$width" "F" "Final QA"
    operations_menu_render_pair "$width" "N" "Next step"
  fi

  ui_box_line bot "$width"
}

show_operations_updates_menu() {
  while true; do
    ui_submenu_header "Updates" \
      "Check readiness and update ERPNext safely."

    local width
    width="$(ui_panel_width)"

    ui_box_line top "$width"

    if ((width >= 80)); then
      operations_menu_render_pair "$width" "1" "Update check" "2" "Safe update"
    else
      operations_menu_render_pair "$width" "1" "Update check"
      operations_menu_render_pair "$width" "2" "Safe update"
    fi

    ui_box_line bot "$width"

    ui_submenu_footer

    local choice=""
    menu_read_choice choice

    case "$choice" in
      1)
        run_update_preflight
        pause_after_screen "Press Enter to return to Updates..."
        ;;
      2)
        run_safe_update_wizard
        pause_after_screen "Press Enter to return to Updates..."
        ;;
      b | B | "")
        return 0
        ;;
      q | Q)
        exit 0
        ;;
      *)
        warn "Invalid option"
        ;;
    esac
  done
}

show_operations_menu() {
  while true; do
    ui_submenu_header "Operations" \
      "Monitor, control, maintain, update, and recover ERPNext."

    render_operations_menu_options

    ui_submenu_footer

    local choice=""
    menu_read_choice choice

    case "$choice" in
      1)
        run_operations_dashboard
        pause_after_screen "Press Enter to return to Operations..."
        ;;
      2)
        show_service_menu
        ;;
      3)
        run_maintenance_menu
        ;;
      4)
        show_operations_updates_menu
        ;;
      5)
        production_ops_wizard
        ;;
      6)
        show_service_recovery_plan
        pause_after_screen "Press Enter to return to Operations..."
        ;;
      f | F)
        final_qa_wizard
        pause_after_screen "Press Enter to return to Operations..."
        ;;
      n | N)
        show_next_step
        pause_after_screen "Press Enter to return to Operations..."
        ;;
      b | B | "")
        return 0
        ;;
      q | Q)
        exit 0
        ;;
      *)
        warn "Invalid option"
        ;;
    esac
  done
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
      2) show_local_development_menu ;;
      3) show_production_setup_menu ;;
      4) show_status_menu ;;
      5) show_access_menu ;;
      6) show_https_domains_menu ;;
      7) show_app_library_menu ;;
      8) security_hardening_wizard ;;
      9) run_backup_maintenance_menu ;;
      10) show_operations_menu ;;
      11) show_advanced_menu ;;
      12)
        show_help
        pause_after_screen "Press Enter to return to Main menu..."
        ;;
      d | D)
        run_operations_dashboard
        pause_after_screen "Press Enter to return to Main menu..."
        ;;
      l | L) engine_runtime_logs ;;
      q | Q) exit 0 ;;
      *)
        warn "Invalid option"
        sleep 0.6 2>/dev/null || true
        ;;
    esac
  done
}

# Non-interactive render for CI (no clear, no read).
menu_render_test() {
  if [[ "${MENU_RENDER_TEST_COLOR:-0}" != "1" ]]; then
    FORCE_NO_COLOR=1
    NO_COLOR=1
    export FORCE_NO_COLOR NO_COLOR
  else
    unset FORCE_NO_COLOR NO_COLOR
  fi
  MENU_NO_CLEAR=1
  export MENU_NO_CLEAR
  MENU_FORCE_ONE_COLUMN="${MENU_FORCE_ONE_COLUMN:-false}"
  UI_FORCE_ASCII="${UI_FORCE_ASCII:-0}"
  render_main_menu_screen
  ui_text cyan "Choose an option:"
  printf ' \n'
}
