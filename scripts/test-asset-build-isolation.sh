#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "OK: $*"
}

# Managed service must use a watcher-free Procfile.
# shellcheck disable=SC2016
grep -q 'ensure_toolkit_runtime_procfile "\$bench_dir"' lib/service.sh \
  || fail "managed service does not generate Procfile.toolkit"
grep -q 'bench start --procfile Procfile.toolkit' lib/service.sh \
  || fail "managed systemd runtime does not use Procfile.toolkit"
pass "managed development service uses Procfile.toolkit"

grep -q '^ensure_erpnext_service_definition()' lib/service.sh \
  || fail "existing service migration helper is missing"
grep -q 'Updating ERPNext systemd service to watcher-free managed runtime' lib/service.sh \
  || fail "existing watcher-enabled service is not migrated automatically"
pass "existing installed service is migrated to watcher-free runtime"

# Procfile.toolkit must explicitly remove only the watch process.
grep -q "awk '!/\^\[\[:space:\]\]\*watch\[\[:space:\]\]\*:/'" lib/service.sh \
  || fail "Procfile.toolkit generation does not remove watch:"
pass "toolkit Procfile removes the Frappe watch process"

# Installation's temporary Bench runtime must also disable the watcher.
grep -q 'Starting temporary Bench services for Redis Queue (watcher disabled)' lib/install.sh \
  || fail "install-time temporary runtime does not declare watcher isolation"
grep -q 'bench start --procfile Procfile.toolkit >' lib/install.sh \
  || fail "install-time temporary runtime still uses the default watcher-enabled Procfile"
pass "install-time temporary runtime disables asset watcher"

# wait-ready must be observational only: the function body may not call rebuild.
wait_body="$(awk '/^wait_for_erpnext_ready\(\)/,/^}/' lib/service.sh)"
if grep -q 'try_rebuild_frontend_assets_once' <<<"$wait_body"; then
  fail "wait-ready still invokes automatic asset rebuild"
fi
if grep -q 'maintenance_build' <<<"$wait_body"; then
  fail "wait-ready still invokes bench build"
fi
pass "wait-ready is read-only"

# Explicit repair must keep Redis available while preventing the asset watcher
# from competing with the one-shot production build.
repair_body="$(awk '/^repair_frontend_assets\(\)/,/^}/' lib/service.sh)"

if grep -q '_asset_build_runtime_stop' <<<"$repair_body"; then
  fail "repair still stops the complete runtime, including redis_cache, before bench build"
fi

grep -q '_prepare_asset_build_runtime' <<<"$repair_body" \
  || fail "repair does not prepare a watcher-free runtime before building"

grep -q 'maintenance_build' <<<"$repair_body" \
  || fail "repair no longer performs the explicit isolated asset build"

grep -q 'wait_for_core_runtime_ready' <<<"$repair_body" \
  || fail "repair does not wait for runtime recovery before frontend verification"

pass "frontend repair keeps runtime dependencies available and waits after restart"

prepare_body="$(awk '/^_prepare_asset_build_runtime\(\)/,/^}/' lib/service.sh)"

grep -q 'ensure_erpnext_service_definition' <<<"$prepare_body" \
  || grep -q 'ensure_toolkit_runtime_procfile' <<<"$prepare_body" \
  || fail "asset-build preparation does not establish the watcher-free runtime"

grep -q 'systemctl.*restart' <<<"$prepare_body" \
  || fail "asset-build preparation does not restart the managed runtime"

grep -q 'wait_for_core_runtime_ready' <<<"$prepare_body" \
  || fail "asset-build preparation does not wait for core runtime readiness"

pass "watcher-free runtime is established before the isolated build"

# Installation must not turn a browser-layer failure into a false core-install failure.
install_tail="$(awk '/# Core installation success is separate from browser-asset readiness/,/post_install_validation_summary/' lib/install.sh)"
if grep -q 'fail "Post-install frontend settle failed' <<<"$install_tail"; then
  fail "post-install frontend failure still aborts the completed core install"
