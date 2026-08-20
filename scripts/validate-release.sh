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
[[ -f VERSION ]] || fail "VERSION is missing"
[[ -x scripts/release-version.sh ]] \
  || fail "scripts/release-version.sh is missing or not executable"
[[ -x scripts/test-release-version.sh ]] \
  || fail "scripts/test-release-version.sh is missing or not executable"
[[ -x scripts/build-info.sh ]] \
  || fail "scripts/build-info.sh is missing or not executable"
[[ -x scripts/test-build-info.sh ]] \
  || fail "scripts/test-build-info.sh is missing or not executable"
[[ -x scripts/release-test-env.sh ]] \
  || fail "scripts/release-test-env.sh is missing or not executable"
[[ -x scripts/test-release-test-env.sh ]] \
  || fail "scripts/test-release-test-env.sh is missing or not executable"
[[ -x scripts/test-release-context-isolation.sh ]] \
  || fail "scripts/test-release-context-isolation.sh is missing or not executable"
[[ -x scripts/release-manifest-files.sh ]] \
  || fail "scripts/release-manifest-files.sh is missing or not executable"
[[ -x scripts/check-release-artifact-consistency.sh ]] \
  || fail "scripts/check-release-artifact-consistency.sh is missing or not executable"
[[ -x scripts/test-release-manifest.sh ]] \
  || fail "scripts/test-release-manifest.sh is missing or not executable"
[[ -x scripts/test-release-artifact-consistency.sh ]] \
  || fail "scripts/test-release-artifact-consistency.sh is missing or not executable"
[[ -f SHA256SUMS ]] || fail "SHA256SUMS is missing"
[[ -f RELEASE-MANIFEST.txt ]] || fail "RELEASE-MANIFEST.txt is missing"
[[ -f README.md ]] || fail "README.md is missing"
[[ -f SECURITY.md ]] || fail "SECURITY.md is missing"
[[ -x scripts/test-installation-profile-contract.sh ]] \
  || fail "scripts/test-installation-profile-contract.sh is missing or not executable"

[[ -x scripts/release-update-metadata.sh ]] \
  || fail "scripts/release-update-metadata.sh is missing or not executable"
[[ -x scripts/release-prepare-beta.sh ]] \
  || fail "scripts/release-prepare-beta.sh is missing or not executable"
[[ -x scripts/test-release-metadata.sh ]] \
  || fail "scripts/test-release-metadata.sh is missing or not executable"
[[ -x scripts/test-release-prepare-beta.sh ]] \
  || fail "scripts/test-release-prepare-beta.sh is missing or not executable"

[[ -x scripts/release-promote-stable.sh ]] \
  || fail "scripts/release-promote-stable.sh is missing or not executable"
[[ -x scripts/release-pretag-check.sh ]] \
  || fail "scripts/release-pretag-check.sh is missing or not executable"
[[ -x scripts/test-release-promote-stable.sh ]] \
  || fail "scripts/test-release-promote-stable.sh is missing or not executable"
[[ -x scripts/test-release-pretag-check.sh ]] \
  || fail "scripts/test-release-pretag-check.sh is missing or not executable"
[[ -x scripts/test-release-bootstrap-guidance.sh ]] \
  || fail "scripts/test-release-bootstrap-guidance.sh is missing or not executable"
[[ -x scripts/release-asset-inventory.sh ]] \
  || fail "scripts/release-asset-inventory.sh is missing or not executable"
[[ -x scripts/bootstrap-verify.sh ]] \
  || fail "scripts/bootstrap-verify.sh is missing or not executable"
[[ -x scripts/test-release-asset-trust.sh ]] \
  || fail "scripts/test-release-asset-trust.sh is missing or not executable"
[[ -x scripts/repo-workflow.sh ]] \
  || fail "scripts/repo-workflow.sh is missing or not executable"
[[ -x scripts/test-repo-workflow.sh ]] \
  || fail "scripts/test-repo-workflow.sh is missing or not executable"
[[ -x scripts/test-repo-workflow-work.sh ]] \
  || fail "scripts/test-repo-workflow-work.sh is missing or not executable"
