# shellcheck shell=bash
# Health monitoring, go-live validation, and production readiness helpers.
[[ -n "${_ERPNEXT_DEV_HEALTH_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_HEALTH_LOADED=1

# ============================================================
# Health / Go-Live / Production Readiness
# ============================================================

health_check_unit_paths() {
  echo "/etc/systemd/system/${HEALTH_CHECK_SERVICE}"
  echo "/etc/systemd/system/${HEALTH_CHECK_TIMER}"
}

health_check_timer_enabled() {
  systemctl is-enabled --quiet "${HEALTH_CHECK_TIMER}" 2>/dev/null
}

health_check_timer_active() {
  systemctl is-active --quiet "${HEALTH_CHECK_TIMER}" 2>/dev/null
}

systemd_service_active_detail() {
  local svc="$1"
  if systemctl list-unit-files "${svc}" >/dev/null 2>&1 && systemctl is-active --quiet "${svc}" 2>/dev/null; then
    echo "OK|running"
  elif systemctl list-unit-files "${svc}" >/dev/null 2>&1; then
    echo "WARN|not running"
  else
    echo "WARN|not found"
  fi
}

health_backup_age_hours() {
  local latest_lines db_file now file_epoch
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  [[ -n "$latest_lines" ]] || { echo "unknown"; return 0; }
  db_file="$(printf '%s\n' "$latest_lines" | sed -n '2p')"
  [[ -n "$db_file" && -f "$db_file" ]] || { echo "unknown"; return 0; }
  now="$(date +%s)"
  file_epoch="$(stat -c %Y "$db_file" 2>/dev/null || echo 0)"
  if [[ "$file_epoch" =~ ^[0-9]+$ && "$file_epoch" -gt 0 ]]; then
    echo $(( (now - file_epoch) / 3600 ))
  else
    echo "unknown"
  fi
}


health_state_value() {
  local key="$1"
  [[ -f "$HEALTH_CHECK_STATE_FILE" ]] || return 0
  grep -E "^${key}=" "$HEALTH_CHECK_STATE_FILE" 2>/dev/null | tail -n 1 | cut -d= -f2-
}

health_check_write_state() {
  local overall="$1" installed="$2" runtime="$3" ssl_status="$4" disk_percent="$5" backup_state="$6" backup_age="$7" off_status="$8"
  mkdir -p "$(dirname "$HEALTH_CHECK_STATE_FILE")"
  cat > "$HEALTH_CHECK_STATE_FILE" <<EOF_HEALTH_STATE
HEALTH_CHECK_STATUS=${overall}
HEALTH_CHECK_RECORDED_AT=$(date -Iseconds)
HEALTH_CHECK_SITE=${SITE_NAME}
HEALTH_CHECK_DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-unknown}
HEALTH_CHECK_INSTALL=${installed}
HEALTH_CHECK_RUNTIME=${runtime}
HEALTH_CHECK_HTTPS_STATUS=${ssl_status}
HEALTH_CHECK_DISK_PERCENT=${disk_percent}
HEALTH_CHECK_BACKUP_STATUS=${backup_state}
HEALTH_CHECK_BACKUP_AGE_HOURS=${backup_age}
HEALTH_CHECK_OFF_VM_STATUS=${off_status}
HEALTH_CHECK_TOOLKIT_VERSION=${SCRIPT_VERSION}
EOF_HEALTH_STATE
  chmod 600 "$HEALTH_CHECK_STATE_FILE" 2>/dev/null || true
}

health_check_summary_pair() {
  local status recorded site age
  status="$(health_state_value HEALTH_CHECK_STATUS)"
  recorded="$(health_state_value HEALTH_CHECK_RECORDED_AT)"
  site="$(health_state_value HEALTH_CHECK_SITE)"
  age="$(health_state_value HEALTH_CHECK_BACKUP_AGE_HOURS)"
  if [[ -z "$status" ]]; then
    echo "INFO|no recorded health check yet"
  elif [[ "$status" == "OK" ]]; then
    echo "OK|last check OK at ${recorded:-unknown}; site ${site:-unknown}; backup age ${age:-unknown}h"
  else
    echo "WARN|last check ${status} at ${recorded:-unknown}; review health-check output"
  fi
}

run_health_check() {
  require_sudo

  local overall="OK" installed runtime ssl_pair ssl_status ssl_detail disk_percent disk_state
  local latest_lines completeness backup_age backup_state backup_msg redis_pair mariadb_pair nginx_pair
  local off_last_status off_last_run

  installed="$(install_state 2>/dev/null || echo "Unknown")"
  runtime="$(runtime_state 2>/dev/null || echo "Unknown")"

  if is_public_vm_workflow; then
    ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo "WARN|not confirmed")"
  else
    ssl_pair="INFO|production HTTPS not required for local mode"
  fi
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"

  disk_percent="$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5+0}' || echo 0)"
  if [[ "$disk_percent" =~ ^[0-9]+$ && "$disk_percent" -ge "${HEALTH_CHECK_DISK_WARN_PERCENT}" ]]; then
    disk_state="WARN"; overall="WARN"
  else
    disk_state="OK"
  fi

  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  if [[ -n "$latest_lines" ]]; then
    completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
  else
    completeness="none"
  fi
  backup_age="$(health_backup_age_hours)"
  backup_state="WARN"
  backup_msg="${completeness}"
  if [[ "$completeness" == "complete" ]]; then
    backup_state="OK"
    backup_msg="complete"
    if [[ "$backup_age" =~ ^[0-9]+$ ]]; then
      backup_msg="complete; ${backup_age}h old"
      if [[ "$backup_age" -gt "${HEALTH_CHECK_BACKUP_MAX_AGE_HOURS}" ]]; then
        backup_state="WARN"; overall="WARN"
      fi
    fi
  else
    overall="WARN"
  fi

  [[ "$installed" == "Installed" ]] || overall="WARN"
  [[ "$runtime" == Running* ]] || overall="WARN"
  [[ "$ssl_status" == "OK" || "$ssl_status" == "INFO" ]] || overall="WARN"

  ui_box_start "Health Check"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Install" "$([[ "$installed" == "Installed" ]] && echo OK || echo WARN)" "$installed"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo WARN)" "$runtime"

  if service_exists; then
    if systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}" 2>/dev/null; then
      status_line "ERPNext service" "OK" "running"
    else
      status_line "ERPNext service" "WARN" "not running"
      overall="WARN"
    fi
  else
    status_line "ERPNext service" "WARN" "not configured"
    overall="WARN"
  fi

  nginx_pair="$(systemd_service_active_detail nginx.service)"
  mariadb_pair="$(systemd_service_active_detail mariadb.service)"
  redis_pair="$(systemd_service_active_detail redis-server.service)"
  status_line "Nginx" "${nginx_pair%%|*}" "${nginx_pair#*|}"
  status_line "MariaDB" "${mariadb_pair%%|*}" "${mariadb_pair#*|}"
  status_line "Redis" "${redis_pair%%|*}" "${redis_pair#*|}"
  [[ "${nginx_pair%%|*}" == "OK" ]] || ! is_public_vm_workflow || overall="WARN"
  [[ "${mariadb_pair%%|*}" == "OK" ]] || overall="WARN"
  [[ "${redis_pair%%|*}" == "OK" ]] || overall="WARN"

  if port_listens 8000; then
    status_line "Bench web" "OK" "port 8000 listening"
  else
    status_line "Bench web" "WARN" "port 8000 not listening"
    overall="WARN"
  fi
  if port_listens 9000; then
    status_line "Socket.io" "OK" "port 9000 listening"
  else
    status_line "Socket.io" "WARN" "port 9000 not listening"
    overall="WARN"
  fi
  status_line "HTTPS" "$ssl_status" "$ssl_detail"
  status_line "Disk usage" "$disk_state" "${disk_percent}% used; warn at ${HEALTH_CHECK_DISK_WARN_PERCENT}%"
  status_line "Latest backup" "$backup_state" "$backup_msg"

  if backup_schedule_timer_active; then
    status_line "Backup timer" "OK" "active"
  else
    status_line "Backup timer" "INFO" "not active"
  fi

  if ufw_is_active; then
    status_line "UFW" "OK" "active"
  else
    status_line "UFW" "WARN" "not active"
    overall="WARN"
  fi
  if command -v fail2ban-client >/dev/null 2>&1 && $SUDO fail2ban-client status sshd >/dev/null 2>&1; then
    status_line "Fail2Ban" "OK" "sshd jail enabled"
  else
    status_line "Fail2Ban" "WARN" "sshd jail not confirmed"
    overall="WARN"
  fi

  if off_vm_backup_configured; then
    off_last_status="$(off_vm_backup_last_state LAST_STATUS 2>/dev/null || echo none)"
    off_last_run="$(off_vm_backup_last_state LAST_RUN_AT 2>/dev/null || echo never)"
    status_line "Off-VM backup" "$([[ "$off_last_status" == OK ]] && echo OK || echo INFO)" "configured; last run ${off_last_status} at ${off_last_run}"
  else
    off_last_status="not_configured"
    status_line "Off-VM backup" "INFO" "not configured"
  fi

  health_check_write_state "$overall" "$installed" "$runtime" "$ssl_status" "$disk_percent" "$backup_state" "$backup_age" "$off_last_status"
  status_line "State file" "OK" "$HEALTH_CHECK_STATE_FILE"
  status_line "Overall" "$overall" "$([[ "$overall" == OK ]] && echo "healthy" || echo "review WARN rows")"
  ui_box_end
  ui_next "$(toolkit_cmd health-check-status)" "$(toolkit_cmd health-monitoring-wizard)" "$(toolkit_cmd production-checklist)"
}

