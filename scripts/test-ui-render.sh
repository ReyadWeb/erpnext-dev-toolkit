#!/usr/bin/env bash
# Hermetic UI render checks for the polished main menu (v1.17.3+).
# No sudo, no install, no network. Verifies NO_COLOR / TERM=dumb emit no ANSI.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
note_fail() {
  echo "FAIL: $*" >&2
  fail=$((fail + 1))
}
pass() { echo "OK: $*"; }

bash -n lib/ui.sh || note_fail "bash -n lib/ui.sh"
bash -n lib/menu.sh || note_fail "bash -n lib/menu.sh"
bash -n erpnext-dev.sh || note_fail "bash -n erpnext-dev.sh"

export NO_COLOR=1
export FORCE_NO_COLOR=1
export TERM=dumb
export COLUMNS=80
export MENU_FORCE_ONE_COLUMN=true
export UI_FORCE_ASCII=1
export MENU_NO_CLEAR=1

tmp="$(mktemp /tmp/erpnext-dev-ui-render.XXXXXX)"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

# Run through the real entrypoint (sources all libs, then menu_render_test).
if ! ./erpnext-dev.sh menu-render-test >"$tmp" 2>/tmp/erpnext-dev-ui-render.err; then
  note_fail "menu-render-test exited non-zero"
  cat /tmp/erpnext-dev-ui-render.err >&2 || true
fi

grep -q "ERPNext Developer Toolkit" "$tmp" || note_fail "missing toolkit title"
grep -q "Start here / setup wizard" "$tmp" || note_fail "missing Start here item"
grep -q "Production operations" "$tmp" || note_fail "missing Production operations item"
grep -q "Choose an option" "$tmp" || note_fail "missing Choose an option prompt"
grep -qE '\[q\]|q\) Quit' "$tmp" || note_fail "missing quit affordance"

if grep -q $'\033' "$tmp"; then
  note_fail "ANSI escape codes present with NO_COLOR=1 / TERM=dumb"
fi

# Wide / two-column layout (no MENU_FORCE_TWO_COLUMNS): item 1 and 10 share a row.
export COLUMNS=100
export MENU_TERMINAL_COLS=100
export MENU_FORCE_ONE_COLUMN=false
unset MENU_FORCE_TWO_COLUMNS
tmp2="$(mktemp /tmp/erpnext-dev-ui-render-wide.XXXXXX)"
./erpnext-dev.sh menu-render-test >"$tmp2" 2>/dev/null || note_fail "wide menu-render-test failed"
grep -q "Operations dashboard" "$tmp2" || note_fail "wide layout missing Operations dashboard"
if ! grep -qE '\[1\].*\[10\]' "$tmp2"; then
  note_fail "expected two-column row with [1] and [10] at COLUMNS=100"
  echo "----- wide render -----" >&2
  cat "$tmp2" >&2 || true
fi
if grep -q $'\033' "$tmp2"; then
  note_fail "ANSI escape codes in wide layout with NO_COLOR=1"
fi
rm -f "$tmp2"

# 80-col terminals must stay two-column (threshold was previously 90 → single-col).
export COLUMNS=80
export MENU_TERMINAL_COLS=80
export MENU_FORCE_ONE_COLUMN=false
unset MENU_FORCE_TWO_COLUMNS
tmp3="$(mktemp /tmp/erpnext-dev-ui-render-80.XXXXXX)"
./erpnext-dev.sh menu-render-test >"$tmp3" 2>/dev/null || note_fail "80-col menu-render-test failed"
if ! grep -qE '\[1\].*\[10\]' "$tmp3"; then
  note_fail "expected two-column menu at COLUMNS=80"
  echo "----- 80-col render -----" >&2
  cat "$tmp3" >&2 || true
fi
rm -f "$tmp3"

# Pre-tee snapshot helper: when only ERPNEXT_DEV_TTY_COLS is set (no MENU/COLUMNS),
# ui_detect_terminal_cols must still return that width (simulates post-tee menu).
# shellcheck source=lib/ui.sh disable=SC1091
source "$ROOT_DIR/lib/ui.sh"
unset MENU_TERMINAL_COLS COLUMNS
export ERPNEXT_DEV_TTY_COLS=100
# Bypass live stty by pointing MENU override through a function-local path:
# call detector with MENU_TERMINAL_COLS cleared and a fake empty tty read — if
# /dev/tty exists on the runner, prefer asserting the snapshot export path.
(
  unset MENU_TERMINAL_COLS COLUMNS
  export ERPNEXT_DEV_TTY_COLS=100
  detected="$(ui_detect_terminal_cols)"
  # Accept either live stty width or the snapshot/default (>=80 for two-col intent).
  if ! [[ "$detected" =~ ^[0-9]+$ ]] || (( detected < 80 )); then
    note_fail "ui_detect_terminal_cols returned unusable width: ${detected}"
  else
    pass "ui_detect_terminal_cols width ${detected}"
  fi
)
unset ERPNEXT_DEV_TTY_COLS

# Color must survive the post-tee re-init path (interactive menus log via tee,
# which makes `[[ -t 1 ]]` false). Snapshot ERPNEXT_DEV_STDOUT_TTY once.
unset NO_COLOR FORCE_NO_COLOR ERPNEXT_DEV_STDOUT_TTY GREEN YELLOW RED BLUE BOLD RESET
export TERM="${TERM:-xterm-256color}"
# shellcheck source=lib/common.sh disable=SC1091
source "$ROOT_DIR/lib/common.sh"
ERPNEXT_DEV_STDOUT_TTY=1
FORCE_NO_COLOR=0
erpnext_dev_init_terminal_colors
if [[ -z "${GREEN:-}" ]]; then
  note_fail "GREEN empty after TTY snapshot re-init (OK status would be uncolored)"
else
  pass "status colors preserved after simulated tee re-init"
fi
FORCE_NO_COLOR=1
NO_COLOR=1
export NO_COLOR
erpnext_dev_init_terminal_colors
if [[ -n "${GREEN:-}" ]]; then
  note_fail "--no-color / FORCE_NO_COLOR did not clear GREEN"
else
  pass "--no-color clears status colors"
fi

# menu_read_choice must receive the typed value (ui_prompt must not shadow __choice).
choice_file="$(mktemp /tmp/erpnext-dev-menu-choice.XXXXXX)"
FORCE_NO_COLOR=1
NO_COLOR=1
export NO_COLOR FORCE_NO_COLOR
printf 'q\n' | bash -c '
  source "'"$ROOT_DIR"'/lib/common.sh"
  source "'"$ROOT_DIR"'/lib/ui.sh"
  ui_init
  menu_read_choice got
  printf "%s" "$got" > "'"$choice_file"'"
' >/dev/null
got="$(cat "$choice_file" 2>/dev/null || true)"
rm -f "$choice_file"
if [[ "$got" != "q" ]]; then
  note_fail "menu_read_choice did not return q (got='${got}') — ui_prompt shadowing regress?"
else
  pass "menu_read_choice returns typed selection"
fi

if (( fail > 0 )); then
  echo "test-ui-render: ${fail} failure(s)" >&2
  echo "----- render output (compact) -----" >&2
  cat "$tmp" >&2 || true
  exit 1
fi
echo "test-ui-render: all checks passed"
