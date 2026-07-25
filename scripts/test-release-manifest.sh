#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d /tmp/erpnext-dev-manifest-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_root="${tmp_dir}/root"
manifest="${fixture_root}/RELEASE-MANIFEST.txt"

mkdir -p \
  "${fixture_root}/lib" \
  "${fixture_root}/.github/workflows"

printf 'entrypoint\n' >"${fixture_root}/erpnext-dev.sh"
printf 'module\n' >"${fixture_root}/lib/common.sh"
printf 'workflow\n' >"${fixture_root}/.github/workflows/ci.yml"
printf 'checksums\n' >"${fixture_root}/SHA256SUMS"

cat >"$manifest" <<'EOF_VALID'
# Valid fixture
erpnext-dev.sh
SHA256SUMS
lib/common.sh
.github/workflows/ci.yml
EOF_VALID

run_parser() {
  ERPNEXT_RELEASE_ROOT="$fixture_root" \
    ERPNEXT_RELEASE_MANIFEST="$manifest" \
    scripts/release-manifest-files.sh "$@"
}

expected_all="$(
  printf '%s\n' \
    erpnext-dev.sh \
    SHA256SUMS \
    lib/common.sh \
    .github/workflows/ci.yml
)"
[[ "$(run_parser --include-checksum)" == "$expected_all" ]] \
  || fail "valid manifest output differed from expected"

expected_without_checksum="$(
  printf '%s\n' \
    erpnext-dev.sh \
    lib/common.sh \
    .github/workflows/ci.yml
)"
[[ "$(run_parser --exclude-checksum)" == "$expected_without_checksum" ]] \
  || fail "checksum exclusion differed from expected"

expect_failure() {
  local label="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    fail "${label} was accepted"
  fi
}

cat >"$manifest" <<'EOF_DUPLICATE'
erpnext-dev.sh
erpnext-dev.sh
EOF_DUPLICATE
expect_failure "duplicate entry" run_parser --include-checksum

printf '%s\n' '/etc/passwd' >"$manifest"
expect_failure "absolute path" run_parser --include-checksum

printf '%s\n' '../outside' >"$manifest"
expect_failure "parent traversal" run_parser --include-checksum

printf '%s\n' 'lib/../common.sh' >"$manifest"
expect_failure "embedded traversal" run_parser --include-checksum

printf '%s\n' 'file with spaces' >"$manifest"
expect_failure "whitespace path" run_parser --include-checksum

printf '%s\n' 'missing.txt' >"$manifest"
expect_failure "missing file" run_parser --include-checksum

mkdir -p "${fixture_root}/directory"
printf '%s\n' 'directory' >"$manifest"
expect_failure "directory entry" run_parser --include-checksum

ln -s erpnext-dev.sh "${fixture_root}/linked-entry"
printf '%s\n' 'linked-entry' >"$manifest"
expect_failure "symbolic-link entry" run_parser --include-checksum

echo "release manifest tests: all checks passed"
