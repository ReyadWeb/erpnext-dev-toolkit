# shellcheck shell=bash
# Install preflight, stack bootstrap, repair/uninstall, summaries, and setup workflows.
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

  # Native install supports Debian-family distributions with apt + systemd. The
  # tested targets are Ubuntu 24.04/26.04 LTS and Debian 13 (trixie); all use the
  # same apt package names, MariaDB/Redis systemd units, and useradd flow below.
  case "${ID:-}" in
    ubuntu)
      case "${VERSION_ID}" in
        "24.04") ok "Ubuntu 24.04 LTS detected" ;;
        "26.04") ok "Ubuntu 26.04 LTS detected" ;;
        *) fail "Unsupported Ubuntu version: ${PRETTY_NAME:-Ubuntu ${VERSION_ID}}. Supported: Ubuntu 24.04 LTS, Ubuntu 26.04 LTS, and Debian 13." ;;
      esac
      ;;
    debian)
      case "${VERSION_ID}" in
        "13") ok "Debian 13 (trixie) detected" ;;
        *) fail "Unsupported Debian version: ${PRETTY_NAME:-Debian ${VERSION_ID}}. Supported: Debian 13 (trixie). Ubuntu 24.04/26.04 LTS are also supported." ;;
      esac
      ;;
    *)
      fail "This script supports Ubuntu 24.04/26.04 LTS and Debian 13 (trixie). Detected: ${PRETTY_NAME:-unknown}"
      ;;
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

  # Engine-aware preflight. Docker abstracts the guest OS, so it runs its own
  # compatibility block (OS / engine / architecture / Docker / image).
  if deployment_engine_is_docker; then
    docker_preflight
    echo
    if [[ -t 0 ]] && confirm "Start the Docker ERPNext setup now?"; then
      docker_guided_install
      return 0
    fi
    echo "Next command:"
    echo "  $(toolkit_cmd install)"
    return 0
  fi

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

  # Keep this list Debian-family portable (Ubuntu 24.04/26.04 + Debian 13).
  # Do not hard-require Ubuntu-only packages here — Debian 13 removed
  # software-properties-common, and we never call add-apt-repository.
  local packages=(
    git curl wget nano ca-certificates gnupg lsb-release
    build-essential pkg-config
    redis-server mariadb-server mariadb-client libmariadb-dev
    python3 python3-dev python3-pip python3-venv
    libffi-dev libssl-dev libjpeg-dev zlib1g-dev
    xvfb
    cron netcat-openbsd
  )

  # Refresh apt metadata before availability probes so Debian/Ubuntu package
  # names resolve against a current index.
  $SUDO apt-get update

  # fontconfig runtime: Debian ships libfontconfig1; some Ubuntu releases also
  # expose a libfontconfig transitional name. Prefer the portable package.
  if apt_package_available "libfontconfig1"; then
    packages+=(libfontconfig1)
  elif apt_package_available "libfontconfig"; then
    packages+=(libfontconfig)
  else
    packages+=(fontconfig)
  fi

  install_required_packages "${packages[@]}"

  log "Installing optional packages"
  # Ubuntu convenience package only; absent on Debian 13 (and unused by us).
  install_optional_package "software-properties-common"
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
    # Prefer useradd over adduser for non-interactive creation.
    # On Ubuntu 26.04+, adduser's Perl sanitize_string can abort when the
    # caller's HOME (often preserved by `sudo -E`) contains filenames with
    # quotes/Unicode — notably GitHub Actions runners' preinstalled
    # ~/.nvm/test fixtures. useradd does not walk that tree.
    if command -v useradd >/dev/null 2>&1; then
      $SUDO useradd --create-home --shell /bin/bash --comment "" "$FRAPPE_USER"
      $SUDO passwd -l "$FRAPPE_USER" >/dev/null 2>&1 || true
    else
      $SUDO env HOME=/root adduser --disabled-password --gecos "" "$FRAPPE_USER"
    fi
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

# Pin XDG base dirs under the frappe home. Otherwise a caller-inherited
# XDG_CONFIG_HOME/XDG_* (e.g. /home/runner/.config in CI, or a sudo env that
# preserves it) leaks in, and tools like the uv installer try to write their
# receipt there and fail with a permission error. Installs must not depend on
# the invoking user's XDG environment.
export XDG_CONFIG_HOME="\$HOME/.config"
export XDG_DATA_HOME="\$HOME/.local/share"
export XDG_STATE_HOME="\$HOME/.local/state"
export XDG_CACHE_HOME="\$HOME/.cache"

mkdir -p "\$HOME" "\$XDG_CONFIG_HOME" "\$XDG_DATA_HOME" "\$XDG_STATE_HOME" "\$XDG_CACHE_HOME"
cd "\$HOME"

echo
echo "==> Installing nvm / Node ${NODE_VERSION} / Yarn"

