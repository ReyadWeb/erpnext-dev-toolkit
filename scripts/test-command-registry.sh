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

dispatcher_arm_for_token() {
  local source_file="$1" command_name="$2"
  awk -v command_name="$command_name" '
    /^  case / && index($0, "ACTION:-menu") { in_dispatcher = 1; next }
    !in_dispatcher { next }
    /^  esac$/ { exit }
    /^    [^[:space:]].*\)/ {
      if (matched) exit
      pattern = $0
      sub(/^    /, "", pattern)
      sub(/\).*/, "", pattern)
      count = split(pattern, tokens, /[[:space:]]*\|[[:space:]]*/)
      for (i = 1; i <= count; i++) {
        if (tokens[i] == command_name) matched = 1
      }
    }
    matched { print }
  ' "$source_file"
}

dispatcher_bindings_valid() {
  local source_file="$1" name aliases handler command_name arm
  while IFS='|' read -r name aliases handler _; do
    IFS=',' read -ra names <<<"$name${aliases:+,$aliases}"
    for command_name in "${names[@]}"; do
      arm="$(dispatcher_arm_for_token "$source_file" "$command_name")"
      [[ -n "$arm" ]] || {
        echo "missing dispatcher arm for ${command_name}" >&2
        return 1
      }
      grep -Eq "(^|[^a-zA-Z0-9_])${handler}([^a-zA-Z0-9_]|$)" <<<"$arm" \
        || {
          echo "dispatcher arm for ${command_name} does not call ${handler}" >&2
          return 1
        }
    done
  done <<<"$records"
}

dispatcher_bindings_valid "$root_dir/erpnext-dev.sh" || fail 'registry dispatcher binding mismatch'

swapped_dispatcher="$(mktemp)"
trap 'rm -f "$swapped_dispatcher"' EXIT
sed -e 's/update_toolkit/registry_swap_placeholder/g' \
  -e 's/rollback_toolkit/update_toolkit/g' \
  -e 's/registry_swap_placeholder/rollback_toolkit/g' \
  "$root_dir/erpnext-dev.sh" >"$swapped_dispatcher"
if dispatcher_bindings_valid "$swapped_dispatcher" 2>/dev/null; then
  fail 'swapped dispatcher handlers were accepted'
fi
rm -f "$swapped_dispatcher"
trap - EXIT

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
