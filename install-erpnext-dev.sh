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
SCRIPT_VERSION="0.3.1"

FRAPPE_USER="${FRAPPE_USER:-frappe}"
FRAPPE_HOME="/home/${FRAPPE_USER}"
BENCH_PARENT="${BENCH_PARENT:-${FRAPPE_HOME}/frappe}"
BENCH_NAME="${BENCH_NAME:-frappe-bench}"
BENCH_DIR="${BENCH_PARENT}/${BENCH_NAME}"
SITE_NAME="${SITE_NAME:-erp.test}"
AUTO_START="${AUTO_START:-prompt}"
ENABLE_AUTOSTART="${ENABLE_AUTOSTART:-prompt}"
ERPNEXT_SERVICE_NAME="${ERPNEXT_SERVICE_NAME:-erpnext-dev.service}"

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

  if [[ ! -d "${BENCH_DIR}" ]]; then
    fail "Bench folder not found: ${BENCH_DIR}. Run install first."
  fi

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
    cd \"${BENCH_DIR}\"
    bench start
  "
}


erpnext_service_path() {
  echo "/etc/systemd/system/${ERPNEXT_SERVICE_NAME}"
}

service_exists() {
  [[ -f "$(erpnext_service_path)" ]]
}

create_erpnext_service() {
  require_sudo

  if [[ ! -d "${BENCH_DIR}" ]]; then
    fail "Bench folder not found: ${BENCH_DIR}. Run Recommended Setup first."
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
WorkingDirectory=${BENCH_DIR}
Environment=HOME=${FRAPPE_HOME}
ExecStart=/bin/bash -lc 'export NVM_DIR="\$HOME/.nvm"; [ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"; export PATH="\$HOME/.local/bin:\$PATH"; cd "${BENCH_DIR}" && bench start'
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
    create_erpnext_service
  fi

  log "Enabling ERPNext autostart on VM boot"
  $SUDO systemctl enable "${ERPNEXT_SERVICE_NAME}"
  ok "Autostart enabled"
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
    create_erpnext_service
  fi

  log "Starting ERPNext service"
  $SUDO systemctl start "${ERPNEXT_SERVICE_NAME}"
  ok "ERPNext service started"
  show_access_instructions
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
    create_erpnext_service
  fi

  log "Restarting ERPNext service"
  $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}"
  ok "ERPNext service restarted"
  show_access_instructions
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

require_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO=""
  else
    sudo -v || fail "This command requires sudo access."
    SUDO="sudo"
  fi
}

run_as_frappe() {
  local cmd="$1"

  if ! id "$FRAPPE_USER" >/dev/null 2>&1; then
    return 1
  fi

  if [[ "${EUID}" -eq 0 ]]; then
    su - "$FRAPPE_USER" -s /bin/bash -c "export PATH=\"\$HOME/.local/bin:\$PATH\"; ${cmd}"
  else
    sudo -iu "$FRAPPE_USER" bash -lc "export PATH=\"\$HOME/.local/bin:\$PATH\"; ${cmd}"
  fi
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
  if [[ -d "$BENCH_PARENT" ]]; then
    local archive_path
    archive_path="${BENCH_PARENT}-backup-$(date +%Y%m%d-%H%M%S)"

    log "Archiving existing ERPNext environment"
    $SUDO mv "$BENCH_PARENT" "$archive_path"
    ok "Existing environment archived to: $archive_path"
  fi
}

fix_frappe_ownership() {
  if id "$FRAPPE_USER" >/dev/null 2>&1 && [[ -d "$FRAPPE_HOME" ]]; then
    log "Fixing ${FRAPPE_HOME} ownership"
    $SUDO chown -R "$FRAPPE_USER:$FRAPPE_USER" "$FRAPPE_HOME"
    ok "Ownership fixed"
  fi
}

