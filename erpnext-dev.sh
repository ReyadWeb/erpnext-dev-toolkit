#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================
# ERPNext / Frappe Developer Toolkit Manager
# Target: Ubuntu 24.04 / 26.04 LTS developer VM
# Default: Frappe v16 + ERPNext v16 + site erp.test
# Mode: local development using bench start
# ============================================================

APP_NAME="ERPNext Developer Toolkit"
SCRIPT_VERSION="1.1.84"

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
APP_BACKUP_BEFORE_INSTALL="${APP_BACKUP_BEFORE_INSTALL:-prompt}"
APP_BACKUP_AFTER_INSTALL="${APP_BACKUP_AFTER_INSTALL:-prompt}"
FIREWALL_BACKUP_DIR="${FIREWALL_BACKUP_DIR:-/var/backups/erpnext-dev/firewall}"
ERPNEXT_SERVICE_NAME="${ERPNEXT_SERVICE_NAME:-erpnext-dev.service}"
READY_TIMEOUT="${READY_TIMEOUT:-90}"
READY_INTERVAL="${READY_INTERVAL:-5}"
CONFIG_FILE="${CONFIG_FILE:-/etc/erpnext-dev/config.env}"
LEGACY_CONFIG_FILE="${LEGACY_CONFIG_FILE:-${FRAPPE_HOME}/erpnext-dev-config.env}"

SSL_CERT_DIR="${SSL_CERT_DIR:-/etc/erpnext-dev-ssl}"
SSL_NGINX_CONF_DIR="${SSL_NGINX_CONF_DIR:-/etc/nginx}"
SSL_REDIRECT_HTTP="${SSL_REDIRECT_HTTP:-true}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
LETSENCRYPT_STAGING="${LETSENCRYPT_STAGING:-false}"
PRODUCTION_SSL_WEBROOT="${PRODUCTION_SSL_WEBROOT:-/var/www/erpnext-production-acme}"
CLOUDFLARE_ORIGIN_DIR="${CLOUDFLARE_ORIGIN_DIR:-/etc/ssl/cloudflare-origin}"
CLOUDFLARE_ORIGIN_CERT_FILE="${CLOUDFLARE_ORIGIN_CERT_FILE:-}"
CLOUDFLARE_ORIGIN_KEY_FILE="${CLOUDFLARE_ORIGIN_KEY_FILE:-}"

FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
ERPNEXT_BRANCH="${ERPNEXT_BRANCH:-version-16}"

NODE_VERSION="${NODE_VERSION:-24}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14}"

DB_ADMIN_USER="${DB_ADMIN_USER:-frappe_db_admin}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

ASSUME_YES=0
ACTION=""
DOCTOR_FORMAT="human"
# Default SUDO to an empty command prefix. Some read-only/status functions
# call helper routines before require_sudo() has initialized SUDO; with
# set -u enabled, leaving it unset can make those checks falsely fail.
SUDO="${SUDO:-}"

# Logging and locking are initialized centrally so every command path behaves
# the same way whether the toolkit is run as root, through sudo, or as a
# normal user. Keep defaults user-safe; callers may still override LOG_DIR,
# LOG_FILE, LOCK_DIR, or LOCK_FILE explicitly when needed.
LOG_DIR_WAS_SET=0
LOG_FILE_WAS_SET=0
LOCK_DIR_WAS_SET=0
LOCK_FILE_WAS_SET=0
[[ -n "${LOG_DIR+x}" ]] && LOG_DIR_WAS_SET=1
[[ -n "${LOG_FILE+x}" ]] && LOG_FILE_WAS_SET=1
[[ -n "${LOCK_DIR+x}" ]] && LOCK_DIR_WAS_SET=1
[[ -n "${LOCK_FILE+x}" ]] && LOCK_FILE_WAS_SET=1

if [[ "$LOG_DIR_WAS_SET" -eq 0 ]]; then
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    LOG_DIR="/var/log/erpnext-dev"
  else
    LOG_DIR="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/erpnext-dev/logs"
  fi
fi

if [[ "$LOCK_DIR_WAS_SET" -eq 0 ]]; then
  LOCK_DIR="/tmp/erpnext-dev-locks"
fi
if [[ "$LOCK_FILE_WAS_SET" -eq 0 ]]; then
  LOCK_FILE="${LOCK_DIR}/toolkit.lock"
fi

TOOLKIT_INSTALL_DIR="${TOOLKIT_INSTALL_DIR:-/opt/erpnext-dev}"
INSTALLER_CANONICAL_PATH="${INSTALLER_CANONICAL_PATH:-${TOOLKIT_INSTALL_DIR}/erpnext-dev.sh}"
TOOLKIT_CLI_PATH="${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev}"
BACKUP_SCHEDULE_SERVICE="${BACKUP_SCHEDULE_SERVICE:-erpnext-dev-backup.service}"
BACKUP_SCHEDULE_TIMER="${BACKUP_SCHEDULE_TIMER:-erpnext-dev-backup.timer}"
BACKUP_SCHEDULE_ON_CALENDAR="${BACKUP_SCHEDULE_ON_CALENDAR:-daily}"
BACKUP_SCHEDULE_RANDOM_DELAY="${BACKUP_SCHEDULE_RANDOM_DELAY:-30m}"
BACKUP_RETENTION_KEEP_COMPLETE="${BACKUP_RETENTION_KEEP_COMPLETE:-14}"
BACKUP_RETENTION_WARN_DISK_PERCENT="${BACKUP_RETENTION_WARN_DISK_PERCENT:-80}"
OFF_VM_BACKUP_CONFIG_FILE="${OFF_VM_BACKUP_CONFIG_FILE:-/etc/erpnext-dev/off-vm-backup.env}"
OFF_VM_BACKUP_STATE_FILE="${OFF_VM_BACKUP_STATE_FILE:-/etc/erpnext-dev/off-vm-backup.state}"
OFF_VM_BACKUP_TARGET="${OFF_VM_BACKUP_TARGET:-}"
OFF_VM_BACKUP_SSH_IDENTITY="${OFF_VM_BACKUP_SSH_IDENTITY:-}"
OFF_VM_BACKUP_DEFAULT_IDENTITY="${OFF_VM_BACKUP_DEFAULT_IDENTITY:-/root/.ssh/erpnext_offvm_backup}"
RESTORE_BACKUP_SSH_IDENTITY="${RESTORE_BACKUP_SSH_IDENTITY:-/root/.ssh/erpnext_restore_backup}"
RESTORE_PULL_CONFIG_FILE="${RESTORE_PULL_CONFIG_FILE:-/etc/erpnext-dev/restore-pull.env}"
RESTORE_REHEARSAL_RECORD_FILE="${RESTORE_REHEARSAL_RECORD_FILE:-/etc/erpnext-dev/restore-rehearsal.env}"
RESTORE_AUTHORIZED_KEYS_USER="${RESTORE_AUTHORIZED_KEYS_USER:-erpbackup}"
OFF_VM_BACKUP_RSYNC_DELETE="${OFF_VM_BACKUP_RSYNC_DELETE:-false}"
HEALTH_CHECK_SERVICE="${HEALTH_CHECK_SERVICE:-erpnext-dev-health-check.service}"
HEALTH_CHECK_TIMER="${HEALTH_CHECK_TIMER:-erpnext-dev-health-check.timer}"
HEALTH_CHECK_STATE_FILE="${HEALTH_CHECK_STATE_FILE:-/etc/erpnext-dev/health-check.state}"
HEALTH_CHECK_ON_CALENDAR="${HEALTH_CHECK_ON_CALENDAR:-hourly}"
HEALTH_CHECK_RANDOM_DELAY="${HEALTH_CHECK_RANDOM_DELAY:-10m}"
HEALTH_CHECK_DISK_WARN_PERCENT="${HEALTH_CHECK_DISK_WARN_PERCENT:-80}"
HEALTH_CHECK_BACKUP_MAX_AGE_HOURS="${HEALTH_CHECK_BACKUP_MAX_AGE_HOURS:-30}"
GO_LIVE_RECORD_FILE="${GO_LIVE_RECORD_FILE:-/etc/erpnext-dev/go-live-validation.env}"

# Hard safety gates for fresh installs. These are intentionally conservative because
# a too-small VM can leave a half-installed ERPNext stack, corrupt user expectations,
# or create an unstable service that is difficult for beginners to recover.
MIN_INSTALL_CPU_CORES="${MIN_INSTALL_CPU_CORES:-2}"
RECOMMENDED_INSTALL_CPU_CORES="${RECOMMENDED_INSTALL_CPU_CORES:-4}"
MIN_INSTALL_RAM_MB="${MIN_INSTALL_RAM_MB:-4096}"
RECOMMENDED_INSTALL_RAM_MB="${RECOMMENDED_INSTALL_RAM_MB:-8192}"
MIN_INSTALL_DISK_GB="${MIN_INSTALL_DISK_GB:-30}"
RECOMMENDED_INSTALL_DISK_GB="${RECOMMENDED_INSTALL_DISK_GB:-60}"
MIN_INSTALL_TMP_GB="${MIN_INSTALL_TMP_GB:-4}"
ERPNEXT_ALLOW_UNSAFE_INSTALL="${ERPNEXT_ALLOW_UNSAFE_INSTALL:-false}"

_ERPNEXT_DEV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/common.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/common.sh" >&2
  exit 1
fi
# shellcheck source=lib/common.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/common.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/support.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/support.sh" >&2
  exit 1
fi
# shellcheck source=lib/support.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/support.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/backup.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/backup.sh" >&2
  exit 1
fi
# shellcheck source=lib/backup.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/backup.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/ssl.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/ssl.sh" >&2
  exit 1
fi
# shellcheck source=lib/ssl.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/ssl.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/firewall.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/firewall.sh" >&2
  exit 1
fi
# shellcheck source=lib/firewall.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/firewall.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/apps.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/apps.sh" >&2
  exit 1
fi
# shellcheck source=lib/apps.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/apps.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/health.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/health.sh" >&2
  exit 1
fi
# shellcheck source=lib/health.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/health.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/storage.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/storage.sh" >&2
  exit 1
fi
# shellcheck source=lib/storage.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/storage.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/service.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/service.sh" >&2
  exit 1
fi
# shellcheck source=lib/service.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/service.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/install.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/install.sh" >&2
  exit 1
fi
# shellcheck source=lib/install.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/install.sh"
erpnext_dev_init_terminal_colors

prepare_log_file
exec > >(tee -a "$LOG_FILE") 2>&1

install_toolkit_cli_entry() {
  local dest cli_dir
  dest="${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"
  cli_dir="$(dirname "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev}")"
  mkdir -p "$cli_dir" 2>/dev/null || return 1
  ln -sf "$dest" "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev}" 2>/dev/null || return 1
  chmod 755 "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev}" 2>/dev/null || true
  return 0
}

install_self_for_reuse() {
  # One-command quickstart runs from a temporary /tmp bootstrap file. Copy the active
  # toolkit into /opt and expose the short erpnext-dev command for future use.
  local src dest src_root dest_root
  dest="${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"
  src="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
  [[ -n "$src" && -f "$src" ]] || return 0

  src_root="$(cd "$(dirname "$src")" && pwd)"
  dest_root="$(dirname "$dest")"
  mkdir -p "$dest_root" 2>/dev/null || true

  if [[ "$src" != "$dest" ]]; then
    if cp "$src" "$dest" 2>/dev/null; then
      chmod 755 "$dest" 2>/dev/null || true
      chown root:root "$dest" 2>/dev/null || true
    fi
  else
    chmod 755 "$dest" 2>/dev/null || true
    chown root:root "$dest" 2>/dev/null || true
  fi

  sync_toolkit_lib_tree "$src_root" "$dest_root" 2>/dev/null || warn "Could not copy toolkit lib/ tree to ${dest_root}/lib"

  install_toolkit_cli_entry 2>/dev/null || true
}


show_where_installed() {
  local src stable_state cli_state cli_target config_state
  src="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo unknown)"
  if [[ -x "${INSTALLER_CANONICAL_PATH}" ]]; then
    stable_state="OK"
  else
    stable_state="WARN"
  fi
  if [[ -x "${TOOLKIT_CLI_PATH}" ]]; then
    cli_state="OK"
    cli_target="$(readlink -f "${TOOLKIT_CLI_PATH}" 2>/dev/null || echo "${TOOLKIT_CLI_PATH}")"
  else
    cli_state="WARN"
    cli_target="not installed"
  fi
  if [[ -f "${CONFIG_FILE}" ]]; then
    config_state="OK"
  else
    config_state="INFO"
  fi

  ui_box_start "ERPNext Toolkit Installation"
  status_line "Version" "INFO" "${SCRIPT_VERSION}"
  status_line "Active script" "INFO" "${src}"
  status_line "Stable toolkit" "${stable_state}" "${INSTALLER_CANONICAL_PATH}"
  status_line "CLI command" "${cli_state}" "${TOOLKIT_CLI_PATH}${cli_target:+ -> ${cli_target}}"
  status_line "Config file" "${config_state}" "${CONFIG_FILE}"
  status_line "Short command" "INFO" "erpnext-dev"
  ui_box_end
}

