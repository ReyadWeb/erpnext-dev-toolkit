# shellcheck shell=bash
# ERPNext systemd service, runtime readiness, and state helpers.
[[ -n "${_ERPNEXT_DEV_SERVICE_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_SERVICE_LOADED=1

# ============================================================
# Service / Runtime
# ============================================================

start_erpnext_foreground() {
  log "Starting ERPNext development server in foreground"

  local bench_dir
  bench_dir="$(require_bench_dir)" || return 1

  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "ERPNext will start in development mode."
  echo
  echo "Keep this terminal open while using ERPNext."
  echo
  echo "Preferred URL after HOST /etc/hosts is configured:"
  echo "  http://${SITE_NAME}:8000/login"
  echo
  echo "Troubleshooting only (often unstyled — Host header mismatch):"
  echo "  http://${vm_ip}:8000"
  echo
  echo "If ${SITE_NAME} does not open, confirm /etc/hosts, then run:"
  echo "  $(toolkit_cmd access)"
  echo

  $SUDO -iu "$FRAPPE_USER" bash -lc "
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    cd \"${bench_dir}\"
    bench start
  "
}


erpnext_service_path() {
  echo "/etc/systemd/system/${ERPNEXT_SERVICE_NAME}"
}

service_exists() {
  [[ -f "$(erpnext_service_path)" ]]
}


port_listens() {
  local port="$1"
  nc -z 127.0.0.1 "$port" >/dev/null 2>&1
}

bench_ports_ready() {
  port_listens 8000 && port_listens 9000 && port_listens 11000 && port_listens 13000
}

bench_ready_count() {
  local count=0
  local port

  for port in 8000 9000 11000 13000; do
    if port_listens "$port"; then
      count=$((count + 1))
    fi
  done

  echo "$count"
}

bench_readiness_line() {
  local elapsed="$1"
  local timeout="$2"
  local http_state="${3:-}"
  local assets_state="${4:-}"
  local web socket queue cache

  if port_listens 8000; then web="OK"; else web="wait"; fi
  if port_listens 9000; then socket="OK"; else socket="wait"; fi
  if port_listens 11000; then queue="OK"; else queue="wait"; fi
  if port_listens 13000; then cache="OK"; else cache="wait"; fi
  if [[ -z "$http_state" ]]; then
    if bench_http_ready; then http_state="OK"; else http_state="wait"; fi
  fi
  if [[ -z "$assets_state" ]]; then
    if bench_static_assets_ready; then assets_state="OK"; else assets_state="wait"; fi
  fi

  printf "  [%3ss/%3ss] web: %-4s http: %-4s assets: %-4s socket: %-4s queue: %-4s cache: %-4s\n" \
    "$elapsed" "$timeout" "$web" "$http_state" "$assets_state" "$socket" "$queue" "$cache"
}

# Login CSS/JS must answer 2xx/3xx with a non-empty body (probe_login_static_asset).
# Prefers HTTPS (nginx) when :443 listens so the same path the browser uses is
# checked; otherwise probes bench :8000 directly.
# Must honor the probe return code — printing path|status alone is not success
# (empty Content-Length: 0 bodies used to false-pass wait-ready).
bench_static_assets_ready() {
  local probe_rc=0

  if port_listens 443; then
    set +e
    probe_login_static_asset "https://${SITE_NAME}/login" "$SITE_NAME" 443 "127.0.0.1" >/dev/null
    probe_rc=$?
    set -e
  elif port_listens 8000; then
    set +e
    probe_login_static_asset "http://${SITE_NAME}:8000/login" "$SITE_NAME" 8000 "127.0.0.1" >/dev/null
    probe_rc=$?
    set -e
  else
    return 1
  fi

  [[ "$probe_rc" -eq 0 ]]
}

# shellcheck disable=SC2120 # timeout/interval are optional overrides with sane defaults
wait_for_erpnext_ready() {
  local timeout="${1:-$READY_TIMEOUT}"
  local interval="${2:-$READY_INTERVAL}"
  local elapsed=0
  local http_state assets_state

  echo
  echo "Waiting for ERPNext services to become ready..."
  echo "Requires ports, HTTP ping, and login static assets (CSS/JS)."
  echo "This can take up to ${timeout}s after start/restart (READY_TIMEOUT)."
  echo

  while (( elapsed <= timeout )); do
    http_state="wait"
    assets_state="wait"
    if bench_http_ready; then
      http_state="OK"
    fi
    # Assets depend on a working login response; skip the extra curls until ping works.
    if [[ "$http_state" == "OK" ]] && bench_static_assets_ready; then
      assets_state="OK"
    fi

    bench_readiness_line "$elapsed" "$timeout" "$http_state" "$assets_state"

    # Ports alone are not enough: the login HTML can return before CSS/JS bundles
    # are served (unstyled page). Require HTTP ping + static-asset probe in both
    # development and production runtimes.
    if bench_ports_ready && [[ "$http_state" == "OK" && "$assets_state" == "OK" ]]; then
      if runtime_is_production; then
        ok "ERPNext is ready. Production runtime is serving (HTTP + static assets)."
      else
        ok "ERPNext is ready. Development ports, HTTP, and static assets are OK."
      fi
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  warn "ERPNext did not become fully ready within ${timeout}s."
  echo
  echo "Useful checks:"
  echo "  $(toolkit_cmd runtime-status)"
  echo "  $(toolkit_cmd verify-local-ssl)   # look at Static assets"
  echo "  $(toolkit_cmd logs)"
  echo "  sudo systemctl status ${ERPNEXT_SERVICE_NAME} --no-pager -l"
  echo
  echo "If only assets stay on wait, rebuild and clear cache, then retry:"
  echo "  $(toolkit_cmd repair-frontend-assets)"
  echo "  READY_TIMEOUT=${timeout} $(toolkit_cmd wait-frontend-assets)"
  echo "  (or: READY_TIMEOUT=${timeout} $(toolkit_cmd wait-ready))"
  return 1
}

# One-shot frontend asset status (login Link CSS/JS). Exit 0 when OK.
verify_frontend_assets() {
  local probe_out="" probe_rc=0 asset_path="" asset_head=""
  local mode="http"

  require_site_environment >/dev/null || true

  ui_box_start "Frontend assets"
  status_line "Site" "INFO" "${SITE_NAME}"

  if port_listens 443; then
    mode="https"
    set +e
    probe_out="$(probe_login_static_asset "https://${SITE_NAME}/login" "$SITE_NAME" 443 "127.0.0.1")"
    probe_rc=$?
    set -e
  elif port_listens 8000; then
    set +e
    probe_out="$(probe_login_static_asset "http://${SITE_NAME}:8000/login" "$SITE_NAME" 8000 "127.0.0.1")"
    probe_rc=$?
    set -e
  else
    status_line "Static assets" "FAIL" "neither :443 nor :8000 is listening"
    echo
    echo "Start the stack, then re-check:"
    echo "  $(toolkit_cmd start)"
    echo "  $(toolkit_cmd wait-ready)"
    ui_box_end
    return 1
  fi

  asset_path="${probe_out%%|*}"
  asset_head="${probe_out#*|}"
  status_line "Probe mode" "INFO" "${mode}"

  case "$probe_rc" in
    0)
      status_line "Static assets" "OK" "${asset_path} (${asset_head})"
      ui_next "$(toolkit_cmd wait-frontend-assets)" "$(toolkit_cmd repair-frontend-assets)" "$(toolkit_cmd verify-access)"
      ui_box_end
      return 0
      ;;
    2)
      status_line "Static assets" "FAIL" "login response has no Link preload for CSS/JS"
      ;;
    *)
      status_line "Static assets" "FAIL" "${asset_path:-unknown} (${asset_head:-no status})"
      ;;
  esac

  echo
  echo "Repair path:"
  echo "  $(toolkit_cmd repair-frontend-assets)"
  echo "  $(toolkit_cmd wait-frontend-assets)"
  ui_box_end
  return 1
}

