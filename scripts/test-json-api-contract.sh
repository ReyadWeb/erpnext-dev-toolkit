#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fixture_marker='api-contract-fixture-7f2c9d'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_cli() {
  local name="$1"
  shift
  set +e
  INSTALLATION_PROFILE=invalid DEPLOYMENT_ENGINE=invalid \
    DB_ADMIN_PASSWORD="$fixture_marker" ADMIN_PASSWORD="$fixture_marker" \
    PRIVATE_URL="https://${fixture_marker}.invalid/private" \
    LOG_DIR="$work/nonexistent/log-dir" LOG_FILE="$work/toolkit.log" \
    LOCK_DIR="$work/locks" LOCK_FILE="$work/locks/toolkit.lock" \
    "$root_dir/erpnext-dev.sh" "$@" >"$work/$name.out" 2>"$work/$name.err"
  printf '%s' "$?" >"$work/$name.rc"
  set -e
}

assert_rc() { [[ "$(<"$work/$1.rc")" == "$2" ]] || fail "$1 exit $(<"$work/$1.rc"), expected $2"; }
assert_empty() { [[ ! -s "$1" ]] || fail "$1 is not empty"; }

run_cli version_command api-version --json
run_cli version_option --json api-version
run_cli caps_command capabilities --json
run_cli caps_option --json capabilities
for name in version_command version_option caps_command caps_option; do
  assert_rc "$name" 0
  assert_empty "$work/$name.err"
done

invalid_cases=(
  'api-version --json version'
  'api-version version --json'
  '--json api-version version'
  'api-version --json --unknown'
  'api-version --json unexpected extra'
  'capabilities --json status'
  'capabilities --json unexpected'
  '--json capabilities unexpected'
)
index=0
for args in "${invalid_cases[@]}"; do
  index=$((index + 1))
  # Intentional word splitting: fixtures contain only fixed safe CLI tokens.
  # shellcheck disable=SC2086
  run_cli "invalid_$index" $args
  assert_rc "invalid_$index" 64
  assert_empty "$work/invalid_$index.err"
done

run_cli no_color --no-color capabilities --json
assert_rc no_color 0
assert_empty "$work/no_color.err"

# An unrelated action with a stable command word as data must use legacy parsing/logging.
set +e
ERPNEXT_DEV_LOG_DIR="$work/legacy-logs" LOG_FILE="$work/legacy.log" \
  "$root_dir/erpnext-dev.sh" version api-version --json >"$work/legacy.out" 2>"$work/legacy.err"
legacy_rc=$?
set -e
[[ "$legacy_rc" -eq 0 ]]
grep -Fxq 'ERPNext Developer Toolkit v1.20.4' "$work/legacy.out"

# Human discovery output is independent and human invalid arguments use stderr.
run_cli human_version api-version
assert_rc human_version 0
grep -Fxq 'Machine API version: 1.0' "$work/human_version.out"
set +e
LOG_FILE="$work/human.log" "$root_dir/erpnext-dev.sh" capabilities unexpected >"$work/human_bad.out" 2>"$work/human_bad.err"
human_bad_rc=$?
set -e
[[ "$human_bad_rc" -eq 64 && ! -s "$work/human_bad.out" ]]
grep -Fxq 'ERROR: capabilities accepts only --json and --no-color.' "$work/human_bad.err"

# Discovery never initializes normal logs or locks despite hostile unrelated config.
[[ ! -e "$work/toolkit.log" && ! -e "$work/locks" ]]

# Native/Docker metadata must not depend on the configured engine.
DEPLOYMENT_ENGINE=native "$root_dir/erpnext-dev.sh" capabilities --json >"$work/native.json" 2>"$work/native.err"
DEPLOYMENT_ENGINE=docker "$root_dir/erpnext-dev.sh" capabilities --json >"$work/docker.json" 2>"$work/docker.err"
assert_empty "$work/native.err"
assert_empty "$work/docker.err"

# Obtain the authoritative records without running a deployment command.
ERPNEXT_DEV_LOG_DIR="$work/source-logs" LOG_FILE=/dev/null bash -c \
  'source "$1" --help >/dev/null 2>&1 || true; command_registry_records' _ \
  "$root_dir/erpnext-dev.sh" >"$work/registry.txt"

# Fault paths are exercised hermetically without accepting executable paths.
set +e
bash -c '
  source "$1/lib/api.sh"
  SCRIPT_VERSION=1.20.4; STABLE_API_ACTION=capabilities; STABLE_API_JSON=1
  command_registry_validate() { return 1; }
  run_capabilities
' _ "$root_dir" >"$work/registry-failure.out" 2>"$work/registry-failure.err"
registry_failure_rc=$?
bash -c '
  source "$1/lib/api.sh"
  SCRIPT_VERSION=1.20.4; STABLE_API_ACTION=api-version; STABLE_API_JSON=1
  api_encoder_available() { return 1; }
  run_api_version
