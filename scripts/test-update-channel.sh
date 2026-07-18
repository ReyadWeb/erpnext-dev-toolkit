#!/usr/bin/env bash
# Hermetic checks for update-toolkit channel / install-slot resolution.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${label}: expected '${expected}' got '${actual}'" >&2
    fail=$((fail + 1))
  else
    echo "OK: ${label}"
  fi
}

# Minimal stubs so we can source security.sh helpers.
APP_NAME="ERPNext Developer Toolkit"
SCRIPT_VERSION="1.17.5"
ASSUME_YES=1
_ERPNEXT_DEV_ROOT="$ROOT_DIR"

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/security.sh"

unset TOOLKIT_UPDATE_CHANNEL TOOLKIT_UPDATE_FROM_MAIN TOOLKIT_UPDATE_VERSION TOOLKIT_UPDATE_SLOT

TOOLKIT_UPDATE_CHANNEL=main
assert_eq "main channel default slot" "main" "$(resolve_toolkit_update_version)"

TOOLKIT_UPDATE_SLOT=field-test
assert_eq "main channel custom slot" "field-test" "$(resolve_toolkit_update_version)"
unset TOOLKIT_UPDATE_SLOT

# Accidental tag-shaped VERSION must not become the install slot on main.
TOOLKIT_UPDATE_VERSION=v1.17.5
assert_eq "main channel ignores v* VERSION" "main" "$(resolve_toolkit_update_version)"
unset TOOLKIT_UPDATE_VERSION TOOLKIT_UPDATE_CHANNEL

TOOLKIT_UPDATE_VERSION=v1.17.5
assert_eq "tag channel keeps VERSION" "v1.17.5" "$(resolve_toolkit_update_version)"

if ((fail > 0)); then
  echo "test-update-channel: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-update-channel: all checks passed"
