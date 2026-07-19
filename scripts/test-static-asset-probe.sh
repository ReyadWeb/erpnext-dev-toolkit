#!/usr/bin/env bash
# Hermetic tests for login frontend asset discovery + all-assets probes (no ERPNext).
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

LOGIN_LINKS=$'HTTP/2 200\nLink: </assets/frappe/dist/css/website.bundle.AID4Y6BO.css>; as=style; rel=preload\nLink: </assets/frappe/dist/css/login.bundle.6WUAC63A.css>; as=style; rel=preload\nLink: </assets/frappe/dist/js/website.bundle.ABC.js>; as=script; rel=preload\n'

assert_eq "extract all link paths count" "3" \
  "$(extract_all_link_asset_paths "$LOGIN_LINKS" | wc -l | tr -d ' ')"

assert_eq "legacy first css still works" \
  "/assets/frappe/dist/css/website.bundle.AID4Y6BO.css" \
  "$(extract_link_asset_path_css "$LOGIN_LINKS")"

HTML_MULTI=$'<html><link href="/assets/frappe/dist/css/website.bundle.A.css" rel="stylesheet">\n<link href="/assets/frappe/dist/css/login.bundle.B.css">\n<link href="/assets/erpnext/dist/css/erpnext-web.bundle.C.css">\n<script src="/assets/frappe/dist/js/website.bundle.D.js"></script>\n<link href="https://cdn.example/x.css">\n</html>'

assert_eq "html extract ignores external" "4" \
  "$(extract_all_html_asset_paths "$HTML_MULTI" | wc -l | tr -d ' ')"

# Deduped union of Link + HTML overlapping website.css
MIXED_HTML=$'<link href="/assets/frappe/dist/css/website.bundle.A.css"><script src="/assets/frappe/dist/js/website.bundle.D.js">'
MIXED_HEADERS=$'HTTP/2 200\nLink: </assets/frappe/dist/css/website.bundle.A.css>; as=style; rel=preload\nLink: </assets/frappe/dist/css/login.bundle.B.css>; as=style; rel=preload\n'
union_count="$(
  {
    extract_all_link_asset_paths "$MIXED_HEADERS"
    extract_all_html_asset_paths "$MIXED_HTML"
  } | awk 'NF && !seen[$0]++' | wc -l | tr -d ' '
)"
assert_eq "html+link dedupe count" "3" "$union_count"

# asset_headers_nonempty (legacy helper still used by older call sites/tests)
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
echo "OK: asset_headers_nonempty"

# Drift guard: login/asset probes must use GET header dump, not HEAD (-I).
if grep -A20 '^curl_response_headers()' "${ROOT_DIR}/lib/access.sh" | grep -qE -- '-I\b'; then
  echo "FAIL: curl_response_headers still uses HEAD (-I)" >&2
  fail=$((fail + 1))
else
  echo "OK: curl_response_headers does not use HEAD -I"
fi

tmpdir="$(mktemp -d /tmp/erpnext-dev-asset-probe.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Mock curl: supports -D - -o BODY for login, and -w metrics for asset GETs.
write_curl_mock() {
  cat >"${tmpdir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=""
body_out="/dev/null"
write_out=""
dump_headers=0
args=("$@")
i=0
while ((i < ${#args[@]})); do
  a="${args[$i]}"
  case "$a" in
    -o)
      i=$((i + 1))
      body_out="${args[$i]}"
      ;;
    -D)
      i=$((i + 1))
      [[ "${args[$i]}" == "-" ]] && dump_headers=1
      ;;
    -w)
      i=$((i + 1))
      write_out="${args[$i]}"
      ;;
    --resolve|--max-time|--max-redirs)
      i=$((i + 1))
      ;;
    -*)
      ;;
    *)
      url="$a"
      ;;
  esac
  i=$((i + 1))
done

# Asset probe with -w: print metrics only (body discarded).
if [[ -n "$write_out" ]]; then
  case "$url" in
    */website.bundle.TEST.css|*/website.bundle.TEST.js|*/login.bundle.TEST.css|*/erpnext-web.bundle.TEST.css|*/website.bundle.OK.js)
      printf '200|42|text/css|%s' "$url"
      ;;
    */login.bundle.MISSING.css|*/erpnext-web.bundle.MISSING.css|*/third.bundle.MISSING.css)
      printf '404|0||%s' "$url"
      ;;
    */empty.bundle.css)
      printf '200|0|text/css|%s' "$url"
      ;;
    */bytes-no-cl.css)
      # size_download > 0 even without Content-Length on a real curl; mock bytes.
      printf '200|99|text/css|%s' "$url"
      ;;
    *)
      printf '404|0||%s' "$url"
      ;;
  esac
  exit 0
