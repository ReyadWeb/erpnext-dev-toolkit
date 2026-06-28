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
SCRIPT_VERSION="0.8.0"

FRAPPE_USER="${FRAPPE_USER:-frappe}"
FRAPPE_HOME="/home/${FRAPPE_USER}"
BENCH_PARENT="${BENCH_PARENT:-${FRAPPE_HOME}/frappe}"
BENCH_NAME="${BENCH_NAME:-frappe-bench}"
BENCH_DIR="${BENCH_PARENT}/${BENCH_NAME}"
SITE_NAME="${SITE_NAME:-erp.test}"
AUTO_START="${AUTO_START:-prompt}"
ENABLE_AUTOSTART="${ENABLE_AUTOSTART:-prompt}"
ERPNEXT_SERVICE_NAME="${ERPNEXT_SERVICE_NAME:-erpnext-dev.service}"
READY_TIMEOUT="${READY_TIMEOUT:-90}"
READY_INTERVAL="${READY_INTERVAL:-5}"

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
LOG_FILE="/tmp/erpnext-dev-installer-$(date +%Y%m%d-%H%M%S).log"

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

exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo -e "\n${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
ok() { echo -e "${GREEN}OK:${RESET} $*"; }
warn() { echo -e "${YELLOW}WARN:${RESET} $*"; }
err() { echo -e "${RED}ERROR:${RESET} $*" >&2; }
fail() { err "$*"; echo "Log file: $LOG_FILE" >&2; exit 1; }


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

Important:
  The certificate must be trusted by the HOST browser machine, not only by
  the ERPNext VM. For local development, mkcert is usually the best workflow.

Expected certificate paths inside the VM:
  Certificate: ${cert_path}
  Private key: ${key_path}

Recommended mkcert workflow on your Linux Mint/Ubuntu HOST:

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

Then configure the local HTTPS reverse proxy:

  ./install-erpnext-dev.sh configure-local-ssl
  ./install-erpnext-dev.sh ssl-status

Host /etc/hosts still needs to map ${SITE_NAME} to this VM IP:

  sudo sed -i '/[[:space:]]${escaped_site}\$/d' /etc/hosts
  echo "${vm_ip} ${SITE_NAME}" | sudo tee -a /etc/hosts

Test from the host:

  curl -kI https://${SITE_NAME}

Browser URL:

  https://${SITE_NAME}

Direct Bench access remains available:

  http://${SITE_NAME}:8000
  http://${vm_ip}:8000

============================================================
EOF_LOCAL_SSL
}

show_ssl_status() {
  local cert_path key_path available_path enabled_path vm_ip nginx_state ssl_ready
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  available_path="$(ssl_nginx_available_path)"
  enabled_path="$(ssl_nginx_enabled_path)"
  vm_ip="$(get_vm_ip)"

  if command -v nginx >/dev/null 2>&1; then
    nginx_state="installed"
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

  if [[ -f "$cert_path" ]]; then
    status_line "SSL certificate" "OK" "$cert_path"
  else
    status_line "SSL certificate" "WARN" "missing at $cert_path"
  fi

  if [[ -f "$key_path" ]]; then
    status_line "SSL private key" "OK" "$key_path"
  else
    status_line "SSL private key" "WARN" "missing at $key_path"
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
  echo "URLs:"
  echo "  Direct Bench:     http://${vm_ip}:8000"
  echo "  Friendly Bench:   http://${SITE_NAME}:8000"
  echo "  Local HTTPS:      https://${SITE_NAME}"
  echo

  ssl_ready=0
  if [[ -f "$available_path" && ( -L "$enabled_path" || -f "$enabled_path" ) && -f "$cert_path" && -f "$key_path" ]] && port_listens 443; then
    ssl_ready=1
  fi

  if [[ "$ssl_ready" -eq 1 ]]; then
    ok "Local HTTPS appears configured. Test from the host: curl -kI https://${SITE_NAME}"
  else
    warn "Local HTTPS is not fully configured yet. Run: ./install-erpnext-dev.sh local-ssl-guide"
  fi

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

  SITE_NAME=erp1.test ./install-erpnext-dev.sh install
  SITE_NAME=school.test ./install-erpnext-dev.sh install
  SITE_NAME=client-a.test ./install-erpnext-dev.sh install

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
    echo "11) Configure local SSL reverse proxy"
    echo "12) Disable local SSL reverse proxy"
    echo "13) Back"
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
      11) configure_local_ssl ;;
      12) disable_local_ssl ;;
      13) return 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
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
  echo "  Password: ${ADMIN_PASSWORD}"
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
  check_resources

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
    echo "10) KVM Fixed IP Guide"
    echo "11) Multi-Environment Guide"
    echo "12) SSL/HTTPS Roadmap"
    echo "13) Local SSL Status"
    echo "14) Local SSL Guide"
    echo "15) Configure Local SSL"
    echo "16) Disable Local SSL"
    echo "17) Start Bench in Foreground"
    echo "18) Show Service Logs"
    echo "19) Access Submenu"
    echo "20) Back"
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
      10) show_kvm_fixed_ip_guide ;;
      11) show_multi_environment_guide ;;
      12) show_ssl_roadmap_guide ;;
      13) show_ssl_status ;;
      14) show_local_ssl_guide ;;
      15) configure_local_ssl ;;
      16) disable_local_ssl ;;
      17) run_foreground_start ;;
      18) show_erpnext_service_logs ;;
      19) show_access_menu ;;
      20) return 0 ;;
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
  local-ssl-guide Show local mkcert/certificate setup guide
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
  configure-local-ssl Configure Nginx local HTTPS reverse proxy
  disable-local-ssl   Disable local HTTPS reverse proxy site
  multi-env-guide     Show multiple local environment guide

Options:
  -y, --yes     Assume yes for install confirmations

Environment overrides:
  SITE_NAME=erp.test
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
      setup|install|repair|status|status-menu|runtime-status|install-status|service-summary|doctor|full-status|start|stop|uninstall|advanced|access|access-menu|backup-menu|backup|backup-files|list-backups|backups|restore-db|restore-full|maintenance|migrate|build|clear-cache|restart|wait-ready|menu|help|-h|--help|foreground-start|enable-autostart|disable-autostart|service-start|service-stop|service-restart|service-status|logs|logs-follow|kvm-guide|kvm-identify|network-status|hosts-command|host-test|ssl-roadmap|ssl-status|local-ssl-guide|configure-local-ssl|disable-local-ssl|multi-env-guide|app-library|apps|list-apps|app-status|install-crm|install-hrms|install-helpdesk|install-telephony|install-insights|install-custom-app|repair-app-registry)
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
    configure-local-ssl) configure_local_ssl ;;
    disable-local-ssl) disable_local_ssl ;;
    multi-env-guide) show_multi_environment_guide ;;
    help|-h|--help) show_help ;;
    *) fail "Unknown action: ${ACTION}" ;;
  esac
}

main "$@"