# Wait until login static assets pass (ports + HTTP + assets), same gate as wait-ready.
wait_frontend_assets() {
  wait_for_erpnext_ready "$@"
}

# Rebuild assets, clear cache, restart, and re-verify the login CSS/JS probe.
repair_frontend_assets() {
  require_sudo
  require_site_environment >/dev/null || fail "Site/bench environment is required before repairing frontend assets."

  ui_box_start "Repair frontend assets"
  status_line "Site" "INFO" "${SITE_NAME}"
  echo
  log "Building assets (bench build)"
  maintenance_build || fail "bench build failed; fix the build error, then retry $(toolkit_cmd repair-frontend-assets)."
  log "Clearing site cache"
  maintenance_clear_cache || fail "clear-cache failed after build."
  log "Restarting ERPNext service"
  restart_erpnext_service || fail "Service restart failed after asset rebuild."
  echo
  if bench_static_assets_ready; then
    status_line "Static assets" "OK" "login CSS/JS probe passed"
    ok "Frontend assets repaired and verified."
    ui_next "$(toolkit_cmd verify-frontend-assets)" "$(toolkit_cmd verify-access)" "$(toolkit_cmd doctor)"
    ui_box_end
    return 0
  fi
  status_line "Static assets" "FAIL" "probe still failing after rebuild"
  err "Assets still failing after build/clear-cache/restart."
  echo "Check: $(toolkit_cmd logs) · $(toolkit_cmd verify-frontend-assets) · $(toolkit_cmd verify-local-ssl)"
  ui_box_end
  return 1
}

