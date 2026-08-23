# shellcheck shell=bash
# Installation profile contract: describes which first-party applications a
# deployment must contain. Deployment engine remains the independent "where".
[[ -n "${_ERPNEXT_DEV_PROFILE_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_PROFILE_LOADED=1

normalize_installation_profile() {
  local raw="${1:-}"
  # Reject separators and control bytes before compatibility normalization.
  # Removing them would turn malformed, untrusted input into a valid profile.
  [[ -n "$raw" && ! "$raw" =~ [[:space:][:cntrl:]] ]] || return 1
  raw="$(printf '%s' "$raw" | tr '[:upper:]_' '[:lower:]-')"
  case "$raw" in
    recommended | default | erpnext | frappe-erpnext) printf 'recommended\n' ;;
    frappe-only | frappe) printf 'frappe-only\n' ;;
    advanced) printf 'advanced\n' ;;
    existing) printf 'existing\n' ;;
    *) return 1 ;;
  esac
}

installation_profile_is_setup_intent() {
  case "${1:-}" in
    recommended | frappe-only | advanced | existing) return 0 ;;
    *) return 1 ;;
  esac
}

installation_profile_requires_explicit_apps() {
  [[ "${1:-$(effective_installation_profile)}" == advanced ]]
}

installation_profile_allows_apps_option() {
  installation_profile_requires_explicit_apps "${1:-$(effective_installation_profile)}"
}

installation_profile_plan_preview_requested() {
  [[ "${INSTALLATION_PROFILE_OPTION_PROVIDED:-0}" -eq 1 \
    && "${QUICK_INSTALL_PREVIEW:-0}" -eq 1 \
    && ("${ACTION:-}" == install || "${ACTION:-}" == setup) ]]
}

installation_profile_executable_preview_requested() {
  installation_profile_plan_preview_requested \
    && [[ "$(effective_installation_profile)" == advanced \
      && "${INSTALLATION_PROFILE_APPS_OPTION_PROVIDED:-0}" -eq 1 \
      && "${QUICK_INSTALL_SITE_OPTION_PROVIDED:-0}" -eq 1 ]]
}

validate_installation_profile_value() {
  normalize_installation_profile "$1" >/dev/null 2>&1
}

effective_installation_profile() {
  local resolved
  if resolved="$(normalize_installation_profile "${INSTALLATION_PROFILE:-}" 2>/dev/null)"; then
    printf '%s\n' "$resolved"
  else
    printf 'recommended\n'
  fi
}

installation_profile_label() {
  case "${1:-$(effective_installation_profile)}" in
    recommended) printf 'Recommended (Frappe + ERPNext)\n' ;;
    frappe-only) printf 'Frappe only\n' ;;
    advanced) printf 'Advanced (explicit supported applications)\n' ;;
    existing) printf 'Existing installation management (preview only)\n' ;;
    *) return 1 ;;
  esac
}

installation_profile_erpnext_action() {
  case "${1:-$(effective_installation_profile)}" in
    recommended) printf 'Will be installed\n' ;;
    frappe-only) printf 'Will not be installed\n' ;;
    advanced) printf 'Depends on the validated application plan\n' ;;
    existing) printf 'Observed only; no installation planned\n' ;;
    *) return 1 ;;
  esac
}

# Shared runtime terminology is deliberately profile-neutral: Frappe owns the
# site, Bench/container processes, and service lifecycle. ERPNext is an app.
frappe_runtime_label() { printf 'Frappe stack\n'; }
frappe_service_label() { printf 'managed Frappe stack service\n'; }
frappe_ready_label() { printf 'Frappe site is ready\n'; }
site_administrator_label() { printf 'Site Administrator\n'; }

installation_mode_label() {
  case "${INSTALLATION_MODE:-}" in
    quick) printf 'Quick\n' ;;
    advanced) printf 'Advanced\n' ;;
    existing) printf 'Existing installation\n' ;;
    *) printf 'Non-interactive\n' ;;
  esac
}

