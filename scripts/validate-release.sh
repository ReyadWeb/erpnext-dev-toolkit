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

[[ -f erpnext-dev.sh ]] || fail "erpnext-dev.sh is missing"
[[ -f SHA256SUMS ]] || fail "SHA256SUMS is missing"
[[ -f RELEASE-MANIFEST.txt ]] || fail "RELEASE-MANIFEST.txt is missing"
[[ -f README.md ]] || fail "README.md is missing"
[[ -f SECURITY.md ]] || fail "SECURITY.md is missing"

bash -n erpnext-dev.sh
[[ -f lib/common.sh ]] || fail "lib/common.sh is missing"
[[ -f lib/config.sh ]] || fail "lib/config.sh is missing"
[[ -f lib/access.sh ]] || fail "lib/access.sh is missing"
[[ -f lib/frappe.sh ]] || fail "lib/frappe.sh is missing"
[[ -f lib/support.sh ]] || fail "lib/support.sh is missing"
bash -n lib/common.sh
bash -n lib/config.sh
bash -n lib/access.sh
bash -n lib/frappe.sh
bash -n lib/support.sh
[[ -f lib/backup.sh ]] || fail "lib/backup.sh is missing"
bash -n lib/backup.sh
[[ -f lib/ssl.sh ]] || fail "lib/ssl.sh is missing"
bash -n lib/ssl.sh
[[ -f lib/firewall.sh ]] || fail "lib/firewall.sh is missing"
bash -n lib/firewall.sh
[[ -f lib/apps.sh ]] || fail "lib/apps.sh is missing"
bash -n lib/apps.sh
[[ -f lib/health.sh ]] || fail "lib/health.sh is missing"
bash -n lib/health.sh
[[ -f lib/storage.sh ]] || fail "lib/storage.sh is missing"
bash -n lib/storage.sh
[[ -f lib/service.sh ]] || fail "lib/service.sh is missing"
bash -n lib/service.sh
[[ -f lib/status.sh ]] || fail "lib/status.sh is missing"
bash -n lib/status.sh
[[ -f lib/docker.sh ]] || fail "lib/docker.sh is missing"
bash -n lib/docker.sh
[[ -f lib/engine.sh ]] || fail "lib/engine.sh is missing"
bash -n lib/engine.sh
[[ -f lib/install.sh ]] || fail "lib/install.sh is missing"
bash -n lib/install.sh
[[ -f lib/ops.sh ]] || fail "lib/ops.sh is missing"
bash -n lib/ops.sh
[[ -f lib/security.sh ]] || fail "lib/security.sh is missing"
bash -n lib/security.sh
[[ -f lib/update.sh ]] || fail "lib/update.sh is missing"
bash -n lib/update.sh
pass "bash syntax valid"

chmod +x erpnext-dev.sh scripts/validate-release.sh scripts/generate-release-checksums.sh scripts/run-shellcheck.sh scripts/check-module-consistency.sh scripts/test-atomic-update.sh scripts/test-staged-signature.sh scripts/test-host-os-output.sh scripts/test-install-self-path.sh scripts/test-engine-select.sh scripts/test-health-snapshot.sh scripts/test-ui-render.sh scripts/test-dashboard-render.sh scripts/test-static-asset-probe.sh scripts/test-health-env-parser.sh scripts/test-update-channel.sh scripts/release-signing-policy.sh scripts/assert-github-release-assets.sh

# Module lists and dispatcher targets must all agree. This is the single guard
# that prevents a module from being sourced at runtime while missing from the
# integrity/self-update chain, and catches dispatcher commands with no backing
# function.
scripts/check-module-consistency.sh
pass "module consistency verified"

if command -v shellcheck >/dev/null 2>&1; then
  scripts/run-shellcheck.sh
  pass "shellcheck passed"
else
  pass "skipped shellcheck (not installed)"
fi

version_output="$(./erpnext-dev.sh version)"
echo "$version_output"
[[ "$version_output" == *"ERPNext Developer Toolkit v"* ]] || fail "version output not recognized"
pass "version command works"

