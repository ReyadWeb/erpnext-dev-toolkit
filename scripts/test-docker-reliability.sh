#!/usr/bin/env bash
# Hermetic regression tests for Docker reboot persistence, strict service
# health, and progress-aware create-site waiting.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
pass() { echo "OK: $*"; }
fail_case() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}
assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" == *"$needle"* ]] \
    && pass "$label" \
    || fail_case "$label: missing '$needle'"
}
assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" != *"$needle"* ]] \
    && pass "$label" \
    || fail_case "$label: unexpectedly found '$needle'"
}
assert_succeeds() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail_case "$label"
  fi
}
assert_fails() {
  local label="$1"
  shift
  if "$@"; then
    fail_case "$label: unexpectedly succeeded"
  else
    pass "$label"
  fi
}
assert_process_gone() {
  local label="$1" pid="$2" state
  for _ in {1..40}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      pass "$label"
      return 0
    fi
    state="$(ps -o stat= -p "$pid" 2>/dev/null || true)"
    if [[ "$state" == Z* ]]; then
      pass "$label"
      return 0
    fi
    sleep 0.05
  done
  fail_case "$label: PID ${pid} survived the timeout"
}

TMP_ROOT="$(mktemp -d /tmp/erpnext-dev-docker-reliability.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export ERPNEXT_DEV_ENTRY_SCRIPT="${ROOT_DIR}/erpnext-dev.sh"
DOCKER_WORKDIR="${TMP_ROOT}/docker"
DOCKER_PROJECT_NAME="erpnext-dev"
DOCKER_MODE="development"
DOCKER_CREATE_SITE_TIMEOUT=10
DOCKER_CREATE_SITE_MAX_TIMEOUT=100
SITE_NAME="erp.test"
SUDO=""

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/docker.sh"

require_sudo() { :; }
deployment_engine_is_docker() { return 0; }
docker_daemon_ready() { return 0; }
ok() { :; }
warn() { :; }
err() { :; }
log() { :; }

mkdir -p "$(dirname "$(docker_compose_base_file)")"
: >"$(docker_compose_base_file)"
: >"$(docker_override_file)"
: >"$(docker_env_file)"

echo "== persistent restart policy overlay =="
docker_write_restart_policy_override
restart_override="$(cat "$(docker_restart_policy_override_file)")"
service_count=0
while IFS= read -r svc; do
  [[ -n "$svc" ]] || continue
  assert_contains "${svc} uses unless-stopped" "$restart_override" "  ${svc}:"
  service_count=$((service_count + 1))
done < <(docker_persistent_services)
[[ "$service_count" -eq 9 ]] \
  && pass "nine persistent services are covered" \
  || fail_case "expected nine persistent services, got ${service_count}"
assert_not_contains "configurator remains one-shot" "$restart_override" "  configurator:"
assert_not_contains "create-site remains one-shot" "$restart_override" "  create-site:"
compose_files="$(docker_compose_file_list)"
assert_contains "Compose includes persistence overlay" "$compose_files" "$(docker_restart_policy_override_file)"

slow_bin="${TMP_ROOT}/slow-bin"
slow_pid_file="${TMP_ROOT}/slow-docker.pid"
mkdir -p "$slow_bin"
cat >"$slow_bin/docker" <<'EOF_SLOW_DOCKER'
#!/usr/bin/env bash
if [[ "${1:-}" == compose && "${2:-}" == version ]]; then
  exit 0
fi
sleep 300 &
child=$!
printf '%s\n' "$child" >"$ERPNEXT_TEST_PID_FILE"
wait "$child"
EOF_SLOW_DOCKER
chmod +x "$slow_bin/docker"

set +e
PATH="$slow_bin:$PATH" ERPNEXT_TEST_PID_FILE="$slow_pid_file" \
  ERPNEXT_DEV_DOCKER_COMPOSE_TIMEOUT=1 docker_compose ps >/dev/null 2>&1
slow_compose_rc=$?
set -e
[[ "$slow_compose_rc" -eq 124 ]] \
  && pass "Docker inventory deadline returns timeout status" \
  || fail_case "Docker inventory deadline returned ${slow_compose_rc}, expected 124"
[[ -s "$slow_pid_file" ]] \
  && assert_process_gone "Docker timeout leaves no child process" "$(<"$slow_pid_file")" \
  || fail_case "slow Docker probe did not record its child PID"

declare -A CID=()
declare -A STATE=()
declare -A HEALTH=()
declare -A POLICY=()
UPDATED_FILE="${TMP_ROOT}/updated.txt"
: >"$UPDATED_FILE"

while IFS= read -r svc; do
  [[ -n "$svc" ]] || continue
  CID["$svc"]="cid-${svc}"
  STATE["$svc"]="running"
  HEALTH["$svc"]="none"
  POLICY["$svc"]="unless-stopped"
done < <(docker_persistent_services)
CID[proxy]="cid-proxy"
STATE[proxy]="running"
HEALTH[proxy]="none"
POLICY[proxy]="unless-stopped"

