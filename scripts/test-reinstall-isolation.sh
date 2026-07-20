#!/usr/bin/env bash
# Hermetic tests for clean-reinstall process isolation and archive safety.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail_count=0
pass() { echo "OK: $*"; }
fail_test() {
  echo "FAIL: $*" >&2
  fail_count=$((fail_count + 1))
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail_test "${label}: expected '${expected}' got '${actual}'"
  fi
}

tmpdir="$(mktemp -d /tmp/erpnext-dev-reinstall-isolation.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

export BENCH_PARENT="${tmpdir}/frappe"
export BENCH_NAME="frappe-bench"
export BENCH_DIR="${BENCH_PARENT}/${BENCH_NAME}"
export FRAPPE_USER="$(id -un)"
export SUDO=""
export ERPNEXT_DEV_PROC_ROOT="${tmpdir}/proc"
export ERPNEXT_SERVICE_NAME="erpnext-dev.service"
mkdir -p "$BENCH_DIR" "$ERPNEXT_DEV_PROC_ROOT"

# Minimal stubs required by the install module helpers under test.
path_is_dir() { [[ -d "$1" ]]; }
log() { :; }
ok() { :; }
warn() { :; }
err() { :; }
fail() {
  echo "ERROR: $*" >&2
  return 1
}
service_exists() { return 1; }
supervisorctl_bin() { printf '%s\n' "${tmpdir}/supervisorctl"; }
supervisor_conf_link() { printf '%s\n' "${tmpdir}/frappe-bench.conf"; }

# shellcheck source=lib/install.sh disable=SC1091
source "${ROOT_DIR}/lib/install.sh"

make_fake_proc() {
  local pid="$1" cwd="$2" cmd_arg="${3:-}" fd_target="${4:-}"
  local proc_dir="${ERPNEXT_DEV_PROC_ROOT}/${pid}"
  mkdir -p "${proc_dir}/fd"
  ln -s "$cwd" "${proc_dir}/cwd"
  ln -s / "${proc_dir}/root"
  ln -s /usr/bin/bash "${proc_dir}/exe"
  if [[ -n "$cmd_arg" ]]; then
    printf '%s\0' "$cmd_arg" >"${proc_dir}/cmdline"
  else
    printf 'bash\0' >"${proc_dir}/cmdline"
  fi
  if [[ -n "$fd_target" ]]; then
    mkdir -p "$(dirname "$fd_target")"
    : >"$fd_target"
    ln -s "$fd_target" "${proc_dir}/fd/9"
  fi
}

make_fake_proc 111 "${BENCH_DIR}" "python"
make_fake_proc 222 /tmp "${BENCH_DIR}/env/bin/python"
make_fake_proc 333 "${BENCH_PARENT}-backup-old/frappe-bench" "${BENCH_PARENT}-backup-old/frappe-bench/env/bin/python"
make_fake_proc 444 /tmp "python" "${BENCH_DIR}/sites/assets/assets.json"

assert_eq "tree boundary accepts child" "yes" "$(path_is_within_tree "${BENCH_DIR}/apps/frappe" "$BENCH_PARENT" && echo yes || echo no)"
assert_eq "tree boundary rejects backup sibling" "no" "$(path_is_within_tree "${BENCH_PARENT}-backup-old/frappe-bench" "$BENCH_PARENT" && echo yes || echo no)"
assert_eq "deleted proc suffix is normalized" "yes" "$(path_is_within_tree "${BENCH_DIR} (deleted)" "$BENCH_PARENT" && echo yes || echo no)"

expected_pids=$'111\n222\n444'
actual_pids="$(bench_reference_pids)"
assert_eq "bench process discovery is path-scoped" "$expected_pids" "$actual_pids"

if pid_references_bench_parent 333; then
  fail_test "backup sibling process must not match active BENCH_PARENT"
else
  pass "backup sibling process is ignored"
fi

mkdir -p "${BENCH_DIR}/config"
cat >"${BENCH_DIR}/config/supervisor.conf" <<EOF_SUPERVISOR
[program:frappe-bench-web]
command=${BENCH_DIR}/env/bin/gunicorn

