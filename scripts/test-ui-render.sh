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
grep -q "Network & access" "$tmp" || note_fail "missing Network & access item"
grep -q "HTTPS & domains" "$tmp" || note_fail "missing HTTPS & domains item"
grep -q "Backups & restore" "$tmp" || note_fail "missing Backups & restore item"
grep -q "Operations" "$tmp" || note_fail "missing Operations item"
grep -q "System Overview" "$tmp" || note_fail "missing System Overview"
grep -q "CPU" "$tmp" || note_fail "missing CPU metric"
grep -q "RAM" "$tmp" || note_fail "missing RAM metric"
grep -q "Disk" "$tmp" || note_fail "missing Disk metric"
grep -qE '\[D\][[:space:]]+Dashboard' "$tmp" || note_fail "missing Dashboard shortcut"
grep -qE '\[L\][[:space:]]+Logs' "$tmp" || note_fail "missing Logs shortcut"
grep -q "Choose an option" "$tmp" || note_fail "missing Choose an option prompt"
grep -qE '\[q\]|q\) Quit|Q\. Quit' "$tmp" || note_fail "missing quit affordance"

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
grep -qE 'Go-live[[:space:]]+[+!x-]' "$tmp" \
  || note_fail "layout missing Go-live status indicator"
grep -qE 'Go-live[[:space:]]+-' "$tmp" \
  || note_fail "local mode should render Go-live as a neutral indicator"
grep -qE 'HTTPS[[:space:]]+[+!x-]' "$tmp" \
  || note_fail "layout missing HTTPS status indicator"
grep -qE 'HTTPS[[:space:]]+-' "$tmp" \
  || note_fail "local mode without configured HTTPS should render a neutral HTTPS indicator"
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

# Responsive dashboard width matrix: every rendered line must stay inside the
# effective panel width, and the System Overview must remain visible.
for dashboard_cols in 60 79 80 100 119 120 160; do
  export COLUMNS="$dashboard_cols" MENU_TERMINAL_COLS="$dashboard_cols"
  export MENU_FORCE_ONE_COLUMN=false
  unset MENU_FORCE_TWO_COLUMNS
  dashboard_tmp="$(mktemp /tmp/erpnext-dev-ui-dashboard-${dashboard_cols}.XXXXXX)"
  ./erpnext-dev.sh menu-render-test >"$dashboard_tmp" 2>/dev/null \
    || note_fail "dashboard render failed at width ${dashboard_cols}"
  effective_width="$dashboard_cols"
  ((effective_width > 120)) && effective_width=120
  ((effective_width < 60)) && effective_width=60
  if ! awk -v max="$effective_width" 'length($0) > max { bad=1 } END { exit bad }' "$dashboard_tmp"; then
    note_fail "dashboard render exceeded ${effective_width} columns at width ${dashboard_cols}"
    cat "$dashboard_tmp" >&2 || true
  fi
  grep -q "System Overview" "$dashboard_tmp" \
    || note_fail "System Overview missing at width ${dashboard_cols}"
  rm -f "$dashboard_tmp"
done
pass "responsive dashboard width matrix"

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
grep -q "Access overview" "$access_tmp" \
  || note_fail "Access missing Access overview routing"
grep -q "Verify access" "$access_tmp" \
  || note_fail "Access missing Verify access routing"
grep -q "Network status" "$access_tmp" \
  || note_fail "Access missing Network status routing"
grep -q "Network & IP" "$access_tmp" \
  || note_fail "Access missing local Network & IP routing"
grep -q "Hostname & mapping" "$access_tmp" \
  || note_fail "Access missing local Hostname & mapping routing"
grep -q "Credentials" "$access_tmp" \
  || note_fail "Access missing Credentials routing"
grep -q "Access doctor" "$access_tmp" \
  || note_fail "Access missing local Access doctor routing"
grep -q "HTTPS & domains" "$access_tmp" \
  || note_fail "Access missing HTTPS & domains routing"
grep -qE 'B\.[[:space:]]+Back' "$access_tmp" \
  || note_fail "Access missing canonical B. Back footer"
grep -qE 'Q\.[[:space:]]+Quit' "$access_tmp" \
  || note_fail "Access missing canonical Q. Quit footer"
if grep -q "Back to " "$access_tmp"; then
  note_fail "Access still renders destination-specific Back to wording"
fi
if grep -q "29) Show host access test guide" "$access_tmp"; then
  note_fail "Access still exposes the legacy 29-item flat menu"
fi
rm -f "$access_tmp"

# Categorized Backup & Recovery hub.
backup_hub_tmp="$(mktemp /tmp/erpnext-dev-ui-backup-hub.XXXXXX)"

if ! printf 'q\n' | env \
  NO_COLOR=1 \
  FORCE_NO_COLOR=1 \
  TERM=dumb \
  UI_FORCE_ASCII=1 \
  MENU_NO_CLEAR=1 \
  COLUMNS=120 \
  MENU_TERMINAL_COLS=120 \
  ./erpnext-dev.sh backup-menu >"$backup_hub_tmp" 2>/dev/null; then
  note_fail "Backup & Recovery hub render failed"
