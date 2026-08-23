#!/usr/bin/env bash
# Assert a published GitHub Release has the assets the README install path needs.
#
# Usage:
#   scripts/assert-github-release-assets.sh v1.17.2
#   scripts/assert-github-release-assets.sh v1.17.2 --require-latest
#
# Intended to run at the end of .github/workflows/release.yml after
# `gh release create/upload`, so a tag that only has automatic Source code
# archives cannot be treated as a completed stable publish.
#
# Uses `gh api --jq` (no system jq package required).
set -Eeuo pipefail

tag="${1:-}"
require_latest=0
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-latest) require_latest=1 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -n "$tag" ]] || { echo "Usage: $0 <tag> [--require-latest]" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "gh CLI is required" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "a Git checkout is required to validate the tagged release contract" >&2
  exit 1
}

# The release contract is immutable: validate the annotated remote tag and read
# its manifest from the peeled commit.  Never use the current checkout's
# manifest, since that would retroactively change the contract of old releases.
remote_tag_ref="$(git ls-remote origin "refs/tags/${tag}" 2>/dev/null | awk 'NR == 1 {print $1}')"
remote_commit="$(git ls-remote origin "refs/tags/${tag}^{}" 2>/dev/null | awk 'NR == 1 {print $1}')"
[[ -n "$remote_tag_ref" && -n "$remote_commit" ]] || {
  echo "remote release tag is missing or not annotated: ${tag}" >&2
  exit 1
}
git rev-parse -q --verify "refs/tags/${tag}" >/dev/null || {
  echo "local annotated tag is unavailable: ${tag}" >&2
  exit 1
}
[[ "$(git cat-file -t "refs/tags/${tag}")" == "tag" ]] || {
  echo "local release tag is not annotated: ${tag}" >&2
  exit 1
}
[[ "$(git rev-parse "refs/tags/${tag}^{commit}")" == "$remote_commit" ]] || {
  echo "local and remote release tag commits differ: ${tag}" >&2
  exit 1
}

tag_root="$(mktemp -d /tmp/erpnext-release-tag.XXXXXX)"
tag_manifest="${tag_root}/RELEASE-MANIFEST.txt"
cleanup_tag_root() { rm -rf "$tag_root"; }
trap cleanup_tag_root EXIT
git archive "refs/tags/${tag}^{commit}" | tar -x -C "$tag_root"
git show "${tag}^{commit}:RELEASE-MANIFEST.txt" >"$tag_manifest" || {
  echo "tagged release manifest is missing: ${tag}" >&2
  exit 1
}
ERPNEXT_RELEASE_ROOT="$tag_root" \
  ERPNEXT_RELEASE_MANIFEST="$tag_manifest" \
  scripts/release-manifest-files.sh --include-checksum >/dev/null

repo="${GITHUB_REPOSITORY:-ReyadWeb/erpnext-dev-toolkit}"
stable=0
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && stable=1

draft="$(gh api "repos/${repo}/releases/tags/${tag}" --jq '.draft')"
prerelease="$(gh api "repos/${repo}/releases/tags/${tag}" --jq '.prerelease')"
asset_count="$(gh api "repos/${repo}/releases/tags/${tag}" --jq '.assets | length')"
assets="$(gh api "repos/${repo}/releases/tags/${tag}" --jq '.assets[].name' | sort)"

fail=0
note_fail() {
  echo "FAIL: $*" >&2
  fail=$((fail + 1))
}

[[ "$draft" == "false" ]] || note_fail "release ${tag} is still a draft"

required=(
  "erpnext-dev-${tag}.tar.gz"
  "erpnext-dev-${tag}.BUILD-INFO.json"
  "SHA256SUMS"
  "erpnext-dev.sh"
  "RELEASE-MANIFEST.txt"
  "RELEASE-ASSETS.sha256"
  "erpnext-dev-signing-key.asc"
  "bootstrap-verify.sh"
)
if grep -Fxq "install.sh" <(ERPNEXT_RELEASE_ROOT="$tag_root" \
  ERPNEXT_RELEASE_MANIFEST="$tag_manifest" \
  scripts/release-manifest-files.sh --include-checksum); then
  required+=("install.sh")
fi
if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[1-9][0-9]*)?$ ]]; then
  required+=("SHA256SUMS.asc" "RELEASE-ASSETS.sha256.asc")
fi
if (( stable == 1 )); then
  [[ "$prerelease" == "false" ]] || note_fail "stable tag ${tag} must not be marked prerelease"
fi

for name in "${required[@]}"; do
  if ! grep -Fxq "$name" <<<"$assets"; then
    note_fail "missing required asset: ${name}"
  else
    echo "OK: asset ${name}"
  fi
done

if (( require_latest == 1 && stable == 1 )); then
  latest="$(gh api "repos/${repo}/releases/latest" --jq '.tag_name')"
  if [[ "$latest" != "$tag" ]]; then
    note_fail "/releases/latest is '${latest}', expected '${tag}'"
  else
    echo "OK: /releases/latest -> ${tag}"
  fi
fi

if [[ ! "$asset_count" =~ ^[0-9]+$ ]] || (( asset_count != ${#required[@]} )); then
  note_fail "${asset_count:-0} custom asset(s); expected exactly ${#required[@]} from tagged contract"
else
  expected_assets="$(printf '%s\n' "${required[@]}" | LC_ALL=C sort)"
  if [[ "$assets" != "$expected_assets" ]]; then
    note_fail "published asset set differs from tagged release contract"
  fi
fi

if (( fail > 0 )); then
  echo "assert-github-release-assets: ${fail} failure(s) for ${tag}" >&2
  echo "Present assets:" >&2
  if [[ -n "$assets" ]]; then
    while IFS= read -r a; do printf '  %s\n' "$a" >&2; done <<<"$assets"
  else
    echo "  (none)" >&2
  fi
  exit 1
fi

echo "assert-github-release-assets: ${tag} OK (${asset_count} assets)"
