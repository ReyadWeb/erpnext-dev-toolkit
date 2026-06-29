#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================
# ERPNext / Frappe Developer Installer Manager
# Target: Ubuntu 24.04 / 26.04 LTS developer VM
# Default: Frappe v16 + ERPNext v16 + site erp.test
# Mode: local development using bench start
# ============================================================

APP_NAME="ERPNext Developer Installer"
SCRIPT_VERSION="0.8.16"

FRAPPE_USER="${FRAPPE_USER:-frappe}"
FRAPPE_HOME="/home/${FRAPPE_USER}"
BENCH_PARENT="${BENCH_PARENT:-${FRAPPE_HOME}/frappe}"
BENCH_NAME="${BENCH_NAME:-frappe-bench}"
BENCH_DIR="${BENCH_PARENT}/${BENCH_NAME}"
SITE_NAME_ENV_PROVIDED=0
if [[ -n "${SITE_NAME+x}" ]]; then
  SITE_NAME_ENV_PROVIDED=1
fi
SITE_NAME="${SITE_NAME:-erp.test}"
SITE_NAME_SOURCE="default"
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-development}"
PRODUCTION_DOMAIN="${PRODUCTION_DOMAIN:-}"
PRODUCTION_SSL_MODE="${PRODUCTION_SSL_MODE:-planned}"
AUTO_START="${AUTO_START:-prompt}"
ENABLE_AUTOSTART="${ENABLE_AUTOSTART:-prompt}"
ERPNEXT_SERVICE_NAME="${ERPNEXT_SERVICE_NAME:-erpnext-dev.service}"
READY_TIMEOUT="${READY_TIMEOUT:-90}"
READY_INTERVAL="${READY_INTERVAL:-5}"
CONFIG_FILE="${CONFIG_FILE:-/etc/erpnext-dev-installer/config.env}"
LEGACY_CONFIG_FILE="${LEGACY_CONFIG_FILE:-${FRAPPE_HOME}/erpnext-dev-config.env}"

SSL_CERT_DIR="${SSL_CERT_DIR:-/etc/erpnext-dev-ssl}"
SSL_NGINX_CONF_DIR="${SSL_NGINX_CONF_DIR:-/etc/nginx}"
SSL_REDIRECT_HTTP="${SSL_REDIRECT_HTTP:-true}"

FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
ERPNEXT_BRANCH="${ERPNEXT_BRANCH:-version-16}"

NODE_VERSION="${NODE_VERSION:-24}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14}"

DB_ADMIN_USER="${DB_ADMIN_USER:-frappe_db_admin}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

ASSUME_YES=0
ACTION=""
LOG_DIR="${LOG_DIR:-/tmp}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/erpnext-dev-installer-$(date +%Y%m%d-%H%M%S).log}"
LOCK_FILE="${LOCK_FILE:-/tmp/erpnext-dev-installer.lock}"

if [[ -t 1 ]]; then
  BOLD="\033[1m"
  DIM="\033[2m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  RED="\033[31m"
  BLUE="\033[34m"
  RESET="\033[0m"
else
  BOLD=""
  DIM=""
  GREEN=""
  YELLOW=""
  RED=""
  BLUE=""
  RESET=""
fi

# Keep logs private because install output may include sensitive operational details.
mkdir -p "$LOG_DIR" 2>/dev/null || true
: > "$LOG_FILE" || { echo "ERROR: Cannot write log file: $LOG_FILE" >&2; exit 1; }
chmod 600 "$LOG_FILE" 2>/dev/null || true

exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo -e "\n${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
ok() { echo -e "${GREEN}OK:${RESET} $*"; }
warn() { echo -e "${YELLOW}WARN:${RESET} $*"; }
err() { echo -e "${RED}ERROR:${RESET} $*" >&2; }
fail() { err "$*"; echo "Log file: $LOG_FILE" >&2; exit 1; }

acquire_installer_lock() {
  # Prevent two setup/repair/service commands from changing the same VM at once.
  exec 200>"$LOCK_FILE"
  chmod 600 "$LOCK_FILE" 2>/dev/null || true
  if ! flock -n 200; then
    err "Another installer task is already running."
    echo "Lock file: $LOCK_FILE" >&2
    echo "Wait for it to finish, or remove the lock only if you are sure no installer is running." >&2
    exit 1
  fi
}

action_requires_lock() {
  local action="${1:-menu}"
  case "$action" in
    ""|menu|setup|install|repair|start|stop|uninstall|advanced|backup-menu|backup|backup-files|restore-db|restore-full|maintenance|migrate|build|clear-cache|restart|foreground-start|enable-autostart|disable-autostart|service-start|service-stop|service-restart|install-local-ssl-cert|replace-local-ssl-cert|create-self-signed-local-cert|self-signed-local-cert|configure-local-ssl|disable-local-ssl|repair-site-config|expand-root-storage|app-library|apps|install-crm|install-hrms|install-helpdesk|install-telephony|install-insights|install-custom-app|repair-app-registry)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}


status_line() {
  local label="$1"
  local state="$2"
  local message="$3"

  case "$state" in
    OK) printf "  %-28s ${GREEN}%-7s${RESET} %s\n" "$label" "$state" "$message" ;;
    WARN) printf "  %-28s ${YELLOW}%-7s${RESET} %s\n" "$label" "$state" "$message" ;;
    FAIL) printf "  %-28s ${RED}%-7s${RESET} %s\n" "$label" "$state" "$message" ;;
    INFO) printf "  %-28s ${BLUE}%-7s${RESET} %s\n" "$label" "$state" "$message" ;;
    *) printf "  %-28s %-7s %s\n" "$label" "$state" "$message" ;;
  esac
}

