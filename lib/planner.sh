# shellcheck shell=bash disable=SC2034
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
OPERATION_PREVIOUS_IMAGE=""
OPERATION_REPLACEMENT_IMAGE=""
OPERATION_TYPE="${OPERATION_TYPE:-quick-app-install}"
OPERATION_UPDATE_MODE=""
OPERATION_TARGET_SET=""
OPERATION_AFFECTED_SITES=""
OPERATION_PREVIOUS_REVISIONS=""
OPERATION_ORIGINAL_STATE=""
OPERATION_REMOVAL_SCOPE=""
OPERATION_SELECTED_SITES=""
OPERATION_PER_SITE_STATE=""
OPERATION_CODE_DECISION=""
OPERATION_PREVIOUS_PROFILE=""
OPERATION_RECOVERY_ELIGIBLE=""
OPERATION_BACKUP_TARGETS=""

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
    "$OPERATION_FAILURE_REASON" "$OPERATION_BACKUP_REFERENCE" "$OPERATION_RECOVERY" \
    "$OPERATION_PREVIOUS_IMAGE" "$OPERATION_REPLACEMENT_IMAGE" "$OPERATION_TYPE" \
    "$OPERATION_UPDATE_MODE" "$OPERATION_TARGET_SET" "$OPERATION_AFFECTED_SITES" "$OPERATION_PREVIOUS_REVISIONS" \
    "$OPERATION_ORIGINAL_STATE" "$OPERATION_REMOVAL_SCOPE" "$OPERATION_SELECTED_SITES" \
    "$OPERATION_PER_SITE_STATE" "$OPERATION_CODE_DECISION" "$OPERATION_PREVIOUS_PROFILE" \
    "$OPERATION_RECOVERY_ELIGIBLE" "$OPERATION_BACKUP_TARGETS"; do
    planner_safe_value "$value" || return 1
  done
  {
    printf 'schema=1\n'
    printf 'operation_id=%s\n' "$OPERATION_ID"
    printf 'operation_type=%s\n' "$OPERATION_TYPE"
    printf 'update_mode=%s\n' "$OPERATION_UPDATE_MODE"
    printf 'target_set=%s\n' "$OPERATION_TARGET_SET"
    printf 'affected_sites=%s\n' "$OPERATION_AFFECTED_SITES"
    printf 'previous_revisions=%s\n' "$OPERATION_PREVIOUS_REVISIONS"
    printf 'original_runtime_state=%s\n' "$OPERATION_ORIGINAL_STATE"
    printf 'removal_scope=%s\n' "$OPERATION_REMOVAL_SCOPE"
    printf 'selected_sites=%s\n' "$OPERATION_SELECTED_SITES"
    printf 'per_site_state=%s\n' "$OPERATION_PER_SITE_STATE"
    printf 'code_decision=%s\n' "$OPERATION_CODE_DECISION"
    printf 'previous_profile=%s\n' "$OPERATION_PREVIOUS_PROFILE"
    printf 'recovery_eligible=%s\n' "$OPERATION_RECOVERY_ELIGIBLE"
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
    printf 'backup_targets=%s\n' "${OPERATION_BACKUP_TARGETS:-$PLAN_SITE}"
    printf 'planned_actions=%s\n' "$PLAN_ACTIONS"
    printf 'verification=%s\n' "$PLAN_VERIFICATION"
    printf 'status=%s\n' "$OPERATION_STATUS"
    printf 'checkpoints=%s\n' "$OPERATION_CHECKPOINTS"
    printf 'failure_stage=%s\n' "$OPERATION_FAILURE_STAGE"
    printf 'failure_reason=%s\n' "$OPERATION_FAILURE_REASON"
    printf 'backup_reference=%s\n' "$OPERATION_BACKUP_REFERENCE"
    printf 'previous_image=%s\n' "$OPERATION_PREVIOUS_IMAGE"
    printf 'replacement_image=%s\n' "$OPERATION_REPLACEMENT_IMAGE"
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
  # Hash normalized observable fields only. Repository URLs, credentials, and
  # other potentially sensitive/raw values are deliberately excluded. Source
  # trust is represented by a non-secret classification so a trust change still
  # invalidates a previously reviewed fingerprint.
  local record kind
  while IFS= read -r record; do
    kind="${record%%|*}"
    case "$kind" in
      STACK)
        printf '%s|%s\n' "$kind" \
          "$(printf '%s' "$record" | cut -d'|' -f3-7)"
        ;;
      APP)
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$kind" \
          "$(printf '%s' "$record" | cut -d'|' -f3)" \
          "$(printf '%s' "$record" | cut -d'|' -f4)" \
          "$(printf '%s' "$record" | cut -d'|' -f5)" \
          "$(printf '%s' "$record" | cut -d'|' -f6)" \
          "$(installation_profile_inventory_source_classification "$record")" \
          "$(printf '%s' "$record" | cut -d'|' -f9)" \
          "$(printf '%s' "$record" | cut -d'|' -f10)" \
          "$(printf '%s' "$record" | cut -d'|' -f11)"
        ;;
      SITE) printf '%s|%s\n' "$kind" "$(printf '%s' "$record" | cut -d'|' -f3-4)" ;;
      SITE_APP) printf '%s|%s\n' "$kind" "$(printf '%s' "$record" | cut -d'|' -f3-5)" ;;
      ISSUE) printf '%s|%s\n' "$kind" "$(printf '%s' "$record" | cut -d'|' -f3-5)" ;;
    esac
  done < <(inventory_records_sorted) | LC_ALL=C sort | sha256sum | awk '{print $1}'
}

