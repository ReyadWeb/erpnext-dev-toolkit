#!/usr/bin/env bash
# Hermetic regression for install_self_for_reuse path resolution (Ubuntu 26.04 /
# sudo-rs: readlink -f on a relative invoke path can return empty).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
note_fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}
pass() { echo "OK: $*"; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fake_root="${tmpdir}/fake-repo"
mkdir -p "${fake_root}/lib"
cp erpnext-dev.sh "${fake_root}/"
cp -a lib/. "${fake_root}/lib/"

# Simulate bootstrap resolution when readlink -f would fail on a relative path.
export ERPNEXT_DEV_ENTRY_SCRIPT="${fake_root}/erpnext-dev.sh"
export TOOLKIT_INSTALL_DIR="${tmpdir}/opt/erpnext-dev"
export INSTALLER_CANONICAL_PATH="${TOOLKIT_INSTALL_DIR}/erpnext-dev.sh"
export TOOLKIT_CLI_PATH="${tmpdir}/usr/local/bin/erpnext-dev"

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"

install_self_for_reuse() {
  local src dest src_root dest_root
  dest="${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"
  src="${ERPNEXT_DEV_ENTRY_SCRIPT:-}"
  if [[ -z "$src" || ! -f "$src" ]]; then
    src="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
  fi
  if [[ -z "$src" || ! -f "$src" ]]; then
    src="${BASH_SOURCE[0]}"
    if [[ "$src" != /* ]]; then
      src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
    fi
  fi
  [[ -f "$src" ]] || return 1
  src_root="$(cd "$(dirname "$src")" && pwd)"
  dest_root="$(dirname "$dest")"
  mkdir -p "$dest_root" || return 1
  cp "$src" "$dest" || return 1
  sync_toolkit_lib_tree "$src_root" "$dest_root" || return 1
  return 0
}

if install_self_for_reuse; then
  pass "install_self_for_reuse copied entry + lib"
else
  note_fail "install_self_for_reuse failed"
fi

[[ -f "${INSTALLER_CANONICAL_PATH}" ]] || note_fail "missing ${INSTALLER_CANONICAL_PATH}"
[[ -f "${TOOLKIT_INSTALL_DIR}/lib/common.sh" ]] || note_fail "missing lib/common.sh under /opt"

if ((failures > 0)); then
  echo "install-self path tests: ${failures} failure(s)" >&2
  exit 1
fi
echo "install-self path tests: all checks passed"
