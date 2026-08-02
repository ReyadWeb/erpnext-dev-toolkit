# shellcheck shell=bash
# shellcheck disable=SC2034
# Dependency-aware application removal and checkpoint-driven recovery.
[[ -n "${_ERPNEXT_DEV_REMOVAL_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_REMOVAL_LOADED=1

REMOVAL_SCOPE="${REMOVAL_SCOPE:-site}"
REMOVAL_SITES="${REMOVAL_SITES:-}"
REMOVAL_PREVIEW="${REMOVAL_PREVIEW:-0}"
REMOVAL_DATA_ACK="${REMOVAL_DATA_ACK:-0}"
REMOVAL_PROFILE_ACK="${REMOVAL_PROFILE_ACK:-0}"
REMOVAL_TARGET_PROFILE="${REMOVAL_TARGET_PROFILE:-}"
REMOVAL_DEPENDENTS=""
REMOVAL_INSTALLED_SITES=""
REMOVAL_ALL_SITES=""
REMOVAL_BLOCKER=""
REMOVAL_FAILURE_STAGE=""
REMOVAL_SERVICE_WAS_ACTIVE=0

removal_validate_scope() {
	case "$1" in site | remove-unused-code | erpnext-site | convert-frappe-only) return 0 ;; *) return 1 ;; esac
}

removal_csv_valid_sites() {
	local value="$1" site
	[[ -n "$value" ]] || return 1
	while IFS= read -r site; do
		inventory_valid_name "$site" || return 1
	done < <(printf '%s\n' "$value" | tr ',' '\n')
}

removal_select_stack() {
	local record count=0 engine selected=""
	engine="$(effective_deployment_engine)"
	while IFS= read -r record; do
		[[ "$record" == STACK\|* ]] || continue
		[[ "$(printf '%s' "$record" | cut -d'|' -f3)" == "$engine" ]] || continue
		[[ "$(printf '%s' "$record" | cut -d'|' -f6)" == managed ]] || continue
		[[ "$(printf '%s' "$record" | cut -d'|' -f7)" == clean ]] || continue
		selected="$record"
		count=$((count + 1))
	done < <(inventory_records_sorted)
	[[ "$count" -eq 1 ]] || return 1
	PLAN_STACK="$(printf '%s' "$selected" | cut -d'|' -f2)"
	PLAN_ENGINE="$engine"
	PLAN_BENCH="${PLAN_STACK#native:}"
}

removal_reverse_dependents() {
	local target="$1" candidate dep site
	while IFS= read -r candidate; do
		[[ "$candidate" != "$target" ]] || continue
		load_validated_app_catalog_record "$candidate" || return 1
		while IFS= read -r dep; do
			[[ "$dep" == "$target" ]] || continue
			while IFS= read -r site; do
				planner_site_installed "$PLAN_STACK" "$site" "$candidate" && printf '%s@%s\n' "$candidate" "$site"
			done < <(printf '%s\n' "$REMOVAL_ALL_SITES" | tr ',' '\n')
		done < <(printf '%s\n' "${LIB_APP_REQUIRES:-}" | tr ',' '\n')
	done < <(app_catalog_ids)
}

