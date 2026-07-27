#!/usr/bin/env bash
# Build the complete verified modular toolkit release bundle.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x scripts/release-version.sh ]] \
  || fail "scripts/release-version.sh is missing or not executable"
[[ -x scripts/release-manifest-files.sh ]] \
  || fail "scripts/release-manifest-files.sh is missing or not executable"
[[ -x scripts/check-release-artifact-consistency.sh ]] \
  || fail "scripts/check-release-artifact-consistency.sh is missing or not executable"

scripts/release-version.sh assert-runtime >/dev/null
scripts/check-release-artifact-consistency.sh >/dev/null

tag="$(scripts/release-version.sh tag)"
dist_dir="${ROOT_DIR}/dist"
stage_name="erpnext-dev-${tag}"
stage_dir="${dist_dir}/${stage_name}"
tarball="${dist_dir}/${stage_name}.tar.gz"

rm -rf "$stage_dir" "$tarball"
mkdir -p "$stage_dir"

manifest_count=0

while IFS= read -r entry; do
  mkdir -p "${stage_dir}/$(dirname "$entry")"
  cp -a "$entry" "${stage_dir}/${entry}"
  manifest_count=$((manifest_count + 1))
done < <(scripts/release-manifest-files.sh --include-checksum)

if [[ -f SHA256SUMS.asc ]]; then
  cp -a SHA256SUMS.asc "${stage_dir}/SHA256SUMS.asc"
  echo "included SHA256SUMS.asc (signed bundle)"
else
  echo "note: SHA256SUMS.asc not present; bundle is checksum-verifiable but unsigned"
fi

tar -C "$dist_dir" -czf "$tarball" "$stage_name"
rm -rf "$stage_dir"

echo "Built ${tarball} (${manifest_count} tracked files)"
sha256sum "$tarball"