[[ -x scripts/test-repo-workflow-pr.sh ]] \
  || fail "scripts/test-repo-workflow-pr.sh is missing or not executable"
[[ -x scripts/test-repo-workflow-release.sh ]] \
  || fail "scripts/test-repo-workflow-release.sh is missing or not executable"
[[ -x scripts/test-repo-workflow-release-transaction.sh ]] \
  || fail "scripts/test-repo-workflow-release-transaction.sh is missing or not executable"
[[ -x scripts/test-repo-workflow-release-finalize.sh ]] \
  || fail "scripts/test-repo-workflow-release-finalize.sh is missing or not executable"
[[ -x scripts/test-repo-workflow-release-run.sh ]] \
  || fail "scripts/test-repo-workflow-release-run.sh is missing or not executable"

[[ -x scripts/test-release-state-invariants.sh ]] \
  || fail "scripts/test-release-state-invariants.sh is missing or not executable"

[[ -x scripts/check-release-state-invariants.sh ]] \
  || fail "scripts/check-release-state-invariants.sh is missing or not executable"

bash -n erpnext-dev.sh
bash -n scripts/release-version.sh
bash -n scripts/test-release-version.sh
bash -n scripts/build-info.sh
bash -n scripts/test-build-info.sh
bash -n scripts/release-test-env.sh
bash -n scripts/test-release-test-env.sh
bash -n scripts/test-release-context-isolation.sh
bash -n scripts/check-release-state-invariants.sh
bash -n scripts/test-release-state-invariants.sh
bash -n scripts/release-manifest-files.sh
bash -n scripts/check-release-artifact-consistency.sh
bash -n scripts/test-release-manifest.sh
bash -n scripts/test-release-artifact-consistency.sh
[[ -f lib/common.sh ]] || fail "lib/common.sh is missing"
[[ -f lib/config.sh ]] || fail "lib/config.sh is missing"
[[ -f lib/access.sh ]] || fail "lib/access.sh is missing"
[[ -f lib/local_ip.sh ]] || fail "lib/local_ip.sh is missing"
[[ -f lib/frappe.sh ]] || fail "lib/frappe.sh is missing"
[[ -f lib/support.sh ]] || fail "lib/support.sh is missing"
bash -n lib/common.sh
bash -n lib/config.sh
bash -n lib/access.sh
bash -n lib/local_ip.sh
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
[[ -f lib/dashboard.sh ]] || fail "lib/dashboard.sh is missing"
bash -n lib/dashboard.sh
[[ -f lib/operations_api.sh ]] || fail "lib/operations_api.sh is missing"
bash -n lib/operations_api.sh
[[ -f lib/healing.sh ]] || fail "lib/healing.sh is missing"
bash -n lib/healing.sh
[[ -f lib/security.sh ]] || fail "lib/security.sh is missing"
bash -n lib/security.sh
[[ -f lib/update.sh ]] || fail "lib/update.sh is missing"
bash -n lib/update.sh
bash -n scripts/release-update-metadata.sh
bash -n scripts/release-prepare-beta.sh
bash -n scripts/test-release-metadata.sh
bash -n scripts/test-release-prepare-beta.sh
bash -n scripts/release-promote-stable.sh
bash -n scripts/release-pretag-check.sh
bash -n scripts/test-release-promote-stable.sh
bash -n scripts/test-release-pretag-check.sh
bash -n scripts/test-release-bootstrap-guidance.sh
bash -n scripts/release-asset-inventory.sh
bash -n scripts/bootstrap-verify.sh
bash -n scripts/test-release-asset-trust.sh
bash -n scripts/repo-workflow.sh
bash -n scripts/test-repo-workflow.sh
bash -n scripts/test-repo-workflow-work.sh
bash -n scripts/test-repo-workflow-pr.sh
bash -n scripts/test-repo-workflow-release.sh
bash -n scripts/test-repo-workflow-release-transaction.sh
bash -n scripts/test-repo-workflow-release-finalize.sh
bash -n scripts/test-repo-workflow-release-run.sh
pass "bash syntax valid"

scripts/release-version.sh assert-runtime
pass "VERSION matches runtime output"

