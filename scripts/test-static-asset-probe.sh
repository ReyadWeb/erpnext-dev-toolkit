#!/usr/bin/env bash
# Hermetic tests for login Link-header static-asset probe helpers (no ERPNext).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SITE_NAME="erp.test"
_ERPNEXT_DEV_ROOT="$ROOT_DIR"

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/access.sh"

fail=0
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${label}: expected '${expected}' got '${actual}'" >&2
    fail=$((fail + 1))
  else
    echo "OK: ${label}"
  fi
}

assert_eq "extract css from Link" \
  "/assets/frappe/dist/css/website.bundle.AID4Y6BO.css" \
  "$(extract_link_asset_path $'HTTP/2 200\nLink: </assets/frappe/dist/css/website.bundle.AID4Y6BO.css>; as=style; rel=preload\n')"

assert_eq "extract js when css absent" \
  "/assets/frappe/dist/js/website.bundle.ABC.js" \
  "$(extract_link_asset_path $'HTTP/1.1 200 OK\nLink: </assets/frappe/dist/js/website.bundle.ABC.js>; as=script; rel=preload\n')"

assert_eq "extract empty without Link" \
  "" \
  "$(extract_link_asset_path $'HTTP/1.1 200 OK\nContent-Type: text/html\n')"

# Mock curl for probe_login_static_asset (login HEAD + asset HEAD).
tmpdir="$(mktemp -d /tmp/erpnext-dev-asset-probe.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Last non-option arg is the URL.
url="${*: -1}"
case "$url" in
  */login)
    printf 'HTTP/2 200\r\n'
    printf 'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
    printf '\r\n'
    ;;
  */website.bundle.TEST.css)
    printf 'HTTP/2 200\r\n\r\n'
    ;;
  *)
    printf 'HTTP/1.1 404 Not Found\r\n\r\n'
    exit 0
    ;;
esac
EOF
chmod +x "${tmpdir}/curl"
export PATH="${tmpdir}:${PATH}"

probe_out=""
probe_rc=0
probe_out="$(probe_login_static_asset "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "probe rc success" "0" "$probe_rc"
assert_eq "probe path" "/assets/frappe/dist/css/website.bundle.TEST.css" "${probe_out%%|*}"
assert_eq "probe status contains 200" "1" "$([[ "$probe_out" == *200* ]] && echo 1 || echo 0)"

# Asset missing -> rc 1
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
  */login)
    printf 'HTTP/2 200\r\nLink: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n\r\n'
    ;;
  *)
    printf 'HTTP/1.1 404 Not Found\r\n\r\n'
    ;;
esac
EOF
chmod +x "${tmpdir}/curl"
probe_rc=0
probe_out="$(probe_login_static_asset "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "probe rc asset fail" "1" "$probe_rc"

# No Link header -> rc 2
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
printf 'HTTP/2 200\r\nContent-Type: text/html\r\n\r\n'
EOF
chmod +x "${tmpdir}/curl"
probe_rc=0
probe_out="$(probe_login_static_asset "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "probe rc no link" "2" "$probe_rc"

if (( fail > 0 )); then
  echo "test-static-asset-probe: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-static-asset-probe: all checks passed"