docker_compose() {
  if [[ "${1:-}" == "ps" && "${2:-}" == "-aq" ]]; then
    printf '%s\n' "${CID[${3:-}]:-}"
    return 0
  fi
  if [[ "${1:-}" == "logs" ]]; then
    return 0
  fi
  return 1
}

docker() {
  case "${1:-}" in
    inspect)
      local cid svc
      cid="${*: -1}"
      svc="${cid#cid-}"
      printf '%s|%s|%s\n' \
        "${STATE[$svc]:-unknown}" \
        "${HEALTH[$svc]:-none}" \
        "${POLICY[$svc]:-unknown}"
      ;;
    update)
      printf '%s\n' "${*: -1}" >>"$UPDATED_FILE"
      ;;
    *) return 1 ;;
  esac
}

echo "== strict required-service health =="
stack_detail=""
if stack_detail="$(docker_required_stack_status)"; then
  pass "all required services pass"
else
  fail_case "healthy required services were rejected: ${stack_detail}"
fi
assert_contains "healthy summary counts every service" "$stack_detail" "9/9"

STATE[db]="exited"
assert_fails "stopped database fails strict health" docker_required_stack_status
STATE[db]="running"

STATE[frontend]="restarting"
assert_fails "restarting frontend fails strict health" docker_required_stack_status
STATE[frontend]="running"

HEALTH[db]="unhealthy"
assert_fails "unhealthy database fails strict health" docker_required_stack_status
HEALTH[db]="none"

HEALTH[db]="starting"
assert_fails "health-starting database fails strict health" docker_required_stack_status
HEALTH[db]="none"

saved_queue_long="${CID["queue-long"]}"
CID["queue-long"]=""
assert_fails "missing worker fails strict health" docker_required_stack_status
CID["queue-long"]="$saved_queue_long"

POLICY[backend]="on-failure"
policy_detail=""
if policy_detail="$(docker_restart_policy_status)"; then
  fail_case "on-failure restart policy unexpectedly passed"
else
  pass "on-failure restart policy is rejected"
fi
assert_contains "policy failure prints exact repair command" "$policy_detail" "docker-reconcile-restart-policy"
POLICY[backend]="unless-stopped"
assert_succeeds "unless-stopped policy passes" docker_restart_policy_status

echo "== existing-container reconciliation =="
docker_reconcile_restart_policy
updated_count="$(wc -l <"$UPDATED_FILE" | tr -d ' ')"
[[ "$updated_count" -eq 10 ]] \
  && pass "nine persistent services plus optional proxy reconciled" \
  || fail_case "expected ten reconciled containers, got ${updated_count}"
assert_contains "backend container reconciled" "$(cat "$UPDATED_FILE")" "cid-backend"
assert_contains "database container reconciled" "$(cat "$UPDATED_FILE")" "cid-db"

sequence_next() {
  local name="$1"
  shift
  local file="${TMP_ROOT}/${name}.index" index=0
  [[ -f "$file" ]] && index="$(cat "$file")"
  local -a values=("$@")
  if ((index >= ${#values[@]})); then
    index=$((${#values[@]} - 1))
  fi
  printf '%s\n' "${values[$index]}"
  printf '%s\n' "$((index + 1))" >"$file"
}

reset_sequence() {
  rm -f "${TMP_ROOT}/now.index" "${TMP_ROOT}/result.index" "${TMP_ROOT}/progress.index"
}

docker_compose() {
  if [[ "${1:-}" == "ps" && "${2:-}" == "-aq" && "${3:-}" == "create-site" ]]; then
    printf 'cid-create-site\n'
    return 0
  fi
  if [[ "${1:-}" == "logs" ]]; then
    return 0
  fi
  return 1
}
docker_wait_sleep() { :; }

echo "== progress-aware create-site waiting =="
reset_sequence
docker_now_epoch() { sequence_next now 0 6 12 18; }
docker_create_site_container_result() {
  sequence_next result 'running|0' 'running|0' 'exited|0'
}
docker_create_site_progress_marker() {
  sequence_next progress 'installing frappe' 'installing erpnext' 'complete'
}
assert_succeeds "new progress extends the idle deadline" docker_wait_for_site_creation

reset_sequence
docker_now_epoch() { sequence_next now 0 10; }
docker_create_site_container_result() {
  sequence_next result 'running|0' 'exited|0'
}
docker_create_site_progress_marker() { printf '\n'; }
assert_succeeds "final exit inspection closes the timeout race" docker_wait_for_site_creation

reset_sequence
docker_now_epoch() { sequence_next now 0 11; }
docker_create_site_container_result() { printf 'running|0\n'; }
docker_create_site_progress_marker() { printf '\n'; }
assert_fails "idle create-site job still fails closed" docker_wait_for_site_creation

if ((failures > 0)); then
  echo "docker-reliability tests: ${failures} failure(s)" >&2
  exit 1
fi

echo "docker-reliability tests: all checks passed"
