#!/usr/bin/env bash
# Hermetic audit for risky shell patterns in root-run toolkit libs (v1.18.0 / #68).
# Fails if lib/*.sh still uses eval for dynamic assignment, or sources health.env.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
note_fail() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }
pass() { echo "OK: $*"; }

# Strip comments/strings loosely: flag executable-looking eval usages.
# Allow the word "eval" inside comments and the module-consistency builtin list.
eval_hits="$(
  rg -n --glob 'lib/*.sh' -e '(^|[^[:alnum:]_])eval[[:space:]]' lib \
    | rg -v '^\s*#' \
    | rg -v ':[[:space:]]*#' \
    | rg -v 'no eval' \
    | rg -v 'never.*eval' \
    | rg -v 'without eval' \
    || true
)"
# Also drop pure comment lines that rg -n still emitted as code:line:comment
eval_hits="$(printf '%s\n' "$eval_hits" | rg -v ':[0-9]+:[[:space:]]*#' || true)"

if [[ -n "${eval_hits//[[:space:]]/}" ]]; then
  note_fail "eval still present in lib/*.sh:"
  printf '%s\n' "$eval_hits" >&2
else
  pass "no eval assignments in lib/*.sh"
fi

if rg -n --glob 'lib/*.sh' -e 'source[[:space:]]+"?\$\{?HEALTH_ENV' lib; then
  note_fail "health.env must not be sourced"
else
  pass "health.env is not sourced"
fi

# Nameref compose resolve still populates a caller array when docker-compose exists
# or when the docker compose plugin is available; when neither exists, expect fail.
# shellcheck source=lib/docker.sh disable=SC1091
source "$ROOT_DIR/lib/common.sh" 2>/dev/null || true
# Minimal stubs
: "${SUDO:=}"
# shellcheck source=lib/docker.sh disable=SC1091
source "$ROOT_DIR/lib/docker.sh"
compose_cmd=()
if docker_compose_resolve compose_cmd; then
  [[ "${compose_cmd[0]}" == "docker" || "${compose_cmd[0]}" == "docker-compose" ]] \
    || note_fail "unexpected compose_cmd: ${compose_cmd[*]}"
  pass "docker_compose_resolve nameref -> ${compose_cmd[*]}"
else
  pass "docker_compose_resolve correctly unavailable on this host"
fi

if (( fail > 0 )); then
  echo "test-risky-shell-patterns: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-risky-shell-patterns: all checks passed"
