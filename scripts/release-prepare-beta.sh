#!/usr/bin/env bash
# Prepare a beta release transactionally.
#
# On any edit or validation failure, all release metadata files are restored to
# their exact pre-command state.
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
  scripts/release-prepare-beta.sh X.Y.Z-beta.N "Release title"

Example:
  scripts/release-prepare-beta.sh \
    1.20.0-beta.1 \
    "Release reliability foundation"
EOF_USAGE
}

target_version="${1:-}"
release_title="${2:-}"

[[ -n "$target_version" && -n "$release_title" ]] || {
  usage
  exit 2
}

[[ "$target_version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-beta\.([1-9][0-9]*)$ ]] \
  || fail "beta version must use X.Y.Z-beta.N with N greater than zero"

base_version="${BASH_REMATCH[1]}"
target_tag="v${target_version}"

cd "$ROOT_DIR"

[[ -d .git ]] || fail "release preparation requires a Git working tree"
[[ -x scripts/release-update-metadata.sh ]] \
  || fail "scripts/release-update-metadata.sh is missing or not executable"
[[ -x scripts/generate-release-checksums.sh ]] \
  || fail "scripts/generate-release-checksums.sh is missing or not executable"
[[ -x scripts/validate-release.sh ]] \
  || fail "scripts/validate-release.sh is missing or not executable"
[[ -x scripts/test-release-context-isolation.sh ]] \
  || fail "scripts/test-release-context-isolation.sh is missing or not executable"

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  fail "working tree must be clean before beta preparation"
fi

branch="$(git branch --show-current)"
[[ "$branch" == "release/v${base_version}" ]] \
  || fail "beta ${target_version} must be prepared on release/v${base_version}; current branch is ${branch}"

if git rev-parse -q --verify "refs/tags/${target_tag}" >/dev/null; then
  fail "local tag already exists: ${target_tag}"
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

backup_dir="$(mktemp -d /tmp/erpnext-dev-release-prepare.XXXXXX)"
committed=0

restore_metadata() {
  local file

  if ((committed == 1)); then
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
  echo "Restored pre-preparation release metadata." >&2
}

trap restore_metadata EXIT

for file in "${tracked_files[@]}"; do
  [[ -f "$file" ]] || fail "required release file is missing: ${file}"
  [[ ! -L "$file" ]] || fail "release file must not be a symbolic link: ${file}"
  mkdir -p "${backup_dir}/$(dirname "$file")"
  cp -a "$file" "${backup_dir}/${file}"
done

scripts/release-update-metadata.sh "$target_version" "$release_title"
scripts/generate-release-checksums.sh

scripts/release-version.sh assert-runtime
scripts/check-release-doc-alignment.sh
scripts/check-release-artifact-consistency.sh
ERPNEXT_RELEASE_TAG="$target_tag" \
  ERPNEXT_RELEASE_CHANNEL=beta \
  RELEASE_STRICT=1 \
  scripts/test-release-context-isolation.sh
printf 'OK: prerelease test-context dry-run passed (%s)\n' "$target_tag"
scripts/validate-release.sh

committed=1
rm -rf "$backup_dir"
trap - EXIT

echo
echo "Beta metadata prepared successfully."
echo "Version: ${target_version}"
echo "Tag:     ${target_tag}"
echo "Branch:  ${branch}"
echo
echo "Review and complete CHANGELOG validation notes before committing."
git status --short