configure_health_check_timer() {
  require_sudo
  install_self_for_reuse
  local service_file timer_file
  service_file="$(health_check_unit_paths | sed -n '1p')"
  timer_file="$(health_check_unit_paths | sed -n '2p')"

  ui_box_start "Configure Health Check Timer"
  status_line "Service" "INFO" "${HEALTH_CHECK_SERVICE}"
  status_line "Timer" "INFO" "${HEALTH_CHECK_TIMER}"
  status_line "Schedule" "INFO" "OnCalendar=${HEALTH_CHECK_ON_CALENDAR}"
  status_line "Random delay" "INFO" "${HEALTH_CHECK_RANDOM_DELAY}"
  status_line "Command" "INFO" "${INSTALLER_CANONICAL_PATH} health-check"
  echo
  echo "This creates a local systemd timer that periodically runs a read-only health check."
  echo "Press Enter to accept the suggested schedule. Examples: hourly, daily, *-*-* 03:00:00"
  local schedule_reply delay_reply run_now_reply
  read -r -p "Health check schedule [${HEALTH_CHECK_ON_CALENDAR}]: " schedule_reply || schedule_reply=""
  [[ -n "$schedule_reply" ]] && HEALTH_CHECK_ON_CALENDAR="$schedule_reply"
  read -r -p "Randomized delay [${HEALTH_CHECK_RANDOM_DELAY}]: " delay_reply || delay_reply=""
  [[ -n "$delay_reply" ]] && HEALTH_CHECK_RANDOM_DELAY="$delay_reply"
  echo
  status_line "Selected schedule" "INFO" "OnCalendar=${HEALTH_CHECK_ON_CALENDAR}; RandomizedDelaySec=${HEALTH_CHECK_RANDOM_DELAY}"
  if ! confirm "Configure health check timer now?" "n"; then
    ui_box_end
    return 0
  fi

  log "Writing health check systemd units"
  cat > "$service_file" <<EOF_HEALTH_SERVICE
[Unit]
Description=ERPNext Developer Toolkit health check
After=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=${INSTALLER_CANONICAL_PATH} health-check
EOF_HEALTH_SERVICE

  cat > "$timer_file" <<EOF_HEALTH_TIMER
[Unit]
Description=Run ERPNext Developer Toolkit health check periodically

[Timer]
OnCalendar=${HEALTH_CHECK_ON_CALENDAR}
RandomizedDelaySec=${HEALTH_CHECK_RANDOM_DELAY}
Persistent=true
Unit=${HEALTH_CHECK_SERVICE}

[Install]
WantedBy=timers.target
EOF_HEALTH_TIMER

  systemctl daemon-reload
  systemctl enable --now "${HEALTH_CHECK_TIMER}"

  ui_box_start "Result Summary"
  status_line "Health timer" "OK" "enabled"
  status_line "Timer" "INFO" "${HEALTH_CHECK_TIMER}"
  status_line "Schedule" "INFO" "${HEALTH_CHECK_ON_CALENDAR}"
  ui_box_end
  read -r -p "Run a health check now? [Y/n]: " run_now_reply || run_now_reply=""
  if [[ -z "$run_now_reply" || "$run_now_reply" =~ ^[Yy]$|^[Yy][Ee][Ss]$ ]]; then
    run_health_check
  fi
  ui_next "$(toolkit_cmd health-check-status)" "systemctl list-timers ${HEALTH_CHECK_TIMER} --all"
}