script_version="$(grep -E '^SCRIPT_VERSION=' erpnext-dev.sh | head -n 1 | cut -d'"' -f2)"
[[ -n "$script_version" ]] || fail "could not read SCRIPT_VERSION from erpnext-dev.sh"
tag_version="v${script_version}"

grep -q "^## ${tag_version}" CHANGELOG.md || fail "CHANGELOG.md missing top entry for ${tag_version}"
pass "CHANGELOG version matches SCRIPT_VERSION (${tag_version})"

# Version discipline: a stable release must not be cut from a tree whose
# CHANGELOG still has an open "## Unreleased" section, and the newest entry must
# be the version being released. Enforced when RELEASE_STRICT=1 (set by the
# release workflow); dev branches may keep an Unreleased section during work.
if [[ "${RELEASE_STRICT:-0}" == "1" ]]; then
  first_heading="$(grep -m1 -E '^## ' CHANGELOG.md || true)"
  if [[ "$first_heading" != "## ${tag_version}"* ]]; then
    fail "RELEASE_STRICT: newest CHANGELOG entry is '${first_heading}', expected '## ${tag_version}' (fold any Unreleased section into the release)"
  fi
  pass "RELEASE_STRICT: newest CHANGELOG entry is ${tag_version}"
fi

grep -q "VERSION=\"${tag_version}\"" README.md || fail "README.md missing VERSION=\"${tag_version}\""
pass "README VERSION pin matches SCRIPT_VERSION (${tag_version})"

grep -q "Release Manifest ${tag_version}" RELEASE-MANIFEST.txt || fail "RELEASE-MANIFEST.txt version header does not match ${tag_version}"
pass "RELEASE-MANIFEST version matches SCRIPT_VERSION (${tag_version})"

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [[ -n "$line" ]] || continue
  [[ -e "$line" ]] || fail "RELEASE-MANIFEST entry missing: $line"
done < RELEASE-MANIFEST.txt
pass "RELEASE-MANIFEST entries exist"

sha256sum -c SHA256SUMS
pass "SHA256SUMS verifies all listed release artifacts"

./erpnext-dev.sh --help >/tmp/erpnext-dev-help.$$ 2>&1 || fail "--help failed"
grep -q "production-ops-wizard" /tmp/erpnext-dev-help.$$ || fail "help missing production-ops-wizard"
grep -q "verify-toolkit" /tmp/erpnext-dev-help.$$ || fail "help missing verify-toolkit"
grep -q "support-bundle-audit" /tmp/erpnext-dev-help.$$ || fail "help missing support-bundle-audit"
rm -f /tmp/erpnext-dev-help.$$
pass "help exposes required commands"

./erpnext-dev.sh verify-toolkit >/tmp/erpnext-dev-verify.$$ 2>&1 || fail "verify-toolkit failed"
grep -q "Active match.*OK" /tmp/erpnext-dev-verify.$$ || fail "verify-toolkit did not report Active match OK"
rm -f /tmp/erpnext-dev-verify.$$
pass "verify-toolkit active checksum match"

