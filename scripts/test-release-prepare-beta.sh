#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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

chmod +x "${fixture}/scripts/"*.sh

printf '%s\n' '1.19.22' >"${fixture}/VERSION"
printf '%s\n' '#!/usr/bin/env bash' 'SCRIPT_VERSION="1.19.22"' >"${fixture}/erpnext-dev.sh"
printf '%s\n' '**Current release:** v1.19.22 · fixture' 'VERSION="v1.19.22"' >"${fixture}/README.md"
printf '%s\n' '**Current release:** v1.19.22 (fixture)' >"${fixture}/ROADMAP.md"
printf '%s\n' '**Current release:** v1.19.22 · fixture' >"${fixture}/TESTING.md"
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
  git switch -qc feature/v1.20-release-reliability
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