show_health_check_status() {
  require_sudo
  local service_file timer_file enabled active next_line last_status state_pair state_status state_detail
  service_file="$(health_check_unit_paths | sed -n '1p')"
  timer_file="$(health_check_unit_paths | sed -n '2p')"
  enabled="disabled"
  active="inactive"
  health_check_timer_enabled && enabled="enabled"
  health_check_timer_active && active="active"
  next_line="$(systemctl list-timers "${HEALTH_CHECK_TIMER}" --all --no-pager 2>/dev/null | awk 'NR==2 {print $1" "$2" "$3" "$4}' || true)"
  last_status="$(systemctl show "${HEALTH_CHECK_SERVICE}" -p Result --value 2>/dev/null || echo unknown)"
  state_pair="$(health_check_summary_pair)"
  state_status="${state_pair%%|*}"
  state_detail="${state_pair#*|}"

  ui_box_start "Health Check Timer Status"
  status_line "Service file" "$([[ -f "$service_file" ]] && echo OK || echo WARN)" "$service_file"
  status_line "Timer file" "$([[ -f "$timer_file" ]] && echo OK || echo WARN)" "$timer_file"
  status_line "Timer enabled" "$([[ "$enabled" == enabled ]] && echo OK || echo WARN)" "$enabled"
  status_line "Timer active" "$([[ "$active" == active ]] && echo OK || echo WARN)" "$active"
  status_line "Schedule" "INFO" "${HEALTH_CHECK_ON_CALENDAR}"
  status_line "Last service result" "INFO" "${last_status:-unknown}"
  status_line "Next run" "INFO" "${next_line:-not scheduled}"
  status_line "Last health check" "$state_status" "$state_detail"
  status_line "State file" "$([[ -f "$HEALTH_CHECK_STATE_FILE" ]] && echo OK || echo INFO)" "$HEALTH_CHECK_STATE_FILE"
  echo
  echo "Useful commands:"
  echo "  systemctl list-timers ${HEALTH_CHECK_TIMER} --all"
  echo "  journalctl -u ${HEALTH_CHECK_SERVICE} --no-pager -n 80"
  echo "  sudo $(active_toolkit_path) health-check"
  echo "  sudo $(active_toolkit_path) health-check-journal"
  ui_next "$(toolkit_cmd health-check)" "$(toolkit_cmd health-monitoring-wizard)" "$(toolkit_cmd service-recovery-plan)"
  ui_box_end
}

show_health_check_journal() {
  require_sudo
  ui_box_start "Health Check Journal"
  status_line "Service" "INFO" "${HEALTH_CHECK_SERVICE}"
  echo
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u "${HEALTH_CHECK_SERVICE}" --no-pager -n 120 || true
  else
    status_line "journalctl" "WARN" "not available"
  fi
  ui_box_end
  ui_next "$(toolkit_cmd health-check-status)" "$(toolkit_cmd health-monitoring-wizard)"
}

