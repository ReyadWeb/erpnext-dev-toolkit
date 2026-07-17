# shellcheck shell=bash
# Deployment engine contract. The toolkit supports two first-class engines behind
# one CLI and operator experience:
#   native  -> ERPNext/Frappe installed directly on the VM (systemd, bench, host
#              MariaDB/Redis/Nginx). This is the default and its behavior is
#              unchanged; native_* wrappers below call the existing functions.
#   docker  -> containerized stack wrapping the official frappe_docker project
#              (see lib/docker.sh).
#
# Rather than scattering `if docker` checks across the codebase, all routing lives
# here: each engine_* verb dispatches on the effective engine. Sourced by the
# toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_ENGINE_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_ENGINE_LOADED=1

# Set to 1 once the deployment engine has been chosen in this process, so a
# single guided run does not prompt for the engine more than once.
: "${DEPLOYMENT_ENGINE_SESSION_CHOSEN:=0}"

# ------------------------------------------------------------
# Selection / persistence helpers (mirror the HOST_OS helpers)
# ------------------------------------------------------------
normalize_deployment_engine() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$raw" in
    native|host|bare|vm) printf 'native\n' ;;
    docker|container|compose|containers) printf 'docker\n' ;;
    *) return 1 ;;
  esac
}

validate_deployment_engine_value() {
  normalize_deployment_engine "$1" >/dev/null 2>&1
}

# Resolved engine with a safe default. Empty/unknown -> native so pre-existing
# installs keep their exact behavior.
effective_deployment_engine() {
  local resolved
  if resolved="$(normalize_deployment_engine "${DEPLOYMENT_ENGINE:-}" 2>/dev/null)"; then
    printf '%s\n' "$resolved"
  else
    printf 'native\n'
  fi
}

deployment_engine_is_docker() {
  [[ "$(effective_deployment_engine)" == "docker" ]]
}

# True only when the operator has not chosen an engine yet (config empty and no
# env override).
deployment_engine_is_unset() {
  [[ "${DEPLOYMENT_ENGINE_ENV_PROVIDED:-0}" -ne 1 ]] && ! validate_deployment_engine_value "${DEPLOYMENT_ENGINE:-}"
}

deployment_engine_label() {
  local raw="${1:-$(effective_deployment_engine)}"
  case "$raw" in
    native) printf 'Native (VM)\n' ;;
    docker) printf 'Docker\n' ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

# Interactive engine picker for setup. persist=1 writes config immediately;
# quickstart passes persist=0 because it saves defaults right after.
choose_deployment_engine_for_setup() {
  local persist="${1:-1}"
  local reply resolved current

  # Ask only once per invocation. A single guided run can reach this picker from
  # more than one caller (e.g. run_local_dev_quickstart -> run_guided_setup ->
  # run_install), so without this guard the operator is prompted twice. The
  # explicit `set-engine` command clears the guard so it can always re-prompt.
  if [[ "${DEPLOYMENT_ENGINE_SESSION_CHOSEN:-0}" -eq 1 ]] && validate_deployment_engine_value "${DEPLOYMENT_ENGINE:-}"; then
    DEPLOYMENT_ENGINE="$(normalize_deployment_engine "$DEPLOYMENT_ENGINE")"
    echo "Using deployment engine: $(deployment_engine_label) (already selected)"
    return 0
  fi

  if [[ "${DEPLOYMENT_ENGINE_ENV_PROVIDED:-0}" -eq 1 ]] && validate_deployment_engine_value "${DEPLOYMENT_ENGINE:-}"; then
    DEPLOYMENT_ENGINE="$(normalize_deployment_engine "$DEPLOYMENT_ENGINE")"
    DEPLOYMENT_ENGINE_SESSION_CHOSEN=1
    echo "Using deployment engine: $(deployment_engine_label)"
    return 0
  fi

  current="$(effective_deployment_engine)"

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    echo
    echo "============================================================"
    echo "Choose Deployment Engine"
    echo "============================================================"
    echo
    echo "1) Native Ubuntu/Debian VM"
    echo "   Direct ERPNext/Frappe install on this VM."
    echo "   Best for host-level control and simplicity."
    echo
    echo "2) Docker"
    echo "   Containerized deploy via official Frappe Docker."
    echo "   Best for isolation and upstream alignment."
    echo
    while true; do
      read -r -p "Deployment engine [1-2, default: Native]: " reply
      case "${reply,,}" in
        ""|1|native) resolved="native" ;;
        2|docker) resolved="docker" ;;
        *) echo "Please choose 1 or 2."; continue ;;
      esac
      break
    done
  else
    resolved="$current"
    echo "Using deployment engine: $(deployment_engine_label "$resolved") (non-interactive default; change with $(toolkit_cmd set-engine))"
  fi

  DEPLOYMENT_ENGINE="$resolved"
  DEPLOYMENT_ENGINE_SESSION_CHOSEN=1
  if [[ "$persist" == "1" ]]; then
    write_dev_config_file
  fi
  echo "Deployment engine set to: $(deployment_engine_label)"
  return 0
}

