#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/release-test-env.sh
source "${ROOT_DIR}/scripts/release-test-env.sh"
release_test_env_reexec "$0" "$@"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d /tmp/erpnext-dev-artifact-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_root="${tmp_dir}/root"
manifest="${fixture_root}/RELEASE-MANIFEST.txt"
checksums="${fixture_root}/SHA256SUMS"

mkdir -p "${fixture_root}/lib"

printf 'entrypoint\n' >"${fixture_root}/erpnext-dev.sh"
printf 'module\n' >"${fixture_root}/lib/common.sh"

cat >"$manifest" <<'EOF_MANIFEST'
erpnext-dev.sh
SHA256SUMS
lib/common.sh
EOF_MANIFEST

generate_fixture_checksums() {
  (
    cd "$fixture_root"
    sha256sum erpnext-dev.sh lib/common.sh >SHA256SUMS
  )
}

run_check() {
  ERPNEXT_RELEASE_ROOT="$fixture_root" \
    ERPNEXT_RELEASE_MANIFEST="$manifest" \
    ERPNEXT_RELEASE_CHECKSUMS="$checksums" \
    ERPNEXT_RELEASE_MANIFEST_HELPER="${ROOT_DIR}/scripts/release-manifest-files.sh" \
    scripts/check-release-artifact-consistency.sh
}

expect_failure() {
  local label="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    fail "${label} was accepted"
  fi
}

generate_fixture_checksums
run_check >/dev/null

grep -v 'lib/common.sh' "$checksums" >"${checksums}.tmp"
mv "${checksums}.tmp" "$checksums"
expect_failure "missing checksum entry" run_check

generate_fixture_checksums
printf 'extra\n' >"${fixture_root}/extra.txt"
(
  cd "$fixture_root"
  sha256sum extra.txt >>SHA256SUMS
)
expect_failure "checksum entry outside manifest" run_check

generate_fixture_checksums
printf 'tampered\n' >>"${fixture_root}/lib/common.sh"
expect_failure "tampered artifact" run_check

printf 'module\n' >"${fixture_root}/lib/common.sh"
generate_fixture_checksums
cat "$checksums" >>"${checksums}.duplicate"
cat "${checksums}.duplicate" >>"$checksums"
expect_failure "duplicate checksum entry" run_check

echo "release artifact consistency tests: all checks passed"
