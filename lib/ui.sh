# shellcheck shell=bash
# Terminal-native UI primitives for polished menus (SSH-safe, NO_COLOR, ASCII
# fallback). Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_UI_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_UI_LOADED=1

# Resolve terminal width in a way that still works after
# `exec > >(tee …)` turns stdout/stderr into pipes (tput/COLUMNS alone often
# collapse to the 80-col default and force a single-column menu).
ui_detect_terminal_cols() {
  local cols=""

  cols="${MENU_TERMINAL_COLS:-}"
  if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
    printf '%s' "$cols"
    return 0
  fi

  # Live size from the controlling terminal (works after tee redirect).
  # Prefer stty -F/-f so a failed /dev/tty open does not spam bash redirection errors.
  cols=""
  if cols="$(stty -F /dev/tty size 2>/dev/null)"; then
    :
  elif cols="$(stty -f /dev/tty size 2>/dev/null)"; then
    :
  else
    cols=""
  fi
  cols="$(printf '%s\n' "$cols" | awk '{print $2}')"
  if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
    printf '%s' "$cols"
    return 0
  fi

  cols="${ERPNEXT_DEV_TTY_COLS:-${COLUMNS:-}}"
  if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
    printf '%s' "$cols"
    return 0
  fi

  cols="$(tput cols 2>/dev/null || true)"
  if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
    printf '%s' "$cols"
    return 0
  fi

  # Prefer two-column layout when width is unknown (legacy default of 80 forced
  # single-column menus in SSH / sudo / tee sessions).
  printf '100'
}

# Snapshot width once before the log tee redirect. Safe to call repeatedly.
erpnext_dev_snapshot_terminal_cols() {
  local cols
  if [[ -n "${ERPNEXT_DEV_TTY_COLS:-}" ]] && [[ "${ERPNEXT_DEV_TTY_COLS}" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  cols="$(ui_detect_terminal_cols)"
  ERPNEXT_DEV_TTY_COLS="$cols"
  export ERPNEXT_DEV_TTY_COLS
}

ui_init() {
  local cols colors

  cols="$(ui_detect_terminal_cols)"
  UI_COLS="$cols"
  # Keep the snapshot fresh for subprocesses / later ui_init calls.
  if [[ -z "${ERPNEXT_DEV_TTY_COLS:-}" ]]; then
    ERPNEXT_DEV_TTY_COLS="$cols"
    export ERPNEXT_DEV_TTY_COLS
  fi

  colors="$(tput colors 2>/dev/null || echo 0)"
  if ! [[ "$colors" =~ ^[0-9]+$ ]]; then
    colors=0
  fi
  UI_COLORS="$colors"

  if [[ -n "${NO_COLOR:-}" || "${FORCE_NO_COLOR:-0}" == "1" || "${TERM:-}" == "dumb" ]] \
    || ((UI_COLORS < 8)); then
    # Still allow color when the operator's original stdout was a TTY (same
    # snapshot used for GREEN/OK status lines after tee).
    if [[ "${ERPNEXT_DEV_STDOUT_TTY:-}" == "1" && -z "${NO_COLOR:-}" && "${FORCE_NO_COLOR:-0}" != "1" && "${TERM:-}" != "dumb" ]]; then
      UI_COLOR=1
    else
      UI_COLOR=0
    fi
  else
    UI_COLOR=1
  fi

  case "${LC_ALL:-${LANG:-}}" in
    *UTF-8* | *utf8*) UI_UNICODE=1 ;;
    *) UI_UNICODE=0 ;;
  esac
  # Allow tests / constrained hosts to force ASCII box drawing.
  if [[ "${UI_FORCE_ASCII:-0}" == "1" ]]; then
    UI_UNICODE=0
  fi

  if ((UI_UNICODE == 1)); then
    UI_TL="╭"
    UI_TR="╮"
    UI_BL="╰"
    UI_BR="╯"
    UI_H="─"
    UI_V="│"
    UI_DIV="│"
    UI_DOT="●"
    UI_CHECK="✓"
  else
    UI_TL="+"
    UI_TR="+"
    UI_BL="+"
    UI_BR="+"
    UI_H="-"
    UI_V="|"
    UI_DIV="|"
    UI_DOT="*"
    UI_CHECK="OK"
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
  # Keep two columns on ordinary 80-column SSH terminals whenever labels fit.
  # The fit check in ui_render_boxed_menu still falls back to one column for
  # long submenu labels, so compact mode is reserved for genuinely narrow TTYs.
  if ((${UI_COLS:-100} < 76)); then
    printf 'compact'
  elif ((${UI_COLS:-100} < 100)); then
    printf 'medium'
  else
    printf 'wide'
  fi
}

