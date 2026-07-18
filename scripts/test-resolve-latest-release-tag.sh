#!/usr/bin/env bash
# Hermetic coverage for latest-tag resolution (mocked curl).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() { echo "OK: $*"; }

tmpdir="$(mktemp -d /tmp/erpnext-dev-resolve-latest.XXXXXX)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
# Emulate: curl -fsSL -o /dev/null -w '%{url_effective}' URL
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w)
      shift
      if [[ "${1:-}" == "%{url_effective}" ]]; then
        printf 'https://github.com/ReyadWeb/erpnext-dev-toolkit/releases/tag/v1.18.0'
        exit 0
      fi
      ;;
  esac
  shift || true
done
exit 1
EOF
chmod +x "${tmpdir}/curl"

PATH="${tmpdir}:${PATH}"
got="$(scripts/resolve-latest-release-tag.sh)"
[[ "${got}" == "v1.18.0" ]] || fail "expected v1.18.0, got '${got}'"
pass "resolve-latest-release-tag.sh reads url_effective tag"

cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w)
      shift
      if [[ "${1:-}" == "%{url_effective}" ]]; then
        printf 'https://github.com/ReyadWeb/erpnext-dev-toolkit/releases'
        exit 0
      fi
      ;;
  esac
  shift || true
done
exit 1
EOF
if scripts/resolve-latest-release-tag.sh >/tmp/erpnext-dev-resolve-bad.$$ 2>&1; then
  cat /tmp/erpnext-dev-resolve-bad.$$
  rm -f /tmp/erpnext-dev-resolve-bad.$$
  fail "resolver should fail without a /tag/ URL"
fi
rm -f /tmp/erpnext-dev-resolve-bad.$$
pass "resolve-latest-release-tag.sh fails closed without /tag/"

pass "latest-release tag resolver tests passed"
