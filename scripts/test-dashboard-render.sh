#!/usr/bin/env bash
# Hermetic Operations Dashboard render checks (v1.17.5+).
# No sudo, no install, no network. Uses fixture SNAPSHOT_* via dashboard-render-test.
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
bash -n lib/dashboard.sh || note_fail "bash -n lib/dashboard.sh"

export NO_COLOR=1
export FORCE_NO_COLOR=1
export TERM=dumb
export COLUMNS=100
export UI_FORCE_ASCII=1

tmp="$(mktemp /tmp/erpnext-dev-dashboard-render.XXXXXX)"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

if ! ./erpnext-dev.sh dashboard-render-test >"$tmp" 2>/tmp/erpnext-dev-dashboard-render.err; then
  note_fail "dashboard-render-test exited non-zero"
  cat /tmp/erpnext-dev-dashboard-render.err >&2 || true
fi

grep -q "ERPNext Developer Toolkit" "$tmp" || note_fail "missing toolkit title"
grep -q "Resources" "$tmp" || note_fail "missing Resources section"
grep -q "Application health" "$tmp" || note_fail "missing Application health section"
grep -q "Protection & recovery" "$tmp" || note_fail "missing Protection section"
grep -q "Monitoring & auto-healing" "$tmp" || note_fail "missing Monitoring section"
grep -q "CRITICAL" "$tmp" || note_fail "missing overall CRITICAL from fixture"
grep -q "Web / HTTP" "$tmp" || note_fail "missing Web / HTTP row"
grep -q "Engine runtime" "$tmp" || note_fail "missing Engine runtime row"

# Must not use the legacy ==== box style for section headers.
if grep -qE '^={10,}$' "$tmp"; then
  note_fail "legacy ==== ui_box_start lines still present in dashboard output"
fi

if grep -q $'\033' "$tmp"; then
  note_fail "ANSI escape codes present with NO_COLOR=1 / TERM=dumb"
fi

# Compact width still renders section titles.
export COLUMNS=70
tmp2="$(mktemp /tmp/erpnext-dev-dashboard-render-compact.XXXXXX)"
./erpnext-dev.sh dashboard-render-test >"$tmp2" 2>/dev/null || note_fail "compact dashboard-render-test failed"
grep -q "Resources" "$tmp2" || note_fail "compact layout missing Resources"
if grep -q $'\033' "$tmp2"; then
  note_fail "ANSI escape codes in compact layout with NO_COLOR=1"
fi
rm -f "$tmp2"

if ((fail > 0)); then
  echo "test-dashboard-render: ${fail} failure(s)" >&2
  echo "----- render output -----" >&2
  cat "$tmp" >&2 || true
  exit 1
fi
echo "test-dashboard-render: all checks passed"
