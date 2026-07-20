# shellcheck shell=bash
# Browser access, host DNS, networking guides, and credentials UI for erpnext-dev.sh.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_ACCESS_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_ACCESS_LOADED=1

show_ready_summary() {
  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "ERPNext Ready"
  echo "============================================================"
  echo "ERPNext is running: ports, HTTP ping, and login static assets are OK."
  echo
  if is_public_vm_workflow; then
    if ssl_is_configured 2>/dev/null && port_listens 443; then
      echo "Production HTTPS URLs:"
      echo "  Desk:         https://${SITE_NAME}/app"
      echo "  Login:        https://${SITE_NAME}/login"
      echo "  Website/root: https://${SITE_NAME}"
    else
      echo "Production HTTPS is not configured yet. Continue the guided production setup to enable:"
      echo "  https://${SITE_NAME}"
    fi
    echo
    echo "Backend validation URLs, for troubleshooting only:"
    echo "  Direct IP:    http://${vm_ip}:8000"
    echo "  Domain :8000: http://${SITE_NAME}:8000"
    echo "Production note: public access to ports 8000 and 9000 should be blocked by the cloud firewall and UFW after hardening."
  else
    # Frappe local contract: :8000 with Host=SITE is the primary path.
    echo "Open from the HOST after /etc/hosts is set (Frappe local contract):"
    echo "  Desk:         http://${SITE_NAME}:8000/app"
    echo "  Login:        http://${SITE_NAME}:8000/login"
    echo "  Website/root: http://${SITE_NAME}:8000"
    if ssl_is_configured 2>/dev/null && port_listens 443; then
      echo
      echo "Optional local HTTPS (after :8000 looks styled):"
      echo "  Desk:         https://${SITE_NAME}/app"
      echo "  Login:        https://${SITE_NAME}/login"
      echo "  Website/root: https://${SITE_NAME}"
    fi
    echo
    echo "Avoid bare http://${SITE_NAME} (port 80) and raw IP URLs until verified."
    echo "If unstyled: $(toolkit_cmd frappe-asset-checklist) — docs/FRAPPE-FRONTEND-ASSETS.md"
    echo
    echo "HOST /etc/hosts must map ${SITE_NAME} to ${vm_ip}."
    echo "Troubleshooting only (often unstyled — do not use as primary):"
    echo "  http://${vm_ip}:8000"
  fi
  echo "For full access instructions, run: $(toolkit_cmd access)"
  echo "============================================================"
}
valid_ipv4_address() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=. a b c d
  read -r a b c d <<< "$ip"
  for octet in "$a" "$b" "$c" "$d"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( octet >= 0 && octet <= 255 )) || return 1
  done
  return 0
}

is_usable_vm_ip() {
  local ip="$1"
  valid_ipv4_address "$ip" || return 1
  case "$ip" in
    127.*|169.254.*|0.*) return 1 ;;
    *) return 0 ;;
  esac
}

get_vm_ip() {
  # Do not hardcode the local VM network. Users may be on KVM default NAT
  # (192.168.122.x), VirtualBox/UTM-style NAT (10.x), a bridged LAN address,
  # or a cloud/public interface. Prefer the source IP chosen by the kernel for
  # outbound routing, then fall back to the primary interface address and then
  # the first usable address from hostname -I.
  local candidate="" token="" iface=""
  local IFS=$' \t\n'

  if [[ -n "${VM_IP:-}" ]] && is_usable_vm_ip "$VM_IP"; then
    printf '%s\n' "$VM_IP"
    return 0
  fi

  candidate="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  if is_usable_vm_ip "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}' || true)"
  if [[ -n "$iface" ]]; then
    candidate="$(ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk '{sub(/\/.*$/, "", $4); print $4; exit}' || true)"
    if is_usable_vm_ip "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for token in $(hostname -I 2>/dev/null || true); do
    if is_usable_vm_ip "$token"; then
      printf '%s\n' "$token"
      return 0
    fi
  done

  # Keep callers from printing an empty value; verification will still fail clearly.
  printf '%s\n' "unknown"
}
curl_head_status() {
  local url="${1:-}"
  local host_name="${2:-}"
  local port="${3:-}"
  local resolve_ip="${4:-}"
  local curl_args=()

  [[ -n "$url" ]] || return 1

  curl_args=(-k -sS -I --max-time 10)

  if [[ -n "$host_name" && -n "$port" && -n "$resolve_ip" ]]; then
    curl_args+=(--resolve "${host_name}:${port}:${resolve_ip}")
  fi

  # Strip CR so CRLF HEAD responses do not leave a trailing \r on the status
  # token (which would break http_status_ok's numeric match).
  curl "${curl_args[@]}" "$url" 2>/dev/null | tr -d '\r' | awk 'NR==1 {print; exit}' || true
}

# Extract the numeric status code from an HTTP status line such as "HTTP/2 200"
# or "HTTP/1.1 502 Bad Gateway".
http_status_code() {
  printf '%s' "${1:-}" | awk '{print $2}'
}

# True when a status line represents a successful or redirect response (2xx/3xx).
# Used so health checks do not treat an error page (e.g. nginx 502 when the bench
# backend is down) as a passing result just because *some* HTTP reply came back.
http_status_ok() {
  local code
  code="$(http_status_code "${1:-}")"
  [[ "$code" =~ ^[23][0-9][0-9]$ ]]
}

# Full response headers for asset/login probes (GET, not HEAD). Same resolve
# args as curl_head_status so callers can pin Host:port to 127.0.0.1 inside the VM.
#
# HEAD is unreliable here: Frappe/Werkzeug often omit Link: preload headers on
# HEAD, or advertise Content-Length: 0 for static files that GET serves fine —
# that false-failed wait-ready after an earlier successful probe.
curl_response_headers() {
  local url="${1:-}"
  local host_name="${2:-}"
  local port="${3:-}"
  local resolve_ip="${4:-}"
  local curl_args=()

  [[ -n "$url" ]] || return 1

  # -D - dumps headers to stdout; -o /dev/null discards the body. -L follows
  # /login → /login/ style redirects so Link headers on the final HTML are seen.
  curl_args=(-k -sS -L --max-redirs 5 --max-time 10 -D - -o /dev/null)

  if [[ -n "$host_name" && -n "$port" && -n "$resolve_ip" ]]; then
    curl_args+=(--resolve "${host_name}:${port}:${resolve_ip}")
  fi

  curl "${curl_args[@]}" "$url" 2>/dev/null | tr -d '\r' || true
}

# Fetch login document: headers to stdout (for Link:), body to $2 path.
# Return 0 when curl succeeds; body may still be empty.
curl_login_document() {
  local url="${1:-}"
  local body_file="${2:-}"
  local host_name="${3:-}"
  local port="${4:-}"
  local resolve_ip="${5:-}"
  local curl_args=()

  [[ -n "$url" && -n "$body_file" ]] || return 1

  curl_args=(-k -sS -L --max-redirs 5 --max-time 15 -D - -o "$body_file")
  if [[ -n "$host_name" && -n "$port" && -n "$resolve_ip" ]]; then
    curl_args+=(--resolve "${host_name}:${port}:${resolve_ip}")
  fi
  curl "${curl_args[@]}" "$url" 2>/dev/null | tr -d '\r' || true
}

