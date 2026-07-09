# shellcheck shell=bash
# Shared logging, UI, locking, prompts, and command helpers for erpnext-dev.sh.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_COMMON_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_COMMON_LOADED=1

erpnext_dev_init_terminal_colors() {
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
}

prepare_log_file() {
  local uid fallback_dir template parent
  uid="${EUID:-$(id -u)}"

  if [[ "$LOG_FILE_WAS_SET" -eq 1 ]]; then
    parent="$(dirname "$LOG_FILE")"
    mkdir -p "$parent" 2>/dev/null || {
      echo "ERROR: Cannot create log directory: $parent" >&2
      exit 1
    }
    : >"$LOG_FILE" || {
      echo "ERROR: Cannot write log file: $LOG_FILE" >&2
      exit 1
    }
    chmod 600 "$LOG_FILE" 2>/dev/null || true
    return 0
  fi

  if ! mkdir -p "$LOG_DIR" 2>/dev/null || [[ ! -w "$LOG_DIR" ]]; then
    fallback_dir="/tmp/erpnext-dev-${uid}-logs"
    mkdir -p "$fallback_dir" 2>/dev/null || {
      echo "ERROR: Cannot create fallback log directory: $fallback_dir" >&2
      exit 1
    }
    chmod 700 "$fallback_dir" 2>/dev/null || true
    LOG_DIR="$fallback_dir"
  fi

  template="${LOG_DIR}/erpnext-dev-$(date +%Y%m%d-%H%M%S)-uid${uid}-pid$$.XXXXXX.log"
  LOG_FILE="$(mktemp "$template")" || {
    echo "ERROR: Cannot create log file in: $LOG_DIR" >&2
    exit 1
  }
  chmod 600 "$LOG_FILE" 2>/dev/null || true
}