validate_site_name_value() {
  local name="$1"

  if [[ -z "$name" ]]; then
    err "Site name cannot be empty."
    return 1
  fi

  if [[ "$name" =~ ^https?:// ]]; then
    err "Use only the hostname, not a URL. Example: erp.test"
    return 1
  fi

  if [[ "$name" == *":"* || "$name" == *"/"* || "$name" =~ [[:space:]] ]]; then
    err "Site name must not contain spaces, slashes, or ports. Example: erp107.test"
    return 1
  fi

  if [[ "$name" == *.local ]]; then
    err "Avoid .local because it conflicts with mDNS/Avahi on Linux. Use .test instead."
    return 1
  fi

  if ! [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
    err "Invalid site name: ${name}"
    err "Use a hostname like erp.test, erp107.test, school.test, or client-a.test"
    return 1
  fi

  return 0
}

maybe_warn_site_name() {
  local name="$1"
  if [[ "$name" != *.test ]]; then
    warn "For local development, .test is recommended. Current site name: ${name}"
  fi
}

read_site_name_from_file() {
  local file="$1"
  local value=""

  [[ -r "$file" ]] || return 1
  value="$(grep -E '^SITE_NAME=' "$file" 2>/dev/null | tail -n 1 | sed -E 's/^SITE_NAME=//; s/^"//; s/"$//; s/^'\''//; s/'\''$//' || true)"
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

read_config_key_from_file() {
  local file="$1"
  local key="$2"
  local value=""

  [[ -r "$file" ]] || return 1
  value="$(awk -F= -v k="$key" '$1 == k {v=$0; sub("^[^=]*=", "", v)} END {print v}' "$file" 2>/dev/null || true)"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

read_saved_config_value() {
  local key="$1"
  local file value
  for file in "$CONFIG_FILE" "$LEGACY_CONFIG_FILE"; do
    [[ -n "$file" ]] || continue
    if value="$(read_config_key_from_file "$file" "$key" 2>/dev/null)" && [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

read_saved_site_name() {
  local file value
  for file in "$CONFIG_FILE" "$LEGACY_CONFIG_FILE"; do
    [[ -n "$file" ]] || continue
    if value="$(read_site_name_from_file "$file" 2>/dev/null)" && [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

read_saved_site_name_with_sudo() {
  local file value
  for file in "$CONFIG_FILE" "$LEGACY_CONFIG_FILE"; do
    [[ -n "$file" ]] || continue
    if [[ -r "$file" ]]; then
      if value="$(read_site_name_from_file "$file" 2>/dev/null)" && [[ -n "$value" ]]; then
        printf '%s\n' "$value"
        return 0
      fi
    elif [[ -n "${SUDO:-}" ]]; then
      value="$($SUDO awk -F= '/^SITE_NAME=/ {v=$2} END {gsub(/^\"|\"$/, "", v); gsub(/^'\''|'\''$/, "", v); print v}' "$file" 2>/dev/null || true)"
      if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
        return 0
      fi
    fi
  done
  return 1
}

load_saved_config_if_available() {
  local saved=""

  if [[ "$SITE_NAME_ENV_PROVIDED" -eq 1 ]]; then
    SITE_NAME_SOURCE="environment"
    validate_site_name_value "$SITE_NAME" || exit 1
    maybe_warn_site_name "$SITE_NAME"
    return 0
  fi

  if saved="$(read_saved_site_name 2>/dev/null)" && [[ -n "$saved" ]]; then
    if validate_site_name_value "$saved" >/dev/null 2>&1; then
      SITE_NAME="$saved"
      SITE_NAME_SOURCE="saved config"
      return 0
    else
      warn "Saved SITE_NAME in config is invalid. Falling back to ${SITE_NAME}."
    fi
  fi

  SITE_NAME_SOURCE="default"
  validate_site_name_value "$SITE_NAME" || exit 1
}

load_future_domain_config_if_available() {
  local saved=""

  if [[ -z "$PRODUCTION_DOMAIN" ]]; then
    if saved="$(read_saved_config_value PRODUCTION_DOMAIN 2>/dev/null)" && [[ -n "$saved" ]]; then
      PRODUCTION_DOMAIN="$saved"
    fi
  fi

  if saved="$(read_saved_config_value DEPLOYMENT_MODE 2>/dev/null)" && [[ -n "$saved" && "${DEPLOYMENT_MODE}" == "development" ]]; then
    DEPLOYMENT_MODE="$saved"
  fi

  if saved="$(read_saved_config_value PRODUCTION_SSL_MODE 2>/dev/null)" && [[ -n "$saved" && "${PRODUCTION_SSL_MODE}" == "planned" ]]; then
    PRODUCTION_SSL_MODE="$saved"
  fi
}

validate_production_domain_value() {
  local domain="$1"

  [[ -n "$domain" ]] || return 1
  if [[ "$domain" =~ ^https?:// ]]; then
    err "Use only the domain, not http:// or https://."
    return 1
  fi
  if [[ "$domain" == *":"* || "$domain" == *"/"* || "$domain" =~ [[:space:]] ]]; then
    err "Domain must not contain spaces, slashes, or ports."
    return 1
  fi
  if [[ "$domain" == *.local || "$domain" == *.test ]]; then
    err "Production domain must be a real DNS name, not .local or .test."
    return 1
  fi
  if ! [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
    err "Invalid production domain: ${domain}"
    return 1
  fi
  return 0
}

prompt_for_site_name_if_needed() {
  local reply normalized

  if [[ "$SITE_NAME_ENV_PROVIDED" -eq 1 ]]; then
    validate_site_name_value "$SITE_NAME" || fail "Invalid SITE_NAME override."
    maybe_warn_site_name "$SITE_NAME"
    echo "Using site: ${SITE_NAME}"
    return 0
  fi

  if [[ "$SITE_NAME_SOURCE" == "saved config" ]]; then
    echo "Using site: ${SITE_NAME}"
    return 0
  fi

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    while true; do
      read -r -p "Local site name [${SITE_NAME}]: " reply
      reply="${reply:-$SITE_NAME}"
      normalized="${reply,,}"

      if validate_site_name_value "$normalized" >/dev/null 2>&1; then
        SITE_NAME="$normalized"
        SITE_NAME_SOURCE="setup prompt"
        maybe_warn_site_name "$SITE_NAME"
        echo "Using site: ${SITE_NAME}"
        return 0
      fi

      echo "Invalid site name. Use a hostname like erp.test, no URL or port."
    done
  else
    validate_site_name_value "$SITE_NAME" || fail "Invalid local site name."
    echo "Using site: ${SITE_NAME}"
  fi
}

write_dev_config_file() {
  require_sudo

  log "Writing ERPNext developer config"

  local config_dir legacy_dir
  config_dir="$(dirname "$CONFIG_FILE")"
  legacy_dir="$(dirname "$LEGACY_CONFIG_FILE")"

  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$CONFIG_FILE" >/dev/null <<EOF_DEV_CONFIG
# ERPNext Developer Installer local configuration
# Non-secret settings only. Credentials are stored separately.
SITE_NAME=${SITE_NAME}
DEPLOYMENT_MODE=${DEPLOYMENT_MODE}
PRODUCTION_DOMAIN=${PRODUCTION_DOMAIN}
PRODUCTION_SSL_MODE=${PRODUCTION_SSL_MODE}
FRAPPE_USER=${FRAPPE_USER}
BENCH_PARENT=${BENCH_PARENT}
BENCH_NAME=${BENCH_NAME}
BENCH_DIR=${BENCH_DIR}
EOF_DEV_CONFIG
  $SUDO chown root:root "$CONFIG_FILE" || true
  $SUDO chmod 644 "$CONFIG_FILE" || true

  # Keep the legacy user-home config as a compatibility mirror for older workflows.
  if [[ "$LEGACY_CONFIG_FILE" != "$CONFIG_FILE" ]]; then
    $SUDO mkdir -p "$legacy_dir" || true
    $SUDO tee "$LEGACY_CONFIG_FILE" >/dev/null <<EOF_LEGACY_DEV_CONFIG
# ERPNext Developer Installer local configuration
# Compatibility mirror. Primary config: ${CONFIG_FILE}
SITE_NAME=${SITE_NAME}
DEPLOYMENT_MODE=${DEPLOYMENT_MODE}
PRODUCTION_DOMAIN=${PRODUCTION_DOMAIN}
PRODUCTION_SSL_MODE=${PRODUCTION_SSL_MODE}
FRAPPE_USER=${FRAPPE_USER}
BENCH_PARENT=${BENCH_PARENT}
BENCH_NAME=${BENCH_NAME}
BENCH_DIR=${BENCH_DIR}
EOF_LEGACY_DEV_CONFIG
    if id "$FRAPPE_USER" >/dev/null 2>&1; then
      $SUDO chown "$FRAPPE_USER:$FRAPPE_USER" "$LEGACY_CONFIG_FILE" || true
    fi
    $SUDO chmod 644 "$LEGACY_CONFIG_FILE" || true
  fi

  ok "Config saved to ${CONFIG_FILE}"
}

show_site_config() {
  require_sudo

  local saved="missing" legacy_saved="missing" vm_ip
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  if [[ -r "$CONFIG_FILE" ]]; then
    saved="present"
  elif [[ -e "$CONFIG_FILE" ]]; then
    saved="unreadable"
  fi
  if [[ -r "$LEGACY_CONFIG_FILE" ]]; then
    legacy_saved="present"
  elif [[ -e "$LEGACY_CONFIG_FILE" ]]; then
    legacy_saved="unreadable"
  fi

  echo
  echo "============================================================"
  echo "ERPNext Local Site / Domain Config"
  echo "============================================================"
  status_line "Current site" "INFO" "$SITE_NAME"
  status_line "Site source" "INFO" "$SITE_NAME_SOURCE"
  status_line "Config file" "INFO" "${CONFIG_FILE} (${saved})"
  status_line "Legacy config" "INFO" "${LEGACY_CONFIG_FILE} (${legacy_saved})"
  status_line "Expected bench" "INFO" "$BENCH_DIR"
  status_line "VM IP" "INFO" "$vm_ip"
  echo
  echo "Friendly HTTP URL:"
  echo "  http://${SITE_NAME}:8000"
  echo
  echo "Local HTTPS URL, after local SSL is configured:"
  echo "  https://${SITE_NAME}"
  echo
  echo "Host /etc/hosts command:"
  echo "  sudo sed -i '/[[:space:]]${SITE_NAME//./\\.}\$/d' /etc/hosts"
  echo "  echo \"${vm_ip} ${SITE_NAME}\" | sudo tee -a /etc/hosts"
  echo
  echo "To choose a custom site during a fresh setup:"
  echo "  SITE_NAME=erp107.test ./install-erpnext-dev.sh setup"
  echo
  echo "Or run setup interactively and answer the site-name prompt."
  echo "============================================================"
}


repair_site_config() {
  require_sudo

  local bench_dir
  bench_dir="$(active_bench_dir)"

  if ! validate_site_name_value "$SITE_NAME" >/dev/null 2>&1; then
    fail "Resolved site name is invalid: ${SITE_NAME}"
  fi

  if [[ ! -d "${bench_dir}/sites/${SITE_NAME}" ]]; then
    fail "Cannot repair config because site folder is missing: ${bench_dir}/sites/${SITE_NAME}"
  fi

  write_dev_config_file

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    run_as_frappe "cd '${bench_dir}' && bench use '${SITE_NAME}' && bench set-config -g default_site '${SITE_NAME}'" || warn "Could not update Bench default site automatically."
  fi

  ok "Site config repaired for ${SITE_NAME}"
  show_site_config
}

show_site_name_guide() {
  echo
  echo "============================================================"
  echo "Custom Local Site Name Guide"
  echo "============================================================"
  echo
  echo "Use a unique .test hostname for each ERPNext VM."
  echo
  echo "Examples:"
  echo "  erp.test"
  echo "  erp107.test"
  echo "  school.test"
  echo "  client-a.test"
  echo
  echo "Fresh install with a custom name:"
  echo "  SITE_NAME=erp107.test ./install-erpnext-dev.sh setup"
  echo
  echo "During interactive setup, you can also type the site name when prompted."
  echo
  echo "After setup, map the name on the HOST machine:"
  echo "  echo \"VM_IP erp107.test\" | sudo tee -a /etc/hosts"
  echo
  echo "Rules:"
  echo "  - Do not include http:// or https://"
  echo "  - Do not include :8000"
  echo "  - Do not use spaces or slashes"
  echo "  - Avoid .local because it conflicts with mDNS/Avahi"
  echo "  - Prefer .test for local development"
  echo
  echo "The selected site name is saved in:"
  echo "  ${CONFIG_FILE}"
  echo
  echo "Future commands reuse the saved name automatically."
  echo "============================================================"
}

load_saved_config_if_available
load_future_domain_config_if_available


start_erpnext_foreground() {
  log "Starting ERPNext development server in foreground"

  local bench_dir
  bench_dir="$(require_bench_dir)" || return 1

  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "ERPNext will start in development mode."
  echo
  echo "Keep this terminal open while using ERPNext."
  echo
  echo "Direct browser URL, works immediately while Bench is running:"
  echo "  http://${vm_ip}:8000"
  echo
  echo "Friendly browser URL, works only after the HOST /etc/hosts entry is configured:"
  echo "  http://${SITE_NAME}:8000"
  echo
  echo "If ${SITE_NAME} does not open, use the direct IP URL first, then run:"
  echo "  ./install-erpnext-dev.sh access"
  echo

  $SUDO -iu "$FRAPPE_USER" bash -lc "
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    cd \"${bench_dir}\"
    bench start
  "
}


erpnext_service_path() {
  echo "/etc/systemd/system/${ERPNEXT_SERVICE_NAME}"
}

service_exists() {
  [[ -f "$(erpnext_service_path)" ]]
}


port_listens() {
  local port="$1"
  nc -z 127.0.0.1 "$port" >/dev/null 2>&1
}

bench_ports_ready() {
  port_listens 8000 && port_listens 9000 && port_listens 11000 && port_listens 13000
}

bench_ready_count() {
  local count=0
  local port

  for port in 8000 9000 11000 13000; do
    if port_listens "$port"; then
      count=$((count + 1))
    fi
  done

  echo "$count"
}

bench_readiness_line() {
  local elapsed="$1"
  local timeout="$2"
  local web socket queue cache

  if port_listens 8000; then web="OK"; else web="wait"; fi
  if port_listens 9000; then socket="OK"; else socket="wait"; fi
  if port_listens 11000; then queue="OK"; else queue="wait"; fi
  if port_listens 13000; then cache="OK"; else cache="wait"; fi

  printf "  [%3ss/%3ss] web: %-4s socket: %-4s queue: %-4s cache: %-4s\n" \
    "$elapsed" "$timeout" "$web" "$socket" "$queue" "$cache"
}

wait_for_erpnext_ready() {
  local timeout="${1:-$READY_TIMEOUT}"
  local interval="${2:-$READY_INTERVAL}"
  local elapsed=0

  echo
  echo "Waiting for ERPNext services to become ready..."
  echo "This can take 15-90 seconds after start/restart."
  echo

  while (( elapsed <= timeout )); do
    bench_readiness_line "$elapsed" "$timeout"

    if bench_ports_ready; then
      ok "ERPNext is ready. Required development ports are listening."
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  warn "ERPNext did not become fully ready within ${timeout}s."
  echo
  echo "Useful checks:"
  echo "  ./install-erpnext-dev.sh runtime-status"
  echo "  ./install-erpnext-dev.sh logs"
  echo "  sudo systemctl status ${ERPNEXT_SERVICE_NAME} --no-pager -l"
  return 1
}

show_access_when_ready() {
  if port_listens 8000; then
    show_access_instructions
  else
    warn "Browser access was not shown because web port 8000 is not listening yet."
    echo "Run this after a few seconds:"
    echo "  ./install-erpnext-dev.sh runtime-status"
  fi
}

show_ready_summary() {
  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "ERPNext Ready"
  echo "============================================================"
  echo "ERPNext is running and the required development ports are listening."
  echo
  echo "Open one of these URLs:"
  echo "  Direct IP:    http://${vm_ip}:8000"
  echo "  Friendly URL: http://${SITE_NAME}:8000"
  echo
  echo "Friendly URL note: your HOST /etc/hosts must map ${SITE_NAME} to ${vm_ip}."
  echo "For full access instructions, run: ./install-erpnext-dev.sh access"
  echo "============================================================"
}

path_is_dir() {
  local path="$1"

  [[ -d "$path" ]] && return 0

  if [[ "${SUDO:-}" == "sudo" ]]; then
    $SUDO test -d "$path" 2>/dev/null
  else
    test -d "$path" 2>/dev/null
  fi
}

path_is_file() {
  local path="$1"

  [[ -f "$path" ]] && return 0

  if [[ "${SUDO:-}" == "sudo" ]]; then
    $SUDO test -f "$path" 2>/dev/null
  else
    test -f "$path" 2>/dev/null
  fi
}

path_is_executable() {
  local path="$1"

  [[ -x "$path" ]] && return 0

  if [[ "${SUDO:-}" == "sudo" ]]; then
    $SUDO test -x "$path" 2>/dev/null
  else
    test -x "$path" 2>/dev/null
  fi
}

bench_dir_is_valid() {
  local candidate="$1"

  path_is_dir "$candidate" && path_is_dir "$candidate/apps/frappe" && path_is_dir "$candidate/sites"
}

require_bench_dir() {
  local bench_dir

  if bench_dir="$(detect_bench_dir 2>/dev/null)" && path_is_dir "$bench_dir"; then
    echo "$bench_dir"
    return 0
  fi

  err "Bench folder not found. Expected one of:"
  bench_dir_candidates | awk '{print "  - " $0}' >&2
  err "Run Recommended Setup first, or run: ./install-erpnext-dev.sh install-status"
  return 1
}


erpnext_vm_context_detected() {
  local candidate

  # Do not use sudo here. This is a safety check that should run without
  # modifying the host or prompting for a password.
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    if [[ -d "$candidate/apps/frappe" && -d "$candidate/sites" ]]; then
      return 0
    fi
  done < <(bench_dir_candidates 2>/dev/null | awk '!seen[$0]++')

  [[ -f "$(erpnext_service_path)" ]] && return 0
  [[ -x "${FRAPPE_HOME}/start-erpnext-dev.sh" ]] && return 0
  [[ -f "${FRAPPE_HOME}/erpnext-dev-credentials.txt" ]] && return 0

  return 1
}

show_environment_check() {
  local host user cwd vm_ip detected_bench="missing"
  host="$(hostname 2>/dev/null || echo unknown)"
  user="$(id -un 2>/dev/null || echo unknown)"
  cwd="$(pwd 2>/dev/null || echo unknown)"
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"

  if detect_bench_dir >/dev/null 2>&1; then
    detected_bench="$(detect_bench_dir 2>/dev/null || true)"
  fi

  echo
  echo "============================================================"
  echo "Environment / Location Check"
  echo "============================================================"
  status_line "Current host" "INFO" "$host"
  status_line "Current user" "INFO" "$user"
  status_line "Current directory" "INFO" "$cwd"
  status_line "Detected IP" "INFO" "$vm_ip"
  status_line "Expected site" "INFO" "$SITE_NAME"
  status_line "Site source" "INFO" "$SITE_NAME_SOURCE"
  status_line "Config file" "INFO" "$CONFIG_FILE"
  status_line "Expected bench" "INFO" "$BENCH_DIR"
  if [[ "$detected_bench" == "missing" ]] && { service_exists || path_is_file "${FRAPPE_HOME}/erpnext-dev-credentials.txt" || path_is_executable "${FRAPPE_HOME}/start-erpnext-dev.sh"; }; then
    detected_bench="${BENCH_DIR} (expected; run doctor for sudo-confirmed status)"
  fi
  status_line "Detected bench" "INFO" "$detected_bench"

  if erpnext_vm_context_detected; then
    status_line "ERPNext VM context" "OK" "this looks like the ERPNext VM"
    echo
    echo "VM-only actions are allowed here, including:"
    echo "  ./install-erpnext-dev.sh ssl-status"
    echo "  ./install-erpnext-dev.sh configure-local-ssl"
    echo "  ./install-erpnext-dev.sh install-local-ssl-cert"
  else
    status_line "ERPNext VM context" "WARN" "not detected"
    echo
    echo "This looks like the HOST machine, not the ERPNext VM."
    echo
    echo "Run VM-only commands after SSHing into the VM, for example:"
    echo "  ssh test@VM_IP"
    echo
    echo "Host-side commands are OK here, for example:"
    echo "  mkcert -install"
    echo "  mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} VM_IP"
    echo "  scp ${SITE_NAME}.crt test@VM_IP:/tmp/${SITE_NAME}.crt"
    echo "  curl -I http://${SITE_NAME}"
    echo "  curl -kI https://${SITE_NAME}"
  fi

  echo "============================================================"
}

show_vm_only_guard_message() {
  local action="$1"
  local vm_ip
  vm_ip="$(get_vm_ip 2>/dev/null || true)"

  echo
  echo "============================================================"
  echo "Wrong Machine / VM-Only Command Guard"
  echo "============================================================"
  warn "The command '${action}' must be run inside the ERPNext VM."
  echo
  echo "This script did not detect the ERPNext bench, service, helper, or credentials on this machine."
  echo "To avoid changing the Linux Mint HOST by mistake, the command was blocked before sudo work."
  echo
  echo "Current machine:"
  echo "  Hostname: $(hostname 2>/dev/null || echo unknown)"
  echo "  User:     $(id -un 2>/dev/null || echo unknown)"
  echo "  Folder:   $(pwd 2>/dev/null || echo unknown)"
  echo
  echo "Run this command inside the VM instead. Example:"
  if [[ -n "$vm_ip" && "$vm_ip" != "unknown" ]]; then
    echo "  ssh test@${vm_ip}"
  else
    echo "  ssh test@VM_IP"
  fi
  echo "  ./install-erpnext-dev.sh ${action}"
  echo
  echo "Commands that belong on the HOST:"
  echo "  mkcert -install"
  echo "  mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} VM_IP"
  echo "  scp ${SITE_NAME}.crt test@VM_IP:/tmp/${SITE_NAME}.crt"
  echo "  scp ${SITE_NAME}.key test@VM_IP:/tmp/${SITE_NAME}.key"
  echo "  curl -I http://${SITE_NAME}"
  echo "  curl -kI https://${SITE_NAME}"
  echo
  echo "To check where you are, run:"
  echo "  ./install-erpnext-dev.sh environment-check"
  echo "============================================================"
}

require_erpnext_vm_context() {
  local action="$1"
  if erpnext_vm_context_detected; then
    return 0
  fi
  show_vm_only_guard_message "$action"
  return 1
}

create_erpnext_service() {
  require_sudo

  local bench_dir
  if ! bench_dir="$(require_bench_dir)"; then
    return 1
  fi

  log "Creating ERPNext development systemd service"

  $SUDO tee "$(erpnext_service_path)" >/dev/null <<EOF_SERVICE
[Unit]
Description=ERPNext Frappe Bench Development Server (${SITE_NAME})
After=network-online.target mariadb.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=${FRAPPE_USER}
Group=${FRAPPE_USER}
WorkingDirectory=${bench_dir}
Environment=HOME=${FRAPPE_HOME}
ExecStart=/bin/bash -lc 'export NVM_DIR="\$HOME/.nvm"; [ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"; export PATH="\$HOME/.local/bin:\$PATH"; cd "${bench_dir}" && bench start'
Restart=on-failure
RestartSec=10
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  $SUDO systemctl daemon-reload
  ok "Service created: ${ERPNEXT_SERVICE_NAME}"
}

enable_autostart_service() {
  require_sudo

  if ! service_exists; then
    create_erpnext_service || return 1
  fi

  log "Enabling ERPNext autostart on VM boot"
  if $SUDO systemctl enable "${ERPNEXT_SERVICE_NAME}"; then
    ok "Autostart enabled"
  else
    err "Could not enable autostart for ${ERPNEXT_SERVICE_NAME}"
    return 1
  fi
}

disable_autostart_service() {
  require_sudo

  if service_exists; then
    log "Disabling ERPNext autostart"
    $SUDO systemctl disable "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
    ok "Autostart disabled"
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

start_erpnext_service() {
  require_sudo

  if ! service_exists; then
    create_erpnext_service || return 1
  fi

  log "Starting ERPNext service"
  if $SUDO systemctl start "${ERPNEXT_SERVICE_NAME}"; then
    ok "ERPNext service start command completed"
    if wait_for_erpnext_ready; then
      show_ready_summary
    else
      return 1
    fi
  else
    err "Could not start ${ERPNEXT_SERVICE_NAME}. Check logs with: ./install-erpnext-dev.sh logs"
    return 1
  fi
}

stop_erpnext_service() {
  require_sudo

  if service_exists; then
    log "Stopping ERPNext service"
    $SUDO systemctl stop "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
    ok "ERPNext service stopped"
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    $SUDO pkill -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1 || true
    $SUDO pkill -u "$FRAPPE_USER" -f "frappe.utils.bench_helper" >/dev/null 2>&1 || true
  fi
}

restart_erpnext_service() {
  require_sudo

  if ! service_exists; then
    create_erpnext_service || return 1
  fi

  log "Restarting ERPNext service"
  if $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}"; then
    ok "ERPNext service restart command completed"
    if wait_for_erpnext_ready; then
      show_ready_summary
    else
      return 1
    fi
  else
    err "Could not restart ${ERPNEXT_SERVICE_NAME}. Check logs with: ./install-erpnext-dev.sh logs"
    return 1
  fi
}

show_erpnext_service_status() {
  require_sudo

  if service_exists; then
    $SUDO systemctl status "${ERPNEXT_SERVICE_NAME}" --no-pager || true
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

show_erpnext_service_logs() {
  require_sudo

  if service_exists; then
    $SUDO journalctl -u "${ERPNEXT_SERVICE_NAME}" -n 160 --no-pager || true
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

follow_erpnext_service_logs() {
  require_sudo

  if service_exists; then
    $SUDO journalctl -u "${ERPNEXT_SERVICE_NAME}" -f
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

start_erpnext() {
  start_erpnext_service
}


random_password() {
  python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(28)))
PY
}

confirm() {
  local prompt="${1:-Continue?}"

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    ok "$prompt yes"
    return 0
  fi

  read -r -p "$prompt [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$|^[Yy][Ee][Ss]$ ]]
}

pause_after_screen() {
  local prompt="${1:-Press Enter to return...}"

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    echo
    read -r -p "$prompt" _
  fi
}

require_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO=""
  else
    sudo -v || fail "This command requires sudo access."
    SUDO="sudo"
  fi

  # After sudo is available, resolve the real site from the readable config,
  # the legacy config, currentsite.txt, common_site_config.json, or the single
  # installed site folder. This prevents commands from falling back to erp.test
  # when a custom site such as erp208.test already exists.
  resolve_site_name_after_sudo 2>/dev/null || true
}

frappe_shell_prefix() {
  # Keep this as a semicolon-separated single line.
  # Some sudo/su command paths can collapse multiline command substitution, which breaks
  # constructs like: export NVM_DIR=...if [ -s ... ]. Semicolons make the prefix robust.
  cat <<'EOF_PREFIX'
export PATH="$HOME/.local/bin:$PATH"; export NVM_DIR="$HOME/.nvm"; if [ -s "$NVM_DIR/nvm.sh" ]; then . "$NVM_DIR/nvm.sh"; fi; if command -v node >/dev/null 2>&1; then export PATH="$(dirname "$(command -v node)"):$PATH"; fi;
EOF_PREFIX
}

run_as_frappe() {
  local cmd="$1"
  local prefix
  local tmp_script
  local rc

  if ! id "$FRAPPE_USER" >/dev/null 2>&1; then
    return 1
  fi

  prefix="$(frappe_shell_prefix)"
  tmp_script="$(mktemp /tmp/erpnext-dev-frappe-run.XXXXXX.sh)" || return 1

  {
    echo '#!/usr/bin/env bash'
    echo 'set -o pipefail'
    echo "$prefix"
    echo "$cmd"
  } > "$tmp_script"

  chmod 700 "$tmp_script"

  if [[ "${EUID}" -eq 0 ]]; then
    chown "$FRAPPE_USER:$FRAPPE_USER" "$tmp_script" 2>/dev/null || true
    su - "$FRAPPE_USER" -s /bin/bash -c "bash '$tmp_script'"
    rc=$?
    rm -f "$tmp_script"
  else
    sudo chown "$FRAPPE_USER:$FRAPPE_USER" "$tmp_script" 2>/dev/null || true
    sudo -iu "$FRAPPE_USER" bash "$tmp_script"
    rc=$?
    sudo rm -f "$tmp_script" 2>/dev/null || rm -f "$tmp_script"
  fi

  return "$rc"
}

check_os() {
  log "Checking operating system"

  if [[ ! -f /etc/os-release ]]; then
    fail "Cannot detect OS. /etc/os-release not found."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID}" != "ubuntu" ]]; then
    fail "This script is designed for Ubuntu Server 24.04 or 26.04. Detected: ${PRETTY_NAME:-unknown}"
  fi

  case "${VERSION_ID}" in
    "24.04") ok "Ubuntu 24.04 LTS detected" ;;
    "26.04") ok "Ubuntu 26.04 LTS detected" ;;
    *) fail "Unsupported Ubuntu version: ${PRETTY_NAME:-Ubuntu ${VERSION_ID}}. Supported: Ubuntu 24.04 LTS and Ubuntu 26.04 LTS." ;;
  esac
}

check_internet() {
  log "Checking internet access"

  if curl -fsI --connect-timeout 10 https://github.com >/dev/null 2>&1; then
    ok "Internet access confirmed"
  else
    fail "Cannot reach GitHub. Check DNS/internet access, then rerun."
  fi
}

check_resources() {
  log "Checking VM resources"

  local mem_mb disk_gb
  mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  disk_gb="$(df -BG / | awk 'NR==2 {gsub("G", "", $4); print $4}' 2>/dev/null || echo 0)"

  if [[ "$mem_mb" -lt 4096 ]]; then
    warn "RAM is ${mem_mb} MB. Recommended minimum is 4096 MB; 8192 MB is better."
  else
    ok "RAM: ${mem_mb} MB"
  fi

  if [[ "$disk_gb" -lt 30 ]]; then
    warn "Available disk space is ${disk_gb} GB. Recommended minimum is 60 GB."
  else
    ok "Available disk: ${disk_gb} GB"
  fi
}

# ============================================================
# Generic root storage detection / expansion
# ============================================================

bytes_to_gib() {
  local bytes="${1:-0}"
  python3 - "$bytes" <<'PY_GIB'
import sys
try:
    b = int(float(sys.argv[1]))
except Exception:
    b = 0
print(f"{round(b / (1024 ** 3))}G")
PY_GIB
}

storage_part_number() {
  local part_name
  part_name="$(basename "$1")"

  if [[ "$part_name" =~ p([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$part_name" =~ ([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

storage_parent_disk() {
  local part_dev="$1"
  local parent=""
  parent="$(lsblk -no PKNAME "$part_dev" 2>/dev/null | head -n 1 | tr -d '[:space:]' || true)"
  [[ -n "$parent" ]] || return 1
  printf '/dev/%s\n' "$parent"
}



storage_infer_disk_from_partition() {
  local part_dev="$1"
  local disk_dev=""

  # Common Linux partition names:
  # /dev/vda3, /dev/sda3, /dev/xvda3, /dev/nvme0n1p3, /dev/mmcblk0p3
  if [[ "$part_dev" =~ ^(/dev/(nvme[0-9]+n[0-9]+|mmcblk[0-9]+))p([0-9]+)$ ]]; then
    disk_dev="${BASH_REMATCH[1]}"
  elif [[ "$part_dev" =~ ^(/dev/[a-zA-Z]+[a-zA-Z0-9]*)([0-9]+)$ ]]; then
    disk_dev="${BASH_REMATCH[1]}"
  fi

  if [[ -n "$disk_dev" && -b "$disk_dev" ]]; then
    printf '%s\n' "$disk_dev"
    return 0
  fi

  return 1
}

storage_root_lsblk_value() {
  local key line
  key="$1"
  line="$(lsblk -P -o NAME,TYPE,PKNAME,MOUNTPOINTS 2>/dev/null | awk 'index($0, "MOUNTPOINTS=\"/\"") {print; exit}')"
  [[ -n "$line" ]] || return 1
  printf '%s\n' "$line" | sed -n "s/.*${key}=\"\([^\"]*\)\".*/\1/p"
}

storage_detect_layout() {
  # Generic root storage detector.
  # This intentionally uses the exact proven Ubuntu/LVM repair path when it can
  # derive it safely:
  #   sgdisk -e <disk>; growpart <disk> <part>; pvresize <pv>; lvextend -r <lv>
  # It must not hardcode /dev/vda3 or ubuntu-vg names.
  python3 <<'PY_STORAGE_DETECT'
import os
import re
import shlex
import subprocess
import sys


def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def q(v):
    return "" if v is None else str(v).strip()


def emit(**kv):
    for k, v in kv.items():
        if v is not None and str(v) != "":
            print(f"{k}={v}")


def parse_lsblk_p():
    out = run(["lsblk", "-P", "-o", "NAME,KNAME,PATH,TYPE,PKNAME,PARTN,FSTYPE,MOUNTPOINTS,SIZE"])
    rows = []
    for line in out.splitlines():
        try:
            d = dict(re.findall(r'(\w+)="([^"]*)"', line))
        except Exception:
            d = {}
        if d:
            rows.append(d)
    return rows


def parent_disk_and_partnum(part_dev, rows):
    part_dev = os.path.realpath(part_dev)
    base = os.path.basename(part_dev)
    row = None
    for r in rows:
        names = {r.get("NAME",""), r.get("KNAME",""), os.path.basename(r.get("PATH","") or "")}
        if base in names or os.path.realpath(r.get("PATH","") or "/nonexistent") == part_dev:
            row = r
            break
    partn = q(row.get("PARTN")) if row else ""
    pk = q(row.get("PKNAME")) if row else ""
    disk = f"/dev/{pk}" if pk else ""
    if not partn:
        m = re.search(r'p?(\d+)$', os.path.basename(part_dev))
        if m:
            partn = m.group(1)
    if not disk:
        # /dev/vda3, /dev/sda3, /dev/xvda3
        m = re.match(r'^(/dev/[A-Za-z]+[A-Za-z0-9]*?)(\d+)$', part_dev)
        if m:
            disk = m.group(1)
        # /dev/nvme0n1p3, /dev/mmcblk0p3
        m = re.match(r'^(/dev/(?:nvme\d+n\d+|mmcblk\d+))p(\d+)$', part_dev)
        if m:
            disk = m.group(1)
            partn = partn or m.group(2)
    return disk, partn

root_source = q(run(["findmnt", "-n", "-o", "SOURCE", "/"]).splitlines()[0] if run(["findmnt", "-n", "-o", "SOURCE", "/"]) else "")
root_fs = q(run(["findmnt", "-n", "-o", "FSTYPE", "/"]).splitlines()[0] if run(["findmnt", "-n", "-o", "FSTYPE", "/"]) else "")
if not root_source:
    emit(LAYOUT="unknown", ROOT_SOURCE="unknown", ROOT_FS="unknown", REASON="could not read root mount source")
    sys.exit(0)

root_real = os.path.realpath(root_source)
rows = parse_lsblk_p()
root_row = None
for r in rows:
    mp = r.get("MOUNTPOINTS", "")
    if mp == "/" or "/" in mp.split():
        root_row = r
        break

root_type = q(root_row.get("TYPE")) if root_row else q(run(["lsblk", "-no", "TYPE", root_source]).splitlines()[0] if run(["lsblk", "-no", "TYPE", root_source]) else "")

is_lvm = root_type == "lvm" or root_source.startswith("/dev/mapper/") or root_real.startswith("/dev/dm-")

if is_lvm:
    if not run(["bash", "-lc", "command -v lvs && command -v pvs && command -v vgs"]):
        emit(LAYOUT="unknown", ROOT_SOURCE=root_source, ROOT_FS=root_fs, REASON="LVM tools are not available")
        sys.exit(0)

    # Read LVs, matching either /dev/mapper path, canonical /dev/VG/LV, or dm-* real path.
    lv_out = run(["lvs", "--noheadings", "--separator", "|", "-o", "lv_path,vg_name,devices"])
    lv_path = ""
    vg_name = ""
    devices = ""
    first_lv = None
    for line in lv_out.splitlines():
        parts = [x.strip() for x in line.split("|", 2)]
        if len(parts) < 2:
            continue
        cand_lv, cand_vg = parts[0], parts[1]
        cand_devices = parts[2] if len(parts) > 2 else ""
        if not first_lv:
            first_lv = (cand_lv, cand_vg, cand_devices)
        cand_real = os.path.realpath(cand_lv)
        if cand_lv == root_source or cand_lv == root_real or cand_real == root_real:
            lv_path, vg_name, devices = cand_lv, cand_vg, cand_devices
            break
    if not lv_path and first_lv:
        # If there is only one LV on a simple dev VM, this is usually root.
        lvs_count = len([x for x in lv_out.splitlines() if x.strip()])
        if lvs_count == 1:
            lv_path, vg_name, devices = first_lv
    if not lv_path:
        lv_path = root_source
    if not vg_name:
        vg_name = q(run(["lvs", "--noheadings", "-o", "vg_name", lv_path]).splitlines()[0] if run(["lvs", "--noheadings", "-o", "vg_name", lv_path]) else "")

    # Prefer the PV from LV devices, e.g. /dev/vda3(0). This is the exact value that
    # proved correct manually on Ubuntu Server clones.
    pv_dev = ""
    m = re.search(r'(/dev/[^\s,()]+)(?:\(\d+\))?', devices or "")
    if m:
        pv_dev = m.group(1)

    # Fallback: root lsblk row often has PKNAME=vda3 for LVM roots.
    if not pv_dev and root_row and q(root_row.get("PKNAME")):
        maybe = "/dev/" + q(root_row.get("PKNAME"))
        if os.path.exists(maybe):
            pv_dev = maybe

    # Fallback: if the VG has exactly one PV, use it.
    if not pv_dev and vg_name:
        pv_out = run(["pvs", "--noheadings", "--separator", "|", "-o", "pv_name,vg_name"])
        pvs = []
        for line in pv_out.splitlines():
            parts = [x.strip() for x in line.split("|")]
            if len(parts) >= 2 and parts[1] == vg_name:
                pvs.append(re.sub(r'\(\d+\)$', '', parts[0]))
        if len(set(pvs)) == 1:
            pv_dev = sorted(set(pvs))[0]

    disk_dev = ""
    part_num = ""
    if pv_dev:
        pv_dev = os.path.realpath(pv_dev)
        disk_dev, part_num = parent_disk_and_partnum(pv_dev, rows)

    # This is the supported automatic LVM path. Even if disk/part cannot be derived,
    # lvextend can still consume existing VG free space safely.
    emit(
        LAYOUT="lvm",
        ROOT_SOURCE=root_source,
        ROOT_FS=root_fs,
        LV_PATH=lv_path,
        VG_NAME=vg_name,
        PV_DEV=pv_dev,
        PART_DEV=pv_dev,
        DISK_DEV=disk_dev,
        PART_NUM=part_num,
        REASON="" if pv_dev else "could not identify LVM PV; only existing VG free space can be used automatically",
    )
    sys.exit(0)

# Direct root partition case.
part_dev = root_real
if root_type == "part" or (root_row and root_row.get("TYPE") == "part"):
    disk_dev, part_num = parent_disk_and_partnum(part_dev, rows)
    emit(LAYOUT="partition", ROOT_SOURCE=part_dev, ROOT_FS=root_fs, PART_DEV=part_dev, DISK_DEV=disk_dev, PART_NUM=part_num)
    sys.exit(0)

emit(LAYOUT="unknown", ROOT_SOURCE=root_source, ROOT_FS=root_fs, REASON="root device is not a supported partition or LVM layout")
PY_STORAGE_DETECT
  return 0
}

storage_eval() {
  local data
  local layout="" root_source="" root_fs="" disk_dev="" part_dev="" pv_dev="" lv_path="" vg_name="" reason=""
  local root_bytes="0" disk_bytes="0" part_bytes="0" vg_free_bytes="0" can_expand="no"

  data="$(storage_detect_layout 2>/dev/null || true)"
  [[ -n "$data" ]] || {
    printf 'LAYOUT=unknown\nCAN_EXPAND=no\nREASON=storage layout could not be detected\n'
    return 0
  }

  while IFS='=' read -r k v; do
    case "$k" in
      LAYOUT) layout="$v" ;;
      ROOT_SOURCE) root_source="$v" ;;
      ROOT_FS) root_fs="$v" ;;
      DISK_DEV) disk_dev="$v" ;;
      PART_DEV) part_dev="$v" ;;
      PV_DEV) pv_dev="$v" ;;
      LV_PATH) lv_path="$v" ;;
      VG_NAME) vg_name="$v" ;;
      REASON) reason="$v" ;;
    esac
  done <<< "$data"

  root_bytes="$(df -B1 / 2>/dev/null | awk 'NR==2 {print $2+0}' || echo 0)"

  if [[ -n "$disk_dev" ]]; then
    disk_bytes="$(lsblk -bndo SIZE "$disk_dev" 2>/dev/null | awk 'NR==1 {print $1+0}' || echo 0)"
  fi

  if [[ -n "$part_dev" ]]; then
    part_bytes="$(lsblk -bndo SIZE "$part_dev" 2>/dev/null | awk 'NR==1 {print $1+0}' || echo 0)"
  fi

  if [[ "$layout" == "lvm" ]]; then
    if [[ -z "$vg_name" && -n "$lv_path" ]]; then
      vg_name="$(lvs --noheadings -o vg_name "$lv_path" 2>/dev/null | awk 'NF {print $1; exit}' || true)"
    fi

    if [[ -n "$vg_name" ]]; then
      vg_free_bytes="$(vgs --noheadings --units b --nosuffix -o vg_free "$vg_name" 2>/dev/null | awk 'NF {printf "%.0f", $1+0; exit}' || echo 0)"
    fi
  fi

  # LVM expansion is recommended if:
  # 1) VG already has free extents, OR
  # 2) the physical disk is larger than the LVM partition/PV.
  if [[ "$layout" == "lvm" ]]; then
    if [[ "$vg_free_bytes" =~ ^[0-9]+$ ]] && (( vg_free_bytes > 1073741824 )); then
      can_expand="yes"
      reason="LVM has free space available"
    elif [[ "$disk_bytes" =~ ^[0-9]+$ && "$part_bytes" =~ ^[0-9]+$ ]] && (( disk_bytes > part_bytes + 1073741824 )); then
      can_expand="yes"
      reason="VM disk is larger than the LVM partition"
    else
      reason="root storage already appears to use available LVM/disk space"
    fi
  elif [[ "$layout" == "partition" ]]; then
    if [[ "$disk_bytes" =~ ^[0-9]+$ && "$part_bytes" =~ ^[0-9]+$ ]] && (( disk_bytes > part_bytes + 1073741824 )); then
      can_expand="yes"
      reason="VM disk is larger than the root partition"
    else
      reason="root partition already appears to use available disk space"
    fi
  else
    can_expand="no"
    reason="${reason:-storage layout is not supported for automatic expansion}"
  fi

  printf '%s\n' "$data"
  printf 'ROOT_BYTES=%s\nDISK_BYTES=%s\nPART_BYTES=%s\nVG_FREE_BYTES=%s\nCAN_EXPAND=%s\nREASON=%s\n' \
    "$root_bytes" "$disk_bytes" "$part_bytes" "$vg_free_bytes" "$can_expand" "$reason"
}

show_storage_status() {
  local data layout root_source root_fs disk_dev part_dev lv_path root_bytes disk_bytes vg_free_bytes can_expand reason

  data="$(storage_eval)"
  while IFS='=' read -r k v; do
    case "$k" in
      LAYOUT) layout="$v" ;;
      ROOT_SOURCE) root_source="$v" ;;
      ROOT_FS) root_fs="$v" ;;
      DISK_DEV) disk_dev="$v" ;;
      PART_DEV) part_dev="$v" ;;
      LV_PATH) lv_path="$v" ;;
      ROOT_BYTES) root_bytes="$v" ;;
      DISK_BYTES) disk_bytes="$v" ;;
      VG_FREE_BYTES) vg_free_bytes="$v" ;;
      CAN_EXPAND) can_expand="$v" ;;
      REASON) reason="$v" ;;
    esac
  done <<< "$data"

  echo
  echo "============================================================"
  echo "Root Storage Status"
  echo "============================================================"
  status_line "Layout" "INFO" "${layout:-unknown}"
  status_line "Root filesystem" "INFO" "${root_source:-unknown} (${root_fs:-unknown})"
  [[ -n "${disk_dev:-}" ]] && status_line "Backing disk" "INFO" "${disk_dev} ($(bytes_to_gib "${disk_bytes:-0}"))"
  [[ -n "${part_dev:-}" ]] && status_line "Root partition/PV" "INFO" "${part_dev}"
  [[ -n "${lv_path:-}" ]] && status_line "Root LV" "INFO" "${lv_path}"
  if [[ "${layout:-}" == "lvm" && "${vg_free_bytes:-0}" =~ ^[0-9]+$ && "${vg_free_bytes:-0}" -gt 0 ]]; then
    status_line "VG free" "INFO" "$(bytes_to_gib "${vg_free_bytes:-0}")"
  fi
  status_line "Root size" "INFO" "$(bytes_to_gib "${root_bytes:-0}")"

  if [[ "${can_expand:-no}" == "yes" ]]; then
    status_line "Expansion" "WARN" "recommended"
    echo
    echo "Run: ./install-erpnext-dev.sh expand-root-storage"
  elif [[ "${layout:-unknown}" == "unknown" ]]; then
    status_line "Expansion" "WARN" "not automatic"
    [[ -n "${reason:-}" ]] && echo "Reason: ${reason}"
  else
    status_line "Expansion" "OK" "not needed"
  fi
  echo "============================================================"
}

