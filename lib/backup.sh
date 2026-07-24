# shellcheck shell=bash
# Local backup, off-VM backup, restore, and rehearsal helpers.
[[ -n "${_ERPNEXT_DEV_BACKUP_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_BACKUP_LOADED=1

# ============================================================
# Backup / Restore / Maintenance
# ============================================================

site_backup_dir() {
  local bench_dir
  bench_dir="$(active_bench_dir)"
  echo "${bench_dir}/sites/${SITE_NAME}/private/backups"
}

require_site_environment() {
  local bench_dir
  bench_dir="$(require_bench_dir)" || return 1

  if ! path_is_dir "${bench_dir}/sites/${SITE_NAME}"; then
    err "Site not found: ${SITE_NAME}"
    err "Expected: ${bench_dir}/sites/${SITE_NAME}"
    err "Run Recommended Setup first, or check SITE_NAME."
    return 1
  fi

  echo "$bench_dir"
}

show_latest_backups() {
  local bench_dir backup_rel
  bench_dir="$(active_bench_dir)"
  backup_rel="sites/${SITE_NAME}/private/backups"

  if ! path_is_dir "${bench_dir}/${backup_rel}"; then
    warn "Backup folder not found: ${bench_dir}/${backup_rel}"
    return 0
  fi

  echo
  echo "Latest backup files:"
  run_as_frappe "cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM  %p\\n' 2>/dev/null | sort -r | head -12" || true
}

create_site_backup() {
  require_sudo

  local include_files="${1:-false}"

  if deployment_engine_is_docker; then
    docker_backup "$include_files"
    return
  fi

  local bench_dir backup_cmd tmp_output rc
  bench_dir="$(require_site_environment)" || return 1

  # Backup uses bench, so repair the app registry first. A corrupted apps.txt can make
  # backup print a failure while still leaving partial files behind.
  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before backup."

  if [[ "$include_files" == "true" ]]; then
    log "Creating database + files backup for ${SITE_NAME}"
    backup_cmd="bench --site '${SITE_NAME}' backup --with-files"
  else
    log "Creating database backup for ${SITE_NAME}"
    backup_cmd="bench --site '${SITE_NAME}' backup"
  fi

  tmp_output="$(mktemp /tmp/erpnext-dev-backup.XXXXXX.log)" || return 1
  set +e
  run_as_frappe "cd '${bench_dir}' && ${backup_cmd}" 2>&1 | tee "$tmp_output"
  rc=${PIPESTATUS[0]}
  set -e

  if [[ "$rc" -ne 0 ]] || grep -Eqi 'Backup failed|Traceback|ModuleNotFoundError|Database or site_config.json may be corrupted' "$tmp_output"; then
    warn "Backup did not complete cleanly. Partial backup files may exist, but they should not be trusted."
    rm -f "$tmp_output"
    return 1
  fi

  rm -f "$tmp_output"
  ok "Backup completed"
  show_latest_backups
  if [[ "$include_files" == "true" ]]; then
    show_backup_result_summary || true
  fi
}

show_backup_result_summary() {
  local latest_lines prefix db_file public_file private_file config_file completeness
  latest_lines="$(backup_latest_set_paths || true)"
  [[ -n "$latest_lines" ]] || return 0
  prefix="$(printf '%s
' "$latest_lines" | sed -n '1p')"
  db_file="$(printf '%s
' "$latest_lines" | sed -n '2p')"
  public_file="$(printf '%s
' "$latest_lines" | sed -n '3p')"
  private_file="$(printf '%s
' "$latest_lines" | sed -n '4p')"
  config_file="$(printf '%s
' "$latest_lines" | sed -n '5p')"
  completeness="$(printf '%s
' "$latest_lines" | sed -n '6p')"

  ui_box_start "Backup Result Summary"
  status_line "Latest set" "$([[ "$completeness" == complete ]] && echo OK || echo WARN)" "${prefix} (${completeness})"
  status_line "Database" "$([[ -f "$db_file" ]] && echo OK || echo FAIL)" "$(basename "$db_file")"
  status_line "Public files" "$([[ -f "$public_file" ]] && echo OK || echo WARN)" "$(basename "$public_file")"
  status_line "Private files" "$([[ -f "$private_file" ]] && echo OK || echo WARN)" "$(basename "$private_file")"
  status_line "Site config" "$([[ -f "$config_file" ]] && echo OK || echo WARN)" "$(basename "$config_file")"
  ui_next "$(toolkit_cmd backup-verify)" "$(toolkit_cmd off-vm-backup-guide)"
  ui_box_end
}

print_backup_results() {
  local title="$1"
  local count_cmd="$2"
  local list_cmd="$3"
  local count output

  count="$(run_as_frappe "${count_cmd}" 2>/dev/null | tr -d '[:space:]' || true)"
  count="${count:-0}"

  echo "${title} (${count}):"
  output="$(run_as_frappe "${list_cmd}" 2>/dev/null || true)"
  if [[ -n "$output" ]]; then
    echo "$output"
  else
    echo "  none"
  fi
}

list_site_backups() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_list_backups
    return
  fi

  local bench_dir backup_rel backup_abs
  local db_count_cmd db_list_cmd public_count_cmd public_list_cmd private_count_cmd private_list_cmd
  bench_dir="$(require_site_environment)" || return 1
  backup_rel="sites/${SITE_NAME}/private/backups"
  backup_abs="${bench_dir}/${backup_rel}"

  echo
  echo "============================================================"
  echo "ERPNext Backups"
  echo "============================================================"
  echo "Site: ${SITE_NAME}"
  echo "Backup folder: ${backup_abs}"
  echo

  if ! path_is_dir "$backup_abs"; then
    warn "No backup folder found yet. Create a backup first."
    echo "============================================================"
    return 0
  fi

  db_count_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-database.sql.gz' -o -name '*.sql.gz' -o -name '*database*.sql.gz' \\) -print 2>/dev/null | wc -l"
  db_list_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-database.sql.gz' -o -name '*.sql.gz' -o -name '*database*.sql.gz' \\) -printf '  %TY-%Tm-%Td %TH:%TM  %f\\n' 2>/dev/null | sort -r | head -20"

  # Public and private file backups must be matched separately.
  # Frappe names public backups like '*-files.tar' and private backups like '*-private-files.tar'.
  # A broad '*files.tar' match incorrectly includes private backups, so explicitly exclude them here.
  public_count_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-files.tar' -o -name '*-files.tar.gz' \\) ! -name '*-private-files.tar' ! -name '*-private-files.tar.gz' -print 2>/dev/null | wc -l"
  public_list_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-files.tar' -o -name '*-files.tar.gz' \\) ! -name '*-private-files.tar' ! -name '*-private-files.tar.gz' -printf '  %TY-%Tm-%Td %TH:%TM  %f\\n' 2>/dev/null | sort -r | head -20"

  private_count_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-private-files.tar' -o -name '*-private-files.tar.gz' \\) -print 2>/dev/null | wc -l"
  private_list_cmd="cd '${bench_dir}' && find '${backup_rel}' -maxdepth 1 -type f \\( -name '*-private-files.tar' -o -name '*-private-files.tar.gz' \\) -printf '  %TY-%Tm-%Td %TH:%TM  %f\\n' 2>/dev/null | sort -r | head -20"

  print_backup_results "Database backups" "$db_count_cmd" "$db_list_cmd"
  echo
  print_backup_results "Public file backups" "$public_count_cmd" "$public_list_cmd"
  echo
  print_backup_results "Private file backups" "$private_count_cmd" "$private_list_cmd"
  echo
  echo "Tip: For restore, you can paste either an absolute path or a filename from this folder."
  echo "============================================================"
}

resolve_backup_file_path() {
  local input="$1"
  local backup_dir
  backup_dir="$(site_backup_dir)"

  if [[ -z "$input" ]]; then
    return 1
  fi

  if [[ "$input" = /* ]]; then
    echo "$input"
  else
    echo "${backup_dir}/${input}"
  fi
}

show_restore_database_credentials_note() {
  local cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  echo
  echo "Database admin credentials required for restore:"
  echo "  User: ${DB_ADMIN_USER:-frappe_db_admin}"
  echo "  Password label: MariaDB Bench Admin"
  echo "  Credentials file: ${cred_file}"
  echo
  echo "If you do not have the password ready, open another terminal and run:"
  echo "  $(toolkit_cmd credentials-show)"
  echo
  echo "The restore prompt now asks for a database admin user/password."
  echo "Use the MariaDB Bench Admin credential generated by this toolkit."
}

RESTORE_DB_ADMIN_USER=""
RESTORE_DB_ADMIN_PASSWORD=""

read_restore_database_password_from_credentials() {
  local cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  [[ -f "$cred_file" ]] || return 1
  awk '
    /^MariaDB Bench Admin:/ { in_db=1; next }
    in_db && /^[^[:space:]]/ { in_db=0 }
    in_db && /^[[:space:]]*Password:/ {
      sub(/^[[:space:]]*Password:[[:space:]]*/, "")
      print
      exit
    }
  ' "$cred_file" 2>/dev/null | tail -n 1
}

read_restore_database_admin_credentials() {
  local default_user input_user detected_password
  default_user="${DB_ADMIN_USER:-frappe_db_admin}"

  detected_password="${DB_ADMIN_PASSWORD:-}"
  if [[ -z "$detected_password" ]]; then
    detected_password="$(read_restore_database_password_from_credentials 2>/dev/null || true)"
  fi

  if [[ -n "$detected_password" ]]; then
    RESTORE_DB_ADMIN_USER="$default_user"
    RESTORE_DB_ADMIN_PASSWORD="$detected_password"
    status_line "Database admin credential" "OK" "using local toolkit credentials file for ${RESTORE_DB_ADMIN_USER}"
    return 0
  fi

  show_restore_database_credentials_note

  read -r -p "Enter database admin user [${default_user}]: " input_user
  RESTORE_DB_ADMIN_USER="${input_user:-$default_user}"

  read -r -s -p "Database admin password: " RESTORE_DB_ADMIN_PASSWORD
  echo

  if [[ -z "$RESTORE_DB_ADMIN_USER" ]]; then
    fail "Database admin user is required for restore."
  fi

  if [[ -z "$RESTORE_DB_ADMIN_PASSWORD" ]]; then
    fail "Database admin password is required for restore."
  fi
}

confirm_restore() {
  warn "Restore is destructive. It can overwrite the current site database and files."
  warn "The script will try to create an emergency backup before restore."
  echo
  read -r -p "Type RESTORE to continue: " restore_reply
  [[ "$restore_reply" == "RESTORE" ]]
}

run_post_restore_maintenance() {
  local bench_dir="$1"
  local maintenance_failed=0

  log "Starting ERPNext service before post-restore maintenance"
  if ! service_exists; then
    warn "Restore completed, but the ERPNext service is not configured."
    echo "Run Bench manually before running migrate/clear-cache."
    return 1
  fi

  if ! systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    if ! start_erpnext_service; then
      warn "Restore completed, but the ERPNext service could not be started automatically."
      echo
      echo "Run manually:"
      echo "  $(toolkit_cmd start)"
      echo "  $(toolkit_cmd migrate)"
      echo "  $(toolkit_cmd clear-cache)"
      return 1
    fi
  fi

  if ! ensure_bench_services_for_site_commands "post-restore maintenance"; then
    warn "Restore completed, but Bench services were not ready for post-restore maintenance."
    echo
    echo "Run manually after services are ready:"
    echo "  $(toolkit_cmd wait-ready)"
    echo "  $(toolkit_cmd migrate)"
    echo "  $(toolkit_cmd clear-cache)"
    return 1
  fi

  log "Running post-restore migrate"
  echo "The detailed migrate output is saved to a log file to keep the restore screen readable."
  run_as_frappe_quiet "post-restore migrate" "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate" || maintenance_failed=1

  log "Running post-restore asset build"
  echo "The detailed build output is saved to a log file to keep the restore screen readable."
  # Best-effort: a failed rebuild must not fail the restore when migrate succeeded —
  # existing site assets usually still serve; operators can repair-frontend-assets.
  if ! run_as_frappe_quiet "post-restore asset build" "cd '${bench_dir}' && bench build"; then
    warn "post-restore asset build failed; continuing with existing assets."
    echo "  Later: $(toolkit_cmd repair-frontend-assets)"
  fi

  if ensure_bench_services_for_site_commands "post-restore cache cleanup"; then
    log "Clearing post-restore cache"
    run_as_frappe_quiet "post-restore clear-cache" "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache" || maintenance_failed=1
  else
    maintenance_failed=1
  fi

  if [[ "$maintenance_failed" -ne 0 ]]; then
    warn "Restore completed, but one or more post-restore maintenance steps failed."
    echo
    echo "Run manually after reviewing the logs:"
    echo "  $(toolkit_cmd logs)"
    echo "  $(toolkit_cmd migrate)"
    echo "  $(toolkit_cmd repair-frontend-assets)"
    echo "  $(toolkit_cmd verify-frontend-assets)"
    echo "  $(toolkit_cmd verify-access)"
    return 1
  fi

  restart_erpnext_service || warn "Post-restore maintenance completed, but service restart could not be verified automatically."
  if ! bench_static_assets_ready 2>/dev/null; then
    warn "Post-restore: login static assets are not ready yet."
    echo "Repair: $(toolkit_cmd repair-frontend-assets)"
    echo "Wait:   $(toolkit_cmd wait-frontend-assets)"
  else
    status_line "Static assets" "OK" "login CSS/JS probe passed"
  fi
  ok "Post-restore maintenance completed"
}

restore_site_database() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_restore db
    return
  fi

  local bench_dir db_input db_file db_quoted db_admin_user_quoted db_admin_password_quoted
  bench_dir="$(require_site_environment)" || return 1

  list_site_backups
  echo
  read -r -p "Enter database backup filename or full path: " db_input
  db_file="$(resolve_backup_file_path "$db_input")" || fail "No database backup selected."

  if ! path_is_file "$db_file"; then
    fail "Database backup file not found: ${db_file}"
  fi

  read_restore_database_admin_credentials
  confirm_restore || fail "Restore cancelled."

  log "Creating emergency backup before restore"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' backup --with-files" || warn "Emergency backup failed; continuing only because restore was explicitly confirmed."

  stop_erpnext_service || true

  db_quoted="$(printf '%q' "$db_file")"

  db_admin_user_quoted="$(printf '%q' "$RESTORE_DB_ADMIN_USER")"
  db_admin_password_quoted="$(printf '%q' "$RESTORE_DB_ADMIN_PASSWORD")"

  log "Restoring database backup"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' restore ${db_quoted} --db-root-username ${db_admin_user_quoted} --db-root-password ${db_admin_password_quoted}"

  run_post_restore_maintenance "$bench_dir" || return 1

  ok "Database restore completed"
}

restore_site_full() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_restore full
    return
  fi

  local bench_dir db_input public_input private_input db_file public_file private_file cmd
  local db_quoted public_quoted private_quoted db_admin_user_quoted db_admin_password_quoted
  local latest_lines prefix config_file completeness use_latest
  bench_dir="$(require_site_environment)" || return 1

  list_site_backups
  echo
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  if [[ -n "$latest_lines" ]]; then
    prefix="$(printf '%s
' "$latest_lines" | sed -n '1p')"
    db_file="$(printf '%s
' "$latest_lines" | sed -n '2p')"
    public_file="$(printf '%s
' "$latest_lines" | sed -n '3p')"
    private_file="$(printf '%s
' "$latest_lines" | sed -n '4p')"
    config_file="$(printf '%s
' "$latest_lines" | sed -n '5p')"
    completeness="$(printf '%s
' "$latest_lines" | sed -n '6p')"
    if [[ "$completeness" == "complete" ]]; then
      status_line "Latest complete set" "OK" "$prefix"
      status_line "Database" "OK" "$(basename "$db_file")"
      status_line "Public files" "OK" "$(basename "$public_file")"
      status_line "Private files" "OK" "$(basename "$private_file")"
      if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
        read -r -p "Use this latest complete backup set? [Y/n]: " use_latest
      else
        use_latest="y"
      fi
      if [[ "$use_latest" =~ ^[Nn]$|^[Nn][Oo]$ ]]; then
        db_file=""
        public_file=""
        private_file=""
      fi
    else
      status_line "Latest backup set" "WARN" "${prefix:-none} is partial; manual selection required"
      db_file=""
      public_file=""
      private_file=""
    fi
  fi

  if [[ -z "${db_file:-}" ]]; then
    read -r -p "Enter database backup filename or full path: " db_input
    read -r -p "Enter public files backup filename/path, or leave blank: " public_input
    read -r -p "Enter private files backup filename/path, or leave blank: " private_input
    db_file="$(resolve_backup_file_path "$db_input")" || fail "No database backup selected."
    if [[ -n "$public_input" ]]; then public_file="$(resolve_backup_file_path "$public_input")"; else public_file=""; fi
    if [[ -n "$private_input" ]]; then private_file="$(resolve_backup_file_path "$private_input")"; else private_file=""; fi
  fi

  if ! path_is_file "$db_file"; then
    fail "Database backup file not found: ${db_file}"
  fi

  cmd="bench --site '${SITE_NAME}' restore"
  db_quoted="$(printf '%q' "$db_file")"
  cmd="${cmd} ${db_quoted}"

  if [[ -n "${public_file:-}" ]]; then
    if ! path_is_file "$public_file"; then
      fail "Public files backup not found: ${public_file}"
    fi
    public_quoted="$(printf '%q' "$public_file")"
    cmd="${cmd} --with-public-files ${public_quoted}"
  fi

  if [[ -n "${private_file:-}" ]]; then
    if ! path_is_file "$private_file"; then
      fail "Private files backup not found: ${private_file}"
    fi
    private_quoted="$(printf '%q' "$private_file")"
    cmd="${cmd} --with-private-files ${private_quoted}"
  fi

  read_restore_database_admin_credentials
  confirm_restore || fail "Restore cancelled."

  log "Creating emergency backup before full restore"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' backup --with-files" || warn "Emergency backup failed; continuing only because restore was explicitly confirmed."

  stop_erpnext_service || true

  db_admin_user_quoted="$(printf '%q' "$RESTORE_DB_ADMIN_USER")"
  db_admin_password_quoted="$(printf '%q' "$RESTORE_DB_ADMIN_PASSWORD")"
  cmd="${cmd} --db-root-username ${db_admin_user_quoted} --db-root-password ${db_admin_password_quoted}"

  log "Restoring database/files backup"
  run_as_frappe "cd '${bench_dir}' && ${cmd}"

  run_post_restore_maintenance "$bench_dir" || return 1

  ok "Full restore completed"
}

