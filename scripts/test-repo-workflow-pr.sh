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

assert_log_contains() {
  local expected="$1"
  grep -Fq -- "$expected" "$GH_FAKE_LOG" || {
    cat "$GH_FAKE_LOG" >&2
    fail "missing expected gh invocation: $expected"
  }
}

[[ -x "$WORKFLOW_SOURCE" ]] || fail "workflow script is missing"

tmp="$(mktemp -d /tmp/erpnext-repo-workflow-pr-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="${tmp}/repo"
remote="${tmp}/remote.git"
bin="${tmp}/bin"

mkdir -p "$repo" "$bin"
git -c init.defaultBranch=main init --bare -q "$remote"
git init -q -b main "$repo"

cd "$repo"
git config user.name "Workflow PR Test"
git config user.email "workflow-pr@example.invalid"
git remote add origin "$remote"

mkdir -p scripts
cp "$WORKFLOW_SOURCE" scripts/repo-workflow.sh
chmod +x scripts/repo-workflow.sh

cat >README.md <<'TXT'
Repository workflow PR fixture
TXT

git add -A
git commit -m "Initial PR fixture" >/dev/null
git push -u origin main >/dev/null 2>&1
git switch -c feature/test >/dev/null 2>&1
git push -u origin feature/test >/dev/null 2>&1

cat >"${bin}/gh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${GH_FAKE_LOG:?}"
printf '%q ' "$@" >>"$GH_FAKE_LOG"
printf '\n' >>"$GH_FAKE_LOG"

case "${1:-}:${2:-}" in
  auth:status)
    exit 0
    ;;
  pr:list)
    if [[ "${GH_FAKE_PR_EXISTS:-0}" != "1" ]]; then
      exit 0
    fi
    if printf '%s\n' "$*" | grep -Fq '.[0].number'; then
      echo "42"
    else
      echo "https://github.example.invalid/example/repo/pull/42"
    fi
    ;;
  pr:create)
    echo "https://github.example.invalid/example/repo/pull/42"
    ;;
  pr:view)
    cat <<'TXT'
PR #42: Test pull request
URL: https://github.example.invalid/example/repo/pull/42
State: OPEN
Draft: false
Merge status: CLEAN
Branch: feature/test -> main
TXT
    ;;
  pr:checks)
    if [[ "${GH_FAKE_CHECKS_FAIL:-0}" == "1" ]]; then
      echo "Required checks are not successful" >&2
      exit 1
    fi
    echo "All checks were successful"
    ;;
  pr:merge)
    echo "Merged pull request #42"
    ;;
  *)
    echo "Unexpected fake gh invocation: $*" >&2
    exit 2
    ;;
esac
SH
chmod +x "${bin}/gh"

export PATH="${bin}:${PATH}"
export GH_FAKE_LOG="${tmp}/gh.log"
export GH_FAKE_PR_EXISTS=0
export GH_FAKE_CHECKS_FAIL=0

: >"$GH_FAKE_LOG"
scripts/repo-workflow.sh pr create \
  --base main \
  --title "Test pull request" \
  --body "Test body" \
  >"${tmp}/create.out"

assert_contains "${tmp}/create.out" "pull request ready for CI"
assert_contains "${tmp}/create.out" \
  "https://github.example.invalid/example/repo/pull/42"
assert_log_contains "pr create"
assert_log_contains "--base main"
assert_log_contains "--head feature/test"
assert_log_contains "--title Test\\ pull\\ request"
assert_log_contains "--body Test\\ body"

export GH_FAKE_PR_EXISTS=1
: >"$GH_FAKE_LOG"
scripts/repo-workflow.sh pr create >"${tmp}/existing.out"
assert_contains "${tmp}/existing.out" "reusing existing pull request"
assert_log_contains "pr list"
if grep -Fq "pr create" "$GH_FAKE_LOG"; then
  fail "existing PR detection still called gh pr create"
fi

: >"$GH_FAKE_LOG"
scripts/repo-workflow.sh pr status >"${tmp}/status.out"
assert_contains "${tmp}/status.out" "PR #42: Test pull request"
assert_log_contains "pr view 42"

: >"$GH_FAKE_LOG"
scripts/repo-workflow.sh pr checks --watch --required >"${tmp}/checks.out"
assert_contains "${tmp}/checks.out" "All checks were successful"
assert_log_contains "pr checks 42 --watch --required"

: >"$GH_FAKE_LOG"
scripts/repo-workflow.sh pr merge \
  --squash \
  --admin \
  --delete-branch \
  >"${tmp}/merge.out"

assert_contains "${tmp}/merge.out" "pull request merge completed"
assert_log_contains "pr checks 42 --required"
assert_log_contains "pr merge 42 --squash --admin --delete-branch"

export GH_FAKE_CHECKS_FAIL=1
: >"$GH_FAKE_LOG"
set +e
scripts/repo-workflow.sh pr merge >"${tmp}/merge-fail.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "merge unexpectedly succeeded with failed checks"
assert_contains "${tmp}/merge-fail.out" \
  "required pull request checks are not successful"
if grep -Fq "pr merge" "$GH_FAKE_LOG"; then
  fail "merge command ran after failed required checks"
fi
export GH_FAKE_CHECKS_FAIL=0

git switch main >/dev/null 2>&1
set +e
scripts/repo-workflow.sh pr create >"${tmp}/protected.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "PR creation unexpectedly allowed protected main branch"
assert_contains "${tmp}/protected.out" \
  "pull request operations require a feature, documentation, or release branch"

git switch feature/test >/dev/null 2>&1
echo "dirty" >>README.md
set +e
scripts/repo-workflow.sh pr create >"${tmp}/dirty.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "PR creation unexpectedly allowed a dirty working tree"
assert_contains "${tmp}/dirty.out" \
  "working tree is not clean; publish or commit changes before creating a PR"
git restore README.md

echo "repo workflow PR tests: all checks passed"