installation_profile_inventory_source_classification() {
  local record="$1" app source expected_repo engine
  app="$(printf '%s' "$record" | cut -d'|' -f3)"
  source="$(printf '%s' "$record" | cut -d'|' -f8)"
  [[ "$source" != unknown ]] || {
    printf 'unknown\n'
    return
  }
  load_validated_app_catalog_record "$app" >/dev/null 2>&1 || {
    printf 'unmanaged\n'
    return
  }
  expected_repo="$LIB_APP_REPO"
  if [[ "$source" != image:* ]]; then
    [[ "${source%.git}" == "${expected_repo%.git}" ]] && printf 'catalog-match\n' || printf 'catalog-mismatch\n'
    return
  fi
  engine="${PROFILE_PLAN_ENGINE:-$(effective_deployment_engine)}"
  if [[ "$engine" == docker && "$source" == image:frappe/erpnext:* \
    && ("$app" == frappe || "$app" == erpnext) ]]; then
    printf 'verified-built-in-image\n'
  elif [[ "$engine" == docker ]] && inventory_docker_manifest_trusts_app "$app"; then
    printf 'verified-manifest-image\n'
  else
    printf 'unverified-image\n'
  fi
}

installation_profile_capability_evaluate() {
  local profile="$1" engine="$2" environment="$3" app
  PROFILE_PLAN_CAPABILITY="unsupported"
  PROFILE_PLAN_DURABLE_IMAGE="false"
  PROFILE_PLAN_CAPABILITY_DETAIL="Unsupported engine/environment/profile combination."

  case "${engine}:${environment}" in
    native:native | docker:development | docker:production) ;;
    *) return 1 ;;
  esac

  if [[ "$profile" == existing ]]; then
    PROFILE_PLAN_CAPABILITY="preview-only"
    PROFILE_PLAN_CAPABILITY_DETAIL="Existing-installation management is validation and preview only in PR 7.1."
    return 0
  fi

  for app in "${PROFILE_PLAN_DESIRED_APPS[@]}"; do
    load_validated_app_catalog_record "$app" >/dev/null 2>&1 || return 1
    case "${engine}:${environment}" in
      native:native)
        [[ "$LIB_APP_NATIVE_SUPPORT" == supported ]] || return 1
        ;;
      docker:development)
        [[ "$LIB_APP_DOCKER_DEV_SUPPORT" == supported ]] || return 1
        ;;
      docker:production)
        [[ "$LIB_APP_DOCKER_PROD_STRATEGY" != unsupported ]] || return 1
        ;;
    esac
  done

  if [[ "$engine" == docker && "$environment" == production ]] \
    && { [[ "$profile" == advanced ]] || [[ "$profile" == frappe-only ]]; }; then
    PROFILE_PLAN_CAPABILITY="durable-image-required"
    PROFILE_PLAN_DURABLE_IMAGE="true"
    PROFILE_PLAN_CAPABILITY_DETAIL="A verified cumulative custom image is required; running containers must not be mutated."
  elif [[ "$profile" == advanced ]]; then
    PROFILE_PLAN_CAPABILITY="preview-only"
    PROFILE_PLAN_CAPABILITY_DETAIL="The shared plan is valid; the installation adapter is intentionally deferred."
  else
    PROFILE_PLAN_CAPABILITY="supported"
    PROFILE_PLAN_CAPABILITY_DETAIL="The existing profile adapter supports this engine and environment."
  fi
}