maintenance_migrate() {
  require_sudo
  local bench_dir
  bench_dir="$(require_site_environment)" || return 1
  ensure_bench_services_for_site_commands "migrate" || fail "Bench services are required before running migrate."
  log "Running migrate for ${SITE_NAME}"
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate"
  ok "Migrate completed"
}

maintenance_build() {
  require_sudo
  local bench_dir
  bench_dir="$(require_site_environment)" || return 1
  warn_if_build_memory_low || true
  log "Building assets"
  run_as_frappe "cd '${bench_dir}' && bench build"
  if ! disk_login_asset_bundles_present "$bench_dir"; then
    warn "Login-critical bundles missing on disk after bench build — rebuilding once"
    run_as_frappe "cd '${bench_dir}' && bench build" || true
  fi
  if ! disk_login_asset_bundles_present "$bench_dir"; then
    err "Login CSS/JS still missing under sites/assets after rebuild. See docs/FRAPPE-FRONTEND-ASSETS.md"
    return 1
  fi
  clear_bench_assets_json_cache || true
  ok "Build completed"
}

maintenance_clear_cache() {
  require_sudo
  local bench_dir
  bench_dir="$(require_site_environment)" || return 1
  ensure_bench_services_for_site_commands "clear-cache" || fail "Bench services are required before clearing cache."
  clear_bench_assets_json_cache || {
    log "Clearing cache for ${SITE_NAME}"
    run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache"
  }
  ok "Cache cleared"
}

maintenance_restart() {
  require_sudo
  restart_erpnext_service
}

run_maintenance_menu() {
  while true; do
    ui_submenu_header "Maintenance" "Migrate, build, cache, restart, repair"
    print_two_column_menu \
      "1) Run migrate" \
      "2) Build assets" \
      "3) Clear cache" \
      "4) Restart ERPNext service" \
      "5) Verify frontend assets" \
      "6) Wait for frontend assets" \
      "7) Repair frontend assets" \
      "8) Run safe repair" \
      "9) Show recent service logs"
    ui_submenu_footer
    local maintenance_choice=""
    menu_read_choice maintenance_choice

    case "$maintenance_choice" in
      1)
        maintenance_migrate
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      2)
        maintenance_build
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      3)
        maintenance_clear_cache
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      4)
        maintenance_restart
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      5)
        verify_frontend_assets
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      6)
        wait_frontend_assets
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      7)
        repair_frontend_assets
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      8)
        run_repair
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      9)
        show_erpnext_service_logs
        pause_after_screen "Press Enter to return to Maintenance..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

# ============================================================
# Backup / Restore Hardening
# ============================================================

backup_file_size_human() {
  local file="$1"
  if [[ -f "$file" ]]; then
    du -h "$file" 2>/dev/null | awk '{print $1}'
  else
    echo "missing"
  fi
}

backup_latest_prefix_from_db() {
  local db_file="$1"
  local base
  base="$(basename "$db_file")"
  base="${base%-database.sql.gz}"
  base="${base%.sql.gz}"
  echo "$base"
}

backup_candidate_public_file() {
  local backup_dir="$1" prefix="$2" candidate
  for candidate in "${backup_dir}/${prefix}-files.tar" "${backup_dir}/${prefix}-files.tar.gz"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  echo "${backup_dir}/${prefix}-files.tar"
  return 1
}

backup_candidate_private_file() {
  local backup_dir="$1" prefix="$2" candidate
  for candidate in "${backup_dir}/${prefix}-private-files.tar" "${backup_dir}/${prefix}-private-files.tar.gz"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  echo "${backup_dir}/${prefix}-private-files.tar"
  return 1
}

backup_set_paths_for_db() {
  local db_file="$1" backup_dir prefix public_file private_file config_file completeness
  backup_dir="$(site_backup_dir)"
  prefix="$(backup_latest_prefix_from_db "$db_file")"
  public_file="$(backup_candidate_public_file "$backup_dir" "$prefix" || true)"
  private_file="$(backup_candidate_private_file "$backup_dir" "$prefix" || true)"
  config_file="${backup_dir}/${prefix}-site_config_backup.json"
  completeness="partial"
  if [[ -f "$db_file" && -f "$public_file" && -f "$private_file" && -f "$config_file" ]]; then
    completeness="complete"
  fi
  printf '%s
%s
%s
%s
%s
%s
' "$prefix" "$db_file" "$public_file" "$private_file" "$config_file" "$completeness"
}

backup_latest_set_paths() {
  local backup_dir db_file latest_partial="" candidate completeness
  backup_dir="$(site_backup_dir)"
  if ! path_is_dir "$backup_dir"; then
    return 1
  fi

  while IFS= read -r db_file; do
    [[ -n "$db_file" ]] || continue
    candidate="$(backup_set_paths_for_db "$db_file")"
    completeness="$(printf '%s
' "$candidate" | sed -n '6p')"
    if [[ -z "$latest_partial" ]]; then
      latest_partial="$candidate"
    fi
    if [[ "$completeness" == "complete" ]]; then
      printf '%s
' "$candidate"
      return 0
    fi
  done < <($SUDO find "$backup_dir" -maxdepth 1 -type f \( -name '*-database.sql.gz' -o -name '*.sql.gz' \) -printf '%T@ %p
' 2>/dev/null | sort -nr | cut -d' ' -f2-)

  if [[ -n "$latest_partial" ]]; then
    printf '%s
' "$latest_partial"
    return 0
  fi

  return 1
}

off_vm_backup_summary_pair() {
  off_vm_backup_load_config
  local last_status last_run last_detail
  if off_vm_backup_configured; then
    last_status="$(off_vm_backup_last_state LAST_STATUS 2>/dev/null || echo none)"
    last_run="$(off_vm_backup_last_state LAST_RUN_AT 2>/dev/null || echo never)"
    last_detail="$(off_vm_backup_last_state LAST_DETAIL 2>/dev/null || echo "no previous run")"
    case "$last_status" in
      OK)
        printf 'OK|configured; last run OK at %s\n' "$last_run"
        ;;
      FAIL)
        printf 'WARN|configured; last run failed at %s (%s)\n' "$last_run" "$last_detail"
        ;;
      *)
        printf 'INFO|configured; no successful off-VM run recorded yet\n'
        ;;
    esac
  else
    printf 'WARN|not configured; run off-vm-backup-guided-setup\n'
  fi
}

show_backup_status() {
  require_sudo
  local bench_dir backup_dir count_all count_db count_public count_private latest_lines prefix db_file public_file private_file config_file backup_total completeness
  bench_dir="$(require_site_environment)" || return 1
  backup_dir="$(site_backup_dir)"

  ui_box_start "Backup Status"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Backup folder" "INFO" "$backup_dir"

  if ! path_is_dir "$backup_dir"; then
    status_line "Backup folder" "WARN" "not found; create a backup first"
    ui_next "$(toolkit_cmd backup-files)"
    ui_box_end
    return 0
  fi

  count_all="$($SUDO find "$backup_dir" -maxdepth 1 -type f 2>/dev/null | wc -l | awk '{print $1+0}')"
  count_db="$($SUDO find "$backup_dir" -maxdepth 1 -type f \( -name '*-database.sql.gz' -o -name '*.sql.gz' \) 2>/dev/null | wc -l | awk '{print $1+0}')"
  count_public="$($SUDO find "$backup_dir" -maxdepth 1 -type f \( -name '*-files.tar' -o -name '*-files.tar.gz' \) ! -name '*-private-files.tar' ! -name '*-private-files.tar.gz' 2>/dev/null | wc -l | awk '{print $1+0}')"
  count_private="$($SUDO find "$backup_dir" -maxdepth 1 -type f \( -name '*-private-files.tar' -o -name '*-private-files.tar.gz' \) 2>/dev/null | wc -l | awk '{print $1+0}')"
  backup_total="$($SUDO du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || echo unknown)"

  status_line "Backup files" "INFO" "${count_all} file(s), ${backup_total} total"
  status_line "Database backups" "$([[ "$count_db" -gt 0 ]] && echo OK || echo WARN)" "${count_db} found"
  status_line "Public file backups" "$([[ "$count_public" -gt 0 ]] && echo OK || echo WARN)" "${count_public} found"
  status_line "Private file backups" "$([[ "$count_private" -gt 0 ]] && echo OK || echo WARN)" "${count_private} found"

  latest_lines="$(backup_latest_set_paths || true)"
  if [[ -n "$latest_lines" ]]; then
    prefix="$(printf '%s\n' "$latest_lines" | sed -n '1p')"
    db_file="$(printf '%s\n' "$latest_lines" | sed -n '2p')"
    public_file="$(printf '%s\n' "$latest_lines" | sed -n '3p')"
    private_file="$(printf '%s\n' "$latest_lines" | sed -n '4p')"
    config_file="$(printf '%s\n' "$latest_lines" | sed -n '5p')"
    completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
    status_line "Latest set" "INFO" "$prefix"
    status_line "Latest set state" "$([[ "$completeness" == complete ]] && echo OK || echo WARN)" "${completeness:-partial}"
    status_line "Latest database" "$([[ -f "$db_file" ]] && echo OK || echo FAIL)" "$(basename "$db_file") ($(backup_file_size_human "$db_file"))"
    status_line "Latest public files" "$([[ -f "$public_file" ]] && echo OK || echo WARN)" "$(basename "$public_file") ($(backup_file_size_human "$public_file"))"
    status_line "Latest private files" "$([[ -f "$private_file" ]] && echo OK || echo WARN)" "$(basename "$private_file") ($(backup_file_size_human "$private_file"))"
    status_line "Latest site config" "$([[ -f "$config_file" ]] && echo OK || echo WARN)" "$(basename "$config_file") ($(backup_file_size_human "$config_file"))"
  else
    status_line "Latest set" "WARN" "no database backup found"
  fi

  echo
  local off_pair off_state off_detail
  off_pair="$(off_vm_backup_summary_pair)"
  off_state="${off_pair%%|*}"
  off_detail="${off_pair#*|}"
  status_line "Off-VM copy" "$off_state" "$off_detail"
  if [[ "$off_state" == "OK" ]]; then
    local rehearsal_pair rehearsal_state rehearsal_detail
    rehearsal_pair="$(restore_rehearsal_summary_pair)"
    rehearsal_state="${rehearsal_pair%%|*}"
    rehearsal_detail="${rehearsal_pair#*|}"
    status_line "Restore rehearsal" "$rehearsal_state" "$rehearsal_detail"
    if [[ "$rehearsal_state" == "OK" ]]; then
      echo "Off-VM copy is configured, the last copy completed, and a restore rehearsal is recorded."
      ui_next "$(toolkit_cmd backup-verify)" "$(toolkit_cmd restore-rehearsal-status)" "$(toolkit_cmd production-checklist)"
    else
      echo "Off-VM copy is configured and the last copy completed. Record a successful disposable-VM restore rehearsal before relying on production backups."
      ui_next "$(toolkit_cmd backup-verify)" "$(toolkit_cmd restore-rehearsal-record)" "$(toolkit_cmd restore-rehearsal-guide)"
    fi
  else
    echo "Off-VM copy is not fully proven yet. Configure it, run dry-run, then run a real off-VM backup."
    ui_next "$(toolkit_cmd backup-verify)" "$(toolkit_cmd off-vm-backup-guided-setup)" "$(toolkit_cmd off-vm-backup-status)"
  fi
  ui_box_end
}

verify_backup_file() {
  local label="$1"
  local file="$2"
  local kind="$3"
  if [[ ! -f "$file" ]]; then
    status_line "$label" "WARN" "missing"
    return 1
  fi
  case "$kind" in
    gzip)
      if gzip -t "$file" >/dev/null 2>&1; then
        status_line "$label" "OK" "gzip readable; $(backup_file_size_human "$file")"
        return 0
      fi
      status_line "$label" "FAIL" "gzip test failed"
      return 1
      ;;
    tar)
      if [[ "$file" == *.tar.gz || "$file" == *.tgz ]]; then
        if tar -tzf "$file" >/dev/null 2>&1; then
          status_line "$label" "OK" "tar.gz readable; $(backup_file_size_human "$file")"
          return 0
        fi
      else
        if tar -tf "$file" >/dev/null 2>&1; then
          status_line "$label" "OK" "tar readable; $(backup_file_size_human "$file")"
          return 0
        fi
      fi
      status_line "$label" "FAIL" "tar list failed"
      return 1
      ;;
    json)
      if python3 -m json.tool "$file" >/dev/null 2>&1; then
        status_line "$label" "OK" "json readable; $(backup_file_size_human "$file")"
        return 0
      fi
      status_line "$label" "WARN" "json validation failed or python unavailable"
      return 1
      ;;
  esac
}

verify_latest_backup_set() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_backup_verify
    return
  fi

  local latest_lines prefix db_file public_file private_file config_file completeness ok_count fail_count
  require_site_environment >/dev/null || return 1

  ui_box_start "Backup Verification"
  status_line "Mode" "INFO" "checks latest files only; no restore is performed"
  status_line "Site" "INFO" "$SITE_NAME"

  latest_lines="$(backup_latest_set_paths || true)"
  if [[ -z "$latest_lines" ]]; then
    status_line "Latest backup" "FAIL" "no database backup found"
    ui_next "$(toolkit_cmd backup-files)"
    ui_box_end
    return 1
  fi

  prefix="$(printf '%s\n' "$latest_lines" | sed -n '1p')"
  db_file="$(printf '%s\n' "$latest_lines" | sed -n '2p')"
  public_file="$(printf '%s\n' "$latest_lines" | sed -n '3p')"
  private_file="$(printf '%s\n' "$latest_lines" | sed -n '4p')"
  config_file="$(printf '%s\n' "$latest_lines" | sed -n '5p')"
  completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"

  status_line "Latest set" "INFO" "$prefix"
  status_line "Latest set state" "$([[ "$completeness" == complete ]] && echo OK || echo WARN)" "${completeness:-partial}"
  ok_count=0
  fail_count=0

  if verify_backup_file "Database" "$db_file" gzip; then ok_count=$((ok_count + 1)); else fail_count=$((fail_count + 1)); fi
  if verify_backup_file "Public files" "$public_file" tar; then ok_count=$((ok_count + 1)); else fail_count=$((fail_count + 1)); fi
  if verify_backup_file "Private files" "$private_file" tar; then ok_count=$((ok_count + 1)); else fail_count=$((fail_count + 1)); fi
  if verify_backup_file "Site config" "$config_file" json; then ok_count=$((ok_count + 1)); else true; fi

  if [[ "$fail_count" -eq 0 ]]; then
    if restore_rehearsal_recorded_ok; then
      status_line "Verification" "OK" "backup files are readable; restore rehearsal is recorded"
    else
      status_line "Verification" "OK" "backup files are readable; restore still must be recorded separately"
    fi
  else
    status_line "Verification" "WARN" "${fail_count} required component(s) missing or unreadable"
  fi

  echo
  if restore_rehearsal_recorded_ok; then
    echo "This is not a restore test, but a successful restore rehearsal is recorded on this production VM."
    ui_next "$(toolkit_cmd restore-rehearsal-status)" "$(toolkit_cmd production-checklist)"
  else
    echo "This is not a restore test. For production, rehearse restore on a disposable VM and record it."
    ui_next "$(toolkit_cmd restore-rehearsal-guide)" "$(toolkit_cmd restore-rehearsal-record)"
  fi
  ui_box_end
}

show_off_vm_backup_guide() {
  require_sudo
  local backup_dir host_name
  require_site_environment >/dev/null || return 1
  backup_dir="$(site_backup_dir)"
  host_name="$(hostname -f 2>/dev/null || hostname)"

  ui_box_start "Off-VM Backup Guide"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Backup folder" "INFO" "$backup_dir"
  status_line "Server" "INFO" "$host_name"
  echo
  echo "Run from your workstation, not inside the VM:"
  echo
  echo "  mkdir -p ~/erpnext-backups/${SITE_NAME}"
  echo "  rsync -avz root@${CURRENT_VM_IP:-65.109.221.4}:${backup_dir}/ ~/erpnext-backups/${SITE_NAME}/"
  echo
  echo "Or copy one archive with scp:"
  echo
  echo "  scp root@${CURRENT_VM_IP:-65.109.221.4}:${backup_dir}/FILE_NAME ~/erpnext-backups/${SITE_NAME}/"
  echo
  echo "Recommended after copy:"
  echo "  sha256sum ~/erpnext-backups/${SITE_NAME}/* > ~/erpnext-backups/${SITE_NAME}/SHA256SUMS"
  echo
  ui_next "$(toolkit_cmd backup-verify)" "Take/confirm a cloud snapshot after off-VM copy."
  ui_box_end
}

