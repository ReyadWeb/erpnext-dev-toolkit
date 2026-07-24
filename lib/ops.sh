# shellcheck shell=bash
# Production operations dashboard menus and wizard for erpnext-dev.sh.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_OPS_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_OPS_LOADED=1

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
    ui_submenu_header "Services and Recovery" "Production Operations"
    print_two_column_menu \
      "1) Service status" \
      "2) Start ERPNext service" \
      "3) Stop ERPNext service" \
      "4) Restart ERPNext service" \
      "5) Wait for ERPNext readiness" \
      "6) Verify frontend assets" \
      "7) Repair frontend assets" \
      "8) Service logs" \
      "9) Follow service logs" \
      "10) Service recovery plan"
    menu_footer
    local services_choice=""
    menu_read_choice services_choice
    case "$services_choice" in
      1)
        show_erpnext_service_status
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      2)
        start_erpnext_service
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      3)
        stop_erpnext_service
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      4)
        restart_erpnext_service
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      5)
        wait_for_erpnext_ready
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      6)
        verify_frontend_assets
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      7)
        repair_frontend_assets
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      8)
        show_erpnext_service_logs
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      9)
        follow_erpnext_service_logs
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      10)
        show_service_recovery_plan
        pause_after_screen "Press Enter to return to Services and Recovery..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_backups_menu() {
  require_sudo
  while true; do
    ui_submenu_header "Local Backups" "Production Operations"
    print_two_column_menu \
      "1) Create database + files backup" \
      "2) Backup status" \
      "3) Verify latest backup" \
      "4) Scheduled backup plan" \
      "5) Configure scheduled backups" \
      "6) Scheduled backup status" \
      "7) Retention plan" \
      "8) Retention status" \
      "9) Cleanup old backups dry run" \
      "10) Cleanup old backups" \
      "11) Full backup/maintenance menu"
    menu_footer
    local local_backup_choice=""
    menu_read_choice local_backup_choice
    case "$local_backup_choice" in
      1)
        create_site_backup true
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      2)
        show_backup_status
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      3)
        verify_latest_backup_set
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      4)
        show_backup_schedule_plan
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      5)
        configure_backup_schedule
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      6)
        show_backup_schedule_status
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      7)
        show_backup_retention_plan
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      8)
        show_backup_retention_status
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      9)
        cleanup_old_backups dry-run
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      10)
        cleanup_old_backups prompt
        pause_after_screen "Press Enter to return to Local Backups..."
        ;;
      11) run_backup_maintenance_menu ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_restore_menu() {
  require_sudo
  while true; do
    ui_submenu_header "Restore Readiness and Rehearsal" "Production Operations"
    print_two_column_menu \
      "1) Restore rehearsal status" \
      "2) Restore rehearsal guide" \
      "3) Restore rehearsal wizard" \
      "4) Restore preflight" \
      "5) Record completed restore rehearsal" \
      "6) Restore rehearsal report" \
      "7) List local backups" \
      "8) Restore database only" \
      "9) Restore database + files"
    menu_footer
    local restore_choice=""
    menu_read_choice restore_choice
    case "$restore_choice" in
      1)
        show_restore_rehearsal_status
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      2)
        show_restore_rehearsal_guide
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      3)
        restore_rehearsal_wizard
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      4)
        show_restore_preflight
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      5)
        record_restore_rehearsal
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      6)
        show_restore_rehearsal_report
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      7)
        list_site_backups
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      8)
        restore_site_database
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      9)
        restore_site_full
        pause_after_screen "Press Enter to return to Restore Readiness..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_security_menu() {
  require_sudo
  while true; do
    ui_submenu_header "Security and Firewall" "Production Operations"
    print_two_column_menu \
      "1) Firewall hardening status" \
      "2) VM firewall status" \
      "3) Security hardening wizard" \
      "4) Configure VM firewall" \
      "5) Production firewall profile" \
      "6) Configure Fail2Ban" \
      "7) Fail2Ban status" \
      "8) Security audit" \
      "9) Cloud firewall checklist"
    menu_footer
    local security_choice=""
    menu_read_choice security_choice
    case "$security_choice" in
      1)
        show_firewall_hardening_status
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      2)
        show_vm_firewall_status
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      3)
        security_hardening_wizard
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      4)
        configure_vm_firewall
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      5)
        configure_production_vm_firewall
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      6)
        configure_fail2ban
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      7)
        show_fail2ban_status
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      8)
        run_security_audit
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      9)
        show_cloud_firewall_checklist
        pause_after_screen "Press Enter to return to Security and Firewall..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_https_menu() {
  require_sudo
  while true; do
    ui_submenu_header "HTTPS and Certificates" "Production Operations"
    print_two_column_menu \
      "1) Production SSL status" \
      "2) SSL mode status" \
      "3) Production HTTPS menu" \
      "4) Cloudflare Origin CA status" \
      "5) Cloudflare checklist" \
      "6) SSL compatibility guide"
    menu_footer
    local https_choice=""
    menu_read_choice https_choice
    case "$https_choice" in
      1)
        show_production_ssl_status
        pause_after_screen "Press Enter to return to HTTPS and Certificates..."
        ;;
      2)
        show_ssl_mode_status
        pause_after_screen "Press Enter to return to HTTPS and Certificates..."
        ;;
      3)
        show_production_ssl_menu
        pause_after_screen "Press Enter to return to HTTPS and Certificates..."
        ;;
      4)
        show_cloudflare_origin_ssl_status
        pause_after_screen "Press Enter to return to HTTPS and Certificates..."
        ;;
      5)
        show_cloudflare_checklist
        pause_after_screen "Press Enter to return to HTTPS and Certificates..."
        ;;
      6)
        show_ssl_mode_guide
        pause_after_screen "Press Enter to return to HTTPS and Certificates..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_support_menu() {
  require_sudo
  while true; do
    ui_submenu_header "Support and Diagnostics" "Production Operations"
    print_two_column_menu \
      "1) Doctor" \
      "2) Doctor JSON" \
      "3) Production checklist" \
      "4) Final QA" \
      "5) Command audit" \
      "6) Create support bundle" \
      "7) Show latest support bundle contents" \
      "8) Storage status" \
      "9) Port status" \
      "10) Verify toolkit integrity" \
      "11) Audit latest support bundle"
    menu_footer
    local support_choice=""
    menu_read_choice support_choice
    case "$support_choice" in
      1)
        run_doctor_plain
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      2)
        run_doctor_json
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      3)
        show_production_checklist
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      4)
        final_qa_wizard
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      5)
        show_command_audit
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      6)
        create_support_bundle
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      7)
        show_latest_support_bundle_contents
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      8)
        show_storage_status
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      9)
        support_bundle_port_status
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      10)
        verify_toolkit_integrity
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      11)
        support_bundle_audit_archive
        pause_after_screen "Press Enter to return to Support and Diagnostics..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}
