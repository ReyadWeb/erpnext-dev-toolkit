#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/release-test-env.sh
source "${ROOT_DIR}/scripts/release-test-env.sh"
release_test_env_reexec "$0" "$@"
WORKFLOW_SOURCE="${ROOT_DIR}/scripts/repo-workflow.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "$expected" "$file" || {
    cat "$file" >&2
    fail "missing expected output: $expected"
  }
}

assert_log_contains() {
  local expected="$1"
  grep -Fq -- "$expected" "$RELEASE_FAKE_LOG" || {
    cat "$RELEASE_FAKE_LOG" >&2
    fail "missing expected release helper invocation: $expected"
  }
}

[[ -x "$WORKFLOW_SOURCE" ]] || fail "workflow script is missing"

tmp="$(mktemp -d /tmp/erpnext-repo-workflow-release-transaction-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
repo="${tmp}/repo"
remote="${tmp}/remote.git"
mkdir -p "$repo"
git -c init.defaultBranch=main init --bare -q "$remote"
git init -q -b main "$repo"

cd "$repo"
git config user.name "Workflow Release Transaction Test"
git config user.email "workflow-release-transaction@example.invalid"
git remote add origin "$remote"
mkdir -p scripts docs
cp "$WORKFLOW_SOURCE" scripts/repo-workflow.sh
chmod +x scripts/repo-workflow.sh

cat >VERSION <<'TXT'
1.20.0
TXT
cat >erpnext-dev.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
SCRIPT_VERSION="1.20.0"
SH_SCRIPT
chmod +x erpnext-dev.sh

cat >CHANGELOG.md <<'TXT'
## v1.20.0
TXT
cat >README.md <<'TXT'
Fixture
TXT
cat >ROADMAP.md <<'TXT'
Fixture
TXT
cat >TESTING.md <<'TXT'
Fixture
TXT
cat >RELEASE-MANIFEST.txt <<'TXT'
VERSION
erpnext-dev.sh
CHANGELOG.md
TXT
: >SHA256SUMS

cat >scripts/release-version.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
version="$(cat VERSION)"
runtime="$(sed -nE 's/^SCRIPT_VERSION="([^"]+)".*/\1/p' erpnext-dev.sh | head -n1)"
case "${1:-read}" in
  read) echo "$version" ;;
  script) echo "$runtime" ;;
  tag) echo "v${version}" ;;
  channel)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo stable
    elif [[ "$version" == *-beta.* ]]; then
      echo beta
    elif [[ "$version" == *-rc.* ]]; then
      echo rc
    else
      echo prerelease
    fi
    ;;
  assert-script)
    [[ "$version" == "$runtime" ]]
    ;;
  assert-tag)
    [[ "${2:-}" == "v${version}" ]]
    ;;
  channel-for-tag)
    [[ "${2:-}" == "v${version}" ]]
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo stable
    else
      echo beta
    fi
    ;;
  *) exit 2 ;;
esac
SH_SCRIPT
chmod +x scripts/release-version.sh

export RELEASE_FAKE_LOG="${tmp}/release-helper.log"
: >"$RELEASE_FAKE_LOG"

cat >scripts/release-prepare-beta.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'prepare-beta %q %q\n' "$1" "$2" >>"$RELEASE_FAKE_LOG"
[[ "${RELEASE_FAKE_FAIL_PREPARE:-0}" != "1" ]] || exit 9
printf '%s\n' "$1" >VERSION
sed -i -E "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$1\"/" erpnext-dev.sh
printf '\n## v%s\n' "$1" >>CHANGELOG.md
SH_SCRIPT
chmod +x scripts/release-prepare-beta.sh

cat >scripts/release-promote-stable.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'promote-stable %q %q\n' "$1" "$2" >>"$RELEASE_FAKE_LOG"
printf '%s\n' "$1" >VERSION
sed -i -E "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$1\"/" erpnext-dev.sh
printf '\n## v%s\n' "$1" >>CHANGELOG.md
SH_SCRIPT
chmod +x scripts/release-promote-stable.sh

cat >scripts/release-pretag-check.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'pretag' >>"$RELEASE_FAKE_LOG"
for arg in "$@"; do printf ' %q' "$arg" >>"$RELEASE_FAKE_LOG"; done
printf '\n' >>"$RELEASE_FAKE_LOG"
[[ -z "$(git status --porcelain --untracked-files=all)" ]]
SH_SCRIPT
chmod +x scripts/release-pretag-check.sh

cat >scripts/build-release-bundle.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'build-bundle\n' >>"$RELEASE_FAKE_LOG"
mkdir -p dist
: >"dist/fixture.tar.gz"
SH_SCRIPT
chmod +x scripts/build-release-bundle.sh

