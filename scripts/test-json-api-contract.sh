#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fixture_marker='api-contract-fixture-7f2c9d'
run_json() {
  local output="$1" error="$2"
  shift 2
  ERPNEXT_DEV_LOG_DIR="$work/logs" LOG_FILE="$work/toolkit.log" \
    DB_ADMIN_PASSWORD="$fixture_marker" ADMIN_PASSWORD="$fixture_marker" \
    PRIVATE_URL="https://${fixture_marker}.invalid/private" "$root_dir/erpnext-dev.sh" "$@" >"$output" 2>"$error"
}

run_json "$work/version.json" "$work/version.err" api-version --json
run_json "$work/capabilities.json" "$work/capabilities.err" capabilities --json
[[ ! -s "$work/version.err" && ! -s "$work/capabilities.err" ]]

set +e
run_json "$work/error.json" "$work/error.err" api-version --json unexpected
error_rc=$?
set -e
[[ "$error_rc" -eq 64 ]] || {
  echo "FAIL: invalid argument exit was $error_rc, expected 64" >&2
  exit 1
}
[[ ! -s "$work/error.err" ]]

ERPNEXT_DEV_LOG_DIR="$work/logs" LOG_FILE="$work/toolkit.log" "$root_dir/erpnext-dev.sh" api-version >"$work/human.txt" 2>"$work/human.err"
grep -q '^Machine API version: 1.0$' "$work/human.txt"
! python3 -m json.tool <"$work/human.txt" >/dev/null 2>&1

ERPNEXT_DEV_LOG_DIR="$work/logs" LOG_FILE="$work/toolkit.log" DEPLOYMENT_ENGINE=native "$root_dir/erpnext-dev.sh" capabilities --json >"$work/native.json" 2>"$work/native.err"
ERPNEXT_DEV_LOG_DIR="$work/logs" LOG_FILE="$work/toolkit.log" DEPLOYMENT_ENGINE=docker "$root_dir/erpnext-dev.sh" capabilities --json >"$work/docker.json" 2>"$work/docker.err"

ERPNEXT_DEV_LOG_DIR="$work/logs" LOG_FILE=/dev/null bash -c \
  'source "$1" --help >/dev/null 2>&1 || true; command_registry_records' _ \
  "$root_dir/erpnext-dev.sh" >"$work/registry.txt"

python3 - "$root_dir" "$work" "$fixture_marker" <<'PY'
import datetime, json, pathlib, re, sys
root, work, fixture_marker = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]

schemas = {}
for schema_path in sorted((root / "schemas/api/v1").glob("*.json")):
    schema = json.loads(schema_path.read_text())
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    schemas[schema_path.name] = schema

def schema_validate(value, schema, document=None):
    document = document or schema
    if "$ref" in schema:
        target = document
        for token in schema["$ref"].removeprefix("#/").split("/"):
            target = target[token]
        return schema_validate(value, target, document)
    if "oneOf" in schema:
        passed = 0
        for branch in schema["oneOf"]:
            try: schema_validate(value, branch, document); passed += 1
            except AssertionError: pass
        assert passed == 1
    if "const" in schema: assert value == schema["const"]
    if "enum" in schema: assert value in schema["enum"]
    types = schema.get("type")
    if types:
        types = [types] if isinstance(types, str) else types
        checks = {"object": lambda x: isinstance(x, dict), "array": lambda x: isinstance(x, list),
                  "string": lambda x: isinstance(x, str), "boolean": lambda x: isinstance(x, bool),
                  "null": lambda x: x is None}
        assert any(checks[k](value) for k in types)
    if "pattern" in schema: assert re.fullmatch(schema["pattern"], value)
    if isinstance(value, dict):
        assert set(schema.get("required", ())) <= set(value)
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False: assert set(value) <= set(properties)
        for key in set(value) & set(properties): schema_validate(value[key], properties[key], document)
    if isinstance(value, list) and "items" in schema:
        for item in value: schema_validate(item, schema["items"], document)
        assert len(value) >= schema.get("minItems", 0)
        if schema.get("uniqueItems"): assert len({json.dumps(x, sort_keys=True) for x in value}) == len(value)

def load(name):
    raw = (work / name).read_bytes()
    assert fixture_marker.encode() not in raw
    assert not any(byte < 0x20 for byte in raw.rstrip(b"\n"))
    assert b"\x1b" not in raw
    return json.loads(raw)

def envelope(value, command, success):
    assert list(value) == ["api_version", "generated_at", "command", "success", "data", "error"]
    assert value["api_version"] == "1.0" and value["command"] == command
    assert value["success"] is success and isinstance(value["success"], bool)
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", value["generated_at"])
    datetime.datetime.strptime(value["generated_at"], "%Y-%m-%dT%H:%M:%SZ")
    if success:
        assert isinstance(value["data"], dict) and value["error"] is None
    else:
        assert value["data"] is None and set(value["error"]) == {"id", "message", "details"}
        assert isinstance(value["error"]["id"], str) and isinstance(value["error"]["message"], str)
        assert isinstance(value["error"]["details"], dict)

version = load("version.json"); envelope(version, "api-version", True)
schema_validate(version, schemas["response-envelope.schema.json"])
schema_validate(version, schemas["api-version.schema.json"])
assert version["data"] == {"current_api_version": "1.0", "supported_api_versions": ["1.0"], "toolkit_version": "1.20.4"}
failure = load("error.json"); envelope(failure, "api-version", False)
schema_validate(failure, schemas["response-envelope.schema.json"])
schema_validate(failure, schemas["api-version.schema.json"])
assert failure["error"]["id"] == "invalid_arguments"
caps = load("capabilities.json"); envelope(caps, "capabilities", True)
schema_validate(caps, schemas["response-envelope.schema.json"])
schema_validate(caps, schemas["capabilities.schema.json"])

registry = []
handlers = []
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
assert [r["name"] for r in records] == sorted(r["name"] for r in records)
assert all(isinstance(r["aliases"], list) and isinstance(r["supported_engines"], list) for r in records)
serialized = json.dumps(caps)
assert all(handler not in serialized for handler in handlers)
assert {r["name"] for r in records if r["stable_api_contract"]} == {"api-version", "capabilities"}

native, docker = load("native.json"), load("docker.json")
for item in (native, docker): item["generated_at"] = "TIMESTAMP"
assert native == docker

for fixture in sorted((root / "tests/fixtures/api/v1").glob("*.json")):
    fixture_value = json.loads(fixture.read_text())
    schema_validate(fixture_value, schemas["response-envelope.schema.json"])
PY

# Timestamp aside, repeated capability output is byte deterministic.
run_json "$work/repeat.json" "$work/repeat.err" capabilities --json
python3 - "$work/capabilities.json" "$work/repeat.json" <<'PY'
import json, sys
a, b = (json.load(open(path, encoding="utf-8")) for path in sys.argv[1:])
a["generated_at"] = b["generated_at"] = None
assert a == b
PY

echo "JSON API contract tests: all checks passed"
