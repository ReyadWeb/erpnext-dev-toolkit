#!/usr/bin/env bash
# Promote matching beta/RC metadata to a stable release transactionally.
#
# This command updates and validates release metadata. It never creates or
# pushes a Git tag.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ERPNEXT_RELEASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF_USAGE'
Usage:
  scripts/release-promote-stable.sh X.Y.Z "Release title"
EOF_USAGE
}

target_version="${1:-}"
release_title="${2:-}"

[[ -n "$target_version" && -n "$release_title" ]] || {
  usage
  exit 2
}

[[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "stable version must use X.Y.Z"

[[ "$release_title" != *$'\n'* && "$release_title" != *$'\r'* ]] \
  || fail "release title must be one line"

target_tag="v${target_version}"

cd "$ROOT_DIR"

[[ -d .git ]] || fail "stable promotion requires a Git working tree"

required_helpers=(
  scripts/release-version.sh
  scripts/release-update-metadata.sh
  scripts/generate-release-checksums.sh
  scripts/check-release-doc-alignment.sh
  scripts/check-release-artifact-consistency.sh
  scripts/validate-release.sh
)

for helper in "${required_helpers[@]}"; do
  [[ -x "$helper" ]] \
    || fail "required helper is missing or not executable: ${helper}"
done

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  fail "working tree must be clean before stable promotion"
fi

branch="$(git branch --show-current)"
[[ "$branch" == "release/v${target_version}" ]] \
  || fail "stable ${target_version} must be prepared on release/v${target_version}; current branch is ${branch}"

current_version="$(scripts/release-version.sh read)"
[[ "$current_version" == "${target_version}-beta."* ||
  "$current_version" == "${target_version}-rc."* ]] \
  || fail "current version ${current_version} is not a matching beta or RC for ${target_version}"

if git rev-parse -q --verify "refs/tags/${target_tag}" >/dev/null; then
  fail "local stable tag already exists: ${target_tag}"
fi

tracked_files=(
  VERSION
  erpnext-dev.sh
  README.md
  ROADMAP.md
  TESTING.md
  CHANGELOG.md
  RELEASE-MANIFEST.txt
  SHA256SUMS
)

backup_dir="$(mktemp -d /tmp/erpnext-dev-release-promote.XXXXXX)"
promotion_complete=0

restore_metadata() {
  local file

  if ((promotion_complete == 1)); then
    rm -rf "$backup_dir"
    return
  fi

  for file in "${tracked_files[@]}"; do
    if [[ -f "${backup_dir}/${file}" ]]; then
      mkdir -p "$(dirname "${ROOT_DIR}/${file}")"
      cp -a "${backup_dir}/${file}" "${ROOT_DIR}/${file}"
    fi
  done

  rm -rf "$backup_dir"
  echo "Restored pre-promotion release metadata." >&2
}

trap restore_metadata EXIT

for file in "${tracked_files[@]}"; do
  [[ -f "$file" ]] || fail "required release file is missing: ${file}"
  mkdir -p "${backup_dir}/$(dirname "$file")"
  cp -a "$file" "${backup_dir}/${file}"
done

scripts/release-update-metadata.sh "$target_version" "$release_title"
scripts/generate-release-checksums.sh

scripts/release-version.sh assert-runtime
scripts/check-release-doc-alignment.sh
scripts/check-release-artifact-consistency.sh
RELEASE_STRICT=1 scripts/validate-release.sh

promotion_complete=1
rm -rf "$backup_dir"
trap - EXIT

echo
echo "Stable metadata promotion completed successfully."
echo "Previous: ${current_version}"
echo "Current:  ${target_version}"
echo "Tag:      ${target_tag}"
echo "Branch:   ${branch}"
echo
echo "Review the stable changelog, commit, and merge the release PR to main."
echo "Do not create the stable tag from this release branch."
git status --short
