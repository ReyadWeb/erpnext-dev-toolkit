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

pass() {
  echo "OK: $*"
}

work="$(mktemp -d /tmp/erpnext-dev-release-state-test.XXXXXX)"
trap 'rm -rf "$work"' EXIT

fixture="${work}/fixture"
mkdir -p \
  "${fixture}/scripts" \
  "${fixture}/.github/workflows" \
  "${fixture}/docs/security"

cp scripts/check-release-state-invariants.sh "${fixture}/scripts/"
chmod +x "${fixture}/scripts/check-release-state-invariants.sh"

write_compliant_fixture() {
  rm -f "${fixture}/BUILD-INFO.json"
  printf '%s\n' '1.20.1' >"${fixture}/VERSION"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "ERPNext Developer Toolkit v$(cat VERSION)"' >"${fixture}/erpnext-dev.sh"
  chmod +x "${fixture}/erpnext-dev.sh"

  cat >"${fixture}/scripts/release-version.sh" <<'EOF_RELEASE_HELPER'
#!/usr/bin/env bash
set -Eeuo pipefail

version="$(tr -d '[:space:]' <VERSION)"
expected_tag="v${version}"

case "${1:-read}" in
  read)
    printf '%s\n' "$version"
    ;;
  channel)
    printf '%s\n' "${ERPNEXT_RELEASE_CHANNEL:-development}"
    ;;
  tag)
    explicit="${ERPNEXT_RELEASE_TAG:-}"
    if [[ -n "$explicit" && "$explicit" != "$expected_tag" ]]; then
      exit 1
    fi
    printf '%s\n' "${explicit:-$expected_tag}"
    ;;
  *)
    exit 2
    ;;
esac
EOF_RELEASE_HELPER
  chmod +x "${fixture}/scripts/release-version.sh"

  cat >"${fixture}/scripts/build-info.sh" <<'EOF_BUILD_INFO'
#!/usr/bin/env bash
case "${1:-}" in
  assert-source-clean) [[ ! -e BUILD-INFO.json ]] ;;
  *) exit 0 ;;
esac
EOF_BUILD_INFO
  chmod +x "${fixture}/scripts/build-info.sh"

  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${fixture}/scripts/test-build-info.sh"
  chmod +x "${fixture}/scripts/test-build-info.sh"

  cat >"${fixture}/scripts/build-release-bundle.sh" <<'EOF_BUNDLE'
#!/usr/bin/env bash
scripts/build-info.sh generate
scripts/build-info.sh verify
EOF_BUNDLE
  chmod +x "${fixture}/scripts/build-release-bundle.sh"

  printf '%s\n' \
    '**Current release:** v1.20.0' \
    '**Current project version:** v1.20.1' \
    '| **Current focus** | v1.20.1 release-state, trust, and strict-validation foundation |' \
    >"${fixture}/README.md"

  printf '%s\n' \
    '# Roadmap' \
    '**Current project version:** v1.20.1' \
    '**Current work:** v1.20.1 — Release Coherence and Public Testing Foundation' \
    >"${fixture}/ROADMAP.md"

  printf '%s\n' '**Current project version:** v1.20.1' >"${fixture}/TESTING.md"
  printf '%s\n' '# Security' >"${fixture}/SECURITY.md"
  printf '%s\n' '# Release trust' >"${fixture}/docs/security/RELEASE-TRUST.md"

  cat >"${fixture}/scripts/validate-release.sh" <<'EOF_VALIDATE'
#!/usr/bin/env bash
if [[ "${RELEASE_STRICT:-0}" == "1" ]] && ! command -v shellcheck >/dev/null 2>&1; then
  echo "release-strict: shellcheck is required and missing" >&2
  exit 1
fi
EOF_VALIDATE
  chmod +x "${fixture}/scripts/validate-release.sh"

  cat >"${fixture}/.github/workflows/ci.yml" <<'EOF_CI'
name: CI
jobs:
  validate:
    steps:
      - run: scripts/release-version.sh tag
      - run: scripts/install-verified-ci-tool.sh shellcheck
EOF_CI
}