# Pin NVM_DIR BEFORE running the installer. The nvm installer honors
# XDG_CONFIG_HOME when NVM_DIR is unset, so with the XDG pins above it would
# otherwise install into \$HOME/.config/nvm while the rest of the toolkit (this
# script, the systemd unit, frappe.sh, apps.sh) all source \$HOME/.nvm/nvm.sh.
export NVM_DIR="\$HOME/.nvm"
if [[ ! -s "\$NVM_DIR/nvm.sh" ]]; then
  # Pre-create NVM_DIR. With XDG_CONFIG_HOME set, nvm's "default install dir"
  # is \$XDG_CONFIG_HOME/nvm, and the installer only auto-creates NVM_DIR when
  # it matches that default. Since we force \$HOME/.nvm, the installer would
  # otherwise abort with "that directory does not exist"; creating it first
  # makes the installer clone straight into it.
  mkdir -p "\$NVM_DIR"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | NVM_DIR="\$NVM_DIR" bash
fi

# shellcheck disable=SC1091
source "\$NVM_DIR/nvm.sh"

nvm install "${NODE_VERSION}"
nvm use "${NODE_VERSION}"
# Pin the default alias so non-interactive login shells that only source
# nvm.sh (the systemd unit, frappe_login_bash) activate this Node version
# instead of falling back to a system Node that may be too old for Frappe.
nvm alias default "${NODE_VERSION}"
npm install -g yarn

echo
echo "==> Installing uv / Python ${PYTHON_VERSION} / Bench"

if ! command -v uv >/dev/null 2>&1; then
  # Pin the uv installer to a known version instead of the unversioned "latest"
  # URL, so bootstrap is reproducible. Override with UV_VERSION if needed.
  curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
fi

export PATH="\$HOME/.local/bin:\$PATH"

uv python install "${PYTHON_VERSION}" --default
if [[ -n "${BENCH_VERSION}" ]]; then
  uv tool install "frappe-bench==${BENCH_VERSION}" --force
else
  uv tool install frappe-bench --force
fi

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

  # Choose the deployment engine once (native VM or Docker). Native keeps the
  # exact behavior below; Docker hands off to the frappe_docker-backed engine.
  choose_deployment_engine_for_setup 0
  if deployment_engine_is_docker; then
    docker_guided_install
    return
  fi

  install_self_for_reuse || fail "Could not install the toolkit to ${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"
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
  prompt_production_credential_handoff_if_needed

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
    # Avoid deluser --remove-home on Ubuntu 26.04+: sanitize_string can fail on
    # non-ASCII/special filenames under the home tree (same class as adduser).
    if command -v userdel >/dev/null 2>&1; then
      $SUDO userdel "$FRAPPE_USER" || true
    else
      $SUDO deluser "$FRAPPE_USER" || true
    fi
    $SUDO rm -rf "$FRAPPE_HOME" || true
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

  ui_submenu_header "Uninstall Options" "Soft archive, remove files, or full purge"
  print_two_column_menu \
    "1) Soft uninstall: stop Bench and archive ${BENCH_PARENT}" \
    "2) Remove bench files only" \
    "3) Full purge: remove bench, frappe user, MariaDB/Redis packages"
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
  echo "Browser access (use the friendly hostname after /etc/hosts):"
  echo "  Login: http://${SITE_NAME}:8000/login"
  echo "  Desk:  http://${SITE_NAME}:8000/app"
  echo
  warn "Raw IP (http://${vm_ip}:8000) often shows an unstyled page — Host header mismatch."
  echo "  Prefer http://${SITE_NAME}:8000 after the host mapping below."
  echo
  if ! is_public_vm_workflow; then
    echo "Required host mapping checkpoint before local HTTPS:"
    echo "  $(toolkit_cmd local-host-checkpoint)"
    echo "Recommended next local step after HTTP works:"
    echo "  $(toolkit_cmd local-ssl-wizard)"
    echo "More local SSL options:"
    echo "  $(toolkit_cmd local-ssl-menu)"
    echo "Keep the local VM IP stable (guidance for your hypervisor/host OS):"
    echo "  $(toolkit_cmd local-fixed-ip-guide)"
    echo
  fi
  echo "Run this on the $(host_os_label) HOST for the friendly URL."
  echo "Safe to repeat after VM recreation or DHCP IP changes:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Verify access after setup (includes static-asset probe):"
  echo "  $(toolkit_cmd verify-access)"
  echo "  $(toolkit_cmd wait-ready)"
  echo
  echo "Credentials file:"
  echo "  ${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  echo
  echo "Install log:"
  echo "  ${LOG_FILE}"
  echo
  echo "============================================================"
}

show_setup_lifecycle_plan() {
  require_sudo

  echo
  echo "============================================================"
  echo "Recommended Setup Lifecycle"
  echo "============================================================"
  echo "Local VM order:"
  echo "  1) Check requirements and storage"
  echo "  2) Choose local .test domain, default erp.test"
  echo "  3) Install ERPNext and verify service health"
  echo "  4) Run host DNS mapping checkpoint on the host machine"
  echo "  5) Confirm HTTP works from the host"
  echo "  6) Create backup checkpoint / VM snapshot"
  echo "  7) Configure local HTTPS if wanted"
  echo "  8) Apply Local VM security profile only"
  echo "  9) Install optional apps one at a time"
  echo "  10) Backup after every optional app"
  echo "  11) Final status summary and credentials"
  echo
  echo "Production order:"
  echo "  1) Check requirements, storage, public IP, DNS readiness"
  echo "  2) Set real production domain"
  echo "  3) Install ERPNext and verify service health"
  echo "  4) Create backup checkpoint / provider snapshot"
  echo "  5) Configure production HTTPS"
  echo "  6) Apply Production security profile only after HTTPS works"
  echo "  7) Create a second checkpoint"
  echo "  8) Install optional apps one at a time"
  echo "  9) Backup after every optional app"
  echo "  10) Final QA, access URLs, credentials, support bundle"
  echo "============================================================"
}


