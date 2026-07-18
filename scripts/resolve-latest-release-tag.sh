#!/usr/bin/env bash
# Print the tag name that GitHub /releases/latest currently points at.
# Follows redirects and reads the final URL (no API token). Fails closed if
# resolution fails — this is what README install blocks should use so a
# SCRIPT_VERSION bump on main cannot 404 before signed assets are published.
#
# Usage:
#   scripts/resolve-latest-release-tag.sh
#   scripts/resolve-latest-release-tag.sh ReyadWeb/erpnext-dev-toolkit
set -euo pipefail

REPO="${1:-ReyadWeb/erpnext-dev-toolkit}"
url="https://github.com/${REPO}/releases/latest"

final_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "${url}")"
VERSION="$(sed -n 's|.*/tag/\([^[:space:]/]*\)$|\1|p' <<<"${final_url}")"

if [[ ! "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "Could not resolve latest release tag from ${url} (got: ${final_url:-empty})" >&2
  exit 1
fi

printf '%s\n' "${VERSION}"
