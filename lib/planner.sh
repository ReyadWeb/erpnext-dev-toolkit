# shellcheck shell=bash
# Unified application operation planner. Phase 3 enables native Quick installs.
[[ -n "${_ERPNEXT_DEV_PLANNER_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_PLANNER_LOADED=1

OPERATION_STATE_DIR="${OPERATION_STATE_DIR:-/var/lib/erpnext-dev/operations}"
QUICK_INSTALL_SITE="${QUICK_INSTALL_SITE:-}"
QUICK_INSTALL_PREVIEW="${QUICK_INSTALL_PREVIEW:-0}"

OPERATION_ID=""
OPERATION_FILE=""
OPERATION_STATUS=""
OPERATION_CHECKPOINTS=""
OPERATION_FAILURE_STAGE=""
OPERATION_FAILURE_REASON=""
OPERATION_BACKUP_REFERENCE=""
OPERATION_RECOVERY=""

planner_exit_code() {
  case "$1" in
    success) return 0 ;;
    already-complete) return 10 ;;
    preview) return 11 ;;
    cancelled) return 12 ;;
    invalid-input) return 20 ;;
    ambiguous-target) return 21 ;;
    incompatible) return 22 ;;
    unsupported) return 23 ;;
    backup-failed) return 30 ;;
    mutation-failed) return 31 ;;
    verification-failed) return 32 ;;
    recovery-required) return 33 ;;
    conflict) return 34 ;;
    *) return 1 ;;
  esac
}

planner_safe_value() {
  [[ "${1:-}" != *$'\n'* && "${1:-}" != *$'\r'* && "${1:-}" != *$'\t'* ]]
}

planner_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

planner_prepare_state_dir() {
  require_sudo
  if [[ -L "$OPERATION_STATE_DIR" ]]; then
    err "Refusing symlinked operation directory: $OPERATION_STATE_DIR"
    return 1
  fi
  $SUDO mkdir -p "$OPERATION_STATE_DIR" || return 1
  $SUDO chmod 700 "$OPERATION_STATE_DIR" || return 1
}

planner_record_write() {
  local temp="${OPERATION_FILE}.tmp.$$" value
  planner_prepare_state_dir || return 1
  [[ -n "$OPERATION_FILE" && "$OPERATION_FILE" == "$OPERATION_STATE_DIR/"*.state ]] || return 1
  [[ ! -L "$OPERATION_FILE" && ! -L "$temp" ]] || return 1
  for value in "$OPERATION_ID" "$OPERATION_STATUS" "$OPERATION_CHECKPOINTS" "$OPERATION_FAILURE_STAGE" \
    "$OPERATION_FAILURE_REASON" "$OPERATION_BACKUP_REFERENCE" "$OPERATION_RECOVERY"; do
    planner_safe_value "$value" || return 1
  done
  {
    printf 'schema=1\n'
    printf 'operation_id=%s\n' "$OPERATION_ID"
    printf 'operation_type=quick-app-install\n'
    printf 'requested_app=%s\n' "$PLAN_APP"
    printf 'catalog_id=%s\n' "$PLAN_CATALOG_ID"
    printf 'install_app_name=%s\n' "$PLAN_INSTALL_NAME"
    printf 'target_stack=%s\n' "$PLAN_STACK"
    printf 'target_bench=%s\n' "$PLAN_BENCH"
    printf 'target_site=%s\n' "$PLAN_SITE"
    printf 'current_profile=%s\n' "$PLAN_CURRENT_PROFILE"
    printf 'resulting_profile=%s\n' "$PLAN_RESULT_PROFILE"
    printf 'inventory_fingerprint=%s\n' "$PLAN_INVENTORY_FINGERPRINT"
    printf 'code_state=%s\n' "$PLAN_CODE_STATE"
    printf 'site_state=%s\n' "$PLAN_SITE_STATE"
    printf 'dependencies=%s\n' "$PLAN_DEPENDENCIES"
    printf 'compatibility=%s\n' "$PLAN_COMPATIBILITY"
    printf 'trust=%s\n' "$PLAN_TRUST"
    printf 'shared_sites=%s\n' "$PLAN_SHARED_SITES"
    printf 'backup_targets=%s\n' "$PLAN_SITE"
    printf 'planned_actions=%s\n' "$PLAN_ACTIONS"
    printf 'verification=%s\n' "$PLAN_VERIFICATION"
    printf 'status=%s\n' "$OPERATION_STATUS"
    printf 'checkpoints=%s\n' "$OPERATION_CHECKPOINTS"
    printf 'failure_stage=%s\n' "$OPERATION_FAILURE_STAGE"
    printf 'failure_reason=%s\n' "$OPERATION_FAILURE_REASON"
    printf 'backup_reference=%s\n' "$OPERATION_BACKUP_REFERENCE"
    printf 'recovery=%s\n' "$OPERATION_RECOVERY"
    printf 'started_at=%s\n' "$PLAN_STARTED_AT"
    printf 'completed_at=%s\n' "${PLAN_COMPLETED_AT:-}"
  } | $SUDO tee "$temp" >/dev/null || return 1
  $SUDO chmod 600 "$temp" || return 1
  $SUDO mv "$temp" "$OPERATION_FILE" || return 1
}