fi

# Login document: headers on stdout when -D -, body to -o file.
if [[ "$url" == */login* ]]; then
  mode="${MOCK_LOGIN_MODE:-full3}"
  hdr=""
  body=""
  case "$mode" in
    full3)
      hdr=$'HTTP/2 200\r\n'
      hdr+=$'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/frappe/dist/css/login.bundle.TEST.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/erpnext/dist/css/erpnext-web.bundle.TEST.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
      hdr+=$'\r\n'
      body=$'<html><link href="/assets/frappe/dist/css/website.bundle.TEST.css"><script src="/assets/frappe/dist/js/website.bundle.TEST.js"></script></html>'
      ;;
    field_fail)
      # website + js OK; login + erpnext-web missing (field failure shape)
      hdr=$'HTTP/2 200\r\n'
      hdr+=$'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/frappe/dist/css/login.bundle.MISSING.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/erpnext/dist/css/erpnext-web.bundle.MISSING.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
      hdr+=$'\r\n'
      body=$'<html><link href="/assets/frappe/dist/css/website.bundle.TEST.css"><link href="/assets/frappe/dist/css/login.bundle.MISSING.css"><link href="/assets/erpnext/dist/css/erpnext-web.bundle.MISSING.css"><script src="/assets/frappe/dist/js/website.bundle.TEST.js"></script></html>'
      ;;
    third_css_fail)
      hdr=$'HTTP/2 200\r\n'
      hdr+=$'Link: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/frappe/dist/css/login.bundle.TEST.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/frappe/dist/css/third.bundle.MISSING.css>; as=style; rel=preload\r\n'
      hdr+=$'Link: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n'
      hdr+=$'\r\n'
      body='<html></html>'
      ;;
    empty_css)
      hdr=$'HTTP/2 200\r\nLink: </assets/frappe/dist/css/empty.bundle.css>; as=style; rel=preload\r\nLink: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n\r\n'
      body='<html></html>'
      ;;
    no_cl_ok)
      hdr=$'HTTP/2 200\r\nLink: </assets/frappe/dist/css/bytes-no-cl.css>; as=style; rel=preload\r\nLink: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n\r\n'
      body='<html></html>'
      ;;
    dual_only)
      hdr=$'HTTP/2 200\r\nLink: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\nLink: </assets/frappe/dist/js/website.bundle.TEST.js>; as=script; rel=preload\r\n\r\n'
      body=$'<html><link href="/assets/frappe/dist/css/website.bundle.TEST.css"><script src="/assets/frappe/dist/js/website.bundle.TEST.js"></script></html>'
      ;;
    css_only)
      hdr=$'HTTP/2 200\r\nLink: </assets/frappe/dist/css/website.bundle.TEST.css>; as=style; rel=preload\r\n\r\n'
      body='<html></html>'
      ;;
    *)
      hdr=$'HTTP/2 200\r\nContent-Type: text/html\r\n\r\n'
      body='<html></html>'
      ;;
  esac
  printf '%s' "$body" >"$body_out"
  if [[ "$dump_headers" -eq 1 ]]; then
    printf '%s' "$hdr"
  fi
  exit 0
fi

printf 'HTTP/1.1 404\r\n\r\n' >&2
exit 22
EOF
  chmod +x "${tmpdir}/curl"
}

export PATH="${tmpdir}:${PATH}"

# --- Test C: all required assets succeed (3 CSS + 1 JS) ---
write_curl_mock
export MOCK_LOGIN_MODE=full3
disc="$(discover_login_frontend_assets "https://erp.test/login" "erp.test" 443 "127.0.0.1")"
assert_eq "discover count full3" "4" "$(printf '%s\n' "$disc" | grep -c '/assets/' || true)"
printf '%s\n' "$disc" | grep -q 'login.bundle.TEST.css' || {
  echo "FAIL: discover must include login.bundle" >&2
  fail=$((fail + 1))
}
printf '%s\n' "$disc" | grep -q 'erpnext-web.bundle.TEST.css' || {
  echo "FAIL: discover must include erpnext-web.bundle" >&2
  fail=$((fail + 1))
}
echo "OK: discover returns all four assets"

probe_rc=0
probe_login_frontend_assets_all "https://erp.test/login" "erp.test" 443 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
assert_eq "all-assets PASS when every asset OK" "0" "$probe_rc"

