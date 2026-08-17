#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
primary="$work/primary.env"
legacy="$work/legacy.env"
marker='deployment-info-fixture-91ac'
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

write_config() {
  local path="$1"
  shift
  printf '%s\n' "$@" >"$path"
  chmod 0644 "$path"
}

run_case() {
  local name="$1"
  shift
  set +e
  CONFIG_FILE="$primary" LEGACY_CONFIG_FILE="$legacy" \
    INSTALLATION_PROFILE=invalid DEPLOYMENT_ENGINE=invalid SITE_NAME="${marker}.invalid" \
    DB_ADMIN_PASSWORD="$marker" ADMIN_PASSWORD="$marker" API_TOKEN="$marker" \
    LOG_DIR="$work/no-log-dir" LOG_FILE="$work/toolkit.log" \
    LOCK_DIR="$work/locks" LOCK_FILE="$work/locks/toolkit.lock" \
    "$root_dir/erpnext-dev.sh" "$@" >"$work/$name.out" 2>"$work/$name.err"
  printf '%s' "$?" >"$work/$name.rc"
  set -e
}

status_is() {
  python3 - "$work/$1.out" "$2" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))["data"]["configuration"]["status"] == sys.argv[2]
PY
}

deployment_is() {
  python3 - "$work/$1.out" "$2" "$3" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["data"]["deployment"]
assert d["engine"] == sys.argv[2] and d["installation_profile"] == sys.argv[3]
PY
}

schema2_native=(
  'CONFIG_SCHEMA=2' 'DEPLOYMENT_ENGINE=native' 'INSTALLATION_PROFILE=recommended'
  'DEPLOYMENT_MODE=development' 'RUNTIME_MODE=dev' 'DOCKER_MODE=development'
  'SITE_NAME=erp.test' 'PRODUCTION_DOMAIN='
)
write_config "$primary" "${schema2_native[@]}"
cp "$primary" "$work/native.before"
run_case native deployment-info --json
status_is native managed
deployment_is native native recommended
cmp -s "$primary" "$work/native.before" || fail 'Native fixture was modified'

write_config "$primary" 'CONFIG_SCHEMA=2' 'DEPLOYMENT_ENGINE=native' 'INSTALLATION_PROFILE=frappe-only' 'SITE_NAME=frappe.test'
run_case frappe_only --json deployment-info
deployment_is frappe_only native frappe-only

write_config "$primary" 'CONFIG_SCHEMA=2' 'DEPLOYMENT_ENGINE=docker' 'INSTALLATION_PROFILE=recommended' 'DEPLOYMENT_MODE=development' 'RUNTIME_MODE=dev' 'DOCKER_MODE=development' 'SITE_NAME=docker.test'
run_case docker_dev deployment-info --no-color --json
deployment_is docker_dev docker recommended

write_config "$primary" 'CONFIG_SCHEMA=2' 'DEPLOYMENT_ENGINE=docker' 'INSTALLATION_PROFILE=recommended' 'DEPLOYMENT_MODE=public-vm' 'RUNTIME_MODE=production' 'DOCKER_MODE=production' 'SITE_NAME=erp.example.com' 'PRODUCTION_DOMAIN=erp.example.com'
run_case docker_prod --no-color --json deployment-info
deployment_is docker_prod docker recommended

write_config "$primary" 'CONFIG_SCHEMA=2' 'DEPLOYMENT_ENGINE=docker' 'INSTALLATION_PROFILE=advanced' 'INSTALLATION_PROFILE_APPS=crm,helpdesk' 'DOCKER_MODE=production' 'SITE_NAME=apps.example.com'
run_case advanced deployment-info --json
deployment_is advanced docker advanced

# Legacy explicit values and documented defaults.
write_config "$primary" 'DEPLOYMENT_ENGINE=docker' 'INSTALLATION_PROFILE=recommended' 'DOCKER_MODE=development' 'SITE_NAME=legacy.test'
run_case legacy_explicit deployment-info --json
status_is legacy_explicit legacy-compatible
write_config "$primary" 'DEPLOYMENT_MODE=development' 'RUNTIME_MODE=dev' 'SITE_NAME=default.test'
run_case legacy_defaults deployment-info --json
status_is legacy_defaults legacy-compatible
python3 - "$work/legacy_defaults.out" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))["data"]["deployment"]
assert (d["engine"],d["engine_source"],d["installation_profile"],d["profile_source"]) == ("native","legacy-default","recommended","legacy-default")
PY