run_guided_setup() {
  require_sudo

  echo
  echo "============================================================"
  echo "Guided ERPNext Setup"
  echo "============================================================"
  echo "Flow: requirements -> domain -> install -> verify -> backup checkpoint -> HTTPS -> security profile -> apps -> final QA."
  echo "Keep this terminal open until setup finishes."
  echo "============================================================"

  run_install

  echo
  if declare -F bench_static_assets_ready >/dev/null 2>&1 && \
     { port_listens 443 || port_listens 8000; } && \
     ! bench_static_assets_ready; then
    warn "Install finished, but login CSS/JS are not ready yet."
    warn "Opening the site now can show an unstyled page — wait, then refresh."
    echo "  $(toolkit_cmd wait-frontend-assets)"
    echo "  $(toolkit_cmd repair-frontend-assets)"
  else
    ok "ERPNext installation workflow finished successfully."
  fi
  echo "Verifying access state..."
  verify_access
  post_core_install_checkpoint
  show_next_step
  if ! is_public_vm_workflow; then
    show_local_host_mapping_checkpoint
    local_guided_followups
  fi
  prompt_open_main_menu_after_install
}

# Guided local follow-up chain: after the core install, walk the user through
# the optional steps that finish a local development environment. Each step is
# opt-in (confirm defaults to "No"), mirroring the way the public-vm guided setup
# chains HTTPS -> security -> apps. Only runs in a genuinely interactive session;
# under -y (ASSUME_YES) or a non-tty we keep the plain install behavior so
# automation/CI is unaffected.
local_guided_followups() {
  [[ -t 0 ]] || return 0
  [[ "$ASSUME_YES" -eq 1 ]] && return 0

  ui_box_start "Local setup: guided follow-up steps"
  echo "ERPNext is installed. Prefer http://${SITE_NAME}:8000/login (not the raw IP)."
  echo "If the login page looks unstyled, wait until $(toolkit_cmd wait-ready) reports"
  echo "static assets OK, then hard-refresh the browser."
  echo "These optional steps finish a local development environment (each is opt-in)."
  ui_box_end

  echo
  echo "Trusted local HTTPS uses mkcert so ${SITE_NAME} opens without browser warnings."
  echo "For other options (self-signed, status, disable), use: $(toolkit_cmd local-ssl-wizard)"
  if confirm "Set up trusted local HTTPS (mkcert) now?"; then
    # Run the recommended trusted-HTTPS path directly rather than opening the full
    # SSL sub-menu. In a guided flow the operator should not have to find "Back"
    # to continue: when mkcert finishes, control returns here and the chain moves
    # on to credentials -> security -> apps automatically.
    run_trusted_mkcert_setup || true
  else
    echo "Skipped. Run later with: $(toolkit_cmd local-ssl-wizard)"
  fi

  local_guided_credentials_checkpoint

  echo
  if confirm "Apply the local security profile / firewall now (security-hardening-wizard)?"; then
    security_hardening_wizard || true
  else
    echo "Skipped. Run later with: $(toolkit_cmd security-hardening-wizard)"
  fi

  echo
  if confirm "Install optional Frappe apps now (app-install-wizard)?"; then
    run_app_install_wizard || true
  else
    echo "Skipped. Run later with: $(toolkit_cmd app-install-wizard)"
  fi

  echo
  ok "Local guided follow-up steps complete."
  show_next_step || true
}

# Credentials checkpoint in the guided chain: after HTTPS is set up and before
# security hardening, remind the operator where the login credentials live and
# offer to reveal them once on this private console. credentials_show handles the
# SHOW confirmation and writes secrets only to /dev/tty (never the log stream).
local_guided_credentials_checkpoint() {
  [[ -t 0 ]] || return 0
  [[ "$ASSUME_YES" -eq 1 ]] && return 0

  echo
  ui_box_start "Local setup: login credentials"
  echo "Your ERPNext Administrator login is ready. Save it before hardening the VM."
  ui_box_end
  show_credentials_info || true

  echo
  if confirm "Reveal the generated Administrator password now (private console only)?"; then
    credentials_show || true
  else
    echo "Skipped. Reveal it later with: $(toolkit_cmd credentials-show)"
  fi
}


prompt_open_main_menu_after_install() {
  local reply

  [[ -t 0 ]] || return 0
  echo
  if is_public_vm_workflow; then
    echo "Recommended production follow-up actions:"
    echo "  Production HTTPS / SSL: $(toolkit_cmd production-ssl-menu)"
    echo "  Security profile:       $(toolkit_cmd security-hardening-wizard)"
    echo "  Optional apps:          $(toolkit_cmd app-install-wizard)"
    echo "  Final QA:               $(toolkit_cmd final-qa)"
  else
    echo "Recommended local VM follow-up actions:"
    echo "  Required host step:     $(toolkit_cmd local-host-checkpoint)"
    echo "  Next after HTTP works:  $(toolkit_cmd local-ssl-wizard)"
    echo "  More SSL options:       $(toolkit_cmd local-ssl-menu)"
    echo "  Keep VM IP stable:      $(toolkit_cmd local-fixed-ip-guide)"
    echo "  Local security profile: $(toolkit_cmd security-hardening-wizard)"
    echo "  Optional apps:          $(toolkit_cmd app-install-wizard)"
    echo "  Next step check:        $(toolkit_cmd next-step)"
  fi
  echo
  read -r -p "Open the main toolkit menu now? [Y/n]: " reply
  reply="${reply:-Y}"
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    show_menu
  else
    echo
    echo "Open it later with:"
    echo "  $(toolkit_cmd menu)"
  fi
}

