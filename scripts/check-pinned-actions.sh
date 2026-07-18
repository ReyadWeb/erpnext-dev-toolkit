#!/usr/bin/env bash
# Fail if any workflow uses a floating Actions tag/branch instead of a commit SHA.
# Allowed: uses: ./.github/workflows/... and uses: owner/name@<40-hex> (# comment ok).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF_DIR="${ROOT}/.github/workflows"

if [[ ! -d "${WF_DIR}" ]]; then
  echo "FAIL: missing ${WF_DIR}" >&2
  exit 1
fi

bad=0
while IFS= read -r line; do
  file="${line%%:*}"
  rest="${line#*:}"
  lineno="${rest%%:*}"
  text="${rest#*:}"
  # Strip leading whitespace / list marker noise for matching.
  uses="$(sed -E 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*//' <<<"${text}")"
  uses="${uses%%#*}"
  uses="$(sed -E 's/[[:space:]]+$//' <<<"${uses}")"
  uses="${uses%\"}"
  uses="${uses#\"}"
  uses="${uses%\'}"
  uses="${uses#\'}"

  if [[ "${uses}" == ./* ]]; then
    continue
  fi
  if [[ "${uses}" =~ @[0-9a-fA-F]{40}$ ]]; then
    continue
  fi
  echo "FAIL: unpinned Action at ${file}:${lineno}: ${uses}" >&2
  bad=1
done < <(grep -RInE '^[[:space:]]*-?[[:space:]]*uses:' "${WF_DIR}" || true)

if [[ "${bad}" -ne 0 ]]; then
  echo "Pin third-party Actions to a full commit SHA (with optional # vX.Y.Z comment)." >&2
  exit 1
fi

echo "OK: all third-party Actions are pinned to commit SHAs"