# set-engine dispatcher entry point.
run_set_engine() {
  require_sudo
  DEPLOYMENT_ENGINE_ENV_PROVIDED=0
  # Force a fresh prompt even if the engine was already chosen this session.
  DEPLOYMENT_ENGINE_SESSION_CHOSEN=0
  choose_deployment_engine_for_setup 1
}

show_engine_status() {
  ui_box_start "Deployment Engine"
  status_line "Engine" "INFO" "$(deployment_engine_label)"
  status_line "Configured value" "INFO" "${DEPLOYMENT_ENGINE:-<unset; default native>}"
  if deployment_engine_is_docker; then
    status_line "Docker mode" "INFO" "$(docker_mode_label 2>/dev/null || echo development)"
    status_line "Compose project" "INFO" "${DOCKER_PROJECT_NAME:-erpnext-dev}"
    status_line "Published port" "INFO" "${DOCKER_PUBLISH_PORT:-8080}"
    status_line "ERPNext image" "INFO" "${DOCKER_ERPNEXT_IMAGE:-frappe/erpnext}"
    status_line "Site" "INFO" "$(docker_site_name 2>/dev/null || echo "${SITE_NAME:-erp.test}")"
    if [[ -r "${DOCKER_PINS_FILE:-}" ]]; then
      local pin_sha pin_digest
      pin_sha="$(sed -n 's/^FRAPPE_DOCKER_SHA=//p' "$DOCKER_PINS_FILE" 2>/dev/null | tail -n1)"
      pin_digest="$(sed -n 's/^DOCKER_ERPNEXT_IMAGE_DIGEST=//p' "$DOCKER_PINS_FILE" 2>/dev/null | tail -n1)"
      [[ -n "$pin_sha" ]] && status_line "frappe_docker SHA" "INFO" "$pin_sha"
      [[ -n "$pin_digest" ]] && status_line "Image digest" "INFO" "$pin_digest"
    fi
  else
    status_line "Bench" "INFO" "${BENCH_DIR}"
    status_line "Service" "INFO" "${ERPNEXT_SERVICE_NAME}"
  fi
  ui_box_end
  echo "Switch engines for a fresh setup with: $(toolkit_cmd set-engine)"
}

# ------------------------------------------------------------
# Contract dispatch: native wrappers call existing functions unchanged.
# ------------------------------------------------------------
engine_install() {
  if deployment_engine_is_docker; then
    docker_guided_install
  else
    run_install
  fi
}

engine_runtime_start() {
  if deployment_engine_is_docker; then
    docker_runtime_start
  else
    start_erpnext_service
  fi
}

engine_runtime_stop() {
  if deployment_engine_is_docker; then
    docker_runtime_stop
  else
    stop_erpnext_service
  fi
}

engine_runtime_restart() {
  if deployment_engine_is_docker; then
    docker_runtime_restart
  else
    restart_erpnext_service
  fi
}

engine_runtime_status() {
  if deployment_engine_is_docker; then
    docker_runtime_status
  else
    show_erpnext_service_status
  fi
}

engine_runtime_logs() {
  if deployment_engine_is_docker; then
    docker_runtime_logs
  else
    show_erpnext_service_logs
  fi
}

engine_ready() {
  if deployment_engine_is_docker; then
    docker_ready
  else
    wait_for_erpnext_ready
  fi
}

# Run a bench command in the right context. Native mirrors run_as_frappe in the
# active bench dir; docker execs inside the backend container.
engine_bench() {
  if deployment_engine_is_docker; then
    docker_bench "$@"
  else
    local bench_dir args
    bench_dir="$(active_bench_dir)"
    args="$(printf '%q ' "$@")"
    run_as_frappe "cd '${bench_dir}' && bench ${args}"
  fi
}

engine_backup() {
  local include_files="${1:-false}"
  if deployment_engine_is_docker; then
    docker_backup "$include_files"
  else
    create_site_backup "$include_files"
  fi
}

engine_site_url() {
  if deployment_engine_is_docker; then
    docker_site_url
  else
    printf 'http://%s:8000\n' "${SITE_NAME}"
  fi
}

# ------------------------------------------------------------
# Contract closure: restore / upgrade / rollback / diagnostics.
# These promote previously command-only operations to first-class engine verbs
# so both engines answer the full lifecycle contract uniformly (see
# DEPLOYMENT-ARCHITECTURE.md section 5). They route to existing implementations;
# for the Docker engine, upgrade/rollback route to container-native guidance
# (immutable re-deploy) rather than an unsafe in-place mutation.
engine_restore() {
  if deployment_engine_is_docker; then
    docker_restore "${1:-full}"
  else
    restore_site_full
  fi
}

engine_upgrade() {
  if deployment_engine_is_docker; then
    docker_upgrade
  else
    run_safe_update_wizard
  fi
}

engine_rollback() {
  if deployment_engine_is_docker; then
    docker_rollback
  else
    run_update_rollback
  fi
}

# Structured diagnostics. Shared across engines; doctor_collect is engine-aware.
# Arg: plain (default), json, or human (treated as plain for the contract).
engine_diagnostics() {
  case "${1:-plain}" in
    json) run_doctor_json ;;
    *) run_doctor_plain ;;
  esac
}