installation_profile_reconcile() {
  local record stack engine environment management state site site_state app desired observed_csv desired_csv
  local -A observed=() wanted=()
  local extra=0 missing=0 stack_count=0 site_count=0 target_stack="" target_site=""
  local proof_rc=0 proof_scope="observed"

  PROFILE_PLAN_RECONCILIATION="ambiguous"
  PROFILE_PLAN_OBSERVED_APPS=""
  PROFILE_PLAN_OBSERVED_SUMMARY="Inventory is incomplete or unavailable."

  if [[ "${PROFILE_METADATA_STATUS:-compatible}" == incompatible \
    || "$PROFILE_PLAN_CAPABILITY" == unsupported ]]; then
    PROFILE_PLAN_RECONCILIATION="incompatible"
    PROFILE_PLAN_OBSERVED_SUMMARY="Configuration schema or capability validation is incompatible."
    return 0
  fi

  # Known policy failures outrank structural ambiguity. Inspect every discovered
  # stack and catalog application without selecting or combining targets.
  while IFS= read -r record; do
    case "${record%%|*}" in
      STACK)
        engine="$(printf '%s' "$record" | cut -d'|' -f3)"
        environment="$(printf '%s' "$record" | cut -d'|' -f4)"
        if [[ "$engine" != "${PROFILE_PLAN_ENGINE:-$engine}" \
          || "$environment" != "${PROFILE_PLAN_ENVIRONMENT:-$environment}" ]] \
          || [[ ! "${engine}:${environment}" =~ ^(native:native|docker:development|docker:production)$ ]]; then
          PROFILE_PLAN_RECONCILIATION="incompatible"
          PROFILE_PLAN_OBSERVED_SUMMARY="Observed engine or topology is incompatible with the requested plan."
          return 0
        fi
        ;;
      APP)
        if installation_profile_app_record_known_incompatible "$record"; then
          PROFILE_PLAN_RECONCILIATION="incompatible"
          PROFILE_PLAN_OBSERVED_SUMMARY="Observed application major, source, trust, or deployment support is incompatible."
          return 0
        fi
        ;;
    esac
  done < <(inventory_records_sorted)

  stack_count="$(inventory_records_sorted | awk -F'|' '$1=="STACK" {n++} END {print n+0}')"
  site_count="$(inventory_records_sorted | awk -F'|' '$1=="SITE" {n++} END {print n+0}')"
  if [[ "$stack_count" -ne 1 || "$site_count" -ne 1 ]] || inventory_has_ambiguous_state; then
    PROFILE_PLAN_RECONCILIATION="ambiguous"
    PROFILE_PLAN_OBSERVED_SUMMARY="Exactly one clean target stack and one complete site inventory must be proven."
    return 0
  fi

  record="$(inventory_records_sorted | awk -F'|' '$1=="STACK" {print; exit}')"
  target_stack="$(printf '%s' "$record" | cut -d'|' -f2)"
  management="$(printf '%s' "$record" | cut -d'|' -f6)"
  state="$(printf '%s' "$record" | cut -d'|' -f7)"
  record="$(inventory_records_sorted | awk -F'|' '$1=="SITE" {print; exit}')"
  stack="$(printf '%s' "$record" | cut -d'|' -f2)"
  site="$(printf '%s' "$record" | cut -d'|' -f3)"
  site_state="$(printf '%s' "$record" | cut -d'|' -f4)"
  if [[ "$target_stack" != "$stack" || "$state" != clean || "$site_state" != known ]]; then
    PROFILE_PLAN_RECONCILIATION="ambiguous"
    PROFILE_PLAN_OBSERVED_SUMMARY="Target stack cleanliness or site inventory completeness cannot be proven."
    return 0
  fi
  target_site="$site"

  while IFS= read -r record; do
    [[ "${record%%|*}" == SITE_APP ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f2)" == "$target_stack" \
      && "$(printf '%s' "$record" | cut -d'|' -f3)" == "$target_site" ]] || continue
    app="$(printf '%s' "$record" | cut -d'|' -f4)"
    inventory_valid_name "$app" && observed["$app"]=1
  done < <(inventory_records_sorted)
  observed_csv="$(printf '%s\n' "${!observed[@]}" | sed '/^$/d' | LC_ALL=C sort | paste -sd, -)"
  PROFILE_PLAN_OBSERVED_APPS="$observed_csv"

  # Every site-app record must have one available code record. Desired catalog
  # applications additionally require proven major/source/trust compatibility.
  for app in "${!observed[@]}"; do
    proof_rc=0
    proof_scope="observed"
    [[ "$app" == frappe || "$app" == erpnext ]] && proof_scope="desired"
    installation_profile_app_proof "$target_stack" "$app" "$proof_scope" || proof_rc=$?
    if [[ "$proof_rc" -ne 0 ]]; then
      PROFILE_PLAN_RECONCILIATION="ambiguous"
      PROFILE_PLAN_OBSERVED_SUMMARY="Observed site application code is missing, dirty, unknown, or conflicting."
      return 0
    fi
  done

  desired_csv="$PROFILE_PLAN_DESIRED_CSV"
  while IFS= read -r desired; do
    [[ -n "$desired" ]] && wanted["$desired"]=1
  done < <(printf '%s\n' "$desired_csv" | tr ',' '\n')
  for desired in "${!wanted[@]}"; do
    [[ -n "${observed[$desired]:-}" ]] || missing=1
    if [[ -n "${observed[$desired]:-}" ]]; then
      proof_rc=0
      installation_profile_app_proof "$target_stack" "$desired" desired || proof_rc=$?
      if [[ "$proof_rc" -eq 1 ]]; then
        PROFILE_PLAN_RECONCILIATION="incompatible"
        PROFILE_PLAN_OBSERVED_SUMMARY="Desired application compatibility proof failed."
        return 0
      elif [[ "$proof_rc" -ne 0 ]]; then
        PROFILE_PLAN_RECONCILIATION="ambiguous"
        PROFILE_PLAN_OBSERVED_SUMMARY="Desired application code or trust proof is incomplete."
        return 0
      fi
    fi
  done
  for app in "${!observed[@]}"; do
    [[ -n "${wanted[$app]:-}" ]] || extra=1
  done
  if [[ "$management" != managed ]]; then
    PROFILE_PLAN_RECONCILIATION="unmanaged"
    PROFILE_PLAN_OBSERVED_SUMMARY="One compatible target remains unmanaged; no adoption occurred."
  elif [[ "${PROFILE_PLAN_PROFILE:-}" == existing ]]; then
    PROFILE_PLAN_RECONCILIATION="unmanaged"
    PROFILE_PLAN_OBSERVED_SUMMARY="One compatible existing target was discovered; no adoption occurred."
  elif ((missing)); then
    PROFILE_PLAN_RECONCILIATION="drift-missing"
    PROFILE_PLAN_OBSERVED_SUMMARY="One or more desired applications are not observed as installed."
  elif ((extra)); then
    PROFILE_PLAN_RECONCILIATION="drift-extra"
    PROFILE_PLAN_OBSERVED_SUMMARY="Additional observed applications will be preserved."
  else
    PROFILE_PLAN_RECONCILIATION="consistent"
    PROFILE_PLAN_OBSERVED_SUMMARY="Observed installed applications match the desired plan."
  fi
}

