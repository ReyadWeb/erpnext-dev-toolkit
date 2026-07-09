#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed" >&2
  exit 1
fi

targets=(
  lib/common.sh
  scripts/validate-release.sh
  scripts/generate-release-checksums.sh
  scripts/run-shellcheck.sh
)

for target in "${targets[@]}"; do
  [[ -f "$target" ]] || {
    echo "missing shellcheck target: $target" >&2
    exit 1
  }
  shellcheck -x -S error "$target"
done

echo "shellcheck passed for ${#targets[@]} file(s)"