health_monitoring_wizard() {
  require_sudo
  local health_title="Health Monitoring"
  if [[ "${PRODUCTION_OPS_CONTEXT:-0}" == "1" ]]; then
    health_title="$(production_ops_breadcrumb_title "Health Monitoring")"
  fi
  while true; do
    ui_box_start "$health_title"
    echo "1) Run health check now"
    echo "2) Configure health timer"
    echo "3) Health timer/status"
    echo "4) Health check journal"
    echo "5) Disable health timer"
    echo "6) Service recovery plan"
    echo "7) Production checklist"
    menu_footer
    local health_choice=""
    menu_read_choice health_choice
    case "$health_choice" in
      1) run_health_check; pause_after_screen "Press Enter to return to Health Monitoring..." ;;
      2) configure_health_check_timer; pause_after_screen "Press Enter to return to Health Monitoring..." ;;
      3) show_health_check_status; pause_after_screen "Press Enter to return to Health Monitoring..." ;;
      4) show_health_check_journal; pause_after_screen "Press Enter to return to Health Monitoring..." ;;
      5) disable_health_check_timer; pause_after_screen "Press Enter to return to Health Monitoring..." ;;
      6) show_service_recovery_plan; pause_after_screen "Press Enter to return to Health Monitoring..." ;;
      7) show_production_checklist; pause_after_screen "Press Enter to return to Health Monitoring..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

disable_health_check_timer() {
  require_sudo
  ui_box_start "Disable Health Check Timer"
  status_line "Timer" "INFO" "${HEALTH_CHECK_TIMER}"
  if ! confirm "Disable health check timer now?" "n"; then
    ui_box_end
    return 0
  fi
  systemctl disable --now "${HEALTH_CHECK_TIMER}" 2>/dev/null || true
  systemctl daemon-reload || true
  status_line "Health timer" "OK" "disabled"
  ui_box_end
  ui_next "$(toolkit_cmd health-check-status)"
}

show_service_recovery_plan() {
  require_sudo
  ui_box_start "Service Recovery Plan"
  status_line "Mode" "INFO" "planning only; no services are restarted"
  status_line "ERPNext service" "INFO" "${ERPNEXT_SERVICE_NAME}"
  echo
  echo "Recommended manual recovery order:"
  echo "  1) Run health-check and review WARN/FAIL rows."
  echo "  2) Check service logs before restarting."
  echo "  3) Restart only the affected service if clear."
  echo "  4) Re-run health-check and verify HTTPS."
  echo "  5) Create support bundle if the issue repeats."
  echo
  echo "Useful commands:"
  echo "  /opt/erpnext-dev/erpnext-dev.sh health-check"
  echo "  systemctl status ${ERPNEXT_SERVICE_NAME} --no-pager"
  echo "  journalctl -u ${ERPNEXT_SERVICE_NAME} --no-pager -n 120"
  echo "  systemctl restart ${ERPNEXT_SERVICE_NAME}"
  echo "  systemctl status nginx mariadb redis-server --no-pager"
  echo "  /opt/erpnext-dev/erpnext-dev.sh support-bundle"
  ui_box_end
}

go_live_value() {
  local key="$1" value=""
  if value="$(read_config_key_from_file "$GO_LIVE_RECORD_FILE" "$key" 2>/dev/null)" && [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}

go_live_bool_true() {
  local key="$1" value
  value="$(go_live_value "$key" 2>/dev/null || true)"
  case "${value,,}" in
    true|yes|y|1|ok|confirmed) return 0 ;;
    *) return 1 ;;
  esac
}

go_live_recorded_ok() {
  local status site
  status="$(go_live_value GO_LIVE_STATUS 2>/dev/null || true)"
  site="$(go_live_value GO_LIVE_SITE 2>/dev/null || true)"
  [[ "$status" == "OK" ]] || return 1
  [[ -z "$site" || "$site" == "$SITE_NAME" ]] || return 1
  go_live_bool_true GO_LIVE_SNAPSHOT_CONFIRMED || return 1
  go_live_bool_true GO_LIVE_CLOUD_FIREWALL_CONFIRMED || return 1
  go_live_bool_true GO_LIVE_CLOUDFLARE_PROXY_CONFIRMED || return 1
  go_live_bool_true GO_LIVE_CLOUDFLARE_FULL_STRICT_CONFIRMED || return 1
  return 0
}

