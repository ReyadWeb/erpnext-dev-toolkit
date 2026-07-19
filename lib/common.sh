# shellcheck shell=bash
# Shared logging, UI, locking, prompts, and command helpers for erpnext-dev.sh.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_COMMON_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_COMMON_LOADED=1

erpnext_dev_init_terminal_colors() {
  # Snapshot whether the operator's original stdout was a TTY *before*
  # `exec > >(tee -a "$LOG_FILE")` turns fd 1 into a pipe. Re-checking `-t 1`
  # after that redirect would permanently disable GREEN/OK colors in menus.
  if [[ -z "${ERPNEXT_DEV_STDOUT_TTY:-}" ]]; then
    if [[ -t 1 ]]; then
      ERPNEXT_DEV_STDOUT_TTY=1
    else
      ERPNEXT_DEV_STDOUT_TTY=0
    fi
    export ERPNEXT_DEV_STDOUT_TTY
  fi

  if [[ -n "${NO_COLOR:-}" || "${FORCE_NO_COLOR:-0}" -eq 1 ]] \
     || [[ "${ERPNEXT_DEV_STDOUT_TTY}" != "1" ]]; then
    BOLD=""
    GREEN=""
    YELLOW=""
    RED=""
    BLUE=""
    RESET=""
  else
    BOLD="\033[1m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    RED="\033[31m"
    BLUE="\033[34m"
    RESET="\033[0m"
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

# Create a private lock directory owned by this user with mode 0700. Returns 0 if
# the directory is safe to use (exists, is a real dir, not a symlink, owned by us).
toolkit_prepare_lock_dir() {
  local dir="$1"
  local uid
  uid="${EUID:-$(id -u)}"

  # Refuse a symlinked directory: a symlink here could redirect the lock file
  # (and its truncate) to an attacker-chosen target.
  if [[ -L "$dir" ]]; then
    return 1
  fi
  mkdir -p "$dir" 2>/dev/null || return 1
  chmod 700 "$dir" 2>/dev/null || true

  # Must be a directory we own (defends against a pre-existing dir owned by
  # someone else on a shared /run or /tmp).
  [[ -d "$dir" && ! -L "$dir" ]] || return 1
  if command -v stat >/dev/null 2>&1; then
    local owner
    owner="$(stat -c '%u' "$dir" 2>/dev/null || echo -1)"
    [[ "$owner" == "$uid" || "$owner" == "0" ]] || return 1
  fi
  return 0
}

prepare_lock_file() {
  local uid lock_dir fallback_dir
  uid="${EUID:-$(id -u)}"

  lock_dir="$(dirname "$LOCK_FILE")"
  if ! toolkit_prepare_lock_dir "$lock_dir"; then
    fallback_dir="/tmp/erpnext-dev-${uid}-locks"
    if ! toolkit_prepare_lock_dir "$fallback_dir"; then
      echo "ERROR: Cannot create a private lock directory (${lock_dir} or ${fallback_dir})." >&2
      exit 1
    fi
    LOCK_FILE="${fallback_dir}/toolkit.lock"
  fi

  # Refuse a symlinked lock file: following it would let a pre-planted symlink
  # redirect our truncate/write to an attacker-chosen target.
  if [[ -L "$LOCK_FILE" ]]; then
    echo "ERROR: Refusing to use a symlinked lock file: $LOCK_FILE" >&2
    echo "Remove it if you are sure it is safe: sudo rm -f \"$LOCK_FILE\"" >&2
    exit 1
  fi

  # Create the lock file if missing; do NOT truncate an existing one — another
  # process may hold flock on that inode and we want its pid= metadata intact.
  if [[ ! -e "$LOCK_FILE" ]]; then
    : >"$LOCK_FILE" 2>/dev/null || {
      echo "ERROR: Cannot write lock file: $LOCK_FILE" >&2
      exit 1
    }
  fi
  # Private lock file: owner read/write only. The directory is already 0700.
  chmod 600 "$LOCK_FILE" 2>/dev/null || true
}

# List PIDs that currently hold an open handle on the lock file (best-effort).
toolkit_lock_holder_pids() {
  local lock="${1:-$LOCK_FILE}"
  local pids=""
  if command -v fuser >/dev/null 2>&1; then
    pids="$(fuser "$lock" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')" || true
  elif command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t "$lock" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" || true
  fi
  printf '%s' "$pids"
}

toolkit_describe_lock_holders() {
  local lock="${1:-$LOCK_FILE}"
  local pids pid cmd meta
  pids="$(toolkit_lock_holder_pids "$lock")"
  if [[ -z "$pids" ]]; then
    echo "  (no process currently holds the lock file open)"
    return 1
  fi
  for pid in $pids; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    cmd="$(ps -o args= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
    [[ -n "$cmd" ]] || cmd="(process exited while inspecting)"
    echo "  PID ${pid}: ${cmd}"
  done
  if [[ -f "$lock" ]] && meta="$(head -n 3 "$lock" 2>/dev/null)" && [[ -n "$meta" ]]; then
    echo "  Lock file metadata:"
    printf '%s\n' "$meta" | sed 's/^/    /'
  fi
  return 0
}

acquire_toolkit_lock() {
  prepare_lock_file
  # Final defense in depth: never open a symlinked lock file.
  if [[ -L "$LOCK_FILE" ]]; then
    err "Refusing to open a symlinked lock file: $LOCK_FILE"
    exit 1
  fi
  # Open read/write without truncating so a failed acquire still leaves holder metadata readable.
  exec 200<>"$LOCK_FILE"
  if ! flock -n 200; then
    err "Another toolkit task is already running (or a previous session is still holding the lock)."
    echo "Lock file: $LOCK_FILE" >&2
    echo >&2
    echo "Who holds it:" >&2
    toolkit_describe_lock_holders "$LOCK_FILE" >&2 || true
    echo >&2
    echo "What to do:" >&2
    echo "  1. Check other terminals/SSH sessions for a running 'erpnext-dev' / menu." >&2
    echo "  2. If a PID is listed above and it is stuck, stop it:  sudo kill <PID>" >&2
    echo "  3. If you are sure nothing is running, clear safely:" >&2
    echo "       sudo erpnext-dev clear-lock" >&2
    echo >&2
    echo "Do NOT 'rm' the lock file while another toolkit is still running — that can" >&2
    echo "allow two installs to run at once. Prefer clear-lock (it refuses if a holder is live)." >&2
    exit 1
  fi
  # We own the lock: reset metadata for the next waiter.
  : >"$LOCK_FILE"
  {
    echo "pid=$$"
    echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "cmd=${APP_NAME:-erpnext-dev} ${ACTION:-menu}"
  } >&200 || true
}

# Safe unlock helper: refuses if a live process still holds the flock.
clear_toolkit_lock() {
  require_sudo
  local pids force="${FORCE_CLEAR_LOCK:-0}"

  prepare_lock_file
  ui_box_start "Clear toolkit lock"
  status_line "Lock file" "INFO" "$LOCK_FILE"

  pids="$(toolkit_lock_holder_pids "$LOCK_FILE")"
  if [[ -n "$pids" && "$force" != "1" ]]; then
    status_line "Lock holders" "FAIL" "still live"
    toolkit_describe_lock_holders "$LOCK_FILE" || true
    echo
    err "Refusing to clear: a process still holds the lock."
    echo "Stop that process first (sudo kill <PID>), or re-check other terminals."
    echo "Only if you are certain those PIDs are wrong, override with:"
    echo "  sudo FORCE_CLEAR_LOCK=1 erpnext-dev clear-lock"
    ui_box_end
    return 1
  fi

  if [[ -n "$pids" && "$force" == "1" ]]; then
    warn "FORCE_CLEAR_LOCK=1: removing lock while holders may still be alive: ${pids}"
    toolkit_describe_lock_holders "$LOCK_FILE" || true
  elif [[ -z "$pids" ]]; then
    status_line "Lock holders" "OK" "none (safe to clear)"
  fi

  rm -f "$LOCK_FILE" 2>/dev/null || fail "Could not remove ${LOCK_FILE}"
  # The next run recreates the lock file (mode 0600) in its private lock dir.
  ok "Lock cleared. You can run: sudo erpnext-dev"
  ui_box_end
}

action_requires_lock() {
  local action="${1:-menu}"
  case "$action" in
    ""|menu|first-run|start-here|quickstart|setup-wizard|public-vm-quickstart|public-setup|public-vm-guided-setup|public-guided-setup|production-guided-setup|local-dev-quickstart|local-setup|install-preflight|environment-preflight|set-domain|guided-setup|setup|install|repair|start|stop|uninstall|advanced|backup-menu|backup|backup-files|backup-status|backup-verify|verify-backups|off-vm-backup-guide|restore-rehearsal-guide|restore-rehearsal-status|restore-rehearsal-record|restore-rehearsal-report|go-live-record|go-live-status|cloud-firewall-checklist|cloudflare-checklist|restore-rehearsal-wizard|restore-key-setup|pull-off-vm-backup|backup-server-add-restore-key|backup-server-remove-restore-key|backup-server-list-restore-keys|production-checklist|release-readiness|final-qa|final-qa-wizard|command-audit|release-notes-guide|backup-hardening-wizard|backup-wizard|backup-schedule-plan|configure-backup-schedule|backup-schedule-status|scheduled-backup-status|disable-backup-schedule|scheduled-backups|backup-retention-plan|backup-retention-status|cleanup-old-backups|cleanup-old-backups-dry-run|backup-cleanup-dry-run|backup-cleanup|off-vm-backup-plan|off-vm-backup-guided-setup|generate-off-vm-backup-key|off-vm-backup-keygen|backup-server-setup|prepare-backup-server|off-vm-backup-server-setup|configure-rsync-backup-target|off-vm-trust-host-key|off-vm-verify-host-key|off-vm-strict-host-key-enable|off-vm-strict-host-key-disable|off-vm-backup-dry-run|run-off-vm-backup|off-vm-backup-status|disable-off-vm-backup|off-vm-backup-wizard|credentials-info|credentials|login-info|credentials-show|show-credentials|credentials-file-status|credentials-secure|credentials-delete|credentials-menu|login-menu|reset-admin-password|admin-password-reset|health-check|health-check-run-now|configure-health-check-timer|health-check-status|health-check-journal|disable-health-check-timer|health-monitoring-wizard|production-monitoring-wizard|dashboard|ops-dashboard-v2|health-snapshot|incidents|incident-show|health-history|health-metrics|openmetrics|service-recovery-plan|restore-preflight|production-ops-wizard|production-ops-dashboard|operations-wizard|operations-dashboard|ops-wizard|ops-dashboard|restore-db|restore-full|maintenance|migrate|build|clear-cache|restart|verify-frontend-assets|wait-frontend-assets|repair-frontend-assets|frappe-asset-checklist|frappe-frontend-assets|foreground-start|enable-autostart|disable-autostart|service-start|service-stop|service-restart|install-local-ssl-cert|replace-local-ssl-cert|create-self-signed-local-cert|self-signed-local-cert|configure-local-ssl|disable-local-ssl|production-ssl-menu|production-https|production-https-menu|configure-production-ssl|production-ssl-wizard|ssl-provider-wizard|ssl-mode-status|ssl-mode-guide|ssl-compatibility|setup-effort-guide|setup-step-count|setup-lifecycle-plan|setup-order-plan|configure-cloudflare-origin-ssl|install-cloudflare-origin-cert|switch-to-cloudflare-origin-ssl|disable-production-ssl|configure-vm-firewall|vm-firewall-wizard|security-hardening-wizard|security-mode-status|local-firewall-profile|local-security-profile|production-firewall-profile|production-security-profile|repair-local-access|local-access-doctor|local-domain-status|local-host-checkpoint|host-dns-checkpoint|host-mapping-checkpoint|host-dns-guide|print-hosts-command|local-ip-menu|local-network|local-network-menu|local-ip-status|local-ip-plan|local-ip-drift-check|local-ip-save|local-static-ip-wizard|local-static-ip-rollback|local-fixed-ip-guide|fixed-ip-guide|kvm-fixed-ip-guide|firewall-rollback-snapshots|configure-fail2ban|ufw-ssh-admin-only|local-ssl-menu|local-https|local-vm-ssl|local-ssl-wizard|ssl-wizard|trusted-mkcert-setup|mkcert-setup|repair-site-config|change-local-domain|local-domain-wizard|rename-local-site|change-site-domain|expand-root-storage|app-library|apps|app-install-wizard|app-wizard|app-install-guide|app-rollback-guide|install-crm|install-hrms|install-helpdesk|install-telephony|install-insights|install-payments|install-webshop|install-ecommerce|install-builder|install-lms|install-education|install-wiki|install-print-designer|install-drive|install-raven|advanced-app-tools|app-advanced-tools|custom-app-tools|install-custom-app|repair-app-registry|install-cli|repair-cli|update-toolkit|verify-toolkit|toolkit-verify|verify-install)
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

# Print where the user is in the menu tree and how to reopen this screen later.
# Example: menu_location_note "Main menu > 8) Local HTTPS > 1) SSL Wizard" "local-ssl-wizard"
menu_location_note() {
  local path="${1:-}"
  local reopen_cmd="${2:-}"
  [[ -n "$path" ]] && echo "Path: ${path}"
  if [[ -n "$reopen_cmd" ]]; then
    echo "Reopen anytime: $(toolkit_cmd "$reopen_cmd")"
  fi
}

menu_footer() {
  local mode="${1:-back}"
  local back_label="${2:-}"
  echo
  if declare -F ui_init >/dev/null 2>&1; then
    ui_init
    if [[ "$mode" == "quit-only" ]]; then
      ui_text cyan "[q]"
      printf ' Quit\n'
    elif [[ -n "$back_label" ]]; then
      ui_text cyan "[b]"
      printf ' Back to %s\n' "$back_label"
      ui_text cyan "[q]"
      printf ' Quit\n'
    else
      ui_text cyan "[b]"
      printf ' Back    '
      ui_text cyan "[q]"
      printf ' Quit\n'
    fi
  else
    if [[ "$mode" == "quit-only" ]]; then
      printf '[q] Quit\n'
    elif [[ -n "$back_label" ]]; then
      printf '[b] Back to %s\n' "$back_label"
      printf '[q] Quit\n'
    else
      printf '[b] Back    [q] Quit\n'
    fi
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

  if declare -F ui_prompt >/dev/null 2>&1; then
    ui_prompt "Choose an option: " __choice
  elif ! read -r -p "Choose an option: " __choice; then
    __choice="q"
  fi

  __choice="$(trim_menu_choice "$__choice")"
  case "${__choice,,}" in
    quit|exit) __choice="q" ;;
    back) __choice="b" ;;
  esac

  printf -v "$__target" '%s' "$__choice"
}