removal_build_plan() {
	local app="$1" scope="$2" site installed="" selected="${REMOVAL_SITES:-${QUICK_INSTALL_SITE:-}}" code_record inventory_app
	inventory_valid_name "$app" || return 20
	removal_validate_scope "$scope" || return 20
	load_validated_app_catalog_record "$app" || return 22
	[[ "$app" != frappe && "$LIB_APP_UNINSTALL_CAPABILITY" != never ]] || {
		REMOVAL_BLOCKER=protected-application
		return 26
	}
	if [[ "$app" == erpnext ]]; then
		[[ "$scope" == erpnext-site || "$scope" == convert-frappe-only ]] || return 20
	else
		[[ "$scope" == site || "$scope" == remove-unused-code ]] || return 20
		[[ "$LIB_APP_UNINSTALL_CAPABILITY" == supported ]] || return 22
	fi
	inventory_collect
	if inventory_has_ambiguous_state; then
		REMOVAL_BLOCKER=ambiguous-inventory
		return 21
	fi
	removal_select_stack || return 21
	PLAN_APP="$app" PLAN_CATALOG_ID="$LIB_APP_ID" PLAN_INSTALL_NAME="$LIB_APP_NAME" PLAN_REPO="$LIB_APP_REPO" PLAN_BRANCH="$LIB_APP_BRANCH"
	PLAN_CURRENT_PROFILE="$(effective_installation_profile)" PLAN_RESULT_PROFILE="$PLAN_CURRENT_PROFILE"
	REMOVAL_ALL_SITES="$(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" '$1=="SITE"&&$2==s&&$4=="known"{print $3}' | paste -sd, -)"
	[[ -n "$REMOVAL_ALL_SITES" ]] || return 21
	while IFS= read -r inventory_app; do
		load_validated_app_catalog_record "$inventory_app" >/dev/null 2>&1 || {
			REMOVAL_BLOCKER="unknown-installed-application:${inventory_app}"
			return 22
		}
	done < <(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" '$1=="SITE_APP"&&$2==s{print $4}' | sort -u)
	load_validated_app_catalog_record "$app" || return 22
	PLAN_CATALOG_ID="$LIB_APP_ID" PLAN_INSTALL_NAME="$LIB_APP_NAME" PLAN_REPO="$LIB_APP_REPO" PLAN_BRANCH="$LIB_APP_BRANCH"
	while IFS= read -r site; do
		planner_site_installed "$PLAN_STACK" "$site" "$app" && installed+="${installed:+,}${site}"
	done < <(printf '%s\n' "$REMOVAL_ALL_SITES" | tr ',' '\n')
	REMOVAL_INSTALLED_SITES="$installed"
	if [[ "$scope" == convert-frappe-only ]]; then
		[[ "$app" == erpnext && "$PLAN_CURRENT_PROFILE" == recommended ]] || return 22
		selected="$installed"
		PLAN_RESULT_PROFILE=frappe-only
	else
		removal_csv_valid_sites "$selected" || return 20
	fi
	while IFS= read -r site; do
		[[ ",${REMOVAL_ALL_SITES}," == *",${site},"* ]] || return 21
		planner_site_installed "$PLAN_STACK" "$site" "$app" || return 10
	done < <(printf '%s\n' "$selected" | tr ',' '\n')
	code_record="$(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" -v a="$app" '$1=="APP"&&$2==s&&$3==a{print;exit}')"
	[[ -n "$code_record" && "$(printf '%s' "$code_record" | cut -d'|' -f10)" == managed ]] || return 22
	[[ "$(printf '%s' "$code_record" | cut -d'|' -f8)" == "$LIB_APP_REPO" || "$(printf '%s' "$code_record" | cut -d'|' -f8)" == "${LIB_APP_REPO}.git" || "$PLAN_ENGINE" == docker ]] || return 25
	REMOVAL_DEPENDENTS="$(removal_reverse_dependents "$app" | while IFS= read -r dep_record; do
		[[ "$scope" == remove-unused-code || "$scope" == convert-frappe-only || ",${selected}," == *",${dep_record#*@},"* ]] && printf '%s\n' "$dep_record"
	done | paste -sd, - || true)"
	[[ -z "$REMOVAL_DEPENDENTS" ]] || {
		REMOVAL_BLOCKER="dependents:${REMOVAL_DEPENDENTS};remove dependents first in separate operations"
		return 27
	}
	load_validated_app_catalog_record "$app" || return 22
	if [[ "$scope" == remove-unused-code && ",${selected}," != ",${installed}," ]] ||
		[[ "$scope" == convert-frappe-only && ",${selected}," != ",${installed}," ]]; then
		REMOVAL_BLOCKER="shared-code-required-by:${installed}"
		return 27
	fi
	OPERATION_TYPE=app-removal OPERATION_REMOVAL_SCOPE="$scope" OPERATION_SELECTED_SITES="$selected"
	OPERATION_CODE_DECISION=retain
	[[ "$scope" == remove-unused-code || "$scope" == convert-frappe-only ]] && OPERATION_CODE_DECISION=remove
	OPERATION_PREVIOUS_PROFILE="$PLAN_CURRENT_PROFILE" OPERATION_RECOVERY_ELIGIBLE=yes
	PLAN_SITE="${selected%%,*}" PLAN_SHARED_SITES="$REMOVAL_ALL_SITES" PLAN_DEPENDENCIES="${LIB_APP_REQUIRES:-none}"
	PLAN_CODE_STATE=available PLAN_SITE_STATE=installed PLAN_TRUST="$LIB_APP_TRUST" PLAN_COMPATIBILITY=compatible
	PLAN_ACTIONS="checkpoint,backup,maintenance,site-uninstall"
	[[ "$OPERATION_CODE_DECISION" == remove ]] && PLAN_ACTIONS+=",candidate-or-source-checkpoint,shared-code-removal"
	PLAN_ACTIONS+=",migrate,assets,services,verify"
	PLAN_VERIFICATION="selected-absence,unselected-presence,remaining-apps,database,http,workers,scheduler,queues,redis,assets,services,inventory,profile"
	PLAN_INVENTORY_FINGERPRINT="$(planner_inventory_fingerprint)" PLAN_STARTED_AT="$(planner_timestamp)"
	OPERATION_ID="remove-$(date -u +%Y%m%dT%H%M%SZ)-$$-${app}"
	OPERATION_FILE="${OPERATION_STATE_DIR}/${OPERATION_ID}.state" OPERATION_STATUS=planned OPERATION_CHECKPOINTS=planned
	OPERATION_AFFECTED_SITES="$REMOVAL_ALL_SITES" OPERATION_PER_SITE_STATE="$(printf '%s' "$selected" | tr ',' ';' | sed 's/[^;]*/&:pending/g')"
	OPERATION_BACKUP_TARGETS="$selected"
	[[ "$OPERATION_CODE_DECISION" != remove ]] || OPERATION_BACKUP_TARGETS="$REMOVAL_ALL_SITES"
	OPERATION_RECOVERY="Restore compatible code/image first, then verified site database and files, configuration/profile, migrations/assets, original services, and verify inventory."
}