ensure_storage_tools() {
  local packages=()

  command -v growpart >/dev/null 2>&1 || packages+=(cloud-guest-utils)
  command -v sgdisk >/dev/null 2>&1 || packages+=(gdisk)

  if [[ "${#packages[@]}" -gt 0 ]]; then
    log "Installing storage resize tools"
    $SUDO apt-get update
    $SUDO apt-get install -y "${packages[@]}"
  fi
}

expand_root_storage() {
  require_sudo

  local data layout root_fs lv_path pv_dev part_dev disk_dev part_num vg_free_bytes can_expand reason

  data="$(storage_eval)"
  while IFS='=' read -r k v; do
    case "$k" in
      LAYOUT) layout="$v" ;;
      ROOT_FS) root_fs="$v" ;;
      LV_PATH) lv_path="$v" ;;
      PV_DEV) pv_dev="$v" ;;
      PART_DEV) part_dev="$v" ;;
      DISK_DEV) disk_dev="$v" ;;
      PART_NUM) part_num="$v" ;;
      VG_FREE_BYTES) vg_free_bytes="$v" ;;
      CAN_EXPAND) can_expand="$v" ;;
      REASON) reason="$v" ;;
    esac
  done <<< "$data"

  echo
  echo "============================================================"
  echo "Expand Root Storage"
  echo "============================================================"

  if [[ "${can_expand:-no}" != "yes" ]]; then
    if [[ "${layout:-unknown}" == "unknown" ]]; then
      status_line "Storage" "WARN" "not automatic"
      [[ -n "${reason:-}" ]] && echo "Reason: ${reason}"
      echo "No changes made."
    else
      status_line "Storage" "OK" "no expansion needed"
      [[ -n "${reason:-}" ]] && echo "${reason}"
    fi
    echo "============================================================"
    return 0
  fi

  if [[ "${layout:-unknown}" != "lvm" && "${layout:-unknown}" != "partition" ]]; then
    status_line "Storage" "WARN" "layout not supported"
    [[ -n "${reason:-}" ]] && echo "Reason: ${reason}"
    echo "No changes made."
    echo "============================================================"
    return 0
  fi

  if [[ "$layout" != "lvm" && ( -z "${disk_dev:-}" || -z "${part_num:-}" || -z "${part_dev:-}" ) ]]; then
    status_line "Storage" "WARN" "could not identify disk/partition safely"
    echo "No changes made."
    echo "============================================================"
    return 0
  fi

  [[ -n "${disk_dev:-}" ]] && status_line "Target disk" "INFO" "$disk_dev"
  [[ -n "${part_dev:-}" ]] && status_line "Target partition" "INFO" "$part_dev"
  [[ -n "${lv_path:-}" ]] && status_line "Target LV" "INFO" "$lv_path"
  status_line "Layout" "INFO" "$layout"

  if [[ "${EXPAND_ROOT_CONFIRMED:-0}" != "1" && "$ASSUME_YES" -ne 1 ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Expand root storage now? [Y/n]: " reply
      reply="${reply:-Y}"
      if ! [[ "$reply" =~ ^[Yy]$ ]]; then
        warn "Storage expansion skipped."
        echo "============================================================"
        return 0
      fi
    fi
  fi

  ensure_storage_tools

  if [[ "$layout" == "lvm" ]]; then
    if ! command -v pvresize >/dev/null 2>&1 || ! command -v lvextend >/dev/null 2>&1; then
      log "Installing LVM tools"
      $SUDO apt-get install -y lvm2
    fi

    if [[ -n "${disk_dev:-}" && -n "${part_num:-}" && -n "${part_dev:-}" ]]; then
      log "Growing partition ${part_dev}"
      if command -v sgdisk >/dev/null 2>&1; then
        $SUDO sgdisk -e "$disk_dev" >/dev/null 2>&1 || true
      fi
      $SUDO partprobe "$disk_dev" >/dev/null 2>&1 || true
      if ! $SUDO growpart "$disk_dev" "$part_num"; then
        warn "growpart did not report a clean change. Continuing with LVM resize if possible."
      fi
      $SUDO partprobe "$disk_dev" >/dev/null 2>&1 || true
      log "Growing LVM physical volume"
      $SUDO pvresize "${pv_dev:-$part_dev}"
    else
      warn "Could not safely grow the LVM physical partition. Using existing VG free space only."
    fi

    log "Extending root logical volume"
    $SUDO lvextend -r -l +100%FREE "$lv_path"
  else
    log "Growing partition ${part_dev}"
    if command -v sgdisk >/dev/null 2>&1; then
      $SUDO sgdisk -e "$disk_dev" >/dev/null 2>&1 || true
    fi
    $SUDO partprobe "$disk_dev" >/dev/null 2>&1 || true

    if ! $SUDO growpart "$disk_dev" "$part_num"; then
      warn "growpart did not report a clean change. Continuing with filesystem resize if possible."
    fi
    $SUDO partprobe "$disk_dev" >/dev/null 2>&1 || true
    case "$root_fs" in
      ext2|ext3|ext4)
        log "Growing ${root_fs} filesystem"
        $SUDO resize2fs "$part_dev"
        ;;
      xfs)
        log "Growing XFS filesystem"
        $SUDO xfs_growfs /
        ;;
      *)
        warn "Filesystem ${root_fs:-unknown} is not supported for automatic resize."
        warn "Partition was grown if possible, but filesystem was not changed."
        ;;
    esac
  fi

  ok "Root storage expansion completed"
  show_storage_status
}

storage_debug() {
  echo
  echo "============================================================"
  echo "Storage Debug"
  echo "============================================================"
  echo "findmnt:"
  findmnt -no SOURCE,FSTYPE,SIZE,AVAIL / || true
  echo
  echo "lsblk:"
  lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,PKNAME,PARTN || true
  echo
  echo "lvs:"
  sudo lvs -o lv_path,vg_name,lv_size,devices 2>/dev/null || true
  echo
  echo "pvs:"
  sudo pvs -o pv_name,vg_name,pv_size,pv_free 2>/dev/null || true
  echo
  echo "vgs:"
  sudo vgs -o vg_name,vg_size,vg_free 2>/dev/null || true
  echo
  echo "detector:"
  storage_detect_layout || true
  echo "============================================================"
}

verify_storage() {
  local free_gb
  free_gb="$(df -BG / | awk 'NR==2 {gsub("G", "", $4); print $4}' 2>/dev/null || echo 0)"

  show_storage_status

  if [[ "$free_gb" -lt 30 ]]; then
    warn "Root free space is ${free_gb}G. ERPNext can install, but 60G+ is recommended."
    return 1
  fi

  ok "Root free space: ${free_gb}G"
}

maybe_offer_root_storage_expansion() {
  local data can_expand root_bytes disk_bytes vg_free_bytes layout reply

  data="$(storage_eval)"
  while IFS='=' read -r k v; do
    case "$k" in
      CAN_EXPAND) can_expand="$v" ;;
      ROOT_BYTES) root_bytes="$v" ;;
      DISK_BYTES) disk_bytes="$v" ;;
      VG_FREE_BYTES) vg_free_bytes="$v" ;;
      LAYOUT) layout="$v" ;;
    esac
  done <<< "$data"

  if [[ "${can_expand:-no}" != "yes" ]]; then
    return 0
  fi

  echo
  if [[ "${disk_bytes:-0}" =~ ^[0-9]+$ && "${disk_bytes:-0}" -gt 0 ]]; then
    echo "Storage: root uses $(bytes_to_gib "${root_bytes:-0}") of $(bytes_to_gib "${disk_bytes:-0}") disk."
  elif [[ "${layout:-}" == "lvm" && "${vg_free_bytes:-0}" =~ ^[0-9]+$ && "${vg_free_bytes:-0}" -gt 0 ]]; then
    echo "Storage: root can use $(bytes_to_gib "${vg_free_bytes:-0}") free LVM space."
  else
    echo "Storage expansion is available."
  fi

  if [[ "${AUTO_EXPAND_ROOT:-prompt}" == "false" ]]; then
    warn "Root storage expansion skipped by AUTO_EXPAND_ROOT=false."
    return 0
  fi

  if [[ "${AUTO_EXPAND_ROOT:-prompt}" == "true" || "$ASSUME_YES" -eq 1 ]]; then
    EXPAND_ROOT_CONFIRMED=1 expand_root_storage
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -p "Expand root storage now? [Y/n]: " reply
    reply="${reply:-Y}"
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      EXPAND_ROOT_CONFIRMED=1 expand_root_storage
    else
      warn "Storage expansion skipped."
    fi
  fi
}


apt_package_available() {
  local package="$1"
  local candidate

  candidate="$(apt-cache policy "$package" | awk '/Candidate:/ {print $2}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

install_required_packages() {
  log "Installing required system packages"

  $SUDO apt-get update
  $SUDO apt-get install -y "$@"
}

install_optional_package() {
  local package="$1"

  if apt_package_available "$package"; then
    $SUDO apt-get install -y "$package"
    ok "Optional package installed: $package"
  else
    warn "Optional package not available from apt: $package"
    warn "Continuing without $package. ERPNext can install, but PDF generation may need manual setup later."
  fi
}

install_system_packages() {
  log "Installing system packages"

  install_required_packages \
    git curl wget nano ca-certificates gnupg lsb-release \
    software-properties-common build-essential pkg-config \
    redis-server mariadb-server mariadb-client libmariadb-dev \
    python3 python3-dev python3-pip python3-venv \
    libffi-dev libssl-dev libjpeg-dev zlib1g-dev \
    xvfb libfontconfig \
    cron netcat-openbsd

  log "Installing optional packages"
  install_optional_package "wkhtmltopdf"

  $SUDO systemctl enable --now mariadb
  $SUDO systemctl enable --now redis-server

  ok "System packages installed"
}

configure_sysctl_for_redis() {
  log "Configuring Redis memory overcommit"

  echo "vm.overcommit_memory = 1" | $SUDO tee /etc/sysctl.d/99-erpnext-dev.conf >/dev/null
  $SUDO sysctl -w vm.overcommit_memory=1 >/dev/null || true

  ok "Redis overcommit setting configured"
}

prepare_passwords() {
  log "Preparing credentials"

  if [[ -z "$DB_ADMIN_PASSWORD" ]]; then
    DB_ADMIN_PASSWORD="$(random_password)"
  fi

  if [[ -z "$ADMIN_PASSWORD" ]]; then
    ADMIN_PASSWORD="$(random_password)"
  fi

  ok "Credentials prepared"
}

create_frappe_user() {
  log "Preparing Linux user: ${FRAPPE_USER}"

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    ok "User ${FRAPPE_USER} already exists"
  else
    $SUDO adduser --disabled-password --gecos "" "$FRAPPE_USER"
    ok "User ${FRAPPE_USER} created without password login"
  fi
}

create_mariadb_admin_user() {
  log "Creating MariaDB admin user for Bench"

  $SUDO mariadb <<SQL
CREATE USER IF NOT EXISTS '${DB_ADMIN_USER}'@'localhost' IDENTIFIED BY '${DB_ADMIN_PASSWORD}';
ALTER USER '${DB_ADMIN_USER}'@'localhost' IDENTIFIED BY '${DB_ADMIN_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${DB_ADMIN_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

  ok "MariaDB admin user ready: ${DB_ADMIN_USER}"
}

stop_bench_processes() {
  log "Stopping existing Bench processes"

  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    $SUDO systemctl stop "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    $SUDO pkill -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1 || true
    $SUDO pkill -u "$FRAPPE_USER" -f "frappe.utils.bench_helper" >/dev/null 2>&1 || true
    $SUDO pkill -u "$FRAPPE_USER" -f "redis.*11000|redis.*13000|node.*socketio|esbuild" >/dev/null 2>&1 || true
  fi

  sleep 2
  ok "Bench process cleanup completed"
}

archive_existing_bench_parent() {
  if path_is_dir "$BENCH_PARENT"; then
    local archive_path
    archive_path="${BENCH_PARENT}-backup-$(date +%Y%m%d-%H%M%S)"

    log "Archiving existing ERPNext environment"
    $SUDO mv "$BENCH_PARENT" "$archive_path"
    ok "Existing environment archived to: $archive_path"
  fi
}

fix_frappe_ownership() {
  if id "$FRAPPE_USER" >/dev/null 2>&1 && path_is_dir "$FRAPPE_HOME"; then
    log "Fixing ${FRAPPE_HOME} ownership"
    $SUDO chown -R "$FRAPPE_USER:$FRAPPE_USER" "$FRAPPE_HOME"
    ok "Ownership fixed"
  fi
}

create_start_helper() {
  if ! id "$FRAPPE_USER" >/dev/null 2>&1; then
    return 0
  fi

  local bench_dir
  bench_dir="$(active_bench_dir)"

  log "Creating start helper script"

  $SUDO tee "$FRAPPE_HOME/start-erpnext-dev.sh" >/dev/null <<EOF_HELPER
#!/usr/bin/env bash
set -e
export PATH="\$HOME/.local/bin:\$PATH"
cd "${bench_dir}"
bench start
EOF_HELPER

  $SUDO chown "$FRAPPE_USER:$FRAPPE_USER" "$FRAPPE_HOME/start-erpnext-dev.sh"
  $SUDO chmod +x "$FRAPPE_HOME/start-erpnext-dev.sh"

  ok "Helper created: ${FRAPPE_HOME}/start-erpnext-dev.sh"
}

install_frappe_stack_as_user() {
  log "Installing Node, Python, Bench, Frappe, and ERPNext as ${FRAPPE_USER}"

  $SUDO -H -u "$FRAPPE_USER" bash <<EOF_USER
set -Eeuo pipefail

export HOME="${FRAPPE_HOME}"
export PATH="\$HOME/.local/bin:\$PATH"

mkdir -p "\$HOME"
cd "\$HOME"

echo
echo "==> Installing nvm / Node ${NODE_VERSION} / Yarn"

if [[ ! -d "\$HOME/.nvm" ]]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

export NVM_DIR="\$HOME/.nvm"
# shellcheck disable=SC1091
source "\$NVM_DIR/nvm.sh"

nvm install "${NODE_VERSION}"
nvm use "${NODE_VERSION}"
npm install -g yarn

echo
echo "==> Installing uv / Python ${PYTHON_VERSION} / Bench"

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

export PATH="\$HOME/.local/bin:\$PATH"

uv python install "${PYTHON_VERSION}" --default
uv tool install frappe-bench --force

echo
echo "==> Creating bench"

mkdir -p "${BENCH_PARENT}"
cd "${BENCH_PARENT}"

if [[ -d "${BENCH_NAME}" ]]; then
  echo "Bench already exists: ${BENCH_DIR}"
else
  bench init "${BENCH_NAME}" --frappe-branch "${FRAPPE_BRANCH}"
fi

cd "${BENCH_DIR}"

echo
echo "==> Ensuring Frappe frontend dependencies"

cd apps/frappe
yarn install --check-files
cd ../../

echo
echo "==> Creating site ${SITE_NAME}"

if [[ -d "sites/${SITE_NAME}" ]]; then
  echo "Site already exists: ${SITE_NAME}"
else
  bench new-site "${SITE_NAME}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --db-root-username "${DB_ADMIN_USER}" \
    --db-root-password "${DB_ADMIN_PASSWORD}"
fi

bench use "${SITE_NAME}"
bench set-config -g default_site "${SITE_NAME}"
bench set-config -g serve_default_site true

echo
echo "==> Downloading ERPNext"

if [[ -d "apps/erpnext" ]]; then
  echo "ERPNext app already exists"
else
  bench get-app erpnext --branch "${ERPNEXT_BRANCH}"
fi

echo
echo "==> Starting temporary Bench services for Redis Queue"

mkdir -p logs
BENCH_INSTALL_LOG="logs/install-bench-start.log"

bench start > "\$BENCH_INSTALL_LOG" 2>&1 &
BENCH_PID=\$!

cleanup_bench() {
  if kill -0 "\$BENCH_PID" >/dev/null 2>&1; then
    echo "Stopping temporary bench services..."
    kill "\$BENCH_PID" >/dev/null 2>&1 || true
    sleep 3
    pkill -P "\$BENCH_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup_bench EXIT

echo "Waiting for Bench Redis Queue on 127.0.0.1:11000..."

for i in {1..60}; do
  if nc -z 127.0.0.1 11000 >/dev/null 2>&1; then
    echo "Redis Queue is ready"
    break
  fi

  if [[ "\$i" -eq 60 ]]; then
    echo "Bench services failed to start. Last log lines:"
    tail -100 "\$BENCH_INSTALL_LOG" || true
    exit 1
  fi

  sleep 2
done

echo
echo "==> Installing ERPNext on ${SITE_NAME}"

if bench --site "${SITE_NAME}" list-apps | awk '{print \$1}' | grep -qx "erpnext"; then
  echo "ERPNext is already installed on ${SITE_NAME}"
else
  bench --site "${SITE_NAME}" install-app erpnext
fi

echo
echo "==> Running migrate/build/clear-cache"

bench --site "${SITE_NAME}" migrate
bench build
bench --site "${SITE_NAME}" clear-cache
EOF_USER

  create_start_helper
  ok "Frappe/ERPNext stack installed"
}

write_credentials_file() {
  log "Writing credentials file"

  local cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  local bench_dir
  bench_dir="$(active_bench_dir)"

  $SUDO tee "$cred_file" >/dev/null <<EOF_CREDS
ERPNext Developer Environment

Site:
  ${SITE_NAME}

Bench:
  ${bench_dir}

Login:
  Username: Administrator
  Password: ${ADMIN_PASSWORD}

MariaDB Bench Admin:
  User: ${DB_ADMIN_USER}
  Password: ${DB_ADMIN_PASSWORD}

Start ERPNext:
  sudo -iu ${FRAPPE_USER}
  export PATH="\$HOME/.local/bin:\$PATH"
  cd ${bench_dir}
  bench start

One-line start command:
  sudo -iu ${FRAPPE_USER} bash -lc 'export PATH="\$HOME/.local/bin:\$PATH"; cd ${bench_dir} && bench start'

Browser access:
  Direct IP URL, works while Bench is running:
    http://$(get_vm_ip):8000

  Friendly local URL, works after HOST /etc/hosts is configured:
    http://${SITE_NAME}:8000

Important:
  ${SITE_NAME} only works after ERPNext is running and your HOST machine maps ${SITE_NAME} to the VM IP.
  Use ./install-erpnext-dev.sh access to print the required host-side command.
EOF_CREDS

  $SUDO chown "$FRAPPE_USER:$FRAPPE_USER" "$cred_file"
  $SUDO chmod 600 "$cred_file"

  ok "Credentials saved to ${cred_file}"
}

get_vm_ip() {
  hostname -I | awk '{print $1}'
}

show_access_instructions() {
  local vm_ip escaped_site bench_dir
  vm_ip="$(get_vm_ip)"
  bench_dir="$(active_bench_dir)"
  escaped_site="${SITE_NAME//./\\.}"

  echo
  echo "============================================================"
  echo "Browser / Hostname Instructions"
  echo "============================================================"
  echo
  echo "ERPNext must be running before any browser URL will work."
  echo
  echo "Start ERPNext inside the VM with:"
  echo "  ./install-erpnext-dev.sh start"
  echo
  echo "Or manually:"
  echo "  sudo -iu ${FRAPPE_USER}"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo "  cd ${bench_dir}"
  echo "  bench start"
  echo
  echo "Direct IP URL, works while Bench is running:"
  echo "  http://${vm_ip}:8000"
  echo
  echo "Friendly local URL:"
  echo "  http://${SITE_NAME}:8000"
  echo
  echo "The friendly URL only works after your HOST machine maps ${SITE_NAME} to this VM IP."
  echo
  echo "Run this on your Linux Mint HOST machine, not inside the VM:"
  echo
  echo "  sudo sed -i '/[[:space:]]${escaped_site}\$/d' /etc/hosts"
  echo "  echo \"${vm_ip} ${SITE_NAME}\" | sudo tee -a /etc/hosts"
  echo
  echo "Then test on the host:"
  echo "  getent hosts ${SITE_NAME}"
  echo
  echo "If ${SITE_NAME} still does not open, use the direct IP URL first:"
  echo "  http://${vm_ip}:8000"
  echo
  echo "============================================================"
}



show_host_hosts_command() {
  local vm_ip escaped_site
  vm_ip="$(get_vm_ip)"
  escaped_site="${SITE_NAME//./\\.}"

  echo
  echo "============================================================"
  echo "Host /etc/hosts Command"
  echo "============================================================"
  echo
  echo "Run these commands on your HOST machine, not inside this VM:"
  echo
  echo "  sudo sed -i '/[[:space:]]${escaped_site}\$/d' /etc/hosts"
  echo "  echo \"${vm_ip} ${SITE_NAME}\" | sudo tee -a /etc/hosts"
  echo
  echo "Then test from the host:"
  echo "  getent hosts ${SITE_NAME}"
  echo
  echo "Expected:"
  echo "  ${vm_ip} ${SITE_NAME}"
  echo
  echo "Direct fallback URL while Bench is running:"
  echo "  http://${vm_ip}:8000"
  echo
  echo "Friendly URL after the host entry is added:"
  echo "  http://${SITE_NAME}:8000"
  echo
  echo "============================================================"
}


get_primary_interface() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
}

get_default_gateway() {
  ip route 2>/dev/null | awk '/^default/ {print $3; exit}'
}

get_primary_mac() {
  local iface
  iface="$(get_primary_interface || true)"

  if [[ -n "${iface}" && -r "/sys/class/net/${iface}/address" ]]; then
    cat "/sys/class/net/${iface}/address"
    return 0
  fi

  ip -o link show 2>/dev/null | awk '$2 != "lo:" {for (i=1; i<=NF; i++) if ($i=="link/ether") {print $(i+1); exit}}'
}

show_network_status() {
  local vm_ip iface mac gateway host_name detected_network
  vm_ip="$(get_vm_ip)"
  iface="$(get_primary_interface || true)"
  mac="$(get_primary_mac || true)"
  gateway="$(get_default_gateway || true)"
  host_name="$(hostname 2>/dev/null || echo unknown)"

  if [[ "${vm_ip}" == 192.168.122.* ]]; then
    detected_network="likely KVM/libvirt default NAT"
  elif [[ "${vm_ip}" == 10.* || "${vm_ip}" == 172.* || "${vm_ip}" == 192.168.* ]]; then
    detected_network="private/LAN or custom NAT"
  else
    detected_network="public or routed address"
  fi

  echo
  echo "============================================================"
  echo "VM Network / Access Status"
  echo "============================================================"
  status_line "VM hostname" "INFO" "${host_name}"
  status_line "Primary interface" "INFO" "${iface:-unknown}"
  status_line "Primary MAC" "INFO" "${mac:-unknown}"
  status_line "VM IP" "INFO" "${vm_ip:-unknown}"
  status_line "Default gateway" "INFO" "${gateway:-unknown}"
  status_line "Network type" "INFO" "${detected_network}"
  status_line "Direct URL" "INFO" "http://${vm_ip}:8000"
  status_line "Friendly URL" "INFO" "http://${SITE_NAME}:8000"

  if port_listens 8000; then
    status_line "Bench web" "OK" "port 8000 listening"
  else
    status_line "Bench web" "INFO" "port 8000 not listening"
  fi

  if [[ -n "${vm_ip}" && -n "${mac}" ]]; then
    echo
    echo "Host /etc/hosts command:"
    echo "  sudo sed -i '/[[:space:]]${SITE_NAME//./\\.}\$/d' /etc/hosts"
    echo "  echo \"${vm_ip} ${SITE_NAME}\" | sudo tee -a /etc/hosts"
    echo
    echo "KVM host helper to find the matching VM by MAC:"
    echo "  target_mac=\"${mac}\""
    echo "  while IFS= read -r vm; do [ -n \"\$vm\" ] || continue; virsh domiflist \"\$vm\" | grep -qi \"\$target_mac\" && echo \"\$vm\"; done < <(virsh list --all --name)"
  fi

  echo
  echo "Tip: if the friendly URL fails, use the Direct URL first, then update the HOST /etc/hosts entry."
  echo "============================================================"
}

show_host_access_test_guide() {
  local vm_ip escaped_site
  vm_ip="$(get_vm_ip)"
  escaped_site="${SITE_NAME//./\\.}"

  echo
  echo "============================================================"
  echo "Host Access Test Guide"
  echo "============================================================"
  echo
  echo "Run these on the HOST machine, not inside this VM:"
  echo
  echo "1) Confirm the host resolves the friendly name:"
  echo "  getent hosts ${SITE_NAME}"
  echo
  echo "2) If it does not resolve to ${vm_ip}, update /etc/hosts:"
  echo "  sudo sed -i '/[[:space:]]${escaped_site}\$/d' /etc/hosts"
  echo "  echo \"${vm_ip} ${SITE_NAME}\" | sudo tee -a /etc/hosts"
  echo
  echo "3) Test the direct URL:"
  echo "  curl -I http://${vm_ip}:8000"
  echo
  echo "4) Test the friendly URL:"
  echo "  curl -I http://${SITE_NAME}:8000"
  echo
  echo "5) Browser URLs:"
  echo "  http://${vm_ip}:8000"
  echo "  http://${SITE_NAME}:8000"
  echo
  echo "If curl fails but runtime-status is OK inside the VM, check firewall, NAT/bridge mode, or the host /etc/hosts mapping."
  echo "============================================================"
}

show_kvm_vm_identification_guide() {
  local vm_ip mac clean_name
  vm_ip="$(get_vm_ip)"
  mac="$(get_primary_mac || true)"
  clean_name="${SITE_NAME//./-}"

  echo
  echo "============================================================"
  echo "KVM / libvirt VM Identification + Fixed IP Helper"
  echo "============================================================"
  echo
  echo "Detected inside this VM:"
  echo "  IP:       ${vm_ip}"
  echo "  MAC:      ${mac:-unknown}"
  echo "  Hostname: $(hostname 2>/dev/null || echo unknown)"
  echo
  echo "Run on the KVM HOST to find which libvirt domain owns this MAC:"
  echo
  echo "  target_mac=\"${mac:-PASTE_VM_MAC}\""
  echo "  while IFS= read -r vm; do"
  echo "    [ -n \"\$vm\" ] || continue"
  echo "    if virsh domiflist \"\$vm\" | grep -qi \"\$target_mac\"; then"
  echo "      echo \"Matched VM: \$vm\""
  echo "    fi"
  echo "  done < <(virsh list --all --name)"
  echo
  echo "After identifying the VM name, reserve this IP on the default libvirt NAT network:"
  echo
  echo "  sudo virsh net-update default add ip-dhcp-host \"<host mac='${mac:-PASTE_VM_MAC}' name='${clean_name}' ip='${vm_ip}'/>\" --live --config"
  echo
  echo "Then reboot the VM and confirm:"
  echo "  virsh shutdown \"YOUR_VM_NAME\""
  echo "  virsh start \"YOUR_VM_NAME\""
  echo "  virsh net-dhcp-leases default"
  echo
  echo "Important: libvirt domain names can contain spaces. Use the while-read loop above instead of: for vm in \$(virsh list ...)."
  echo "============================================================"
}

show_ssl_roadmap_guide() {
  cat <<EOF_SSL

============================================================
Future SSL / HTTPS Direction
============================================================

SSL is planned, but it should be added carefully because HTTPS changes
access from direct Bench :8000 to a reverse-proxy model.

Local developer SSL target:
  https://${SITE_NAME}

Planned local architecture:
  Browser HTTPS :443
    -> Nginx reverse proxy inside the VM
      -> Bench web on 127.0.0.1:8000
      -> Socket.io on 127.0.0.1:9000

Planned local SSL commands:
  ./install-erpnext-dev.sh ssl-status
  ./install-erpnext-dev.sh local-ssl-guide
  ./install-erpnext-dev.sh mkcert-guide
  ./install-erpnext-dev.sh verify-local-ssl
  ./install-erpnext-dev.sh configure-local-ssl
  ./install-erpnext-dev.sh disable-local-ssl

Recommended local certificate direction:
  - Use mkcert or a local CA workflow.
  - Trust the local CA on the HOST browser machine.
  - Keep Redis and internal services private.

Production SSL should be a separate production track, not mixed into the
current developer bench-start workflow.

Future production SSL options:
  1) Let's Encrypt HTTP-01 for public DNS pointing to the server.
  2) Let's Encrypt DNS-01 with Cloudflare for Cloudflare-managed DNS.
  3) Cloudflare Origin CA for Cloudflare-proxied deployments.