# Print a menu item like "3) CRM [official]" with a cyan number prefix when
# color UI is available (same look as the polished main menu).
print_menu_item_text() {
  local item="$1"
  local num rest
  if declare -F ui_text >/dev/null 2>&1 && [[ "$item" =~ ^([0-9]+)\)[[:space:]]*(.*)$ ]]; then
    num="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    ui_text cyan "${num})"
    printf ' %s' "$rest"
  else
    printf '%s' "$item"
  fi
}

print_two_column_menu() {
  # Prefer the shared boxed renderer so submenus match the main menu UI.
  if declare -F ui_render_boxed_menu >/dev/null 2>&1; then
    ui_render_boxed_menu "$@"
    return 0
  fi

  # Legacy fallback (ui.sh not loaded).
  local item
  for item in "$@"; do
    print_menu_item_text "$item"
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

  # Prefer the entry script resolved at bootstrap (readlink -f of erpnext-dev.sh).
  # Do NOT use BASH_SOURCE[1] here: callers live in lib/*.sh, so that would print
  # a library path (e.g. lib/common.sh) instead of the toolkit entrypoint.
  if [[ -n "${ERPNEXT_DEV_ENTRY_SCRIPT:-}" && -f "${ERPNEXT_DEV_ENTRY_SCRIPT}" ]]; then
    printf '%s' "$ERPNEXT_DEV_ENTRY_SCRIPT"
    return 0
  fi

  src="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
  if [[ -n "$src" && -f "$src" && "$(basename "$src")" == "erpnext-dev.sh" ]]; then
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

  # shellcheck disable=SC2034 # SUDO is a shared global consumed by the sourced lib/* modules
  SUDO=""

  if declare -F resolve_site_name_after_sudo >/dev/null 2>&1; then
    resolve_site_name_after_sudo 2>/dev/null || true
  fi
}
