# shellcheck shell=bash
# Installation profile contract: describes which first-party applications a
# deployment must contain. Deployment engine remains the independent "where".
[[ -n "${_ERPNEXT_DEV_PROFILE_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_PROFILE_LOADED=1

normalize_installation_profile() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]_' '[:lower:]-' | tr -d '[:space:]')"
  case "$raw" in
    recommended | default | erpnext | frappe-erpnext) printf 'recommended\n' ;;
    frappe-only | frappe) printf 'frappe-only\n' ;;
    *) return 1 ;;
  esac
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
    *) return 1 ;;
  esac
}

installation_profile_requires_app() {
  local app="$1"
  case "$(effective_installation_profile):${app}" in
    recommended:frappe | recommended:erpnext | frappe-only:frappe) return 0 ;;
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
  printf 'frappe\n'
  installation_profile_requires_erpnext && printf 'erpnext\n'
}

installation_profile_asset_policy() {
  if installation_profile_requires_erpnext; then
    printf 'frappe-and-erpnext\n'
  else
    printf 'frappe-only\n'
  fi
}

installation_profile_health_pair() {
  local app missing=()
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
