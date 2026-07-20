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
grep -q "Start here" "$tmp" || note_fail "missing Start here item"
grep -q "Access & networking" "$tmp" || note_fail "missing Access & networking item"
grep -q "HTTPS & domains" "$tmp" || note_fail "missing HTTPS & domains item"
grep -q "Backup & recovery" "$tmp" || note_fail "missing Backup & recovery item"
grep -q "Operations" "$tmp" || note_fail "missing Operations item"
grep -q "Choose an option" "$tmp" || note_fail "missing Choose an option prompt"
grep -qE '\[q\]|q\) Quit' "$tmp" || note_fail "missing quit affordance"

if grep -q $'\033' "$tmp"; then
  note_fail "ANSI escape codes present with NO_COLOR=1 / TERM=dumb"
fi

# Wide / two-column layout (no MENU_FORCE_TWO_COLUMNS): item 1 and 7 share a row.
export COLUMNS=100
export MENU_TERMINAL_COLS=100
export MENU_FORCE_ONE_COLUMN=false
unset MENU_FORCE_TWO_COLUMNS
tmp2="$(mktemp /tmp/erpnext-dev-ui-render-wide.XXXXXX)"
./erpnext-dev.sh menu-render-test >"$tmp2" 2>/dev/null || note_fail "wide menu-render-test failed"
grep -q "Operations" "$tmp2" || note_fail "wide layout missing Operations"
if ! grep -qE '\[1\].*\[7\]' "$tmp2"; then
  note_fail "expected two-column row with [1] and [7] at COLUMNS=100"
  echo "----- wide render -----" >&2
  cat "$tmp2" >&2 || true
else
  pass "two-column menu at COLUMNS=100"
fi
grep -q "Go-live:" "$tmp2" || note_fail "wide layout missing Go-live status badge"
grep -qE 'Go-live:[[:space:]]*Local' "$tmp2" || note_fail "local mode should show Go-live: Local (not Unknown)"
grep -qE 'HTTPS:[[:space:]]*(None|mkcert|Self-signed|OK)' "$tmp2" \
  || note_fail "local mode should show HTTPS as None/mkcert/Self-signed/OK (not Unknown)"
# Status badges must wrap: Go-live must not share a line with HTTPS.
if grep -E 'HTTPS:.*Go-live:' "$tmp2" >/dev/null 2>&1; then
  note_fail "Go-live still on the same status row as HTTPS (overflow risk)"
  echo "----- wide render -----" >&2
  cat "$tmp2" >&2 || true
fi
if grep -q $'\033' "$tmp2"; then
  note_fail "ANSI escape codes in wide layout with NO_COLOR=1"
fi
rm -f "$tmp2"

# 80-col terminals now stay two-column when labels fit (v1.19.11 page UX).
export COLUMNS=80
export MENU_TERMINAL_COLS=80
export MENU_FORCE_ONE_COLUMN=false
unset MENU_FORCE_TWO_COLUMNS
tmp3="$(mktemp /tmp/erpnext-dev-ui-render-80.XXXXXX)"
./erpnext-dev.sh menu-render-test >"$tmp3" 2>/dev/null || note_fail "80-col menu-render-test failed"
if ! grep -qE '\[1\].*\[7\]' "$tmp3"; then
  note_fail "expected two-column menu at COLUMNS=80"
  echo "----- 80-col render -----" >&2
  cat "$tmp3" >&2 || true
else
  pass "two-column menu at COLUMNS=80"
fi
grep -q "Start here" "$tmp3" || note_fail "80-col missing Start here"
rm -f "$tmp3"

# Genuinely narrow terminals remain one-column.
export COLUMNS=70
export MENU_TERMINAL_COLS=70
tmpn="$(mktemp /tmp/erpnext-dev-ui-render-70.XXXXXX)"
./erpnext-dev.sh menu-render-test >"$tmpn" 2>/dev/null || note_fail "70-col menu-render-test failed"
if grep -qE '\[1\].*\[7\]' "$tmpn"; then
  note_fail "expected single-column menu at COLUMNS=70"
  cat "$tmpn" >&2 || true
else
  pass "single-column menu at COLUMNS=70"
fi
rm -f "$tmpn"

# 120-col stays two-column.
export COLUMNS=120
export MENU_TERMINAL_COLS=120
export MENU_FORCE_ONE_COLUMN=false
unset MENU_FORCE_TWO_COLUMNS
tmp4="$(mktemp /tmp/erpnext-dev-ui-render-120.XXXXXX)"
./erpnext-dev.sh menu-render-test >"$tmp4" 2>/dev/null || note_fail "120-col menu-render-test failed"
if ! grep -qE '\[1\].*\[7\]' "$tmp4"; then
  note_fail "expected two-column menu at COLUMNS=120"
  echo "----- 120-col render -----" >&2
  cat "$tmp4" >&2 || true
else
  pass "two-column menu at COLUMNS=120"
fi
rm -f "$tmp4"

