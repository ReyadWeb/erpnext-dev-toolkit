#!/usr/bin/env bash
# Lint toolkit shell sources with shellcheck.
# Supports SKIP_SHELLCHECK=1 (CI runs this once, then validate-release skips).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${SKIP_SHELLCHECK:-0}" == "1" ]]; then
  echo "shellcheck skipped (SKIP_SHELLCHECK=1)"
  exit 0
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed" >&2
  exit 1
fi

# Note: erpnext-dev.sh is intentionally omitted. `shellcheck -x` on the
# entrypoint re-analyzes every sourced module and hung CI until cancel
# (~2+ minutes on erpnext-dev.sh alone). Modules/scripts below cover the
# real logic; module consistency + bash -n cover the entrypoint wiring.
targets=(
  lib/common.sh
  lib/ui.sh
  lib/profile.sh
  lib/config.sh
  lib/access.sh
  lib/local_ip.sh
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
  lib/docker.sh
  lib/engine.sh
  lib/install.sh
  lib/ops.sh
  lib/dashboard.sh
  lib/healing.sh
  lib/menu.sh
  lib/security.sh
  lib/update.sh
  scripts/validate-release.sh
  scripts/repo-workflow.sh
  scripts/test-repo-workflow.sh
  scripts/test-repo-workflow-work.sh
  scripts/test-repo-workflow-pr.sh
  scripts/test-repo-workflow-release.sh
  scripts/test-repo-workflow-release-transaction.sh
  scripts/test-repo-workflow-release-finalize.sh
  scripts/test-repo-workflow-release-run.sh
  scripts/release-version.sh
  scripts/test-release-version.sh
  scripts/build-info.sh
  scripts/test-build-info.sh
  scripts/release-test-env.sh
  scripts/test-release-test-env.sh
  scripts/test-release-context-isolation.sh
  scripts/check-release-state-invariants.sh
  scripts/test-release-state-invariants.sh
  scripts/release-manifest-files.sh
  scripts/check-release-artifact-consistency.sh
  scripts/test-release-manifest.sh
  scripts/test-release-artifact-consistency.sh
  scripts/release-update-metadata.sh
  scripts/release-prepare-beta.sh
  scripts/test-release-metadata.sh
  scripts/test-release-prepare-beta.sh
  scripts/release-promote-stable.sh
  scripts/release-pretag-check.sh
  scripts/test-release-promote-stable.sh
  scripts/test-release-pretag-check.sh
  scripts/generate-release-checksums.sh
  scripts/run-shellcheck.sh
  scripts/check-module-consistency.sh
  scripts/build-release-bundle.sh
  scripts/test-atomic-update.sh
  scripts/test-staged-signature.sh
  scripts/test-host-os-output.sh
  scripts/test-install-self-path.sh
  scripts/test-legacy-modular-bootstrap.sh
  scripts/test-engine-select.sh
  scripts/test-docker-reliability.sh
  scripts/test-ui-render.sh
  scripts/test-dashboard-render.sh
  scripts/test-static-asset-probe.sh
  scripts/test-reinstall-isolation.sh
  scripts/test-asset-build-isolation.sh
  scripts/test-health-env-parser.sh
  scripts/test-offvm-host-key.sh
  scripts/test-risky-shell-patterns.sh
  scripts/test-adversarial-inputs.sh
  scripts/test-update-channel.sh
  scripts/test-local-ip.sh
  scripts/test-healing.sh
  scripts/release-signing-policy.sh
  scripts/assert-github-release-assets.sh
)

# Per-file timeout so a single hung analysis cannot block the release job forever.
SHELLCHECK_FILE_TIMEOUT="${SHELLCHECK_FILE_TIMEOUT:-180}"

run_sc() {
  local target="$1"
  if command -v timeout >/dev/null 2>&1; then
    timeout "${SHELLCHECK_FILE_TIMEOUT}" shellcheck -x -S warning "$target"
  else
    shellcheck -x -S warning "$target"
  fi
}

failed=0
for target in "${targets[@]}"; do
  [[ -f "$target" ]] || {
    echo "missing shellcheck target: $target" >&2
    exit 1
  }
  echo "shellcheck: ${target}"
  if ! run_sc "$target"; then
    echo "shellcheck FAILED: ${target}" >&2
    failed=1
  fi
done

if ((failed != 0)); then
  echo "shellcheck reported failures" >&2
  exit 1
fi

echo "shellcheck passed for ${#targets[@]} file(s)"