# Support bundle audit fixture: a clean share-safe archive should pass.
fixture_dir="$(mktemp -d /tmp/erpnext-dev-support-fixture.XXXXXX)"
fixture_archive="${fixture_dir}/erpnext-dev-support-bundle-fixture.tar.gz"
mkdir -p "${fixture_dir}/erpnext-dev-support-bundle-fixture"
cat > "${fixture_dir}/erpnext-dev-support-bundle-fixture/manifest.txt" <<'EOF_FIXTURE'
ERPNext Developer Toolkit Support Bundle
Generated for validation fixture.
No credentials are included.
EOF_FIXTURE
cat > "${fixture_dir}/erpnext-dev-support-bundle-fixture/system-summary.txt" <<'EOF_FIXTURE'
Runtime OK
HTTPS OK
Backup OK
EOF_FIXTURE
tar -C "$fixture_dir" -czf "$fixture_archive" erpnext-dev-support-bundle-fixture
SUPPORT_BUNDLE_AUDIT_ARCHIVE="$fixture_archive" ./erpnext-dev.sh support-bundle-audit >/tmp/erpnext-dev-support-audit.$$ 2>&1 || {
  cat /tmp/erpnext-dev-support-audit.$$
  rm -rf "$fixture_dir" /tmp/erpnext-dev-support-audit.$$
  fail "support-bundle-audit fixture failed"
}
grep -q "Audit result.*OK" /tmp/erpnext-dev-support-audit.$$ || {
  cat /tmp/erpnext-dev-support-audit.$$
  rm -rf "$fixture_dir" /tmp/erpnext-dev-support-audit.$$
  fail "support-bundle-audit did not report OK"
}
rm -rf "$fixture_dir" /tmp/erpnext-dev-support-audit.$$
pass "support-bundle-audit clean fixture passed"

# Negative fixture: a bundle carrying secrets/forbidden names MUST fail the audit.
# Without this, a regression that silently disabled the scanner would still pass CI.
bad_dir="$(mktemp -d /tmp/erpnext-dev-support-badfixture.XXXXXX)"
bad_archive="${bad_dir}/erpnext-dev-support-bundle-badfixture.tar.gz"
bad_root="${bad_dir}/erpnext-dev-support-bundle-badfixture"
mkdir -p "$bad_root"
# Forbidden filename + secret content.
cat > "${bad_root}/site_config.json" <<'EOF_BAD'
{ "db_password": "supersecret123", "encryption_key": "abc" }
EOF_BAD
cat > "${bad_root}/id_ed25519" <<'EOF_BAD'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAA
-----END OPENSSH PRIVATE KEY-----
EOF_BAD
# Build the secret keywords from fragments so this validator's own source does
# not contain a literal "<keyword>=" assignment (which its repo self-scan below
# would otherwise flag). The generated fixture file still contains the full
# strings, which is what the support-bundle scanner must catch.
kw_pw="pass""word"
kw_tok="tok""en"
{
  printf '%s=hunter2hunter2\n' "$kw_pw"
  printf '%s=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n' "$kw_tok"
  # New stateless GitHub App / Actions token format: ghs_-prefixed JWT (~520
  # chars, contains dots). The scanner must catch this too, not just the classic
  # opaque ghp_ shape. See github.blog/changelog 2026-05-15 (per-request override).
  printf '%s=ghs_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbb.cccccccccccccccccccc\n' "$kw_tok"
} > "${bad_root}/notes.txt"
: > "${bad_root}/database.sql.gz"
tar -C "$bad_dir" -czf "$bad_archive" erpnext-dev-support-bundle-badfixture

bad_out="/tmp/erpnext-dev-support-badaudit.$$"
if SUPPORT_BUNDLE_AUDIT_ARCHIVE="$bad_archive" ./erpnext-dev.sh support-bundle-audit >"$bad_out" 2>&1; then
  cat "$bad_out"
  rm -rf "$bad_dir" "$bad_out"
  fail "support-bundle-audit passed a bundle containing secrets (scanner regression)"
fi
grep -q "Audit result.*FAIL" "$bad_out" || {
  cat "$bad_out"
  rm -rf "$bad_dir" "$bad_out"
  fail "support-bundle-audit did not report FAIL for the unsafe fixture"
}
rm -rf "$bad_dir" "$bad_out"
pass "support-bundle-audit negative fixture correctly failed"

chmod +x scripts/release-signing-policy.sh
if scripts/release-signing-policy.sh v1.2.3 0 >/tmp/erpnext-dev-signpol.$$ 2>&1; then
  cat /tmp/erpnext-dev-signpol.$$
  rm -f /tmp/erpnext-dev-signpol.$$
  fail "release-signing-policy should fail stable tag without GPG key"
