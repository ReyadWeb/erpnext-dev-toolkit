# shellcheck shell=bash
# Support bundle, diagnostics, and command-audit helpers.
[[ -n "${_ERPNEXT_DEV_SUPPORT_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_SUPPORT_LOADED=1

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
  local data layout root_bytes vg_free_bytes tail_free_bytes reason
  data="$(storage_eval 2>/dev/null || true)"

  while IFS='=' read -r k v; do
    case "$k" in
      LAYOUT) layout="$v" ;;
      ROOT_BYTES) root_bytes="$v" ;;
      VG_FREE_BYTES) vg_free_bytes="$v" ;;
      TAIL_FREE_BYTES) tail_free_bytes="$v" ;;
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

  if grep -Ei '(^|/)(site_config\.json|site_config_backup\.json|common_site_config\.json|secrets\.json|\.env(\.|$|/|$)|.*credentials.*|erpnext-dev-credentials\.txt|id_rsa|id_ed25519|authorized_keys|.*\.pem|.*\.key|.*\.enc|.*\.sql(\.gz)?|.*database.*\.gz|.*private-files\.tar|.*passwd.*|.*shadow.*|.*token.*\.(json|txt|env))' "$listing_file" > "$hit_file"; then
    status_line "Forbidden filenames" "FAIL" "potential secret/backup filenames found"
    sed -n '1,80p' "$hit_file"
    rc=1
  else
    status_line "Forbidden filenames" "OK" "none found"
  fi

  if tar -xzf "$archive" -C "$tmpdir" 2>"${tmpdir}/tar-extract.stderr"; then
    if grep -RInE '(-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----|Bearer[[:space:]]+[A-Za-z0-9._~+/=-]+|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk_(live|test)_[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16}|aws_secret_access_key[[:space:]]*=[[:space:]]*[^[:space:]"'"'"';]+|("?(password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|authorization|cookie|db_password|admin_password|mysql_password|redis_password)"?[[:space:]]*[:=][[:space:]]*[^[:space:],;]"'"'"'`]+))'       --exclude='archive-list.txt'       --exclude='audit-hits.txt'       "$tmpdir" > "$hit_file" 2>/dev/null; then
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
  status_line "Security" "OK" "security-audit, security-hardening-wizard, vm-firewall-status, fail2ban-status"
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