find_toolkit_checksum_file() {
  local active_dir stable_dir candidate
  active_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")"
  stable_dir="$(dirname "${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}")"

  for candidate in \
    "${CHECKSUM_FILE:-}" \
    "${TOOLKIT_CHECKSUM_FILE:-}" \
    "./SHA256SUMS" \
    "${active_dir}/SHA256SUMS" \
    "${stable_dir}/SHA256SUMS" \
    "/opt/erpnext-dev/SHA256SUMS"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

checksum_expected_for_toolkit() {
  local checksum_file="$1"
  awk '
    $2 == "erpnext-dev.sh" { print $1; found=1; exit }
    $2 == "./erpnext-dev.sh" { print $1; found=1; exit }
    $2 ~ /\/erpnext-dev\.sh$/ { print $1; found=1; exit }
    END { if (!found) exit 1 }
  ' "$checksum_file"
}

verify_toolkit_integrity() {
  local active stable cli_target checksum_file expected active_hash stable_hash cli_hash match_state=0
  active="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  stable="${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"
  cli_target="$(readlink -f "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev}" 2>/dev/null || true)"

  ui_box_start "Verify ERPNext Toolkit Integrity"
  status_line "Toolkit version" "INFO" "${SCRIPT_VERSION}"
  status_line "Active script" "$([[ -f "$active" ]] && echo OK || echo WARN)" "$active"
  status_line "Stable toolkit" "$([[ -f "$stable" ]] && echo OK || echo WARN)" "$stable"
  if [[ -n "$cli_target" ]]; then
    status_line "CLI command" "OK" "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev} -> ${cli_target}"
  else
    status_line "CLI command" "WARN" "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev} not found"
  fi

  if ! command -v sha256sum >/dev/null 2>&1; then
    status_line "sha256sum" "FAIL" "sha256sum command not found"
    ui_box_end
    return 1
  fi

  if [[ -f "$active" ]]; then
    active_hash="$(sha256sum "$active" | awk '{print $1}')"
    status_line "Active SHA256" "INFO" "$active_hash"
  fi
  if [[ -f "$stable" ]]; then
    stable_hash="$(sha256sum "$stable" | awk '{print $1}')"
    status_line "Stable SHA256" "INFO" "$stable_hash"
  fi
  if [[ -n "$cli_target" && -f "$cli_target" ]]; then
    cli_hash="$(sha256sum "$cli_target" | awk '{print $1}')"
    status_line "CLI SHA256" "INFO" "$cli_hash"
  fi

  if checksum_file="$(find_toolkit_checksum_file 2>/dev/null)"; then
    status_line "Checksum file" "OK" "$checksum_file"
    if expected="$(checksum_expected_for_toolkit "$checksum_file" 2>/dev/null)"; then
      status_line "Expected SHA256" "INFO" "$expected"
      if [[ -n "${active_hash:-}" && "$active_hash" == "$expected" ]]; then
        status_line "Active match" "OK" "active script matches SHA256SUMS"
      else
        status_line "Active match" "FAIL" "active script does not match SHA256SUMS"
        match_state=1
      fi
      if [[ -n "${stable_hash:-}" ]]; then
        if [[ "$stable_hash" == "$expected" ]]; then
          status_line "Stable match" "OK" "stable toolkit matches SHA256SUMS"
        else
          status_line "Stable match" "WARN" "stable toolkit does not match SHA256SUMS"
        fi
      fi
      if [[ -n "${cli_hash:-}" ]]; then
        if [[ "$cli_hash" == "$expected" ]]; then
          status_line "CLI match" "OK" "CLI target matches SHA256SUMS"
        else
          status_line "CLI match" "WARN" "CLI target does not match SHA256SUMS"
        fi
      fi
    else
      status_line "Expected SHA256" "WARN" "no erpnext-dev.sh entry found in checksum file"
    fi
  else
    status_line "Checksum file" "WARN" "not found; download SHA256SUMS beside erpnext-dev.sh or set CHECKSUM_FILE=/path/SHA256SUMS"
  fi

  echo
  echo "Verified stable-path update example:"
  echo "  VERSION=\"v${SCRIPT_VERSION}\""
  echo '  workdir="$(mktemp -d /tmp/erpnext-dev-update.XXXXXX)"; cd "$workdir" || exit 1'
  echo '  curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/${VERSION}/erpnext-dev.sh"'
  echo '  curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/${VERSION}/SHA256SUMS"'
  echo "  sha256sum -c SHA256SUMS"
  echo "  sudo mkdir -p /opt/erpnext-dev"
  echo "  sudo install -m 0755 erpnext-dev.sh /opt/erpnext-dev/erpnext-dev.sh"
  echo "  sudo install -m 0644 SHA256SUMS /opt/erpnext-dev/SHA256SUMS"
  echo "  sudo ln -sf /opt/erpnext-dev/erpnext-dev.sh /usr/local/bin/erpnext-dev"
  echo "  sudo erpnext-dev verify-toolkit"
  ui_box_end
  return "$match_state"
}

install_toolkit_cli() {
  require_sudo
  install_self_for_reuse
  ui_box_start "Install ERPNext Toolkit CLI"
  if [[ -x "${INSTALLER_CANONICAL_PATH}" ]]; then
    status_line "Stable toolkit" "OK" "${INSTALLER_CANONICAL_PATH}"
  else
    status_line "Stable toolkit" "FAIL" "${INSTALLER_CANONICAL_PATH} missing"
    ui_box_end
    return 1
  fi

  if install_toolkit_cli_entry; then
    status_line "CLI command" "OK" "${TOOLKIT_CLI_PATH}"
    echo
    echo "You can now run:"
    echo "  erpnext-dev --help"
    echo "  sudo erpnext-dev menu"
  else
    status_line "CLI command" "FAIL" "could not create ${TOOLKIT_CLI_PATH}"
    ui_box_end
    return 1
  fi
  ui_box_end
}

repair_toolkit_cli() {
  install_toolkit_cli
}

update_toolkit() {
  require_sudo
  local url tmp lib_file lib_url lib_dest lib_dir cache_bust
  url="https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)"
  cache_bust="$(date +%s)"
  tmp="$(mktemp /tmp/erpnext-dev-update.XXXXXX.sh)" || fail "Could not create temporary update file."

  ui_box_start "Update ERPNext Toolkit"
  status_line "Download URL" "INFO" "$url"
  status_line "Temporary file" "INFO" "$tmp"
  status_line "Stable toolkit" "INFO" "$INSTALLER_CANONICAL_PATH"

  command -v curl >/dev/null 2>&1 || fail "curl is required. Install it with: sudo apt-get install -y curl ca-certificates"

  log "Downloading latest toolkit"
  curl -fsSL "$url" -o "$tmp" || fail "Failed to download latest toolkit."
  chmod +x "$tmp"
  bash -n "$tmp" || fail "Downloaded toolkit failed bash syntax validation."

  mkdir -p "$(dirname "$INSTALLER_CANONICAL_PATH")"
  cp "$tmp" "$INSTALLER_CANONICAL_PATH"
  chmod 755 "$INSTALLER_CANONICAL_PATH"
  chown root:root "$INSTALLER_CANONICAL_PATH" 2>/dev/null || true

  lib_dir="$(dirname "$INSTALLER_CANONICAL_PATH")/lib"
  mkdir -p "$lib_dir"
  for lib_file in common.sh support.sh backup.sh ssl.sh firewall.sh apps.sh health.sh storage.sh service.sh install.sh; do
    lib_url="https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/lib/${lib_file}?cache_bust=${cache_bust}"
    lib_dest="${lib_dir}/${lib_file}"
    if curl -fsSL "$lib_url" -o "$lib_dest"; then
      chmod 644 "$lib_dest" 2>/dev/null || true
      chown root:root "$lib_dest" 2>/dev/null || true
      status_line "Library ${lib_file}" "OK" "$lib_dest"
    else
      status_line "Library ${lib_file}" "WARN" "could not download lib/${lib_file}"
    fi
  done

  install_toolkit_cli_entry || fail "Updated toolkit, but failed to recreate ${TOOLKIT_CLI_PATH}."

  ok "Toolkit updated."
  "$INSTALLER_CANONICAL_PATH" version
  ui_box_end
}

is_public_vm_workflow() {
  [[ "${DEPLOYMENT_MODE:-}" == "public-vm" ]] && return 0
  [[ -n "${PRODUCTION_DOMAIN:-}" ]] && return 0
  return 1
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

  # Public/production-domain workflows intentionally use real hostnames.
  # Keep this quiet there so small terminals are not filled with repeated
  # local-development warnings.
  if [[ "$name" != *.test ]]; then
    if [[ -n "${PRODUCTION_DOMAIN:-}" || "${DEPLOYMENT_MODE:-development}" != "development" ]]; then
      return 0
    fi
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

  # Older installs may have been created before public-vm onboarding existed.
  # If a real production domain is saved, treat the current session as a
  # public VM workflow even if the saved mode still says development.
  if [[ "${DEPLOYMENT_MODE}" == "development" ]] \
    && [[ -n "${PRODUCTION_DOMAIN:-}" ]] \
    && validate_production_domain_value "$PRODUCTION_DOMAIN" >/dev/null 2>&1; then
    DEPLOYMENT_MODE="public-vm"
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

choose_local_site_name_for_setup() {
  local reply normalized default_name

  if [[ "$SITE_NAME_ENV_PROVIDED" -eq 1 ]]; then
    validate_site_name_value "$SITE_NAME" || fail "Invalid SITE_NAME override."
    SITE_NAME="${SITE_NAME,,}"
    SITE_NAME_SOURCE="environment"
    maybe_warn_site_name "$SITE_NAME"
    echo "Using local VM domain: ${SITE_NAME}"
    return 0
  fi

  default_name="${SITE_NAME:-erp.test}"
  if [[ -z "$default_name" || "$default_name" != *.test ]]; then
    default_name="erp.test"
  fi

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    while true; do
      echo
      read -r -p "Local VM domain / Frappe site name [${default_name}]: " reply
      reply="${reply:-$default_name}"
      normalized="${reply,,}"

      if validate_site_name_value "$normalized" >/dev/null 2>&1; then
        SITE_NAME="$normalized"
        SITE_NAME_SOURCE="setup prompt"
        maybe_warn_site_name "$SITE_NAME"
        echo "Using local VM domain: ${SITE_NAME}"
        return 0
      fi

      echo "Invalid site name. Use a hostname like erp.test, school.test, or client-a.test. Do not include http://, ports, spaces, or slashes."
    done
  else
    SITE_NAME="$default_name"
    SITE_NAME_SOURCE="local quickstart"
    validate_site_name_value "$SITE_NAME" || fail "Invalid local VM domain."
    echo "Using local VM domain: ${SITE_NAME}"
  fi
}


change_local_domain_wizard() {
  require_sudo

  local bench_dir old_site new_site reply normalized vm_ip site_exists_flag service_was_active old_available old_enabled old_cert old_key maybe_rebuild_ssl
  local -a _local_ssl_paths
  bench_dir="$(active_bench_dir)"
  old_site="$SITE_NAME"
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  site_exists_flag="no"
  service_was_active="no"
  maybe_rebuild_ssl="no"

  if [[ -d "${bench_dir}/sites/${old_site}" ]]; then
    site_exists_flag="yes"
  fi

  readarray -t _local_ssl_paths < <(local_ssl_paths_for_site "$old_site")
  old_available="${_local_ssl_paths[0]:-}"
  old_enabled="${_local_ssl_paths[1]:-}"
  old_cert="${_local_ssl_paths[2]:-}"
  old_key="${_local_ssl_paths[3]:-}"

  echo
  echo "============================================================"
  echo "Change Local VM Domain / Site Name"
  echo "============================================================"
  status_line "Current local site" "INFO" "$old_site"
  status_line "Bench" "INFO" "$bench_dir"
  status_line "Site folder" "$([[ "$site_exists_flag" == yes ]] && echo OK || echo WARN)" "$([[ "$site_exists_flag" == yes ]] && echo present || echo not-found/config-only)"
  status_line "VM IP" "INFO" "$vm_ip"
  echo
  echo "Use a .test name for local VM work, for example: erp.test, erpnext.test, school.test."
  echo "Press Enter to keep the current value."
  echo

  while true; do
    if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
      read -r -p "New local VM domain [${old_site}]: " reply || reply=""
      reply="${reply:-$old_site}"
    else
      reply="$old_site"
    fi
    normalized="${reply,,}"

    if validate_site_name_value "$normalized" >/dev/null 2>&1; then
      new_site="$normalized"
      break
    fi
    echo "Invalid site name. Use a hostname only, for example erpnext.test."
  done

  if [[ "$new_site" == "$old_site" ]]; then
    ok "No change needed. Local site is already ${old_site}."
    show_site_config
    return 0
  fi

  if [[ "$new_site" != *.test ]]; then
    warn "For local VM work, .test is strongly recommended. Selected: ${new_site}"
    if ! confirm "Continue with ${new_site}?"; then
      fail "Local domain change cancelled."
    fi
  fi

  if [[ -d "${bench_dir}/sites/${new_site}" ]]; then
    fail "Target site already exists: ${bench_dir}/sites/${new_site}"
  fi

  echo
  echo "Planned change:"
  status_line "Old local site" "INFO" "$old_site"
  status_line "New local site" "INFO" "$new_site"
  if [[ "$site_exists_flag" == yes ]]; then
    status_line "Frappe action" "INFO" "bench rename-site"
    status_line "Backup" "INFO" "database + files before rename"
  else
    status_line "Frappe action" "INFO" "config-only; no site folder found"
  fi
  status_line "Host mapping" "INFO" "update HOST /etc/hosts after this finishes"
  echo

  if [[ "$ASSUME_YES" -ne 1 ]]; then
    if ! confirm "Apply this local domain change now?"; then
      fail "Local domain change cancelled."
    fi
  fi

  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    service_was_active="yes"
    log "Stopping ERPNext service before site rename"
    $SUDO systemctl stop "${ERPNEXT_SERVICE_NAME}" || warn "Could not stop ${ERPNEXT_SERVICE_NAME}; continuing carefully."
  fi

  if [[ "$site_exists_flag" == yes ]]; then
    log "Creating safety backup for ${old_site}"
    run_as_frappe "cd '${bench_dir}' && bench --site '${old_site}' backup --with-files" || warn "Backup command did not complete cleanly. Check Bench logs before relying on this backup."

    log "Renaming Frappe site from ${old_site} to ${new_site}"
    if ! run_as_frappe "cd '${bench_dir}' && if bench rename-site --help 2>&1 | grep -q -- '--force'; then bench rename-site --force '${old_site}' '${new_site}'; else bench rename-site '${old_site}' '${new_site}'; fi"; then
      if [[ "$service_was_active" == yes ]]; then
        $SUDO systemctl start "${ERPNEXT_SERVICE_NAME}" || true
      fi
      fail "bench rename-site failed. The toolkit config was not changed. Review the output above."
    fi

    log "Updating Bench default site"
    run_as_frappe "cd '${bench_dir}' && bench use '${new_site}' && bench set-config -g default_site '${new_site}' && bench set-config -g serve_default_site true" || warn "Could not update Bench default site automatically."
  fi

  SITE_NAME="$new_site"
  SITE_NAME_SOURCE="domain change wizard"
  DEPLOYMENT_MODE="development"
  PRODUCTION_DOMAIN=""
  PRODUCTION_SSL_MODE="planned"
  write_dev_config_file
  SITE_NAME_SOURCE="saved config"

  if [[ -n "$old_enabled" && -e "$old_enabled" ]]; then
    log "Disabling old local SSL Nginx site for ${old_site}"
    $SUDO rm -f "$old_enabled" || true
    maybe_rebuild_ssl="yes"
  fi

  if [[ -n "$old_available" && -e "$old_available" ]]; then
    $SUDO mv "$old_available" "${old_available}.disabled.$(date +%Y%m%d_%H%M%S)" || true
  fi

  if command -v nginx >/dev/null 2>&1; then
    $SUDO nginx -t >/dev/null 2>&1 && $SUDO systemctl reload nginx || true
  fi

  if [[ "$service_was_active" == yes ]]; then
    log "Starting ERPNext service after site rename"
    $SUDO systemctl start "${ERPNEXT_SERVICE_NAME}" || warn "Could not restart ${ERPNEXT_SERVICE_NAME}. Run: $(toolkit_cmd start)"
  fi

  ok "Local VM domain changed to ${SITE_NAME}"
  echo
  echo "Run this on your HOST machine, not inside the VM:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test from the HOST:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"

  if [[ "$maybe_rebuild_ssl" == yes || -f "$old_cert" || -f "$old_key" ]]; then
    echo
    warn "Local SSL certificates are domain-specific. Rebuild local SSL for ${SITE_NAME}."
    echo "Recommended next command:"
    echo "  $(toolkit_cmd local-ssl-wizard)"
  fi

  echo
  show_site_config
}

write_dev_config_file() {
  require_sudo

  log "Writing ERPNext developer config"

  local config_dir legacy_dir
  config_dir="$(dirname "$CONFIG_FILE")"
  legacy_dir="$(dirname "$LEGACY_CONFIG_FILE")"

  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$CONFIG_FILE" >/dev/null <<EOF_DEV_CONFIG
# ERPNext Developer Toolkit local configuration
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
# ERPNext Developer Toolkit local configuration
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
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "To choose a custom site during a fresh setup:"
  echo "  $(toolkit_cmd_env "SITE_NAME=erp107.test" setup)"
  echo
  echo "Or run setup interactively and answer the site-name prompt."
  echo
  echo "To change the local domain after install:"
  echo "  $(toolkit_cmd change-local-domain)"
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
  echo "  $(toolkit_cmd_env "SITE_NAME=erp107.test" setup)"
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
  echo
  echo "To rename an existing local site automatically:"
  echo "  $(toolkit_cmd change-local-domain)"
  echo "============================================================"
}

load_saved_config_if_available
load_future_domain_config_if_available



show_access_when_ready() {
  if port_listens 8000; then
    show_access_instructions
  else
    warn "Browser access was not shown because web port 8000 is not listening yet."
    echo "Run this after a few seconds:"
    echo "  $(toolkit_cmd runtime-status)"
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
  if is_public_vm_workflow; then
    if ssl_is_configured 2>/dev/null && port_listens 443; then
      echo "Production HTTPS URLs:"
      echo "  Desk:         https://${SITE_NAME}/app"
      echo "  Login:        https://${SITE_NAME}/login"
      echo "  Website/root: https://${SITE_NAME}"
    else
      echo "Production HTTPS is not configured yet. Continue the guided production setup to enable:"
      echo "  https://${SITE_NAME}"
    fi
    echo
    echo "Backend validation URLs, for troubleshooting only:"
    echo "  Direct IP:    http://${vm_ip}:8000"
    echo "  Domain :8000: http://${SITE_NAME}:8000"
    echo "Production note: public access to ports 8000 and 9000 should be blocked by the cloud firewall and UFW after hardening."
  else
    if ssl_is_configured 2>/dev/null && port_listens 443; then
      echo "Open these HTTPS URLs from the HOST after /etc/hosts is set:"
      echo "  Desk:         https://${SITE_NAME}/app"
      echo "  Login:        https://${SITE_NAME}/login"
      echo "  Website/root: https://${SITE_NAME}"
      echo
      echo "Direct Bench fallback, useful for troubleshooting:"
      echo "  Direct IP:    http://${vm_ip}:8000"
      echo "  Friendly URL: http://${SITE_NAME}:8000"
    else
      echo "Open one of these URLs:"
      echo "  Direct IP:    http://${vm_ip}:8000"
      echo "  Friendly URL: http://${SITE_NAME}:8000"
    fi
    echo
    echo "Friendly URL note: your HOST /etc/hosts must map ${SITE_NAME} to ${vm_ip}."
  fi
  echo "For full access instructions, run: $(toolkit_cmd access)"
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
  err "Run Recommended Setup first, or run: $(toolkit_cmd install-status)"
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
    echo "  $(toolkit_cmd ssl-status)"
    echo "  $(toolkit_cmd configure-local-ssl)"
    echo "  $(toolkit_cmd install-local-ssl-cert)"
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
  echo "To avoid changing the Linux HOST by mistake, the command was blocked before sudo work."
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
  echo "  $(toolkit_cmd "${action}")"
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
  echo "  $(toolkit_cmd environment-check)"
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




frappe_shell_prefix() {
  # Keep this as a semicolon-separated single line.
  # Some sudo/su command paths can collapse multiline command substitution, which breaks
  # constructs like: export NVM_DIR=...if [ -s ... ]. Semicolons make the prefix robust.
  cat <<'EOF_PREFIX'
export PATH="$HOME/.local/bin:$PATH"; export NVM_DIR="$HOME/.nvm"; if [ -s "$NVM_DIR/nvm.sh" ]; then . "$NVM_DIR/nvm.sh"; fi; if command -v node >/dev/null 2>&1; then export PATH="$(dirname "$(command -v node)"):$PATH"; fi;
EOF_PREFIX
}

frappe_login_bash() {
  # Read a Bash script from stdin and execute it as the frappe user.
  # This must work both when the toolkit is run as root and when it is run
  # by a sudo-capable non-root user. Do not prefix sudo options with an empty
  # $SUDO value; root would otherwise try to execute "-H" as a command.
  if [[ "${EUID}" -eq 0 ]]; then
    su - "$FRAPPE_USER" -s /bin/bash
  else
    sudo -H -u "$FRAPPE_USER" bash
  fi
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
    printf '%s\n' "$cmd"
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

run_as_frappe_quiet() {
  local label="$1"
  local cmd="$2"
  local safe_label output_file fallback_dir rc

  safe_label="$(printf '%s' "$label" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9_.-')"
  [[ -n "$safe_label" ]] || safe_label="command"

  output_file="$(mktemp "${LOG_DIR}/erpnext-dev-${safe_label}.XXXXXX.log" 2>/dev/null || true)"
  if [[ -z "$output_file" ]]; then
    fallback_dir="/tmp/erpnext-dev-${EUID:-$(id -u)}-logs"
    mkdir -p "$fallback_dir" 2>/dev/null || true
    chmod 700 "$fallback_dir" 2>/dev/null || true
    output_file="$(mktemp "${fallback_dir}/erpnext-dev-${safe_label}.XXXXXX.log")" || return 1
  fi
  chmod 600 "$output_file" 2>/dev/null || true

  echo "  Output log: ${output_file}"
  if run_as_frappe "$cmd" >"$output_file" 2>&1; then
    return 0
  fi

  rc=$?
  warn "${label} failed. Last 80 lines from ${output_file}:"
  tail -n 80 "$output_file" 2>/dev/null | sed 's/^/  /' || true
  return "$rc"
}






valid_ipv4_address() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=. a b c d
  read -r a b c d <<< "$ip"
  for octet in "$a" "$b" "$c" "$d"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( octet >= 0 && octet <= 255 )) || return 1
  done
  return 0
}

is_usable_vm_ip() {
  local ip="$1"
  valid_ipv4_address "$ip" || return 1
  case "$ip" in
    127.*|169.254.*|0.*) return 1 ;;
    *) return 0 ;;
  esac
}

get_vm_ip() {
  # Do not hardcode the local VM network. Users may be on KVM default NAT
  # (192.168.122.x), VirtualBox/UTM-style NAT (10.x), a bridged LAN address,
  # or a cloud/public interface. Prefer the source IP chosen by the kernel for
  # outbound routing, then fall back to the primary interface address and then
  # the first usable address from hostname -I.
  local candidate="" token="" iface=""
  local IFS=$' \t\n'

  if [[ -n "${VM_IP:-}" ]] && is_usable_vm_ip "$VM_IP"; then
    printf '%s\n' "$VM_IP"
    return 0
  fi

  candidate="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  if is_usable_vm_ip "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}' || true)"
  if [[ -n "$iface" ]]; then
    candidate="$(ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk '{sub(/\/.*$/, "", $4); print $4; exit}' || true)"
    if is_usable_vm_ip "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for token in $(hostname -I 2>/dev/null || true); do
    if is_usable_vm_ip "$token"; then
      printf '%s\n' "$token"
      return 0
    fi
  done

  # Keep callers from printing an empty value; verification will still fail clearly.
  printf '%s\n' "unknown"
}

curl_head_status() {
  local url="${1:-}"
  local host_name="${2:-}"
  local port="${3:-}"
  local resolve_ip="${4:-}"
  local curl_args=()

  [[ -n "$url" ]] || return 1

  curl_args=(-k -sS -I --max-time 10)

  if [[ -n "$host_name" && -n "$port" && -n "$resolve_ip" ]]; then
    curl_args+=(--resolve "${host_name}:${port}:${resolve_ip}")
  fi

  curl "${curl_args[@]}" "$url" 2>/dev/null | awk 'NR==1 {print; exit}' || true
}

escape_hosts_regex() {
  printf '%s' "$1" | sed 's/[.[\*^$()+?{}|]/\\&/g'
}

print_host_dns_commands_for_site() {
  local site="${1:-$SITE_NAME}" vm_ip="${2:-}"
  local escaped_site
  vm_ip="${vm_ip:-$(get_vm_ip)}"
  escaped_site="$(escape_hosts_regex "$site")"

  echo "  VM_IP=\"${vm_ip}\""
  echo "  LOCAL_DOMAIN=\"${site}\""
  echo "  sudo cp /etc/hosts \"/etc/hosts.bak.\$(date +%Y%m%d-%H%M%S)\""
  echo "  sudo sed -i \"/[[:space:]]${escaped_site}\\([[:space:]]\\|$\\)/d\" /etc/hosts"
  echo "  echo \"\${VM_IP} \${LOCAL_DOMAIN}\" | sudo tee -a /etc/hosts"
}

print_host_dns_tests_for_site() {
  local site="${1:-$SITE_NAME}" vm_ip="${2:-}"
  vm_ip="${vm_ip:-$(get_vm_ip)}"
  echo "  getent hosts ${site}"
  if [[ "$vm_ip" != "unknown" && -n "$vm_ip" ]]; then
    echo "  curl -I http://${vm_ip}:8000"
  else
    echo "  curl -I http://\${VM_IP}:8000"
  fi
  echo "  curl -I http://${site}:8000"
  if port_listens 443; then
    echo "  curl -kI https://${site}"
  fi
}