# Missing, fallback, identical mirror and conflict precedence.
rm -f "$primary" "$legacy"
run_case missing deployment-info --json
status_is missing missing
write_config "$legacy" 'DEPLOYMENT_ENGINE=native' 'INSTALLATION_PROFILE=recommended' 'SITE_NAME=legacy.test'
run_case fallback deployment-info --json
status_is fallback legacy-compatible
cp "$legacy" "$primary"
run_case identical deployment-info --json
status_is identical legacy-compatible
write_config "$legacy" 'DEPLOYMENT_ENGINE=native' 'INSTALLATION_PROFILE=frappe-only' 'SITE_NAME=legacy.test'
run_case conflict deployment-info --json
status_is conflict conflict

# File trust states. Primary failures never fall back to the valid legacy file.
write_config "$legacy" 'DEPLOYMENT_ENGINE=native' 'INSTALLATION_PROFILE=recommended' 'SITE_NAME=legacy.test'
write_config "$primary" "${schema2_native[@]}"
chmod 0000 "$primary"
run_case unreadable deployment-info --json
status_is unreadable unreadable
rm -f "$primary"
ln -s "$legacy" "$primary"
run_case symlink deployment-info --json
status_is symlink unsafe
rm -f "$primary"
mkfifo "$primary"
run_case fifo deployment-info --json
status_is fifo unsafe
rm -f "$primary"
mkdir "$primary"
run_case directory deployment-info --json
status_is directory unsafe
rm -rf "$primary"
dd if=/dev/zero of="$primary" bs=65537 count=1 status=none
chmod 0644 "$primary"
run_case oversized deployment-info --json
status_is oversized unsafe
write_config "$primary" "${schema2_native[@]}"
chmod 0664 "$primary"
run_case group_writable deployment-info --json
status_is group_writable unsafe
chmod 0666 "$primary"
run_case world_writable deployment-info --json
status_is world_writable unsafe

# Invalid data matrix.
invalid_configs=(
  $'CONFIG_SCHEMA=2\nCONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=native\nINSTALLATION_PROFILE=recommended'
  $'CONFIG_SCHEMA=9\nDEPLOYMENT_ENGINE=native\nINSTALLATION_PROFILE=recommended'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=native\nINSTALLATION_PROFILE=existing'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=podman\nINSTALLATION_PROFILE=recommended'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=native\nINSTALLATION_PROFILE=recommended\nDEPLOYMENT_MODE=local'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=native\nINSTALLATION_PROFILE=recommended\nRUNTIME_MODE=running'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=docker\nINSTALLATION_PROFILE=recommended\nDOCKER_MODE=compose'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=docker\nINSTALLATION_PROFILE=advanced\nINSTALLATION_PROFILE_APPS=helpdesk,crm\nDOCKER_MODE=development'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=docker\nINSTALLATION_PROFILE=advanced\nINSTALLATION_PROFILE_APPS=crm,crm\nDOCKER_MODE=development'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=docker\nINSTALLATION_PROFILE=advanced\nINSTALLATION_PROFILE_APPS=custom_app\nDOCKER_MODE=development'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=native\nINSTALLATION_PROFILE=recommended\nSITE_NAME=https://erp.test'
  $'CONFIG_SCHEMA=2\nDEPLOYMENT_ENGINE=native\nINSTALLATION_PROFILE=recommended\nPRODUCTION_DOMAIN=erp.example.com:443'
)
index=0
for contents in "${invalid_configs[@]}"; do
  index=$((index + 1))
  printf '%s\n' "$contents" >"$primary"
  chmod 0644 "$primary"
  run_case "invalid_config_$index" deployment-info --json
  status_is "invalid_config_$index" invalid
done

# Payloads are parsed as inert data; unknown secret-like keys and comments never escape.
execution_marker="$work/payload-executed"
write_config "$primary" 'CONFIG_SCHEMA=2' 'DEPLOYMENT_ENGINE=native' 'INSTALLATION_PROFILE=recommended' \
  'SITE_NAME=$(touch /tmp/deployment-info-must-not-run)' \
  "DB_PASSWORD=$marker" "API_TOKEN=$marker" "# PRIVATE_GIT_URL=https://${marker}.invalid/repo" \
  'SSH_PRIVATE_KEY=`touch /tmp/deployment-info-backtick-must-not-run`'
