#!/usr/bin/env bash
# Verify exact coverage between RELEASE-MANIFEST.txt and SHA256SUMS, then
# verify every declared artifact hash.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROOT_DIR="${ERPNEXT_RELEASE_ROOT:-${DEFAULT_ROOT}}"
MANIFEST_FILE="${ERPNEXT_RELEASE_MANIFEST:-${ROOT_DIR}/RELEASE-MANIFEST.txt}"
CHECKSUM_FILE="${ERPNEXT_RELEASE_CHECKSUMS:-${ROOT_DIR}/SHA256SUMS}"
MANIFEST_HELPER="${ERPNEXT_RELEASE_MANIFEST_HELPER:-${SCRIPT_DIR}/release-manifest-files.sh}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$MANIFEST_HELPER" ]] \
  || fail "release manifest helper is missing or not executable: ${MANIFEST_HELPER}"
[[ -f "$CHECKSUM_FILE" ]] \
  || fail "checksum file is missing: ${CHECKSUM_FILE}"

mapfile -t manifest_entries < <(
  ERPNEXT_RELEASE_ROOT="$ROOT_DIR" \
    ERPNEXT_RELEASE_MANIFEST="$MANIFEST_FILE" \
    "$MANIFEST_HELPER" --exclude-checksum
)

((${#manifest_entries[@]} > 0)) \
  || fail "release manifest has no checksum targets"

declare -A checksum_seen=()
checksum_entries=()
line_number=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line_number=$((line_number + 1))
  [[ -n "$line" ]] || fail "blank line in ${CHECKSUM_FILE}:${line_number}"

  if [[ ! "$line" =~ ^([0-9a-fA-F]{64})[[:space:]][[:space:]](\*?)([^[:space:]]+)$ ]]; then
    fail "malformed checksum line ${line_number}: ${line}"
  fi

  file="${BASH_REMATCH[3]}"

  [[ -z "${checksum_seen[$file]:-}" ]] \
    || fail "duplicate checksum entry: ${file}"

  checksum_seen["$file"]=1
  checksum_entries+=("$file")
done <"$CHECKSUM_FILE"

((${#checksum_entries[@]} > 0)) \
  || fail "checksum file contains no entries"

manifest_sorted="$(
  printf '%s\n' "${manifest_entries[@]}" \
    | LC_ALL=C sort
)"
checksum_sorted="$(
  printf '%s\n' "${checksum_entries[@]}" \
    | LC_ALL=C sort
)"

if [[ "$manifest_sorted" != "$checksum_sorted" ]]; then
  only_manifest="$(
    comm -23 \
      <(printf '%s\n' "$manifest_sorted") \
      <(printf '%s\n' "$checksum_sorted") \
      | tr '\n' ' '
  )"
  only_checksums="$(
    comm -13 \
      <(printf '%s\n' "$manifest_sorted") \
      <(printf '%s\n' "$checksum_sorted") \
      | tr '\n' ' '
  )"

  [[ -z "$only_manifest" ]] \
    || echo "FAIL: manifest files missing from SHA256SUMS: ${only_manifest}" >&2
  [[ -z "$only_checksums" ]] \
    || echo "FAIL: SHA256SUMS files absent from manifest: ${only_checksums}" >&2

  exit 1
fi

(
  cd "$ROOT_DIR"
  sha256sum -c "$CHECKSUM_FILE"
)

echo "OK: release manifest and SHA256SUMS cover the same ${#manifest_entries[@]} artifact(s)"
