#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_SOURCE="${ROOT_DIR}/scripts/repo-workflow.sh"
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
contains() {
  grep -Fq "$2" "$1" || {
    cat "$1" >&2
    fail "missing: $2"
  }
}

tmp="$(mktemp -d /tmp/erpnext-work-consolidation-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
remote="$tmp/remote.git"
bin="$tmp/bin"
mkdir -p "$repo/scripts" "$bin"
git -c init.defaultBranch=main init --bare -q "$remote"
git init -q -b main "$repo"
cd "$repo"
git config user.name "Workflow Work Test"
git config user.email "workflow-work@example.invalid"
git remote add origin "$remote"
cp "$WORKFLOW_SOURCE" scripts/repo-workflow.sh
chmod +x scripts/repo-workflow.sh
cat >README.md <<'EOF'
workflow fixture
EOF
cat >scripts/release-version.sh <<'EOF'
#!/usr/bin/env bash
case "${1:-read}" in
  read) echo 1.20.0 ;;
  tag) echo v1.20.0 ;;
  runtime|script) echo 1.20.0 ;;
  assert-runtime|assert-script) exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat >scripts/generate-release-checksums.sh <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >scripts/check-release-doc-alignment.sh <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >scripts/check-release-artifact-consistency.sh <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >scripts/validate-release.sh <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >scripts/build-release-bundle.sh <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x scripts/*.sh
git add -A && git commit -m init >/dev/null
git push -u origin main >/dev/null 2>&1

scripts/repo-workflow.sh work start feature/work-test >"$tmp/start.out"
contains "$tmp/start.out" "Work Branch Ready"
[[ "$(git branch --show-current)" == feature/work-test ]] || fail "branch not created"

echo change >>README.md

cat >"$bin/gh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%q ' "$@" >>"${GH_FAKE_LOG:?}"; printf '\n' >>"$GH_FAKE_LOG"
case "${1:-}:${2:-}" in
 auth:status) exit 0 ;;
 pr:list)
   if [[ "${GH_PR_EXISTS:-0}" == 1 ]]; then
     if printf '%s' "$*" | grep -Fq '.[0].number'; then echo 42; else echo https://example.invalid/pr/42; fi
   fi ;;
 pr:create)
   gh_args="$(printf '%s\n' "$@")"
   if ! grep -Fxq -- '--fill' <<<"$gh_args"; then
     grep -Fxq -- '--title' <<<"$gh_args" \
       || { echo "missing --title or --fill for non-interactive PR creation" >&2; exit 2; }
     if ! grep -Eq -- '^--body(-file)?$' <<<"$gh_args"; then
       echo "missing --body/--body-file or --fill for non-interactive PR creation" >&2
       exit 2
     fi
   fi
   echo https://example.invalid/pr/42
   ;;
 pr:checks)
   if printf '%s\n' "$*" | grep -Fq -- '--json bucket'; then
     if printf '%s\n' "$*" | grep -Fq -- '--required'; then
       printf '7\t7\t0\t0\t0\n'
     else
       printf '8\t8\t0\t0\t0\n'
     fi
   else
     echo "All checks were successful"
   fi
   ;;
 pr:view)
   if printf '%s' "$*" | grep -Fq '\"'; then
     echo "invalid escaped quote in --jq filter" >&2
     exit 2
   fi
   echo 'OPEN|CLEAN|'
   ;;
 repo:view) echo 'ReyadWeb/erpnext-dev-toolkit' ;;
 api) echo true ;;
 pr:merge)
   git --git-dir="${TEST_REMOTE:?}" update-ref refs/heads/main "$(git rev-parse HEAD)"
   echo merged ;;
 *) echo "unexpected gh: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$bin/gh"
cat >"$bin/shellcheck" <<'EOF'
#!/usr/bin/env bash
if [[ "${SHELLCHECK_FAKE_FAIL:-0}" == "1" ]]; then
  echo "simulated ShellCheck failure" >&2
  exit 1
fi
exit 0
EOF
chmod +x "$bin/shellcheck"
export PATH="$bin:$PATH" GH_FAKE_LOG="$tmp/gh.log" GH_PR_EXISTS=0 TEST_REMOTE="$remote"

echo "# lint-failure fixture" >>scripts/release-version.sh
export SHELLCHECK_FAKE_FAIL=1
set +e
scripts/repo-workflow.sh work finish --dry-run --fast --no-cache -m "Test: lint failure" \
  --pr-title "Lint Failure PR" >"$tmp/lint-failure.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "changed-file ShellCheck failure was ignored"
contains "$tmp/lint-failure.out" "FAILED: Changed shell lint"
export SHELLCHECK_FAKE_FAIL=0

scripts/repo-workflow.sh work finish --dry-run --fast --no-cache -m "Test: dry run" --pr-title "Dry Run PR" >"$tmp/dry-run.out"
contains "$tmp/dry-run.out" "dry run complete"
[[ -n "$(git status --porcelain)" ]] || fail "dry run unexpectedly removed the pending change"

scripts/repo-workflow.sh work finish --fast --no-watch -m "Test: consolidated finish" --pr-title "Test PR" >"$tmp/finish.out"
contains "$tmp/finish.out" "Work Ready to Land"
[[ -z "$(git status --porcelain)" ]] || fail "finish left dirty tree"
export GH_PR_EXISTS=1
scripts/repo-workflow.sh work land --confirm --delete-branch >"$tmp/land.out"
contains "$tmp/land.out" "Work Landed"
[[ "$(git branch --show-current)" == main ]] || fail "land did not switch to main"

echo "repo workflow work tests: all checks passed"
