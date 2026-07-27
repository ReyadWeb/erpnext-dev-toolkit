#!/usr/bin/env bash
# Fail if in-repo release surfaces disagree with canonical project identity.
# Does not call the network (safe during the release-PR → publish window).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f VERSION ]] || fail "VERSION is missing"

[[ -x scripts/release-version.sh ]] \
  || fail "scripts/release-version.sh is missing or not executable"

scripts/release-version.sh assert-runtime >/dev/null

project_version="$(scripts/release-version.sh read)"
tag="$(scripts/release-version.sh tag)"

grep -qE "^\*\*Current release:\*\* ${tag}( |$|\.|·)" README.md \
  || fail "README.md Current release banner must be ${tag}"
grep -qE "^\*\*Current release:\*\* ${tag}( |$|\.|·)" ROADMAP.md \
  || fail "ROADMAP.md Current release banner must be ${tag}"
grep -qE "^\*\*Current release:\*\* ${tag}( |$|\.|·)" TESTING.md \
  || fail "TESTING.md Current release banner must be ${tag}"
grep -q "Release Manifest ${tag}" RELEASE-MANIFEST.txt \
  || fail "RELEASE-MANIFEST.txt header must be ${tag}"

# Primary install path must resolve /releases/latest (never a hardcoded future tag).
grep -q 'releases/latest' README.md \
  || fail "README.md install path must resolve GitHub /releases/latest"
grep -q 'url_effective' README.md \
  || fail "README.md must document url_effective latest-tag resolution"

# Exact-pin example remains aligned with the current release surface.
if grep -qE '^VERSION="v[0-9]+\.[0-9]+\.[0-9]+"' README.md; then
  grep -q "VERSION=\"${tag}\"" README.md \
    || fail "README.md VERSION=\"...\" pin example must be ${tag} when present"
fi

echo "OK: in-repo release docs aligned to ${tag}"
