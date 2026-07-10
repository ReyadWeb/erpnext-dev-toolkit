#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed" >&2
  exit 1
fi

targets=(
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
  lib/security.sh
  lib/update.sh
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
