# shellcheck shell=bash
# Frappe user execution, bench detection, and VM context helpers for erpnext-dev.sh.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_FRAPPE_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_FRAPPE_LOADED=1

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

  # Docker installations intentionally have no host Bench directory or native
  # systemd service. Treat a provisioned toolkit-owned Docker stack as a valid
  # ERPNext VM context so shared VM-only helpers (notably local mkcert/Nginx
  # HTTPS) work for the Docker engine too.
  if declare -F deployment_engine_is_docker >/dev/null 2>&1 && deployment_engine_is_docker; then
    if [[ -f "${DOCKER_WORKDIR:-/opt/erpnext-dev/docker}/frappe_docker/pwd.yml" || \
          -f "${DOCKER_WORKDIR:-/opt/erpnext-dev/docker}/frappe_docker/compose.yaml" ]]; then
      return 0
    fi
  fi

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
  echo "To avoid changing the HOST machine by mistake, the command was blocked before sudo work."
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