show_local_domain_status() {
  require_sudo
  local vm_ip bench_dir detected_network
  vm_ip="$(get_vm_ip)"
  bench_dir="$(active_bench_dir 2>/dev/null || printf '%s' "$BENCH_DIR")"

  if [[ "$vm_ip" == 192.168.122.* ]]; then
    detected_network="KVM/libvirt default NAT"
  elif [[ "$vm_ip" == 10.* || "$vm_ip" == 172.* || "$vm_ip" == 192.168.* ]]; then
    detected_network="private NAT/LAN/bridged network"
  elif [[ "$vm_ip" == unknown ]]; then
    detected_network="unknown"
  else
    detected_network="public or routed interface"
  fi

  echo
  echo "============================================================"
  echo "Local Domain / Host DNS Status"
  echo "============================================================"
  status_line "Local domain" "INFO" "$SITE_NAME"
  status_line "VM IP" "$([[ "$vm_ip" != unknown ]] && echo OK || echo WARN)" "$vm_ip"
  status_line "Network type" "INFO" "$detected_network"
  status_line "Bench" "INFO" "$bench_dir"
  status_line "Direct URL" "INFO" "http://${vm_ip}:8000"
  status_line "Friendly URL" "INFO" "http://${SITE_NAME}:8000"
  echo
  echo "Important: ${SITE_NAME} is a local-only name. It is not public DNS."
  echo "Your HOST machine must map ${SITE_NAME} to the current VM IP."
  echo "The IP is detected dynamically; do not copy someone else's 192.168.122.x value."
  echo
  echo "Run this on the HOST machine, not inside the VM:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test from the HOST machine:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo "============================================================"
}

show_host_dns_guide() {
  show_local_domain_status
}

show_local_host_mapping_checkpoint() {
  require_sudo

  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Required Local Host Mapping Checkpoint"
  echo "============================================================"
  echo
  echo "Before using the friendly local URL or configuring local HTTPS,"
  echo "make sure your HOST machine maps this local domain to the current VM IP."
  echo
  status_line "Local domain" "INFO" "$SITE_NAME"
  status_line "Detected VM IP" "$([[ "$vm_ip" != unknown ]] && echo OK || echo WARN)" "$vm_ip"
  echo
  echo "Run this on your HOST machine, not inside this VM."
  echo "It is safe to repeat: it backs up /etc/hosts, removes only the old ${SITE_NAME} entry, then adds the current mapping."
  echo
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test from the HOST machine:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Run this checkpoint whenever:"
  echo "  - You create a fresh local VM"
  echo "  - You delete and recreate the VM"
  echo "  - The VM gets a new DHCP IP"
  echo "  - ${SITE_NAME} opens the wrong VM or stops resolving"
  echo
  echo "After the HTTP test works, continue with:"
  echo "  $(toolkit_cmd local-ssl-wizard)"
  echo "============================================================"
}