show_restore_rehearsal_guide() {
  ui_box_start "Restore Rehearsal Guide"
  status_line "Mode" "INFO" "planning only; no restore is performed"
  status_line "Site" "INFO" "$SITE_NAME"
  restore_rehearsal_status_line || true
  echo
  echo "Safe restore test workflow:"
  echo "  1) Take a cloud snapshot of the current VM."
  echo "  2) Create a disposable local/cloud restore VM with similar OS/resources."
  echo "  3) Install the same script version and ERPNext stack using the same site name."
  echo "  4) Generate a temporary restore key on the restore VM."
  echo "  5) Add that key on the backup server, restricted to the restore VM's current outbound public IP."
  echo "  6) Pull the database, public files, private files, and site_config backup to the restore VM."
  echo "  7) Run restore on the restore VM only, then verify service, HTTP access, and login."
  echo "  8) Remove the temporary restore key from the backup server."
  echo "  9) Record the rehearsal on the production ERPNext VM."
  echo
  echo "Recommended command flow:"
  echo "  On restore VM:      $(toolkit_cmd restore-rehearsal-wizard)"
  echo "  On restore VM:      $(toolkit_cmd restore-rehearsal-report)"
  echo "  On production VM:   $(toolkit_cmd restore-rehearsal-record)"
  echo "  On production VM:   $(toolkit_cmd restore-rehearsal-status)"
  echo
  echo "The restore VM IP is evidence only. It may change when the restore VM moves networks."
  echo "Do not use the first restore rehearsal on the live production VM."
  ui_next "$(toolkit_cmd restore-rehearsal-status)" "$(toolkit_cmd restore-rehearsal-record)" "$(toolkit_cmd backup-status)"
  ui_box_end
}

restore_rehearsal_value() {
  local key="$1" value=""
  if value="$(read_config_key_from_file "$RESTORE_REHEARSAL_RECORD_FILE" "$key" 2>/dev/null)" && [[ -n "$value" ]]; then
    printf '%s
' "$value"
    return 0
  fi
  return 1
}

restore_rehearsal_recorded_ok() {
  local status site
  status="$(restore_rehearsal_value RESTORE_REHEARSAL_STATUS 2>/dev/null || true)"
  site="$(restore_rehearsal_value RESTORE_REHEARSAL_SITE 2>/dev/null || true)"
  [[ "$status" == "OK" ]] || return 1
  [[ -z "$site" || "$site" == "$SITE_NAME" ]] || return 1
  return 0
}

restore_rehearsal_summary_pair() {
  local status site recorded_at backup_set target_label target_kind target_ip login_validated
  if [[ ! -r "$RESTORE_REHEARSAL_RECORD_FILE" ]]; then
    printf 'WARN|not recorded; run restore-rehearsal-record after a successful disposable-VM restore
'
    return 0
  fi
  status="$(restore_rehearsal_value RESTORE_REHEARSAL_STATUS 2>/dev/null || true)"
  site="$(restore_rehearsal_value RESTORE_REHEARSAL_SITE 2>/dev/null || true)"
  recorded_at="$(restore_rehearsal_value RESTORE_REHEARSAL_RECORDED_AT 2>/dev/null || true)"
  backup_set="$(restore_rehearsal_value RESTORE_REHEARSAL_BACKUP_SET 2>/dev/null || true)"
  target_kind="$(restore_rehearsal_value RESTORE_REHEARSAL_TARGET_KIND 2>/dev/null || true)"
  target_label="$(restore_rehearsal_value RESTORE_REHEARSAL_TARGET_LABEL 2>/dev/null || true)"
  target_ip="$(restore_rehearsal_value RESTORE_REHEARSAL_TARGET_IP 2>/dev/null || true)"
  login_validated="$(restore_rehearsal_value RESTORE_REHEARSAL_LOGIN_VALIDATED 2>/dev/null || true)"
  if [[ "$status" != "OK" ]]; then
    printf 'WARN|record exists but status is %s
' "${status:-unknown}"
    return 0
  fi
  if [[ -n "$site" && "$site" != "$SITE_NAME" ]]; then
    printf 'WARN|recorded for %s, current site is %s
' "$site" "$SITE_NAME"
    return 0
  fi
  local detail="completed"
  [[ -n "$recorded_at" ]] && detail="${detail} ${recorded_at}"
  [[ -n "$backup_set" ]] && detail="${detail}; backup set ${backup_set}"
  [[ -n "$target_kind" || -n "$target_label" ]] && detail="${detail}; target ${target_kind:-restore-vm}${target_label:+/${target_label}}"
  [[ -n "$target_ip" ]] && detail="${detail}; IP noted ${target_ip}"
  case "$login_validated" in
    true | yes | YES | 1) detail="${detail}; login validated" ;;
    false | no | NO | 0) detail="${detail}; login not recorded" ;;
  esac
  printf 'OK|%s
' "$detail"
}

restore_rehearsal_status_line() {
  local pair state detail
  pair="$(restore_rehearsal_summary_pair)"
  state="${pair%%|*}"
  detail="${pair#*|}"
  status_line "Restore rehearsal" "$state" "$detail"
}

sanitize_restore_rehearsal_value() {
  local value="$1"
  printf '%s' "$value" | tr '
	' '   ' | sed -E 's/[[:space:]]+/-/g; s/[^A-Za-z0-9._:@\/+=,-]/-/g; s/^-+//; s/-+$//' | cut -c1-240
}

restore_rehearsal_latest_backup_set_hint() {
  local latest_lines prefix
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  prefix="$(printf '%s
' "$latest_lines" | sed -n '1p')"
  printf '%s
' "$prefix"
}

show_restore_rehearsal_status() {
  require_sudo
  ui_box_start "Restore Rehearsal Status"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Record file" "$($SUDO test -f "$RESTORE_REHEARSAL_RECORD_FILE" && echo OK || echo WARN)" "$RESTORE_REHEARSAL_RECORD_FILE"
  restore_rehearsal_status_line || true
  if $SUDO test -f "$RESTORE_REHEARSAL_RECORD_FILE"; then
    echo
    echo "Recorded metadata:"
    $SUDO sed -E 's/(PASSWORD|TOKEN|SECRET|KEY)=.*/=[REDACTED]/' "$RESTORE_REHEARSAL_RECORD_FILE" | sed 's/^/  /'
  else
    echo
    echo "No restore rehearsal record exists yet on this VM."
    echo "After a successful disposable-VM restore, run:"
    echo "  sudo erpnext-dev restore-rehearsal-record"
  fi
  echo
  echo "Note: restore VM IP is recorded only as evidence. It may change when the VM uses another network."
  ui_next "$(toolkit_cmd restore-rehearsal-record)" "$(toolkit_cmd production-checklist)" "$(toolkit_cmd backup-status)"
  ui_box_end
}

record_restore_rehearsal() {
  require_sudo
  local latest_hint backup_set target_kind target_label target_ip result notes login_validated recorded_at config_dir
  local answer_backup answer_kind answer_label answer_ip answer_result answer_notes answer_login
  latest_hint="$(restore_rehearsal_latest_backup_set_hint 2>/dev/null || true)"
  backup_set="${RESTORE_REHEARSAL_BACKUP_SET:-$latest_hint}"
  target_kind="${RESTORE_REHEARSAL_TARGET_KIND:-local-vm}"
  target_label="${RESTORE_REHEARSAL_TARGET_LABEL:-restore-vm}"
  target_ip="${RESTORE_REHEARSAL_TARGET_IP:-}"
  result="${RESTORE_REHEARSAL_RESULT:-full_restore_completed}"
  notes="${RESTORE_REHEARSAL_NOTES:-off-vm-backup-restored-on-disposable-vm}"
  login_validated="${RESTORE_REHEARSAL_LOGIN_VALIDATED:-}"

  ui_box_start "Record Restore Rehearsal"
  echo "Run this on the production ERPNext VM after a successful restore rehearsal on a disposable VM."
  echo "This records the completed rehearsal so production-checklist, backup-status, and final QA stop showing stale restore warnings."
  echo
  status_line "Record file" "INFO" "$RESTORE_REHEARSAL_RECORD_FILE"
  status_line "Current site" "INFO" "$SITE_NAME"
  status_line "Latest local backup set" "$([[ -n "$latest_hint" ]] && echo INFO || echo WARN)" "${latest_hint:-not detected}"
  echo
  echo "The restore VM IP is evidence only. If the restore VM moved to another network, enter the current/known IP or leave it blank."

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Backup set restored [${backup_set}]: " answer_backup
    backup_set="${answer_backup:-$backup_set}"
    read -r -p "Restore target kind [${target_kind}]: " answer_kind
    target_kind="${answer_kind:-$target_kind}"
    read -r -p "Restore target label [${target_label}]: " answer_label
    target_label="${answer_label:-$target_label}"
    read -r -p "Restore VM IP/address evidence, optional [${target_ip}]: " answer_ip
    target_ip="${answer_ip:-$target_ip}"
    read -r -p "Result [${result}]: " answer_result
    result="${answer_result:-$result}"
    read -r -p "Was browser/login validation completed? [y/N]: " answer_login
    case "$answer_login" in
      y | Y | yes | YES) login_validated="true" ;;
      n | N | no | NO | "") login_validated="false" ;;
      *) login_validated="$(sanitize_restore_rehearsal_value "$answer_login")" ;;
    esac
    read -r -p "Notes [${notes}]: " answer_notes
    notes="${answer_notes:-$notes}"
  fi

  [[ -n "$backup_set" ]] || fail "Backup set is required."
  backup_set="$(sanitize_restore_rehearsal_value "$backup_set")"
  target_kind="$(sanitize_restore_rehearsal_value "$target_kind")"
  target_label="$(sanitize_restore_rehearsal_value "$target_label")"
  target_ip="$(sanitize_restore_rehearsal_value "$target_ip")"
  result="$(sanitize_restore_rehearsal_value "$result")"
  notes="$(sanitize_restore_rehearsal_value "$notes")"
  login_validated="$(sanitize_restore_rehearsal_value "${login_validated:-false}")"
  recorded_at="$(date -Is 2>/dev/null || date)"

  config_dir="$(dirname "$RESTORE_REHEARSAL_RECORD_FILE")"
  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$RESTORE_REHEARSAL_RECORD_FILE" >/dev/null <<EOF_RESTORE_REHEARSAL
RESTORE_REHEARSAL_STATUS=OK
RESTORE_REHEARSAL_RECORDED_AT=${recorded_at}
RESTORE_REHEARSAL_SITE=${SITE_NAME}
RESTORE_REHEARSAL_BACKUP_SET=${backup_set}
RESTORE_REHEARSAL_TARGET_KIND=${target_kind}
RESTORE_REHEARSAL_TARGET_LABEL=${target_label}
RESTORE_REHEARSAL_TARGET_IP=${target_ip}
RESTORE_REHEARSAL_RESULT=${result}
RESTORE_REHEARSAL_LOGIN_VALIDATED=${login_validated}
RESTORE_REHEARSAL_NOTES=${notes}
RESTORE_REHEARSAL_RECORDED_BY_TOOLKIT_VERSION=${SCRIPT_VERSION}
EOF_RESTORE_REHEARSAL
  $SUDO chown root:root "$RESTORE_REHEARSAL_RECORD_FILE" || true
  $SUDO chmod 600 "$RESTORE_REHEARSAL_RECORD_FILE" || true
  status_line "Restore rehearsal record" "OK" "saved"
  restore_rehearsal_status_line || true
  ui_next "$(toolkit_cmd restore-rehearsal-status)" "$(toolkit_cmd production-checklist)" "$(toolkit_cmd backup-status)"
  ui_box_end
}

show_restore_rehearsal_report() {
  require_sudo
  local latest_lines prefix completeness vm_ip public_ip installed runtime http_local http_ip
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  prefix="$(printf '%s
' "$latest_lines" | sed -n '1p')"
  completeness="$(printf '%s
' "$latest_lines" | sed -n '6p')"
  vm_ip="$(get_vm_ip 2>/dev/null || true)"
  public_ip="$(detect_outbound_public_ipv4 2>/dev/null || true)"
  installed="$(install_state 2>/dev/null || echo unknown)"
  runtime="$(runtime_state 2>/dev/null || echo unknown)"
  http_local="$(curl -I -s --max-time 5 http://127.0.0.1:8000 2>/dev/null | awk 'NR==1 {print $0}' | tr -d '
' || true)"
  if [[ -n "$vm_ip" ]]; then
    http_ip="$(curl -I -s --max-time 5 "http://${vm_ip}:8000" 2>/dev/null | awk 'NR==1 {print $0}' | tr -d '
' || true)"
  fi

  ui_box_start "Restore Rehearsal Report"
  echo "Run this on the disposable restore VM after restore-full and service validation."
  echo
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Toolkit version" "INFO" "$SCRIPT_VERSION"
  status_line "Install" "$([[ "$installed" == "Installed" ]] && echo OK || echo WARN)" "$installed"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo WARN)" "$runtime"
  status_line "Backup set" "$([[ -n "$prefix" ]] && echo OK || echo WARN)" "${prefix:-not detected}"
  status_line "Backup set state" "$([[ "$completeness" == complete ]] && echo OK || echo WARN)" "${completeness:-unknown}"
  status_line "Restore VM private IP" "INFO" "${vm_ip:-unknown}"
  status_line "Restore VM outbound IP" "INFO" "${public_ip:-unknown; may change by network}"
  status_line "HTTP localhost" "$([[ "$http_local" == HTTP/* ]] && echo OK || echo WARN)" "${http_local:-not responding}"
  status_line "HTTP VM IP" "$([[ "$http_ip" == HTTP/* ]] && echo OK || echo WARN)" "${http_ip:-not tested}"
  echo
  echo "After cleanup of the temporary restore key, run this on the production ERPNext VM to record the rehearsal:"
  echo "  sudo RESTORE_REHEARSAL_BACKUP_SET='${prefix:-BACKUP_SET}' \
    RESTORE_REHEARSAL_TARGET_KIND='local-vm' \
    RESTORE_REHEARSAL_TARGET_LABEL='restore-vm' \
    RESTORE_REHEARSAL_TARGET_IP='${vm_ip:-}' \
    RESTORE_REHEARSAL_RESULT='full_restore_completed' \
    RESTORE_REHEARSAL_LOGIN_VALIDATED='false' \
    erpnext-dev restore-rehearsal-record"
  echo
  echo "If browser/login was validated, change RESTORE_REHEARSAL_LOGIN_VALIDATED to true."
  echo "If the VM IP changed, update or omit RESTORE_REHEARSAL_TARGET_IP; it is evidence only."
  ui_next "$(toolkit_cmd doctor)" "$(toolkit_cmd status)" "$(toolkit_cmd restore-rehearsal-record) on production VM"
  ui_box_end
}

backup_schedule_timer_active() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-active --quiet "$BACKUP_SCHEDULE_TIMER" 2>/dev/null
}

backup_schedule_timer_enabled() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-enabled --quiet "$BACKUP_SCHEDULE_TIMER" 2>/dev/null
}

show_backup_schedule_plan() {
  require_sudo
  ui_box_start "Scheduled Backup Plan"
  status_line "Mode" "INFO" "planning only; no timer changes are applied"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Service" "INFO" "$BACKUP_SCHEDULE_SERVICE"
  status_line "Timer" "INFO" "$BACKUP_SCHEDULE_TIMER"
  status_line "Schedule" "INFO" "OnCalendar=${BACKUP_SCHEDULE_ON_CALENDAR}"
  status_line "Random delay" "INFO" "$BACKUP_SCHEDULE_RANDOM_DELAY"
  status_line "Command" "INFO" "${INSTALLER_CANONICAL_PATH} backup-files"
  echo
  echo "What this does:"
  echo "  - Creates a systemd timer inside the VM."
  echo "  - Runs database + files backup using the same toolkit script."
  echo "  - Keeps backups in the site's private/backups folder."
  echo
  echo "What this does not do:"
  echo "  - It does not copy backups off the VM."
  echo "  - It does not replace cloud snapshots."
  echo "  - It does not prove restore works; use restore rehearsal for that."
  ui_next "$(toolkit_cmd configure-backup-schedule)" "$(toolkit_cmd backup-schedule-status)"
  ui_box_end
}

configure_backup_schedule() {
  require_sudo
  require_site_environment >/dev/null || return 1
  install_self_for_reuse

  ui_box_start "Configure Scheduled Backups"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Schedule" "INFO" "OnCalendar=${BACKUP_SCHEDULE_ON_CALENDAR}"
  status_line "Random delay" "INFO" "$BACKUP_SCHEDULE_RANDOM_DELAY"
  status_line "Command" "INFO" "${INSTALLER_CANONICAL_PATH} backup-files"
  echo
  echo "This creates a local VM systemd timer for database + files backups."
  echo "Off-VM backup copy is still required for production."
  if ! confirm "Configure scheduled local backups now?"; then
    warn "Scheduled backup configuration skipped."
    ui_box_end
    return 0
  fi

  log "Writing scheduled backup systemd units"
  local service_tmp timer_tmp
  service_tmp="$(mktemp /tmp/erpnext-dev-backup.XXXXXX.service)" || fail "Could not create temporary service unit file."
  timer_tmp="$(mktemp /tmp/erpnext-dev-backup.XXXXXX.timer)" || fail "Could not create temporary timer unit file."

  cat >"$service_tmp" <<EOF_SERVICE
[Unit]
Description=ERPNext scheduled backup for ${SITE_NAME}
Wants=network-online.target
After=network-online.target mariadb.service redis-server.service

[Service]
Type=oneshot
Environment=SITE_NAME=${SITE_NAME}
Environment=PRODUCTION_DOMAIN=${PRODUCTION_DOMAIN:-}
Environment=DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-development}
ExecStart=${INSTALLER_CANONICAL_PATH} backup-files
EOF_SERVICE

  cat >"$timer_tmp" <<EOF_TIMER