installation_profile_app_record_known_incompatible() {
  local record="$1" app availability version branch source trust engine environment major expected_repo
  app="$(printf '%s' "$record" | cut -d'|' -f3)"
  load_validated_app_catalog_record "$app" >/dev/null 2>&1 || return 1
  availability="$(printf '%s' "$record" | cut -d'|' -f4)"
  version="$(printf '%s' "$record" | cut -d'|' -f5)"
  branch="$(printf '%s' "$record" | cut -d'|' -f6)"
  source="$(printf '%s' "$record" | cut -d'|' -f8)"
  trust="$(printf '%s' "$record" | cut -d'|' -f9)"
  expected_repo="$LIB_APP_REPO"
  engine="${PROFILE_PLAN_ENGINE:-$(effective_deployment_engine)}"
  environment="${PROFILE_PLAN_ENVIRONMENT:-$(docker_mode 2>/dev/null || printf native)}"

  [[ "$availability" == available ]] || return 1
  inventory_deployment_supported "$engine" "$environment" "$LIB_APP_NATIVE_SUPPORT" \
    "$LIB_APP_DOCKER_DEV_SUPPORT" "$LIB_APP_DOCKER_PROD_STRATEGY" || return 0
  [[ "$trust" == "$LIB_APP_TRUST" ]] || return 0
  if [[ "$source" != unknown && "$source" != image:* \
    && "${source%.git}" != "${expected_repo%.git}" ]]; then
    return 0
  fi
  if [[ "$source" == image:* && "$engine" != docker ]]; then
    return 0
  fi
  if [[ "$source" == image:* && "$engine" == docker ]]; then
    if [[ "$source" != image:frappe/erpnext:* || ("$app" != frappe && "$app" != erpnext) ]]; then
      inventory_docker_manifest_trusts_app "$app" || return 0
    fi
  fi
  if [[ "$app" == frappe || "$app" == erpnext ]]; then
    major=""
    if [[ "$version" =~ ^v?([0-9]+) ]]; then
      major="${BASH_REMATCH[1]}"
    elif [[ "$branch" =~ ^version-([0-9]+)$ ]]; then
      major="${BASH_REMATCH[1]}"
    fi
    [[ -z "$major" ]] && return 1
    if [[ "$app" == frappe ]]; then
      [[ ",${LIB_APP_SUPPORTED_FRAPPE}," == *",${major},"* ]] || return 0
    else
      [[ ",${LIB_APP_SUPPORTED_ERPNEXT}," == *",${major},"* ]] || return 0
    fi
  fi
  return 1
}

