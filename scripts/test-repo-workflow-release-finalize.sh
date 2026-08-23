#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/release-test-env.sh
source "${ROOT_DIR}/scripts/release-test-env.sh"
release_test_env_reexec "$0" "$@"
WORKFLOW_SOURCE="${ROOT_DIR}/scripts/repo-workflow.sh"

fail_test() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "$expected" "$file" || {
    cat "$file" >&2
    fail_test "missing expected output: $expected"
  }
}

assert_not_contains() {
  local file="$1" unexpected="$2"
  if grep -Fq -- "$unexpected" "$file"; then
    cat "$file" >&2
    fail_test "unexpected output: $unexpected"
  fi
}

[[ -x "$WORKFLOW_SOURCE" ]] || fail_test "workflow script is missing"

tmp="$(mktemp -d /tmp/erpnext-repo-release-finalize-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="${tmp}/repo"
remote="${tmp}/remote.git"
bin="${tmp}/bin"
assets="${tmp}/assets"
bundle_build="${tmp}/bundle-build"
bundle_root="${bundle_build}/erpnext-dev-v1.2.3"

mkdir -p "$repo" "$bin" "$assets" "$bundle_root/scripts" "$bundle_root/docs"
git -c init.defaultBranch=main init --bare -q "$remote"
git init -q -b main "$repo"

cd "$repo"
git config user.name "Workflow Release Test"
git config user.email "workflow-release@example.invalid"
git remote add origin "$remote"

mkdir -p scripts docs
cp "$WORKFLOW_SOURCE" scripts/repo-workflow.sh
cp "${ROOT_DIR}/scripts/release-manifest-files.sh" scripts/release-manifest-files.sh
chmod +x scripts/repo-workflow.sh scripts/release-manifest-files.sh

cat >VERSION <<'TXT'
1.2.3
TXT

cat >erpnext-dev.sh <<'SH2'
#!/usr/bin/env bash
SCRIPT_VERSION="1.2.3"
case "${1:-version}" in
  version) echo "ERPNext Developer Toolkit v${SCRIPT_VERSION}" ;;
  *) exit 0 ;;
esac
SH2
chmod +x erpnext-dev.sh

cat >scripts/release-version.sh <<'SH2'
#!/usr/bin/env bash
set -Eeuo pipefail
version="$(cat VERSION)"
script_version="$(sed -nE 's/^SCRIPT_VERSION="([^"]+)".*/\1/p' erpnext-dev.sh | head -n1)"
case "${1:-read}" in
  read) echo "$version" ;;
  script) echo "$script_version" ;;
  channel) echo stable ;;
  tag) echo "v${version}" ;;
  assert-script)
    [[ "$version" == "$script_version" ]]
    echo "OK: VERSION matches SCRIPT_VERSION (${version})"
    ;;
  assert-tag)
    [[ "${2:-}" == "v${version}" ]]
    echo "OK: tag matches canonical version (v${version})"
    ;;
  channel-for-tag)
    [[ "${2:-}" == "v${version}" ]]
    echo stable
    ;;
  *) exit 2 ;;
esac
SH2
chmod +x scripts/release-version.sh

cat >scripts/build-info.sh <<'SH2'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  verify) echo "OK: BUILD-INFO.json verified (stable)" ;;
  *) exit 0 ;;
esac
SH2
chmod +x scripts/build-info.sh

cat >scripts/release-pretag-check.sh <<'SH2'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == "v1.2.3" ]]
echo "pretag fixture passed"
SH2
chmod +x scripts/release-pretag-check.sh

cat >scripts/assert-github-release-assets.sh <<'SH2'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == "v1.2.3" ]]
echo "assert-github-release-assets: v1.2.3 OK (6 assets)"
SH2
chmod +x scripts/assert-github-release-assets.sh

cat >RELEASE-MANIFEST.txt <<'TXT'
erpnext-dev.sh
VERSION
scripts/release-version.sh
scripts/build-info.sh
docs/erpnext-dev-signing-key.asc
TXT

cat >docs/erpnext-dev-signing-key.asc <<'TXT'
FAKE PUBLIC KEY FOR HERMETIC TEST
TXT

git add -A
git commit -m "Initial release fixture" >/dev/null
git push -u origin main >/dev/null 2>&1

scripts/repo-workflow.sh release pretag v1.2.3 >"${tmp}/pretag.out"
assert_contains "${tmp}/pretag.out" "strict pre-tag validation passed; no tag was created"

set +e
scripts/repo-workflow.sh release tag --confirm v1.2.4 >"${tmp}/wrong-tag.out" 2>&1
rc=$?
set -e
((rc != 0)) || fail_test "wrong tag confirmation unexpectedly succeeded"
assert_contains "${tmp}/wrong-tag.out" "does not match canonical tag v1.2.3"

scripts/repo-workflow.sh release tag --confirm v1.2.3 >"${tmp}/tag.out"
assert_contains "${tmp}/tag.out" "annotated release tag created and pushed"
[[ "$(git cat-file -t v1.2.3)" == "tag" ]] || fail_test "local release tag is not annotated"
head_commit="$(git rev-parse HEAD)"
remote_commit="$(git ls-remote origin 'refs/tags/v1.2.3^{}' | awk 'NR == 1 {print $1}')"
[[ "$remote_commit" == "$head_commit" ]] || fail_test "remote annotated tag does not peel to HEAD"

