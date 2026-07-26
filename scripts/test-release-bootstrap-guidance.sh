#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

test_fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# shellcheck disable=SC2034 # consumed by the sourced bootstrap renderer
SCRIPT_VERSION="$(<VERSION)"
# shellcheck source=lib/common.sh
source lib/common.sh

rendered="$(verified_release_bundle_bootstrap "first-run" "  ")"

required_rendered=(
  'erpnext-dev-${VERSION}.tar.gz'
  "SHA256SUMS.asc"
  "docs/erpnext-dev-signing-key.asc"
  "BFC10C79427CF73496EA6F5A30BFD17DD559C8B6"
  "gpg --batch --verify SHA256SUMS.asc SHA256SUMS"
  "sha256sum -c SHA256SUMS"
  "TOOLKIT_UPDATE_VERSION=\"\$VERSION\""
  "sudo erpnext-dev first-run"
)

for expected in "${required_rendered[@]}"; do
  grep -Fq -- "$expected" <<<"$rendered" \
    || test_fail "rendered bootstrap is missing: $expected"
done

if grep -Eq 'raw\.githubusercontent\.com/.*/erpnext-dev\.sh' <<<"$rendered"; then
  test_fail "rendered bootstrap still downloads the entrypoint from raw.githubusercontent.com"
fi

active_guidance_files=(
  erpnext-dev.sh
  lib/backup.sh
  lib/ssl.sh
  lib/security.sh
  SECURITY.md
  TESTING.md
)

if grep -REn \
  'curl -fsSLO .*raw\.githubusercontent\.com/ReyadWeb/erpnext-dev-toolkit/.+erpnext-dev\.sh' \
  "${active_guidance_files[@]}"; then
  test_fail "obsolete two-file bootstrap guidance remains"
fi

[[ "$(grep -Fc 'verified_release_bundle_bootstrap "backup-server-setup" "  "' lib/backup.sh)" -eq 2 ]] \
  || test_fail "backup guidance must use the canonical helper twice"

[[ "$(grep -Fc 'verified_release_bundle_bootstrap "first-run" "  "' lib/ssl.sh)" -eq 1 ]] \
  || test_fail "SSL/setup guidance must use the canonical helper once"

[[ "$(grep -Fc 'verified_release_bundle_bootstrap "verify-toolkit" "  "' lib/security.sh)" -eq 1 ]] \
  || test_fail "integrity guidance must use the canonical helper once"

grep -Fq '$(verified_release_bundle_bootstrap "first-run" "  ")' erpnext-dev.sh \
  || test_fail "main help does not render the canonical signed bootstrap"

for doc in SECURITY.md TESTING.md; do
  grep -Fq 'erpnext-dev-${VERSION}.tar.gz' "$doc" \
    || test_fail "$doc does not document the release archive"
  grep -Fq 'SHA256SUMS.asc' "$doc" \
    || test_fail "$doc does not document signature verification"
  grep -Fq 'BFC10C79427CF73496EA6F5A30BFD17DD559C8B6' "$doc" \
    || test_fail "$doc does not pin the signing-key fingerprint"
done

echo "OK: signed release bootstrap guidance is canonical and regression-tested"