ensure_bench_services_for_site_commands() {
  local context="${1:-maintenance command}"
  local bench_dir
  bench_dir="$(active_bench_dir)"

  if ! service_exists; then
    err "ERPNext service is not configured, so Bench services are not managed by this toolkit yet."
    echo
    echo "Start Bench manually as the ${FRAPPE_USER} user if you are using development mode:"
    echo "  sudo -iu ${FRAPPE_USER} bash -lc 'export PATH=\"\$HOME/.local/bin:\$PATH\"; cd ${bench_dir} && bench start'"
    return 1
  fi

  if systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}" && bench_ports_ready; then
    if bench_http_ready && bench_static_assets_ready; then
      ok "Bench services are ready for ${context} (HTTP + static assets)."
      return 0
    fi
    # Do not block mid-flow ops (clear-cache, post-restore) on a full ready wait —
    # that races asset rebuilds and broke restore CI. Surface clearly; callers that
    # need a hard gate use wait-ready / wait-frontend-assets / repair-frontend-assets.
    warn "Ports are up for ${context}, but HTTP/static assets are not ready yet."
    echo "  If the UI looks unstyled: $(toolkit_cmd repair-frontend-assets)"
    echo "  Or wait: $(toolkit_cmd wait-frontend-assets)"
    return 0
  fi

  if systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    warn "ERPNext service is active, but one or more Bench ports are not ready. Restarting before ${context}."
  else
    warn "ERPNext service is not running. Starting it before ${context}."
  fi

  if ! $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}"; then
    err "Could not restart ${ERPNEXT_SERVICE_NAME} before ${context}."
    echo "Check logs with: $(toolkit_cmd logs)"
    return 1
  fi

  wait_for_erpnext_ready
}

create_erpnext_service() {
  require_sudo

  local bench_dir
  if ! bench_dir="$(require_bench_dir)"; then
    return 1
  fi

  log "Creating ERPNext development systemd service"

  $SUDO tee "$(erpnext_service_path)" >/dev/null <<EOF_SERVICE
[Unit]
Description=ERPNext Frappe Bench Development Server (${SITE_NAME})
After=network-online.target mariadb.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=${FRAPPE_USER}
Group=${FRAPPE_USER}
WorkingDirectory=${bench_dir}
Environment=HOME=${FRAPPE_HOME}
ExecStart=/bin/bash -lc 'export NVM_DIR="\$HOME/.nvm"; [ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"; nvm use --silent default >/dev/null 2>&1 || true; export PATH="\$HOME/.local/bin:\$PATH"; cd "${bench_dir}" && bench start'
Restart=on-failure
RestartSec=10
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  $SUDO systemctl daemon-reload
  ok "Service created: ${ERPNEXT_SERVICE_NAME}"
}

enable_autostart_service() {
  require_sudo

  if ! service_exists; then
    create_erpnext_service || return 1
  fi

  log "Enabling ERPNext autostart on VM boot"
  if $SUDO systemctl enable "${ERPNEXT_SERVICE_NAME}"; then
    ok "Autostart enabled"
  else
    err "Could not enable autostart for ${ERPNEXT_SERVICE_NAME}"
    return 1
  fi
}

disable_autostart_service() {
  require_sudo

  if service_exists; then
    log "Disabling ERPNext autostart"
    $SUDO systemctl disable "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
    ok "Autostart disabled"
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

start_erpnext_service() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_start
    return
  fi

  if runtime_is_production; then
    production_runtime_start
    return
  fi

  if ! service_exists; then
    create_erpnext_service || return 1
  fi

  log "Starting ERPNext service"
  if $SUDO systemctl start "${ERPNEXT_SERVICE_NAME}"; then
    ok "ERPNext service start command completed"
    if wait_for_erpnext_ready; then
      show_ready_summary
    else
      return 1
    fi
  else
    err "Could not start ${ERPNEXT_SERVICE_NAME}. Check logs with: $(toolkit_cmd logs)"
    return 1
  fi
}

