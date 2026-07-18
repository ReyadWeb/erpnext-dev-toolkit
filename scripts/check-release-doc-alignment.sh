#!/usr/bin/env bash
# Fail if in-repo version banners disagree with SCRIPT_VERSION.
# Does not call the network (safe during the release-PR → publish window).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

script_version="$(grep -E '^SCRIPT_VERSION=' erpnext-dev.sh | head -n1 | cut -d'"' -f2)"
[[ -n "${script_version}" ]] || fail "could not read SCRIPT_VERSION"
tag="v${script_version}"

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

# Exact-pin example (reproducible installs) should match SCRIPT_VERSION when present.
if grep -qE '^VERSION="v[0-9]+\.[0-9]+\.[0-9]+"' README.md; then
  grep -q "VERSION=\"${tag}\"" README.md \
    || fail "README.md VERSION=\"...\" pin example must be ${tag} when present"
fi

echo "OK: in-repo release docs aligned to ${tag}"