prompt_and_save_public_domain() {
  require_sudo

  local current default_domain domain reply site_reply use_as_site
  current="${PRODUCTION_DOMAIN:-}"
  if [[ -z "$current" && "$SITE_NAME" != *.test && "$SITE_NAME" != *.local ]]; then
    current="$SITE_NAME"
  fi
  default_domain="${current:-erp.company.com}"

  ui_box_start "Set Public ERPNext Domain"
  echo "Enter the real hostname users will open in the browser."
  echo "Example: erp.flowmaya.com"
  echo

  while true; do
    if [[ "$ASSUME_YES" -ne 1 ]]; then
      read -r -p "Production domain [${default_domain}]: " domain || domain=""
      domain="${domain:-$default_domain}"
    else
      domain="$default_domain"
    fi
    domain="${domain,,}"
    if validate_production_domain_value "$domain" >/dev/null 2>&1; then
      break
    fi
    echo "Invalid domain. Use a real hostname such as erp.company.com."
  done

  use_as_site="Y"
  if [[ "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Use ${domain} as the ERPNext site name too? [Y/n]: " reply || reply=""
    reply="${reply:-Y}"
    [[ "$reply" =~ ^[Nn]$ ]] && use_as_site="N"
  fi

  PRODUCTION_DOMAIN="$domain"
  DEPLOYMENT_MODE="public-vm"
  PRODUCTION_SSL_MODE="planned"

  if [[ "$use_as_site" == "Y" ]]; then
    SITE_NAME="$domain"
    SITE_NAME_SOURCE="domain wizard"
  else
    while true; do
      if [[ "$ASSUME_YES" -ne 1 ]]; then
        read -r -p "ERPNext site name [${SITE_NAME}]: " site_reply || site_reply=""
        site_reply="${site_reply:-$SITE_NAME}"
      else
        site_reply="$SITE_NAME"
      fi
      site_reply="${site_reply,,}"
      if validate_site_name_value "$site_reply" >/dev/null 2>&1; then
        SITE_NAME="$site_reply"
        SITE_NAME_SOURCE="domain wizard"
        break
      fi
      echo "Invalid site name. Use a hostname without URL, port, spaces, or slashes."
    done
  fi

  write_dev_config_file
  SITE_NAME_SOURCE="saved config"

  ui_box_start "Result Summary"
  status_line "Production domain" "OK" "$PRODUCTION_DOMAIN"
  status_line "ERPNext site" "OK" "$SITE_NAME"
  status_line "Deployment mode" "INFO" "$DEPLOYMENT_MODE"
  status_line "Saved config" "OK" "$CONFIG_FILE"
  ui_box_end
  ui_next "$(toolkit_cmd public-vm-quickstart)" "$(toolkit_cmd production-domain-plan)"
}

set_local_dev_defaults() {
  require_sudo

  if [[ "$SITE_NAME_ENV_PROVIDED" -eq 0 && ( -z "${SITE_NAME:-}" || "$SITE_NAME" != *.test ) ]]; then
    SITE_NAME="erp.test"
  fi
  SITE_NAME_SOURCE="local quickstart"
  DEPLOYMENT_MODE="development"
  PRODUCTION_DOMAIN=""
  PRODUCTION_SSL_MODE="planned"
  # Normalize to a stored value (defaults to linux) so the config always records
  # a concrete host OS once local defaults are saved.
  # shellcheck disable=SC2034  # consumed by write_dev_config_file in lib/config.sh
  HOST_OS="$(effective_host_os)"
  # Record a concrete engine (defaults to native) so config always has a value.
  # shellcheck disable=SC2034  # consumed by write_dev_config_file in lib/config.sh
  DEPLOYMENT_ENGINE="$(effective_deployment_engine)"
  write_dev_config_file
  SITE_NAME_SOURCE="saved config"
}

run_local_dev_quickstart() {
  require_sudo
  install_self_for_reuse || fail "Could not install the toolkit to ${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"

  ui_box_start "Local VM Quickstart"
  echo "This path uses local development defaults and keeps inputs minimal."
  echo "You can choose the local VM domain now, or press Enter for erp.test."
  status_line "Current site" "INFO" "${SITE_NAME:-erp.test}"
  status_line "Production domain" "INFO" "not used"
  status_line "Mode" "INFO" "local development"
  ui_box_end

  choose_local_site_name_for_setup

  # Ask once which host OS is in use; set_local_dev_defaults persists it below.
  choose_host_os_for_setup 0

  # Choose the deployment engine. Docker hands off to the containerized flow.
  choose_deployment_engine_for_setup 0
  if deployment_engine_is_docker; then
    docker_guided_install
    return
  fi

  ui_box_start "Local VM Setup Confirmation"
  status_line "Local VM domain" "OK" "${SITE_NAME}"
  status_line "Default if skipped" "INFO" "erp.test"
  status_line "Host OS" "INFO" "$(host_os_label)"
  status_line "Deployment engine" "INFO" "$(deployment_engine_label)"
  status_line "Production domain" "INFO" "not used"
  ui_box_end

  echo "The host DNS command will be generated with this VM's detected IP. Do not hardcode another user's IP."
  echo "Warning: DHCP guest IPs often change after reboot and break ${SITE_NAME:-erp.test} / local HTTPS."
  echo "Plan a stable IP early: $(toolkit_cmd local-ip-status) → $(toolkit_cmd local-ip-plan) → $(toolkit_cmd local-static-ip-wizard)."
  echo "After install, the toolkit will print browser URLs, host DNS guidance, and the direct local HTTPS command."
  echo "Useful follow-up commands:"
  echo "  $(toolkit_cmd local-host-checkpoint)"
  echo "  $(toolkit_cmd host-dns-guide)"
  echo "  $(toolkit_cmd local-ssl-wizard)"
  echo "  $(toolkit_cmd local-ip-menu)"
  echo "  $(toolkit_cmd local-fixed-ip-guide)"

  if confirm "Save local defaults and start guided setup now?"; then
    set_local_dev_defaults
    run_guided_setup
  else
    ui_next "$(toolkit_cmd local-dev-quickstart)" "$(toolkit_cmd setup-wizard)"
  fi
}

public_quickstart_status_summary() {
  local vm_ip installed runtime ssl_pair ssl_status ssl_detail domain_status dns_ip provider
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  installed="$(install_state 2>/dev/null || echo "Not installed")"
  runtime="$(runtime_state 2>/dev/null || echo "Stopped")"
  provider="$(active_production_ssl_provider 2>/dev/null || echo "none")"
  ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo "WARN|not configured")"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"
  dns_ip=""
  domain_status="INFO"
  if [[ -n "${PRODUCTION_DOMAIN:-}" ]]; then
    dns_ip="$(resolve_ipv4_first "$PRODUCTION_DOMAIN")"
    if [[ -n "$dns_ip" ]]; then
      if [[ "$dns_ip" == "$vm_ip" || "$provider" == "Cloudflare Origin CA" ]]; then
        domain_status="OK"
      else
        domain_status="WARN"
      fi
    else
      domain_status="WARN"
    fi
  else
    domain_status="WARN"
  fi

  status_line "Domain" "$domain_status" "${PRODUCTION_DOMAIN:-not set}${dns_ip:+; DNS=$dns_ip}; VM=$vm_ip"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Install" "$([[ "$installed" == "Installed" ]] && echo OK || echo WARN)" "$installed"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo WARN)" "$runtime"
  status_line "HTTPS" "$ssl_status" "$ssl_detail"
}

ensure_public_domain_configured() {
  if [[ -n "${PRODUCTION_DOMAIN:-}" ]] && validate_production_domain_value "$PRODUCTION_DOMAIN" >/dev/null 2>&1; then
    return 0
  fi

  warn "Public VM setup needs a real production domain before install/HTTPS."
  if confirm "Set the production domain now?"; then
    prompt_and_save_public_domain
    return 0
  fi
  return 1
}

public_quickstart_maybe_initial_backup() {
  local latest_lines completeness
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
  if [[ "$completeness" == "complete" ]]; then
    status_line "Initial backup" "OK" "complete backup set exists"
    return 0
  fi

  status_line "Initial backup" "WARN" "no complete backup set yet"
  if confirm "Create initial database + files backup now?"; then
    create_site_backup true || return 1
    verify_latest_backup_set || true
  else
    ui_next "$(toolkit_cmd backup-files)" "$(toolkit_cmd backup-verify)"
  fi
}

public_quickstart_final_status() {
  show_production_readiness
  show_production_ssl_status
  show_firewall_hardening_status
  public_quickstart_maybe_initial_backup || true
  show_release_readiness
  ui_next "$(toolkit_cmd support-bundle)" "Take a cloud snapshot after validation."
}


public_vm_guided_step() {
  local number="$1"
  local title="$2"
  echo
  echo "============================================================"
  echo "Production Guided Setup - Step ${number}"
  echo "${title}"
  echo "============================================================"
}

public_vm_guided_require_dns_ready() {
  local vm_ip dns_ip domain ctx mode detail provider choice
  domain="${PRODUCTION_DOMAIN:-}"
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  dns_ip="$(resolve_ipv4_first "$domain")"

  public_vm_guided_step "3" "DNS readiness gate"
  status_line "Production domain" "$([[ -n "$domain" ]] && echo OK || echo FAIL)" "${domain:-not set}"
  status_line "DNS A record" "$([[ -n "$dns_ip" ]] && echo OK || echo FAIL)" "${dns_ip:-unresolved}"
  status_line "VM IPv4" "INFO" "$vm_ip"

  if [[ -z "$dns_ip" ]]; then
    echo
    err "DNS does not resolve yet. Create/update the A record before continuing."
    echo "Required record:"
    echo "  A    ${domain}    ${vm_ip}"
    return 1
  fi

  if [[ "$dns_ip" == "$vm_ip" ]]; then
    ok "DNS points to this VM."
    return 0
  fi

  ctx="$(ssl_mode_context)"
  mode="${ctx%%|*}"; ctx="${ctx#*|}"
  detail="${ctx%%|*}"; ctx="${ctx#*|}"
  provider="${ctx%%|*}"

  echo
  warn "DNS does not resolve directly to this VM."
  echo "Expected origin IP: ${vm_ip}"
  echo "Public DNS result:  ${dns_ip}"
  echo

  if [[ "$provider" == "Cloudflare Origin CA" || "${PRODUCTION_SSL_MODE:-planned}" == "cloudflare-origin-ca" ]]; then
    status_line "Cloudflare path" "OK" "Cloudflare Origin CA is active/selected; public DNS may return Cloudflare edge IPs"
    ok "Continuing with Cloudflare Origin CA mode. Confirm Cloudflare DNS origin remains ${vm_ip}."
    return 0
  fi

  echo "This is expected only when Cloudflare proxy/orange-cloud is active."
  echo "For the default Let's Encrypt HTTP-01 path, switch Cloudflare to DNS-only/gray-cloud first."
  echo "For Cloudflare Origin CA, confirm the hidden Cloudflare A-record content points to this VM."
  echo

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    err "Cannot auto-confirm Cloudflare proxied DNS in non-interactive mode."
    return 1
  fi

  echo "1) Stop and use DNS-only/gray-cloud for Let's Encrypt (recommended default)"
  echo "2) Continue with Cloudflare proxied / Origin CA path"
  echo "3) Show SSL mode guide/status"
  menu_footer
  menu_read_choice choice
  case "$choice" in
    2)
      echo
      status_line "Cloudflare proxy" "INFO" "public DNS returns ${dns_ip}, not the origin IP"
      echo "Required Cloudflare dashboard state:"
      echo "  DNS record ${domain}: A record content ${vm_ip}, Proxied / orange-cloud"
      echo "  SSL/TLS encryption mode: Full (strict) after Origin CA is installed"
      echo
      if confirm "Cloudflare DNS origin is ${vm_ip} and proxy/orange-cloud is intended"; then
        PRODUCTION_SSL_MODE="cloudflare-origin-ca"
        write_dev_config_file >/dev/null || true
        ok "Cloudflare Origin CA path selected. Public DNS returning Cloudflare IPs is expected."
        return 0
      fi
      warn "Stop here. Confirm Cloudflare DNS origin/proxy settings, then rerun: $(toolkit_cmd public-vm-guided-setup)"
      return 1
      ;;
    3)
      show_ssl_mode_status || true
      show_ssl_mode_guide || true
      warn "Rerun guided setup after choosing DNS-only Let's Encrypt or Cloudflare Origin CA."
      return 1
      ;;
    b|B|q|Q|1|"")
      warn "Stop here. Use DNS-only/gray-cloud for Let's Encrypt, or rerun and choose the Cloudflare Origin CA path."
      return 1
      ;;
    *)
      warn "Invalid option: ${choice}"
      return 1
      ;;
  esac
}