planner_checkpoint() {
  local checkpoint="$1" status="${2:-$OPERATION_STATUS}"
  OPERATION_STATUS="$status"
  if [[ ",${OPERATION_CHECKPOINTS}," != *",${checkpoint},"* ]]; then
    OPERATION_CHECKPOINTS="${OPERATION_CHECKPOINTS:+${OPERATION_CHECKPOINTS},}${checkpoint}"
  fi
  planner_record_write
}

planner_fail_record() {
  local stage="$1" reason="$2" recovery="$3" status="${4:-failed}"
  OPERATION_STATUS="$status"
  OPERATION_FAILURE_STAGE="$stage"
  OPERATION_FAILURE_REASON="${reason//[$'\n\r\t']/ }"
  OPERATION_RECOVERY="${recovery//[$'\n\r\t']/ }"
  planner_record_write || true
}

planner_inventory_fingerprint() {
  inventory_records_sorted | sha256sum | awk '{print $1}'
}

planner_site_installed() {
  local stack="$1" site="$2" app="$3"
  inventory_records_sorted | awk -F'|' -v s="$stack" -v t="$site" -v a="$app" \
    '$1=="SITE_APP" && $2==s && $3==t && $4==a {found=1} END {exit !found}'
}

planner_dependency_visit() {
  local app="$1" dep
  [[ ",${PLAN_DEPENDENCY_SEEN}," != *",${app},"* ]] || return 0
  PLAN_DEPENDENCY_SEEN="${PLAN_DEPENDENCY_SEEN:+${PLAN_DEPENDENCY_SEEN},}${app}"
  load_validated_app_catalog_record "$app" || return 1
  while IFS= read -r dep; do
    [[ -n "$dep" && "$dep" != frappe ]] || continue
    planner_dependency_visit "$dep" || return 1
    [[ "$dep" == "$PLAN_APP" ]] || PLAN_DEPENDENCY_ORDER+=("$dep")
  done < <(printf '%s\n' "${LIB_APP_REQUIRES:-}" | tr ',' '\n')
}

planner_resolve_dependencies() {
  PLAN_DEPENDENCY_ORDER=()
  PLAN_DEPENDENCY_SEEN=""
  planner_dependency_visit "$PLAN_APP" || return 1
  PLAN_DEPENDENCIES="$(printf '%s\n' "${PLAN_DEPENDENCY_ORDER[@]}" | awk 'NF&&!seen[$0]++' | paste -sd, -)"
}

