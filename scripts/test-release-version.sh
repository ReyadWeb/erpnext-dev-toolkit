#!/usr/bin/env bash
# Hermetic tests for scripts/release-version.sh.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d /tmp/erpnext-dev-version-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

version_file="${tmp_dir}/VERSION"
entrypoint="${tmp_dir}/erpnext-dev.sh"

run_helper() {
  ERPNEXT_VERSION_FILE="$version_file" \
    ERPNEXT_ENTRYPOINT="$entrypoint" \
    scripts/release-version.sh "$@"
}

printf '%s\n' '1.20.0-beta.1' >"$version_file"

cat >"$entrypoint" <<'EOF_ENTRYPOINT'
#!/usr/bin/env bash
SCRIPT_VERSION="1.20.0-beta.1"
EOF_ENTRYPOINT

[[ "$(run_helper read)" == "1.20.0-beta.1" ]] \
  || fail "read did not return the canonical version"

[[ "$(run_helper tag)" == "v1.20.0-beta.1" ]] \
  || fail "tag did not return the canonical tag"

[[ "$(run_helper script)" == "1.20.0-beta.1" ]] \
  || fail "script did not return SCRIPT_VERSION"

[[ "$(run_helper channel)" == "beta" ]] \
  || fail "channel did not identify the beta version"

run_helper assert-script >/dev/null
run_helper assert-tag v1.20.0-beta.1 >/dev/null

if run_helper assert-tag v1.20.0 >/dev/null 2>&1; then
  fail "a mismatched tag was accepted"
fi

sed -i \
  's/1\.20\.0-beta\.1/1.20.0-beta.2/' \
  "$entrypoint"

if run_helper assert-script >/dev/null 2>&1; then
  fail "a mismatched SCRIPT_VERSION was accepted"
fi

printf '%s\n' 'not-a-version' >"$version_file"

if run_helper read >/dev/null 2>&1; then
  fail "invalid VERSION syntax was accepted"
fi

printf '%s\n\n%s\n' \
  '1.20.0-beta.1' \
  '1.20.0-beta.2' \
  >"$version_file"

if run_helper read >/dev/null 2>&1; then
  fail "multiple VERSION values were accepted"
fi

echo "release version tests: all checks passed"
