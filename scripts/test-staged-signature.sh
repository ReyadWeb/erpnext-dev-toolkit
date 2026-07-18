#!/usr/bin/env bash
# Unit-style tests for toolkit_verify_staged_signature (v1.8.2 hardening).
# Hermetic: ephemeral Ed25519 test key, no network, no sudo.
#
# Usage: scripts/test-staged-signature.sh
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

command -v gpg >/dev/null 2>&1 || fail "gpg is required for staged-signature tests"

work="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-dev-staged-sig.XXXXXX")"
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

export ERPNEXT_DEV_ENTRY_SCRIPT="${ROOT_DIR}/erpnext-dev.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"
erpnext_dev_init_terminal_colors
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/security.sh"

build_signed_tree() {
  local tree="$1"
  mkdir -p "${tree}/docs"
  printf 'fixture-checksum-content\n' >"${tree}/SHA256SUMS"
  cp -a "$TEST_PUBKEY" "${tree}/docs/erpnext-dev-signing-key.asc"
  GNUPGHOME="$TEST_GNUPG_HOME" gpg --batch --yes --local-user "$TEST_SIGNER" \
    --detach-sign --armor --output "${tree}/SHA256SUMS.asc" "${tree}/SHA256SUMS"
}

expect_staged_pass() {
  local label="$1" tree="$2"
  TOOLKIT_SIGNING_KEY_FINGERPRINT="$TEST_FINGERPRINT" \
    toolkit_verify_staged_signature "$tree" >/dev/null 2>&1 \
    || fail "${label}: expected PASS"
  pass "${label}: PASS"
}

expect_staged_fail() {
  local label="$1" tree="$2"
  if TOOLKIT_SIGNING_KEY_FINGERPRINT="$TEST_FINGERPRINT" \
    toolkit_verify_staged_signature "$tree" >/dev/null 2>&1; then
    fail "${label}: expected FAIL"
  fi
  pass "${label}: FAIL (expected)"
}

good_tree="${work}/good"
build_signed_tree "$good_tree"
expect_staged_pass "valid signed bundle" "$good_tree"

no_sig_tree="${work}/no-sig"
build_signed_tree "$no_sig_tree"
rm -f "${no_sig_tree}/SHA256SUMS.asc"
expect_staged_fail "missing SHA256SUMS.asc" "$no_sig_tree"

no_pubkey_tree="${work}/no-pubkey"
build_signed_tree "$no_pubkey_tree"
rm -f "${no_pubkey_tree}/docs/erpnext-dev-signing-key.asc"
expect_staged_fail "missing bundled public key" "$no_pubkey_tree"

tampered_tree="${work}/tampered"
build_signed_tree "$tampered_tree"
printf 'tampered\n' >>"${tampered_tree}/SHA256SUMS"
expect_staged_fail "tampered SHA256SUMS" "$tampered_tree"

wrong_fp_tree="${work}/wrong-fp"
build_signed_tree "$wrong_fp_tree"
if (
  unset TOOLKIT_SIGNING_KEY_FINGERPRINT
  toolkit_verify_staged_signature "$wrong_fp_tree" >/dev/null 2>&1
); then
  fail "valid signature with wrong pinned fingerprint: expected FAIL"
fi
pass "valid signature, wrong pinned fingerprint: FAIL (expected)"

wrong_key_tree="${work}/wrong-key"
build_signed_tree "$wrong_key_tree"
cp -a "${ROOT_DIR}/docs/erpnext-dev-signing-key.asc" "${wrong_key_tree}/docs/erpnext-dev-signing-key.asc"
expect_staged_fail "valid signature against mismatched bundled pubkey" "$wrong_key_tree"

no_gpg_tree="${work}/no-gpg"
build_signed_tree "$no_gpg_tree"
fakebin="${work}/fakebin"
mkdir -p "$fakebin"
for cmd in awk grep printf mktemp rm tr; do
  ln -sf "$(command -v "$cmd")" "${fakebin}/${cmd}"
done
if PATH="$fakebin" TOOLKIT_SIGNING_KEY_FINGERPRINT="$TEST_FINGERPRINT" \
  toolkit_verify_staged_signature "$no_gpg_tree" >/dev/null 2>&1; then
  fail "missing gpg in PATH: expected FAIL"
fi
pass "missing gpg: FAIL (expected)"

rm -rf "$work"
pass "staged signature verification matrix complete"
