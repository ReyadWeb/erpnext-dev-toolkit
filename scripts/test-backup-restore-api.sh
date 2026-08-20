#!/usr/bin/env bash
set -Eeuo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$work/native" "$work/docker/erp.test/set-docker" "$work/evidence"
chmod 0700 "$work/native" "$work/docker" "$work/docker/erp.test" "$work/docker/erp.test/set-docker" "$work/evidence"
printf 'x' >"$work/native/20260820_120000-erp_test-database.sql.gz"
printf 'xx' >"$work/native/20260820_120000-erp_test-files.tar.gz"
printf 'xxx' >"$work/native/20260820_120000-erp_test-private-files.tar.gz"
printf '{}' >"$work/native/20260820_120000-erp_test-site_config_backup.json"
printf 'x' >"$work/docker/erp.test/set-docker/database.sql.gz"
printf 'x' >"$work/docker/erp.test/set-docker/files.tar.gz"
printf 'x' >"$work/docker/erp.test/set-docker/private-files.tar.gz"
printf '{}' >"$work/docker/erp.test/set-docker/site_config_backup.json"
printf 'metadata only\n' >"$work/docker/erp.test/set-docker/SHA256SUMS"
chmod 0600 "$work/native"/* "$work/docker/erp.test/set-docker"/*
printf 'OFF_VM_BACKUP_TARGET=secret-user@private-host:/secret/path\n' >"$work/evidence/off.env"
printf 'LAST_STATUS=OK\nLAST_RUN_AT=2026-08-20T12:00:00Z\n' >"$work/evidence/off.state"
printf 'OBJECT_RCLONE_REMOTE=secret-remote\nOBJECT_BUCKET=secret-bucket\n' >"$work/evidence/object.env"
printf 'LAST_STATUS=OK\nLAST_RUN_AT=2026-08-20T12:00:00Z\n' >"$work/evidence/object.state"
chmod 0600 "$work/evidence"/*

run_cli() {
  local name="$1" engine="$2" dir="$3"
  shift 3
  set +e
  ERPNEXT_DEV_BACKUP_API_TEST_ALLOW_NONROOT=1 BACKUP_API_ENGINE="$engine" BACKUP_API_SITE=erp.test \
    CONFIG_FILE="$work/no-config" LEGACY_CONFIG_FILE="$work/no-legacy-config" \
    BACKUP_API_BACKUP_DIR="$dir" BACKUP_API_NO_SYSTEMCTL=1 BACKUP_API_SCHEDULE_ENABLED=true BACKUP_API_SCHEDULE_ACTIVE=true \
    OFF_VM_BACKUP_CONFIG_FILE="$work/evidence/off.env" OFF_VM_BACKUP_STATE_FILE="$work/evidence/off.state" \
    OBJECT_BACKUP_CONFIG_FILE="$work/evidence/object.env" OBJECT_BACKUP_STATE_FILE="$work/evidence/object.state" \
    RESTORE_REHEARSAL_RECORD_FILE="$work/evidence/rehearsal.env" DOCKER_RESTORE_REHEARSAL_FILE="$work/evidence/docker-rehearsal.env" \
    LOG_FILE="$work/forbidden.log" LOCK_DIR="$work/forbidden-lock" "$root_dir/erpnext-dev.sh" "$@" >"$work/$name.out" 2>"$work/$name.err"
  printf '%s' "$?" >"$work/$name.rc"
  set -e
}

for spec in 'backup-status --json' '--json backup-status' 'backup-status --json --no-color' \
  'restore-status --json' '--no-color --json restore-status'; do
  name="ok_${spec//[^A-Za-z0-9]/_}"
  # shellcheck disable=SC2086
  run_cli "$name" native "$work/native" $spec
  [[ "$(<"$work/$name.rc")" == 0 && ! -s "$work/$name.err" ]] || fail "$spec failed"
  [[ "$(wc -l <"$work/$name.out")" == 1 ]] || fail "$spec did not emit exactly one JSON line"
done

for command_name in backup-status restore-status; do
  for bad in unexpected --watch --details --verify --force --latest selection; do
    run_cli "bad_${command_name}_${bad#--}" native "$work/native" "$command_name" --json "$bad"
    [[ "$(<"$work/bad_${command_name}_${bad#--}.rc")" == 64 ]] || fail "$command_name accepted $bad"
    [[ ! -s "$work/bad_${command_name}_${bad#--}.err" ]] || fail 'invalid JSON request wrote stderr'
  done
done

run_cli native native "$work/native" backup-status --json
run_cli docker docker "$work/docker/erp.test" backup-status --json
run_cli missing native "$work/missing" backup-status --json
mkdir "$work/partial"
chmod 0700 "$work/partial"
printf x >"$work/partial/partial-database.sql.gz"
chmod 0600 "$work/partial/partial-database.sql.gz"
run_cli partial native "$work/partial" backup-status --json
printf 'RESTORE_REHEARSAL_STATUS=OK\nRESTORE_REHEARSAL_RECORDED_AT=2026-08-20T13:00:00Z\nRESTORE_REHEARSAL_SITE=erp.test\nRESTORE_REHEARSAL_BACKUP_SET=20260820_120000-erp_test\nRESTORE_REHEARSAL_LOGIN_VALIDATED=true\n' >"$work/evidence/rehearsal.env"
chmod 0600 "$work/evidence/rehearsal.env"
run_cli restore native "$work/native" restore-status --json

python3 - "$work" <<'PY'
import json,pathlib,re,sys
w=pathlib.Path(sys.argv[1])
for p in w.glob("*.out"):
    if p.name.startswith("bad_"): continue
    raw=p.read_bytes(); assert raw.endswith(b"\n") and raw.count(b"\n")==1 and b"\x1b" not in raw
    assert all(c>=32 for c in raw[:-1])
    d=json.loads(raw); assert d["success"] and d["error"] is None
    assert d["command"] in ("backup-status","restore-status")
n=json.loads((w/"native.out").read_text())["data"]
d=json.loads((w/"docker.out").read_text())["data"]
assert set(n)==set(d) and set(n["local"])==set(d["local"])
assert n["local"]["latest_set"]["completeness"]=="complete"
assert d["local"]["storage_kind"]=="docker-host-artifact"
m=json.loads((w/"missing.out").read_text())["data"]
assert m["local"]["latest_set"] is None and "backup_directory_missing" in m["issues"]
p=json.loads((w/"partial.out").read_text())["data"]
assert p["local"]["latest_set"]["completeness"]=="partial" and "backup_set_partial" in p["issues"]
r=json.loads((w/"restore.out").read_text())["data"]
assert r["candidate"]["database_available"] and r["readiness"]["matching_rehearsal_proven"]
assert not r["readiness"]["deep_integrity_verified"] and not r["readiness"]["live_restore_performed"]
for p in w.glob("*.out"):
    raw=p.read_text(errors="strict")
    for secret in ("secret-user","private-host","secret/path","secret-remote","secret-bucket","database.sql.gz","site_config_backup.json"):
        assert secret not in raw
    for value in re.findall(r'"issues":\[(.*?)\]',raw): assert "//" not in value
PY

# Unsafe evidence fails closed and is never echoed. Each final-component type is
# tested independently so a permissive check cannot be hidden by another failure.
assert_unsafe_rehearsal() {
  local name="$1"
  run_cli "unsafe_$name" native "$work/native" restore-status --json
  grep -Fq 'rehearsal_evidence_unsafe' "$work/unsafe_$name.out" || fail "unsafe rehearsal was accepted: $name"
  ! grep -Fq 'marker-never-output' "$work/unsafe_$name.out" || fail "unsafe contents leaked: $name"
  rm -f "$work/evidence/rehearsal.env"
}
printf 'RESTORE_REHEARSAL_STATUS=OK\nRESTORE_REHEARSAL_STATUS=FAIL\n' >"$work/evidence/rehearsal.env"
chmod 0600 "$work/evidence/rehearsal.env"
assert_unsafe_rehearsal duplicate
printf 'RESTORE_REHEARSAL_STATUS=OK\377\n' >"$work/evidence/rehearsal.env"
chmod 0600 "$work/evidence/rehearsal.env"
assert_unsafe_rehearsal invalid_utf8
printf 'RESTORE_REHEARSAL_STATUS=OK\n' >"$work/evidence/rehearsal.env"
chmod 0666 "$work/evidence/rehearsal.env"
assert_unsafe_rehearsal permissions
ln -s /etc/passwd "$work/evidence/rehearsal.env"
assert_unsafe_rehearsal symlink
mkfifo "$work/evidence/rehearsal.env"
assert_unsafe_rehearsal fifo
ln -s /dev/null "$work/evidence/rehearsal.env"
assert_unsafe_rehearsal device
dd if=/dev/zero of="$work/evidence/rehearsal.env" bs=65537 count=1 status=none
chmod 0600 "$work/evidence/rehearsal.env"
assert_unsafe_rehearsal oversized

# The bounded reader must compare the same open file before/after reading; this
# is the deterministic regression guard for replacement and read-race defense.
grep -Fq '(before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns)' \
  "$root_dir/lib/backup_api.sh" || fail 'evidence read-race guard missing'

# Bounded scan and metadata-only proof: a FIFO and symlink are ignored and a large sparse archive is never opened.
mkdir "$work/bounded"
chmod 0700 "$work/bounded"
for i in $(seq 1 260); do printf x >"$work/bounded/set-$i-database.sql.gz"; done
mkfifo "$work/bounded/hostile.sql.gz"
ln -s /etc/passwd "$work/bounded/link-database.sql.gz"
chmod 0600 "$work/bounded"/set-*-database.sql.gz
run_cli bounded native "$work/bounded" backup-status --json
grep -Fq 'backup_scan_truncated' "$work/bounded.out" || fail 'bounded scan issue missing'

# Stable execution must remain ahead of all legacy side effects and prohibited commands.
[[ ! -e "$work/forbidden.log" && ! -e "$work/forbidden-lock" ]] || fail 'stable execution created logs or locks'
for token in 'docker exec' 'docker compose exec' 'docker compose run' 'bench ' 'frappe ' 'rsync ' 'rclone ' 'ssh ' 'git '; do
  ! grep -Fiq "$token" "$root_dir/lib/backup_api.sh" || fail "prohibited path appears: $token"
done
bash -c 'source "$1/lib/api.sh"; ! stable_api_parse backup-status && ! stable_api_parse restore-status' _ "$root_dir" \
  || fail 'human backup commands entered stable dispatch without --json'

if ((EUID != 0)); then
  set +e
  "$root_dir/erpnext-dev.sh" backup-status --json >"$work/permission.out" 2>"$work/permission.err"
  rc=$?
  set -e
  [[ "$rc" == 77 && ! -s "$work/permission.err" ]] || fail 'permission contract'
fi
echo 'test-backup-restore-api: all checks passed'
