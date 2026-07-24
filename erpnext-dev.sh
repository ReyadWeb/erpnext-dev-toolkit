#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================
# ERPNext / Frappe Developer Toolkit
# Supported hosts: Ubuntu 24.04 / 26.04 LTS and Debian 13 (native or Docker)
# Default: Frappe v16 + ERPNext v16 + site erp.test
# Mode: local dev (bench start) or production (supervisor: gunicorn + workers)
# ============================================================

APP_NAME="ERPNext Developer Toolkit"
SCRIPT_VERSION="1.19.21-beta.4"

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
RUNTIME_MODE="${RUNTIME_MODE:-}"
# Which OS the operator's HOST machine runs, so host-side instructions
# (/etc/hosts mapping, connectivity tests, mkcert trust, stable VM IP) match it.
# Empty means "not chosen yet"; host emitters then fall back to linux so existing
# Linux users are unaffected. Persisted in the toolkit config and set via set-host-os.
HOST_OS_ENV_PROVIDED=0
if [[ -n "${HOST_OS+x}" ]]; then
  HOST_OS_ENV_PROVIDED=1
fi
HOST_OS="${HOST_OS:-}"
# Deployment engine: native (direct VM install, default) or docker (containerized
# stack wrapping the official frappe_docker). Empty means "not chosen yet"; the
# engine dispatch falls back to native so existing installs are unaffected.
# Persisted in the toolkit config and set via set-engine.
DEPLOYMENT_ENGINE_ENV_PROVIDED=0
if [[ -n "${DEPLOYMENT_ENGINE+x}" ]]; then
  DEPLOYMENT_ENGINE_ENV_PROVIDED=1
fi
DEPLOYMENT_ENGINE="${DEPLOYMENT_ENGINE:-}"
# Docker engine settings (used only when DEPLOYMENT_ENGINE=docker). See lib/docker.sh.
DOCKER_WORKDIR="${DOCKER_WORKDIR:-/opt/erpnext-dev/docker}"
FRAPPE_DOCKER_REPO="${FRAPPE_DOCKER_REPO:-https://github.com/frappe/frappe_docker.git}"
# Audited immutable default (frappe/frappe_docker @ 2026-07-15). Override with
# FRAPPE_DOCKER_REF=main (or another ref) only when you intentionally want a
# moving tip; the resolved SHA is still recorded in erpnext-dev.pins.
FRAPPE_DOCKER_REF="${FRAPPE_DOCKER_REF:-c004361e790125ed13aaa933d11f7838711a8960}"
DOCKER_ERPNEXT_IMAGE="${DOCKER_ERPNEXT_IMAGE:-frappe/erpnext:v16.26.2}"
DOCKER_PROJECT_NAME="${DOCKER_PROJECT_NAME:-erpnext-dev}"
# Track whether the published port was set via the environment this run, so the
# saved config value only overrides the default (not an explicit env choice).
DOCKER_PUBLISH_PORT_ENV_PROVIDED=0
if [[ -n "${DOCKER_PUBLISH_PORT+x}" ]]; then
  DOCKER_PUBLISH_PORT_ENV_PROVIDED=1
fi
DOCKER_PUBLISH_PORT="${DOCKER_PUBLISH_PORT:-8080}"
# Docker deployment mode: development (default; disposable pwd.yml stack) or
# production (wraps upstream compose.yaml + overrides). Decoupled from the native
# DEPLOYMENT_MODE so the containerized production path does not inherit host
# bench/nginx/firewall assumptions. Persisted in the toolkit config.
DOCKER_MODE_ENV_PROVIDED=0
if [[ -n "${DOCKER_MODE+x}" ]]; then
  DOCKER_MODE_ENV_PROVIDED=1
fi
DOCKER_MODE="${DOCKER_MODE:-development}"
AUTO_START="${AUTO_START:-prompt}"
ENABLE_AUTOSTART="${ENABLE_AUTOSTART:-prompt}"
APP_BACKUP_BEFORE_INSTALL="${APP_BACKUP_BEFORE_INSTALL:-prompt}"
APP_BACKUP_AFTER_INSTALL="${APP_BACKUP_AFTER_INSTALL:-prompt}"
FIREWALL_BACKUP_DIR="${FIREWALL_BACKUP_DIR:-/var/backups/erpnext-dev/firewall}"
ERPNEXT_SERVICE_NAME="${ERPNEXT_SERVICE_NAME:-erpnext-dev.service}"
# Stricter wait-ready (ports + HTTP + login CSS/JS) can need more than 90s on cold start.
READY_TIMEOUT="${READY_TIMEOUT:-180}"
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
# Pin bootstrap tool versions for reproducible installs. nvm is already pinned
# in lib/install.sh; UV_VERSION pins the uv installer instead of always pulling
# "latest" from the unversioned install URL.
NVM_VERSION="${NVM_VERSION:-0.40.3}"
UV_VERSION="${UV_VERSION:-0.11.28}"
# Pin the frappe-bench CLI installed via uv so installs are reproducible. Set
# BENCH_VERSION= (empty) to intentionally install the latest published bench.
BENCH_VERSION="${BENCH_VERSION-5.31.0}"

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
  # Never use a world-shared lock dir: a predictable path in a 1777 directory
  # lets another local user pre-plant a symlink and have a later root run follow
  # it. Root uses /run/lock (root-owned tmpfs); non-root uses its private runtime
  # dir, falling back to a per-uid /tmp dir created mode 0700.
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    LOCK_DIR="/run/lock/erpnext-dev"
  elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    LOCK_DIR="${XDG_RUNTIME_DIR}/erpnext-dev"
  else
    LOCK_DIR="/tmp/erpnext-dev-${EUID:-$(id -u)}-locks"
  fi
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
OFF_VM_KNOWN_HOSTS_FILE="${OFF_VM_KNOWN_HOSTS_FILE:-/etc/erpnext-dev/off-vm-known_hosts}"
OFF_VM_STRICT_HOST_KEY="${OFF_VM_STRICT_HOST_KEY:-false}"
OBJECT_BACKUP_CONFIG_FILE="${OBJECT_BACKUP_CONFIG_FILE:-/etc/erpnext-dev/object-backup.env}"
OBJECT_BACKUP_STATE_FILE="${OBJECT_BACKUP_STATE_FILE:-/etc/erpnext-dev/object-backup.state}"
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
DASHBOARD_FORMAT="${DASHBOARD_FORMAT:-human}"
DASHBOARD_WATCH_SEC="${DASHBOARD_WATCH_SEC:-0}"
DASHBOARD_DETAILS="${DASHBOARD_DETAILS:-0}"
FORCE_NO_COLOR="${FORCE_NO_COLOR:-0}"
ACTION_ARG="${ACTION_ARG:-}"
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

# Resolve the entry script through any symlinks (the /usr/local/bin/erpnext-dev
# CLI symlink, and the /opt/erpnext-dev/current release symlink used by atomic
# self-update) so lib/ is sourced from the REAL release directory, not from the
# symlink's directory.
_ERPNEXT_DEV_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
_ERPNEXT_DEV_ROOT="$(cd "$(dirname "${_ERPNEXT_DEV_REAL}")" && pwd)"
ERPNEXT_DEV_ENTRY_SCRIPT="${_ERPNEXT_DEV_REAL}"

