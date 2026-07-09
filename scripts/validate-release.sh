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
[[ -f README.md ]] || fail "README.md is missing"
[[ -f SECURITY.md ]] || fail "SECURITY.md is missing"
[[ -f RELIABILITY-PLAN.md ]] || fail "RELIABILITY-PLAN.md is missing"

bash -n erpnext-dev.sh
pass "bash syntax valid"

chmod +x erpnext-dev.sh
version_output="$(./erpnext-dev.sh version)"
echo "$version_output"
[[ "$version_output" == *"ERPNext Developer Toolkit v"* ]] || fail "version output not recognized"
pass "version command works"

sha256sum -c SHA256SUMS
pass "SHA256SUMS verifies erpnext-dev.sh"

./erpnext-dev.sh --help >/tmp/erpnext-dev-help.$$ 2>&1 || fail "--help failed"
grep -q "production-ops-wizard" /tmp/erpnext-dev-help.$$ || fail "help missing production-ops-wizard"
grep -q "verify-toolkit" /tmp/erpnext-dev-help.$$ || fail "help missing verify-toolkit"
rm -f /tmp/erpnext-dev-help.$$
pass "help exposes required commands"

./erpnext-dev.sh verify-toolkit >/tmp/erpnext-dev-verify.$$ 2>&1 || fail "verify-toolkit failed"
grep -q "Active match.*OK" /tmp/erpnext-dev-verify.$$ || fail "verify-toolkit did not report Active match OK"
rm -f /tmp/erpnext-dev-verify.$$
pass "verify-toolkit active checksum match"

if find . -maxdepth 2 -type f -name 'GITHUB-UPDATE-v*.md' | grep -q .; then
  find . -maxdepth 2 -type f -name 'GITHUB-UPDATE-v*.md'
  fail "GITHUB-UPDATE release notes file found in package tree"
fi
pass "no GITHUB-UPDATE-v*.md files"

if grep -RInE '(password|secret|token|private[-_ ]?key)=' \
  --exclude-dir=.git \
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
