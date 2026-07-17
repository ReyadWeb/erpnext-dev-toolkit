# shellcheck shell=bash
# Terminal-native UI primitives for polished menus (SSH-safe, NO_COLOR, ASCII
# fallback). Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_UI_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_UI_LOADED=1

ui_init() {
  local cols colors

  cols="${MENU_TERMINAL_COLS:-${COLUMNS:-}}"
  if [[ -z "$cols" ]]; then
    cols="$(tput cols 2>/dev/null || true)"
  fi
  if ! [[ "$cols" =~ ^[0-9]+$ ]] || (( cols <= 0 )); then
    cols=80
  fi
  UI_COLS="$cols"

  colors="$(tput colors 2>/dev/null || echo 0)"
  if ! [[ "$colors" =~ ^[0-9]+$ ]]; then
    colors=0
  fi
  UI_COLORS="$colors"

  if [[ -n "${NO_COLOR:-}" || "${FORCE_NO_COLOR:-0}" == "1" || "${TERM:-}" == "dumb" ]] \
     || (( UI_COLORS < 8 )); then
    UI_COLOR=0
  else
    UI_COLOR=1
  fi

  case "${LC_ALL:-${LANG:-}}" in
    *UTF-8*|*utf8*) UI_UNICODE=1 ;;
    *) UI_UNICODE=0 ;;
  esac
  # Allow tests / constrained hosts to force ASCII box drawing.
  if [[ "${UI_FORCE_ASCII:-0}" == "1" ]]; then
    UI_UNICODE=0
  fi

  if (( UI_UNICODE == 1 )); then
    UI_TL="╭"; UI_TR="╮"; UI_BL="╰"; UI_BR="╯"
    UI_H="─"; UI_V="│"; UI_DIV="│"
    UI_DOT="●"; UI_CHECK="✓"
  else
    UI_TL="+"; UI_TR="+"; UI_BL="+"; UI_BR="+"
    UI_H="-"; UI_V="|"; UI_DIV="|"
    UI_DOT="*"; UI_CHECK="OK"
  fi
  # Exported for lib/menu.sh and other renderers.
  export UI_COLS UI_COLOR UI_UNICODE \
    UI_TL UI_TR UI_BL UI_BR UI_H UI_V UI_DIV UI_DOT UI_CHECK
}

ui_layout_mode() {
  if [[ "${MENU_FORCE_ONE_COLUMN:-false}" == "true" ]]; then
    printf 'compact'
    return 0
  fi
  if [[ "${MENU_FORCE_TWO_COLUMNS:-false}" == "true" ]]; then
    printf 'wide'
    return 0
  fi
  if (( ${UI_COLS:-80} < 90 )); then
    printf 'compact'
  elif (( ${UI_COLS:-80} < 115 )); then
    printf 'medium'
  else
    printf 'wide'
  fi
}

ui_c() {
  (( ${UI_COLOR:-0} == 1 )) || return 0
  case "$1" in
    blue) printf '\033[38;5;39m' ;;
    cyan) printf '\033[38;5;45m' ;;
    green) printf '\033[38;5;82m' ;;
    orange) printf '\033[38;5;214m' ;;
    red) printf '\033[38;5;196m' ;;
    muted) printf '\033[38;5;244m' ;;
    bold) printf '\033[1m' ;;
    reset) printf '\033[0m' ;;
  esac
}

ui_text() {
  local color="$1"
  shift
  ui_c "$color"
  printf '%s' "$*"
  ui_c reset
}

ui_repeat() {
  local char="$1" count="${2:-0}"
  if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count <= 0 )); then
    return 0
  fi
  # Portable repeat without relying on tr's set length for multi-byte UTF-8.
  local i
  for (( i = 0; i < count; i++ )); do
    printf '%s' "$char"
  done
}

ui_panel_width() {
  local width="${UI_COLS:-80}"
  (( width > 120 )) && width=120
  (( width < 60 )) && width=60
  printf '%s' "$width"
}

ui_box_line() {
  # ui_box_line top|mid|bot [width]
  local kind="$1"
  local width="${2:-$(ui_panel_width)}"
  local inner=$((width - 2))
  (( inner < 10 )) && inner=10
  case "$kind" in
    top) printf '%s%s%s\n' "$UI_TL" "$(ui_repeat "$UI_H" "$inner")" "$UI_TR" ;;
    bot) printf '%s%s%s\n' "$UI_BL" "$(ui_repeat "$UI_H" "$inner")" "$UI_BR" ;;
    mid) printf '%s%s%s\n' "$UI_V" "$(ui_repeat "$UI_H" "$inner")" "$UI_V" ;;
  esac
}

ui_status_color() {
  local value="$1"
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    ok|running|active|verified|rehearsed|recorded|healthy|complete)
      printf 'green'
      ;;
    warn|warning|degraded|attention|unknown|planned)
      printf 'orange'
      ;;
    fail|failed|critical|missing|inactive|error)
      printf 'red'
      ;;
    *)
      printf 'muted'
      ;;
  esac
}

ui_status_badge() {
  local label="$1" value="$2"
  local color
  color="$(ui_status_color "$value")"
  ui_text cyan "${label}:"
  printf ' '
  if [[ "$(ui_status_color "$value")" == "green" ]]; then
    ui_text green "${UI_DOT} ${value}"
  else
    ui_text "$color" "$value"
  fi
}

ui_prompt() {
  local prompt="${1:-Choose an option: }"
  local __target="${2:-}"
  local __choice=""
  ui_text cyan "$prompt"
  if ! read -r __choice; then
    __choice="q"
  fi
  __choice="$(trim_menu_choice "$__choice" 2>/dev/null || printf '%s' "$__choice")"
  case "${__choice,,}" in
    quit|exit) __choice="q" ;;
    back) __choice="b" ;;
  esac
  if [[ -n "$__target" ]]; then
    printf -v "$__target" '%s' "$__choice"
  else
    printf '%s' "$__choice"
  fi
}

# Compact submenu title used by App Wizard / Library and other nested menus.
ui_submenu_header() {
  local title="$1"
  local subtitle="${2:-}"
  local width inner pad

  ui_init
  width="$(ui_panel_width)"
  inner=$((width - 2))
  (( inner < 10 )) && inner=10

  echo
  ui_box_line top "$width"
  printf '%s ' "$UI_V"
  ui_text cyan "$title"
  pad=$((inner - 1 - ${#title}))
  (( pad < 0 )) && pad=0
  printf '%*s%s\n' "$pad" "" "$UI_V"
  if [[ -n "$subtitle" ]]; then
    printf '%s ' "$UI_V"
    ui_text muted "$subtitle"
    pad=$((inner - 1 - ${#subtitle}))
    (( pad < 0 )) && pad=0
    printf '%*s%s\n' "$pad" "" "$UI_V"
  fi
  ui_box_line bot "$width"
  echo
}
