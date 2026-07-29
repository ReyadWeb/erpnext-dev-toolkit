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
cp erpnext-dev.sh VERSION "${fake_root}/"
cp -a lib/. "${fake_root}/lib/"

# Simulate bootstrap resolution when readlink -f would fail on a relative path.
export ERPNEXT_DEV_ENTRY_SCRIPT="${fake_root}/erpnext-dev.sh"
export TOOLKIT_INSTALL_DIR="${tmpdir}/opt/erpnext-dev"
export INSTALLER_CANONICAL_PATH="${TOOLKIT_INSTALL_DIR}/erpnext-dev.sh"
export TOOLKIT_CLI_PATH="${tmpdir}/usr/local/bin/erpnext-dev"

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"

install_toolkit_cli_entry() {
  mkdir -p "$(dirname "$TOOLKIT_CLI_PATH")" || return 1
  ln -sf "$INSTALLER_CANONICAL_PATH" "$TOOLKIT_CLI_PATH" || return 1
  return 0
}

install_self_for_reuse() {
  local src dest src_root dest_root src_root_real dest_root_real
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
  src_root_real="$(cd "$src_root" && pwd -P)" || return 1
  dest_root_real="$(cd "$dest_root" && pwd -P)" || return 1
  if [[ "$src_root_real" == "$dest_root_real" ]]; then
    return 0
  fi
  cp "$src" "$dest" || return 1
  sync_toolkit_lib_tree "$src_root" "$dest_root" || return 1
  cp -a "${src_root}/VERSION" "${dest_root}/VERSION" || return 1
  install_toolkit_cli_entry || return 1
  return 0
}

install_toolkit_cli() {
  install_self_for_reuse
}

if install_self_for_reuse; then
  pass "install_self_for_reuse copied entry + lib"
else
  note_fail "install_self_for_reuse failed"
fi

export ERPNEXT_DEV_ENTRY_SCRIPT="${INSTALLER_CANONICAL_PATH}"
if install_self_for_reuse; then
  pass "install_self_for_reuse skipped installed source/destination path"
else
  note_fail "install_self_for_reuse failed when source and destination roots matched"
fi

export ERPNEXT_DEV_ENTRY_SCRIPT="${fake_root}/erpnext-dev.sh"
printf '%s\n' '# stale installed copy' >"${INSTALLER_CANONICAL_PATH}"
if install_toolkit_cli && grep -Fq 'ERPNext Developer Toolkit' "${INSTALLER_CANONICAL_PATH}"; then
  pass "install-cli refreshed stale installed toolkit from current source"
else
  note_fail "install-cli did not refresh stale installed toolkit"
fi

if sync_toolkit_lib_tree "$TOOLKIT_INSTALL_DIR" "$TOOLKIT_INSTALL_DIR"; then
  pass "sync_toolkit_lib_tree skipped same source/destination lib path"
else
  note_fail "sync_toolkit_lib_tree failed when source and destination lib paths matched"
fi

[[ -f "${INSTALLER_CANONICAL_PATH}" ]] || note_fail "missing ${INSTALLER_CANONICAL_PATH}"
[[ -f "${TOOLKIT_INSTALL_DIR}/lib/common.sh" ]] || note_fail "missing lib/common.sh under /opt"
[[ -f "${TOOLKIT_INSTALL_DIR}/VERSION" ]] || note_fail "missing VERSION under /opt"

if ((failures > 0)); then
  echo "install-self path tests: ${failures} failure(s)" >&2
  exit 1
fi
echo "install-self path tests: all checks passed"