public_vm_guided_external_gate() {
  local vm_ip domain
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  domain="${PRODUCTION_DOMAIN:-$SITE_NAME}"

  public_vm_guided_step "4" "External cloud firewall and snapshot gate"
  echo "These checks happen outside Ubuntu, so the toolkit cannot safely apply them without provider API credentials."
  echo
  status_line "Production domain" "INFO" "$domain"
  status_line "VM IPv4" "INFO" "$vm_ip"
  echo
  echo "Confirm your cloud/provider firewall allows only:"
  echo "  22/tcp    from your admin IP only"
  echo "  80/tcp    from anywhere"
  echo "  443/tcp   from anywhere"
  echo "  8000/tcp  blocked from anywhere"
  echo "  9000/tcp  blocked from anywhere"
  echo
  if ! confirm "Cloud firewall baseline is configured as above"; then
    warn "Stop here, configure the cloud firewall, then rerun: $(toolkit_cmd public-vm-guided-setup)"
    return 1
  fi
  echo
  echo "Confirm you took a clean provider snapshot before installation."
  echo "Recommended name: erpnext-toolkit-v${SCRIPT_VERSION}-clean-before-install"
  if ! confirm "Initial clean provider snapshot exists"; then
    warn "Stop here, take the clean snapshot, then rerun: $(toolkit_cmd public-vm-guided-setup)"
    return 1
  fi
}