Future production architecture should use:
  - Nginx
  - Supervisor or production systemd units
  - Firewall rules
  - Domain/DNS validation
  - SSL renewal checks
  - Backups and restore testing
  - Monitoring and update strategy

Recommended roadmap:
  v0.7.x  VM/networking and hostname foundation
  v0.8.x  Local HTTPS reverse proxy planning/implementation
  v0.9.x  Production planning branch
  v1.x    Stable developer installer
  prod    Separate production installer track

============================================================
EOF_SSL
}

show_domain_config() {
  local prod_domain="${PRODUCTION_DOMAIN:-not set}"
  echo
  echo "============================================================"
  echo "Domain Configuration"
  echo "============================================================"
  status_line "Mode" "INFO" "$DEPLOYMENT_MODE"
  status_line "Local site" "INFO" "$SITE_NAME"
  status_line "Production domain" "INFO" "$prod_domain"
  status_line "Production SSL" "INFO" "$PRODUCTION_SSL_MODE"
  status_line "Config file" "INFO" "$CONFIG_FILE"
  echo
  echo "Local URL:      http://${SITE_NAME}:8000"
  if [[ -n "$PRODUCTION_DOMAIN" ]]; then
    echo "Future prod URL: https://${PRODUCTION_DOMAIN}"
  else
    echo "Future prod URL: set PRODUCTION_DOMAIN=erp.company.com later"
  fi
  echo "============================================================"
}

show_production_domain_guide() {
  cat <<EOF_PROD_DOMAIN

============================================================
Production Domain Planning
============================================================

Production should use a real DNS name, for example:
  erp.company.com

Current local site:
  ${SITE_NAME}

Future production config example:
  PRODUCTION_DOMAIN=erp.company.com

DNS requirements:
  - Public server: DNS A/AAAA record points to the server.
  - Local datacenter: internal DNS points to the ERPNext server.
  - Avoid .test and .local for production.

This developer installer only plans production settings.
Production automation should be a separate track.
============================================================
EOF_PROD_DOMAIN
}

show_production_ssl_guide() {
  cat <<EOF_PROD_SSL

============================================================
Production SSL Planning
============================================================

Future production SSL options:
  1) Let's Encrypt HTTP-01 for public DNS/server.
  2) Let's Encrypt DNS-01 for Cloudflare-managed DNS.
  3) Cloudflare Origin CA for Cloudflare-proxied sites.
  4) Manual certificate install for private datacenter SSL.

Production needs:
  - real domain
  - Nginx reverse proxy
  - port 80/443 plan
  - renewal checks
  - backup/restore testing

Current local SSL remains separate:
  ./install-erpnext-dev.sh configure-local-ssl
============================================================
EOF_PROD_SSL
}

show_production_readiness() {
  local domain_state="not set"
  local domain_status="WARN"
  local nginx_state="not installed"
  local ssl_state="local/dev only"

  if [[ -n "$PRODUCTION_DOMAIN" ]]; then
    if validate_production_domain_value "$PRODUCTION_DOMAIN" >/dev/null 2>&1; then
      domain_state="$PRODUCTION_DOMAIN"
      domain_status="OK"
    else
      domain_state="invalid: $PRODUCTION_DOMAIN"
      domain_status="WARN"
    fi
  fi

  if command -v nginx >/dev/null 2>&1; then
    nginx_state="installed"
  fi

  echo
  echo "============================================================"
  echo "Production Readiness Preview"
  echo "============================================================"
  status_line "Developer mode" "OK" "active"
  status_line "Production automation" "INFO" "planned, not enabled"
  status_line "Local site" "INFO" "$SITE_NAME"
  status_line "Production domain" "$domain_status" "$domain_state"
  status_line "Nginx" "INFO" "$nginx_state"
  status_line "SSL mode" "INFO" "$ssl_state"
  echo
  echo "Next planning commands:"
  echo "  ./install-erpnext-dev.sh production-domain-guide"
  echo "  ./install-erpnext-dev.sh production-ssl-guide"
  echo "============================================================"
}


ssl_site_slug() {
  printf '%s' "$SITE_NAME" | tr -c 'A-Za-z0-9._-' '-'
}

ssl_nginx_site_name() {
  echo "erpnext-dev-$(ssl_site_slug)"
}

ssl_cert_path() {
  echo "${SSL_CERT_PATH:-${SSL_CERT_DIR}/${SITE_NAME}.crt}"
}

ssl_key_path() {
  echo "${SSL_KEY_PATH:-${SSL_CERT_DIR}/${SITE_NAME}.key}"
}

ssl_nginx_available_path() {
  echo "${SSL_NGINX_CONF_DIR}/sites-available/$(ssl_nginx_site_name).conf"
}

ssl_nginx_enabled_path() {
  echo "${SSL_NGINX_CONF_DIR}/sites-enabled/$(ssl_nginx_site_name).conf"
}

show_local_ssl_guide() {
  local vm_ip cert_path key_path escaped_site
  vm_ip="$(get_vm_ip)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  escaped_site="${SITE_NAME//./\\.}"

  cat <<EOF_LOCAL_SSL

============================================================
Local SSL / HTTPS Guide
============================================================

Goal:
  https://${SITE_NAME}

The local SSL feature uses Nginx inside the VM as a reverse proxy:

  Browser HTTPS :443
    -> Nginx inside the VM
      -> Bench web on 127.0.0.1:8000
      -> Socket.io on 127.0.0.1:9000

Direct Bench access remains available:
  http://${SITE_NAME}:8000
  http://${vm_ip}:8000

Expected certificate paths inside the VM:
  Certificate: ${cert_path}
  Private key: ${key_path}

Option 1: Quick self-signed test certificate
  This is the fastest way to prove the reverse proxy works.
  Browsers will show a certificate warning. That is expected.

  ./install-erpnext-dev.sh create-self-signed-local-cert
  ./install-erpnext-dev.sh configure-local-ssl
  ./install-erpnext-dev.sh ssl-status

  Test from the HOST:
    curl -kI https://${SITE_NAME}

Option 2: Trusted local certificate with mkcert
  This is the better browser experience because the host browser trusts the certificate.
  For the full checklist, run:
    ./install-erpnext-dev.sh mkcert-guide

  Summary on your Linux Mint/Ubuntu HOST:
    mkcert -install
    mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} ${vm_ip} localhost 127.0.0.1

  Copy the generated certificate and key into the VM:
    scp ${SITE_NAME}.crt ${SITE_NAME}.key USER@${vm_ip}:/tmp/

  Inside the VM, install the certificate files:
    sudo mkdir -p ${SSL_CERT_DIR}
    sudo cp /tmp/${SITE_NAME}.crt ${cert_path}
    sudo cp /tmp/${SITE_NAME}.key ${key_path}
    sudo chown root:root ${cert_path} ${key_path}
    sudo chmod 644 ${cert_path}
    sudo chmod 600 ${key_path}

  Then configure HTTPS:
    ./install-erpnext-dev.sh configure-local-ssl
    ./install-erpnext-dev.sh ssl-status

Host /etc/hosts still needs to map ${SITE_NAME} to this VM IP:
  sudo sed -i '/[[:space:]]${escaped_site}\$/d' /etc/hosts
  echo "${vm_ip} ${SITE_NAME}" | sudo tee -a /etc/hosts

Host tests:
  getent hosts ${SITE_NAME}
  curl -I http://${SITE_NAME}
  curl -kI https://${SITE_NAME}
  curl -I http://${SITE_NAME}:8000

Expected behavior after local SSL is configured:
  http://${SITE_NAME}       -> 301 redirect to https://${SITE_NAME}/
  https://${SITE_NAME}      -> ERPNext login page through Nginx
  http://${SITE_NAME}:8000  -> direct Bench fallback still works

Rollback:
  ./install-erpnext-dev.sh disable-local-ssl
  ./install-erpnext-dev.sh ssl-rollback-guide

============================================================
EOF_LOCAL_SSL
}

show_mkcert_local_ssl_guide() {
  local vm_ip cert_path key_path escaped_site
  vm_ip="$(get_vm_ip)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  escaped_site="${SITE_NAME//./\\.}"

  cat <<EOF_MKCERT

============================================================
Trusted Local SSL with mkcert
============================================================

Goal:
  Use https://${SITE_NAME} without browser warnings on the HOST machine.

Important:
  The browser trust must happen on the HOST machine where the browser runs,
  not only inside the ERPNext VM.

Safety rule:
  Run mkcert and curl browser tests on the HOST.
  Run install-local-ssl-cert, configure-local-ssl, ssl-status, and verify-local-ssl inside the ERPNext VM.
  If unsure, run: ./install-erpnext-dev.sh environment-check

1) On the Linux Mint/Ubuntu HOST, install mkcert:

  sudo apt update
  sudo apt install -y libnss3-tools

  # Install mkcert from your distro package manager if available, or from the
  # official mkcert release package for your OS.

2) On the HOST, create and trust the local CA:

  mkcert -install

3) On the HOST, generate a certificate for this VM/site:

  mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} ${vm_ip} localhost 127.0.0.1

4) Copy the cert/key from HOST to VM:

  scp ${SITE_NAME}.crt ${SITE_NAME}.key USER@${vm_ip}:/tmp/

5) Inside the VM, install the cert/key safely:

  ./install-erpnext-dev.sh install-local-ssl-cert

  This copies from:
    /tmp/${SITE_NAME}.crt
    /tmp/${SITE_NAME}.key

  To:
    ${cert_path}
    ${key_path}

  Existing cert/key files are backed up first, and permissions are enforced.

6) Inside the VM, enable/reload the HTTPS reverse proxy:

  ./install-erpnext-dev.sh configure-local-ssl
  ./install-erpnext-dev.sh verify-local-ssl

7) On the HOST, confirm DNS/hosts and HTTPS:

  sudo sed -i '/[[:space:]]${escaped_site}\$/d' /etc/hosts
  echo "${vm_ip} ${SITE_NAME}" | sudo tee -a /etc/hosts
  getent hosts ${SITE_NAME}
  curl -I http://${SITE_NAME}
  curl -I https://${SITE_NAME}

Expected:
  http://${SITE_NAME}       -> 301 redirect to https://${SITE_NAME}/
  https://${SITE_NAME}      -> 200 OK without using curl -k
  http://${SITE_NAME}:8000  -> direct Bench fallback still works

Rollback:
  ./install-erpnext-dev.sh disable-local-ssl
  ./install-erpnext-dev.sh ssl-rollback-guide

============================================================
EOF_MKCERT
}


show_browser_trust_check_guide() {
  local vm_ip escaped_site
  vm_ip="$(get_vm_ip)"
  escaped_site="${SITE_NAME//./\\.}"

  cat <<EOF_BROWSER_TRUST

============================================================
Browser Trust / Trusted Certificate Check
============================================================

Purpose:
  Confirm whether https://${SITE_NAME} is only working with curl -k
  or is trusted by the HOST browser/curl normally.

Run these on the HOST machine, not inside the VM:

1) Confirm hostname resolution:
  getent hosts ${SITE_NAME}

2) If needed, update /etc/hosts:
  sudo sed -i '/[[:space:]]${escaped_site}\$/d' /etc/hosts
  echo "${vm_ip} ${SITE_NAME}" | sudo tee -a /etc/hosts

3) Test HTTPS without bypassing certificate validation:
  curl -I https://${SITE_NAME}

Expected for trusted mkcert/local CA:
  HTTP/2 200

Expected for self-signed certificate:
  curl: (60) SSL certificate problem

4) Test HTTPS with validation bypass, for self-signed testing only:
  curl -kI https://${SITE_NAME}

5) Browser test:
  Open https://${SITE_NAME}

If the browser warns about the certificate:
  - The reverse proxy may still be working.
  - The certificate is not trusted by the HOST browser yet.
  - Use: ./install-erpnext-dev.sh mkcert-guide

Important:
  Certificate trust must be installed on the HOST machine where the browser runs.
  Trusting a CA inside the VM alone does not make the host browser trust it.

============================================================
EOF_BROWSER_TRUST
}

install_local_ssl_cert() {
  require_erpnext_vm_context "install-local-ssl-cert" || return 1
  require_sudo

  local src_cert src_key cert_path key_path stamp
  src_cert="${LOCAL_SSL_CERT_SOURCE:-/tmp/${SITE_NAME}.crt}"
  src_key="${LOCAL_SSL_KEY_SOURCE:-/tmp/${SITE_NAME}.key}"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"

  echo
  echo "============================================================"
  echo "Install / Replace Local SSL Certificate"
  echo "============================================================"
  echo "Source certificate: ${src_cert}"
  echo "Source private key: ${src_key}"
  echo "Target certificate: ${cert_path}"
  echo "Target private key: ${key_path}"
  echo

  if [[ ! -f "$src_cert" || ! -f "$src_key" ]]; then
    warn "Source certificate or key was not found."
    echo
    echo "Default expected source files inside the VM:"
    echo "  /tmp/${SITE_NAME}.crt"
    echo "  /tmp/${SITE_NAME}.key"
    echo
    echo "Generate trusted local certificates on the HOST with mkcert, then copy them to the VM:"
    echo "  scp ${SITE_NAME}.crt test@VM_IP:/tmp/${SITE_NAME}.crt"
    echo "  scp ${SITE_NAME}.key test@VM_IP:/tmp/${SITE_NAME}.key"
    echo
    echo "You can override the VM source paths like this:"
    echo "  LOCAL_SSL_CERT_SOURCE=/path/to/${SITE_NAME}.crt LOCAL_SSL_KEY_SOURCE=/path/to/${SITE_NAME}.key ./install-erpnext-dev.sh install-local-ssl-cert"
    echo
    echo "For the full workflow, run: ./install-erpnext-dev.sh mkcert-guide"
    echo "============================================================"
    return 1
  fi

  $SUDO mkdir -p "$SSL_CERT_DIR"

  stamp="$(date +%Y%m%d_%H%M%S)"
  if [[ -f "$cert_path" ]]; then
    warn "Existing certificate found. Backing up to ${cert_path}.bak.${stamp}"
    $SUDO cp "$cert_path" "${cert_path}.bak.${stamp}"
  fi
  if [[ -f "$key_path" ]]; then
    warn "Existing key found. Backing up to ${key_path}.bak.${stamp}"
    $SUDO cp "$key_path" "${key_path}.bak.${stamp}"
  fi

  $SUDO install -o root -g root -m 644 "$src_cert" "$cert_path"
  $SUDO install -o root -g root -m 600 "$src_key" "$key_path"

  ok "Certificate installed with safe permissions"

  if command -v nginx >/dev/null 2>&1 && [[ -L "$(ssl_nginx_enabled_path)" || -f "$(ssl_nginx_enabled_path)" ]]; then
    log "Testing and reloading Nginx with the new certificate"
    if $SUDO nginx -t; then
      $SUDO systemctl reload nginx || true
      ok "Nginx reloaded"
    else
      warn "Nginx config test failed. The certificate was copied, but Nginx was not reloaded."
      warn "Check manually: sudo nginx -t"
    fi
  else
    echo
    echo "Next step:"
    echo "  ./install-erpnext-dev.sh configure-local-ssl"
  fi

  echo
  echo "Verify:"
  echo "  ./install-erpnext-dev.sh ssl-status"
  echo "  ./install-erpnext-dev.sh verify-local-ssl"
  echo "============================================================"
}

verify_ssl_rollback() {
  require_erpnext_vm_context "verify-ssl-rollback" || return 1

  local enabled_path available_path cert_path key_path bench_head https_head http_head
  enabled_path="$(ssl_nginx_enabled_path)"
  available_path="$(ssl_nginx_available_path)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"

  echo
  echo "============================================================"
  echo "Verify Local SSL Rollback / Disable State"
  echo "============================================================"

  if [[ -L "$enabled_path" || -f "$enabled_path" ]]; then
    status_line "SSL site enabled" "WARN" "$enabled_path is still enabled"
  else
    status_line "SSL site enabled" "OK" "disabled"
  fi

  [[ -f "$available_path" ]] && status_line "Saved SSL config" "INFO" "$available_path kept for reuse" || status_line "Saved SSL config" "INFO" "not present"
  [[ -f "$cert_path" ]] && status_line "SSL certificate" "INFO" "$cert_path kept for reuse" || status_line "SSL certificate" "INFO" "not present"
  [[ -f "$key_path" ]] && status_line "SSL private key" "INFO" "$key_path kept for reuse" || status_line "SSL private key" "INFO" "not present"

  if port_listens 443; then
    status_line "Port 443" "INFO" "listening; another/default Nginx site may still be active"
  else
    status_line "Port 443" "OK" "not listening"
  fi

  if port_listens 8000; then
    status_line "Direct Bench fallback" "OK" "127.0.0.1:8000 listening"
  else
    status_line "Direct Bench fallback" "WARN" "127.0.0.1:8000 not listening"
  fi

  echo
  echo "Local response checks from inside the VM:"
  http_head="$(curl_head_status "http://${SITE_NAME}/" "$SITE_NAME" 80 "127.0.0.1" || true)"
  https_head="$(curl_head_status "https://${SITE_NAME}/" "$SITE_NAME" 443 "127.0.0.1" || true)"
  bench_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  echo "  http://${SITE_NAME}       -> ${http_head:-no response}"
  echo "  https://${SITE_NAME}      -> ${https_head:-no response}"
  echo "  http://127.0.0.1:8000    -> ${bench_head:-no response}"

  echo
  echo "Re-enable later with:"
  echo "  ./install-erpnext-dev.sh configure-local-ssl"
  echo "============================================================"
}

show_ssl_rollback_guide() {
  local available_path enabled_path cert_path key_path
  available_path="$(ssl_nginx_available_path)"
  enabled_path="$(ssl_nginx_enabled_path)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"

  cat <<EOF_SSL_ROLLBACK

============================================================
Local SSL Rollback / Disable Guide
============================================================

Safe rollback command:
  ./install-erpnext-dev.sh disable-local-ssl

What it does:
  - Removes the enabled Nginx site symlink:
    ${enabled_path}
  - Reloads Nginx if the configuration is valid
  - Keeps the saved config and certificate files for later reuse

What it does NOT change:
  - ERPNext dev service
  - Bench ports 8000/9000
  - MariaDB / Redis
  - Site data
  - Certificate files

Direct fallback should remain available:
  http://${SITE_NAME}:8000

Manual cleanup if you want to remove files later:
  sudo rm -f ${enabled_path}
  sudo rm -f ${available_path}
  sudo rm -f ${cert_path} ${key_path}
  sudo nginx -t && sudo systemctl reload nginx

============================================================
EOF_SSL_ROLLBACK
}

verify_local_ssl() {
  require_erpnext_vm_context "verify-local-ssl" || return 1
  echo
  echo "============================================================"
  echo "Verify Local SSL / HTTPS"
  echo "============================================================"
  show_ssl_status
  echo
  echo "Host-side verification commands:"
  echo "  curl -I http://${SITE_NAME}"
  echo "  curl -kI https://${SITE_NAME}     # self-signed test"
  echo "  curl -I https://${SITE_NAME}      # trusted mkcert test"
  echo "  curl -I http://${SITE_NAME}:8000"
  echo "============================================================"
}

ssl_file_permissions() {
  local file_path="$1"
  if [[ -e "$file_path" ]]; then
    stat -c '%U:%G %a' "$file_path" 2>/dev/null || echo "exists"
  else
    echo "missing"
  fi
}