[Unit]
Description=Run ERPNext scheduled backup for ${SITE_NAME}

[Timer]
OnCalendar=${BACKUP_SCHEDULE_ON_CALENDAR}
RandomizedDelaySec=${BACKUP_SCHEDULE_RANDOM_DELAY}
Persistent=true
Unit=${BACKUP_SCHEDULE_SERVICE}

[Install]
WantedBy=timers.target
EOF_TIMER

  $SUDO mv "$service_tmp" "/etc/systemd/system/${BACKUP_SCHEDULE_SERVICE}"
  $SUDO mv "$timer_tmp" "/etc/systemd/system/${BACKUP_SCHEDULE_TIMER}"
  $SUDO chmod 0644 "/etc/systemd/system/${BACKUP_SCHEDULE_SERVICE}" "/etc/systemd/system/${BACKUP_SCHEDULE_TIMER}"
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now "$BACKUP_SCHEDULE_TIMER"

  ui_box_start "Result Summary"
  status_line "Scheduled backups" "OK" "timer enabled"
  status_line "Timer" "INFO" "$BACKUP_SCHEDULE_TIMER"
  status_line "Schedule" "INFO" "OnCalendar=${BACKUP_SCHEDULE_ON_CALENDAR}"
  status_line "Backup type" "INFO" "database + public/private files"
  status_line "Off-VM copy" "WARN" "still required"
  ui_next "$(toolkit_cmd backup-schedule-status)" "$(toolkit_cmd off-vm-backup-guide)"
  ui_box_end
}

show_backup_schedule_status() {
  require_sudo
  local service_path timer_path enabled active next_line latest_lines completeness
  service_path="/etc/systemd/system/${BACKUP_SCHEDULE_SERVICE}"
  timer_path="/etc/systemd/system/${BACKUP_SCHEDULE_TIMER}"
  enabled="disabled"
  active="inactive"
  backup_schedule_timer_enabled && enabled="enabled"
  backup_schedule_timer_active && active="active"
  next_line="$($SUDO systemctl list-timers "$BACKUP_SCHEDULE_TIMER" --all --no-pager 2>/dev/null | awk 'NR==2 {print $1" "$2" "$3" "$4}' || true)"
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"

  ui_box_start "Scheduled Backup Status"
  status_line "Service file" "$([[ -f "$service_path" ]] && echo OK || echo WARN)" "$service_path"
  status_line "Timer file" "$([[ -f "$timer_path" ]] && echo OK || echo WARN)" "$timer_path"
  status_line "Timer enabled" "$([[ "$enabled" == enabled ]] && echo OK || echo WARN)" "$enabled"
  status_line "Timer active" "$([[ "$active" == active ]] && echo OK || echo WARN)" "$active"
  status_line "Schedule" "INFO" "${BACKUP_SCHEDULE_ON_CALENDAR}"
  status_line "Latest backup" "$([[ "$completeness" == complete ]] && echo OK || echo WARN)" "${completeness:-none}"
  if [[ -n "$next_line" ]]; then
    status_line "Next run" "INFO" "$next_line"
  fi
  echo
  echo "Useful commands:"
  echo "  systemctl list-timers ${BACKUP_SCHEDULE_TIMER} --all"
  echo "  journalctl -u ${BACKUP_SCHEDULE_SERVICE} --no-pager -n 80"
  ui_next "$(toolkit_cmd backup-status)" "$(toolkit_cmd backup-verify)"
  ui_box_end
}