installation_profile_requires_app() {
  local app="$1"
  case "$(effective_installation_profile):${app}" in
    recommended:frappe | recommended:erpnext | frappe-only:frappe) return 0 ;;
    advanced:frappe) return 0 ;;
    *) return 1 ;;
  esac
}

installation_profile_requires_erpnext() {
  installation_profile_requires_app erpnext
}

validate_platform_profile_combination() {
  local engine
  engine="$(effective_deployment_engine 2>/dev/null || printf native)"
  [[ "$engine" =~ ^(native|docker)$ ]] || return 1
}

installation_profile_required_apps() {
  case "$(effective_installation_profile)" in
    recommended) printf 'frappe\nerpnext\n' ;;
    frappe-only | advanced) printf 'frappe\n' ;;
    existing) return 0 ;;
  esac
}

installation_profile_asset_policy() {
  if installation_profile_requires_erpnext; then
    printf 'frappe-and-erpnext\n'
  elif [[ "$(effective_installation_profile)" == existing ]]; then
    printf 'observed-existing\n'
  else
    printf 'frappe-only\n'
  fi
}

installation_profile_health_pair() {
  local app missing=() desired observed
  if [[ "$(effective_installation_profile)" == existing ]]; then
    printf 'INFO|Existing installation readiness is deferred; no managed claim is made\n'
    return 0
  fi
  # Operational surfaces may provide a planner reconciliation snapshot. When
  # present it is authoritative: profile metadata or an installed marker alone
  # must never turn incomplete or conflicting evidence into ready.
  if [[ -n "${PROFILE_CONTEXT_RECONCILIATION:-}" ]]; then
    case "$PROFILE_CONTEXT_RECONCILIATION" in
      consistent)
        printf 'OK|desired applications match observed inventory: %s\n' "${PROFILE_CONTEXT_DESIRED_APPS:-none}"
        return 0
        ;;
      drift-extra)
        printf 'INFO|additional observed applications are preserved: %s\n' "${PROFILE_CONTEXT_OBSERVED_APPS:-none}"
        return 0
        ;;
      drift-missing)
        desired="${PROFILE_CONTEXT_DESIRED_APPS:-}"
        observed="${PROFILE_CONTEXT_OBSERVED_APPS:-}"
        while IFS= read -r app; do
          [[ -n "$app" ]] || continue
          case ",${observed}," in *",${app},"*) ;; *) missing+=("$app") ;; esac
        done < <(printf '%s\n' "$desired" | tr ',' '\n')
        printf 'WARN|desired applications missing or unproven: %s\n' "$(IFS=,; printf '%s' "${missing[*]:-unknown}")"
        return 0
        ;;
      ambiguous)
        printf 'WARN|profile reconciliation is ambiguous; application requirements are not fully proven\n'
        return 0
        ;;
      incompatible)
        printf 'FAIL|profile reconciliation is incompatible\n'
        return 0
        ;;
    esac
  fi
  if deployment_engine_is_docker 2>/dev/null; then
    if [[ "$(install_state 2>/dev/null || true)" == "Installed" ]]; then
      printf 'OK|required apps supplied by the %s Docker profile image\n' "$(effective_installation_profile)"
    else
      printf 'WARN|%s Docker profile image is not provisioned\n' "$(effective_installation_profile)"
    fi
    return 0
  fi
  while IFS= read -r app; do
    if ! check_bench_app_installed "$app" || ! site_app_installed "$app"; then
      missing+=("$app")
    fi
  done < <(installation_profile_required_apps)
  if ((${#missing[@]} == 0)); then
    printf 'OK|required apps present: %s\n' "$(installation_profile_required_apps | paste -sd, -)"
  else
    printf 'WARN|required apps missing or unconfirmed: %s\n' "$(
      IFS=,
      printf '%s' "${missing[*]}"
    )"
  fi
}