ssl_cert_summary() {
  local cert_path="$1"
  if [[ -f "$cert_path" ]] && command -v openssl >/dev/null 2>&1; then
    local subject issuer dates san enddate end_epoch now_epoch days_left cert_type
    subject="$(openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | sed 's/^subject=//')"
    issuer="$(openssl x509 -in "$cert_path" -noout -issuer 2>/dev/null | sed 's/^issuer=//')"
    dates="$(openssl x509 -in "$cert_path" -noout -dates 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    san="$(openssl x509 -in "$cert_path" -noout -ext subjectAltName 2>/dev/null | tail -n +2 | tr -d '\n' | sed 's/^[[:space:]]*//')"
    enddate="$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
    [[ -n "$subject" ]] && echo "  Subject: ${subject}"
    [[ -n "$issuer" ]] && echo "  Issuer:  ${issuer}"
    [[ -n "$dates" ]] && echo "  Dates:   ${dates}"
    [[ -n "$san" ]] && echo "  SAN:     ${san}"

    if [[ -n "$subject" && -n "$issuer" && "$subject" == "$issuer" ]]; then
      cert_type="self-signed"
    else
      cert_type="CA-signed or locally trusted CA"
    fi
    echo "  Type:    ${cert_type}"

    if [[ -n "$enddate" ]] && command -v date >/dev/null 2>&1; then
      end_epoch="$(date -d "$enddate" +%s 2>/dev/null || true)"
      now_epoch="$(date +%s 2>/dev/null || true)"
      if [[ -n "$end_epoch" && -n "$now_epoch" ]]; then
        days_left=$(( (end_epoch - now_epoch) / 86400 ))
        if (( days_left < 0 )); then
          echo "  Expiry:  EXPIRED ($days_left days)"
        elif (( days_left <= 30 )); then
          echo "  Expiry:  WARNING (${days_left} days left)"
        else
          echo "  Expiry:  OK (${days_left} days left)"
        fi
      fi
    fi
  fi
}

ssl_key_permission_status() {
  local key_path="$1"
  local mode owner group
  [[ -f "$key_path" ]] || return 0
  mode="$(stat -c '%a' "$key_path" 2>/dev/null || true)"
  owner="$(stat -c '%U' "$key_path" 2>/dev/null || true)"
  group="$(stat -c '%G' "$key_path" 2>/dev/null || true)"
  if [[ "$owner" == "root" && "$group" == "root" && "$mode" == "600" ]]; then
    status_line "SSL key permissions" "OK" "root:root 600"
  else
    status_line "SSL key permissions" "WARN" "current ${owner}:${group} ${mode}; recommended root:root 600"
  fi
}

curl_head_status() {
  local url="$1"
  local resolve_host="$2"
  local resolve_port="$3"
  local resolve_ip="$4"

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl missing"
    return 1
  fi

  if [[ -n "$resolve_host" && -n "$resolve_port" && -n "$resolve_ip" ]]; then
    curl -kIsS --max-time 5 --resolve "${resolve_host}:${resolve_port}:${resolve_ip}" "$url" 2>/dev/null | awk 'NR==1 {print; exit}'
  else
    curl -kIsS --max-time 5 "$url" 2>/dev/null | awk 'NR==1 {print; exit}'
  fi
}

show_ssl_status() {
  require_erpnext_vm_context "ssl-status" || return 1
  local cert_path key_path available_path enabled_path vm_ip nginx_state
  local http_head https_head bench_head cert_perms key_perms
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  available_path="$(ssl_nginx_available_path)"
  enabled_path="$(ssl_nginx_enabled_path)"
  vm_ip="$(get_vm_ip)"

  if command -v nginx >/dev/null 2>&1; then
    nginx_state="installed: $(nginx -v 2>&1 | sed 's/^nginx version: //')"
  else
    nginx_state="not installed"
  fi

  echo
  echo "============================================================"
  echo "Local SSL / HTTPS Status"
  echo "============================================================"
  status_line "Nginx" "INFO" "$nginx_state"

  if systemctl list-unit-files nginx.service >/dev/null 2>&1; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
      status_line "Nginx service" "OK" "running"
    else
      status_line "Nginx service" "WARN" "not running"
    fi
  else
    status_line "Nginx service" "INFO" "not available"
  fi

  if [[ -f "$available_path" ]]; then
    status_line "Nginx SSL config" "OK" "$available_path"
  else
    status_line "Nginx SSL config" "WARN" "missing at $available_path"
  fi

  if [[ -L "$enabled_path" || -f "$enabled_path" ]]; then
    status_line "Nginx SSL enabled" "OK" "$enabled_path"
  else
    status_line "Nginx SSL enabled" "WARN" "not enabled"
  fi

  cert_perms="$(ssl_file_permissions "$cert_path")"
  key_perms="$(ssl_file_permissions "$key_path")"

  if [[ -f "$cert_path" ]]; then
    status_line "SSL certificate" "OK" "$cert_path (${cert_perms})"
  else
    status_line "SSL certificate" "WARN" "missing at $cert_path"
  fi

  if [[ -f "$key_path" ]]; then
    status_line "SSL private key" "OK" "$key_path (${key_perms})"
    ssl_key_permission_status "$key_path"
  else
    status_line "SSL private key" "WARN" "missing at $key_path"
  fi

  if [[ -f "$cert_path" ]]; then
    echo
    echo "Certificate details:"
    ssl_cert_summary "$cert_path"
  fi

  if port_listens 80; then
    status_line "HTTP reverse proxy" "OK" "port 80 listening"
  else
    status_line "HTTP reverse proxy" "INFO" "port 80 not listening"
  fi

  if port_listens 443; then
    status_line "HTTPS reverse proxy" "OK" "port 443 listening"
  else
    status_line "HTTPS reverse proxy" "INFO" "port 443 not listening"
  fi

  if port_listens 8000; then
    status_line "Bench web" "OK" "127.0.0.1:8000 listening"
  else
    status_line "Bench web" "WARN" "127.0.0.1:8000 not listening"
  fi

  if port_listens 9000; then
    status_line "Socket.io" "OK" "127.0.0.1:9000 listening"
  else
    status_line "Socket.io" "WARN" "127.0.0.1:9000 not listening"
  fi

  echo
  echo "Local HTTP tests from inside the VM:"
  http_head="$(curl_head_status "http://${SITE_NAME}/" "$SITE_NAME" 80 "127.0.0.1" || true)"
  https_head="$(curl_head_status "https://${SITE_NAME}/" "$SITE_NAME" 443 "127.0.0.1" || true)"
  bench_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  echo "  http://${SITE_NAME}       -> ${http_head:-no response}"
  echo "  https://${SITE_NAME}      -> ${https_head:-no response}"
  echo "  http://127.0.0.1:8000    -> ${bench_head:-no response}"

  echo
  echo "Host test commands:"
  echo "  curl -I http://${SITE_NAME}"
  echo "  curl -kI https://${SITE_NAME}"
  echo "  curl -I http://${SITE_NAME}:8000"
  echo
  echo "URLs:"
  echo "  Direct Bench:     http://${vm_ip}:8000"
  echo "  Friendly Bench:   http://${SITE_NAME}:8000"
  echo "  Local HTTPS:      https://${SITE_NAME}"
  echo

  if [[ -f "$available_path" && ( -L "$enabled_path" || -f "$enabled_path" ) && -f "$cert_path" && -f "$key_path" ]] && port_listens 443; then
    ok "Local HTTPS appears configured. For self-signed certs, browser warning is expected unless the CA is trusted."
  else
    warn "Local HTTPS is not fully configured yet. Run: ./install-erpnext-dev.sh local-ssl-guide"
  fi

  echo "============================================================"
}

create_self_signed_local_cert() {
  require_erpnext_vm_context "create-self-signed-local-cert" || return 1
  require_sudo

  local cert_path key_path vm_ip
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Create Self-Signed Local SSL Certificate"
  echo "============================================================"
  echo "This creates a quick local test certificate for ${SITE_NAME}."
  echo "Browsers will show a certificate warning unless you use mkcert/trusted CA."
  echo
  echo "Certificate: ${cert_path}"
  echo "Private key: ${key_path}"
  echo

  if ! command -v openssl >/dev/null 2>&1; then
    log "Installing openssl"
    $SUDO apt-get update
    $SUDO apt-get install -y openssl
  fi

  $SUDO mkdir -p "$SSL_CERT_DIR"

  if [[ -f "$cert_path" || -f "$key_path" ]]; then
    local stamp
    stamp="$(date +%Y%m%d_%H%M%S)"
    warn "Existing certificate/key found. Backing them up first."
    [[ -f "$cert_path" ]] && $SUDO cp "$cert_path" "${cert_path}.bak.${stamp}"
    [[ -f "$key_path" ]] && $SUDO cp "$key_path" "${key_path}.bak.${stamp}"
  fi

  $SUDO openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "$key_path" \
    -out "$cert_path" \
    -subj "/CN=${SITE_NAME}" \
    -addext "subjectAltName=DNS:${SITE_NAME},IP:${vm_ip},DNS:localhost,IP:127.0.0.1"

  $SUDO chown root:root "$cert_path" "$key_path"
  $SUDO chmod 644 "$cert_path"
  $SUDO chmod 600 "$key_path"

  ok "Self-signed local certificate created"
  echo
  echo "Next steps:"
  echo "  ./install-erpnext-dev.sh configure-local-ssl"
  echo "  ./install-erpnext-dev.sh ssl-status"
  echo
  echo "Host test:"
  echo "  curl -kI https://${SITE_NAME}"
  echo "============================================================"
}

write_local_ssl_nginx_config() {
  local available_path cert_path key_path redirect_block
  available_path="$(ssl_nginx_available_path)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"

  if [[ "$SSL_REDIRECT_HTTP" == "true" ]]; then
    redirect_block="return 301 https://\$host\$request_uri;"
  else
    redirect_block="proxy_pass http://127.0.0.1:8000;\n    proxy_set_header Host \$host;\n    proxy_set_header X-Forwarded-Host \$host;\n    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n    proxy_set_header X-Forwarded-Proto http;\n    proxy_set_header X-Real-IP \$remote_addr;\n    proxy_redirect off;"
  fi

  $SUDO mkdir -p "${SSL_NGINX_CONF_DIR}/sites-available" "${SSL_NGINX_CONF_DIR}/sites-enabled"

  $SUDO tee "$available_path" >/dev/null <<EOF_NGINX
# Managed by ERPNext Developer Installer.
# Local development reverse proxy for ${SITE_NAME}.
# Direct Bench access remains available on :8000.

server {
    listen 80;
    server_name ${SITE_NAME};

    ${redirect_block}
}

server {
    listen 443 ssl http2;
    server_name ${SITE_NAME};

    ssl_certificate     ${cert_path};
    ssl_certificate_key ${key_path};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    client_max_body_size 100m;

    proxy_read_timeout 120s;
    proxy_send_timeout 120s;

    location /socket.io {
        proxy_pass http://127.0.0.1:9000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;
    }
}
EOF_NGINX
}

configure_local_ssl() {
  require_erpnext_vm_context "configure-local-ssl" || return 1
  require_sudo

  local cert_path key_path available_path enabled_path vm_ip
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  available_path="$(ssl_nginx_available_path)"
  enabled_path="$(ssl_nginx_enabled_path)"
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Configure Local SSL / HTTPS"
  echo "============================================================"
  echo "This configures Nginx as a local HTTPS reverse proxy."
  echo "It does not replace the ERPNext dev service and does not remove :8000 access."
  echo
  echo "Expected certificate: ${cert_path}"
  echo "Expected key:         ${key_path}"
  echo

  if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
    $SUDO mkdir -p "$SSL_CERT_DIR"
    warn "Certificate or key is missing."
    echo
    echo "Create/copy the certificate files first, then rerun this command."
    echo "For instructions, run: ./install-erpnext-dev.sh local-ssl-guide"
    echo
    echo "Quick target paths:"
    echo "  ${cert_path}"
    echo "  ${key_path}"
    echo "============================================================"
    return 1
  fi

  log "Installing Nginx if needed"
  $SUDO apt-get update
  $SUDO apt-get install -y nginx

  log "Writing local SSL reverse proxy config"
  write_local_ssl_nginx_config

  log "Enabling local SSL Nginx site"
  $SUDO ln -sfn "$available_path" "$enabled_path"

  log "Testing Nginx configuration"
  if ! $SUDO nginx -t; then
    err "Nginx configuration test failed. Disabling the new SSL site."
    $SUDO rm -f "$enabled_path"
    fail "Local SSL configuration failed. Existing ERPNext :8000 access was not changed."
  fi

  log "Starting/reloading Nginx"
  $SUDO systemctl enable --now nginx
  $SUDO systemctl reload nginx

  ok "Local HTTPS reverse proxy configured"
  echo
  echo "Test from the host:"
  echo "  curl -kI https://${SITE_NAME}"
  echo
  echo "Open in browser:"
  echo "  https://${SITE_NAME}"
  echo
  echo "Direct Bench access still works:"
  echo "  http://${SITE_NAME}:8000"
  echo "  http://${vm_ip}:8000"
  echo "============================================================"
}

disable_local_ssl() {
  require_erpnext_vm_context "disable-local-ssl" || return 1
  require_sudo

  local enabled_path available_path
  enabled_path="$(ssl_nginx_enabled_path)"
  available_path="$(ssl_nginx_available_path)"

  echo
  echo "============================================================"
  echo "Disable Local SSL / HTTPS"
  echo "============================================================"
  echo "This disables the Nginx site symlink only."
  echo "It keeps certificate files and the saved Nginx config for later reuse."
  echo

  if [[ -L "$enabled_path" || -f "$enabled_path" ]]; then
    $SUDO rm -f "$enabled_path"
    ok "Disabled local SSL site: $enabled_path"
  else
    warn "Local SSL site was not enabled."
  fi

  if command -v nginx >/dev/null 2>&1; then
    if $SUDO nginx -t; then
      $SUDO systemctl reload nginx || true
      ok "Nginx reloaded"
    else
      warn "Nginx config test failed after disabling. Check manually: sudo nginx -t"
    fi
  fi

  echo
  echo "Saved config: ${available_path}"
  echo "Direct Bench access remains available on :8000."
  echo "============================================================"
}

show_kvm_fixed_ip_guide() {
  local vm_ip clean_name escaped_site
  vm_ip="$(get_vm_ip)"
  clean_name="${SITE_NAME//./-}"
  escaped_site="${SITE_NAME//./\\.}"

  echo
  echo "============================================================"
  echo "KVM / libvirt Fixed IP Guide"
  echo "============================================================"
  echo
  echo "Purpose:"
  echo "  Keep this VM on the same IP so ${SITE_NAME} does not break after reboot."
  echo
  echo "Current VM IP detected inside this VM:"
  echo "  ${vm_ip}"
  echo

  if [[ "${vm_ip}" == 192.168.122.* ]]; then
    echo "This looks like the default libvirt NAT network range: 192.168.122.0/24"
  else
    echo "This IP is not in the default libvirt NAT range."
    echo "The guide still applies, but your network may be bridged, custom NAT, VMware, VirtualBox, or cloud."
  fi

  echo
  echo "Run these commands on the KVM HOST machine, not inside this VM:"
  echo
  echo "  virsh list --all"
  echo "  virsh domiflist \"YOUR_VM_NAME\""
  echo
  echo "Copy the VM MAC address from domiflist, then reserve the IP:"
  echo
  echo "  sudo virsh net-update default add ip-dhcp-host \"<host mac='YOUR_VM_MAC' name='${clean_name}' ip='${vm_ip}'/>\" --live --config"
  echo
  echo "Restart the VM from the host:"
  echo
  echo "  virsh shutdown \"YOUR_VM_NAME\""
  echo "  virsh start \"YOUR_VM_NAME\""
  echo
  echo "Verify the lease from the host:"
  echo
  echo "  sudo virsh net-dhcp-leases default"
  echo
  echo "Then update the host /etc/hosts entry:"
  echo
  echo "  sudo sed -i '/[[:space:]]${escaped_site}\$/d' /etc/hosts"
  echo "  echo \"${vm_ip} ${SITE_NAME}\" | sudo tee -a /etc/hosts"
  echo
  echo "Notes:"
  echo "  - Use one unique fixed IP per ERPNext VM."
  echo "  - Do not reserve the same IP for two VMs."
  echo "  - If this VM already has a different reservation, remove/update the old one on the host."
  echo
  echo "============================================================"
}

show_multi_environment_guide() {
  cat <<EOF_MULTI

============================================================
Multiple Local ERPNext Environments
============================================================

Use one VM, one site name, and one fixed IP per development environment.

Recommended examples:

  192.168.122.61  erp1.test
  192.168.122.62  erp2.test
  192.168.122.63  school.test
  192.168.122.64  client-a.test
  192.168.122.65  client-b.test

Install examples inside each VM:

  SITE_NAME=erp1.test ./install-erpnext-dev.sh setup
  SITE_NAME=school.test ./install-erpnext-dev.sh setup
  SITE_NAME=client-a.test ./install-erpnext-dev.sh setup

Host /etc/hosts examples on your Linux Mint host:

  192.168.122.61 erp1.test
  192.168.122.62 erp2.test
  192.168.122.63 school.test
  192.168.122.64 client-a.test

Recommended rule:
  - Local development: use .test domains.
  - Avoid .local because it is commonly used by mDNS/Avahi and tools like LocalWP.
  - Cloud/production: use a real domain and HTTPS, not bench start.

============================================================
EOF_MULTI
}

show_access_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "Access / Hostname / VM Networking Guide"
    echo "============================================================"
    echo "1) Show current VM browser access instructions"
    echo "2) Show host /etc/hosts command only"
    echo "3) Show VM network/access status"
    echo "4) Show host access test guide"
    echo "5) Show KVM VM identification + fixed IP helper"
    echo "6) Show KVM/libvirt fixed IP guide"
    echo "7) Show multi-environment naming guide"
    echo "8) Show SSL/HTTPS roadmap"
    echo "9) Show local SSL status"
    echo "10) Show local SSL guide"
    echo "11) Show trusted mkcert SSL guide"
    echo "12) Show browser trust check guide"
    echo "13) Verify local SSL"
    echo "14) Install/replace local SSL cert"
    echo "15) Create self-signed local cert"
    echo "16) Configure local SSL reverse proxy"
    echo "17) Disable local SSL reverse proxy"
    echo "18) Verify SSL rollback"
    echo "19) Show SSL rollback guide"
    echo "20) Domain config"
    echo "21) Production readiness preview"
    echo "22) Production domain guide"
    echo "23) Production SSL guide"
    echo "24) Environment / location check"
    echo "25) Back"
    echo
    read -r -p "Choose an option: " access_choice

    case "$access_choice" in
      1) show_access_instructions ;;
      2) show_host_hosts_command ;;
      3) show_network_status ;;
      4) show_host_access_test_guide ;;
      5) show_kvm_vm_identification_guide ;;
      6) show_kvm_fixed_ip_guide ;;
      7) show_multi_environment_guide ;;
      8) show_ssl_roadmap_guide ;;
      9) show_ssl_status ;;
      10) show_local_ssl_guide ;;
      11) show_mkcert_local_ssl_guide ;;
      12) show_browser_trust_check_guide ;;
      13) verify_local_ssl ;;
      14) install_local_ssl_cert ;;
      15) create_self_signed_local_cert ;;
      16) configure_local_ssl ;;
      17) disable_local_ssl ;;
      18) verify_ssl_rollback ;;
      19) show_ssl_rollback_guide ;;
      20) show_domain_config ;;
      21) show_production_readiness ;;
      22) show_production_domain_guide ;;
      23) show_production_ssl_guide ;;
      24) show_environment_check ;;
      25) return 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

post_install_validation_summary() {
  local free_gb service_status autostart_status
  free_gb="$(df -BG / | awk 'NR==2 {gsub("G", "", $4); print $4}' 2>/dev/null || echo 0)"
  service_status="$(service_state 2>/dev/null || echo unknown)"
  autostart_status="$(autostart_state 2>/dev/null || echo unknown)"

  echo
  echo "============================================================"
  echo "Post-Install Validation"
  echo "============================================================"

  if [[ "$free_gb" =~ ^[0-9]+$ && "$free_gb" -ge 30 ]]; then
    status_line "Root free space" "OK" "${free_gb}G available"
  else
    status_line "Root free space" "WARN" "${free_gb}G available; 60G+ recommended"
  fi

  if [[ "$service_status" == "Running" ]]; then
    status_line "ERPNext service" "OK" "$service_status"
  else
    status_line "ERPNext service" "INFO" "$service_status"
  fi

  if [[ "$autostart_status" == "Enabled" ]]; then
    status_line "Autostart" "OK" "$autostart_status"
  else
    status_line "Autostart" "WARN" "$autostart_status"
  fi

  if path_is_file "${FRAPPE_HOME}/erpnext-dev-credentials.txt"; then
    status_line "Credentials file" "OK" "${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  else
    status_line "Credentials file" "WARN" "missing at ${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  fi

  echo "============================================================"
}

print_summary() {
  local vm_ip bench_dir
  vm_ip="$(get_vm_ip)"
  bench_dir="$(active_bench_dir)"

  echo
  echo "============================================================"
  echo "ERPNext Developer Environment Installed"
  echo "============================================================"
  echo
  echo "Site: ${SITE_NAME}"
  echo "Bench: ${bench_dir}"
  echo
  echo "Login:"
  echo "  Username: Administrator"
  echo "  Password: saved in the credentials file"
  echo "  View with: sudo cat ${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  echo
  echo "Start ERPNext:"
  echo "  ./install-erpnext-dev.sh start"
  echo
  echo "Manual start command:"
  echo "  sudo -iu ${FRAPPE_USER}"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo "  cd ${bench_dir}"
  echo "  bench start"
  echo
  echo "Browser access:"
  echo "  Direct IP URL, works while Bench is running:"
  echo "    http://${vm_ip}:8000"
  echo
  echo "  Friendly URL, works after HOST /etc/hosts setup:"
  echo "    http://${SITE_NAME}:8000"
  echo
  echo "On your HOST machine, add/update this /etc/hosts entry:"
  echo "  ${vm_ip} ${SITE_NAME}"
  echo
  echo "Credentials file:"
  echo "  ${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  echo
  echo "Install log:"
  echo "  ${LOG_FILE}"
  echo
  echo "============================================================"
}


bench_dir_candidates() {
  printf '%s\n' \
    "${BENCH_DIR}" \
    "${FRAPPE_HOME}/${BENCH_NAME}" \
    "${FRAPPE_HOME}/frappe/${BENCH_NAME}"
}

detect_bench_dir() {
  local candidate found=""

  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    if bench_dir_is_valid "$candidate"; then
      echo "$candidate"
      return 0
    fi
    if [[ -z "$found" ]] && path_is_dir "$candidate"; then
      found="$candidate"
    fi
  done < <(bench_dir_candidates | awk '!seen[$0]++')

  if path_is_dir "$FRAPPE_HOME"; then
    if [[ "${SUDO:-}" == "sudo" ]]; then
      candidate="$($SUDO find "$FRAPPE_HOME" -maxdepth 3 -type d -name "$BENCH_NAME" 2>/dev/null | head -n 1 || true)"
    else
      candidate="$(find "$FRAPPE_HOME" -maxdepth 3 -type d -name "$BENCH_NAME" 2>/dev/null | head -n 1 || true)"
    fi
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  if [[ -n "$found" ]]; then
    echo "$found"
    return 0
  fi

  echo "$BENCH_DIR"
  return 1
}

active_bench_dir() {
  detect_bench_dir 2>/dev/null || echo "$BENCH_DIR"
}


bench_site_candidates() {
  local bench_dir="$1"
  local site

  [[ -d "${bench_dir}/sites" ]] || return 1

  if [[ -n "${SUDO:-}" && "${SUDO:-}" == "sudo" ]]; then
    $SUDO find "${bench_dir}/sites" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" 2>/dev/null \
      | grep -Ev "^(assets|private|public|logs|__pycache__)$" \
      | sort
  else
    find "${bench_dir}/sites" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" 2>/dev/null \
      | grep -Ev "^(assets|private|public|logs|__pycache__)$" \
      | sort
  fi
}

detect_site_name_from_bench() {
  local bench_dir current_site default_site sites_count first_site
  bench_dir="$(active_bench_dir)"

  [[ -d "$bench_dir" ]] || return 1

  if [[ -n "${SUDO:-}" && "${SUDO:-}" == "sudo" ]]; then
    current_site="$($SUDO cat "${bench_dir}/sites/currentsite.txt" 2>/dev/null | head -n 1 || true)"
  else
    current_site="$(cat "${bench_dir}/sites/currentsite.txt" 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -n "$current_site" ]] && validate_site_name_value "$current_site" >/dev/null 2>&1; then
    echo "$current_site"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    if [[ -n "${SUDO:-}" && "${SUDO:-}" == "sudo" ]]; then
      default_site="$($SUDO python3 - "$bench_dir" <<'PY_SITE_DEFAULT' 2>/dev/null || true
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "sites" / "common_site_config.json"
try:
    print(json.loads(p.read_text()).get("default_site", ""))
except Exception:
    pass
PY_SITE_DEFAULT
)"
    else
      default_site="$(python3 - "$bench_dir" <<'PY_SITE_DEFAULT' 2>/dev/null || true
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "sites" / "common_site_config.json"
try:
    print(json.loads(p.read_text()).get("default_site", ""))
