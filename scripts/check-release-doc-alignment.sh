#!/usr/bin/env bash
# Verify current project identity without conflating it with the latest
# published release banner. Does not call the network.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f VERSION ]] || fail "VERSION is missing"
[[ -x scripts/release-version.sh ]] \
  || fail "scripts/release-version.sh is missing or not executable"

scripts/release-version.sh assert-runtime >/dev/null

project_version="$(scripts/release-version.sh read)"
project_tag="v${project_version}"

current_release=""
for file in README.md ROADMAP.md TESTING.md; do
  banner="$(sed -nE 's/^\*\*Current release:\*\*[[:space:]]+(v[^[:space:]·.]+(\.[^[:space:]·.]+)*)[[:space:]·.]*$/\1/p' "$file" | head -n 1)"
  [[ "$banner" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] \
    || fail "${file} must contain one valid Current release banner"
  if [[ -z "$current_release" ]]; then
    current_release="$banner"
  else
    [[ "$banner" == "$current_release" ]] \
      || fail "${file} Current release banner (${banner}) differs from ${current_release}"
  fi

  grep -qE "^\*\*Current project version:\*\* ${project_tag}([[:space:]]|$|\.|·)" "$file" \
    || fail "${file} Current project version must be ${project_tag}"
done

grep -q "Release Manifest ${project_tag}" RELEASE-MANIFEST.txt \
  || fail "RELEASE-MANIFEST.txt header must be ${project_tag}"

# Primary install path must resolve /releases/latest (never a hardcoded future tag).
grep -q 'releases/latest' README.md \
  || fail "README.md install path must resolve GitHub /releases/latest"
grep -q 'url_effective' README.md \
  || fail "README.md must document url_effective latest-tag resolution"

# Exact-pin examples describe the published release, not the development tree.
if grep -qE '^VERSION="v[0-9]+\.[0-9]+\.[0-9]+"' README.md; then
  grep -q "VERSION=\"${current_release}\"" README.md \
    || fail "README.md exact VERSION pin must match Current release ${current_release}"
fi

echo "OK: project ${project_tag}; published release banner ${current_release}"