# --- Test A / G: field failure — login + erpnext-web 404 ---
export MOCK_LOGIN_MODE=field_fail
probe_rc=0
probe_out="$(probe_login_frontend_assets_all "https://erp.test/login" "erp.test" 443 "127.0.0.1" || true)" && true
probe_login_frontend_assets_all "https://erp.test/login" "erp.test" 443 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
assert_eq "field 3-CSS fail -> rc 1" "1" "$probe_rc"
fail_n="$(printf '%s\n' "$probe_out" | grep -c '^FAIL|' || true)"
assert_eq "field fail count" "2" "$fail_n"
printf '%s\n' "$probe_out" | grep -q 'login.bundle.MISSING.css' || {
  echo "FAIL: missing login.bundle not reported" >&2
  fail=$((fail + 1))
}
echo "OK: Test A/G field three-CSS failure"

# --- Test B: third required CSS fails ---
export MOCK_LOGIN_MODE=third_css_fail
probe_rc=0
probe_login_frontend_assets_all "https://erp.test/login" "erp.test" 443 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
assert_eq "third CSS 404 -> rc 1" "1" "$probe_rc"

# --- Test F: size_download 0 fails even with HTTP 200 ---
export MOCK_LOGIN_MODE=empty_css
probe_rc=0
probe_login_frontend_assets_all "https://erp.test/login" "erp.test" 443 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
assert_eq "empty body size_download 0 -> rc 1" "1" "$probe_rc"

# --- Test F positive: missing Content-Length but bytes > 0 → PASS ---
export MOCK_LOGIN_MODE=no_cl_ok
probe_rc=0
probe_login_frontend_assets_all "https://erp.test/login" "erp.test" 443 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
assert_eq "bytes>0 without relying on Content-Length -> rc 0" "0" "$probe_rc"

# --- Test E already covered by dedupe assert ---

# --- Dual-only success + css-only discovery incomplete ---
export MOCK_LOGIN_MODE=dual_only
probe_rc=0
probe_login_frontend_assets_all "https://erp.test/login" "erp.test" 443 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
assert_eq "dual css+js OK -> rc 0" "0" "$probe_rc"

export MOCK_LOGIN_MODE=css_only
probe_rc=0
probe_login_frontend_assets_all "https://erp.test/login" "erp.test" 443 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
assert_eq "css-only discovery -> rc 2" "2" "$probe_rc"

# bench_static_assets_ready must use all-assets probe
if ! grep -A20 '^bench_static_assets_ready()' "${ROOT_DIR}/lib/service.sh" | grep -q 'probe_login_frontend_assets_all'; then
  echo "FAIL: bench_static_assets_ready must call probe_login_frontend_assets_all" >&2
  fail=$((fail + 1))
else
  echo "OK: service.sh uses all-assets probe"
fi

if ! grep -q 'bench_static_assets_ready_stable' "${ROOT_DIR}/lib/service.sh"; then
  echo "FAIL: missing consecutive stability helper" >&2
  fail=$((fail + 1))
else
  echo "OK: consecutive stability helper present"
fi

# classify: file exists + 404 → STATIC_ROUTE_FAILURE
fs_tmp="$(mktemp -d /tmp/erpnext-dev-fs.XXXXXX)"
mkdir -p "${fs_tmp}/sites/assets/frappe/dist/css"
touch "${fs_tmp}/sites/assets/frappe/dist/css/login.bundle.MISSING.css"
assert_eq "classify route failure" "STATIC_ROUTE_FAILURE" \
  "$(classify_asset_failure 404 0 "${fs_tmp}/sites/assets/frappe/dist/css/login.bundle.MISSING.css")"
assert_eq "classify file missing" "ASSET_FILE_MISSING" \
  "$(classify_asset_failure 404 0 "${fs_tmp}/sites/assets/frappe/dist/css/nope.css")"
assert_eq "classify empty" "ASSET_EMPTY" "$(classify_asset_failure 200 0 "")"
rm -rf "$fs_tmp"
echo "OK: Test D classification helpers"

# No head -n 1 in discovery helpers
if grep -n 'extract_all_link_asset_paths\|extract_all_html_asset_paths\|discover_login_frontend_assets' -A15 "${ROOT_DIR}/lib/access.sh" | grep -q 'head -n 1'; then
  # legacy extract_link_* still use head -n 1; ensure discover body does not.
  if grep -A80 '^discover_login_frontend_assets()' "${ROOT_DIR}/lib/access.sh" | grep -q 'head -n 1'; then
    echo "FAIL: discover_login_frontend_assets must not use head -n 1" >&2
    fail=$((fail + 1))
  else
    echo "OK: discover path has no head -n 1"
  fi
else
  echo "OK: all-extract helpers have no head -n 1"
fi

if ((fail > 0)); then
  echo "test-static-asset-probe: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-static-asset-probe: all checks passed"