cat >scripts/generate-release-checksums.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
: >SHA256SUMS
SH_SCRIPT
cat >scripts/check-release-doc-alignment.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
exit 0
SH_SCRIPT
cat >scripts/check-release-artifact-consistency.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
exit 0
SH_SCRIPT
cat >scripts/validate-release.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
version="$(cat VERSION)"
if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$version" != "1.20.0" ]]; then
  [[ "${ERPNEXT_RELEASE_PHASE:-}" == "stable-promotion" ]] || exit 31
  [[ "${ERPNEXT_RELEASE_SOURCE_TAG:-}" == "v${version}-beta.1" ]] || exit 32
  [[ "${ERPNEXT_RELEASE_CHANNEL:-}" == "stable" ]] || exit 33
  [[ "${ERPNEXT_RELEASE_TAG:-}" == "v${version}" ]] || exit 34
  [[ "${RELEASE_STRICT:-0}" == "1" ]] || exit 35
fi
if [[ "${RELEASE_FAKE_FAIL_VALIDATE_ONCE:-0}" == "1" &&
  ! -e "${RELEASE_FAKE_LOG}.validate-failed" ]]; then
  : >"${RELEASE_FAKE_LOG}.validate-failed"
  exit 36
fi
exit 0
SH_SCRIPT
chmod +x scripts/generate-release-checksums.sh \
  scripts/check-release-doc-alignment.sh \
  scripts/check-release-artifact-consistency.sh \
  scripts/validate-release.sh

git add -A
git commit -m "Initial release transaction fixture" >/dev/null
git push -u origin main >/dev/null 2>&1

git switch -c feature/v1.21.0-workflow >/dev/null 2>&1
git push -u origin feature/v1.21.0-workflow >/dev/null 2>&1

set +e
scripts/repo-workflow.sh release prepare-beta \
  1.21.0-beta.1 \
  "Release transaction fixture" \
  >"${tmp}/prepare-wrong-branch.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "beta preparation unexpectedly succeeded on a feature branch"
assert_contains "${tmp}/prepare-wrong-branch.out" \
  "beta preparation for v1.21.0-beta.1 requires release/v1.21.0"

git switch main >/dev/null 2>&1
git switch -c release/v1.21.0 >/dev/null 2>&1
git push -u origin release/v1.21.0 >/dev/null 2>&1

scripts/repo-workflow.sh release prepare-beta \
  1.21.0-beta.1 \
  "Release transaction fixture" \
  >"${tmp}/prepare.out"

assert_contains "${tmp}/prepare.out" "Release Metadata Prepared"
assert_contains "${tmp}/prepare.out" "review required before publication"
assert_contains "${tmp}/prepare.out" "release publish --confirm-reviewed"
assert_log_contains "prepare-beta 1.21.0-beta.1 Release\\ transaction\\ fixture"
assert_log_contains "build-bundle"
[[ "$(cat VERSION)" == "1.21.0-beta.1" ]] || fail "beta version was not prepared"
[[ -n "$(git status --porcelain)" ]] || fail "beta preparation unexpectedly committed changes"
[[ "$(cat .git/erpnext-workflow/release-state | sed -n 's/^phase=//p')" == "beta-preparation" ]] \
  || fail "beta phase was not persisted"

scripts/repo-workflow.sh release prepare-beta \
  1.21.0-beta.1 \
  "Release transaction fixture" \
  >"${tmp}/prepare-again.out"
assert_contains "${tmp}/prepare-again.out" "Beta Metadata Already Prepared"
assert_contains "${tmp}/prepare-again.out" "no preparation changes were repeated"
[[ "$(grep -Fc 'prepare-beta 1.21.0-beta.1' "$RELEASE_FAKE_LOG")" == "1" ]] \
  || fail "idempotent beta preparation repeated the metadata helper"

scripts/repo-workflow.sh release beta \
  1.21.0-beta.1 \
  "Release transaction fixture" \
  >"${tmp}/beta-review-gate.out"
assert_contains "${tmp}/beta-review-gate.out" "review required before publication"

set +e
scripts/repo-workflow.sh release publish \
  -m "Release: prepare v1.21.0-beta.1" \
  >"${tmp}/publish-unconfirmed.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "release publish succeeded without --confirm-reviewed"
assert_contains "${tmp}/publish-unconfirmed.out" "requires --confirm-reviewed"

scripts/repo-workflow.sh release beta \
  1.21.0-beta.1 \
  "Release transaction fixture" \
  --confirm-reviewed \
  >"${tmp}/publish.out"
assert_contains "${tmp}/publish.out" "reviewed release metadata validated, committed, and pushed"
assert_contains "${tmp}/publish.out" "Beta Tag Confirmation Required"
assert_contains "${tmp}/publish.out" "no tag was created"
[[ -z "$(git status --porcelain)" ]] || fail "release publish left a dirty tree"
[[ "$(git log -1 --format=%s)" == "Release: prepare v1.21.0-beta.1" ]] \
  || fail "unexpected beta release commit message"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/release/v1.21.0)" ]] \
  || fail "beta release branch was not pushed"

git tag -a v1.21.0-beta.1 -m "Accepted beta fixture"
scripts/repo-workflow.sh release promote-stable \
  1.21.0 \
  "Release transaction fixture" \
  >"${tmp}/promote.out"