planner_select_target() {
  local record count=0 selected="" site_count=0 site_record
  while IFS= read -r record; do
    [[ "$record" == STACK\|* ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f3)" == native ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f6)" == managed ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f7)" == clean ]] || continue
    selected="$record"
    count=$((count + 1))
  done < <(inventory_records_sorted)
  [[ "$count" -eq 1 ]] || return 2
  PLAN_STACK="$(printf '%s' "$selected" | cut -d'|' -f2)"
  PLAN_BENCH="${PLAN_STACK#native:}"
  while IFS= read -r site_record; do
    [[ "$site_record" == SITE\|"${PLAN_STACK}"\|* ]] || continue
    [[ "$(printf '%s' "$site_record" | cut -d'|' -f4)" == known ]] || return 2
    site_count=$((site_count + 1))
    [[ -n "$QUICK_INSTALL_SITE" ]] || PLAN_SITE="$(printf '%s' "$site_record" | cut -d'|' -f3)"
  done < <(inventory_records_sorted)
  if [[ -n "$QUICK_INSTALL_SITE" ]]; then
    inventory_valid_name "$QUICK_INSTALL_SITE" || return 1
    PLAN_SITE="$QUICK_INSTALL_SITE"
    inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" -v t="$PLAN_SITE" \
      '$1=="SITE" && $2==s && $3==t && $4=="known" {found=1} END {exit !found}' || return 2
  elif [[ "$site_count" -ne 1 ]]; then
    return 2
  fi
  [[ -n "$PLAN_SITE" ]] || return 2
}

planner_evaluate_compatibility() {
  local saved_profile="$INSTALLATION_PROFILE" rc dep class trust management
  local -a inventory_snapshot=("${INVENTORY_RECORDS[@]}")
  if [[ "$PLAN_APP" == erpnext && "$PLAN_CURRENT_PROFILE" == frappe-only ]]; then
    INSTALLATION_PROFILE=recommended
  fi
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    load_validated_app_catalog_record "$dep" || {
      INSTALLATION_PROFILE="$saved_profile"
      INVENTORY_RECORDS=("${inventory_snapshot[@]}")
      return 1
    }
    if ! inventory_app_available "$dep"; then
      class="$(inventory_catalog_classification "$dep")"
      trust="${class%%|*}"
      management="${class#*|}"
      inventory_add_record APP "$PLAN_STACK" "$dep" available unknown "$LIB_APP_BRANCH" unknown \
        "$LIB_APP_REPO" "$trust" "$management" clean || {
        INSTALLATION_PROFILE="$saved_profile"
        INVENTORY_RECORDS=("${inventory_snapshot[@]}")
        return 1
      }
    fi
    inventory_compatibility_evaluate "$dep" || {
      INSTALLATION_PROFILE="$saved_profile"
      INVENTORY_RECORDS=("${inventory_snapshot[@]}")
      return 1
    }
  done < <(printf '%s\n' "$PLAN_DEPENDENCIES" | tr ',' '\n')
  if inventory_compatibility_evaluate "$PLAN_APP"; then rc=0; else rc=$?; fi
  INSTALLATION_PROFILE="$saved_profile"
  INVENTORY_RECORDS=("${inventory_snapshot[@]}")
  PLAN_COMPATIBILITY="$INVENTORY_COMPAT_STATUS"
  [[ "$rc" -eq 0 ]]
}

