#!/usr/bin/env bash
set -Eeuo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -c 'source "$1/lib/api.sh"; ! stable_api_parse dashboard && ! stable_api_parse health-snapshot && ! stable_api_parse incidents' _ "$root_dir" \
  || fail 'no-flag human/legacy commands were classified as stable API calls'

run_cli() {
  local name="$1"
  shift
  set +e
  ERPNEXT_DEV_OPERATIONS_TEST_ALLOW_NONROOT=1 HEALTH_CPU_SAMPLE_SEC=0.01 \
    HEALTH_LIB_DIR="$work/health" LOG_FILE="$work/log" LOCK_DIR="$work/lock" \
    "$root_dir/erpnext-dev.sh" "$@" >"$work/$name.out" 2>"$work/$name.err"
  printf '%s' "$?" >"$work/$name.rc"
  set -e
}

for spec in 'dashboard --json' '--json dashboard' 'dashboard --no-color --json' '--no-color --json dashboard' \
  'health-snapshot --json' '--json health-snapshot' 'incidents --json' '--json incidents'; do
  name="ok_${spec//[^a-zA-Z0-9]/_}"
  # shellcheck disable=SC2086
  run_cli "$name" $spec
  [[ "$(<"$work/$name.rc")" == 0 ]] || fail "$spec failed"
  [[ ! -s "$work/$name.err" ]] || fail "$spec wrote stderr"
  [[ "$(wc -l <"$work/$name.out")" == 1 ]] || fail "$spec did not emit one line"
done

for command_name in dashboard health-snapshot incidents; do
  for bad in '--watch' '--details' '--force' 'unexpected' ';touch-hostile'; do
    name="bad_${command_name}_${bad//[^a-zA-Z0-9]/_}"
    run_cli "$name" "$command_name" --json "$bad"
    [[ "$(<"$work/$name.rc")" == 64 ]] || fail "$command_name accepted $bad"
    [[ ! -s "$work/$name.err" ]] || fail 'JSON argument error wrote stderr'
  done
done

python3 - "$work/ok_incidents___json.out" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d["success"] and d["data"]["incidents"]==[] and d["data"]["limit"]==20
PY

mkdir -p "$work/health/incidents"
for i in $(seq -w 1 23); do
  ts="2026-01-${i}T00:00:00Z"
  id="incident-${i}"
  printf '{"id":"%s","timestamp":"%s","previous_status":"HEALTHY","status":"DEGRADED","site":"erp.test","host":"HEALTHY","application":"DEGRADED","http":"HEALTHY","protection":"HEALTHY","would_heal":"none"}\n' "$id" "$ts" >"$work/health/incidents/$id.json"
  chmod 0600 "$work/health/incidents/$id.json"
done
ln -s incident-23.json "$work/health/incidents/latest.json"
printf '{"id":"bad","id":"duplicate"}\n' >"$work/health/incidents/bad.json"
chmod 0600 "$work/health/incidents/bad.json"
ln -s incident-01.json "$work/health/incidents/symlink.json"
find "$work/health" -printf '%P|%y|%m|%U|%G|%T@|%l\n' | LC_ALL=C sort >"$work/tree.before"
find "$work/health" -type f -exec sha256sum {} + | LC_ALL=C sort >"$work/hashes.before"
run_cli populated incidents --json
find "$work/health" -printf '%P|%y|%m|%U|%G|%T@|%l\n' | LC_ALL=C sort >"$work/tree.after"
find "$work/health" -type f -exec sha256sum {} + | LC_ALL=C sort >"$work/hashes.after"
cmp -s "$work/tree.before" "$work/tree.after" || fail 'incident execution changed directory metadata'
cmp -s "$work/hashes.before" "$work/hashes.after" || fail 'incident execution changed file contents'
python3 - "$work/populated.out" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))["data"]
assert d["count"]==20 and d["truncated"] is True
assert [x["timestamp"] for x in d["incidents"]]==sorted((x["timestamp"] for x in d["incidents"]),reverse=True)
assert "incident_invalid" in d["issues"] and "incident_not_regular" in d["issues"]
assert all("http_detail" not in x for x in d["incidents"])
PY

if ((EUID != 0)); then
  set +e
  "$root_dir/erpnext-dev.sh" dashboard --json >"$work/permission.out" 2>"$work/permission.err"
  rc=$?
  set -e
  [[ "$rc" == 77 && ! -s "$work/permission.err" ]] || fail 'permission contract'
  grep -Fq '"id":"permission_denied"' "$work/permission.out" || fail 'permission id'
fi

for forbidden in health_snapshot_write_compat_state health_monitor_after_snapshot health_history_append health_record_incident \
  health_alert_dispatch healing_maybe_execute 'docker exec' 'docker compose exec' 'docker compose run' 'redis-cli'; do
  ! grep -Fq "$forbidden" "$root_dir/lib/operations_api.sh" || fail "forbidden stable path: $forbidden"
done
[[ ! -e "$work/log" && ! -e "$work/lock" ]] || fail 'stable execution created log or lock'

runtime_version="$(cat VERSION)"
python3 - "$work" "$runtime_version" <<'PY'
import json,pathlib,re,sys
work=pathlib.Path(sys.argv[1])
runtime_version=sys.argv[2]
for p in work.glob("ok_*.out"):
 d=json.loads(p.read_text()); assert d["api_version"]=="1.0" and d["error"] is None and d["success"] is True
 assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ",d["generated_at"])
 raw=p.read_bytes(); assert b"\x1b" not in raw and all(c in (9,10,13) or c>=32 for c in raw)
for command in ("dashboard","health-snapshot"):
 candidates=[p for p in work.glob("ok_*.out") if json.loads(p.read_text())["command"]==command]
 d=json.loads(candidates[0].read_text())
 assert d["data"]["toolkit_version"]==runtime_version
 assert set(d["data"])=={"toolkit_version","observed_at","deployment","overall_status","resources","application","runtime","protection","healing","checks","issues"}
PY
echo 'test-operations-api: all checks passed'