installation_profile_app_proof() {
  local stack="$1" app="$2" scope="$3" record count availability version branch source repo_state management major=""
  count="$(inventory_records_sorted | awk -F'|' -v s="$stack" -v a="$app" '$1=="APP"&&$2==s&&$3==a {n++} END {print n+0}')"
  [[ "$count" -eq 1 ]] || return 2
  record="$(inventory_records_sorted | awk -F'|' -v s="$stack" -v a="$app" '$1=="APP"&&$2==s&&$3==a {print; exit}')"
  availability="$(printf '%s' "$record" | cut -d'|' -f4)"
  version="$(printf '%s' "$record" | cut -d'|' -f5)"
  branch="$(printf '%s' "$record" | cut -d'|' -f6)"
  source="$(printf '%s' "$record" | cut -d'|' -f8)"
  management="$(printf '%s' "$record" | cut -d'|' -f10)"
  repo_state="$(printf '%s' "$record" | cut -d'|' -f11)"
  [[ "$availability" == available && "$management" == managed ]] || return 2
  [[ "$repo_state" == clean || "$repo_state" == immutable ]] || return 2
  [[ "$source" != unknown ]] || return 2
  if [[ "$scope" == desired ]]; then
    load_validated_app_catalog_record "$app" >/dev/null 2>&1 || return 2
    if [[ "$app" == frappe || "$app" == erpnext ]]; then
      if [[ "$version" =~ ^v?([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
      elif [[ "$branch" =~ ^version-([0-9]+)$ ]]; then
        major="${BASH_REMATCH[1]}"
      fi
      [[ -n "$major" ]] || return 2
    fi
    installation_profile_app_record_known_incompatible "$record" && return 1
  fi
  return 0
}

installation_profile_plan_build() {
  local profile="$1" apps_raw="${2:-}" engine environment metadata_file="${3:-${CONFIG_FILE:-}}"
  PROFILE_PLAN_VALID="false"
  PROFILE_PLAN_ERROR=""
  PROFILE_PLAN_PROFILE="$profile"
  PROFILE_PLAN_REQUESTED_APPS=()
  PROFILE_PLAN_REQUESTED_CSV=""
  PROFILE_PLAN_DESIRED_APPS=()
  PROFILE_PLAN_DESIRED_CSV=""
  PROFILE_PLAN_RECONCILIATION="ambiguous"
  PROFILE_PLAN_METADATA_STATE="unavailable"

  installation_profile_is_setup_intent "$profile" || {
    PROFILE_PLAN_ERROR="Invalid canonical installation profile."
    return 20
  }
  if [[ "$profile" == advanced ]]; then
    profile_plan_parse_requested_apps "$apps_raw" || return 20
  elif [[ -n "$apps_raw" ]]; then
    PROFILE_PLAN_ERROR="--apps is valid only with --profile advanced."
    return 20
  fi
  profile_plan_resolve_apps "$profile" || return 22

  engine="$(effective_deployment_engine)"
  if [[ "$engine" == docker ]]; then
    environment="$(docker_mode 2>/dev/null || printf development)"
  else
    environment="native"
  fi
  PROFILE_PLAN_ENGINE="$engine"
  PROFILE_PLAN_ENVIRONMENT="$environment"
  installation_profile_capability_evaluate "$profile" "$engine" "$environment" || {
    PROFILE_PLAN_ERROR="$PROFILE_PLAN_CAPABILITY_DETAIL"
    return 23
  }

  read_installation_profile_metadata "$metadata_file" >/dev/null 2>&1 || true
  if [[ "${PROFILE_METADATA_STATUS:-unmanaged}" == incompatible ]]; then
    PROFILE_PLAN_METADATA_STATE="incompatible"
  elif [[ "${PROFILE_METADATA_STATUS:-unmanaged}" == unmanaged ]]; then
    PROFILE_PLAN_METADATA_STATE="unavailable"
  elif [[ "${PROFILE_METADATA_EXPLICIT:-false}" != true ]]; then
    PROFILE_PLAN_METADATA_STATE="unavailable"
  elif [[ "${PROFILE_METADATA_PROFILE:-recommended}" == "$profile" ]]; then
    PROFILE_PLAN_METADATA_STATE="matches-request"
  else
    PROFILE_PLAN_METADATA_STATE="stale"
    PROFILE_PLAN_CAPABILITY_DETAIL="${PROFILE_PLAN_CAPABILITY_DETAIL} Persisted intent differs from this explicit request and was not treated as installed reality."
  fi
  inventory_collect
  PROFILE_PLAN_INVENTORY_FINGERPRINT="$(planner_inventory_fingerprint)"
  installation_profile_reconcile
  if [[ "$PROFILE_PLAN_RECONCILIATION" == incompatible ]]; then
    PROFILE_PLAN_ERROR="Observed configuration or capability is incompatible with read-only planning."
    return 22
  fi
  PROFILE_PLAN_VALID="true"
}

installation_profile_plan_json_array() {
  local csv="${1:-}" first=1 item
  printf '['
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    ((first)) || printf ','
    first=0
    inventory_json_escape "$item"
  done < <(printf '%s\n' "$csv" | tr ',' '\n')
  printf ']'
}

installation_profile_plan_emit_json() {
  printf '{"schema_version":1,"read_only":true,"valid":%s' "$PROFILE_PLAN_VALID"
  printf ',"profile":'; inventory_json_escape "${PROFILE_PLAN_PROFILE:-unknown}"
  printf ',"requested_applications":'; installation_profile_plan_json_array "${PROFILE_PLAN_REQUESTED_CSV:-}"
  printf ',"desired_applications":'; installation_profile_plan_json_array "${PROFILE_PLAN_DESIRED_CSV:-}"
  printf ',"engine":'; inventory_json_escape "${PROFILE_PLAN_ENGINE:-unknown}"
  printf ',"environment":'; inventory_json_escape "${PROFILE_PLAN_ENVIRONMENT:-unknown}"
  printf ',"capability":'; inventory_json_escape "${PROFILE_PLAN_CAPABILITY:-unsupported}"
  printf ',"durable_image_required":%s' "${PROFILE_PLAN_DURABLE_IMAGE:-false}"
  printf ',"observed_applications":'; installation_profile_plan_json_array "${PROFILE_PLAN_OBSERVED_APPS:-}"
  printf ',"observed_summary":'; inventory_json_escape "${PROFILE_PLAN_OBSERVED_SUMMARY:-Inventory unavailable.}"
  printf ',"inventory_fingerprint":'; inventory_json_escape "${PROFILE_PLAN_INVENTORY_FINGERPRINT:-unavailable}"
  printf ',"configuration_schema":'; inventory_json_escape "${PROFILE_METADATA_SCHEMA:-unavailable}"
  printf ',"metadata_state":'; inventory_json_escape "${PROFILE_PLAN_METADATA_STATE:-unavailable}"
  printf ',"reconciliation":'; inventory_json_escape "${PROFILE_PLAN_RECONCILIATION:-incompatible}"
  printf ',"warning":'; inventory_json_escape "${PROFILE_PLAN_CAPABILITY_DETAIL:-}"
  printf ',"blocking_error":'; inventory_json_escape "${PROFILE_PLAN_ERROR:-}"
  printf ',"mutation_performed":false}\n'
}

installation_profile_plan_emit_human() {
  printf 'Installation Profile Plan (schema 1)\n'
  printf 'Read only: yes\n'
  printf 'Profile: %s\n' "${PROFILE_PLAN_PROFILE:-unknown}"
  printf 'Requested applications: %s\n' "${PROFILE_PLAN_REQUESTED_CSV:-none}"
  printf 'Desired applications: %s\n' "${PROFILE_PLAN_DESIRED_CSV:-none}"
  printf 'Engine/environment: %s/%s\n' "${PROFILE_PLAN_ENGINE:-unknown}" "${PROFILE_PLAN_ENVIRONMENT:-unknown}"
  printf 'Capability: %s\n' "${PROFILE_PLAN_CAPABILITY:-unsupported}"
  printf 'Durable Docker image required: %s\n' "${PROFILE_PLAN_DURABLE_IMAGE:-false}"
  printf 'Observed applications: %s\n' "${PROFILE_PLAN_OBSERVED_APPS:-none}"
  printf 'Observed inventory: %s\n' "${PROFILE_PLAN_OBSERVED_SUMMARY:-Inventory unavailable.}"
  printf 'Inventory fingerprint: %s\n' "${PROFILE_PLAN_INVENTORY_FINGERPRINT:-unavailable}"
  printf 'Configuration schema: %s\n' "${PROFILE_METADATA_SCHEMA:-unavailable}"
  printf 'Persisted metadata: %s\n' "${PROFILE_PLAN_METADATA_STATE:-unavailable}"
  printf 'Reconciliation: %s\n' "${PROFILE_PLAN_RECONCILIATION:-incompatible}"
  [[ -z "${PROFILE_PLAN_CAPABILITY_DETAIL:-}" ]] || printf 'Warning: %s\n' "$PROFILE_PLAN_CAPABILITY_DETAIL"
  [[ -z "${PROFILE_PLAN_ERROR:-}" ]] || printf 'Blocking error: %s\n' "$PROFILE_PLAN_ERROR"
  printf 'NO DEPLOYMENT MUTATION OCCURRED.\n'
}

run_installation_profile_preview() {
  local rc=0 profile
  profile="$(normalize_installation_profile "${INSTALLATION_PROFILE:-}" 2>/dev/null)" || rc=20
  if ((rc == 0)); then
    installation_profile_plan_build "$profile" "${INSTALLATION_PROFILE_APPS_RAW:-}" || rc=$?
  else
    PROFILE_PLAN_VALID="false"
    PROFILE_PLAN_PROFILE="invalid"
    PROFILE_PLAN_ERROR="Invalid installation profile."
  fi
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    installation_profile_plan_emit_json
  else
    installation_profile_plan_emit_human
  fi
  return "$rc"
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
  local record count=0 selected="" site_count=0 site_record engine
  engine="$(effective_deployment_engine)"
  while IFS= read -r record; do
    [[ "$record" == STACK\|* ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f3)" == "$engine" ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f6)" == managed ]] || continue
    [[ "$(printf '%s' "$record" | cut -d'|' -f7)" == clean ]] || continue
    selected="$record"
    count=$((count + 1))
  done < <(inventory_records_sorted)
  [[ "$count" -eq 1 ]] || return 2
  PLAN_STACK="$(printf '%s' "$selected" | cut -d'|' -f2)"
  PLAN_ENGINE="$engine"
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
  if [[ "$PLAN_ENGINE" == docker && "$(docker_mode)" == production ]]; then
    PLAN_ACTIONS="write-cumulative-manifest,build-image,verify-image,backup-sites,capture-previous-image,deploy-image,install-site-app,migrate,verify-stack"
  elif [[ "$PLAN_ENGINE" == docker ]]; then
    PLAN_ACTIONS="development-only-container-code,install-site-app,migrate"
  else
    PLAN_ACTIONS="backup-site"
    [[ "$PLAN_CODE_STATE" == available ]] || PLAN_ACTIONS+=",acquire-bench-code"
    [[ -n "$PLAN_DEPENDENCIES" ]] && PLAN_ACTIONS+=",install-dependencies"
    PLAN_ACTIONS+=",install-site-app,migrate,build-assets,clear-cache,restart-services"
  fi
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
    printf ',"status":"%s","engine":"%s","stack":' "$OPERATION_STATUS" "$PLAN_ENGINE"
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
  status_line "Deployment" "INFO" "$PLAN_ENGINE ($(docker_mode 2>/dev/null || printf native))"
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

planner_docker_backup_all() {
  local site saved_site="${DOCKER_SITE_NAME:-}" refs=""
  while IFS= read -r site; do
    [[ -n "$site" ]] || continue
    DOCKER_SITE_NAME="$site"
    docker_backup true || {
      DOCKER_SITE_NAME="$saved_site"
      return 1
    }
    docker_backup_verify || {
      DOCKER_SITE_NAME="$saved_site"
      return 1
    }
    refs="${refs}${refs:+,}${site}:verified"
  done < <(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" '$1=="SITE"&&$2==s{print $3}')
  DOCKER_SITE_NAME="$saved_site"
  OPERATION_BACKUP_REFERENCE="$refs"
  [[ -n "$refs" ]]
}

planner_execute_docker_production() {
  local current_fingerprint profile="" saved_profile="$INSTALLATION_PROFILE" image image_id requested=""
  if [[ "$PLAN_APP" != erpnext ]]; then
    profile="$(docker_profile_for_app_name "$PLAN_APP")" || return 22
    requested="$profile"
  fi
  INSTALLATION_PROFILE="$PLAN_RESULT_PROFILE"
  current_fingerprint="$(planner_inventory_fingerprint)"
  [[ "$current_fingerprint" == "$PLAN_INVENTORY_FINGERPRINT" ]] || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record preflight "Inventory changed after preview." "Generate and confirm a fresh plan."
    return 34
  }
  planner_checkpoint validated validated || return 1
  mapfile -t PLAN_DOCKER_PROFILES < <(docker_collect_desired_app_profiles "$requested")
  docker_write_apps_json "${PLAN_DOCKER_PROFILES[@]}" || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record manifest "Cumulative manifest validation failed." "Correct the managed manifest; deployment was unchanged."
    return 22
  }
  planner_checkpoint manifest-validated validated || return 1
  ASSUME_YES=1 docker_build_custom_image || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record image-build "Replacement image build failed." "Running deployment was unchanged."
    return 31
  }
  image="$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE)"
  image_id="$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE_ID)"
  [[ -n "$image" && "$image_id" =~ ^sha256: ]] || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record image-verify "Replacement image digest was not verified." "Running deployment was unchanged."
    return 32
  }
  OPERATION_REPLACEMENT_IMAGE="${image}@${image_id}"
  planner_checkpoint image-verified validated || return 1
  inventory_collect
  [[ "$(planner_inventory_fingerprint)" == "$PLAN_INVENTORY_FINGERPRINT" ]] || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record pre-backup "Inventory changed during image build." "Discard the candidate image and create a fresh plan."
    return 34
  }
  planner_docker_backup_all || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record backup "A Docker site backup failed verification." "Deployment was not changed."
    return 30
  }
  planner_checkpoint backup-complete backup-complete || return 1
  OPERATION_PREVIOUS_IMAGE="${DOCKER_ERPNEXT_IMAGE}@${DOCKER_ERPNEXT_IMAGE_DIGEST:-unrecorded}"
  planner_checkpoint previous-image-recorded backup-complete || return 1
  ASSUME_YES=1 docker_deploy_custom_image || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record deployment "Replacement-image deployment failed." "Redeploy ${OPERATION_PREVIOUS_IMAGE}; restore from ${OPERATION_BACKUP_REFERENCE} if site data changed." recovery-required
    return 31
  }
  planner_checkpoint mutation-complete mutation-complete || return 1
  inventory_collect
  planner_site_installed "$PLAN_STACK" "$PLAN_SITE" "$PLAN_APP" || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record verification "Docker post-deployment inventory verification failed." "Previous image: ${OPERATION_PREVIOUS_IMAGE}; backups: ${OPERATION_BACKUP_REFERENCE}." recovery-required
    return 32
  }
  docker_custom_image_verify_runtime "$(docker_custom_image_selected_app_names)" || {
    INSTALLATION_PROFILE="$saved_profile"
    planner_fail_record verification "Docker stack health verification failed." "Previous image: ${OPERATION_PREVIOUS_IMAGE}; backups: ${OPERATION_BACKUP_REFERENCE}." recovery-required
    return 32
  }
  planner_checkpoint verification-complete verification-complete || return 1
  if [[ "$PLAN_RESULT_PROFILE" != "$PLAN_CURRENT_PROFILE" ]]; then
    INSTALLATION_PROFILE="$PLAN_RESULT_PROFILE"
    write_dev_config_file || {
      INSTALLATION_PROFILE="$saved_profile"
      return 33
    }
  fi
  PLAN_COMPLETED_AT="$(planner_timestamp)"
  planner_checkpoint completed completed
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
  if [[ "$PLAN_ENGINE" == docker ]]; then
    if [[ "$(docker_mode)" == production ]]; then
      planner_execute_docker_production
      return
    fi
    warn "Docker development mutation is temporary and may be lost on container recreation."
    OPERATION_RECOVERY="Development-only container state is not durable; rebuild the cumulative image or re-run after recreation."
    load_validated_app_catalog_record "$PLAN_APP" || return 22
    ASSUME_YES=1 docker_install_app "$LIB_APP_NAME" "$LIB_APP_DISPLAY" "$LIB_APP_REPO" "$LIB_APP_BRANCH" || return 31
    PLAN_COMPLETED_AT="$(planner_timestamp)"
    planner_checkpoint development-temporary completed
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
      23) err "Quick installation is unsupported on the selected deployment method." ;;
      *) err "Could not build a safe operation plan." ;;
    esac
    return "$rc"
  }
  planner_preview
  planner_execute
}
