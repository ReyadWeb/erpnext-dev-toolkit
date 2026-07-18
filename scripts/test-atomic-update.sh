#!/usr/bin/env bash
# Hermetic smoke test for atomic self-update and rollback.
#
# Drives the real update-toolkit / toolkit-rollback code paths against a local
# file:// release server in a temp stable-root. Uses an ephemeral GPG test key
# so tag-channel updates exercise the v1.8.2 signature + fingerprint gate.
#
# Usage: sudo -E scripts/test-atomic-update.sh
# (or run without sudo if passwordless sudo is unavailable — the script will
#  invoke sudo -E itself when needed.)
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

# Same checksum targets as generate-release-checksums.sh (release tree only).
checksum_targets=(
  erpnext-dev.sh
  lib/common.sh lib/ui.sh lib/config.sh lib/access.sh lib/frappe.sh lib/support.sh
  lib/backup.sh lib/ssl.sh lib/firewall.sh lib/apps.sh lib/health.sh
  lib/storage.sh lib/service.sh lib/status.sh lib/docker.sh lib/engine.sh lib/install.sh lib/ops.sh
  lib/dashboard.sh lib/menu.sh lib/security.sh lib/update.sh
  scripts/validate-release.sh scripts/run-shellcheck.sh
  scripts/check-module-consistency.sh scripts/build-release-bundle.sh
  RELEASE-MANIFEST.txt
)

regenerate_checksums_in_tree() {
  local tree="$1"
  local tmp_file file
  tmp_file="$(mktemp "${tree}/SHA256SUMS.XXXXXX")"
  for file in "${checksum_targets[@]}"; do
    [[ -f "${tree}/${file}" ]] || fail "missing checksum target in synthetic tree: ${file}"
    (cd "$tree" && sha256sum "$file") >>"$tmp_file"
  done
  mv "$tmp_file" "${tree}/SHA256SUMS"
}

sign_checksums_in_tree() {
  local tree="$1"
  [[ -n "${TEST_GNUPG_HOME:-}" ]] || fail "test signing key not initialized"
  GNUPGHOME="$TEST_GNUPG_HOME" gpg --batch --yes --local-user "$TEST_SIGNER" \
    --detach-sign --armor --output "${tree}/SHA256SUMS.asc" "${tree}/SHA256SUMS"
}

build_synthetic_bundle() {
  local tag="$1"      # v9.9.8
  local srv_root="$2" # file server root
  local ver_num="${tag#v}"
  local stage bundle_dir bundle_path entry line

  stage="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-dev-bundle-stage.XXXXXX")"
  bundle_dir="${stage}/erpnext-dev-${tag}"
  mkdir -p "$bundle_dir/docs"

  while IFS= read -r line || [[ -n "$line" ]]; do
    entry="${line%%#*}"
    entry="$(printf '%s' "$entry" | tr -d '[:space:]')"
    [[ -n "$entry" ]] || continue
    [[ -e "${ROOT_DIR}/${entry}" ]] || fail "manifest entry missing for bundle build: ${entry}"
    mkdir -p "${bundle_dir}/$(dirname "$entry")"
    cp -a "${ROOT_DIR}/${entry}" "${bundle_dir}/${entry}"
  done <"${ROOT_DIR}/RELEASE-MANIFEST.txt"

  cp -a "$TEST_PUBKEY" "${bundle_dir}/docs/erpnext-dev-signing-key.asc"

  sed -i "s/^SCRIPT_VERSION=\"[^\"]*\"/SCRIPT_VERSION=\"${ver_num}\"/" "${bundle_dir}/erpnext-dev.sh"
  regenerate_checksums_in_tree "$bundle_dir"
  sign_checksums_in_tree "$bundle_dir"

  bundle_path="${srv_root}/releases/download/${tag}/erpnext-dev-${tag}.tar.gz"
  mkdir -p "$(dirname "$bundle_path")"
  tar -C "$stage" -czf "$bundle_path" "erpnext-dev-${tag}"
  rm -rf "$stage"
  printf '%s\n' "$bundle_path"
}

current_release() {
  local stable_root="$1"
  readlink -f "${stable_root}/current" 2>/dev/null | xargs -r basename 2>/dev/null || true
}

assert_current_is() {
  local stable_root="$1" expected="$2"
  local actual
  actual="$(current_release "$stable_root")"
  [[ "$actual" == "$expected" ]] || fail "expected current -> releases/${expected}, got '${actual:-<none>}'"
}