fi

grep -qE '\[1\].*Overview.*\[5\].*Restore' "$backup_hub_tmp" \
  || note_fail "Backup hub missing Overview / Restore routing"

grep -qE '\[2\].*Create backup.*\[6\].*Recovery readiness' "$backup_hub_tmp" \
  || note_fail "Backup hub missing Create backup / Recovery readiness routing"

grep -qE '\[3\].*Verify backups.*\[7\].*Off-VM backups' "$backup_hub_tmp" \
  || note_fail "Backup hub missing Verify / Off-VM routing"

grep -qE '\[4\].*Scheduled backups.*\[8\].*Retention' "$backup_hub_tmp" \
  || note_fail "Backup hub missing Scheduled backups / Retention routing"

grep -qE '\[M\].*Maintenance' "$backup_hub_tmp" \
  || note_fail "Backup hub missing Maintenance routing"

if grep -qE '\[1\].*Database backup' "$backup_hub_tmp"; then
  note_fail "Backup hub still exposes the legacy flat menu"
fi

if ! awk '
  index($0, "Overview") && index($0, "Restore") {
    found = 1
    if (length($0) != 120 || substr($0, 120, 1) != "|") {
      bad = 1
    }
  }
  END {
    exit !(found && !bad)
  }
' "$backup_hub_tmp"; then
  note_fail "Backup hub right border is not aligned at 120 columns"
fi

grep -qE 'B\.[[:space:]]+Back' "$backup_hub_tmp" \
  || note_fail "Backup hub missing canonical Back footer"

grep -qE 'Q\.[[:space:]]+Quit' "$backup_hub_tmp" \
  || note_fail "Backup hub missing canonical Quit footer"

rm -f "$backup_hub_tmp"

# Create Backup submenu.
backup_create_tmp="$(mktemp /tmp/erpnext-dev-ui-backup-create.XXXXXX)"

if ! printf '2\nq\n' | env \
  NO_COLOR=1 \
  FORCE_NO_COLOR=1 \
  TERM=dumb \
  UI_FORCE_ASCII=1 \
  MENU_NO_CLEAR=1 \
  COLUMNS=120 \
  MENU_TERMINAL_COLS=120 \
  ./erpnext-dev.sh backup-menu >"$backup_create_tmp" 2>/dev/null; then
  note_fail "Create Backup submenu render failed"
fi

grep -q "Create Backup" "$backup_create_tmp" \
  || note_fail "Create Backup submenu title missing"

grep -q "Database only" "$backup_create_tmp" \
  || note_fail "Create Backup submenu missing Database only"

grep -q "Database + files" "$backup_create_tmp" \
  || note_fail "Create Backup submenu missing Database + files"

rm -f "$backup_create_tmp"

# Scheduled Backups submenu.
backup_schedule_tmp="$(mktemp /tmp/erpnext-dev-ui-backup-schedule.XXXXXX)"

if ! printf '4\nq\n' | env \
  NO_COLOR=1 \
  FORCE_NO_COLOR=1 \
  TERM=dumb \
  UI_FORCE_ASCII=1 \
  MENU_NO_CLEAR=1 \
  COLUMNS=120 \
  MENU_TERMINAL_COLS=120 \
  ./erpnext-dev.sh backup-menu >"$backup_schedule_tmp" 2>/dev/null; then
  note_fail "Scheduled Backups submenu render failed"
fi

grep -q "Scheduled Backups" "$backup_schedule_tmp" \
  || note_fail "Scheduled Backups submenu title missing"

grep -q "Configure schedule" "$backup_schedule_tmp" \
  || note_fail "Scheduled Backups submenu missing Configure schedule"

grep -q "Disable schedule" "$backup_schedule_tmp" \
  || note_fail "Scheduled Backups submenu missing Disable schedule"

rm -f "$backup_schedule_tmp"

# Narrow Backup & Recovery layout must remain single-column.
backup_narrow_tmp="$(mktemp /tmp/erpnext-dev-ui-backup-narrow.XXXXXX)"

if ! printf 'q\n' | env \
  NO_COLOR=1 \
  FORCE_NO_COLOR=1 \
  TERM=dumb \
  UI_FORCE_ASCII=1 \
  MENU_NO_CLEAR=1 \
  COLUMNS=70 \
  MENU_TERMINAL_COLS=70 \
  ./erpnext-dev.sh backup-menu >"$backup_narrow_tmp" 2>/dev/null; then
  note_fail "narrow Backup & Recovery hub render failed"
fi

if grep -qE '\[1\].*\[5\]' "$backup_narrow_tmp"; then
  note_fail "Backup hub did not switch to single-column at 70 columns"
fi

grep -q "Overview" "$backup_narrow_tmp" \
  || note_fail "narrow Backup hub missing Overview"

grep -q "Restore" "$backup_narrow_tmp" \
  || note_fail "narrow Backup hub missing Restore"

rm -f "$backup_narrow_tmp"

# Environment-aware Security hub.
security_local_tmp="$(mktemp /tmp/erpnext-dev-ui-security-local.XXXXXX)"