scripts/test-release-version.sh
pass "canonical release version tests passed"

scripts/build-info.sh assert-source-clean >/dev/null
pass "source tree contains no generated build metadata"

scripts/test-build-info.sh
pass "immutable build identity tests passed"

scripts/test-release-test-env.sh
pass "release test environment helper tests passed"

scripts/test-release-context-isolation.sh
pass "release fixture context-isolation matrix passed"

scripts/test-release-state-invariants.sh
pass "release-state invariant detector tests passed"

scripts/check-release-state-invariants.sh release-state
pass "release-state invariants enforced"

scripts/test-release-manifest.sh
pass "release manifest parser tests passed"

scripts/test-release-artifact-consistency.sh
pass "release artifact consistency tests passed"

chmod +x erpnext-dev.sh scripts/validate-release.sh scripts/generate-release-checksums.sh scripts/run-shellcheck.sh scripts/check-module-consistency.sh scripts/check-pinned-actions.sh scripts/check-shfmt.sh scripts/check-release-doc-alignment.sh scripts/resolve-latest-release-tag.sh scripts/test-atomic-update.sh scripts/test-staged-signature.sh scripts/test-host-os-output.sh scripts/test-install-self-path.sh scripts/test-engine-select.sh scripts/test-platform-profiles.sh scripts/test-inventory-compatibility.sh scripts/test-docker-access-routing.sh scripts/test-docker-reliability.sh scripts/test-health-snapshot.sh scripts/test-ui-render.sh scripts/test-dashboard-render.sh scripts/test-static-asset-probe.sh scripts/test-reinstall-isolation.sh scripts/test-asset-build-isolation.sh scripts/frappe-frontend-asset-checklist.sh scripts/test-health-env-parser.sh scripts/test-offvm-host-key.sh scripts/test-risky-shell-patterns.sh scripts/test-adversarial-inputs.sh scripts/test-restore-input.sh scripts/test-update-channel.sh scripts/test-resolve-latest-release-tag.sh scripts/test-local-ip.sh scripts/test-healing.sh scripts/release-signing-policy.sh scripts/assert-github-release-assets.sh scripts/release-update-metadata.sh scripts/test-release-metadata.sh scripts/release-prepare-beta.sh scripts/test-release-prepare-beta.sh scripts/release-promote-stable.sh scripts/release-pretag-check.sh scripts/test-release-promote-stable.sh scripts/test-release-pretag-check.sh scripts/check-release-state-invariants.sh scripts/test-release-state-invariants.sh scripts/build-info.sh scripts/test-build-info.sh scripts/release-test-env.sh scripts/test-release-test-env.sh scripts/test-release-context-isolation.sh
chmod +x scripts/test-installation-profile-contract.sh

chmod +x \
  scripts/release-manifest-files.sh \
  scripts/check-release-artifact-consistency.sh \
  scripts/test-release-manifest.sh \
  scripts/test-release-artifact-consistency.sh \
  scripts/test-release-bootstrap-guidance.sh \
  scripts/release-asset-inventory.sh \
  scripts/bootstrap-verify.sh \
  scripts/test-release-asset-trust.sh
chmod +x scripts/repo-workflow.sh scripts/test-repo-workflow.sh scripts/test-repo-workflow-work.sh scripts/test-repo-workflow-pr.sh scripts/test-repo-workflow-release.sh scripts/test-repo-workflow-release-transaction.sh scripts/test-repo-workflow-release-finalize.sh scripts/test-repo-workflow-release-run.sh

scripts/test-release-metadata.sh
pass "release metadata update tests passed"

scripts/test-release-prepare-beta.sh
pass "beta preparation transaction tests passed"

scripts/test-release-promote-stable.sh
pass "stable promotion transaction tests passed"

scripts/test-release-pretag-check.sh
pass "pre-tag repository gate tests passed"

scripts/test-release-bootstrap-guidance.sh
pass "signed release bootstrap guidance tests passed"

scripts/test-release-asset-trust.sh
pass "pre-privilege release asset trust tests passed"

