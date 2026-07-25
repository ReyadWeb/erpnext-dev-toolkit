#!/usr/bin/env bash
# Validate RELEASE-MANIFEST.txt and print one safe repository-relative file
# per line. The manifest is the authoritative release-content inventory.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROOT_DIR="${ERPNEXT_RELEASE_ROOT:-${DEFAULT_ROOT}}"
MANIFEST_FILE="${ERPNEXT_RELEASE_MANIFEST:-${ROOT_DIR}/RELEASE-MANIFEST.txt}"
MODE="${1:---include-checksum}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

trim_value() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"

  printf '%s' "$value"
}

validate_entry() {
  local entry="$1"
  local component

  [[ -n "$entry" ]] || fail "empty manifest entry"
  [[ "$entry" != /* ]] \
    || fail "absolute paths are forbidden in the release manifest: ${entry}"
  [[ "$entry" =~ ^[A-Za-z0-9._/-]+$ ]] \
    || fail "unsafe characters or whitespace in manifest path: ${entry}"
  [[ "$entry" != */ ]] \
    || fail "manifest entries must be files, not directory paths: ${entry}"
  [[ "$entry" != *"//"* ]] \
    || fail "empty path component in manifest entry: ${entry}"

  IFS='/' read -r -a components <<<"$entry"
  for component in "${components[@]}"; do
    [[ -n "$component" ]] \
      || fail "empty path component in manifest entry: ${entry}"
    [[ "$component" != "." && "$component" != ".." ]] \
      || fail "path traversal component in manifest entry: ${entry}"
  done

  [[ ! -L "${ROOT_DIR}/${entry}" ]] \
    || fail "symbolic links are forbidden in the release manifest: ${entry}"

  [[ -f "${ROOT_DIR}/${entry}" ]] \
    || fail "manifest entry is missing or not a regular file: ${entry}"
}

case "$MODE" in
  --include-checksum | --exclude-checksum) ;;
  *)
    fail "usage: scripts/release-manifest-files.sh [--include-checksum|--exclude-checksum]"
    ;;
esac

[[ -f "$MANIFEST_FILE" ]] \
  || fail "release manifest is missing: ${MANIFEST_FILE}"

declare -A seen=()
count=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  entry="${raw_line%%#*}"
  entry="$(trim_value "$entry")"

  [[ -n "$entry" ]] || continue

  validate_entry "$entry"

  [[ -z "${seen[$entry]:-}" ]] \
    || fail "duplicate release manifest entry: ${entry}"
  seen["$entry"]=1

  if [[ "$MODE" == "--exclude-checksum" && "$entry" == "SHA256SUMS" ]]; then
    continue
  fi

  printf '%s\n' "$entry"
  count=$((count + 1))
done <"$MANIFEST_FILE"

((count > 0)) || fail "release manifest contains no files"