if ! env \
  NO_COLOR=1 \
  FORCE_NO_COLOR=1 \
  TERM=dumb \
  UI_FORCE_ASCII=1 \
  COLUMNS=120 \
  MENU_TERMINAL_COLS=120 \
  bash -c '
    source "'"$ROOT_DIR"'/lib/common.sh"
    source "'"$ROOT_DIR"'/lib/ui.sh"
    source "'"$ROOT_DIR"'/lib/firewall.sh"
    ui_init
    render_local_security_hub_options
    ui_submenu_footer
  ' >"$security_local_tmp" 2>/dev/null; then
  note_fail "local Security hub render failed"
fi

grep -qE '\[1\].*Overview.*\[5\].*Intrusion protection' \
  "$security_local_tmp" \
  || note_fail "local Security hub missing Overview / Intrusion protection"

grep -qE '\[2\].*Hardening.*\[6\].*Credentials' \
  "$security_local_tmp" \
  || note_fail "local Security hub missing Hardening / Credentials"

grep -qE '\[3\].*Firewall.*\[7\].*Security audit' \
  "$security_local_tmp" \
  || note_fail "local Security hub missing Firewall / Security audit"

grep -qE '\[4\].*Access recovery.*\[8\].*Rollback snapshots' \
  "$security_local_tmp" \
  || note_fail "local Security hub missing recovery routing"

grep -qE '\[S\].*Status.*\[G\].*Guidance' \
  "$security_local_tmp" \
  || note_fail "local Security hub missing Status / Guidance"

if grep -q "Cloud guidance" "$security_local_tmp"; then
  note_fail "local Security hub exposes production Cloud guidance"
fi

if ! awk '
  index($0, "Overview") && index($0, "Intrusion protection") {
    found = 1

    if (length($0) != 120 || substr($0, 120, 1) != "|") {
      bad = 1
    }
  }

  END {
    exit !(found && !bad)
  }
' "$security_local_tmp"; then
  note_fail "local Security hub right border is not aligned"
fi

grep -qE 'B\.[[:space:]]+Back' "$security_local_tmp" \
  || note_fail "local Security hub missing canonical Back footer"

grep -qE 'Q\.[[:space:]]+Quit' "$security_local_tmp" \
  || note_fail "local Security hub missing canonical Quit footer"

rm -f "$security_local_tmp"

security_prod_tmp="$(mktemp /tmp/erpnext-dev-ui-security-production.XXXXXX)"

if ! env \
  NO_COLOR=1 \
  FORCE_NO_COLOR=1 \
  TERM=dumb \
  UI_FORCE_ASCII=1 \
  COLUMNS=120 \
  MENU_TERMINAL_COLS=120 \
  bash -c '
    source "'"$ROOT_DIR"'/lib/common.sh"
    source "'"$ROOT_DIR"'/lib/ui.sh"
    source "'"$ROOT_DIR"'/lib/firewall.sh"
    ui_init
    render_production_security_hub_options
    ui_submenu_footer
  ' >"$security_prod_tmp" 2>/dev/null; then
  note_fail "production Security hub render failed"
fi

grep -qE '\[4\].*Exposure.*\[8\].*Recovery' "$security_prod_tmp" \
  || note_fail "production Security hub missing Exposure / Recovery"

grep -qE '\[S\].*Status.*\[G\].*Cloud guidance' "$security_prod_tmp" \
  || note_fail "production Security hub missing Status / Cloud guidance"

if grep -q "Access recovery" "$security_prod_tmp"; then
  note_fail "production Security hub exposes local Access recovery"
fi

rm -f "$security_prod_tmp"

security_narrow_tmp="$(mktemp /tmp/erpnext-dev-ui-security-narrow.XXXXXX)"

if ! env \
  NO_COLOR=1 \
  FORCE_NO_COLOR=1 \
  TERM=dumb \
  UI_FORCE_ASCII=1 \
  COLUMNS=70 \
  MENU_TERMINAL_COLS=70 \
  bash -c '
    source "'"$ROOT_DIR"'/lib/common.sh"
    source "'"$ROOT_DIR"'/lib/ui.sh"
    source "'"$ROOT_DIR"'/lib/firewall.sh"
    ui_init
    render_local_security_hub_options
  ' >"$security_narrow_tmp" 2>/dev/null; then
  note_fail "narrow Security hub render failed"
fi

if grep -qE '\[1\].*\[5\]' "$security_narrow_tmp"; then
  note_fail "Security hub did not switch to single-column at 70 columns"
fi

grep -q "Overview" "$security_narrow_tmp" \
  || note_fail "narrow Security hub missing Overview"

grep -q "Rollback snapshots" "$security_narrow_tmp" \
  || note_fail "narrow Security hub missing Rollback snapshots"

rm -f "$security_narrow_tmp"

if ((fail > 0)); then
  echo "test-ui-render: ${fail} failure(s)" >&2
  echo "----- render output (compact) -----" >&2
  cat "$tmp" >&2 || true
  exit 1
fi
echo "test-ui-render: all checks passed"
