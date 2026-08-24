#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ASSERTIONS=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
pass() {
  ASSERTIONS=$((ASSERTIONS + 1))
  printf 'OK: %s\n' "$1"
}
assert_has() {
  grep -Fq -- "$3" <<<"$2" || fail "$1: missing [$3]"
  pass "$1"
}
assert_lacks() {
  ! grep -Fq -- "$3" <<<"$2" || fail "$1: found [$3]"
  pass "$1"
}

mkdir -p "$WORK/bin" "$WORK/fixtures"
cat >"$WORK/fixtures/bootstrap-verify.sh" <<'BOOTSTRAP'
#!/usr/bin/env bash
set -eu
[[ "${TEST_BOOTSTRAP_FAIL:-0}" != 1 ]] || exit 41
root="$2/erpnext-dev-$1"
mkdir -p "$root"
cat >"$root/erpnext-dev.sh" <<'TOOLKIT'
#!/usr/bin/env bash
exit "${TEST_TOOLKIT_FAIL:-0}"
TOOLKIT
chmod +x "$root/erpnext-dev.sh"
BOOTSTRAP
chmod +x "$WORK/fixtures/bootstrap-verify.sh"

cat >"$WORK/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -eu
output="" url=""
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --write-out) shift 2 ;;
    --max-redirs|--connect-timeout|--max-time|--max-filesize|--proto) shift 2 ;;
    --tlsv1.2|--fail|--silent|--show-error|--location) shift ;;
    *) url="$1"; shift ;;
  esac
done
[[ "${TEST_CURL_FAIL:-0}" != 1 ]] || exit 22
case "$url" in
  */releases/latest|*/releases/tags/*|*/releases\?*) cp "$TEST_METADATA" "$output" ;;
  */RELEASE-ASSETS.sha256)
    digest="$(sha256sum "$TEST_BOOTSTRAP")"
    digest="${digest%% *}"
    [[ "${TEST_BAD_DIGEST:-0}" != 1 ]] || digest=0000000000000000000000000000000000000000000000000000000000000000
    printf '%s  bootstrap-verify.sh\n' "$digest" >"$output"
    [[ "${TEST_MISSING_BOOTSTRAP:-0}" != 1 ]] || printf '%s  archive.tar.gz\n' "$digest" >"$output"
    ;;
  */RELEASE-ASSETS.sha256.asc) printf 'signature\n' >"$output" ;;
  */erpnext-dev-signing-key.asc) printf 'key\n' >"$output" ;;
  */bootstrap-verify.sh) cp "$TEST_BOOTSTRAP" "$output" ;;
  *) exit 22 ;;
esac
if [[ "${TEST_BAD_REDIRECT:-0}" == 1 ]]; then
  printf 'https://evil.example/payload'
else
  printf '%s' "$url"
fi
CURL

cat >"$WORK/bin/gpg" <<'GPG'
#!/usr/bin/env bash
set -eu
if [[ "$*" == *--show-keys* ]]; then
  if [[ "${TEST_BAD_FINGERPRINT:-0}" == 1 ]]; then
    printf 'fpr:::::::::BAD:\n'
  else
    printf 'fpr:::::::::BFC10C79427CF73496EA6F5A30BFD17DD559C8B6:\n'
  fi
  exit 0
fi
[[ "${TEST_GPG_FAIL:-0}" != 1 ]] || exit 1
exit 0
GPG

cat >"$WORK/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$TEST_SUDO_LOG"
case "$*" in
  *update-toolkit*) exit "${TEST_UPDATE_FAIL:-0}" ;;
  *install-cli*) exit "${TEST_CLI_FAIL:-0}" ;;
  *first-run*) exit "${TEST_WIZARD_FAIL:-0}" ;;
esac
exit 0
SUDO
chmod +x "$WORK/bin/"*