stop_erpnext_service() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_stop
    return
  fi

  if runtime_is_production; then
    production_runtime_stop
    return
  fi

  if service_exists; then
    log "Stopping ERPNext service"
    $SUDO systemctl stop "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
    ok "ERPNext service stopped"
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    $SUDO pkill -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1 || true
    $SUDO pkill -u "$FRAPPE_USER" -f "frappe.utils.bench_helper" >/dev/null 2>&1 || true
  fi
}

restart_erpnext_service() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_restart
    return
  fi

  if runtime_is_production; then
    production_runtime_restart
    return
  fi

  if ! service_exists; then
    create_erpnext_service || return 1
  fi

  log "Restarting ERPNext service"
  if $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}"; then
    ok "ERPNext service restart command completed"
    if wait_for_erpnext_ready; then
      show_ready_summary
    else
      return 1
    fi
  else
    err "Could not restart ${ERPNEXT_SERVICE_NAME}. Check logs with: $(toolkit_cmd logs)"
    return 1
  fi
}

show_erpnext_service_status() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_status
    return
  fi

  if runtime_is_production; then
    show_production_runtime_status
    return
  fi

  if service_exists; then
    $SUDO systemctl status "${ERPNEXT_SERVICE_NAME}" --no-pager || true
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

show_erpnext_service_logs() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_logs
    return
  fi

  if runtime_is_production; then
    show_production_runtime_logs
    return
  fi

  if service_exists; then
    $SUDO journalctl -u "${ERPNEXT_SERVICE_NAME}" -n 160 --no-pager || true
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

follow_erpnext_service_logs() {
  require_sudo

  if service_exists; then
    $SUDO journalctl -u "${ERPNEXT_SERVICE_NAME}" -f
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

install_state() {
  local bench_dir
  bench_dir="$(active_bench_dir)"

  if path_is_dir "${bench_dir}" && path_is_dir "${bench_dir}/apps/frappe" && path_is_dir "${bench_dir}/apps/erpnext" && path_is_dir "${bench_dir}/sites/${SITE_NAME}"; then
    if site_app_installed erpnext || [[ -f "${bench_dir}/sites/apps.txt" ]]; then
      echo "Installed"
    else
      echo "Installed files found; site app not confirmed"
    fi
  elif path_is_dir "${bench_dir}" || path_is_dir "${FRAPPE_HOME}"; then
    echo "Incomplete"
  else
    echo "Not installed"
  fi
}

runtime_state() {
  local ready_count
  ready_count="$(bench_ready_count)"

  if runtime_is_production; then
    if production_runtime_configured && production_processes_running && bench_ports_ready; then
      echo "Running via supervisor (production)"
    elif production_runtime_configured && production_processes_running; then
      echo "Starting via supervisor (production)"
    elif production_runtime_configured; then
      echo "Stopped (production/supervisor)"
    else
      echo "Production runtime not set up"
    fi
    return
  fi

  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    if bench_ports_ready; then
      echo "Running via service"
    elif [[ "$ready_count" -gt 0 ]]; then
      echo "Starting / partially ready via service"
    else
      echo "Starting via service"
    fi
  elif port_listens 8000; then
    echo "Running in foreground"
  elif id "$FRAPPE_USER" >/dev/null 2>&1 && pgrep -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1; then
    echo "Starting / partially running"
  else
    echo "Stopped"
  fi
}

autostart_state() {
  if service_exists && systemctl is-enabled --quiet "${ERPNEXT_SERVICE_NAME}" 2>/dev/null; then
    echo "Enabled"
  elif service_exists; then
    echo "Disabled"
  else
    echo "Not configured"
  fi
}

service_state() {
  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    echo "Running"
  elif service_exists; then
    echo "Stopped"
  else
    echo "Not configured"
  fi
}

run_start() {
  require_sudo
  start_erpnext_service
}

run_stop() {
  require_sudo
  stop_erpnext_service
}

run_foreground_start() {
  require_sudo

  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    warn "ERPNext service is already running in the background."
    if ! confirm "Start a foreground bench session anyway?"; then
      return 0
    fi
  fi

  start_erpnext_foreground
}

show_service_menu() {
  while true; do
    ui_submenu_header "Autostart / Service Manager" "systemd service control"
    print_two_column_menu \
      "1) Enable autostart on VM boot" \
      "2) Disable autostart" \
      "3) Start ERPNext service" \
      "4) Stop ERPNext service" \
      "5) Restart ERPNext service" \
      "6) Show service status" \
      "7) Show recent service logs" \
      "8) Follow service logs"
    menu_footer
    local service_choice=""
    menu_read_choice service_choice

    case "$service_choice" in
      1) enable_autostart_service ;;
      2) disable_autostart_service ;;
      3) start_erpnext_service ;;
      4) stop_erpnext_service ;;
      5) restart_erpnext_service ;;
      6) show_erpnext_service_status ;;
      7) show_erpnext_service_logs ;;
      8) follow_erpnext_service_logs ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