local_access_doctor() {
  require_sudo
  local vm_ip direct_head site_head ip_head gateway
  vm_ip="$(get_vm_ip)"
  gateway="$(get_default_gateway 2>/dev/null || true)"

  echo
  echo "============================================================"
  echo "Local Access Doctor"
  echo "============================================================"
  status_line "Local domain" "INFO" "$SITE_NAME"
  status_line "Detected VM IP" "$([[ "$vm_ip" != unknown ]] && echo OK || echo WARN)" "$vm_ip"
  status_line "Default gateway" "INFO" "${gateway:-unknown}"

  if port_listens 8000; then
    status_line "Bench web port" "OK" "8000 listening"
  else
    status_line "Bench web port" "WARN" "8000 is not listening; start ERPNext service or bench"
  fi

  if port_listens 9000; then
    status_line "Socket.IO port" "OK" "9000 listening"
  else
    status_line "Socket.IO port" "INFO" "9000 not listening"
  fi

  direct_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  site_head="$(curl_head_status "http://${SITE_NAME}:8000/" "$SITE_NAME" 8000 "127.0.0.1" || true)"
  ip_head="$(curl_head_status "http://${vm_ip}:8000/" "" "" "" || true)"

  [[ "$direct_head" == HTTP/* ]] && status_line "Inside VM direct HTTP" "OK" "$direct_head" || status_line "Inside VM direct HTTP" "WARN" "no response from 127.0.0.1:8000"
  [[ "$site_head" == HTTP/* ]] && status_line "Inside VM Host header" "OK" "$site_head" || status_line "Inside VM Host header" "WARN" "no response for ${SITE_NAME} host header"
  [[ "$ip_head" == HTTP/* ]] && status_line "Inside VM IP HTTP" "OK" "$ip_head" || status_line "Inside VM IP HTTP" "INFO" "no response from ${vm_ip}:8000 inside VM"

  if command -v ufw >/dev/null 2>&1; then
    status_line "UFW status" "INFO" "$(ufw status 2>/dev/null | head -n 1 | sed 's/^Status: //' || echo unknown)"
  fi

  echo
  echo "If the HOST shows 'Could not resolve host: ${SITE_NAME}', that is host DNS mapping."
  echo "Fix it on the HOST machine with the dynamic command below:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "HOST-side tests:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "If direct IP works but ${SITE_NAME} fails, the fix is /etc/hosts on the HOST."
  echo "If both direct IP and ${SITE_NAME} fail, run:"
  echo "  $(toolkit_cmd repair-local-access)"
  echo "  $(toolkit_cmd verify-access)"
  echo "============================================================"
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
  echo "  $(toolkit_cmd start)"
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
  echo "Run this on your Linux HOST machine, not inside the VM:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test on the host:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "If ${SITE_NAME} still does not open, use the direct IP URL first:"
  echo "  http://${vm_ip}:8000"
  echo
  echo "============================================================"
}




verify_access() {
  require_sudo

  local vm_ip escaped_site direct_head friendly_head ip_head https_head
  vm_ip="$(get_vm_ip)"
  escaped_site="${SITE_NAME//./\\.}"

  echo
  echo "============================================================"
  echo "Access Verification"
  echo "============================================================"

  if port_listens 8000; then
    status_line "Bench web" "OK" "127.0.0.1:8000 listening"
  else
    status_line "Bench web" "WARN" "127.0.0.1:8000 not listening"
  fi

  if port_listens 9000; then
    status_line "Socket.io" "OK" "127.0.0.1:9000 listening"
  else
    status_line "Socket.io" "INFO" "127.0.0.1:9000 not listening"
  fi

  direct_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  friendly_head="$(curl_head_status "http://${SITE_NAME}:8000/" "$SITE_NAME" 8000 "127.0.0.1" || true)"
  ip_head="$(curl_head_status "http://${vm_ip}:8000/" "" "" "" || true)"

  if [[ "$direct_head" == HTTP/* ]]; then
    status_line "Local direct HTTP" "OK" "$direct_head"
  else
    status_line "Local direct HTTP" "WARN" "no response from http://127.0.0.1:8000"
  fi

  if [[ "$friendly_head" == HTTP/* ]]; then
    status_line "Local site HTTP" "OK" "$friendly_head"
  else
    status_line "Local site HTTP" "WARN" "no response using ${SITE_NAME} host header"
  fi

  if [[ "$ip_head" == HTTP/* ]]; then
    status_line "VM IP HTTP" "OK" "$ip_head"
  else
    status_line "VM IP HTTP" "INFO" "host-side test may still work if networking is correct"
  fi

  if port_listens 443; then
    https_head="$(curl_head_status "https://${SITE_NAME}/" "$SITE_NAME" 443 "127.0.0.1" || true)"
    [[ "$https_head" == HTTP/* ]] && status_line "Local HTTPS" "OK" "$https_head" || status_line "Local HTTPS" "WARN" "port 443 listens, but HTTPS did not respond cleanly"
  else
    status_line "Local HTTPS" "INFO" "not configured yet"
  fi

  echo
  if is_public_vm_workflow; then
    echo "Production URL:"
    echo "  https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo
    echo "Backend port note:"
    echo "  8000 and 9000 may listen inside the VM, but should be blocked publicly."
    echo
    echo "Workstation tests:"
    echo "  curl -I https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo "  curl -I --connect-timeout 10 http://${vm_ip}:8000"
    echo "  curl -I --connect-timeout 10 http://${vm_ip}:9000"
  else
    echo "Open from the HOST after /etc/hosts is set:"
    echo "  http://${vm_ip}:8000"
    echo "  http://${SITE_NAME}:8000"
    echo
    echo "HOST /etc/hosts command:"
    print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
    echo
    echo "HOST tests:"
    print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  fi

  echo
  echo "Important browser paths:"
  if is_public_vm_workflow; then
    echo "  Desk:  https://${PRODUCTION_DOMAIN:-$SITE_NAME}/app"
    echo "  Login: https://${PRODUCTION_DOMAIN:-$SITE_NAME}/login"
  else
    echo "  Desk:  http://${vm_ip}:8000/app"
    echo "  Login: http://${vm_ip}:8000/login"
  fi

  if site_app_installed education; then
    print_education_access_note
  fi

  echo "============================================================"
}

print_primary_access_urls() {
  local vm_ip base
  vm_ip="$(get_vm_ip)"

  if is_public_vm_workflow; then
    base="https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo "Primary URLs:"
    echo "  Website / portal root: ${base}"
    echo "  ERPNext / Frappe Desk: ${base}/app"
    echo "  Login page:            ${base}/login"
  else
    echo "Primary URLs from the HOST:"
    echo "  Website / portal root: http://${vm_ip}:8000"
    echo "  ERPNext / Frappe Desk: http://${vm_ip}:8000/app"
    echo "  Login page:            http://${vm_ip}:8000/login"
    echo
    echo "Friendly local URLs after /etc/hosts is set:"
    echo "  Website / portal root: http://${SITE_NAME}:8000"
    echo "  ERPNext / Frappe Desk: http://${SITE_NAME}:8000/app"
    echo "  Login page:            http://${SITE_NAME}:8000/login"
  fi
}

print_education_access_note() {
  local vm_ip base
  vm_ip="$(get_vm_ip)"

  echo
  warn "Education access note"
  echo "  Education can make the normal website root open the Education portal."
  echo "  This is expected after installing the Education app."
  echo "  Use /app for ERPNext/Frappe Desk and /login for the login page."
  echo

  if is_public_vm_workflow; then
    base="https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo "Education-aware URLs:"
    echo "  ERPNext / Frappe Desk: ${base}/app"
    echo "  Login page:            ${base}/login"
    echo "  Education portal:      ${base}/edu-portal/students"
  else
    echo "Education-aware direct URLs:"
    echo "  ERPNext / Frappe Desk: http://${vm_ip}:8000/app"
    echo "  Login page:            http://${vm_ip}:8000/login"
    echo "  Education portal:      http://${vm_ip}:8000/edu-portal/students"
    echo
    echo "Education-aware friendly URLs after /etc/hosts is set:"
    echo "  ERPNext / Frappe Desk: http://${SITE_NAME}:8000/app"
    echo "  Login page:            http://${SITE_NAME}:8000/login"
    echo "  Education portal:      http://${SITE_NAME}:8000/edu-portal/students"
  fi
}

show_access_info() {
  require_sudo

  echo
  echo "============================================================"
  echo "Access Information"
  echo "============================================================"
  print_primary_access_urls

  if site_app_installed education; then
    print_education_access_note
  fi

  echo
  echo "Useful checks:"
  echo "  $(toolkit_cmd verify-access)"
  echo "  $(toolkit_cmd doctor)"
  echo "============================================================"
}

show_education_access_info() {
  require_sudo

  echo
  echo "============================================================"
  echo "Education Access Information"
  echo "============================================================"
  print_education_access_note
  echo
  echo "If /app fails, run:"
  echo "  $(toolkit_cmd service-restart)"
  echo "  $(toolkit_cmd wait-ready)"
  echo "  $(toolkit_cmd doctor)"
  echo "============================================================"
}

show_next_step() {
  require_sudo

  local vm_ip installed runtime auto data can_expand storage_reason storage_state ssl_state next_label next_command
  vm_ip="$(get_vm_ip)"
  installed="$(install_state 2>/dev/null || echo "Not installed")"
  runtime="$(runtime_state 2>/dev/null || echo "Stopped")"
  auto="$(autostart_state 2>/dev/null || echo "Not configured")"
  data="$(storage_eval 2>/dev/null || true)"
  can_expand="$(printf '%s\n' "$data" | awk -F= '$1=="CAN_EXPAND" {print $2; exit}')"
  storage_reason="$(printf '%s\n' "$data" | awk -F= '$1=="REASON" {print $2; exit}')"
  storage_state="OK"
  ssl_state="not configured"

  if [[ "${can_expand:-no}" == "yes" ]]; then
    storage_state="recommended"
  elif [[ -z "${can_expand:-}" ]]; then
    storage_state="unknown"
  fi

  if ssl_is_configured 2>/dev/null; then
    ssl_state="configured"
  fi

  if is_public_vm_workflow; then
    local prod_ssl_pair prod_ssl_status prod_ssl_detail backup_lines backup_complete
    prod_ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not configured for production')"
    prod_ssl_status="${prod_ssl_pair%%|*}"
    prod_ssl_detail="${prod_ssl_pair#*|}"
    backup_lines="$(backup_latest_set_paths 2>/dev/null || true)"
    backup_complete="$(printf '%s\n' "$backup_lines" | sed -n '6p')"

    echo
    echo "============================================================"
    echo "Next Step"
    echo "============================================================"
    status_line "Storage" "INFO" "${storage_state}${storage_reason:+ - ${storage_reason}}"
    status_line "Install" "INFO" "$installed"
    status_line "Runtime" "INFO" "$runtime"
    status_line "Autostart" "INFO" "$auto"
    status_line "Production SSL" "$prod_ssl_status" "$prod_ssl_detail"
    status_line "Latest backup" "$([[ "$backup_complete" == complete ]] && echo OK || echo WARN)" "${backup_complete:-none}"
    echo

    if [[ "${can_expand:-no}" == "yes" ]]; then
      next_label="expand root storage"
      next_command="$(toolkit_cmd expand-root-storage)"
    elif [[ "$installed" != "Installed" ]]; then
      next_label="run public quickstart install"
      next_command="$(toolkit_cmd public-vm-guided-setup)"
    elif [[ "$runtime" != Running* ]]; then
      next_label="start ERPNext"
      next_command="$(toolkit_cmd start)"
    elif [[ "$prod_ssl_status" != "OK" ]]; then
      next_label="configure production HTTPS"
      next_command="$(toolkit_cmd production-ssl-wizard)"
    elif [[ "$backup_complete" != "complete" ]]; then
      next_label="create initial backup"
      next_command="$(toolkit_cmd backup-files)"
    else
      next_label="run release readiness"
      next_command="$(toolkit_cmd release-readiness)"
    fi

    echo "Recommended next step: ${next_label}."
    echo "  $(toolkit_display_item "$next_command")"
    echo
    echo "Production URL:"
    echo "  https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo
    echo "Backend ports 8000/9000 should be blocked publicly after hardening."
    echo "============================================================"
    return 0
  fi

  echo
  echo "============================================================"
  echo "Next Step"
  echo "============================================================"
  status_line "Storage" "INFO" "${storage_state}${storage_reason:+ - ${storage_reason}}"
  status_line "Install" "INFO" "$installed"
  status_line "Runtime" "INFO" "$runtime"
  status_line "Autostart" "INFO" "$auto"
  status_line "Local SSL" "INFO" "$ssl_state"
  echo

  if [[ "${can_expand:-no}" == "yes" ]]; then
    next_label="expand root storage"
    next_command="$(toolkit_cmd expand-root-storage)"
  else
    case "$installed" in
      "Not installed")
        next_label="run guided setup"
        next_command="$(toolkit_cmd guided-setup)"
        ;;
      "Incomplete")
        next_label="repair or reinstall the environment"
        next_command="$(toolkit_cmd repair)"
        ;;
      *)
        if [[ "$runtime" != Running* ]]; then
          next_label="start ERPNext"
          next_command="$(toolkit_cmd start)"
        elif [[ "$auto" != "Enabled" ]]; then
          next_label="enable autostart so the VM recovers cleanly after reboot"
          next_command="$(toolkit_cmd enable-autostart)"
        elif [[ "$ssl_state" != "configured" ]]; then
          next_label="configure local HTTPS"
          next_command="$(toolkit_cmd local-ssl-wizard)"
        else
          next_label="install optional apps with a checkpoint"
          next_command="$(toolkit_cmd app-install-wizard)"
        fi
        ;;
    esac
  fi

  echo "Recommended next step: ${next_label}."
  echo "  $(toolkit_display_item "$next_command")"
  echo
  echo "Required host mapping checkpoint before local HTTPS:"
  echo "  $(toolkit_cmd local-host-checkpoint)"
  echo
  echo "Useful checks:"
  echo "  $(toolkit_cmd verify-access)"
  echo "  $(toolkit_cmd storage-status)"
  echo
  echo "Open when running:"
  echo "  http://${vm_ip}:8000"
  echo "  http://${SITE_NAME}:8000"
  if [[ "$ssl_state" == "configured" ]]; then
    echo "  https://${SITE_NAME}"
  fi
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
  ok "ERPNext installation workflow finished successfully."
  echo "Verifying access state..."
  verify_access
  post_core_install_checkpoint
  show_next_step
  if ! is_public_vm_workflow; then
    show_local_host_mapping_checkpoint
  fi
  prompt_open_main_menu_after_install
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


show_host_hosts_command() {
  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Host /etc/hosts Command"
  echo "============================================================"
  echo
  echo "Run these commands on your HOST machine, not inside this VM:"
  echo
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test from the host:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Expected host mapping:"
  echo "  ${vm_ip} ${SITE_NAME}"
  echo
  echo "This command is environment-aware. The VM IP is detected from this VM,"
  echo "so it works for KVM, bridged LAN, VirtualBox/UTM-style NAT, or other private networks."
  echo "============================================================"
}


show_config_summary() {
  require_sudo
  local vm_ip prod_display mode_display ssl_display
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  prod_display="${PRODUCTION_DOMAIN:-not set}"
  mode_display="${DEPLOYMENT_MODE:-development}"
  ssl_display="${PRODUCTION_SSL_MODE:-planned}"

  ui_box_start "Toolkit Config Summary"
  status_line "Site" "INFO" "${SITE_NAME} (${SITE_NAME_SOURCE})"
  status_line "Production domain" "$([[ -n "${PRODUCTION_DOMAIN:-}" ]] && echo OK || echo INFO)" "$prod_display"
  status_line "Deployment mode" "INFO" "$mode_display"
  status_line "SSL mode" "INFO" "$ssl_display"
  status_line "VM IP" "INFO" "$vm_ip"
  status_line "Config file" "INFO" "$CONFIG_FILE"
  ui_box_end
  ui_next "$(toolkit_cmd setup-wizard)" "$(toolkit_cmd production-readiness)"
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
  write_dev_config_file
  SITE_NAME_SOURCE="saved config"
}

run_local_dev_quickstart() {
  require_sudo
  install_self_for_reuse

  ui_box_start "Local VM Quickstart"
  echo "This path uses local development defaults and keeps inputs minimal."
  echo "You can choose the local VM domain now, or press Enter for erp.test."
  status_line "Current site" "INFO" "${SITE_NAME:-erp.test}"
  status_line "Production domain" "INFO" "not used"
  status_line "Mode" "INFO" "local development"
  ui_box_end

  choose_local_site_name_for_setup

  ui_box_start "Local VM Setup Confirmation"
  status_line "Local VM domain" "OK" "${SITE_NAME}"
  status_line "Default if skipped" "INFO" "erp.test"
  status_line "Production domain" "INFO" "not used"
  ui_box_end

  echo "The host DNS command will be generated with this VM's detected IP. Do not hardcode another user's IP."
  echo "After install, the toolkit will print browser URLs, host DNS guidance, and the direct local HTTPS command."
  echo "Useful follow-up commands:"
  echo "  $(toolkit_cmd local-host-checkpoint)"
  echo "  $(toolkit_cmd host-dns-guide)"
  echo "  $(toolkit_cmd local-ssl-wizard)"
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
    ui_box_start "Public VM Quickstart"
    echo "Production order: requirements -> domain -> install -> backup -> HTTPS -> security profile -> apps -> final QA."
    echo
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
    ui_box_start "First Run / Setup Wizard"
    echo "Choose the setup type. The script will save non-secret settings."
    echo
    status_line "Current site" "INFO" "${SITE_NAME} (${SITE_NAME_SOURCE})"
    status_line "Production domain" "$([[ -n "${PRODUCTION_DOMAIN:-}" ]] && echo OK || echo INFO)" "${PRODUCTION_DOMAIN:-not set}"
    status_line "Config" "INFO" "$CONFIG_FILE"
    echo
    echo "1) Local development VM"
    echo "2) Public VM / production-candidate"
    echo "3) Existing install / maintenance menu"
    echo "4) Show saved config"
    echo "5) Setup lifecycle / SSL mode guide"
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
    print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
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
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "3) Test direct and friendly URLs:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
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

Structured planning command:
  $(toolkit_cmd production-domain-plan)

This developer toolkit only plans production settings.
Production automation should be a separate track.
============================================================
EOF_PROD_DOMAIN
}

show_production_domain_plan() {
  local vm_ip planned_domain domain_status domain_detail network_note dns_target record_name record_value

  require_sudo

  vm_ip="$(get_vm_ip)"
  planned_domain="${PRODUCTION_DOMAIN:-erp.company.com}"
  domain_status="WARN"
  domain_detail="not set; using placeholder example ${planned_domain}"

  if [[ -n "${PRODUCTION_DOMAIN:-}" ]]; then
    if validate_production_domain_value "$PRODUCTION_DOMAIN" >/dev/null 2>&1; then
      domain_status="OK"
      domain_detail="$PRODUCTION_DOMAIN"
    else
      domain_status="WARN"
      domain_detail="invalid value: $PRODUCTION_DOMAIN"
    fi
  fi

  network_note="Private/NAT address detected. For public production, DNS should point to the production server public IP, not this VM IP."
  dns_target="PRODUCTION_SERVER_PUBLIC_IP"
  record_name="$planned_domain"
  record_value="$dns_target"

  if [[ "$vm_ip" != 10.* && "$vm_ip" != 172.16.* && "$vm_ip" != 172.17.* && "$vm_ip" != 172.18.* && "$vm_ip" != 172.19.* && "$vm_ip" != 172.2* && "$vm_ip" != 172.30.* && "$vm_ip" != 172.31.* && "$vm_ip" != 192.168.* ]]; then
    network_note="Current VM IP does not look private. Confirm it is the intended production server IP before using it in DNS."
    dns_target="$vm_ip"
    record_value="$vm_ip"
  fi

  echo
  echo "============================================================"
  echo "Production Domain Plan"
  echo "============================================================"
  status_line "Mode" "INFO" "planning only; no DNS changes are applied"
  status_line "Local site" "INFO" "${SITE_NAME} (${SITE_NAME_SOURCE})"
  status_line "Current VM IP" "INFO" "${vm_ip}"
  status_line "Production domain" "$domain_status" "$domain_detail"
  status_line "Network note" "INFO" "$network_note"
  echo
  echo "Recommended DNS record:"
  echo "  Type:  A"
  echo "  Name:  ${record_name}"
  echo "  Value: ${record_value}"
  echo
  echo "Provider notes:"
  echo "  - Cloudflare: create/update the A record, then decide proxied vs DNS-only before SSL planning."
  echo "  - GoDaddy/other DNS: create/update the A record to the production server public IP."
  echo "  - Internal-only ERPNext: use internal DNS instead of public DNS."
  echo "  - Do not change MX/email records unless you are intentionally changing mail routing."
  echo
  echo "Validation checklist:"
  echo "  - Domain is not .test or .local."
  echo "  - DNS target is the production server, not a temporary dev NAT IP."
  echo "  - Ports 80/443 are reachable for the chosen SSL method."
  echo "  - The ERPNext site/domain mapping is planned before go-live."
  echo
  echo "Useful commands:"
  echo "  $(toolkit_cmd_env "PRODUCTION_DOMAIN=${record_name}" production-readiness)"
  echo "  $(toolkit_cmd_env "PRODUCTION_DOMAIN=${record_name}" production-domain-plan)"
  echo "  $(toolkit_cmd production-ssl-guide)"
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
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
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

  $(toolkit_cmd_env "SITE_NAME=erp1.test" setup)
  $(toolkit_cmd_env "SITE_NAME=school.test" setup)
  $(toolkit_cmd_env "SITE_NAME=client-a.test" setup)

Host /etc/hosts examples on your Linux host:

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
    echo "2) Local domain / host DNS status"
    echo "3) Local access doctor"
    echo "4) Show host /etc/hosts command only"
    echo "5) Show VM network/access status"
    echo "6) Show host access test guide"
    echo "7) Verify ERPNext HTTP access"
    echo "8) Show KVM VM identification + fixed IP helper"
    echo "9) Show KVM/libvirt fixed IP guide"
    echo "10) Show multi-environment naming guide"
    echo "11) Show SSL/HTTPS roadmap"
    echo "12) Show local SSL status"
    echo "13) Show local SSL guide"
    echo "14) Local SSL wizard"
    echo "15) Show trusted mkcert SSL guide"
    echo "16) Show browser trust check guide"
    echo "17) Verify local SSL"
    echo "18) Install/replace local SSL cert"
    echo "19) Create self-signed local cert"
    echo "20) Configure local SSL reverse proxy"
    echo "21) Disable local SSL reverse proxy"
    echo "22) Verify SSL rollback"
    echo "23) Show SSL rollback guide"
    echo "24) Domain config"
    echo "25) Production readiness preview"
    echo "26) Production domain guide"
    echo "27) Production SSL guide"
    echo "28) Environment / location check"
    menu_footer
    menu_read_choice access_choice

    case "$access_choice" in
      1) show_access_instructions ;;
      2) show_local_domain_status ;;
      3) local_access_doctor ;;
      4) show_host_hosts_command ;;
      5) show_network_status ;;
      6) show_host_access_test_guide ;;
      7) verify_access ;;
      8) show_kvm_vm_identification_guide ;;
      9) show_kvm_fixed_ip_guide ;;
      10) show_multi_environment_guide ;;
      11) show_ssl_roadmap_guide ;;
      12) show_ssl_status ;;
      13) show_local_ssl_guide ;;
      14) run_local_ssl_wizard ;;
      15) show_mkcert_local_ssl_guide ;;
      16) show_browser_trust_check_guide ;;
      17) verify_local_ssl ;;
      18) install_local_ssl_cert ;;
      19) create_self_signed_local_cert ;;
      20) configure_local_ssl ;;
      21) disable_local_ssl ;;
      22) verify_ssl_rollback ;;
      23) show_ssl_rollback_guide ;;
      24) show_domain_config ;;
      25) show_production_readiness ;;
      26) show_production_domain_guide ;;
      27) show_production_ssl_guide ;;
      28) show_environment_check ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}


show_credentials_info() {
  require_sudo

  local cred_file bench_dir current_site reset_site
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  bench_dir="$(active_bench_dir 2>/dev/null || printf '%s' "${BENCH_DIR}")"
  current_site="${PRODUCTION_DOMAIN:-${SITE_NAME}}"
  reset_site="${SITE_NAME}"

  echo
  echo "============================================================"
  echo "ERPNext Credentials / Login Info"
  echo "============================================================"
  echo
  status_line "ERPNext username" "INFO" "Administrator"
  if path_is_file "$cred_file"; then
    status_line "Credentials file" "OK" "$cred_file"
  else
    status_line "Credentials file" "WARN" "missing at $cred_file"
  fi
  status_line "Site" "INFO" "$current_site"
  status_line "Bench" "INFO" "$bench_dir"
  echo
  echo "Recommended commands:"
  echo "  View safe credential info:       $(toolkit_cmd credentials-info)"
  echo "  Show generated password:         $(toolkit_cmd credentials-show)"
  echo "  Check credential file security:  $(toolkit_cmd credentials-file-status)"
  echo "  Fix credential file permissions: $(toolkit_cmd credentials-secure)"
  echo "  Delete local plaintext file:     $(toolkit_cmd credentials-delete)"
  echo "  Reset Administrator password:    $(toolkit_cmd reset-admin-password)"
  echo
  echo "ERPNext web login:"
  echo "  Username: Administrator"
  echo "  Password: value shown by credentials-show or in ${cred_file}"
  echo
  echo "Security note:"
  echo "  credentials-info does not print passwords."
  echo "  The toolkit does not print passwords in diagnostics, support bundles, or shared logs."
  echo "  After saving credentials in a password manager, remove the local plaintext file on production systems."
  echo
  echo "Manual fallback for experienced admins: sudo cat ${cred_file}"
  echo "Prefer credentials-show because it includes safety warnings."
  echo
  echo "For a public/production site, replace ${reset_site} with the actual site name if different."
  echo "============================================================"
}

show_credentials_file_status() {
  require_sudo

  local cred_file owner group mode size modified status perm_status
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  echo
  echo "============================================================"
  echo "Credentials File Status"
  echo "============================================================"

  if ! path_is_file "$cred_file"; then
    status_line "Credentials file" "WARN" "missing at $cred_file"
    echo
    echo "If you already saved the credentials in a password manager, this is acceptable."
    echo "If you still need access, reset the Administrator password with:"
    echo "  $(toolkit_cmd reset-admin-password)"
    echo "============================================================"
    return 0
  fi

  owner="$(stat -c '%U' "$cred_file" 2>/dev/null || echo unknown)"
  group="$(stat -c '%G' "$cred_file" 2>/dev/null || echo unknown)"
  mode="$(stat -c '%a' "$cred_file" 2>/dev/null || echo unknown)"
  size="$(stat -c '%s' "$cred_file" 2>/dev/null || echo unknown)"
  modified="$(stat -c '%y' "$cred_file" 2>/dev/null | cut -d'.' -f1 || echo unknown)"

  if [[ "$owner" == "root" && "$mode" == "600" ]]; then
    perm_status="OK"
    status="root-only permissions"
  else
    perm_status="WARN"
    status="recommended owner=root and mode=600; run $(toolkit_cmd credentials-secure)"
  fi

  status_line "Credentials file" "OK" "$cred_file"
  status_line "Owner" "$([[ "$owner" == "root" ]] && echo OK || echo WARN)" "$owner"
  status_line "Group" "INFO" "$group"
  status_line "Mode" "$([[ "$mode" == "600" ]] && echo OK || echo WARN)" "$mode"
  status_line "Size" "INFO" "${size} bytes"
  status_line "Modified" "INFO" "$modified"
  status_line "Security" "$perm_status" "$status"
  echo
  echo "Production recommendation:"
  echo "  1. Save the credentials in a password manager."
  echo "  2. Run: $(toolkit_cmd credentials-delete)"
  echo "============================================================"
}

credentials_secure() {
  require_sudo

  local cred_file
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  if ! path_is_file "$cred_file"; then
    warn "Credentials file is missing: $cred_file"
    echo "Use $(toolkit_cmd reset-admin-password) if you need to set a new Administrator password."
    return 0
  fi

  $SUDO chown root:root "$cred_file"
  $SUDO chmod 600 "$cred_file"
  ok "Credentials file secured with owner=root and mode=600"
  show_credentials_file_status
}

credentials_show() {
  require_sudo

  local cred_file reply
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  echo
  echo "============================================================"
  echo "Show ERPNext Credentials"
  echo "============================================================"

  if ! path_is_file "$cred_file"; then
    status_line "Credentials file" "WARN" "missing at $cred_file"
    echo
    echo "If the file was deleted after handoff, reset the Administrator password with:"
    echo "  $(toolkit_cmd reset-admin-password)"
    echo "============================================================"
    return 1
  fi

  warn "This will display generated passwords in your terminal."
  echo "Only continue from a private console. Do not paste this output into chats, tickets, logs, or screenshots."
  echo

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    reply="SHOW"
  else
    read -r -p "Type SHOW to display credentials: " reply
  fi

  if [[ "$reply" != "SHOW" ]]; then
    warn "Credentials display cancelled."
    echo "============================================================"
    return 1
  fi

  echo
  echo "----- BEGIN CREDENTIALS (${cred_file}) -----"
  $SUDO cat "$cred_file"
  echo "----- END CREDENTIALS -----"
  echo
  echo "After saving these credentials in a password manager, production systems should run:"
  echo "  $(toolkit_cmd credentials-delete)"
  echo "============================================================"
}

credentials_delete() {
  require_sudo

  local cred_file reply
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  echo
  echo "============================================================"
  echo "Delete Local Credentials File"
  echo "============================================================"

  if ! path_is_file "$cred_file"; then
    status_line "Credentials file" "INFO" "already missing at $cred_file"
    echo "============================================================"
    return 0
  fi

  warn "This removes the local plaintext credentials file from the VM."
  echo "Only continue after saving credentials in a password manager or completing handoff."
  echo "This does not change the ERPNext Administrator password."
  echo

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    reply="DELETE"
  else
    read -r -p "Type DELETE to remove ${cred_file}: " reply
  fi

  if [[ "$reply" != "DELETE" ]]; then
    warn "Credentials deletion cancelled."
    echo "============================================================"
    return 1
  fi

  $SUDO rm -f "$cred_file"
  ok "Deleted local credentials file: $cred_file"
  echo "If access is needed later, run: $(toolkit_cmd reset-admin-password)"
  echo "============================================================"
}

reset_admin_password() {
  require_sudo

  local bench_dir site new_password confirm_password pw_quoted site_quoted
  bench_dir="$(active_bench_dir 2>/dev/null || printf '%s' "${BENCH_DIR}")"
  site="${SITE_NAME}"

  echo
  echo "============================================================"
  echo "Reset ERPNext Administrator Password"
  echo "============================================================"
  status_line "Site" "INFO" "$site"
  status_line "Bench" "INFO" "$bench_dir"
  echo

  if [[ ! -d "$bench_dir" ]]; then
    fail "Bench folder not found: $bench_dir"
  fi

  if [[ ! -t 0 ]]; then
    fail "Interactive terminal required for password reset."
  fi

  read -r -s -p "New Administrator password: " new_password
  echo
  read -r -s -p "Confirm new Administrator password: " confirm_password
  echo

  if [[ -z "$new_password" ]]; then
    fail "Password cannot be empty."
  fi
  if [[ "$new_password" != "$confirm_password" ]]; then
    fail "Passwords do not match."
  fi

  pw_quoted="$(printf '%q' "$new_password")"
  site_quoted="$(printf '%q' "$site")"

  echo "Updating Administrator password..."
  run_as_frappe "cd '${bench_dir}' && bench --site ${site_quoted} set-admin-password ${pw_quoted}"
  ok "Administrator password updated for ${site}"
  echo
  echo "Save the new password in a password manager."
  echo "If the generated credentials file contains the old password, remove it with:"
  echo "  $(toolkit_cmd credentials-delete)"
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
  local detected

  detected="$(detect_bench_dir 2>/dev/null || true)"
  if [[ -n "$detected" ]]; then
    printf '%s
' "$detected" | head -n 1
  else
    echo "$BENCH_DIR"
  fi
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

  if [[ "$SITE_NAME_SOURCE" == "setup prompt" || "$SITE_NAME_SOURCE" == "domain wizard" || "$SITE_NAME_SOURCE" == "local quickstart" ]]; then
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
          echo "ERPNext is running. Optional: enable autostart with $(toolkit_cmd enable-autostart)"
        fi
      else
        echo "Start ERPNext with $(toolkit_cmd start)"
      fi
      ;;
    "Incomplete")
      echo "Run $(toolkit_cmd repair), or run setup for a clean reinstall."
      ;;
    *)
      echo "Run $(toolkit_cmd setup)"
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
  echo "  - Detailed diagnostics: $(toolkit_cmd doctor)"
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
    echo "  sleep 30 && $(toolkit_cmd runtime-status)"
    echo "  $(toolkit_cmd logs)"
  else
    echo "If installed but stopped, run: $(toolkit_cmd start)"
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
  echo "  $(toolkit_cmd enable-autostart)"
  echo "  $(toolkit_cmd disable-autostart)"
  echo "  $(toolkit_cmd service-start)"
  echo "  $(toolkit_cmd service-stop)"
  echo "  $(toolkit_cmd logs)"
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
    menu_footer
    menu_read_choice status_choice

    case "$status_choice" in
      1) run_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      2) run_runtime_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      3) run_installation_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      4) run_service_summary; pause_after_screen "Press Enter to return to Status Menu..." ;;
      5) run_app_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      6) run_full_status; pause_after_screen "Press Enter to return to Status Menu..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option"; pause_after_screen "Press Enter to continue..." ;;
    esac
  done
}



status_line_plain() {
  local label="$1"
  local state="$2"
  local message="$3"

  printf "  %-28s %-7s %s\n" "$label" "$state" "$message"
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

doctor_add_check() {
  DOCTOR_CHECK_NAMES+=("$1")
  DOCTOR_CHECK_STATUSES+=("$2")
  DOCTOR_CHECK_DETAILS+=("$3")
}

doctor_command_version() {
  local cmd="$1"
  shift || true

  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" "$@" 2>/dev/null | head -n 1 || true
  else
    echo "missing"
  fi
}

doctor_run_as_frappe_one_line() {
  local cmd="$1"

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    run_as_frappe "$cmd" 2>/dev/null | head -n 1 || true
  else
    echo "frappe user missing"
  fi
}

doctor_storage_detail() {
  local data layout root_bytes vg_free_bytes tail_free_bytes can_expand reason
  data="$(storage_eval 2>/dev/null || true)"

  while IFS='=' read -r k v; do
    case "$k" in
      LAYOUT) layout="$v" ;;
      ROOT_BYTES) root_bytes="$v" ;;
      VG_FREE_BYTES) vg_free_bytes="$v" ;;
      TAIL_FREE_BYTES) tail_free_bytes="$v" ;;
      CAN_EXPAND) can_expand="$v" ;;
      REASON) reason="$v" ;;
    esac
  done <<< "$data"

  printf 'layout=%s; root=%s; vg_free=%s; tail_free=%s; reason=%s\n' \
    "${layout:-unknown}" \
    "$(bytes_to_gib "${root_bytes:-0}" 2>/dev/null || echo unknown)" \
    "$(bytes_to_gib "${vg_free_bytes:-0}" 2>/dev/null || echo unknown)" \
    "$(bytes_to_gib "${tail_free_bytes:-0}" 2>/dev/null || echo unknown)" \
    "${reason:-unknown}"
}

doctor_optional_app_detail() {
  local bench_dir="$1"
  local app="$2"

  if site_app_installed "$app" 2>/dev/null; then
    echo "installed on ${SITE_NAME}"
  elif app_folder_exists "$bench_dir" "$app" 2>/dev/null && app_in_apps_txt "$app" 2>/dev/null; then
    echo "downloaded and registered, not installed on ${SITE_NAME}"
  elif app_folder_exists "$bench_dir" "$app" 2>/dev/null; then
    echo "downloaded, not registered"
  else
    echo "not installed"
  fi
}

doctor_collect() {
  require_sudo

  DOCTOR_GENERATED_AT="$(date -Iseconds 2>/dev/null || date)"
  DOCTOR_HOSTNAME="$(hostname 2>/dev/null || echo unknown)"
  DOCTOR_CURRENT_USER="$(id -un 2>/dev/null || echo unknown)"
  DOCTOR_VM_IP="$(get_vm_ip 2>/dev/null || echo unknown)"
  DOCTOR_BENCH_DIR="$(active_bench_dir 2>/dev/null || echo "$BENCH_DIR")"
  DOCTOR_INSTALL_STATE="$(install_state 2>/dev/null || echo unknown)"
  DOCTOR_RUNTIME_STATE="$(runtime_state 2>/dev/null || echo unknown)"
  DOCTOR_SERVICE_STATE="$(service_state 2>/dev/null || echo unknown)"
  DOCTOR_AUTOSTART_STATE="$(autostart_state 2>/dev/null || echo unknown)"
  DOCTOR_SSL_STATE="not configured"
  DOCTOR_CHECK_NAMES=()
  DOCTOR_CHECK_STATUSES=()
  DOCTOR_CHECK_DETAILS=()
  DOCTOR_OPTIONAL_APPS=()
  DOCTOR_OPTIONAL_LABELS=()
  DOCTOR_OPTIONAL_DETAILS=()

  if ssl_is_configured 2>/dev/null; then
    DOCTOR_SSL_STATE="configured"
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DOCTOR_OS="${PRETTY_NAME:-unknown}"
    if [[ "${ID:-}" == "ubuntu" && ( "${VERSION_ID:-}" == "24.04" || "${VERSION_ID:-}" == "26.04" ) ]]; then
      doctor_add_check "OS" "OK" "$DOCTOR_OS"
    else
      doctor_add_check "OS" "FAIL" "${DOCTOR_OS}; supported: Ubuntu 24.04 / 26.04"
    fi
  else
    DOCTOR_OS="unknown"
    doctor_add_check "OS" "FAIL" "/etc/os-release not found"
  fi

  local py_system py_frappe node_frappe mariadb_version redis_version storage_detail storage_data storage_can_expand storage_layout storage_reason
  py_system="$(doctor_command_version python3 --version)"
  py_frappe="$(doctor_run_as_frappe_one_line 'python --version 2>&1')"
  node_frappe="$(doctor_run_as_frappe_one_line 'node --version 2>/dev/null || echo missing')"
  mariadb_version="$(doctor_command_version mariadb --version)"
  if [[ "$mariadb_version" == "missing" ]]; then
    mariadb_version="$(doctor_command_version mysql --version)"
  fi
  redis_version="$(doctor_command_version redis-server --version)"

  doctor_add_check "System Python" "INFO" "$py_system"
  doctor_add_check "frappe Python" "INFO" "$py_frappe"
  doctor_add_check "frappe Node" "INFO" "$node_frappe"
  doctor_add_check "MariaDB version" "INFO" "$mariadb_version"
  doctor_add_check "Redis version" "INFO" "$redis_version"

  if systemctl is-active --quiet mariadb 2>/dev/null; then
    doctor_add_check "MariaDB service" "OK" "running"
  else
    doctor_add_check "MariaDB service" "WARN" "not running"
  fi

  if systemctl is-active --quiet redis-server 2>/dev/null; then
    doctor_add_check "Redis service" "OK" "running"
  else
    doctor_add_check "Redis service" "WARN" "not running"
  fi

  if [[ "$(sysctl -n vm.overcommit_memory 2>/dev/null || echo 0)" == "1" ]]; then
    doctor_add_check "Redis overcommit" "OK" "vm.overcommit_memory=1"
  else
    doctor_add_check "Redis overcommit" "WARN" "not set to 1"
  fi

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    doctor_add_check "frappe user" "OK" "$FRAPPE_USER exists"
  else
    doctor_add_check "frappe user" "FAIL" "$FRAPPE_USER missing"
  fi

  if path_is_dir "$DOCTOR_BENCH_DIR"; then
    doctor_add_check "Bench folder" "OK" "$DOCTOR_BENCH_DIR"
  else
    doctor_add_check "Bench folder" "FAIL" "$DOCTOR_BENCH_DIR missing"
  fi

  if check_bench_app_installed frappe; then
    doctor_add_check "Frappe app files" "OK" "apps/frappe exists"
  else
    doctor_add_check "Frappe app files" "FAIL" "apps/frappe missing"
  fi

  if check_bench_app_installed erpnext; then
    doctor_add_check "ERPNext app files" "OK" "apps/erpnext exists"
  else
    doctor_add_check "ERPNext app files" "WARN" "apps/erpnext missing"
  fi

  if site_exists; then
    doctor_add_check "Site folder" "OK" "${SITE_NAME} exists"
  else
    doctor_add_check "Site folder" "WARN" "${SITE_NAME} missing"
  fi

  if site_app_installed frappe 2>/dev/null; then
    doctor_add_check "Site app: frappe" "OK" "installed on ${SITE_NAME}"
  else
    doctor_add_check "Site app: frappe" "WARN" "not confirmed on ${SITE_NAME}"
  fi

  if site_app_installed erpnext 2>/dev/null; then
    doctor_add_check "Site app: erpnext" "OK" "installed on ${SITE_NAME}"
  else
    doctor_add_check "Site app: erpnext" "WARN" "not confirmed on ${SITE_NAME}"
  fi

  case "$DOCTOR_INSTALL_STATE" in
    Installed) doctor_add_check "Install state" "OK" "$DOCTOR_INSTALL_STATE" ;;
    Incomplete) doctor_add_check "Install state" "WARN" "$DOCTOR_INSTALL_STATE" ;;
    *) doctor_add_check "Install state" "INFO" "$DOCTOR_INSTALL_STATE" ;;
  esac

  case "$DOCTOR_RUNTIME_STATE" in
    Running*) doctor_add_check "Runtime state" "OK" "$DOCTOR_RUNTIME_STATE" ;;
    Starting*) doctor_add_check "Runtime state" "WARN" "$DOCTOR_RUNTIME_STATE" ;;
    *) doctor_add_check "Runtime state" "INFO" "$DOCTOR_RUNTIME_STATE" ;;
  esac

  case "$DOCTOR_SERVICE_STATE" in
    Running) doctor_add_check "Service state" "OK" "$DOCTOR_SERVICE_STATE" ;;
    "Not configured") doctor_add_check "Service state" "WARN" "$DOCTOR_SERVICE_STATE" ;;
    *) doctor_add_check "Service state" "INFO" "$DOCTOR_SERVICE_STATE" ;;
  esac

  case "$DOCTOR_AUTOSTART_STATE" in
    Enabled) doctor_add_check "Autostart" "OK" "$DOCTOR_AUTOSTART_STATE" ;;
    *) doctor_add_check "Autostart" "WARN" "$DOCTOR_AUTOSTART_STATE" ;;
  esac

  local port label item
  for item in "8000:Bench web" "9000:Socket.io" "11000:Bench Redis queue" "13000:Bench Redis cache"; do
    port="${item%%:*}"
    label="${item#*:}"
    if port_listens "$port"; then
      doctor_add_check "$label" "OK" "port ${port} listening"
    else
      doctor_add_check "$label" "INFO" "port ${port} not listening"
    fi
  done

  storage_data="$(storage_eval 2>/dev/null || true)"
  storage_can_expand="$(printf '%s\n' "$storage_data" | awk -F= '$1=="CAN_EXPAND" {print $2; exit}')"
  storage_layout="$(printf '%s\n' "$storage_data" | awk -F= '$1=="LAYOUT" {print $2; exit}')"
  storage_reason="$(printf '%s\n' "$storage_data" | awk -F= '$1=="REASON" {print $2; exit}')"
  storage_detail="$(doctor_storage_detail)"
  if [[ "${storage_can_expand:-no}" == "yes" ]]; then
    doctor_add_check "Root storage" "WARN" "expansion recommended; ${storage_detail}"
  elif [[ "${storage_layout:-unknown}" == "unknown" ]]; then
    doctor_add_check "Root storage" "WARN" "not automatic; ${storage_reason:-unknown}"
  else
    doctor_add_check "Root storage" "OK" "${storage_detail}"
  fi

  if [[ "$DOCTOR_SSL_STATE" == "configured" ]]; then
    local cert_path cert_detail="configured"
    cert_path="$(ssl_cert_path 2>/dev/null || true)"
    if [[ -n "$cert_path" && -f "$cert_path" ]] && ssl_cert_is_self_signed "$cert_path" 2>/dev/null; then
      cert_detail="configured; self-signed/local test certificate"
    elif [[ -n "$cert_path" && -f "$cert_path" ]]; then
      cert_detail="configured; certificate is not self-signed"
    fi
    doctor_add_check "Local SSL" "OK" "$cert_detail"
  else
    doctor_add_check "Local SSL" "INFO" "not configured"
  fi

  if path_is_executable "${FRAPPE_HOME}/start-erpnext-dev.sh"; then
    doctor_add_check "Start helper" "OK" "${FRAPPE_HOME}/start-erpnext-dev.sh"
  else
    doctor_add_check "Start helper" "WARN" "missing or not executable at ${FRAPPE_HOME}/start-erpnext-dev.sh"
  fi

  if path_is_file "${FRAPPE_HOME}/erpnext-dev-credentials.txt"; then
    doctor_add_check "Credentials file" "OK" "present; content intentionally not displayed"
  else
    doctor_add_check "Credentials file" "WARN" "missing"
  fi

  local optional_profile optional_app optional_label optional_detail
  for optional_profile in $(app_profile_list); do
    app_profile_defaults "$optional_profile" || continue
    optional_app="$LIB_APP_NAME"
    optional_label="$LIB_APP_DISPLAY"
    optional_detail="$(doctor_optional_app_detail "$DOCTOR_BENCH_DIR" "$optional_app")"
    DOCTOR_OPTIONAL_APPS+=("$optional_app")
    DOCTOR_OPTIONAL_LABELS+=("$optional_label")
    DOCTOR_OPTIONAL_DETAILS+=("$optional_detail")
  done

  DOCTOR_BENCH_VERSION="$(doctor_run_as_frappe_one_line "cd '${DOCTOR_BENCH_DIR}' 2>/dev/null && bench version 2>/dev/null | head -n 1")"
  [[ -n "$DOCTOR_BENCH_VERSION" ]] || DOCTOR_BENCH_VERSION="not available"
}

run_doctor_plain() {
  doctor_collect

  echo
  echo "============================================================"
  echo "ERPNext Developer Diagnostics (Plain / Safe to Share)"
  echo "============================================================"
  echo "Generated: ${DOCTOR_GENERATED_AT}"
  echo "Script:    ${APP_NAME} v${SCRIPT_VERSION}"
  echo "Note:      Secrets, passwords, tokens, private keys, and credential contents are intentionally excluded."
  echo
  echo "Context:"
  status_line_plain "Hostname" "INFO" "$DOCTOR_HOSTNAME"
  status_line_plain "Current user" "INFO" "$DOCTOR_CURRENT_USER"
  status_line_plain "VM IP" "INFO" "$DOCTOR_VM_IP"
  status_line_plain "Site" "INFO" "${SITE_NAME} (${SITE_NAME_SOURCE})"
  status_line_plain "Bench" "INFO" "$DOCTOR_BENCH_DIR"
  status_line_plain "Bench version" "INFO" "$DOCTOR_BENCH_VERSION"
  status_line_plain "Service name" "INFO" "$ERPNEXT_SERVICE_NAME"
  status_line_plain "Config file" "INFO" "${CONFIG_FILE}"
  echo
  echo "Checks:"

  local i
  for i in "${!DOCTOR_CHECK_NAMES[@]}"; do
    status_line_plain "${DOCTOR_CHECK_NAMES[$i]}" "${DOCTOR_CHECK_STATUSES[$i]}" "${DOCTOR_CHECK_DETAILS[$i]}"
  done

  echo
  echo "Optional apps:"
  for i in "${!DOCTOR_OPTIONAL_APPS[@]}"; do
    status_line_plain "${DOCTOR_OPTIONAL_APPS[$i]}" "INFO" "${DOCTOR_OPTIONAL_LABELS[$i]}: ${DOCTOR_OPTIONAL_DETAILS[$i]}"
  done

  echo
  echo "Access:"
  echo "  Direct URL:   http://${DOCTOR_VM_IP}:8000"
  echo "  Friendly URL: http://${SITE_NAME}:8000"
  if [[ "$DOCTOR_SSL_STATE" == "configured" ]]; then
    echo "  HTTPS URL:    https://${SITE_NAME}"
  fi
  echo "  HOST mapping: ${DOCTOR_VM_IP} ${SITE_NAME}"
  echo
  echo "Log file for this run: ${LOG_FILE}"
  echo "============================================================"
}

run_doctor_json() {
  doctor_collect

  local i
  printf '{\n'
  printf '  "schema_version": "1",\n'
  printf '  "safe_to_share": true,\n'
  printf '  "redaction_note": ' ; json_escape "Secrets, passwords, tokens, private keys, and credential contents are intentionally excluded." ; printf ',\n'
  printf '  "generated_at": ' ; json_escape "$DOCTOR_GENERATED_AT" ; printf ',\n'
  printf '  "script": {"name": ' ; json_escape "$APP_NAME" ; printf ', "version": ' ; json_escape "$SCRIPT_VERSION" ; printf '},\n'
  printf '  "context": {\n'
  printf '    "hostname": ' ; json_escape "$DOCTOR_HOSTNAME" ; printf ',\n'
  printf '    "current_user": ' ; json_escape "$DOCTOR_CURRENT_USER" ; printf ',\n'
  printf '    "vm_ip": ' ; json_escape "$DOCTOR_VM_IP" ; printf ',\n'
  printf '    "site_name": ' ; json_escape "$SITE_NAME" ; printf ',\n'
  printf '    "site_source": ' ; json_escape "$SITE_NAME_SOURCE" ; printf ',\n'
  printf '    "bench_dir": ' ; json_escape "$DOCTOR_BENCH_DIR" ; printf ',\n'
  printf '    "bench_version": ' ; json_escape "$DOCTOR_BENCH_VERSION" ; printf ',\n'
  printf '    "service_name": ' ; json_escape "$ERPNEXT_SERVICE_NAME" ; printf ',\n'
  printf '    "config_file": ' ; json_escape "$CONFIG_FILE" ; printf ',\n'
  printf '    "install_state": ' ; json_escape "$DOCTOR_INSTALL_STATE" ; printf ',\n'
  printf '    "runtime_state": ' ; json_escape "$DOCTOR_RUNTIME_STATE" ; printf ',\n'
  printf '    "service_state": ' ; json_escape "$DOCTOR_SERVICE_STATE" ; printf ',\n'
  printf '    "autostart_state": ' ; json_escape "$DOCTOR_AUTOSTART_STATE" ; printf ',\n'
  printf '    "local_ssl_state": ' ; json_escape "$DOCTOR_SSL_STATE" ; printf '\n'
  printf '  },\n'
  printf '  "checks": [\n'
  for i in "${!DOCTOR_CHECK_NAMES[@]}"; do
    if [[ "$i" -gt 0 ]]; then printf ',\n'; fi
    printf '    {"name": ' ; json_escape "${DOCTOR_CHECK_NAMES[$i]}" ; printf ', "status": ' ; json_escape "${DOCTOR_CHECK_STATUSES[$i]}" ; printf ', "detail": ' ; json_escape "${DOCTOR_CHECK_DETAILS[$i]}" ; printf '}'
  done
  printf '\n  ],\n'
  printf '  "optional_apps": [\n'
  for i in "${!DOCTOR_OPTIONAL_APPS[@]}"; do
    if [[ "$i" -gt 0 ]]; then printf ',\n'; fi
    printf '    {"app": ' ; json_escape "${DOCTOR_OPTIONAL_APPS[$i]}" ; printf ', "label": ' ; json_escape "${DOCTOR_OPTIONAL_LABELS[$i]}" ; printf ', "detail": ' ; json_escape "${DOCTOR_OPTIONAL_DETAILS[$i]}" ; printf '}'
  done
  printf '\n  ],\n'
  printf '  "access": {\n'
  printf '    "direct_url": ' ; json_escape "http://${DOCTOR_VM_IP}:8000" ; printf ',\n'
  printf '    "friendly_url": ' ; json_escape "http://${SITE_NAME}:8000" ; printf ',\n'
  if [[ "$DOCTOR_SSL_STATE" == "configured" ]]; then
    printf '    "https_url": ' ; json_escape "https://${SITE_NAME}" ; printf ',\n'
  fi
  printf '    "host_mapping": ' ; json_escape "${DOCTOR_VM_IP} ${SITE_NAME}" ; printf '\n'
  printf '  }\n'
  printf '}\n'
}


redact_file_in_place() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  if command -v perl >/dev/null 2>&1; then
    perl -0pi -e 's/(?i)(("?)(?:password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|authorization|cookie|db_password|admin_password)\2\s*[:=]\s*)(["\x27])(?:(?!\3).)*\3/${1}${3}[REDACTED]${3}/gs; s/(?i)(("?)(?:password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|authorization|cookie|db_password|admin_password)\2\s*[:=]\s*)[^\s,;}]+/${1}[REDACTED]/g; s/(?i)(Bearer\s+)[A-Za-z0-9._~+\/=-]+/${1}[REDACTED]/g; s/-----BEGIN ([A-Z0-9 ]*PRIVATE KEY)-----.*?-----END \1-----/-----BEGIN $1-----\n[REDACTED]\n-----END $1-----/gis;' "$file" 2>/dev/null || true
  else
    sed -Ei \
      -e "s/(password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|authorization|cookie)([[:space:]_:=\"]+)[^[:space:]\",;}]+/\1\2[REDACTED]/Ig" \
      -e "s/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/Ig" \
      "$file" 2>/dev/null || true
  fi
}

support_bundle_write_file() {
  local output_file="$1"
  shift

  if ! "$@" > "$output_file" 2>&1; then
    {
      echo
      echo "WARN: command failed while collecting this section."
      echo "Command: $*"
    } >> "$output_file"
  fi

  redact_file_in_place "$output_file"
  chmod 600 "$output_file" 2>/dev/null || true
}

support_bundle_manifest() {
  cat <<EOF_SUPPORT_MANIFEST
ERPNext Developer Toolkit Support Bundle
=========================================

Generated: $(date -Iseconds 2>/dev/null || date)
Script:    ${APP_NAME} v${SCRIPT_VERSION}
Site:      ${SITE_NAME}

Safe-to-share intent:
- This bundle is designed for troubleshooting and support.
- It includes share-safe diagnostics, status summaries, and recent redacted service errors.
- It intentionally excludes credential files, private keys, raw site_config.json secrets, tokens, and database passwords.

Recommended review before sharing:
- Open the included .txt and .json files.
- Confirm there is no client-sensitive text from custom logs before sending outside your organization.

Included files:
- doctor-plain.txt
- doctor.json
- doctor-json-validation.txt
- system-summary.txt
- service-status.txt
- port-status.txt
- storage-status.txt
- ssl-status.txt
- bench-status.txt
- recent-errors.txt
- manifest.txt
EOF_SUPPORT_MANIFEST
}

support_bundle_system_summary() {
  echo "Generated: $(date -Iseconds 2>/dev/null || date)"
  echo "Script: ${APP_NAME} v${SCRIPT_VERSION}"
  echo
  echo "OS release:"
  if [[ -f /etc/os-release ]]; then
    cat /etc/os-release
  else
    echo "/etc/os-release missing"
  fi
  echo
  echo "Kernel:"
  uname -a || true
  echo
  echo "Hostname:"
  hostname || true
  echo
  echo "Current user:"
  id || true
  echo
  echo "Uptime:"
  uptime || true
  echo
  echo "Memory:"
  free -h || true
  echo
  echo "Root filesystem:"
  df -hT / || true
  echo
  echo "Tool versions:"
  python3 --version 2>&1 || true
  mariadb --version 2>&1 || mysql --version 2>&1 || true
  redis-server --version 2>&1 || true
  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    doctor_run_as_frappe_one_line 'node --version 2>/dev/null || echo node missing'
    doctor_run_as_frappe_one_line 'python --version 2>&1 || echo python missing'
  fi
}

support_bundle_service_status() {
  local svc
  for svc in mariadb redis-server "$ERPNEXT_SERVICE_NAME"; do
    echo "============================================================"
    echo "Service: ${svc}"
    echo "============================================================"
    systemctl is-enabled "$svc" 2>/dev/null || true
    systemctl is-active "$svc" 2>/dev/null || true
    systemctl status "$svc" --no-pager --lines=30 2>&1 || true
    echo
  done
}

support_bundle_port_status() {
  echo "Listening TCP ports:"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>&1 || true
  else
    netstat -ltn 2>&1 || true
  fi
  echo
  echo "ERPNext development port checks:"
  local item port label
  for item in "8000:Bench web" "9000:Socket.io" "11000:Bench Redis queue" "13000:Bench Redis cache" "80:HTTP" "443:HTTPS"; do
    port="${item%%:*}"
    label="${item#*:}"
    if port_listens "$port"; then
      printf '%-24s OK    port %s listening\n' "$label" "$port"
    else
      printf '%-24s INFO  port %s not listening\n' "$label" "$port"
    fi
  done
}

support_bundle_storage_status() {
  echo "Raw storage evaluator output:"
  storage_eval 2>&1 || true
  echo
  echo "Root mount:"
  findmnt -n -o SOURCE,FSTYPE,SIZE,AVAIL,TARGET / 2>&1 || true
  echo
  echo "df -hT:"
  df -hT || true
  echo
  echo "lsblk -f:"
  lsblk -f 2>&1 || true
  echo
  if command -v pvs >/dev/null 2>&1; then
    echo "LVM physical volumes:"
    pvs 2>&1 || true
    echo
  fi
  if command -v vgs >/dev/null 2>&1; then
    echo "LVM volume groups:"
    vgs 2>&1 || true
    echo
  fi
  if command -v lvs >/dev/null 2>&1; then
    echo "LVM logical volumes:"
    lvs 2>&1 || true
    echo
  fi
}

support_bundle_ssl_status() {
  echo "Script SSL status:"
  show_ssl_status || true
  echo
  echo "Local SSL verification summary:"
  verify_local_ssl || true
}

support_bundle_bench_status() {
  local bench_dir
  bench_dir="$(active_bench_dir 2>/dev/null || echo "$BENCH_DIR")"

  echo "Bench directory: ${bench_dir}"
  echo "Site: ${SITE_NAME}"
  echo

  if ! id "$FRAPPE_USER" >/dev/null 2>&1; then
    echo "frappe user missing; Bench status unavailable."
    return 0
  fi

  if ! path_is_dir "$bench_dir"; then
    echo "Bench directory missing; Bench status unavailable."
    return 0
  fi

  echo "Bench version:"
  run_as_frappe "cd '${bench_dir}' && bench version" 2>&1 || true
  echo
  echo "Installed site apps:"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' list-apps" 2>&1 || true
  echo
  echo "Downloaded app folders and Git branches:"
  run_as_frappe "cd '${bench_dir}' && for appdir in apps/*; do [ -d \"\$appdir\" ] || continue; app=\$(basename \"\$appdir\"); branch=\$(git -C \"\$appdir\" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown); printf '%s %s\\n' \"\$app\" \"\$branch\"; done | sort" 2>&1 || true
}

support_bundle_recent_errors() {
  local svc
  for svc in "$ERPNEXT_SERVICE_NAME" mariadb redis-server; do
    echo "============================================================"
    echo "Recent warnings/errors: ${svc}"
    echo "============================================================"
    journalctl -u "$svc" -n 120 --no-pager -o short-iso -p warning..alert 2>&1 || true
    echo
  done
}



support_bundle_production_checklist() { show_production_checklist; }
support_bundle_backup_status() { show_backup_status; }
support_bundle_backup_verify() { verify_latest_backup_set; }
support_bundle_off_vm_backup_status() { show_off_vm_backup_status; }
support_bundle_restore_rehearsal_status() { show_restore_rehearsal_status; }
support_bundle_health_check_status() { show_health_check_status; }
support_bundle_go_live_status() { show_go_live_status; }

create_support_bundle() {
  require_sudo

  local timestamp bundle_name bundle_parent bundle_dir archive json_stderr validation_file
  timestamp="$(date +%Y%m%d-%H%M%S)"
  bundle_name="erpnext-dev-support-bundle-${timestamp}"
  bundle_parent="${SUPPORT_BUNDLE_DIR:-/tmp}"
  bundle_dir="${bundle_parent}/${bundle_name}"
  archive="${bundle_parent}/${bundle_name}.tar.gz"
  json_stderr="${bundle_dir}/doctor-json.stderr"
  validation_file="${bundle_dir}/doctor-json-validation.txt"

  log "Creating redacted support bundle"

  rm -rf "$bundle_dir" "$archive" 2>/dev/null || true
  mkdir -p "$bundle_dir"
  chmod 700 "$bundle_dir" 2>/dev/null || true

  support_bundle_write_file "${bundle_dir}/manifest.txt" support_bundle_manifest
  support_bundle_write_file "${bundle_dir}/doctor-plain.txt" run_doctor_plain

  if run_doctor_json > "${bundle_dir}/doctor.json" 2> "$json_stderr"; then
    :
  else
    echo "WARN: doctor --json returned a non-zero exit code." > "$validation_file"
  fi
  redact_file_in_place "${bundle_dir}/doctor.json"
  redact_file_in_place "$json_stderr"
  chmod 600 "${bundle_dir}/doctor.json" "$json_stderr" 2>/dev/null || true

  if [[ ! -s "$json_stderr" ]]; then
    rm -f "$json_stderr"
  fi

  if command -v python3 >/dev/null 2>&1 && python3 -m json.tool "${bundle_dir}/doctor.json" >/dev/null 2>&1; then
    echo "OK: doctor.json is valid JSON." >> "$validation_file"
  else
    echo "WARN: doctor.json could not be validated as JSON on this system." >> "$validation_file"
  fi
  chmod 600 "$validation_file" 2>/dev/null || true

  support_bundle_write_file "${bundle_dir}/system-summary.txt" support_bundle_system_summary
  support_bundle_write_file "${bundle_dir}/service-status.txt" support_bundle_service_status
  support_bundle_write_file "${bundle_dir}/port-status.txt" support_bundle_port_status
  support_bundle_write_file "${bundle_dir}/storage-status.txt" support_bundle_storage_status
  support_bundle_write_file "${bundle_dir}/ssl-status.txt" support_bundle_ssl_status
  support_bundle_write_file "${bundle_dir}/bench-status.txt" support_bundle_bench_status
  support_bundle_write_file "${bundle_dir}/recent-errors.txt" support_bundle_recent_errors
  support_bundle_write_file "${bundle_dir}/production-checklist.txt" support_bundle_production_checklist
  support_bundle_write_file "${bundle_dir}/backup-status.txt" support_bundle_backup_status
  support_bundle_write_file "${bundle_dir}/backup-verify.txt" support_bundle_backup_verify
  support_bundle_write_file "${bundle_dir}/off-vm-backup-status.txt" support_bundle_off_vm_backup_status
  support_bundle_write_file "${bundle_dir}/restore-rehearsal-status.txt" support_bundle_restore_rehearsal_status
  support_bundle_write_file "${bundle_dir}/health-check-status.txt" support_bundle_health_check_status
  support_bundle_write_file "${bundle_dir}/go-live-status.txt" support_bundle_go_live_status

  tar -C "$bundle_parent" -czf "$archive" "$bundle_name"
  chmod 600 "$archive" 2>/dev/null || true
  rm -rf "$bundle_dir"

  ok "Support bundle created: ${archive}"
  echo
  echo "Review before sharing:"
  echo "  tar -tzf ${archive}"
  echo "  mkdir -p /tmp/erpnext-support-review && tar -xzf ${archive} -C /tmp/erpnext-support-review"
  echo
  echo "This bundle intentionally excludes credential files, private keys, raw site_config.json secrets, tokens, and passwords."
  ui_next "Review archive contents before sharing."
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
    "payments:Frappe Payments"
    "webshop:Frappe Webshop / E-Commerce"
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






production_ops_summary() {
  local install_state_value runtime_value ssl_pair ssl_state ssl_detail
  local latest_lines completeness off_pair off_state off_detail
  local rehearsal_pair rehearsal_state rehearsal_detail health_pair health_state health_detail go_pair go_state go_detail

  install_state_value="$(production_quick_install_state 2>/dev/null || echo Unknown)"
  runtime_value="$(runtime_state 2>/dev/null || echo Unknown)"
  ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not confirmed')"
  ssl_state="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"

  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  if [[ -n "$latest_lines" ]]; then
    completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
  else
    completeness="none"
  fi

  off_pair="$(off_vm_backup_summary_pair 2>/dev/null || echo 'WARN|not configured')"
  off_state="${off_pair%%|*}"
  off_detail="${off_pair#*|}"
  rehearsal_pair="$(restore_rehearsal_summary_pair 2>/dev/null || echo 'WARN|not recorded')"
  rehearsal_state="${rehearsal_pair%%|*}"
  rehearsal_detail="${rehearsal_pair#*|}"
  go_pair="$(go_live_summary_pair 2>/dev/null || echo 'WARN|not recorded')"
  go_state="${go_pair%%|*}"
  go_detail="${go_pair#*|}"

  status_line "Runtime" "$([[ "$runtime_value" == Running* ]] && echo OK || echo WARN)" "$runtime_value"
  status_line "Install" "$([[ "$install_state_value" == Installed ]] && echo OK || echo WARN)" "$install_state_value"
  status_line "HTTPS" "$ssl_state" "$ssl_detail"

  if ufw_is_active; then
    status_line "Security" "OK" "UFW active"
  else
    status_line "Security" "WARN" "UFW not active"
  fi

  status_line "Local backup" "$([[ "$completeness" == complete ]] && echo OK || echo WARN)" "latest set ${completeness:-none}"
  status_line "Off-VM backup" "$off_state" "$off_detail"
  status_line "Restore rehearsal" "$rehearsal_state" "$rehearsal_detail"

  if health_check_timer_active; then
    health_pair="$(health_check_summary_pair 2>/dev/null || echo 'WARN|state unavailable')"
    health_state="${health_pair%%|*}"
    health_detail="${health_pair#*|}"
    status_line "Health monitoring" "$health_state" "timer active; $health_detail"
  else
    status_line "Health monitoring" "INFO" "timer not configured"
  fi

  status_line "Go-live validation" "$go_state" "$go_detail"
}

production_ops_breadcrumb_title() {
  printf 'ERPNext Production Operations > %s' "$1"
}

production_ops_services_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Services and Recovery")"
    echo "1) Service status"
    echo "2) Start ERPNext service"
    echo "3) Stop ERPNext service"
    echo "4) Restart ERPNext service"
    echo "5) Wait for ERPNext readiness"
    echo "6) Service logs"
    echo "7) Follow service logs"
    echo "8) Service recovery plan"
    menu_footer
    menu_read_choice services_choice
    case "$services_choice" in
      1) show_erpnext_service_status; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      2) start_erpnext_service; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      3) stop_erpnext_service; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      4) restart_erpnext_service; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      5) wait_for_erpnext_ready; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      6) show_erpnext_service_logs; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      7) follow_erpnext_service_logs ;;
      8) show_service_recovery_plan; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_backups_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Local Backups")"
    echo "1) Create database + files backup"
    echo "2) Backup status"
    echo "3) Verify latest backup"
    echo "4) Scheduled backup plan"
    echo "5) Configure scheduled backups"
    echo "6) Scheduled backup status"
    echo "7) Retention plan"
    echo "8) Retention status"
    echo "9) Cleanup old backups dry run"
    echo "10) Cleanup old backups"
    echo "11) Full backup/maintenance menu"
    menu_footer
    menu_read_choice local_backup_choice
    case "$local_backup_choice" in
      1) create_site_backup true; pause_after_screen "Press Enter to return to Local Backups..." ;;
      2) show_backup_status; pause_after_screen "Press Enter to return to Local Backups..." ;;
      3) verify_latest_backup_set; pause_after_screen "Press Enter to return to Local Backups..." ;;
      4) show_backup_schedule_plan; pause_after_screen "Press Enter to return to Local Backups..." ;;
      5) configure_backup_schedule; pause_after_screen "Press Enter to return to Local Backups..." ;;
      6) show_backup_schedule_status; pause_after_screen "Press Enter to return to Local Backups..." ;;
      7) show_backup_retention_plan; pause_after_screen "Press Enter to return to Local Backups..." ;;
      8) show_backup_retention_status; pause_after_screen "Press Enter to return to Local Backups..." ;;
      9) cleanup_old_backups dry-run; pause_after_screen "Press Enter to return to Local Backups..." ;;
      10) cleanup_old_backups prompt; pause_after_screen "Press Enter to return to Local Backups..." ;;
      11) run_backup_maintenance_menu ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_restore_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Restore Readiness and Rehearsal")"
    echo "1) Restore rehearsal status"
    echo "2) Restore rehearsal guide"
    echo "3) Restore rehearsal wizard"
    echo "4) Restore preflight"
    echo "5) Record completed restore rehearsal"
    echo "6) Restore rehearsal report"
    echo "7) List local backups"
    echo "8) Restore database only"
    echo "9) Restore database + files"
    menu_footer
    menu_read_choice restore_choice
    case "$restore_choice" in
      1) show_restore_rehearsal_status; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      2) show_restore_rehearsal_guide; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      3) restore_rehearsal_wizard; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      4) show_restore_preflight; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      5) record_restore_rehearsal; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      6) show_restore_rehearsal_report; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      7) list_site_backups; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      8) restore_site_database; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      9) restore_site_full; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_security_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Security and Firewall")"
    echo "1) Firewall hardening status"
    echo "2) VM firewall status"
    echo "3) Security hardening wizard"
    echo "4) Configure VM firewall"
    echo "5) Production firewall profile"
    echo "6) Configure Fail2Ban"
    echo "7) Fail2Ban status"
    echo "8) Cloud firewall checklist"
    menu_footer
    menu_read_choice security_choice
    case "$security_choice" in
      1) show_firewall_hardening_status; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      2) show_vm_firewall_status; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      3) security_hardening_wizard; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      4) configure_vm_firewall; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      5) configure_production_vm_firewall; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      6) configure_fail2ban; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      7) show_fail2ban_status; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      8) show_cloud_firewall_checklist; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_https_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "HTTPS and Certificates")"
    echo "1) Production SSL status"
    echo "2) SSL mode status"
    echo "3) Production HTTPS / SSL menu"
    echo "4) Cloudflare Origin CA status"
    echo "5) Cloudflare checklist"
    echo "6) SSL compatibility guide"
    menu_footer
    menu_read_choice https_choice
    case "$https_choice" in
      1) show_production_ssl_status; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      2) show_ssl_mode_status; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      3) show_production_ssl_menu; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      4) show_cloudflare_origin_ssl_status; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      5) show_cloudflare_checklist; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      6) show_ssl_mode_guide; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_support_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Support and Diagnostics")"
    echo "1) Doctor"
    echo "2) Doctor JSON"
    echo "3) Production checklist"
    echo "4) Final QA"
    echo "5) Command audit"
    echo "6) Create support bundle"
    echo "7) Show latest support bundle contents"
    echo "8) Storage status"
    echo "9) Port status"
    echo "10) Verify toolkit integrity"
    echo "11) Audit latest support bundle"
    menu_footer
    menu_read_choice support_choice
    case "$support_choice" in
      1) run_doctor_plain; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      2) run_doctor_json; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      3) show_production_checklist; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      4) final_qa_wizard; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      5) show_command_audit; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      6) create_support_bundle; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      7) show_latest_support_bundle_contents; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      8) show_storage_status; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      9) support_bundle_port_status; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      10) verify_toolkit_integrity; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      11) support_bundle_audit_archive; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_latest_support_bundle_contents() {
  require_sudo
  ui_box_start "Latest Support Bundle Contents"
  local latest_bundle
  latest_bundle="$(ls -t /tmp/erpnext-dev-support-bundle-*.tar.gz 2>/dev/null | head -n 1 || true)"
  if [[ -z "$latest_bundle" ]]; then
    status_line "Support bundle" "WARN" "no /tmp/erpnext-dev-support-bundle-*.tar.gz archive found"
    ui_next "$(toolkit_cmd support-bundle)"
    ui_box_end
    return 0
  fi
  status_line "Latest bundle" "OK" "$latest_bundle"
  echo
  tar -tzf "$latest_bundle" || warn "Could not list archive contents"
  ui_box_end
}

support_bundle_audit_archive() {
  local archive="${SUPPORT_BUNDLE_AUDIT_ARCHIVE:-}"
  local tmpdir listing_file hit_file rc=0 file_count=0

  if [[ -z "$archive" ]]; then
    archive="$(ls -t /tmp/erpnext-dev-support-bundle-*.tar.gz 2>/dev/null | head -n 1 || true)"
  fi

  ui_box_start "Support Bundle Audit"

  if [[ -z "$archive" ]]; then
    status_line "Support bundle" "WARN" "no /tmp/erpnext-dev-support-bundle-*.tar.gz archive found"
    ui_next "$(toolkit_cmd support-bundle)"
    ui_box_end
    return 1
  fi

  if [[ ! -f "$archive" ]]; then
    status_line "Archive" "FAIL" "not found: ${archive}"
    ui_box_end
    return 1
  fi

  status_line "Archive" "OK" "$archive"

  tmpdir="$(mktemp -d /tmp/erpnext-support-audit.XXXXXX)"
  listing_file="${tmpdir}/archive-list.txt"
  hit_file="${tmpdir}/audit-hits.txt"

  if ! tar -tzf "$archive" > "$listing_file" 2>"${tmpdir}/tar-list.stderr"; then
    status_line "Archive listing" "FAIL" "tar could not list archive"
    sed -n '1,40p' "${tmpdir}/tar-list.stderr" 2>/dev/null || true
    rm -rf "$tmpdir"
    ui_box_end
    return 1
  fi

  file_count="$(grep -cve '/$' "$listing_file" 2>/dev/null || echo 0)"
  status_line "Archive listing" "OK" "${file_count} file(s)"

  if grep -Ei '(^|/)(site_config\.json|site_config_backup\.json|.*credentials.*|id_rsa|id_ed25519|.*\.pem|.*\.key|.*\.sql(\.gz)?|.*database.*\.gz|.*private-files\.tar)$' "$listing_file" > "$hit_file"; then
    status_line "Forbidden filenames" "FAIL" "potential secret/backup filenames found"
    sed -n '1,80p' "$hit_file"
    rc=1
  else
    status_line "Forbidden filenames" "OK" "none found"
  fi

  if tar -xzf "$archive" -C "$tmpdir" 2>"${tmpdir}/tar-extract.stderr"; then
    if grep -RInE '(-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----|Bearer[[:space:]]+[A-Za-z0-9._~+/=-]+|("?(password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|authorization|cookie|db_password|admin_password)"?[[:space:]]*[:=][[:space:]]*[^[:space:],;}]+))'       --exclude='archive-list.txt'       --exclude='audit-hits.txt'       "$tmpdir" > "$hit_file" 2>/dev/null; then
      status_line "Secret pattern scan" "FAIL" "possible unredacted secret pattern found"
      sed -n '1,80p' "$hit_file"
      rc=1
    else
      status_line "Secret pattern scan" "OK" "no obvious secret patterns found"
    fi
  else
    status_line "Archive extract" "FAIL" "tar could not extract archive for content scan"
    sed -n '1,40p' "${tmpdir}/tar-extract.stderr" 2>/dev/null || true
    rc=1
  fi

  rm -rf "$tmpdir"

  if [[ "$rc" -eq 0 ]]; then
    status_line "Audit result" "OK" "support bundle passed filename and content checks"
  else
    status_line "Audit result" "FAIL" "review findings before sharing bundle"
  fi

  echo
  echo "Scope: best-effort audit for common secret filenames and obvious token/password/private-key patterns."
  echo "Always manually review support bundles before external sharing."
  ui_box_end
  return "$rc"
}

production_ops_wizard() {
  require_sudo
  while true; do
    ui_box_start "ERPNext Production Operations"
    status_line "Site" "INFO" "$SITE_NAME"
    status_line "Toolkit" "INFO" "v${SCRIPT_VERSION}"
    echo
    echo "Current state"
    production_ops_summary
    echo
    echo "1) System health and readiness"
    echo "2) Services and recovery"
    echo "3) Local backups"
    echo "4) Off-VM backups"
    echo "5) Restore readiness and rehearsal"
    echo "6) Health monitoring"
    echo "7) Security and firewall"
    echo "8) HTTPS and certificates"
    echo "9) Go-live validation"
    echo "10) Support and diagnostics"
    echo "11) Final QA"
    menu_footer quit-only
    menu_read_choice ops_choice
    case "$ops_choice" in
      1) show_release_readiness; pause_after_screen "Press Enter to return to Production Operations..." ;;
      2) production_ops_services_menu ;;
      3) production_ops_backups_menu ;;
      4) off_vm_backup_wizard; pause_after_screen "Press Enter to return to Production Operations..." ;;
      5) production_ops_restore_menu ;;
      6) PRODUCTION_OPS_CONTEXT=1 health_monitoring_wizard; pause_after_screen "Press Enter to return to Production Operations..." ;;
      7) production_ops_security_menu ;;
      8) production_ops_https_menu ;;
      9) show_go_live_status; pause_after_screen "Press Enter to return to Production Operations..." ;;
      10) production_ops_support_menu ;;
      11) final_qa_wizard; pause_after_screen "Press Enter to return to Production Operations..." ;;
      "") continue ;;
      b|B) return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}




show_command_audit() {
  ui_box_start "Command Audit / Key Workflows"
  status_line "Start here" "OK" "first-run, public-vm-guided-setup, public-vm-quickstart, local-dev-quickstart"
  status_line "Preflight" "OK" "install-preflight, environment-preflight"
  status_line "Toolkit CLI" "OK" "where-installed, install-cli, repair-cli, update-toolkit"
  status_line "Config" "OK" "set-domain, show-config, setup-effort-guide"
  status_line "Install/status" "OK" "guided-setup, status, doctor, support-bundle"
  status_line "Credentials" "OK" "credentials-info, credentials-show, credentials-file-status, credentials-secure, credentials-delete, reset-admin-password"
  status_line "Production SSL" "OK" "production-ssl-wizard, production-ssl-status, ssl-mode-status"
  status_line "Cloudflare" "OK" "cloudflare-origin-guide, configure-cloudflare-origin-ssl"
  status_line "Security" "OK" "security-hardening-wizard, vm-firewall-status, fail2ban-status"
  status_line "Firewall" "OK" "firewall-hardening-status, production-firewall-plan"
  status_line "Backups" "OK" "backup-files, backup-status, backup-verify, backup-hardening-wizard"
  status_line "Scheduled backups" "OK" "backup-schedule-plan, configure-backup-schedule, backup-schedule-status, scheduled-backup-status"
  status_line "Backup retention" "OK" "backup-retention-plan, backup-retention-status, cleanup-old-backups"
  status_line "Off-VM backup" "OK" "off-vm-backup-plan, configure-rsync-backup-target, run-off-vm-backup"
  status_line "Health monitoring" "OK" "health-monitoring-wizard, health-check, configure-health-check-timer, health-check-status, health-check-journal"
  status_line "Go-live validation" "OK" "go-live-record, go-live-status, cloud-firewall-checklist, cloudflare-checklist"
  status_line "Restore safety" "OK" "restore-rehearsal-guide, restore-rehearsal-status, restore-rehearsal-record, restore-preflight, restore-db, restore-full"
  status_line "Optional apps" "OK" "app-install-wizard, app-status, app-compatibility, install-payments, install-webshop, install-builder, install-lms, install-education, install-wiki, install-print-designer, install-drive, install-raven, advanced-app-tools"
  ui_box_end
  ui_next "$(toolkit_cmd release-readiness)" "$(toolkit_cmd help)"
}




show_advanced_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "Advanced Options"
    echo "============================================================"
    print_two_column_menu       "1) Install / Reinstall"       "2) Repair Environment"       "3) Uninstall / Reset"       "4) Autostart / Service Manager"       "5) Backup / Maintenance"       "6) App Library"       "7) Optional App Status"       "8) Full Health Report"       "9) VM Network Status"       "10) Environment / location check"       "11) KVM Fixed IP Guide"       "12) Multi-Environment Guide"       "13) Local VM HTTPS / SSL"       "14) Local SSL Status"       "15) Local SSL Guide"       "16) Local SSL Wizard"       "17) Trusted mkcert SSL Guide"       "18) Browser Trust Check Guide"       "19) Install/Replace Local SSL Cert"       "20) Verify Local SSL"       "21) Create Self-Signed Local Cert"       "22) Configure Local SSL"       "23) Disable Local SSL"       "24) Verify SSL Rollback"       "25) Storage Status"       "26) Expand Root Storage"       "27) Verify Storage"       "28) Domain Config"       "29) Production Readiness Preview"       "30) Production Domain Guide"       "31) Production SSL Guide"       "32) Public VM Readiness"       "33) Production SSL Plan"       "34) Production Firewall Plan"       "35) Firewall Hardening Status"       "36) Configure Production SSL"       "37) Production SSL Status"       "38) Disable Production SSL"       "39) Start Bench in Foreground"       "40) Show Service Logs"       "41) Access Submenu"       "42) Next Step"       "43) Verify ERPNext HTTP Access"       "44) App Install Wizard"       "45) App Rollback Guide"       "46) Install Environment Preflight"       "47) Change Local Domain"
    menu_footer
    menu_read_choice advanced_choice

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
      13) show_local_ssl_menu ;;
      14) show_ssl_status ;;
      15) show_local_ssl_guide ;;
      16) run_local_ssl_wizard ;;
      17) show_mkcert_local_ssl_guide ;;
      18) show_browser_trust_check_guide ;;
      19) install_local_ssl_cert ;;
      20) verify_local_ssl ;;
      21) create_self_signed_local_cert ;;
      22) configure_local_ssl ;;
      23) disable_local_ssl ;;
      24) verify_ssl_rollback ;;
      25) show_storage_status ;;
      26) expand_root_storage ;;
      27) verify_storage ;;
      28) show_domain_config ;;
      29) show_production_readiness ;;
      30) show_production_domain_guide ;;
      31) show_production_ssl_guide ;;
      32) show_public_vm_readiness ;;
      33) show_production_ssl_plan ;;
      34) show_production_firewall_plan ;;
      35) show_firewall_hardening_status ;;
      36) configure_production_ssl ;;
      37) show_production_ssl_status ;;
      38) disable_production_ssl ;;
      39) run_foreground_start ;;
      40) show_erpnext_service_logs ;;
      41) show_access_menu ;;
      42) show_next_step ;;
      43) verify_access ;;
      44) run_app_install_wizard ;;
      45) show_app_rollback_guide ;;
      46) run_install_preflight ;;
      47) change_local_domain_wizard ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

menu_navigation_self_test() {
  # Safe smoke test for interactive menus. It checks navigation input only.
  # It does not choose install, SSL, firewall, backup, app, or destructive actions.
  local script rc out failures=0 tested=0
  local action input
  local invoke=(bash)
  script="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      invoke=(sudo -E bash)
    else
      ui_box_start "Menu Navigation Self-Test"
      status_line "Menu navigation" "FAIL" "menu-self-test requires root or sudo"
      ui_box_end
      return 1
    fi
  fi

  ui_box_start "Menu Navigation Self-Test"
  echo "Testing q/Q and b/B handling for non-destructive menu entry points."
  echo

  local quit_actions=(
    menu
    first-run
    advanced
    access
    status-menu
    local-ssl-menu
    local-ssl-wizard
    production-ssl-menu
    app-library
    advanced-app-tools
    backup-menu
    maintenance
    backup-hardening-wizard
    off-vm-backup-wizard
    production-ops-wizard
    health-monitoring-wizard
    security-hardening-wizard
    final-qa-wizard
    uninstall
  )

  for action in "${quit_actions[@]}"; do
    for input in q Q; do
      tested=$((tested + 1))
      out="$(printf '%s\n' "$input" | timeout 5 "${invoke[@]}" "$script" "$action" 2>&1)"
      rc=$?
      if (( rc != 0 )) || printf '%s\n' "$out" | grep -Eqi 'Invalid option|command not found|unbound variable|syntax error'; then
        failures=$((failures + 1))
        status_line "${action} ${input}" "FAIL" "q/Q did not exit cleanly"
      fi
    done
  done

  local back_actions=(
    first-run
    advanced
    access
    status-menu
    local-ssl-menu
    local-ssl-wizard
    production-ssl-menu
    app-library
    advanced-app-tools
    backup-menu
    maintenance
    backup-hardening-wizard
    off-vm-backup-wizard
    production-ops-wizard
    health-monitoring-wizard
    security-hardening-wizard
    final-qa-wizard
  )

  for action in "${back_actions[@]}"; do
    for input in b B; do
      tested=$((tested + 1))
      out="$(printf '%s\nq\n' "$input" | timeout 5 "${invoke[@]}" "$script" "$action" 2>&1)"
      rc=$?
      if (( rc != 0 )) || printf '%s\n' "$out" | grep -Eqi 'Invalid option|command not found|unbound variable|syntax error'; then
        failures=$((failures + 1))
        status_line "${action} ${input}" "FAIL" "b/B did not return cleanly"
      fi
    done
  done

  # Test a few nested submenu paths where prior bugs could drop the user into shell.
  local nested_tests=(
    "advanced|4|q"
    "advanced|5|q"
    "advanced|6|q"
    "advanced|13|q"
    "menu|8|q"
    "menu|9|q"
    "menu|12|q"
    "menu|13|q"
    "health-monitoring-wizard|3|q"
    "production-ops-wizard|6|b"
    "production-ops-wizard|10|b"
  )
  local row root select quit
  for row in "${nested_tests[@]}"; do
    IFS='|' read -r root select quit <<< "$row"
    tested=$((tested + 1))
    out="$(printf '%s\n%s\n' "$select" "$quit" | timeout 5 "${invoke[@]}" "$script" "$root" 2>&1)"
    rc=$?
    if (( rc != 0 )) || printf '%s\n' "$out" | grep -Eqi 'command not found|unbound variable|syntax error'; then
      failures=$((failures + 1))
      status_line "${root}->${select}->${quit}" "FAIL" "nested menu quit failed"
    fi
  done

  status_line "Tests executed" "INFO" "$tested"
  if (( failures == 0 )); then
    status_line "Menu navigation" "OK" "q/Q and b/B handled cleanly in tested menus"
  else
    status_line "Menu navigation" "FAIL" "${failures} failure(s) detected"
    ui_box_end
    return 1
  fi
  ui_box_end
}

show_help() {
  cat <<EOF_HELP
${APP_NAME} v${SCRIPT_VERSION}

Usage:
  $(toolkit_cmd "[command]")

Start here:
  first-run           Pick local VM, public VM, or maintenance flow
  public-vm-guided-setup Guided production VPS setup; domain -> DNS -> install -> HTTPS -> security -> QA
  public-vm-quickstart Public VM manual menu for production tasks
  local-dev-quickstart Local VM setup; prompts for domain, Enter defaults to erp.test
  install-preflight   Check OS, internet, CPU, RAM, disk, and /tmp before installing
  set-domain          Save public domain and site config
  show-config         Show saved toolkit config
  setup-effort-guide  Show commands/input count by setup type
  setup-lifecycle-plan Show recommended local/production setup order

Core:
  version             Print toolkit version
  where-installed     Show active script, stable /opt path, CLI path, and config path
  verify-toolkit      Show installed script SHA256 and compare against SHA256SUMS when available
  install-cli         Install or repair the erpnext-dev command
  repair-cli          Alias for install-cli
  update-toolkit      Download latest erpnext-dev.sh from GitHub and update /opt copy
  menu-self-test      Validate q/Q and b/B handling across interactive menus
  guided-setup        Guided install / repair workflow
  status              Compact ERPNext status
  verify-access       HTTP access checks
  access-info         Show Desk, login, portal, and host access URLs
  education-access-info Show Education portal and ERPNext Desk URLs
  credentials-info    Safe credential overview; does not print passwords
  credentials-show    Show generated passwords after confirmation
  credentials-file-status Check owner/mode/age of the credentials file
  credentials-secure  Set credentials file to root:root 600
  credentials-delete  Delete local plaintext credentials file after secure handoff
  reset-admin-password Reset ERPNext Administrator password safely
  next-step           Recommended next action
  doctor --plain      Safe diagnostics
  support-bundle      Redacted troubleshooting archive
  support-bundle-audit Audit latest support bundle for forbidden filenames and obvious secret patterns
  environment-preflight Alias for install-preflight

Local VM HTTPS / SSL:
  local-ssl-menu       Local VM HTTPS / SSL submenu
  local-ssl-wizard     Guided local HTTPS setup; Back opens main menu when run directly
  trusted-mkcert-setup Guided mkcert setup; installs copied cert/key when available
  change-local-domain  Rename the local VM domain/site and update toolkit config
  local-domain-status  Show dynamic VM IP, local domain, and host mapping status
  local-access-doctor  Diagnose local URL/DNS/firewall/access issues
  local-host-checkpoint Required safe host mapping checkpoint before local HTTPS
  host-dns-guide       Print host-side /etc/hosts commands using the current VM IP
  local-fixed-ip-guide  Print KVM/libvirt DHCP reservation guidance for a stable local VM IP
  local-ssl-guide      Local SSL guide
  ssl-status           Local SSL status
  install-local-ssl-cert Install/replace local certificate from /tmp
  create-self-signed-local-cert Create local self-signed certificate
  verify-local-ssl     Verify local HTTPS access
  disable-local-ssl    Disable local HTTPS config

Production / HTTPS:
  production-readiness    Production-candidate check
  production-ssl-menu     Production HTTPS / SSL submenu
  production-ssl-wizard   Choose Let's Encrypt or Cloudflare Origin CA
  production-ssl-status   HTTPS/Nginx/certificate status
  ssl-mode-status         Recommended SSL mode for current config
  ssl-mode-guide          SSL compatibility matrix
  public-vm-readiness     Public VM DNS/access/listener check

Security:
  security-hardening-wizard  Environment-aware UFW + Fail2Ban workflow
  security-mode-status       Show local vs production hardening context
  local-firewall-profile     Apply local VM profile; keeps 8000/9000 reachable privately
  production-firewall-profile Apply production profile; blocks backend ports
  repair-local-access        Restore local erp.test / port 8000 access after over-hardening
  firewall-rollback-snapshots Show saved UFW rule snapshots
  firewall-hardening-status  Cloud firewall + backend-port guidance
  vm-firewall-status         UFW status
  fail2ban-status            SSH jail status

Backup / Restore:
  backup-files        Database + files backup
  backup-status       Backup inventory and latest-set status
  backup-verify       Verify latest backup files without restoring
  backup-schedule-plan Show scheduled-backup design
  configure-backup-schedule Enable local scheduled backups with systemd
  backup-schedule-status Show scheduled backup timer status
  scheduled-backup-status Alias for backup-schedule-status
  backup-retention-plan Show local backup retention policy
  cleanup-old-backups-dry-run Preview old backup cleanup
  off-vm-backup-plan  Show rsync off-VM backup plan
  off-vm-backup-guided-setup Guided two-server off-VM backup setup
  generate-off-vm-backup-key Create dedicated rsync SSH key on ERPNext VM
  backup-server-setup Prepare a remote Linux server to receive backups
  configure-rsync-backup-target Save off-VM rsync target
  off-vm-backup-dry-run Preview off-VM rsync copy
  run-off-vm-backup   Copy backups to configured off-VM target
  off-vm-backup-status Show off-VM backup configuration/status
  off-vm-backup-guide Commands to copy backups off this VM
  health-monitoring-wizard Guided health timer and monitoring workflow
  health-check       Compact production health check
  health-check-run-now Alias for health-check
  configure-health-check-timer Enable periodic health checks with systemd
  health-check-status Show health check timer and last health status
  health-check-journal Show recent health-check systemd journal output
  service-recovery-plan Manual service recovery checklist
  restore-preflight   Safe restore readiness check
  restore-rehearsal-guide Safe restore test plan
  restore-rehearsal-status Show recorded restore rehearsal status
  restore-rehearsal-record Record completed restore rehearsal evidence on production VM
  restore-rehearsal-report Print restore evidence from a disposable restore VM
  go-live-record    Record snapshot/firewall/Cloudflare go-live validation
  go-live-status    Show recorded external go-live validation status
  cloud-firewall-checklist Show provider firewall checklist
  cloudflare-checklist Show Cloudflare DNS/SSL checklist
  restore-rehearsal-wizard Guided off-VM restore rehearsal workflow
  restore-key-setup   Generate a temporary restore SSH key and exact backup-server command
  pull-off-vm-backup  Pull off-VM backups to this restore VM with rsync
  backup-server-add-restore-key Add a temporary restore key on the backup server
  backup-server-remove-restore-key Remove temporary restore keys from the backup server
  backup-hardening-wizard Backup and restore readiness workflow

Production checklist:
  production-checklist  Go-live readiness checklist
  release-readiness    Compact final QA readiness summary
  final-qa             Final QA / release-readiness wizard
  production-ops-wizard Unified production operations dashboard
  production-ops-dashboard Alias for production-ops-wizard
  backup-retention-plan Backup retention and cleanup plan
  cleanup-old-backups-dry-run Preview old backup cleanup

Apps:
  app-install-wizard  Optional Frappe app installer
  app-status          Optional app status
  app-compatibility   Optional app compatibility matrix
  install-payments    Install Frappe Payments
  install-webshop     Install Frappe Webshop / E-Commerce
  install-builder     Install Frappe Builder
  install-lms         Install Frappe Learning / LMS
  install-education   Install Frappe Education
  install-wiki        Install Frappe Wiki
  install-print-designer Install Frappe Print Designer
  install-drive       Install Frappe Drive
  install-raven       Install Raven Team Chat
  advanced-app-tools Advanced app tools for custom apps and repairs
  install-custom-app Advanced: install trusted custom app from Git URL

Guides:
  production-domain-plan   DNS/domain plan
  production-ssl-plan      SSL plan
  production-firewall-plan Firewall plan
  cloudflare-origin-guide  Cloudflare Origin CA guide
  vm-firewall-plan         UFW plan

Menus:
  menu        Main menu
  advanced    Full advanced menu
  maintenance Backup/maintenance menu

Examples:
  $(toolkit_cmd first-run)
  $(toolkit_cmd public-vm-guided-setup)
  $(toolkit_cmd public-vm-quickstart)
  $(toolkit_cmd local-dev-quickstart)
  $(toolkit_cmd local-ssl-menu)
  $(toolkit_cmd production-ssl-wizard)
  $(toolkit_cmd security-hardening-wizard)
  $(toolkit_cmd final-qa)
  $(toolkit_cmd production-ops-wizard)

Options:
  -y, --yes  Assume yes for supported confirmations

Verified release entry points:
  Public VM:
    VERSION="v${SCRIPT_VERSION}"; curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/\${VERSION}/erpnext-dev.sh"; curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/\${VERSION}/SHA256SUMS"; sha256sum -c SHA256SUMS; chmod +x erpnext-dev.sh; sudo ./erpnext-dev.sh public-vm-guided-setup
  Local VM:
    VERSION="v${SCRIPT_VERSION}"; curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/\${VERSION}/erpnext-dev.sh"; curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/\${VERSION}/SHA256SUMS"; sha256sum -c SHA256SUMS; chmod +x erpnext-dev.sh; sudo ./erpnext-dev.sh local-dev-quickstart

Common environment overrides:
  SITE_NAME=erp.test
  PRODUCTION_DOMAIN=erp.company.com
  LETSENCRYPT_EMAIL=admin@example.com
  LETSENCRYPT_STAGING=true|false
  ADMIN_SSH_SOURCE_IP=68.144.2.171/32
  FAIL2BAN_SSH_BANTIME=1h
  FAIL2BAN_SSH_FINDTIME=10m
  FAIL2BAN_SSH_MAXRETRY=5
  BACKUP_SCHEDULE_ON_CALENDAR=daily
  BACKUP_SCHEDULE_RANDOM_DELAY=30m
  BACKUP_RETENTION_KEEP_COMPLETE=14
  BACKUP_RETENTION_WARN_DISK_PERCENT=80
  ERPNEXT_ALLOW_UNSAFE_INSTALL=false
  OFF_VM_BACKUP_TARGET=backup@example.com:/srv/erpnext-backups/site/
  OFF_VM_BACKUP_SSH_IDENTITY=/root/.ssh/id_ed25519
  OFF_VM_BACKUP_RSYNC_DELETE=false
  PAYMENTS_BRANCH=                # blank = repository default branch
  WEBSHOP_BRANCH=develop
  EDUCATION_BRANCH=version-16
  LMS_BRANCH=                     # blank = repository default branch

Use $(toolkit_cmd advanced) for the complete command menu.
After first run, use the short command: sudo erpnext-dev menu
EOF_HELP
}

show_menu() {
  while true; do
    echo
    echo "============================================================"
    echo "${APP_NAME} v${SCRIPT_VERSION}"
    echo "============================================================"
    print_two_column_menu       "1) Start here / setup wizard"       "2) Public VM quickstart"       "3) Local VM quickstart"       "4) Status"       "5) Start service"       "6) Stop service"       "7) Verify access"       "8) Local VM HTTPS / SSL"       "9) Production HTTPS / SSL"       "10) Security profiles"       "11) Backup / maintenance"       "12) Optional apps"       "13) Advanced"       "14) Final QA"       "15) Production operations"       "16) Help"
    menu_footer quit-only
    menu_read_choice choice

    case "$choice" in
      1) run_first_run_wizard ;;
      2) run_public_vm_guided_setup ;;
      3) run_local_dev_quickstart ;;
      4) show_status_menu ;;
      5) run_start ;;
      6) run_stop ;;
      7) verify_access ;;
      8) show_local_ssl_menu ;;
      9) show_production_ssl_menu ;;
      10) security_hardening_wizard ;;
      11) run_backup_maintenance_menu ;;
      12) show_app_library_menu ;;
      13) show_advanced_menu ;;
      14) final_qa_wizard ;;
      15) production_ops_wizard ;;
      16) show_help ;;
      q|Q) exit 0 ;;
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
      --plain)
        DOCTOR_FORMAT="plain"
        shift
        ;;
      --json)
        DOCTOR_FORMAT="json"
        shift
        ;;
      first-run|start-here|quickstart|setup-wizard|public-vm-quickstart|public-setup|public-vm-guided-setup|public-guided-setup|production-guided-setup|local-dev-quickstart|local-setup|install-preflight|environment-preflight|set-domain|show-config|guided-setup|setup|install|repair|status|status-menu|runtime-status|install-status|service-summary|doctor|support-bundle|support|support-bundle-audit|audit-support-bundle|support-bundle-audit-test|full-status|start|stop|uninstall|advanced|access|verify-access|access-info|education-access-info|portal-access-info|desk-url|credentials-info|credentials|login-info|credentials-show|show-credentials|credentials-file-status|credentials-secure|credentials-delete|reset-admin-password|admin-password-reset|next-step|local-ssl-menu|local-https|local-vm-ssl|local-ssl-wizard|ssl-wizard|trusted-mkcert-setup|mkcert-setup|access-menu|access-info|education-access-info|portal-access-info|desk-url|backup-menu|backup|backup-files|backup-status|backup-verify|verify-backups|off-vm-backup-guide|restore-rehearsal-guide|restore-rehearsal-status|restore-rehearsal-record|restore-rehearsal-report|go-live-record|go-live-status|cloud-firewall-checklist|cloudflare-checklist|restore-rehearsal-wizard|restore-key-setup|pull-off-vm-backup|backup-server-add-restore-key|backup-server-remove-restore-key|backup-server-list-restore-keys|production-checklist|release-readiness|final-qa|final-qa-wizard|command-audit|release-notes-guide|backup-hardening-wizard|backup-wizard|backup-schedule-plan|configure-backup-schedule|backup-schedule-status|scheduled-backup-status|disable-backup-schedule|scheduled-backups|backup-retention-plan|backup-retention-status|cleanup-old-backups|cleanup-old-backups-dry-run|backup-cleanup-dry-run|backup-cleanup|off-vm-backup-plan|off-vm-backup-guided-setup|generate-off-vm-backup-key|off-vm-backup-keygen|backup-server-setup|prepare-backup-server|off-vm-backup-server-setup|configure-rsync-backup-target|off-vm-backup-dry-run|run-off-vm-backup|off-vm-backup-status|disable-off-vm-backup|off-vm-backup-wizard|credentials-info|credentials|login-info|credentials-show|show-credentials|credentials-file-status|credentials-secure|credentials-delete|reset-admin-password|admin-password-reset|health-check|health-check-run-now|configure-health-check-timer|health-check-status|health-check-journal|disable-health-check-timer|health-monitoring-wizard|production-monitoring-wizard|service-recovery-plan|restore-preflight|restore-rehearsal-wizard|restore-key-setup|pull-off-vm-backup|backup-server-add-restore-key|backup-server-remove-restore-key|backup-server-list-restore-keys|production-ops-wizard|production-ops-dashboard|operations-wizard|operations-dashboard|ops-wizard|ops-dashboard|list-backups|backups|restore-db|restore-full|maintenance|migrate|build|clear-cache|restart|wait-ready|menu|help|-h|--help|version|--version|where-installed|verify-toolkit|toolkit-verify|verify-install|install-cli|repair-cli|update-toolkit|menu-self-test|menu-navigation-self-test|foreground-start|enable-autostart|disable-autostart|service-start|service-stop|service-restart|service-status|logs|logs-follow|kvm-guide|kvm-identify|network-status|local-domain-status|local-host-checkpoint|host-dns-checkpoint|host-mapping-checkpoint|local-access-doctor|hosts-command|print-hosts-command|host-dns-guide|local-fixed-ip-guide|fixed-ip-guide|kvm-fixed-ip-guide|host-test|ssl-roadmap|ssl-status|local-ssl-guide|mkcert-guide|trusted-local-ssl-guide|browser-trust-guide|trust-check-guide|ssl-rollback-guide|verify-ssl-rollback|verify-local-ssl|install-local-ssl-cert|replace-local-ssl-cert|create-self-signed-local-cert|self-signed-local-cert|configure-local-ssl|disable-local-ssl|environment-check|where-am-i|site-config|domain-config|change-local-domain|local-domain-wizard|rename-local-site|change-site-domain|storage-status|storage-debug|expand-root-storage|verify-storage|production-readiness|production-plan|prod-plan|production-domain-plan|prod-domain-plan|public-vm-readiness|public-readiness|production-ssl-plan|prod-ssl-plan|production-firewall-plan|prod-firewall-plan|firewall-hardening-status|firewall-status|hardening-status|vm-firewall-plan|ufw-plan|configure-vm-firewall|local-firewall-profile|local-security-profile|production-firewall-profile|production-security-profile|repair-local-access|firewall-rollback-snapshots|vm-firewall-status|ufw-status|configure-fail2ban|fail2ban-status|security-hardening-wizard|vm-firewall-wizard|ufw-ssh-admin-only|production-ssl-menu|production-https|production-https-menu|configure-production-ssl|production-ssl-wizard|ssl-provider-wizard|ssl-mode-status|ssl-mode-guide|ssl-compatibility|setup-effort-guide|setup-step-count|setup-lifecycle-plan|setup-order-plan|configure-cloudflare-origin-ssl|install-cloudflare-origin-cert|switch-to-cloudflare-origin-ssl|cloudflare-origin-ssl-status|cloudflare-origin-guide|production-ssl-status|ssl-mode-status|ssl-mode-guide|ssl-compatibility|setup-effort-guide|setup-step-count|disable-production-ssl|production-domain-guide|production-ssl-guide|repair-site-config|site-name-guide|custom-site-guide|multi-env-guide|app-library|apps|list-apps|app-status|app-compatibility|app-compat|app-preflight|install-crm|install-hrms|install-helpdesk|install-telephony|install-insights|install-payments|install-webshop|install-ecommerce|install-builder|install-lms|install-education|install-wiki|install-print-designer|install-drive|install-raven|advanced-app-tools|app-advanced-tools|custom-app-tools|install-custom-app|app-install-wizard|app-wizard|app-install-guide|app-rollback-guide|repair-app-registry)
        ACTION="$1"
        shift
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done

  if [[ -z "${ACTION}" && "${DOCTOR_FORMAT}" != "human" ]]; then
    ACTION="doctor"
  fi
}

main() {
  parse_args "$@"

  if action_requires_lock "${ACTION:-menu}"; then
    acquire_toolkit_lock
  fi

  case "${ACTION:-menu}" in
    ""|menu) show_menu ;;
    version|--version) echo "${APP_NAME} v${SCRIPT_VERSION}" ;;
    where-installed) show_where_installed ;;
    verify-toolkit|toolkit-verify|verify-install) verify_toolkit_integrity ;;
    install-cli) install_toolkit_cli ;;
    repair-cli) repair_toolkit_cli ;;
    update-toolkit) update_toolkit ;;
    menu-self-test|menu-navigation-self-test) menu_navigation_self_test ;;
    first-run|start-here|quickstart|setup-wizard) run_first_run_wizard ;;
    public-vm-guided-setup|public-guided-setup|production-guided-setup) run_public_vm_guided_setup ;;
    public-vm-quickstart|public-setup) run_public_vm_quickstart ;;
    local-dev-quickstart|local-setup) run_local_dev_quickstart ;;
    install-preflight|environment-preflight) run_install_preflight ;;
    set-domain) prompt_and_save_public_domain ;;
    show-config) show_config_summary ;;
    guided-setup) run_guided_setup ;;
    setup|install) run_install ;;
    repair) run_repair ;;
    status) run_status ;;
    status-menu) show_status_menu ;;
    runtime-status) run_runtime_status ;;
    install-status) run_installation_status ;;
    service-summary) run_service_summary ;;
    doctor|full-status)
      case "$DOCTOR_FORMAT" in
        plain) run_doctor_plain ;;
        json) run_doctor_json ;;
        *) run_full_status ;;
      esac
      ;;
    support-bundle|support) create_support_bundle ;;
    support-bundle-audit|audit-support-bundle|support-bundle-audit-test) support_bundle_audit_archive ;;
    start) run_start ;;
    stop) run_stop ;;
    uninstall) run_uninstall_menu ;;
    advanced) show_advanced_menu ;;
    access|access-menu) show_access_menu ;;
    verify-access) verify_access ;;
    access-info|desk-url) show_access_info ;;
    education-access-info|portal-access-info) show_education_access_info ;;
    credentials-info|credentials|login-info) show_credentials_info ;;
    credentials-show|show-credentials) credentials_show ;;
    credentials-file-status) show_credentials_file_status ;;
    credentials-secure) credentials_secure ;;
    credentials-delete) credentials_delete ;;
    reset-admin-password|admin-password-reset) reset_admin_password ;;
    next-step) show_next_step ;;
    local-ssl-menu|local-https|local-vm-ssl) show_local_ssl_menu main ;;
    local-ssl-wizard|ssl-wizard) run_local_ssl_wizard main ;;
    backup-menu) run_backup_maintenance_menu ;;
    app-library|apps) show_app_library_menu ;;
    app-install-wizard|app-wizard) run_app_install_wizard ;;
    app-install-guide) show_app_install_guide ;;
    app-rollback-guide) show_app_rollback_guide ;;
    advanced-app-tools|app-advanced-tools|custom-app-tools) show_advanced_app_tools_menu ;;
    list-apps) show_installed_apps ;;
    app-status) run_app_status ;;
    app-compatibility|app-compat|app-preflight) show_app_compatibility_matrix ;;
    install-crm) install_app_profile crm ;;
    install-hrms) install_app_profile hrms ;;
    install-helpdesk) install_app_profile helpdesk ;;
    install-telephony) install_app_profile telephony ;;
    install-insights) install_app_profile insights ;;
    install-payments) install_app_profile payments ;;
    install-webshop|install-ecommerce) install_app_profile webshop ;;
    install-builder) install_app_profile builder ;;
    install-lms) install_app_profile lms ;;
    install-education) install_app_profile education ;;
    install-wiki) install_app_profile wiki ;;
    install-print-designer) install_app_profile print_designer ;;
    install-drive) install_app_profile drive ;;
    install-raven) install_app_profile raven ;;
    install-custom-app) install_custom_app_interactive ;;
    repair-app-registry) repair_app_registry ;;
    backup) create_site_backup false ;;
    backup-files) create_site_backup true ;;
    backup-status) show_backup_status ;;
    backup-verify|verify-backups) verify_latest_backup_set ;;
    off-vm-backup-guide) show_off_vm_backup_guide ;;
    restore-rehearsal-guide) show_restore_rehearsal_guide ;;
    restore-rehearsal-status) show_restore_rehearsal_status ;;
    restore-rehearsal-record) record_restore_rehearsal ;;
    restore-rehearsal-report) show_restore_rehearsal_report ;;
    go-live-record) record_go_live_validation ;;
    go-live-status) show_go_live_status ;;
    cloud-firewall-checklist) show_cloud_firewall_checklist ;;
    cloudflare-checklist) show_cloudflare_checklist ;;
    production-checklist) show_production_checklist ;;
    release-readiness) show_release_readiness ;;
    command-audit) show_command_audit ;;
    release-notes-guide) show_release_notes_guide ;;
    final-qa|final-qa-wizard) final_qa_wizard ;;
    backup-hardening-wizard|backup-wizard) backup_hardening_wizard ;;
    backup-schedule-plan|scheduled-backups) show_backup_schedule_plan ;;
    configure-backup-schedule) configure_backup_schedule ;;
    backup-schedule-status|scheduled-backup-status) show_backup_schedule_status ;;
    disable-backup-schedule) disable_backup_schedule ;;
    backup-retention-plan) show_backup_retention_plan ;;
    backup-retention-status) show_backup_retention_status ;;
    cleanup-old-backups|backup-cleanup) cleanup_old_backups prompt ;;
    cleanup-old-backups-dry-run|backup-cleanup-dry-run) cleanup_old_backups dry-run ;;
    off-vm-backup-plan) show_off_vm_backup_plan ;;
    off-vm-backup-guided-setup) off_vm_backup_guided_setup ;;
    generate-off-vm-backup-key|off-vm-backup-keygen) generate_off_vm_backup_key ;;
    backup-server-setup|prepare-backup-server|off-vm-backup-server-setup) backup_server_setup ;;
    configure-rsync-backup-target) configure_rsync_backup_target ;;
    off-vm-backup-dry-run) run_off_vm_backup_rsync dry-run ;;
    run-off-vm-backup) run_off_vm_backup_rsync run ;;
    off-vm-backup-status) show_off_vm_backup_status ;;
    disable-off-vm-backup) disable_off_vm_backup ;;
    off-vm-backup-wizard) off_vm_backup_wizard ;;
    health-check|health-check-run-now) run_health_check ;;
    configure-health-check-timer) configure_health_check_timer ;;
    health-check-status) show_health_check_status ;;
    health-check-journal) show_health_check_journal ;;
    disable-health-check-timer) disable_health_check_timer ;;
    health-monitoring-wizard|production-monitoring-wizard) health_monitoring_wizard ;;
    service-recovery-plan) show_service_recovery_plan ;;
    restore-preflight) show_restore_preflight ;;
    restore-rehearsal-wizard) restore_rehearsal_wizard ;;
    restore-key-setup) generate_restore_backup_key ;;
    pull-off-vm-backup) pull_off_vm_backup_to_restore_vm ;;
    backup-server-add-restore-key) backup_server_add_restore_key ;;
    backup-server-remove-restore-key) backup_server_remove_restore_key ;;
    backup-server-list-restore-keys) backup_server_list_restore_keys ;;
    production-ops-wizard|production-ops-dashboard|operations-wizard|operations-dashboard|ops-wizard|ops-dashboard) production_ops_wizard ;;
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
    kvm-guide|local-fixed-ip-guide|fixed-ip-guide|kvm-fixed-ip-guide) show_kvm_fixed_ip_guide ;;
    kvm-identify) show_kvm_vm_identification_guide ;;
    network-status) show_network_status ;;
    local-domain-status) show_local_domain_status ;;
    local-host-checkpoint|host-dns-checkpoint|host-mapping-checkpoint) show_local_host_mapping_checkpoint ;;
    local-access-doctor) local_access_doctor ;;
    hosts-command|print-hosts-command|host-dns-guide) show_host_hosts_command ;;
    host-test) show_host_access_test_guide ;;
    ssl-roadmap) show_ssl_roadmap_guide ;;
    ssl-status) show_ssl_status ;;
    local-ssl-guide) show_local_ssl_guide ;;
    mkcert-guide|trusted-local-ssl-guide) show_mkcert_local_ssl_guide ;;
    trusted-mkcert-setup|mkcert-setup) run_trusted_mkcert_setup ;;
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
    change-local-domain|local-domain-wizard|rename-local-site|change-site-domain) change_local_domain_wizard ;;
    production-readiness) show_production_readiness ;;
    production-plan|prod-plan) show_production_plan ;;
    production-domain-plan|prod-domain-plan) show_production_domain_plan ;;
    public-vm-readiness|public-readiness) show_public_vm_readiness ;;
    production-ssl-plan|prod-ssl-plan) show_production_ssl_plan ;;
    production-firewall-plan|prod-firewall-plan) show_production_firewall_plan ;;
    firewall-hardening-status|firewall-status|hardening-status) show_firewall_hardening_status ;;
    vm-firewall-plan|ufw-plan) vm_firewall_plan ;;
    security-mode-status) security_mode_status ;;
    configure-vm-firewall) configure_vm_firewall ;;
    local-firewall-profile|local-security-profile) configure_local_vm_firewall ;;
    production-firewall-profile|production-security-profile) configure_production_vm_firewall ;;
    repair-local-access) repair_local_access ;;
    firewall-rollback-snapshots) show_firewall_rollback_snapshots ;;
    vm-firewall-status|ufw-status) show_vm_firewall_status ;;
    configure-fail2ban) configure_fail2ban ;;
    fail2ban-status) show_fail2ban_status ;;
    security-hardening-wizard|vm-firewall-wizard) security_hardening_wizard ;;
    ufw-ssh-admin-only) configure_ufw_ssh_admin_only ;;
    production-ssl-menu|production-https|production-https-menu) show_production_ssl_menu ;;
    production-ssl-wizard|ssl-provider-wizard) production_ssl_wizard ;;
    configure-production-ssl) configure_production_ssl ;;
    configure-cloudflare-origin-ssl|install-cloudflare-origin-cert|switch-to-cloudflare-origin-ssl) configure_cloudflare_origin_ssl ;;
    cloudflare-origin-ssl-status) show_cloudflare_origin_ssl_status ;;
    cloudflare-origin-guide) show_cloudflare_origin_guide ;;
    production-ssl-status) show_production_ssl_status ;;
    ssl-mode-status) show_ssl_mode_status ;;
    ssl-mode-guide|ssl-compatibility) show_ssl_mode_guide ;;
    setup-effort-guide|setup-step-count) show_setup_effort_guide ;;
    setup-lifecycle-plan|setup-order-plan) show_setup_lifecycle_plan ;;
    disable-production-ssl) disable_production_ssl ;;
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