write_metadata() { printf '%s\n' "$1" >"$WORK/fixtures/metadata.json"; }
run_case() {
  local name="$1"
  shift
  [[ "${1:-}" != env ]] || shift
  local extra_env=()
  while [[ "${1:-}" == *=* ]]; do
    extra_env+=("$1")
    shift
  done
  : >"$WORK/sudo.log"
  set +e
  if [[ "$name" == beta-confirm-required ]]; then
    output="$(PATH="$WORK/bin:$PATH" TEST_METADATA="$WORK/fixtures/metadata.json" \
      TEST_BOOTSTRAP="$WORK/fixtures/bootstrap-verify.sh" TEST_SUDO_LOG="$WORK/sudo.log" \
      env "${extra_env[@]}" setsid -w "$ROOT_DIR/install.sh" --no-start "$@" </dev/null 2>&1)"
  else
    output="$(PATH="$WORK/bin:$PATH" TEST_METADATA="$WORK/fixtures/metadata.json" \
      TEST_BOOTSTRAP="$WORK/fixtures/bootstrap-verify.sh" TEST_SUDO_LOG="$WORK/sudo.log" \
      env "${extra_env[@]}" "$ROOT_DIR/install.sh" --no-start "$@" 2>&1)"
  fi
  rc=$?
  set -e
  printf '%s' "$output" >"$WORK/$name.out"
}

stable='{"tag_name":"v1.20.4","draft":false,"prerelease":false}'
write_metadata "$stable"
run_case stable-default env
[[ "$rc" == 0 ]] || fail "stable default failed: $output"
assert_has 'stable default exact tag' "$output" 'v1.20.4'
assert_has 'stable atomic update' "$(<"$WORK/sudo.log")" 'TOOLKIT_UPDATE_VERSION=v1.20.4'
assert_has 'stable CLI repair' "$(<"$WORK/sudo.log")" 'erpnext-dev install-cli'
assert_lacks 'no-start skips wizard' "$(<"$WORK/sudo.log")" 'first-run'

write_metadata "$stable"
run_case stable-explicit env --stable
[[ "$rc" == 0 ]] || fail 'explicit stable failed'
pass 'explicit stable channel'

write_metadata '[{"tag_name":"v1.9.9-beta.9","draft":false,"prerelease":true},{"tag_name":"v2.0.0-beta.1","draft":false,"prerelease":true},{"tag_name":"v9.0.0-beta.8","draft":true,"prerelease":true},{"tag_name":"v3.0.0-rc.1","draft":false,"prerelease":true},{"tag_name":"v4.0.0-alpha.1","draft":false,"prerelease":true},{"tag_name":"v5.0.0-beta.2-unsigned","draft":false,"prerelease":true}]'
run_case beta env --beta --yes
[[ "$rc" == 0 ]] || fail "beta selection failed: $output"
assert_has 'semantic beta selection' "$output" 'v2.0.0-beta.1'
assert_lacks 'draft beta ignored' "$output" 'v9.0.0-beta.8'
assert_has 'beta disposable warning' "$output" 'disposable testing only'
assert_lacks 'RC excluded from beta selection' "$output" 'v3.0.0-rc.1'
assert_lacks 'alpha excluded from beta selection' "$output" 'v4.0.0-alpha.1'
assert_lacks 'unsigned excluded from beta selection' "$output" 'v5.0.0-beta.2-unsigned'

run_case beta-confirm-required env --beta
[[ "$rc" != 0 ]] || fail 'beta confirmation was bypassed without --yes'
assert_has 'beta confirmation required' "$output" 'requires terminal confirmation or --yes'
[[ ! -s "$WORK/sudo.log" ]] || fail 'unconfirmed beta reached sudo'
pass 'unconfirmed beta is non-mutating'

write_metadata '[]'
run_case no-beta env --beta --yes
[[ "$rc" != 0 ]] || fail 'missing beta fell back'
assert_has 'no beta fails clearly' "$output" 'could not resolve a valid published beta release'
assert_lacks 'no beta has no sudo' "$(<"$WORK/sudo.log")" 'update-toolkit'

write_metadata "$stable"
run_case exact-stable env --tag v1.20.4
[[ "$rc" == 0 ]] || fail 'exact stable failed'
pass 'exact stable tag'
write_metadata '{"tag_name":"v1.21.0-beta.3","draft":false,"prerelease":true}'
run_case exact-beta env --beta --tag v1.21.0-beta.3 --yes
[[ "$rc" == 0 ]] || fail 'exact beta failed'
pass 'exact beta tag'

for args in '--stable --beta' '--stable --stable' '--tag v1.2.3 --tag v1.2.3' '--unknown' '--beta --tag v1.2.3' '--tag v1.2.3-beta.1'; do
  # shellcheck disable=SC2086 # deliberate invalid argument vectors
  run_case invalid env $args
  [[ "$rc" != 0 ]] || fail "invalid options accepted: $args"
  [[ ! -s "$WORK/sudo.log" ]] || fail "invalid options reached sudo: $args"
  pass "reject options $args"
