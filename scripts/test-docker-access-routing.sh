#!/usr/bin/env bash
# Regression tests for Docker access / HTTPS / credentials / firewall / production optional-app image routing (v1.19.21-beta.1).
# Hermetic: no Docker daemon, sudo, network, nginx, or UFW changes.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
pass() { echo "OK: $*"; }
fail_case() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  [[ "$expected" == "$actual" ]] && pass "$label: $actual" || fail_case "$label: expected '$expected', got '$actual'"
}
assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" == *"$needle"* ]] && pass "$label" || fail_case "$label: missing '$needle' in '$haystack'"
}
assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" != *"$needle"* ]] && pass "$label" || fail_case "$label: unexpectedly found '$needle'"
}

TMP_ROOT="$(mktemp -d /tmp/erpnext-dev-docker-routing.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export ERPNEXT_DEV_ENTRY_SCRIPT="${ROOT_DIR}/erpnext-dev.sh"
SITE_NAME="erp.test"
SITE_NAME_SOURCE="test"
SITE_NAME_ENV_PROVIDED=1
PRODUCTION_DOMAIN="erp.example.com"
DEPLOYMENT_MODE="development"
DEPLOYMENT_ENGINE="docker"
DEPLOYMENT_ENGINE_ENV_PROVIDED=1
DOCKER_MODE="development"
DOCKER_MODE_ENV_PROVIDED=1
DOCKER_WORKDIR="${TMP_ROOT}/docker"
DOCKER_PROJECT_NAME="erpnext-dev"
DOCKER_PUBLISH_PORT="8080"
DOCKER_ERPNEXT_IMAGE="frappe/erpnext:v16.26.2"
DOCKER_CREDENTIALS_FILE="${DOCKER_WORKDIR}/credentials.txt"
DOCKER_HTTPS_STATE_FILE="${DOCKER_WORKDIR}/https.env"
DOCKER_CF_ORIGIN_DIR="${DOCKER_WORKDIR}/cloudflare-origin"
DOCKER_LOCAL_FIREWALL_SCRIPT="${TMP_ROOT}/runtime/docker-local-firewall.sh"
DOCKER_LOCAL_FIREWALL_SERVICE_PATH="${TMP_ROOT}/systemd/erpnext-dev-docker-firewall.service"
SSL_CERT_DIR="${TMP_ROOT}/ssl"
SSL_NGINX_CONF_DIR="${TMP_ROOT}/nginx"
SSL_REDIRECT_HTTP="true"
INSTALLER_CANONICAL_PATH="${ROOT_DIR}/erpnext-dev.sh"
CONFIG_FILE="${TMP_ROOT}/config.env"
LEGACY_CONFIG_FILE="${TMP_ROOT}/legacy.env"
FRAPPE_USER="frappe"
BENCH_PARENT="/home/frappe/frappe"
BENCH_NAME="frappe-bench"
BENCH_DIR="/home/frappe/frappe/frappe-bench"
ERPNEXT_SERVICE_NAME="erpnext-dev.service"
HOST_OS="linux"
HOST_OS_ENV_PROVIDED=1
ASSUME_YES=1
LOG_FILE="${TMP_ROOT}/test.log"
SUDO=""

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"
erpnext_dev_init_terminal_colors 2>/dev/null || true
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/config.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/docker.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/apps.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/engine.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/access.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/firewall.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/ssl.sh"

require_sudo() { :; }
log() { :; }
warn() { echo "WARN: $*" >/dev/null; }
path_is_file() { [[ -f "$1" ]]; }

mkdir -p "$DOCKER_WORKDIR"

# 1. Port contract: Docker direct access is 8080 by default; native remains 8000.
echo "== direct access ports =="
assert_eq "docker local entry port" "8080" "$(local_entry_http_port)"
assert_eq "docker direct URL" "http://vm.example:8080" "$(docker_direct_http_url vm.example)"
assert_eq "docker local firewall port" "8080" "$(local_dev_direct_ports)"

DEPLOYMENT_ENGINE="native"
assert_eq "native local entry port" "8000" "$(local_entry_http_port)"
assert_eq "native local firewall ports" $'8000\n9000' "$(local_dev_direct_ports)"
DEPLOYMENT_ENGINE="docker"