# ============================================================
# Production runtime (supervisor: gunicorn + workers + scheduler + socket.io)
#
# In production the toolkit does NOT use `bench start` (a development server
# with a live-reload watcher and debugger). Instead it uses Frappe's own
# `bench setup supervisor` to generate the correct, version-matched process set
# and runs it under supervisord. The toolkit's existing Nginx/TLS layer stays in
# front, proxying :443/:80 to gunicorn (:8000) and socket.io (:9000) exactly as
# it already does for the dev runtime.
# ============================================================

supervisor_conf_link() {
  echo "/etc/supervisor/conf.d/frappe-bench.conf"
}

supervisorctl_bin() {
  command -v supervisorctl 2>/dev/null || echo /usr/bin/supervisorctl
}

production_runtime_configured() {
  [[ -L "$(supervisor_conf_link)" || -f "$(supervisor_conf_link)" ]]
}

production_supervisor_status() {
  $SUDO "$(supervisorctl_bin)" status 2>/dev/null || true
}

production_processes_running() {
  production_supervisor_status | grep -q "RUNNING"
}

# HTTP-level readiness: gunicorn must actually answer, not just listen.
bench_http_ready() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${SITE_NAME}" \
    "http://127.0.0.1:8000/api/method/ping" 2>/dev/null || echo 000)"
  [[ "$code" == "200" ]]
}

production_runtime_start() {
  require_sudo
  if ! production_runtime_configured; then
    err "Production runtime is not set up. Run: $(toolkit_cmd setup-production-runtime)"
    return 1
  fi
  log "Starting production runtime (supervisor)"
  $SUDO "$(supervisorctl_bin)" start all >/dev/null 2>&1 || true
  if wait_for_erpnext_ready; then
    show_ready_summary
  else
    return 1
  fi
}

production_runtime_stop() {
  require_sudo
  log "Stopping production runtime (supervisor)"
  $SUDO "$(supervisorctl_bin)" stop all >/dev/null 2>&1 || true
  ok "Production processes stopped."
}

production_runtime_restart() {
  require_sudo
  if ! production_runtime_configured; then
    err "Production runtime is not set up. Run: $(toolkit_cmd setup-production-runtime)"
    return 1
  fi
  log "Restarting production runtime (supervisor)"
  $SUDO "$(supervisorctl_bin)" restart all >/dev/null 2>&1 || true
  if wait_for_erpnext_ready; then
    show_ready_summary
  else
    return 1
  fi
}

show_production_runtime_logs() {
  require_sudo
  local bench_dir logf
  bench_dir="$(active_bench_dir)"

  echo "Supervisor programs:"
  production_supervisor_status
  echo
  for logf in web.error.log web.log worker.error.log worker.log schedule.log; do
    if [[ -f "${bench_dir}/logs/${logf}" ]]; then
      echo "== ${bench_dir}/logs/${logf} (last 40 lines) =="
      $SUDO tail -n 40 "${bench_dir}/logs/${logf}" 2>/dev/null || true
      echo
    fi
  done
}

show_production_runtime_status() {
  require_sudo
  ui_box_start "Production Runtime Status"
  status_line "Runtime mode" "INFO" "$(runtime_mode)"
  status_line "Supervisor config" "$(production_runtime_configured && echo OK || echo WARN)" "$(supervisor_conf_link)"
  status_line "Web (gunicorn) :8000" "$(port_listens 8000 && echo OK || echo WARN)" "backend web workers"
  status_line "Socket.IO :9000" "$(port_listens 9000 && echo OK || echo WARN)" "realtime"
  status_line "HTTP ping" "$(bench_http_ready && echo OK || echo WARN)" "http://127.0.0.1:8000/api/method/ping"
  status_line "Static assets" "$(bench_static_assets_ready && echo OK || echo WARN)" "login CSS/JS Link probe"
  echo
  echo "Supervisor programs:"
  production_supervisor_status
  ui_box_end
}

