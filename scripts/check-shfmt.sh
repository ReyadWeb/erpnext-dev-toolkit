#!/usr/bin/env bash
# Scoped shfmt gate for hermetic test scripts.
# Full-tree reformatting of lib/ is a separate follow-up (large churn).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

SHFMT_FLAGS=(-i 2 -ci -bn)

if ! command -v shfmt >/dev/null 2>&1; then
  echo "FAIL: shfmt not on PATH (install mvdan/sh)" >&2
  exit 1
fi

mapfile -t targets < <(compgen -G 'scripts/test-*.sh' || true)
if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "FAIL: no scripts/test-*.sh files found" >&2
  exit 1
fi

if ! shfmt -d "${SHFMT_FLAGS[@]}" "${targets[@]}"; then
  echo "FAIL: shfmt drift in hermetic tests. Run:" >&2
  echo "  shfmt -w ${SHFMT_FLAGS[*]} scripts/test-*.sh" >&2
  exit 1
fi

echo "OK: shfmt clean for ${#targets[@]} hermetic test scripts"