scripts/test-repo-workflow.sh
pass "repository workflow transaction tests passed"
scripts/test-repo-workflow-pr.sh
pass "repository pull request workflow tests passed"
scripts/test-repo-workflow-release.sh
pass "repository release-status workflow tests passed"
scripts/test-repo-workflow-release-transaction.sh
pass "repository release transaction workflow tests passed"
scripts/test-repo-workflow-release-finalize.sh
pass "repository release finalization workflow tests passed"
scripts/test-repo-workflow-release-run.sh
pass "repository resumable release workflow tests passed"

# Module lists and dispatcher targets must all agree. This is the single guard
# that prevents a module from being sourced at runtime while missing from the
# integrity/self-update chain, and catches dispatcher commands with no backing
# function.
scripts/check-module-consistency.sh
pass "module consistency verified"

scripts/test-platform-profiles.sh
pass "platform/profile selection tests passed"

scripts/test-installation-profile-contract.sh
pass "installation-profile contract and read-only planning tests passed"

scripts/test-interactive-installation-profiles.sh
pass "interactive installation-profile tests passed"

scripts/test-frappe-platform-lifecycle.sh
pass "Frappe platform lifecycle tests passed"

scripts/test-inventory-compatibility.sh
pass "inventory/compatibility tests passed"

scripts/test-operation-planner.sh
pass "operation planner tests passed"

scripts/test-json-api-contract.sh
pass "stable JSON API contract tests passed"

scripts/test-deployment-info-api.sh
pass "deployment-info API contract tests passed"

scripts/test-operations-api.sh
pass "operations API contract and security tests passed"

scripts/test-docker-durability.sh
pass "Docker durability tests passed"

scripts/test-safe-update-lifecycle.sh
pass "safe-update lifecycle tests passed"
scripts/test-app-uninstall-recovery.sh
pass "app-uninstall recovery tests passed"

if [[ "${SKIP_SHELLCHECK:-0}" == "1" ]]; then
  command -v shellcheck >/dev/null 2>&1 \
    || fail "SKIP_SHELLCHECK=1 requires shellcheck to be installed"
  pass "shellcheck already completed by the calling strict workflow"
elif command -v shellcheck >/dev/null 2>&1; then
  scripts/run-shellcheck.sh
  pass "shellcheck passed"
else
  [[ "${RELEASE_STRICT:-0}" != "1" ]] \
    || fail "RELEASE_STRICT: shellcheck is required and may not be skipped"
  pass "skipped shellcheck in contributor mode (not installed)"
fi

version_output="$(./erpnext-dev.sh version)"
echo "$version_output"
[[ "$version_output" == *"ERPNext Developer Toolkit v"* ]] || fail "version output not recognized"
pass "version command works"

tag_version="$(scripts/release-version.sh tag)"
release_channel="$(scripts/release-version.sh channel)"

if [[ "$release_channel" == "development" ]]; then
  grep -q '^## Unreleased' CHANGELOG.md \
    || fail "development tree must contain an open ## Unreleased changelog section"
  pass "CHANGELOG has an open development section"
else
  grep -q "^## ${tag_version}" CHANGELOG.md \
    || fail "CHANGELOG.md missing release entry for ${tag_version}"
  pass "CHANGELOG version matches release identity (${tag_version})"
fi

# Version discipline: strict development CI remains fail-closed for required
# tooling while retaining the open Unreleased section. Beta, RC, and stable
# qualification must instead expose the exact release entry as the newest one.
# release-pretag-check supplies an explicit validated tag/channel before the
# Git tag exists.
if [[ "${RELEASE_STRICT:-0}" == "1" && "$release_channel" != "development" ]]; then
  first_heading="$(grep -m1 -E '^## ' CHANGELOG.md || true)"
  if [[ "$first_heading" != "## ${tag_version}"* ]]; then
    fail "RELEASE_STRICT: newest CHANGELOG entry is '${first_heading}', expected '## ${tag_version}' (fold any Unreleased section into the release)"
  fi
  pass "RELEASE_STRICT: newest CHANGELOG entry is ${tag_version}"
fi

