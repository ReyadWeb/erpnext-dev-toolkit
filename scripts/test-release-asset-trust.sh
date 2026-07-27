#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/release-test-env.sh
source "${ROOT}/scripts/release-test-env.sh"
release_test_env_reexec "$0" "$@"
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
work="$(mktemp -d /tmp/erpnext-dev-asset-trust.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root/dist" "$work/root/docs" "$work/root/scripts"
for f in SHA256SUMS erpnext-dev.sh RELEASE-MANIFEST.txt; do printf '%s\n' "$f" >"$work/root/$f"; done
printf 'key\n' >"$work/root/docs/erpnext-dev-signing-key.asc"
printf 'bootstrap\n' >"$work/root/scripts/bootstrap-verify.sh"
printf 'archive\n' >"$work/root/dist/erpnext-dev-v1.2.3.tar.gz"
printf '{}\n' >"$work/root/dist/erpnext-dev-v1.2.3.BUILD-INFO.json"
scripts/release-asset-inventory.sh generate --root "$work/root" --tag v1.2.3 --output "$work/inventory"
mkdir "$work/assets"
cp "$work/root/dist/"* "$work/assets/"
cp "$work/root/SHA256SUMS" "$work/root/erpnext-dev.sh" "$work/root/RELEASE-MANIFEST.txt" "$work/assets/"
cp "$work/root/docs/erpnext-dev-signing-key.asc" "$work/assets/"
cp "$work/root/scripts/bootstrap-verify.sh" "$work/assets/"
scripts/release-asset-inventory.sh verify --inventory "$work/inventory" --asset-dir "$work/assets" --require erpnext-dev-v1.2.3.tar.gz
printf 'tamper\n' >>"$work/assets/erpnext-dev-v1.2.3.tar.gz"
if scripts/release-asset-inventory.sh verify --inventory "$work/inventory" --asset-dir "$work/assets" >/dev/null 2>&1; then fail "tampered asset passed"; fi
bash -n scripts/bootstrap-verify.sh scripts/release-asset-inventory.sh
grep -Fq 'sudo ./erpnext-dev.sh local-dev-quickstart' scripts/bootstrap-verify.sh || fail "bootstrap lacks post-verification handoff"
! grep -Eq 'sudo[[:space:]]+\./erpnext-dev\.sh[[:space:]]+verify-signature' scripts/bootstrap-verify.sh || fail "bootstrap executes downloaded verifier under sudo"
echo "OK: release asset trust tests passed"