assert_contains "${tmp}/promote.out" "Release Metadata Prepared"
assert_log_contains "promote-stable 1.21.0 Release\\ transaction\\ fixture"
[[ "$(cat VERSION)" == "1.21.0" ]] || fail "stable version was not prepared"
[[ -n "$(git status --porcelain)" ]] || fail "stable promotion unexpectedly committed changes"
assert_contains .git/erpnext-workflow/release-state "phase=stable-promotion"
assert_contains .git/erpnext-workflow/release-state "source_tag=v1.21.0-beta.1"
assert_contains .git/erpnext-workflow/release-state \
  "source_commit=$(git rev-parse 'v1.21.0-beta.1^{commit}')"

scripts/repo-workflow.sh release stable \
  1.21.0 \
  --from v1.21.0-beta.1 \
  "Release transaction fixture" \
  >"${tmp}/stable-review-gate.out"
assert_contains "${tmp}/stable-review-gate.out" "review required before publication"

: >.git/erpnext-workflow/cache/full.fingerprint
export RELEASE_FAKE_FAIL_VALIDATE_ONCE=1
set +e
scripts/repo-workflow.sh release publish \
  --confirm-reviewed \
  -m "Release: promote v1.21.0 stable" \
  >"${tmp}/stable-publish-fail.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "transient stable publication failure unexpectedly succeeded"
assert_contains .git/erpnext-workflow/release-state "review_confirmed=1"
unset RELEASE_FAKE_FAIL_VALIDATE_ONCE

scripts/repo-workflow.sh release recover >"${tmp}/stable-publish.out"
assert_contains "${tmp}/stable-publish.out" "Safe recovery"
assert_contains "${tmp}/stable-publish.out" \
  "scripts/repo-workflow.sh release publish --resume-prepared"
[[ -z "$(git status --porcelain)" ]] || fail "stable publication left a dirty tree"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/release/v1.21.0)" ]] \
  || fail "stable release branch was not pushed"
assert_contains .git/erpnext-workflow/release-state "phase=stable-pr"

set +e
scripts/repo-workflow.sh release pretag v1.21.0 --offline \
  >"${tmp}/pretag-release-branch.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "stable pre-tag unexpectedly succeeded on the release branch"
assert_contains "${tmp}/pretag-release-branch.out" \
  "stable pre-tag validation for v1.21.0 requires main"

scripts/repo-workflow.sh release status --offline >"${tmp}/proof-release-branch.out"
assert_contains "${tmp}/proof-release-branch.out" "Phase                        stable-pr"
assert_contains "${tmp}/proof-release-branch.out" \
  "stable release branch is ready for PR"

git switch main >/dev/null 2>&1
git merge --ff-only release/v1.21.0 >/dev/null 2>&1
git push origin main >/dev/null 2>&1
scripts/repo-workflow.sh release doctor --offline >"${tmp}/doctor-main.out"
assert_contains "${tmp}/doctor-main.out" "Phase                        stable-pretag"
assert_contains "${tmp}/doctor-main.out" "Expected branch              main"
assert_contains "${tmp}/doctor-main.out" "Source beta/RC               v1.21.0-beta.1"
assert_contains "${tmp}/doctor-main.out" "Source verified              yes"

scripts/repo-workflow.sh release pretag v1.21.0 --offline >"${tmp}/pretag.out"
assert_contains "${tmp}/pretag.out" "Pre-Tag Proof Recorded"
assert_contains "${tmp}/pretag.out" "no tag was created"
assert_log_contains "pretag v1.21.0 --offline"
[[ ! -e .git/refs/tags/v1.21.0 ]] || fail "W3.2 unexpectedly created a tag"
[[ "$(cat .git/erpnext-workflow/release-pretag/tag)" == "v1.21.0" ]] \
  || fail "pre-tag proof tag is incorrect"
[[ "$(cat .git/erpnext-workflow/release-pretag/commit)" == "$(git rev-parse HEAD)" ]] \
  || fail "pre-tag proof commit is incorrect"

scripts/repo-workflow.sh release status --offline >"${tmp}/proof-main.out"
assert_contains "${tmp}/proof-main.out" "Pre-tag proof                valid for exact commit"
assert_contains "${tmp}/proof-main.out" "pre-tag validation passed for exact commit"

echo "stale" >>README.md
scripts/repo-workflow.sh release status --offline >"${tmp}/stale-status.out"
assert_contains "${tmp}/stale-status.out" "Pre-tag proof                stale"
git restore README.md

: >"$RELEASE_FAKE_LOG"
git switch -c release/v1.22.0 >/dev/null 2>&1
git push -u origin release/v1.22.0 >/dev/null 2>&1
export RELEASE_FAKE_FAIL_PREPARE=1
set +e
scripts/repo-workflow.sh release prepare-beta \
  1.22.0-beta.1 \
  "Failure fixture" \
  >"${tmp}/prepare-fail.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "failing beta helper unexpectedly succeeded"
[[ -z "$(git status --porcelain)" ]] || fail "failed beta helper left repository changes"
unset RELEASE_FAKE_FAIL_PREPARE

echo "repo workflow release-transaction tests: all checks passed"