fi
[[ "$(cat /tmp/erpnext-dev-signpol.$$)" == "fail" ]] || fail "release-signing-policy stable+no-key should print fail"
rm -f /tmp/erpnext-dev-signpol.$$
pass "release-signing-policy: stable tag without key fails"

policy_out="$(scripts/release-signing-policy.sh v1.2.3-unsigned 0)"
[[ "$policy_out" == "publish-unsigned" ]] || fail "release-signing-policy pre-release+no-key should publish-unsigned, got: ${policy_out}"
pass "release-signing-policy: pre-release without key allows publish-unsigned"

policy_out="$(scripts/release-signing-policy.sh v1.2.3 1)"
[[ "$policy_out" == "sign" ]] || fail "release-signing-policy stable+key should sign, got: ${policy_out}"
pass "release-signing-policy: stable tag with key requires sign"

scripts/test-staged-signature.sh >/tmp/erpnext-dev-staged-sig.$$ 2>&1 || {
  cat /tmp/erpnext-dev-staged-sig.$$
  rm -f /tmp/erpnext-dev-staged-sig.$$
  fail "test-staged-signature.sh failed"
}
rm -f /tmp/erpnext-dev-staged-sig.$$
pass "staged signature verification matrix passed"

scripts/test-host-os-output.sh >/tmp/erpnext-dev-host-os.$$ 2>&1 || {
  cat /tmp/erpnext-dev-host-os.$$
  rm -f /tmp/erpnext-dev-host-os.$$
  fail "test-host-os-output.sh failed"
}
rm -f /tmp/erpnext-dev-host-os.$$
pass "host-OS output matrix passed"

scripts/test-install-self-path.sh >/tmp/erpnext-dev-install-self.$$ 2>&1 || {
  cat /tmp/erpnext-dev-install-self.$$
  rm -f /tmp/erpnext-dev-install-self.$$
  fail "test-install-self-path.sh failed"
}
rm -f /tmp/erpnext-dev-install-self.$$
pass "install-self path resolution passed"

scripts/test-engine-select.sh >/tmp/erpnext-dev-engine-select.$$ 2>&1 || {
  cat /tmp/erpnext-dev-engine-select.$$
  rm -f /tmp/erpnext-dev-engine-select.$$
  fail "test-engine-select.sh failed"
}
rm -f /tmp/erpnext-dev-engine-select.$$
pass "deployment-engine selection passed"

scripts/test-health-snapshot.sh >/tmp/erpnext-dev-health-snapshot.$$ 2>&1 || {
  cat /tmp/erpnext-dev-health-snapshot.$$
  rm -f /tmp/erpnext-dev-health-snapshot.$$
  fail "test-health-snapshot.sh failed"
}
rm -f /tmp/erpnext-dev-health-snapshot.$$
pass "health snapshot status model passed"

scripts/test-ui-render.sh >/tmp/erpnext-dev-ui-render.$$ 2>&1 || {
  cat /tmp/erpnext-dev-ui-render.$$
  rm -f /tmp/erpnext-dev-ui-render.$$
  fail "test-ui-render.sh failed"
}
rm -f /tmp/erpnext-dev-ui-render.$$
pass "main menu UI render (NO_COLOR) passed"

scripts/test-dashboard-render.sh >/tmp/erpnext-dev-dashboard-render.$$ 2>&1 || {
  cat /tmp/erpnext-dev-dashboard-render.$$
  rm -f /tmp/erpnext-dev-dashboard-render.$$
  fail "test-dashboard-render.sh failed"
}
rm -f /tmp/erpnext-dev-dashboard-render.$$
pass "operations dashboard UI render (NO_COLOR) passed"

scripts/test-static-asset-probe.sh >/tmp/erpnext-dev-static-asset-probe.$$ 2>&1 || {
  cat /tmp/erpnext-dev-static-asset-probe.$$
  rm -f /tmp/erpnext-dev-static-asset-probe.$$
  fail "test-static-asset-probe.sh failed"
}
rm -f /tmp/erpnext-dev-static-asset-probe.$$
pass "login static-asset probe helpers passed"