create_start_helper() {
  if ! id "$FRAPPE_USER" >/dev/null 2>&1; then
    return 0
  fi

  log "Creating start helper script"

  $SUDO tee "$FRAPPE_HOME/start-erpnext-dev.sh" >/dev/null <<EOF_HELPER
#!/usr/bin/env bash
set -e
export PATH="\$HOME/.local/bin:\$PATH"
cd "${BENCH_DIR}"
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

  $SUDO tee "$cred_file" >/dev/null <<EOF_CREDS
ERPNext Developer Environment

Site:
  ${SITE_NAME}

Bench:
  ${BENCH_DIR}

Login:
  Username: Administrator
  Password: ${ADMIN_PASSWORD}

MariaDB Bench Admin:
  User: ${DB_ADMIN_USER}
  Password: ${DB_ADMIN_PASSWORD}

Start ERPNext:
  sudo -iu ${FRAPPE_USER}
  export PATH="\$HOME/.local/bin:\$PATH"
  cd ${BENCH_DIR}
  bench start

One-line start command:
  sudo -iu ${FRAPPE_USER} bash -lc 'export PATH="\$HOME/.local/bin:\$PATH"; cd ${BENCH_DIR} && bench start'

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
  local vm_ip escaped_site
  vm_ip="$(get_vm_ip)"
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
  echo "  cd ${BENCH_DIR}"
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
    echo "3) Show KVM/libvirt fixed IP guide"
    echo "4) Show multi-environment naming guide"
    echo "5) Back"
    echo
    read -r -p "Choose an option: " access_choice

    case "$access_choice" in
      1) show_access_instructions ;;
      2) show_host_hosts_command ;;
      3) show_kvm_fixed_ip_guide ;;
      4) show_multi_environment_guide ;;
      5) return 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

print_summary() {
  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "ERPNext Developer Environment Installed"
  echo "============================================================"
  echo
  echo "Site: ${SITE_NAME}"
  echo "Bench: ${BENCH_DIR}"
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
  echo "  cd ${BENCH_DIR}"
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
    if [[ -d "$candidate/apps/frappe" && -d "$candidate/sites" ]]; then
      echo "$candidate"
      return 0
    fi
    if [[ -z "$found" && -d "$candidate" ]]; then
      found="$candidate"
    fi
  done < <(bench_dir_candidates | awk '!seen[$0]++')

  if [[ -d "$FRAPPE_HOME" ]]; then
    candidate="$(find "$FRAPPE_HOME" -maxdepth 3 -type d -name "$BENCH_NAME" 2>/dev/null | head -n 1 || true)"
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

  [[ -d "${bench_dir}/apps/${app}" ]]
}

site_exists() {
  local bench_dir
  bench_dir="$(active_bench_dir)"

  [[ -d "${bench_dir}/sites/${SITE_NAME}" ]]
}

site_app_installed() {
  local app="$1"
  local bench_dir
  bench_dir="$(active_bench_dir)"

  if [[ ! -d "$bench_dir" || ! -d "${bench_dir}/sites/${SITE_NAME}" ]]; then
    return 1
  fi

  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' list-apps" 2>/dev/null | awk '{print $1}' | grep -qx "$app"
}

install_state() {
  local bench_dir
  bench_dir="$(active_bench_dir)"

  if [[ -d "${bench_dir}" && -d "${bench_dir}/apps/frappe" && -d "${bench_dir}/apps/erpnext" && -d "${bench_dir}/sites/${SITE_NAME}" ]]; then
    if site_app_installed erpnext || [[ -f "${bench_dir}/sites/apps.txt" ]]; then
      echo "Installed"
    else
      echo "Installed files found; site app not confirmed"
    fi
  elif [[ -d "${bench_dir}" || -d "${FRAPPE_HOME}" ]]; then
    echo "Incomplete"
  else
    echo "Not installed"
  fi
}