scripts/check-release-doc-alignment.sh >/tmp/erpnext-dev-doc-align.$$ 2>&1 || {
  cat /tmp/erpnext-dev-doc-align.$$
  rm -f /tmp/erpnext-dev-doc-align.$$
  fail "check-release-doc-alignment.sh failed"
}
rm -f /tmp/erpnext-dev-doc-align.$$
pass "release doc banners + README latest-install path aligned (${tag_version})"

grep -q "Release Manifest ${tag_version}" RELEASE-MANIFEST.txt || fail "RELEASE-MANIFEST.txt version header does not match ${tag_version}"
pass "RELEASE-MANIFEST version matches canonical project version (${tag_version})"

scripts/check-release-artifact-consistency.sh
pass "release manifest and SHA256SUMS are complete and valid"

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
cat >"${fixture_dir}/erpnext-dev-support-bundle-fixture/manifest.txt" <<'EOF_FIXTURE'
ERPNext Developer Toolkit Support Bundle
Generated for validation fixture.
No credentials are included.
EOF_FIXTURE
cat >"${fixture_dir}/erpnext-dev-support-bundle-fixture/system-summary.txt" <<'EOF_FIXTURE'
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
cat >"${bad_root}/site_config.json" <<'EOF_BAD'
{ "db_password": "supersecret123", "encryption_key": "abc" }
EOF_BAD
cat >"${bad_root}/id_ed25519" <<'EOF_BAD'
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
} >"${bad_root}/notes.txt"
: >"${bad_root}/database.sql.gz"
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

scripts/test-legacy-modular-bootstrap.sh >/tmp/erpnext-dev-legacy-bootstrap.$$ 2>&1 || {
  cat /tmp/erpnext-dev-legacy-bootstrap.$$
  rm -f /tmp/erpnext-dev-legacy-bootstrap.$$
  fail "test-legacy-modular-bootstrap.sh failed"
}
rm -f /tmp/erpnext-dev-legacy-bootstrap.$$
pass "legacy modular bootstrap recovery passed"

scripts/test-engine-select.sh >/tmp/erpnext-dev-engine-select.$$ 2>&1 || {
  cat /tmp/erpnext-dev-engine-select.$$
  rm -f /tmp/erpnext-dev-engine-select.$$
  fail "test-engine-select.sh failed"
}
rm -f /tmp/erpnext-dev-engine-select.$$
pass "deployment-engine selection passed"

scripts/test-docker-access-routing.sh >/tmp/erpnext-dev-docker-routing.$$ 2>&1 || {
  cat /tmp/erpnext-dev-docker-routing.$$
  rm -f /tmp/erpnext-dev-docker-routing.$$
  fail "test-docker-access-routing.sh failed"
}
rm -f /tmp/erpnext-dev-docker-routing.$$
pass "Docker access / HTTPS routing passed"

scripts/test-docker-reliability.sh >/tmp/erpnext-dev-docker-reliability.$$ 2>&1 || {
  cat /tmp/erpnext-dev-docker-reliability.$$
  rm -f /tmp/erpnext-dev-docker-reliability.$$
  fail "test-docker-reliability.sh failed"
}
rm -f /tmp/erpnext-dev-docker-reliability.$$
pass "Docker reboot / strict-health / slow-site reliability passed"

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

scripts/test-reinstall-isolation.sh >/tmp/erpnext-dev-reinstall-isolation.$$ 2>&1 || {
  cat /tmp/erpnext-dev-reinstall-isolation.$$
  rm -f /tmp/erpnext-dev-reinstall-isolation.$$
  fail "test-reinstall-isolation.sh failed"
}
rm -f /tmp/erpnext-dev-reinstall-isolation.$$
pass "clean reinstall isolation helpers passed"

scripts/test-asset-build-isolation.sh >/tmp/erpnext-dev-asset-build-isolation.$$ 2>&1 || {
  cat /tmp/erpnext-dev-asset-build-isolation.$$
  rm -f /tmp/erpnext-dev-asset-build-isolation.$$
  fail "test-asset-build-isolation.sh failed"
}
rm -f /tmp/erpnext-dev-asset-build-isolation.$$
pass "asset build isolation helpers passed"