# Local SSL guidance/status must inherit the Docker direct-port contract instead
# of leaking native Bench :8000 instructions into the Docker workflow.
echo "== local Docker HTTPS guidance =="
get_vm_ip() { echo "192.0.2.55"; }
ssl_guide="$(show_local_ssl_guide)"
assert_contains "Docker SSL guide uses 8080" "$ssl_guide" "http://erp.test:8080"
assert_not_contains "Docker SSL guide does not advertise native :8000" "$ssl_guide" "http://erp.test:8000"
rollback_guide="$(show_ssl_rollback_guide)"
assert_contains "Docker SSL rollback uses 8080" "$rollback_guide" "http://erp.test:8080"

# 2. Production routing domain may differ from the internal Frappe site.
echo "== production domain routing =="
assert_eq "internal site stays erp.test" "erp.test" "$(docker_site_name)"
assert_eq "public domain" "erp.example.com" "$(docker_public_domain)"
assert_eq "Traefik host rule" 'Host(`erp.example.com`)' "$(docker_https_sites_rule)"

# 3. Production hardening blocks the Docker host-published direct port as well
# as native/container backend ports.
echo "== production firewall model =="
blocked="$(production_block_ports | sort -un | tr '\n' ' ')"
assert_contains "production hardening tracks Docker 8080 defense-in-depth" "$blocked" "8080"
assert_contains "production protects Frappe 8000" "$blocked" "8000"
assert_contains "production protects socket 9000" "$blocked" "9000"

# 4. Promotion reuses credentials from the existing quick/dev stack so the
# retained MariaDB volume is not paired with a newly invented root password.
echo "== promotion credential reuse =="
cat >"$(docker_env_file)" <<'ENV'
DOCKER_ADMIN_PASSWORD=existing-admin-secret
DOCKER_DB_ROOT_PASSWORD=existing-db-secret
ENV

docker_write_prod_env >/dev/null
assert_eq "production DB password reused" "existing-db-secret" "$(docker_env_value "$(docker_prod_env_file)" DB_PASSWORD)"
assert_eq "production pre-HTTPS port is loopback-only" "127.0.0.1:8080" "$(docker_env_value "$(docker_prod_env_file)" HTTP_PUBLISH_PORT)"
creds="$(cat "$DOCKER_CREDENTIALS_FILE")"
assert_contains "Administrator password reused" "$creds" "existing-admin-secret"
assert_contains "MariaDB password reused" "$creds" "existing-db-secret"

assert_eq "Docker credentials menu uses engine-native file" "$DOCKER_CREDENTIALS_FILE" "$(credentials_file_path)"
assert_contains "Docker credentials record has shared Login section" "$creds" "Login:"
assert_contains "Docker credentials record has Administrator username" "$creds" "Username: Administrator"
assert_contains "Docker credentials record has MariaDB Root section" "$creds" "MariaDB Root:"

# Password reset state should refresh an existing Docker credential record, but an
# intentional credentials-delete must stay deleted rather than being recreated.
#
# The production function rewrites the Docker env as root:root. This hermetic
# regression test runs unprivileged, so route privileged commands through a
# test-only shim that preserves behavior while omitting ownership changes.
MOCK_SUDO="${TMP_ROOT}/mock-sudo"
cat >"$MOCK_SUDO" <<'MOCK_SUDO_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
  install)
    shift
    args=()
    while (($#)); do
      case "$1" in
        -o|-g)
          shift 2
          ;;
        *)
          args+=("$1")
          shift
          ;;
      esac
    done
    exec install "${args[@]}"
    ;;
  chown)
    exit 0
    ;;
  *)
    exec "$@"
    ;;
esac
MOCK_SUDO_EOF
chmod +x "$MOCK_SUDO"

ORIGINAL_SUDO="${SUDO:-}"
SUDO="$MOCK_SUDO"

DOCKER_MODE="development"
cat >"$(docker_env_file)" <<'ENV_RESET'
DOCKER_ADMIN_PASSWORD=old-admin-secret
DOCKER_DB_ROOT_PASSWORD=existing-db-secret
ENV_RESET
docker_write_credentials_record "old-admin-secret" "existing-db-secret" "development"
docker_update_credentials_admin_password "new-admin-secret"
assert_eq "Docker reset updates dev env Administrator state" "new-admin-secret" "$(docker_env_value "$(docker_env_file)" DOCKER_ADMIN_PASSWORD)"
updated_creds="$(cat "$DOCKER_CREDENTIALS_FILE")"
assert_contains "Docker reset refreshes existing credential record" "$updated_creds" "new-admin-secret"
rm -f "$DOCKER_CREDENTIALS_FILE"
docker_update_credentials_admin_password "newer-admin-secret"
if [[ -f "$DOCKER_CREDENTIALS_FILE" ]]; then
  fail_case "Docker reset recreated an intentionally deleted credential record"
