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
  "SHA256SUMS"
  "erpnext-dev.sh"
  "RELEASE-MANIFEST.txt"
)
if (( stable == 1 )); then
  required+=("SHA256SUMS.asc")
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

if [[ ! "$asset_count" =~ ^[0-9]+$ ]] || (( asset_count < ${#required[@]} )); then
  note_fail "only ${asset_count:-0} custom asset(s); expected at least ${#required[@]}"
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
