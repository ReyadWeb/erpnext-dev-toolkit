# shellcheck shell=bash
# Install/runtime status summaries and health reports for erpnext-dev.sh.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_STATUS_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_STATUS_LOADED=1

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

  if deployment_engine_is_docker; then
    local installed runtime
    installed="$(install_state)"
    runtime="$(runtime_state)"
    echo
    echo "============================================================"
    echo "ERPNext Developer Status (Docker)"
    echo "============================================================"
    status_line "Install" "$([[ "$installed" == "Installed" ]] && echo OK || echo WARN)" "$installed"
    status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo WARN)" "$runtime"
    status_line "Docker mode" "INFO" "$(docker_mode_label)"
    status_line "Internal site" "INFO" "$(docker_site_name)"
    if docker_is_production; then
      status_line "Public domain" "INFO" "$(docker_public_domain)"
      status_line "HTTPS mode" "$([[ "$(docker_https_mode)" != http ]] && echo OK || echo WARN)" "$(docker_https_mode)"
    else
      status_line "Direct port" "INFO" "${DOCKER_PUBLISH_PORT} (8080 by default)"
    fi
    echo "============================================================"
    docker_print_access
    return 0
  fi

  local vm_ip installed runtime auto svc bench_dir
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

  if deployment_engine_is_docker; then
    echo
    echo "============================================================"
    echo "ERPNext Runtime Status (Docker)"
    echo "============================================================"
    status_line "Runtime" "INFO" "$(runtime_state)"
    status_line "Mode" "INFO" "$(docker_mode_label)"
    status_line "Direct port" "INFO" "${DOCKER_PUBLISH_PORT} (local/pre-HTTPS only)"
    echo
    docker_runtime_status
    echo "============================================================"
    return 0
  fi

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

  if deployment_engine_is_docker; then
    local install_status
    install_status="$(install_state)"
    echo
    echo "============================================================"
    echo "ERPNext Installation Status (Docker)"
    echo "============================================================"
    status_line "Install status" "$([[ "$install_status" == "Installed" ]] && echo OK || echo FAIL)" "$install_status"
    status_line "Docker mode" "INFO" "$(docker_mode_label)"
    status_line "Compose project" "INFO" "$DOCKER_PROJECT_NAME"
    status_line "Internal site" "INFO" "$(docker_site_name)"
    status_line "frappe_docker" "$([[ -f "$(docker_compose_base_file)" || -f "$(docker_prod_base_file)" ]] && echo OK || echo WARN)" "$(docker_clone_dir)"
    echo
    echo "Container status:"
    docker_runtime_status || true
    echo "============================================================"
    return 0
  fi

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

  if deployment_engine_is_docker; then
    echo
    echo "============================================================"
    echo "ERPNext Service / Autostart Status (Docker)"
    echo "============================================================"
    status_line "Runtime model" "INFO" "Docker Compose (no native erpnext-dev.service)"
    status_line "Runtime" "INFO" "$(runtime_state)"
    status_line "Compose project" "INFO" "$DOCKER_PROJECT_NAME"
    echo
    docker_runtime_status || true
    echo
    echo "Lifecycle commands:"
    echo "  $(toolkit_cmd start)"
    echo "  $(toolkit_cmd stop)"
    echo "  $(toolkit_cmd restart)"
    echo "  $(toolkit_cmd logs)"
    echo "============================================================"
    return 0
  fi

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
    ui_submenu_header "Status & Health" "Runtime, installation, services, apps, and full health views"
    print_two_column_menu \
      "1) Status Summary" \
      "2) Runtime Status" \
      "3) Installation Status" \
      "4) Service / Autostart Status" \
      "5) Optional App Status" \
      "6) Full Health Report"
    menu_footer
    local status_choice=""
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




run_full_status() {
  require_sudo

  if deployment_engine_is_docker; then
    echo
    echo "============================================================"
    echo "ERPNext Developer Full Health Report (Docker)"
    echo "============================================================"
    status_line "Install" "INFO" "$(install_state)"
    status_line "Runtime" "INFO" "$(runtime_state)"
    status_line "Mode" "INFO" "$(docker_mode_label)"
    status_line "Site" "INFO" "$(docker_site_name)"
    if docker_is_production; then
      status_line "Public domain" "INFO" "$(docker_public_domain)"
      status_line "HTTPS mode" "INFO" "$(docker_https_mode)"
    else
      status_line "Direct port" "INFO" "${DOCKER_PUBLISH_PORT} (8080 by default)"
    fi
    echo "============================================================"
    echo
    docker_verify_access || true
    if docker_is_production; then
      echo
      docker_https_status || true
      echo
      docker_production_exposure || true
    fi
    return 0
  fi

  echo
  echo "============================================================"
  echo "ERPNext Developer Full Health Report"
  echo "============================================================"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if { [[ "${ID:-}" == "ubuntu" ]] && [[ "${VERSION_ID:-}" == "24.04" || "${VERSION_ID:-}" == "26.04" ]]; } \
      || { [[ "${ID:-}" == "debian" ]] && [[ "${VERSION_ID:-}" == "13" ]]; }; then
      status_line "OS" "OK" "${PRETTY_NAME:-unknown}"
    else
      status_line "OS" "FAIL" "${PRETTY_NAME:-unknown}; supported: Ubuntu 24.04 / 26.04, Debian 13"
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