except Exception:
    pass
PY_SITE_DEFAULT
)"
    fi
    if [[ -n "$default_site" ]] && validate_site_name_value "$default_site" >/dev/null 2>&1; then
      echo "$default_site"
      return 0
    fi
  fi

  sites_count="$(bench_site_candidates "$bench_dir" | wc -l | tr -d ' ' || echo 0)"
  if [[ "$sites_count" == "1" ]]; then
    first_site="$(bench_site_candidates "$bench_dir" | head -n 1)"
    if [[ -n "$first_site" ]] && validate_site_name_value "$first_site" >/dev/null 2>&1; then
      echo "$first_site"
      return 0
    fi
  fi

  return 1
}

resolve_site_name_after_sudo() {
  local saved detected

  if [[ "$SITE_NAME_ENV_PROVIDED" -eq 1 ]]; then
    SITE_NAME_SOURCE="environment"
    return 0
  fi

  if [[ "$SITE_NAME_SOURCE" == "setup prompt" ]]; then
    return 0
  fi

  if saved="$(read_saved_site_name_with_sudo 2>/dev/null)" && [[ -n "$saved" ]]; then
    if validate_site_name_value "$saved" >/dev/null 2>&1; then
      SITE_NAME="$saved"
      SITE_NAME_SOURCE="saved config"
      return 0
    fi
  fi

  if detected="$(detect_site_name_from_bench 2>/dev/null)" && [[ -n "$detected" ]]; then
    if validate_site_name_value "$detected" >/dev/null 2>&1; then
      SITE_NAME="$detected"
      SITE_NAME_SOURCE="detected bench site"
      return 0
    fi
  fi

  return 0
}

check_bench_app_installed() {
  local app="$1"
  local bench_dir
  bench_dir="$(active_bench_dir)"

  path_is_dir "${bench_dir}/apps/${app}"
}

site_exists() {
  local bench_dir
  bench_dir="$(active_bench_dir)"

  path_is_dir "${bench_dir}/sites/${SITE_NAME}"
}

site_app_installed() {
  local app="$1"
  local bench_dir
  bench_dir="$(active_bench_dir)"

  if ! path_is_dir "$bench_dir" || ! path_is_dir "${bench_dir}/sites/${SITE_NAME}"; then
    return 1
  fi

  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' list-apps" 2>/dev/null | awk '{print $1}' | grep -qx "$app"
}

install_state() {
  local bench_dir
  bench_dir="$(active_bench_dir)"

  if path_is_dir "${bench_dir}" && path_is_dir "${bench_dir}/apps/frappe" && path_is_dir "${bench_dir}/apps/erpnext" && path_is_dir "${bench_dir}/sites/${SITE_NAME}"; then
    if site_app_installed erpnext || [[ -f "${bench_dir}/sites/apps.txt" ]]; then
      echo "Installed"
    else
      echo "Installed files found; site app not confirmed"
    fi
  elif path_is_dir "${bench_dir}" || path_is_dir "${FRAPPE_HOME}"; then
    echo "Incomplete"
  else
    echo "Not installed"
  fi
}

runtime_state() {
  local ready_count
  ready_count="$(bench_ready_count)"

  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    if bench_ports_ready; then
      echo "Running via service"
    elif [[ "$ready_count" -gt 0 ]]; then
      echo "Starting / partially ready via service"
    else
      echo "Starting via service"
    fi
  elif port_listens 8000; then
    echo "Running in foreground"
  elif id "$FRAPPE_USER" >/dev/null 2>&1 && pgrep -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1; then
    echo "Starting / partially running"
  else
    echo "Stopped"
  fi
}

autostart_state() {
  if service_exists && systemctl is-enabled --quiet "${ERPNEXT_SERVICE_NAME}" 2>/dev/null; then
    echo "Enabled"
  elif service_exists; then
    echo "Disabled"
  else
    echo "Not configured"
  fi
}

service_state() {
  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    echo "Running"
  elif service_exists; then
    echo "Stopped"
  else
    echo "Not configured"
  fi
}

recommended_action() {
  local installed runtime auto
  installed="$1"
  runtime="$2"
  auto="$3"

  case "$installed" in
    "Installed"|"Installed files found; site app not confirmed")
      if [[ "$runtime" == Running* ]]; then
        if [[ "$auto" == "Enabled" ]]; then
          echo "ERPNext is ready. Open the browser URL below."
        else
          echo "ERPNext is running. Optional: enable autostart with ./install-erpnext-dev.sh enable-autostart"
        fi
      else
        echo "Start ERPNext with ./install-erpnext-dev.sh start"
      fi
      ;;
    "Incomplete")
      echo "Run ./install-erpnext-dev.sh repair, or run setup for a clean reinstall."
      ;;
    *)
      echo "Run ./install-erpnext-dev.sh setup"
      ;;
  esac
}

run_status() {
  require_sudo

  local vm_ip installed runtime auto svc bench_dir url_status
  vm_ip="$(get_vm_ip)"
  installed="$(install_state)"
  runtime="$(runtime_state)"
  auto="$(autostart_state)"
  svc="$(service_state)"
  bench_dir="$(active_bench_dir)"

  echo
  echo "============================================================"
  echo "ERPNext Developer Status"
  echo "============================================================"
  printf "  %-18s %s\n" "Install:" "$installed"
  printf "  %-18s %s\n" "Runtime:" "$runtime"
  printf "  %-18s %s\n" "Service:" "$svc"
  printf "  %-18s %s\n" "Autostart:" "$auto"
  printf "  %-18s %s\n" "Site:" "$SITE_NAME"
  printf "  %-18s %s\n" "VM IP:" "$vm_ip"
  printf "  %-18s http://%s:8000\n" "Direct URL:" "$vm_ip"
  printf "  %-18s http://%s:8000\n" "Friendly URL:" "$SITE_NAME"
  echo
  echo "Recommended action:"
  echo "  $(recommended_action "$installed" "$runtime" "$auto")"
  echo
  echo "Notes:"
  echo "  - Direct URL works after ERPNext is running."
  echo "  - Friendly URL also needs the HOST /etc/hosts entry: ${vm_ip} ${SITE_NAME}"
  echo "  - Detailed diagnostics: ./install-erpnext-dev.sh doctor"
  echo "============================================================"
}

run_runtime_status() {
  require_sudo

  echo
  echo "============================================================"
  echo "ERPNext Runtime Status"
  echo "============================================================"
  local runtime_status service_status autostart_status
  runtime_status="$(runtime_state)"
  service_status="$(service_state)"
  autostart_status="$(autostart_state)"

  if [[ "$runtime_status" == Running* ]]; then
    status_line "Runtime" "OK" "$runtime_status"
  elif [[ "$runtime_status" == Starting* ]]; then
    status_line "Runtime" "WARN" "$runtime_status"
  else
    status_line "Runtime" "INFO" "$runtime_status"
  fi

  if [[ "$service_status" == "Running" ]]; then
    status_line "Service" "OK" "$service_status"
  elif [[ "$service_status" == "Not configured" ]]; then
    status_line "Service" "WARN" "$service_status"
  else
    status_line "Service" "INFO" "$service_status"
  fi

  if [[ "$autostart_status" == "Enabled" ]]; then
    status_line "Autostart" "OK" "$autostart_status"
  else
    status_line "Autostart" "WARN" "$autostart_status"
  fi

  local item port label
  local port_checks=(
    "8000:Bench web"
    "9000:Socket.io"
    "11000:Bench Redis queue"
    "13000:Bench Redis cache"
  )

  for item in "${port_checks[@]}"; do
    port="${item%%:*}"
    label="${item#*:}"
    if port_listens "$port"; then
      status_line "$label" "OK" "port ${port} listening"
    elif [[ "$service_status" == "Running" ]]; then
      status_line "$label" "WARN" "port ${port} not listening yet"
    else
      status_line "$label" "INFO" "port ${port} not listening"
    fi
  done

  echo
  if [[ "$runtime_status" == Starting* ]]; then
    echo "ERPNext was recently started/restarted. If ports are still waiting, run:"
    echo "  sleep 30 && ./install-erpnext-dev.sh runtime-status"
    echo "  ./install-erpnext-dev.sh logs"
  else
    echo "If installed but stopped, run: ./install-erpnext-dev.sh start"
  fi
  echo "============================================================"
}

run_installation_status() {
  require_sudo

  local bench_dir
  bench_dir="$(active_bench_dir)"

  echo
  echo "============================================================"
  echo "ERPNext Installation Status"
  echo "============================================================"
  local install_status
  install_status="$(install_state)"
  if [[ "$install_status" == "Installed" ]]; then
    status_line "Install status" "OK" "$install_status"
  elif [[ "$install_status" == "Installed files found; site app not confirmed" ]]; then
    status_line "Install status" "WARN" "$install_status"
  else
    status_line "Install status" "FAIL" "$install_status"
  fi

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    status_line "frappe user" "OK" "$FRAPPE_USER exists"
  else
    status_line "frappe user" "FAIL" "$FRAPPE_USER missing"
  fi

  if path_is_dir "$bench_dir"; then
    status_line "Bench folder" "OK" "$bench_dir"
  else
    status_line "Bench folder" "FAIL" "$bench_dir missing"
  fi

  if check_bench_app_installed frappe; then
    status_line "Frappe app files" "OK" "apps/frappe exists"
  else
    status_line "Frappe app files" "FAIL" "apps/frappe missing"
  fi

  if check_bench_app_installed erpnext; then
    status_line "ERPNext app files" "OK" "apps/erpnext exists"
  else
    status_line "ERPNext app files" "WARN" "apps/erpnext missing"
  fi

  if site_exists; then
    status_line "Site folder" "OK" "${SITE_NAME} exists"
  else
    status_line "Site folder" "WARN" "${SITE_NAME} missing"
  fi

  if site_app_installed frappe; then
    status_line "Site app: frappe" "OK" "installed on ${SITE_NAME}"
  else
    status_line "Site app: frappe" "WARN" "not confirmed on ${SITE_NAME}"
  fi

  if site_app_installed erpnext; then
    status_line "Site app: erpnext" "OK" "installed on ${SITE_NAME}"
  else
    status_line "Site app: erpnext" "WARN" "not confirmed on ${SITE_NAME}"
  fi

  echo "============================================================"
}

run_service_summary() {
  require_sudo

  echo
  echo "============================================================"
  echo "ERPNext Service / Autostart Status"
  echo "============================================================"
  local service_status autostart_status
  service_status="$(service_state)"
  autostart_status="$(autostart_state)"

  if service_exists; then
    status_line "Service file" "OK" "$(erpnext_service_path)"
  else
    status_line "Service file" "WARN" "not created: $(erpnext_service_path)"
  fi

  if [[ "$service_status" == "Running" ]]; then
    status_line "Service" "OK" "$service_status"
  elif [[ "$service_status" == "Not configured" ]]; then
    status_line "Service" "WARN" "$service_status"
  else
    status_line "Service" "INFO" "$service_status"
  fi

  if [[ "$autostart_status" == "Enabled" ]]; then
    status_line "Autostart" "OK" "$autostart_status"
  else
    status_line "Autostart" "WARN" "$autostart_status"
  fi
  echo
  echo "Useful commands:"
  echo "  ./install-erpnext-dev.sh enable-autostart"
  echo "  ./install-erpnext-dev.sh disable-autostart"
  echo "  ./install-erpnext-dev.sh service-start"
  echo "  ./install-erpnext-dev.sh service-stop"
  echo "  ./install-erpnext-dev.sh logs"
  echo "============================================================"
}

show_status_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "Status"
    echo "============================================================"
    echo "1) Status Summary"
    echo "2) Runtime Status"
    echo "3) Installation Status"
    echo "4) Service / Autostart Status"
    echo "5) Optional App Status"
    echo "6) Full Health Report"
    echo "7) Back"
    echo
    read -r -p "Choose an option: " status_choice

    case "$status_choice" in
      1) run_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      2) run_runtime_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      3) run_installation_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      4) run_service_summary; pause_after_screen "Press Enter to return to Status Menu..." ;;
      5) run_app_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      6) run_full_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      7) return 0 ;;
      *) warn "Invalid option"; pause_after_screen "Press Enter to continue..." ;;
    esac
  done
}


run_full_status() {
  require_sudo

  echo
  echo "============================================================"
  echo "ERPNext Developer Full Health Report"
  echo "============================================================"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" && ( "${VERSION_ID:-}" == "24.04" || "${VERSION_ID:-}" == "26.04" ) ]]; then
      status_line "OS" "OK" "${PRETTY_NAME:-Ubuntu}"
    else
      status_line "OS" "FAIL" "${PRETTY_NAME:-unknown}; supported: Ubuntu 24.04 / 26.04"
    fi
  else
    status_line "OS" "FAIL" "/etc/os-release not found"
  fi

  if systemctl is-active --quiet mariadb; then
    status_line "MariaDB service" "OK" "running"
  else
    status_line "MariaDB service" "WARN" "not running"
  fi

  if systemctl is-active --quiet redis-server; then
    status_line "Redis service" "OK" "running"
  else
    status_line "Redis service" "WARN" "not running"
  fi

  if [[ "$(sysctl -n vm.overcommit_memory 2>/dev/null || echo 0)" == "1" ]]; then
    status_line "Redis overcommit" "OK" "vm.overcommit_memory=1"
  else
    status_line "Redis overcommit" "WARN" "not set to 1"
  fi

  if service_exists; then
    if systemctl is-enabled --quiet "${ERPNEXT_SERVICE_NAME}" 2>/dev/null; then
      status_line "ERPNext autostart" "OK" "enabled"
    else
      status_line "ERPNext autostart" "WARN" "disabled"
    fi

    if systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
      status_line "ERPNext service" "OK" "running"
    else
      status_line "ERPNext service" "INFO" "installed but stopped"
    fi
  else
    status_line "ERPNext service" "WARN" "not configured"
  fi

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    status_line "frappe user" "OK" "$FRAPPE_USER exists"
  else
    status_line "frappe user" "FAIL" "$FRAPPE_USER missing"
  fi

  local bench_dir
  bench_dir="$(active_bench_dir)"

  if path_is_dir "$bench_dir"; then
    status_line "Bench folder" "OK" "$bench_dir"
  else
    status_line "Bench folder" "FAIL" "$bench_dir missing"
  fi

  if check_bench_app_installed frappe; then
    status_line "Frappe app" "OK" "apps/frappe exists"
  else
    status_line "Frappe app" "FAIL" "apps/frappe missing"
  fi

  if check_bench_app_installed erpnext; then
    status_line "ERPNext app files" "OK" "apps/erpnext exists"
  else
    status_line "ERPNext app files" "WARN" "apps/erpnext missing"
  fi

  if path_is_dir "${bench_dir}/sites/${SITE_NAME}"; then
    status_line "Site" "OK" "${SITE_NAME} exists"
  else
    status_line "Site" "WARN" "${SITE_NAME} missing"
  fi

  if site_app_installed frappe; then
    status_line "Site app: frappe" "OK" "installed on ${SITE_NAME}"
  else
    status_line "Site app: frappe" "WARN" "not confirmed on ${SITE_NAME}"
  fi

  if site_app_installed erpnext; then
    status_line "Site app: erpnext" "OK" "installed on ${SITE_NAME}"
  else
    status_line "Site app: erpnext" "WARN" "not confirmed on ${SITE_NAME}"
  fi

  local optional_app optional_label optional_item
  local optional_apps=(
    "crm:Frappe CRM"
    "hrms:Frappe HR / HRMS"
    "telephony:Frappe Telephony"
    "helpdesk:Frappe Helpdesk"
    "insights:Frappe Insights"
  )

  for optional_item in "${optional_apps[@]}"; do
    optional_app="${optional_item%%:*}"
    optional_label="${optional_item#*:}"
    if site_app_installed "$optional_app"; then
      status_line "Optional: ${optional_app}" "OK" "${optional_label} installed"
    elif app_folder_exists "$bench_dir" "$optional_app"; then
      status_line "Optional: ${optional_app}" "WARN" "downloaded but not installed"
    else
      status_line "Optional: ${optional_app}" "INFO" "not installed"
    fi
  done

  local common_config="${bench_dir}/sites/common_site_config.json"
  if path_is_file "$common_config"; then
    if $SUDO grep -q '"default_site"[[:space:]]*:[[:space:]]*"'"${SITE_NAME}"'"' "$common_config" 2>/dev/null; then
      status_line "Default site" "OK" "${SITE_NAME}"
    else
      status_line "Default site" "WARN" "not set to ${SITE_NAME}"
    fi
  else
    status_line "Common config" "WARN" "common_site_config.json missing at ${common_config}"
  fi

  local port label item
  local port_checks=(
    "8000:Bench web"
    "9000:Socket.io"
    "11000:Bench Redis queue"
    "13000:Bench Redis cache"
  )

  for item in "${port_checks[@]}"; do
    port="${item%%:*}"
    label="${item#*:}"
    if port_listens "$port"; then
      status_line "$label" "OK" "port ${port} listening"
    else
      status_line "$label" "INFO" "port ${port} not listening"
    fi
  done

  if path_is_executable "${FRAPPE_HOME}/start-erpnext-dev.sh"; then
    status_line "Start helper" "OK" "${FRAPPE_HOME}/start-erpnext-dev.sh"
  else
    status_line "Start helper" "WARN" "missing or not executable at ${FRAPPE_HOME}/start-erpnext-dev.sh"
  fi

  if path_is_file "${FRAPPE_HOME}/erpnext-dev-credentials.txt"; then
    status_line "Credentials file" "OK" "${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  else
    status_line "Credentials file" "WARN" "missing at ${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  fi

  status_line "VM IP" "INFO" "$(get_vm_ip)"
  status_line "Direct IP URL" "INFO" "http://$(get_vm_ip):8000"
  status_line "Friendly URL" "INFO" "http://${SITE_NAME}:8000"
  status_line "Host /etc/hosts" "INFO" "$(get_vm_ip) ${SITE_NAME}"

  echo
  echo "Log file: ${LOG_FILE}"
  echo "============================================================"
}


# ============================================================
# App Library
# ============================================================

app_profile_defaults() {
  local profile="$1"

  LIB_APP_KEY=""
  LIB_APP_DISPLAY=""
  LIB_APP_NAME=""
  LIB_APP_REPO=""
  LIB_APP_BRANCH=""
  LIB_APP_NOTES=""

  case "$profile" in
    crm)
      LIB_APP_KEY="crm"
      LIB_APP_DISPLAY="Frappe CRM"
      LIB_APP_NAME="crm"
      LIB_APP_REPO="https://github.com/frappe/crm"
      LIB_APP_BRANCH="${CRM_BRANCH:-main}"
      LIB_APP_NOTES="Standalone modern CRM app. ERPNext already includes classic CRM features; install this if you want the separate Frappe CRM experience."
      ;;
    hrms|hr)
      LIB_APP_KEY="hrms"
      LIB_APP_DISPLAY="Frappe HR / HRMS"
      LIB_APP_NAME="hrms"
      LIB_APP_REPO="https://github.com/frappe/hrms"
      LIB_APP_BRANCH="${HRMS_BRANCH:-version-16}"
      LIB_APP_NOTES="HR, payroll, attendance, leave, employee lifecycle, and HR operations app for Frappe/ERPNext."
      ;;
    telephony)
      LIB_APP_KEY="telephony"
      LIB_APP_DISPLAY="Frappe Telephony"
      LIB_APP_NAME="telephony"
      LIB_APP_REPO="https://github.com/frappe/telephony"
      LIB_APP_BRANCH="${TELEPHONY_BRANCH:-develop}"
      LIB_APP_NOTES="Dependency app used by Frappe Helpdesk for telephony integrations. Installed automatically before Helpdesk when required."
      ;;
    helpdesk)
      LIB_APP_KEY="helpdesk"
      LIB_APP_DISPLAY="Frappe Helpdesk"
      LIB_APP_NAME="helpdesk"
      LIB_APP_REPO="https://github.com/frappe/helpdesk"
      LIB_APP_BRANCH="${HELPDESK_BRANCH:-main}"
      LIB_APP_NOTES="Ticketing and customer support app. Requires the Frappe Telephony app; the installer handles that dependency automatically."
      ;;
    insights)
      LIB_APP_KEY="insights"
      LIB_APP_DISPLAY="Frappe Insights"
      LIB_APP_NAME="insights"
      LIB_APP_REPO="https://github.com/frappe/insights"
      LIB_APP_BRANCH="${INSIGHTS_BRANCH:-main}"
      LIB_APP_NOTES="Business intelligence, reporting, and dashboard app for Frappe sites."
      ;;
    *)
      return 1
      ;;
  esac
}

