#!/usr/bin/env bash
# Generate SHA256SUMS from the authoritative release manifest.
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

tmp_file="$(mktemp "${CHECKSUM_FILE}.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

count=0

while IFS= read -r file; do
  (
    cd "$ROOT_DIR"
    sha256sum "$file"
  ) >>"$tmp_file"
  count=$((count + 1))
done < <(
  ERPNEXT_RELEASE_ROOT="$ROOT_DIR" \
    ERPNEXT_RELEASE_MANIFEST="$MANIFEST_FILE" \
    "$MANIFEST_HELPER" --exclude-checksum
)

((count > 0)) || fail "release manifest contains no checksum targets"

mv "$tmp_file" "$CHECKSUM_FILE"
trap - EXIT

echo "Wrote ${CHECKSUM_FILE} with ${count} manifest artifact(s)."