else
  pass "Docker reset respects intentionally deleted credential record"
fi

SUDO="$ORIGINAL_SUDO"

# Restore production state for the remaining routing tests.
DOCKER_MODE="production"
docker_write_prod_env >/dev/null

# 5. Local Docker HTTPS must route into the native-parity local SSL workflow,
# rather than fail with 'run docker-production-setup first'.
echo "== HTTPS wizard routing =="
local_ssl_routed=0
run_local_ssl_wizard() { local_ssl_routed=1; }
DEPLOYMENT_MODE="development"
PRODUCTION_DOMAIN=""
DOCKER_MODE="development"
docker_https_wizard >/dev/null
assert_eq "local Docker HTTPS routes to local SSL" "1" "$local_ssl_routed"

# 6. Public Docker HTTPS automatically invokes production promotion first.
promotion_routed=0
PRODUCTION_DOMAIN="erp.example.com"
docker_promote_to_production() {
  promotion_routed=1
  DOCKER_MODE="production"
}
DEPLOYMENT_MODE="public-vm"
DOCKER_MODE="development"
docker_https_wizard >/dev/null
assert_eq "public Docker HTTPS routes through promotion" "1" "$promotion_routed"

# 7. Static guided-flow guardrails: public setup must call the Docker-specific
# production HTTPS and promotion paths.
echo "== guided workflow wiring =="
if grep -q 'docker_promote_to_production || return 1' lib/install.sh; then
  pass "public guided install promotes existing Docker dev stack"
else
  fail_case "public guided install missing Docker promotion"
fi
if grep -q 'docker_https_wizard || return 1' lib/install.sh; then
  pass "public guided HTTPS invokes Docker HTTPS wizard"
else
  fail_case "public guided HTTPS missing Docker wizard"
fi
if grep -q 'DOCKER_PUBLISH_PORT}/tcp  do not allow publicly' lib/install.sh; then
  pass "public cloud-firewall gate documents Docker published port"
else
  fail_case "public cloud-firewall gate missing Docker published port"
fi

if grep -q 'docker_guided_host_mapping_checkpoint' lib/docker.sh && grep -q 'confirmed http://.*DOCKER_PUBLISH_PORT.*login works' lib/docker.sh; then
  pass "local Docker guided flow gates HTTPS on friendly HTTP confirmation"
else
  fail_case "local Docker guided flow missing friendly HTTP checkpoint"
fi
if grep -q 'if deployment_engine_is_docker; then docker_app_install_wizard; else run_app_install_wizard; fi' lib/install.sh; then
  pass "public quickstart optional-app action is engine-aware"
else
  fail_case "public quickstart optional-app action still assumes native engine"
fi
if grep -q 'configure_local_vm_firewall' lib/docker.sh; then
  pass "local Docker guided flow offers engine-aware firewall hardening"
else
  fail_case "local Docker guided flow missing firewall hardening step"
fi

if grep -q 'docker_guided_credentials_checkpoint' lib/docker.sh \
  && grep -q 'Reveal the generated Administrator password now' lib/docker.sh; then
  pass "Docker guided flow offers credentials reveal checkpoint"
else
  fail_case "Docker guided flow missing credentials reveal checkpoint"
fi
if grep -q 'public_vm_guided_credentials_checkpoint' lib/install.sh \
  && grep -q 'public_vm_guided_configure_https || return 1' lib/install.sh \
  && grep -q 'public_vm_guided_credentials_checkpoint || true' lib/install.sh; then
  pass "public Docker guided flow includes credentials between HTTPS and hardening"
else
  fail_case "public Docker guided flow missing credentials checkpoint"
fi
if grep -q 'docker_bench --site "$site" set-admin-password "$new_password"' lib/access.sh; then
  pass "shared reset-admin-password routes to Docker bench"
else
  fail_case "Docker Administrator password reset is not engine-aware"
fi

