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

[[ -x "$WORKFLOW_SOURCE" ]] || fail "workflow script is missing"

tmp="$(mktemp -d /tmp/erpnext-repo-workflow-release-run-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
repo="${tmp}/repo"
remote="${tmp}/remote.git"
bin="${tmp}/bin"
gh_state="${tmp}/gh-state"
mkdir -p "$repo" "$bin" "$gh_state"
git -c init.defaultBranch=main init --bare -q "$remote"
git init -q -b main "$repo"

cd "$repo"
git config user.name "Resumable Release Test"
git config user.email "resumable-release@example.invalid"
git remote add origin "$remote"
mkdir -p scripts
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
for file in README.md ROADMAP.md TESTING.md; do
  printf 'Fixture\n' >"$file"
done
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
    [[ "$version" == *-beta.* ]] && echo beta || echo stable
    ;;
  assert-script) [[ "$version" == "$runtime" ]] ;;
  assert-tag) [[ "${2:-}" == "v${version}" ]] ;;
  channel-for-tag)
    [[ "${2:-}" == "v${version}" ]]
    [[ "$version" == *-beta.* ]] && echo beta || echo stable
    ;;
  *) exit 2 ;;
esac
SH_SCRIPT

cat >scripts/release-prepare-beta.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$1" >VERSION
sed -i -E "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$1\"/" erpnext-dev.sh
printf '\n## v%s — %s\n' "$1" "$2" >>CHANGELOG.md
SH_SCRIPT

cat >scripts/release-promote-stable.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$1" >VERSION
sed -i -E "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$1\"/" erpnext-dev.sh
printf '\n## v%s — %s\n' "$1" "$2" >>CHANGELOG.md
SH_SCRIPT

cat >scripts/release-pretag-check.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == "v$(cat VERSION)" ]]
[[ -z "$(git status --porcelain --untracked-files=all)" ]]
echo "pretag fixture passed"
SH_SCRIPT

cat >scripts/build-release-bundle.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p dist
: >dist/fixture.tar.gz
SH_SCRIPT

cat >scripts/generate-release-checksums.sh <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
: >SHA256SUMS
SH_SCRIPT

for script in check-release-doc-alignment.sh check-release-artifact-consistency.sh validate-release.sh; do
  cat >"scripts/${script}" <<'SH_SCRIPT'