removal_preview() {
	if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
		printf '{"schema_version":1,"read_only":true,"operation_type":"app-removal","scope":"%s","application":"%s","engine":"%s","selected_sites":"%s","shared_sites":"%s","installed_sites":"%s","dependents":"%s","code_decision":"%s","profile_before":"%s","profile_after":"%s","status":"%s"}\n' \
			"$OPERATION_REMOVAL_SCOPE" "$PLAN_APP" "$PLAN_ENGINE" "$OPERATION_SELECTED_SITES" "$REMOVAL_ALL_SITES" "$REMOVAL_INSTALLED_SITES" "${REMOVAL_DEPENDENTS:-none}" "$OPERATION_CODE_DECISION" "$PLAN_CURRENT_PROFILE" "$PLAN_RESULT_PROFILE" "$OPERATION_STATUS"
		return
	fi
	ui_box_start "Application Removal Plan"
	status_line "Scope" "WARN" "$OPERATION_REMOVAL_SCOPE"
	status_line "Application" "INFO" "$PLAN_APP"
	status_line "Deployment / stack" "INFO" "$PLAN_ENGINE / $PLAN_STACK"
	status_line "Selected sites" "WARN" "$OPERATION_SELECTED_SITES"
	status_line "Sites using app" "INFO" "${REMOVAL_INSTALLED_SITES:-none}"
	status_line "Shared sites" "INFO" "$REMOVAL_ALL_SITES"
	status_line "Dependencies / dependents" "INFO" "${PLAN_DEPENDENCIES:-none} / ${REMOVAL_DEPENDENTS:-none}"
	status_line "Shared code" "WARN" "$OPERATION_CODE_DECISION"
	status_line "Profile" "WARN" "$PLAN_CURRENT_PROFILE -> $PLAN_RESULT_PROFILE"
	status_line "Data impact" "WARN" "supported uninstall may remove or transform application-owned data; reinstall does not restore it"
	status_line "Backup targets" "INFO" "$([[ "$OPERATION_CODE_DECISION" == remove ]] && printf '%s' "$REMOVAL_ALL_SITES" || printf '%s' "$OPERATION_SELECTED_SITES")"
	status_line "Recovery" "INFO" "verified backups plus source/image, manifest, profile, and service checkpoint"
	ui_box_end
}