' _ "$root_dir" >"$work/encoder-failure.out" 2>"$work/encoder-failure.err"
encoder_failure_rc=$?
bash -c '
  source "$1/lib/api.sh"
  SCRIPT_VERSION=1.20.4; STABLE_API_ACTION=capabilities; STABLE_API_JSON=1
  command_registry_validate() { return 0; }
  command_registry_records() { printf "%s\n" "capabilities||handler|user|read-only|none|both|safe|native,docker|yes|1.0"; }
  api_encode() { return 1; }
  run_capabilities
' _ "$root_dir" >"$work/serialization-failure.out" 2>"$work/serialization-failure.err"
serialization_failure_rc=$?
set -e
[[ "$registry_failure_rc" -eq 70 && "$encoder_failure_rc" -eq 69 && "$serialization_failure_rc" -eq 70 ]]
assert_empty "$work/registry-failure.err"
[[ ! -s "$work/encoder-failure.out" && ! -s "$work/serialization-failure.out" ]]
! grep -qi 'traceback' "$work/encoder-failure.err" "$work/serialization-failure.err"

python3 - "$root_dir" "$work" "$fixture_marker" <<'PY'
import copy, datetime, json, pathlib, re, sys
root, work, fixture_marker = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
schema_dir = root / "schemas/api/v1"
schemas = {p.name: json.loads(p.read_text()) for p in schema_dir.glob("*.json")}

def resolve(ref, document):
    if ref.startswith("#"):
        target, fragment, target_doc = document, ref[1:], document
    else:
        filename, _, fragment = ref.partition("#")
        target = target_doc = schemas[filename]
    for token in fragment.removeprefix("/").split("/") if fragment else ():
        target = target[token.replace("~1", "/").replace("~0", "~")]
    return target, target_doc

def validate(value, schema, document=None):
    document = document or schema
    if "$ref" in schema:
        target, target_doc = resolve(schema["$ref"], document)
        validate(value, target, target_doc)
    for branch in schema.get("allOf", ()): validate(value, branch, document)
    if "oneOf" in schema:
        matches = 0
        for branch in schema["oneOf"]:
            try: validate(value, branch, document); matches += 1
            except (AssertionError, KeyError, TypeError): pass
        assert matches == 1
    if "const" in schema: assert value == schema["const"]
    if "enum" in schema: assert value in schema["enum"]
    types = schema.get("type")
    if types:
        types = [types] if isinstance(types, str) else types
        checks = {"object": lambda x: isinstance(x, dict), "array": lambda x: isinstance(x, list),
                  "string": lambda x: isinstance(x, str), "boolean": lambda x: isinstance(x, bool),
                  "integer": lambda x: isinstance(x, int) and not isinstance(x, bool),
                  "number": lambda x: isinstance(x, (int, float)) and not isinstance(x, bool),
                  "null": lambda x: x is None}
        assert any(checks[t](value) for t in types)
    if "pattern" in schema and isinstance(value, str): assert re.fullmatch(schema["pattern"], value)
    if "minLength" in schema: assert len(value) >= schema["minLength"]
    if isinstance(value, dict):
        assert set(schema.get("required", ())) <= set(value)
        props = schema.get("properties", {})
        if schema.get("additionalProperties") is False: assert set(value) <= set(props)
        for key in set(value) & set(props): validate(value[key], props[key], document)
    if isinstance(value, list):
        if "items" in schema:
            for item in value: validate(item, schema["items"], document)
        assert len(value) >= schema.get("minItems", 0)
        if schema.get("uniqueItems"): assert len({json.dumps(x, sort_keys=True) for x in value}) == len(value)

def rejects(value, schema_name):
    try: validate(value, schemas[schema_name])
    except (AssertionError, KeyError, TypeError): return
    raise AssertionError(f"negative schema case accepted by {schema_name}")

def load_runtime(name):
    raw = (work / name).read_bytes()
    assert raw.endswith(b"\n") and raw.count(b"\n") == 1
    assert fixture_marker.encode() not in raw and b"\x1b" not in raw
    assert not any(byte < 0x20 for byte in raw[:-1])
    value = json.loads(raw)
    datetime.datetime.strptime(value["generated_at"], "%Y-%m-%dT%H:%M:%SZ")
    return value

version = load_runtime("version_command.out")
version_option = load_runtime("version_option.out")
caps = load_runtime("caps_command.out")
caps_option = load_runtime("caps_option.out")
for value, schema_name in ((version, "api-version.schema.json"), (version_option, "api-version.schema.json"),
                           (caps, "capabilities.schema.json"), (caps_option, "capabilities.schema.json")):
    validate(value, schemas["response-envelope.schema.json"])
    validate(value, schemas[schema_name])

for index in range(1, 9):
    value = load_runtime(f"invalid_{index}.out")
    command = "api-version" if index <= 5 else "capabilities"
    assert value["command"] == command and value["success"] is False and value["data"] is None
    assert value["error"]["id"] == "invalid_arguments"
    validate(value, schemas["response-envelope.schema.json"])
    validate(value, schemas[f"{command}.schema.json"])

