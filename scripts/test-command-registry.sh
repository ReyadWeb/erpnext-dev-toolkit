#!/usr/bin/env bash
set -Eeuo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERPNEXT_DEV_LOG_DIR=/tmp LOG_FILE=/dev/null source "$root_dir/erpnext-dev.sh" --help >/dev/null 2>&1 || true
if ! command_registry_validate; then
  echo 'FAIL: command registry validation' >&2
  exit 1
fi
records="$(command_registry_records)"
[[ "$(printf '%s\n' "$records" | wc -l)" -ge 8 ]]
if printf '%s\n' "$records" | awk -F'|' '{print $1}' | sort | uniq -d | grep -q .; then exit 1; fi
echo 'command registry tests: all checks passed'
