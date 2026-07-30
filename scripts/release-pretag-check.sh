#!/usr/bin/env bash
# Validate every local condition required immediately before creating a tag.
#
# Stable tags are allowed only from synchronized main. Prerelease tags are
# allowed from synchronized main after the reviewed release PR merges, or from
# the legacy beta and matching release/feature branches. This command never
# creates or pushes a tag.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ERPNEXT_RELEASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REMOTE_CHECK="${ERPNEXT_RELEASE_REMOTE_CHECK:-1}"
REMOTE_NAME="${ERPNEXT_RELEASE_REMOTE_NAME:-origin}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF_USAGE'
Usage:
  scripts/release-pretag-check.sh [vX.Y.Z[-prerelease]] [--offline]

Options:
  --offline  Skip remote tag and branch-synchronization checks.
EOF_USAGE
}

target_tag=""
offline=0

for argument in "$@"; do
  case "$argument" in
    --offline)
      offline=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    v*)
      [[ -z "$target_tag" ]] || fail "only one tag may be supplied"
      target_tag="$argument"
      ;;
    *)
      fail "unknown argument: ${argument}"
      ;;
  esac
done

cd "$ROOT_DIR"

[[ -d .git ]] || fail "pre-tag validation requires a Git working tree"

required_helpers=(
  scripts/release-version.sh
  scripts/check-release-artifact-consistency.sh
  scripts/validate-release.sh
  scripts/build-release-bundle.sh
  scripts/build-info.sh
)

for helper in "${required_helpers[@]}"; do
  [[ -x "$helper" ]] \
    || fail "required helper is missing or not executable: ${helper}"
done

target_tag="${target_tag:-$(scripts/release-version.sh tag)}"
canonical_version="$(scripts/release-version.sh read)"
base_version="${canonical_version%%-*}"
series_version="${base_version%.*}"
channel="$(scripts/release-version.sh channel-for-tag "$target_tag")"

scripts/release-version.sh assert-runtime
scripts/release-version.sh assert-tag "$target_tag"

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  fail "working tree must be clean before pre-tag validation"
fi

branch="$(git branch --show-current)"
[[ -n "$branch" ]] || fail "pre-tag validation cannot run from detached HEAD"

if git rev-parse -q --verify "refs/tags/${target_tag}" >/dev/null; then
  fail "local tag already exists: ${target_tag}"
fi

case "$channel" in
  stable)
    [[ "$branch" == "main" ]] \
      || fail "stable tag ${target_tag} must be created from main; current branch is ${branch}"
    ;;
  *)
    case "$branch" in
      "main" | \
        "beta" | \
        "release/v${base_version}" | \
        "feature/v${base_version}-"* | \
        "feature/v${series_version}-"*) ;;
      *)
        fail "prerelease tag ${target_tag} is not on main, beta, or a matching release/feature branch: ${branch}"
        ;;
    esac
    ;;
esac

if ((offline == 1)); then
  REMOTE_CHECK=0
fi

if [[ "$REMOTE_CHECK" == "1" ]]; then
  git remote get-url "$REMOTE_NAME" >/dev/null 2>&1 \
    || fail "Git remote is unavailable: ${REMOTE_NAME}"

  if git ls-remote --exit-code --tags "$REMOTE_NAME" \
    "refs/tags/${target_tag}" >/dev/null 2>&1; then
    fail "remote tag already exists: ${target_tag}"
  fi

  git fetch --quiet "$REMOTE_NAME" \
    "+refs/heads/${branch}:refs/remotes/${REMOTE_NAME}/${branch}" \
    || fail "could not fetch ${REMOTE_NAME}/${branch}"

  remote_ref="refs/remotes/${REMOTE_NAME}/${branch}"
  git show-ref --verify --quiet "$remote_ref" \
    || fail "remote branch reference is missing: ${REMOTE_NAME}/${branch}"

  local_head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse "$remote_ref")"

  [[ "$local_head" == "$remote_head" ]] \
    || fail "local ${branch} is not synchronized with ${REMOTE_NAME}/${branch}"
else
  echo "NOTE: remote tag and branch-synchronization checks skipped"
fi

validation_phase=""
if [[ "$channel" == "stable" ]]; then
  validation_phase="stable-pretag"
fi

ERPNEXT_RELEASE_PHASE="$validation_phase" \
  ERPNEXT_RELEASE_TAG="$target_tag" \
  ERPNEXT_RELEASE_CHANNEL="$channel" \
  RELEASE_STRICT=1 \
  scripts/validate-release.sh
scripts/check-release-artifact-consistency.sh

rm -rf dist
ERPNEXT_RELEASE_PHASE="$validation_phase" \
  ERPNEXT_RELEASE_TAG="$target_tag" \
  ERPNEXT_RELEASE_CHANNEL="$channel" \
  scripts/build-release-bundle.sh

bundle="dist/erpnext-dev-${target_tag}.tar.gz"
[[ -f "$bundle" ]] || fail "expected release bundle was not created: ${bundle}"

extract_root="$(mktemp -d /tmp/erpnext-dev-pretag.XXXXXX)"
trap 'rm -rf "$extract_root"' EXIT

tar -C "$extract_root" -xzf "$bundle"
bundle_root="${extract_root}/erpnext-dev-${target_tag}"

[[ -d "$bundle_root" ]] \
  || fail "release bundle root is missing: erpnext-dev-${target_tag}"

(
  cd "$bundle_root"

  sha256sum -c SHA256SUMS
  scripts/release-version.sh assert-runtime
  scripts/release-version.sh assert-tag "$target_tag"
  scripts/build-info.sh verify \
    --root . \
    --archive "erpnext-dev-${target_tag}.tar.gz" \
    --expected-tag "$target_tag" \
    --expected-channel "$channel" \
    --expected-commit "$(git -C "$ROOT_DIR" rev-parse HEAD)" >/dev/null

  version_output="$(./erpnext-dev.sh version)"
  [[ "$version_output" == *"ERPNext Developer Toolkit v${canonical_version}"* ]] \
    || fail "bundle runtime version output does not match ${canonical_version}"

  verify_output="$(mktemp /tmp/erpnext-dev-pretag-verify.XXXXXX)"
  trap 'rm -f "$verify_output"' EXIT

  ./erpnext-dev.sh verify-toolkit >"$verify_output" 2>&1 \
    || fail "bundle verify-toolkit failed"

  grep -qi "active match.*OK" "$verify_output" \
    || fail "bundle verify-toolkit did not report Active match OK"

  rm -f "$verify_output"
  trap - EXIT
)

rm -rf "$extract_root"
trap - EXIT

[[ -z "$(git status --porcelain)" ]] \
  || fail "pre-tag validation changed tracked repository files"

echo
echo "Pre-tag validation passed."
echo "Tag:     ${target_tag}"
echo "Version: ${canonical_version}"
echo "Channel: ${channel}"
echo "Branch:  ${branch}"
echo "Commit:  $(git rev-parse HEAD)"
echo "Bundle:  ${bundle}"
echo
echo "The tag has not been created."
