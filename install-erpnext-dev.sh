#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================
# ERPNext / Frappe Developer Installer
# Target: Ubuntu 26.04 LTS developer VM
# Default: Frappe v16 + ERPNext v16 + site erp.test
# Mode: local development using bench start
# ============================================================

APP_NAME="ERPNext Developer Installer"
SCRIPT_VERSION="0.1.0"

FRAPPE_USER="${FRAPPE_USER:-frappe}"
BENCH_PARENT="${BENCH_PARENT:-/home/${FRAPPE_USER}/frappe}"
BENCH_NAME="${BENCH_NAME:-frappe-bench}"
SITE_NAME="${SITE_NAME:-erp.test}"

FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
ERPNEXT_BRANCH="${ERPNEXT_BRANCH:-version-16}"

NODE_VERSION="${NODE_VERSION:-24}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14}"

DB_ADMIN_USER="${DB_ADMIN_USER:-frappe_db_admin}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

LOG_FILE="/tmp/erpnext-dev-install-$(date +%Y%m%d-%H%M%S).log"

if [[ -t 1 ]]; then
  BOLD="\033[1m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  RED="\033[31m"
  BLUE="\033[34m"
  RESET="\033[0m"
else
  BOLD=""
  GREEN=""
  YELLOW=""
  RED=""
  BLUE=""
  RESET=""
fi

exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  echo -e "\n${BLUE}==>${RESET} ${BOLD}$*${RESET}"
}

ok() {
  echo -e "${GREEN}OK:${RESET} $*"
}

warn() {
  echo -e "${YELLOW}WARN:${RESET} $*"
}

fail() {
  echo -e "${RED}ERROR:${RESET} $*" >&2
  echo "Log file: $LOG_FILE" >&2
  exit 1
}

random_password() {
  python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(28)))
PY
}

require_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO=""
  else
    sudo -v || fail "This installer requires sudo access."
    SUDO="sudo"
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
    "24.04")
      ok "Ubuntu 24.04 LTS detected"
      ;;
    "26.04")
      ok "Ubuntu 26.04 LTS detected"
      ;;
    *)
      fail "Unsupported Ubuntu version: ${PRETTY_NAME:-Ubuntu ${VERSION_ID}}. Supported: Ubuntu 24.04 LTS and Ubuntu 26.04 LTS."
      ;;
  esac
}
apt_package_available() {
  local package="$1"
  apt-cache policy "$package" | grep -qv "Candidate: (none)"
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
    warn "Continuing without $package."
  fi
}


prepare_passwords() {
  log "Preparing generated credentials"

  if [[ -z "$DB_ADMIN_PASSWORD" ]]; then
    DB_ADMIN_PASSWORD="$(random_password)"
  fi

  if [[ -z "$ADMIN_PASSWORD" ]]; then
    ADMIN_PASSWORD="$(random_password)"
  fi

  ok "Credentials prepared"
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

  if grep -q "^vm.overcommit_memory" /etc/sysctl.conf; then
    $SUDO sed -i "s/^vm.overcommit_memory.*/vm.overcommit_memory = 1/" /etc/sysctl.conf
  else
    echo "vm.overcommit_memory = 1" | $SUDO tee -a /etc/sysctl.conf >/dev/null
  fi

  $SUDO sysctl -p >/dev/null || true
  ok "Redis overcommit setting configured"
}

create_frappe_user() {
  log "Preparing Linux user: ${FRAPPE_USER}"

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    ok "User ${FRAPPE_USER} already exists"
  else
    $SUDO adduser --disabled-password --gecos "" "$FRAPPE_USER"
    $SUDO usermod -aG sudo "$FRAPPE_USER"
    ok "User ${FRAPPE_USER} created"
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

install_frappe_stack_as_user() {
  log "Installing Node, Python, Bench, Frappe, and ERPNext as ${FRAPPE_USER}"

  $SUDO -H -u "$FRAPPE_USER" bash <<EOF
set -Eeuo pipefail

export HOME="/home/${FRAPPE_USER}"
export PATH="\$HOME/.local/bin:\$PATH"

mkdir -p "\$HOME"

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
  echo "Bench already exists: ${BENCH_PARENT}/${BENCH_NAME}"
else
  bench init "${BENCH_NAME}" --frappe-branch "${FRAPPE_BRANCH}"
fi

cd "${BENCH_PARENT}/${BENCH_NAME}"

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

echo
echo "==> Creating helper script"

cat > "\$HOME/start-erpnext-dev.sh" <<'HELPER'
#!/usr/bin/env bash
set -e
cd ~/frappe/frappe-bench
bench start
HELPER

chmod +x "\$HOME/start-erpnext-dev.sh"

EOF

  ok "Frappe/ERPNext stack installed"
}

write_credentials_file() {
  log "Writing credentials file"

  CRED_FILE="/home/${FRAPPE_USER}/erpnext-dev-credentials.txt"

  $SUDO tee "$CRED_FILE" >/dev/null <<EOF
ERPNext Developer Environment

Site:
  ${SITE_NAME}

Bench:
  ${BENCH_PARENT}/${BENCH_NAME}

Login:
  Username: Administrator
  Password: ${ADMIN_PASSWORD}

MariaDB Bench Admin:
  User: ${DB_ADMIN_USER}
  Password: ${DB_ADMIN_PASSWORD}

Start ERPNext:
  su - ${FRAPPE_USER}
  cd ${BENCH_PARENT}/${BENCH_NAME}
  bench start

Browser:
  http://${SITE_NAME}:8000

Notes:
  Add this site name to your HOST machine /etc/hosts, not only inside the VM.
EOF

  $SUDO chown "$FRAPPE_USER:$FRAPPE_USER" "$CRED_FILE"
  $SUDO chmod 600 "$CRED_FILE"

  ok "Credentials saved to ${CRED_FILE}"
}

print_summary() {
  VM_IP="$(hostname -I | awk '{print $1}')"

  echo
  echo "============================================================"
  echo "ERPNext Developer Environment Installed"
  echo "============================================================"
  echo
  echo "Site:"
  echo "  ${SITE_NAME}"
  echo
  echo "Bench:"
  echo "  ${BENCH_PARENT}/${BENCH_NAME}"
  echo
  echo "Login:"
  echo "  Username: Administrator"
  echo "  Password: ${ADMIN_PASSWORD}"
  echo
  echo "Start ERPNext:"
  echo "  su - ${FRAPPE_USER}"
  echo "  cd ${BENCH_PARENT}/${BENCH_NAME}"
  echo "  bench start"
  echo
  echo "Inside browser:"
  echo "  http://${SITE_NAME}:8000"
  echo
  echo "On your HOST machine, add this to /etc/hosts:"
  echo "  ${VM_IP} ${SITE_NAME}"
  echo
  echo "Credentials file:"
  echo "  /home/${FRAPPE_USER}/erpnext-dev-credentials.txt"
  echo
  echo "Install log:"
  echo "  ${LOG_FILE}"
  echo
  echo "============================================================"
}

main() {
  echo "${APP_NAME} v${SCRIPT_VERSION}"
  echo "Log file: ${LOG_FILE}"

  require_sudo
  check_os
  prepare_passwords
  install_system_packages
  configure_sysctl_for_redis
  create_frappe_user
  create_mariadb_admin_user
  install_frappe_stack_as_user
  write_credentials_file
  print_summary
}

main "$@"