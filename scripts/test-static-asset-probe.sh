#!/usr/bin/env bash
# Hermetic tests for login frontend asset discovery + all-assets probes (no ERPNext).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SITE_NAME="erp.test"
_ERPNEXT_DEV_ROOT="$ROOT_DIR"

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/access.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/service.sh"

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

# Readiness fingerprint path must use the complete all-assets probe.
if ! grep -A30 '^_frontend_asset_route_fingerprint()' "${ROOT_DIR}/lib/service.sh" | grep -q 'probe_login_frontend_assets_all'; then
  echo "FAIL: readiness fingerprint must call probe_login_frontend_assets_all" >&2
  fail=$((fail + 1))
else
  echo "OK: readiness fingerprint uses all-assets probe"
fi

if ! grep -q 'bench_static_assets_ready_stable' "${ROOT_DIR}/lib/service.sh"; then
  echo "FAIL: missing consecutive stability helper" >&2
  fail=$((fail + 1))
else
  echo "OK: consecutive stability helper present"
fi

if ! grep -q '_verify_frontend_assets_port80' "${ROOT_DIR}/lib/service.sh"; then
  echo "FAIL: verify-frontend-assets must diagnose port 80" >&2
  fail=$((fail + 1))
else
  echo "OK: port 80 browser-path diagnosis present"
fi

if ! grep -q 'ensure_local_http_redirects_to_https' "${ROOT_DIR}/lib/ssl.sh"; then
  echo "FAIL: missing ensure_local_http_redirects_to_https" >&2
  fail=$((fail + 1))
else
  echo "OK: HTTP→HTTPS redirect repair helper present"
fi

if ! grep -q 'frappe_nginx_assets_location_block' "${ROOT_DIR}/lib/access.sh"; then
  echo "FAIL: missing frappe_nginx_assets_location_block" >&2
  fail=$((fail + 1))
else
  echo "OK: Frappe disk /assets nginx helper present"
fi

if ! grep -q 'frappe_nginx_assets_location_block' "${ROOT_DIR}/lib/ssl.sh"; then
  echo "FAIL: ssl.sh must embed frappe_nginx_assets_location_block" >&2
  fail=$((fail + 1))
else
  echo "OK: ssl.sh embeds Frappe disk /assets block"
fi

if ! grep -q 'clear_bench_assets_json_cache' "${ROOT_DIR}/lib/access.sh"; then
  echo "FAIL: missing clear_bench_assets_json_cache" >&2
  fail=$((fail + 1))
else
  echo "OK: assets_json cache clear helper present"
fi
if ! grep -q 'evict_redis_assets_json_keys' "${ROOT_DIR}/lib/access.sh"; then
  echo "FAIL: missing evict_redis_assets_json_keys (must DEL on redis_cache :13000)" >&2
  fail=$((fail + 1))
else
  echo "OK: hard redis assets_json eviction helper present"
fi
# wait-ready must prefer Frappe local :8000 over :443
if ! grep -A35 '^bench_static_assets_probe_fingerprint()' "${ROOT_DIR}/lib/service.sh" | grep -q 'port_listens 8000'; then
  echo "FAIL: asset fingerprint readiness must probe :8000" >&2
  fail=$((fail + 1))
else
  # Prefer 8000: first port_listens in the function body should be 8000.
  first_port="$(grep -A35 '^bench_static_assets_probe_fingerprint()' "${ROOT_DIR}/lib/service.sh" | grep -m1 'port_listens' || true)"
  if [[ "$first_port" != *8000* ]]; then
    echo "FAIL: asset fingerprint readiness must prefer :8000 before :443 (got: ${first_port})" >&2
    fail=$((fail + 1))
  else
    echo "OK: asset fingerprint readiness prefers :8000"
  fi
fi

if ! grep -q 'disk_login_asset_bundles_present' "${ROOT_DIR}/lib/access.sh"; then
  echo "FAIL: missing disk_login_asset_bundles_present" >&2
  fail=$((fail + 1))
else
  echo "OK: disk login bundle helper present"
fi

if [[ ! -f "${ROOT_DIR}/docs/FRAPPE-FRONTEND-ASSETS.md" ]]; then
  echo "FAIL: docs/FRAPPE-FRONTEND-ASSETS.md missing" >&2
  fail=$((fail + 1))
