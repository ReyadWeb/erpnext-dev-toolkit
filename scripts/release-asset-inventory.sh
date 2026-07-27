#!/usr/bin/env bash
# Generate and verify the signed external release-asset inventory.
set -Eeuo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/release-asset-inventory.sh generate --tag TAG --output FILE [--root PATH]
  scripts/release-asset-inventory.sh verify --inventory FILE --asset-dir PATH [--require NAME]...
USAGE
}

mode="${1:-}"
shift || true
root="."
tag=""
output=""
inventory=""
asset_dir=""
requires=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --tag) tag="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --inventory) inventory="$2"; shift 2 ;;
    --asset-dir) asset_dir="$2"; shift 2 ;;
    --require) requires+=("$2"); shift 2 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done

safe_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "unsafe asset name: $1"
}

case "$mode" in
  generate)
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(beta|rc)\.[1-9][0-9]*|-unsigned)?$ ]] \
      || fail "invalid release tag: ${tag}"
    [[ -n "$output" ]] || fail "--output is required"
    root="$(cd "$root" && pwd)"
    archive="erpnext-dev-${tag}.tar.gz"
    sidecar="erpnext-dev-${tag}.BUILD-INFO.json"
    assets=(
      "$archive"
      "$sidecar"
      "SHA256SUMS"
      "erpnext-dev.sh"
      "RELEASE-MANIFEST.txt"
      "erpnext-dev-signing-key.asc"
      "bootstrap-verify.sh"
    )
    : >"$output"
    for name in "${assets[@]}"; do
      safe_name "$name"
      case "$name" in
        "$archive"|"$sidecar") path="${root}/dist/${name}" ;;
        erpnext-dev-signing-key.asc) path="${root}/docs/erpnext-dev-signing-key.asc" ;;
        bootstrap-verify.sh) path="${root}/scripts/bootstrap-verify.sh" ;;
        *) path="${root}/${name}" ;;
      esac
      [[ -f "$path" ]] || fail "required release asset is missing: ${path}"
      sha256sum "$path" | awk -v n="$name" '{print $1 "  " n}' >>"$output"
    done
    LC_ALL=C sort -k2,2 -o "$output" "$output"
    echo "OK: generated signed asset inventory ${output} (${#assets[@]} assets)"
    ;;
  verify)
    [[ -f "$inventory" ]] || fail "--inventory must name a file"
    [[ -d "$asset_dir" ]] || fail "--asset-dir must name a directory"
    python3 - "$inventory" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
seen=set()
for lineno,line in enumerate(p.read_text().splitlines(),1):
    m=re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)",line)
    if not m: raise SystemExit(f"FAIL: invalid inventory line {lineno}")
    if m.group(2) in seen: raise SystemExit(f"FAIL: duplicate inventory asset: {m.group(2)}")
    seen.add(m.group(2))
PY
    for name in "${requires[@]}"; do
      safe_name "$name"
      grep -Eq "^[0-9a-f]{64}  ${name//./\\.}$" "$inventory" \
        || fail "required asset is absent from inventory: ${name}"
    done
    (cd "$asset_dir" && sha256sum -c "$(cd "$(dirname "$inventory")" && pwd)/$(basename "$inventory")")
    echo "OK: external release assets match the signed inventory"
    ;;
  *) usage; exit 2 ;;
esac