# 8. Native optional-app UX should keep the safety checks that matter without
# repeatedly rendering the full compatibility matrix or doing duplicate remote
# branch probes before bench get-app performs the real fetch.
echo "== native optional-app fast path =="
preflight_calls="$(awk '/^run_app_install_wizard\(\)/,/^}/' lib/apps.sh | grep -c 'app_wizard_preflight' || true)"
assert_eq "native app wizard runs general preflight once" "1" "$preflight_calls"
if awk '/^install_frappe_app\(\)/,/^}/' lib/apps.sh | grep -q 'branch_available'; then
  fail_case "native app install still performs duplicate branch_available network precheck"
else
  pass "native app install lets bench get-app perform the single remote branch validation"
fi
if grep -q 'show_app_compatibility_card .* "false"' lib/apps.sh; then
  pass "selected native app keeps local compatibility guidance without remote pre-probe"
else
  fail_case "selected native app compatibility path still performs remote pre-probe"
fi

# 9. Docker-published ports bypass normal UFW INPUT handling. The local profile
# therefore writes a persistent DOCKER-USER filter, including an IPv6 mirror
# when Docker's IPv6 forwarding backend is active.
echo "== Docker-aware local firewall filter =="
write_docker_local_firewall_filter
filter_script="$(cat "$DOCKER_LOCAL_FIREWALL_SCRIPT")"
filter_service="$(cat "$DOCKER_LOCAL_FIREWALL_SERVICE_PATH")"
assert_contains "Docker filter hooks DOCKER-USER" "$filter_script" 'DOCKER-USER'
assert_contains "Docker filter matches original published port" "$filter_script" '--ctorigdstport "$PORT"'
assert_contains "Docker filter allows private IPv4" "$filter_script" '192.168.0.0/16'
assert_contains "Docker filter mirrors IPv6 ULA policy" "$filter_script" 'fc00::/7'
assert_contains "Docker filter drops unmatched published-port traffic" "$filter_script" '-j DROP'
assert_contains "Docker filter persists after Docker startup" "$filter_service" 'After=docker.service network-online.target'

UFW_LOG="${TMP_ROOT}/ufw.calls"
: >"$UFW_LOG"
ufw() { printf '%s\n' "$*" >>"$UFW_LOG"; }
unset SSH_CLIENT || true
DEPLOYMENT_ENGINE="docker"
allow_local_dev_ports
ufw_calls="$(cat "$UFW_LOG")"
assert_not_contains "Docker local profile does not pretend UFW controls 8080" "$ufw_calls" '8080'
: >"$UFW_LOG"
DEPLOYMENT_ENGINE="native"
allow_local_dev_ports
ufw_calls="$(cat "$UFW_LOG")"
assert_contains "Native local profile still grants UFW 8000" "$ufw_calls" '8000'
DEPLOYMENT_ENGINE="docker"

# 10. Production HTTP is safe before TLS: the direct frontend port must bind to
# loopback only. Once HTTPS is enabled, only Traefik's 80/443 may be public.
echo "== production exposure bindings =="
DOCKER_MODE="production"
DEPLOYMENT_MODE="public-vm"
DOCKER_HTTPS_MODE="http"
docker() {
  if [[ "${1:-}" == "ps" ]]; then
    echo 'erpnext-dev-frontend-1 127.0.0.1:8080->8080/tcp'
    return 0
  fi
  return 1
}
if exposure_output="$(docker_production_exposure)"; then
  pass "production pre-HTTPS loopback binding passes exposure guard"
else
  fail_case "production pre-HTTPS loopback binding failed exposure guard"
fi
assert_contains "exposure guard reports loopback-only HTTP" "$exposure_output" '127.0.0.1:8080 only; not public'

docker() {
  if [[ "${1:-}" == "ps" ]]; then
    echo 'erpnext-dev-frontend-1 0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp'
    return 0
  fi
  return 1
}
if public_exposure_output="$(docker_production_exposure 2>&1)"; then
  fail_case "production pre-HTTPS public 8080 should fail exposure guard"
else
  pass "production pre-HTTPS public 8080 is rejected"
fi
assert_contains "public 8080 failure is explicit" "$public_exposure_output" '8080 is publicly published before HTTPS'

# 11. Production Docker optional apps must use a cumulative immutable image.
# This protects against the v1.19.20 defect where bench get-app mutated only
# the backend container while frontend, workers, scheduler, and websocket kept
# running the original ERPNext-only image.
echo "== production Docker optional-app image lifecycle =="