# Fit-based fallback: oversized labels force single-column even at wide width.
# shellcheck source=lib/ui.sh disable=SC1091
source "$ROOT_DIR/lib/ui.sh"
export COLUMNS=120 MENU_TERMINAL_COLS=120
unset MENU_FORCE_ONE_COLUMN MENU_FORCE_TWO_COLUMNS
UI_FORCE_ASCII=1
ui_init
fit_tmp="$(mktemp /tmp/erpnext-dev-ui-fit.XXXXXX)"
ui_render_boxed_menu \
  "1|Short" \
  "2|This label is intentionally far too long to fit beside another column cell at normal panel widths" \
  >"$fit_tmp"
if grep -qE '\[1\].*\[2\]' "$fit_tmp"; then
  note_fail "fit-based fallback did not force single-column for oversized labels"
  cat "$fit_tmp" >&2 || true
else
  pass "fit-based single-column for oversized labels"
fi
rm -f "$fit_tmp"

# Pre-tee snapshot helper: when only ERPNEXT_DEV_TTY_COLS is set (no MENU/COLUMNS),
# ui_detect_terminal_cols must still return that width (simulates post-tee menu).
unset MENU_TERMINAL_COLS COLUMNS
export ERPNEXT_DEV_TTY_COLS=100
(
  unset MENU_TERMINAL_COLS COLUMNS
  export ERPNEXT_DEV_TTY_COLS=100
  detected="$(ui_detect_terminal_cols)"
  # Accept either live stty width or the snapshot/default (>=80 for usable menus).
  if ! [[ "$detected" =~ ^[0-9]+$ ]] || ((detected < 80)); then
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

# Numbered choices trigger the interactive page clear hook; back/quit do not.
clear_hook_file="$(mktemp /tmp/erpnext-dev-menu-clear-hook.XXXXXX)"
printf '4\n' | bash -c '
  source "'"$ROOT_DIR"'/lib/common.sh"
  source "'"$ROOT_DIR"'/lib/ui.sh"
  ui_clear_screen() { printf clear > "'"$clear_hook_file"'"; }
  menu_read_choice got
' >/dev/null
if [[ "$(cat "$clear_hook_file" 2>/dev/null || true)" == "clear" ]]; then
  pass "numbered menu selection starts a fresh action page"
else
  note_fail "numbered menu selection did not trigger page clear"
fi
rm -f "$clear_hook_file"

# The page return footer must accept q/Q as a real quit path instead of treating
# it as ignored text at an Enter-only pause.
if printf 'q\n' | bash -c '
  source "'"$ROOT_DIR"'/lib/common.sh"
  ASSUME_YES=0
  MENU_TEST_INTERACTIVE_PAUSE=1
  pause_after_screen "Press Enter to return to Test menu..."
  exit 99
' >/dev/null 2>&1; then
  pass "result-page footer accepts q to quit"
else
  note_fail "result-page footer q handling failed"
fi

# v1.19.16 information architecture: Advanced and Access are grouped routing menus,
# not the former 50-item / 29-item flat command indexes.
adv_tmp="$(mktemp /tmp/erpnext-dev-ui-advanced.XXXXXX)"
if ! printf 'q\n' | ./erpnext-dev.sh advanced >"$adv_tmp" 2>/dev/null; then
  note_fail "advanced menu render failed"
fi
grep -q "Installation & repair" "$adv_tmp" || note_fail "Advanced missing Installation & repair"
grep -q "Deployment engine" "$adv_tmp" || note_fail "Advanced missing Deployment engine"
grep -q "Services & logs" "$adv_tmp" || note_fail "Advanced missing Services & logs"
grep -q "Domains & HTTPS" "$adv_tmp" || note_fail "Advanced missing Domains & HTTPS"
grep -q "Developer tools" "$adv_tmp" || note_fail "Advanced missing Developer tools"
if grep -q "50) Credentials / Login" "$adv_tmp"; then
  note_fail "Advanced still exposes the legacy 50-item flat menu"
fi
rm -f "$adv_tmp"

access_tmp="$(mktemp /tmp/erpnext-dev-ui-access.XXXXXX)"
if ! printf 'q\n' | ./erpnext-dev.sh access >"$access_tmp" 2>/dev/null; then
  note_fail "access menu render failed"
fi
grep -q "Browser access information" "$access_tmp" || note_fail "Access missing browser access information"
grep -q "Local network & stable IP" "$access_tmp" || note_fail "Access missing local network routing"
grep -q "Hostname & hosts mapping" "$access_tmp" || note_fail "Access missing hostname / hosts routing"
grep -q "HTTPS & domains" "$access_tmp" || note_fail "Access missing HTTPS & domains routing"
if grep -q "29) Show host access test guide" "$access_tmp"; then
  note_fail "Access still exposes the legacy 29-item flat menu"
fi
rm -f "$access_tmp"

if ((fail > 0)); then
  echo "test-ui-render: ${fail} failure(s)" >&2
  echo "----- render output (compact) -----" >&2
  cat "$tmp" >&2 || true
  exit 1
fi
echo "test-ui-render: all checks passed"
