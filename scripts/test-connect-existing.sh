#!/usr/bin/env bash
set -Eeuo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
CONFIG_FILE="$tmp/config"
source "$root_dir/lib/connect.sh"
mkdir -p "$tmp/bench" "$tmp/docker"
chmod 700 "$tmp/bench" "$tmp/docker"
connect_existing_preview native "$tmp/bench" '' site.test >/dev/null
connect_existing native "$tmp/bench" '' site.test
[[ -f "$CONFIG_FILE.connection" ]]
echo 'OK: native connection persisted'
connect_existing native "$tmp/bench" '' site.test
echo 'OK: idempotent connection'
connect_existing_disconnect
[[ ! -e "$CONFIG_FILE.connection" ]]
echo 'OK: disconnect metadata only'
connect_existing_preview docker "$tmp/docker" project site.test >/dev/null
connect_existing docker "$tmp/docker" project site.test
grep -q 'managed=false' "$CONFIG_FILE.connection"
echo 'OK: docker unmanaged connection'
if connect_existing native relative '' site; then exit 1; fi
echo 'OK: unsafe path rejected'
if connect_existing docker "$tmp/docker" 'bad/project' site; then exit 1; fi
echo 'OK: unsafe project rejected'
DOCTOR_FORMAT=json
out="$(connect_existing_preview docker "$tmp/docker" project site.test)"
[[ "$out" == *'"external":true'* && "$out" == *'"mutation":false'* ]]
echo 'OK: secret-free JSON preview'
echo 'connect-existing tests: all checks passed'