runtime_state() {
  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    echo "Running via service"
  elif nc -z 127.0.0.1 8000 >/dev/null 2>&1; then
    echo "Running"
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

  local vm_ip installed runtime auto svc bench_dir creds_state helper_state
  vm_ip="$(get_vm_ip)"
  installed="$(install_state)"
  runtime="$(runtime_state)"
  auto="$(autostart_state)"
  svc="$(service_state)"
  bench_dir="$(active_bench_dir)"

  if [[ -f "${FRAPPE_HOME}/erpnext-dev-credentials.txt" ]]; then
    creds_state="Available"
  else
    creds_state="Missing"
  fi

  if [[ -x "${FRAPPE_HOME}/start-erpnext-dev.sh" ]]; then
    helper_state="Available"
  else
    helper_state="Missing"
  fi

  echo
  echo "============================================================"
  echo "ERPNext Developer Quick Status"
  echo "============================================================"
  printf "  %-24s %s\n" "Install status:" "$installed"
  printf "  %-24s %s\n" "Runtime status:" "$runtime"
  printf "  %-24s %s\n" "Autostart:" "$auto"
  printf "  %-24s %s\n" "Service:" "$svc"
  printf "  %-24s %s\n" "Site:" "$SITE_NAME"
  printf "  %-24s %s\n" "Bench folder:" "$bench_dir"
  printf "  %-24s %s\n" "Credentials:" "$creds_state"
  printf "  %-24s %s\n" "Start helper:" "$helper_state"
  printf "  %-24s %s\n" "VM IP:" "$vm_ip"
  printf "  %-24s http://%s:8000\n" "Direct URL:" "$vm_ip"
  printf "  %-24s http://%s:8000\n" "Friendly URL:" "$SITE_NAME"
  echo
  echo "Recommended action:"
  echo "  $(recommended_action "$installed" "$runtime" "$auto")"
  echo
  echo "Friendly URL note: http://${SITE_NAME}:8000 only works after ERPNext is running and your HOST /etc/hosts maps ${SITE_NAME} to ${vm_ip}."
  echo "For detailed diagnostics, run: ./install-erpnext-dev.sh doctor"
  echo "============================================================"
}

