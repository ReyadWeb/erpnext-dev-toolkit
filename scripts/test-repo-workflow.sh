#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_SOURCE="${ROOT_DIR}/scripts/repo-workflow.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq "$expected" "$file" || {
    cat "$file" >&2
    fail "missing expected output: $expected"
  }
}

[[ -x "$WORKFLOW_SOURCE" ]] || fail "workflow script is missing"

tmp="$(mktemp -d /tmp/erpnext-repo-workflow-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
repo="${tmp}/repo"
remote="${tmp}/remote.git"
mkdir -p "$repo"
git -c init.defaultBranch=main init --bare -q "$remote"
git init -q -b main "$repo"
cd "$repo"
git config user.name "Workflow Test"
git config user.email "workflow@example.invalid"
git remote add origin "$remote"
mkdir -p scripts docs
cp "$WORKFLOW_SOURCE" scripts/repo-workflow.sh
chmod +x scripts/repo-workflow.sh

cat >VERSION <<'TXT'
1.20.0
TXT
cat >README.md <<'TXT'
**Current release:** v1.20.0
releases/latest
url_effective
VERSION="v1.20.0"
TXT
cat >ROADMAP.md <<'TXT'
**Current release:** v1.20.0
TXT
cat >TESTING.md <<'TXT'
**Current release:** v1.20.0
TXT
cat >SECURITY.md <<'TXT'
security
TXT
cat >CHANGELOG.md <<'TXT'
## v1.20.0 - Test
TXT
cat >RELEASE-MANIFEST.txt <<'TXT'
# ERPNext Developer Toolkit Release Manifest v1.20.0
SHA256SUMS
RELEASE-MANIFEST.txt
VERSION
README.md
ROADMAP.md
TESTING.md
SECURITY.md
CHANGELOG.md
scripts/repo-workflow.sh
scripts/release-version.sh
scripts/generate-release-checksums.sh
scripts/check-release-doc-alignment.sh
scripts/check-release-artifact-consistency.sh
scripts/validate-release.sh
scripts/build-release-bundle.sh
TXT

cat >scripts/release-version.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-read}" in
  read) cat VERSION ;;
  tag) printf 'v%s\n' "$(cat VERSION)" ;;
  assert-script) exit 0 ;;
  *) exit 1 ;;
esac
SH
cat >scripts/generate-release-checksums.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
: >SHA256SUMS
while IFS= read -r file; do
  [[ -n "$file" && "$file" != \#* && "$file" != SHA256SUMS ]] || continue
  sha256sum "$file" >>SHA256SUMS
done <RELEASE-MANIFEST.txt
echo "checksums generated"
SH
cat >scripts/check-release-doc-alignment.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
grep -Fxq '**Current release:** v1.20.0' README.md
grep -Fxq '**Current release:** v1.20.0' ROADMAP.md
grep -Fxq '**Current release:** v1.20.0' TESTING.md
echo "docs aligned"
SH
cat >scripts/check-release-artifact-consistency.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
sha256sum -c SHA256SUMS >/dev/null
echo "artifacts aligned"
SH
cat >scripts/validate-release.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'full\n' >>"${WORKFLOW_TEST_LOG:?}"
echo "full validation"
SH
cat >scripts/build-release-bundle.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'bundle\n' >>"${WORKFLOW_TEST_LOG:?}"
echo "bundle built"
SH
chmod +x scripts/*.sh
scripts/generate-release-checksums.sh >/dev/null
git add -A
git commit -m "Initial test repository" >/dev/null
git push -u origin main >/dev/null 2>&1

git switch -c feature/test >/dev/null 2>&1
git push -u origin feature/test >/dev/null 2>&1

export WORKFLOW_TEST_LOG="${tmp}/calls.log"
: >"$WORKFLOW_TEST_LOG"

echo "docs change" >>docs-note.md
out="${tmp}/status.out"
scripts/repo-workflow.sh status >"$out"
assert_contains "$out" "Validation mode              fast"

out="${tmp}/fast.out"
scripts/repo-workflow.sh check >"$out"
assert_contains "$out" "fast validation passed"
[[ ! -s "$WORKFLOW_TEST_LOG" ]] || fail "fast check unexpectedly ran full validation"

git reset --hard HEAD >/dev/null
rm -f docs-note.md
: >"$WORKFLOW_TEST_LOG"
echo "# high risk" >>scripts/validate-release.sh
out="${tmp}/full.out"
scripts/repo-workflow.sh check >"$out"
assert_contains "$out" "cached full validation"
grep -Fxq full "$WORKFLOW_TEST_LOG" || fail "full validator was not called"
grep -Fxq bundle "$WORKFLOW_TEST_LOG" || fail "bundle builder was not called"

: >"$WORKFLOW_TEST_LOG"
out="${tmp}/cache.out"
scripts/repo-workflow.sh check >"$out"
assert_contains "$out" "full validation already passed"
[[ ! -s "$WORKFLOW_TEST_LOG" ]] || fail "cached full check reran expensive commands"

git reset --hard HEAD >/dev/null
: >"$WORKFLOW_TEST_LOG"
echo "protected" >>README.md
git switch main >/dev/null 2>&1
set +e
scripts/repo-workflow.sh publish -m "Should fail" >"${tmp}/protected.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "publish unexpectedly allowed protected main branch"
assert_contains "${tmp}/protected.out" "publish is blocked on protected branch"
git restore README.md

git switch feature/test >/dev/null 2>&1
echo "publish change" >>README.md
scripts/repo-workflow.sh publish --fast -m "Docs: publish test" >"${tmp}/publish.out"
assert_contains "${tmp}/publish.out" "validated, committed, and pushed"
[[ -z "$(git status --porcelain)" ]] || fail "publish did not leave a clean tree"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/feature/test)" ]] \
  || fail "publish did not synchronize the feature branch"

# Simulate a push failure after a successful commit, then resume safely.
echo "resume change" >>README.md
git remote set-url origin "${tmp}/missing.git"
set +e
scripts/repo-workflow.sh publish --fast -m "Docs: resume test" >"${tmp}/resume-fail.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "publish unexpectedly succeeded with an invalid remote"
assert_contains "${tmp}/resume-fail.out" "Resume with:"
[[ -z "$(git status --porcelain)" ]] || fail "failed push should occur after a clean commit"
git remote set-url origin "$remote"
scripts/repo-workflow.sh resume >"${tmp}/resume.out"
assert_contains "${tmp}/resume.out" "saved publish operation completed"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/feature/test)" ]] \
  || fail "resume did not push the saved commit"

scripts/repo-workflow.sh clean-cache >/dev/null
[[ ! -f "$(git rev-parse --git-path erpnext-workflow)/action" ]] \
  || fail "clean-cache did not remove state"

echo "repo workflow tests: all checks passed"
