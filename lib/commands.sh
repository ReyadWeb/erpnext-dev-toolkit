# shellcheck shell=bash
# Curated initial v1.21-managed subset of existing public commands. Commands
# absent here remain supported legacy CLI commands; absence is not rejection.
[[ -n "${_ERPNEXT_DEV_COMMANDS_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_COMMANDS_LOADED=1

command_registry_records() {
	cat <<'EOF_COMMANDS'
menu||show_menu|user|read-only|none|interactive|safe|native,docker|no
doctor||run_doctor_plain|user|read-only|none|both|safe|native,docker|yes
status||run_status|user|read-only|none|both|safe|native,docker|yes
status-menu||show_status_menu|user|read-only|none|interactive|safe|native,docker|no
health-check|health-check-run-now|run_health_check|user|read-only|none|both|safe|native,docker|yes
health-check-status||show_health_check_status|user|read-only|none|both|safe|native,docker|yes
verify-toolkit|toolkit-verify,verify-install|verify_toolkit_integrity|user|read-only|none|both|safe|native,docker|no
update-toolkit||update_toolkit|root|mutating|required|both|administrative|native,docker|no
toolkit-rollback|update-toolkit-rollback,rollback-toolkit|rollback_toolkit|root|mutating|required|both|administrative|native,docker|no
backup-status||show_backup_status|user|read-only|none|both|safe|native,docker|yes
restore-preflight||show_restore_preflight|root|read-only|required|interactive|safe|native,docker|no
install|setup|run_install|root|mutating|required|both|destructive|native,docker|no
EOF_COMMANDS
}

command_registry_validate() {
	local name aliases handler root mode lock interactive destructive engines json alias
	local -A seen=()
	while IFS='|' read -r name aliases handler root mode lock interactive destructive engines json; do
		[[ -n "$name" && "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
		[[ -z "${seen[$name]:-}" ]] || return 1
		seen["$name"]=1
		declare -F "$handler" >/dev/null 2>&1 || return 1
		[[ "$root" =~ ^(user|root)$ && "$mode" =~ ^(read-only|mutating)$ ]] || return 1
		[[ "$lock" =~ ^(none|required)$ && "$interactive" =~ ^(interactive|non-interactive|both)$ ]] || return 1
		[[ "$destructive" =~ ^(safe|administrative|destructive)$ && "$json" =~ ^(yes|no)$ ]] || return 1
		[[ "$mode" == read-only && "$destructive" == safe || "$mode" == mutating && "$destructive" != safe ]] || return 1
		[[ "$engines" == native,docker || "$engines" == native || "$engines" == docker ]] || return 1
		IFS=',' read -ra _aliases <<<"$aliases"
		for alias in "${_aliases[@]}"; do
			[[ "$alias" =~ ^[a-z0-9][a-z0-9-]*$ && -z "${seen[$alias]:-}" ]] || return 1
			seen["$alias"]="$name"
		done
	done < <(command_registry_records)
}

command_registry_check() { command_registry_validate && command_registry_records; }
