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

LOGIN_LINKS=$'HTTP/2 200\nLink: </assets/frappe/dist/css/website.bundle.AID4Y6BO.css>; as=style; rel=preload\nLink: </assets/frappe/dist/js/website.bundle.ABC.js>; as=script; rel=preload\n'

assert_eq "extract first css|js from Link" \
  "/assets/frappe/dist/css/website.bundle.AID4Y6BO.css" \
  "$(extract_link_asset_path "$LOGIN_LINKS")"

assert_eq "extract css helper" \
  "/assets/frappe/dist/css/website.bundle.AID4Y6BO.css" \
  "$(extract_link_asset_path_css "$LOGIN_LINKS")"

assert_eq "extract js helper" \
  "/assets/frappe/dist/js/website.bundle.ABC.js" \
  "$(extract_link_asset_path_js "$LOGIN_LINKS")"

assert_eq "extract js when css absent" \
  "/assets/frappe/dist/js/website.bundle.ABC.js" \
  "$(extract_link_asset_path $'HTTP/1.1 200 OK\nLink: </assets/frappe/dist/js/website.bundle.ABC.js>; as=script; rel=preload\n')"

assert_eq "extract empty without Link" \
  "" \
  "$(extract_link_asset_path $'HTTP/1.1 200 OK\nContent-Type: text/html\n')"

# asset_headers_nonempty
asset_headers_nonempty $'HTTP/2 200\nContent-Length: 120\n' || {
  echo "FAIL: nonempty CL should pass" >&2
  fail=$((fail + 1))
}
if asset_headers_nonempty $'HTTP/2 200\nContent-Length: 0\n'; then
  echo "FAIL: zero CL should fail" >&2
  fail=$((fail + 1))
else
  echo "OK: zero Content-Length rejected"
fi
asset_headers_nonempty $'HTTP/2 200\n' || {
  echo "FAIL: missing CL should pass" >&2
  fail=$((fail + 1))
}
echo "OK: asset_headers_nonempty"

# Mock curl for probes (login HEAD + asset HEAD).
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
    printf 'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
    printf '\r\n'
    ;;
  */website.bundle.TEST.css|*/website.bundle.TEST.js)
    printf 'HTTP/2 200\r\nContent-Length: 42\r\n\r\n'
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
assert_eq "single probe rc success" "0" "$probe_rc"
assert_eq "single probe path" "/assets/frappe/dist/css/website.bundle.TEST.css" "${probe_out%%|*}"
assert_eq "single probe status contains 200" "1" "$([[ "$probe_out" == *200* ]] && echo 1 || echo 0)"

probe_rc=0
probe_out="$(probe_login_frontend_assets "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "dual probe rc success" "0" "$probe_rc"
assert_eq "dual probe has css path" "1" "$([[ "$probe_out" == */website.bundle.TEST.css* ]] && echo 1 || echo 0)"
assert_eq "dual probe has js path" "1" "$([[ "$probe_out" == */website.bundle.TEST.js* ]] && echo 1 || echo 0)"

# Explicit empty body (Content-Length: 0) -> single probe rc 1
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
  */login)
    printf 'HTTP/2 200\r\nLink: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n\r\n'
    ;;
  *)
    printf 'HTTP/2 200\r\nContent-Length: 0\r\n\r\n'
    ;;
esac
EOF
chmod +x "${tmpdir}/curl"
probe_rc=0
probe_out="$(probe_login_static_asset "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "single probe rc empty body" "1" "$probe_rc"

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
assert_eq "single probe rc asset fail" "1" "$probe_rc"

# No Link header -> rc 2
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
printf 'HTTP/2 200\r\nContent-Type: text/html\r\n\r\n'
EOF
chmod +x "${tmpdir}/curl"
probe_rc=0
probe_out="$(probe_login_static_asset "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "single probe rc no link" "2" "$probe_rc"

# Dual: JS OK / CSS 404 -> NOT READY
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
  */login)
    printf 'HTTP/2 200\r\n'
    printf 'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
    printf 'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
    printf '\r\n'
    ;;
  */website.bundle.TEST.js)
    printf 'HTTP/2 200\r\nContent-Length: 42\r\n\r\n'
    ;;
  */website.bundle.TEST.css)
    printf 'HTTP/1.1 404 Not Found\r\n\r\n'
    ;;
  *)
    printf 'HTTP/1.1 404 Not Found\r\n\r\n'
    ;;
esac
EOF
chmod +x "${tmpdir}/curl"
probe_rc=0
probe_out="$(probe_login_frontend_assets "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "dual probe JS OK CSS 404 -> rc 1" "1" "$probe_rc"

# Dual: CSS empty body + JS OK -> NOT READY
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
  */login)
    printf 'HTTP/2 200\r\n'
    printf 'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
    printf 'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
    printf '\r\n'
    ;;
  */website.bundle.TEST.css)
    printf 'HTTP/2 200\r\nContent-Length: 0\r\n\r\n'
    ;;
  */website.bundle.TEST.js)
    printf 'HTTP/2 200\r\nContent-Length: 42\r\n\r\n'
    ;;
  *)
    printf 'HTTP/1.1 404 Not Found\r\n\r\n'
    ;;
esac
EOF
chmod +x "${tmpdir}/curl"
probe_rc=0
probe_out="$(probe_login_frontend_assets "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "dual probe CSS empty JS OK -> rc 1" "1" "$probe_rc"

