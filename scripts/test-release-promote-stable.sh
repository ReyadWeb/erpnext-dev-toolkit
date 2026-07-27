#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d /tmp/erpnext-dev-promote-stable-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="${tmp_dir}/fixture"
mkdir -p "${fixture}/scripts"

cp scripts/release-version.sh "${fixture}/scripts/"
cp scripts/release-update-metadata.sh "${fixture}/scripts/"
cp scripts/release-promote-stable.sh "${fixture}/scripts/"

cat >"${fixture}/scripts/generate-release-checksums.sh" <<'EOF_GENERATE'
#!/usr/bin/env bash
printf 'fixture\n' >SHA256SUMS
EOF_GENERATE

for helper in \
  check-release-doc-alignment.sh \
  check-release-artifact-consistency.sh; do
  cat >"${fixture}/scripts/${helper}" <<'EOF_PASS'
#!/usr/bin/env bash
exit 0
EOF_PASS
done

cat >"${fixture}/scripts/validate-release.sh" <<'EOF_VALIDATE'
#!/usr/bin/env bash
exit "${FIXTURE_VALIDATE_EXIT:-0}"
EOF_VALIDATE

chmod +x "${fixture}/scripts/"*.sh

printf '%s\n' '1.20.0-beta.1' >"${fixture}/VERSION"
cat >"${fixture}/erpnext-dev.sh" <<'EOF_ENTRY'
#!/usr/bin/env bash
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  version) printf 'ERPNext Developer Toolkit v%s\n' "$(tr -d '[:space:]' <"${root}/VERSION")" ;;
  *) exit 2 ;;
esac
EOF_ENTRY
chmod +x "${fixture}/erpnext-dev.sh"
printf '%s\n' '**Current release:** v1.20.0-beta.1 · fixture' '**Current project version:** v1.20.0-beta.1' 'VERSION="v1.20.0-beta.1"' >"${fixture}/README.md"
printf '%s\n' '**Current release:** v1.20.0-beta.1 (fixture)' '**Current project version:** v1.20.0-beta.1' >"${fixture}/ROADMAP.md"
printf '%s\n' '**Current release:** v1.20.0-beta.1 · fixture' '**Current project version:** v1.20.0-beta.1' >"${fixture}/TESTING.md"
printf '%s\n' '## v1.20.0-beta.1 - Beta release' '' '- Beta.' >"${fixture}/CHANGELOG.md"
printf '%s\n' '# ERPNext Developer Toolkit Release Manifest v1.20.0-beta.1' 'VERSION' >"${fixture}/RELEASE-MANIFEST.txt"
printf '%s\n' 'fixture' >"${fixture}/SHA256SUMS"

(
  cd "$fixture"
  git init -q
  git config user.name "Release Test"
  git config user.email "release-test@example.invalid"
  git add .
  git commit -qm "beta fixture"
  git switch -qc wrong-branch
)

run_promote() {
  ERPNEXT_RELEASE_ROOT="$fixture" \
    "${fixture}/scripts/release-promote-stable.sh" "$@"
}

if run_promote 1.20.0 "Stable release" >/dev/null 2>&1; then
  fail "wrong branch was accepted"
fi

(
  cd "$fixture"
  git switch -qc release/v1.20.0
)

before_hash="$(
  cd "$fixture"
  sha256sum \
    VERSION \
    erpnext-dev.sh \
    README.md \
    ROADMAP.md \
    TESTING.md \
    CHANGELOG.md \
    RELEASE-MANIFEST.txt \
    SHA256SUMS
)"

if FIXTURE_VALIDATE_EXIT=1 run_promote \
  1.20.0 \
  "Stable release" >/dev/null 2>&1; then
  fail "validation failure was accepted"
fi

after_hash="$(
  cd "$fixture"
  sha256sum \
    VERSION \
    erpnext-dev.sh \
    README.md \
    ROADMAP.md \
    TESTING.md \
    CHANGELOG.md \
    RELEASE-MANIFEST.txt \
    SHA256SUMS
)"

[[ "$before_hash" == "$after_hash" ]] \
  || fail "failed stable promotion did not restore original files"

(
  cd "$fixture"
  git tag v1.20.0
)

if run_promote 1.20.0 "Stable release" >/dev/null 2>&1; then
  fail "existing stable tag was accepted"
fi

(
  cd "$fixture"
  git tag -d v1.20.0 >/dev/null
)

run_promote 1.20.0 "Stable release" >/dev/null

[[ "$(cat "${fixture}/VERSION")" == "1.20.0" ]] \
  || fail "stable promotion did not update VERSION"

[[ "$("${fixture}/erpnext-dev.sh" version)" == "ERPNext Developer Toolkit v1.20.0" ]] \
  || fail "stable promotion runtime did not derive VERSION"

first_heading="$(grep -m1 '^## ' "${fixture}/CHANGELOG.md")"
[[ "$first_heading" == "## v1.20.0 - Stable release" ]] \
  || fail "stable changelog entry is not first"

echo "stable promotion tests: all checks passed"