go_live_summary_pair() {
  local status site recorded_at snapshot_name firewall cf_proxy cf_strict cf_origin notes detail
  if [[ ! -r "$GO_LIVE_RECORD_FILE" ]]; then
    printf 'WARN|not recorded; confirm snapshot, cloud firewall, and Cloudflare settings, then run go-live-record\n'
    return 0
  fi
  status="$(go_live_value GO_LIVE_STATUS 2>/dev/null || true)"
  site="$(go_live_value GO_LIVE_SITE 2>/dev/null || true)"
  recorded_at="$(go_live_value GO_LIVE_RECORDED_AT 2>/dev/null || true)"
  snapshot_name="$(go_live_value GO_LIVE_SNAPSHOT_NAME 2>/dev/null || true)"
  firewall="$(go_live_value GO_LIVE_CLOUD_FIREWALL_CONFIRMED 2>/dev/null || true)"
  cf_proxy="$(go_live_value GO_LIVE_CLOUDFLARE_PROXY_CONFIRMED 2>/dev/null || true)"
  cf_strict="$(go_live_value GO_LIVE_CLOUDFLARE_FULL_STRICT_CONFIRMED 2>/dev/null || true)"
  cf_origin="$(go_live_value GO_LIVE_CLOUDFLARE_ORIGIN_CERT_CONFIRMED 2>/dev/null || true)"
  notes="$(go_live_value GO_LIVE_NOTES 2>/dev/null || true)"
  if [[ -n "$site" && "$site" != "$SITE_NAME" ]]; then
    printf 'WARN|recorded for %s, current site is %s\n' "$site" "$SITE_NAME"
    return 0
  fi
  detail="recorded"
  [[ -n "$recorded_at" ]] && detail="${detail} ${recorded_at}"
  [[ -n "$snapshot_name" ]] && detail="${detail}; snapshot ${snapshot_name}"
  case "${firewall,,}" in true|yes|y|1|ok|confirmed) detail="${detail}; cloud firewall confirmed" ;; *) detail="${detail}; cloud firewall not confirmed" ;; esac
  case "${cf_proxy,,}" in true|yes|y|1|ok|confirmed) detail="${detail}; Cloudflare proxied" ;; *) detail="${detail}; Cloudflare proxy not confirmed" ;; esac
  case "${cf_strict,,}" in true|yes|y|1|ok|confirmed) detail="${detail}; Full strict confirmed" ;; *) detail="${detail}; Full strict not confirmed" ;; esac
  case "${cf_origin,,}" in true|yes|y|1|ok|confirmed) detail="${detail}; origin cert confirmed" ;; esac
  if go_live_recorded_ok; then
    printf 'OK|%s\n' "$detail"
  else
    printf 'WARN|%s\n' "$detail"
  fi
}

go_live_status_line() {
  local pair state detail
  pair="$(go_live_summary_pair)"
  state="${pair%%|*}"
  detail="${pair#*|}"
  status_line "Go-live validation" "$state" "$detail"
}

show_cloud_firewall_checklist() {
  ui_box_start "Cloud Firewall Checklist"
  echo "Confirm these rules in the cloud provider firewall, outside the VM."
  echo
  status_line "SSH 22" "INFO" "allow only from admin IP where possible"
  status_line "HTTP 80" "INFO" "allow from the Internet"
  status_line "HTTPS 443" "INFO" "allow from the Internet"
  status_line "ERPNext dev 8000" "INFO" "blocked externally"
  status_line "Socket.io 9000" "INFO" "blocked externally"
  status_line "Redis 11000/13000" "INFO" "blocked externally"
  status_line "MariaDB 3306" "INFO" "blocked externally"
  echo
  echo "After confirming the cloud firewall, record it with:"
  echo "  sudo erpnext-dev go-live-record"
  ui_next "$(toolkit_cmd go-live-record)" "$(toolkit_cmd go-live-status)" "$(toolkit_cmd production-checklist)"
  ui_box_end
}

show_cloudflare_checklist() {
  ui_box_start "Cloudflare Checklist"
  echo "Confirm these settings in Cloudflare for the production hostname."
  echo
  status_line "Hostname" "INFO" "$SITE_NAME"
  status_line "DNS proxy" "INFO" "proxied / orange-cloud"
  status_line "SSL/TLS mode" "INFO" "Full (strict)"
  status_line "Origin certificate" "INFO" "Cloudflare Origin CA certificate installed on Nginx"
  status_line "Direct dev ports" "INFO" "8000/9000 not publicly exposed"
  echo
  echo "After confirming Cloudflare, record it with:"
  echo "  sudo erpnext-dev go-live-record"
  ui_next "$(toolkit_cmd go-live-record)" "$(toolkit_cmd go-live-status)" "$(toolkit_cmd production-checklist)"
  ui_box_end
}

show_go_live_status() {
  require_sudo
  ui_box_start "Go-Live Validation Status"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Record file" "$($SUDO test -f "$GO_LIVE_RECORD_FILE" && echo OK || echo WARN)" "$GO_LIVE_RECORD_FILE"
  go_live_status_line || true
  if $SUDO test -f "$GO_LIVE_RECORD_FILE"; then
    echo
    echo "Recorded metadata:"
    $SUDO sed -E 's/(PASSWORD|TOKEN|SECRET|KEY)=.*/\1=[REDACTED]/' "$GO_LIVE_RECORD_FILE" | sed 's/^/  /'
  else
    echo
    echo "No go-live validation record exists yet on this VM."
    echo "After confirming snapshot, cloud firewall, and Cloudflare settings, run:"
    echo "  sudo erpnext-dev go-live-record"
  fi
  echo
  echo "This records external platform checks that the toolkit cannot fully verify from inside the VM."
  ui_next "$(toolkit_cmd go-live-record)" "$(toolkit_cmd cloud-firewall-checklist)" "$(toolkit_cmd cloudflare-checklist)"
  ui_box_end
}

