#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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
case "${1:-read}" in
  read) cat VERSION ;;
  channel) echo development ;;
  tag) printf 'v%s\n' "$(cat VERSION)" ;;
  *) exit 2 ;;
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

echo "release-state invariant tests: all checks passed"