run_check() {
  ERPNEXT_RELEASE_ROOT="$fixture" \
    "${fixture}/scripts/check-release-state-invariants.sh" "$@"
}

write_compliant_fixture
run_check enforce >/dev/null || fail "compliant fixture was rejected"
pass "compliant release-state fixture"

write_compliant_fixture
printf '%s\n' '1.20.2-beta.1' >"${fixture}/VERSION"
sed -i \
  -e 's/Current project version:\*\* v1\.20\.1/Current project version:** v1.20.2-beta.1/' \
  -e 's/v1\.20\.1 release-state/v1.20.2 workflow-hardening/' \
  "${fixture}/README.md"
sed -i \
  -e 's/Current project version:\*\* v1\.20\.1/Current project version:** v1.20.2-beta.1/' \
  -e 's/Current work:\*\* v1\.20\.1/Current work:** v1.20.2/' \
  "${fixture}/ROADMAP.md"
sed -i \
  's/Current project version:\*\* v1\.20\.1/Current project version:** v1.20.2-beta.1/' \
  "${fixture}/TESTING.md"
run_check enforce >/dev/null \
  || fail "prerelease fixture with matching programme status was rejected"
pass "prerelease programme status derives from the canonical project version"

printf '%s\n' 'SCRIPT_VERSION="1.20.1"' >>"${fixture}/erpnext-dev.sh"
if run_check enforce >/dev/null 2>&1; then
  fail "duplicate runtime version literal was accepted"
fi
run_check audit >/dev/null || fail "audit mode failed while reporting a known gap"
pass "duplicate runtime version is detected"

write_compliant_fixture
printf '%s\n' '{}' >"${fixture}/BUILD-INFO.json"
if run_check release-state >/dev/null 2>&1; then
  fail "generated source BUILD-INFO.json was accepted"
fi
pass "generated source build metadata is detected"

write_compliant_fixture
printf '%s\n' '      - run: grep SCRIPT_VERSION erpnext-dev.sh' >>"${fixture}/.github/workflows/ci.yml"
if run_check enforce >/dev/null 2>&1; then
  fail "workflow version bypass was accepted"
fi
pass "workflow bypass is detected"

write_compliant_fixture
printf '%s\n' 'sudo ./erpnext-dev.sh verify-signature' >>"${fixture}/README.md"
if run_check enforce >/dev/null 2>&1; then
  fail "pre-sudo trust violation was accepted"
fi
pass "pre-sudo trust violation is detected"

write_compliant_fixture
cat >>"${fixture}/.github/workflows/ci.yml" <<'EOF_UNSAFE_MULTILINE_CI'
      - run: |
          curl -fsSL example.invalid/tool.tar.xz |
            sudo tar -xJ -C /usr/local/bin
EOF_UNSAFE_MULTILINE_CI
if run_check enforce >/dev/null 2>&1; then
  fail "multiline privileged CI download pipe was accepted"
fi
pass "multiline privileged CI download pipe is detected"

write_compliant_fixture
cat >"${fixture}/scripts/validate-release.sh" <<'EOF_WEAK_VALIDATE'
#!/usr/bin/env bash
if [[ "${RELEASE_STRICT:-0}" == "1" ]]; then
  echo "strict release validation enabled"
fi
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck script.sh
else
  echo "skipped shellcheck (not installed)"
fi
EOF_WEAK_VALIDATE
if run_check enforce >/dev/null 2>&1; then
  fail "realistic strict-mode skip weakness was accepted"
fi
pass "realistic strict-mode skip weakness is detected"

grep -Fq \
  'if [[ "${RELEASE_STRICT:-0}" == "1" && "$release_channel" != "development" ]]; then' \
  scripts/validate-release.sh \
  || fail "strict validation does not preserve the development changelog state"
pass "strict development validation preserves the Unreleased changelog"

grep -Fq 'scripts/test-release-context-isolation.sh' scripts/validate-release.sh \
  || fail "complete release validation does not run the context-isolation matrix"
grep -Fq 'ERPNEXT_RELEASE_TAG="$target_tag"' scripts/release-prepare-beta.sh \
  || fail "beta preparation does not inject the intended prerelease tag"