# Convert an existing install from the dev bench-start runtime to a supervisor
# managed production runtime. Idempotent: safe to re-run.
setup_production_runtime() {
  require_sudo
  local bench_dir
  bench_dir="$(require_bench_dir)" || return 1

  if [[ "$(install_state)" != Installed* ]]; then
    err "ERPNext is not fully installed yet. Run the install first: $(toolkit_cmd install)"
    return 1
  fi

  ui_box_start "Set up production runtime (supervisor)"

  log "Installing supervisor package"
  if ! command -v supervisorctl >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y >/dev/null 2>&1 || true
    if ! DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y supervisor >/dev/null 2>&1; then
      err "Could not install the supervisor package."
      ui_box_end
      return 1
    fi
  fi
  $SUDO systemctl enable --now supervisor >/dev/null 2>&1 || true

  log "Generating supervisor config from bench (bench setup supervisor)"
  if ! frappe_login_bash <<EOF_PROD
set -Eeuo pipefail
export PATH="\$HOME/.local/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
cd "${bench_dir}"
bench setup supervisor --user "${FRAPPE_USER}" --yes
EOF_PROD
  then
    err "bench setup supervisor failed. See the output above."
    ui_box_end
    return 1
  fi

  if [[ -f "${bench_dir}/config/supervisor.conf" ]]; then
    $SUDO ln -sf "${bench_dir}/config/supervisor.conf" "$(supervisor_conf_link)"
    ok "Linked supervisor config -> $(supervisor_conf_link)"
  else
    err "Expected ${bench_dir}/config/supervisor.conf was not generated."
    ui_box_end
    return 1
  fi

  # Stop and disable the development bench-start service; production must never
  # silently fall back to the dev server.
  if service_exists; then
    log "Disabling development bench-start service"
    $SUDO systemctl disable --now "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    $SUDO pkill -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1 || true
  fi

  # shellcheck disable=SC2034 # cross-module global read via runtime_mode()/config.sh
  RUNTIME_MODE="production"
  write_dev_config_file

  log "Reloading supervisor"
  $SUDO "$(supervisorctl_bin)" reread >/dev/null 2>&1 || true
  $SUDO "$(supervisorctl_bin)" update >/dev/null 2>&1 || true
  $SUDO "$(supervisorctl_bin)" start all >/dev/null 2>&1 || true

  if wait_for_erpnext_ready; then
    ok "Production runtime active: gunicorn + workers + scheduler + socket.io under supervisor."
  else
    warn "Production processes were started but readiness did not pass yet."
    echo "  Inspect with: $(toolkit_cmd production-runtime-status)"
  fi

  echo
  echo "The development bench-start service is now disabled; ERPNext runs under supervisor."
  echo "Nginx/TLS remain managed by the toolkit (proxying to 127.0.0.1:8000 / :9000)."
  echo "Manage the runtime with: $(toolkit_cmd service-status) / $(toolkit_cmd restart) / $(toolkit_cmd logs)"
  ui_box_end
}

run_setup_production_runtime() {
  require_sudo
  if runtime_is_production && production_runtime_configured; then
    warn "Production runtime already configured. Re-running to refresh the supervisor config."
  fi
  setup_production_runtime
}

# Revert from the supervisor production runtime back to the dev bench-start
# service. Does not touch the database or apps.
convert_to_dev_runtime() {
  require_sudo
  require_bench_dir >/dev/null || return 1

  ui_box_start "Convert back to development runtime (bench start)"

  if production_runtime_configured; then
    log "Stopping supervisor-managed processes"
    $SUDO "$(supervisorctl_bin)" stop all >/dev/null 2>&1 || true
    $SUDO rm -f "$(supervisor_conf_link)"
    $SUDO "$(supervisorctl_bin)" reread >/dev/null 2>&1 || true
    $SUDO "$(supervisorctl_bin)" update >/dev/null 2>&1 || true
    ok "Removed the supervisor program group."
  fi

  # shellcheck disable=SC2034 # cross-module global read via runtime_mode()/config.sh
  RUNTIME_MODE="dev"
  write_dev_config_file

  if create_erpnext_service; then
    ok "Development runtime restored. Start it with: $(toolkit_cmd start)"
  else
    ui_box_end
    return 1
  fi
  ui_box_end
}

run_convert_to_dev_runtime() {
  require_sudo
  convert_to_dev_runtime
}
