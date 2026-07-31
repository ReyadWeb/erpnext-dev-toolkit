#!/usr/bin/env bash
# shellcheck disable=SC2034 # planner journal fields are consumed by sourced sibling modules
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

update_local_changes_state_file() {
  printf '%s/last-update-local-changes.state\n' "${LOG_DIR:-/var/log/erpnext-dev}"
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

update_dirty_apps_details() {
  local bench_dir="$1"
  run_as_frappe "cd '${bench_dir}/apps' 2>/dev/null || exit 0
for d in */; do
  app=\"\${d%/}\"
  [ -d \"\$app/.git\" ] || continue
  status=\"\$(git -C \"\$app\" status --short 2>/dev/null || true)\"
  [ -n \"\$status\" ] || continue
  printf '%s\n' \"\$app\"
  printf '%s\n' \"\$status\" | sed 's/^/  /'
done"
}

update_stash_dirty_apps() {
  local bench_dir="$1" stamp="$2"
  run_as_frappe "set -e
cd '${bench_dir}/apps' 2>/dev/null || exit 0
for d in */; do
  app=\"\${d%/}\"
  [ -d \"\$app/.git\" ] || continue
  if [ -n \"\$(git -C \"\$app\" status --porcelain 2>/dev/null)\" ]; then
    before=\"\$(git -C \"\$app\" stash list 2>/dev/null | sed -n '1p' || true)\"
    git -C \"\$app\" stash push --include-untracked -m \"erpnext-dev safe-update ${stamp}\" >/dev/null
    after=\"\$(git -C \"\$app\" stash list 2>/dev/null | sed -n '1p' || true)\"
    if [ -n \"\$after\" ] && [ \"\$after\" != \"\$before\" ]; then
      printf '%s|%s\n' \"\$app\" \"\$after\"
    else
      printf '%s|no stash created\n' \"\$app\"
    fi
  fi
done"
}

run_update_protect_local_changes() {
  require_sudo

  local bench_dir dirty details reply stamp output state_file state_dir tmp_state app_list
  bench_dir="$(require_site_environment)" || return 1
  dirty="$(update_dirty_apps "$bench_dir" 2>/dev/null || true)"

  ui_box_start "Protect Local App Changes"
  status_line "Mode" "INFO" "save dirty app working trees before ERPNext/Frappe update"
  status_line "Bench directory" "OK" "$bench_dir"

  if [[ -z "$dirty" ]]; then
    status_line "App working trees" "OK" "clean; nothing to protect"
    echo "Next: $(toolkit_cmd update-preflight)"
    ui_box_end
    return 0
  fi

  status_line "App working trees" "WARN" "uncommitted local changes in: $(printf '%s' "$dirty" | tr '\n' ' ')"
  details="$(update_dirty_apps_details "$bench_dir" 2>/dev/null || true)"
  if [[ -n "$details" ]]; then
    echo
    echo "Dirty app details:"
    printf '%s\n' "$details" | sed 's/^/  /'
  fi

  echo
  echo "This will run 'git stash push --include-untracked' inside each dirty app repo."
  echo "The stashes are NOT reapplied automatically after the update; review and apply"
  echo "them manually only if you intentionally customized core app code."
  echo

  if [[ "${ASSUME_YES:-0}" -ne 1 && "${UPDATE_PROTECT_CONFIRMED:-0}" != "1" ]]; then
    read -r -p "Type STASH to protect these app changes: " reply
    [[ "$reply" == "STASH" ]] || fail "Local app change protection cancelled."
  fi

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  output="$(update_stash_dirty_apps "$bench_dir" "$stamp")" || {
    ui_box_end
    fail "Could not stash one or more dirty app working trees."
  }

  state_file="$(update_local_changes_state_file)"
  state_dir="$(dirname "$state_file")"
  mkdir -p "$state_dir" 2>/dev/null || true
  tmp_state="$(mktemp "${state_dir}/erpnext-dev-app-stashes.XXXXXX.tmp" 2>/dev/null || mktemp /tmp/erpnext-dev-app-stashes.XXXXXX.tmp)"
  {
    echo "# ERPNext Dev Toolkit — local app changes protected before update"
    echo "UPDATE_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "BENCH_DIR=${bench_dir}"
    echo "SITE_NAME=${SITE_NAME}"
    echo "# app|stash reference"
    printf '%s\n' "$output"
  } >"$tmp_state"
  if mv -f "$tmp_state" "$state_file" 2>/dev/null; then
    chmod 600 "$state_file" 2>/dev/null || true
    status_line "Protection record" "OK" "$state_file"
  else
    rm -f "$tmp_state" 2>/dev/null || true
    status_line "Protection record" "WARN" "could not write ${state_file}; Git stashes were still created"
  fi

  app_list="$(printf '%s\n' "$output" | awk -F'|' 'NF {print $1}' | tr '\n' ' ')"
  status_line "Protected apps" "OK" "${app_list:-none}"
  if [[ -n "$output" ]]; then
    echo
    echo "Created stashes:"
    printf '%s\n' "$output" | while IFS='|' read -r app ref; do
      [[ -n "$app" ]] || continue
      printf '  %-16s %s\n' "$app" "${ref:-unknown}"
    done
  fi

  echo
  echo "Next: $(toolkit_cmd update-preflight), then $(toolkit_cmd safe-update-wizard)."
  ui_box_end
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
    echo "  Protect these from the Updates menu, or run: $(toolkit_cmd protect-local-app-changes)"
    echo "  Advanced/manual: commit, stash, or discard them before upgrading."
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

  local bench_dir reply pre_state latest_lines backup_prefix state_file dirty
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
      dirty="$(update_dirty_apps "$bench_dir" 2>/dev/null || true)"
      if [[ -n "$dirty" ]]; then
        echo
        warn "Preflight found dirty app working trees. Safe Update can protect them with Git stashes, then rerun preflight."
        if [[ "${ASSUME_YES:-0}" -eq 1 || "${UPDATE_AUTO_STASH:-0}" == "1" ]]; then
          UPDATE_PROTECT_CONFIRMED=1 run_update_protect_local_changes
        else
          read -r -p "Type STASH to protect local app changes and retry preflight: " reply
          [[ "$reply" == "STASH" ]] || fail "Preflight found blockers. Resolve them, then re-run $(toolkit_cmd safe-update-wizard)."
          UPDATE_PROTECT_CONFIRMED=1 run_update_protect_local_changes
        fi
        if ! run_update_preflight; then
          fail "Preflight still found blockers after protecting local app changes."
        fi
      else
        fail "Preflight found blockers. Resolve them or re-run with UPDATE_FORCE=1 to override."
      fi
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

# Phase 5 managed update lifecycle. This deliberately coexists with the legacy
# safe-update wizard so existing command contracts do not change.
MANAGED_UPDATE_POLICY="${MANAGED_UPDATE_POLICY:-v1-release-line-16}"
MANAGED_UPDATE_MODE="${MANAGED_UPDATE_MODE:-}"
MANAGED_UPDATE_APP="${MANAGED_UPDATE_APP:-}"
MANAGED_UPDATE_SITE="${MANAGED_UPDATE_SITE:-}"
MANAGED_UPDATE_PREVIEW="${MANAGED_UPDATE_PREVIEW:-0}"
UPDATE_TARGET_SET=""
UPDATE_CURRENT_SET=""
UPDATE_AFFECTED_SITES=""
UPDATE_FAILURE_STAGE=""

managed_update_validate_mode() {
  case "$1" in app | safe | full) return 0 ;; *) return 1 ;; esac
}

managed_update_stable_branch() {
  case "$1" in *nightly* | *preview* | *alpha* | *beta* | *develop*) return 1 ;; *) return 0 ;; esac
}

managed_update_resolve_commit() {
  local repo="$1" revision="$2" result
  [[ "$repo" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]] || return 1
  validate_branch_name "$revision" || return 1
  managed_update_stable_branch "$revision" || return 1
  result="$(git ls-remote --refs "$repo" "refs/heads/${revision}" "refs/tags/${revision}^{}" 2>/dev/null | awk 'NR==1{print $1}')"
  [[ "$result" =~ ^[a-f0-9]{40,64}$ ]] || return 1
  printf '%s\n' "$result"
}

managed_update_inventory_apps() {
  inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" '$1=="APP"&&$2==s&&$10=="managed"{print $3}'
}

managed_update_sites() {
  inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" '$1=="SITE"&&$2==s&&$4=="known"{print $3}'
}

managed_update_select_target() {
  local record selected="" count=0 engine
  engine="$(effective_deployment_engine)"
  while IFS= read -r record; do
    [[ "$record" == STACK\|* ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f3)" == "$engine" ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f6)" == managed ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f7)" == clean ]] || continue
    selected="$record"; count=$((count + 1))
  done < <(inventory_records_sorted)
  [[ "$count" -eq 1 ]] || return 1
  PLAN_STACK="$(printf '%s' "$selected" | cut -d'|' -f2)"
  PLAN_ENGINE="$engine"
  PLAN_BENCH="${PLAN_STACK#native:}"
}

managed_update_build_plan() {
  local mode="$1" requested="${2:-}" app record current branch target repo management source repo_state
  managed_update_validate_mode "$mode" || return 20
  [[ "$mode" != app ]] || inventory_valid_name "$requested" || return 20
  OPERATION_TYPE=managed-update
  OPERATION_UPDATE_MODE="$mode"
  PLAN_APP="${requested:-managed-stack}"
  PLAN_CATALOG_ID="$PLAN_APP"
  PLAN_INSTALL_NAME="$PLAN_APP"
  PLAN_CURRENT_PROFILE="$(effective_installation_profile)"
  PLAN_RESULT_PROFILE="$PLAN_CURRENT_PROFILE"
  inventory_collect
  managed_update_select_target || return 21
  UPDATE_AFFECTED_SITES="$(managed_update_sites | paste -sd, -)"
  [[ -n "$UPDATE_AFFECTED_SITES" ]] || return 21
  [[ -z "$MANAGED_UPDATE_SITE" || ",${UPDATE_AFFECTED_SITES}," == *",${MANAGED_UPDATE_SITE},"* ]] || return 21
  UPDATE_CURRENT_SET="" UPDATE_TARGET_SET=""
  local -a apps=()
  if [[ "$mode" == app ]]; then
    PLAN_APP="$requested"
    planner_resolve_dependencies || return 22
    if [[ -n "$PLAN_DEPENDENCIES" ]]; then
      mapfile -t apps < <(printf '%s\n' "$PLAN_DEPENDENCIES" | tr ',' '\n')
    fi
    apps+=("$requested")
  elif [[ "$mode" == safe ]]; then
    apps=(frappe)
    installation_profile_requires_erpnext && apps+=(erpnext)
  else
    mapfile -t apps < <(managed_update_inventory_apps)
  fi
  ((${#apps[@]} > 0)) || return 22
  for app in "${apps[@]}"; do
    load_validated_app_catalog_record "$app" || return 22
    [[ "$LIB_APP_TRUST" == official || "$LIB_APP_TRUST" == trusted ]] || return 22
    branch="$LIB_APP_BRANCH"
    [[ -n "$branch" ]] || return 24
    managed_update_stable_branch "$branch" || return 22
    repo="$LIB_APP_REPO"
    record="$(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" -v a="$app" '$1=="APP"&&$2==s&&$3==a{print;exit}')"
    [[ -n "$record" ]] || return 22
    current="$(printf '%s' "$record" | cut -d'|' -f7)"
    source="$(printf '%s' "$record" | cut -d'|' -f8)"
    management="$(printf '%s' "$record" | cut -d'|' -f10)"
    repo_state="$(printf '%s' "$record" | cut -d'|' -f11)"
    [[ "$management" == managed && "$current" =~ ^[a-f0-9]{7,64}$ ]] || return 25
    if [[ "$PLAN_ENGINE" == native ]]; then
      [[ "$source" == "$repo" || "$source" == "${repo}.git" ]] || return 25
      [[ "$repo_state" == clean ]] || return 25
    fi
    inventory_compatibility_evaluate "$app" || return 22
    [[ "$INVENTORY_COMPAT_STATUS" == COMPATIBLE ]] || return 22
    target="$(managed_update_resolve_commit "$repo" "$branch")" || return 24
    UPDATE_CURRENT_SET+="${UPDATE_CURRENT_SET:+,}${app}@${current}"
    UPDATE_TARGET_SET+="${UPDATE_TARGET_SET:+,}${app}@${target}"
  done
  PLAN_STACK="${PLAN_STACK}" PLAN_BENCH="${PLAN_BENCH}" PLAN_SITE="${MANAGED_UPDATE_SITE:-${UPDATE_AFFECTED_SITES%%,*}}"
  PLAN_CODE_STATE=available PLAN_SITE_STATE=installed PLAN_DEPENDENCIES=validated PLAN_COMPATIBILITY=compatible PLAN_TRUST=trusted
  PLAN_SHARED_SITES="$UPDATE_AFFECTED_SITES"
  PLAN_ACTIONS="recovery-checkpoint,backup-all-sites,maintenance,update-code-or-image,migrate-all-sites,assets,services,verify-all-sites"
  PLAN_VERIFICATION="revisions,installed-apps,database,http,workers,scheduler,queues,redis,assets,services,inventory,profile"
  PLAN_INVENTORY_FINGERPRINT="$(planner_inventory_fingerprint)"
  PLAN_STARTED_AT="$(planner_timestamp)"
  OPERATION_ID="update-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  OPERATION_FILE="${OPERATION_STATE_DIR}/${OPERATION_ID}.state"
  OPERATION_STATUS=planned OPERATION_CHECKPOINTS=planned
  OPERATION_TARGET_SET="$UPDATE_TARGET_SET" OPERATION_AFFECTED_SITES="$UPDATE_AFFECTED_SITES"
  if [[ "$UPDATE_CURRENT_SET" == "$UPDATE_TARGET_SET" ]]; then
    OPERATION_STATUS=already-complete
  fi
  return 0
}

managed_update_preview() {
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    printf '{"schema_version":1,"read_only":true,"operation_type":"managed-update","mode":"%s","engine":"%s","stack":' "$OPERATION_UPDATE_MODE" "$PLAN_ENGINE"
    inventory_json_escape "$PLAN_STACK"
    printf ',"profile":"%s","affected_sites":' "$PLAN_CURRENT_PROFILE"
    inventory_json_escape "$UPDATE_AFFECTED_SITES"
    printf ',"current_set":'
    inventory_json_escape "$UPDATE_CURRENT_SET"
    printf ',"target_set":'
    inventory_json_escape "$UPDATE_TARGET_SET"
    printf ',"status":"%s"}\n' "$OPERATION_STATUS"
    return
  fi
  ui_box_start "Managed Update Plan"
  status_line "Mode" "INFO" "$OPERATION_UPDATE_MODE"
  status_line "Deployment" "INFO" "$PLAN_ENGINE"
  status_line "Stack" "INFO" "$PLAN_STACK"
  status_line "Profile" "INFO" "$PLAN_CURRENT_PROFILE (preserved)"
  status_line "Affected sites" "INFO" "$UPDATE_AFFECTED_SITES"
  status_line "Current revisions" "INFO" "$UPDATE_CURRENT_SET"
  status_line "Pinned targets" "INFO" "$UPDATE_TARGET_SET"
  status_line "Shared impact" "WARN" "shared code/image; every affected site is backed up, migrated, and verified"
  status_line "Maintenance" "WARN" "controlled maintenance and service restoration"
  status_line "Recovery" "INFO" "exact revisions or previous image plus verified per-site backups"
  ui_box_end
}

managed_update_native_preflight() {
  local item app path branch remote
  [[ "$PLAN_BENCH" == /* && -d "$PLAN_BENCH/apps" && ! -L "$PLAN_BENCH" ]] || return 1
  while IFS= read -r item; do
    app="${item%@*}" path="${PLAN_BENCH}/apps/${app}"
    [[ -d "$path/.git" && ! -L "$path" ]] || return 1
    [[ -z "$(git -C "$path" status --porcelain)" ]] || return 1
    branch="$(git -C "$path" symbolic-ref --short -q HEAD)" || return 1
    load_validated_app_catalog_record "$app" || return 1
    [[ "$branch" == "$LIB_APP_BRANCH" ]] || return 1
    remote="$(git -C "$path" remote get-url origin)" || return 1
    [[ "$remote" == "$LIB_APP_REPO" || "$remote" == "${LIB_APP_REPO}.git" ]] || return 1
    [[ -z "$(git -C "$path" rev-parse -q --verify MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD BISECT_HEAD 2>/dev/null)" ]] || return 1
  done < <(printf '%s\n' "$UPDATE_TARGET_SET" | tr ',' '\n')
  [[ "$(df -Pk "$PLAN_BENCH" | awk 'NR==2{print $4}')" -ge 5242880 ]] || return 1
}

managed_update_backup_native_sites() {
  local site saved="$SITE_NAME" refs=""
  while IFS= read -r site; do
    SITE_NAME="$site"
    create_site_backup true && verify_latest_backup_set >/dev/null || { SITE_NAME="$saved"; return 1; }
    refs+="${refs:+,}${site}:verified"
  done < <(printf '%s\n' "$UPDATE_AFFECTED_SITES" | tr ',' '\n')
  SITE_NAME="$saved" OPERATION_BACKUP_REFERENCE="$refs"
}

managed_update_execute_native() {
  local item app target site fingerprint
  fingerprint="$(planner_inventory_fingerprint)"
  [[ "$fingerprint" == "$PLAN_INVENTORY_FINGERPRINT" ]] || return 34
  UPDATE_FAILURE_STAGE=preflight
  managed_update_native_preflight || return 25
  OPERATION_PREVIOUS_REVISIONS="$UPDATE_CURRENT_SET"
  OPERATION_ORIGINAL_STATE="maintenance=off,service=$(systemctl is-active "${ERPNEXT_SERVICE_NAME:-erpnext-dev}" 2>/dev/null || printf inactive),scheduler=preserve"
  planner_checkpoint recovery-checkpoint-ready validated || return 1
  UPDATE_FAILURE_STAGE=backup
  managed_update_backup_native_sites || return 30
  planner_checkpoint backup-complete backup-complete || return 1
  UPDATE_FAILURE_STAGE=maintenance
  run_as_frappe_quiet "enter maintenance" "cd '${PLAN_BENCH}' && bench set-maintenance-mode on" || return 31
  planner_checkpoint maintenance-entered mutation-started || return 1
  while IFS= read -r item; do
    UPDATE_FAILURE_STAGE=code-update
    app="${item%@*}" target="${item#*@}"
    run_as_frappe "git -C '${PLAN_BENCH}/apps/${app}' fetch --no-tags origin '${target}' && git -C '${PLAN_BENCH}/apps/${app}' merge-base --is-ancestor HEAD '${target}' && git -C '${PLAN_BENCH}/apps/${app}' merge --ff-only '${target}'" || return 31
  done < <(printf '%s\n' "$UPDATE_TARGET_SET" | tr ',' '\n')
  planner_checkpoint code-or-image-updated mutation-complete || return 1
  while IFS= read -r site; do
    UPDATE_FAILURE_STAGE=migration
    run_as_frappe_quiet "update migrate ${site}" "cd '${PLAN_BENCH}' && bench --site '${site}' migrate" || return 33
  done < <(printf '%s\n' "$UPDATE_AFFECTED_SITES" | tr ',' '\n')
  planner_checkpoint migration-complete mutation-complete || return 1
  UPDATE_FAILURE_STAGE=assets
  run_as_frappe_quiet "update assets" "cd '${PLAN_BENCH}' && bench build" || return 33
  planner_checkpoint assets-complete mutation-complete || return 1
  UPDATE_FAILURE_STAGE=services
  run_as_frappe_quiet "leave maintenance" "cd '${PLAN_BENCH}' && bench set-maintenance-mode off" || return 33
  restart_erpnext_service || return 33
  planner_checkpoint services-restored mutation-complete || return 1
  UPDATE_FAILURE_STAGE=verification
  wait_for_erpnext_ready || return 32
  inventory_collect
  planner_checkpoint verification-complete verification-complete || return 1
  PLAN_COMPLETED_AT="$(planner_timestamp)"; planner_checkpoint completed completed
}

managed_update_execute_docker() {
  local profiles=() item app target actual fingerprint site
  [[ "$(docker_mode)" == production ]] || { warn "Docker development updates are temporary unless using a managed cumulative image."; return 23; }
  [[ -f "$DOCKER_APP_MANIFEST_FILE" ]] && docker_validate_app_manifest "$DOCKER_APP_MANIFEST_FILE" || return 25
  OPERATION_PREVIOUS_IMAGE="${DOCKER_ERPNEXT_IMAGE}@${DOCKER_ERPNEXT_IMAGE_DIGEST:-unrecorded}"
  OPERATION_ORIGINAL_STATE="maintenance=off,deployment=${DOCKER_PROJECT_NAME:-erpnext-dev},scheduler=preserve"
  planner_prepare_state_dir || return 1
  [[ ! -L "${OPERATION_STATE_DIR}/${OPERATION_ID}.previous-manifest.tsv" ]] || return 1
  $SUDO cp "$DOCKER_APP_MANIFEST_FILE" "${OPERATION_STATE_DIR}/${OPERATION_ID}.previous-manifest.tsv" || return 1
  mapfile -t profiles < <(awk -F'\t' '$1=="APP"&&$2!="frappe"&&$2!="erpnext"{print $2}' "$DOCKER_APP_MANIFEST_FILE")
  UPDATE_FAILURE_STAGE=manifest
  docker_write_apps_json "${profiles[@]}" || return 25
  planner_checkpoint recovery-checkpoint-ready validated || return 1
  UPDATE_FAILURE_STAGE=image-build
  ASSUME_YES=1 docker_build_custom_image || return 31
  while IFS= read -r item; do
    app="${item%@*}" target="${item#*@}"
    actual="$(${SUDO:-} docker run --rm --entrypoint git "$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE)" -C "/home/frappe/frappe-bench/apps/${app}" rev-parse HEAD 2>/dev/null)"
    [[ "$actual" == "$target" ]] || { UPDATE_FAILURE_STAGE=image-verification; return 32; }
  done < <(printf '%s\n' "$UPDATE_TARGET_SET" | tr ',' '\n')
  planner_checkpoint image-verified validated || return 1
  fingerprint="$(planner_inventory_fingerprint)"
  [[ "$fingerprint" == "$PLAN_INVENTORY_FINGERPRINT" ]] || return 34
  UPDATE_FAILURE_STAGE=backup
  planner_docker_backup_all || return 30
  planner_checkpoint backup-complete backup-complete || return 1
  UPDATE_FAILURE_STAGE=deployment
  DOCKER_DEFER_MANIFEST_PROMOTION=1 ASSUME_YES=1 docker_deploy_custom_image || return 31
  planner_checkpoint code-or-image-updated mutation-complete || return 1
  while IFS= read -r site; do
    UPDATE_FAILURE_STAGE=migration
    docker_bench --site "$site" migrate || return 33
  done < <(printf '%s\n' "$UPDATE_AFFECTED_SITES" | tr ',' '\n')
  planner_checkpoint migration-complete mutation-complete || return 1
  UPDATE_FAILURE_STAGE=verification
  docker_custom_image_verify_runtime "$(docker_custom_image_selected_app_names)" || return 32
  UPDATE_FAILURE_STAGE=manifest-promotion
  docker_promote_app_manifest || return 33
  planner_checkpoint verification-complete verification-complete || return 1
  PLAN_COMPLETED_AT="$(planner_timestamp)"; planner_checkpoint completed completed
}

run_managed_update() {
  local mode="$1" app="${2:-}" rc
  managed_update_build_plan "$mode" "$app" || { rc=$?; err "Could not resolve a trusted compatible update plan (code ${rc})."; return "$rc"; }
  managed_update_preview
  [[ "$OPERATION_STATUS" != already-complete ]] || return 10
  [[ "$MANAGED_UPDATE_PREVIEW" != 1 ]] || return 11
  if [[ "${ASSUME_YES:-0}" -ne 1 ]]; then confirm "Apply this managed update plan?" || return 12; fi
  planner_record_write || return 1
  if [[ "$PLAN_ENGINE" == native ]]; then
    managed_update_execute_native || rc=$?
  else
    managed_update_execute_docker || rc=$?
  fi
  if [[ -n "${rc:-}" ]]; then
    case "$rc" in
      20 | 21 | 22 | 23 | 24 | 25 | 30) planner_fail_record "$UPDATE_FAILURE_STAGE" "Managed update stopped before deployment mutation." "Resolve the reported blocker and create a fresh plan." failed ;;
      *) planner_fail_record "$UPDATE_FAILURE_STAGE" "Managed update did not complete verification." "Use backups ${OPERATION_BACKUP_REFERENCE:-unavailable} with previous revisions/image ${OPERATION_PREVIOUS_REVISIONS:-${OPERATION_PREVIOUS_IMAGE:-unavailable}}; inspect the recorded checkpoint before restoring code, data, files, assets, and services." recovery-required ;;
    esac
    return "$rc"
  fi
}

run_managed_update_availability() {
  local app="${1:-}" mode=safe
  [[ -z "$app" ]] || mode=app
  MANAGED_UPDATE_PREVIEW=1 run_managed_update "$mode" "$app"
}