planner_build() {
  local app="$1" app_record other_sites
  inventory_valid_name "$app" || return 20
  load_validated_app_catalog_record "$app" || return 20
  [[ "${LIB_APP_QUICK_INSTALL:-unsupported}" == supported ]] || return 22
  [[ "$LIB_APP_TRUST" == official || "$LIB_APP_TRUST" == community ]] || return 22
  PLAN_APP="$app"
  PLAN_CATALOG_ID="$LIB_APP_ID"
  PLAN_INSTALL_NAME="$LIB_APP_NAME"
  PLAN_TRUST="$LIB_APP_TRUST"
  PLAN_REPO="$LIB_APP_REPO"
  PLAN_BRANCH="$LIB_APP_BRANCH"
  inventory_collect
  [[ "$(effective_deployment_engine)" == native ]] || return 23
  planner_select_target || return $?
  PLAN_CURRENT_PROFILE="$(effective_installation_profile)"
  PLAN_RESULT_PROFILE="$PLAN_CURRENT_PROFILE"
  [[ "$app" == erpnext && "$PLAN_CURRENT_PROFILE" == frappe-only ]] && PLAN_RESULT_PROFILE=recommended
  if [[ "$app" == erpnext && "$PLAN_CURRENT_PROFILE" == frappe-only ]] \
    && planner_site_installed "$PLAN_STACK" "$PLAN_SITE" erpnext; then
    return 22
  fi
  planner_resolve_dependencies || return 22
  planner_evaluate_compatibility || return 22
  app_record="$(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" -v a="$app" '$1=="APP"&&$2==s&&$3==a{print;exit}')"
  PLAN_CODE_STATE="$(printf '%s' "$app_record" | cut -d'|' -f4)"
  PLAN_CODE_STATE="${PLAN_CODE_STATE:-missing}"
  if planner_site_installed "$PLAN_STACK" "$PLAN_SITE" "$app"; then
    PLAN_SITE_STATE=installed
  else
    PLAN_SITE_STATE=not-installed
  fi
  other_sites="$(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" -v t="$PLAN_SITE" \
    '$1=="SITE"&&$2==s&&$3!=t{print $3}' | paste -sd, -)"
  PLAN_SHARED_SITES="${other_sites:-none}"
  PLAN_ACTIONS="backup-site"
  [[ "$PLAN_CODE_STATE" == available ]] || PLAN_ACTIONS+=",acquire-bench-code"
  [[ -n "$PLAN_DEPENDENCIES" ]] && PLAN_ACTIONS+=",install-dependencies"
  PLAN_ACTIONS+=",install-site-app,migrate,build-assets,clear-cache,restart-services"
  PLAN_VERIFICATION="installed-apps,dependencies,bench-doctor,database,http,workers,scheduler,queues,redis,assets,services,inventory"
  PLAN_INVENTORY_FINGERPRINT="$(planner_inventory_fingerprint)"
  PLAN_STARTED_AT="$(planner_timestamp)"
  PLAN_COMPLETED_AT=""
  OPERATION_ID="${OPERATION_ID_OVERRIDE:-$(date -u +%Y%m%dT%H%M%SZ)-$$-${app}}"
  OPERATION_FILE="${OPERATION_STATE_DIR}/${OPERATION_ID}.state"
  OPERATION_STATUS=planned
  OPERATION_CHECKPOINTS=planned
  OPERATION_FAILURE_STAGE=""
  OPERATION_FAILURE_REASON=""
  OPERATION_BACKUP_REFERENCE=""
  OPERATION_RECOVERY="Use the recorded backup with the documented restore workflow; inspect the last checkpoint before retrying."
  return 0
}

