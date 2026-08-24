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

tmp_dir="$(mktemp -d /tmp/erpnext-dev-prepare-beta-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="${tmp_dir}/fixture"
mkdir -p "${fixture}/scripts"

cp scripts/release-update-metadata.sh "${fixture}/scripts/"
cp scripts/release-prepare-beta.sh "${fixture}/scripts/"

cat >"${fixture}/scripts/generate-release-checksums.sh" <<'EOF_GENERATE'
#!/usr/bin/env bash
printf 'fixture\n' >SHA256SUMS
EOF_GENERATE

for script in \
  release-version.sh \
  check-release-doc-alignment.sh \
  check-release-artifact-consistency.sh; do
  cat >"${fixture}/scripts/${script}" <<'EOF_PASS'
#!/usr/bin/env bash
exit 0
EOF_PASS
done

cat >"${fixture}/scripts/validate-release.sh" <<'EOF_VALIDATE'
#!/usr/bin/env bash
exit "${FIXTURE_VALIDATE_EXIT:-0}"
EOF_VALIDATE

cat >"${fixture}/scripts/test-release-context-isolation.sh" <<'EOF_CONTEXT'
#!/usr/bin/env bash
set -Eeuo pipefail
version="$(tr -d '[:space:]' <VERSION)"
[[ "${ERPNEXT_RELEASE_CHANNEL:-}" == "beta" ]]
[[ "${ERPNEXT_RELEASE_TAG:-}" == "v${version}" ]]
[[ "${RELEASE_STRICT:-0}" == "1" ]]
exit "${FIXTURE_CONTEXT_EXIT:-0}"
EOF_CONTEXT

chmod +x "${fixture}/scripts/"*.sh

printf '%s\n' '1.19.22' >"${fixture}/VERSION"
printf '%s\n' '#!/usr/bin/env bash' '# runtime derives VERSION in the real tree' >"${fixture}/erpnext-dev.sh"
printf '%s\n' '**Current release:** v1.19.22 · fixture' '**Current project version:** v1.19.22' '| **Current focus** | v1.19.22 release baseline |' 'VERSION="v1.19.22"' >"${fixture}/README.md"
printf '%s\n' '**Current release:** v1.19.22 (fixture)' '**Current project version:** v1.19.22' '**Current work:** v1.19.22 release baseline' >"${fixture}/ROADMAP.md"
printf '%s\n' '**Current release:** v1.19.22 · fixture' '**Current project version:** v1.19.22' >"${fixture}/TESTING.md"
printf '%s\n' '## v1.19.22 - Previous release' '' '- Previous.' >"${fixture}/CHANGELOG.md"
printf '%s\n' '# ERPNext Developer Toolkit Release Manifest v1.19.22' 'VERSION' >"${fixture}/RELEASE-MANIFEST.txt"
printf '%s\n' 'fixture' >"${fixture}/SHA256SUMS"

(
  cd "$fixture"
  git init -q
  git config user.name "Release Test"
  git config user.email "release-test@example.invalid"
  git add .
  git commit -qm "fixture"
  git switch -qc release/v1.20.0
)

run_prepare() {
  ERPNEXT_RELEASE_ROOT="$fixture" \
    "${fixture}/scripts/release-prepare-beta.sh" "$@"
}

run_prepare \
  1.20.0-beta.1 \
  "Release reliability foundation" >/dev/null

[[ "$(cat "${fixture}/VERSION")" == "1.20.0-beta.1" ]] \
  || fail "beta preparation did not update VERSION"

for file in README.md ROADMAP.md TESTING.md; do
  grep -q '^\*\*Current release:\*\* v1.19.22' "${fixture}/${file}" \
    || fail "${file} published release banner changed during beta preparation"
  grep -q '^\*\*Current project version:\*\* v1.20.0-beta.1' \
    "${fixture}/${file}" \
    || fail "${file} beta project version was not updated"
done

grep -qx 'VERSION="v1.19.22"' "${fixture}/README.md" \
  || fail "README stable exact pin changed during beta preparation"
grep -Fqx '| **Current focus** | v1.20.0 beta qualification |' "${fixture}/README.md" \
  || fail "README beta focus marker was not updated"
grep -Fqx '**Current work:** v1.20.0 beta qualification' "${fixture}/ROADMAP.md" \
  || fail "ROADMAP beta work marker was not updated"

(
  cd "$fixture"
  git add .
  git commit -qm "prepared beta fixture"
)

printf '%s\n' 'dirty' >>"${fixture}/README.md"
if run_prepare \
  1.20.0-beta.2 \
  "Second beta" >/dev/null 2>&1; then
  fail "dirty working tree was accepted"
fi
(
  cd "$fixture"
  git reset --hard -q HEAD
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

if FIXTURE_CONTEXT_EXIT=1 run_prepare \
  1.20.0-beta.2 \
  "Second beta" >/dev/null 2>&1; then
  fail "prerelease test-context dry-run failure was accepted"
fi

context_hash="$(
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

[[ "$before_hash" == "$context_hash" ]] \
  || fail "failed test-context dry-run did not restore original files"

if FIXTURE_VALIDATE_EXIT=1 run_prepare \
  1.20.0-beta.2 \
  "Second beta" >/dev/null 2>&1; then
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
  || fail "failed beta preparation did not restore original files"

(
  cd "$fixture"
  git switch -qc wrong-branch
)

if run_prepare \
  1.20.0-beta.2 \
  "Second beta" >/dev/null 2>&1; then
  fail "wrong release branch was accepted"
fi

echo "release beta preparation tests: all checks passed"