else
  echo "OK: Frappe frontend assets doc present"
fi

if [[ ! -x "${ROOT_DIR}/scripts/frappe-frontend-asset-checklist.sh" ]] && [[ ! -f "${ROOT_DIR}/scripts/frappe-frontend-asset-checklist.sh" ]]; then
  echo "FAIL: frappe-frontend-asset-checklist.sh missing" >&2
  fail=$((fail + 1))
else
  echo "OK: frappe-frontend-asset-checklist.sh present"
fi

# disk helper smoke (tmpdir fixtures)
fs_assets="$(mktemp -d /tmp/erpnext-dev-disk-assets.XXXXXX)"
mkdir -p "${fs_assets}/sites/assets/frappe/dist/css" \
  "${fs_assets}/sites/assets/frappe/dist/js" \
  "${fs_assets}/sites/assets/erpnext/dist/css"
touch "${fs_assets}/sites/assets/frappe/dist/css/website.bundle.A.css" \
  "${fs_assets}/sites/assets/frappe/dist/css/login.bundle.B.css" \
  "${fs_assets}/sites/assets/erpnext/dist/css/erpnext-web.bundle.C.css" \
  "${fs_assets}/sites/assets/frappe/dist/js/frappe-web.bundle.D.js"
if disk_login_asset_bundles_present "$fs_assets"; then
  echo "OK: disk_login_asset_bundles_present accepts full set"
else
  echo "FAIL: disk_login_asset_bundles_present should pass with fixtures" >&2
  fail=$((fail + 1))
fi
rm -f "${fs_assets}/sites/assets/frappe/dist/css/login.bundle.B.css"
if disk_login_asset_bundles_present "$fs_assets"; then
  echo "FAIL: disk helper should fail without login.bundle" >&2
  fail=$((fail + 1))
else
  echo "OK: disk helper fails when login.bundle missing"
fi
rm -rf "$fs_assets"

assets_loc="$(frappe_nginx_assets_location_block /bench/sites)"
printf '%s\n' "$assets_loc" | grep -q 'alias /bench/sites/assets' || {
  echo "FAIL: assets location alias path wrong" >&2
  fail=$((fail + 1))
}
printf '%s\n' "$assets_loc" | grep -q 'try_files \$uri =404' || printf '%s\n' "$assets_loc" | grep -q 'try_files $uri =404' || {
  echo "FAIL: assets location missing try_files" >&2
  fail=$((fail + 1))
}
echo "OK: frappe_nginx_assets_location_block shape"

# nginx writer: redirect mode must 301; proxy mode must use location /
if ! grep -A30 'SSL_REDIRECT_HTTP" == "true"' "${ROOT_DIR}/lib/ssl.sh" | grep -q 'return 301 https://'; then
  echo "FAIL: local SSL nginx must 301 http→https when redirect enabled" >&2
  fail=$((fail + 1))
else
  echo "OK: local SSL nginx redirect mode uses return 301"
fi
if grep -A5 'SSL_REDIRECT_HTTP" != "true"\|SSL_REDIRECT_HTTP" == "false"' "${ROOT_DIR}/lib/ssl.sh" | grep -q 'proxy_pass.*\\\\n'; then
  echo "FAIL: proxy mode must not embed literal \\\\n proxy_pass at server scope" >&2
  fail=$((fail + 1))
else
  echo "OK: no broken literal-\\\\n proxy_pass pattern"
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

# Stable-readiness fingerprint must represent the exact all-asset probe set.
port_listens() { [[ "$1" == "8000" ]]; }
export MOCK_LOGIN_MODE=full3
fingerprint_full="$(bench_static_assets_probe_fingerprint 2>/dev/null || true)"
if [[ "$fingerprint_full" =~ ^[0-9a-f]{64}$ ]]; then
  echo "OK: stable asset fingerprint generated"
else
  echo "FAIL: stable asset fingerprint missing/invalid: ${fingerprint_full}" >&2
  fail=$((fail + 1))
fi
export MOCK_LOGIN_MODE=dual_only
fingerprint_dual="$(bench_static_assets_probe_fingerprint 2>/dev/null || true)"
if [[ -n "$fingerprint_full" && -n "$fingerprint_dual" && "$fingerprint_full" != "$fingerprint_dual" ]]; then
  echo "OK: asset fingerprint changes when advertised manifest changes"