run_runtime_status() {
  require_sudo

  echo
  echo "============================================================"
  echo "ERPNext Runtime Status"
  echo "============================================================"
  status_line "Runtime" "INFO" "$(runtime_state)"
  status_line "Service" "INFO" "$(service_state)"
  status_line "Autostart" "INFO" "$(autostart_state)"

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
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      status_line "$label" "OK" "port ${port} listening"
    else
      status_line "$label" "INFO" "port ${port} not listening"
    fi
  done

  echo
  echo "If installed but stopped, run: ./install-erpnext-dev.sh start"
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
  status_line "Install status" "INFO" "$(install_state)"

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    status_line "frappe user" "OK" "$FRAPPE_USER exists"
  else
    status_line "frappe user" "FAIL" "$FRAPPE_USER missing"
  fi

  if [[ -d "$bench_dir" ]]; then
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
  status_line "Service file" "INFO" "$(erpnext_service_path)"
  status_line "Service" "INFO" "$(service_state)"
  status_line "Autostart" "INFO" "$(autostart_state)"
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
    echo "1) Quick Status"
    echo "2) Runtime Status"
    echo "3) Installation Status"
    echo "4) Service / Autostart Status"
    echo "5) Full Health Report"
    echo "6) Back"
    echo
    read -r -p "Choose an option: " status_choice

    case "$status_choice" in
      1) run_status ;;
      2) run_runtime_status ;;
      3) run_installation_status ;;
      4) run_service_summary ;;
      5) run_full_status ;;
      6) return 0 ;;
      *) warn "Invalid option" ;;
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

  if [[ -d "$bench_dir" ]]; then
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

  if [[ -d "${bench_dir}/sites/${SITE_NAME}" ]]; then
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

  if [[ -f "${bench_dir}/sites/common_site_config.json" ]]; then
    if grep -q '"default_site"[[:space:]]*:[[:space:]]*"'"${SITE_NAME}"'"' "${bench_dir}/sites/common_site_config.json"; then
      status_line "Default site" "OK" "${SITE_NAME}"
    else
      status_line "Default site" "WARN" "not set to ${SITE_NAME}"
    fi
  else
    status_line "Common config" "WARN" "common_site_config.json missing"
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
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      status_line "$label" "OK" "port ${port} listening"
    else
      status_line "$label" "INFO" "port ${port} not listening"
    fi
  done

  if [[ -x "${FRAPPE_HOME}/start-erpnext-dev.sh" ]]; then
    status_line "Start helper" "OK" "${FRAPPE_HOME}/start-erpnext-dev.sh"
  else
    status_line "Start helper" "WARN" "missing or not executable"
  fi

  if [[ -f "${FRAPPE_HOME}/erpnext-dev-credentials.txt" ]]; then
    status_line "Credentials file" "OK" "${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  else
    status_line "Credentials file" "WARN" "missing"
  fi

  status_line "VM IP" "INFO" "$(get_vm_ip)"
  status_line "Direct IP URL" "INFO" "http://$(get_vm_ip):8000"
  status_line "Friendly URL" "INFO" "http://${SITE_NAME}:8000"
  status_line "Host /etc/hosts" "INFO" "$(get_vm_ip) ${SITE_NAME}"

  echo
  echo "Log file: ${LOG_FILE}"
  echo "============================================================"
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

  if [[ -d "$BENCH_DIR" && -d "${BENCH_DIR}/sites/${SITE_NAME}" ]]; then
    log "Repairing Bench site configuration"
    run_as_frappe "cd '${BENCH_DIR}' && bench use '${SITE_NAME}' || true"
    run_as_frappe "cd '${BENCH_DIR}' && bench set-config -g default_site '${SITE_NAME}' || true"
    run_as_frappe "cd '${BENCH_DIR}' && bench set-config -g serve_default_site true || true"

    if confirm "Run migrate/build/clear-cache now?"; then
      run_as_frappe "cd '${BENCH_DIR}' && bench --site '${SITE_NAME}' migrate"
      run_as_frappe "cd '${BENCH_DIR}' && bench build"
      run_as_frappe "cd '${BENCH_DIR}' && bench --site '${SITE_NAME}' clear-cache"
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

  if [[ -d "$BENCH_PARENT" ]]; then
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
  create_erpnext_service
  print_summary
  show_access_instructions

  local enable_boot start_now

  if [[ "${ENABLE_AUTOSTART}" == "true" || "$ASSUME_YES" -eq 1 ]]; then
    enable_autostart_service
  elif [[ "${ENABLE_AUTOSTART}" == "false" ]]; then
    warn "Autostart was not enabled because ENABLE_AUTOSTART=false."
  elif [[ -t 0 ]]; then
    echo
    read -r -p "Enable ERPNext autostart when this VM boots? [Y/n]: " enable_boot
    enable_boot="${enable_boot:-Y}"
    if [[ "$enable_boot" =~ ^[Yy]$ ]]; then
      enable_autostart_service
    fi
  fi

  if [[ "${AUTO_START}" == "true" || "$ASSUME_YES" -eq 1 ]]; then
    start_erpnext_service
  elif [[ "${AUTO_START}" == "false" ]]; then
    echo
    echo "You can start ERPNext later with:"
    echo "  ./install-erpnext-dev.sh start"
  elif [[ -t 0 ]]; then
    echo
    read -r -p "Start ERPNext now in the background service? [Y/n]: " start_now
    start_now="${start_now:-Y}"
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
      start_erpnext_service
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

  if [[ -d "$BENCH_PARENT" ]]; then
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
    echo "5) Full Health Report"
    echo "6) KVM Fixed IP Guide"
    echo "7) Multi-Environment Guide"
    echo "8) Start Bench in Foreground"
    echo "9) Show Service Logs"
    echo "10) Access Submenu"
    echo "11) Back"
    echo
    read -r -p "Choose an option: " advanced_choice

    case "$advanced_choice" in
      1) run_install ;;
      2) run_repair ;;
      3) run_uninstall_menu ;;
      4) show_service_menu ;;
      5) run_full_status ;;
      6) show_kvm_fixed_ip_guide ;;
      7) show_multi_environment_guide ;;
      8) run_foreground_start ;;
      9) show_erpnext_service_logs ;;
      10) show_access_menu ;;
      11) return 0 ;;
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
  menu          Show interactive menu
  help          Show this help

Advanced actions:
  repair              Run safe environment repair
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
    echo "6) Advanced Options"
    echo "7) Help"
    echo "8) Exit"
    echo
    read -r -p "Choose an option: " choice

    case "$choice" in
      1) run_install ;;
      2) run_start ;;
      3) run_stop ;;
      4) show_status_menu ;;
      5) show_access_instructions ;;
      6) show_advanced_menu ;;
      7) show_help ;;
      8) exit 0 ;;
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
      setup|install|repair|status|status-menu|runtime-status|install-status|service-summary|doctor|full-status|start|stop|uninstall|advanced|access|access-menu|menu|help|-h|--help|foreground-start|enable-autostart|disable-autostart|service-start|service-stop|service-restart|service-status|logs|logs-follow|kvm-guide|multi-env-guide)
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
    multi-env-guide) show_multi_environment_guide ;;
    help|-h|--help) show_help ;;
    *) fail "Unknown action: ${ACTION}" ;;
  esac
}

main "$@"