# Main-dashboard layout contract. Keep this separate from ui_layout_mode so the
# broader submenu system can retain its current fit-based behavior while the
# dashboard gets explicit wide / compact / narrow breakpoints.
ui_dashboard_layout_mode() {
  local cols="${UI_COLS:-100}"
  if ((cols < 80)); then
    printf 'narrow'
  elif ((cols < 120)); then
    printf 'compact'
  else
    printf 'wide'
  fi
}

# Render a fixed-width percentage bar with Unicode blocks when available and a
# portable ASCII fallback otherwise. The caller controls any surrounding color.
ui_percent_bar() {
  local percent="${1:-0}" length="${2:-10}"
  local filled empty fill_char empty_char

  [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
  [[ "$length" =~ ^[0-9]+$ ]] || length=10
  ((percent < 0)) && percent=0
  ((percent > 100)) && percent=100
  ((length < 4)) && length=4

  filled=$(((percent * length + 50) / 100))
  ((filled > length)) && filled="$length"
  empty=$((length - filled))

  if ((${UI_UNICODE:-0} == 1)); then
    fill_char="█"
    empty_char="░"
  else
    fill_char="#"
    empty_char="-"
  fi

  printf '['
  ui_repeat "$fill_char" "$filled"
  ui_repeat "$empty_char" "$empty"
  printf ']'
}

# Clear only the operator's live terminal, never the captured log stream.
# This keeps interactive menus page-oriented even after stdout is redirected
# through tee, while direct/non-interactive CLI commands remain print-and-exit.
ui_clear_screen() {
  [[ "${MENU_NO_CLEAR:-0}" != "1" ]] || return 0
  [[ "${TERM:-}" != "dumb" ]] || return 0
  [[ -t 0 ]] || return 0
  [[ -w /dev/tty ]] || return 0

  if command -v tput >/dev/null 2>&1; then
    tput clear >/dev/tty 2>/dev/null || true
  else
    printf '\033[2J\033[H' >/dev/tty 2>/dev/null || true
  fi
}

# True when every menu label fits a two-column cell at the current panel width.
# Prefix budget covers "[nn] " (up to 5 digits + brackets + space).
ui_menu_labels_fit_two_column() {
  local width left_width right_width cell item parsed label
  width="$(ui_panel_width)"
  left_width=$((width / 2 - 4))
  right_width=$((width - left_width - 7))
  ((left_width < 24)) && left_width=24
  ((right_width < 24)) && right_width=24
  cell="$left_width"
  ((right_width < cell)) && cell="$right_width"
  for item in "$@"; do
    parsed="$(ui_menu_item_parts "$item" || true)"
    if [[ -n "$parsed" ]]; then
      label="${parsed#*|}"
    else
      label="$item"
    fi
    if ((${#label} + 6 > cell)); then
      return 1
    fi
  done
  return 0
}

ui_c() {
  ((${UI_COLOR:-0} == 1)) || return 0
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
  if ! [[ "$count" =~ ^[0-9]+$ ]] || ((count <= 0)); then
    return 0
  fi
  # Portable repeat without relying on tr's set length for multi-byte UTF-8.
  local i
  for ((i = 0; i < count; i++)); do
    printf '%s' "$char"
  done
}

ui_panel_width() {
  local width="${UI_COLS:-80}"
  ((width > 120)) && width=120
  ((width < 60)) && width=60
  printf '%s' "$width"
}

ui_box_line() {
  # ui_box_line top|mid|bot [width]
  local kind="$1"
  local width="${2:-$(ui_panel_width)}"
  local inner=$((width - 2))
  ((inner < 10)) && inner=10
  ui_c muted
  case "$kind" in
    top) printf '%s%s%s\n' "$UI_TL" "$(ui_repeat "$UI_H" "$inner")" "$UI_TR" ;;
    bot) printf '%s%s%s\n' "$UI_BL" "$(ui_repeat "$UI_H" "$inner")" "$UI_BR" ;;
    mid) printf '%s%s%s\n' "$UI_V" "$(ui_repeat "$UI_H" "$inner")" "$UI_V" ;;
  esac
  ui_c reset
}

ui_status_color() {
  local value="$1"
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    ok | running | active | verified | rehearsed | recorded | healthy | complete | mkcert | self-signed | selfsigned)
      printf 'green'
      ;;
    warn | warning | degraded | attention | unknown | planned)
      printf 'orange'
      ;;
    fail | failed | critical | missing | inactive | error)
      printf 'red'
      ;;
    local | none | n/a | na | info)
      printf 'muted'
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