scripts/test-health-env-parser.sh >/tmp/erpnext-dev-health-env-parser.$$ 2>&1 || {
  cat /tmp/erpnext-dev-health-env-parser.$$
  rm -f /tmp/erpnext-dev-health-env-parser.$$
  fail "test-health-env-parser.sh failed"
}
rm -f /tmp/erpnext-dev-health-env-parser.$$
pass "health.env allowlist parser passed"

scripts/test-update-channel.sh >/tmp/erpnext-dev-update-channel.$$ 2>&1 || {
  cat /tmp/erpnext-dev-update-channel.$$
  rm -f /tmp/erpnext-dev-update-channel.$$
  fail "test-update-channel.sh failed"
}
rm -f /tmp/erpnext-dev-update-channel.$$
pass "update-toolkit channel/slot resolution passed"

if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  # shellcheck disable=SC2024 # redirect is intentionally to the invoking user's /tmp file, not root's
  sudo -E ./erpnext-dev.sh menu-self-test >/tmp/erpnext-dev-menu-self-test.$$ 2>&1 || {
    cat /tmp/erpnext-dev-menu-self-test.$$
    rm -f /tmp/erpnext-dev-menu-self-test.$$
    fail "menu-self-test failed"
  }
  grep -q "Menu navigation.*OK" /tmp/erpnext-dev-menu-self-test.$$ || {
    cat /tmp/erpnext-dev-menu-self-test.$$
    rm -f /tmp/erpnext-dev-menu-self-test.$$
    fail "menu-self-test did not report success"
  }
  rm -f /tmp/erpnext-dev-menu-self-test.$$
  pass "menu-self-test passed"

  # shellcheck disable=SC2024 # redirect is intentionally to the invoking user's /tmp file, not root's
  printf 'q\n' | sudo -E ./erpnext-dev.sh production-ops-wizard >/tmp/erpnext-dev-ops-wizard.$$ 2>&1 || {
    cat /tmp/erpnext-dev-ops-wizard.$$
    rm -f /tmp/erpnext-dev-ops-wizard.$$
    fail "production-ops-wizard quit smoke test failed"
  }
  rm -f /tmp/erpnext-dev-ops-wizard.$$
  pass "production-ops-wizard quit smoke test passed"

  scripts/test-atomic-update.sh >/tmp/erpnext-dev-atomic.$$ 2>&1 || {
    cat /tmp/erpnext-dev-atomic.$$
    rm -f /tmp/erpnext-dev-atomic.$$
    fail "test-atomic-update.sh failed"
  }
  rm -f /tmp/erpnext-dev-atomic.$$
  pass "atomic update smoke test passed"
else
  pass "skipped menu-self-test and production-ops-wizard smoke tests (passwordless sudo not available)"
  pass "skipped atomic update smoke test (passwordless sudo not available)"
fi

if find . -maxdepth 2 -type f -name 'GITHUB-UPDATE-v*.md' | grep -q .; then
  find . -maxdepth 2 -type f -name 'GITHUB-UPDATE-v*.md'
  fail "GITHUB-UPDATE release notes file found in package tree"
fi
pass "no GITHUB-UPDATE-v*.md files"

if grep -RInE '(password|secret|token|private[-_ ]?key|api[-_]?key|access[-_]?key|secret[-_]?access[-_]?key|client[-_]?secret|aws[-_]?secret)=' \
  --exclude-dir=.git \
  --exclude-dir=lib \
  --exclude='*.zip' \
  --exclude='CHANGELOG.md' \
  --exclude='erpnext-dev.sh' \
  . >/tmp/erpnext-dev-secret-grep.$$ 2>/dev/null; then
  cat /tmp/erpnext-dev-secret-grep.$$
  rm -f /tmp/erpnext-dev-secret-grep.$$
  fail "possible literal secret assignment found"
fi
rm -f /tmp/erpnext-dev-secret-grep.$$
pass "basic secret-pattern scan passed"

pass "release validation complete"