production_ops_menu_render_option() {
  local key="$1"
  local label="$2"

  ui_row_add_colored cyan "[$key]"
  ui_row_add " $label"
}

production_ops_menu_render_pair() {
  local width="$1"
  local left_key="$2"
  local left_label="$3"
  local right_key="${4:-}"
  local right_label="${5:-}"
  local second_column

  second_column=$((width / 2))

  ui_row_begin
  production_ops_menu_render_option "$left_key" "$left_label"

  if [[ -n "$right_key" ]]; then
    ui_row_pad_to "$second_column"
    production_ops_menu_render_option "$right_key" "$right_label"
  fi

  ui_row_end
}

production_ops_menu_footer() {
  echo
  ui_text cyan "B."
  printf ' Back'
  printf '                        '
  ui_text orange "Q."
  printf ' Quit
'
}

production_ops_summary_state() {
  local summary="$1"
  local label="$2"
  local line stripped rest state

  while IFS= read -r line; do
    stripped="${line#"${line%%[![:space:]]*}"}"

    if [[ "$stripped" == "$label"* ]]; then
      rest="${stripped#"$label"}"
      IFS=$' \t' read -r state _ <<<"$rest"
      printf '%s' "${state:-INFO}"
      return 0
    fi
  done <<<"$summary"

  printf 'INFO'
}

production_ops_indicator_color() {
  case "${1:-INFO}" in
    OK) printf 'green' ;;
    WARN) printf 'orange' ;;
    FAIL | ERROR | CRITICAL) printf 'red' ;;
    *) printf 'muted' ;;
  esac
}