record_go_live_validation() {
  require_sudo
  local snapshot_name snapshot_confirmed firewall_confirmed cf_proxy cf_strict cf_origin notes recorded_at config_dir
  local answer
  snapshot_name="${GO_LIVE_SNAPSHOT_NAME:-erp-flowmaya-v${SCRIPT_VERSION}-final-validated-$(date +%Y%m%d)}"
  snapshot_confirmed="${GO_LIVE_SNAPSHOT_CONFIRMED:-false}"
  firewall_confirmed="${GO_LIVE_CLOUD_FIREWALL_CONFIRMED:-false}"
  cf_proxy="${GO_LIVE_CLOUDFLARE_PROXY_CONFIRMED:-false}"
  cf_strict="${GO_LIVE_CLOUDFLARE_FULL_STRICT_CONFIRMED:-false}"
  cf_origin="${GO_LIVE_CLOUDFLARE_ORIGIN_CERT_CONFIRMED:-true}"
  notes="${GO_LIVE_NOTES:-snapshot-firewall-cloudflare-confirmed}"

  ui_box_start "Record Go-Live Validation"
  echo "Run this on the production ERPNext VM after confirming the external cloud controls."
  echo "This records snapshot, cloud firewall, and Cloudflare status for production-checklist, final QA, and support bundles."
  echo
  status_line "Record file" "INFO" "$GO_LIVE_RECORD_FILE"
  status_line "Current site" "INFO" "$SITE_NAME"
  echo
  echo "Use cloud-firewall-checklist and cloudflare-checklist if you want the exact checklist before recording."
  echo

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Snapshot name [${snapshot_name}]: " answer
    snapshot_name="${answer:-$snapshot_name}"
    read -r -p "Snapshot created/verified? [y/N]: " answer
    case "$answer" in y|Y|yes|YES) snapshot_confirmed="true" ;; *) snapshot_confirmed="false" ;; esac
    read -r -p "Cloud firewall confirmed? 22 admin IP, 80/443 open, 8000/9000 blocked [y/N]: " answer
    case "$answer" in y|Y|yes|YES) firewall_confirmed="true" ;; *) firewall_confirmed="false" ;; esac
    read -r -p "Cloudflare DNS proxied/orange-cloud confirmed? [y/N]: " answer
    case "$answer" in y|Y|yes|YES) cf_proxy="true" ;; *) cf_proxy="false" ;; esac
    read -r -p "Cloudflare SSL/TLS Full (strict) confirmed? [y/N]: " answer
    case "$answer" in y|Y|yes|YES) cf_strict="true" ;; *) cf_strict="false" ;; esac
    read -r -p "Cloudflare Origin CA certificate active on Nginx? [Y/n]: " answer
    case "$answer" in n|N|no|NO) cf_origin="false" ;; *) cf_origin="true" ;; esac
    read -r -p "Notes [${notes}]: " answer
    notes="${answer:-$notes}"
  fi

  snapshot_name="$(sanitize_restore_rehearsal_value "$snapshot_name")"
  notes="$(sanitize_restore_rehearsal_value "$notes")"
  recorded_at="$(date -Is 2>/dev/null || date)"

  local status="OK"
  for v in "$snapshot_confirmed" "$firewall_confirmed" "$cf_proxy" "$cf_strict"; do
    case "${v,,}" in true|yes|y|1|ok|confirmed) : ;; *) status="WARN" ;; esac
  done

  config_dir="$(dirname "$GO_LIVE_RECORD_FILE")"
  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$GO_LIVE_RECORD_FILE" >/dev/null <<EOF_GO_LIVE
GO_LIVE_STATUS=${status}
GO_LIVE_RECORDED_AT=${recorded_at}
GO_LIVE_SITE=${SITE_NAME}
GO_LIVE_SNAPSHOT_CONFIRMED=${snapshot_confirmed}
GO_LIVE_SNAPSHOT_NAME=${snapshot_name}
GO_LIVE_CLOUD_FIREWALL_CONFIRMED=${firewall_confirmed}
GO_LIVE_CLOUDFLARE_PROXY_CONFIRMED=${cf_proxy}
GO_LIVE_CLOUDFLARE_FULL_STRICT_CONFIRMED=${cf_strict}
GO_LIVE_CLOUDFLARE_ORIGIN_CERT_CONFIRMED=${cf_origin}
GO_LIVE_NOTES=${notes}
GO_LIVE_RECORDED_BY_TOOLKIT_VERSION=${SCRIPT_VERSION}
EOF_GO_LIVE
  $SUDO chown root:root "$GO_LIVE_RECORD_FILE" || true
  $SUDO chmod 600 "$GO_LIVE_RECORD_FILE" || true
  status_line "Go-live record" "$status" "saved"
  go_live_status_line || true
  ui_next "$(toolkit_cmd go-live-status)" "$(toolkit_cmd production-checklist)" "$(toolkit_cmd final-qa)"
  ui_box_end
}

