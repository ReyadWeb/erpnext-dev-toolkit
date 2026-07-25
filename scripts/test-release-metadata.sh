#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d /tmp/erpnext-dev-release-metadata-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="${tmp_dir}/fixture"
mkdir -p "$fixture"

printf '%s\n' '1.19.22' >"${fixture}/VERSION"
printf '%s\n' '#!/usr/bin/env bash' 'SCRIPT_VERSION="1.19.22"' >"${fixture}/erpnext-dev.sh"
printf '%s\n' '**Current release:** v1.19.22 · fixture' 'VERSION="v1.19.22"' >"${fixture}/README.md"
printf '%s\n' '**Current release:** v1.19.22 (fixture)' >"${fixture}/ROADMAP.md"
printf '%s\n' '**Current release:** v1.19.22 · fixture' >"${fixture}/TESTING.md"
printf '%s\n' '## v1.19.22 - Previous release' '' '- Previous.' >"${fixture}/CHANGELOG.md"
printf '%s\n' '# ERPNext Developer Toolkit Release Manifest v1.19.22' 'VERSION' >"${fixture}/RELEASE-MANIFEST.txt"

run_update() {
  ERPNEXT_RELEASE_ROOT="$fixture" \
    scripts/release-update-metadata.sh "$@"
}

run_update \
  1.20.0-beta.1 \
  "Release reliability foundation" >/dev/null

[[ "$(cat "${fixture}/VERSION")" == "1.20.0-beta.1" ]] \
  || fail "VERSION was not updated"

grep -qx 'SCRIPT_VERSION="1.20.0-beta.1"' "${fixture}/erpnext-dev.sh" \
  || fail "SCRIPT_VERSION was not updated"

for file in README.md ROADMAP.md TESTING.md; do
  grep -q '^\*\*Current release:\*\* v1.20.0-beta.1' "${fixture}/${file}" \
    || fail "${file} banner was not updated"
done

grep -qx 'VERSION="v1.20.0-beta.1"' "${fixture}/README.md" \
  || fail "README exact pin was not updated"

grep -qx '# ERPNext Developer Toolkit Release Manifest v1.20.0-beta.1' \
  "${fixture}/RELEASE-MANIFEST.txt" \
  || fail "manifest header was not updated"

first_heading="$(grep -m1 '^## ' "${fixture}/CHANGELOG.md")"
[[ "$first_heading" == "## v1.20.0-beta.1 - Release reliability foundation" ]] \
  || fail "beta changelog heading was not added at the top"

run_update \
  1.20.0-beta.1 \
  "Release reliability foundation" >/dev/null

heading_count="$(
  grep -c '^## v1\.20\.0-beta\.1 ' "${fixture}/CHANGELOG.md"
)"
[[ "$heading_count" == "1" ]] \
  || fail "metadata update was not idempotent"

if run_update invalid-version "Invalid" >/dev/null 2>&1; then
  fail "invalid version was accepted"
fi

echo "release metadata tests: all checks passed"
