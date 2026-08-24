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

tmp_dir="$(mktemp -d /tmp/erpnext-dev-release-metadata-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="${tmp_dir}/fixture"
mkdir -p "$fixture"

printf '%s\n' '1.19.22' >"${fixture}/VERSION"
cat >"${fixture}/erpnext-dev.sh" <<'EOF_ENTRY'
#!/usr/bin/env bash
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  version) printf 'ERPNext Developer Toolkit v%s\n' "$(tr -d '[:space:]' <"${root}/VERSION")" ;;
  *) exit 2 ;;
esac
EOF_ENTRY
chmod +x "${fixture}/erpnext-dev.sh"
printf '%s\n' '**Current release:** v1.19.22 · fixture' '**Current project version:** v1.19.22' '| **Current focus** | v1.19.22 stable release |' 'VERSION="v1.19.22"' >"${fixture}/README.md"
printf '%s\n' '**Current release:** v1.19.22 (fixture)' '**Current project version:** v1.19.22' '**Current work:** v1.19.22 stable release' >"${fixture}/ROADMAP.md"
printf '%s\n' '**Current release:** v1.19.22 · fixture' '**Current project version:** v1.19.22' >"${fixture}/TESTING.md"
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

[[ "$("${fixture}/erpnext-dev.sh" version)" == "ERPNext Developer Toolkit v1.20.0-beta.1" ]] \
  || fail "runtime did not derive the updated VERSION"

for file in README.md ROADMAP.md TESTING.md; do
  grep -q '^\*\*Current release:\*\* v1.19.22' "${fixture}/${file}" \
    || fail "${file} published release banner changed during beta preparation"
done

for file in README.md ROADMAP.md TESTING.md; do
  grep -q '^\*\*Current project version:\*\* v1.20.0-beta.1' "${fixture}/${file}" \
    || fail "${file} project version was not updated"
done

grep -qx 'VERSION="v1.19.22"' "${fixture}/README.md" \
  || fail "README stable exact pin changed during beta preparation"

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

run_update \
  1.20.0 \
  "Stable release" >/dev/null

[[ "$(cat "${fixture}/VERSION")" == "1.20.0" ]] \
  || fail "stable VERSION was not updated"

for file in README.md ROADMAP.md TESTING.md; do
  grep -q '^\*\*Current release:\*\* v1.20.0' "${fixture}/${file}" \
    || fail "${file} published release banner was not advanced for stable"
  grep -q '^\*\*Current project version:\*\* v1.20.0' "${fixture}/${file}" \
    || fail "${file} project version was not advanced for stable"
done

grep -qx 'VERSION="v1.20.0"' "${fixture}/README.md" \
  || fail "README exact pin was not advanced for stable"

grep -qx '# ERPNext Developer Toolkit Release Manifest v1.20.0' \
  "${fixture}/RELEASE-MANIFEST.txt" \
  || fail "stable manifest header was not updated"

first_heading="$(grep -m1 '^## ' "${fixture}/CHANGELOG.md")"
[[ "$first_heading" == "## v1.20.0 - Stable release" ]] \
  || fail "stable changelog heading was not added at the top"

if run_update invalid-version "Invalid" >/dev/null 2>&1; then
  fail "invalid version was accepted"
fi

echo "release metadata tests: all checks passed"