# Compatibility bridge for installations created by the legacy single-file
# self-updater. That updater could replace /opt/erpnext-dev/erpnext-dev.sh with a
# modular entry script without installing lib/, leaving the CLI unable to start.
# When that exact partial layout is detected, recover from the signed bundle for
# this script version, promote it into the atomic releases/<tag> layout, and
# re-exec from the verified tree. Normal source checkouts and arbitrary missing
# files never trigger network recovery.
_ERPNEXT_DEV_BOOTSTRAP_SIGNING_FINGERPRINT_DEFAULT="BFC10C79427CF73496EA6F5A30BFD17DD559C8B6"

_erpnext_dev_required_lib_files() {
  printf '%s\n' \
    common.sh ui.sh config.sh access.sh local_ip.sh frappe.sh support.sh backup.sh ssl.sh firewall.sh \
    apps.sh health.sh storage.sh service.sh status.sh docker.sh engine.sh install.sh ops.sh \
    dashboard.sh healing.sh menu.sh security.sh update.sh
}

_erpnext_dev_missing_lib_files() {
  local lib_file
  while IFS= read -r lib_file; do
    [[ -f "${_ERPNEXT_DEV_ROOT}/lib/${lib_file}" ]] || printf '%s\n' "$lib_file"
  done < <(_erpnext_dev_required_lib_files)
}

_erpnext_dev_bootstrap_signature_ok() {
  local tree="$1"
  local sums="${tree}/SHA256SUMS"
  local sig="${tree}/SHA256SUMS.asc"
  local pubkey="${tree}/docs/erpnext-dev-signing-key.asc"
  local gnupg key_fpr valid_fpr status
  local expected_fpr="${TOOLKIT_BOOTSTRAP_SIGNING_FINGERPRINT:-${_ERPNEXT_DEV_BOOTSTRAP_SIGNING_FINGERPRINT_DEFAULT}}"

  [[ -f "$sums" && -f "$sig" && -f "$pubkey" ]] || return 1
  command -v gpg >/dev/null 2>&1 || return 1

  key_fpr="$(gpg --batch --with-colons --show-keys "$pubkey" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
  [[ -n "$key_fpr" && "$key_fpr" == "$expected_fpr" ]] || return 1

  gnupg="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-dev-bootstrap-gpg.XXXXXX")" || return 1
  chmod 700 "$gnupg" 2>/dev/null || true
  if ! GNUPGHOME="$gnupg" gpg --batch --quiet --import "$pubkey" >/dev/null 2>&1; then
    rm -rf "$gnupg"
    return 1
  fi

  status="$(GNUPGHOME="$gnupg" gpg --batch --status-fd 1 --verify "$sig" "$sums" 2>/dev/null || true)"
  rm -rf "$gnupg"
  valid_fpr="$(printf '%s\n' "$status" | awk '$2 == "VALIDSIG" { print $3; exit }')"
  [[ -n "$valid_fpr" && "$valid_fpr" == "$expected_fpr" ]]
}

_erpnext_dev_bootstrap_failure_help() {
  local missing="$1"
  cat >&2 <<EOF
ERROR: This installation has a modular erpnext-dev.sh but is missing required libraries:
${missing}

The legacy single-file updater created an incomplete /opt installation.
Automatic recovery from the signed v${SCRIPT_VERSION} release bundle was not possible.

Recovery from a trusted local checkout:
  cd /path/to/erpnext-dev-toolkit
  sudo install -d -m 0755 "$(dirname "${INSTALLER_CANONICAL_PATH}")/lib"
  sudo cp -a lib/. "$(dirname "${INSTALLER_CANONICAL_PATH}")/lib/"
  sudo chmod 0755 "${INSTALLER_CANONICAL_PATH}"
  sudo chmod 0644 "$(dirname "${INSTALLER_CANONICAL_PATH}")"/lib/*.sh
  sudo erpnext-dev version
EOF
}

_erpnext_dev_recover_legacy_modular_install() {
  local missing stable_root current_entry version_tag release_base workdir bundle tree
  local releases_dir new_release current_tmp entry_tmp name lib_file tar_entry

  missing="$(_erpnext_dev_missing_lib_files)"
  [[ -n "$missing" ]] || return 0

  stable_root="$(dirname "${INSTALLER_CANONICAL_PATH}")"

  # Only self-heal the canonical installed entry. A source checkout with missing
  # files should fail loudly instead of silently downloading code into the tree.
  [[ "${_ERPNEXT_DEV_ROOT}" == "$stable_root" ]] || {
    _erpnext_dev_bootstrap_failure_help "$missing"
    return 1
  }

  # If an atomic release is already present, prefer it over the network.
  current_entry="${stable_root}/current/erpnext-dev.sh"
  if [[ -x "$current_entry" && -f "${stable_root}/current/lib/common.sh" ]]; then
    exec "$current_entry" "$@"
  fi

  if [[ ! -w "$stable_root" ]]; then
    echo "ERROR: ${stable_root} is not writable. Re-run the command with sudo." >&2
    _erpnext_dev_bootstrap_failure_help "$missing"
    return 1
  fi

  command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is required for legacy modular recovery." >&2
    _erpnext_dev_bootstrap_failure_help "$missing"
    return 1
  }
  command -v tar >/dev/null 2>&1 || {
    echo "ERROR: tar is required for legacy modular recovery." >&2
    _erpnext_dev_bootstrap_failure_help "$missing"
    return 1
  }
  command -v sha256sum >/dev/null 2>&1 || {
    echo "ERROR: sha256sum is required for legacy modular recovery." >&2
    _erpnext_dev_bootstrap_failure_help "$missing"
    return 1
  }
  command -v gpg >/dev/null 2>&1 || {
    echo "ERROR: gpg is required to verify the signed recovery bundle." >&2
    _erpnext_dev_bootstrap_failure_help "$missing"
    return 1
  }

  version_tag="v${SCRIPT_VERSION}"
  release_base="${TOOLKIT_RELEASE_GITHUB:-https://github.com/ReyadWeb/erpnext-dev-toolkit}/releases/download/${version_tag}"
  workdir="$(mktemp -d "${stable_root}/.legacy-bootstrap.XXXXXX")" || return 1
  bundle="${workdir}/erpnext-dev-${version_tag}.tar.gz"

  echo "INFO: Incomplete legacy toolkit install detected; recovering ${version_tag} from its signed release bundle." >&2
  if ! curl -fsSL "${release_base}/erpnext-dev-${version_tag}.tar.gz" -o "$bundle"; then
    rm -rf "$workdir"
    echo "ERROR: Could not download the signed ${version_tag} release bundle." >&2
    _erpnext_dev_bootstrap_failure_help "$missing"
    return 1
  fi

  # Reject absolute paths and traversal before extraction.
  while IFS= read -r tar_entry; do
    case "$tar_entry" in
      /*|../*|*/../*|*/..)
        rm -rf "$workdir"
        echo "ERROR: Unsafe path detected in recovery bundle: ${tar_entry}" >&2
        return 1
        ;;
    esac
  done < <(tar -tzf "$bundle")

  if ! tar -C "$workdir" -xzf "$bundle"; then
    rm -rf "$workdir"
    echo "ERROR: Could not extract the recovery bundle." >&2
    return 1
  fi

  tree="${workdir}/erpnext-dev-${version_tag}"
  if [[ ! -d "$tree" || ! -f "${tree}/erpnext-dev.sh" || ! -f "${tree}/SHA256SUMS" ]]; then
    rm -rf "$workdir"
    echo "ERROR: Recovery bundle layout is incomplete." >&2
    return 1
  fi

  if ! (cd "$tree" && sha256sum -c SHA256SUMS >/dev/null); then
    rm -rf "$workdir"
    echo "ERROR: Recovery bundle checksum verification failed." >&2
    return 1
  fi

  if ! _erpnext_dev_bootstrap_signature_ok "$tree"; then
    rm -rf "$workdir"
    echo "ERROR: Recovery bundle signature verification failed." >&2
    return 1
  fi

  bash -n "${tree}/erpnext-dev.sh" || {
    rm -rf "$workdir"
    echo "ERROR: Recovered entry script failed syntax validation." >&2
    return 1
  }
  while IFS= read -r lib_file; do
    [[ -f "${tree}/lib/${lib_file}" ]] || {
      rm -rf "$workdir"
      echo "ERROR: Signed recovery bundle is missing lib/${lib_file}." >&2
      return 1
    }
    bash -n "${tree}/lib/${lib_file}" || {
      rm -rf "$workdir"
      echo "ERROR: Recovered lib/${lib_file} failed syntax validation." >&2
      return 1
    }
  done < <(_erpnext_dev_required_lib_files)

  releases_dir="${stable_root}/releases"
  new_release="${releases_dir}/${version_tag}"
  mkdir -p "$releases_dir" || {
    rm -rf "$workdir"
    return 1
  }
  rm -rf "$new_release"
  mv -T "$tree" "$new_release" || {
    rm -rf "$workdir"
    return 1
  }
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    chown -R root:root "$new_release" 2>/dev/null || true
  fi

  current_tmp="${stable_root}/.current.bootstrap.$$"
  ln -sfn "releases/${version_tag}" "$current_tmp"
  mv -T "$current_tmp" "${stable_root}/current"

  entry_tmp="${stable_root}/.entry.bootstrap.$$"
  ln -sfn "current/erpnext-dev.sh" "$entry_tmp"
  mv -T "$entry_tmp" "${stable_root}/erpnext-dev.sh"

  for name in lib SHA256SUMS SHA256SUMS.asc RELEASE-MANIFEST.txt docs; do
    [[ -e "${stable_root}/current/${name}" ]] || continue
    rm -rf "${stable_root:?}/${name}"
    ln -sfn "current/${name}" "${stable_root}/${name}"
  done

  if mkdir -p "$(dirname "${TOOLKIT_CLI_PATH}")" 2>/dev/null; then
    ln -sfn "${stable_root}/erpnext-dev.sh" "${TOOLKIT_CLI_PATH}" 2>/dev/null || true
  fi

  rm -rf "$workdir"
  echo "OK: Recovered the complete signed ${version_tag} toolkit and migrated to the atomic release layout." >&2
  exec "${stable_root}/current/erpnext-dev.sh" "$@"
}