public_vm_guided_install_core() {
  local installed runtime
  installed="$(install_state 2>/dev/null || echo "Not installed")"
  runtime="$(runtime_state 2>/dev/null || echo "Stopped")"

  public_vm_guided_step "5" "Install or repair ERPNext"
  status_line "Install" "$([[ "$installed" == Installed* ]] && echo OK || echo WARN)" "$installed"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo WARN)" "$runtime"

  if [[ "$installed" != Installed* ]]; then
    run_install
  elif [[ "$runtime" != Running* ]]; then
    if confirm "ERPNext is installed but not running. Start the service now?"; then
      start_erpnext_service || return 1
    fi
  else
    ok "ERPNext is already installed and running."
  fi

  echo
  ok "Core ERPNext step complete."
  verify_access || true
}

public_vm_guided_production_runtime() {
  public_vm_guided_step "5b" "Production runtime"
  echo "Production serves ERPNext with gunicorn + background workers + scheduler +"
  echo "socket.io under supervisor, not the development 'bench start' server"
  echo "(which runs a debugger and a live-reload watcher)."
  echo

  if runtime_is_production && production_runtime_configured; then
    ok "Production runtime already configured (supervisor)."
    return 0
  fi

  if [[ "$(install_state 2>/dev/null)" != Installed* ]]; then
    warn "ERPNext is not fully installed yet; skipping production runtime setup."
    return 0
  fi

  if [[ "$ASSUME_YES" -eq 1 ]] || confirm "Switch this VM to the production runtime now?"; then
    setup_production_runtime || warn "Production runtime setup did not complete; staying on the development runtime."
  else
    warn "Keeping the development bench-start runtime."
    echo "  Switch later with: $(toolkit_cmd setup-production-runtime)"
  fi
}