grep -Fq 'scripts/test-release-context-isolation.sh' scripts/release-prepare-beta.sh \
  || fail "beta preparation does not run the pre-tag-context dry-run"
pass "release qualification enforces hermetic fixture context isolation"

for workflow in .github/workflows/ci.yml .github/workflows/security.yml .github/workflows/security-analysis.yml; do
  grep -A2 -E '^[[:space:]]*pull_request:' "$workflow" \
    | grep -Eq "branches:.*release/\*\*" || fail "release-branch pull requests do not trigger ${workflow}"
done
pass "release-branch pull requests trigger required workflows"

write_compliant_fixture

(
  cd "$fixture"
  rm -rf .git
  git init -q
  git config user.name "Release Test"
  git config user.email "release-test@example.invalid"
  git add .
  git commit -qm "stable qualification fixture"
  git tag v1.20.1-rc.1
  git commit --allow-empty -qm "qualification head"
  git switch -qc release/v1.20.1
  git tag v1.20.1-beta.1
)

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  run_check release-state >/dev/null 2>&1; then
  fail "untagged stable context without a qualification phase was accepted"
fi
pass "untagged stable context requires an authorised qualification phase"

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-promotion \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-promotion without strict mode was accepted"
fi
pass "stable-promotion requires strict mode"

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.2 \
  ERPNEXT_RELEASE_PHASE=stable-promotion \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-promotion with a mismatched target tag was accepted"
fi
pass "stable qualification rejects a mismatched target tag"

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-promotion \
  ERPNEXT_RELEASE_SOURCE_TAG=v1.20.1-beta.2 \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-promotion accepted a missing source prerelease tag"
fi
pass "stable-promotion rejects a missing source prerelease tag"

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-promotion \
  ERPNEXT_RELEASE_SOURCE_TAG=v1.20.1-rc.1 \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-promotion accepted a source tag from another commit"
fi
pass "stable-promotion rejects a source tag from another commit"

(
  cd "$fixture"
  git switch -qc feature/wrong-stable-branch
)

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-promotion \
  ERPNEXT_RELEASE_SOURCE_TAG=v1.20.1-beta.1 \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-promotion accepted the wrong branch"
fi
pass "stable-promotion rejects the wrong branch"

(
  cd "$fixture"
  git switch -q release/v1.20.1
  git tag v1.20.1 HEAD^
)

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-promotion \
  ERPNEXT_RELEASE_SOURCE_TAG=v1.20.1-beta.1 \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-promotion accepted an existing target tag"
fi
pass "stable-promotion rejects an existing target tag"

(
  cd "$fixture"
  git tag -d v1.20.1 >/dev/null
)

ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-promotion \
  ERPNEXT_RELEASE_SOURCE_TAG=v1.20.1-beta.1 \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null \
  || fail "valid stable-promotion context was rejected"
pass "valid stable-promotion context is accepted"

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-pretag \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-pretag accepted a non-main branch"
fi
pass "stable-pretag rejects a non-main branch"

(
  cd "$fixture"
  git switch -qc main
  printf '%s\n' dirty >>README.md
)

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-pretag \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-pretag accepted a dirty working tree"
fi
pass "stable-pretag rejects a dirty working tree"

(
  cd "$fixture"
  git reset --hard -q HEAD
  git tag v1.20.1 HEAD^
)

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-pretag \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "stable-pretag accepted an existing target tag"
fi
pass "stable-pretag rejects an existing target tag"

(
  cd "$fixture"
  git tag -d v1.20.1 >/dev/null
)

ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=stable-pretag \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null \
  || fail "valid stable-pretag context was rejected"
pass "valid stable-pretag context is accepted"

if ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  ERPNEXT_RELEASE_PHASE=unknown-phase \
  RELEASE_STRICT=1 \
  run_check release-state >/dev/null 2>&1; then
  fail "unknown stable qualification phase was accepted"
fi
pass "unknown stable qualification phase is rejected"

(
  cd "$fixture"
  git tag v1.20.1
)

ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v1.20.1 \
  run_check release-state >/dev/null \
  || fail "exact stable tag on HEAD was rejected"
pass "exact stable tag is accepted without a qualification phase"

echo "release-state invariant tests: all checks passed"
