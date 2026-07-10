#!/usr/bin/env bash
# ============================================================
# lib/update.sh — guarded ERPNext/Frappe version upgrades
#
# `bench update` pulls new upstream code, runs migrations, rebuilds assets, and
# restarts services. On a working install that is the single most dangerous
# routine operation: a failed migration or upstream breakage can take a healthy
# site down. This module wraps it so an upgrade is always backup-first,
# pre-checked, health-verified afterwards, and rollback-documented.
#
# Commands:
#   update-preflight       read-only readiness report (no changes)
#   safe-update-wizard     backup -> bench update -> verify, with rollback plan
#   update-rollback        restore recorded app commits from the last upgrade
# ============================================================

# Where the pre-upgrade rollback state is recorded (root-owned).
update_state_file() {
  printf '%s/last-update.state\n' "${LOG_DIR:-/var/log/erpnext-dev}"
}

# Emit one "app|branch|shortsha" line per git-backed app in the bench.
update_app_git_state() {
  local bench_dir="$1"
  run_as_frappe "cd '${bench_dir}/apps' 2>/dev/null || exit 0
for d in */; do
  app=\"\${d%/}\"
  [ -d \"\$app/.git\" ] || continue
  b=\$(git -C \"\$app\" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
  s=\$(git -C \"\$app\" rev-parse --short HEAD 2>/dev/null || echo unknown)
  printf '%s|%s|%s\n' \"\$app\" \"\$b\" \"\$s\"
done"
}

# Emit apps that have uncommitted local changes (dirty working tree).
update_dirty_apps() {
  local bench_dir="$1"
  run_as_frappe "cd '${bench_dir}/apps' 2>/dev/null || exit 0
for d in */; do
  app=\"\${d%/}\"
  [ -d \"\$app/.git\" ] || continue
  if [ -n \"\$(git -C \"\$app\" status --porcelain 2>/dev/null)\" ]; then
    printf '%s\n' \"\$app\"
  fi
done"
}

# Read-only preflight. Returns 0 if the upgrade looks safe to attempt, 1 if
# there are hard blockers the operator should resolve first.
run_update_preflight() {
  require_sudo

  local bench_dir env_label blockers=0 warnings=0
  local avail_kb avail_gib min_gib=5
  local app_state dirty latest_lines backup_prefix backup_completeness

  bench_dir="$(require_site_environment)" || return 1
  env_label="$(security_environment_label 2>/dev/null || echo unknown)"

  ui_box_start "ERPNext Update Preflight"
  status_line "Mode" "INFO" "read-only checks; no changes are made"
  status_line "Environment" "INFO" "$env_label"
  status_line "Bench directory" "OK" "$bench_dir"
  status_line "Target site" "INFO" "$SITE_NAME"

  if is_public_vm_workflow; then
    status_line "Production caution" "WARN" "public/production workflow: upgrade during a maintenance window and confirm a tested backup first"
    warnings=$((warnings + 1))
  fi

  # Service state (informational; the wizard restarts as needed).
  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}" 2>/dev/null; then
    status_line "Service" "OK" "${ERPNEXT_SERVICE_NAME} active"
  else
    status_line "Service" "WARN" "${ERPNEXT_SERVICE_NAME} not active; a healthy running site is the safest thing to upgrade"
    warnings=$((warnings + 1))
  fi

  # Free disk: an upgrade needs room for a fresh backup plus a rebuild.
  avail_kb="$(df -Pk "$bench_dir" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -n "$avail_kb" ]]; then
    avail_gib=$(( avail_kb / 1024 / 1024 ))
    if (( avail_gib >= min_gib )); then
      status_line "Free disk" "OK" "${avail_gib} GiB available on the bench filesystem"
    else
      status_line "Free disk" "FAIL" "${avail_gib} GiB available; need at least ${min_gib} GiB for backup + rebuild"
      blockers=$((blockers + 1))
    fi
  else
    status_line "Free disk" "WARN" "could not determine free space on ${bench_dir}"
    warnings=$((warnings + 1))
  fi

  # Uncommitted changes block a clean pull.
  dirty="$(update_dirty_apps "$bench_dir" 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    status_line "App working trees" "FAIL" "uncommitted local changes in: $(printf '%s' "$dirty" | tr '\n' ' ')"
    echo "  Commit, stash, or discard these before upgrading; bench update will not overwrite local work."
    blockers=$((blockers + 1))
  else
    status_line "App working trees" "OK" "clean; no uncommitted local changes"
  fi

  # Current app versions.
  app_state="$(update_app_git_state "$bench_dir" 2>/dev/null || true)"
  if [[ -n "$app_state" ]]; then
    echo
    echo "Installed apps (branch @ commit):"
    printf '%s\n' "$app_state" | while IFS='|' read -r app branch sha; do
      [[ -n "$app" ]] || continue
      printf '  %-16s %s @ %s\n' "$app" "${branch:-unknown}" "${sha:-unknown}"
    done
  else
    status_line "Installed apps" "WARN" "could not read app git state"
    warnings=$((warnings + 1))
  fi

  # Backup recency.
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  if [[ -n "$latest_lines" ]]; then
    backup_prefix="$(printf '%s\n' "$latest_lines" | sed -n '1p')"
    backup_completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
    if [[ "$backup_completeness" == "complete" ]]; then
      status_line "Existing backup" "OK" "latest complete set: $(basename "${backup_prefix:-unknown}")"
    else
      status_line "Existing backup" "WARN" "latest set is partial; the wizard will make a fresh full backup"
      warnings=$((warnings + 1))
    fi
  else
    status_line "Existing backup" "INFO" "none found; the wizard always makes a fresh full backup before upgrading"
  fi

  echo
  if (( blockers > 0 )); then
    status_line "Verdict" "FAIL" "${blockers} blocker(s), ${warnings} warning(s) — resolve blockers before upgrading"
    echo "Next: fix the items marked FAIL, then re-run $(toolkit_cmd update-preflight)."
    ui_box_end
    return 1
  fi

  status_line "Verdict" "OK" "no blockers (${warnings} warning(s))"
  echo "Next: $(toolkit_cmd safe-update-wizard) to upgrade with a backup-first, verified flow."
  ui_box_end
  return 0
}

# Backup-first, verified `bench update`.
run_safe_update_wizard() {
  require_sudo

  local bench_dir reply pre_state latest_lines backup_prefix state_file
  bench_dir="$(require_site_environment)" || return 1

  ui_box_start "Safe ERPNext Update"
  echo "This upgrades installed apps with 'bench update' (pull + migrate + build + restart)."
  echo "It is destructive to the current code/schema. This wizard makes a full backup first"
  echo "and records the current commits so you can roll back."
  echo

  # Hard gate on blockers unless explicitly forced.
  if ! run_update_preflight; then
    if [[ "${UPDATE_FORCE:-0}" == "1" ]]; then
      warn "Preflight reported blockers but UPDATE_FORCE=1 is set; continuing at your own risk."
    else
      fail "Preflight found blockers. Resolve them or re-run with UPDATE_FORCE=1 to override."
    fi
  fi

  echo
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
    log "ASSUME_YES set; proceeding without interactive confirmation."
  else
    warn "About to upgrade ${SITE_NAME}. This can change your ERPNext/Frappe version."
    read -r -p "Type UPDATE to continue: " reply
    [[ "$reply" == "UPDATE" ]] || fail "Update cancelled."
  fi

  # 1) Capture the pre-upgrade commit state for rollback.
  pre_state="$(update_app_git_state "$bench_dir" 2>/dev/null || true)"

  # 2) Full backup before touching anything.
  log "Creating a full backup (database + files) before upgrading"
  if ! create_site_backup true; then
    fail "Pre-upgrade backup failed. Not proceeding — a verified backup is required before an upgrade."
  fi

  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  backup_prefix="$(printf '%s\n' "$latest_lines" | sed -n '1p')"

  # 3) Persist rollback state.
  state_file="$(update_state_file)"
  {
    echo "# ERPNext Dev Toolkit — pre-update rollback state"
    echo "UPDATE_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "BENCH_DIR=${bench_dir}"
    echo "SITE_NAME=${SITE_NAME}"
    echo "BACKUP_PREFIX=${backup_prefix:-unknown}"
    echo "# app|branch|sha (pre-update)"
    printf '%s\n' "$pre_state"
  } > "$state_file" 2>/dev/null || warn "Could not write rollback state file at ${state_file}."
  chmod 600 "$state_file" 2>/dev/null || true
  status_line "Rollback state" "OK" "recorded at ${state_file}"

  # 4) The upgrade itself.
  log "Running 'bench update' (this can take several minutes)"
  if ! run_as_frappe_quiet "bench update" "cd '${bench_dir}' && bench update"; then
    warn "bench update did not complete cleanly."
    update_print_rollback_plan "$state_file"
    ui_box_end
    return 1
  fi

  # 5) Post-upgrade migrate (idempotent belt-and-suspenders) + health gate.
  log "Ensuring migrations are applied"
  ensure_bench_services_for_site_commands "post-update migrate" \
    && run_as_frappe_quiet "post-update migrate" "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate" \
    || warn "Post-update migrate reported an issue; review the log above."

  log "Verifying the site is healthy after the upgrade"
  if wait_for_erpnext_ready; then
    status_line "Post-update health" "OK" "site is serving after the upgrade"
  else
    warn "Site did not become ready after the upgrade."
    update_print_rollback_plan "$state_file"
    ui_box_end
    return 1
  fi

  echo
  echo "Apps after upgrade (branch @ commit):"
  update_app_git_state "$bench_dir" 2>/dev/null | while IFS='|' read -r app branch sha; do
    [[ -n "$app" ]] || continue
    printf '  %-16s %s @ %s\n' "$app" "${branch:-unknown}" "${sha:-unknown}"
  done

  echo
  ok "Upgrade completed and the site is healthy."
  echo "Rollback state (kept in case a latent issue appears): ${state_file}"
  echo "If needed: $(toolkit_cmd update-rollback)"
  ui_box_end
  return 0
}

update_print_rollback_plan() {
  local state_file="$1"
  echo
  warn "ROLLBACK PLAN"
  echo "Your pre-upgrade state was recorded at: ${state_file}"
  echo
  echo "Automated (recommended):"
  echo "  $(toolkit_cmd update-rollback)"
  echo
  echo "Manual, if you prefer:"
  echo "  1. Restore the pre-upgrade backup:   $(toolkit_cmd restore-full)"
  echo "  2. Check out the recorded commit for each app under ${BENCH_DIR}/apps,"
  echo "     e.g.:  sudo -iu ${FRAPPE_USER} git -C ${BENCH_DIR}/apps/<app> checkout <sha>"
  echo "  3. Rebuild + restart:                $(toolkit_cmd migrate) && $(toolkit_cmd restart)"
}

# Emergency rollback: check out the app commits recorded before the last upgrade.
# Database rollback is handed off to restore-full (the recorded backup prefix).
run_update_rollback() {
  require_sudo

  local state_file bench_dir reply backup_prefix
  state_file="$(update_state_file)"

  if [[ ! -f "$state_file" ]]; then
    fail "No rollback state found at ${state_file}. Nothing to roll back to."
  fi

  # shellcheck disable=SC1090
  bench_dir="$(awk -F= '/^BENCH_DIR=/{print $2; exit}' "$state_file")"
  backup_prefix="$(awk -F= '/^BACKUP_PREFIX=/{print $2; exit}' "$state_file")"
  [[ -n "$bench_dir" ]] || bench_dir="$(require_site_environment)" || return 1

  ui_box_start "Update Rollback"
  echo "This checks out the app commits recorded before the last upgrade:"
  echo
  grep -E '^[^#].*\|' "$state_file" | while IFS='|' read -r app branch sha; do
    [[ -n "$app" ]] || continue
    printf '  %-16s -> %s\n' "$app" "${sha:-unknown}"
  done
  echo
  echo "Recorded pre-update backup: ${backup_prefix:-unknown}"
  warn "Rolling back code does NOT by itself revert database schema changes."
  echo "For a full rollback, also restore the recorded backup with $(toolkit_cmd restore-full)."
  echo

  if [[ "${ASSUME_YES:-0}" -ne 1 ]]; then
    read -r -p "Type ROLLBACK to check out the recorded commits: " reply
    [[ "$reply" == "ROLLBACK" ]] || fail "Rollback cancelled."
  fi

  local failed=0
  while IFS='|' read -r app branch sha; do
    [[ -n "$app" && -n "$sha" && "$sha" != "unknown" ]] || continue
    log "Checking out ${app} @ ${sha}"
    if ! run_as_frappe "git -C '${bench_dir}/apps/${app}' checkout '${sha}'"; then
      warn "Could not check out ${app} @ ${sha}."
      failed=1
    fi
  done < <(grep -E '^[^#].*\|' "$state_file")

  log "Rebuilding assets after rollback"
  run_as_frappe_quiet "rollback build" "cd '${bench_dir}' && bench build" || warn "Asset build reported an issue."
  restart_erpnext_service || warn "Service restart reported an issue."

  echo
  if (( failed == 0 )); then
    ok "Code rolled back to the recorded commits."
  else
    warn "Rollback finished with some errors; review the messages above."
  fi
  echo "If the database schema also changed, restore the recorded backup now:"
  echo "  $(toolkit_cmd restore-full)"
  ui_box_end
  return "$failed"
}
