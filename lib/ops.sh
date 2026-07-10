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
    ui_box_start "$(production_ops_breadcrumb_title "Services and Recovery")"
    echo "1) Service status"
    echo "2) Start ERPNext service"
    echo "3) Stop ERPNext service"
    echo "4) Restart ERPNext service"
    echo "5) Wait for ERPNext readiness"
    echo "6) Service logs"
    echo "7) Follow service logs"
    echo "8) Service recovery plan"
    menu_footer
    local services_choice=""
    menu_read_choice services_choice
    case "$services_choice" in
      1) show_erpnext_service_status; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      2) start_erpnext_service; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      3) stop_erpnext_service; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      4) restart_erpnext_service; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      5) wait_for_erpnext_ready; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      6) show_erpnext_service_logs; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      7) follow_erpnext_service_logs ;;
      8) show_service_recovery_plan; pause_after_screen "Press Enter to return to Services and Recovery..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_backups_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Local Backups")"
    echo "1) Create database + files backup"
    echo "2) Backup status"
    echo "3) Verify latest backup"
    echo "4) Scheduled backup plan"
    echo "5) Configure scheduled backups"
    echo "6) Scheduled backup status"
    echo "7) Retention plan"
    echo "8) Retention status"
    echo "9) Cleanup old backups dry run"
    echo "10) Cleanup old backups"
    echo "11) Full backup/maintenance menu"
    menu_footer
    local local_backup_choice=""
    menu_read_choice local_backup_choice
    case "$local_backup_choice" in
      1) create_site_backup true; pause_after_screen "Press Enter to return to Local Backups..." ;;
      2) show_backup_status; pause_after_screen "Press Enter to return to Local Backups..." ;;
      3) verify_latest_backup_set; pause_after_screen "Press Enter to return to Local Backups..." ;;
      4) show_backup_schedule_plan; pause_after_screen "Press Enter to return to Local Backups..." ;;
      5) configure_backup_schedule; pause_after_screen "Press Enter to return to Local Backups..." ;;
      6) show_backup_schedule_status; pause_after_screen "Press Enter to return to Local Backups..." ;;
      7) show_backup_retention_plan; pause_after_screen "Press Enter to return to Local Backups..." ;;
      8) show_backup_retention_status; pause_after_screen "Press Enter to return to Local Backups..." ;;
      9) cleanup_old_backups dry-run; pause_after_screen "Press Enter to return to Local Backups..." ;;
      10) cleanup_old_backups prompt; pause_after_screen "Press Enter to return to Local Backups..." ;;
      11) run_backup_maintenance_menu ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_restore_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Restore Readiness and Rehearsal")"
    echo "1) Restore rehearsal status"
    echo "2) Restore rehearsal guide"
    echo "3) Restore rehearsal wizard"
    echo "4) Restore preflight"
    echo "5) Record completed restore rehearsal"
    echo "6) Restore rehearsal report"
    echo "7) List local backups"
    echo "8) Restore database only"
    echo "9) Restore database + files"
    menu_footer
    local restore_choice=""
    menu_read_choice restore_choice
    case "$restore_choice" in
      1) show_restore_rehearsal_status; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      2) show_restore_rehearsal_guide; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      3) restore_rehearsal_wizard; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      4) show_restore_preflight; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      5) record_restore_rehearsal; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      6) show_restore_rehearsal_report; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      7) list_site_backups; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      8) restore_site_database; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      9) restore_site_full; pause_after_screen "Press Enter to return to Restore Readiness..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_security_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Security and Firewall")"
    echo "1) Firewall hardening status"
    echo "2) VM firewall status"
    echo "3) Security hardening wizard"
    echo "4) Configure VM firewall"
    echo "5) Production firewall profile"
    echo "6) Configure Fail2Ban"
    echo "7) Fail2Ban status"
    echo "8) Security audit"
    echo "9) Cloud firewall checklist"
    menu_footer
    local security_choice=""
    menu_read_choice security_choice
    case "$security_choice" in
      1) show_firewall_hardening_status; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      2) show_vm_firewall_status; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      3) security_hardening_wizard; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      4) configure_vm_firewall; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      5) configure_production_vm_firewall; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      6) configure_fail2ban; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      7) show_fail2ban_status; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      8) run_security_audit; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      9) show_cloud_firewall_checklist; pause_after_screen "Press Enter to return to Security and Firewall..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_https_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "HTTPS and Certificates")"
    echo "1) Production SSL status"
    echo "2) SSL mode status"
    echo "3) Production HTTPS / SSL menu"
    echo "4) Cloudflare Origin CA status"
    echo "5) Cloudflare checklist"
    echo "6) SSL compatibility guide"
    menu_footer
    local https_choice=""
    menu_read_choice https_choice
    case "$https_choice" in
      1) show_production_ssl_status; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      2) show_ssl_mode_status; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      3) show_production_ssl_menu; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      4) show_cloudflare_origin_ssl_status; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      5) show_cloudflare_checklist; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      6) show_ssl_mode_guide; pause_after_screen "Press Enter to return to HTTPS and Certificates..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