production_ops_indicator_symbol() {
  local color="${1:-muted}"

  if [[ -n "${NO_COLOR:-}" || "${FORCE_NO_COLOR:-0}" == "1" ]]; then
    case "$color" in
      green) printf '+' ;;
      orange) printf '!' ;;
      red) printf 'x' ;;
      *) printf '-' ;;
    esac
    return 0
  fi

  if ((${UI_UNICODE:-0} == 1)); then
    if [[ "$color" == "muted" ]]; then
      printf '○'
    else
      printf '●'
    fi
  else
    case "$color" in
      green) printf '+' ;;
      orange) printf '!' ;;
      red) printf 'x' ;;
      *) printf '-' ;;
    esac
  fi
}

production_ops_add_status_indicator() {
  local label="$1"
  local state="$2"
  local color symbol

  color="$(production_ops_indicator_color "$state")"
  symbol="$(production_ops_indicator_symbol "$color")"

  ui_row_add_colored cyan "$label"
  ui_row_add " "
  ui_row_add_colored "$color" "$symbol"
}

render_production_ops_status_strip() {
  local width summary
  local runtime install https security backup
  local offvm restore health golive

  width="$(ui_panel_width)"

  # Reuse the canonical production summary as the status source.
  # NO_COLOR keeps the captured data clean for parsing.
  summary="$(NO_COLOR=1 production_ops_summary 2>/dev/null || true)"

  runtime="$(production_ops_summary_state "$summary" "Runtime")"
  install="$(production_ops_summary_state "$summary" "Install")"
  https="$(production_ops_summary_state "$summary" "HTTPS")"
  security="$(production_ops_summary_state "$summary" "Security")"
  backup="$(production_ops_summary_state "$summary" "Local backup")"
  offvm="$(production_ops_summary_state "$summary" "Off-VM backup")"
  restore="$(production_ops_summary_state "$summary" "Restore rehearsal")"
  health="$(production_ops_summary_state "$summary" "Health monitoring")"
  golive="$(production_ops_summary_state "$summary" "Go-live validation")"

  ui_box_titled_top "Current state" "$width"

  if ((width >= 100)); then
    ui_row_begin
    production_ops_add_status_indicator "Runtime" "$runtime"
    ui_row_add "   "
    production_ops_add_status_indicator "Install" "$install"
    ui_row_add "   "
    production_ops_add_status_indicator "HTTPS" "$https"
    ui_row_add "   "
    production_ops_add_status_indicator "Security" "$security"
    ui_row_add "   "
    production_ops_add_status_indicator "Backup" "$backup"
    ui_row_end

    ui_row_begin
    production_ops_add_status_indicator "Off-VM" "$offvm"
    ui_row_add "   "
    production_ops_add_status_indicator "Restore" "$restore"
    ui_row_add "   "
    production_ops_add_status_indicator "Health" "$health"
    ui_row_add "   "
    production_ops_add_status_indicator "Go-live" "$golive"
    ui_row_end
  else
    ui_row_begin
    production_ops_add_status_indicator "Runtime" "$runtime"
    ui_row_add "   "
    production_ops_add_status_indicator "Install" "$install"
    ui_row_add "   "
    production_ops_add_status_indicator "HTTPS" "$https"
    ui_row_end

    ui_row_begin
    production_ops_add_status_indicator "Security" "$security"
    ui_row_add "   "
    production_ops_add_status_indicator "Backup" "$backup"
    ui_row_add "   "
    production_ops_add_status_indicator "Off-VM" "$offvm"
    ui_row_end

    ui_row_begin
    production_ops_add_status_indicator "Restore" "$restore"
    ui_row_add "   "
    production_ops_add_status_indicator "Health" "$health"
    ui_row_add "   "
    production_ops_add_status_indicator "Go-live" "$golive"
    ui_row_end
  fi

  ui_box_line bot "$width"
}

production_ops_status_page() {
  require_sudo

  ui_submenu_header "Production Status" \
    "Detailed production state and the reason behind each status."

  production_ops_summary

  echo
  ui_text muted "Dashboard provides deeper host, application, protection, and healing diagnostics."
  printf '\n'
}

