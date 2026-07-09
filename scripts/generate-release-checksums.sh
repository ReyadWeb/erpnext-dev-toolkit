#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

checksum_files=(
  erpnext-dev.sh
  lib/common.sh
  lib/config.sh
  lib/access.sh
  lib/frappe.sh
  lib/support.sh
  lib/backup.sh
  lib/ssl.sh
  lib/firewall.sh
  lib/apps.sh
  lib/health.sh
  lib/storage.sh
  lib/service.sh
  lib/status.sh
  lib/install.sh
  lib/ops.sh
  scripts/validate-release.sh
  scripts/run-shellcheck.sh
  RELEASE-MANIFEST.txt
)

tmp_file="$(mktemp "${ROOT_DIR}/SHA256SUMS.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

for file in "${checksum_files[@]}"; do
  [[ -f "$file" ]] || {
    echo "missing checksum target: $file" >&2
    exit 1
  }
  sha256sum "$file" >>"$tmp_file"
done

mv "$tmp_file" SHA256SUMS
echo "Wrote SHA256SUMS with ${#checksum_files[@]} entries:"
cat SHA256SUMS