# Dual: only CSS Link advertised -> rc 2
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
  */login)
    printf 'HTTP/2 200\r\nLink: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n\r\n'
    ;;
  *)
    printf 'HTTP/2 200\r\nContent-Length: 42\r\n\r\n'
    ;;
esac
EOF
chmod +x "${tmpdir}/curl"
probe_rc=0
probe_out="$(probe_login_frontend_assets "https://erp.test/login" "erp.test" 443 "127.0.0.1")" && probe_rc=0 || probe_rc=$?
assert_eq "dual probe CSS-only Link -> rc 2" "2" "$probe_rc"

# bench_static_assets_ready must use dual probe (CSS+JS).
# Minimal copy of the fixed helper so we do not source all of lib/service.sh.
bench_static_assets_ready() {
  local probe_rc=0
  if port_listens 443; then
    set +e
    probe_login_frontend_assets "https://${SITE_NAME}/login" "$SITE_NAME" 443 "127.0.0.1" >/dev/null
    probe_rc=$?
    set -e
  elif port_listens 8000; then
    set +e
    probe_login_frontend_assets "http://${SITE_NAME}:8000/login" "$SITE_NAME" 8000 "127.0.0.1" >/dev/null
    probe_rc=$?
    set -e
  else
    return 1
  fi
  [[ "$probe_rc" -eq 0 ]]
}
port_listens() { [[ "$1" == "443" ]]; }

# JS OK / CSS 404: ready helper must fail.
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
*/login)
  printf 'HTTP/2 200\r\n'
  printf 'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
  printf 'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
  printf '\r\n'
  ;;
*/website.bundle.TEST.js)
  printf 'HTTP/2 200\r\nContent-Length: 42\r\n\r\n'
  ;;
*)
  printf 'HTTP/1.1 404 Not Found\r\n\r\n'
  ;;
esac
EOF
chmod +x "${tmpdir}/curl"
if bench_static_assets_ready; then
  echo "FAIL: bench_static_assets_ready should reject JS OK / CSS 404" >&2
  fail=$((fail + 1))
else
  echo "OK: bench_static_assets_ready rejects JS OK / CSS missing"
fi

# CSS empty + JS OK: ready helper must fail.
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
*/login)
  printf 'HTTP/2 200\r\n'
  printf 'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
  printf 'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
  printf '\r\n'
  ;;
*/website.bundle.TEST.css)
  printf 'HTTP/2 200\r\nContent-Length: 0\r\n\r\n'
  ;;
*/website.bundle.TEST.js)
  printf 'HTTP/2 200\r\nContent-Length: 42\r\n\r\n'
  ;;
*)
  printf 'HTTP/1.1 404 Not Found\r\n\r\n'
  ;;
esac
EOF
chmod +x "${tmpdir}/curl"
if bench_static_assets_ready; then
  echo "FAIL: bench_static_assets_ready should reject empty CSS body" >&2
  fail=$((fail + 1))
else
  echo "OK: bench_static_assets_ready rejects empty CSS body"
fi

# Both nonempty: ready helper must pass.
cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
*/login)
  printf 'HTTP/2 200\r\n'
  printf 'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
  printf 'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
  printf '\r\n'
  ;;
*/website.bundle.TEST.css|*/website.bundle.TEST.js)
  printf 'HTTP/2 200\r\nContent-Length: 42\r\n\r\n'
  ;;
*)
  printf 'HTTP/1.1 404 Not Found\r\n\r\n'
  ;;
esac
EOF
chmod +x "${tmpdir}/curl"
if bench_static_assets_ready; then
  echo "OK: bench_static_assets_ready accepts CSS+JS nonempty"
else
  echo "FAIL: bench_static_assets_ready should accept dual nonempty assets" >&2
  fail=$((fail + 1))
fi

# Drift guards: production helper must use dual probe + probe return code.
if grep -A25 '^bench_static_assets_ready()' "${ROOT_DIR}/lib/service.sh" | grep -q 'http_status_ok "\$asset_head"'; then
  echo "FAIL: lib/service.sh bench_static_assets_ready still uses http_status_ok on probe output (ignores empty body)" >&2
  fail=$((fail + 1))
else
  echo "OK: lib/service.sh bench_static_assets_ready uses probe rc"
fi
if ! grep -A25 '^bench_static_assets_ready()' "${ROOT_DIR}/lib/service.sh" | grep -q 'probe_rc'; then
  echo "FAIL: lib/service.sh bench_static_assets_ready missing probe_rc check" >&2
  fail=$((fail + 1))
else
  echo "OK: lib/service.sh probe_rc present"
fi
if ! grep -A25 '^bench_static_assets_ready()' "${ROOT_DIR}/lib/service.sh" | grep -q 'probe_login_frontend_assets'; then
  echo "FAIL: lib/service.sh bench_static_assets_ready must call probe_login_frontend_assets" >&2
  fail=$((fail + 1))
else
  echo "OK: lib/service.sh uses dual CSS+JS probe"
fi
if grep -A25 '^bench_static_assets_ready()' "${ROOT_DIR}/lib/service.sh" | grep -q 'probe_login_static_asset'; then
  echo "FAIL: lib/service.sh bench_static_assets_ready still uses single-asset probe" >&2
  fail=$((fail + 1))
else
  echo "OK: lib/service.sh no longer uses single-asset probe for ready"
fi

if ((fail > 0)); then
  echo "test-static-asset-probe: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-static-asset-probe: all checks passed"