if [[ -n "$(_erpnext_dev_missing_lib_files)" ]]; then
  _erpnext_dev_recover_legacy_modular_install "$@" || exit 1
fi

if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/common.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/common.sh" >&2
  exit 1
fi
# shellcheck source=lib/common.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/common.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/ui.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/ui.sh" >&2
  exit 1
fi
# shellcheck source=lib/ui.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/ui.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/config.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/config.sh" >&2
  exit 1
fi
# shellcheck source=lib/config.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/config.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/access.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/access.sh" >&2
  exit 1
fi
# shellcheck source=lib/access.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/access.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/local_ip.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/local_ip.sh" >&2
  exit 1
fi
# shellcheck source=lib/local_ip.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/local_ip.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/frappe.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/frappe.sh" >&2
  exit 1
fi
# shellcheck source=lib/frappe.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/frappe.sh"
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
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/status.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/status.sh" >&2
  exit 1
fi
# shellcheck source=lib/status.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/status.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/docker.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/docker.sh" >&2
  exit 1
fi
# shellcheck source=lib/docker.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/docker.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/engine.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/engine.sh" >&2
  exit 1
fi
# shellcheck source=lib/engine.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/engine.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/install.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/install.sh" >&2
  exit 1
fi
# shellcheck source=lib/install.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/install.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/ops.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/ops.sh" >&2
  exit 1
fi
# shellcheck source=lib/ops.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/ops.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/dashboard.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/dashboard.sh" >&2
  exit 1
fi
# shellcheck source=lib/dashboard.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/dashboard.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/healing.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/healing.sh" >&2
  exit 1
fi
# shellcheck source=lib/healing.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/healing.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/menu.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/menu.sh" >&2
  exit 1
fi
# shellcheck source=lib/menu.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/menu.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/security.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/security.sh" >&2
  exit 1
fi
# shellcheck source=lib/security.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/security.sh"
if [[ ! -f "${_ERPNEXT_DEV_ROOT}/lib/update.sh" ]]; then
  echo "ERROR: Missing toolkit library: ${_ERPNEXT_DEV_ROOT}/lib/update.sh" >&2
  exit 1
fi
# shellcheck source=lib/update.sh disable=SC1091
source "${_ERPNEXT_DEV_ROOT}/lib/update.sh"
erpnext_dev_init_terminal_colors
# Capture width/TTY before tee turns stdout into a pipe (otherwise the main menu
# often falls back to 80-col single-column layout).
erpnext_dev_snapshot_terminal_cols
ui_init

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

# `install-cli` / `repair-cli` dispatcher entry points. Both (re)create the
# short `erpnext-dev` command that points at the installed toolkit. They share
# one implementation because "repair" is just an idempotent reinstall.
install_toolkit_cli() {
  require_sudo
  local cli_path="${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev}"
  local dest="${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"

  if [[ ! -f "$dest" ]]; then
    warn "Toolkit is not installed at ${dest} yet."
    echo "Run a quickstart or 'setup' first so the toolkit lives in a stable location,"
    echo "then re-run '$(basename "$0") install-cli'."
    return 1
  fi

  if install_toolkit_cli_entry; then
    ok "Installed the erpnext-dev command at ${cli_path} -> ${dest}"
  else
    fail "Could not create ${cli_path}. Re-run with sudo, or check permissions on $(dirname "$cli_path")."
  fi
}

repair_toolkit_cli() {
  install_toolkit_cli
}