[program:frappe-bench-worker]
command=${BENCH_DIR}/env/bin/python worker.py
EOF_SUPERVISOR
ln -s "${BENCH_DIR}/config/supervisor.conf" "$(supervisor_conf_link)"

if bench_supervisor_config_targets_environment; then
  pass "Supervisor config is associated with the active Bench"
else
  fail_test "Supervisor config association was not detected"
fi
assert_eq "Supervisor program discovery" $'frappe-bench-web\nfrappe-bench-worker' "$(bench_supervisor_programs)"

rm -f "$(supervisor_conf_link)"
cat >"${tmpdir}/unrelated.conf" <<'EOF_UNRELATED'
[program:other-app]
command=/srv/other-app/run
EOF_UNRELATED
ln -s "${tmpdir}/unrelated.conf" "$(supervisor_conf_link)"
if bench_supervisor_config_targets_environment; then
  fail_test "unrelated Supervisor config must not be treated as this Bench"
else
  pass "unrelated Supervisor config is ignored"
fi

assert_eq "known Bench runtime ports" $'6787\n8000\n9000\n11000\n12000\n13000' "$(bench_runtime_ports)"

# Live-process regression: terminate only a process rooted in the active Bench;
# a process rooted in an archive sibling must survive.
export ERPNEXT_DEV_PROC_ROOT=/proc
export BENCH_QUIESCE_TIMEOUT=3
mkdir -p "${BENCH_PARENT}-backup-old/frappe-bench"
python3 -c 'import time; time.sleep(60)' "${BENCH_DIR}/runtime-marker" &
active_pid=$!
python3 -c 'import time; time.sleep(60)' "${BENCH_PARENT}-backup-old/frappe-bench/runtime-marker" &
sibling_pid=$!
sleep 0.2

if terminate_bench_reference_processes; then
  pass "live Bench-owned process tree can be terminated"
else
  fail_test "live Bench-owned process tree was not terminated"
fi
wait "$active_pid" 2>/dev/null || true
if kill -0 "$active_pid" 2>/dev/null; then
  fail_test "active Bench process survived targeted termination"
  kill "$active_pid" 2>/dev/null || true
else
  pass "active Bench process was terminated"
fi
if kill -0 "$sibling_pid" 2>/dev/null; then
  pass "archive-sibling process was preserved"
  kill "$sibling_pid" 2>/dev/null || true
  wait "$sibling_pid" 2>/dev/null || true
else
  fail_test "archive-sibling process was terminated unexpectedly"
fi
export ERPNEXT_DEV_PROC_ROOT="${tmpdir}/proc"

# Regression guards: archive itself owns the quiesce boundary, so callers cannot
# accidentally move a live tree. Broad pkill-by-user patterns must stay out of
# the reinstall implementation because the same Unix user can own another Bench.
archive_body="$(sed -n '/^archive_existing_bench_parent()/,/^}/p' "${ROOT_DIR}/lib/install.sh")"
if grep -q 'stop_bench_processes' <<<"$archive_body"; then
  pass "archive enforces quiesce before move"
else
  fail_test "archive must enforce stop_bench_processes before mv"
fi

if grep -q 'pkill -u "\$FRAPPE_USER"' "${ROOT_DIR}/lib/install.sh"; then
  fail_test "install module still contains broad pkill-by-user cleanup"
else
  pass "reinstall cleanup avoids broad pkill-by-user"
fi

run_install_body="$(sed -n '/^run_install()/,/^}/p' "${ROOT_DIR}/lib/install.sh")"
if grep -Fq 'reinstall_runtime_mode="$(runtime_mode)"' <<<"$run_install_body" \
  && grep -Fq 'setup_production_runtime' <<<"$run_install_body" \
  && grep -Fq 'production_runtime_restored=1' <<<"$run_install_body"; then
  pass "clean reinstall preserves the prior production runtime mode"
else
  fail_test "run_install must restore Supervisor production mode after a production reinstall"
fi

if ((fail_count > 0)); then
  echo "test-reinstall-isolation: ${fail_count} failure(s)" >&2
  exit 1
fi

echo "test-reinstall-isolation: all checks passed"