fi
grep -q 'Overall state: DEGRADED' <<<"$install_tail" \
  || fail "degraded frontend state is not reported explicitly"
pass "core install remains preserved when frontend readiness is degraded"

# Interactive local setup must treat static-IP choice and hostname mapping as
# separate concerns. Host mapping + HTTP verification must always sit between
# the stable-IP decision and the HTTPS offer.
guided_body="$(awk '/^local_guided_followups\(\)/,/^}/' lib/install.sh)"
stable_line="$(grep -n 'local_guided_stable_ip_checkpoint' <<<"$guided_body" | head -n1 | cut -d: -f1)"
host_line="$(grep -n 'local_guided_host_mapping_checkpoint' <<<"$guided_body" | head -n1 | cut -d: -f1)"
https_line="$(grep -n 'Set up trusted local HTTPS' <<<"$guided_body" | head -n1 | cut -d: -f1)"
[[ -n "$stable_line" && -n "$host_line" && -n "$https_line" ]] \
  || fail "guided local flow is missing stable-IP / host-mapping / HTTPS stages"
((stable_line < host_line && host_line < https_line)) \
  || fail "guided local flow does not verify hostname HTTP after IP choice and before HTTPS"
grep -q 'DHCP/current IP; update the HOST mapping if this IP changes' lib/install.sh \
  || fail "DHCP users are not warned that the HOST mapping may need refresh"
grep -q 'Guided HTTPS skipped because friendly-hostname HTTP was not confirmed' lib/install.sh \
  || fail "guided setup can still offer HTTPS without confirmed hostname HTTP"
pass "guided hostname checkpoint is independent of static-IP choice"

# Trusted mkcert setup must use a single HOST handoff confirmation and then
# automatically finish the VM-side certificate install/configure/verification.
mkcert_body="$(awk '/^run_trusted_mkcert_setup\(\)/,/^}/' lib/ssl.sh)"
grep -q 'Have you completed the HOST mkcert command and copied both certificate files to this VM?' <<<"$mkcert_body" \
  || fail "trusted mkcert setup lacks the explicit HOST handoff confirmation"
if grep -q 'Install the copied mkcert certificate and enable local HTTPS now?' <<<"$mkcert_body"; then
  fail "trusted mkcert setup still asks for a second redundant VM-side confirmation"
fi
install_line="$(grep -n '^  install_local_ssl_cert$' <<<"$mkcert_body" | head -n1 | cut -d: -f1)"
configure_line="$(grep -n '^  configure_local_ssl$' <<<"$mkcert_body" | head -n1 | cut -d: -f1)"
verify_line="$(grep -n 'verify_local_ssl' <<<"$mkcert_body" | tail -n1 | cut -d: -f1)"
[[ -n "$install_line" && -n "$configure_line" && -n "$verify_line" ]] \
  || fail "trusted mkcert setup is missing automatic install/configure/verify stages"
((install_line < configure_line && configure_line < verify_line)) \
  || fail "trusted mkcert VM-side automation is in the wrong order"
pass "trusted mkcert HOST handoff automatically completes VM HTTPS setup"

# Beta channel must be a first-class proving channel.
grep -q 'beta) printf.*beta' lib/security.sh \
  || fail "beta update channel is not implemented"

grep -q 'branches: \[ beta \]' .github/workflows/integration.yml \
  || fail "beta branch does not trigger real integration testing"

grep -q 'branches: \[ main, beta \]' .github/workflows/ci.yml \
  || fail "beta branch does not trigger fast release validation"

grep -q 'repair-frontend-assets' .github/workflows/integration.yml \
  || fail "beta integration does not execute the real frontend repair transaction"

grep -q 'ubuntu-24.04' .github/workflows/integration.yml \
  || fail "beta integration does not include Ubuntu 24.04"

grep -q 'ubuntu-26.04' .github/workflows/integration.yml \
  || fail "beta integration does not include Ubuntu 26.04"

pass "beta branch has fast CI plus real install and frontend-repair gates"

echo "test-asset-build-isolation: all checks passed"