log() { echo -e "\n${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
ok() { echo -e "${GREEN}OK:${RESET} $*"; }
warn() { echo -e "${YELLOW}WARN:${RESET} $*"; }
err() { echo -e "${RED}ERROR:${RESET} $*" >&2; }
fail() { err "$*"; echo "Log file: $LOG_FILE" >&2; exit 1; }

prepare_lock_file() {
  local uid fallback_dir
  uid="${EUID:-$(id -u)}"

  if [[ "$LOCK_FILE_WAS_SET" -eq 0 ]]; then
    mkdir -p "$LOCK_DIR" 2>/dev/null || true
    chmod 1777 "$LOCK_DIR" 2>/dev/null || true
  else
    mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
  fi

  if ! (: >"$LOCK_FILE") 2>/dev/null; then
    fallback_dir="/tmp/erpnext-dev-${uid}-locks"
    mkdir -p "$fallback_dir" 2>/dev/null || {
      echo "ERROR: Cannot create fallback lock directory: $fallback_dir" >&2
      exit 1
    }
    chmod 700 "$fallback_dir" 2>/dev/null || true
    LOCK_FILE="${fallback_dir}/toolkit.lock"
    : >"$LOCK_FILE" 2>/dev/null || {
      echo "ERROR: Cannot write lock file: $LOCK_FILE" >&2
      exit 1
    }
  fi

  chmod 666 "$LOCK_FILE" 2>/dev/null || true
}

acquire_toolkit_lock() {
  prepare_lock_file
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    err "Another toolkit task is already running."
    echo "Lock file: $LOCK_FILE" >&2
    echo "Wait for it to finish, or remove the lock only if you are sure no toolkit is running." >&2
    exit 1
  fi
}

action_requires_lock() {
  local action="${1:-menu}"
  case "$action" in
    ""|menu|first-run|start-here|quickstart|setup-wizard|public-vm-quickstart|public-setup|public-vm-guided-setup|public-guided-setup|production-guided-setup|local-dev-quickstart|local-setup|install-preflight|environment-preflight|set-domain|guided-setup|setup|install|repair|start|stop|uninstall|advanced|backup-menu|backup|backup-files|backup-status|backup-verify|verify-backups|off-vm-backup-guide|restore-rehearsal-guide|restore-rehearsal-status|restore-rehearsal-record|restore-rehearsal-report|go-live-record|go-live-status|cloud-firewall-checklist|cloudflare-checklist|restore-rehearsal-wizard|restore-key-setup|pull-off-vm-backup|backup-server-add-restore-key|backup-server-remove-restore-key|backup-server-list-restore-keys|production-checklist|release-readiness|final-qa|final-qa-wizard|command-audit|release-notes-guide|backup-hardening-wizard|backup-wizard|backup-schedule-plan|configure-backup-schedule|backup-schedule-status|scheduled-backup-status|disable-backup-schedule|scheduled-backups|backup-retention-plan|backup-retention-status|cleanup-old-backups|cleanup-old-backups-dry-run|backup-cleanup-dry-run|backup-cleanup|off-vm-backup-plan|off-vm-backup-guided-setup|generate-off-vm-backup-key|off-vm-backup-keygen|backup-server-setup|prepare-backup-server|off-vm-backup-server-setup|configure-rsync-backup-target|off-vm-backup-dry-run|run-off-vm-backup|off-vm-backup-status|disable-off-vm-backup|off-vm-backup-wizard|credentials-info|credentials|login-info|credentials-show|show-credentials|credentials-file-status|credentials-secure|credentials-delete|reset-admin-password|admin-password-reset|health-check|health-check-run-now|configure-health-check-timer|health-check-status|health-check-journal|disable-health-check-timer|health-monitoring-wizard|production-monitoring-wizard|service-recovery-plan|restore-preflight|restore-rehearsal-wizard|restore-key-setup|pull-off-vm-backup|backup-server-add-restore-key|backup-server-remove-restore-key|backup-server-list-restore-keys|production-ops-wizard|production-ops-dashboard|operations-wizard|operations-dashboard|ops-wizard|ops-dashboard|restore-db|restore-full|maintenance|migrate|build|clear-cache|restart|foreground-start|enable-autostart|disable-autostart|service-start|service-stop|service-restart|install-local-ssl-cert|replace-local-ssl-cert|create-self-signed-local-cert|self-signed-local-cert|configure-local-ssl|disable-local-ssl|production-ssl-menu|production-https|production-https-menu|configure-production-ssl|production-ssl-wizard|ssl-provider-wizard|ssl-mode-status|ssl-mode-guide|ssl-compatibility|setup-effort-guide|setup-step-count|setup-lifecycle-plan|setup-order-plan|configure-cloudflare-origin-ssl|install-cloudflare-origin-cert|switch-to-cloudflare-origin-ssl|disable-production-ssl|configure-vm-firewall|vm-firewall-wizard|security-hardening-wizard|security-mode-status|local-firewall-profile|local-security-profile|production-firewall-profile|production-security-profile|repair-local-access|local-access-doctor|local-domain-status|local-host-checkpoint|host-dns-checkpoint|host-mapping-checkpoint|host-dns-guide|print-hosts-command|local-fixed-ip-guide|fixed-ip-guide|kvm-fixed-ip-guide|firewall-rollback-snapshots|configure-fail2ban|ufw-ssh-admin-only|local-ssl-menu|local-https|local-vm-ssl|local-ssl-wizard|ssl-wizard|trusted-mkcert-setup|mkcert-setup|repair-site-config|change-local-domain|local-domain-wizard|rename-local-site|change-site-domain|expand-root-storage|app-library|apps|app-install-wizard|app-wizard|app-install-guide|app-rollback-guide|install-crm|install-hrms|install-helpdesk|install-telephony|install-insights|install-payments|install-webshop|install-ecommerce|install-builder|install-lms|install-education|install-wiki|install-print-designer|install-drive|install-raven|advanced-app-tools|app-advanced-tools|custom-app-tools|install-custom-app|repair-app-registry|install-cli|repair-cli|update-toolkit|verify-toolkit|toolkit-verify|verify-install)
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

ui_box_start() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

ui_box_end() {
  echo "============================================================"
}

ui_next() {
  local item
  echo
  echo "Next:"
  for item in "$@"; do
    printf '  %s\n' "$(toolkit_display_item "$item")"
  done
}

menu_footer() {
  local mode="${1:-back}"
  echo
  echo "-----------------------------"
  if [[ "$mode" == "quit-only" ]]; then
    printf 'q) Quit\n'
  else
    printf 'b) Back                        q) Quit\n'
  fi
  echo
}

trim_menu_choice() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

menu_read_choice() {
  local __target="$1"
  local __choice=""

  if ! read -r -p "Choose an option: " __choice; then
    __choice="q"
  fi

  __choice="$(trim_menu_choice "$__choice")"
  case "${__choice,,}" in
    quit|exit) __choice="q" ;;
    back) __choice="b" ;;
  esac

  printf -v "$__target" '%s' "$__choice"
}