public_vm_guided_backup_checkpoint() {
  public_vm_guided_step "6" "Backup checkpoint"
  public_quickstart_maybe_initial_backup || return 1
  verify_latest_backup_set || true
}

public_vm_guided_configure_https() {
  local ssl_pair ssl_status ssl_detail ctx mode detail provider dns_ip vm_ip choice
  ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not configured for production')"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"

  public_vm_guided_step "7" "Production HTTPS"
  status_line "Current HTTPS" "$ssl_status" "$ssl_detail"
  if [[ "$ssl_status" == "OK" ]]; then
    ok "Production HTTPS is already configured."
    show_production_ssl_status || true
    return 0
  fi

  ctx="$(ssl_mode_context)"
  mode="${ctx%%|*}"; ctx="${ctx#*|}"
  detail="${ctx%%|*}"; ctx="${ctx#*|}"
  provider="${ctx%%|*}"; ctx="${ctx#*|}"
  dns_ip="${ctx%%|*}"; ctx="${ctx#*|}"
  vm_ip="$ctx"

  status_line "Recommended mode" "INFO" "$mode"
  status_line "Active provider" "INFO" "$provider"
  status_line "DNS / VM" "INFO" "DNS=${dns_ip}; VM=${vm_ip}"
  echo "Reason: $detail"
  echo

  case "$mode" in
    letsencrypt)
      echo "Recommended guided choice: Let's Encrypt directly on this VM."
      echo "Alternative available: Cloudflare Origin CA for Cloudflare-proxied Full (strict) deployments."
      echo
      if [[ "$ASSUME_YES" -eq 1 ]]; then
        configure_production_ssl || return 1
      else
        echo "1) Use recommended Let's Encrypt directly on this VM (default)"
        echo "2) Choose another SSL provider / advanced SSL wizard"
        echo "3) Show SSL mode guide/status"
        menu_footer
        menu_read_choice choice
        case "$choice" in
          1|"") configure_production_ssl || return 1 ;;
          2) production_ssl_wizard || return 1 ;;
          3) show_ssl_mode_status; show_ssl_mode_guide; production_ssl_wizard || return 1 ;;
          b|B) warn "Production HTTPS was not configured. Rerun: $(toolkit_cmd public-vm-guided-setup)"; return 1 ;;
          q|Q) exit 0 ;;
          *) warn "Invalid option: ${choice}"; return 1 ;;
        esac
      fi
      ;;
    cloudflare-origin-ca)
      warn "DNS does not look like direct origin DNS, or Cloudflare Origin CA is already selected."
      echo "The guided setup will open the SSL provider wizard so you can choose Cloudflare Origin CA or adjust back to Let's Encrypt."
      production_ssl_wizard || return 1
      ;;
    *)
      err "Production HTTPS is not ready. Fix DNS/SSL planning first."
      echo "Helpful commands:"
      echo "  $(toolkit_cmd production-domain-plan)"
      echo "  $(toolkit_cmd production-ssl-plan)"
      return 1
      ;;
  esac

  ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not configured for production')"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"
  if [[ "$ssl_status" != "OK" ]]; then
    status_line "Production HTTPS" "$ssl_status" "$ssl_detail"
    warn "Production HTTPS is not fully verified yet. Complete SSL configuration before continuing production setup."
    return 1
  fi

  show_production_ssl_status || true
}

public_vm_guided_security_profile() {
  public_vm_guided_step "8" "Production security profile"
  echo "This applies the VM UFW production profile and then configures Fail2Ban for sshd."
  echo "Provider firewall restrictions still remain your cloud-provider responsibility."
  configure_production_vm_firewall || return 1
  configure_fail2ban || true
  show_fail2ban_status || true
  show_firewall_hardening_status || true
}

public_vm_guided_backups_and_operations() {
  public_vm_guided_step "9" "Scheduled backups and off-VM backup planning"
  configure_backup_schedule || true
  show_backup_schedule_status || true
  show_off_vm_backup_plan || true
  show_off_vm_backup_status || true
}

public_vm_guided_optional_apps() {
  public_vm_guided_step "10" "Optional apps"
  echo "Optional Frappe apps should be installed only after core ERPNext, HTTPS, backups, and security are healthy."
  if confirm "Open the optional app installer now?"; then
    run_app_install_wizard || true
  else
    echo "Skipped optional apps. You can run later: $(toolkit_cmd app-install-wizard)"
  fi
}

