# shellcheck shell=bash
[[ -n "${_ERPNEXT_DEV_API_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_API_LOADED=1

ERPNEXT_DEV_API_VERSION="1.0"
ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS=64
# Reserved by the documented v1 contract for future failures in stable commands.
# shellcheck disable=SC2034
ERPNEXT_DEV_API_EXIT_UNAVAILABLE=69
# shellcheck disable=SC2034
ERPNEXT_DEV_API_EXIT_INTERNAL=70

api_emit_version_json() {
	python3 -c '
import datetime, json, sys
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
payload = {
    "api_version": sys.argv[1], "generated_at": now, "command": "api-version",
    "success": True,
    "data": {"current_api_version": sys.argv[1], "supported_api_versions": [sys.argv[1]], "toolkit_version": sys.argv[2]},
    "error": None,
}
print(json.dumps(payload, separators=(",", ":")))
' "$ERPNEXT_DEV_API_VERSION" "$SCRIPT_VERSION"
}

api_emit_error_json() {
	local command_name="$1" error_id="$2" message="$3"
	python3 -c '
import datetime, json, sys
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
payload = {
    "api_version": sys.argv[1], "generated_at": now, "command": sys.argv[2],
    "success": False, "data": None,
    "error": {"id": sys.argv[3], "message": sys.argv[4], "details": {}},
}
print(json.dumps(payload, separators=(",", ":")))
' "$ERPNEXT_DEV_API_VERSION" "$command_name" "$error_id" "$message"
}

api_emit_capabilities_json() {
	command_registry_records | python3 -c '
import datetime, json, sys
records = []
for line in sys.stdin:
    name, aliases, _handler, root, mode, lock, interaction, risk, engines, json_value, contract = line.rstrip("\n").split("|")
    records.append({
        "name": name, "aliases": sorted(filter(None, aliases.split(","))),
        "requires_root": root == "root", "operation_mode": mode, "lock_policy": lock,
        "interaction_mode": interaction, "risk_classification": risk,
        "supported_engines": sorted(engines.split(",")), "json_available": json_value == "yes",
        "stable_api_contract": contract != "none",
        "api_contract_version": None if contract == "none" else contract,
    })
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
payload = {"api_version": sys.argv[1], "generated_at": now, "command": "capabilities", "success": True,
           "data": {"capabilities": sorted(records, key=lambda item: item["name"])}, "error": None}
print(json.dumps(payload, separators=(",", ":")))
' "$ERPNEXT_DEV_API_VERSION"
}

api_reject_arguments() {
	local command_name="$1"
	if [[ "${MACHINE_JSON:-0}" == 1 ]]; then
		api_emit_error_json "$command_name" "invalid_arguments" "This command does not accept positional arguments."
	else
		printf 'ERROR: %s does not accept positional arguments.\n' "$command_name" >&2
	fi
	return "$ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS"
}

run_api_version() {
	if [[ -n "${ACTION_ARG:-}" || -n "${ACTION_ARG2:-}" ]]; then
		api_reject_arguments api-version
		return $?
	fi
	if [[ "${MACHINE_JSON:-0}" == 1 ]]; then api_emit_version_json; else
		printf 'Machine API version: %s\nSupported API versions: %s\nToolkit version: %s\n' "$ERPNEXT_DEV_API_VERSION" "$ERPNEXT_DEV_API_VERSION" "$SCRIPT_VERSION"
	fi
}

run_capabilities() {
	if [[ -n "${ACTION_ARG:-}" || -n "${ACTION_ARG2:-}" ]]; then
		api_reject_arguments capabilities
		return $?
	fi
	if [[ "${MACHINE_JSON:-0}" == 1 ]]; then api_emit_capabilities_json; else
		printf 'Registered public commands:\n'
		command_registry_records | cut -d '|' -f 1 | LC_ALL=C sort | sed 's/^/  /'
	fi
}