install_self_for_reuse() {
  # One-command quickstart runs from a temporary /tmp bootstrap file. Copy the active
  # toolkit into /opt and expose the short erpnext-dev command for future use.
  local src dest src_root dest_root
  dest="${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"

  # Prefer the path resolved at bootstrap. Re-resolving BASH_SOURCE[0] with
  # readlink -f can return empty on Ubuntu 26.04 + sudo-rs when the invoke path
  # is relative (e.g. sudo ./erpnext-dev.sh), which previously skipped the /opt
  # copy silently and broke integration verify-toolkit on the 26.04 leg.
  src="${ERPNEXT_DEV_ENTRY_SCRIPT:-}"
  if [[ -z "$src" || ! -f "$src" ]]; then
    src="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
  fi
  if [[ -z "$src" || ! -f "$src" ]]; then
    src="${BASH_SOURCE[0]}"
    if [[ "$src" != /* ]]; then
      src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
    fi
  fi
  if [[ ! -f "$src" ]]; then
    warn "Could not resolve toolkit entry script for /opt install (src=${src:-<empty>})"
    return 1
  fi

  src_root="$(cd "$(dirname "$src")" && pwd)"
  dest_root="$(dirname "$dest")"
  mkdir -p "$dest_root" 2>/dev/null || {
    warn "Could not create ${dest_root}"
    return 1
  }

  if [[ "$src" != "$dest" ]]; then
    if ! cp "$src" "$dest" 2>/dev/null; then
      warn "Could not copy toolkit entry script to ${dest}"
      return 1
    fi
    chmod 755 "$dest" 2>/dev/null || true
    chown root:root "$dest" 2>/dev/null || true
  else
    chmod 755 "$dest" 2>/dev/null || true
    chown root:root "$dest" 2>/dev/null || true
  fi

  if ! sync_toolkit_lib_tree "$src_root" "$dest_root"; then
    warn "Could not copy toolkit lib/ tree to ${dest_root}/lib"
    return 1
  fi

  install_toolkit_cli_entry 2>/dev/null || true
  return 0
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
  toolkit_version_matrix_status_lines
  ui_box_end
}

# Single source of truth for the pinned toolchain. Emits "Label|value" pairs so
# callers can render them however they like (status lines, plain text bundle).
toolkit_version_matrix_pairs() {
  printf '%s|%s\n' "Toolkit" "${SCRIPT_VERSION}"
  printf '%s|%s\n' "Node" "${NODE_VERSION}"
  printf '%s|%s\n' "nvm" "${NVM_VERSION}"
  printf '%s|%s\n' "uv" "${UV_VERSION}"
  printf '%s|%s\n' "Python" "${PYTHON_VERSION}"
  printf '%s|%s\n' "Frappe branch" "${FRAPPE_BRANCH}"
  printf '%s|%s\n' "ERPNext branch" "${ERPNEXT_BRANCH}"
  printf '%s|%s\n' "frappe-bench" "${BENCH_VERSION:-unpinned (latest)}"
}

# Render the matrix as status lines inside an already-open UI box.
toolkit_version_matrix_status_lines() {
  local label value
  while IFS='|' read -r label value; do
    [[ -n "$label" ]] || continue
    status_line "${label}" "INFO" "${value}"
  done < <(toolkit_version_matrix_pairs)
}

# Standalone read-only `versions` command: shows the pinned compatibility matrix.
show_toolkit_versions() {
  ui_box_start "Toolkit compatibility matrix"
  toolkit_version_matrix_status_lines
  echo
  echo "These versions are pinned for reproducible installs. Override any of them"
  echo "with an environment variable, e.g. BENCH_VERSION= (empty) installs the"
  echo "latest published frappe-bench."
  ui_box_end
}

















show_advanced_installation_menu() {
  while true; do
    ui_submenu_header "Advanced > Installation & Repair" \
      "Install, preflight, repair, or intentionally remove the environment"
    print_two_column_menu \
      "1) Install / reinstall" \
      "2) Repair environment" \
      "3) Installation preflight" \
      "4) Uninstall / reset [destructive]"
    menu_footer back "Advanced"
    local choice=""
    menu_read_choice choice
    case "$choice" in
      1) run_install; pause_after_screen "Press Enter to return to Installation & Repair..." ;;
      2) run_repair; pause_after_screen "Press Enter to return to Installation & Repair..." ;;
      3) run_install_preflight; pause_after_screen "Press Enter to return to Installation & Repair..." ;;
      4) run_uninstall_menu ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_advanced_engine_menu() {
  while true; do
    ui_submenu_header "Advanced > Deployment Engine" \
      "Inspect or choose the native / Docker deployment engine"
    print_two_column_menu \
      "1) Deployment engine status" \
      "2) Choose deployment engine" \
      "3) Environment / location check" \
      "4) Multi-environment guide"
    menu_footer back "Advanced"
    local choice=""
    menu_read_choice choice
    case "$choice" in
      1) show_engine_status; pause_after_screen "Press Enter to return to Deployment Engine..." ;;
      2) run_set_engine; pause_after_screen "Press Enter to return to Deployment Engine..." ;;
      3) show_environment_check; pause_after_screen "Press Enter to return to Deployment Engine..." ;;
      4) show_multi_environment_guide; pause_after_screen "Press Enter to return to Deployment Engine..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_advanced_services_menu() {
  while true; do
    ui_submenu_header "Advanced > Services & Logs" \
      "Service management, foreground Bench, runtime state, and logs"
    print_two_column_menu \
      "1) Service manager" \
      "2) Start Bench in foreground" \
      "3) Show service logs" \
      "4) Runtime status" \
      "5) Service recovery plan"
    menu_footer back "Advanced"
    local choice=""
    menu_read_choice choice
    case "$choice" in
      1) show_service_menu ;;
      2) run_foreground_start; pause_after_screen "Press Enter to return to Services & Logs..." ;;
      3) show_erpnext_service_logs; pause_after_screen "Press Enter to return to Services & Logs..." ;;
      4) run_runtime_status; pause_after_screen "Press Enter to return to Services & Logs..." ;;
      5) show_service_recovery_plan; pause_after_screen "Press Enter to return to Services & Logs..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_advanced_storage_menu() {
  while true; do
    ui_submenu_header "Advanced > Storage" \
      "Inspect, expand, and verify VM root storage"
    print_two_column_menu \
      "1) Storage status" \
      "2) Expand root storage" \
      "3) Verify storage"
    menu_footer back "Advanced"
    local choice=""
    menu_read_choice choice
    case "$choice" in
      1) show_storage_status; pause_after_screen "Press Enter to return to Storage..." ;;
      2) expand_root_storage; pause_after_screen "Press Enter to return to Storage..." ;;
      3) verify_storage; pause_after_screen "Press Enter to return to Storage..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_advanced_networking_menu() {
  while true; do
    ui_submenu_header "Advanced > Networking" \
      "Access routing, VM network state, stable IP, and host guidance"
    print_two_column_menu \
      "1) Access & networking" \
      "2) VM network status" \
      "3) Local network & stable IP" \
      "4) KVM fixed IP guide" \
      "5) Multi-environment guide" \
      "6) Verify ERPNext HTTP access"
    menu_footer back "Advanced"
    local choice=""
    menu_read_choice choice
    case "$choice" in
      1) show_access_menu ;;
      2) show_network_status; pause_after_screen "Press Enter to return to Networking..." ;;
      3) show_local_ip_menu ;;
      4) show_kvm_fixed_ip_guide; pause_after_screen "Press Enter to return to Networking..." ;;
      5) show_multi_environment_guide; pause_after_screen "Press Enter to return to Networking..." ;;
      6) verify_access; pause_after_screen "Press Enter to return to Networking..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_advanced_diagnostics_menu() {
  while true; do
    ui_submenu_header "Advanced > Diagnostics" \
      "Health, readiness, environment, and recommended-next-step checks"
    print_two_column_menu \
      "1) Full health report" \
      "2) Optional app status" \
      "3) Environment / location check" \
      "4) Production readiness preview" \
      "5) Public VM readiness" \
      "6) Next recommended action" \
      "7) Verify ERPNext HTTP access" \
      "8) Operations dashboard"
    menu_footer back "Advanced"
    local choice=""
    menu_read_choice choice
    case "$choice" in
      1) run_full_status; pause_after_screen "Press Enter to return to Diagnostics..." ;;
      2) run_app_status; pause_after_screen "Press Enter to return to Diagnostics..." ;;
      3) show_environment_check; pause_after_screen "Press Enter to return to Diagnostics..." ;;
      4) show_production_readiness; pause_after_screen "Press Enter to return to Diagnostics..." ;;
      5) show_public_vm_readiness; pause_after_screen "Press Enter to return to Diagnostics..." ;;
      6) show_next_step; pause_after_screen "Press Enter to return to Diagnostics..." ;;
      7) verify_access; pause_after_screen "Press Enter to return to Diagnostics..." ;;
      8) run_operations_dashboard; pause_after_screen "Press Enter to return to Diagnostics..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_advanced_developer_tools_menu() {
  while true; do
    ui_submenu_header "Advanced > Developer Tools" \
      "Applications, compatibility, custom app tools, and rollback guidance"
    print_two_column_menu \
      "1) Application library" \
      "2) App install wizard" \
      "3) Optional app status" \
      "4) App compatibility" \
      "5) App rollback guide" \
      "6) Advanced app tools"
    menu_footer back "Advanced"
    local choice=""
    menu_read_choice choice
    case "$choice" in
      1) show_app_library_menu ;;
      2) run_app_install_wizard ;;
      3) run_app_status; pause_after_screen "Press Enter to return to Developer Tools..." ;;
      4) show_app_compatibility_matrix; pause_after_screen "Press Enter to return to Developer Tools..." ;;
      5) show_app_rollback_guide; pause_after_screen "Press Enter to return to Developer Tools..." ;;
      6) show_advanced_app_tools_menu ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_advanced_menu() {
  while true; do
    ui_submenu_header "Advanced" \
      "Grouped expert tools; normal workflows remain in the Main menu"
    print_two_column_menu \
      "1) Installation & repair" \
      "2) Deployment engine" \
      "3) Services & logs" \
      "4) Storage" \
      "5) Networking" \
      "6) Domains & HTTPS" \
      "7) Credentials" \
      "8) Diagnostics" \
      "9) Developer tools"
    menu_footer back "Main menu"
    local advanced_choice=""
    menu_read_choice advanced_choice

    case "$advanced_choice" in
      1) show_advanced_installation_menu ;;
      2) show_advanced_engine_menu ;;
      3) show_advanced_services_menu ;;
      4) show_advanced_storage_menu ;;
      5) show_advanced_networking_menu ;;
      6) show_https_domains_menu ;;
      7) show_credentials_menu ;;
      8) show_advanced_diagnostics_menu ;;
      9) show_advanced_developer_tools_menu ;;
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
    credentials-menu
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
    dashboard
    health-monitoring-wizard
    security-hardening-wizard
    final-qa-wizard
    uninstall
  )

  for action in "${quit_actions[@]}"; do
    for input in q Q; do
      tested=$((tested + 1))
      # set +e: a non-zero child must not abort this loop under set -e.
      set +e
      out="$(printf '%s\n' "$input" | timeout 5 "${invoke[@]}" "$script" "$action" 2>&1)"
      rc=$?
      set -e
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
    credentials-menu
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
    dashboard
    health-monitoring-wizard
    security-hardening-wizard
    final-qa-wizard
  )

  for action in "${back_actions[@]}"; do
    for input in b B; do
      tested=$((tested + 1))
      set +e
      out="$(printf '%s\nq\n' "$input" | timeout 5 "${invoke[@]}" "$script" "$action" 2>&1)"
      rc=$?
      set -e
      if (( rc != 0 )) || printf '%s\n' "$out" | grep -Eqi 'Invalid option|command not found|unbound variable|syntax error'; then
        failures=$((failures + 1))
        status_line "${action} ${input}" "FAIL" "b/B did not return cleanly"
      fi
    done
  done

  # Test a few nested submenu paths where prior bugs could drop the user into shell.
  local nested_tests=(
    "advanced|1|q"
    "advanced|3|q"
    "advanced|5|q"
    "advanced|6|q"
    "advanced|7|q"
    "advanced|9|q"
    "menu|2|q"
    "menu|3|q"
    "menu|5|q"
    "menu|6|q"
    "menu|9|q"
    "menu|10|q"
    "menu|11|q"
    "health-monitoring-wizard|3|q"
    "production-ops-wizard|7|b"
    "production-ops-wizard|10|b"
  )
  local row root select quit
  for row in "${nested_tests[@]}"; do
    IFS='|' read -r root select quit <<< "$row"
    tested=$((tested + 1))
    set +e
    out="$(printf '%s\n%s\n' "$select" "$quit" | timeout 5 "${invoke[@]}" "$script" "$root" 2>&1)"
    rc=$?
    set -e
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
  versions            Show the pinned compatibility matrix (Node/nvm/uv/Python/branches/bench)
  where-installed     Show active script, stable /opt path, CLI path, and config path
  verify-toolkit      Show installed script SHA256 and compare against SHA256SUMS when available
  verify-signature    Verify the GPG signature over SHA256SUMS (needs TOOLKIT_SIGNING_PUBKEY)
  install-cli         Install or repair the erpnext-dev command
  repair-cli          Alias for install-cli
  update-toolkit      Atomic update: verified bundle -> releases/<ver> -> current symlink
  toolkit-rollback    Switch the current symlink back to the previously installed release
  clear-lock          Clear a stale toolkit lock (refuses if another process still holds it)
  update-preflight    Read-only readiness report before an ERPNext/Frappe upgrade
  safe-update-wizard  Backup-first, verified 'bench update' with a recorded rollback plan
  update-rollback     Check out the app commits recorded before the last safe update
  security-audit      Read-only SSH, firewall, HTTPS, credential, and patch posture review
  menu-self-test      Validate q/Q and b/B handling across interactive menus
  menu-render-test    Print the polished main menu once (CI / NO_COLOR checks)
  dashboard-render-test  Print the polished operations dashboard once (CI / fixture)
  guided-setup        Guided install / repair workflow
  status              Compact ERPNext status
  verify-access       HTTP access checks
  verify-frontend-assets  One-shot login CSS/JS probe (live HTTP)
  wait-frontend-assets    Wait until ports + HTTP + static assets are OK
  repair-frontend-assets  bench build + clear assets_json/cache + restart + re-verify
  frappe-asset-checklist  Frappe-first disk/:8000 diagnosis (docs/FRAPPE-FRONTEND-ASSETS.md)
  wait-ready          Alias-style wait: ports + HTTP + static assets
  access-info         Show Desk, login, portal, and host access URLs
  education-access-info Show Education portal and ERPNext Desk URLs
  credentials-info    Safe credential overview; does not print passwords
  credentials-show    Show generated passwords after confirmation
  credentials-file-status Check owner/mode/age of the credentials file
  credentials-secure  Set credentials file to root:root 600
  credentials-delete  Delete local plaintext credentials file after secure handoff
  credentials-menu    Credentials / Login submenu (Advanced → Credentials / Login)
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
  set-host-os          Choose your HOST OS (Linux/macOS/Windows) to tailor host commands
  set-engine           Choose the deployment engine (native VM or Docker) for a fresh setup
  engine-status        Show the active deployment engine (native or Docker) and its settings
  engine-restore       Engine-agnostic: restore a site from backup (native or Docker)
  engine-upgrade       Engine-agnostic: guarded upgrade (native bench update / Docker re-deploy)
  engine-rollback      Engine-agnostic: roll back the last upgrade (native or Docker)
  engine-diagnostics   Engine-agnostic: structured doctor diagnostics (add --plain/--json)
  docker-production-setup  Provision a production Docker stack (compose.yaml + upstream overrides)
  docker-backup            Docker: back up and export a durable, verified host artifact
  docker-backup-verify     Docker: verify the newest exported host backup artifact
  docker-restore           Docker: restore the site from an exported host backup artifact
  docker-restore-rehearsal Docker: prove a backup restores into a clean throwaway site
  docker-restore-evidence  Docker: show the recorded restore-rehearsal evidence
  docker-offvm-backup      Docker: rsync durable host artifacts off-VM (checksum-verified)
  docker-offvm-status      Docker: show off-VM + object-storage shipment status
  configure-object-backup  Engine-agnostic: configure object backups (stores non-secret rclone coords only)
  object-backup            Engine-agnostic: upload backups via rclone (S3/R2/B2/…); --dry-run available
  object-status            Engine-agnostic: show object-storage backup status
  docker-object-config     Docker: configure object-storage backups (rclone remote)
  docker-object-backup     Docker: upload durable host artifacts to object storage
  docker-object-status     Docker: show object-storage backup status
  docker-https-wizard      Docker HTTPS: local trusted HTTPS or production Traefik TLS
  docker-enable-letsencrypt Docker: enable Traefik + Let's Encrypt HTTPS on 80/443
  docker-configure-cloudflare-origin Docker: enable Traefik + Cloudflare Origin CA HTTPS
  docker-https-status      Docker: show production HTTPS mode, proxy, and certificate
  docker-https-rollback    Docker: roll back to HTTP (remove the Traefik proxy)
  docker-production-exposure Docker: verify only web ports are public, backend ports internal
  docker-custom-image-config Docker: choose apps to bake into a durable custom image
  docker-build-custom-image  Docker: build an immutable image (ERPNext + selected apps)
  docker-deploy-custom-image Docker: recreate the stack on the built image and install apps
  docker-custom-image-status Docker: show configured apps and the built image
  docker-reconcile-app-image Docker: rebuild/redeploy one image from installed curated apps
  local-domain-status  Show dynamic VM IP, local domain, and host mapping status
  local-access-doctor  Diagnose local URL/DNS/firewall/access issues
  local-host-checkpoint Required safe host mapping checkpoint before local HTTPS
  host-dns-guide       Print host-side hosts-file commands using the current VM IP
  local-ip-menu         Local network / stable IP submenu
  local-ip-status       Current guest IP, DHCP vs static signals, saved mapping
  local-ip-plan         Ranked options to keep erp.test stable after reboot
  local-ip-drift-check  Detect saved IP vs current IP mismatch
  local-ip-save         Record the current guest IP mapping for drift checks
  local-static-ip-wizard  Apply guest Netplan static IP with backup
  local-static-ip-rollback  Restore the previous Netplan backup
  local-fixed-ip-guide  Print stable local VM IP guidance for your hypervisor/host OS
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

Runtime (how ERPNext is served):
  setup-production-runtime Switch to a production runtime: gunicorn + workers + scheduler + socket.io under supervisor (no 'bench start')
  convert-to-dev-runtime   Revert to the development 'bench start' runtime
  production-runtime-status Show supervisor programs, gunicorn/socket.io ports, and HTTP readiness

Security:
  security-hardening-wizard  Environment-aware UFW + Fail2Ban workflow
  security-mode-status       Show local vs production hardening context
  local-firewall-profile     Apply engine-aware local VM profile (Docker 8080; native 8000/9000)
  production-firewall-profile Apply production profile; blocks backend ports
  repair-local-access        Restore local direct access for the active deployment engine
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
  off-vm-trust-host-key Capture off-VM SSH host key into toolkit known_hosts
  off-vm-verify-host-key Probe off-VM SSH under current host-key policy
  off-vm-strict-host-key-enable Require StrictHostKeyChecking=yes for off-VM SSH
  off-vm-strict-host-key-disable Return off-VM SSH to accept-new (first-setup convenience)
  off-vm-backup-dry-run Preview off-VM rsync copy
  run-off-vm-backup   Copy backups to configured off-VM target
  off-vm-backup-status Show off-VM backup configuration/status
  off-vm-backup-guide Commands to copy backups off this VM
  health-monitoring-wizard Guided health timer and monitoring workflow
  health-check       Compact production health check (uses canonical snapshot)
  health-check-run-now Alias for health-check
  configure-health-check-timer Enable periodic health checks with systemd
  health-check-status Show health check timer and last health status
  health-check-journal Show recent health-check systemd journal output
  dashboard          Operations dashboard (host + app + protection + healing)
  health-snapshot    Alias for dashboard --json (CloudPanel contract)
  incidents          List recent health incidents
  incident-show      Show one incident (default: latest)
  health-history     Show recent metrics history samples
  health-metrics     OpenMetrics text export (Prometheus scrape helper)
  healing-status     Show guarded auto-healing mode, lockout, last action
  healing-policy     Show dedicated healing.env policy (allowlist keys)
  healing-history    Show healing audit log entries
  healing-enable-safe Enable safe healing (restarts; never host reboot)
  healing-disable    Return healing to monitor-only
  healing-unlock     Clear AUTO-HEALING LOCKED after manual review
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
  install-drive       Install Frappe Drive (official)
  install-gameplan    Install Frappe Gameplan (official)
  install-lending     Install Frappe Lending (official)
  install-raven       Install Raven Team Chat (community)
  install-india-compliance Install India Compliance GST (community)
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
    VERSION="v${SCRIPT_VERSION}"; curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/\${VERSION}/erpnext-dev.sh"; curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/\${VERSION}/SHA256SUMS"; sha256sum -c SHA256SUMS; chmod +x erpnext-dev.sh; sudo ./erpnext-dev.sh public-vm-guided-setup
  Local VM:
    VERSION="v${SCRIPT_VERSION}"; curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/\${VERSION}/erpnext-dev.sh"; curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/\${VERSION}/SHA256SUMS"; sha256sum -c SHA256SUMS; chmod +x erpnext-dev.sh; sudo ./erpnext-dev.sh local-dev-quickstart

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

Use $(toolkit_cmd advanced) for grouped expert tools; direct CLI commands remain available.
After first run, use the short command: sudo erpnext-dev menu

Questions or bugs? See SUPPORT.md. Want to contribute? See CONTRIBUTING.md.
  https://github.com/ReyadWeb/erpnext-dev-toolkit/blob/main/SUPPORT.md
EOF_HELP
}

# show_menu is defined in lib/menu.sh (polished status panel + responsive layout).

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
        DASHBOARD_FORMAT="json"
        shift
        ;;
      --no-color)
        FORCE_NO_COLOR=1
        NO_COLOR=1
        export NO_COLOR
        shift
        ;;
      --details)
        DASHBOARD_DETAILS=1
        shift
        ;;
      --watch)
        shift
        if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
          DASHBOARD_WATCH_SEC="$1"
          shift
        else
          DASHBOARD_WATCH_SEC=5
        fi
        ;;
      first-run|start-here|quickstart|setup-wizard|public-vm-quickstart|public-setup|public-vm-guided-setup|public-guided-setup|production-guided-setup|local-dev-quickstart|local-setup|install-preflight|environment-preflight|set-domain|show-config|guided-setup|setup|install|repair|status|status-menu|runtime-status|install-status|service-summary|doctor|support-bundle|support|support-bundle-audit|audit-support-bundle|support-bundle-audit-test|full-status|start|stop|uninstall|advanced|access|verify-access|access-info|education-access-info|portal-access-info|desk-url|credentials-info|credentials|login-info|credentials-show|show-credentials|credentials-file-status|credentials-secure|credentials-delete|credentials-menu|login-menu|reset-admin-password|admin-password-reset|next-step|local-ssl-menu|local-https|local-vm-ssl|local-ssl-wizard|ssl-wizard|trusted-mkcert-setup|mkcert-setup|access-menu|backup-menu|backup|backup-files|backup-status|backup-verify|verify-backups|off-vm-backup-guide|restore-rehearsal-guide|restore-rehearsal-status|restore-rehearsal-record|restore-rehearsal-report|go-live-record|go-live-status|cloud-firewall-checklist|cloudflare-checklist|restore-rehearsal-wizard|restore-key-setup|pull-off-vm-backup|backup-server-add-restore-key|backup-server-remove-restore-key|backup-server-list-restore-keys|production-checklist|release-readiness|final-qa|final-qa-wizard|command-audit|release-notes-guide|backup-hardening-wizard|backup-wizard|backup-schedule-plan|configure-backup-schedule|backup-schedule-status|scheduled-backup-status|disable-backup-schedule|scheduled-backups|backup-retention-plan|backup-retention-status|cleanup-old-backups|cleanup-old-backups-dry-run|backup-cleanup-dry-run|backup-cleanup|off-vm-backup-plan|off-vm-backup-guided-setup|generate-off-vm-backup-key|off-vm-backup-keygen|backup-server-setup|prepare-backup-server|off-vm-backup-server-setup|configure-rsync-backup-target|off-vm-trust-host-key|off-vm-verify-host-key|off-vm-strict-host-key-enable|off-vm-strict-host-key-disable|off-vm-backup-dry-run|run-off-vm-backup|off-vm-backup-status|disable-off-vm-backup|off-vm-backup-wizard|health-check|health-check-run-now|configure-health-check-timer|health-check-status|health-check-journal|disable-health-check-timer|health-monitoring-wizard|production-monitoring-wizard|dashboard|ops-dashboard-v2|health-snapshot|incidents|incident-show|health-history|health-metrics|openmetrics|healing-status|healing-policy|healing-history|healing-enable-safe|healing-disable|healing-unlock|service-recovery-plan|restore-preflight|production-ops-wizard|production-ops-dashboard|operations-wizard|operations-dashboard|ops-wizard|ops-dashboard|list-backups|backups|restore-db|restore-full|maintenance|migrate|build|clear-cache|restart|update-preflight|upgrade-preflight|safe-update|safe-update-wizard|update-erpnext|upgrade-erpnext|update-rollback|rollback-update|wait-ready|verify-frontend-assets|wait-frontend-assets|repair-frontend-assets|frappe-asset-checklist|frappe-frontend-assets|menu|help|-h|--help|version|--version|versions|version-matrix|toolchain|where-installed|verify-toolkit|toolkit-verify|verify-install|verify-signature|verify-release-signature|verify-sig|install-cli|repair-cli|update-toolkit|toolkit-rollback|update-toolkit-rollback|rollback-toolkit|clear-lock|unlock|force-unlock|menu-self-test|menu-navigation-self-test|menu-render-test|dashboard-render-test|foreground-start|enable-autostart|disable-autostart|service-start|service-stop|service-restart|service-status|setup-production-runtime|convert-to-production|production-runtime-setup|convert-to-dev-runtime|convert-to-development-runtime|production-runtime-status|runtime-mode-status|logs|logs-follow|kvm-guide|kvm-identify|network-status|local-domain-status|local-host-checkpoint|host-dns-checkpoint|host-mapping-checkpoint|local-access-doctor|hosts-command|print-hosts-command|host-dns-guide|local-ip-menu|local-network|local-network-menu|local-ip-status|local-ip-plan|local-ip-drift-check|local-ip-save|local-static-ip-wizard|local-static-ip-rollback|local-fixed-ip-guide|fixed-ip-guide|kvm-fixed-ip-guide|host-test|ssl-roadmap|ssl-status|local-ssl-guide|mkcert-guide|trusted-local-ssl-guide|browser-trust-guide|trust-check-guide|ssl-rollback-guide|verify-ssl-rollback|verify-local-ssl|install-local-ssl-cert|replace-local-ssl-cert|create-self-signed-local-cert|self-signed-local-cert|configure-local-ssl|disable-local-ssl|environment-check|where-am-i|site-config|domain-config|change-local-domain|local-domain-wizard|rename-local-site|change-site-domain|set-host-os|host-os|choose-host-os|set-engine|engine|choose-engine|deployment-engine|engine-status|engine-restore|engine-upgrade|engine-rollback|engine-diagnostics|docker-production-setup|docker-prod-setup|docker-production|docker-backup|docker-backup-files|docker-backup-verify|docker-restore|docker-restore-full|docker-restore-db|docker-restore-rehearsal|docker-restore-evidence|docker-offvm-backup|docker-offvm-backup-dry-run|docker-offvm-status|docker-object-config|docker-object-backup-config|docker-object-backup|docker-object-backup-dry-run|docker-object-status|configure-object-backup|object-backup-config|object-config|object-backup|run-object-backup|object-backup-dry-run|object-status|object-backup-status|docker-https-wizard|docker-production-https|docker-https-menu|docker-enable-letsencrypt|docker-letsencrypt|docker-https-letsencrypt|docker-configure-cloudflare-origin|docker-cloudflare-origin|docker-https-cloudflare-origin|docker-https-status|docker-https-rollback|docker-disable-https|docker-production-exposure|docker-exposure-check|docker-custom-image-config|docker-custom-apps|docker-build-custom-image|docker-custom-image-build|docker-deploy-custom-image|docker-custom-image-deploy|docker-custom-image-status|docker-reconcile-app-image|storage-status|storage-debug|expand-root-storage|verify-storage|production-readiness|production-plan|prod-plan|production-domain-plan|prod-domain-plan|public-vm-readiness|public-readiness|production-ssl-plan|prod-ssl-plan|production-firewall-plan|prod-firewall-plan|firewall-hardening-status|firewall-status|hardening-status|vm-firewall-plan|ufw-plan|configure-vm-firewall|local-firewall-profile|local-security-profile|production-firewall-profile|production-security-profile|repair-local-access|firewall-rollback-snapshots|vm-firewall-status|ufw-status|configure-fail2ban|fail2ban-status|security-audit|security-audit-test|security-hardening-wizard|vm-firewall-wizard|ufw-ssh-admin-only|production-ssl-menu|production-https|production-https-menu|configure-production-ssl|production-ssl-wizard|ssl-provider-wizard|ssl-mode-status|ssl-mode-guide|ssl-compatibility|setup-effort-guide|setup-step-count|setup-lifecycle-plan|setup-order-plan|configure-cloudflare-origin-ssl|install-cloudflare-origin-cert|switch-to-cloudflare-origin-ssl|cloudflare-origin-ssl-status|cloudflare-origin-guide|production-ssl-status|disable-production-ssl|production-domain-guide|production-ssl-guide|repair-site-config|site-name-guide|custom-site-guide|multi-env-guide|app-library|apps|list-apps|app-status|app-compatibility|app-compat|app-preflight|install-crm|install-hrms|install-helpdesk|install-telephony|install-insights|install-payments|install-webshop|install-ecommerce|install-builder|install-lms|install-education|install-wiki|install-print-designer|install-drive|install-gameplan|install-lending|install-raven|install-india-compliance|install-gst|install-india-gst|advanced-app-tools|app-advanced-tools|custom-app-tools|install-custom-app|app-install-wizard|app-wizard|app-install-guide|app-rollback-guide|repair-app-registry)
        ACTION="$1"
        shift
        ;;
      *)
        if [[ -n "${ACTION:-}" && "$1" != -* ]]; then
          ACTION_ARG="$1"
          shift
        else
          fail "Unknown argument: $1"
        fi
        ;;
    esac
  done

  if [[ -z "${ACTION}" && "${DOCTOR_FORMAT}" != "human" ]]; then
    ACTION="doctor"
  fi
}

main() {
  parse_args "$@"
  # Re-apply color policy after flags such as --no-color / NO_COLOR.
  # Uses ERPNEXT_DEV_STDOUT_TTY (snapshotted before tee) so OK/WARN/FAIL
  # colors survive the log redirect on interactive terminals.
  erpnext_dev_init_terminal_colors
  ui_init

  if action_requires_lock "${ACTION:-menu}"; then
    acquire_toolkit_lock
  fi

  case "${ACTION:-menu}" in
    ""|menu) show_menu ;;
    version|--version) echo "${APP_NAME} v${SCRIPT_VERSION}" ;;
    versions|version-matrix|toolchain) show_toolkit_versions ;;
    where-installed) show_where_installed ;;
    verify-toolkit|toolkit-verify|verify-install) verify_toolkit_integrity ;;
    verify-signature|verify-release-signature|verify-sig) verify_toolkit_signature ;;
    install-cli) install_toolkit_cli ;;
    repair-cli) repair_toolkit_cli ;;
    update-toolkit) update_toolkit ;;
    toolkit-rollback|update-toolkit-rollback|rollback-toolkit) rollback_toolkit ;;
    clear-lock|unlock|force-unlock) clear_toolkit_lock ;;
    menu-self-test|menu-navigation-self-test) menu_navigation_self_test ;;
    menu-render-test) menu_render_test ;;
    dashboard-render-test) dashboard_render_test ;;
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
    credentials-menu|login-menu) show_credentials_menu ;;
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
    install-gameplan) install_app_profile gameplan ;;
    install-lending) install_app_profile lending ;;
    install-raven) install_app_profile raven ;;
    install-india-compliance|install-gst|install-india-gst) install_app_profile india_compliance ;;
    install-custom-app) install_custom_app_interactive ;;
    repair-app-registry) repair_app_registry ;;
    backup) engine_backup false ;;
    backup-files) engine_backup true ;;
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
    off-vm-trust-host-key) off_vm_trust_host_key ;;
    off-vm-verify-host-key) off_vm_verify_host_key ;;
    off-vm-strict-host-key-enable) off_vm_strict_host_key_enable ;;
    off-vm-strict-host-key-disable) off_vm_strict_host_key_disable ;;
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
    dashboard|ops-dashboard-v2) run_operations_dashboard ;;
    health-snapshot) DASHBOARD_FORMAT=json; run_operations_dashboard ;;
    incidents) show_health_incidents ;;
    incident-show) show_health_incident "${ACTION_ARG:-}" ;;
    health-history) show_health_history "${ACTION_ARG:-20}" ;;
    health-metrics|openmetrics) health_emit_openmetrics ;;
    healing-status) show_healing_status ;;
    healing-policy) show_healing_policy ;;
    healing-history) show_healing_history "${ACTION_ARG:-20}" ;;
    healing-enable-safe) healing_enable_safe ;;
    healing-disable) healing_disable ;;
    healing-unlock) healing_unlock ;;
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
    update-preflight|upgrade-preflight) run_update_preflight ;;
    safe-update|safe-update-wizard|update-erpnext|upgrade-erpnext) run_safe_update_wizard ;;
    update-rollback|rollback-update) run_update_rollback ;;
    build) maintenance_build ;;
    clear-cache) maintenance_clear_cache ;;
    restart) maintenance_restart ;;
    wait-ready) wait_for_erpnext_ready ;;
    verify-frontend-assets) verify_frontend_assets ;;
    wait-frontend-assets) wait_frontend_assets ;;
    repair-frontend-assets) repair_frontend_assets ;;
    frappe-asset-checklist|frappe-frontend-assets) run_frappe_asset_checklist ;;
    foreground-start) run_foreground_start ;;
    enable-autostart) enable_autostart_service ;;
    disable-autostart) disable_autostart_service ;;
    service-start) start_erpnext_service ;;
    service-stop) stop_erpnext_service ;;
    service-restart) restart_erpnext_service ;;
    service-status) show_erpnext_service_status ;;
    setup-production-runtime|convert-to-production|production-runtime-setup) run_setup_production_runtime ;;
    convert-to-dev-runtime|convert-to-development-runtime) run_convert_to_dev_runtime ;;
    production-runtime-status|runtime-mode-status) show_production_runtime_status ;;
    logs) show_erpnext_service_logs ;;
    logs-follow) follow_erpnext_service_logs ;;
    local-ip-menu|local-network|local-network-menu) show_local_ip_menu main ;;
    local-ip-status) show_local_ip_status ;;
    local-ip-plan) show_local_ip_plan ;;
    local-ip-drift-check) run_local_ip_drift_check ;;
    local-ip-save) local_ip_save_mapping ;;
    local-static-ip-wizard) run_local_static_ip_wizard ;;
    local-static-ip-rollback) run_local_static_ip_rollback ;;
    local-fixed-ip-guide|fixed-ip-guide) show_local_fixed_ip_guide ;;
    kvm-guide|kvm-fixed-ip-guide) show_kvm_fixed_ip_guide ;;
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
    set-host-os|host-os|choose-host-os) run_set_host_os ;;
    set-engine|engine|choose-engine|deployment-engine) run_set_engine ;;
    engine-status) show_engine_status ;;
    engine-restore) engine_restore ;;
    engine-upgrade) engine_upgrade ;;
    engine-rollback) engine_rollback ;;
    engine-diagnostics) engine_diagnostics "$DOCTOR_FORMAT" ;;
    docker-production-setup|docker-prod-setup|docker-production) run_docker_production_setup ;;
    docker-backup) docker_backup false ;;
    docker-backup-files) docker_backup true ;;
    docker-backup-verify) docker_backup_verify ;;
    docker-restore|docker-restore-full) docker_restore full ;;
    docker-restore-db) docker_restore db ;;
    docker-restore-rehearsal) docker_restore_rehearsal ;;
    docker-restore-evidence) docker_show_restore_evidence ;;
    docker-offvm-backup) run_off_vm_backup_rsync run ;;
    docker-offvm-backup-dry-run) run_off_vm_backup_rsync dry-run ;;
    docker-offvm-status) show_off_vm_backup_status ;;
    docker-object-config|docker-object-backup-config) configure_docker_object_backup ;;
    docker-object-backup) run_docker_object_backup run ;;
    docker-object-backup-dry-run) run_docker_object_backup dry-run ;;
    docker-object-status) show_docker_object_backup_status ;;
    configure-object-backup|object-backup-config|object-config) run_configure_object_backup ;;
    object-backup|run-object-backup) run_engine_object_backup run ;;
    object-backup-dry-run) run_engine_object_backup dry-run ;;
    object-status|object-backup-status) show_engine_object_backup_status ;;
    docker-https-wizard|docker-production-https|docker-https-menu) docker_https_wizard ;;
    docker-enable-letsencrypt|docker-letsencrypt|docker-https-letsencrypt) docker_enable_letsencrypt ;;
    docker-configure-cloudflare-origin|docker-cloudflare-origin|docker-https-cloudflare-origin) docker_configure_cloudflare_origin ;;
    docker-https-status) docker_https_status ;;
    docker-https-rollback|docker-disable-https) docker_https_rollback ;;
    docker-production-exposure|docker-exposure-check) docker_production_exposure ;;
    docker-custom-image-config|docker-custom-apps) docker_custom_image_config ;;
    docker-build-custom-image|docker-custom-image-build) docker_build_custom_image ;;
    docker-deploy-custom-image|docker-custom-image-deploy) docker_deploy_custom_image ;;
    docker-custom-image-status) docker_custom_image_status ;;
    docker-reconcile-app-image) docker_reconcile_app_image ;;
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
    security-audit|security-audit-test) run_security_audit ;;
    security-hardening-wizard|vm-firewall-wizard) security_hardening_wizard ;;
    ufw-ssh-admin-only) configure_ufw_ssh_admin_only ;;
    production-ssl-menu|production-https|production-https-menu) show_production_ssl_menu main ;;
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