registry_failure = load_runtime("registry-failure.out")
assert registry_failure["error"]["id"] == "internal_error"
validate(registry_failure, schemas["capabilities.schema.json"])

registry, handlers = [], []
for line in (work / "registry.txt").read_text().splitlines():
    name, aliases, handler, root_req, mode, lock, interaction, risk, engines, json_ok, contract = line.split("|")
    handlers.append(handler)
    registry.append({"name": name, "aliases": sorted(filter(None, aliases.split(","))),
        "requires_root": root_req == "root", "operation_mode": mode, "lock_policy": lock,
        "interaction_mode": interaction, "risk_classification": risk,
        "supported_engines": sorted(engines.split(",")), "json_available": json_ok == "yes",
        "stable_api_contract": contract != "none", "api_contract_version": None if contract == "none" else contract})
records = caps["data"]["capabilities"]
assert records == sorted(registry, key=lambda item: item["name"])
assert len({r["name"] for r in records}) == len(records)
assert all(h not in json.dumps(caps) for h in handlers)

native, docker = load_runtime("native.json"), load_runtime("docker.json")
native["generated_at"] = docker["generated_at"] = None
assert native == docker

fixtures = {
    "api-version-success.json": "api-version.schema.json",
    "api-version-invalid-arguments.json": "api-version.schema.json",
    "capabilities-success.json": "capabilities.schema.json",
    "capabilities-invalid-arguments.json": "capabilities.schema.json",
    "backup-status-native-healthy.json": "backup-status.schema.json",
    "backup-status-docker-healthy.json": "backup-status.schema.json",
    "backup-status-missing.json": "backup-status.schema.json",
    "backup-status-partial-disabled.json": "backup-status.schema.json",
    "restore-status-matching.json": "restore-status.schema.json",
    "restore-status-no-rehearsal.json": "restore-status.schema.json",
    "restore-status-failed-mismatch.json": "restore-status.schema.json",
    "backup-status-invalid-arguments.json": "backup-status.schema.json",
    "restore-status-invalid-arguments.json": "restore-status.schema.json",
    "backup-status-permission-denied.json": "backup-status.schema.json",
    "restore-status-unavailable.json": "restore-status.schema.json",
    "backup-status-internal-error.json": "backup-status.schema.json",
}
for filename, schema_name in fixtures.items():
    value = json.loads((root / "tests/fixtures/api/v1" / filename).read_text())
    validate(value, schemas["response-envelope.schema.json"])
    validate(value, schemas[schema_name])

base = json.loads((root / "tests/fixtures/api/v1/capabilities-success.json").read_text())
negative = []
case = copy.deepcopy(base); case["success"] = "true"; negative.append(case)
case = copy.deepcopy(base); case["extra"] = 1; negative.append(case)
case = copy.deepcopy(base); case["success"] = False; negative.append(case)
case = copy.deepcopy(base); case["data"]["capabilities"][0]["aliases"] = ["dup", "dup"]; negative.append(case)
case = copy.deepcopy(base); case["data"]["capabilities"][0]["supported_engines"] = ["native", "native"]; negative.append(case)
case = copy.deepcopy(base); case["data"]["capabilities"][0]["supported_engines"] = ["remote"]; negative.append(case)
case = copy.deepcopy(base); case["data"]["capabilities"][0]["operation_mode"] = "probe"; negative.append(case)
case = copy.deepcopy(base); case["data"]["capabilities"][0]["api_contract_version"] = None; negative.append(case)
case = copy.deepcopy(base); case["data"]["capabilities"][1]["api_contract_version"] = "1.0"; negative.append(case)
case = copy.deepcopy(base); case["data"]["capabilities"][0]["api_contract_version"] = "2.0"; negative.append(case)
for case in negative: rejects(case, "capabilities.schema.json")

bad_version = json.loads((root / "tests/fixtures/api/v1/api-version-success.json").read_text())
bad_version["data"]["supported_api_versions"] = ["2.0"]
rejects(bad_version, "api-version.schema.json")
PY

# Repeated output is deterministic except for generated_at.
run_cli repeat capabilities --json
python3 - "$work/caps_command.out" "$work/repeat.out" <<'PY'
import json, sys
a, b = (json.load(open(path, encoding="utf-8")) for path in sys.argv[1:])
a["generated_at"] = b["generated_at"] = None
assert a == b
PY

# Static ordering proves early dispatch precedes UI, log, profile, platform and lock paths.
python3 - "$root_dir/erpnext-dev.sh" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
dispatch = text.index('if stable_api_parse "$@"; then')
for marker in ('erpnext_dev_init_terminal_colors\n', 'prepare_log_file\n', 'validate_platform_profile_combination', 'acquire_toolkit_lock'):
    assert dispatch < text.index(marker, dispatch)
PY

echo 'JSON API contract tests: all checks passed'
