#!/usr/bin/env bash
# Hermetic tests for the strict health.env allowlist parser (v1.18.0 / #66).
# No sudo, no network. Never sources policy files as shell.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
note_fail() {
  echo "FAIL: $*" >&2
  fail=$((fail + 1))
}
pass() { echo "OK: $*"; }

bash -n lib/dashboard.sh || note_fail "bash -n lib/dashboard.sh"

# shellcheck source=lib/common.sh disable=SC1091
source "$ROOT_DIR/lib/common.sh"
FORCE_NO_COLOR=1
NO_COLOR=1
erpnext_dev_init_terminal_colors 2>/dev/null || true
: "${YELLOW:=}" "${RESET:=}" "${GREEN:=}" "${RED:=}" "${BLUE:=}" "${BOLD:=}"
# shellcheck source=lib/dashboard.sh disable=SC1091
source "$ROOT_DIR/lib/dashboard.sh"

tmpdir="$(mktemp -d /tmp/erpnext-dev-health-env.XXXXXX)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

export HEALTH_ENV_SKIP_OWNER_CHECK=1
export HEALTH_ENV_FILE="$tmpdir/health.env"

reset_policy_defaults() {
  HEALTH_ALERT_ON=CRITICAL
  HEALTH_ALERT_WEBHOOK_URL=
  HEALTH_ALERT_WEBHOOK_TIMEOUT_SEC=5
  HEALTH_ALERT_WEBHOOK_ALLOW_HTTP=0
  HEALTH_CONSECUTIVE_FAIL_THRESHOLD=3
  HEALTH_COOLDOWN_SEC=600
  HEALTH_HISTORY_MAX_LINES=2016
  HEALTH_INCIDENT_KEEP=50
}

# --- benign policy applies ---
reset_policy_defaults
cat >"$HEALTH_ENV_FILE" <<'EOF'
# comment
HEALTH_ALERT_ON=DEGRADED
HEALTH_ALERT_WEBHOOK_URL=https://hooks.example.com/erpnext-dev
HEALTH_CONSECUTIVE_FAIL_THRESHOLD=5
HEALTH_COOLDOWN_SEC=900
HEALTH_DISK_DEGRADED_PERCENT=75
EOF
chmod 600 "$HEALTH_ENV_FILE"
health_load_policy
[[ "$HEALTH_ALERT_ON" == "DEGRADED" ]] || note_fail "ALERT_ON not applied (got ${HEALTH_ALERT_ON})"
[[ "$HEALTH_ALERT_WEBHOOK_URL" == "https://hooks.example.com/erpnext-dev" ]] || note_fail "webhook URL not applied"
[[ "$HEALTH_CONSECUTIVE_FAIL_THRESHOLD" == "5" ]] || note_fail "fail threshold not applied"
[[ "$HEALTH_COOLDOWN_SEC" == "900" ]] || note_fail "cooldown not applied"
[[ "$HEALTH_DISK_DEGRADED_PERCENT" == "75" ]] || note_fail "disk degraded percent not applied"
pass "benign allowlisted keys apply"

# --- malicious / unknown keys ignored ---
reset_policy_defaults
cat >"$HEALTH_ENV_FILE" <<'EOF'
HEALTH_ALERT_ON=CRITICAL
EVIL_KEY=1
PATH=/tmp/evil
HEALTH_ALERT_WEBHOOK_URL=https://ok.example/hook
$(touch /tmp/pwned)
HEALTH_COOLDOWN_SEC=$((1+2))
HEALTH_ALERT_ON=CRITICAL; rm -rf /
UNKNOWN_THING=yes
HEALTH_ALERT_WEBHOOK_URL=http://evil.example/hook
EOF
chmod 600 "$HEALTH_ENV_FILE"
health_load_policy
[[ "$HEALTH_ALERT_ON" == "CRITICAL" ]] || note_fail "ALERT_ON should stay CRITICAL from first valid line"
[[ "$HEALTH_ALERT_WEBHOOK_URL" == "https://ok.example/hook" ]] || note_fail "http evil webhook should not replace https ok"
[[ "$HEALTH_COOLDOWN_SEC" == "600" ]] || note_fail "arithmetic/command value must not apply (got ${HEALTH_COOLDOWN_SEC})"
[[ "${PATH}" != "/tmp/evil" ]] || note_fail "PATH must not be overwritten by health.env"
pass "malicious and unknown keys ignored"

# --- shell metacharacters in values rejected ---
reset_policy_defaults
cat >"$HEALTH_ENV_FILE" <<'EOF'
HEALTH_ALERT_WEBHOOK_URL=https://ok.example/`id`
HEALTH_COOLDOWN_SEC=600;id
EOF
chmod 600 "$HEALTH_ENV_FILE"
health_load_policy
[[ -z "$HEALTH_ALERT_WEBHOOK_URL" ]] || note_fail "backtick webhook must be rejected"
[[ "$HEALTH_COOLDOWN_SEC" == "600" ]] || note_fail "semicolon cooldown must be rejected"
pass "shell metacharacters rejected"

# --- local http webhook allowed; remote http rejected ---
reset_policy_defaults
cat >"$HEALTH_ENV_FILE" <<'EOF'
HEALTH_ALERT_WEBHOOK_URL=http://127.0.0.1:9999/hook
EOF
chmod 600 "$HEALTH_ENV_FILE"
health_load_policy
[[ "$HEALTH_ALERT_WEBHOOK_URL" == "http://127.0.0.1:9999/hook" ]] || note_fail "localhost http webhook should be allowed"
reset_policy_defaults
cat >"$HEALTH_ENV_FILE" <<'EOF'
HEALTH_ALERT_WEBHOOK_URL=http://example.com/hook
EOF
chmod 600 "$HEALTH_ENV_FILE"
health_load_policy
[[ -z "$HEALTH_ALERT_WEBHOOK_URL" ]] || note_fail "remote http webhook must be rejected without ALLOW_HTTP"
pass "webhook URL scheme rules"

# --- world-writable / bad mode rejected when owner checks on ---
reset_policy_defaults
export HEALTH_ENV_SKIP_OWNER_CHECK=0
cat >"$HEALTH_ENV_FILE" <<'EOF'
HEALTH_COOLDOWN_SEC=111
EOF
chmod 666 "$HEALTH_ENV_FILE"
health_load_policy
[[ "$HEALTH_COOLDOWN_SEC" == "600" ]] || note_fail "world-writable policy must be ignored"
chmod 600 "$HEALTH_ENV_FILE"
health_load_policy
[[ "$HEALTH_COOLDOWN_SEC" == "111" ]] || note_fail "owner-matching 600 file should apply for non-root tests (got ${HEALTH_COOLDOWN_SEC})"
pass "permission gate"
export HEALTH_ENV_SKIP_OWNER_CHECK=1

# --- source must not appear in load path (static check) ---
if grep -nE 'source[[:space:]]+"?\$\{?HEALTH_ENV' lib/dashboard.sh; then
  note_fail "health.env must not be sourced"
else
  pass "no source of HEALTH_ENV_FILE"
fi

if ((fail > 0)); then
  echo "test-health-env-parser: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-health-env-parser: all checks passed"
