# shellcheck shell=bash
# Curated initial v1.21-managed subset of existing public commands. Commands
# absent here remain supported legacy CLI commands; absence is not rejection.
[[ -n "${_ERPNEXT_DEV_COMMANDS_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_COMMANDS_LOADED=1

command_registry_records() {
	cat <<'EOF_COMMANDS'
api-version||run_api_version|user|read-only|none|both|safe|native,docker|yes|1.0
backup-status||show_backup_status|user|read-only|none|both|safe|native,docker|yes|none
capabilities||run_capabilities|user|read-only|none|both|safe|native,docker|yes|1.0
deployment-info||run_deployment_info|user|read-only|none|both|safe|native,docker|yes|1.0
doctor||run_doctor_plain|user|read-only|none|both|safe|native,docker|yes|none
health-check|health-check-run-now|run_health_check|user|read-only|none|both|safe|native,docker|yes|none
health-check-status||show_health_check_status|user|read-only|none|both|safe|native,docker|yes|none
install|setup|run_install|root|mutating|required|both|destructive|native,docker|no|none
menu||show_menu|user|read-only|none|interactive|safe|native,docker|no|none
restore-preflight||show_restore_preflight|root|read-only|required|interactive|safe|native,docker|no|none
status||run_status|user|read-only|none|both|safe|native,docker|yes|none
status-menu||show_status_menu|user|read-only|none|interactive|safe|native,docker|no|none
toolkit-rollback|update-toolkit-rollback,rollback-toolkit|rollback_toolkit|root|mutating|required|both|administrative|native,docker|no|none
update-toolkit||update_toolkit|root|mutating|required|both|administrative|native,docker|no|none
verify-toolkit|toolkit-verify,verify-install|verify_toolkit_integrity|user|read-only|none|both|safe|native,docker|no|none
EOF_COMMANDS
}

command_registry_validate() {
	local name aliases handler root mode lock interactive destructive engines json contract alias
	local -A seen=()
	while IFS='|' read -r name aliases handler root mode lock interactive destructive engines json contract; do
		[[ -n "$name" && "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
		[[ -z "${seen[$name]:-}" ]] || return 1
		seen["$name"]=1
		declare -F "$handler" >/dev/null 2>&1 || return 1
		[[ "$root" =~ ^(user|root)$ && "$mode" =~ ^(read-only|mutating)$ ]] || return 1
		[[ "$lock" =~ ^(none|required)$ && "$interactive" =~ ^(interactive|non-interactive|both)$ ]] || return 1
		[[ "$destructive" =~ ^(safe|administrative|destructive)$ && "$json" =~ ^(yes|no)$ ]] || return 1
		[[ "$contract" =~ ^(none|1\.0)$ ]] || return 1
		[[ "$contract" == none || "$json" == yes ]] || return 1
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
