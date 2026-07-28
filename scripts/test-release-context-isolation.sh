#!/usr/bin/env bash
# Prove that hermetic release fixtures are invariant under ambient qualification
# context injected by strict pre-tag validation.
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

work="$(mktemp -d /tmp/erpnext-dev-release-context-isolation.XXXXXX)"
trap 'rm -rf "$work"' EXIT

run_poisoned() {
  local label="$1" channel="$2" tag="$3" test_script="$4"
  local log
  log="${work}/$(basename "$test_script").${label}.log"
  shift 4

  if env \
    ERPNEXT_RELEASE_CHANNEL="$channel" \
    ERPNEXT_RELEASE_TAG="$tag" \
    ERPNEXT_RELEASE_PHASE=stable-promotion \
    ERPNEXT_RELEASE_SOURCE_TAG=v9.9.9-beta.1 \
    ERPNEXT_RELEASE_ROOT=/nonexistent/release-root \
    ERPNEXT_VERSION_FILE=/nonexistent/VERSION \
    ERPNEXT_ENTRYPOINT=/nonexistent/erpnext-dev.sh \
    ERPNEXT_BUILD_INFO_FILE=/nonexistent/BUILD-INFO.json \
    ERPNEXT_BUILD_INFO_HELPER=/nonexistent/build-info.sh \
    ERPNEXT_GIT_ROOT=/nonexistent/git-root \
    ERPNEXT_RELEASE_REMOTE_CHECK=1 \
    ERPNEXT_RELEASE_REMOTE_NAME=poison \
    ERPNEXT_TEST_RUNTIME_VERSION=9.9.9 \
    RELEASE_STRICT=1 \
    SKIP_SHELLCHECK=1 \
    SOURCE_DATE_EPOCH=1 \
    FIXTURE_VALIDATE_EXIT=99 \
    FIXTURE_CONTEXT_EXIT=99 \
    "$test_script" "$@" >"$log" 2>&1; then
    pass "$(basename "$test_script") is isolated from ${label} context"
  else
    cat "$log" >&2
    fail "$(basename "$test_script") changed under ${label} context"
  fi
}

isolated_tests=(
  scripts/test-build-info.sh
  scripts/test-legacy-modular-bootstrap.sh
  scripts/test-release-artifact-consistency.sh
  scripts/test-release-asset-trust.sh
  scripts/test-release-bootstrap-guidance.sh
  scripts/test-release-manifest.sh
  scripts/test-release-metadata.sh
  scripts/test-release-prepare-beta.sh
  scripts/test-release-pretag-check.sh
  scripts/test-release-promote-stable.sh
  scripts/test-release-state-invariants.sh
  scripts/test-release-version.sh
  scripts/test-repo-workflow-release.sh
  scripts/test-repo-workflow-release-transaction.sh
  scripts/test-repo-workflow-release-finalize.sh
)

for test_script in "${isolated_tests[@]}"; do
  grep -Fq 'release_test_env_reexec "$0" "$@"' "$test_script" \
    || fail "release test does not use canonical environment isolation: ${test_script}"
done
pass "all release fixtures use the canonical environment boundary"

contexts=(
  'development|development|v9.9.9-beta.1'
  'beta|beta|v9.9.9-beta.1'
  'rc|rc|v9.9.9-rc.1'
  'stable|stable|v9.9.9'
)

for context in "${contexts[@]}"; do
  IFS='|' read -r label channel tag <<<"$context"
  run_poisoned "$label" "$channel" "$tag" scripts/test-release-version.sh
  run_poisoned "$label" "$channel" "$tag" scripts/test-build-info.sh
done

# Exercise the two heavier end-to-end fixtures once under the exact ambient
# context that previously broke strict beta qualification.
run_poisoned beta beta v9.9.9-beta.1 scripts/test-release-pretag-check.sh
run_poisoned beta beta v9.9.9-beta.1 \
  scripts/test-legacy-modular-bootstrap.sh --identity-only

echo "release context isolation tests: all checks passed"
