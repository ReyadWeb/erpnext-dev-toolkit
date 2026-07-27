#!/usr/bin/env bash
# Build the complete verified modular toolkit release bundle with generated
# immutable BUILD-INFO.json identity.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

required_helpers=(
  scripts/release-version.sh
  scripts/release-manifest-files.sh
  scripts/check-release-artifact-consistency.sh
  scripts/build-info.sh
)
for helper in "${required_helpers[@]}"; do
  [[ -x "$helper" ]] || fail "required helper is missing or not executable: ${helper}"
done

scripts/build-info.sh assert-source-clean >/dev/null
scripts/release-version.sh assert-runtime >/dev/null
scripts/check-release-artifact-consistency.sh >/dev/null

version="$(scripts/release-version.sh read)"
channel="$(scripts/release-version.sh channel)"
label="$(scripts/build-info.sh artifact-label)"
tag=""
if [[ "$channel" != "development" ]]; then
  tag="$(scripts/release-version.sh tag)"
fi
commit="$(git rev-parse HEAD 2>/dev/null || true)"
[[ "$commit" =~ ^[0-9a-fA-F]{40,64}$ ]] \
  || fail "release bundle construction requires an exact Git commit"

dist_dir="${ROOT_DIR}/dist"
stage_name="erpnext-dev-${label}"
stage_dir="${dist_dir}/${stage_name}"
archive_name="${stage_name}.tar.gz"
tarball="${dist_dir}/${archive_name}"
sidecar="${dist_dir}/${stage_name}.BUILD-INFO.json"

rm -rf "$stage_dir" "$tarball" "$sidecar"
mkdir -p "$stage_dir"

cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

manifest_count=0
while IFS= read -r entry; do
  mkdir -p "${stage_dir}/$(dirname "$entry")"
  cp -a "$entry" "${stage_dir}/${entry}"
  manifest_count=$((manifest_count + 1))
done < <(scripts/release-manifest-files.sh --include-checksum)

if [[ -f SHA256SUMS.asc ]]; then
  cp -a SHA256SUMS.asc "${stage_dir}/SHA256SUMS.asc"
  echo "included SHA256SUMS.asc (signed payload inventory)"
else
  echo "note: SHA256SUMS.asc not present; bundle payload is checksum-verifiable but unsigned"
fi

(
  cd "$stage_dir"
  sha256sum -c SHA256SUMS >/dev/null
) || fail "staged release payload does not match SHA256SUMS"

generate_args=(
  generate
  --source-root "$ROOT_DIR"
  --stage-root "$stage_dir"
  --archive "$archive_name"
  --channel "$channel"
  --commit "$commit"
)
[[ -z "$tag" ]] || generate_args+=(--tag "$tag")
scripts/build-info.sh "${generate_args[@]}" >/dev/null

verify_args=(
  verify
  --root "$stage_dir"
  --archive "$archive_name"
  --expected-channel "$channel"
  --expected-commit "$commit"
)
[[ -z "$tag" ]] || verify_args+=(--expected-tag "$tag")
scripts/build-info.sh "${verify_args[@]}" >/dev/null
cp -a "${stage_dir}/BUILD-INFO.json" "$sidecar"

tar -C "$dist_dir" -czf "$tarball" "$stage_name"

verify_root="$(mktemp -d /tmp/erpnext-dev-bundle-verify.XXXXXX)"
trap 'rm -rf "$verify_root"; cleanup' EXIT
tar -C "$verify_root" -xzf "$tarball"
extracted="${verify_root}/${stage_name}"
[[ -d "$extracted" ]] || fail "built archive is missing expected root: ${stage_name}"
extract_verify_args=(
  verify
  --root "$extracted"
  --archive "$archive_name"
  --expected-channel "$channel"
  --expected-commit "$commit"
)
[[ -z "$tag" ]] || extract_verify_args+=(--expected-tag "$tag")
scripts/build-info.sh "${extract_verify_args[@]}" >/dev/null
cmp -s "$sidecar" "${extracted}/BUILD-INFO.json" \
  || fail "BUILD-INFO sidecar differs from packaged metadata"

rm -rf "$verify_root"
cleanup
trap - EXIT

echo "Built ${tarball} (${manifest_count} tracked files + BUILD-INFO.json)"
echo "Build identity: ${sidecar}"
echo "Project version: ${version}"
echo "Channel: ${channel}"
echo "Commit: ${commit}"
sha256sum "$tarball"