show_production_checklist() {
  require_sudo
  ui_box_start "Production Checklist"
  local install_quick runtime_quick
  status_line "Site" "INFO" "$SITE_NAME"
  install_quick="$(production_quick_install_state)"
  runtime_quick="$(runtime_state 2>/dev/null || echo Stopped)"
  if [[ "$install_quick" == "Installed" ]]; then
    status_line "Install" "OK" "$install_quick"
  else
    status_line "Install" "WARN" "$install_quick"
  fi
  if [[ "$runtime_quick" == Running* ]]; then
    status_line "Runtime" "OK" "$runtime_quick"
  else
    status_line "Runtime" "WARN" "$runtime_quick"
  fi
  if production_ssl_ok_detail >/dev/null 2>&1; then
    status_line "HTTPS" "OK" "$(production_ssl_ok_detail)"
  else
    status_line "HTTPS" "WARN" "not confirmed"
  fi
  if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -qi '^Status: active'; then
    status_line "UFW" "OK" "active"
  else
    status_line "UFW" "WARN" "not active"
  fi
  if command -v fail2ban-client >/dev/null 2>&1 && $SUDO fail2ban-client status sshd >/dev/null 2>&1; then
    status_line "Fail2Ban" "OK" "sshd jail enabled"
  else
    status_line "Fail2Ban" "WARN" "sshd jail not confirmed"
  fi
  local bcount off_pair_for_local off_state_for_local
  bcount="$(production_backup_count)"
  off_pair_for_local="$(off_vm_backup_summary_pair)"
  off_state_for_local="${off_pair_for_local%%|*}"
  if [[ "$bcount" =~ ^[0-9]+$ && "$bcount" -gt 0 ]]; then
    if [[ "$off_state_for_local" == "OK" ]]; then
      status_line "Local backups" "OK" "${bcount} backup file(s); off-VM copy verified"
    else
      status_line "Local backups" "OK" "${bcount} backup file(s); off-VM copy still needs validation"
    fi
  else
    status_line "Local backups" "WARN" "no local backup files detected"
  fi
  if backup_schedule_timer_active; then
    status_line "Scheduled backups" "OK" "local timer active"
  else
    status_line "Scheduled backups" "INFO" "not configured; optional but recommended"
  fi
  local retention_candidates
  retention_candidates="$(backup_retention_candidate_sets 2>/dev/null | wc -l | awk '{print $1+0}')"
  status_line "Retention candidates" "$([[ "$retention_candidates" -gt 0 ]] && echo WARN || echo OK)" "${retention_candidates} old backup set(s)"
  local off_pair off_state off_detail
  off_pair="$(off_vm_backup_summary_pair)"
  off_state="${off_pair%%|*}"
  off_detail="${off_pair#*|}"
  status_line "Off-VM backup" "$off_state" "$off_detail"
  local rehearsal_pair rehearsal_state rehearsal_detail
  rehearsal_pair="$(restore_rehearsal_summary_pair)"
  rehearsal_state="${rehearsal_pair%%|*}"
  rehearsal_detail="${rehearsal_pair#*|}"
  status_line "Restore rehearsal" "$rehearsal_state" "$rehearsal_detail"
  if health_check_timer_active; then
    local health_pair health_state health_detail
    health_pair="$(health_check_summary_pair)"
    health_state="${health_pair%%|*}"
    health_detail="${health_pair#*|}"
    status_line "Health timer" "OK" "active"
    status_line "Health check" "$health_state" "$health_detail"
  else
    status_line "Health timer" "INFO" "not configured; optional"
  fi
  local go_pair go_state go_detail
  go_pair="$(go_live_summary_pair)"
  go_state="${go_pair%%|*}"
  go_detail="${go_pair#*|}"
  status_line "Go-live validation" "$go_state" "$go_detail"
  if [[ "$go_state" != "OK" ]]; then
    status_line "Snapshot" "INFO" "take/verify cloud snapshot before go-live"
  fi
  echo
  echo "Remaining production decisions:"
  if [[ "$off_state" != "OK" ]]; then
    echo "  - Configure and run off-VM backup, then rehearse restore on a disposable VM."
  elif [[ "$rehearsal_state" != "OK" ]]; then
    echo "  - Rehearse restore from the off-VM backup on a disposable VM and record it."
  else
    echo "  - Restore rehearsal recorded; repeat after major upgrade, migration, or backup-policy change."
  fi
  echo "  - Confirm scheduled local backups and retention policy."
  if health_check_timer_active; then
    echo "  - Health timer active; review health-check-status after major changes."
  else
    echo "  - Configure health timer if ongoing monitoring is required."
  fi
  if [[ "$go_state" == "OK" ]]; then
    echo "  - Go-live validation recorded; repeat after snapshot, firewall, DNS, or SSL changes."
  else
    echo "  - Confirm cloud firewall: 22 admin IP, 80/443 allowed, 8000/9000 blocked."
    echo "  - Confirm Cloudflare SSL mode and DNS proxy state."
    echo "  - Create named cloud snapshot after final validation."
    echo "  - Record external go-live validation with go-live-record."
  fi
  ui_next "$(toolkit_cmd backup-status)" "$(toolkit_cmd off-vm-backup-status)" "$(toolkit_cmd go-live-status)"
  ui_box_end
}