public_vm_guided_final_qa() {
  public_vm_guided_step "11" "Final QA and support bundle"
  show_production_checklist || true
  show_release_readiness || true
  verify_latest_backup_set || true
  create_support_bundle || true
  echo
  echo "External validation commands to run from your workstation/admin machine:"
  echo "  curl -I https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
  echo "  curl -I --connect-timeout 10 http://$(get_vm_ip 2>/dev/null || echo VM_IP):8000"
  echo "  curl -I --connect-timeout 10 http://$(get_vm_ip 2>/dev/null || echo VM_IP):9000"
  echo
  echo "Expected external result: HTTPS responds; 8000 and 9000 are blocked or unreachable."
  echo
  echo "Take a named post-validation provider snapshot now."
  echo "Recommended name: erpnext-toolkit-v${SCRIPT_VERSION}-post-production-validation"
  prompt_production_credential_handoff_if_needed
}

run_public_vm_guided_setup() {
  require_sudo
  install_self_for_reuse

  ui_box_start "Public VM Guided Setup"
  echo "This guided path keeps the Public VM menu available, but walks the production VPS flow in order."
  echo "Flow: domain -> DNS -> external firewall/snapshot gate -> install -> backup -> HTTPS -> security -> scheduled backups -> final QA."
  echo
  status_line "VM IPv4" "INFO" "$(get_vm_ip 2>/dev/null || echo unknown)"
  status_line "Production domain" "$([[ -n "${PRODUCTION_DOMAIN:-}" ]] && echo OK || echo WARN)" "${PRODUCTION_DOMAIN:-not set}"
  status_line "Site" "INFO" "$SITE_NAME"
  ui_box_end

  public_vm_guided_step "1" "Production domain"
  ensure_public_domain_configured || return 1

  public_vm_guided_step "2" "Requirements and production plan"
  show_production_domain_plan
  show_public_vm_readiness

  public_vm_guided_require_dns_ready || return 1
  public_vm_guided_external_gate || return 1
  public_vm_guided_install_core || return 1
  public_vm_guided_production_runtime || true
  public_vm_guided_backup_checkpoint || true
  public_vm_guided_configure_https || return 1
  public_vm_guided_security_profile || return 1
  public_vm_guided_backups_and_operations || true
  public_vm_guided_optional_apps || true
  public_vm_guided_final_qa || true

  echo
  ok "Public VM guided setup finished. Review any WARN rows before using this as production."
  prompt_open_main_menu_after_install
}

run_public_vm_quickstart() {
  require_sudo
  install_self_for_reuse

  while true; do
    ui_submenu_header "Public VM Quickstart" \
      "Requirements → domain → install → backup → HTTPS → security → apps → QA"
    public_quickstart_status_summary
    echo
    print_two_column_menu \
      "1) Setup lifecycle plan" \
      "2) Set/change domain" \
      "3) Check requirements + DNS" \
      "4) Install or repair ERPNext" \
      "5) Create backup checkpoint" \
      "6) Configure HTTPS" \
      "7) Security hardening" \
      "8) Optional apps" \
      "9) Final status / support bundle" \
      "10) SSL mode guide / setup steps"
    menu_footer
    menu_read_choice choice

    case "$choice" in
      1) show_setup_lifecycle_plan ;;
      2) prompt_and_save_public_domain ;;
      3) ensure_public_domain_configured && show_production_domain_plan && show_public_vm_readiness ;;
      4) ensure_public_domain_configured && run_guided_setup ;;
      5) public_quickstart_maybe_initial_backup ;;
      6) ensure_public_domain_configured && production_ssl_wizard ;;
      7) security_hardening_wizard ;;
      8) run_app_install_wizard ;;
      9) public_quickstart_final_status ;;
      10) show_ssl_mode_status; show_setup_effort_guide ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *)
        if menu_invalid_choice "$choice" "type b to go back or q to quit"; then :; else
          [[ $? -eq 2 ]] && return 0
        fi
        ;;
    esac
  done
}

run_first_run_wizard() {
  require_sudo

  while true; do
    ui_submenu_header "First Run / Setup Wizard" \
      "Choose setup type · non-secret settings are saved"
    status_line "Current site" "INFO" "${SITE_NAME} (${SITE_NAME_SOURCE})"
    status_line "Production domain" "$([[ -n "${PRODUCTION_DOMAIN:-}" ]] && echo OK || echo INFO)" "${PRODUCTION_DOMAIN:-not set}"
    status_line "Config" "INFO" "$CONFIG_FILE"
    echo
    print_two_column_menu \
      "1) Local development VM" \
      "2) Public VM / production-candidate" \
      "3) Existing install / maintenance menu" \
      "4) Show saved config" \
      "5) Setup lifecycle / SSL mode guide"
    menu_footer
    menu_read_choice choice

    case "$choice" in
      1) run_local_dev_quickstart ;;
      2) run_public_vm_guided_setup ;;
      3) show_menu ;;
      4) show_config_summary ;;
      5) show_setup_lifecycle_plan; show_setup_effort_guide; show_ssl_mode_guide ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *)
        if menu_invalid_choice "$choice" "type b to go back or q to quit"; then :; else
          [[ $? -eq 2 ]] && return 0
        fi
        ;;
    esac
  done
}