assert_version_at() {
  local script_path="$1" expected_ver="$2"
  local out
  out="$("$script_path" version 2>/dev/null || true)"
  [[ "$out" == *"${expected_ver}"* ]] || fail "expected version ${expected_ver} at ${script_path}, got: ${out}"
}

run_toolkit() {
  export TOOLKIT_INSTALL_DIR INSTALLER_CANONICAL_PATH TOOLKIT_CLI_PATH
  export TOOLKIT_RELEASE_GITHUB ASSUME_YES TOOLKIT_SIGNING_KEY_FINGERPRINT
  "${ROOT_DIR}/erpnext-dev.sh" "$@"
}

verify_at_current() {
  local stable_root="$1"
  export CHECKSUM_FILE="${stable_root}/current/SHA256SUMS"
  (cd "${stable_root}/current" && ./erpnext-dev.sh verify-toolkit)
}

setup_test_signing_key() {
  command -v gpg >/dev/null 2>&1 || fail "gpg is required for atomic update smoke tests"

  TEST_GNUPG_HOME="${work}/gnupg"
  mkdir -p "$TEST_GNUPG_HOME"
  chmod 700 "$TEST_GNUPG_HOME"

  cat >"${TEST_GNUPG_HOME}/batch.genkey" <<'EOF'
Key-Type: EDDSA
Key-Curve: Ed25519
Key-Usage: sign
Name-Real: ERPNext Dev Toolkit Test Signer
Name-Email: test-signer@erpnext-dev-toolkit.local
Expire-Date: 0
%no-protection
%commit
EOF

  GNUPGHOME="$TEST_GNUPG_HOME" gpg --batch --generate-key "${TEST_GNUPG_HOME}/batch.genkey" >/dev/null 2>&1 \
    || fail "could not generate ephemeral test signing key"

  TEST_SIGNER="test-signer@erpnext-dev-toolkit.local"
  TEST_PUBKEY="${work}/test-signing-key.asc"
  GNUPGHOME="$TEST_GNUPG_HOME" gpg --armor --export "$TEST_SIGNER" >"$TEST_PUBKEY"
  TEST_FINGERPRINT="$(GNUPGHOME="$TEST_GNUPG_HOME" gpg --with-colons --fingerprint "$TEST_SIGNER" \
    | awk -F: '/^fpr:/ { print $10; exit }')"
  [[ -n "$TEST_FINGERPRINT" ]] || fail "could not read test key fingerprint"
  export TOOLKIT_SIGNING_KEY_FINGERPRINT="$TEST_FINGERPRINT"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || fail "root or sudo required"
  exec sudo -E "$0" "$@"
fi

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

work="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-dev-atomic-test.XXXXXX")"
srv="${work}/fileserver"
stable="${work}/opt"
cli="${work}/bin/erpnext-dev"

export TOOLKIT_INSTALL_DIR="${stable}"
export INSTALLER_CANONICAL_PATH="${stable}/erpnext-dev.sh"
export TOOLKIT_CLI_PATH="${cli}"
export TOOLKIT_RELEASE_GITHUB="file://${srv}"
export ASSUME_YES=1

mkdir -p "${stable}" "${work}/bin"
chmod 755 "${work}/bin"

setup_test_signing_key

echo "== Building synthetic signed release bundles =="
build_synthetic_bundle "v9.9.8" "$srv" >/dev/null
build_synthetic_bundle "v9.9.9" "$srv" >/dev/null
pass "built signed v9.9.8 and v9.9.9 bundles on file://${srv}"

echo "== update-toolkit v9.9.8 =="
TOOLKIT_UPDATE_VERSION=v9.9.8 run_toolkit update-toolkit >/tmp/erpnext-dev-atomic-u1.$$ 2>&1 || {
  cat /tmp/erpnext-dev-atomic-u1.$$
  fail "update-toolkit v9.9.8 failed"
}
rm -f /tmp/erpnext-dev-atomic-u1.$$
assert_current_is "$stable" "v9.9.8"
assert_version_at "${stable}/current/erpnext-dev.sh" "9.9.8"
verify_at_current "$stable" >/tmp/erpnext-dev-atomic-v1.$$ 2>&1 || {
  cat /tmp/erpnext-dev-atomic-v1.$$
  fail "verify-toolkit failed after v9.9.8 update"
}
grep -q "Active match.*OK" /tmp/erpnext-dev-atomic-v1.$$ || fail "verify-toolkit did not report Active match OK after v9.9.8"
rm -f /tmp/erpnext-dev-atomic-v1.$$
pass "v9.9.8 installed; current symlink and verify-toolkit OK"