planner_preview() {
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    printf '{"schema_version":1,"read_only":true,"operation_id":'
    inventory_json_escape "$OPERATION_ID"
    printf ',"status":"%s","engine":"native","stack":' "$OPERATION_STATUS"
    inventory_json_escape "$PLAN_STACK"
    printf ',"site":'
    inventory_json_escape "$PLAN_SITE"
    printf ',"application":'
    inventory_json_escape "$PLAN_APP"
    printf ',"code_state":"%s","site_state":"%s","dependencies":' "$PLAN_CODE_STATE" "$PLAN_SITE_STATE"
    inventory_json_escape "$PLAN_DEPENDENCIES"
    printf ',"shared_sites":'
    inventory_json_escape "$PLAN_SHARED_SITES"
    printf ',"backup_target":'
    inventory_json_escape "$PLAN_SITE"
    printf ',"verification":'
    inventory_json_escape "$PLAN_VERIFICATION"
    printf '}\n'
    return
  fi
  ui_box_start "Quick Application Installation Plan"
  status_line "Deployment" "INFO" "native"
  status_line "Bench / stack" "INFO" "$PLAN_STACK"
  status_line "Target site" "INFO" "$PLAN_SITE"
  status_line "Profile" "INFO" "${PLAN_CURRENT_PROFILE} -> ${PLAN_RESULT_PROFILE}"
  status_line "Application" "INFO" "$PLAN_APP"
  status_line "Bench code" "INFO" "$PLAN_CODE_STATE"
  status_line "Site installation" "INFO" "$PLAN_SITE_STATE"
  status_line "Dependencies" "INFO" "${PLAN_DEPENDENCIES:-none}"
  status_line "Other shared sites" "INFO" "$PLAN_SHARED_SITES"
  status_line "Backup target" "INFO" "$PLAN_SITE"
  status_line "Availability impact" "INFO" "asset build and service restart may briefly interrupt this Bench"
  status_line "Verification" "INFO" "$PLAN_VERIFICATION"
  status_line "Recovery checkpoint" "INFO" "verified site backup before first mutation"
  status_line "Already complete" "INFO" "$([[ "$PLAN_SITE_STATE" == installed ]] && echo yes || echo no)"
  ui_box_end
}

planner_verify_backup_target() {
  local lines prefix db_file public_file private_file config_file completeness expected path
  lines="$(backup_latest_set_paths)" || return 1
  prefix="$(printf '%s\n' "$lines" | sed -n '1p')"
  db_file="$(printf '%s\n' "$lines" | sed -n '2p')"
  public_file="$(printf '%s\n' "$lines" | sed -n '3p')"
  private_file="$(printf '%s\n' "$lines" | sed -n '4p')"
  config_file="$(printf '%s\n' "$lines" | sed -n '5p')"
  completeness="$(printf '%s\n' "$lines" | sed -n '6p')"
  expected="${PLAN_BENCH}/sites/${PLAN_SITE}/private/backups/"
  [[ -n "$prefix" && "$completeness" == complete ]] || return 1
  for path in "$db_file" "$public_file" "$private_file" "$config_file"; do
    [[ -f "$path" && "$path" == "$expected"* && ! -L "$path" ]] || return 1
  done
  verify_backup_file Database "$db_file" gzip >/dev/null \
    && verify_backup_file Public "$public_file" tar >/dev/null \
    && verify_backup_file Private "$private_file" tar >/dev/null \
    && verify_backup_file Config "$config_file" json >/dev/null \
    || return 1
  OPERATION_BACKUP_REFERENCE="${PLAN_SITE}:${prefix}"
}

planner_backup_gate() {
  local previous_site="$SITE_NAME"
  SITE_NAME="$PLAN_SITE"
  if ! create_site_backup true || ! verify_latest_backup_set || ! planner_verify_backup_target; then
    SITE_NAME="$previous_site"
    return 1
  fi
  SITE_NAME="$previous_site"
  planner_checkpoint backup-complete backup-complete
}

planner_run_native_action() {
  local action="$1" app="$2" bench_q site_q repo_q branch_q app_q
  printf -v bench_q %q "$PLAN_BENCH"
  printf -v site_q %q "$PLAN_SITE"
  printf -v repo_q %q "$PLAN_REPO"
  printf -v branch_q %q "$PLAN_BRANCH"
  printf -v app_q %q "$app"
  case "$action" in
    acquire)
      if [[ -n "$PLAN_BRANCH" ]]; then
        run_as_frappe "cd ${bench_q} && bench get-app ${repo_q} --branch ${branch_q}"
      else
        run_as_frappe "cd ${bench_q} && bench get-app ${repo_q}"
      fi
      ;;
    install) run_as_frappe "cd ${bench_q} && bench --site ${site_q} install-app ${app_q}" ;;
    migrate) run_as_frappe "cd ${bench_q} && bench --site ${site_q} migrate" ;;
    build) run_as_frappe "cd ${bench_q} && bench build" ;;
    clear-cache) run_as_frappe "cd ${bench_q} && bench --site ${site_q} clear-cache" ;;
    doctor) run_as_frappe "cd ${bench_q} && bench --site ${site_q} doctor" ;;
    *) return 1 ;;
  esac
}