# Normalize a candidate asset URL/path to a local /assets/...css|js path, or empty.
normalize_local_asset_path() {
  local raw="${1:-}"
  raw="${raw%%[?#]*}"
  raw="${raw//$'\r'/}"
  # Absolute same-host forms → path only.
  if [[ "$raw" =~ ^https?://[^/]+(/assets/.+\.(css|js))$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$raw" =~ ^(/assets/.+\.(css|js))$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  # Protocol-relative or other external → ignore.
  printf '\n'
}

# Extract every local /assets/*.css|js from Link: preload header lines (no head -n 1).
extract_all_link_asset_paths() {
  printf '%s\n' "${1:-}" \
    | awk 'tolower($1)=="link:"{print}' \
    | grep -oE '/assets/[^>,[:space:]]+\.(css|js)' \
    | sed 's/[?#].*$//' \
    | awk 'NF && !seen[$0]++' || true
}

# Extract every local /assets/*.css|js from login HTML (link href + script src).
extract_all_html_asset_paths() {
  local html="${1:-}"
  {
    printf '%s\n' "$html" | grep -oE '(href|src)="(/assets/[^"]+\.(css|js))"' || true
    printf '%s\n' "$html" | grep -oE "(href|src)='(/assets/[^']+\.(css|js))'" || true
  } | sed -E "s/^(href|src)=[\"']//; s/[\"']$//; s/[?#].*$//" \
    | awk 'NF && !seen[$0]++' || true
}

# Compatibility: first path only (legacy helpers / older tests). Prefer
# discover_login_frontend_assets / extract_all_* for browser-ready gates.
extract_link_asset_path() {
  extract_all_link_asset_paths "${1:-}" | head -n 1 || true
}

extract_link_asset_path_css() {
  extract_all_link_asset_paths "${1:-}" | grep '\.css$' | head -n 1 || true
}

extract_link_asset_path_js() {
  extract_all_link_asset_paths "${1:-}" | grep '\.js$' | head -n 1 || true
}

# True when response headers do not declare an empty body. Legacy helper kept for
# tests; browser-ready probes use curl size_download instead.
asset_headers_nonempty() {
  local headers="${1:-}"
  local cl
  cl="$(printf '%s\n' "$headers" | tr -d '\r' | awk 'tolower($1)=="content-length:"{v=$2} END{print v}')"
  [[ -z "$cl" ]] && return 0
  [[ "$cl" =~ ^[0-9]+$ ]] || return 0
  ((cl > 0))
}

# Last HTTP status line in a (possibly multi-response) header dump.
asset_headers_status_line() {
  printf '%s\n' "${1:-}" | awk '/^HTTP\//{line=$0} END{print line}'
}

# Discover all local CSS/JS required by /login (HTML + Link headers, deduped).
# Prints one /assets/... path per line. Return 0 if at least one CSS and one JS
# were found; 1 if the document was fetched but incomplete; 2 on fetch failure.
discover_login_frontend_assets() {
  local url="${1:-}"
  local host_name="${2:-}"
  local port="${3:-}"
  local resolve_ip="${4:-}"
  local body_file headers html path normalized
  local -a paths=()
  local has_css=0 has_js=0

  [[ -n "$url" && -n "$host_name" && -n "$port" && -n "$resolve_ip" ]] || return 2

  body_file="$(mktemp /tmp/erpnext-dev-login-body.XXXXXX)"
  headers="$(curl_login_document "$url" "$body_file" "$host_name" "$port" "$resolve_ip" || true)"
  if [[ ! -s "$body_file" ]] && [[ -z "$headers" ]]; then
    rm -f "$body_file"
    return 2
  fi
  html="$(cat "$body_file" 2>/dev/null || true)"
  rm -f "$body_file"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    normalized="$(normalize_local_asset_path "$path")"
    [[ -n "$normalized" ]] || continue
    paths+=("$normalized")
  done < <(
    {
      extract_all_link_asset_paths "$headers"
      extract_all_html_asset_paths "$html"
    } | awk 'NF && !seen[$0]++'
  )

  if ((${#paths[@]} == 0)); then
    return 2
  fi

  for path in "${paths[@]}"; do
    printf '%s\n' "$path"
    [[ "$path" == *.css ]] && has_css=1
    [[ "$path" == *.js ]] && has_js=1
  done

  if ((has_css == 1 && has_js == 1)); then
    return 0
  fi
  return 1
}

# Map /assets/... URL path to a likely on-disk path under the active bench.
asset_path_to_filesystem() {
  local asset_path="${1:-}"
  local bench_dir="${2:-}"
  local rel

  [[ -n "$asset_path" && -n "$bench_dir" ]] || return 1
  # /assets/frappe/dist/... → sites/assets/frappe/dist/...
  if [[ "$asset_path" == /assets/* ]]; then
    rel="sites${asset_path}"
    printf '%s/%s\n' "$bench_dir" "$rel"
    return 0
  fi
  return 1
}

# Classify a failed asset probe for operator diagnostics.
classify_asset_failure() {
  local http_code="${1:-}"
  local size_download="${2:-0}"
  local fs_path="${3:-}"

  if [[ "$http_code" == "404" ]]; then
    if [[ -n "$fs_path" && -f "$fs_path" ]]; then
      printf 'STATIC_ROUTE_FAILURE\n'
    elif [[ -n "$fs_path" && ! -e "$fs_path" ]]; then
      printf 'ASSET_FILE_MISSING\n'
    else
      printf 'ASSET_HTTP_404\n'
    fi
    return 0
  fi
  if [[ "$size_download" =~ ^[0-9]+$ ]] && ((size_download == 0)); then
    printf 'ASSET_EMPTY\n'
    return 0
  fi
  printf 'ASSET_HTTP_%s\n' "${http_code:-UNKNOWN}"
}

# Absolute path to bench sites/ (Frappe nginx root for /assets).
bench_sites_dir() {
  local bench_dir="${1:-}"
  if [[ -z "$bench_dir" ]] && declare -F active_bench_dir >/dev/null 2>&1; then
    bench_dir="$(active_bench_dir 2>/dev/null || true)"
  fi
  bench_dir="${bench_dir:-${BENCH_DIR:-/home/frappe/frappe/frappe-bench}}"
  printf '%s/sites\n' "$bench_dir"
}

# True when the login-critical hashed bundles exist on disk (Frappe contract).
# Checks website + login (frappe) and erpnext-web (erpnext).
disk_login_asset_bundles_present() {
  local bench_dir="${1:-}"
  local assets
  assets="$(bench_sites_dir "$bench_dir")/assets"
  [[ -d "$assets" ]] || return 1
  ls "${assets}/frappe/dist/css/website.bundle."*.css >/dev/null 2>&1 || return 1
  ls "${assets}/frappe/dist/css/login.bundle."*.css >/dev/null 2>&1 || return 1
  ls "${assets}/erpnext/dist/css/erpnext-web.bundle."*.css >/dev/null 2>&1 || return 1
  ls "${assets}/frappe/dist/js/frappe-web.bundle."*.js >/dev/null 2>&1 || return 1
  return 0
}

# Warn when RAM is below the install minimum (yarn/esbuild OOM → incomplete assets).
warn_if_build_memory_low() {
  local mem_mb min_mb="${MIN_INSTALL_RAM_MB:-4096}"
  mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$mem_mb" =~ ^[0-9]+$ ]] && ((mem_mb > 0 && mem_mb < min_mb)); then
    warn "Host RAM is ${mem_mb} MB (minimum ${min_mb} MB). bench build may OOM and leave login CSS/JS missing."
    echo "  See docs/FRAPPE-FRONTEND-ASSETS.md and frappe#33468."
    return 1
  fi
  return 0
}

# Parse host:port from redis:// URL in common_site_config (bench cache is often :13000).
bench_redis_cache_host_port() {
  local bench_dir="${1:-}" cfg url hostport
  [[ -n "$bench_dir" ]] || bench_dir="$(active_bench_dir 2>/dev/null || true)"
  cfg="${bench_dir}/sites/common_site_config.json"
  [[ -f "$cfg" ]] || return 1
  url="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('redis_cache','') or '')" "$cfg" 2>/dev/null || true)"
  [[ "$url" == redis://* || "$url" == rediss://* ]] || return 1
  hostport="${url#*://}"
  hostport="${hostport%%/*}"
  # strip userinfo if present
  hostport="${hostport##*@}"
  [[ -n "$hostport" ]] || return 1
  printf '%s\n' "$hostport"
}

# Hard-DEL assets_json keys on the bench redis_cache instance (not host :6379).
# plain `redis-cli KEYS` misses frappe cache on :13000 — field failure on e.test.
evict_redis_assets_json_keys() {
  local bench_dir="${1:-}" hostport host port
  local -a keys=()

  hostport="$(bench_redis_cache_host_port "$bench_dir")" || return 1
  if [[ "$hostport" == *:* ]]; then
    host="${hostport%:*}"
    port="${hostport##*:}"
  else
    host="$hostport"
    port=6379
  fi
  command -v redis-cli >/dev/null 2>&1 || return 1

  mapfile -t keys < <(redis-cli -h "$host" -p "$port" --scan --pattern '*assets_json*' 2>/dev/null || true)
  if ((${#keys[@]} == 0)); then
    # Frappe often uses the bare key name as well.
    keys=("assets_json")
  fi
  redis-cli -h "$host" -p "$port" DEL "${keys[@]}" >/dev/null 2>&1 || true
  return 0
}

# True when sites/assets/assets.json login/website hashes exist as files on disk.
assets_json_login_hashes_on_disk() {
  local bench_dir="${1:-}" assets json
  assets="$(bench_sites_dir "$bench_dir")/assets"
  json="${assets}/assets.json"
  [[ -f "$json" ]] || return 1
  python3 - "$assets" "$json" <<'PY'
import json, os, sys
assets, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
needles = ("login.bundle", "website.bundle", "erpnext-web.bundle", "frappe-web.bundle")
checked = 0
for key, val in data.items():
    if not any(n in str(key) or n in str(val) for n in needles):
        continue
    rel = str(val).lstrip("/")
    if rel.startswith("assets/"):
        rel = rel[len("assets/"):]
    fp = os.path.join(assets, rel)
    if not os.path.isfile(fp):
        # val may already be app/dist/... under assets/
        fp2 = os.path.join(assets, str(val).lstrip("/"))
        if not os.path.isfile(fp2):
            sys.exit(1)
    checked += 1
sys.exit(0 if checked else 1)
PY
}

# Evict Redis assets_json + site/website caches after bench build (frappe#29901).
clear_bench_assets_json_cache() {
  local bench_dir site="${SITE_NAME:-}"
  bench_dir="$(active_bench_dir 2>/dev/null || true)"
  [[ -n "$bench_dir" && -n "$site" ]] || return 1

  log "Clearing site cache and Redis assets_json for ${site}"
  run_as_frappe "cd '${bench_dir}' && bench --site '${site}' clear-cache" || true
  run_as_frappe "cd '${bench_dir}' && bench --site '${site}' clear-website-cache" || true
  # Explicit shared-key eviction; clear-cache should cover this, but stale
  # assets_json is a known unstyled-login cause after rebuilds.
  run_as_frappe "cd '${bench_dir}' && bench --site '${site}' execute frappe.cache_manager.clear_global_cache" || true
  # Bench redis_cache is usually 127.0.0.1:13000 — never assume host redis-cli :6379.
  if evict_redis_assets_json_keys "$bench_dir"; then
    log "Deleted assets_json keys on bench redis_cache ($(bench_redis_cache_host_port "$bench_dir" 2>/dev/null || echo unknown))"
  else
    warn "Could not hard-DEL assets_json on redis_cache; relying on bench clear-cache only"
  fi
  # If assets.json points at hashes that are not on disk, drop it so the next
  # bench build regenerates a consistent map (HTML 404 ghost-hash failure mode).
  if [[ -f "$(bench_sites_dir "$bench_dir")/assets/assets.json" ]] && \
     ! assets_json_login_hashes_on_disk "$bench_dir"; then
    warn "sites/assets/assets.json hashes do not match files on disk — removing stale map"
    run_as_frappe "rm -f '$(bench_sites_dir "$bench_dir")/assets/assets.json'" || \
      $SUDO rm -f "$(bench_sites_dir "$bench_dir")/assets/assets.json" 2>/dev/null || true
  fi
  return 0
}

# Nginx location block matching Frappe bench setup nginx (disk /assets).
# Prints lines suitable for embedding in an unquoted heredoc (\$ already expanded).
frappe_nginx_assets_location_block() {
  local sites_dir="${1:-}"
  [[ -n "$sites_dir" ]] || sites_dir="$(bench_sites_dir)"
  printf '%s\n' \
    "    # Frappe contract (bench setup nginx): serve hashed bundles from disk." \
    "    location /assets {" \
    "        alias ${sites_dir}/assets;" \
    "        try_files \$uri =404;" \
    "        add_header Cache-Control \"max-age=31536000\";" \
    "    }"
}

# CLI: Frappe-first disk/:8000 checklist (see docs/FRAPPE-FRONTEND-ASSETS.md).
run_frappe_asset_checklist() {
  local script_path root
  require_site_environment >/dev/null || true
  root="${_ERPNEXT_DEV_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  script_path="${root}/scripts/frappe-frontend-asset-checklist.sh"
  if [[ ! -f "$script_path" ]]; then
    err "frappe-frontend-asset-checklist.sh not found at ${script_path}"
    return 1
  fi
  SITE_NAME="${SITE_NAME}" BENCH_DIR="$(active_bench_dir 2>/dev/null || echo "${BENCH_DIR:-}")" \
    bash "$script_path"
}

# Probe one asset URL with a real GET. Prints:
#   path|http_code|size_download|content_type|class_or_OK
# Return: 0 = OK (2xx/3xx and size_download > 0), 1 = fail.
probe_one_static_asset() {
  local asset_path="${1:-}"
  local host_name="${2:-}"
  local port="${3:-}"
  local resolve_ip="${4:-}"
  local scheme="${5:-https}"
  local bench_dir="${6:-}"
  local asset_url metrics http_code size_download content_type
  local fs_path="" class="OK" curl_args=()

  [[ -n "$asset_path" && -n "$host_name" && -n "$port" && -n "$resolve_ip" ]] || return 1

  if [[ "$scheme" == "https" ]]; then
    asset_url="https://${host_name}${asset_path}"
  else
    asset_url="http://${host_name}:${port}${asset_path}"
  fi

  curl_args=(-k -sS -L --max-redirs 5 --max-time 15 -o /dev/null \
    -w '%{http_code}|%{size_download}|%{content_type}')
  if [[ -n "$host_name" && -n "$port" && -n "$resolve_ip" ]]; then
    curl_args+=(--resolve "${host_name}:${port}:${resolve_ip}")
  fi

  metrics="$(curl "${curl_args[@]}" "$asset_url" 2>/dev/null || true)"
  IFS='|' read -r http_code size_download content_type <<<"${metrics:-||}"
  http_code="${http_code:-000}"
  size_download="${size_download:-0}"

  if [[ -z "$bench_dir" ]] && declare -F active_bench_dir >/dev/null 2>&1; then
    bench_dir="$(active_bench_dir 2>/dev/null || true)"
  fi
  if [[ -n "$bench_dir" ]]; then
    fs_path="$(asset_path_to_filesystem "$asset_path" "$bench_dir" 2>/dev/null || true)"
  fi

  if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]] && [[ "$size_download" =~ ^[0-9]+$ ]] && ((size_download > 0)); then
    printf '%s|%s|%s|%s|OK\n' "$asset_path" "$http_code" "$size_download" "${content_type:-}"
    return 0
  fi

  class="$(classify_asset_failure "$http_code" "$size_download" "$fs_path")"
  printf '%s|%s|%s|%s|%s\n' "$asset_path" "$http_code" "$size_download" "${content_type:-}" "$class"
  return 1
}

# Compatibility wrapper: first discovered asset only (legacy single-asset probe).
# Prefer probe_login_frontend_assets_all for browser-ready gates.
# Prints "asset_path|http_code" ; RC 0/1/2 as before.
probe_login_static_asset() {
  local url="${1:-}"
  local host_name="${2:-}"
  local port="${3:-}"
  local resolve_ip="${4:-}"
  local scheme="http" asset_path out

  [[ -n "$url" && -n "$host_name" && -n "$port" && -n "$resolve_ip" ]] || return 2

  asset_path="$(discover_login_frontend_assets "$url" "$host_name" "$port" "$resolve_ip" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$asset_path" ]]; then
    return 2
  fi

  [[ "$url" == https://* ]] && scheme="https"
  out="$(probe_one_static_asset "$asset_path" "$host_name" "$port" "$resolve_ip" "$scheme")" || true
  # Legacy print shape: path|HTTP status token
  printf '%s|HTTP %s\n' "$asset_path" "$(printf '%s' "$out" | cut -d'|' -f2)"
  printf '%s' "$out" | grep -q '|OK$'
}

# Browser-ready gate: every local CSS/JS required by /login must GET successfully
# with size_download > 0. At least one CSS and one JS must be discovered.
# Prints one result line per asset: STATUS|path|http_code|bytes|class
# Return: 0 = all OK, 1 = one or more failed, 2 = discovery incomplete/failed.
probe_login_frontend_assets_all() {
  local url="${1:-}"
  local host_name="${2:-}"
  local port="${3:-}"
  local resolve_ip="${4:-}"
  local scheme="http" path out rc=0 disc_rc=0
  local -a assets=()
  local fail_count=0 ok_count=0 has_css=0 has_js=0

  [[ -n "$url" && -n "$host_name" && -n "$port" && -n "$resolve_ip" ]] || return 2

  local disc_tmp
  disc_tmp="$(mktemp /tmp/erpnext-dev-discover.XXXXXX)"
  set +e
  discover_login_frontend_assets "$url" "$host_name" "$port" "$resolve_ip" >"$disc_tmp"
  disc_rc=$?
  set -e
  mapfile -t assets <"$disc_tmp"
  rm -f "$disc_tmp"

  if ((${#assets[@]} == 0)) || ((disc_rc == 2)); then
    return 2
  fi

  [[ "$url" == https://* ]] && scheme="https"

  for path in "${assets[@]}"; do
    [[ -n "$path" ]] || continue
    [[ "$path" == *.css ]] && has_css=1
    [[ "$path" == *.js ]] && has_js=1
    out=""
    set +e
    out="$(probe_one_static_asset "$path" "$host_name" "$port" "$resolve_ip" "$scheme")"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      printf 'OK|%s\n' "$out"
      ok_count=$((ok_count + 1))
    else
      printf 'FAIL|%s\n' "${out:-${path}|000|0||UNKNOWN}"
      fail_count=$((fail_count + 1))
    fi
  done

  if ((has_css == 0 || has_js == 0)) || ((disc_rc == 1 && fail_count == 0 && ok_count == 0)); then
    return 2
  fi
  # Incomplete discovery (css xor js) still fails the browser gate.
  if ((has_css == 0 || has_js == 0)); then
    return 2
  fi
  if ((fail_count > 0)); then
    return 1
  fi
  return 0
}

# Alias: historical name now means the complete all-assets gate (not first CSS+JS).
# Legacy dual-line print is no longer used; callers should use _all or check RC only.
probe_login_frontend_assets() {
  probe_login_frontend_assets_all "$@"
}

escape_hosts_regex() {
  printf '%s' "$1" | sed 's/[.[\*^$()+?{}|]/\\&/g'
}

# Human-readable name for a host OS token (defaults to the resolved host OS).
# shellcheck disable=SC2120  # arg is optional; most callers rely on the default
host_os_label() {
  local os="${1:-$(effective_host_os)}"
  case "$os" in
    linux) printf 'Linux\n' ;;
    macos) printf 'macOS\n' ;;
    windows) printf 'Windows (PowerShell as Administrator)\n' ;;
    windows-wsl) printf 'Windows + WSL2\n' ;;
    *) printf 'Linux\n' ;;
  esac
}

# The IP the HOST should map the local domain to. For a WSL2 guest, Windows
# reaches the services over localhost, so map to 127.0.0.1 rather than the
# WSL2 interface address (which changes on every boot).
host_mapping_ip() {
  local vm_ip="${1:-}"
  if [[ "$(effective_host_os)" == "windows-wsl" ]]; then
    printf '127.0.0.1\n'
    return 0
  fi
  printf '%s\n' "$vm_ip"
}

# Print the exact commands to run on the HOST to map the local domain to the
# VM IP, tailored to the operator's host OS. Unix hosts (Linux/macOS) edit
# /etc/hosts; Windows edits the drivers\etc\hosts file from an elevated
# PowerShell. macOS uses BSD sed (`sed -i ''`), which differs from GNU sed.
# One copy-paste HOST command to map the local domain (backs up, removes stale
# entries, guarantees a trailing newline, then appends VM_IP LOCAL_DOMAIN).
print_host_dns_one_liner_for_site() {
  local site="${1:-$SITE_NAME}" vm_ip="${2:-}"
  local escaped_site map_ip host_os
  vm_ip="${vm_ip:-$(get_vm_ip)}"
  escaped_site="$(escape_hosts_regex "$site")"
  host_os="$(effective_host_os)"
  map_ip="$(host_mapping_ip "$vm_ip")"

  case "$host_os" in
    windows|windows-wsl)
      echo "\$VM_IP=\"${map_ip}\"; \$LOCAL_DOMAIN=\"${site}\"; \$hosts=\"\$env:SystemRoot\\System32\\drivers\\etc\\hosts\"; Copy-Item \$hosts \"\$hosts.bak.\$(Get-Date -Format yyyyMMdd-HHmmss)\"; \$pattern='\\s+'+[regex]::Escape(\$LOCAL_DOMAIN)+'(\\s|\$)'; (Get-Content \$hosts) -notmatch \$pattern | Set-Content \$hosts; Add-Content \$hosts \"\$VM_IP \$LOCAL_DOMAIN\""
      ;;
    macos)
      # BSD/macOS sed requires an explicit (empty) backup suffix after -i.
      echo "VM_IP=\"${map_ip}\" LOCAL_DOMAIN=\"${site}\" && sudo cp /etc/hosts \"/etc/hosts.bak.\$(date +%Y%m%d-%H%M%S)\" && sudo sed -i '' \"/[[:space:]]${escaped_site}\\([[:space:]]\\|\$\\)/d\" /etc/hosts && { [ -n \"\$(tail -c1 /etc/hosts)\" ] && echo | sudo tee -a /etc/hosts >/dev/null || true; } && echo \"\${VM_IP} \${LOCAL_DOMAIN}\" | sudo tee -a /etc/hosts"
      ;;
    *)
      echo "VM_IP=\"${map_ip}\" LOCAL_DOMAIN=\"${site}\" && sudo cp /etc/hosts \"/etc/hosts.bak.\$(date +%Y%m%d-%H%M%S)\" && sudo sed -i \"/[[:space:]]${escaped_site}\\([[:space:]]\\|\$\\)/d\" /etc/hosts && { [ -n \"\$(tail -c1 /etc/hosts)\" ] && echo | sudo tee -a /etc/hosts >/dev/null || true; } && echo \"\${VM_IP} \${LOCAL_DOMAIN}\" | sudo tee -a /etc/hosts"
      ;;
  esac
}

print_host_dns_commands_for_site() {
  local site="${1:-$SITE_NAME}" vm_ip="${2:-}"
  local host_os host_label
  host_os="$(effective_host_os)"
  host_label="$(host_os_label "$host_os")"

  case "$host_os" in
    windows|windows-wsl)
      echo "  Copy and run this entire command in PowerShell (Administrator):"
      ;;
    *)
      echo "  Copy and run this entire command on the ${host_label} HOST:"
      ;;
  esac
  echo "  $(print_host_dns_one_liner_for_site "$site" "$vm_ip")"
}

# Print the HOST-side commands to verify the mapping and reach the site,
# tailored to the host OS (getent/dscacheutil/Resolve-DnsName differ).
print_host_dns_tests_for_site() {
  local site="${1:-$SITE_NAME}" vm_ip="${2:-}"
  local host_os map_ip
  vm_ip="${vm_ip:-$(get_vm_ip)}"
  host_os="$(effective_host_os)"
  map_ip="$(host_mapping_ip "$vm_ip")"

  case "$host_os" in
    windows|windows-wsl)
      echo "  Resolve-DnsName ${site}    # or: nslookup ${site}"
      echo "  curl.exe -I http://${site}:8000    # or: Invoke-WebRequest http://${site}:8000"
      if [[ "$host_os" == "windows-wsl" ]]; then
        echo "  curl.exe -I http://127.0.0.1:8000   # troubleshooting only"
      elif [[ "$vm_ip" != "unknown" && -n "$vm_ip" ]]; then
        echo "  curl.exe -I http://${vm_ip}:8000   # troubleshooting only"
      fi
      if port_listens 443; then
        echo "  curl.exe -kI https://${site}"
      fi
      ;;
    macos)
      echo "  dscacheutil -q host -a name ${site}"
      echo "  curl -I http://${site}:8000"
      if [[ "$vm_ip" != "unknown" && -n "$vm_ip" ]]; then
        echo "  curl -I http://${vm_ip}:8000   # troubleshooting only"
      else
        echo "  curl -I http://\${VM_IP}:8000   # troubleshooting only"
      fi
      if port_listens 443; then
        echo "  curl -kI https://${site}"
      fi
      ;;
    *)
      echo "  getent hosts ${site}"
      echo "  curl -I http://${site}:8000"
      if [[ "$vm_ip" != "unknown" && -n "$vm_ip" ]]; then
        echo "  curl -I http://${vm_ip}:8000   # troubleshooting only"
      else
        echo "  curl -I http://\${VM_IP}:8000   # troubleshooting only"
      fi
      if port_listens 443; then
        echo "  curl -kI https://${site}"
      fi
      ;;
  esac
}

show_local_domain_status() {
  require_sudo
  local vm_ip bench_dir detected_network
  vm_ip="$(get_vm_ip)"
  bench_dir="$(active_bench_dir 2>/dev/null || printf '%s' "$BENCH_DIR")"

  if [[ "$vm_ip" == 192.168.122.* ]]; then
    detected_network="KVM/libvirt default NAT"
  elif [[ "$vm_ip" == 10.* || "$vm_ip" == 172.* || "$vm_ip" == 192.168.* ]]; then
    detected_network="private NAT/LAN/bridged network"
  elif [[ "$vm_ip" == unknown ]]; then
    detected_network="unknown"
  else
    detected_network="public or routed interface"
  fi

  echo
  echo "============================================================"
  echo "Local Domain / Host DNS Status"
  echo "============================================================"
  status_line "Local domain" "INFO" "$SITE_NAME"
  status_line "VM IP" "$([[ "$vm_ip" != unknown ]] && echo OK || echo WARN)" "$vm_ip"
  status_line "Host OS" "INFO" "$(host_os_label)"
  status_line "Network type" "INFO" "$detected_network"
  status_line "Bench" "INFO" "$bench_dir"
  status_line "Direct URL" "INFO" "http://${vm_ip}:8000"
  status_line "Friendly URL" "INFO" "http://${SITE_NAME}:8000"
  echo
  echo "Important: ${SITE_NAME} is a local-only name. It is not public DNS."
  echo "Your HOST machine must map ${SITE_NAME} to the current VM IP."
  echo "The IP is detected dynamically; do not copy someone else's 192.168.122.x value."
  echo
  echo "Run this on the HOST machine, not inside the VM:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test from the HOST machine:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo "============================================================"
}

show_local_host_mapping_checkpoint() {
  require_sudo

  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Required Local Host Mapping Checkpoint"
  echo "============================================================"
  echo
  echo "Before using the friendly local URL or configuring local HTTPS,"
  echo "make sure your HOST machine maps this local domain to the current VM IP."
  echo
  status_line "Local domain" "INFO" "$SITE_NAME"
  status_line "Detected VM IP" "$([[ "$vm_ip" != unknown ]] && echo OK || echo WARN)" "$vm_ip"
  status_line "Host OS" "INFO" "$(host_os_label)"
  if host_os_is_unset; then
    echo
    echo "Host OS not chosen yet; showing $(host_os_label) commands by default."
    echo "If your host is macOS or Windows, run: $(toolkit_cmd set-host-os)"
  fi
  echo
  echo "Run this on your $(host_os_label) HOST machine, not inside this VM."
  echo "It is safe to repeat: it backs up the hosts file, removes only the old ${SITE_NAME} entry, then adds the current mapping."
  echo
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test from the HOST machine:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Run this checkpoint whenever:"
  echo "  - You create a fresh local VM"
  echo "  - You delete and recreate the VM"
  echo "  - The VM gets a new DHCP IP"
  echo "  - ${SITE_NAME} opens the wrong VM or stops resolving"
  echo
  echo "After the HTTP test works, continue with:"
  echo "  $(toolkit_cmd local-ssl-wizard)"
  echo "============================================================"
}

local_access_doctor() {
  require_sudo
  local vm_ip direct_head site_head ip_head gateway
  vm_ip="$(get_vm_ip)"
  gateway="$(get_default_gateway 2>/dev/null || true)"

  echo
  echo "============================================================"
  echo "Local Access Doctor"
  echo "============================================================"
  status_line "Local domain" "INFO" "$SITE_NAME"
  status_line "Detected VM IP" "$([[ "$vm_ip" != unknown ]] && echo OK || echo WARN)" "$vm_ip"
  status_line "Default gateway" "INFO" "${gateway:-unknown}"

  if port_listens 8000; then
    status_line "Bench web port" "OK" "8000 listening"
  else
    status_line "Bench web port" "WARN" "8000 is not listening; start ERPNext service or bench"
  fi

  if port_listens 9000; then
    status_line "Socket.IO port" "OK" "9000 listening"
  else
    status_line "Socket.IO port" "INFO" "9000 not listening"
  fi

  direct_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  site_head="$(curl_head_status "http://${SITE_NAME}:8000/" "$SITE_NAME" 8000 "127.0.0.1" || true)"
  ip_head="$(curl_head_status "http://${vm_ip}:8000/" "" "" "" || true)"

  [[ "$direct_head" == HTTP/* ]] && status_line "Inside VM direct HTTP" "OK" "$direct_head" || status_line "Inside VM direct HTTP" "WARN" "no response from 127.0.0.1:8000"
  [[ "$site_head" == HTTP/* ]] && status_line "Inside VM Host header" "OK" "$site_head" || status_line "Inside VM Host header" "WARN" "no response for ${SITE_NAME} host header"
  [[ "$ip_head" == HTTP/* ]] && status_line "Inside VM IP HTTP" "OK" "$ip_head" || status_line "Inside VM IP HTTP" "INFO" "no response from ${vm_ip}:8000 inside VM"

  if command -v ufw >/dev/null 2>&1; then
    status_line "UFW status" "INFO" "$(ufw status 2>/dev/null | head -n 1 | sed 's/^Status: //' || echo unknown)"
  fi

  echo
  echo "If the HOST shows 'Could not resolve host: ${SITE_NAME}', that is host DNS mapping."
  echo "Fix it on the HOST machine with the dynamic command below:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "HOST-side tests:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "If the page loads but looks broken/unstyled when using the raw IP, that is expected:"
  echo "  open http://${SITE_NAME}:8000 (or https://${SITE_NAME} after local HTTPS) instead."
  echo "If direct IP works but ${SITE_NAME} fails, the fix is /etc/hosts on the HOST."
  echo "If both direct IP and ${SITE_NAME} fail, run:"
  echo "  $(toolkit_cmd repair-local-access)"
  echo "  $(toolkit_cmd verify-access)"
  echo "============================================================"
}

show_access_instructions() {
  local vm_ip escaped_site bench_dir
  vm_ip="$(get_vm_ip)"
  bench_dir="$(active_bench_dir)"
  escaped_site="${SITE_NAME//./\\.}"

  echo
  echo "============================================================"
  echo "Browser / Hostname Instructions"
  echo "============================================================"
  echo
  echo "ERPNext must be running before any browser URL will work."
  echo
  echo "Start ERPNext inside the VM with:"
  echo "  $(toolkit_cmd start)"
  echo
  echo "Or manually:"
  echo "  sudo -iu ${FRAPPE_USER}"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo "  cd ${bench_dir}"
  echo "  bench start"
  echo
  echo "Direct IP URL, works while Bench is running:"
  echo "  http://${vm_ip}:8000"
  echo
  echo "Friendly local URL:"
  echo "  http://${SITE_NAME}:8000"
  echo
  echo "The friendly URL only works after your HOST machine maps ${SITE_NAME} to this VM IP."
  echo
  echo "Run this on your $(host_os_label) HOST machine, not inside the VM:"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test on the host:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "If ${SITE_NAME} still does not open, use the direct IP URL first:"
  echo "  http://${vm_ip}:8000"
  echo
  echo "============================================================"
}




verify_access() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_verify_access
    return
  fi

  local vm_ip escaped_site direct_head friendly_head ip_head https_head
  vm_ip="$(get_vm_ip)"
  escaped_site="${SITE_NAME//./\\.}"

  echo
  echo "============================================================"
  echo "Access Verification"
  echo "============================================================"

  if port_listens 8000; then
    status_line "Bench web" "OK" "127.0.0.1:8000 listening"
  else
    status_line "Bench web" "WARN" "127.0.0.1:8000 not listening"
  fi

  if port_listens 9000; then
    status_line "Socket.io" "OK" "127.0.0.1:9000 listening"
  else
    status_line "Socket.io" "INFO" "127.0.0.1:9000 not listening"
  fi

  direct_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  friendly_head="$(curl_head_status "http://${SITE_NAME}:8000/" "$SITE_NAME" 8000 "127.0.0.1" || true)"
  ip_head="$(curl_head_status "http://${vm_ip}:8000/" "" "" "" || true)"

  if [[ "$direct_head" == HTTP/* ]]; then
    status_line "Local direct HTTP" "OK" "$direct_head"
  else
    status_line "Local direct HTTP" "WARN" "no response from http://127.0.0.1:8000"
  fi

  if [[ "$friendly_head" == HTTP/* ]]; then
    status_line "Local site HTTP" "OK" "$friendly_head"
  else
    status_line "Local site HTTP" "WARN" "no response using ${SITE_NAME} host header"
  fi

  if [[ "$ip_head" == HTTP/* ]]; then
    status_line "VM IP HTTP" "OK" "$ip_head"
  else
    status_line "VM IP HTTP" "INFO" "host-side test may still work if networking is correct"
  fi

  if port_listens 443; then
    https_head="$(curl_head_status "https://${SITE_NAME}/" "$SITE_NAME" 443 "127.0.0.1" || true)"
    [[ "$https_head" == HTTP/* ]] && status_line "Local HTTPS" "OK" "$https_head" || status_line "Local HTTPS" "WARN" "port 443 listens, but HTTPS did not respond cleanly"
  else
    status_line "Local HTTPS" "INFO" "not configured yet"
  fi

  # Same gate as wait-ready: every CSS/JS required by /login must be nonempty.
  if declare -F probe_login_frontend_assets_all >/dev/null 2>&1; then
    local probe_rc=0
    if port_listens 443; then
      probe_login_frontend_assets_all "https://${SITE_NAME}/login" "$SITE_NAME" 443 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
    elif port_listens 8000; then
      probe_login_frontend_assets_all "http://${SITE_NAME}:8000/login" "$SITE_NAME" 8000 "127.0.0.1" >/dev/null && probe_rc=0 || probe_rc=$?
    else
      probe_rc=2
    fi
    if [[ "$probe_rc" -eq 0 ]]; then
      status_line "Static assets" "OK" "all required login CSS/JS"
    elif [[ "$probe_rc" -eq 1 ]]; then
      status_line "Static assets" "FAIL" "required login CSS/JS missing — page will look unstyled"
      echo "    Wait or repair, then reload:"
      echo "      $(toolkit_cmd verify-frontend-assets)"
      echo "      $(toolkit_cmd repair-frontend-assets)"
    else
      status_line "Static assets" "WARN" "could not discover login CSS/JS assets yet"
    fi
  fi

  echo
  if is_public_vm_workflow; then
    echo "Production URL:"
    echo "  https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo
    echo "Backend port note:"
    echo "  8000 and 9000 may listen inside the VM, but should be blocked publicly."
    echo
    echo "Workstation tests:"
    echo "  curl -I https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo "  curl -I --connect-timeout 10 http://${vm_ip}:8000"
    echo "  curl -I --connect-timeout 10 http://${vm_ip}:9000"
  else
    print_primary_access_urls
    echo
    echo "HOST /etc/hosts command:"
    print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
    echo
    echo "HOST tests:"
    print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  fi

  echo
  echo "Important browser paths:"
  if is_public_vm_workflow; then
    echo "  Desk:  https://${PRODUCTION_DOMAIN:-$SITE_NAME}/app"
    echo "  Login: https://${PRODUCTION_DOMAIN:-$SITE_NAME}/login"
  elif ssl_is_configured 2>/dev/null && port_listens 443; then
    echo "  Desk:  https://${SITE_NAME}/app"
    echo "  Login: https://${SITE_NAME}/login"
  else
    echo "  Desk:  http://${SITE_NAME}:8000/app"
    echo "  Login: http://${SITE_NAME}:8000/login"
  fi

  if site_app_installed education; then
    print_education_access_note
  fi

  echo "============================================================"
}

print_primary_access_urls() {
  local vm_ip base
  vm_ip="$(get_vm_ip)"

  if is_public_vm_workflow; then
    base="https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo "Primary URLs:"
    echo "  Website / portal root: ${base}"
    echo "  ERPNext / Frappe Desk: ${base}/app"
    echo "  Login page:            ${base}/login"
  else
    if ssl_is_configured 2>/dev/null && port_listens 443; then
      base="https://${SITE_NAME}"
      echo "Primary URLs from the HOST (after /etc/hosts is set):"
      echo "  Website / portal root: ${base}"
      echo "  ERPNext / Frappe Desk: ${base}/app"
      echo "  Login page:            ${base}/login"
      echo
      echo "HTTP fallback:"
      echo "  http://${SITE_NAME}:8000"
    else
      echo "Primary URLs from the HOST (after /etc/hosts is set):"
      echo "  Website / portal root: http://${SITE_NAME}:8000"
      echo "  ERPNext / Frappe Desk: http://${SITE_NAME}:8000/app"
      echo "  Login page:            http://${SITE_NAME}:8000/login"
    fi
    echo
    warn "Raw IP URLs often show an unstyled/broken page (Host header mismatch)."
    echo "  Use the friendly hostname above. Troubleshooting only: http://${vm_ip}:8000"
  fi
}

print_education_access_note() {
  local vm_ip base
  vm_ip="$(get_vm_ip)"

  echo
  warn "Education access note"
  echo "  Education can make the normal website root open the Education portal."
  echo "  This is expected after installing the Education app."
  echo "  Use /app for ERPNext/Frappe Desk and /login for the login page."
  echo

  if is_public_vm_workflow; then
    base="https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo "Education-aware URLs:"
    echo "  ERPNext / Frappe Desk: ${base}/app"
    echo "  Login page:            ${base}/login"
    echo "  Education portal:      ${base}/edu-portal/students"
  else
    if ssl_is_configured 2>/dev/null && port_listens 443; then
      base="https://${SITE_NAME}"
      echo "Education-aware URLs (after /etc/hosts is set):"
      echo "  ERPNext / Frappe Desk: ${base}/app"
      echo "  Login page:            ${base}/login"
      echo "  Education portal:      ${base}/edu-portal/students"
    else
      echo "Education-aware URLs after /etc/hosts is set:"
      echo "  ERPNext / Frappe Desk: http://${SITE_NAME}:8000/app"
      echo "  Login page:            http://${SITE_NAME}:8000/login"
      echo "  Education portal:      http://${SITE_NAME}:8000/edu-portal/students"
    fi
    echo
    echo "Troubleshooting only (often unstyled): http://${vm_ip}:8000/app"
  fi
}

show_access_info() {
  require_sudo

  echo
  echo "============================================================"
  echo "Access Information"
  echo "============================================================"
  print_primary_access_urls

  if site_app_installed education; then
    print_education_access_note
  fi

  echo
  echo "Useful checks:"
  echo "  $(toolkit_cmd verify-access)"
  echo "  $(toolkit_cmd doctor)"
  echo "============================================================"
}

show_education_access_info() {
  require_sudo

  echo
  echo "============================================================"
  echo "Education Access Information"
  echo "============================================================"
  print_education_access_note
  echo
  echo "If /app fails, run:"
  echo "  $(toolkit_cmd service-restart)"
  echo "  $(toolkit_cmd wait-ready)"
  echo "  $(toolkit_cmd doctor)"
  echo "============================================================"
}
show_next_step() {
  require_sudo

  local vm_ip installed runtime auto data can_expand storage_reason storage_state ssl_state next_label next_command
  vm_ip="$(get_vm_ip)"
  installed="$(install_state 2>/dev/null || echo "Not installed")"
  runtime="$(runtime_state 2>/dev/null || echo "Stopped")"
  auto="$(autostart_state 2>/dev/null || echo "Not configured")"
  data="$(storage_eval 2>/dev/null || true)"
  can_expand="$(printf '%s\n' "$data" | awk -F= '$1=="CAN_EXPAND" {print $2; exit}')"
  storage_reason="$(printf '%s\n' "$data" | awk -F= '$1=="REASON" {print $2; exit}')"
  storage_state="OK"
  ssl_state="not configured"

  if [[ "${can_expand:-no}" == "yes" ]]; then
    storage_state="recommended"
  elif [[ -z "${can_expand:-}" ]]; then
    storage_state="unknown"
  fi

  if ssl_is_configured 2>/dev/null; then
    ssl_state="configured"
  fi

  if is_public_vm_workflow; then
    local prod_ssl_pair prod_ssl_status prod_ssl_detail backup_lines backup_complete
    prod_ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not configured for production')"
    prod_ssl_status="${prod_ssl_pair%%|*}"
    prod_ssl_detail="${prod_ssl_pair#*|}"
    backup_lines="$(backup_latest_set_paths 2>/dev/null || true)"
    backup_complete="$(printf '%s\n' "$backup_lines" | sed -n '6p')"

    echo
    echo "============================================================"
    echo "Next Step"
    echo "============================================================"
    status_line "Storage" "INFO" "${storage_state}${storage_reason:+ - ${storage_reason}}"
    status_line "Install" "INFO" "$installed"
    status_line "Runtime" "INFO" "$runtime"
    status_line "Autostart" "INFO" "$auto"
    status_line "Production SSL" "$prod_ssl_status" "$prod_ssl_detail"
    status_line "Latest backup" "$([[ "$backup_complete" == complete ]] && echo OK || echo WARN)" "${backup_complete:-none}"
    echo

    if [[ "${can_expand:-no}" == "yes" ]]; then
      next_label="expand root storage"
      next_command="$(toolkit_cmd expand-root-storage)"
    elif [[ "$installed" != "Installed" ]]; then
      next_label="run public quickstart install"
      next_command="$(toolkit_cmd public-vm-guided-setup)"
    elif [[ "$runtime" != Running* ]]; then
      next_label="start ERPNext"
      next_command="$(toolkit_cmd start)"
    elif [[ "$prod_ssl_status" != "OK" ]]; then
      next_label="configure production HTTPS"
      next_command="$(toolkit_cmd production-ssl-wizard)"
    elif [[ "$backup_complete" != "complete" ]]; then
      next_label="create initial backup"
      next_command="$(toolkit_cmd backup-files)"
    else
      next_label="run release readiness"
      next_command="$(toolkit_cmd release-readiness)"
    fi

    echo "Recommended next step: ${next_label}."
    echo "  $(toolkit_display_item "$next_command")"
    echo
    echo "Production URL:"
    echo "  https://${PRODUCTION_DOMAIN:-$SITE_NAME}"
    echo
    echo "Backend ports 8000/9000 should be blocked publicly after hardening."
    echo "============================================================"
    return 0
  fi

  echo
  echo "============================================================"
  echo "Next Step"
  echo "============================================================"
  status_line "Storage" "INFO" "${storage_state}${storage_reason:+ - ${storage_reason}}"
  status_line "Install" "INFO" "$installed"
  status_line "Runtime" "INFO" "$runtime"
  status_line "Autostart" "INFO" "$auto"
  status_line "Local SSL" "INFO" "$ssl_state"
  echo

  if [[ "${can_expand:-no}" == "yes" ]]; then
    next_label="expand root storage"
    next_command="$(toolkit_cmd expand-root-storage)"
  else
    case "$installed" in
      "Not installed")
        next_label="run guided setup"
        next_command="$(toolkit_cmd guided-setup)"
        ;;
      "Incomplete")
        next_label="repair or reinstall the environment"
        next_command="$(toolkit_cmd repair)"
        ;;
      *)
        if [[ "$runtime" != Running* ]]; then
          next_label="start ERPNext"
          next_command="$(toolkit_cmd start)"
        elif [[ "$auto" != "Enabled" ]]; then
          next_label="enable autostart so the VM recovers cleanly after reboot"
          next_command="$(toolkit_cmd enable-autostart)"
        elif [[ "$ssl_state" != "configured" ]]; then
          next_label="configure local HTTPS"
          next_command="$(toolkit_cmd local-ssl-wizard)"
        else
          next_label="install optional apps with a checkpoint"
          next_command="$(toolkit_cmd app-install-wizard)"
        fi
        ;;
    esac
  fi

  echo "Recommended next step: ${next_label}."
  echo "  $(toolkit_display_item "$next_command")"
  echo
  echo "Required host mapping checkpoint before local HTTPS:"
  echo "  $(toolkit_cmd local-host-checkpoint)"
  echo
  echo "Useful checks:"
  echo "  $(toolkit_cmd verify-access)"
  echo "  $(toolkit_cmd storage-status)"
  echo
  echo "Open when running (friendly hostname — avoid raw IP):"
  if [[ "$ssl_state" == "configured" ]] && port_listens 443; then
    echo "  https://${SITE_NAME}/login"
    echo "  https://${SITE_NAME}/app"
  else
    echo "  http://${SITE_NAME}:8000/login"
    echo "  http://${SITE_NAME}:8000/app"
  fi
  echo "  Troubleshooting only: http://${vm_ip}:8000"
  echo "============================================================"
}
show_host_hosts_command() {
  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Host Mapping Command ($(host_os_label))"
  echo "============================================================"
  echo
  if host_os_is_unset; then
    echo "Host OS not chosen yet; showing $(host_os_label) commands by default."
    echo "If your host is macOS or Windows, run: $(toolkit_cmd set-host-os)"
    echo
  fi
  echo "Run these commands on your $(host_os_label) HOST machine, not inside this VM:"
  echo
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test from the host:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Expected host mapping:"
  echo "  $(host_mapping_ip "$vm_ip") ${SITE_NAME}"
  echo
  echo "This command is environment-aware. The VM IP is detected from this VM,"
  echo "so it works for KVM, bridged LAN, VirtualBox/UTM-style NAT, or other private networks."
  echo "============================================================"
}
get_primary_interface() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
}

get_default_gateway() {
  ip route 2>/dev/null | awk '/^default/ {print $3; exit}'
}

get_primary_mac() {
  local iface
  iface="$(get_primary_interface || true)"

  if [[ -n "${iface}" && -r "/sys/class/net/${iface}/address" ]]; then
    cat "/sys/class/net/${iface}/address"
    return 0
  fi

  ip -o link show 2>/dev/null | awk '$2 != "lo:" {for (i=1; i<=NF; i++) if ($i=="link/ether") {print $(i+1); exit}}'
}

show_network_status() {
  local vm_ip iface mac gateway host_name detected_network
  vm_ip="$(get_vm_ip)"
  iface="$(get_primary_interface || true)"
  mac="$(get_primary_mac || true)"
  gateway="$(get_default_gateway || true)"
  host_name="$(hostname 2>/dev/null || echo unknown)"

  if [[ "${vm_ip}" == 192.168.122.* ]]; then
    detected_network="likely KVM/libvirt default NAT"
  elif [[ "${vm_ip}" == 10.* || "${vm_ip}" == 172.* || "${vm_ip}" == 192.168.* ]]; then
    detected_network="private/LAN or custom NAT"
  else
    detected_network="public or routed address"
  fi

  echo
  echo "============================================================"
  echo "VM Network / Access Status"
  echo "============================================================"
  status_line "VM hostname" "INFO" "${host_name}"
  status_line "Primary interface" "INFO" "${iface:-unknown}"
  status_line "Primary MAC" "INFO" "${mac:-unknown}"
  status_line "VM IP" "INFO" "${vm_ip:-unknown}"
  status_line "Default gateway" "INFO" "${gateway:-unknown}"
  status_line "Network type" "INFO" "${detected_network}"
  status_line "Direct URL" "INFO" "http://${vm_ip}:8000"
  status_line "Friendly URL" "INFO" "http://${SITE_NAME}:8000"

  if port_listens 8000; then
    status_line "Bench web" "OK" "port 8000 listening"
  else
    status_line "Bench web" "INFO" "port 8000 not listening"
  fi

  if [[ -n "${vm_ip}" && -n "${mac}" ]]; then
    echo
    echo "Host /etc/hosts command:"
    print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
    echo
    echo "KVM host helper to find the matching VM by MAC:"
    echo "  target_mac=\"${mac}\""
    echo "  while IFS= read -r vm; do [ -n \"\$vm\" ] || continue; virsh domiflist \"\$vm\" | grep -qi \"\$target_mac\" && echo \"\$vm\"; done < <(virsh list --all --name)"
  fi

  echo
  echo "Tip: if the friendly URL fails, use the Direct URL first, then update the HOST /etc/hosts entry."
  echo "============================================================"
}

show_host_access_test_guide() {
  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Host Access Test Guide"
  echo "============================================================"
  echo
  echo "Run these on the $(host_os_label) HOST machine, not inside this VM:"
  echo
  echo "1) Update the host mapping if the friendly name does not resolve to $(host_mapping_ip "$vm_ip"):"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "2) Confirm resolution and test direct and friendly URLs:"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "5) Browser URLs:"
  echo "  http://${vm_ip}:8000"
  echo "  http://${SITE_NAME}:8000"
  echo
  echo "If curl fails but runtime-status is OK inside the VM, check firewall, NAT/bridge mode, or the host /etc/hosts mapping."
  echo "============================================================"
}

show_kvm_vm_identification_guide() {
  local vm_ip mac clean_name
  vm_ip="$(get_vm_ip)"
  mac="$(get_primary_mac || true)"
  clean_name="${SITE_NAME//./-}"

  echo
  echo "============================================================"
  echo "KVM / libvirt VM Identification + Fixed IP Helper"
  echo "============================================================"
  echo
  echo "Detected inside this VM:"
  echo "  IP:       ${vm_ip}"
  echo "  MAC:      ${mac:-unknown}"
  echo "  Hostname: $(hostname 2>/dev/null || echo unknown)"
  echo
  echo "Run on the KVM HOST to find which libvirt domain owns this MAC:"
  echo
  echo "  target_mac=\"${mac:-PASTE_VM_MAC}\""
  echo "  while IFS= read -r vm; do"
  echo "    [ -n \"\$vm\" ] || continue"
  echo "    if virsh domiflist \"\$vm\" | grep -qi \"\$target_mac\"; then"
  echo "      echo \"Matched VM: \$vm\""
  echo "    fi"
  echo "  done < <(virsh list --all --name)"
  echo
  echo "After identifying the VM name, reserve this IP on the default libvirt NAT network:"
  echo
  echo "  sudo virsh net-update default add ip-dhcp-host \"<host mac='${mac:-PASTE_VM_MAC}' name='${clean_name}' ip='${vm_ip}'/>\" --live --config"
  echo
  echo "Then reboot the VM and confirm:"
  echo "  virsh shutdown \"YOUR_VM_NAME\""
  echo "  virsh start \"YOUR_VM_NAME\""
  echo "  virsh net-dhcp-leases default"
  echo
  echo "Important: libvirt domain names can contain spaces. Use the while-read loop above instead of: for vm in \$(virsh list ...)."
  echo "============================================================"
}









# Universal fallback guidance (print-only). Prefer `local-static-ip-wizard`
# (Netplan on Ubuntu, ifupdown on Debian) via lib/local_ip.sh.
print_guest_static_ip_fallback() {
  local vm_ip gateway
  vm_ip="$(get_vm_ip)"
  gateway="$(get_default_gateway 2>/dev/null || true)"
  echo "Universal fallback (works on any hypervisor) — pin a static IP inside THIS VM:"
  echo
  echo "  Preferred: $(toolkit_cmd local-static-ip-wizard)"
  echo "  (uses Netplan when installed; otherwise classic Debian ifupdown)"
  echo
  echo "  # Inspect the current interface and gateway first:"
  echo "  ip -brief address"
  echo "  ip route | awk '/default/ {print \$3; exit}'"
  echo
  echo "  # Ubuntu / Netplan guests — /etc/netplan/99-erpnext-static.yaml:"
  echo "  network:"
  echo "    version: 2"
  echo "    ethernets:"
  echo "      eth0:"
  echo "        dhcp4: false"
  echo "        addresses: [${vm_ip:-192.168.x.y}/24]"
  echo "        routes:"
  echo "          - to: default"
  echo "            via: ${gateway:-192.168.x.1}"
  echo "        nameservers:"
  echo "          addresses: [1.1.1.1, 8.8.8.8]"
  echo "  sudo netplan apply"
  echo
  echo "  # Debian without Netplan — /etc/network/interfaces.d/99-erpnext-static:"
  echo "  auto eth0"
  echo "  iface eth0 inet static"
  echo "      address ${vm_ip:-192.168.x.y}/24"
  echo "      gateway ${gateway:-192.168.x.1}"
  echo "      dns-nameservers 1.1.1.1 8.8.8.8"
  echo "  sudo systemctl restart networking"
}

# Host-OS/hypervisor-aware stable local VM IP guidance. Linux hosts get the
# KVM/libvirt reservation flow; macOS and Windows hosts get guidance for their
# common hypervisors, and every host gets the universal guest-netplan fallback.
show_local_fixed_ip_guide() {
  local vm_ip host_os
  vm_ip="$(get_vm_ip)"
  host_os="$(effective_host_os)"

  case "$host_os" in
    linux)
      show_kvm_fixed_ip_guide
      return 0
      ;;
    macos)
      echo
      echo "============================================================"
      echo "Stable Local VM IP Guide (macOS host)"
      echo "============================================================"
      echo
      echo "Purpose:"
      echo "  Keep this VM on the same IP so ${SITE_NAME} does not break after reboot."
      echo
      echo "Current VM IP detected inside this VM: ${vm_ip}"
      echo
      echo "UTM (QEMU):"
      echo "  - Prefer 'Emulated VLAN'/Shared networking, then reserve the IP with a"
      echo "    static lease, or set a static IP inside the guest (fallback below)."
      echo "VMware Fusion:"
      echo "  - Edit /Library/Preferences/VMware\\ Fusion/vmnet8/dhcpd.conf and add a"
      echo "    'host' stanza binding the VM MAC to a fixed IP, then restart networking."
      echo "Parallels Desktop:"
      echo "  - Use Control Center > Network, or 'prlsrvctl net set' to reserve a DHCP"
      echo "    lease for the VM MAC address."
      echo
      print_guest_static_ip_fallback
      echo
      echo "Then update the host mapping:"
      print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
      echo "============================================================"
      return 0
      ;;
    windows|windows-wsl)
      echo
      echo "============================================================"
      echo "Stable Local VM IP Guide (Windows host)"
      echo "============================================================"
      echo
      echo "Purpose:"
      echo "  Keep this VM on the same IP so ${SITE_NAME} does not break after reboot."
      echo
      echo "Current VM IP detected inside this VM: ${vm_ip}"
      echo
      if [[ "$host_os" == "windows-wsl" ]]; then
        echo "WSL2 note:"
        echo "  The WSL2 IP changes on every boot, but Windows reaches WSL2 services over"
        echo "  localhost. Map ${SITE_NAME} to 127.0.0.1 (see host mapping below) instead"
        echo "  of chasing the WSL2 address; no reservation is needed."
        echo
      fi
      echo "Hyper-V:"
      echo "  - The Default Switch uses dynamic NAT. For a stable IP, create an External"
      echo "    virtual switch (or an Internal switch with a static host IP), then set a"
      echo "    static IP inside the guest (fallback below), or reserve by MAC on your router."
      echo "VirtualBox:"
      echo "  - Use a Host-Only adapter and a static guest IP, or reserve via:"
      echo "    VBoxManage dhcpserver modify --network=HostInterfaceNetworking-VirtualBox\\ Host-Only\\ Ethernet\\ Adapter \\"
      echo "      --fixed-address <ip> --mac-address <vm-mac>"
      echo
      print_guest_static_ip_fallback
      echo
      echo "Then update the host mapping:"
      print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
      echo "============================================================"
      return 0
      ;;
    *)
      show_kvm_fixed_ip_guide
      return 0
      ;;
  esac
}

show_kvm_fixed_ip_guide() {
  local vm_ip clean_name escaped_site
  vm_ip="$(get_vm_ip)"
  clean_name="${SITE_NAME//./-}"
  escaped_site="${SITE_NAME//./\\.}"

  echo
  echo "============================================================"
  echo "KVM / libvirt Fixed IP Guide"
  echo "============================================================"
  echo
  echo "Purpose:"
  echo "  Keep this VM on the same IP so ${SITE_NAME} does not break after reboot."
  echo
  echo "Current VM IP detected inside this VM:"
  echo "  ${vm_ip}"
  echo

  if [[ "${vm_ip}" == 192.168.122.* ]]; then
    echo "This looks like the default libvirt NAT network range: 192.168.122.0/24"
  else
    echo "This IP is not in the default libvirt NAT range."
    echo "The guide still applies, but your network may be bridged, custom NAT, VMware, VirtualBox, or cloud."
  fi

  echo
  echo "Run these commands on the KVM HOST machine, not inside this VM:"
  echo
  echo "  virsh list --all"
  echo "  virsh domiflist \"YOUR_VM_NAME\""
  echo
  echo "Copy the VM MAC address from domiflist, then reserve the IP:"
  echo
  echo "  sudo virsh net-update default add ip-dhcp-host \"<host mac='YOUR_VM_MAC' name='${clean_name}' ip='${vm_ip}'/>\" --live --config"
  echo
  echo "Restart the VM from the host:"
  echo
  echo "  virsh shutdown \"YOUR_VM_NAME\""
  echo "  virsh start \"YOUR_VM_NAME\""
  echo
  echo "Verify the lease from the host:"
  echo
  echo "  sudo virsh net-dhcp-leases default"
  echo
  echo "Then update the host /etc/hosts entry:"
  echo
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Notes:"
  echo "  - Use one unique fixed IP per ERPNext VM."
  echo "  - Do not reserve the same IP for two VMs."
  echo "  - If this VM already has a different reservation, remove/update the old one on the host."
  echo
  echo "============================================================"
}

show_multi_environment_guide() {
  local host_label hosts_path
  host_label="$(host_os_label)"
  case "$(effective_host_os)" in
    windows|windows-wsl) hosts_path="%SystemRoot%\\System32\\drivers\\etc\\hosts" ;;
    *) hosts_path="/etc/hosts" ;;
  esac
  cat <<EOF_MULTI

============================================================
Multiple Local ERPNext Environments
============================================================

Use one VM, one site name, and one fixed IP per development environment.

Recommended examples:

  192.168.122.61  erp1.test
  192.168.122.62  erp2.test
  192.168.122.63  school.test
  192.168.122.64  client-a.test
  192.168.122.65  client-b.test

Install examples inside each VM:

  $(toolkit_cmd_env "SITE_NAME=erp1.test" setup)
  $(toolkit_cmd_env "SITE_NAME=school.test" setup)
  $(toolkit_cmd_env "SITE_NAME=client-a.test" setup)

Host mapping examples (${host_label} hosts file: ${hosts_path}):

  192.168.122.61 erp1.test
  192.168.122.62 erp2.test
  192.168.122.63 school.test
  192.168.122.64 client-a.test

Recommended rule:
  - Local development: use .test domains.
  - Avoid .local because it is commonly used by mDNS/Avahi and tools like LocalWP.
  - Cloud/production: use a real domain and HTTPS, not bench start.

============================================================
EOF_MULTI
}
show_access_menu() {
  while true; do
    ui_submenu_header "Access / Hostname / Networking" "Browser URLs, hosts DNS, and local SSL helpers"
    print_two_column_menu \
      "1) Show current VM browser access instructions" \
      "2) Local domain / host DNS status" \
      "3) Local access doctor" \
      "4) Show host /etc/hosts command only" \
      "5) Show VM network/access status" \
      "6) Local network / stable IP menu" \
      "7) Verify ERPNext HTTP access" \
      "8) Show KVM VM identification + fixed IP helper" \
      "9) Show stable VM IP guide (per host OS / hypervisor)" \
      "10) Show multi-environment naming guide" \
      "11) Show SSL/HTTPS roadmap" \
      "12) Show local SSL status" \
      "13) Show local SSL guide" \
      "14) Local SSL wizard" \
      "15) Show trusted mkcert SSL guide" \
      "16) Show browser trust check guide" \
      "17) Verify local SSL" \
      "18) Install/replace local SSL cert" \
      "19) Create self-signed local cert" \
      "20) Configure local SSL reverse proxy" \
      "21) Disable local SSL reverse proxy" \
      "22) Verify SSL rollback" \
      "23) Show SSL rollback guide" \
      "24) Domain config" \
      "25) Production readiness preview" \
      "26) Production domain guide" \
      "27) Production SSL guide" \
      "28) Environment / location check" \
      "29) Show host access test guide"
    menu_footer
    local access_choice=""
    menu_read_choice access_choice

    case "$access_choice" in
      1) show_access_instructions; pause_after_screen "Press Enter to return to Access..." ;;
      2) show_local_domain_status; pause_after_screen "Press Enter to return to Access..." ;;
      3) local_access_doctor; pause_after_screen "Press Enter to return to Access..." ;;
      4) show_host_hosts_command; pause_after_screen "Press Enter to return to Access..." ;;
      5) show_network_status; pause_after_screen "Press Enter to return to Access..." ;;
      6) show_local_ip_menu ;;
      7) verify_access; pause_after_screen "Press Enter to return to Access..." ;;
      8) show_kvm_vm_identification_guide; pause_after_screen "Press Enter to return to Access..." ;;
      9) show_local_fixed_ip_guide; pause_after_screen "Press Enter to return to Access..." ;;
      10) show_multi_environment_guide; pause_after_screen "Press Enter to return to Access..." ;;
      11) show_ssl_roadmap_guide; pause_after_screen "Press Enter to return to Access..." ;;
      12) show_ssl_status; pause_after_screen "Press Enter to return to Access..." ;;
      13) show_local_ssl_guide; pause_after_screen "Press Enter to return to Access..." ;;
      14) run_local_ssl_wizard ;;
      15) show_mkcert_local_ssl_guide; pause_after_screen "Press Enter to return to Access..." ;;
      16) show_browser_trust_check_guide; pause_after_screen "Press Enter to return to Access..." ;;
      17) verify_local_ssl; pause_after_screen "Press Enter to return to Access..." ;;
      18) install_local_ssl_cert; pause_after_screen "Press Enter to return to Access..." ;;
      19) create_self_signed_local_cert; pause_after_screen "Press Enter to return to Access..." ;;
      20) configure_local_ssl; pause_after_screen "Press Enter to return to Access..." ;;
      21) disable_local_ssl; pause_after_screen "Press Enter to return to Access..." ;;
      22) verify_ssl_rollback; pause_after_screen "Press Enter to return to Access..." ;;
      23) show_ssl_rollback_guide; pause_after_screen "Press Enter to return to Access..." ;;
      24) show_domain_config; pause_after_screen "Press Enter to return to Access..." ;;
      25) show_production_readiness; pause_after_screen "Press Enter to return to Access..." ;;
      26) show_production_domain_guide; pause_after_screen "Press Enter to return to Access..." ;;
      27) show_production_ssl_guide; pause_after_screen "Press Enter to return to Access..." ;;
      28) show_environment_check; pause_after_screen "Press Enter to return to Access..." ;;
      29) show_host_access_test_guide; pause_after_screen "Press Enter to return to Access..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_credentials_menu() {
  while true; do
    ui_submenu_header "Credentials / Login" "Private console required to reveal passwords"
    print_two_column_menu \
      "1) Login info" \
      "2) Show password" \
      "3) File status" \
      "4) Secure file" \
      "5) Delete local file" \
      "6) Reset admin password"
    menu_footer
    local credentials_choice=""
    menu_read_choice credentials_choice

    case "$credentials_choice" in
      1) show_credentials_info; pause_after_screen "Press Enter to return to Credentials / Login..." ;;
      2) credentials_show; pause_after_screen "Press Enter to return to Credentials / Login..." ;;
      3) show_credentials_file_status; pause_after_screen "Press Enter to return to Credentials / Login..." ;;
      4) credentials_secure; pause_after_screen "Press Enter to return to Credentials / Login..." ;;
      5) credentials_delete; pause_after_screen "Press Enter to return to Credentials / Login..." ;;
      6) reset_admin_password; pause_after_screen "Press Enter to return to Credentials / Login..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option"; pause_after_screen "Press Enter to continue..." ;;
    esac
  done
}

show_credentials_info() {
  require_sudo

  local cred_file current_site
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"
  current_site="${PRODUCTION_DOMAIN:-${SITE_NAME}}"

  ui_box_start "ERPNext Login"
  status_line "Username" "INFO" "Administrator"
  status_line "Site" "INFO" "$current_site"
  if path_is_file "$cred_file"; then
    status_line "Credentials file" "OK" "$cred_file"
  else
    status_line "Credentials file" "WARN" "missing at $cred_file"
  fi
  echo
  echo "Password"
  echo "  $(toolkit_cmd credentials-show)"
  echo
  echo "Manage"
  echo "  File status:    $(toolkit_cmd credentials-file-status)"
  echo "  Secure file:    $(toolkit_cmd credentials-secure)"
  echo "  Reset password: $(toolkit_cmd reset-admin-password)"
  echo "  Delete file:    $(toolkit_cmd credentials-delete)"
  echo
  echo "The password command writes secrets only to the private terminal, not the toolkit log."
  ui_box_end
}

show_credentials_file_status() {
  require_sudo

  local cred_file owner group mode size modified status perm_status
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  echo
  echo "============================================================"
  echo "Credentials File Status"
  echo "============================================================"

  if ! path_is_file "$cred_file"; then
    status_line "Credentials file" "WARN" "missing at $cred_file"
    echo
    echo "If you already saved the credentials in a password manager, this is acceptable."
    echo "If you still need access, reset the Administrator password with:"
    echo "  $(toolkit_cmd reset-admin-password)"
    echo "============================================================"
    return 0
  fi

  owner="$(stat -c '%U' "$cred_file" 2>/dev/null || echo unknown)"
  group="$(stat -c '%G' "$cred_file" 2>/dev/null || echo unknown)"
  mode="$(stat -c '%a' "$cred_file" 2>/dev/null || echo unknown)"
  size="$(stat -c '%s' "$cred_file" 2>/dev/null || echo unknown)"
  modified="$(stat -c '%y' "$cred_file" 2>/dev/null | cut -d'.' -f1 || echo unknown)"

  if [[ "$owner" == "root" && "$mode" == "600" ]]; then
    perm_status="OK"
    status="root-only permissions"
  else
    perm_status="WARN"
    status="recommended owner=root and mode=600; run $(toolkit_cmd credentials-secure)"
  fi

  status_line "Credentials file" "OK" "$cred_file"
  status_line "Owner" "$([[ "$owner" == "root" ]] && echo OK || echo WARN)" "$owner"
  status_line "Group" "INFO" "$group"
  status_line "Mode" "$([[ "$mode" == "600" ]] && echo OK || echo WARN)" "$mode"
  status_line "Size" "INFO" "${size} bytes"
  status_line "Modified" "INFO" "$modified"
  status_line "Security" "$perm_status" "$status"
  echo
  echo "Production recommendation:"
  echo "  1. Save the credentials in a password manager."
  echo "  2. Run: $(toolkit_cmd credentials-delete)"
  echo "============================================================"
}

credentials_secure() {
  require_sudo

  local cred_file
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  if ! path_is_file "$cred_file"; then
    warn "Credentials file is missing: $cred_file"
    echo "Use $(toolkit_cmd reset-admin-password) if you need to set a new Administrator password."
    return 0
  fi

  $SUDO chown root:root "$cred_file"
  $SUDO chmod 600 "$cred_file"
  ok "Credentials file secured with owner=root and mode=600"
  show_credentials_file_status
}

credentials_show() {
  require_sudo

  local cred_file reply
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  echo
  echo "============================================================"
  echo "Show ERPNext Credentials"
  echo "============================================================"

  if ! path_is_file "$cred_file"; then
    status_line "Credentials file" "WARN" "missing at $cred_file"
    echo
    echo "If the file was deleted after handoff, reset the Administrator password with:"
    echo "  $(toolkit_cmd reset-admin-password)"
    echo "============================================================"
    return 1
  fi

  warn "This will display generated passwords in your terminal."
  echo "Only continue from a private console. Do not paste this output into chats, tickets, logs, or screenshots."
  echo

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    reply="SHOW"
  else
    read -r -p "Type SHOW to display credentials: " reply
  fi

  if [[ "$reply" != "SHOW" ]]; then
    warn "Credentials display cancelled."
    echo "============================================================"
    return 1
  fi

  echo
  # The toolkit tees all stdout to a log file, so printing the credentials to
  # stdout would persist plaintext secrets on disk — exactly what the warning
  # above tells operators not to do. Write the secret block straight to the
  # controlling terminal instead, which bypasses the log. If there is no private
  # terminal (non-interactive/CI), refuse rather than leak into a logged stream.
  if [[ -w /dev/tty ]]; then
    {
      echo "============================================================"
      echo "ERPNext Credentials"
      echo "============================================================"
      $SUDO awk '
        /^Login:/ { section="login"; next }
        /^MariaDB Bench Admin:/ { section="db"; next }
        /^Start ERPNext:/ { exit }
        section == "login" && /^[[:space:]]+Username:/ { sub(/^[[:space:]]+/, ""); print "ERPNext " $0; next }
        section == "login" && /^[[:space:]]+Password:/ { sub(/^[[:space:]]+/, ""); print "ERPNext " $0; next }
        section == "db" && /^[[:space:]]+User:/ { sub(/^[[:space:]]+/, ""); print "MariaDB " $0; next }
        section == "db" && /^[[:space:]]+Password:/ { sub(/^[[:space:]]+/, ""); print "MariaDB " $0; next }
      ' "$cred_file"
      echo "============================================================"
    } > /dev/tty
  else
    warn "No private terminal (/dev/tty) available; not writing secrets to the logged output stream."
    echo "Read the file directly on a private console instead:"
    echo "  sudo cat ${cred_file}"
  fi
  echo
  echo "After saving these credentials in a password manager, production systems should run:"
  echo "  $(toolkit_cmd credentials-delete)"
  echo "============================================================"
}

credentials_delete() {
  require_sudo

  local cred_file reply
  cred_file="${FRAPPE_HOME}/erpnext-dev-credentials.txt"

  echo
  echo "============================================================"
  echo "Delete Local Credentials File"
  echo "============================================================"

  if ! path_is_file "$cred_file"; then
    status_line "Credentials file" "INFO" "already missing at $cred_file"
    echo "============================================================"
    return 0
  fi

  warn "This removes the local plaintext credentials file from the VM."
  echo "Only continue after saving credentials in a password manager or completing handoff."
  echo "This does not change the ERPNext Administrator password."
  echo

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    reply="DELETE"
  else
    read -r -p "Type DELETE to remove ${cred_file}: " reply
  fi

  if [[ "$reply" != "DELETE" ]]; then
    warn "Credentials deletion cancelled."
    echo "============================================================"
    return 1
  fi

  $SUDO rm -f "$cred_file"
  ok "Deleted local credentials file: $cred_file"
  echo "If access is needed later, run: $(toolkit_cmd reset-admin-password)"
  echo "============================================================"
}

reset_admin_password() {
  require_sudo

  local bench_dir site new_password confirm_password pw_quoted site_quoted
  bench_dir="$(active_bench_dir 2>/dev/null || printf '%s' "${BENCH_DIR}")"
  site="${SITE_NAME}"

  echo
  echo "============================================================"
  echo "Reset ERPNext Administrator Password"
  echo "============================================================"
  status_line "Site" "INFO" "$site"
  status_line "Bench" "INFO" "$bench_dir"
  echo

  if [[ ! -d "$bench_dir" ]]; then
    fail "Bench folder not found: $bench_dir"
  fi

  if [[ ! -t 0 ]]; then
    fail "Interactive terminal required for password reset."
  fi

  read -r -s -p "New Administrator password: " new_password
  echo
  read -r -s -p "Confirm new Administrator password: " confirm_password
  echo

  if [[ -z "$new_password" ]]; then
    fail "Password cannot be empty."
  fi
  if [[ "$new_password" != "$confirm_password" ]]; then
    fail "Passwords do not match."
  fi

  pw_quoted="$(printf '%q' "$new_password")"
  site_quoted="$(printf '%q' "$site")"

  echo "Updating Administrator password..."
  run_as_frappe "cd '${bench_dir}' && bench --site ${site_quoted} set-admin-password ${pw_quoted}"
  ok "Administrator password updated for ${site}"
  echo
  echo "Save the new password in a password manager."
  echo "If the generated credentials file contains the old password, remove it with:"
  echo "  $(toolkit_cmd credentials-delete)"
  echo "============================================================"
}
