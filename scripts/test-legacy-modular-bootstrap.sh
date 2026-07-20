#!/usr/bin/env bash
# Hermetic regression test for the legacy single-file updater -> modular toolkit
# compatibility bridge. No network access is used.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v gpg >/dev/null 2>&1 || {
  echo "SKIP: gpg is required for legacy modular bootstrap test"
  exit 0
}
command -v curl >/dev/null 2>&1 || {
  echo "SKIP: curl is required for legacy modular bootstrap test"
  exit 0
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

version="$(grep -E '^SCRIPT_VERSION=' erpnext-dev.sh | head -n1 | cut -d'"' -f2)"
[[ -n "$version" ]] || fail "could not read SCRIPT_VERSION"
tag="v${version}"

work="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-dev-legacy-bootstrap-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

legacy_root="${work}/legacy"
release_root="${work}/release-server"
release_tree="${work}/erpnext-dev-${tag}"
release_download_dir="${release_root}/releases/download/${tag}"
gpg_home="${work}/gnupg"
mkdir -p "$legacy_root" "$release_tree/lib" "$release_tree/docs" "$release_download_dir" "$gpg_home"
chmod 700 "$gpg_home"

# Build a minimal-but-complete runtime release tree from the current checkout.
cp erpnext-dev.sh "$release_tree/erpnext-dev.sh"
cp -a lib/. "$release_tree/lib/"

cat >"${work}/gpg-batch" <<GPG
Key-Type: RSA
Key-Length: 2048
Name-Real: ERPNext Toolkit Bootstrap Test
Name-Email: bootstrap-test@example.invalid
Expire-Date: 0
%no-protection
%commit
GPG
GNUPGHOME="$gpg_home" gpg --batch --quiet --generate-key "${work}/gpg-batch"
fingerprint="$(GNUPGHOME="$gpg_home" gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ -n "$fingerprint" ]] || fail "could not determine test signing fingerprint"
GNUPGHOME="$gpg_home" gpg --batch --armor --export "$fingerprint" >"${release_tree}/docs/erpnext-dev-signing-key.asc"

(
  cd "$release_tree"
  {
    sha256sum erpnext-dev.sh
    find lib -maxdepth 1 -type f -name '*.sh' -print0 | sort -z | xargs -0 sha256sum
    sha256sum docs/erpnext-dev-signing-key.asc
  } >SHA256SUMS
  GNUPGHOME="$gpg_home" gpg --batch --yes --armor --detach-sign --local-user "$fingerprint" --output SHA256SUMS.asc SHA256SUMS
)

tar -C "$work" -czf "${release_download_dir}/erpnext-dev-${tag}.tar.gz" "erpnext-dev-${tag}"

# Reproduce the exact legacy failure: only the new modular entry script exists;
# lib/ was never installed by the old updater.
cp erpnext-dev.sh "${legacy_root}/erpnext-dev.sh"
chmod 755 "${legacy_root}/erpnext-dev.sh"

output="$(
  INSTALLER_CANONICAL_PATH="${legacy_root}/erpnext-dev.sh" \
    TOOLKIT_CLI_PATH="${legacy_root}/bin/erpnext-dev" \
    TOOLKIT_RELEASE_GITHUB="file://${release_root}" \
    TOOLKIT_BOOTSTRAP_SIGNING_FINGERPRINT="$fingerprint" \
    LOG_DIR="${legacy_root}/logs" \
    LOCK_DIR="${legacy_root}/locks" \
    "${legacy_root}/erpnext-dev.sh" version 2>&1
)" || {
  printf '%s\n' "$output" >&2
  fail "legacy modular bootstrap command failed"
}

printf '%s\n' "$output" | grep -q "ERPNext Developer Toolkit v${version}" \
  || fail "recovered toolkit did not execute the requested version command"
printf '%s\n' "$output" | grep -q "Recovered the complete signed ${tag} toolkit" \
  || fail "recovery success marker missing"

[[ -L "${legacy_root}/current" ]] || fail "current symlink was not created"
[[ "$(readlink "${legacy_root}/current")" == "releases/${tag}" ]] \
  || fail "current symlink does not point to releases/${tag}"
[[ -L "${legacy_root}/erpnext-dev.sh" ]] || fail "top-level entry was not converted to a symlink"
[[ -f "${legacy_root}/current/lib/common.sh" ]] || fail "recovered lib/common.sh is missing"
[[ -x "${legacy_root}/current/erpnext-dev.sh" ]] || fail "recovered entry is not executable"

# A second invocation must use the recovered tree directly and remain healthy.
second="$(
  INSTALLER_CANONICAL_PATH="${legacy_root}/erpnext-dev.sh" \
    TOOLKIT_CLI_PATH="${legacy_root}/bin/erpnext-dev" \
    LOG_DIR="${legacy_root}/logs" \
    LOCK_DIR="${legacy_root}/locks" \
    "${legacy_root}/erpnext-dev.sh" version 2>&1
)" || fail "second invocation after recovery failed"
printf '%s\n' "$second" | grep -q "ERPNext Developer Toolkit v${version}" \
  || fail "second invocation returned the wrong version"

printf 'OK: legacy single-file updater recovery migrated to atomic %s layout\n' "$tag"