print_two_column_menu() {
  local items=("$@")
  local total="${#items[@]}"
  local cols half i left right left_len right_len
  local max_left=0 max_right=0 gap=4 width required

  cols="${MENU_TERMINAL_COLS:-}"
  if [[ -z "$cols" ]]; then
    cols="$(tput cols 2>/dev/null || true)"
  fi
  if ! [[ "$cols" =~ ^[0-9]+$ ]] || ((cols <= 0)); then
    cols="${COLUMNS:-100}"
  fi
  if ! [[ "$cols" =~ ^[0-9]+$ ]] || ((cols <= 0)); then
    cols=100
  fi

  half=$(((total + 1) / 2))

  for ((i = 0; i < half; i++)); do
    left="${items[$i]}"
    right="${items[$((i + half))]:-}"
    left_len=${#left}
    right_len=${#right}
    ((left_len > max_left)) && max_left="$left_len"
    ((right_len > max_right)) && max_right="$right_len"
  done

  required=$((max_left + gap + max_right))
  if ((required > cols)); then
    gap=2
    required=$((max_left + gap + max_right))
  fi

  if [[ "${MENU_FORCE_ONE_COLUMN:-false}" == "true" ]]; then
    for left in "${items[@]}"; do
      printf '%s\n' "$left"
    done
    return 0
  fi

  if ((required > cols)) && [[ "${MENU_FORCE_TWO_COLUMNS:-false}" != "true" ]]; then
    for left in "${items[@]}"; do
      printf '%s\n' "$left"
    done
    return 0
  fi

  width=$((max_left + gap))
  if [[ -n "${MENU_COLUMN_WIDTH:-}" && "${MENU_COLUMN_WIDTH}" =~ ^[0-9]+$ ]]; then
    width="${MENU_COLUMN_WIDTH}"
  fi

  for ((i = 0; i < half; i++)); do
    left="${items[$i]}"
    right="${items[$((i + half))]:-}"
    printf '%-*s' "$width" "$left"
    if [[ -n "$right" ]]; then
      printf '%s' "$right"
    fi
    printf '\n'
  done
}

sync_toolkit_lib_tree() {
  local src_root="$1"
  local dest_root="$2"

  if [[ ! -d "${src_root}/lib" ]]; then
    return 0
  fi

  mkdir -p "${dest_root}/lib" || return 1
  cp -a "${src_root}/lib/." "${dest_root}/lib/" || return 1
  return 0
}

active_toolkit_path() {
  local src

  if [[ -x "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev}" ]]; then
    printf '%s' "erpnext-dev"
    return 0
  fi

  if [[ -x "${INSTALLER_CANONICAL_PATH:-}" ]]; then
    printf '%s' "$INSTALLER_CANONICAL_PATH"
    return 0
  fi

  src="$(readlink -f "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" 2>/dev/null || true)"
  if [[ -n "$src" && -f "$src" ]]; then
    printf '%s' "$src"
    return 0
  fi

  printf '%s' "./erpnext-dev.sh"
}

toolkit_display_item() {
  local item="$1"
  local suffix

  if [[ "$item" == .\/erpnext-dev.sh* ]]; then
    suffix="${item#.\/erpnext-dev.sh}"
    suffix="${suffix# }"
    toolkit_cmd "$suffix"
    return 0
  fi

  if [[ -n "${INSTALLER_CANONICAL_PATH:-}" && "$item" == "${INSTALLER_CANONICAL_PATH}"* ]]; then
    suffix="${item#${INSTALLER_CANONICAL_PATH}}"
    suffix="${suffix# }"
    toolkit_cmd "$suffix"
    return 0
  fi

  printf '%s' "$item"
}

toolkit_cmd() {
  local subcmd="${1:-}"
  local script_path
  script_path="$(active_toolkit_path)"
  printf '%s' "sudo ${script_path}${subcmd:+ $subcmd}"
}

toolkit_cmd_env() {
  local env_args="${1:-}"
  local subcmd="${2:-}"
  local script_path
  script_path="$(active_toolkit_path)"
  printf '%s' "sudo ${env_args:+$env_args }${script_path}${subcmd:+ $subcmd}"
}

suggested_vm_ssh_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    printf '%s' "$SUDO_USER"
  else
    id -un 2>/dev/null || printf 'USER'
  fi
}

menu_invalid_choice() {
  local choice="${1:-}" exit_hint="${2:-type the menu number}"
  if [[ "$choice" == *erpnext-dev.sh* || "$choice" == *erpnext-dev* || "$choice" == ./* || "$choice" == sudo\ * || "$choice" == curl\ * ]]; then
    warn "A shell command was pasted into an interactive menu."
    echo "This menu expects a number, b/B, or q/Q. ${exit_hint}, then run commands at the shell prompt."
    return 2
  fi
  warn "Invalid option. Type a menu number, b/B for Back, or q/Q for Quit."
  return 1
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
  if [[ "${EUID}" -ne 0 ]]; then
    err "This command changes or inspects protected ERPNext VM resources and must be run with sudo."
    echo
    echo "Run:"
    echo "  sudo $(active_toolkit_path) ${ACTION:-menu}"
    echo
    echo "Help and version can be run without sudo:"
    echo "  erpnext-dev --help"
    echo "  erpnext-dev version"
    exit 1
  fi

  SUDO=""

  if declare -F resolve_site_name_after_sudo >/dev/null 2>&1; then
    resolve_site_name_after_sudo 2>/dev/null || true
  fi
}
