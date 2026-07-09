# shellcheck shell=bash
# Install preflight, system packages, Frappe stack bootstrap, repair, uninstall, and post-install summaries.
[[ -n "${_ERPNEXT_DEV_INSTALL_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_INSTALL_LOADED=1

# ============================================================
# Install / Repair / Uninstall (core engine)
# ============================================================

random_password() {
  python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(28)))
PY
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

install_override_enabled() {
  [[ "${ERPNEXT_ALLOW_UNSAFE_INSTALL,,}" =~ ^(1|true|yes)$ ]]
}

check_resources() {
  log "Checking VM resources"

  local mem_mb disk_gb tmp_gb cpu_cores blockers warnings
  mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  disk_gb="$(df -BG / | awk 'NR==2 {gsub("G", "", $4); print $4}' 2>/dev/null || echo 0)"
  tmp_gb="$(df -BG /tmp 2>/dev/null | awk 'NR==2 {gsub("G", "", $4); print $4}' || echo 0)"
  cpu_cores="$(nproc 2>/dev/null || echo 0)"
  blockers=0
  warnings=0

  echo
  echo "Install Environment Preflight"
  echo "------------------------------------------------------------"

  if [[ ! "$cpu_cores" =~ ^[0-9]+$ || "$cpu_cores" -lt 1 ]]; then
    status_line "CPU cores" "FAIL" "could not detect CPU count"
    blockers=$((blockers + 1))
  elif [[ "$cpu_cores" -lt "$MIN_INSTALL_CPU_CORES" ]]; then
    status_line "CPU cores" "FAIL" "${cpu_cores} found; minimum is ${MIN_INSTALL_CPU_CORES}. Increase VM vCPU count before installing."
    blockers=$((blockers + 1))
  elif [[ "$cpu_cores" -lt "$RECOMMENDED_INSTALL_CPU_CORES" ]]; then
    status_line "CPU cores" "WARN" "${cpu_cores} found; ${RECOMMENDED_INSTALL_CPU_CORES}+ recommended for smoother builds."
    warnings=$((warnings + 1))
  else
    status_line "CPU cores" "OK" "${cpu_cores}"
  fi

  if [[ ! "$mem_mb" =~ ^[0-9]+$ || "$mem_mb" -lt 1 ]]; then
    status_line "RAM" "FAIL" "could not detect memory"
    blockers=$((blockers + 1))
  elif [[ "$mem_mb" -lt "$MIN_INSTALL_RAM_MB" ]]; then
    status_line "RAM" "FAIL" "${mem_mb} MB found; minimum is ${MIN_INSTALL_RAM_MB} MB. Increase VM RAM before installing."
    blockers=$((blockers + 1))
  elif [[ "$mem_mb" -lt "$RECOMMENDED_INSTALL_RAM_MB" ]]; then
    status_line "RAM" "WARN" "${mem_mb} MB found; ${RECOMMENDED_INSTALL_RAM_MB} MB recommended for ERPNext builds."
    warnings=$((warnings + 1))
  else
    status_line "RAM" "OK" "${mem_mb} MB"
  fi

  if [[ ! "$disk_gb" =~ ^[0-9]+$ || "$disk_gb" -lt 1 ]]; then
    status_line "Root free disk" "FAIL" "could not detect free disk space on /"
    blockers=$((blockers + 1))
  elif [[ "$disk_gb" -lt "$MIN_INSTALL_DISK_GB" ]]; then
    status_line "Root free disk" "FAIL" "${disk_gb} GB available; minimum is ${MIN_INSTALL_DISK_GB} GB. Expand the VM disk before installing."
    blockers=$((blockers + 1))
  elif [[ "$disk_gb" -lt "$RECOMMENDED_INSTALL_DISK_GB" ]]; then
    status_line "Root free disk" "WARN" "${disk_gb} GB available; ${RECOMMENDED_INSTALL_DISK_GB} GB recommended."
    warnings=$((warnings + 1))
  else
    status_line "Root free disk" "OK" "${disk_gb} GB available"
  fi

  if [[ ! "$tmp_gb" =~ ^[0-9]+$ || "$tmp_gb" -lt 1 ]]; then
    status_line "/tmp free disk" "WARN" "could not detect /tmp free space"
    warnings=$((warnings + 1))
  elif [[ "$tmp_gb" -lt "$MIN_INSTALL_TMP_GB" ]]; then
    status_line "/tmp free disk" "FAIL" "${tmp_gb} GB available; minimum is ${MIN_INSTALL_TMP_GB} GB for package/build temp files."
    blockers=$((blockers + 1))
  else
    status_line "/tmp free disk" "OK" "${tmp_gb} GB available"
  fi

  status_line "Warnings" "$([[ "$warnings" -eq 0 ]] && echo OK || echo WARN)" "${warnings}"
  status_line "Blockers" "$([[ "$blockers" -eq 0 ]] && echo OK || echo FAIL)" "${blockers}"
  echo "------------------------------------------------------------"

  if [[ "$blockers" -gt 0 ]]; then
    echo -e "${RED}INSTALL BLOCKED:${RESET} this VM does not meet the safe minimum requirements."
    echo "Fix the FAIL rows above before installing ERPNext."
    echo
    echo "Minimum safe install requirements:"
    echo "  CPU:       ${MIN_INSTALL_CPU_CORES}+ cores"
    echo "  RAM:       ${MIN_INSTALL_RAM_MB}+ MB"
    echo "  Root disk: ${MIN_INSTALL_DISK_GB}+ GB free"
    echo "  /tmp disk: ${MIN_INSTALL_TMP_GB}+ GB free"
    echo
    echo "Recommended for smoother local development:"
    echo "  CPU:       ${RECOMMENDED_INSTALL_CPU_CORES}+ cores"
    echo "  RAM:       ${RECOMMENDED_INSTALL_RAM_MB}+ MB"
    echo "  Root disk: ${RECOMMENDED_INSTALL_DISK_GB}+ GB free"
    echo
    echo "If the only blocker is root disk size and the VM disk was expanded, run:"
    echo "  $(toolkit_cmd expand-root-storage)"

    if install_override_enabled; then
      warn "Unsafe install override is enabled with ERPNEXT_ALLOW_UNSAFE_INSTALL=${ERPNEXT_ALLOW_UNSAFE_INSTALL}. Continuing anyway."
    else
      fail "Environment preflight failed. Installation was stopped before making system changes."
    fi
  else
    ok "Install environment preflight passed"
  fi
}

run_install_preflight() {
  require_sudo
  install_self_for_reuse
  check_os
  check_internet
  check_resources
  echo
  ok "This VM is safe to continue with ERPNext installation."

  if [[ -t 0 ]]; then
    echo
    echo "Next step: start the local VM quickstart."
    echo "This will first offer to expand root storage if extra VM disk capacity is detected."
    if confirm "Start local ERPNext installation now?"; then
      run_local_dev_quickstart
      return 0
    fi
  fi

  echo "Next command:"
  echo "  $(toolkit_cmd local-dev-quickstart)"
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

  frappe_login_bash <<EOF_USER
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
  Use $(toolkit_cmd access) to print the required host-side command.
EOF_CREDS

  $SUDO chown root:root "$cred_file"
  $SUDO chmod 600 "$cred_file"

  ok "Credentials saved to ${cred_file}"
  ok "Credentials file secured with root-only permissions"
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
  install_self_for_reuse
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
      warn "Run this later: $(toolkit_cmd start)"
    fi
  elif [[ "${AUTO_START}" == "false" ]]; then
    echo
    echo "You can start ERPNext later with:"
    echo "  $(toolkit_cmd start)"
  elif [[ -t 0 ]]; then
    echo
    read -r -p "Start ERPNext now in the background service? [Y/n]: " start_now
    start_now="${start_now:-Y}"
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
      if ! start_erpnext_service; then
        warn "Install completed, but ERPNext could not be started automatically."
        warn "Run this later: $(toolkit_cmd start)"
      fi
    else
      echo
      echo "You can start ERPNext later with:"
      echo "  $(toolkit_cmd start)"
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
  menu_footer
  menu_read_choice choice

  case "$choice" in
    1) soft_uninstall ;;
    2) remove_bench_files ;;
    3) full_purge ;;
    b|B|"") return 0 ;;
    q|Q) exit 0 ;;
    *) warn "Invalid option" ;;
  esac
}