else
  echo "FAIL: asset fingerprint did not detect manifest change" >&2
  fail=$((fail + 1))
fi

# Dedicated redis_cache FLUSHDB must target only the configured cache endpoint
# and refuse a cache/queue endpoint collision.
redis_bench="$(mktemp -d /tmp/erpnext-dev-redis-cache.XXXXXX)"
mkdir -p "${redis_bench}/sites"
cat >"${redis_bench}/sites/common_site_config.json" <<'EOF_REDIS_CFG'
{
  "redis_cache": "redis://127.0.0.1:13000",
  "redis_queue": "redis://127.0.0.1:11000"
}
EOF_REDIS_CFG
redis_log="${tmpdir}/redis-cli.log"
cat >"${tmpdir}/redis-cli" <<'EOF_REDIS_MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${REDIS_CLI_LOG}"
exit 0
EOF_REDIS_MOCK
chmod +x "${tmpdir}/redis-cli"
export REDIS_CLI_LOG="$redis_log"
: >"$redis_log"
warn() { :; }
log() { :; }
if flush_bench_redis_cache "$redis_bench" && grep -q -- '-p 13000 FLUSHDB' "$redis_log"; then
  echo "OK: redis_cache FLUSHDB targets only cache endpoint"
else
  echo "FAIL: redis_cache FLUSHDB did not target port 13000" >&2
  fail=$((fail + 1))
fi
cat >"${redis_bench}/sites/common_site_config.json" <<'EOF_REDIS_SHARED'
{
  "redis_cache": "redis://127.0.0.1:13000",
  "redis_queue": "redis://127.0.0.1:13000"
}
EOF_REDIS_SHARED
before_calls="$(wc -l <"$redis_log" | tr -d ' ')"
if flush_bench_redis_cache "$redis_bench"; then
  echo "FAIL: redis_cache FLUSHDB must refuse shared queue endpoint" >&2
  fail=$((fail + 1))
else
  after_calls="$(wc -l <"$redis_log" | tr -d ' ')"
  assert_eq "shared cache/queue endpoint sends no FLUSHDB" "$before_calls" "$after_calls"
fi
rm -rf "$redis_bench"

# Regression guards for the v1.19.13/v1.19.14 settle implementation.
if grep -q '^flush_bench_redis_cache()' "${ROOT_DIR}/lib/access.sh"; then
  echo "OK: dedicated redis_cache FLUSHDB helper present"
else
  echo "FAIL: missing flush_bench_redis_cache regression fix" >&2
  fail=$((fail + 1))
fi
if grep -q '^settle_stack_after_install()' "${ROOT_DIR}/lib/service.sh" \
  && grep -q '^settle_stack_after_local_https()' "${ROOT_DIR}/lib/service.sh"; then
  echo "OK: post-install and post-HTTPS settle helpers present"
else
  echo "FAIL: missing mandatory local settle helpers" >&2
  fail=$((fail + 1))
fi
if grep -A120 '^run_install()' "${ROOT_DIR}/lib/install.sh" | grep -q 'settle_stack_after_install'; then
  echo "OK: run_install enforces local post-install settle"
else
  echo "FAIL: run_install does not enforce post-install settle" >&2
  fail=$((fail + 1))
fi
if grep -A180 '^run_trusted_mkcert_setup()' "${ROOT_DIR}/lib/ssl.sh" | grep -q 'settle_stack_after_local_https'; then
  echo "OK: trusted mkcert path enforces post-HTTPS settle"
else
  echo "FAIL: trusted mkcert path does not enforce post-HTTPS settle" >&2
  fail=$((fail + 1))
fi
if grep -A70 '^repair_frontend_assets()' "${ROOT_DIR}/lib/service.sh" | grep -q 'flush_bench_redis_cache'; then
  echo "OK: frontend repair flushes dedicated redis_cache before restart"
else
  echo "FAIL: frontend repair lost redis_cache FLUSHDB regression fix" >&2
  fail=$((fail + 1))
fi

if ((fail > 0)); then
  echo "test-static-asset-probe: ${fail} failure(s)" >&2
  exit 1
fi
echo "test-static-asset-probe: all checks passed"