backup_complete_sets() {
  local backup_dir db_file candidate completeness prefix public_file private_file config_file mtime
  backup_dir="$(site_backup_dir)"
  if ! path_is_dir "$backup_dir"; then
    return 1
  fi

  while IFS= read -r db_file; do
    [[ -n "$db_file" ]] || continue
    candidate="$(backup_set_paths_for_db "$db_file")"
    completeness="$(printf '%s\n' "$candidate" | sed -n '6p')"
    [[ "$completeness" == "complete" ]] || continue
    prefix="$(printf '%s\n' "$candidate" | sed -n '1p')"
    public_file="$(printf '%s\n' "$candidate" | sed -n '3p')"
    private_file="$(printf '%s\n' "$candidate" | sed -n '4p')"
    config_file="$(printf '%s\n' "$candidate" | sed -n '5p')"
    mtime="$($SUDO stat -c '%Y' "$db_file" 2>/dev/null || echo 0)"
    printf '%s|%s|%s|%s|%s|%s\n' "$mtime" "$prefix" "$db_file" "$public_file" "$private_file" "$config_file"
  done < <($SUDO find "$backup_dir" -maxdepth 1 -type f \( -name '*-database.sql.gz' -o -name '*.sql.gz' \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
}

backup_complete_set_count() {
  backup_complete_sets 2>/dev/null | wc -l | awk '{print $1+0}'
}

backup_retention_keep_count() {
  local keep="${BACKUP_RETENTION_KEEP_COMPLETE:-14}"
  if [[ ! "$keep" =~ ^[0-9]+$ || "$keep" -lt 1 ]]; then
    keep=14
  fi
  echo "$keep"
}

backup_disk_usage_percent() {
  local backup_dir
  backup_dir="$(site_backup_dir)"
  if path_is_dir "$backup_dir"; then
    df -P "$backup_dir" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}'
  else
    echo 0
  fi
}

backup_retention_candidate_sets() {
  local keep index line
  keep="$(backup_retention_keep_count)"
  index=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    index=$((index + 1))
    if [[ "$index" -gt "$keep" ]]; then
      printf '%s\n' "$line"
    fi
  done < <(backup_complete_sets)
}

show_backup_retention_plan() {
  require_sudo
  require_site_environment >/dev/null || return 1
  local backup_dir complete_count keep delete_count disk_percent warn_percent backup_total
  backup_dir="$(site_backup_dir)"
  complete_count="$(backup_complete_set_count)"
  keep="$(backup_retention_keep_count)"
  delete_count=0
  if [[ "$complete_count" -gt "$keep" ]]; then
    delete_count=$((complete_count - keep))
  fi
  disk_percent="$(backup_disk_usage_percent)"
  warn_percent="${BACKUP_RETENTION_WARN_DISK_PERCENT:-80}"
  backup_total="$($SUDO du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || echo unknown)"

  ui_box_start "Backup Retention Plan"
  status_line "Mode" "INFO" "planning only; no files are deleted"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Backup folder" "INFO" "$backup_dir"
  status_line "Retention" "INFO" "keep latest ${keep} complete backup set(s)"
  status_line "Complete sets" "$([[ "$complete_count" -gt 0 ]] && echo OK || echo WARN)" "${complete_count} found"
  status_line "Cleanup candidates" "$([[ "$delete_count" -gt 0 ]] && echo WARN || echo OK)" "${delete_count} old complete set(s)"
  status_line "Backup folder size" "INFO" "$backup_total"
  status_line "Disk usage" "$([[ "$disk_percent" -ge "$warn_percent" ]] && echo WARN || echo OK)" "${disk_percent}% used; warn at ${warn_percent}%"
  echo
  echo "Safe retention policy:"
  echo "  - Deletes only old complete backup sets after confirmation."
  echo "  - Keeps the newest ${keep} complete set(s)."
  echo "  - Does not replace off-VM backups or cloud snapshots."
  echo "  - Does not delete partial/orphan files in this first implementation."
  ui_next "$(toolkit_cmd cleanup-old-backups-dry-run)" "$(toolkit_cmd cleanup-old-backups)"
  ui_box_end
}

show_backup_retention_status() {
  require_sudo
  require_site_environment >/dev/null || return 1
  local backup_dir complete_count keep candidate_count disk_percent warn_percent backup_total latest_lines completeness
  backup_dir="$(site_backup_dir)"
  complete_count="$(backup_complete_set_count)"
  keep="$(backup_retention_keep_count)"
  candidate_count="$(backup_retention_candidate_sets 2>/dev/null | wc -l | awk '{print $1+0}')"
  disk_percent="$(backup_disk_usage_percent)"
  warn_percent="${BACKUP_RETENTION_WARN_DISK_PERCENT:-80}"
  backup_total="$($SUDO du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || echo unknown)"
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"

  ui_box_start "Backup Retention Status"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Retention" "INFO" "keep latest ${keep} complete backup set(s)"
  status_line "Complete sets" "$([[ "$complete_count" -gt 0 ]] && echo OK || echo WARN)" "${complete_count} found"
  status_line "Latest backup" "$([[ "$completeness" == complete ]] && echo OK || echo WARN)" "${completeness:-none}"
  status_line "Cleanup candidates" "$([[ "$candidate_count" -gt 0 ]] && echo WARN || echo OK)" "${candidate_count} old set(s)"
  status_line "Backup folder size" "INFO" "$backup_total"
  status_line "Disk usage" "$([[ "$disk_percent" -ge "$warn_percent" ]] && echo WARN || echo OK)" "${disk_percent}% used; warn at ${warn_percent}%"
  ui_next "$(toolkit_cmd backup-retention-plan)" "$(toolkit_cmd cleanup-old-backups-dry-run)"
  ui_box_end
}

cleanup_old_backups() {
  require_sudo
  require_site_environment >/dev/null || return 1
  local mode="${1:-prompt}" keep candidates count disk_before disk_after prefix db_file public_file private_file config_file file
  keep="$(backup_retention_keep_count)"
  candidates="$(backup_retention_candidate_sets 2>/dev/null || true)"
  count="$(printf '%s\n' "$candidates" | sed '/^$/d' | wc -l | awk '{print $1+0}')"
  disk_before="$($SUDO du -sh "$(site_backup_dir)" 2>/dev/null | awk '{print $1}' || echo unknown)"

  ui_box_start "$([[ "$mode" == dry-run ]] && echo "Backup Cleanup Dry Run" || echo "Cleanup Old Backups")"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Retention" "INFO" "keep latest ${keep} complete backup set(s)"
  status_line "Candidates" "$([[ "$count" -gt 0 ]] && echo WARN || echo OK)" "${count} old complete set(s)"
  status_line "Current backup size" "INFO" "$disk_before"

  if [[ "$count" -eq 0 ]]; then
    echo
    echo "No cleanup needed. Current complete backup count is within retention."
    ui_next "$(toolkit_cmd backup-retention-status)"
    ui_box_end
    return 0
  fi

  echo
  echo "Old complete backup sets selected by retention:"
  while IFS='|' read -r _mtime prefix db_file public_file private_file config_file; do
    [[ -n "$prefix" ]] || continue
    echo "  - $prefix"
  done <<<"$candidates"

  if [[ "$mode" == "dry-run" ]]; then
    echo
    echo "Dry run only. No files were deleted."
    ui_next "$(toolkit_cmd cleanup-old-backups)" "$(toolkit_cmd backup-retention-status)"
    ui_box_end
    return 0
  fi

  echo
  echo "This will permanently delete the old complete backup set(s) listed above."
  echo "Make sure an off-VM backup copy exists before cleanup."
  if ! confirm "Delete old backup files now?"; then
    warn "Backup cleanup cancelled."
    ui_box_end
    return 0
  fi

  while IFS='|' read -r _mtime prefix db_file public_file private_file config_file; do
    [[ -n "$prefix" ]] || continue
    for file in "$db_file" "$public_file" "$private_file" "$config_file"; do
      if [[ -f "$file" ]]; then
        $SUDO rm -f -- "$file"
      fi
    done
  done <<<"$candidates"

  disk_after="$($SUDO du -sh "$(site_backup_dir)" 2>/dev/null | awk '{print $1}' || echo unknown)"
  echo
  status_line "Deleted sets" "OK" "$count"
  status_line "Backup size before" "INFO" "$disk_before"
  status_line "Backup size after" "INFO" "$disk_after"
  ui_next "$(toolkit_cmd backup-retention-status)" "$(toolkit_cmd backup-verify)"
  ui_box_end
}

disable_backup_schedule() {
  require_sudo
  local timer_known=0 service_known=0 timer_enabled_before="unknown" timer_active_before="unknown"

  systemctl cat "$BACKUP_SCHEDULE_TIMER" >/dev/null 2>&1 && timer_known=1
  systemctl cat "$BACKUP_SCHEDULE_SERVICE" >/dev/null 2>&1 && service_known=1
  systemctl is-enabled "$BACKUP_SCHEDULE_TIMER" >/dev/null 2>&1 && timer_enabled_before="enabled" || timer_enabled_before="disabled/not-installed"
  systemctl is-active "$BACKUP_SCHEDULE_TIMER" >/dev/null 2>&1 && timer_active_before="active" || timer_active_before="inactive/not-installed"

  ui_box_start "Disable Scheduled Backups"
  status_line "Timer" "INFO" "$BACKUP_SCHEDULE_TIMER"
  status_line "Timer unit" "$([[ "$timer_known" -eq 1 ]] && echo OK || echo INFO)" "$([[ "$timer_known" -eq 1 ]] && echo present || echo not installed/configured)"
  status_line "Service unit" "$([[ "$service_known" -eq 1 ]] && echo OK || echo INFO)" "$([[ "$service_known" -eq 1 ]] && echo present || echo not installed/configured)"
  status_line "Timer enabled" "INFO" "$timer_enabled_before"
  status_line "Timer active" "INFO" "$timer_active_before"
  echo
  echo "This stops and disables the local VM backup timer."
  echo "Existing backup files are not deleted."

  if [[ "$timer_known" -ne 1 && "$service_known" -ne 1 ]]; then
    echo
    status_line "Scheduled backups" "INFO" "nothing to disable; schedule is not configured"
    ui_next "$(toolkit_cmd configure-backup-schedule)" "$(toolkit_cmd backup-schedule-status)"
    ui_box_end
    return 0
  fi

  if ! confirm "Disable scheduled local backups now?"; then
    warn "Scheduled backup disable skipped."
    ui_box_end
    return 0
  fi

  $SUDO systemctl disable --now "$BACKUP_SCHEDULE_TIMER" >/dev/null 2>&1 || true
  $SUDO systemctl daemon-reload >/dev/null 2>&1 || true

  if systemctl is-enabled "$BACKUP_SCHEDULE_TIMER" >/dev/null 2>&1 || systemctl is-active "$BACKUP_SCHEDULE_TIMER" >/dev/null 2>&1; then
    status_line "Scheduled backups" "WARN" "disable command ran, but timer may still be enabled/active"
  else
    status_line "Scheduled backups" "OK" "timer disabled"
  fi
  ui_next "$(toolkit_cmd backup-schedule-status)" "$(toolkit_cmd configure-backup-schedule)"
  ui_box_end
}

show_restore_preflight() {
  require_sudo
  ui_box_start "Restore Preflight"
  status_line "Mode" "INFO" "check only; no restore is performed"
  status_line "Site" "INFO" "$SITE_NAME"
  if verify_latest_backup_set; then
    echo
    status_line "Preflight" "OK" "latest backup files are readable"
  else
    echo
    status_line "Preflight" "WARN" "backup verification did not fully pass"
  fi
  echo
  echo "Restore safety rules:"
  echo "  - Rehearse restore on a disposable VM first."
  echo "  - Take a cloud snapshot before any live restore."
  echo "  - Use restore-full only when you intentionally want database + files restored."
  ui_next "$(toolkit_cmd restore-rehearsal-guide)" "$(toolkit_cmd restore-full)"
  ui_box_end
}

off_vm_backup_load_config() {
  local value
  if [[ -z "${OFF_VM_BACKUP_TARGET:-}" ]]; then
    if value="$(read_config_key_from_file "$OFF_VM_BACKUP_CONFIG_FILE" OFF_VM_BACKUP_TARGET 2>/dev/null)" && [[ -n "$value" ]]; then
      OFF_VM_BACKUP_TARGET="$value"
    fi
  fi
  if [[ -z "${OFF_VM_BACKUP_SSH_IDENTITY:-}" ]]; then
    if value="$(read_config_key_from_file "$OFF_VM_BACKUP_CONFIG_FILE" OFF_VM_BACKUP_SSH_IDENTITY 2>/dev/null)" && [[ -n "$value" ]]; then
      OFF_VM_BACKUP_SSH_IDENTITY="$value"
    fi
  fi
  if value="$(read_config_key_from_file "$OFF_VM_BACKUP_CONFIG_FILE" OFF_VM_BACKUP_RSYNC_DELETE 2>/dev/null)" && [[ -n "$value" && "${OFF_VM_BACKUP_RSYNC_DELETE}" == "false" ]]; then
    OFF_VM_BACKUP_RSYNC_DELETE="$value"
  fi
  if value="$(read_config_key_from_file "$OFF_VM_BACKUP_CONFIG_FILE" OFF_VM_STRICT_HOST_KEY 2>/dev/null)" && [[ -n "$value" ]]; then
    OFF_VM_STRICT_HOST_KEY="$value"
  fi
  if value="$(read_config_key_from_file "$OFF_VM_BACKUP_CONFIG_FILE" OFF_VM_KNOWN_HOSTS_FILE 2>/dev/null)" && [[ -n "$value" ]]; then
    OFF_VM_KNOWN_HOSTS_FILE="$value"
  fi
  : "${OFF_VM_KNOWN_HOSTS_FILE:=/etc/erpnext-dev/off-vm-known_hosts}"
  : "${OFF_VM_STRICT_HOST_KEY:=false}"
}

off_vm_strict_host_key_enabled() {
  off_vm_backup_load_config
  case "${OFF_VM_STRICT_HOST_KEY,,}" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

# Host portion of user@host:/path (default SSH port).
# Usage: off_vm_backup_target_host "user@host:/path"
off_vm_backup_target_host() {
  local target="$1" host
  validate_off_vm_backup_target "$target" || return 1
  host="${target%%:*}"
  host="${host##*@}"
  [[ -n "$host" && "$host" != *[[:space:]]* ]] || return 1
  printf '%s\n' "$host"
}

# Append BatchMode / ConnectTimeout / known_hosts / StrictHostKeyChecking to a nameref array.
off_vm_append_ssh_security_opts() {
  local -n __ssh_opts="$1"
  local known="${OFF_VM_KNOWN_HOSTS_FILE:-/etc/erpnext-dev/off-vm-known_hosts}"
  __ssh_opts+=(-o BatchMode=yes -o ConnectTimeout=15)
  __ssh_opts+=(-o "UserKnownHostsFile=${known}")
  __ssh_opts+=(-o GlobalKnownHostsFile=/dev/null)
  if off_vm_strict_host_key_enabled; then
    __ssh_opts+=(-o StrictHostKeyChecking=yes)
  else
    __ssh_opts+=(-o StrictHostKeyChecking=accept-new)
  fi
}

off_vm_backup_write_config_file() {
  local config_dir
  require_sudo
  off_vm_backup_load_config
  config_dir="$(dirname "$OFF_VM_BACKUP_CONFIG_FILE")"
  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$OFF_VM_BACKUP_CONFIG_FILE" >/dev/null <<EOF_OFF_VM_CONFIG
# ERPNext Developer Toolkit off-VM backup configuration
# Non-secret settings only. Use SSH keys/agent for authentication.
OFF_VM_BACKUP_TARGET=${OFF_VM_BACKUP_TARGET:-}
OFF_VM_BACKUP_SSH_IDENTITY=${OFF_VM_BACKUP_SSH_IDENTITY:-}
OFF_VM_BACKUP_RSYNC_DELETE=${OFF_VM_BACKUP_RSYNC_DELETE:-false}
OFF_VM_STRICT_HOST_KEY=${OFF_VM_STRICT_HOST_KEY:-false}
OFF_VM_KNOWN_HOSTS_FILE=${OFF_VM_KNOWN_HOSTS_FILE:-/etc/erpnext-dev/off-vm-known_hosts}
SITE_NAME=${SITE_NAME}
EOF_OFF_VM_CONFIG
  $SUDO chown root:root "$OFF_VM_BACKUP_CONFIG_FILE" || true
  $SUDO chmod 600 "$OFF_VM_BACKUP_CONFIG_FILE" || true
}

validate_off_vm_backup_target() {
  local target="$1"
  [[ -n "$target" ]] || return 1
  [[ "$target" == *:* ]] || return 1
  [[ "$target" != *[[:space:]]* ]] || return 1
  [[ "$target" != *"'"* ]] || return 1
  [[ "$target" != -* ]] || return 1
  case "$target" in
    *example-backup-server* | *example.com* | backup@*)
      # Reject documentation placeholders so users do not save/test the example target.
      [[ "$target" != *example-backup-server* && "$target" != *example.com* ]] || return 1
      ;;
  esac
  return 0
}

off_vm_backup_ssh_command_string() {
  local ssh_cmd=() identity="${OFF_VM_BACKUP_SSH_IDENTITY:-}"
  off_vm_backup_load_config
  ssh_cmd=(ssh)
  off_vm_append_ssh_security_opts ssh_cmd
  if [[ -n "$identity" ]]; then
    [[ "$identity" != *[[:space:]]* ]] || fail "SSH identity file path must not contain spaces: $identity"
    [[ -r "$identity" ]] || fail "SSH identity file is not readable: $identity"
    ssh_cmd+=(-i "$identity")
  fi
  local IFS=' '
  printf '%s' "${ssh_cmd[*]}"
}

# Capture the configured off-VM host key into /etc/erpnext-dev/off-vm-known_hosts.
off_vm_trust_host_key() {
  require_sudo
  local host known tmp scan
  off_vm_backup_load_config
  host="$(off_vm_backup_target_host "${OFF_VM_BACKUP_TARGET:-}")" || fail "Configure an off-VM target first: $(toolkit_cmd configure-rsync-backup-target)"
  known="${OFF_VM_KNOWN_HOSTS_FILE}"
  command -v ssh-keyscan >/dev/null 2>&1 || fail "ssh-keyscan is required (install openssh-client)."
  ui_box_start "Trust Off-VM Host Key"
  status_line "Host" "INFO" "$host"
  status_line "Known hosts file" "INFO" "$known"
  tmp="$(mktemp /tmp/erpnext-dev-offvm-keyscan.XXXXXX)"
  if ! scan="$(ssh-keyscan -T 5 -H "$host" 2>/dev/null)" || [[ -z "$scan" ]]; then
    rm -f "$tmp"
    fail "Could not fetch host keys for ${host}. Check network/DNS/firewall, then retry."
  fi
  printf '%s\n' "$scan" >"$tmp"
  $SUDO mkdir -p "$(dirname "$known")"
  if [[ -f "$known" ]]; then
    $SUDO cat "$known" "$tmp" | $SUDO tee "${known}.new" >/dev/null
    $SUDO mv "${known}.new" "$known"
  else
    $SUDO cp "$tmp" "$known"
  fi
  rm -f "$tmp"
  $SUDO chown root:root "$known" || true
  $SUDO chmod 600 "$known" || true
  status_line "Host key" "OK" "stored for ${host}"
  ui_next "$(toolkit_cmd off-vm-verify-host-key)" "$(toolkit_cmd off-vm-strict-host-key-enable)"
  ui_box_end
}

# Verify SSH can authenticate to the off-VM host under current host-key policy.
off_vm_verify_host_key() {
  require_sudo
  local host ssh_cmd_str rc
  off_vm_backup_load_config
  host="$(off_vm_backup_target_host "${OFF_VM_BACKUP_TARGET:-}")" || fail "Configure an off-VM target first: $(toolkit_cmd configure-rsync-backup-target)"
  ui_box_start "Verify Off-VM Host Key"
  status_line "Host" "INFO" "$host"
  status_line "Strict mode" "INFO" "$(off_vm_strict_host_key_enabled && echo enabled || echo accept-new)"
  status_line "Known hosts" "INFO" "${OFF_VM_KNOWN_HOSTS_FILE}"
  ssh_cmd_str="$(off_vm_backup_ssh_command_string)"
  # Probe with a no-op remote command; auth failures still prove host-key handling.
  set +e
  # shellcheck disable=SC2086
  $SUDO $ssh_cmd_str "$host" true >/tmp/erpnext-dev-offvm-verify.out 2>&1
  rc=$?
  set -e
  if ((rc == 0)); then
    status_line "SSH probe" "OK" "host key and auth accepted"
  else
    status_line "SSH probe" "WARN" "exit ${rc} (host key mismatch, missing trust, or auth). See /tmp/erpnext-dev-offvm-verify.out"
    if off_vm_strict_host_key_enabled; then
      warn "Strict mode is on. Re-run $(toolkit_cmd off-vm-trust-host-key) after confirming the server was rebuilt intentionally."
    else
      warn "Try $(toolkit_cmd off-vm-trust-host-key) then re-verify."
    fi
  fi
  ui_next "$(toolkit_cmd off-vm-backup-dry-run)" "$(toolkit_cmd off-vm-strict-host-key-enable)"
  ui_box_end
  return 0
}

off_vm_strict_host_key_enable() {
  require_sudo
  local known host
  off_vm_backup_load_config
  host="$(off_vm_backup_target_host "${OFF_VM_BACKUP_TARGET:-}")" || fail "Configure an off-VM target first: $(toolkit_cmd configure-rsync-backup-target)"
  known="${OFF_VM_KNOWN_HOSTS_FILE}"
  [[ -s "$known" ]] || fail "Known hosts file is empty. Run $(toolkit_cmd off-vm-trust-host-key) first (${known})."
  ui_box_start "Enable Strict Off-VM Host Key Checking"
  status_line "Host" "INFO" "$host"
  status_line "Known hosts" "INFO" "$known"
  OFF_VM_STRICT_HOST_KEY=true
  off_vm_backup_write_config_file
  status_line "Strict mode" "OK" "enabled (StrictHostKeyChecking=yes)"
  echo
  echo "SSH/rsync will use UserKnownHostsFile=${known} and reject unknown hosts."
  ui_next "$(toolkit_cmd off-vm-verify-host-key)" "$(toolkit_cmd off-vm-backup-dry-run)"
  ui_box_end
}

off_vm_strict_host_key_disable() {
  require_sudo
  off_vm_backup_load_config
  ui_box_start "Disable Strict Off-VM Host Key Checking"
  OFF_VM_STRICT_HOST_KEY=false
  off_vm_backup_write_config_file
  status_line "Strict mode" "OK" "disabled (accept-new for first setup convenience)"
  echo "Production VMs should re-enable with $(toolkit_cmd off-vm-strict-host-key-enable)."
  ui_box_end
}

off_vm_backup_target_display() {
  off_vm_backup_load_config
  if [[ -n "${OFF_VM_BACKUP_TARGET:-}" ]]; then
    printf '%s\n' "$OFF_VM_BACKUP_TARGET"
  else
    printf '%s\n' "not configured"
  fi
}

off_vm_backup_configured() {
  off_vm_backup_load_config
  validate_off_vm_backup_target "${OFF_VM_BACKUP_TARGET:-}"
}

off_vm_backup_last_state() {
  local key="$1" value=""
  if value="$(read_config_key_from_file "$OFF_VM_BACKUP_STATE_FILE" "$key" 2>/dev/null)" && [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}

off_vm_backup_write_state() {
  local status="$1" detail="$2" now config_dir
  require_sudo
  now="$(date -Is 2>/dev/null || date)"
  config_dir="$(dirname "$OFF_VM_BACKUP_STATE_FILE")"
  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$OFF_VM_BACKUP_STATE_FILE" >/dev/null <<EOF_OFF_VM_STATE
LAST_RUN_AT=${now}
LAST_STATUS=${status}
LAST_DETAIL=${detail}
LAST_TARGET=${OFF_VM_BACKUP_TARGET:-}
SITE_NAME=${SITE_NAME}
EOF_OFF_VM_STATE
  $SUDO chown root:root "$OFF_VM_BACKUP_STATE_FILE" || true
  $SUDO chmod 600 "$OFF_VM_BACKUP_STATE_FILE" || true
}

off_vm_backup_ensure_rsync() {
  if command -v rsync >/dev/null 2>&1; then
    return 0
  fi
  log "Installing rsync"
  $SUDO apt-get update
  $SUDO apt-get install -y rsync
}

off_vm_backup_default_identity() {
  if [[ -n "${OFF_VM_BACKUP_SSH_IDENTITY:-}" ]]; then
    printf '%s\n' "$OFF_VM_BACKUP_SSH_IDENTITY"
  else
    printf '%s\n' "$OFF_VM_BACKUP_DEFAULT_IDENTITY"
  fi
}

generate_off_vm_backup_key() {
  require_sudo
  local key_path key_dir comment pub_file
  require_site_environment >/dev/null || true
  key_path="$(off_vm_backup_default_identity)"
  key_dir="$(dirname "$key_path")"
  pub_file="${key_path}.pub"
  comment="erpnext-offvm-backup-${SITE_NAME}"

  ui_box_start "Generate Off-VM Backup SSH Key"
  status_line "Purpose" "INFO" "dedicated key for rsync backup from this ERPNext VM"
  status_line "Private key" "INFO" "$key_path"
  status_line "Public key" "INFO" "$pub_file"
  echo
  echo "This key is used by the ERPNext VM to push backup files to the backup server."
  echo "Do not copy the private key to the backup server. Only copy the public key."
  echo

  $SUDO mkdir -p "$key_dir"
  $SUDO chmod 700 "$key_dir" || true
  if [[ -f "$key_path" && -f "$pub_file" ]]; then
    status_line "SSH key" "OK" "already exists"
  else
    if [[ -f "$key_path" || -f "$pub_file" ]]; then
      fail "Partial key exists at ${key_path}. Move it aside or set OFF_VM_BACKUP_SSH_IDENTITY to another path."
    fi
    log "Generating dedicated off-VM backup SSH key"
    $SUDO ssh-keygen -t ed25519 -f "$key_path" -C "$comment" -N ""
    $SUDO chmod 600 "$key_path" || true
    $SUDO chmod 644 "$pub_file" || true
    status_line "SSH key" "OK" "generated"
  fi

  echo
  echo "Public key to paste into the backup server setup command:"
  echo "------------------------------------------------------------"
  $SUDO cat "$pub_file"
  echo "------------------------------------------------------------"
  echo
  echo "Next on the backup server, run:"
  echo "  sudo erpnext-dev backup-server-setup"
  echo
  echo "Or bootstrap it directly from GitHub on the backup server:"
  echo "  sudo apt-get update && sudo apt-get install -y curl ca-certificates"
  echo "  VERSION=\"v${SCRIPT_VERSION}\"; curl -fsSLO \"https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/\${VERSION}/erpnext-dev.sh\"; curl -fsSLO \"https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/\${VERSION}/SHA256SUMS\"; sha256sum -c SHA256SUMS; chmod +x erpnext-dev.sh; sudo ./erpnext-dev.sh backup-server-setup"
  ui_next "$(toolkit_cmd backup-server-setup) on the backup server" "$(toolkit_cmd off-vm-backup-guided-setup) on this ERPNext VM"
  ui_box_end
}

restore_backup_default_identity() {
  printf '%s\n' "${RESTORE_BACKUP_SSH_IDENTITY:-/root/.ssh/erpnext_restore_backup}"
}

detect_outbound_public_ipv4() {
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip="$(curl -fsS4 --max-time 6 https://api.ipify.org 2>/dev/null || true)"
    if ! valid_ipv4_address "$ip" 2>/dev/null; then
      ip="$(curl -fsS4 --max-time 6 https://ifconfig.me 2>/dev/null || true)"
    fi
  fi
  if valid_ipv4_address "$ip" 2>/dev/null; then
    printf '%s\n' "$ip"
    return 0
  fi
  return 1
}

generate_restore_backup_key() {
  require_sudo
  local key_path key_dir pub_file comment public_key public_ip cmd
  require_site_environment >/dev/null || true
  key_path="$(restore_backup_default_identity)"
  key_dir="$(dirname "$key_path")"
  pub_file="${key_path}.pub"
  comment="erpnext-restore-backup-${SITE_NAME}"

  ui_box_start "Generate Restore Rehearsal SSH Key"
  status_line "Purpose" "INFO" "temporary key for a disposable restore VM to pull off-VM backups"
  status_line "Private key" "INFO" "$key_path"
  status_line "Public key" "INFO" "$pub_file"
  echo
  echo "Run this on the restore VM. Do not run it on the backup server."
  echo "Only the public key is copied to the backup server. The private key stays on this restore VM."
  echo

  $SUDO mkdir -p "$key_dir"
  $SUDO chmod 700 "$key_dir" || true
  if [[ -f "$key_path" && -f "$pub_file" ]]; then
    status_line "SSH key" "OK" "already exists"
  else
    if [[ -f "$key_path" || -f "$pub_file" ]]; then
      fail "Partial restore key exists at ${key_path}. Move it aside or set RESTORE_BACKUP_SSH_IDENTITY to another path."
    fi
    log "Generating temporary restore rehearsal SSH key"
    $SUDO ssh-keygen -t ed25519 -f "$key_path" -C "$comment" -N ""
    $SUDO chmod 600 "$key_path" || true
    $SUDO chmod 644 "$pub_file" || true
    status_line "SSH key" "OK" "generated"
  fi

  public_key="$($SUDO cat "$pub_file")"
  public_ip="$(detect_outbound_public_ipv4 2>/dev/null || true)"
  status_line "Detected outbound IPv4" "$([[ -n "$public_ip" ]] && echo OK || echo WARN)" "${public_ip:-not detected; enter it manually on backup server}"

  echo
  echo "Public key:"
  echo "------------------------------------------------------------"
  printf '%s\n' "$public_key"
  echo "------------------------------------------------------------"
  echo
  echo "Next command to run on the backup server:"
  if [[ -n "$public_ip" ]]; then
    cmd="sudo RESTORE_SOURCE_IP='${public_ip}' RESTORE_SITE_NAME='${SITE_NAME}' RESTORE_PUBLIC_KEY='${public_key}' erpnext-dev backup-server-add-restore-key"
    echo "  ${cmd}"
  else
    echo "  sudo erpnext-dev backup-server-add-restore-key"
  fi
  echo
  echo "After the key is added on the backup server, return to this restore VM and run:"
  echo "  sudo erpnext-dev pull-off-vm-backup"
  ui_box_end
}

backup_server_authorized_keys_file() {
  local backup_user="${1:-${RESTORE_AUTHORIZED_KEYS_USER:-erpbackup}}"
  printf '%s\n' "/home/${backup_user}/.ssh/authorized_keys"
}

backup_server_list_restore_keys() {
  require_sudo
  local backup_user auth_file
  backup_user="${BACKUP_SERVER_USER:-${RESTORE_AUTHORIZED_KEYS_USER:-erpbackup}}"
  auth_file="$(backup_server_authorized_keys_file "$backup_user")"
  ui_box_start "Backup Server Restore Keys"
  status_line "Backup user" "INFO" "$backup_user"
  status_line "Authorized keys" "$($SUDO test -f "$auth_file" && echo OK || echo WARN)" "$auth_file"
  echo
  if $SUDO test -f "$auth_file"; then
    echo "Marked restore rehearsal keys:"
    $SUDO grep -n "erpnext-dev restore rehearsal key start" "$auth_file" 2>/dev/null || echo "  none"
    echo
    echo "Sanitized authorized_keys overview:"
    $SUDO nl -ba "$auth_file" 2>/dev/null | sed -E 's/(ssh-(ed25519|rsa) )[A-Za-z0-9+\/=]+/\1[REDACTED]/' || true
  else
    echo "No authorized_keys file found."
  fi
  ui_box_end
}

backup_server_add_restore_key() {
  require_sudo
  local backup_user ssh_dir auth_file source_ip site_name public_key opts key_line start_marker end_marker answer_backup_user answer_source_ip answer_site_name
  backup_user="${BACKUP_SERVER_USER:-${RESTORE_AUTHORIZED_KEYS_USER:-erpbackup}}"
  source_ip="${RESTORE_SOURCE_IP:-}"
  site_name="${RESTORE_SITE_NAME:-${SITE_NAME}}"
  public_key="${RESTORE_PUBLIC_KEY:-}"

  ui_box_start "Add Temporary Restore Key"
  echo "Run this on the backup server. It adds a temporary restore-VM key to ${backup_user}'s authorized_keys."
  echo "The key is restricted with from=, no forwarding, and no pseudo-terminal."
  echo

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Backup Linux user [${backup_user}]: " answer_backup_user
    backup_user="${answer_backup_user:-$backup_user}"
    read -r -p "Restore VM outbound public IPv4 [${source_ip}]: " answer_source_ip
    source_ip="${answer_source_ip:-$source_ip}"
    read -r -p "Site/domain label [${site_name}]: " answer_site_name
    site_name="${answer_site_name:-$site_name}"
    if [[ -z "$public_key" ]]; then
      echo "Paste the restore VM public key from 'sudo erpnext-dev restore-key-setup'."
      read -r -p "Restore public key: " public_key
    fi
  fi

  safe_backup_username "$backup_user" || fail "Invalid backup user: ${backup_user}."
  valid_ipv4_address "$source_ip" || fail "Restore VM public IPv4 is required. Example: 68.144.3.13"
  [[ -n "$site_name" && "$site_name" != *[[:space:]]* ]] || fail "Site/domain label is required. Example: erp.flowmaya.com"
  [[ "$public_key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)[[:space:]]+ ]] || fail "Restore public key does not look like an OpenSSH public key."

  if ! id "$backup_user" >/dev/null 2>&1; then
    fail "Backup user does not exist: ${backup_user}. Run backup-server-setup first."
  fi

  ssh_dir="/home/${backup_user}/.ssh"
  auth_file="$(backup_server_authorized_keys_file "$backup_user")"
  $SUDO mkdir -p "$ssh_dir"
  $SUDO chown -R "${backup_user}:${backup_user}" "$ssh_dir"
  $SUDO chmod 700 "$ssh_dir"
  $SUDO touch "$auth_file"
  $SUDO sed -i '/PASTE_PUBLIC_KEY_HERE/d' "$auth_file" 2>/dev/null || true

  if $SUDO grep -Fq -- "$public_key" "$auth_file" 2>/dev/null; then
    status_line "Restore key" "OK" "already present"
  else
    opts="from=\"${source_ip}\",no-agent-forwarding,no-X11-forwarding,no-port-forwarding,no-pty"
    key_line="${opts} ${public_key}"
    start_marker="# erpnext-dev restore rehearsal key start: ${site_name} ${source_ip}"
    end_marker="# erpnext-dev restore rehearsal key end: ${site_name} ${source_ip}"
    {
      printf '%s\n' "$start_marker"
      printf '%s\n' "$key_line"
      printf '%s\n' "$end_marker"
    } | $SUDO tee -a "$auth_file" >/dev/null
    status_line "Restore key" "OK" "installed"
  fi
  $SUDO chown "${backup_user}:${backup_user}" "$auth_file"
  $SUDO chmod 600 "$auth_file"

  status_line "Restricted source" "OK" "$source_ip"
  status_line "Authorized keys" "OK" "$auth_file"
  echo
  echo "Next on the restore VM, test access and pull backups:"
  echo "  sudo erpnext-dev pull-off-vm-backup"
  echo
  echo "After restore validation, remove the temporary key with:"
  echo "  sudo RESTORE_SOURCE_IP='${source_ip}' RESTORE_SITE_NAME='${site_name}' erpnext-dev backup-server-remove-restore-key"
  ui_box_end
}

backup_server_remove_restore_key() {
  require_sudo
  local backup_user auth_file source_ip site_name tmp_file rc answer_site_name answer_source_ip
  backup_user="${BACKUP_SERVER_USER:-${RESTORE_AUTHORIZED_KEYS_USER:-erpbackup}}"
  source_ip="${RESTORE_SOURCE_IP:-}"
  site_name="${RESTORE_SITE_NAME:-}"
  auth_file="$(backup_server_authorized_keys_file "$backup_user")"

  ui_box_start "Remove Temporary Restore Key"
  status_line "Backup user" "INFO" "$backup_user"
  status_line "Authorized keys" "$($SUDO test -f "$auth_file" && echo OK || echo WARN)" "$auth_file"
  echo
  if ! $SUDO test -f "$auth_file"; then
    ui_box_end
    return 0
  fi

  echo "Existing marked restore rehearsal keys:"
  $SUDO grep -n "erpnext-dev restore rehearsal key start" "$auth_file" 2>/dev/null || echo "  none"
  echo

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Site/domain label to remove [${site_name:-all sites matching IP}]: " answer_site_name
    site_name="${answer_site_name:-$site_name}"
    read -r -p "Restore VM public IPv4 to remove [${source_ip}]: " answer_source_ip
    source_ip="${answer_source_ip:-$source_ip}"
  fi
  [[ -n "$source_ip" || -n "$site_name" ]] || fail "Provide RESTORE_SOURCE_IP and/or RESTORE_SITE_NAME so the correct temporary key can be removed."
  if [[ -n "$source_ip" ]]; then
    valid_ipv4_address "$source_ip" || fail "Invalid IPv4: ${source_ip}"
  fi
  confirm "Remove matching temporary restore key block(s) now?" || return 0

  tmp_file="$(mktemp /tmp/erpnext-dev-authkeys.XXXXXX)"
  set +e
  $SUDO awk -v site="$site_name" -v ip="$source_ip" '
    BEGIN { skip=0; removed=0 }
    /^# erpnext-dev restore rehearsal key start:/ {
      line=$0
      if ((site == "" || index(line, site) > 0) && (ip == "" || index(line, ip) > 0)) { skip=1; removed=1; next }
    }
    skip && /^# erpnext-dev restore rehearsal key end:/ { skip=0; next }
    !skip { print }
    END { if (removed == 0) exit 2 }
  ' "$auth_file" >"$tmp_file"
  rc=$?
  set -e
  if [[ "$rc" -eq 2 ]]; then
    rm -f "$tmp_file"
    warn "No matching marked restore key block was found."
    ui_box_end
    return 0
  elif [[ "$rc" -ne 0 ]]; then
    rm -f "$tmp_file"
    fail "Failed to process authorized_keys."
  fi
  $SUDO cp "$tmp_file" "$auth_file"
  rm -f "$tmp_file"
  $SUDO chown "${backup_user}:${backup_user}" "$auth_file"
  $SUDO chmod 600 "$auth_file"
  status_line "Restore key cleanup" "OK" "matching temporary key block(s) removed"
  ui_box_end
}

restore_clean_vm_preflight() {
  require_sudo
  local cpu_count mem_mb disk_gb conflict_lines vm_ip
  cpu_count="$(nproc 2>/dev/null || echo 0)"
  mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  disk_gb="$(df -BG / 2>/dev/null | awk 'NR==2 {gsub("G", "", $4); print $4+0}' || echo 0)"
  vm_ip="$(get_vm_ip 2>/dev/null || true)"
  conflict_lines="$(systemctl list-units --type=service --state=running 2>/dev/null | grep -Ei 'docker|containerd|kube|calico|microk8s' || true)"

  ui_box_start "Restore VM Preflight"
  status_line "Role" "INFO" "disposable local/cloud restore VM"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "VM IP" "INFO" "${vm_ip:-unknown}"
  status_line "CPU" "$([[ "$cpu_count" -ge 4 ]] && echo OK || echo WARN)" "${cpu_count} core(s); 4 preferred"
  status_line "RAM" "$([[ "$mem_mb" -ge 8192 ]] && echo OK || echo WARN)" "${mem_mb} MB; 8192 MB preferred"
  status_line "Root free space" "$([[ "$disk_gb" -ge 60 ]] && echo OK || echo WARN)" "${disk_gb} GB free; 60 GB preferred"
  if [[ -n "$conflict_lines" ]]; then
    status_line "Conflicting services" "WARN" "Docker/Kubernetes/Calico-like services running"
    echo
    echo "$conflict_lines" | sed 's/^/  /'
  else
    status_line "Conflicting services" "OK" "none detected"
  fi
  echo
  echo "Restore rehearsal safety: use only a disposable restore VM, never the first live production VM."
  ui_next "$(toolkit_cmd restore-key-setup)" "$(toolkit_cmd pull-off-vm-backup)" "$(toolkit_cmd restore-full)"
  ui_box_end
}

pull_off_vm_backup_to_restore_vm() {
  require_sudo
  local bench_dir backup_dir target identity target_suggest config_dir answer_target answer_identity
  bench_dir="$(require_site_environment)" || return 1
  backup_dir="$(site_backup_dir)"
  off_vm_backup_load_config || true
  target="${RESTORE_OFF_VM_BACKUP_TARGET:-${OFF_VM_BACKUP_TARGET:-}}"
  identity="${RESTORE_BACKUP_SSH_IDENTITY:-$(restore_backup_default_identity)}"
  target_suggest="${target:-erpbackup@BACKUP_SERVER_IP:/mnt/HC_Volume_ID/erpnext-backups/${SITE_NAME}/}"

  ui_box_start "Pull Off-VM Backup to Restore VM"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Local backup folder" "INFO" "$backup_dir"
  echo
  echo "Run this on the restore VM after the backup server has authorized the restore key."
  echo "Press Enter to accept suggested values shown in brackets."
  echo
  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Off-VM backup target URI [${target_suggest}]: " answer_target
    target="${answer_target:-$target_suggest}"
    read -r -p "Restore SSH identity file [${identity}]: " answer_identity
    identity="${answer_identity:-$identity}"
  fi
  validate_off_vm_backup_target "$target" || fail "Invalid target. Use user@host:/absolute/path/"
  [[ -r "$identity" ]] || fail "Restore SSH identity is not readable: ${identity}. Run restore-key-setup first."

  off_vm_backup_ensure_rsync
  $SUDO mkdir -p "$backup_dir"
  log "Pulling off-VM backups to restore VM"
  local pull_ssh=() pull_ssh_str
  off_vm_backup_load_config
  pull_ssh=(ssh -i "$identity" -o IdentitiesOnly=yes)
  off_vm_append_ssh_security_opts pull_ssh
  local IFS=' '
  pull_ssh_str="${pull_ssh[*]}"
  $SUDO rsync -avz \
    -e "$pull_ssh_str" \
    "${target%/}/" \
    "${backup_dir}/"
  $SUDO chown -R "${FRAPPE_USER}:${FRAPPE_USER}" "$backup_dir" || true

  config_dir="$(dirname "$RESTORE_PULL_CONFIG_FILE")"
  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$RESTORE_PULL_CONFIG_FILE" >/dev/null <<EOF_RESTORE_PULL
# ERPNext Developer Toolkit restore-pull configuration
RESTORE_OFF_VM_BACKUP_TARGET=${target}
RESTORE_BACKUP_SSH_IDENTITY=${identity}
SITE_NAME=${SITE_NAME}
EOF_RESTORE_PULL
  $SUDO chown root:root "$RESTORE_PULL_CONFIG_FILE" || true
  $SUDO chmod 600 "$RESTORE_PULL_CONFIG_FILE" || true

  status_line "Rsync pull" "OK" "completed"
  status_line "Config file" "OK" "$RESTORE_PULL_CONFIG_FILE"
  ui_next "$(toolkit_cmd list-backups)" "$(toolkit_cmd backup-verify)" "$(toolkit_cmd restore-preflight)"
  ui_box_end
}

restore_rehearsal_wizard() {
  require_sudo
  while true; do
    ui_submenu_header "Restore Rehearsal" \
      "Disposable restore VM only — not for first production restore"
    print_two_column_menu \
      "1) Restore VM preflight" \
      "2) Generate restore key" \
      "3) Pull off-VM backup" \
      "4) Verify pulled backup" \
      "5) Restore latest backup set" \
      "6) Post-restore checks" \
      "7) Cleanup reminder"
    ui_submenu_footer
    local restore_choice=""
    menu_read_choice restore_choice
    case "$restore_choice" in
      1)
        restore_clean_vm_preflight
        pause_after_screen "Press Enter to return to Restore Rehearsal..."
        ;;
      2)
        generate_restore_backup_key
        pause_after_screen "Press Enter to return to Restore Rehearsal..."
        ;;
      3)
        pull_off_vm_backup_to_restore_vm
        pause_after_screen "Press Enter to return to Restore Rehearsal..."
        ;;
      4)
        verify_latest_backup_set
        show_restore_preflight
        pause_after_screen "Press Enter to return to Restore Rehearsal..."
        ;;
      5)
        restore_site_full
        pause_after_screen "Press Enter to return to Restore Rehearsal..."
        ;;
      6)
        run_full_status || true
        show_backup_status || true
        pause_after_screen "Press Enter to return to Restore Rehearsal..."
        ;;
      7)
        echo
        echo "After browser/login validation, run this on the backup server:"
        echo "  sudo erpnext-dev backup-server-list-restore-keys"
        echo "  sudo erpnext-dev backup-server-remove-restore-key"
        pause_after_screen "Press Enter to return to Restore Rehearsal..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) menu_invalid_choice "$restore_choice" "type b to go back or q to quit" || true ;;
    esac
  done
}