post_core_install_checkpoint() {
  local reply
  echo
  echo "Core install checkpoint recommended."
  echo "Create a database + files backup now, and take a VM/provider snapshot if this VM is important."

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    create_site_backup true || warn "Core install backup failed. Create a manual checkpoint before HTTPS/hardening/apps."
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -p "Create database + files backup now? [Y/n]: " reply
    reply="${reply:-Y}"
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      create_site_backup true || warn "Core install backup failed. Create a manual checkpoint before HTTPS/hardening/apps."
    else
      warn "Core install backup skipped. Take a VM snapshot or backup before HTTPS, hardening, or app installs."
    fi
  fi
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
  echo "  Credentials help: $(toolkit_cmd credentials-info)"
  echo "  Show password: $(toolkit_cmd credentials-show)"
  echo
  echo "Start ERPNext:"
  echo "  $(toolkit_cmd start)"
  echo
  echo "Manual start command:"
  echo "  sudo -iu ${FRAPPE_USER}"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo "  cd ${bench_dir}"
  echo "  bench start"
  echo
  echo "Browser access:"
  echo "  Direct IP:    http://${vm_ip}:8000"
  echo "  Friendly URL: http://${SITE_NAME}:8000"
  echo
  if ! is_public_vm_workflow; then
    echo "Required host mapping checkpoint before local HTTPS:"
    echo "  $(toolkit_cmd local-host-checkpoint)"
    echo "Recommended next local step after HTTP works:"
    echo "  $(toolkit_cmd local-ssl-wizard)"
    echo "More local SSL options:"
    echo "  $(toolkit_cmd local-ssl-menu)"
    echo "Keep the local VM IP stable, especially on KVM/libvirt:"
    echo "  $(toolkit_cmd local-fixed-ip-guide)"
    echo
  fi
  echo "Run this on the HOST for the friendly URL."
  echo "Safe to repeat after VM recreation or DHCP IP changes:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Verify access after setup:"
  echo "  $(toolkit_cmd verify-access)"
  echo
  echo "Credentials file:"
  echo "  ${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  echo
  echo "Install log:"
  echo "  ${LOG_FILE}"
  echo
  echo "============================================================"
}