planner_mutate() {
  local dep
  planner_checkpoint mutation-started mutation-started || return 1
  if [[ "$PLAN_CODE_STATE" != available ]]; then
    planner_run_native_action acquire "$PLAN_APP" || return 1
    planner_checkpoint code-acquired mutation-started || return 1
  fi
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    if ! planner_site_installed "$PLAN_STACK" "$PLAN_SITE" "$dep"; then
      load_validated_app_catalog_record "$dep" || return 1
      PLAN_REPO="$LIB_APP_REPO"
      PLAN_BRANCH="$LIB_APP_BRANCH"
      inventory_app_available "$dep" || planner_run_native_action acquire "$dep" || return 1
      planner_run_native_action install "$dep" || return 1
      planner_checkpoint "dependency-${dep}" mutation-started || return 1
    fi
  done < <(printf '%s\n' "$PLAN_DEPENDENCIES" | tr ',' '\n')
  load_validated_app_catalog_record "$PLAN_APP" || return 1
  PLAN_REPO="$LIB_APP_REPO"
  PLAN_BRANCH="$LIB_APP_BRANCH"
  planner_run_native_action install "$PLAN_APP" || return 1
  planner_checkpoint app-installed mutation-started || return 1
  planner_run_native_action migrate "$PLAN_APP" || return 1
  planner_checkpoint migrated mutation-started || return 1
  planner_run_native_action build "$PLAN_APP" || return 1
  planner_checkpoint assets-built mutation-started || return 1
  planner_run_native_action clear-cache "$PLAN_APP" || return 1
  restart_erpnext_service || return 1
  planner_checkpoint mutation-complete mutation-complete
}

planner_verify() {
  local dep shared_site previous_site="$SITE_NAME"
  SITE_NAME="$PLAN_SITE"
  planner_run_native_action doctor "$PLAN_APP" || {
    SITE_NAME="$previous_site"
    return 1
  }
  site_app_installed "$PLAN_APP" || {
    SITE_NAME="$previous_site"
    return 1
  }
  while IFS= read -r dep; do
    [[ -z "$dep" ]] || site_app_installed "$dep" || {
      SITE_NAME="$previous_site"
      return 1
    }
  done < <(printf '%s\n' "$PLAN_DEPENDENCIES" | tr ',' '\n')
  [[ "$(runtime_state 2>/dev/null || true)" == Running* ]] || {
    SITE_NAME="$previous_site"
    return 1
  }
  port_listens 8000 || {
    SITE_NAME="$previous_site"
    return 1
  }
  port_listens 11000 || {
    SITE_NAME="$previous_site"
    return 1
  }
  port_listens 13000 || {
    SITE_NAME="$previous_site"
    return 1
  }
  bench_http_ready || {
    SITE_NAME="$previous_site"
    return 1
  }
  bench_static_assets_ready || {
    SITE_NAME="$previous_site"
    return 1
  }
  SITE_NAME="$previous_site"
  inventory_collect
  planner_site_installed "$PLAN_STACK" "$PLAN_SITE" "$PLAN_APP" || return 1
  while IFS= read -r shared_site; do
    [[ -z "$shared_site" || "$shared_site" == none ]] && continue
    inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" -v t="$shared_site" \
      '$1=="SITE"&&$2==s&&$3==t&&$4=="known"{found=1} END{exit !found}' || return 1
  done < <(printf '%s\n' "$PLAN_SHARED_SITES" | tr ',' '\n')
  planner_checkpoint verification-complete verification-complete
}