production_ops_support_menu() {
  require_sudo
  while true; do
    ui_box_start "$(production_ops_breadcrumb_title "Support and Diagnostics")"
    echo "1) Doctor"
    echo "2) Doctor JSON"
    echo "3) Production checklist"
    echo "4) Final QA"
    echo "5) Command audit"
    echo "6) Create support bundle"
    echo "7) Show latest support bundle contents"
    echo "8) Storage status"
    echo "9) Port status"
    echo "10) Verify toolkit integrity"
    echo "11) Audit latest support bundle"
    menu_footer
    local support_choice=""
    menu_read_choice support_choice
    case "$support_choice" in
      1) run_doctor_plain; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      2) run_doctor_json; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      3) show_production_checklist; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      4) final_qa_wizard; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      5) show_command_audit; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      6) create_support_bundle; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      7) show_latest_support_bundle_contents; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      8) show_storage_status; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      9) support_bundle_port_status; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      10) verify_toolkit_integrity; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      11) support_bundle_audit_archive; pause_after_screen "Press Enter to return to Support and Diagnostics..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}
production_ops_wizard() {
  require_sudo
  while true; do
    ui_box_start "ERPNext Production Operations"
    status_line "Site" "INFO" "$SITE_NAME"
    status_line "Toolkit" "INFO" "v${SCRIPT_VERSION}"
    echo
    echo "Current state"
    production_ops_summary
    echo
    echo "1) System health and readiness"
    echo "2) Services and recovery"
    echo "3) Local backups"
    echo "4) Off-VM backups"
    echo "5) Restore readiness and rehearsal"
    echo "6) Health monitoring"
    echo "7) Security and firewall"
    echo "8) HTTPS and certificates"
    echo "9) Go-live validation"
    echo "10) Support and diagnostics"
    echo "11) Final QA"
    menu_footer quit-only
    local ops_choice=""
    menu_read_choice ops_choice
    case "$ops_choice" in
      1) show_release_readiness; pause_after_screen "Press Enter to return to Production Operations..." ;;
      2) production_ops_services_menu ;;
      3) production_ops_backups_menu ;;
      4) off_vm_backup_wizard; pause_after_screen "Press Enter to return to Production Operations..." ;;
      5) production_ops_restore_menu ;;
      6) PRODUCTION_OPS_CONTEXT=1 health_monitoring_wizard; pause_after_screen "Press Enter to return to Production Operations..." ;;
      7) production_ops_security_menu ;;
      8) production_ops_https_menu ;;
      9) show_go_live_status; pause_after_screen "Press Enter to return to Production Operations..." ;;
      10) production_ops_support_menu ;;
      11) final_qa_wizard; pause_after_screen "Press Enter to return to Production Operations..." ;;
      "") continue ;;
      b|B) return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}
