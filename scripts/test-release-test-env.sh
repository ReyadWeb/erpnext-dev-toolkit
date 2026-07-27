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

helper="${ROOT_DIR}/scripts/release-test-env.sh"
[[ -x "$helper" ]] || fail "release-test-env helper is missing or not executable"

poisoned_variables=(
  ERPNEXT_RELEASE_CHANNEL
  ERPNEXT_RELEASE_TAG
  ERPNEXT_RELEASE_ROOT
  ERPNEXT_VERSION_FILE
  ERPNEXT_ENTRYPOINT
  ERPNEXT_BUILD_INFO_FILE
  ERPNEXT_BUILD_INFO_HELPER
  ERPNEXT_GIT_ROOT
  ERPNEXT_RELEASE_REMOTE_CHECK
  ERPNEXT_RELEASE_REMOTE_NAME
  ERPNEXT_RELEASE_MANIFEST
  ERPNEXT_RELEASE_CHECKSUMS
  ERPNEXT_RELEASE_MANIFEST_HELPER
  ERPNEXT_TEST_RUNTIME_VERSION
  RELEASE_STRICT
  SKIP_SHELLCHECK
  SOURCE_DATE_EPOCH
  FIXTURE_VALIDATE_EXIT
  FIXTURE_CONTEXT_EXIT
)

poison_args=(env)
for variable in "${poisoned_variables[@]}"; do
  poison_args+=("${variable}=poison")
done

"${poison_args[@]}" "$helper" clean bash -c '
  set -Eeuo pipefail
  for variable in "$@"; do
    [[ -z "${!variable+x}" ]] || {
      echo "variable remained set: ${variable}" >&2
      exit 1
    }
  done
' bash "${poisoned_variables[@]}" || fail "clean execution retained release-test variables"
pass "clean execution removes release-test variables"

"${poison_args[@]}" "$helper" clean env \
  ERPNEXT_RELEASE_CHANNEL=beta \
  ERPNEXT_RELEASE_TAG=v1.2.3-beta.1 \
  bash -c '
    [[ "$ERPNEXT_RELEASE_CHANNEL" == "beta" ]]
    [[ "$ERPNEXT_RELEASE_TAG" == "v1.2.3-beta.1" ]]
    [[ -z "${RELEASE_STRICT+x}" ]]
  ' || fail "explicit fixture context could not be added after isolation"
pass "explicit fixture context is added only after isolation"

work="$(mktemp -d /tmp/erpnext-dev-release-test-env.XXXXXX)"
trap 'rm -rf "$work"' EXIT
probe="${work}/probe.sh"
cat >"$probe" <<EOF_PROBE
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$ROOT_DIR"
# shellcheck source=scripts/release-test-env.sh
source "\${ROOT_DIR}/scripts/release-test-env.sh"
release_test_env_reexec "\$0" "\$@"
[[ "\${ERPNEXT_RELEASE_TEST_ISOLATED:-0}" == "1" ]]
[[ -z "\${ERPNEXT_RELEASE_CHANNEL+x}" ]]
[[ -z "\${ERPNEXT_RELEASE_TAG+x}" ]]
[[ -z "\${RELEASE_STRICT+x}" ]]
EOF_PROBE
chmod +x "$probe"

ERPNEXT_RELEASE_CHANNEL=stable \
  ERPNEXT_RELEASE_TAG=v9.9.9 \
  RELEASE_STRICT=1 \
  "$probe" || fail "test re-execution did not isolate inherited release context"
pass "test re-execution isolates inherited release context"

echo "release test environment tests: all checks passed"