show_release_readiness() {
  require_sudo

  local syntax_status syntax_detail installed runtime ssl_pair ssl_status ssl_detail
  local ufw_status fail2ban_status latest_lines completeness release_state rehearsal_pair rehearsal_state rehearsal_detail go_pair go_state go_detail

  if bash -n "$0" >/dev/null 2>&1; then
    syntax_status="OK"; syntax_detail="bash syntax valid"
  else
    syntax_status="FAIL"; syntax_detail="bash syntax check failed"
  fi

  installed="$(install_state 2>/dev/null || echo "Unknown")"
  runtime="$(runtime_state 2>/dev/null || echo "Unknown")"
  ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo "WARN|not confirmed")"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"

  if ufw_is_active; then
    ufw_status="OK|active"
  else
    ufw_status="WARN|not active"
  fi

  if command -v fail2ban-client >/dev/null 2>&1 && $SUDO fail2ban-client status sshd >/dev/null 2>&1; then
    fail2ban_status="OK|sshd jail enabled"
  else
    fail2ban_status="WARN|sshd jail not confirmed"
  fi

  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  if [[ -n "$latest_lines" ]]; then
    completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
  else
    completeness="none"
  fi

  release_state="OK"
  [[ "$syntax_status" == "OK" ]] || release_state="WARN"
  [[ "$installed" == "Installed" ]] || release_state="WARN"
  [[ "$runtime" == Running* ]] || release_state="WARN"
  [[ "$ssl_status" == "OK" ]] || release_state="WARN"
  [[ "${ufw_status%%|*}" == "OK" ]] || release_state="WARN"
  [[ "${fail2ban_status%%|*}" == "OK" ]] || release_state="WARN"
  [[ "$completeness" == "complete" ]] || release_state="WARN"

  ui_box_start "Release Readiness / Final QA"
  status_line "Script version" "INFO" "${SCRIPT_VERSION}"
  status_line "Syntax" "$syntax_status" "$syntax_detail"
  status_line "Site" "INFO" "${SITE_NAME} (${SITE_NAME_SOURCE})"
  status_line "Deployment mode" "INFO" "${DEPLOYMENT_MODE:-unknown}"
  status_line "Install" "$([[ "$installed" == "Installed" ]] && echo OK || echo WARN)" "$installed"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo WARN)" "$runtime"
  status_line "HTTPS" "$ssl_status" "$ssl_detail"
  status_line "UFW" "${ufw_status%%|*}" "${ufw_status#*|}"
  status_line "Fail2Ban" "${fail2ban_status%%|*}" "${fail2ban_status#*|}"
  status_line "Latest backup" "$([[ "$completeness" == "complete" ]] && echo OK || echo WARN)" "${completeness:-none}"
  rehearsal_pair="$(restore_rehearsal_summary_pair)"
  rehearsal_state="${rehearsal_pair%%|*}"
  rehearsal_detail="${rehearsal_pair#*|}"
  status_line "Restore rehearsal" "$rehearsal_state" "$rehearsal_detail"
  if [[ "${DEPLOYMENT_MODE:-development}" != "development" && "$rehearsal_state" != "OK" ]]; then
    release_state="WARN"
  fi
  if health_check_timer_active; then
    local health_pair health_state health_detail
    health_pair="$(health_check_summary_pair)"
    health_state="${health_pair%%|*}"
    health_detail="${health_pair#*|}"
    status_line "Health monitoring" "OK" "timer active; ${health_detail}"
  else
    status_line "Health monitoring" "INFO" "timer not configured; optional"
  fi
  go_pair="$(go_live_summary_pair)"
  go_state="${go_pair%%|*}"
  go_detail="${go_pair#*|}"
  status_line "Go-live validation" "$go_state" "$go_detail"
  if [[ "${DEPLOYMENT_MODE:-development}" != "development" && "$go_state" != "OK" ]]; then
    release_state="WARN"
  fi
  status_line "Release state" "$release_state" "$([[ "$release_state" == OK ]] && echo "ready for production use" || echo "review WARN rows before production use")"
  ui_box_end

  ui_next "$(toolkit_cmd production-checklist)" "$(toolkit_cmd support-bundle)"
}

show_release_notes_guide() {
  ui_box_start "v${SCRIPT_VERSION} Release Notes Draft"
  echo "Release focus: unified Production Operations dashboard and operator experience."
  echo
  echo "Changed in this release:"
  echo "  - Added health-monitoring-wizard and health-check-journal."
  echo "  - Health checks now write /etc/erpnext-dev/health-check.state for status tracking."
  echo "  - Health timer setup now prompts for schedule/randomized delay and can run a check immediately."
  echo "  - Production checklist and final QA now surface health monitoring status."
  echo
  echo "Validation focus:"
  echo "  - Run the new README production command on a fresh disposable VPS with a real subdomain."
  echo "  - Confirm the guided path avoids manual menu-number hopping."
  echo "  - Confirm the manual Public VM menu still works for individual operations."
  echo
  echo "Current readiness rating:"
  echo "  - Local VM workflow: 9.5/10, passed"
  echo "  - Production VPS workflow: production-candidate; continue real VPS validation before client production use"
  echo
  echo "Known production responsibility:"
  echo "  - DNS records and provider firewall rules are still external provider actions."
  echo "  - Copy backups off the VM and rehearse restore on a disposable VM."
  echo "  - Keep provider snapshots named and current."
  ui_box_end
  ui_next "$(toolkit_cmd release-readiness)" "$(toolkit_cmd production-checklist)"
}

final_qa_wizard() {
  require_sudo

  while true; do
    ui_box_start "Final QA / Release Readiness"
    echo "Compact checks before production handoff or release validation."
    echo
    echo "1) Release readiness summary"
    echo "2) Command audit"
    echo "3) Production checklist"
    echo "4) Backup verify"
    echo "5) Release notes draft"
    echo "6) Create support bundle"
    echo "7) Restore rehearsal status"
    echo "8) Health monitoring status"
    echo "9) Go-live validation status"
    menu_footer
    local choice=""
    menu_read_choice choice

    case "$choice" in
      1) show_release_readiness; pause_after_screen "Press Enter to return to Final QA..." ;;
      2) show_command_audit; pause_after_screen "Press Enter to return to Final QA..." ;;
      3) show_production_checklist; pause_after_screen "Press Enter to return to Final QA..." ;;
      4) verify_latest_backup_set; pause_after_screen "Press Enter to return to Final QA..." ;;
      5) show_release_notes_guide; pause_after_screen "Press Enter to return to Final QA..." ;;
      6) create_support_bundle; pause_after_screen "Press Enter to return to Final QA..." ;;
      7) show_restore_rehearsal_status; pause_after_screen "Press Enter to return to Final QA..." ;;
      8) show_health_check_status; pause_after_screen "Press Enter to return to Final QA..." ;;
      9) show_go_live_status; pause_after_screen "Press Enter to return to Final QA..." ;;
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