planner_execute() {
  local current_fingerprint previous_profile="$INSTALLATION_PROFILE"
  if [[ "$PLAN_SITE_STATE" == installed ]]; then
    OPERATION_STATUS=completed
    PLAN_COMPLETED_AT="$(planner_timestamp)"
    planner_checkpoint already-complete completed
    planner_exit_code already-complete
    return
  fi
  if [[ "$QUICK_INSTALL_PREVIEW" == 1 ]]; then
    planner_exit_code preview
    return
  fi
  planner_record_write || return 1
  if [[ "$ASSUME_YES" -ne 1 ]] && ! confirm "Apply this verified plan now?"; then
    OPERATION_STATUS=failed
    planner_fail_record confirmation "User cancelled after preview." "No mutation occurred."
    planner_exit_code cancelled
    return
  fi
  inventory_collect
  current_fingerprint="$(planner_inventory_fingerprint)"
  if [[ "$current_fingerprint" != "$PLAN_INVENTORY_FINGERPRINT" ]]; then
    planner_fail_record preflight "Inventory changed after preview." "Generate and confirm a fresh plan."
    planner_exit_code conflict
    return
  fi
  planner_checkpoint validated validated || return 1
  if ! planner_backup_gate; then
    planner_fail_record backup "Backup creation or verification failed." "Resolve backup errors; no mutation was attempted."
    planner_exit_code backup-failed
    return
  fi
  inventory_collect
  current_fingerprint="$(planner_inventory_fingerprint)"
  if [[ "$current_fingerprint" != "$PLAN_INVENTORY_FINGERPRINT" ]]; then
    planner_fail_record pre-mutation "Inventory changed during the backup gate." "Generate and confirm a fresh plan."
    planner_exit_code conflict
    return
  fi
  if ! planner_mutate; then
    planner_fail_record mutation "Native installation action failed." \
      "Use ${OPERATION_BACKUP_REFERENCE}; inspect checkpoints and Bench logs before retrying." recovery-required
    planner_exit_code mutation-failed
    return
  fi
  if ! planner_verify; then
    planner_fail_record verification "Post-install health or inventory verification failed." \
      "Installation may be partial. Use ${OPERATION_BACKUP_REFERENCE}; inspect Bench health before retrying." recovery-required
    planner_exit_code verification-failed
    return
  fi
  if [[ "$PLAN_RESULT_PROFILE" != "$PLAN_CURRENT_PROFILE" ]]; then
    INSTALLATION_PROFILE="$PLAN_RESULT_PROFILE"
    write_dev_config_file || {
      INSTALLATION_PROFILE="$previous_profile"
      planner_fail_record profile "Verified install succeeded, but profile persistence failed." \
        "Installation is present; repair config and verify before recording the profile." recovery-required
      planner_exit_code recovery-required
      return
    }
  fi
  PLAN_COMPLETED_AT="$(planner_timestamp)"
  planner_checkpoint completed completed
  ok "${PLAN_APP} installation completed and verified on ${PLAN_SITE}"
}

run_quick_app_install() {
  local app="$1" rc
  if [[ "$ASSUME_YES" -eq 1 && -z "$QUICK_INSTALL_SITE" ]]; then
    err "Non-interactive Quick installation requires --site SITE."
    planner_exit_code invalid-input
    return
  fi
  planner_build "$app" || {
    rc=$?
    case "$rc" in
      20) err "Invalid or unmanaged Quick-install application: $app" ;;
      21 | 2) err "Target stack/site is ambiguous; pass --site with an exact managed site." ;;
      22) err "Application is incompatible or unsupported by trusted Quick-install policy." ;;
      23) err "Quick installation supports managed native Bench deployments only." ;;
      *) err "Could not build a safe operation plan." ;;
    esac
    return "$rc"
  }
  planner_preview
  planner_execute
}