DOCKER_CUSTOM_IMAGE_PROFILES_FILE="${DOCKER_WORKDIR}/test-custom-image-profiles"
DOCKER_CUSTOM_IMAGE_APPS_FILE="${DOCKER_WORKDIR}/test-apps.json"
DOCKER_CUSTOM_IMAGE_STATE_FILE="${DOCKER_WORKDIR}/test-custom-image.env"

docker_resolve_default_branch() {
  echo "develop"
}

DOCKER_TEST_LIST_APPS=""
DOCKER_BENCH_CALLS="${TMP_ROOT}/docker-bench.calls"
: >"$DOCKER_BENCH_CALLS"

docker_bench() {
  if [[ "$*" == *"list-apps"* ]]; then
    printf '%s\n' "$DOCKER_TEST_LIST_APPS"
    return 0
  fi

  printf '%s\n' "$*" >>"$DOCKER_BENCH_CALLS"
  return 0
}

# Existing installed optional apps must be rediscovered and preserved when a
# new custom image is generated.
DOCKER_TEST_LIST_APPS=$'frappe\nerpnext\ncrm\nbuilder'
rm -f "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE"

discovered_profiles="$(docker_collect_desired_app_profiles)"
assert_eq \
  "production image rediscovers all installed curated apps" \
  $'crm\nbuilder' \
  "$discovered_profiles"

docker_write_apps_json crm builder

persisted_profiles="$(cat "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE")"
assert_eq \
  "custom-image profiles persist across CLI invocations" \
  $'crm\nbuilder' \
  "$persisted_profiles"

assert_eq \
  "persistent profiles resolve to install-app names" \
  "crm builder" \
  "$(docker_custom_image_selected_app_names)"

apps_json="$(cat "$DOCKER_CUSTOM_IMAGE_APPS_FILE")"
assert_contains \
  "custom image includes CRM repository" \
  "$apps_json" \
  '"https://github.com/frappe/crm"'

assert_contains \
  "custom image includes Builder repository" \
  "$apps_json" \
  '"https://github.com/frappe/builder"'

# Dependencies must be accumulated into the desired image state.
DOCKER_TEST_LIST_APPS=$'frappe\nerpnext'
rm -f "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE"

dependency_profiles="$(docker_collect_desired_app_profiles helpdesk)"
assert_eq \
  "Helpdesk production image includes Telephony dependency" \
  $'telephony\nhelpdesk' \
  "$dependency_profiles"

# Reconciliation must refuse to guess repository information for an installed
# app that is not represented by a curated profile.
DOCKER_TEST_LIST_APPS=$'frappe\nerpnext\nunknown_custom_app'

if docker_collect_installed_optional_profiles >/dev/null 2>&1; then
  fail_case "unknown installed Docker app was silently accepted for reconciliation"
else
  pass "unknown installed Docker app safely blocks automatic reconciliation"
fi

# Normal production app installation must route through build + deploy rather
# than mutating the backend container directly.
DOCKER_MODE="production"
DEPLOYMENT_MODE="public-vm"
DOCKER_TEST_LIST_APPS=$'frappe\nerpnext'
rm -f \
  "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE" \
  "$DOCKER_CUSTOM_IMAGE_APPS_FILE"

IMAGE_WORKFLOW_CALLS="${TMP_ROOT}/custom-image-workflow.calls"
: >"$IMAGE_WORKFLOW_CALLS"

docker_build_custom_image() {
  printf '%s\n' build >>"$IMAGE_WORKFLOW_CALLS"
}

docker_deploy_custom_image() {
  printf '%s\n' deploy >>"$IMAGE_WORKFLOW_CALLS"
}

docker_install_app \
  builder \
  "Frappe Builder" \
  "https://github.com/frappe/builder" \
  "" \
  >/dev/null

image_workflow_calls="$(cat "$IMAGE_WORKFLOW_CALLS")"

assert_eq \
  "production optional app builds then deploys custom image" \
  $'build\ndeploy' \
  "$image_workflow_calls"

assert_eq \
  "production optional app persists requested profile" \
  "builder" \
  "$(cat "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE")"

# Development mode intentionally retains the disposable runtime-install path.
DOCKER_MODE="development"
: >"$DOCKER_BENCH_CALLS"
: >"$IMAGE_WORKFLOW_CALLS"

docker_runtime_restart() {
  return 0
}