#!/usr/bin/env bash
exit 0
SH_SCRIPT
done
chmod +x scripts/*.sh

cat >"${bin}/gh" <<'SH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

state_dir="${GH_FAKE_STATE_DIR:?}"
pr_head_file="${state_dir}/pr-head"
pr_merge_file="${state_dir}/pr-merge"
pr_number_file="${state_dir}/pr-number"

case "${1:-}:${2:-}" in
  auth:status)
    exit 0
    ;;
  repo:view)
    echo "example/repo"
    ;;
  api:*)
    if [[ "$*" == *"repos/example/repo/pulls/"* ]]; then
      number="$(cat "$pr_number_file")"
      head="$(cat "$pr_head_file")"
      if [[ -f "$pr_merge_file" ]]; then
        merge="$(cat "$pr_merge_file")"
        echo "closed|2026-07-30T22:00:00Z|${head}|${merge}|https://example.invalid/pr/${number}"
      else
        echo "open||${head}||https://example.invalid/pr/${number}"
      fi
    elif [[ "$*" == *"repos/example/repo/pulls"* && -f "$pr_head_file" ]]; then
      cat "$pr_number_file"
    fi
    ;;
  pr:list)
    if [[ ! -f "$pr_head_file" ]]; then
      exit 0
    elif [[ "$*" == *"--json url"* ]]; then
      echo "https://example.invalid/pr/$(cat "$pr_number_file")"
    else
      cat "$pr_number_file"
    fi
    ;;
  pr:create)
    if grep -q -- '-beta\\.' VERSION; then
      echo "17" >"$pr_number_file"
    else
      echo "18" >"$pr_number_file"
    fi
    git rev-parse HEAD >"$pr_head_file"
    echo "https://example.invalid/pr/$(cat "$pr_number_file")"
    ;;
  pr:checks)
    if [[ "$*" == *"--json bucket"* ]]; then
      printf '1\t1\t0\t0\t0\n'
    else
      echo "All checks were successful"
    fi
    ;;
  pr:merge)
    branch="$(git branch --show-current)"
    [[ "$branch" == "release/v1.21.0" ]]
    git switch main >/dev/null
    git merge --no-ff "$branch" -m "Merge resumable release fixture" >/dev/null
    git push origin main >/dev/null
    git rev-parse HEAD >"$pr_merge_file"
    git push origin --delete "$branch" >/dev/null
    git branch -D "$branch" >/dev/null
    echo "Merged pull request #$(cat "$pr_number_file")"
    ;;
  run:list)
    echo "77"
    ;;
  run:view)
    if [[ "$*" == *".headSha"* ]]; then
      git rev-parse "v$(cat VERSION)^{}"
    elif [[ "$*" == *".conclusion"* ]]; then
      [[ ! -f "${state_dir}/workflow-done" ]] || echo "success"
    elif [[ "$*" == *".url"* ]]; then
      echo "https://example.invalid/actions/runs/77"
    fi
    ;;
  run:watch)
    if [[ ! -f "${state_dir}/watch-interrupted" ]]; then
      : >"${state_dir}/watch-interrupted"
      echo "failed to get jobs: HTTP 502" >&2
      exit 1
    fi
    : >"${state_dir}/workflow-done"
    echo "workflow complete"
    ;;
  *)
    echo "Unexpected fake gh invocation: $*" >&2
    exit 2
    ;;
esac
SH_SCRIPT
chmod +x "${bin}/gh"

git add -A
git commit -m "Initial resumable release fixture" >/dev/null
git push -u origin main >/dev/null 2>&1

export PATH="${bin}:${PATH}"
export GH_FAKE_STATE_DIR="$gh_state"

scripts/repo-workflow.sh release run \
  beta \
  1.21.0-beta.1 \
  "Resumable release fixture" \
  --confirm-reviewed \
  --confirm-merge \
  --non-interactive \
  >"${tmp}/through-merge.out"

assert_contains "${tmp}/through-merge.out" "Release Branch Ready"
assert_contains "${tmp}/through-merge.out" "Merged Release Synchronized"
assert_contains "${tmp}/through-merge.out" "no reconstruction required"
assert_contains "${tmp}/through-merge.out" "release paused safely before tag creation"
[[ "$(git branch --show-current)" == "main" ]] \
  || fail "resumable release did not finish the merge stage on main"
[[ "$(git rev-parse HEAD)" == "$(cat "${gh_state}/pr-merge")" ]] \
  || fail "main does not match the exact release PR merge commit"
[[ ! -e .git/refs/heads/release/v1.21.0 ]] \
  || fail "deleted local release branch was reconstructed"
[[ -z "$(git ls-remote --heads origin release/v1.21.0)" ]] \
  || fail "deleted remote release branch was reconstructed"
[[ "$(sed -n 's/^phase=//p' .git/erpnext-workflow/release-state)" == "beta-pretag" ]] \
  || fail "release run did not persist beta-pretag after merge"

# Reproduce the historical interruption: the PR is merged, main is synchronized,
# and the release branch is gone, but the saved phase still says beta-pr.
sed -i 's/^phase=beta-pretag$/phase=beta-pr/' .git/erpnext-workflow/release-state
scripts/repo-workflow.sh release status --offline >"${tmp}/merged-status.out"
assert_contains "${tmp}/merged-status.out" "release commit is ready for exact PR reconciliation"
assert_contains "${tmp}/merged-status.out" "scripts/repo-workflow.sh release run"
if grep -Fq "Switch to or create release/v1.21.0" "${tmp}/merged-status.out"; then
  fail "release status still recommends manual branch reconstruction"
fi
scripts/repo-workflow.sh release run --non-interactive >"${tmp}/resume-merged.out"
assert_contains "${tmp}/resume-merged.out" "Merged Release Synchronized"
assert_contains "${tmp}/resume-merged.out" "no reconstruction required"
assert_contains "${tmp}/resume-merged.out" "release paused safely before tag creation"
[[ ! -e .git/refs/heads/release/v1.21.0 ]] \
  || fail "merged-PR recovery reconstructed the deleted local release branch"
[[ -z "$(git ls-remote --heads origin release/v1.21.0)" ]] \
  || fail "merged-PR recovery reconstructed the deleted remote release branch"

scripts/repo-workflow.sh release run \
  --confirm-tag v1.21.0-beta.1 \
  --non-interactive \
  >"${tmp}/tag-watch.out" 2>&1
assert_contains "${tmp}/tag-watch.out" "annotated release tag created and pushed"
assert_contains "${tmp}/tag-watch.out" "HTTP 502"
assert_contains "${tmp}/tag-watch.out" "workflow watch was interrupted"
assert_contains "${tmp}/tag-watch.out" "release workflow completed successfully"
assert_contains "${tmp}/tag-watch.out" "release paused safely before published asset verification"
[[ "$(git rev-parse 'v1.21.0-beta.1^{}')" == "$(git rev-parse main)" ]] \
  || fail "beta tag does not point to synchronized main"
[[ "$(sed -n 's/^phase=//p' .git/erpnext-workflow/release-state)" == "beta-published" ]] \
  || fail "release run did not persist beta-published after the protected workflow"

# Stable uses the same state machine and must also tag synchronized main without
# recreating release/v1.21.0.
sed -i 's/^phase=beta-published$/phase=beta-verified/' .git/erpnext-workflow/release-state
rm -f \
  "${gh_state}/pr-head" \
  "${gh_state}/pr-merge" \
  "${gh_state}/pr-number" \
  "${gh_state}/watch-interrupted" \
  "${gh_state}/workflow-done"

scripts/repo-workflow.sh release run \
  stable \
  1.21.0 \
  --from v1.21.0-beta.1 \
  "Resumable stable fixture" \
  --confirm-reviewed \
  --confirm-merge \
  --non-interactive \
  >"${tmp}/stable-through-merge.out"
assert_contains "${tmp}/stable-through-merge.out" "Merged Release Synchronized"
assert_contains "${tmp}/stable-through-merge.out" "no reconstruction required"
assert_contains "${tmp}/stable-through-merge.out" "release paused safely before tag creation"
[[ "$(git branch --show-current)" == "main" ]] \
  || fail "stable resumable release did not finish the merge stage on main"
[[ ! -e .git/refs/heads/release/v1.21.0 ]] \
  || fail "stable release reconstructed the deleted local release branch"
[[ -z "$(git ls-remote --heads origin release/v1.21.0)" ]] \
  || fail "stable release reconstructed the deleted remote release branch"

scripts/repo-workflow.sh release run \
  --confirm-tag v1.21.0 \
  --non-interactive \
  >"${tmp}/stable-tag-watch.out" 2>&1
assert_contains "${tmp}/stable-tag-watch.out" "annotated release tag created and pushed"
assert_contains "${tmp}/stable-tag-watch.out" "workflow watch was interrupted"
assert_contains "${tmp}/stable-tag-watch.out" "release paused safely before published asset verification"
[[ "$(git rev-parse 'v1.21.0^{}')" == "$(git rev-parse main)" ]] \
  || fail "stable tag does not point to synchronized main"
[[ "$(sed -n 's/^phase=//p' .git/erpnext-workflow/release-state)" == "stable-published" ]] \
  || fail "release run did not persist stable-published"

echo "repo workflow resumable release tests: all checks passed"