echo "== update-toolkit v9.9.9 =="
TOOLKIT_UPDATE_VERSION=v9.9.9 run_toolkit update-toolkit >/tmp/erpnext-dev-atomic-u2.$$ 2>&1 || {
  cat /tmp/erpnext-dev-atomic-u2.$$
  fail "update-toolkit v9.9.9 failed"
}
rm -f /tmp/erpnext-dev-atomic-u2.$$
assert_current_is "$stable" "v9.9.9"
assert_version_at "${stable}/current/erpnext-dev.sh" "9.9.9"
[[ "$(cat "${stable}/releases/.previous" 2>/dev/null || true)" == "v9.9.8" ]] \
  || fail "releases/.previous should record v9.9.8 after update to v9.9.9"
pass "v9.9.9 installed; .previous records v9.9.8"

echo "== toolkit-rollback =="
run_toolkit toolkit-rollback >/tmp/erpnext-dev-atomic-rb.$$ 2>&1 || {
  cat /tmp/erpnext-dev-atomic-rb.$$
  fail "toolkit-rollback failed"
}
rm -f /tmp/erpnext-dev-atomic-rb.$$
assert_current_is "$stable" "v9.9.8"
assert_version_at "${stable}/current/erpnext-dev.sh" "9.9.8"
verify_at_current "$stable" >/tmp/erpnext-dev-atomic-v2.$$ 2>&1 || {
  cat /tmp/erpnext-dev-atomic-v2.$$
  fail "verify-toolkit failed after rollback"
}
grep -q "Active match.*OK" /tmp/erpnext-dev-atomic-v2.$$ || fail "verify-toolkit did not report Active match OK after rollback"
rm -f /tmp/erpnext-dev-atomic-v2.$$
pass "rollback restored v9.9.8; verify-toolkit OK"

echo "== negative: corrupt v9.9.9 bundle must not half-apply =="
bundle_v999="${srv}/releases/download/v9.9.9/erpnext-dev-v9.9.9.tar.gz"
work_extract="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-dev-corrupt.XXXXXX")"
tar -C "$work_extract" -xzf "$bundle_v999"
# Tamper a file but leave SHA256SUMS + signature unchanged — checksum gate must fail.
printf '\n# tamper-fixture\n' >>"${work_extract}/erpnext-dev-v9.9.9/lib/common.sh"
tar -C "$work_extract" -czf "$bundle_v999" "erpnext-dev-v9.9.9"
rm -rf "$work_extract"

if TOOLKIT_UPDATE_VERSION=v9.9.9 run_toolkit update-toolkit >/tmp/erpnext-dev-atomic-bad.$$ 2>&1; then
  cat /tmp/erpnext-dev-atomic-bad.$$
  fail "update-toolkit should have failed on corrupted v9.9.9 bundle"
fi
rm -f /tmp/erpnext-dev-atomic-bad.$$
assert_current_is "$stable" "v9.9.8"
pass "corrupt update rejected; current still v9.9.8"

echo "== negative: unsigned v9.9.9 bundle must not apply =="
bundle_v999="${srv}/releases/download/v9.9.9/erpnext-dev-v9.9.9.tar.gz"
work_extract="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-dev-unsigned.XXXXXX")"
tar -C "$work_extract" -xzf "$bundle_v999"
rm -f "${work_extract}/erpnext-dev-v9.9.9/SHA256SUMS.asc"
tar -C "$work_extract" -czf "$bundle_v999" "erpnext-dev-v9.9.9"
rm -rf "$work_extract"

if TOOLKIT_UPDATE_VERSION=v9.9.9 run_toolkit update-toolkit >/tmp/erpnext-dev-atomic-unsigned.$$ 2>&1; then
  cat /tmp/erpnext-dev-atomic-unsigned.$$
  fail "update-toolkit should have failed on unsigned v9.9.9 bundle"
fi
rm -f /tmp/erpnext-dev-atomic-unsigned.$$
assert_current_is "$stable" "v9.9.8"
pass "unsigned update rejected; current still v9.9.8"

rm -rf "$work"
pass "atomic update smoke test complete"