docker_install_app \
  builder \
  "Frappe Builder" \
  "https://github.com/frappe/builder" \
  "" \
  >/dev/null

dev_bench_calls="$(cat "$DOCKER_BENCH_CALLS")"

assert_contains \
  "development Docker still permits runtime get-app" \
  "$dev_bench_calls" \
  "get-app https://github.com/frappe/builder"

if [[ -s "$IMAGE_WORKFLOW_CALLS" ]]; then
  fail_case "development Docker unexpectedly invoked production custom-image workflow"
else
  pass "development Docker does not invoke production custom-image workflow"
fi

# The production image override must pin every application-bearing service to
# exactly the same immutable image.
# Normal registry-backed production images must retain the upstream/default
# pull behavior. pull_policy: never is reserved for Toolkit-built local images.
DOCKER_ERPNEXT_IMAGE="frappe/erpnext:v16.26.2"
docker_write_prod_image_override

registry_override="$(cat "$(docker_prod_image_override_file)")"

assert_not_contains \
  "registry-backed production image is not forced local-only" \
  "$registry_override" \
  "pull_policy: never"

# Toolkit-built production images are local artifacts unless explicitly pushed
# elsewhere. All application-bearing services must use the local image without
# attempting a registry pull.
DOCKER_ERPNEXT_IMAGE="erpnext-dev/custom:test-regression"
docker_write_prod_image_override never

prod_override="$(cat "$(docker_prod_image_override_file)")"

for svc in \
  configurator \
  backend \
  frontend \
  websocket \
  queue-short \
  queue-long \
  scheduler; do
  assert_contains \
    "production image override includes ${svc}" \
    "$prod_override" \
    "  ${svc}:"
done

override_image_count="$(
  grep -c 'image: erpnext-dev/custom:test-regression' \
    "$(docker_prod_image_override_file)" \
    || true
)"

assert_eq \
  "all seven customizable services use the same image" \
  "7" \
  "$override_image_count"

override_never_count="$(
  grep -c 'pull_policy: never' \
    "$(docker_prod_image_override_file)" \
    || true
)"

assert_eq \
  "all seven local custom-image services disable registry pulls" \
  "7" \
  "$override_never_count"

deploy_function="$(
  awk '/^docker_deploy_custom_image\(\)/,/^docker_reconcile_app_image\(\)/' \
    lib/docker.sh
)"

assert_contains \
  "custom-image deployment writes a local-only production override" \
  "$deploy_function" \
  "docker_write_prod_image_override never"

# Runtime consistency verification must inspect every long-running application
# service and reject the backend-only deployment shape that caused the original
# CRM and Builder failure.
RUNTIME_VERIFY_CALLS="${TMP_ROOT}/runtime-verify.calls"
: >"$RUNTIME_VERIFY_CALLS"

docker_compose() {
  if [[ "${1:-}" == "ps" && "${2:-}" == "-q" ]]; then
    printf 'cid-%s\n' "${3:-unknown}"
    return 0
  fi

  if [[ "${1:-}" == "exec" ]]; then
    printf 'compose:%s\n' "$*" >>"$RUNTIME_VERIFY_CALLS"
    return 0
  fi

  return 0
}

docker() {
  printf 'docker:%s\n' "$*" >>"$RUNTIME_VERIFY_CALLS"
  return 0
}

if docker_custom_image_verify_runtime "crm builder"; then
  pass "custom-image runtime consistency verification succeeds for uniform services"
else
  fail_case "custom-image runtime consistency verification unexpectedly failed"
fi

runtime_verify_calls="$(cat "$RUNTIME_VERIFY_CALLS")"

for svc in \
  backend \
  frontend \
  websocket \
  queue-short \
  queue-long \
  scheduler; do
  assert_contains \
    "runtime verification checks ${svc}" \
    "$runtime_verify_calls" \
    "cid-${svc}"
done

assert_contains \
  "runtime verification checks CRM frontend assets" \
  "$runtime_verify_calls" \
  "/home/frappe/frappe-bench/assets/crm"

assert_contains \
  "runtime verification checks Builder frontend assets" \
  "$runtime_verify_calls" \
  "/home/frappe/frappe-bench/assets/builder"

if [[ "$failures" -gt 0 ]]; then
  echo "docker-access-routing tests: ${failures} failure(s)" >&2
  exit 1
fi

echo "docker-access-routing tests: all checks passed"