validate_app_name() {
  local app_name="$1"
  [[ "$app_name" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]
}

validate_branch_name() {
  local branch="$1"
  [[ -z "$branch" || "$branch" =~ ^[A-Za-z0-9._/-]+$ ]]
}

app_folder_exists() {
  local bench_dir="$1"
  local app_name="$2"
  path_is_dir "${bench_dir}/apps/${app_name}"
}

get_app_current_branch() {
  local bench_dir="$1"
  local app_name="$2"

  if app_folder_exists "$bench_dir" "$app_name"; then
    run_as_frappe "cd '${bench_dir}/apps/${app_name}' && git rev-parse --abbrev-ref HEAD 2>/dev/null" 2>/dev/null || true
  fi
}

branch_available() {
  local repo="$1"
  local branch="$2"
  local repo_q branch_q

  [[ -z "$branch" ]] && return 0

  repo_q="$(printf '%q' "$repo")"
  branch_q="$(printf '%q' "$branch")"
  git ls-remote --exit-code --heads "$repo" "$branch" >/dev/null 2>&1 || run_as_frappe "git ls-remote --exit-code --heads ${repo_q} ${branch_q} >/dev/null 2>&1"
}


ensure_app_library_node_tools() {
  log "Checking Node/Yarn environment for App Library"

  run_as_frappe '
set -e

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js was not found for the frappe user." >&2
  echo "Run Recommended Setup or repair the Node/nvm installation first." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm was not found for the frappe user." >&2
  exit 1
fi

if ! command -v yarn >/dev/null 2>&1; then
  echo "Yarn was not found. Installing Yarn globally with npm..."
  npm install -g yarn
fi

echo "Node: $(command -v node) $(node -v)"
echo "NPM:  $(command -v npm) $(npm -v)"
echo "Yarn: $(command -v yarn) $(yarn -v)"
' || fail "Node/Yarn preflight failed for App Library."

  ok "Node/Yarn environment ready"
}

prepare_downloaded_app_dependencies() {
  local bench_dir="$1"
  local app_name="$2"

  if ! app_folder_exists "$bench_dir" "$app_name"; then
    return 0
  fi

  log "Preparing dependencies for downloaded app: ${app_name}"

  run_as_frappe "
set -e
cd '${bench_dir}'

if [ -x './env/bin/python' ]; then
  echo 'Installing Python package in bench environment...'
  ./env/bin/python -m pip install -q -e 'apps/${app_name}'
fi

if [ -f 'apps/${app_name}/package.json' ]; then
  echo 'Installing frontend dependencies with Yarn...'
  cd 'apps/${app_name}'
  yarn install --check-files
fi
" || fail "Dependency preparation failed for ${app_name}. Check the app compatibility and logs."

  ok "Dependencies ready for ${app_name}"
}


normalize_apps_txt() {
  local bench_dir="$1"
  local required_app="${2:-}"
  local quiet="${3:-false}"
  local repair_py
  local bench_q repair_py_q required_q quiet_q

  bench_q="$(printf '%q' "$bench_dir")"
  required_q="$(printf '%q' "$required_app")"
  quiet_q="$(printf '%q' "$quiet")"

  if [[ "$quiet" != "true" ]]; then
    log "Normalizing Bench app registry: sites/apps.txt"
  fi

  repair_py="$(mktemp /tmp/erpnext-dev-app-registry.XXXXXX.py)" || return 1

  cat > "$repair_py" <<'PY_APP_REGISTRY'
from pathlib import Path
import sys

required = sys.argv[1] if len(sys.argv) > 1 else ""
quiet = (sys.argv[2].lower() == "true") if len(sys.argv) > 2 else False

apps_dir = Path("apps")
apps_txt = Path("sites/apps.txt")
apps_txt.parent.mkdir(parents=True, exist_ok=True)

valid = []
if apps_dir.exists():
    for d in sorted([x for x in apps_dir.iterdir() if x.is_dir()], key=lambda x: x.name):
        # A Frappe app folder normally contains a Python package with the same name.
        # setup.py / pyproject.toml are fallback signals for app repositories.
        if (d / d.name).is_dir() or (d / "pyproject.toml").exists() or (d / "setup.py").exists():
            valid.append(d.name)

valid_set = set(valid)
raw = apps_txt.read_text() if apps_txt.exists() else ""
original = raw

names_by_len = sorted(valid, key=len, reverse=True)

def split_concat(token: str):
    token = token.strip()
    if not token:
        return []
    if token in valid_set:
        return [token]

    out = []
    i = 0
    while i < len(token):
        match = None
        for name in names_by_len:
            if token.startswith(name, i):
                match = name
                break
        if match is None:
            # Unknown token. Returning it allows filtering below to drop it safely.
            return [token]
        out.append(match)
        i += len(match)
    return out

items = []
for token in raw.replace("\r", "\n").replace(",", "\n").split():
    for item in split_concat(token):
        if item and item not in items:
            items.append(item)

# Drop invalid entries like erpnextcrm. Frappe tries to import every entry in apps.txt.
items = [x for x in items if x in valid_set]

ordered = []
preferred = ("frappe", "erpnext", "crm", "hrms", "telephony", "helpdesk", "insights")

# Keep core and curated apps in a predictable order for cleaner diagnostics.
for name in preferred:
    if name in valid_set and name not in ordered:
        ordered.append(name)

# Preserve any custom app entries after the curated apps.
for item in items:
    if item in valid_set and item not in ordered:
        ordered.append(item)

if required and required in valid_set and required not in ordered:
    ordered.append(required)

# Register valid downloaded apps so partially interrupted get-app states are recoverable.
for item in valid:
    if item not in ordered:
        ordered.append(item)

new = "\n".join(ordered) + ("\n" if ordered else "")
if new != original:
    if apps_txt.exists():
        backup = apps_txt.with_name("apps.txt.bak.registry-repair")
        backup.write_text(original)
    apps_txt.write_text(new)
    if not quiet:
        print("Repaired sites/apps.txt:")
        print(new, end="")
else:
    if not quiet:
        print("sites/apps.txt already normalized")
PY_APP_REGISTRY

  chmod 644 "$repair_py" 2>/dev/null || true

  repair_py_q="$(printf '%q' "$repair_py")"

  run_as_frappe "set -e; cd ${bench_q}; python3 ${repair_py_q} ${required_q} ${quiet_q}"
  local rc=$?

  rm -f "$repair_py" 2>/dev/null || true
  return "$rc"
}

repair_app_registry() {
  require_sudo
  local bench_dir
  bench_dir="$(require_site_environment)" || return 1
  normalize_apps_txt "$bench_dir" "" "false" || fail "Could not repair sites/apps.txt."
  ok "Bench app registry repair completed"
  show_installed_apps
}

ensure_app_in_apps_txt() {
  local bench_dir="$1"
  local app_name="$2"
  local bench_q app_q

  if ! app_folder_exists "$bench_dir" "$app_name"; then
    fail "App folder apps/${app_name} is missing; cannot register it in sites/apps.txt."
  fi

  bench_q="$(printf '%q' "$bench_dir")"
  app_q="$(printf '%q' "$app_name")"

  normalize_apps_txt "$bench_dir" "$app_name" "false" || fail "Could not normalize sites/apps.txt before installing ${app_name}."

  run_as_frappe "cd ${bench_q} && grep -qxF ${app_q} sites/apps.txt" || fail "Could not register ${app_name} in sites/apps.txt."

  ok "${app_name} is registered in sites/apps.txt"
}

app_in_apps_txt() {
  local app="$1"
  local bench_dir bench_q app_q
  bench_dir="$(active_bench_dir)"
  bench_q="$(printf '%q' "$bench_dir")"
  app_q="$(printf '%q' "$app")"

  path_is_file "${bench_dir}/sites/apps.txt" || return 1
  run_as_frappe "cd ${bench_q} && grep -qxF ${app_q} sites/apps.txt" >/dev/null 2>&1
}

run_app_status() {
  require_sudo

  local bench_dir app label
  bench_dir="$(require_site_environment)" || return 1

  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before app status."

  echo
  echo "============================================================"
  echo "Optional Frappe App Status"
  echo "============================================================"
  echo "Site: ${SITE_NAME}"
  echo "Bench: ${bench_dir}"
  echo

  local app_items=(
    "crm:Frappe CRM"
    "hrms:Frappe HR / HRMS"
    "telephony:Frappe Telephony"
    "helpdesk:Frappe Helpdesk"
    "insights:Frappe Insights"
  )

  for item in "${app_items[@]}"; do
    app="${item%%:*}"
    label="${item#*:}"

    if site_app_installed "$app"; then
      status_line "$label" "OK" "installed on ${SITE_NAME}"
    elif app_folder_exists "$bench_dir" "$app" && app_in_apps_txt "$app"; then
      status_line "$label" "WARN" "downloaded and registered, not installed on ${SITE_NAME}"
    elif app_folder_exists "$bench_dir" "$app"; then
      status_line "$label" "WARN" "downloaded, not registered in sites/apps.txt"
    else
      status_line "$label" "INFO" "not installed"
    fi
  done

  echo "============================================================"
}

show_installed_apps() {
  require_sudo

  local bench_dir bench_q site_q
  bench_dir="$(require_site_environment)" || return 1
  bench_q="$(printf '%q' "$bench_dir")"
  site_q="$(printf '%q' "$SITE_NAME")"

  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before listing apps."

  echo
  echo "============================================================"
  echo "Frappe / ERPNext Apps"
  echo "============================================================"
  echo "Site: ${SITE_NAME}"
  echo "Bench: ${bench_dir}"
  echo
  echo "Installed on site:"
  run_as_frappe "cd ${bench_q} && bench --site ${site_q} list-apps" || warn "Could not list installed apps."
  echo
  echo "Downloaded app folders:"
  run_as_frappe "cd ${bench_q} && find apps -maxdepth 1 -mindepth 1 -type d -printf '  %f\\n' | sort" || warn "Could not list downloaded app folders."
  echo
  echo "Downloaded but not installed on ${SITE_NAME}:"
  run_as_frappe "
set -e
cd ${bench_q}
installed=\$(bench --site ${site_q} list-apps 2>/dev/null | awk '{print \$1}')
missing=0
for d in apps/*; do
  [ -d \"\$d\" ] || continue
  app=\"\${d##*/}\"
  if ! printf '%s\\n' \"\$installed\" | grep -qx \"\$app\"; then
    echo \"  \$app\"
    missing=1
  fi
done
if [ \"\${missing:-0}\" = \"0\" ]; then
  echo '  none'
fi
" || warn "Could not compare downloaded apps with installed site apps."
  echo
  echo "Downloaded but not registered in sites/apps.txt:"
  run_as_frappe "
set -e
cd ${bench_q}
missing=0
for d in apps/*; do
  [ -d \"\$d\" ] || continue
  app=\"\${d##*/}\"
  if ! grep -qxF \"\$app\" sites/apps.txt 2>/dev/null; then
    echo \"  \$app\"
    missing=1
  fi
done
if [ \"\${missing:-0}\" = \"0\" ]; then
  echo '  none'
fi
" || warn "Could not compare downloaded apps with sites/apps.txt."
  echo "============================================================"
}

print_app_profile() {
  local display="$1"
  local app_name="$2"
  local repo="$3"
  local branch="$4"
  local notes="$5"

  echo
  echo "App:    ${display}"
  echo "Name:   ${app_name}"
  echo "Repo:   ${repo}"
  if [[ -n "$branch" ]]; then
    echo "Branch: ${branch}"
  else
    echo "Branch: default repository branch"
  fi
  echo "Notes:  ${notes}"
  echo
}


install_app_dependency_telephony() {
  local bench_dir="$1"
  local dep_name="telephony"
  local dep_display="Frappe Telephony"
  local dep_repo="https://github.com/frappe/telephony"
  local dep_branch="${TELEPHONY_BRANCH:-develop}"
  local repo_q branch_q downloaded_branch

  if site_app_installed "$dep_name"; then
    ok "${dep_display} dependency is already installed on ${SITE_NAME}"
    return 0
  fi

  echo
  log "Frappe Helpdesk requires ${dep_display}. Installing dependency first."

  if ! validate_branch_name "$dep_branch"; then
    fail "Invalid TELEPHONY_BRANCH value: ${dep_branch}"
  fi

  if app_folder_exists "$bench_dir" "$dep_name"; then
    downloaded_branch="$(get_app_current_branch "$bench_dir" "$dep_name" | tail -1 | tr -d '[:space:]')"
    ok "Dependency already downloaded: apps/${dep_name}"
    if [[ -n "$dep_branch" && -n "$downloaded_branch" && "$downloaded_branch" != "$dep_branch" ]]; then
      warn "Downloaded ${dep_name} branch is '${downloaded_branch}', requested '${dep_branch}'."
      warn "The script will not switch branches automatically. Use Git manually if needed."
    fi
  else
    log "Verifying branch ${dep_branch} exists for ${dep_repo}"
    if ! branch_available "$dep_repo" "$dep_branch"; then
      fail "Branch '${dep_branch}' was not found or GitHub could not be reached for ${dep_repo}. Override TELEPHONY_BRANCH or install manually."
    fi

    repo_q="$(printf '%q' "$dep_repo")"
    branch_q="$(printf '%q' "$dep_branch")"

    log "Downloading ${dep_display}"
    run_as_frappe "cd '${bench_dir}' && bench get-app ${repo_q} --branch ${branch_q}" || fail "Could not download ${dep_display}."
  fi

  prepare_downloaded_app_dependencies "$bench_dir" "$dep_name"
  ensure_app_in_apps_txt "$bench_dir" "$dep_name"

  if site_app_installed "$dep_name"; then
    ok "${dep_display} dependency is already installed on ${SITE_NAME}"
  else
    log "Installing ${dep_display} dependency on ${SITE_NAME}"
    run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' install-app '${dep_name}'" || fail "Could not install ${dep_display} dependency."
    ok "${dep_display} dependency installed"
  fi
}

install_app_dependencies() {
  local bench_dir="$1"
  local app_name="$2"

  case "$app_name" in
    helpdesk)
      install_app_dependency_telephony "$bench_dir"
      ;;
  esac
}

install_frappe_app() {
  require_sudo
  check_internet

  local app_name="$1"
  local display="$2"
  local repo="$3"
  local branch="$4"
  local notes="$5"
  local bench_dir repo_q branch_q downloaded_branch was_running

  bench_dir="$(require_site_environment)" || return 1

  if ! validate_app_name "$app_name"; then
    fail "Invalid app name: ${app_name}"
  fi

  if ! validate_branch_name "$branch"; then
    fail "Invalid branch name: ${branch}"
  fi

  print_app_profile "$display" "$app_name" "$repo" "$branch" "$notes"

  # Repair any existing apps.txt corruption before backups or bench site commands.
  # A prior interrupted app install can create concatenated entries like erpnextcrm.
  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before app install."

  if site_app_installed "$app_name"; then
    ok "${display} is already installed on ${SITE_NAME}"
    return 0
  fi

  if ! confirm "Install ${display} on ${SITE_NAME}?"; then
    warn "App installation cancelled."
    return 0
  fi

  if confirm "Create a database + files backup before installing ${display}?"; then
    create_site_backup true || warn "Pre-install backup failed. Continuing only because app installation was explicitly confirmed."
  fi

  ensure_app_library_node_tools
  install_app_dependencies "$bench_dir" "$app_name"

  was_running=0
  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    was_running=1
  fi

  if app_folder_exists "$bench_dir" "$app_name"; then
    downloaded_branch="$(get_app_current_branch "$bench_dir" "$app_name" | tail -1 | tr -d '[:space:]')"
    ok "App already downloaded: apps/${app_name}"
    if [[ -n "$branch" && -n "$downloaded_branch" && "$downloaded_branch" != "$branch" ]]; then
      warn "Downloaded app branch is '${downloaded_branch}', requested '${branch}'."
      warn "The script will not switch branches automatically. Use Git manually if needed."
    fi
  else
    if [[ -n "$branch" ]]; then
      log "Verifying branch ${branch} exists for ${repo}"
      if ! branch_available "$repo" "$branch"; then
        fail "Branch '${branch}' was not found or GitHub could not be reached for ${repo}. Override the branch with an environment variable or install manually."
      fi
    fi

    repo_q="$(printf '%q' "$repo")"
    branch_q="$(printf '%q' "$branch")"

    log "Downloading ${display}"
    if [[ -n "$branch" ]]; then
      run_as_frappe "cd '${bench_dir}' && bench get-app ${repo_q} --branch ${branch_q}"
    else
      run_as_frappe "cd '${bench_dir}' && bench get-app ${repo_q}"
    fi
  fi

  prepare_downloaded_app_dependencies "$bench_dir" "$app_name"
  ensure_app_in_apps_txt "$bench_dir" "$app_name"

  if site_app_installed "$app_name"; then
    ok "${display} is already installed on ${SITE_NAME}"
  else
    log "Installing ${display} on ${SITE_NAME}"
    run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' install-app '${app_name}'"
  fi

  log "Running post-app maintenance"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate"
  run_as_frappe "cd '${bench_dir}' && bench build"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache"

  if [[ "$was_running" -eq 1 ]]; then
    restart_erpnext_service || warn "${display} installed, but the service could not be restarted automatically."
  fi

  ok "${display} installation workflow completed"
  show_installed_apps
}

install_app_profile() {
  local profile="$1"

  app_profile_defaults "$profile" || fail "Unknown app profile: ${profile}"
  install_frappe_app "$LIB_APP_NAME" "$LIB_APP_DISPLAY" "$LIB_APP_REPO" "$LIB_APP_BRANCH" "$LIB_APP_NOTES"
}

install_custom_app_interactive() {
  require_sudo

  local app_name display repo branch notes

  echo
  echo "============================================================"
  echo "Install Custom Frappe App"
  echo "============================================================"
  echo "Use this for trusted Frappe apps only. The app must be compatible with your Frappe branch."
  echo

  read -r -p "App name used by bench install-app, for example my_app: " app_name
  if ! validate_app_name "$app_name"; then
    fail "Invalid app name. Use letters, numbers, underscore, or hyphen only."
  fi

  read -r -p "Git repository URL: " repo
  if [[ -z "$repo" ]]; then
    fail "Repository URL is required."
  fi

  read -r -p "Branch [leave blank for repository default]: " branch
  if ! validate_branch_name "$branch"; then
    fail "Invalid branch name."
  fi

  read -r -p "Display name [${app_name}]: " display
  display="${display:-$app_name}"
  notes="Custom app provided by the user. Verify compatibility before using it with important data."

  install_frappe_app "$app_name" "$display" "$repo" "$branch" "$notes"
}

show_app_library_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "App Library"
    echo "============================================================"
    echo "1) Show installed apps"
    echo "2) Install Frappe CRM"
    echo "3) Install Frappe HR / HRMS"
    echo "4) Install Frappe Helpdesk"
    echo "5) Install Frappe Telephony"
    echo "6) Install Frappe Insights"
    echo "7) Install custom app from Git URL"
    echo "8) Back"
    echo
    echo "Notes:"
    echo "  - App installs can take several minutes."
    echo "  - The script offers a backup before installation."
    echo "  - Optional apps should be tested in a VM snapshot before production use."
    echo
    read -r -p "Choose an option: " app_choice

    case "$app_choice" in
      1) show_installed_apps; pause_after_screen "Press Enter to return to App Library..." ;;
      2) install_app_profile crm; pause_after_screen "Press Enter to return to App Library..." ;;
      3) install_app_profile hrms; pause_after_screen "Press Enter to return to App Library..." ;;
      4) install_app_profile helpdesk; pause_after_screen "Press Enter to return to App Library..." ;;
      5) install_app_profile telephony; pause_after_screen "Press Enter to return to App Library..." ;;
      6) install_app_profile insights; pause_after_screen "Press Enter to return to App Library..." ;;
      7) install_custom_app_interactive; pause_after_screen "Press Enter to return to App Library..." ;;
      8) return 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

# ============================================================
# Backup / Restore / Maintenance
# ============================================================

site_backup_dir() {
  local bench_dir
  bench_dir="$(active_bench_dir)"
  echo "${bench_dir}/sites/${SITE_NAME}/private/backups"
}

require_site_environment() {
  local bench_dir
  bench_dir="$(require_bench_dir)" || return 1

  if ! path_is_dir "${bench_dir}/sites/${SITE_NAME}"; then
    err "Site not found: ${SITE_NAME}"
    err "Expected: ${bench_dir}/sites/${SITE_NAME}"
    err "Run Recommended Setup first, or check SITE_NAME."
    return 1
  fi

  echo "$bench_dir"
}

show_latest_backups() {
  local bench_dir backup_rel
  bench_dir="$(active_bench_dir)"
  backup_rel="sites/${SITE_NAME}/private/backups"

  if ! path_is_dir "${bench_dir}/${backup_rel}"; then
    warn "Backup folder not found: ${bench_dir}/${backup_rel}"
    return 0
  fi

  echo
  echo "Latest backup files:"
  run_as_frappe "cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM  %p\\n' 2>/dev/null | sort -r | head -12" || true
}

create_site_backup() {
  require_sudo

  local include_files="${1:-false}"
  local bench_dir backup_cmd tmp_output rc
  bench_dir="$(require_site_environment)" || return 1

  # Backup uses bench, so repair the app registry first. A corrupted apps.txt can make
  # backup print a failure while still leaving partial files behind.
  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before backup."

  if [[ "$include_files" == "true" ]]; then
    log "Creating database + files backup for ${SITE_NAME}"
    backup_cmd="bench --site '${SITE_NAME}' backup --with-files"
  else
    log "Creating database backup for ${SITE_NAME}"
    backup_cmd="bench --site '${SITE_NAME}' backup"
  fi

  tmp_output="$(mktemp /tmp/erpnext-dev-backup.XXXXXX.log)" || return 1
  set +e
  run_as_frappe "cd '${bench_dir}' && ${backup_cmd}" 2>&1 | tee "$tmp_output"
  rc=${PIPESTATUS[0]}
  set -e

  if [[ "$rc" -ne 0 ]] || grep -Eqi 'Backup failed|Traceback|ModuleNotFoundError|Database or site_config.json may be corrupted' "$tmp_output"; then
    warn "Backup did not complete cleanly. Partial backup files may exist, but they should not be trusted."
    rm -f "$tmp_output"
    return 1
  fi

  rm -f "$tmp_output"
  ok "Backup completed"
  show_latest_backups
}

print_backup_results() {
  local title="$1"
  local count_cmd="$2"
  local list_cmd="$3"
  local count output

  count="$(run_as_frappe "${count_cmd}" 2>/dev/null | tr -d '[:space:]' || true)"
  count="${count:-0}"

  echo "${title} (${count}):"
  output="$(run_as_frappe "${list_cmd}" 2>/dev/null || true)"
  if [[ -n "$output" ]]; then
    echo "$output"
  else
    echo "  none"
  fi
}

list_site_backups() {
  require_sudo

  local bench_dir backup_rel backup_abs
  local db_count_cmd db_list_cmd public_count_cmd public_list_cmd private_count_cmd private_list_cmd
  bench_dir="$(require_site_environment)" || return 1
  backup_rel="sites/${SITE_NAME}/private/backups"
  backup_abs="${bench_dir}/${backup_rel}"

  echo
  echo "============================================================"
  echo "ERPNext Backups"
  echo "============================================================"
  echo "Site: ${SITE_NAME}"
  echo "Backup folder: ${backup_abs}"
  echo

  if ! path_is_dir "$backup_abs"; then
    warn "No backup folder found yet. Create a backup first."
    echo "============================================================"
    return 0
  fi

  db_count_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-database.sql.gz' -o -name '*.sql.gz' -o -name '*database*.sql.gz' \\) -print 2>/dev/null | wc -l"
  db_list_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-database.sql.gz' -o -name '*.sql.gz' -o -name '*database*.sql.gz' \\) -printf '  %TY-%Tm-%Td %TH:%TM  %f\\n' 2>/dev/null | sort -r | head -20"

  # Public and private file backups must be matched separately.
  # Frappe names public backups like '*-files.tar' and private backups like '*-private-files.tar'.
  # A broad '*files.tar' match incorrectly includes private backups, so explicitly exclude them here.
  public_count_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-files.tar' -o -name '*-files.tar.gz' \\) ! -name '*-private-files.tar' ! -name '*-private-files.tar.gz' -print 2>/dev/null | wc -l"
  public_list_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-files.tar' -o -name '*-files.tar.gz' \\) ! -name '*-private-files.tar' ! -name '*-private-files.tar.gz' -printf '  %TY-%Tm-%Td %TH:%TM  %f\\n' 2>/dev/null | sort -r | head -20"

  private_count_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-private-files.tar' -o -name '*-private-files.tar.gz' \\) -print 2>/dev/null | wc -l"
  private_list_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-private-files.tar' -o -name '*-private-files.tar.gz' \\) -printf '  %TY-%Tm-%Td %TH:%TM  %f\\n' 2>/dev/null | sort -r | head -20"

  print_backup_results "Database backups" "$db_count_cmd" "$db_list_cmd"
  echo
  print_backup_results "Public file backups" "$public_count_cmd" "$public_list_cmd"
  echo
  print_backup_results "Private file backups" "$private_count_cmd" "$private_list_cmd"
  echo
  echo "Tip: For restore, you can paste either an absolute path or a filename from this folder."
  echo "============================================================"
}