run_case inert deployment-info --json
status_is inert invalid
[[ ! -e "$execution_marker" && ! -e /tmp/deployment-info-must-not-run && ! -e /tmp/deployment-info-backtick-must-not-run ]]
! grep -R -Fq "$marker" "$work"/*.out "$work"/*.err 2>/dev/null || fail 'secret fixture escaped'

# Stable argument parser cases, including unsupported leading global flags.
rm -f "$primary" "$legacy"
argument_cases=(
  'deployment-info --json status' 'deployment-info status --json'
  '--json deployment-info status' 'deployment-info --json --unknown'
  '--yes deployment-info --json' '--unknown deployment-info --json'
  'deployment-info --profile recommended --json' 'deployment-info unexpected extra --json'
)
index=0
for args in "${argument_cases[@]}"; do
  index=$((index + 1))
  # shellcheck disable=SC2086
  run_case "argument_$index" $args
  [[ "$(<"$work/argument_$index.rc")" == 64 ]]
  [[ ! -s "$work/argument_$index.err" ]]
done

# A different first action remains legacy and is not reclassified.
set +e
LOG_FILE="$work/legacy-command.log" "$root_dir/erpnext-dev.sh" version deployment-info --json >"$work/legacy-command.out" 2>"$work/legacy-command.err"
legacy_rc=$?
set -e
[[ "$legacy_rc" -eq 0 ]]
grep -Fxq 'ERPNext Developer Toolkit v1.20.4' "$work/legacy-command.out"

# Human output is separate, concise and explicitly non-observational.
run_case human deployment-info --no-color
[[ "$(<"$work/human.rc")" == 0 ]]
! python3 -m json.tool <"$work/human.out" >/dev/null 2>&1
grep -Fq 'Runtime and inventory were not inspected' "$work/human.out"

# Immediate-fail stubs prove the command executes no prohibited probe command.
probe_marker="$work/probe-called"
probe_fail() {
  printf '%s\n' "$1" >>"$probe_marker"
  return 99
}
sudo() { probe_fail sudo; }
docker() { probe_fail docker; }
mariadb() { probe_fail mariadb; }
mysql() { probe_fail mysql; }
bench() { probe_fail bench; }
systemctl() { probe_fail systemctl; }
service() { probe_fail service; }
curl() { probe_fail curl; }
wget() { probe_fail wget; }
ssh() { probe_fail ssh; }
git() { probe_fail git; }
export -f probe_fail sudo docker mariadb mysql bench systemctl service curl wget ssh git
run_case prohibited deployment-info --json
[[ ! -e "$probe_marker" ]]
unset -f probe_fail sudo docker mariadb mysql bench systemctl service curl wget ssh git

# No stable invocation creates the normal log or lock.
[[ ! -e "$work/toolkit.log" && ! -e "$work/locks" ]]

python3 - "$root_dir" "$work" "$marker" <<'PY'
import copy, datetime, json, pathlib, re, sys
root, work, marker = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
schemas = {p.name: json.loads(p.read_text()) for p in (root/"schemas/api/v1").glob("*.json")}
def resolve(ref, doc):
    if ref.startswith("#"): target, frag, target_doc = doc, ref[1:], doc
    else:
        name, _, frag = ref.partition("#"); target = target_doc = schemas[name]
    for token in frag.removeprefix("/").split("/") if frag else (): target = target[token]
    return target, target_doc
def validate(value, schema, doc=None):
    doc = doc or schema
    if "$ref" in schema:
        target, target_doc = resolve(schema["$ref"], doc); validate(value, target, target_doc)
    for item in schema.get("allOf", ()): validate(value, item, doc)
    if "oneOf" in schema:
        count=0
        for item in schema["oneOf"]:
            try: validate(value,item,doc); count+=1
            except (AssertionError,KeyError,TypeError): pass
        assert count == 1
    if "const" in schema: assert value == schema["const"]
    if "enum" in schema: assert value in schema["enum"]
    types=schema.get("type")
    if types:
        types=[types] if isinstance(types,str) else types
        checks={"object":lambda x:isinstance(x,dict),"array":lambda x:isinstance(x,list),"string":lambda x:isinstance(x,str),"boolean":lambda x:isinstance(x,bool),"null":lambda x:x is None,"integer":lambda x:isinstance(x,int) and not isinstance(x,bool),"number":lambda x:isinstance(x,(int,float)) and not isinstance(x,bool)}
        assert any(checks[t](value) for t in types)
    if "pattern" in schema and value is not None: assert re.fullmatch(schema["pattern"],value)
    if isinstance(value,dict):
        assert set(schema.get("required",())) <= set(value)
        props=schema.get("properties",{})
        if schema.get("additionalProperties") is False: assert set(value) <= set(props)
        for key in set(value)&set(props): validate(value[key],props[key],doc)
    if isinstance(value,list):
        for item in value: validate(item,schema["items"],doc) if "items" in schema else None
        assert len(value)>=schema.get("minItems",0) and len(value)<=schema.get("maxItems",10**9)
        if schema.get("uniqueItems"): assert len({json.dumps(x,sort_keys=True) for x in value})==len(value)
        if "contains" in schema: assert any(_matches(x,schema["contains"],doc) for x in value)
def _matches(value,schema,doc):
    try: validate(value,schema,doc); return True
    except (AssertionError,KeyError,TypeError): return False
def reject(value): assert not _matches(value,schemas["deployment-info.schema.json"],schemas["deployment-info.schema.json"])
def load(path):
    raw=path.read_bytes(); assert raw.endswith(b"\n") and raw.count(b"\n")==1
    assert marker.encode() not in raw and b"\x1b" not in raw and not any(c<32 for c in raw[:-1])
    value=json.loads(raw); datetime.datetime.strptime(value["generated_at"],"%Y-%m-%dT%H:%M:%SZ"); return value

for path in sorted((root/"tests/fixtures/api/v1").glob("deployment-info-*.json")):
    value=json.loads(path.read_text()); validate(value,schemas["response-envelope.schema.json"]); validate(value,schemas["deployment-info.schema.json"])
for prefix, schema_name in (("dashboard-","dashboard.schema.json"),("health-snapshot-","health-snapshot.schema.json"),("incidents-","incidents.schema.json")):
    for path in sorted((root/"tests/fixtures/api/v1").glob(prefix+"*.json")):
        value=json.loads(path.read_text()); validate(value,schemas["response-envelope.schema.json"]); validate(value,schemas[schema_name])
for path in sorted(work.glob("*.out")):
    if path.name.startswith(("human","legacy-command","encoder","serialization")) or not path.stat().st_size: continue
    try: value=load(path)
    except json.JSONDecodeError: continue
    if value.get("command")=="deployment-info": validate(value,schemas["deployment-info.schema.json"])

base=json.loads((root/"tests/fixtures/api/v1/deployment-info-native.json").read_text())
negative=[]
c=copy.deepcopy(base); del c["data"]["observation"]; negative.append(c)
c=copy.deepcopy(base); c["data"]["extra"]=1; negative.append(c)
c=copy.deepcopy(base); c["data"]["deployment"]["engine"]=7; negative.append(c)
c=copy.deepcopy(base); c["data"]["configuration"]["status"]="ready"; negative.append(c)
c=copy.deepcopy(base); c["data"]["deployment"]["site_name"]="https://erp.test"; negative.append(c)
c=copy.deepcopy(base); c["data"]["issues"]=["configuration_invalid","configuration_invalid"]; negative.append(c)
c=copy.deepcopy(base); c["data"]["deployment"]["requested_applications"]=["crm","crm"]; negative.append(c)
c=copy.deepcopy(base); c["data"]["deployment"]["docker_mode"]="production"; negative.append(c)
c=copy.deepcopy(base); c["data"]["deployment"]["engine"]="docker"; c["data"]["deployment"]["docker_mode"]=None; negative.append(c)
c=json.loads((root/"tests/fixtures/api/v1/deployment-info-missing.json").read_text()); c["data"]["deployment"]["engine"]="native"; negative.append(c)
c=json.loads((root/"tests/fixtures/api/v1/deployment-info-missing.json").read_text()); c["data"]["observation"]["management_scope"]="configuration-only"; negative.append(c)
c=json.loads((root/"tests/fixtures/api/v1/deployment-info-invalid-arguments.json").read_text()); c["data"]={}; negative.append(c)
c=copy.deepcopy(base); c["api_version"]="2.0"; negative.append(c)
for value in negative: reject(value)
PY

# Deterministic output except timestamp.
rm -f "$primary" "$legacy"
run_case repeat_one deployment-info --json
run_case repeat_two deployment-info --json
python3 - "$work/repeat_one.out" "$work/repeat_two.out" <<'PY'
import json,sys
a,b=(json.load(open(p)) for p in sys.argv[1:]); a["generated_at"]=b["generated_at"]=None; assert a==b
PY

echo 'deployment-info API tests: all checks passed'