safe_backup_username() {
  local name="$1"
  [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

normalize_backup_server_dir() {
  local dir="$1"
  [[ -n "$dir" ]] || return 1
  [[ "$dir" == /* ]] || return 1
  [[ "$dir" != *[[:space:]]* ]] || return 1
  [[ "$dir" != *".."* ]] || return 1
  printf '%s\n' "${dir%/}"
}

backup_server_suggested_root() {
  local configured="${1:-}" volume_mount=""
  if [[ -n "$configured" && "$configured" != "/srv/erpnext-backups" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi
  if command -v findmnt >/dev/null 2>&1; then
    volume_mount="$(findmnt -rn -o TARGET 2>/dev/null | awk '/^\/mnt\/HC_Volume_[0-9]+$/ {print; exit}')"
  fi
  if [[ -z "$volume_mount" ]]; then
    local candidate
    for candidate in /mnt/HC_Volume_*; do
      [[ -d "$candidate" ]] || continue
      if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$candidate"; then
        volume_mount="$candidate"
        break
      fi
    done
  fi
  if [[ -n "$volume_mount" ]]; then
    printf '%s\n' "${volume_mount%/}/erpnext-backups"
  else
    printf '%s\n' "/srv/erpnext-backups"
  fi
}

infer_site_name_from_public_key() {
  local key="$1" comment=""
  [[ -n "$key" ]] || return 1
  comment="$(printf '%s\n' "$key" | awk '{print $3}')"
  case "$comment" in
    erpnext-offvm-backup-*)
      printf '%s\n' "${comment#erpnext-offvm-backup-}"
      return 0
      ;;
  esac
  return 1
}

backup_server_setup() {
  require_sudo
  local backup_user backup_root site_name source_ip public_key ssh_dir auth_file target_dir target_uri host_hint key_line opts
  backup_user="${BACKUP_SERVER_USER:-erpbackup}"
  backup_root="${BACKUP_SERVER_ROOT:-/srv/erpnext-backups}"
  backup_root="$(backup_server_suggested_root "$backup_root")"
  site_name="${BACKUP_SITE_NAME:-}"
  source_ip="${BACKUP_SOURCE_IP:-}"
  public_key="${BACKUP_SOURCE_PUBLIC_KEY:-}"

  ui_box_start "Prepare Off-VM Backup Server"
  echo "Run this on the remote backup server, not on the ERPNext application VM."
  echo "It creates a locked-down backup user/folder and optionally installs the ERPNext VM public key."
  echo "Press Enter to accept suggested values shown in brackets."
  echo
  echo "Before continuing, generate/copy the public key on the ERPNext application VM:"
  echo "  sudo erpnext-dev generate-off-vm-backup-key"
  echo "Paste the single ssh-ed25519 public key line here when this wizard asks for it."
  echo
  status_line "Suggested user" "INFO" "$backup_user"
  status_line "Suggested backup root" "INFO" "$backup_root"
  status_line "Site/domain example" "INFO" "erp.flowmaya.com"
  echo

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Do you already have the ERPNext VM public key ready? [Y/n]: " answer_key_ready
    if [[ "$answer_key_ready" =~ ^[Nn]$|^[Nn][Oo]$ ]]; then
      warn "Generate the key on the ERPNext application VM first, then paste only the .pub line here."
      echo "Command to run on ERPNext VM: sudo erpnext-dev generate-off-vm-backup-key"
      echo "You can still continue now to create the user/folder and add the key later."
      echo
    fi
    read -r -p "Backup Linux user [${backup_user}]: " answer_backup_user
    backup_user="${answer_backup_user:-$backup_user}"
    read -r -p "Backup root folder [${backup_root}]: " answer_backup_root
    backup_root="${answer_backup_root:-$backup_root}"
    read -r -p "ERPNext site/domain folder [auto from public key if blank; example erp.flowmaya.com]: " answer_site_name
    site_name="${answer_site_name:-$site_name}"
    read -r -p "Restrict SSH key to ERPNext VM source IP (optional; example 65.109.221.4) [${source_ip}]: " answer_source_ip
    source_ip="${answer_source_ip:-$source_ip}"
    echo
    echo "Paste the ERPNext VM public key from 'sudo erpnext-dev generate-off-vm-backup-key'."
    echo "Leave blank to create the user/folder only and add the key later."
    read -r -p "Public key: " answer_public_key
    public_key="${answer_public_key:-$public_key}"
  fi

  if [[ -z "$site_name" && -n "$public_key" ]]; then
    site_name="$(infer_site_name_from_public_key "$public_key" 2>/dev/null || true)"
    if [[ -n "$site_name" ]]; then
      status_line "Site/domain folder" "OK" "inferred from public key: ${site_name}"
    fi
  fi

  safe_backup_username "$backup_user" || fail "Invalid backup user: ${backup_user}. Use a simple Linux username such as erpbackup."
  backup_root="$(normalize_backup_server_dir "$backup_root")" || fail "Invalid backup root folder: ${backup_root}. Use an absolute path without spaces."
  [[ -n "$site_name" ]] || fail "Site/domain folder is required if no ERPNext public-key comment is available. Example: erp.flowmaya.com"
  [[ "$site_name" != *[[:space:]]* && "$site_name" != *".."* && "$site_name" != /* ]] || fail "Invalid site/domain folder: ${site_name}"
  if [[ -n "$source_ip" ]]; then
    valid_ipv4_address "$source_ip" || warn "Source IP does not look like a plain IPv4 address. Key restriction will not use from= unless valid."
  fi

  status_line "Backup user" "INFO" "$backup_user"
  status_line "Backup folder" "INFO" "${backup_root}/${site_name}"
  status_line "SSH source IP" "$([[ -n "$source_ip" ]] && echo INFO || echo WARN)" "${source_ip:-not restricted by source IP}"
  echo

  log "Installing backup server packages"
  $SUDO apt-get update
  $SUDO apt-get install -y openssh-server rsync

  if id "$backup_user" >/dev/null 2>&1; then
    status_line "Linux user" "OK" "exists: $backup_user"
  else
    log "Creating backup user ${backup_user}"
    # Prefer useradd: Ubuntu 26.04+ adduser can fail via sanitize_string when
    # the caller's HOME contains special filenames (e.g. Actions runner ~/.nvm).
    if command -v useradd >/dev/null 2>&1; then
      $SUDO useradd --create-home --shell /bin/bash --comment "" "$backup_user"
    else
      $SUDO env HOME=/root adduser --disabled-password --gecos "" "$backup_user"
    fi
    $SUDO passwd -l "$backup_user" >/dev/null 2>&1 || true
    status_line "Linux user" "OK" "created: $backup_user"
  fi
  $SUDO passwd -l "$backup_user" >/dev/null 2>&1 || true

  target_dir="${backup_root}/${site_name}"
  $SUDO mkdir -p "$target_dir"
  $SUDO chown -R "${backup_user}:${backup_user}" "$backup_root"
  $SUDO chmod 750 "$backup_root" "$target_dir" || true
  status_line "Backup folder" "OK" "$target_dir"

  ssh_dir="/home/${backup_user}/.ssh"
  auth_file="${ssh_dir}/authorized_keys"
  $SUDO mkdir -p "$ssh_dir"
  $SUDO chown -R "${backup_user}:${backup_user}" "$ssh_dir"
  $SUDO chmod 700 "$ssh_dir"

  if [[ -n "$public_key" ]]; then
    if [[ ! "$public_key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)[[:space:]]+ ]]; then
      fail "The pasted public key does not look like an OpenSSH public key."
    fi
    opts="no-agent-forwarding,no-X11-forwarding,no-port-forwarding,no-pty"
    if valid_ipv4_address "$source_ip" 2>/dev/null; then
      opts="from=\"${source_ip}\",${opts}"
    fi
    key_line="${opts} ${public_key}"
    if $SUDO test -f "$auth_file" && $SUDO grep -Fq -- "$public_key" "$auth_file"; then
      status_line "Authorized key" "OK" "already present"
    else
      printf '%s\n' "$key_line" | $SUDO tee -a "$auth_file" >/dev/null
      status_line "Authorized key" "OK" "installed"
    fi
  else
    status_line "Authorized key" "WARN" "not installed; add the ERPNext VM public key before testing rsync"
  fi
  $SUDO chown "${backup_user}:${backup_user}" "$auth_file" 2>/dev/null || true
  $SUDO chmod 600 "$auth_file" 2>/dev/null || true

  if command -v hostname >/dev/null 2>&1; then
    host_hint="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  host_hint="${host_hint:-BACKUP_SERVER_IP}"
  target_uri="${backup_user}@${host_hint}:${target_dir}/"

  ui_box_start "Backup Server Result Summary"
  status_line "Backup server" "OK" "prepared"
  status_line "Target URI" "INFO" "$target_uri"
  status_line "Delete mode" "INFO" "do not enable rsync --delete for first validation"
  echo
  echo "Next on the ERPNext VM:"
  echo "  sudo erpnext-dev generate-off-vm-backup-key"
  echo "  sudo erpnext-dev configure-rsync-backup-target"
  echo "  sudo erpnext-dev off-vm-backup-dry-run"
  echo "  sudo erpnext-dev run-off-vm-backup"
  echo
  echo "Use this target when prompted:"
  echo "  ${target_uri}"
  ui_box_end
}

off_vm_backup_guided_setup() {
  require_sudo
  require_site_environment >/dev/null || return 1
  local target identity delete_mode config_dir

  ui_box_start "Guided Off-VM Backup Setup"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Local backup folder" "INFO" "$(site_backup_dir)"
  echo
  echo "This guided flow prepares the ERPNext VM side of rsync off-VM backups."
  echo "Use a different server/account as the target. Do not target this same VM."
  ui_box_end

  generate_off_vm_backup_key

  echo
  echo "Prepare the backup server next. On the backup server, run:"
  echo "  sudo apt-get update && sudo apt-get install -y curl ca-certificates"
  echo "  VERSION=\"v${SCRIPT_VERSION}\"; curl -fsSLO \"https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/\${VERSION}/erpnext-dev.sh\"; curl -fsSLO \"https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/\${VERSION}/SHA256SUMS\"; sha256sum -c SHA256SUMS; chmod +x erpnext-dev.sh; sudo ./erpnext-dev.sh backup-server-setup"
  echo
  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    echo "Paste the Target URI printed by backup-server-setup."
    echo "Example: erpbackup@65.109.220.250:/mnt/HC_Volume_106276869/erpnext-backups/${SITE_NAME}/"
    read -r -p "Rsync target URI: " target
    validate_off_vm_backup_target "$target" || fail "Invalid target. Use user@host:/absolute/path/"
    identity="$(off_vm_backup_default_identity)"
    read -r -p "SSH identity file on this ERPNext VM [${identity}]: " answer_identity
    identity="${answer_identity:-$identity}"
    read -r -p "Enable rsync --delete on remote target? [y/N]: " delete_mode
    if [[ "$delete_mode" =~ ^[Yy]$|^[Yy][Ee][Ss]$ ]]; then
      delete_mode="true"
    else
      delete_mode="false"
    fi
  else
    target="${OFF_VM_BACKUP_TARGET:-}"
    validate_off_vm_backup_target "$target" || fail "Set OFF_VM_BACKUP_TARGET=user@host:/path before using --yes."
    identity="$(off_vm_backup_default_identity)"
    delete_mode="${OFF_VM_BACKUP_RSYNC_DELETE:-false}"
  fi

  [[ -r "$identity" ]] || fail "SSH identity file is not readable: $identity"
  OFF_VM_BACKUP_TARGET="$target"
  OFF_VM_BACKUP_SSH_IDENTITY="$identity"
  OFF_VM_BACKUP_RSYNC_DELETE="$delete_mode"
  off_vm_backup_write_config_file

  ui_box_start "Off-VM Backup Configured"
  status_line "Target" "OK" "$OFF_VM_BACKUP_TARGET"
  status_line "SSH key" "OK" "$OFF_VM_BACKUP_SSH_IDENTITY"
  status_line "Delete mode" "INFO" "$OFF_VM_BACKUP_RSYNC_DELETE"
  status_line "Host key mode" "INFO" "$(off_vm_strict_host_key_enabled && echo strict || echo accept-new)"
  echo
  echo "For production: trust the host key, enable strict mode, then dry-run."
  ui_next "$(toolkit_cmd off-vm-trust-host-key)" "$(toolkit_cmd off-vm-backup-dry-run)" "$(toolkit_cmd off-vm-backup-status)"
  ui_box_end
}

run_off_vm_backup_rsync() {
  local mode="$1" backup_dir latest_lines completeness ssh_cmd_str rsync_cmd=()
  require_sudo

  if deployment_engine_is_docker; then
    docker_offvm_rsync "$mode"
    return
  fi

  require_site_environment >/dev/null || return 1
  off_vm_backup_load_config
  validate_off_vm_backup_target "${OFF_VM_BACKUP_TARGET:-}" || fail "Off-VM backup target is not configured or invalid. Run configure-rsync-backup-target first."
  backup_dir="$(site_backup_dir)"
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
  [[ "$completeness" == "complete" ]] || fail "Latest local backup set is not complete. Run backup-files first."
  off_vm_backup_ensure_rsync

  ssh_cmd_str="$(off_vm_backup_ssh_command_string)"

  rsync_cmd=(rsync -az --human-readable --info=stats2 -e "$ssh_cmd_str")
  [[ "$mode" == "dry-run" ]] && rsync_cmd+=(--dry-run)
  if [[ "${OFF_VM_BACKUP_RSYNC_DELETE:-false}" == "true" ]]; then
    rsync_cmd+=(--delete)
  fi
  rsync_cmd+=("${backup_dir}/" "${OFF_VM_BACKUP_TARGET}")

  if [[ "$mode" == "dry-run" ]]; then
    ui_box_start "Off-VM Backup Dry Run"
    status_line "Site" "INFO" "$SITE_NAME"
    status_line "Target" "INFO" "$OFF_VM_BACKUP_TARGET"
    status_line "Source" "INFO" "$backup_dir/"
    status_line "Delete mode" "INFO" "${OFF_VM_BACKUP_RSYNC_DELETE}"
    echo
    echo "Running rsync dry run. No files will be copied or deleted."
  else
    ui_box_start "Run Off-VM Backup"
    status_line "Site" "INFO" "$SITE_NAME"
    status_line "Target" "INFO" "$OFF_VM_BACKUP_TARGET"
    status_line "Source" "INFO" "$backup_dir/"
    status_line "Delete mode" "INFO" "${OFF_VM_BACKUP_RSYNC_DELETE}"
    echo
    echo "This copies local ERPNext backup files to the configured off-VM target."
    echo "It does not remove local backups."
    if ! confirm "Run off-VM rsync backup now?"; then
      warn "Off-VM backup cancelled."
      ui_box_end
      return 0
    fi
  fi

  echo
  log "Starting rsync ${mode}"
  if "${rsync_cmd[@]}"; then
    if [[ "$mode" == "dry-run" ]]; then
      status_line "Dry run" "OK" "rsync dry run completed"
    else
      off_vm_backup_write_state "OK" "rsync completed"
      status_line "Off-VM backup" "OK" "rsync completed"
    fi
  else
    if [[ "$mode" != "dry-run" ]]; then
      off_vm_backup_write_state "FAIL" "rsync failed"
    fi
    status_line "Off-VM backup" "FAIL" "rsync command failed"
  fi
  ui_next "$(toolkit_cmd off-vm-backup-status)" "$(toolkit_cmd production-checklist)"
  ui_box_end
}

# ------------------------------------------------------------
# Object-storage backups (rclone) for the NATIVE engine.
# Mirrors the Docker object-storage flow (lib/docker.sh) but ships local ERPNext
# backup artifacts from the on-VM backup directory to an rclone remote (S3,
# Cloudflare R2, Backblaze B2, GCS, Azure, MinIO, ...). Secrets stay in the
# rclone config; only non-secret coordinates are persisted here.
# ------------------------------------------------------------
object_backup_load_config() {
  local v
  if [[ -z "${OBJECT_RCLONE_REMOTE:-}" ]]; then
    v="$(read_config_key_from_file "$OBJECT_BACKUP_CONFIG_FILE" OBJECT_RCLONE_REMOTE 2>/dev/null || true)"
    [[ -n "$v" ]] && OBJECT_RCLONE_REMOTE="$v"
  fi
  if [[ -z "${OBJECT_BUCKET:-}" ]]; then
    v="$(read_config_key_from_file "$OBJECT_BACKUP_CONFIG_FILE" OBJECT_BUCKET 2>/dev/null || true)"
    [[ -n "$v" ]] && OBJECT_BUCKET="$v"
  fi
  if [[ -z "${OBJECT_PREFIX:-}" ]]; then
    v="$(read_config_key_from_file "$OBJECT_BACKUP_CONFIG_FILE" OBJECT_PREFIX 2>/dev/null || true)"
    [[ -n "$v" ]] && OBJECT_PREFIX="$v"
  fi
}

object_backup_configured() {
  object_backup_load_config
  [[ -n "${OBJECT_RCLONE_REMOTE:-}" && -n "${OBJECT_BUCKET:-}" ]]
}

# Full rclone destination: <remote>:<bucket>/<prefix>/<site>.
object_backup_dest() {
  object_backup_load_config
  local prefix="${OBJECT_PREFIX:-}"
  prefix="${prefix#/}"
  prefix="${prefix%/}"
  if [[ -n "$prefix" ]]; then
    printf '%s:%s/%s/%s\n' "$OBJECT_RCLONE_REMOTE" "$OBJECT_BUCKET" "$prefix" "$SITE_NAME"
  else
    printf '%s:%s/%s\n' "$OBJECT_RCLONE_REMOTE" "$OBJECT_BUCKET" "$SITE_NAME"
  fi
}

object_backup_ensure_rclone() {
  command -v rclone >/dev/null 2>&1 && return 0
  log "Installing rclone"
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -y >/dev/null 2>&1 || true
  $SUDO apt-get install -y rclone >/dev/null 2>&1 || return 1
  command -v rclone >/dev/null 2>&1
}

object_backup_write_state() {
  require_sudo
  local status="$1" detail="$2" now config_dir
  now="$(date -Is 2>/dev/null || date)"
  config_dir="$(dirname "$OBJECT_BACKUP_STATE_FILE")"
  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$OBJECT_BACKUP_STATE_FILE" >/dev/null <<EOF_OBJ_STATE
LAST_RUN_AT=${now}
LAST_STATUS=${status}
LAST_DETAIL=${detail}
LAST_DEST=$(object_backup_dest 2>/dev/null || echo unknown)
SITE_NAME=${SITE_NAME}
EOF_OBJ_STATE
  $SUDO chown root:root "$OBJECT_BACKUP_STATE_FILE" 2>/dev/null || true
  $SUDO chmod 600 "$OBJECT_BACKUP_STATE_FILE" 2>/dev/null || true
}

# One-line object-storage summary (parallels docker_object_backup_status_line).
object_backup_status_line() {
  local last_status last_run
  if object_backup_configured; then
    last_status="$(read_config_key_from_file "$OBJECT_BACKUP_STATE_FILE" LAST_STATUS 2>/dev/null || true)"
    last_run="$(read_config_key_from_file "$OBJECT_BACKUP_STATE_FILE" LAST_RUN_AT 2>/dev/null || true)"
    case "${last_status:-none}" in
      OK) status_line "Object storage" "OK" "$(object_backup_dest); last OK ${last_run:-?}" ;;
      FAIL) status_line "Object storage" "WARN" "$(object_backup_dest); last run FAILED ${last_run:-?}" ;;
      *) status_line "Object storage" "INFO" "$(object_backup_dest); no successful run yet" ;;
    esac
  else
    status_line "Object storage" "WARN" "not configured; run $(toolkit_cmd configure-object-backup)"
  fi
}

configure_object_backup() {
  require_sudo
  local remote bucket prefix config_dir
  require_site_environment >/dev/null || return 1
  object_backup_load_config

  if ! object_backup_ensure_rclone; then
    fail "rclone is required for object-storage backups but could not be installed. Install rclone, then retry."
  fi

  ui_box_start "Configure Object-Storage Backup (rclone)"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Tool" "INFO" "rclone $(rclone version 2>/dev/null | awk 'NR==1{print $2}')"
  echo
  echo "Uses an existing rclone remote. Create one first with:  rclone config"
  echo "(supports S3, Cloudflare R2, Backblaze B2, GCS, Azure, MinIO, and more)."
  echo
  echo "Configured rclone remotes:"
  rclone listremotes 2>/dev/null | sed 's/^/  /' || echo "  (none — run 'rclone config' first)"
  echo

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    read -r -p "rclone remote name (e.g. r2): " remote
    remote="${remote%:}"
    read -r -p "Bucket / container name: " bucket
    read -r -p "Path prefix inside the bucket [erpnext-backups]: " prefix
    prefix="${prefix:-erpnext-backups}"
  else
    remote="${OBJECT_RCLONE_REMOTE:-}"
    bucket="${OBJECT_BUCKET:-}"
    prefix="${OBJECT_PREFIX:-erpnext-backups}"
    [[ -n "$remote" && -n "$bucket" ]] || fail "Set OBJECT_RCLONE_REMOTE and OBJECT_BUCKET before using --yes."
  fi

  [[ -n "$remote" && -n "$bucket" ]] || fail "Remote name and bucket are required."
  if ! rclone listremotes 2>/dev/null | grep -qx "${remote}:"; then
    warn "rclone remote '${remote}:' is not in 'rclone listremotes'. Save anyway; create it with 'rclone config'."
  fi

  config_dir="$(dirname "$OBJECT_BACKUP_CONFIG_FILE")"
  $SUDO mkdir -p "$config_dir"
  $SUDO tee "$OBJECT_BACKUP_CONFIG_FILE" >/dev/null <<EOF_OBJ_CONFIG
# ERPNext Developer Toolkit - native object-storage backup (rclone) configuration
# Non-secret only. rclone credentials live in the rclone config (rclone config).
OBJECT_RCLONE_REMOTE=${remote}
OBJECT_BUCKET=${bucket}
OBJECT_PREFIX=${prefix}
SITE_NAME=${SITE_NAME}
EOF_OBJ_CONFIG
  $SUDO chown root:root "$OBJECT_BACKUP_CONFIG_FILE" 2>/dev/null || true
  $SUDO chmod 600 "$OBJECT_BACKUP_CONFIG_FILE" 2>/dev/null || true
  OBJECT_RCLONE_REMOTE="$remote"
  OBJECT_BUCKET="$bucket"
  OBJECT_PREFIX="$prefix"

  ui_box_start "Object-Storage Backup Configured"
  status_line "Destination" "OK" "$(object_backup_dest)"
  status_line "Config file" "OK" "$OBJECT_BACKUP_CONFIG_FILE"
  ui_next "$(toolkit_cmd object-backup-dry-run)" "$(toolkit_cmd object-backup)"
  ui_box_end
}

# Upload local ERPNext backup artifacts to object storage with rclone.
# mode: dry-run|run. Uploads are checksum-based and verified with rclone check.
run_object_backup() {
  require_sudo
  local mode="${1:-run}" src dest completeness latest_lines
  local -a rclone_cmd=()

  require_site_environment >/dev/null || return 1
  object_backup_load_config
  object_backup_configured || fail "Object storage not configured. Run: $(toolkit_cmd configure-object-backup)"
  object_backup_ensure_rclone || fail "rclone is not available. Install rclone, then retry."
  src="$(site_backup_dir)"
  [[ -d "$src" ]] || fail "No local backup directory at ${src}. Run $(toolkit_cmd backup-files) first."
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
  [[ "$completeness" == "complete" ]] || fail "Latest local backup set is not complete. Run $(toolkit_cmd backup-files) first."
  dest="$(object_backup_dest)"

  ui_box_start "$([[ "$mode" == "dry-run" ]] && echo "Object-Storage Backup Dry Run" || echo "Object-Storage Backup")"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Source" "INFO" "${src}/ (local backup artifacts)"
  status_line "Destination" "INFO" "$dest"
  echo

  rclone_cmd=(rclone copy "$src" "$dest" --checksum --transfers 4 --stats-one-line)
  [[ "$mode" == "dry-run" ]] && rclone_cmd+=(--dry-run)

  if [[ "$mode" != "dry-run" && -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    if ! confirm "Upload local backups to ${dest} now?"; then
      warn "Object-storage backup cancelled."
      ui_box_end
      return 0
    fi
  fi

  log "Starting rclone ${mode}"
  if ${SUDO:-} "${rclone_cmd[@]}"; then
    if [[ "$mode" == "dry-run" ]]; then
      status_line "Dry run" "OK" "rclone dry run completed"
    elif ${SUDO:-} rclone check "$src" "$dest" --one-way --checksum >/dev/null 2>&1; then
      status_line "Remote verify" "OK" "rclone check confirmed all files present"
      object_backup_write_state "OK" "rclone copy + check verified"
      status_line "Object storage" "OK" "uploaded and verified"
    else
      status_line "Remote verify" "WARN" "rclone check reported differences"
      object_backup_write_state "OK" "rclone copy completed; check reported differences"
      status_line "Object storage" "WARN" "uploaded (verify manually with rclone check)"
    fi
  else
    [[ "$mode" != "dry-run" ]] && object_backup_write_state "FAIL" "rclone copy failed"
    status_line "Object storage" "FAIL" "rclone command failed"
  fi
  ui_next "$(toolkit_cmd object-status)" "$(toolkit_cmd off-vm-backup-status)"
  ui_box_end
}

show_object_backup_status() {
  require_sudo
  object_backup_load_config
  ui_box_start "Object-Storage Backup Status"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "rclone" "$(command -v rclone >/dev/null 2>&1 && echo OK || echo WARN)" "$(command -v rclone >/dev/null 2>&1 && rclone version 2>/dev/null | awk 'NR==1{print $2}' || echo 'not installed')"
  status_line "Config file" "$([[ -f "$OBJECT_BACKUP_CONFIG_FILE" ]] && echo OK || echo WARN)" "$OBJECT_BACKUP_CONFIG_FILE"
  if object_backup_configured; then
    status_line "Destination" "OK" "$(object_backup_dest)"
  else
    status_line "Destination" "WARN" "not configured"
  fi
  object_backup_status_line
  ui_next "$(toolkit_cmd object-backup-dry-run)" "$(toolkit_cmd object-backup)"
  ui_box_end
}

# ------------------------------------------------------------
# Engine-agnostic object-storage entry points (native + docker).
# ------------------------------------------------------------
run_configure_object_backup() {
  if deployment_engine_is_docker; then
    configure_docker_object_backup
  else
    configure_object_backup
  fi
}

run_engine_object_backup() {
  if deployment_engine_is_docker; then
    run_docker_object_backup "${1:-run}"
  else
    run_object_backup "${1:-run}"
  fi
}

show_engine_object_backup_status() {
  if deployment_engine_is_docker; then
    show_docker_object_backup_status
  else
    show_object_backup_status
  fi
}

show_off_vm_backup_plan() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_offvm_plan
    return
  fi

  require_site_environment >/dev/null || return 1
  off_vm_backup_load_config
  ui_box_start "Off-VM Backup Plan"
  status_line "Mode" "INFO" "planning only; no files are copied"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Local backup folder" "INFO" "$(site_backup_dir)"
  status_line "Target" "$([[ -n "${OFF_VM_BACKUP_TARGET:-}" ]] && echo INFO || echo WARN)" "$(off_vm_backup_target_display)"
  status_line "Transport" "INFO" "rsync over SSH"
  status_line "Delete mode" "INFO" "${OFF_VM_BACKUP_RSYNC_DELETE}"
  echo
  echo "Recommended first setup:"
  echo "  1) Create a backup user/folder on another Linux server."
  echo "  2) Make SSH key login work from this VM to the backup server."
  echo "  3) Configure the rsync target here."
  echo "  4) Run dry-run first, then the real off-VM backup."
  echo
  echo "Example target:"
  echo "  backup@example-backup-server:/srv/erpnext-backups/${SITE_NAME}/"
  echo
  echo "Safety defaults:"
  echo "  - No remote deletion by default."
  echo "  - No passwords or private keys are printed in logs."
  echo "  - Off-VM backup does not replace restore rehearsal."
  ui_next "$(toolkit_cmd configure-rsync-backup-target)" "$(toolkit_cmd off-vm-backup-dry-run)"
  ui_box_end
}

configure_rsync_backup_target() {
  require_sudo
  local target identity delete_mode config_dir
  ui_box_start "Configure Rsync Off-VM Backup Target"
  status_line "Site" "INFO" "$SITE_NAME"
  echo
  echo "Enter the rsync SSH target for off-VM backups."
  echo "Use the Target URI printed by backup-server-setup."
  echo "Example: erpbackup@65.109.220.250:/mnt/HC_Volume_106276869/erpnext-backups/${SITE_NAME}/"
  echo
  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Rsync target URI: " target
    if ! validate_off_vm_backup_target "$target"; then
      fail "Invalid target. Use user@host:/absolute/or/remote/path with no spaces."
    fi
    read -r -p "SSH identity file on this VM [default SSH config]: " identity
    if [[ -n "$identity" && ! -r "$identity" ]]; then
      warn "Identity file is not readable now: $identity"
      warn "Dry run will fail until the file exists and is readable."
    fi
    read -r -p "Enable rsync --delete on remote target? [y/N]: " delete_mode
    if [[ "$delete_mode" =~ ^[Yy]$|^[Yy][Ee][Ss]$ ]]; then
      delete_mode="true"
    else
      delete_mode="false"
    fi
  else
    target="${OFF_VM_BACKUP_TARGET:-}"
    validate_off_vm_backup_target "$target" || fail "Set OFF_VM_BACKUP_TARGET=user@host:/path before using --yes."
    identity="${OFF_VM_BACKUP_SSH_IDENTITY:-}"
    delete_mode="${OFF_VM_BACKUP_RSYNC_DELETE:-false}"
  fi

  OFF_VM_BACKUP_TARGET="$target"
  OFF_VM_BACKUP_SSH_IDENTITY="$identity"
  OFF_VM_BACKUP_RSYNC_DELETE="$delete_mode"
  off_vm_backup_write_config_file

  ui_box_start "Result Summary"
  status_line "Off-VM target" "OK" "$OFF_VM_BACKUP_TARGET"
  status_line "Config file" "OK" "$OFF_VM_BACKUP_CONFIG_FILE"
  status_line "Delete mode" "INFO" "$OFF_VM_BACKUP_RSYNC_DELETE"
  status_line "Host key mode" "INFO" "$(off_vm_strict_host_key_enabled && echo strict || echo accept-new)"
  status_line "Next test" "INFO" "trust host key (prod) then dry-run"
  ui_next "$(toolkit_cmd off-vm-trust-host-key)" "$(toolkit_cmd off-vm-backup-dry-run)"
  ui_box_end
}

show_off_vm_backup_status() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_offvm_status
    return
  fi

  local target_status target_detail last_status last_run last_detail latest_lines completeness
  off_vm_backup_load_config
  if off_vm_backup_configured; then
    target_status="OK"
    target_detail="$OFF_VM_BACKUP_TARGET"
  else
    target_status="WARN"
    target_detail="not configured"
  fi
  last_status="$(off_vm_backup_last_state LAST_STATUS 2>/dev/null || echo none)"
  last_run="$(off_vm_backup_last_state LAST_RUN_AT 2>/dev/null || echo never)"
  last_detail="$(off_vm_backup_last_state LAST_DETAIL 2>/dev/null || echo "no previous run")"
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"

  ui_box_start "Off-VM Backup Status"
  status_line "Target" "$target_status" "$target_detail"
  status_line "Config file" "$([[ -f "$OFF_VM_BACKUP_CONFIG_FILE" ]] && echo OK || echo WARN)" "$OFF_VM_BACKUP_CONFIG_FILE"
  status_line "Latest local backup" "$([[ "$completeness" == complete ]] && echo OK || echo WARN)" "${completeness:-none}"
  case "$last_status" in
    OK) status_line "Last off-VM run" "OK" "${last_run}; ${last_detail}" ;;
    FAIL) status_line "Last off-VM run" "FAIL" "${last_run}; ${last_detail}" ;;
    *) status_line "Last off-VM run" "INFO" "${last_run}; ${last_detail}" ;;
  esac
  status_line "Delete mode" "INFO" "${OFF_VM_BACKUP_RSYNC_DELETE}"
  status_line "Host key mode" "INFO" "$(off_vm_strict_host_key_enabled && echo strict || echo accept-new)"
  status_line "Known hosts" "INFO" "${OFF_VM_KNOWN_HOSTS_FILE}"
  echo
  echo "Off-VM backup protects against VM/disk loss only if the target is outside this VM/account."
  echo "Production: $(toolkit_cmd off-vm-trust-host-key) → $(toolkit_cmd off-vm-strict-host-key-enable)."
  ui_next "$(toolkit_cmd off-vm-backup-dry-run)" "$(toolkit_cmd run-off-vm-backup)"
  ui_box_end
}

disable_off_vm_backup() {
  require_sudo
  ui_box_start "Disable Off-VM Backup Config"
  status_line "Config file" "INFO" "$OFF_VM_BACKUP_CONFIG_FILE"
  status_line "State file" "INFO" "$OFF_VM_BACKUP_STATE_FILE"
  echo
  echo "This removes the local off-VM backup target configuration only."
  echo "It does not delete any remote backup files."
  if ! confirm "Remove off-VM backup configuration now?"; then
    warn "Disable cancelled."
    ui_box_end
    return 0
  fi
  $SUDO rm -f "$OFF_VM_BACKUP_CONFIG_FILE" "$OFF_VM_BACKUP_STATE_FILE"
  OFF_VM_BACKUP_TARGET=""
  OFF_VM_BACKUP_SSH_IDENTITY=""
  OFF_VM_BACKUP_RSYNC_DELETE="false"
  OFF_VM_STRICT_HOST_KEY="false"
  status_line "Off-VM backup" "OK" "configuration removed"
  echo "Note: ${OFF_VM_KNOWN_HOSTS_FILE} was left in place (remove manually if desired)."
  ui_next "$(toolkit_cmd off-vm-backup-status)"
  ui_box_end
}

off_vm_backup_wizard() {
  require_sudo
  while true; do
    ui_submenu_header "Off-VM Backup" "Rsync target, keys, and restore rehearsal"
    print_two_column_menu \
      "1) Off-VM backup plan" \
      "2) Guided setup" \
      "3) Generate backup SSH key" \
      "4) Configure rsync target" \
      "5) Trust host key" \
      "6) Verify host key" \
      "7) Enable strict host key" \
      "8) Off-VM dry run" \
      "9) Run off-VM backup" \
      "10) Off-VM status" \
      "11) Disable config" \
      "12) Prepare backup server" \
      "13) Restore rehearsal" \
      "14) Generate restore key" \
      "15) Add restore key" \
      "16) Remove restore key"
    ui_submenu_footer
    local off_choice=""
    menu_read_choice off_choice
    case "$off_choice" in
      1)
        show_off_vm_backup_plan
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      2)
        off_vm_backup_guided_setup
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      3)
        generate_off_vm_backup_key
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      4)
        configure_rsync_backup_target
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      5)
        off_vm_trust_host_key
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      6)
        off_vm_verify_host_key
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      7)
        off_vm_strict_host_key_enable
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      8)
        run_off_vm_backup_rsync dry-run
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      9)
        run_off_vm_backup_rsync run
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      10)
        show_off_vm_backup_status
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      11)
        disable_off_vm_backup
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      12)
        backup_server_setup
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      13)
        restore_rehearsal_wizard
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      14)
        generate_restore_backup_key
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      15)
        backup_server_add_restore_key
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      16)
        backup_server_remove_restore_key
        pause_after_screen "Press Enter to return to Off-VM Backup..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

backup_hardening_wizard() {
  while true; do
    ui_submenu_header "Backup Hardening" "Local backup, schedule, retention, off-VM"
    print_two_column_menu \
      "1) DB + files backup" \
      "2) Backup status" \
      "3) Verify latest backup" \
      "4) Off-VM guide" \
      "5) Restore rehearsal guide" \
      "6) Production checklist" \
      "7) List backups" \
      "8) Schedule plan" \
      "9) Configure schedule" \
      "10) Schedule status" \
      "11) Retention plan" \
      "12) Retention status" \
      "13) Cleanup dry run"
    ui_submenu_footer
    local backup_harden_choice=""
    menu_read_choice backup_harden_choice
    case "$backup_harden_choice" in
      1)
        create_site_backup true
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      2)
        show_backup_status
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      3)
        verify_latest_backup_set
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      4)
        show_off_vm_backup_guide
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      5)
        show_restore_rehearsal_guide
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      6)
        show_production_checklist
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      7)
        list_site_backups
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      8)
        show_backup_schedule_plan
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      9)
        configure_backup_schedule
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      10)
        show_backup_schedule_status
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      11)
        show_backup_retention_plan
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      12)
        show_backup_retention_status
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      13)
        cleanup_old_backups dry-run
        pause_after_screen "Press Enter to return to Backup Hardening..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

run_backup_maintenance_menu() {
  while true; do
    ui_submenu_header "Backup & Recovery" "Local backups, restore, schedules, retention, and maintenance"
    print_two_column_menu \
      "1) Database backup" \
      "2) DB + files backup" \
      "3) Backup status" \
      "4) Verify latest backup" \
      "5) Off-VM guide" \
      "6) Restore rehearsal guide" \
      "7) List backups" \
      "8) Restore database" \
      "9) Restore DB + files" \
      "10) Schedule status" \
      "11) Configure schedule" \
      "12) Disable schedule" \
      "13) Retention status" \
      "14) Cleanup dry run" \
      "15) Maintenance tasks"
    ui_submenu_footer
    local backup_choice=""
    menu_read_choice backup_choice

    case "$backup_choice" in
      1)
        create_site_backup false
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      2)
        create_site_backup true
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      3)
        show_backup_status
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      4)
        verify_latest_backup_set
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      5)
        show_off_vm_backup_guide
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      6)
        show_restore_rehearsal_guide
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      7)
        list_site_backups
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      8)
        restore_site_database
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      9)
        restore_site_full
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      10)
        show_backup_schedule_status
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      11)
        configure_backup_schedule
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      12)
        disable_backup_schedule
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      13)
        show_backup_retention_status
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      14)
        cleanup_old_backups dry-run
        pause_after_screen "Press Enter to return to Backup / Maintenance..."
        ;;
      15) run_maintenance_menu ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}
