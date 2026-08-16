#!/usr/bin/env bash
set -Eeuo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERPNEXT_DEV_LOG_DIR=/tmp LOG_FILE=/dev/null source "$root_dir/erpnext-dev.sh" --help >/dev/null 2>&1 || true
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
command_registry_validate || fail 'command registry validation'
records="$(command_registry_records)"
[[ "$(printf '%s\n' "$records" | wc -l)" -ge 8 ]] || fail 'record count'
require_sudo() { :; }

dispatcher_source="$(sed -n '/^main() {/,$p' "$root_dir/erpnext-dev.sh")"
while IFS='|' read -r name aliases handler _; do
  IFS=',' read -ra names <<<"$name${aliases:+,$aliases}"
  for token in "${names[@]}"; do
    grep -Fq -- "$token" <<<"$dispatcher_source" || fail "dispatch rejected $token"
  done
  grep -Fq -- "$handler" <<<"$dispatcher_source" || fail "handler drift for $name"
done <<<"$records"

help_text="$(show_help 2>/dev/null || true)"
while IFS='|' read -r name _ _ _ _ _ _ _ _ json; do
  [[ "$json" == yes ]] || continue
  grep -Fq -- "$name" <<<"$help_text" || fail "help drift for $name"
done <<<"$records"

expect_invalid() {
  local fixture="$1"
  command_registry_records() { printf '%s\n' "$fixture"; }
  command_registry_validate && fail "invalid fixture accepted"
  unset -f command_registry_records
}
expect_invalid $'dup||show_menu|user|read-only|none|interactive|safe|native,docker|no\ndup||show_menu|user|read-only|none|interactive|safe|native,docker|no'
expect_invalid 'missing||no_such_handler|user|read-only|none|interactive|safe|native,docker|no'
expect_invalid 'bad||show_menu|operator|read-only|none|interactive|safe|native,docker|no'
expect_invalid 'bad||show_menu|user|mutating|none|interactive|safe|native,docker|no'
expect_invalid 'bad||show_menu|user|read-only|none|interactive|safe|native,remote|yes'
expect_invalid 'bad||show_menu|user|read-only|none|interactive|safe|native,docker|maybe'
expect_invalid 'bad|alias,alias|show_menu|user|read-only|none|interactive|safe|native,docker|no'
echo 'command registry tests: all checks passed'
