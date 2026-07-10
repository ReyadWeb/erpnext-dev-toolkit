# shellcheck shell=bash
# Site name, domain, and toolkit config file helpers for erpnext-dev.sh.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_CONFIG_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_CONFIG_LOADED=1

is_public_vm_workflow() {
  [[ "${DEPLOYMENT_MODE:-}" == "public-vm" ]] && return 0
  [[ -n "${PRODUCTION_DOMAIN:-}" ]] && return 0
  return 1
}

# Runtime mode controls HOW ERPNext is served:
#   dev        -> `bench start` (development server + watcher + debugger)
#   production -> gunicorn + workers + scheduler + socket.io under supervisor
# It is independent of DEPLOYMENT_MODE (local vs public-vm) and defaults to dev
# unless explicitly set (via setup-production-runtime or the saved config).
runtime_mode() {
  case "${RUNTIME_MODE:-}" in
    production|dev) printf '%s\n' "${RUNTIME_MODE}" ;;
    *) printf 'dev\n' ;;
  esac
}

runtime_is_production() {
  [[ "$(runtime_mode)" == "production" ]]
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

  if [[ -z "${RUNTIME_MODE:-}" ]]; then
    if saved="$(read_saved_config_value RUNTIME_MODE 2>/dev/null)" && [[ -n "$saved" ]]; then
      RUNTIME_MODE="$saved"
    fi
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
RUNTIME_MODE=$(runtime_mode)
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
RUNTIME_MODE=$(runtime_mode)
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