# Badge that also advances UI_ROW_USED (for padded status-box rows).
ui_row_add_badge() {
  local label="$1" value="$2"
  local color vis
  color="$(ui_status_color "$value")"
  ui_text cyan "${label}:"
  printf ' '
  if [[ "$color" == "green" ]]; then
    ui_text green "${UI_DOT} ${value}"
    vis=$((${#label} + 2 + ${#UI_DOT} + 1 + ${#value}))
  else
    ui_text "$color" "$value"
    vis=$((${#label} + 2 + ${#value}))
  fi
  UI_ROW_USED=$((${UI_ROW_USED:-0} + vis))
}

# Parse "12|Label" or "12) Label" into num|label on stdout. Returns 1 if unparseable.
ui_menu_item_parts() {
  local item="${1:-}"
  if [[ "$item" =~ ^([0-9]+)\|(.+)$ ]]; then
    printf '%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "$item" =~ ^([0-9]+)\)[[:space:]]*(.*)$ ]]; then
    printf '%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# Boxed two-column option list matching the main menu ([n] labels, borders).
# Accepts "n|label" or "n) label" items. Truncates labels to fit; never spills
# past ui_panel_width. Single-column when compact / MENU_FORCE_ONE_COLUMN.
ui_render_boxed_menu() {
  local items=("$@")
  local total="${#items[@]}"
  local half width left_width right_width i left right ln lt rn rt parsed
  local mode

  ui_init
  total="${#items[@]}"
  ((total > 0)) || return 0
  half=$(((total + 1) / 2))
  width="$(ui_panel_width)"
  mode="$(ui_layout_mode)"

  # Fit-based fallback: force single-column when any label would truncate in
  # two-column cells (unless the caller forced two columns).
  if [[ "$mode" != "compact" && "${MENU_FORCE_TWO_COLUMNS:-false}" != "true" ]]; then
    if ! ui_menu_labels_fit_two_column "${items[@]}"; then
      mode="compact"
    fi
  fi

  if [[ "$mode" == "compact" || "${MENU_FORCE_ONE_COLUMN:-false}" == "true" ]]; then
    ui_box_line top "$width"
    for left in "${items[@]}"; do
      parsed="$(ui_menu_item_parts "$left" || true)"
      if [[ -n "$parsed" ]]; then
        ln="${parsed%%|*}"
        lt="${parsed#*|}"
      else
        ln=""
        lt="$left"
      fi
      ui_row_begin
      if [[ -n "$ln" ]]; then
        ui_row_add_colored cyan "[${ln}]"
        ui_row_add " "
      fi
      if ((${#lt} > width - 10)); then
        lt="${lt:0:$((width - 13))}..."
      fi
      ui_row_add "$lt"
      ui_row_end
    done
    ui_box_line bot "$width"
    return 0
  fi

  left_width=$((width / 2 - 4))
  right_width=$((width - left_width - 7))
  ((left_width < 24)) && left_width=24
  ((right_width < 24)) && right_width=24

  ui_box_line top "$width"
  for ((i = 0; i < half; i++)); do
    left="${items[$i]:-}"
    right="${items[$((i + half))]:-}"
    parsed="$(ui_menu_item_parts "$left" || true)"
    if [[ -n "$parsed" ]]; then
      ln="${parsed%%|*}"
      lt="${parsed#*|}"
    else
      ln=""
      lt="$left"
    fi
    if ((${#lt} > left_width - 5)); then
      lt="${lt:0:$((left_width - 8))}..."
    fi
    printf '%s ' "$UI_V"
    if [[ -n "$ln" ]]; then
      ui_text cyan "[${ln}]"
      printf ' %-*s ' "$((left_width - 5))" "$lt"
    else
      printf '%-*s ' "$left_width" "$lt"
    fi
    printf '%s ' "$UI_DIV"
    if [[ -n "$right" ]]; then
      parsed="$(ui_menu_item_parts "$right" || true)"
      if [[ -n "$parsed" ]]; then
        rn="${parsed%%|*}"
        rt="${parsed#*|}"
      else
        rn=""
        rt="$right"
      fi
      if ((${#rt} > right_width - 5)); then
        rt="${rt:0:$((right_width - 8))}..."
      fi
      if [[ -n "$rn" ]]; then
        ui_text cyan "[${rn}]"
        printf ' %-*s' "$((right_width - 5))" "$rt"
      else
        printf '%-*s' "$right_width" "$rt"
      fi
    else
      printf '%-*s' "$right_width" ""
    fi
    printf ' %s\n' "$UI_V"
  done
  ui_box_line bot "$width"
}

ui_prompt() {
  local prompt="${1:-Choose an option: }"
  local __target="${2:-}"
  # Must not be named __choice: callers (menu_read_choice) often pass __choice as
  # the destination, and printf -v would only update this function's local.
  local __ui_prompt_choice=""
  ui_text cyan "$prompt"
  if ! read -r __ui_prompt_choice; then
    __ui_prompt_choice="q"
  fi
  __ui_prompt_choice="$(trim_menu_choice "$__ui_prompt_choice" 2>/dev/null || printf '%s' "$__ui_prompt_choice")"
  case "${__ui_prompt_choice,,}" in
    quit | exit) __ui_prompt_choice="q" ;;
    back) __ui_prompt_choice="b" ;;
  esac
  if [[ -n "$__target" ]]; then
    printf -v "$__target" '%s' "$__ui_prompt_choice"
  else
    printf '%s' "$__ui_prompt_choice"
  fi
}

# Compact submenu title used by App Wizard / Library and other nested menus.

ui_submenu_footer() {
  local width gap

  width="$(ui_panel_width)"

  # Keep Back in the left half and Quit aligned with the second
  # menu column. The visible width of "B. Back" is seven chars.
  gap=$((width / 2 - 7))
  ((gap < 4)) && gap=4

  echo
  ui_text cyan "B."
  printf ' Back'
  printf '%*s' "$gap" ''
  ui_text orange "Q."
  printf ' Quit\n'
}

ui_submenu_header() {
  local title="$1"
  local subtitle="${2:-}"
  local width inner pad

  ui_init
  width="$(ui_panel_width)"
  inner=$((width - 2))
  ((inner < 10)) && inner=10

  echo
  ui_box_line top "$width"
  printf '%s ' "$UI_V"
  ui_text cyan "$title"
  pad=$((inner - 1 - ${#title}))
  ((pad < 0)) && pad=0
  printf '%*s%s\n' "$pad" "" "$UI_V"
  if [[ -n "$subtitle" ]]; then
    printf '%s ' "$UI_V"
    ui_text muted "$subtitle"
    pad=$((inner - 1 - ${#subtitle}))
    ((pad < 0)) && pad=0
    printf '%*s%s\n' "$pad" "" "$UI_V"
  fi
  ui_box_line bot "$width"
  echo
}

# --- Dashboard / section boxes (title in top border) -------------------------

ui_box_titled_top() {
  # ╭─ Title ────────────────────────────╮
  local title="$1"
  local width="${2:-$(ui_panel_width)}"
  local inner=$((width - 2))
  local fill
  ((inner < 10)) && inner=10
  # "─ " + title + " " + fill  == inner
  fill=$((inner - 3 - ${#title}))
  ((fill < 1)) && fill=1
  ui_c muted
  printf '%s%s ' "$UI_TL" "$UI_H"
  ui_c reset
  ui_text cyan "$title"
  ui_c muted
  printf ' %s%s\n' "$(ui_repeat "$UI_H" "$fill")" "$UI_TR"
  ui_c reset
}

ui_section_open() {
  local title="$1"
  ui_init
  echo
  ui_box_titled_top "$title" "$(ui_panel_width)"
}

ui_section_close() {
  ui_box_line bot "$(ui_panel_width)"
}

# Row builder: track visible (non-ANSI) width so padding stays inside the box.
ui_row_begin() {
  ui_text muted "$UI_V"
  printf ' '
  UI_ROW_USED=1
}

ui_row_add() {
  local text="${1:-}"
  printf '%s' "$text"
  UI_ROW_USED=$((${UI_ROW_USED:-0} + ${#text}))
}

ui_row_add_colored() {
  local color="$1"
  shift
  local text="$*"
  ui_text "$color" "$text"
  UI_ROW_USED=$((${UI_ROW_USED:-0} + ${#text}))
}

# Add a semantic percentage bar without letting ANSI escape sequences affect
# visible-width accounting. Brackets and the unused segment stay muted while
# the filled segment inherits the caller's utilization color.
ui_row_add_percent_bar() {
  local color="${1:-green}" percent="${2:-0}" length="${3:-10}"
  local filled empty fill_char empty_char

  [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
  [[ "$length" =~ ^[0-9]+$ ]] || length=10
  ((percent < 0)) && percent=0
  ((percent > 100)) && percent=100
  ((length < 4)) && length=4

  filled=$(((percent * length + 50) / 100))
  ((filled > length)) && filled="$length"
  empty=$((length - filled))

  if ((${UI_UNICODE:-0} == 1)); then
    fill_char="█"
    empty_char="░"
  else
    fill_char="#"
    empty_char="-"
  fi

  ui_text muted "["
  ui_c "$color"
  ui_repeat "$fill_char" "$filled"
  ui_c reset
  ui_text muted "$(ui_repeat "$empty_char" "$empty")"
  ui_text muted "]"
  UI_ROW_USED=$((${UI_ROW_USED:-0} + length + 2))
}

# Pad the current box row to an exact visible column. This keeps internal
# dividers and the final right border aligned even when labels or menu numbers
# have different lengths (for example, [7] versus [10]).
ui_row_pad_to() {
  local target="${1:-0}" pad
  [[ "$target" =~ ^[0-9]+$ ]] || return 1
  pad=$((target - ${UI_ROW_USED:-0}))
  ((pad > 0)) || return 0
  printf '%*s' "$pad" ''
  UI_ROW_USED=$((${UI_ROW_USED:-0} + pad))
}

ui_row_end() {
  local width inner pad
  width="$(ui_panel_width)"
  inner=$((width - 2))
  pad=$((inner - ${UI_ROW_USED:-0}))
  ((pad < 0)) && pad=0
  printf '%*s' "$pad" ""
  ui_text muted "$UI_V"
  printf '\n'
  UI_ROW_USED=0
}

ui_row_plain() {
  # Single plain-text row truncated to panel width.
  local text="${1:-}"
  local width inner max
  width="$(ui_panel_width)"
  inner=$((width - 2))
  max=$((inner - 1))
  ((max < 8)) && max=8
  if ((${#text} > max)); then
    text="${text:0:$((max - 3))}..."
  fi
  ui_row_begin
  ui_row_add "$text"
  ui_row_end
}
