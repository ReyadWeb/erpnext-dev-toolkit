# shellcheck shell=bash
[[ -n "${_ERPNEXT_DEV_API_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_API_LOADED=1

ERPNEXT_DEV_API_VERSION="1.0"
ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS=64
ERPNEXT_DEV_API_EXIT_UNAVAILABLE=69
ERPNEXT_DEV_API_EXIT_INTERNAL=70
STABLE_API_ACTION=""
STABLE_API_JSON=0
STABLE_API_INVALID_ARGUMENTS=0

stable_api_parse() {
	local token
	STABLE_API_ACTION=""
	STABLE_API_JSON=0
	STABLE_API_INVALID_ARGUMENTS=0
	for token in "$@"; do
		if [[ -z "$STABLE_API_ACTION" ]]; then
			case "$token" in
			--json) STABLE_API_JSON=1 ;;
			--no-color) : ;;
			api-version | capabilities) STABLE_API_ACTION="$token" ;;
			*) return 1 ;;
			esac
		else
			case "$token" in
			--json) STABLE_API_JSON=1 ;;
			--no-color) : ;;
			*) STABLE_API_INVALID_ARGUMENTS=1 ;;
			esac
		fi
	done
	[[ -n "$STABLE_API_ACTION" ]]
}

api_encoder_available() { command -v python3 >/dev/null 2>&1; }

api_encode() {
	local kind="$1"
	shift
	command python3 -c '
import datetime, json, sys

kind = sys.argv[1]
api_version = sys.argv[2]
command = sys.argv[3]
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
if kind == "error":
    payload = {"api_version": api_version, "generated_at": now, "command": command,
               "success": False, "data": None,
               "error": {"id": sys.argv[4], "message": sys.argv[5], "details": {}}}
elif kind == "version":
    payload = {"api_version": api_version, "generated_at": now, "command": command,
               "success": True,
               "data": {"current_api_version": api_version,
                        "supported_api_versions": [api_version], "toolkit_version": sys.argv[4]},
               "error": None}
elif kind == "capabilities":
    records = []
    for line in sys.stdin:
        name, aliases, _handler, root, mode, lock, interaction, risk, engines, json_value, contract = line.rstrip("\n").split("|")
        records.append({"name": name, "aliases": sorted(filter(None, aliases.split(","))),
            "requires_root": root == "root", "operation_mode": mode, "lock_policy": lock,
            "interaction_mode": interaction, "risk_classification": risk,
            "supported_engines": sorted(engines.split(",")), "json_available": json_value == "yes",
            "stable_api_contract": contract != "none",
            "api_contract_version": None if contract == "none" else contract})
    payload = {"api_version": api_version, "generated_at": now, "command": command,
               "success": True, "data": {"capabilities": sorted(records, key=lambda item: item["name"])},
               "error": None}
else:
    raise ValueError("unsupported encoder operation")
sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
' "$kind" "$ERPNEXT_DEV_API_VERSION" "$@"
}

api_emit_buffered() {
	local output
	if ! api_encoder_available; then
		printf 'ERROR: required JSON encoder is unavailable.\n' >&2
		return "$ERPNEXT_DEV_API_EXIT_UNAVAILABLE"
	fi
	if ! output="$(api_encode "$@" 2>/dev/null)"; then
		printf 'ERROR: internal API serialization failure.\n' >&2
		return "$ERPNEXT_DEV_API_EXIT_INTERNAL"
	fi
	printf '%s\n' "$output"
}

api_emit_error() {
	local command_name="$1" error_id="$2" message="$3"
	api_emit_buffered error "$command_name" "$error_id" "$message"
}

api_fail() {
	local command_name="$1" exit_code="$2" error_id="$3" message="$4"
	if [[ "$STABLE_API_JSON" -eq 1 ]]; then
		api_emit_error "$command_name" "$error_id" "$message" || return $?
	else
		printf 'ERROR: %s\n' "$message" >&2
	fi
	return "$exit_code"
}

run_api_version() {
	if [[ "$STABLE_API_INVALID_ARGUMENTS" -eq 1 || -n "${ACTION_ARG:-}" || -n "${ACTION_ARG2:-}" ]]; then
		api_fail api-version "$ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS" invalid_arguments \
			"api-version accepts only --json and --no-color."
		return $?
	fi
	if [[ "$STABLE_API_JSON" -eq 1 ]]; then
		api_emit_buffered version api-version "$SCRIPT_VERSION"
	else
		printf 'Machine API version: %s\nSupported API versions: %s\nToolkit version: %s\n' \
			"$ERPNEXT_DEV_API_VERSION" "$ERPNEXT_DEV_API_VERSION" "$SCRIPT_VERSION"
	fi
}

run_capabilities() {
	if [[ "$STABLE_API_INVALID_ARGUMENTS" -eq 1 || -n "${ACTION_ARG:-}" || -n "${ACTION_ARG2:-}" ]]; then
		api_fail capabilities "$ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS" invalid_arguments \
			"capabilities accepts only --json and --no-color."
		return $?
	fi
	if ! command_registry_validate; then
		api_fail capabilities "$ERPNEXT_DEV_API_EXIT_INTERNAL" internal_error \
			"The command registry is invalid."
		return $?
	fi
	if [[ "$STABLE_API_JSON" -eq 1 ]]; then
		local output
		if ! api_encoder_available; then
			printf 'ERROR: required JSON encoder is unavailable.\n' >&2
			return "$ERPNEXT_DEV_API_EXIT_UNAVAILABLE"
		fi
		if ! output="$(command_registry_records | api_encode capabilities capabilities 2>/dev/null)"; then
			api_fail capabilities "$ERPNEXT_DEV_API_EXIT_INTERNAL" internal_error \
				"Capability serialization failed."
			return $?
		fi
		printf '%s\n' "$output"
	else
		printf 'Registered public commands:\n'
		command_registry_records | cut -d '|' -f 1 | LC_ALL=C sort | sed 's/^/  /'
	fi
}

stable_api_dispatch() {
	case "$STABLE_API_ACTION" in
	api-version) run_api_version ;;
	capabilities) run_capabilities ;;
	esac
}