scripts/repo-workflow.sh release tag --confirm v1.2.3 >"${tmp}/duplicate.out" 2>&1
assert_contains "${tmp}/duplicate.out" "Release Tag Already Published"
assert_contains "${tmp}/duplicate.out" \
  "v1.2.3 already exists and points to the approved commit; no action required"

cp VERSION "$bundle_root/VERSION"
cp erpnext-dev.sh "$bundle_root/erpnext-dev.sh"
cp RELEASE-MANIFEST.txt "$bundle_root/RELEASE-MANIFEST.txt"
cp scripts/release-version.sh "$bundle_root/scripts/release-version.sh"
cp scripts/build-info.sh "$bundle_root/scripts/build-info.sh"
cp docs/erpnext-dev-signing-key.asc "$bundle_root/docs/erpnext-dev-signing-key.asc"
chmod +x "$bundle_root/erpnext-dev.sh" "$bundle_root/scripts/release-version.sh" "$bundle_root/scripts/build-info.sh"
cat >"$bundle_root/BUILD-INFO.json" <<'JSON'
{
  "archive": "erpnext-dev-v1.2.3.tar.gz",
  "built_at": "2026-07-27T00:00:00Z",
  "channel": "stable",
  "commit": "0000000000000000000000000000000000000000",
  "project_version": "1.2.3",
  "schema_version": 1,
  "tag": "v1.2.3",
  "tree_digest": "fixture"
}
JSON
(
  cd "$bundle_root"
  sha256sum erpnext-dev.sh VERSION scripts/release-version.sh scripts/build-info.sh docs/erpnext-dev-signing-key.asc >SHA256SUMS
)
echo 'FAKE DETACHED SIGNATURE' >"$bundle_root/SHA256SUMS.asc"

tar -C "$bundle_build" -czf "$assets/erpnext-dev-v1.2.3.tar.gz" erpnext-dev-v1.2.3
cp "$bundle_root/SHA256SUMS" "$assets/SHA256SUMS"
cp "$bundle_root/SHA256SUMS.asc" "$assets/SHA256SUMS.asc"
cp "$bundle_root/erpnext-dev.sh" "$assets/erpnext-dev.sh"
cp "$bundle_root/RELEASE-MANIFEST.txt" "$assets/RELEASE-MANIFEST.txt"
cp "$bundle_root/BUILD-INFO.json" "$assets/erpnext-dev-v1.2.3.BUILD-INFO.json"

cat >"${bin}/gpg" <<'SH2'
#!/usr/bin/env bash
set -Eeuo pipefail
if printf '%s\n' "$*" | grep -Fq -- '--with-colons' &&
  printf '%s\n' "$*" | grep -Fq -- '--fingerprint'; then
  echo 'fpr:::::::::BFC10C79427CF73496EA6F5A30BFD17DD559C8B6:'
fi
exit 0
SH2
chmod +x "${bin}/gpg"

cat >"${bin}/gh" <<'SH2'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}:${2:-}" in
  auth:status) exit 0 ;;
  run:list) echo "77" ;;
  run:view)
    case "$*" in
      *".headSha"*) echo "${GH_FAKE_HEAD_SHA}" ;;
      *".conclusion"*) echo "success" ;;
      *".url"*) echo "https://github.example.invalid/actions/runs/77" ;;
      *) echo "success" ;;
    esac
    ;;
  run:watch) echo "Release workflow completed successfully" ;;
  release:view)
    echo "v1.2.3|false|false|https://github.example.invalid/releases/tag/v1.2.3"
    ;;
  release:download)
    destination=""
    while (($# > 0)); do
      if [[ "$1" == "--dir" ]]; then
        shift
        destination="$1"
      fi
      shift
    done
    [[ -n "$destination" ]]
    mkdir -p "$destination"
    cp "${GH_FAKE_ASSET_DIR}"/* "$destination/"
    ;;
  *)
    echo "Unexpected fake gh invocation: $*" >&2
    exit 2
    ;;
esac
SH2
chmod +x "${bin}/gh"

export PATH="${bin}:${PATH}"
export GH_FAKE_HEAD_SHA="$head_commit"
export GH_FAKE_ASSET_DIR="$assets"

scripts/repo-workflow.sh release watch v1.2.3 --interval 1 --attempts 2 >"${tmp}/watch.out"
assert_contains "${tmp}/watch.out" "Protected Release Workflow Already Complete"
assert_contains "${tmp}/watch.out" "release workflow completed successfully"
assert_contains "${tmp}/watch.out" "release verify v1.2.3"

scripts/repo-workflow.sh release verify v1.2.3 >"${tmp}/verify.out"
assert_contains "${tmp}/verify.out" "published release v1.2.3 verified"
assert_contains "${tmp}/verify.out" "maintainer signing-key fingerprint verified"
assert_contains "${tmp}/verify.out" "release bundle checksums verified"

scripts/repo-workflow.sh release verify v1.2.3 >"${tmp}/verify-again.out"
assert_contains "${tmp}/verify-again.out" \
  "v1.2.3 was already verified at this exact commit; rechecking published assets safely"
assert_contains "${tmp}/verify-again.out" "published release v1.2.3 verified"

sed -i 's/^phase=stable-verified$/phase=stable-published/' \
  .git/erpnext-workflow/release-state
scripts/repo-workflow.sh release recover >"${tmp}/recover-published.out"
assert_contains "${tmp}/recover-published.out" \
  "no action taken before final published-asset verification"
assert_contains "${tmp}/recover-published.out" "release verify v1.2.3"
assert_not_contains "${tmp}/recover-published.out" "Published Release Verified"

echo "repo workflow release-finalization tests: all checks passed"