done

for fault in TEST_CURL_FAIL TEST_BAD_REDIRECT TEST_BAD_FINGERPRINT TEST_GPG_FAIL TEST_MISSING_BOOTSTRAP TEST_BAD_DIGEST TEST_BOOTSTRAP_FAIL; do
  write_metadata "$stable"
  run_case "$fault" env "$fault=1"
  [[ "$rc" != 0 ]] || fail "$fault accepted"
  [[ ! -s "$WORK/sudo.log" ]] || fail "$fault reached privileged Toolkit action"
  pass "$fault fails before sudo Toolkit action"
done

write_metadata "$stable"
run_case update-fail env TEST_UPDATE_FAIL=31
[[ "$rc" != 0 ]] || fail 'atomic update failure ignored'
assert_lacks 'update failure blocks CLI' "$(<"$WORK/sudo.log")" 'install-cli'
run_case cli-fail env TEST_CLI_FAIL=32
[[ "$rc" != 0 ]] || fail 'CLI failure ignored'
pass 'CLI failure propagation'

write_metadata '{not-json'
run_case malformed env
[[ "$rc" != 0 ]] || fail 'malformed metadata accepted'
pass 'malformed metadata rejected'
python3 - <<'PY' >"$WORK/fixtures/metadata.json"
print(' ' * 1100000)
PY
run_case oversized env
[[ "$rc" != 0 ]] || fail 'oversized metadata accepted'
pass 'oversized metadata rejected'

! grep -Eq '(^|[^A-Za-z])eval[[:space:]]' "$ROOT_DIR/install.sh" || fail 'installer contains eval'
pass 'no eval'
! grep -Eq 'curl[^\n]*\|[^\n]*sudo|http://' "$ROOT_DIR/install.sh" || fail 'unsafe curl/sudo or HTTP construction'
pass 'no curl-to-sudo or insecure HTTP'
assert_lacks 'output excludes ANSI' "$(<"$WORK/stable-default.out")" $'\033'
assert_has 'event order resolution before verification' "$(<"$WORK/stable-default.out")" 'Verifying exact signed release'
assert_has 'event order verification before install' "$(<"$WORK/stable-default.out")" 'Installing verified release'
write_metadata "$stable"
run_case stable-repeat env
assert_lacks 'deterministic output has no temporary path' "$output" '/tmp/erpnext-dev-one-command.'
assert_has 'exit cleanup trap installed' "$(<"$ROOT_DIR/install.sh")" 'trap cleanup EXIT'
assert_has 'signal termination trap installed' "$(<"$ROOT_DIR/install.sh")" "trap 'exit 143' TERM"

: >"$WORK/sudo.log"
set +e
no_tty_output="$(PATH="$WORK/bin:$PATH" TEST_METADATA="$WORK/fixtures/metadata.json" \
  TEST_BOOTSTRAP="$WORK/fixtures/bootstrap-verify.sh" TEST_SUDO_LOG="$WORK/sudo.log" \
  "$ROOT_DIR/install.sh" --yes 2>&1)"
no_tty_rc=$?
set -e
[[ "$no_tty_rc" != 0 ]] || fail 'missing TTY was accepted'
assert_has 'missing TTY fails clearly' "$no_tty_output" 'first-run requires a usable /dev/tty'
[[ ! -s "$WORK/sudo.log" ]] || fail 'missing TTY reached installation'
pass 'missing TTY fails before installation'

: >"$WORK/sudo.log"
set +e
tty_output="$(PATH="$WORK/bin:$PATH" TEST_METADATA="$WORK/fixtures/metadata.json" \
  TEST_BOOTSTRAP="$WORK/fixtures/bootstrap-verify.sh" TEST_SUDO_LOG="$WORK/sudo.log" \
  TEST_WIZARD_FAIL=33 script -qefc "$ROOT_DIR/install.sh --yes" /dev/null </dev/null 2>&1)"
tty_rc=$?
set -e
[[ "$tty_rc" != 0 ]] || fail 'wizard failure was ignored'
assert_has 'wizard failure propagated' "$tty_output" 'first-run wizard failed'
assert_has 'wizard launched after CLI' "$(<"$WORK/sudo.log")" 'erpnext-dev first-run'

printf 'test-one-command-installer: %s assertions passed\n' "$ASSERTIONS"