render_production_ops_menu_options() {
  local width
  width="$(ui_panel_width)"

  ui_box_line top "$width"

  if ((width >= 80)); then
    production_ops_menu_render_pair "$width" "1" "Dashboard" "5" "Security"
    production_ops_menu_render_pair "$width" "2" "Services" "6" "HTTPS"
    production_ops_menu_render_pair "$width" "3" "Backups" "7" "Monitoring"
    production_ops_menu_render_pair "$width" "4" "Restore" "8" "Diagnostics"

    ui_box_line mid "$width"

    production_ops_menu_render_pair "$width" "S" "Status" "R" "Readiness"
    production_ops_menu_render_pair "$width" "G" "Go-live" "F" "Final QA"
  else
    production_ops_menu_render_pair "$width" "1" "Dashboard"
    production_ops_menu_render_pair "$width" "2" "Services"
    production_ops_menu_render_pair "$width" "3" "Backups"
    production_ops_menu_render_pair "$width" "4" "Restore"
    production_ops_menu_render_pair "$width" "5" "Security"
    production_ops_menu_render_pair "$width" "6" "HTTPS"
    production_ops_menu_render_pair "$width" "7" "Monitoring"
    production_ops_menu_render_pair "$width" "8" "Diagnostics"

    ui_box_line mid "$width"

    production_ops_menu_render_pair "$width" "S" "Status"
    production_ops_menu_render_pair "$width" "R" "Readiness"
    production_ops_menu_render_pair "$width" "G" "Go-live"
    production_ops_menu_render_pair "$width" "F" "Final QA"
  fi

  ui_box_line bot "$width"
}

production_ops_backup_hub_menu() {
  require_sudo

  while true; do
    ui_submenu_header "Backups" \
      "Local and off-VM production backup workflows."

    local width
    width="$(ui_panel_width)"

    ui_box_line top "$width"

    if ((width >= 80)); then
      production_ops_menu_render_pair \
        "$width" \
        "1" "Local backups" \
        "2" "Off-VM backups"
    else
      production_ops_menu_render_pair "$width" "1" "Local backups"
      production_ops_menu_render_pair "$width" "2" "Off-VM backups"
    fi

    ui_box_line bot "$width"

    production_ops_menu_footer

    local choice=""
    menu_read_choice choice

    case "$choice" in
      1)
        production_ops_backups_menu
        ;;
      2)
        off_vm_backup_wizard
        pause_after_screen "Press Enter to return to Backups..."
        ;;
      b | B | "")
        return 0
        ;;
      q | Q)
        exit 0
        ;;
      *)
        warn "Invalid option"
        ;;
    esac
  done
}

production_ops_wizard() {
  require_sudo

  while true; do
    ui_submenu_header "Production" \
      "Monitor, protect, maintain, and validate the production environment."

    render_production_ops_status_strip
    echo

    render_production_ops_menu_options

    production_ops_menu_footer

    local ops_choice=""
    menu_read_choice ops_choice

    case "$ops_choice" in
      1)
        run_operations_dashboard
        pause_after_screen "Press Enter to return to Production..."
        ;;
      2)
        production_ops_services_menu
        ;;
      3)
        production_ops_backup_hub_menu
        ;;
      4)
        production_ops_restore_menu
        ;;
      5)
        production_ops_security_menu
        ;;
      6)
        production_ops_https_menu
        ;;
      7)
        PRODUCTION_OPS_CONTEXT=1 health_monitoring_wizard
        pause_after_screen "Press Enter to return to Production..."
        ;;
      8)
        production_ops_support_menu
        ;;
      s | S)
        production_ops_status_page
        pause_after_screen "Press Enter to return to Production..."
        ;;
      r | R)
        show_release_readiness
        pause_after_screen "Press Enter to return to Production..."
        ;;
      g | G)
        show_go_live_status
        pause_after_screen "Press Enter to return to Production..."
        ;;
      f | F)
        final_qa_wizard
        pause_after_screen "Press Enter to return to Production..."
        ;;
      b | B | "")
        return 0
        ;;
      q | Q)
        exit 0
        ;;
      *)
        warn "Invalid option"
        ;;
    esac
  done
}