removal_backup_sites() {
	local sites="$1" site saved="$SITE_NAME" saved_docker_site="${DOCKER_SITE_NAME:-}" refs=""
	while IFS= read -r site; do
		SITE_NAME="$site" PLAN_SITE="$site"
		if [[ "$PLAN_ENGINE" == docker ]]; then
			DOCKER_SITE_NAME="$site"
			docker_backup true && docker_backup_verify
		else
			create_site_backup true && verify_latest_backup_set && planner_verify_backup_target
		fi || {
			SITE_NAME="$saved"
			DOCKER_SITE_NAME="$saved_docker_site"
			return 1
		}
		refs+="${refs:+,}${site}:verified"
	done < <(printf '%s\n' "$sites" | tr ',' '\n')
	SITE_NAME="$saved" DOCKER_SITE_NAME="$saved_docker_site" OPERATION_BACKUP_REFERENCE="$refs"
}

removal_site_action() {
	local site="$1" bench_q site_q app_q
	printf -v bench_q %q "$PLAN_BENCH"
	printf -v site_q %q "$site"
	printf -v app_q %q "$PLAN_INSTALL_NAME"
	if [[ "$PLAN_ENGINE" == docker ]]; then docker_bench --site "$site" uninstall-app "$PLAN_INSTALL_NAME" --yes; else run_as_frappe "cd ${bench_q} && bench --site ${site_q} uninstall-app ${app_q} --yes"; fi
}

