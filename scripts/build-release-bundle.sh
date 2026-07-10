#!/usr/bin/env bash
# Build a single, self-contained release tarball for the modular toolkit.
#
# The toolkit is no longer one file: erpnext-dev.sh sources lib/*.sh at runtime.
# Downloading only erpnext-dev.sh (as the old monolithic quickstart did) leaves
# every module missing and the script aborts. This script packages the complete
# verified tree — everything listed in RELEASE-MANIFEST.txt, plus the detached
# signature when present — into erpnext-dev-vX.Y.Z.tar.gz.
#
# End users extract it and run `sha256sum -c SHA256SUMS` (integrity) and/or
# `erpnext-dev verify-signature` (authenticity via the bundled key) from the
# extracted directory. The signed SHA256SUMS inside the bundle anchors trust for
# every packaged file.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

version="$(grep -E '^SCRIPT_VERSION=' erpnext-dev.sh | head -n 1 | cut -d'"' -f2)"
[[ -n "$version" ]] || { echo "could not read SCRIPT_VERSION from erpnext-dev.sh" >&2; exit 1; }
tag="v${version}"

dist_dir="${ROOT_DIR}/dist"
stage_name="erpnext-dev-${tag}"
stage_dir="${dist_dir}/${stage_name}"
tarball="${dist_dir}/${stage_name}.tar.gz"

rm -rf "$stage_dir" "$tarball"
mkdir -p "$stage_dir"

# Copy every manifest entry into the staging tree, preserving directory layout.
manifest_count=0
while IFS= read -r entry || [[ -n "$entry" ]]; do
  entry="${entry%%#*}"
  entry="$(printf '%s' "$entry" | tr -d '[:space:]')"
  [[ -n "$entry" ]] || continue
  [[ -e "$entry" ]] || { echo "manifest entry missing: $entry" >&2; exit 1; }
  mkdir -p "${stage_dir}/$(dirname "$entry")"
  cp -a "$entry" "${stage_dir}/${entry}"
  manifest_count=$((manifest_count + 1))
done < RELEASE-MANIFEST.txt

# Include the detached signature when it has already been produced, so
# `verify-signature` works offline from the extracted bundle.
if [[ -f SHA256SUMS.asc ]]; then
  cp -a SHA256SUMS.asc "${stage_dir}/SHA256SUMS.asc"
  echo "included SHA256SUMS.asc (signed bundle)"
else
  echo "note: SHA256SUMS.asc not present; bundle will be checksum-verifiable but unsigned"
fi

tar -C "$dist_dir" -czf "$tarball" "$stage_name"
rm -rf "$stage_dir"

echo "Built ${tarball} (${manifest_count} tracked files)"
sha256sum "$tarball"
