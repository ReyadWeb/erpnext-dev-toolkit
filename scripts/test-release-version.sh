#!/usr/bin/env bash
# Hermetic tests for scripts/release-version.sh.
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

work="$(mktemp -d /tmp/erpnext-dev-version-test.XXXXXX)"
trap 'rm -rf "$work"' EXIT
fixture="${work}/fixture"
mkdir -p "$fixture"
cp scripts/release-version.sh "${fixture}/release-version.sh"
chmod +x "${fixture}/release-version.sh"

write_entrypoint() {
  cat >"${fixture}/erpnext-dev.sh" <<'EOF_ENTRYPOINT'
#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version="$(tr -d '[:space:]' <"${root}/VERSION")"
version="${ERPNEXT_TEST_RUNTIME_VERSION:-${version}}"
case "${1:-}" in
  version) printf 'ERPNext Developer Toolkit v%s\n' "$version" ;;
  *) exit 2 ;;
esac
EOF_ENTRYPOINT
  chmod +x "${fixture}/erpnext-dev.sh"
}

run_helper() {
  ERPNEXT_RELEASE_ROOT="$fixture" \
    ERPNEXT_VERSION_FILE="${fixture}/VERSION" \
    ERPNEXT_ENTRYPOINT="${fixture}/erpnext-dev.sh" \
    ERPNEXT_GIT_ROOT="$fixture" \
    "${fixture}/release-version.sh" "$@"
}

printf '%s\n' '1.20.1' >"${fixture}/VERSION"
write_entrypoint
(
  cd "$fixture"
  git init -q
  git config user.name "Release Version Test"
  git config user.email "release-version@example.invalid"
  git add .
  git commit -qm "development fixture"
)

[[ "$(run_helper read)" == "1.20.1" ]] || fail "read did not return VERSION"
[[ "$(run_helper runtime)" == "1.20.1" ]] || fail "runtime did not return entrypoint output"
[[ "$(run_helper tag)" == "v1.20.1" ]] || fail "default tag was incorrect"
[[ "$(run_helper channel)" == "development" ]] || fail "untagged tree was not development"
run_helper assert-runtime >/dev/null
run_helper assert-tag v1.20.1 >/dev/null
run_helper assert-tag v1.20.1-beta.1 >/dev/null
[[ "$(run_helper channel-for-tag v1.20.1)" == "stable" ]] \
  || fail "stable target tag channel was not stable"
[[ "$(run_helper channel-for-tag v1.20.1-beta.1)" == "beta" ]] \
  || fail "beta target tag channel was not beta"
[[ "$(run_helper channel-for-tag v1.20.1-rc.2)" == "rc" ]] \
  || fail "RC target tag channel was not rc"

(
  cd "$fixture"
  git tag v1.20.1
)
[[ "$(run_helper channel)" == "stable" ]] || fail "exact stable tag was not stable"

(
  cd "$fixture"
  git tag -d v1.20.1 >/dev/null
  git tag v1.20.1-beta.1
)
[[ "$(run_helper tag)" == "v1.20.1-beta.1" ]] || fail "exact beta tag was not selected"
[[ "$(run_helper channel)" == "beta" ]] || fail "exact beta tag was not beta"
run_helper assert-tag v1.20.1-beta.1 >/dev/null

if run_helper assert-tag v1.20.2-beta.1 >/dev/null 2>&1; then
  fail "tag for a different project version was accepted"
fi

if ERPNEXT_TEST_RUNTIME_VERSION=1.20.1-beta.2 run_helper assert-runtime >/dev/null 2>&1; then
  fail "mismatched runtime output was accepted"
fi

[[ "$(ERPNEXT_RELEASE_CHANNEL=rc ERPNEXT_RELEASE_TAG=v1.20.1-rc.2 run_helper channel)" == "rc" ]] \
  || fail "explicit validated RC context failed"
if ERPNEXT_RELEASE_CHANNEL=stable ERPNEXT_RELEASE_TAG=v1.20.1-beta.1 run_helper channel >/dev/null 2>&1; then
  fail "mismatched explicit release context was accepted"
fi

printf '%s\n' 'not-a-version' >"${fixture}/VERSION"
if run_helper read >/dev/null 2>&1; then
  fail "invalid VERSION syntax was accepted"
fi

printf '%s\n\n%s\n' '1.20.1' '1.20.2' >"${fixture}/VERSION"
if run_helper read >/dev/null 2>&1; then
  fail "multiple VERSION values were accepted"
fi

echo "release version tests: all checks passed"
