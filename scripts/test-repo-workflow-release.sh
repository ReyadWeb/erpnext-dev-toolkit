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

tmp="$(mktemp -d /tmp/erpnext-repo-workflow-release-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="${tmp}/repo"
remote="${tmp}/remote.git"
bin="${tmp}/bin"

mkdir -p "$repo" "$bin"
git -c init.defaultBranch=main init --bare -q "$remote"
git init -q -b main "$repo"

cd "$repo"
git config user.name "Workflow Release Test"
git config user.email "workflow-release@example.invalid"
git remote add origin "$remote"

mkdir -p scripts
cp "$WORKFLOW_SOURCE" scripts/repo-workflow.sh
chmod +x scripts/repo-workflow.sh

cat >VERSION <<'TXT'
1.20.0
TXT

cat >erpnext-dev.sh <<'SH'
#!/usr/bin/env bash
SCRIPT_VERSION="1.20.0"
SH
chmod +x erpnext-dev.sh

cat >scripts/release-version.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

version="$(cat VERSION)"
runtime="$(
  sed -nE 's/^SCRIPT_VERSION="([^"]+)".*/\1/p' erpnext-dev.sh \
    | head -n 1
)"

case "${1:-read}" in
  read) printf '%s\n' "$version" ;;
  script) printf '%s\n' "$runtime" ;;
  tag) printf 'v%s\n' "$version" ;;
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
  *) exit 2 ;;
esac
SH
chmod +x scripts/release-version.sh

git add -A
git commit -m "Initial release-status fixture" >/dev/null
git push -u origin main >/dev/null 2>&1
git switch -c feature/test >/dev/null 2>&1
git push -u origin feature/test >/dev/null 2>&1

scripts/repo-workflow.sh release status --offline >"${tmp}/feature-status.out"
assert_contains "${tmp}/feature-status.out" "Version                      1.20.0"
assert_contains "${tmp}/feature-status.out" "Channel                      stable"
assert_contains "${tmp}/feature-status.out" "Current branch               feature/test"
assert_contains "${tmp}/feature-status.out" "Expected branch              main"
assert_contains "${tmp}/feature-status.out" "Static readiness             blocked"
assert_contains "${tmp}/feature-status.out" \
  "Merge the current branch, then switch to synchronized main."

scripts/repo-workflow.sh release explain --offline >"${tmp}/feature-explain.out"
assert_contains "${tmp}/feature-explain.out" "Blocking conditions:"
assert_contains "${tmp}/feature-explain.out" \
  "current branch feature/test does not match expected main"

git switch main >/dev/null 2>&1
scripts/repo-workflow.sh release status --offline >"${tmp}/main-status.out"
assert_contains "${tmp}/main-status.out" \
  "Static readiness             offline static checks passed"
assert_contains "${tmp}/main-status.out" \
  "scripts/repo-workflow.sh release pretag v1.20.0 --offline"

git tag -a v1.20.0 -m "Existing local release"
scripts/repo-workflow.sh release status --offline >"${tmp}/local-tag.out"
assert_contains "${tmp}/local-tag.out" "Local tag                    exists"
assert_contains "${tmp}/local-tag.out" "matching local tag is ready to push"
assert_contains "${tmp}/local-tag.out" \
  "scripts/repo-workflow.sh release tag --confirm v1.20.0"
git tag -d v1.20.0 >/dev/null

cat >"${bin}/gh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}:${2:-}" in
  auth:status)
    exit 0
    ;;
  release:view)
    if [[ "${GH_FAKE_RELEASE_STATE:-missing}" == "published" ]]; then
      echo "https://github.example.invalid/example/repo/releases/tag/v1.20.0|false|false|2026-07-26T00:00:00Z"
      exit 0
    fi
    exit 1
    ;;
  *)
    echo "Unexpected fake gh invocation: $*" >&2
    exit 2
    ;;
esac
SH
chmod +x "${bin}/gh"
export PATH="${bin}:${PATH}"

export GH_FAKE_RELEASE_STATE=missing
scripts/repo-workflow.sh release status >"${tmp}/online-missing.out"
assert_contains "${tmp}/online-missing.out" "Remote refresh               updated"
assert_contains "${tmp}/online-missing.out" "Remote tag                   missing"
assert_contains "${tmp}/online-missing.out" "GitHub release               missing"
assert_contains "${tmp}/online-missing.out" "Static readiness             static checks passed"

git tag -a v1.20.0 -m "Published release"
git push origin v1.20.0 >/dev/null 2>&1
export GH_FAKE_RELEASE_STATE=published
scripts/repo-workflow.sh release status >"${tmp}/published.out"
assert_contains "${tmp}/published.out" "Remote tag                   exists"
assert_contains "${tmp}/published.out" "GitHub release               published;"
assert_contains "${tmp}/published.out" "Static readiness             complete"
assert_contains "${tmp}/published.out" \
  "scripts/repo-workflow.sh release verify v1.20.0"

git tag -d v1.20.0 >/dev/null
git push origin :refs/tags/v1.20.0 >/dev/null 2>&1
export GH_FAKE_RELEASE_STATE=missing

cat >VERSION <<'TXT'
1.21.0-beta.1
TXT
sed -i 's/1.20.0/1.21.0-beta.1/' erpnext-dev.sh
git add VERSION erpnext-dev.sh
git commit -m "Prepare beta fixture" >/dev/null
git switch -c release/v1.21.0 >/dev/null 2>&1
git push -u origin release/v1.21.0 >/dev/null 2>&1

scripts/repo-workflow.sh release status --offline >"${tmp}/beta.out"
assert_contains "${tmp}/beta.out" "Channel                      beta"
assert_contains "${tmp}/beta.out" "Expected tag                 v1.21.0-beta.1"
assert_contains "${tmp}/beta.out" "Expected branch              release/v1.21.0"
assert_contains "${tmp}/beta.out" \
  "Static readiness             offline static checks passed"

echo "dirty" >>erpnext-dev.sh
scripts/repo-workflow.sh release explain --offline >"${tmp}/dirty.out"
assert_contains "${tmp}/dirty.out" "working tree is not clean"
assert_contains "${tmp}/dirty.out" \
  "Publish or commit the current changes before release validation."
git restore erpnext-dev.sh

set +e
scripts/repo-workflow.sh release status --unknown >"${tmp}/unknown.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail "unknown release status option unexpectedly succeeded"
assert_contains "${tmp}/unknown.out" "unknown release status option: --unknown"

echo "repo workflow release-status tests: all checks passed"