scripts/test-health-env-parser.sh >/tmp/erpnext-dev-health-env-parser.$$ 2>&1 || {
  cat /tmp/erpnext-dev-health-env-parser.$$
  rm -f /tmp/erpnext-dev-health-env-parser.$$
  fail "test-health-env-parser.sh failed"
}
rm -f /tmp/erpnext-dev-health-env-parser.$$
pass "health.env allowlist parser passed"

scripts/test-offvm-host-key.sh >/tmp/erpnext-dev-offvm-host-key.$$ 2>&1 || {
  cat /tmp/erpnext-dev-offvm-host-key.$$
  rm -f /tmp/erpnext-dev-offvm-host-key.$$
  fail "test-offvm-host-key.sh failed"
}
rm -f /tmp/erpnext-dev-offvm-host-key.$$
pass "off-VM SSH host-key policy helpers passed"

scripts/test-risky-shell-patterns.sh >/tmp/erpnext-dev-risky-shell.$$ 2>&1 || {
  cat /tmp/erpnext-dev-risky-shell.$$
  rm -f /tmp/erpnext-dev-risky-shell.$$
  fail "test-risky-shell-patterns.sh failed"
}
rm -f /tmp/erpnext-dev-risky-shell.$$
pass "risky shell pattern audit passed"

scripts/test-adversarial-inputs.sh >/tmp/erpnext-dev-adversarial.$$ 2>&1 || {
  cat /tmp/erpnext-dev-adversarial.$$
  rm -f /tmp/erpnext-dev-adversarial.$$
  fail "test-adversarial-inputs.sh failed"
}
rm -f /tmp/erpnext-dev-adversarial.$$
pass "adversarial input suite passed"

scripts/test-restore-input.sh >/tmp/erpnext-dev-restore-input.$$ 2>&1 || {
  cat /tmp/erpnext-dev-restore-input.$$
  rm -f /tmp/erpnext-dev-restore-input.$$
  fail "test-restore-input.sh failed"
}
rm -f /tmp/erpnext-dev-restore-input.$$
pass "restore controlling-terminal input suite passed"

scripts/test-resolve-latest-release-tag.sh >/tmp/erpnext-dev-resolve-latest.$$ 2>&1 || {
  cat /tmp/erpnext-dev-resolve-latest.$$
  rm -f /tmp/erpnext-dev-resolve-latest.$$
  fail "test-resolve-latest-release-tag.sh failed"
}
rm -f /tmp/erpnext-dev-resolve-latest.$$
pass "latest-release tag resolver tests passed"

scripts/test-local-ip.sh >/tmp/erpnext-dev-local-ip.$$ 2>&1 || {
  cat /tmp/erpnext-dev-local-ip.$$
  rm -f /tmp/erpnext-dev-local-ip.$$
  fail "test-local-ip.sh failed"
}
rm -f /tmp/erpnext-dev-local-ip.$$
pass "local IP status/drift/wizard helpers passed"

scripts/test-healing.sh >/tmp/erpnext-dev-healing.$$ 2>&1 || {
  cat /tmp/erpnext-dev-healing.$$
  rm -f /tmp/erpnext-dev-healing.$$
  fail "test-healing.sh failed"
}
rm -f /tmp/erpnext-dev-healing.$$
pass "guarded auto-healing MVP helpers passed"

scripts/check-pinned-actions.sh >/tmp/erpnext-dev-pinned-actions.$$ 2>&1 || {
  cat /tmp/erpnext-dev-pinned-actions.$$
  rm -f /tmp/erpnext-dev-pinned-actions.$$
  fail "check-pinned-actions.sh failed"
}
rm -f /tmp/erpnext-dev-pinned-actions.$$
pass "GitHub Actions pin check passed"

if command -v shfmt >/dev/null 2>&1; then
  scripts/check-shfmt.sh >/tmp/erpnext-dev-shfmt.$$ 2>&1 || {
    cat /tmp/erpnext-dev-shfmt.$$
    rm -f /tmp/erpnext-dev-shfmt.$$
    fail "check-shfmt.sh failed"
  }
  rm -f /tmp/erpnext-dev-shfmt.$$
  pass "shfmt hermetic-test check passed"
else
  pass "skipped shfmt (not installed)"
fi

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