removal_native_preflight() {
	local app path remote branch ref
	[[ "$PLAN_BENCH" == /* && -d "$PLAN_BENCH/apps" && ! -L "$PLAN_BENCH" ]] || return 1
	while IFS= read -r app; do
		load_validated_app_catalog_record "$app" || return 1
		path="${PLAN_BENCH}/apps/${app}"
		[[ -d "$path/.git" && ! -L "$path" ]] || return 1
		[[ "$(inventory_git_value "$path" state)" == clean ]] || return 1
		branch="$(inventory_git_value "$path" branch)"
		[[ -n "$branch" && "$branch" != detached && "$branch" != unknown ]] || return 1
		for ref in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD BISECT_HEAD; do
			inventory_git_ref_absent "$path" "$ref" || return 1
		done
		[[ -z "$LIB_APP_BRANCH" || "$branch" == "$LIB_APP_BRANCH" ]] || return 1
		remote="$(inventory_git_value "$path" source)"
		[[ -n "$remote" && "$remote" != unknown ]] || return 1
		[[ "$remote" == "$LIB_APP_REPO" || "$remote" == "${LIB_APP_REPO}.git" ]] || return 1
	done < <(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" '$1=="APP"&&$2==s&&$10=="managed"{print $3}' | sort -u)
	command -v git >/dev/null && command -v df >/dev/null || return 1
	[[ "$(df -Pk "$PLAN_BENCH" | awk 'NR==2{print $4}')" -ge 1048576 ]] || return 1
}

removal_set_maintenance() {
	local state="$1"
	if [[ "$PLAN_ENGINE" == docker ]]; then
		docker_bench set-maintenance-mode "$state"
	else
		run_as_frappe_quiet "removal maintenance ${state}" "cd '${PLAN_BENCH}' && bench set-maintenance-mode '${state}'"
	fi
}

removal_verify_sites() {
	local site
	while IFS= read -r site; do
		if [[ ",${OPERATION_SELECTED_SITES}," == *",${site},"* ]]; then
			planner_site_installed "$PLAN_STACK" "$site" "$PLAN_APP" && return 1
		elif [[ ",${REMOVAL_INSTALLED_SITES}," == *",${site},"* ]]; then
			planner_site_installed "$PLAN_STACK" "$site" "$PLAN_APP" || return 1
		fi
	done < <(printf '%s\n' "$REMOVAL_ALL_SITES" | tr ',' '\n')
	if [[ "$PLAN_ENGINE" == docker ]]; then
		docker_custom_image_verify_runtime "$(docker_custom_image_selected_app_names)"
	else
		wait_for_erpnext_ready
	fi
}

removal_post_maintenance() {
	local site bench_q site_q
	printf -v bench_q %q "$PLAN_BENCH"
	while IFS= read -r site; do
		printf -v site_q %q "$site"
		if [[ "$PLAN_ENGINE" == docker ]]; then
			docker_bench --site "$site" migrate && docker_bench --site "$site" clear-cache || return 1
		else
			run_as_frappe "cd ${bench_q} && bench --site ${site_q} migrate && bench --site ${site_q} clear-cache" || return 1
		fi
	done < <(printf '%s\n' "$REMOVAL_ALL_SITES" | tr ',' '\n')
	if [[ "$PLAN_ENGINE" == native ]]; then
		run_as_frappe "cd ${bench_q} && bench build" || return 1
	fi
}

removal_docker_prepare_candidate() {
	local profile="$PLAN_CURRENT_PROFILE" candidate_profiles=() image image_id
	[[ -f "$DOCKER_APP_MANIFEST_FILE" && ! -L "$DOCKER_APP_MANIFEST_FILE" ]] || return 1
	docker_validate_app_manifest "$DOCKER_APP_MANIFEST_FILE" || return 1
	OPERATION_PREVIOUS_IMAGE="$(awk -F'\t' '$1=="IMAGE"{print $2"@"$3}' "$DOCKER_APP_MANIFEST_FILE")"
	[[ -n "$OPERATION_PREVIOUS_IMAGE" ]] || return 1
	mapfile -t candidate_profiles < <(awk -F'\t' -v remove="$PLAN_APP" '$1=="APP"&&$2!="frappe"&&$2!="erpnext"&&$2!=remove{print $2}' "$DOCKER_APP_MANIFEST_FILE")
	[[ "$OPERATION_REMOVAL_SCOPE" != convert-frappe-only ]] || profile=frappe-only
	local saved_profile="$INSTALLATION_PROFILE"
	INSTALLATION_PROFILE="$profile"
	docker_write_apps_json "${candidate_profiles[@]}" || {
		INSTALLATION_PROFILE="$saved_profile"
		return 1
	}
	ASSUME_YES=1 docker_build_custom_image || {
		INSTALLATION_PROFILE="$saved_profile"
		return 1
	}
	image="$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE)"
	image_id="$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE_ID)"
	[[ -n "$image" && "$image_id" =~ ^sha256:[a-f0-9]{64}$ ]] || {
		INSTALLATION_PROFILE="$saved_profile"
		return 1
	}
	docker_custom_image_verify_runtime "$(docker_custom_image_selected_app_names)" || {
		INSTALLATION_PROFILE="$saved_profile"
		return 1
	}
	if docker run --rm "$image" test -d "/home/frappe/frappe-bench/apps/${PLAN_APP}" 2>/dev/null; then
		INSTALLATION_PROFILE="$saved_profile"
		return 1
	fi
	OPERATION_REPLACEMENT_IMAGE="${image}@${image_id}"
	INSTALLATION_PROFILE="$saved_profile"
}

removal_execute() {
	local site sites_to_backup="$OPERATION_SELECTED_SITES" source_ref rc=0
	[[ "$(planner_inventory_fingerprint)" == "$PLAN_INVENTORY_FINGERPRINT" ]] || return 34
	[[ "$REMOVAL_DATA_ACK" == 1 ]] || return 28
	[[ "$OPERATION_REMOVAL_SCOPE" != convert-frappe-only || "$REMOVAL_PROFILE_ACK" == 1 ]] || return 28
	REMOVAL_FAILURE_STAGE=preflight
	if [[ "$PLAN_ENGINE" == native ]]; then
		removal_native_preflight || return 25
	elif [[ "$(docker_mode)" == production ]]; then
		[[ -f "$DOCKER_APP_MANIFEST_FILE" && ! -L "$DOCKER_APP_MANIFEST_FILE" ]] || return 25
		docker_validate_app_manifest "$DOCKER_APP_MANIFEST_FILE" || return 25
		[[ "$(awk -F'\t' '$1=="IMAGE"{print $3}' "$DOCKER_APP_MANIFEST_FILE")" =~ ^sha256:[a-f0-9]{64}$ ]] || return 25
	fi
	if [[ "$PLAN_ENGINE" == docker && "$OPERATION_CODE_DECISION" == remove ]]; then
		REMOVAL_FAILURE_STAGE="candidate-image"
		removal_docker_prepare_candidate || return 31
		planner_checkpoint candidate-ready validated || return 1
	fi
	[[ "$OPERATION_CODE_DECISION" != remove ]] || sites_to_backup="$REMOVAL_ALL_SITES"
	if [[ "$PLAN_ENGINE" == native ]] && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME:-erpnext-dev}" 2>/dev/null; then REMOVAL_SERVICE_WAS_ACTIVE=1; fi
	OPERATION_ORIGINAL_STATE="maintenance=off,scheduler=preserve,service_active=${REMOVAL_SERVICE_WAS_ACTIVE}"
	OPERATION_PREVIOUS_REVISIONS="${PLAN_APP}@$(inventory_records_sorted | awk -F'|' -v s="$PLAN_STACK" -v a="$PLAN_APP" '$1=="APP"&&$2==s&&$3==a{print $7;exit}')"
	if [[ "$PLAN_ENGINE" == native && "$OPERATION_CODE_DECISION" == remove ]]; then
		source_ref="${PLAN_BENCH}/.erpnext-dev-recovery/${OPERATION_ID}.source.bundle"
		[[ ! -L "${PLAN_BENCH}/.erpnext-dev-recovery" && ! -L "$source_ref" ]] || return 25
		run_as_frappe "mkdir -p '${PLAN_BENCH}/.erpnext-dev-recovery' && chmod 700 '${PLAN_BENCH}/.erpnext-dev-recovery' && git -C '${PLAN_BENCH}/apps/${PLAN_APP}' bundle create '${source_ref}' --all && git bundle verify '${source_ref}'" || return 31
		OPERATION_RECOVERY_ELIGIBLE="$source_ref"
	elif [[ "$PLAN_ENGINE" == docker ]]; then
		OPERATION_PREVIOUS_IMAGE="${DOCKER_ERPNEXT_IMAGE}@${DOCKER_ERPNEXT_IMAGE_DIGEST:-unrecorded}"
	fi
	planner_checkpoint recovery-checkpoint-ready validated || return 1
	REMOVAL_FAILURE_STAGE=backup
	removal_backup_sites "$sites_to_backup" || return 30
	planner_checkpoint backup-complete backup-complete || return 1
	REMOVAL_FAILURE_STAGE=maintenance
	removal_set_maintenance on || return 31
	planner_checkpoint maintenance-entered mutation-started || return 1
	while IFS= read -r site; do
		REMOVAL_FAILURE_STAGE="site-uninstall:${site}"
		OPERATION_PER_SITE_STATE="${OPERATION_PER_SITE_STATE/${site}:pending/${site}:started}"
		planner_checkpoint site-uninstall-started mutation-started || return 1
		removal_site_action "$site" || {
			rc=33
			break
		}
		OPERATION_PER_SITE_STATE="${OPERATION_PER_SITE_STATE/${site}:started/${site}:complete}"
		planner_checkpoint "site-${site}-complete" mutation-started || return 1
	done < <(printf '%s\n' "$OPERATION_SELECTED_SITES" | tr ',' '\n')
	[[ "$rc" -eq 0 ]] || return "$rc"
	planner_checkpoint site-uninstall-complete mutation-complete || return 1
	if [[ "$OPERATION_CODE_DECISION" == remove ]]; then
		REMOVAL_FAILURE_STAGE="shared-code-removal"
		inventory_collect
		while IFS= read -r site; do
			planner_site_installed "$PLAN_STACK" "$site" "$PLAN_APP" && return 33
		done < <(printf '%s\n' "$REMOVAL_ALL_SITES" | tr ',' '\n')
		[[ -z "$(removal_reverse_dependents "$PLAN_APP")" ]] || return 33
		planner_checkpoint shared-code-removal-started mutation-started || return 1
		if [[ "$PLAN_ENGINE" == native ]]; then
			run_as_frappe "cd '${PLAN_BENCH}' && bench remove-app '${PLAN_INSTALL_NAME}'" || return 33
		else
			DOCKER_DEFER_MANIFEST_PROMOTION=1 ASSUME_YES=1 docker_deploy_custom_image || return 33
			planner_checkpoint deployment-complete mutation-complete || return 1
		fi
		planner_checkpoint shared-code-removal-complete mutation-complete || return 1
	fi
	inventory_collect
	while IFS= read -r site; do planner_site_installed "$PLAN_STACK" "$site" "$PLAN_APP" && return 32; done < <(printf '%s\n' "$OPERATION_SELECTED_SITES" | tr ',' '\n')
	REMOVAL_FAILURE_STAGE="post-uninstall-maintenance"
	removal_post_maintenance || return 33
	removal_set_maintenance off || return 33
	if [[ "$PLAN_ENGINE" == docker || "$REMOVAL_SERVICE_WAS_ACTIVE" == 1 ]]; then restart_erpnext_service || return 33; fi
	inventory_collect
	REMOVAL_FAILURE_STAGE=verification
	removal_verify_sites || return 32
	if [[ "$PLAN_ENGINE" == docker && "$OPERATION_CODE_DECISION" == remove ]]; then
		docker_promote_app_manifest || return 33
	fi
	if [[ "$OPERATION_REMOVAL_SCOPE" == convert-frappe-only ]]; then
		INSTALLATION_PROFILE=frappe-only
		write_dev_config_file || return 33
		planner_checkpoint profile-transition-complete verification-complete || return 1
	fi
	PLAN_COMPLETED_AT="$(planner_timestamp)"
	planner_checkpoint verification-complete verification-complete
	planner_checkpoint completed completed
}

run_removal_check() { REMOVAL_PREVIEW=1 run_app_removal "$1" "${2:-site}"; }

show_app_removal_guide() {
	ui_box_start "Application Removal"
	status_line "Eligibility" "INFO" "$(toolkit_cmd app removal-check APP --site SITE)"
	status_line "Site-only" "INFO" "retains shared Bench/image code and profile"
	status_line "Unused code" "WARN" "requires explicit scope and complete shared-site backup"
	status_line "ERPNext conversion" "WARN" "separate stack conversion with profile acknowledgement"
	status_line "Recovery" "INFO" "$(toolkit_cmd operation status OPERATION_ID)"
	ui_box_end
}

run_app_removal() {
	local app="$1" scope="${2:-$REMOVAL_SCOPE}" rc
	removal_build_plan "$app" "$scope" || {
		rc=$?
		err "Removal is ineligible or blocked (code ${rc}; ${REMOVAL_BLOCKER:-policy/inventory})."
		return "$rc"
	}
	removal_preview
	[[ "$REMOVAL_PREVIEW" != 1 ]] || return 11
	if [[ "${ASSUME_YES:-0}" -ne 1 ]]; then confirm "Continue with this destructive site-data operation?" || return 12; fi
	[[ "$REMOVAL_DATA_ACK" == 1 ]] || {
		err "Explicit --ack-app-data-removal is required."
		return 28
	}
	[[ "$scope" != convert-frappe-only || "$REMOVAL_PROFILE_ACK" == 1 ]] || {
		err "Explicit --ack-profile-transition is required."
		return 28
	}
	planner_record_write || return 1
	removal_execute || {
		rc=$?
		planner_fail_record "$REMOVAL_FAILURE_STAGE" "Removal did not complete safely." "$OPERATION_RECOVERY" recovery-required
		return "$rc"
	}
}

run_removal_operation_status() {
	local id="$1" file
	[[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || return 20
	file="${OPERATION_STATE_DIR}/${id}.state"
	[[ -f "$file" && ! -L "$file" ]] || return 20
	sed -n '/^\(operation_id\|operation_type\|status\|checkpoints\|failure_stage\|recovery\|per_site_state\|backup_reference\)=/p' "$file"
}

run_removal_recovery() {
	local id="$1" file status
	[[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || return 20
	file="${OPERATION_STATE_DIR}/${id}.state"
	[[ -f "$file" && ! -L "$file" ]] || return 20
	status="$(sed -n 's/^status=//p' "$file")"
	[[ "$status" == recovery-required ]] || {
		err "Recovery is not eligible for this operation state."
		return 35
	}
	ui_box_start "Removal Recovery Preview"
	status_line "Operation" "WARN" "$id"
	status_line "Order" "INFO" "restore code/image, backups, configuration/profile, migrations/assets, services, then verify"
	ui_box_end
	[[ "$REMOVAL_PREVIEW" != 1 ]] || return 11
	err "Automatic restoration is blocked unless the exact checkpoint adapter proves every recovery artifact. Follow the recorded recovery guidance."
	return 35
}