resolve_backup_file_path() {
  local input="$1"
  local backup_dir
  backup_dir="$(site_backup_dir)"

  if [[ -z "$input" ]]; then
    return 1
  fi

  if [[ "$input" = /* ]]; then
    echo "$input"
  else
    echo "${backup_dir}/${input}"
  fi
}

confirm_restore() {
  warn "Restore is destructive. It can overwrite the current site database and files."
  warn "The script will try to create an emergency backup before restore."
  echo
  read -r -p "Type RESTORE to continue: " restore_reply
  [[ "$restore_reply" == "RESTORE" ]]
}

restore_site_database() {
  require_sudo

  local bench_dir db_input db_file db_quoted was_running
  bench_dir="$(require_site_environment)" || return 1

  list_site_backups
  echo
  read -r -p "Enter database backup filename or full path: " db_input
  db_file="$(resolve_backup_file_path "$db_input")" || fail "No database backup selected."

  if ! path_is_file "$db_file"; then
    fail "Database backup file not found: ${db_file}"
  fi

  confirm_restore || fail "Restore cancelled."

  was_running=0
  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    was_running=1
  fi

  log "Creating emergency backup before restore"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' backup --with-files" || warn "Emergency backup failed; continuing only because restore was explicitly confirmed."

  stop_erpnext_service || true

  db_quoted="$(printf '%q' "$db_file")"

  log "Restoring database backup"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' restore ${db_quoted}"

  log "Running post-restore maintenance"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate"
  run_as_frappe "cd '${bench_dir}' && bench build"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache"

  if [[ "$was_running" -eq 1 ]]; then
    start_erpnext_service || warn "Restore completed, but service could not be restarted automatically."
  fi

  ok "Database restore completed"
}

restore_site_full() {
  require_sudo

  local bench_dir db_input public_input private_input db_file public_file private_file cmd was_running
  local db_quoted public_quoted private_quoted
  bench_dir="$(require_site_environment)" || return 1

  list_site_backups
  echo
  read -r -p "Enter database backup filename or full path: " db_input
  read -r -p "Enter public files backup filename/path, or leave blank: " public_input
  read -r -p "Enter private files backup filename/path, or leave blank: " private_input

  db_file="$(resolve_backup_file_path "$db_input")" || fail "No database backup selected."
  if ! path_is_file "$db_file"; then
    fail "Database backup file not found: ${db_file}"
  fi

  cmd="bench --site '${SITE_NAME}' restore"
  db_quoted="$(printf '%q' "$db_file")"
  cmd="${cmd} ${db_quoted}"

  if [[ -n "$public_input" ]]; then
    public_file="$(resolve_backup_file_path "$public_input")"
    if ! path_is_file "$public_file"; then
      fail "Public files backup not found: ${public_file}"
    fi
    public_quoted="$(printf '%q' "$public_file")"
    cmd="${cmd} --with-public-files ${public_quoted}"
  fi

  if [[ -n "$private_input" ]]; then
    private_file="$(resolve_backup_file_path "$private_input")"
    if ! path_is_file "$private_file"; then
      fail "Private files backup not found: ${private_file}"
    fi
    private_quoted="$(printf '%q' "$private_file")"
    cmd="${cmd} --with-private-files ${private_quoted}"
  fi

  confirm_restore || fail "Restore cancelled."

  was_running=0
  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    was_running=1
  fi

  log "Creating emergency backup before full restore"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' backup --with-files" || warn "Emergency backup failed; continuing only because restore was explicitly confirmed."

  stop_erpnext_service || true

  log "Restoring database/files backup"
  run_as_frappe "cd '${bench_dir}' && ${cmd}"

  log "Running post-restore maintenance"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate"
  run_as_frappe "cd '${bench_dir}' && bench build"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache"

  if [[ "$was_running" -eq 1 ]]; then
    start_erpnext_service || warn "Restore completed, but service could not be restarted automatically."
  fi

  ok "Full restore completed"
}

maintenance_migrate() {
  require_sudo
  local bench_dir
  bench_dir="$(require_site_environment)" || return 1
  log "Running migrate for ${SITE_NAME}"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate"
  ok "Migrate completed"
}

maintenance_build() {
  require_sudo
  local bench_dir
  bench_dir="$(require_site_environment)" || return 1
  log "Building assets"
  run_as_frappe "cd '${bench_dir}' && bench build"
  ok "Build completed"
}

maintenance_clear_cache() {
  require_sudo
  local bench_dir
  bench_dir="$(require_site_environment)" || return 1
  log "Clearing cache for ${SITE_NAME}"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache"
  ok "Cache cleared"
}

maintenance_restart() {
  require_sudo
  restart_erpnext_service
}

run_maintenance_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "Maintenance"
    echo "============================================================"
    echo "1) Run migrate"
    echo "2) Build assets"
    echo "3) Clear cache"
    echo "4) Restart ERPNext service"
    echo "5) Run safe repair"
    echo "6) Show recent service logs"
    echo "7) Back"
    echo
    read -r -p "Choose an option: " maintenance_choice

    case "$maintenance_choice" in
      1) maintenance_migrate; pause_after_screen "Press Enter to return to Maintenance..." ;;
      2) maintenance_build; pause_after_screen "Press Enter to return to Maintenance..." ;;
      3) maintenance_clear_cache; pause_after_screen "Press Enter to return to Maintenance..." ;;
      4) maintenance_restart; pause_after_screen "Press Enter to return to Maintenance..." ;;
      5) run_repair; pause_after_screen "Press Enter to return to Maintenance..." ;;
      6) show_erpnext_service_logs; pause_after_screen "Press Enter to return to Maintenance..." ;;
      7) return 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

run_backup_maintenance_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "Backup / Restore / Maintenance"
    echo "============================================================"
    echo "1) Create database backup"
    echo "2) Create database + files backup"
    echo "3) List backups"
    echo "4) Restore database backup"
    echo "5) Restore database + files backup"
    echo "6) Maintenance tasks"
    echo "7) Back"
    echo
    read -r -p "Choose an option: " backup_choice

    case "$backup_choice" in
      1) create_site_backup false; pause_after_screen "Press Enter to return to Backup / Maintenance..." ;;
      2) create_site_backup true; pause_after_screen "Press Enter to return to Backup / Maintenance..." ;;
      3) list_site_backups; pause_after_screen "Press Enter to return to Backup / Maintenance..." ;;
      4) restore_site_database; pause_after_screen "Press Enter to return to Backup / Maintenance..." ;;
      5) restore_site_full; pause_after_screen "Press Enter to return to Backup / Maintenance..." ;;
      6) run_maintenance_menu ;;
      7) return 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

run_repair() {
  require_sudo
  check_os

  log "Running safe repair actions"

  $SUDO systemctl enable --now mariadb >/dev/null 2>&1 || warn "Could not start MariaDB"
  $SUDO systemctl enable --now redis-server >/dev/null 2>&1 || warn "Could not start Redis"
  configure_sysctl_for_redis
  create_frappe_user
  fix_frappe_ownership
  create_start_helper

  local bench_dir
  bench_dir="$(active_bench_dir)"

  if path_is_dir "$bench_dir" && path_is_dir "${bench_dir}/sites/${SITE_NAME}"; then
    log "Repairing Bench site configuration"
    run_as_frappe "cd '${bench_dir}' && bench use '${SITE_NAME}' || true"
    run_as_frappe "cd '${bench_dir}' && bench set-config -g default_site '${SITE_NAME}' || true"
    run_as_frappe "cd '${bench_dir}' && bench set-config -g serve_default_site true || true"

    if confirm "Run migrate/build/clear-cache now?"; then
      run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate"
      run_as_frappe "cd '${bench_dir}' && bench build"
      run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache"
    fi
  else
    warn "Bench/site not found. Repair cannot migrate/build yet. Use Install first."
  fi

  run_full_status
}

run_install() {
  require_sudo
  check_os
  check_internet
  maybe_offer_root_storage_expansion
  check_resources
  prompt_for_site_name_if_needed

  if path_is_dir "$BENCH_PARENT"; then
    warn "Existing environment detected at: $BENCH_PARENT"
    if confirm "Archive existing environment and perform clean install?"; then
      stop_bench_processes
      archive_existing_bench_parent
    else
      fail "Install cancelled."
    fi
  fi

  prepare_passwords
  install_system_packages
  configure_sysctl_for_redis
  create_frappe_user
  write_dev_config_file
  create_mariadb_admin_user
  fix_frappe_ownership
  install_frappe_stack_as_user
  write_credentials_file
  if ! create_erpnext_service; then
    warn "Install completed, but the ERPNext service could not be configured automatically."
    warn "You can still start manually with: sudo -iu ${FRAPPE_USER}; cd $(active_bench_dir); bench start"
  fi
  print_summary

  local enable_boot start_now

  if [[ "${ENABLE_AUTOSTART}" == "true" || "$ASSUME_YES" -eq 1 ]]; then
    if ! enable_autostart_service; then
      warn "Install completed, but autostart could not be enabled automatically."
    fi
  elif [[ "${ENABLE_AUTOSTART}" == "false" ]]; then
    warn "Autostart was not enabled because ENABLE_AUTOSTART=false."
  elif [[ -t 0 ]]; then
    echo
    read -r -p "Enable ERPNext autostart when this VM boots? [Y/n]: " enable_boot
    enable_boot="${enable_boot:-Y}"
    if [[ "$enable_boot" =~ ^[Yy]$ ]]; then
      if ! enable_autostart_service; then
        warn "Install completed, but autostart could not be enabled automatically."
      fi
    fi
  fi

  if [[ "${AUTO_START}" == "true" || "$ASSUME_YES" -eq 1 ]]; then
    if ! start_erpnext_service; then
      warn "Install completed, but ERPNext could not be started automatically."
      warn "Run this later: ./install-erpnext-dev.sh start"
    fi
  elif [[ "${AUTO_START}" == "false" ]]; then
    echo
    echo "You can start ERPNext later with:"
    echo "  ./install-erpnext-dev.sh start"
  elif [[ -t 0 ]]; then
    echo
    read -r -p "Start ERPNext now in the background service? [Y/n]: " start_now
    start_now="${start_now:-Y}"
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
      if ! start_erpnext_service; then
        warn "Install completed, but ERPNext could not be started automatically."
        warn "Run this later: ./install-erpnext-dev.sh start"
      fi
    else
      echo
      echo "You can start ERPNext later with:"
      echo "  ./install-erpnext-dev.sh start"
    fi
  fi
  post_install_validation_summary
}

soft_uninstall() {
  require_sudo
  stop_bench_processes
  archive_existing_bench_parent
  ok "Soft uninstall completed. System packages and Linux user were kept."
}

remove_bench_files() {
  require_sudo
  stop_bench_processes

  if path_is_dir "$BENCH_PARENT"; then
    if confirm "Delete ${BENCH_PARENT}?"; then
      $SUDO rm -rf "$BENCH_PARENT"
      ok "Removed ${BENCH_PARENT}"
    fi
  else
    warn "No bench parent folder found at ${BENCH_PARENT}"
  fi
}

full_purge() {
  require_sudo

  warn "Full purge removes the bench, frappe user home, MariaDB/Redis packages, and generated credentials."
  read -r -p "Type DELETE to continue: " reply
  [[ "$reply" == "DELETE" ]] || fail "Full purge cancelled."

  stop_bench_processes

  if service_exists; then
    $SUDO systemctl disable "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
    $SUDO rm -f "$(erpnext_service_path)"
    $SUDO systemctl daemon-reload
  fi

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    $SUDO deluser --remove-home "$FRAPPE_USER" || true
  fi

  $SUDO mariadb <<SQL || true
DROP USER IF EXISTS '${DB_ADMIN_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

  $SUDO apt-get remove --purge -y mariadb-server mariadb-client redis-server redis-tools || true
  $SUDO apt-get autoremove --purge -y || true

  ok "Full purge completed"
}

run_uninstall_menu() {
  require_sudo

  echo
  echo "Uninstall Options"
  echo "1) Soft uninstall: stop Bench and archive ${BENCH_PARENT}"
  echo "2) Remove bench files only"
  echo "3) Full purge: remove bench, frappe user, MariaDB/Redis packages"
  echo "4) Back"
  echo
  read -r -p "Choose an option: " choice

  case "$choice" in
    1) soft_uninstall ;;
    2) remove_bench_files ;;
    3) full_purge ;;
    4) return 0 ;;
    *) warn "Invalid option" ;;
  esac
}

run_start() {
  require_sudo
  start_erpnext_service
}

run_stop() {
  require_sudo
  stop_erpnext_service
}

run_foreground_start() {
  require_sudo

  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    warn "ERPNext service is already running in the background."
    if ! confirm "Start a foreground bench session anyway?"; then
      return 0
    fi
  fi

  start_erpnext_foreground
}

show_service_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "Autostart / Service Manager"
    echo "============================================================"
    echo "1) Enable autostart on VM boot"
    echo "2) Disable autostart"
    echo "3) Start ERPNext service"
    echo "4) Stop ERPNext service"
    echo "5) Restart ERPNext service"
    echo "6) Show service status"
    echo "7) Show recent service logs"
    echo "8) Follow service logs"
    echo "9) Back"
    echo
    read -r -p "Choose an option: " service_choice

    case "$service_choice" in
      1) enable_autostart_service ;;
      2) disable_autostart_service ;;
      3) start_erpnext_service ;;
      4) stop_erpnext_service ;;
      5) restart_erpnext_service ;;
      6) show_erpnext_service_status ;;
      7) show_erpnext_service_logs ;;
      8) follow_erpnext_service_logs ;;
      9) return 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_advanced_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "Advanced Options"
    echo "============================================================"
    echo "1) Install / Reinstall"
    echo "2) Repair Environment"
    echo "3) Uninstall / Reset"
    echo "4) Autostart / Service Manager"
    echo "5) Backup / Maintenance"
    echo "6) App Library"
    echo "7) Optional App Status"
    echo "8) Full Health Report"
    echo "9) VM Network Status"
    echo "10) Environment / location check"
    echo "11) KVM Fixed IP Guide"
    echo "12) Multi-Environment Guide"
    echo "13) SSL/HTTPS Roadmap"
    echo "14) Local SSL Status"
    echo "15) Local SSL Guide"
    echo "16) Trusted mkcert SSL Guide"
    echo "17) Browser Trust Check Guide"
    echo "18) Install/Replace Local SSL Cert"
    echo "19) Verify Local SSL"
    echo "20) Create Self-Signed Local Cert"
    echo "21) Configure Local SSL"
    echo "22) Disable Local SSL"
    echo "23) Verify SSL Rollback"
    echo "24) Storage Status"
    echo "25) Expand Root Storage"
    echo "26) Verify Storage"
    echo "27) Domain Config"
    echo "28) Production Readiness Preview"
    echo "29) Production Domain Guide"
    echo "30) Production SSL Guide"
    echo "31) Start Bench in Foreground"
    echo "32) Show Service Logs"
    echo "33) Access Submenu"
    echo "34) Back"
    echo
    read -r -p "Choose an option: " advanced_choice

    case "$advanced_choice" in
      1) run_install ;;
      2) run_repair ;;
      3) run_uninstall_menu ;;
      4) show_service_menu ;;
      5) run_backup_maintenance_menu ;;
      6) show_app_library_menu ;;
      7) run_app_status ;;
      8) run_full_status ;;
      9) show_network_status ;;
      10) show_environment_check ;;
      11) show_kvm_fixed_ip_guide ;;
      12) show_multi_environment_guide ;;
      13) show_ssl_roadmap_guide ;;
      14) show_ssl_status ;;
      15) show_local_ssl_guide ;;
      16) show_mkcert_local_ssl_guide ;;
      17) show_browser_trust_check_guide ;;
      18) install_local_ssl_cert ;;
      19) verify_local_ssl ;;
      20) create_self_signed_local_cert ;;
      21) configure_local_ssl ;;
      22) disable_local_ssl ;;
      23) verify_ssl_rollback ;;
      24) show_storage_status ;;
      25) expand_root_storage ;;
      26) verify_storage ;;
      27) show_domain_config ;;
      28) show_production_readiness ;;
      29) show_production_domain_guide ;;
      30) show_production_ssl_guide ;;
      31) run_foreground_start ;;
      32) show_erpnext_service_logs ;;
      33) show_access_menu ;;
      34) return 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_help() {
  cat <<EOF_HELP
${APP_NAME} v${SCRIPT_VERSION}

Recommended local developer workflow:
  ./install-erpnext-dev.sh setup
  ./install-erpnext-dev.sh start
  ./install-erpnext-dev.sh access

Usage:
  ./install-erpnext-dev.sh [action] [options]

Basic actions:
  setup         Recommended setup: install, create service, offer autostart/start
  install       Alias for setup
  start         Start ERPNext in the background systemd service
  stop          Stop ERPNext service and development processes
  status        Show quick developer status and exit
  status-menu   Show interactive Status submenu
  runtime-status       Show runtime/port status
  install-status       Show installation/site status
  service-summary      Show service/autostart summary
  access        Show browser/IP/hostname instructions and exit
  network-status Show VM IP/MAC/interface and access diagnostics
  hosts-command Show HOST /etc/hosts command only
  ssl-status    Show local HTTPS reverse proxy status
  local-ssl-guide Show local SSL overview and quick test guide
  mkcert-guide  Show trusted browser SSL workflow with mkcert
  browser-trust-guide Show host browser/curl trust check workflow
  verify-local-ssl Verify local SSL status and show host tests
  install-local-ssl-cert Install/replace local SSL cert/key inside the VM
  create-self-signed-local-cert Create quick self-signed cert for local SSL testing
  environment-check Show whether this is the host or ERPNext VM context
  site-config   Show current local site/domain configuration
  domain-config Show local site and future production domain config
  site-name-guide Show how to choose custom .test names for multiple VMs
  backup        Create database backup
  backup-files  Create database + files backup
  list-backups  List site backups
  app-library   Show optional Frappe app library
  apps          Alias for app-library
  list-apps     Show installed and downloaded Frappe apps
  app-status    Show optional Frappe app install status
  maintenance   Show maintenance menu
  menu          Show interactive menu
  help          Show this help

Advanced actions:
  repair              Run safe environment repair
  backup-menu         Show backup/restore/maintenance menu
  install-crm         Install Frappe CRM
  install-hrms        Install Frappe HR / HRMS
  install-helpdesk    Install Frappe Helpdesk
  install-telephony   Install Frappe Telephony dependency app
  install-insights    Install Frappe Insights
  install-custom-app  Install a custom trusted Frappe app interactively
  repair-app-registry Repair/normalize Bench sites/apps.txt
  restore-db          Restore a database backup interactively
  restore-full        Restore database + files interactively
  migrate             Run site migration
  build               Build assets
  clear-cache         Clear site cache
  restart             Restart ERPNext service and wait until ready
  wait-ready          Wait until ERPNext development ports are ready
  doctor              Show full health report
  full-status         Show full health report
  uninstall           Show uninstall/reset menu
  advanced            Show advanced options menu
  access-menu         Show access/networking submenu
  foreground-start    Start Bench in the foreground terminal
  enable-autostart    Enable ERPNext service on VM boot
  disable-autostart   Disable ERPNext service on VM boot
  service-start       Start ERPNext service
  service-stop        Stop ERPNext service
  service-restart     Restart ERPNext service
  service-status      Show systemd service status
  logs                Show recent ERPNext service logs
  logs-follow         Follow ERPNext service logs
  kvm-guide           Show KVM/libvirt fixed IP guide
  kvm-identify        Show KVM VM identification helper using the VM MAC
  host-test           Show host-side access test commands
  ssl-roadmap         Show future SSL/HTTPS implementation roadmap
  mkcert-guide        Show trusted local SSL workflow with mkcert
  browser-trust-guide Show browser/curl trust validation checklist
  ssl-rollback-guide  Show local SSL rollback/disable guide
  verify-ssl-rollback Verify SSL disable/rollback state
  verify-local-ssl    Verify local SSL status and show host tests
  install-local-ssl-cert Install/replace local SSL cert/key inside the VM
  create-self-signed-local-cert Create quick local SSL test certificate
  environment-check   Show host vs ERPNext VM command context
  site-config         Show current local site/domain configuration
  domain-config       Show local/future production domain configuration
  repair-site-config  Repair saved site/domain config from detected Bench site
  storage-status      Show root disk/filesystem expansion status
  storage-debug       Show storage detection diagnostics
  expand-root-storage Safely expand root filesystem when VM disk is larger
  verify-storage      Verify root storage is suitable for ERPNext
  site-name-guide     Show custom .test hostname guide
  production-readiness Show production readiness preview
  production-domain-guide Show production domain planning guide
  production-ssl-guide Show production SSL planning guide
  configure-local-ssl Configure Nginx local HTTPS reverse proxy
  disable-local-ssl   Disable local HTTPS reverse proxy site
  multi-env-guide     Show multiple local environment guide

Options:
  -y, --yes     Assume yes for install confirmations

Environment overrides:
  SITE_NAME=erp.test               # default local site name; use SITE_NAME=erp107.test for another VM
  PRODUCTION_DOMAIN=erp.company.com # future production planning only
  FRAPPE_USER=frappe
  ADMIN_PASSWORD='YourPassword'
  DB_ADMIN_PASSWORD='YourDbAdminPassword'
  FRAPPE_BRANCH=version-16
  ERPNEXT_BRANCH=version-16
  CRM_BRANCH=main
  HRMS_BRANCH=version-16
  HELPDESK_BRANCH=main
  TELEPHONY_BRANCH=develop
  INSIGHTS_BRANCH=main
  AUTO_START=true|false|prompt
  ENABLE_AUTOSTART=true|false|prompt
  AUTO_EXPAND_ROOT=true|false|prompt

Browser access:
  Direct IP URL works while ERPNext is running: http://VM_IP:8000
  Friendly URL works after HOST /etc/hosts setup: http://${SITE_NAME}:8000

Examples:
  ./install-erpnext-dev.sh
  ./install-erpnext-dev.sh setup
  ./install-erpnext-dev.sh status
  ./install-erpnext-dev.sh start
  ./install-erpnext-dev.sh access
  ./install-erpnext-dev.sh backup
  ./install-erpnext-dev.sh app-library
  ./install-erpnext-dev.sh install-crm
  ./install-erpnext-dev.sh app-status
  ./install-erpnext-dev.sh network-status
  ./install-erpnext-dev.sh ssl-status
  ./install-erpnext-dev.sh local-ssl-guide
  ./install-erpnext-dev.sh mkcert-guide
  ./install-erpnext-dev.sh browser-trust-guide
  ./install-erpnext-dev.sh verify-local-ssl
  ./install-erpnext-dev.sh environment-check
  ./install-erpnext-dev.sh site-config
  ./install-erpnext-dev.sh storage-status
  ./install-erpnext-dev.sh domain-config
  ./install-erpnext-dev.sh production-readiness
  ./install-erpnext-dev.sh doctor
EOF_HELP
}

show_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "${APP_NAME} v${SCRIPT_VERSION}"
    echo "============================================================"
    echo "1) Recommended Setup"
    echo "2) Start ERPNext"
    echo "3) Stop ERPNext"
    echo "4) Status"
    echo "5) Access Instructions"
    echo "6) Backup / Maintenance"
    echo "7) App Library"
    echo "8) Advanced Options"
    echo "9) Help"
    echo "10) Exit"
    echo
    read -r -p "Choose an option: " choice

    case "$choice" in
      1) run_install ;;
      2) run_start ;;
      3) run_stop ;;
      4) show_status_menu ;;
      5) show_access_instructions ;;
      6) run_backup_maintenance_menu ;;
      7) show_app_library_menu ;;
      8) show_advanced_menu ;;
      9) show_help ;;
      10) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      setup|install|repair|status|status-menu|runtime-status|install-status|service-summary|doctor|full-status|start|stop|uninstall|advanced|access|access-menu|backup-menu|backup|backup-files|list-backups|backups|restore-db|restore-full|maintenance|migrate|build|clear-cache|restart|wait-ready|menu|help|-h|--help|foreground-start|enable-autostart|disable-autostart|service-start|service-stop|service-restart|service-status|logs|logs-follow|kvm-guide|kvm-identify|network-status|hosts-command|host-test|ssl-roadmap|ssl-status|local-ssl-guide|mkcert-guide|trusted-local-ssl-guide|browser-trust-guide|trust-check-guide|ssl-rollback-guide|verify-ssl-rollback|verify-local-ssl|install-local-ssl-cert|replace-local-ssl-cert|create-self-signed-local-cert|self-signed-local-cert|configure-local-ssl|disable-local-ssl|environment-check|where-am-i|site-config|domain-config|storage-status|storage-debug|expand-root-storage|verify-storage|production-readiness|production-domain-guide|production-ssl-guide|repair-site-config|site-name-guide|custom-site-guide|multi-env-guide|app-library|apps|list-apps|app-status|install-crm|install-hrms|install-helpdesk|install-telephony|install-insights|install-custom-app|repair-app-registry)
        ACTION="$1"
        shift
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if action_requires_lock "${ACTION:-menu}"; then
    acquire_installer_lock
  fi

  case "${ACTION:-menu}" in
    ""|menu) show_menu ;;
    setup|install) run_install ;;
    repair) run_repair ;;
    status) run_status ;;
    status-menu) show_status_menu ;;
    runtime-status) run_runtime_status ;;
    install-status) run_installation_status ;;
    service-summary) run_service_summary ;;
    doctor|full-status) run_full_status ;;
    start) run_start ;;
    stop) run_stop ;;
    uninstall) run_uninstall_menu ;;
    advanced) show_advanced_menu ;;
    access) show_access_instructions ;;
    access-menu) show_access_menu ;;
    backup-menu) run_backup_maintenance_menu ;;
    app-library|apps) show_app_library_menu ;;
    list-apps) show_installed_apps ;;
    app-status) run_app_status ;;
    install-crm) install_app_profile crm ;;
    install-hrms) install_app_profile hrms ;;
    install-helpdesk) install_app_profile helpdesk ;;
    install-telephony) install_app_profile telephony ;;
    install-insights) install_app_profile insights ;;
    install-custom-app) install_custom_app_interactive ;;
    repair-app-registry) repair_app_registry ;;
    backup) create_site_backup false ;;
    backup-files) create_site_backup true ;;
    list-backups|backups) list_site_backups ;;
    restore-db) restore_site_database ;;
    restore-full) restore_site_full ;;
    maintenance) run_maintenance_menu ;;
    migrate) maintenance_migrate ;;
    build) maintenance_build ;;
    clear-cache) maintenance_clear_cache ;;
    restart) maintenance_restart ;;
    wait-ready) wait_for_erpnext_ready ;;
    foreground-start) run_foreground_start ;;
    enable-autostart) enable_autostart_service ;;
    disable-autostart) disable_autostart_service ;;
    service-start) start_erpnext_service ;;
    service-stop) stop_erpnext_service ;;
    service-restart) restart_erpnext_service ;;
    service-status) show_erpnext_service_status ;;
    logs) show_erpnext_service_logs ;;
    logs-follow) follow_erpnext_service_logs ;;
    kvm-guide) show_kvm_fixed_ip_guide ;;
    kvm-identify) show_kvm_vm_identification_guide ;;
    network-status) show_network_status ;;
    hosts-command) show_host_hosts_command ;;
    host-test) show_host_access_test_guide ;;
    ssl-roadmap) show_ssl_roadmap_guide ;;
    ssl-status) show_ssl_status ;;
    local-ssl-guide) show_local_ssl_guide ;;
    mkcert-guide|trusted-local-ssl-guide) show_mkcert_local_ssl_guide ;;
    browser-trust-guide|trust-check-guide) show_browser_trust_check_guide ;;
    ssl-rollback-guide) show_ssl_rollback_guide ;;
    verify-ssl-rollback) verify_ssl_rollback ;;
    verify-local-ssl) verify_local_ssl ;;
    install-local-ssl-cert|replace-local-ssl-cert) install_local_ssl_cert ;;
    create-self-signed-local-cert|self-signed-local-cert) create_self_signed_local_cert ;;
    configure-local-ssl) configure_local_ssl ;;
    disable-local-ssl) disable_local_ssl ;;
    environment-check|where-am-i) show_environment_check ;;
    site-config) show_site_config ;;
    storage-status) show_storage_status ;;
    storage-debug) storage_debug ;;
    expand-root-storage) expand_root_storage ;;
    verify-storage) verify_storage ;;
    domain-config) show_domain_config ;;
    production-readiness) show_production_readiness ;;
    production-domain-guide) show_production_domain_guide ;;
    production-ssl-guide) show_production_ssl_guide ;;
    repair-site-config) repair_site_config ;;
    site-name-guide|custom-site-guide) show_site_name_guide ;;
    multi-env-guide) show_multi_environment_guide ;;
    help|-h|--help) show_help ;;
    *) fail "Unknown action: ${ACTION}" ;;
  esac
}

main "$@"
