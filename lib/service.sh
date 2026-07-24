# shellcheck shell=bash
# ERPNext systemd service, runtime readiness, and state helpers.
[[ -n "${_ERPNEXT_DEV_SERVICE_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_SERVICE_LOADED=1

# ============================================================
# Service / Runtime
# ============================================================

start_erpnext_foreground() {
  log "Starting ERPNext development server in foreground"

  local bench_dir
  bench_dir="$(require_bench_dir)" || return 1

  local vm_ip
  vm_ip="$(get_vm_ip)"

  echo
  echo "ERPNext will start in development mode."
  echo
  echo "Keep this terminal open while using ERPNext."
  echo
  echo "Preferred URL after HOST /etc/hosts is configured:"
  echo "  http://${SITE_NAME}:8000/login"
  echo
  echo "Troubleshooting only (often unstyled — Host header mismatch):"
  echo "  http://${vm_ip}:8000"
  echo
  echo "If ${SITE_NAME} does not open, confirm /etc/hosts, then run:"
  echo "  $(toolkit_cmd access)"
  echo

  $SUDO -iu "$FRAPPE_USER" bash -lc "
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    cd \"${bench_dir}\"
    bench start
  "
}

erpnext_service_path() {
  echo "/etc/systemd/system/${ERPNEXT_SERVICE_NAME}"
}

service_exists() {
  [[ -f "$(erpnext_service_path)" ]]
}

# Toolkit-managed development runtime deliberately excludes the Frappe asset
# watcher. `bench watch` is useful for active frontend development, but running
# it continuously inside the systemd service can race with explicit `bench build`
# operations and rotate hashed bundles while readiness probes are reading /login.
toolkit_runtime_procfile_path() {
  local bench_dir="${1:-}"
  [[ -n "$bench_dir" ]] || bench_dir="$(require_bench_dir)" || return 1
  printf '%s/Procfile.toolkit\n' "$bench_dir"
}

ensure_toolkit_runtime_procfile() {
  local bench_dir="${1:-}" source_file target_file tmp
  [[ -n "$bench_dir" ]] || bench_dir="$(require_bench_dir)" || return 1
  source_file="${bench_dir}/Procfile"
  target_file="$(toolkit_runtime_procfile_path "$bench_dir")" || return 1
  [[ -f "$source_file" ]] || {
    err "Bench Procfile not found: ${source_file}"
    return 1
  }

  tmp="${target_file}.tmp.$$"
  awk '!/^[[:space:]]*watch[[:space:]]*:/' "$source_file" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$target_file" || return 1
  chown "$FRAPPE_USER:$FRAPPE_USER" "$target_file" 2>/dev/null || true
  chmod 0644 "$target_file" 2>/dev/null || true
  return 0
}

erpnext_service_uses_toolkit_procfile() {
  service_exists && grep -Fq 'bench start --procfile Procfile.toolkit' "$(erpnext_service_path)"
}

# Existing v1.19.18 and older units used plain `bench start`, which starts the
# asset watcher. Rewrite those units before any managed start/restart so beta can
# repair an already-installed VM without requiring reinstall or reboot.
ensure_erpnext_service_definition() {
  local bench_dir
  bench_dir="$(require_bench_dir)" || return 1
  ensure_toolkit_runtime_procfile "$bench_dir" || return 1
  if ! erpnext_service_uses_toolkit_procfile; then
    log "Updating ERPNext systemd service to watcher-free managed runtime"
    create_erpnext_service || return 1
  fi
  return 0
}

port_listens() {
  local port="$1"
  nc -z 127.0.0.1 "$port" >/dev/null 2>&1
}

bench_ports_ready() {
  port_listens 8000 && port_listens 9000 && port_listens 11000 && port_listens 13000
}

# Wait only for the runtime substrate required by frontend verification. This is
# intentionally asset-agnostic so repair-frontend-assets can wait for Redis/web
# after a restart without recursively depending on the asset gate it is fixing.
wait_for_core_runtime_ready() {
  local timeout="${1:-60}"
  local interval="${2:-2}"
  local elapsed=0

  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=60
  [[ "$interval" =~ ^[0-9]+$ ]] && ((interval >= 1)) || interval=2

  while ((elapsed <= timeout)); do
    if bench_ports_ready && bench_http_ready; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 1
}

bench_ready_count() {
  local count=0
  local port

  for port in 8000 9000 11000 13000; do
    if port_listens "$port"; then
      count=$((count + 1))
    fi
  done

  echo "$count"
}

bench_readiness_line() {
  local elapsed="$1"
  local timeout="$2"
  local http_state="${3:-}"
  local assets_state="${4:-}"
  local web socket queue cache

  if port_listens 8000; then web="OK"; else web="wait"; fi
  if port_listens 9000; then socket="OK"; else socket="wait"; fi
  if port_listens 11000; then queue="OK"; else queue="wait"; fi
  if port_listens 13000; then cache="OK"; else cache="wait"; fi
  if [[ -z "$http_state" ]]; then
    if bench_http_ready; then http_state="OK"; else http_state="wait"; fi
  fi
  if [[ -z "$assets_state" ]]; then
    if bench_static_assets_ready; then assets_state="OK"; else assets_state="wait"; fi
  fi

  printf "  [%3ss/%3ss] web: %-4s http: %-4s assets: %-4s socket: %-4s queue: %-4s cache: %-4s\n" \
    "$elapsed" "$timeout" "$web" "$http_state" "$assets_state" "$socket" "$queue" "$cache"
}

# Browser-ready gate: every local CSS/JS required by /login must GET with
# size_download > 0 (probe_login_frontend_assets_all). Prefers Frappe local
# :8000 first, then HTTPS :443 (nginx). One missing login.bundle /
# erpnext-web.bundle style 404 must fail even if website.bundle is OK.
_frontend_asset_route_fingerprint() {
  local url="${1:-}" host="${2:-}" port="${3:-}" tmp probe_rc=0 fingerprint=""

  [[ -n "$url" && -n "$host" && -n "$port" ]] || return 1
  tmp="$(mktemp /tmp/erpnext-dev-ready-assets.XXXXXX)"
  set +e
  probe_login_frontend_assets_all "$url" "$host" "$port" "127.0.0.1" >"$tmp"
  probe_rc=$?
  set -e

  if [[ "$probe_rc" -eq 0 ]]; then
    fingerprint="$(
      awk -F'|' '$1 == "OK" && $2 != "" {print $2}' "$tmp" \
        | LC_ALL=C sort -u \
        | sha256sum \
        | awk '{print $1}'
    )"
  fi
  rm -f "$tmp"

  [[ "$probe_rc" -eq 0 && -n "$fingerprint" ]] || return 1
  printf '%s\n' "$fingerprint"
}

bench_static_assets_probe_fingerprint() {
  local fingerprint=""

  # Preserve the historical route order: try the Frappe-local :8000 contract
  # first, then HTTPS :443 when the first route is not browser-ready.
  if port_listens 8000; then
    fingerprint="$(_frontend_asset_route_fingerprint \
      "http://${SITE_NAME}:8000/login" "$SITE_NAME" 8000)" && {
      printf '%s\n' "$fingerprint"
      return 0
    }
  fi
  if port_listens 443; then
    fingerprint="$(_frontend_asset_route_fingerprint \
      "https://${SITE_NAME}/login" "$SITE_NAME" 443)" && {
      printf '%s\n' "$fingerprint"
      return 0
    }
  fi
  return 1
}

bench_static_assets_ready() {
  bench_static_assets_probe_fingerprint >/dev/null
}

# Require ASSET_READY_STABLE_CHECKS consecutive full successes (default 3)
# separated by ASSET_READY_STABLE_GAP seconds (default 2). Any failure resets.
bench_static_assets_ready_stable() {
  local need="${ASSET_READY_STABLE_CHECKS:-3}"
  local gap="${ASSET_READY_STABLE_GAP:-2}"
  local i fingerprint previous=""

  [[ "$need" =~ ^[0-9]+$ ]] && ((need >= 1)) || need=3
  [[ "$gap" =~ ^[0-9]+$ ]] || gap=2

  for ((i = 1; i <= need; i++)); do
    fingerprint="$(bench_static_assets_probe_fingerprint)" || return 1
    if [[ -n "$previous" && "$fingerprint" != "$previous" ]]; then
      return 1
    fi
    previous="$fingerprint"
    if ((i < need)); then
      sleep "$gap"
    fi
  done
  return 0
}

# Capture failing assets (for diagnostics) before a rebuild. Best-effort.
record_frontend_asset_failures() {
  local url host port line tmp probe_rc=0 fail_count=0
  # Prefer :8000 (Frappe local contract) so diagnostics match wait-ready.
  if port_listens 8000; then
    url="http://${SITE_NAME}:8000/login"
    host="$SITE_NAME"
    port=8000
  elif port_listens 443; then
    url="https://${SITE_NAME}/login"
    host="$SITE_NAME"
    port=443
  else
    echo "Frontend probe unavailable: neither :8000 nor :443 is listening yet."
    return 1
  fi

  tmp="$(mktemp /tmp/erpnext-dev-asset-failures.XXXXXX)"
  set +e
  probe_login_frontend_assets_all "$url" "$host" "$port" "127.0.0.1" >"$tmp"
  probe_rc=$?
  set -e

  echo "Missing / failed required assets:"
  while IFS= read -r line; do
    [[ "$line" == FAIL\|* ]] || continue
    fail_count=$((fail_count + 1))
    # FAIL|path|code|bytes|ctype|class
    printf '  %s\n' "$(printf '%s' "$line" | awk -F'|' '{printf "%s  HTTP %s  (%s)", $2, $3, $6}')"
  done <"$tmp"
  rm -f "$tmp"

  if ((fail_count == 0)); then
    case "$probe_rc" in
      0) echo "  No individual asset failure was returned by the probe." ;;
      2) echo "  Probe could not discover a complete CSS+JavaScript manifest from ${url}." ;;
      *) echo "  Frontend probe failed before it could identify an individual asset (rc=${probe_rc})." ;;
    esac
  fi
  return "$probe_rc"
}

# Rebuild missing login CSS/JS once without nesting wait_for_erpnext_ready
# (restart_erpnext_service / repair_frontend_assets would recurse). Used when
# http is OK but hashed bundles 404 — the failure mode from "Assets for Release
# … don't exist" after a fresh install.
try_rebuild_frontend_assets_once() {
  local bench_dir

  bench_dir="$(require_site_environment 2>/dev/null)" || return 1

  echo
  warn "Login CSS/JS still missing (often HTTP 404) — rebuilding assets once."
  echo "  This is the automatic fix for incomplete post-install bundle builds."
  record_frontend_asset_failures || true
  echo

  if ! maintenance_build; then
    warn "Automatic asset rebuild failed. Run: $(toolkit_cmd repair-frontend-assets)"
    return 1
  fi

  # maintenance_build already clears cache/assets_json; keep a soft second clear
  # without nesting ensure_bench_services → wait_for_erpnext_ready.
  log "Clearing site cache after asset rebuild"
  clear_bench_assets_json_cache \
    || run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache" || true

  # Soft bounce only — never call restart_* helpers that nest wait_for_erpnext_ready.
  if deployment_engine_is_docker; then
    docker_compose restart || return 1
  elif runtime_is_production && production_runtime_configured; then
    log "Restarting production runtime after asset rebuild"
    $SUDO "$(supervisorctl_bin)" restart all >/dev/null 2>&1 || true
  elif service_exists; then
    log "Restarting ERPNext service after asset rebuild"
    $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}" || return 1
  fi

  # After assets exist on :443/:8000, also fix bare http://SITE (:80) so the
  # default browser URL does not keep showing an unstyled login page.
  if ssl_is_configured 2>/dev/null && port_listens 443; then
    ensure_local_http_redirects_to_https || true
  fi

  return 0
}

# shellcheck disable=SC2120 # timeout/interval are optional overrides with sane defaults
wait_for_erpnext_ready() {
  local timeout="${1:-$READY_TIMEOUT}"
  local interval="${2:-$READY_INTERVAL}"
  local elapsed=0
  local http_state assets_state
  local asset_stable_streak=0
  local need_stable="${ASSET_READY_STABLE_CHECKS:-3}"
  local gap_stable="${ASSET_READY_STABLE_GAP:-2}"
  local asset_fingerprint="" previous_asset_fingerprint="" asset_probe_rc=1

  echo
  echo "Waiting for ERPNext services to become ready..."
  echo "Requires ports, HTTP ping, and a stable login asset manifest (CSS/JS)."
  echo "Read-only check: wait-ready never rebuilds assets or changes the runtime."
  echo "This can take up to ${timeout}s after start/restart (READY_TIMEOUT)."
  echo

  [[ "$need_stable" =~ ^[0-9]+$ ]] && ((need_stable >= 1)) || need_stable=3
  [[ "$gap_stable" =~ ^[0-9]+$ ]] || gap_stable=2

  while ((elapsed <= timeout)); do
    http_state="wait"
    assets_state="wait"
    asset_fingerprint=""

    if bench_http_ready; then
      http_state="OK"
    fi

    # Probe every asset advertised by one /login response and fingerprint that
    # exact successful asset set. A changing hash set resets readiness even when
    # each individual request happened to return HTTP 200.
    if [[ "$http_state" == "OK" ]]; then
      set +e
      asset_fingerprint="$(bench_static_assets_probe_fingerprint)"
      asset_probe_rc=$?
      set -e
      if [[ "$asset_probe_rc" -eq 0 && -n "$asset_fingerprint" ]]; then
        assets_state="OK"
        if [[ -n "$previous_asset_fingerprint" && "$asset_fingerprint" == "$previous_asset_fingerprint" ]]; then
          asset_stable_streak=$((asset_stable_streak + 1))
        else
          asset_stable_streak=1
          previous_asset_fingerprint="$asset_fingerprint"
        fi
      else
        asset_stable_streak=0
        previous_asset_fingerprint=""
      fi
    else
      asset_stable_streak=0
      previous_asset_fingerprint=""
    fi

    bench_readiness_line "$elapsed" "$timeout" "$http_state" "$assets_state"

    # Ports alone are not enough: require HTTP plus the same complete asset
    # manifest to pass repeatedly. This rejects rotating stale assets_json views.
    if bench_ports_ready && [[ "$http_state" == "OK" && "$assets_state" == "OK" ]] \
      && ((asset_stable_streak >= need_stable)); then
      if runtime_is_production; then
        ok "ERPNext is ready. Production runtime is serving a stable frontend manifest."
      else
        ok "ERPNext is ready. Development ports, HTTP, and a stable frontend manifest are OK."
      fi
      return 0
    fi

    # Between consecutive successes, wait the stability gap (not only READY_INTERVAL).
    if [[ "$http_state" == "OK" && "$assets_state" == "OK" ]] && ((asset_stable_streak < need_stable)); then
      sleep "$gap_stable"
      elapsed=$((elapsed + gap_stable))
      continue
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  warn "ERPNext did not become fully ready within ${timeout}s."
  echo
  echo "Useful checks:"
  echo "  $(toolkit_cmd runtime-status)"
  echo "  $(toolkit_cmd verify-local-ssl)   # look at Static assets"
  echo "  $(toolkit_cmd logs)"
  echo "  sudo systemctl status ${ERPNEXT_SERVICE_NAME} --no-pager -l"
  echo
  echo "If only assets stay on wait, rebuild and clear cache, then retry:"
  echo "  $(toolkit_cmd repair-frontend-assets)"
  echo "  READY_TIMEOUT=${timeout} $(toolkit_cmd wait-frontend-assets)"
  echo "  (or: READY_TIMEOUT=${timeout} $(toolkit_cmd wait-ready))"
  return 1
}

# Report all-assets probe for one route. Returns 0 when every required asset OK.
_verify_frontend_assets_route() {
  local label="$1" url="$2" host="$3" port="$4"
  local probe_rc=0 line status path code bytes class tmp
  local css_n=0 js_n=0 fail_n=0

  echo
  status_line "$label" "INFO" "$url"
  tmp="$(mktemp /tmp/erpnext-dev-asset-verify.XXXXXX)"
  set +e
  probe_login_frontend_assets_all "$url" "$host" "$port" "127.0.0.1" >"$tmp"
  probe_rc=$?
  set -e

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    status="${line%%|*}"
    path="$(printf '%s' "$line" | cut -d'|' -f2)"
    code="$(printf '%s' "$line" | cut -d'|' -f3)"
    bytes="$(printf '%s' "$line" | cut -d'|' -f4)"
    class="$(printf '%s' "$line" | cut -d'|' -f6)"
    case "$path" in
      *.css) css_n=$((css_n + 1)) ;;
      *.js) js_n=$((js_n + 1)) ;;
    esac
    if [[ "$status" == "OK" ]]; then
      status_line "  ${path##*/}" "OK" "HTTP ${code} (${bytes} bytes)"
    else
      fail_n=$((fail_n + 1))
      status_line "  ${path##*/}" "FAIL" "HTTP ${code} (${class})"
    fi
  done <"$tmp"
  rm -f "$tmp"

  status_line "Required CSS" "INFO" "$css_n"
  status_line "Required JavaScript" "INFO" "$js_n"
  if ((fail_n == 0 && css_n > 0 && js_n > 0 && probe_rc == 0)); then
    status_line "Route readiness" "OK" "all required assets"
    return 0
  fi
  status_line "Route readiness" "FAIL" "${fail_n} failed asset(s) (rc=${probe_rc})"
  return 1
}

# Diagnose bare http://SITE (port 80) — the URL browsers open by default.
# Returns 0 when :80 redirects to HTTPS or serves all login assets; 1 when it
# serves /login but assets fail; 2 when :80 is not usable / not listening.
_verify_frontend_assets_port80() {
  local http_head code
  local probe_rc=0

  if ! port_listens 80; then
    status_line "Nginx :80 entry" "INFO" "port 80 not listening"
    return 2
  fi

  echo
  status_line "Nginx :80 entry" "INFO" "http://${SITE_NAME}/login"
  http_head="$(curl_head_status "http://${SITE_NAME}/login" "$SITE_NAME" 80 "127.0.0.1" || true)"
  code="$(http_status_code "$http_head")"

  if [[ "$code" =~ ^30[1278]$ ]]; then
    status_line "Port 80 behavior" "OK" "${http_head} (redirect — use https://${SITE_NAME}/login)"
    return 0
  fi

  if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    status_line "Port 80 behavior" "INFO" "${http_head} (serving without redirect)"
    if _verify_frontend_assets_route "Nginx :80 frontend" \
      "http://${SITE_NAME}/login" "$SITE_NAME" 80; then
      return 0
    fi
    status_line "Port 80 assets" "FAIL" "login HTML ok but CSS/JS missing on :80"
    echo "    Browsers that open http://${SITE_NAME} (no port) hit this broken path."
    echo "    Prefer: https://${SITE_NAME}/login  or  http://${SITE_NAME}:8000/login"
    return 1
  fi

  if [[ "$http_head" == HTTP/* ]]; then
    status_line "Port 80 behavior" "WARN" "$http_head"
  else
    status_line "Port 80 behavior" "WARN" "no response"
  fi
  return 2
}

# One-shot frontend asset status (all CSS/JS required by /login). Exit 0 when
# the primary route (HTTPS if :443, else :8000) passes. Always diagnoses both
# plus bare http:// :80 (common browser default).
verify_frontend_assets() {
  local primary_ok=0
  local primary_url=""
  local port80_rc=2

  require_site_environment >/dev/null || true

  ui_box_start "Frontend Assets"
  status_line "Site" "INFO" "${SITE_NAME}"

  if ! port_listens 443 && ! port_listens 8000; then
    status_line "Browser readiness" "FAIL" "neither :443 nor :8000 is listening"
    echo
    echo "Start the stack, then re-check:"
    echo "  $(toolkit_cmd start)"
    echo "  $(toolkit_cmd wait-ready)"
    ui_box_end
    return 1
  fi

  if port_listens 443; then
    primary_url="https://${SITE_NAME}"
    status_line "Primary URL" "INFO" "$primary_url"
    if _verify_frontend_assets_route "Nginx :443 frontend" \
      "https://${SITE_NAME}/login" "$SITE_NAME" 443; then
      primary_ok=1
    fi
  fi

  if port_listens 8000; then
    if [[ -z "$primary_url" ]]; then
      primary_url="http://${SITE_NAME}:8000"
      status_line "Primary URL" "INFO" "$primary_url"
    fi
    if _verify_frontend_assets_route "Bench :8000 frontend" \
      "http://${SITE_NAME}:8000/login" "$SITE_NAME" 8000; then
      if ! port_listens 443; then
        primary_ok=1
      fi
    elif ! port_listens 443; then
      primary_ok=0
    fi
  fi

  # If local HTTPS exists but bare http://SITE is broken, repair :80 → HTTPS
  # before the final port-80 diagnosis (common unstyled-login failure mode).
  if port_listens 443 && ssl_is_configured 2>/dev/null; then
    ensure_local_http_redirects_to_https || true
  fi

  set +e
  _verify_frontend_assets_port80
  port80_rc=$?
  set -e
  # Bare http://SITE with HTML but missing assets: treat as not browser-ready.
  if ((port80_rc == 1)); then
    primary_ok=0
  fi

  echo
  echo "Open in the HOST browser (hard refresh: Ctrl+Shift+R):"
  echo "  Preferred (Frappe local):  http://${SITE_NAME}:8000/login"
  if port_listens 443; then
    echo "  Optional HTTPS:            https://${SITE_NAME}/login"
  fi
  echo "  Avoid until verified:      http://${SITE_NAME}  (bare port 80)"
  echo "  Diagnosis:                 $(toolkit_cmd frappe-asset-checklist)"
  echo
  if ((primary_ok == 1)); then
    status_line "Browser readiness" "OK" "all required login CSS/JS"
    if ((port80_rc == 0)) && port_listens 443; then
      status_line "Default http:// URL" "OK" "port 80 redirects or serves assets"
    elif ((port80_rc == 2)) && port_listens 443; then
      status_line "Default http:// URL" "INFO" "use https://${SITE_NAME}/login (port 80 not serving)"
    fi
    ui_next "$(toolkit_cmd wait-frontend-assets)" "$(toolkit_cmd repair-frontend-assets)" "$(toolkit_cmd verify-access)"
    ui_box_end
    return 0
  fi

  status_line "Browser readiness" "FAIL" "one or more required assets failed"
  echo
  if ((port80_rc == 1)); then
    echo "Port 80 served /login without the CSS/JS that :443/:8000 have."
    echo "Use https://${SITE_NAME}/login or http://${SITE_NAME}:8000/login for now."
    echo "Then repair the HTTP→HTTPS redirect:"
    echo "  $(toolkit_cmd configure-local-ssl)"
    echo "  $(toolkit_cmd verify-frontend-assets)"
  fi
  echo "Recommended:"
  echo "  $(toolkit_cmd repair-frontend-assets)"
  echo "  $(toolkit_cmd wait-frontend-assets)"
  ui_box_end
  return 1
}

# Wait until login static assets pass (ports + HTTP + assets), same gate as wait-ready.
wait_frontend_assets() {
  wait_for_erpnext_ready "$@"
}

# Stop/start the managed runtime around an explicit asset build. Building while
# the Frappe watcher is active can race hashed bundle deletion/creation. These
# helpers intentionally do not run readiness checks; the repair transaction does
# one read-only verification after the runtime is back.
_asset_build_runtime_stop() {
  if deployment_engine_is_docker; then
    docker_compose stop || return 1
    return 0
  fi
  if runtime_is_production && production_runtime_configured; then
    $SUDO "$(supervisorctl_bin)" stop all >/dev/null 2>&1 || true
    return 0
  fi
  if service_exists; then
    $SUDO systemctl stop "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || return 1
  fi
  return 0
}

_asset_build_runtime_start() {
  if deployment_engine_is_docker; then
    docker_compose start || return 1
    return 0
  fi
  if runtime_is_production && production_runtime_configured; then
    $SUDO "$(supervisorctl_bin)" start all >/dev/null 2>&1 || return 1
    return 0
  fi
  ensure_erpnext_service_definition || return 1
  $SUDO systemctl start "${ERPNEXT_SERVICE_NAME}" || return 1
  return 0
}

# Prepare a watcher-free runtime before an explicit build while keeping Redis
# available. Frappe's build step updates assets_json through redis_cache; stopping
# the entire Bench service makes that update fail (observed in beta.1 as
# "Cannot connect to redis_cache to update assets_json"). The isolation boundary
# we need is watcher-vs-build, not Redis-vs-build.
_prepare_asset_build_runtime() {
  if deployment_engine_is_docker; then
    docker_compose start >/dev/null 2>&1 || true
    return 0
  fi
  if runtime_is_production && production_runtime_configured; then
    return 0
  fi

  ensure_erpnext_service_definition || return 1
  # Restart once so an older plain `bench start` control group (with watch) is
  # replaced by Procfile.toolkit before bench build runs.
  $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}" || return 1
  wait_for_core_runtime_ready 60 2 || return 1
  return 0
}

# Rebuild assets as an isolated watcher-free transaction. Redis and the core
# runtime stay available during bench build; verification remains read-only.
repair_frontend_assets() {
  require_sudo
  require_site_environment >/dev/null || fail "Site/bench environment is required before repairing frontend assets."

  ui_box_start "Repair frontend assets"
  status_line "Site" "INFO" "${SITE_NAME}"
  echo
  echo "Pre-repair frontend probe:"
  record_frontend_asset_failures || true
  echo

  log "Preparing watcher-free ERPNext runtime (Redis remains available)"
  _prepare_asset_build_runtime \
    || fail "Could not establish a watcher-free runtime with Redis/web ready before rebuilding assets."

  log "Building assets once with the watcher disabled"
  if ! maintenance_build; then
    fail "bench build failed; fix the build error, then retry $(toolkit_cmd repair-frontend-assets)."
  fi

  log "Clearing site cache / assets_json after isolated build"
  clear_bench_assets_json_cache || warn "cache cleanup reported an issue; continuing with verification."
  if declare -F flush_bench_redis_cache >/dev/null 2>&1; then
    flush_bench_redis_cache || warn "redis_cache FLUSHDB failed; continuing with verification"
  fi

  _soft_restart_erpnext_runtime || fail "Runtime restart failed after isolated asset rebuild."

  log "Waiting for ERPNext core runtime before frontend verification"
  if ! wait_for_core_runtime_ready 90 2; then
    status_line "Runtime" "FAIL" "web/Redis did not become ready after rebuild"
    err "Asset build completed, but the core runtime did not recover in time."
    record_frontend_asset_failures || true
    ui_box_end
    return 1
  fi

  if ssl_is_configured 2>/dev/null && port_listens 443; then
    log "Rewriting local SSL nginx (/assets from disk + HTTP→HTTPS)"
    write_local_ssl_nginx_config || true
    ensure_local_http_redirects_to_https || true
  fi

  echo
  if bench_static_assets_ready_stable; then
    status_line "Static assets" "OK" "stable login asset manifest (${ASSET_READY_STABLE_CHECKS:-3} checks)"
    ok "Frontend assets repaired and verified."
    echo "Open (Frappe local contract): http://${SITE_NAME}:8000/login"
    if port_listens 443; then
      echo "Optional HTTPS:               https://${SITE_NAME}/login"
    fi
    ui_next "$(toolkit_cmd verify-frontend-assets)" "$(toolkit_cmd verify-access)" "$(toolkit_cmd doctor)"
    ui_box_end
    return 0
  fi

  status_line "Static assets" "FAIL" "complete probe still failing after rebuild"
  err "Assets still failing after build/cache clear/runtime restart."
  record_frontend_asset_failures || true
  echo "Check: $(toolkit_cmd logs) · $(toolkit_cmd verify-frontend-assets) · $(toolkit_cmd verify-local-ssl)"
  ui_box_end
  return 1
}

ensure_bench_services_for_site_commands() {
  local context="${1:-maintenance command}"
  local bench_dir
  bench_dir="$(active_bench_dir)"

  if ! service_exists; then
    err "ERPNext service is not configured, so Bench services are not managed by this toolkit yet."
    echo
    echo "Start Bench manually as the ${FRAPPE_USER} user if you are using development mode:"
    echo "  sudo -iu ${FRAPPE_USER} bash -lc 'export PATH=\"\$HOME/.local/bin:\$PATH\"; cd ${bench_dir} && bench start'"
    return 1
  fi

  if systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}" && bench_ports_ready; then
    if bench_http_ready && bench_static_assets_ready; then
      ok "Bench services are ready for ${context} (HTTP + static assets)."
      return 0
    fi
    # Do not block mid-flow ops (clear-cache, post-restore) on a full ready wait —
    # that races asset rebuilds and broke restore CI. Surface clearly; callers that
    # need a hard gate use wait-ready / wait-frontend-assets / repair-frontend-assets.
    warn "Ports are up for ${context}, but HTTP/static assets are not ready yet."
    echo "  If the UI looks unstyled: $(toolkit_cmd repair-frontend-assets)"
    echo "  Or wait: $(toolkit_cmd wait-frontend-assets)"
    return 0
  fi

  if systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    warn "ERPNext service is active, but one or more Bench ports are not ready. Restarting before ${context}."
  else
    warn "ERPNext service is not running. Starting it before ${context}."
  fi

  if ! $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}"; then
    err "Could not restart ${ERPNEXT_SERVICE_NAME} before ${context}."
    echo "Check logs with: $(toolkit_cmd logs)"
    return 1
  fi

  wait_for_erpnext_ready
}

create_erpnext_service() {
  require_sudo

  local bench_dir
  if ! bench_dir="$(require_bench_dir)"; then
    return 1
  fi

  log "Creating ERPNext development systemd service"
  ensure_toolkit_runtime_procfile "$bench_dir" || return 1

  $SUDO tee "$(erpnext_service_path)" >/dev/null <<EOF_SERVICE
[Unit]
Description=ERPNext Frappe Bench Development Server (${SITE_NAME})
After=network-online.target mariadb.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=${FRAPPE_USER}
Group=${FRAPPE_USER}
WorkingDirectory=${bench_dir}
Environment=HOME=${FRAPPE_HOME}
ExecStart=/bin/bash -lc 'export NVM_DIR="\$HOME/.nvm"; [ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"; nvm use --silent default >/dev/null 2>&1 || true; export PATH="\$HOME/.local/bin:\$PATH"; cd "${bench_dir}" && bench start --procfile Procfile.toolkit'
Restart=on-failure
RestartSec=10
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  $SUDO systemctl daemon-reload
  ok "Service created: ${ERPNEXT_SERVICE_NAME}"
}

enable_autostart_service() {
  require_sudo

  if ! service_exists; then
    create_erpnext_service || return 1
  fi

  log "Enabling ERPNext autostart on VM boot"
  if $SUDO systemctl enable "${ERPNEXT_SERVICE_NAME}"; then
    ok "Autostart enabled"
  else
    err "Could not enable autostart for ${ERPNEXT_SERVICE_NAME}"
    return 1
  fi
}

disable_autostart_service() {
  require_sudo

  if service_exists; then
    log "Disabling ERPNext autostart"
    $SUDO systemctl disable "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
    ok "Autostart disabled"
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

start_erpnext_service() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_start
    return
  fi

  if runtime_is_production; then
    production_runtime_start
    return
  fi

  ensure_erpnext_service_definition || return 1

  log "Starting ERPNext service"
  if $SUDO systemctl start "${ERPNEXT_SERVICE_NAME}"; then
    ok "ERPNext service start command completed"
    if wait_for_erpnext_ready; then
      show_ready_summary
    else
      return 1
    fi
  else
    err "Could not start ${ERPNEXT_SERVICE_NAME}. Check logs with: $(toolkit_cmd logs)"
    return 1
  fi
}

stop_erpnext_service() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_stop
    return
  fi

  if runtime_is_production; then
    production_runtime_stop
    return
  fi

  if service_exists; then
    log "Stopping ERPNext service"
    $SUDO systemctl stop "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
    ok "ERPNext service stopped"
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    $SUDO pkill -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1 || true
    $SUDO pkill -u "$FRAPPE_USER" -f "frappe.utils.bench_helper" >/dev/null 2>&1 || true
  fi
}

restart_erpnext_service() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_restart
    return
  fi

  if runtime_is_production; then
    production_runtime_restart
    return
  fi

  ensure_erpnext_service_definition || return 1

  log "Restarting ERPNext service"
  if $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}"; then
    ok "ERPNext service restart command completed"
    if wait_for_erpnext_ready; then
      show_ready_summary
    else
      return 1
    fi
  else
    err "Could not restart ${ERPNEXT_SERVICE_NAME}. Check logs with: $(toolkit_cmd logs)"
    return 1
  fi
}

# Soft-bounce ERPNext (or docker/production runtime) without nesting
# wait_for_erpnext_ready / restart_erpnext_service (those recurse into wait).
_soft_restart_erpnext_runtime() {
  if deployment_engine_is_docker; then
    log "Restarting docker compose services"
    if declare -F docker_compose >/dev/null 2>&1; then
      docker_compose restart || return 1
      return 0
    fi
    return 1
  fi
  if declare -F runtime_is_production >/dev/null 2>&1 && runtime_is_production \
    && declare -F production_runtime_configured >/dev/null 2>&1 && production_runtime_configured; then
    log "Restarting production runtime"
    $SUDO "$(supervisorctl_bin)" restart all >/dev/null 2>&1 || return 1
    return 0
  fi
  if declare -F ensure_erpnext_service_definition >/dev/null 2>&1; then
    ensure_erpnext_service_definition || return 1
    log "Restarting ERPNext service"
    $SUDO systemctl restart "${ERPNEXT_SERVICE_NAME}" || return 1
    return 0
  fi
  return 1
}

# Clear Redis cache + bounce ERPNext (+ nginx if up) + wait-ready.
# Field (v1.19.13): assets.json on disk matched real CSS files, but HTML still
# advertised ghost CSS hashes until `redis-cli -p 13000 FLUSHDB` + restart —
# selective DEL *assets_json* was not enough (namespaced / worker-held cache).
# Must run after install (before HTTPS) and again after trusted mkcert.
settle_local_stack() {
  require_sudo
  local reason="${1:-local stack}"
  local rc=0

  echo
  if deployment_engine_is_docker; then
    log "Settling Docker stack after ${reason} (container restart + readiness)"
    _soft_restart_erpnext_runtime || rc=1
    if systemctl list-unit-files nginx.service >/dev/null 2>&1 || systemctl is-active --quiet nginx 2>/dev/null; then
      log "Restarting nginx"
      $SUDO systemctl restart nginx || rc=1
    fi
    if declare -F docker_ready >/dev/null 2>&1; then
      docker_ready || rc=1
    fi
    LOCAL_STACK_SETTLED=1
    export LOCAL_STACK_SETTLED
    if [[ "$rc" -eq 0 ]]; then
      ok "Docker stack settled after ${reason}."
    else
      warn "Docker settle after ${reason} did not fully succeed; check $(toolkit_cmd status)"
    fi
    return "$rc"
  fi

  log "Settling stack after ${reason} (FLUSHDB redis_cache + ERPNext restart)"
  echo "Required so the host browser matches VM probes (replaces guest reboot)."

  if declare -F clear_bench_assets_json_cache >/dev/null 2>&1; then
    clear_bench_assets_json_cache \
      || warn "Could not clear site/assets_json cache; continuing with redis FLUSHDB"
  fi

  if declare -F flush_bench_redis_cache >/dev/null 2>&1; then
    if flush_bench_redis_cache; then
      ok "redis_cache FLUSHDB completed"
    else
      warn "redis_cache FLUSHDB failed; ghost CSS hashes may persist until reboot"
      rc=1
    fi
  else
    warn "redis_cache FLUSHDB helper unavailable"
    rc=1
  fi

  _soft_restart_erpnext_runtime || rc=1

  if systemctl list-unit-files nginx.service >/dev/null 2>&1 \
    || systemctl is-active --quiet nginx 2>/dev/null; then
    log "Restarting nginx"
    if $SUDO systemctl restart nginx; then
      ok "nginx restarted"
    else
      warn "nginx restart failed; check: systemctl status nginx"
      rc=1
    fi
  fi

  if declare -F wait_for_erpnext_ready >/dev/null 2>&1; then
    wait_for_erpnext_ready || rc=1
  fi

  LOCAL_STACK_SETTLED=1
  export LOCAL_STACK_SETTLED
  if [[ "$rc" -eq 0 ]]; then
    ok "Stack settled after ${reason} (ready for host browser)."
  else
    warn "Settle after ${reason} did not fully succeed; check $(toolkit_cmd status)"
  fi
  return "$rc"
}

# After core install / before guided HTTPS: mandatory settle (not skippable).
settle_stack_after_install() {
  settle_local_stack "install" || return 1
  LOCAL_INSTALL_STACK_SETTLED=1
  export LOCAL_INSTALL_STACK_SETTLED
  return 0
}

# After local HTTPS nginx is written: settle again, then print browser URLs.
# Sets LOCAL_HTTPS_STACK_SETTLED=1 so the guided checkpoint can skip a duplicate.
settle_stack_after_local_https() {
  settle_local_stack "local HTTPS" || {
    LOCAL_HTTPS_STACK_SETTLED=1
    export LOCAL_HTTPS_STACK_SETTLED
    return 1
  }
  LOCAL_HTTPS_STACK_SETTLED=1
  export LOCAL_HTTPS_STACK_SETTLED
  return 0
}

show_erpnext_service_status() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_status
    return
  fi

  if runtime_is_production; then
    show_production_runtime_status
    return
  fi

  if service_exists; then
    $SUDO systemctl status "${ERPNEXT_SERVICE_NAME}" --no-pager || true
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

show_erpnext_service_logs() {
  require_sudo

  if deployment_engine_is_docker; then
    docker_runtime_logs
    return
  fi

  if runtime_is_production; then
    show_production_runtime_logs
    return
  fi

  if service_exists; then
    $SUDO journalctl -u "${ERPNEXT_SERVICE_NAME}" -n 160 --no-pager || true
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

follow_erpnext_service_logs() {
  require_sudo

  if service_exists; then
    $SUDO journalctl -u "${ERPNEXT_SERVICE_NAME}" -f
  else
    warn "Service does not exist yet: ${ERPNEXT_SERVICE_NAME}"
  fi
}

install_state() {
  local bench_dir
  if declare -F deployment_engine_is_docker >/dev/null 2>&1 && deployment_engine_is_docker; then
    # Preserve the long-standing install_state contract: callers and health
    # snapshots expect the exact string "Installed". Runtime state is reported
    # separately by runtime_state(), so a stopped Docker stack is still installed.
    if [[ -f "${DOCKER_WORKDIR:-/opt/erpnext-dev/docker}/frappe_docker/pwd.yml" ||
      -f "${DOCKER_WORKDIR:-/opt/erpnext-dev/docker}/frappe_docker/compose.yaml" ]]; then
      echo "Installed"
    else
      echo "Not installed"
    fi
    return
  fi
  bench_dir="$(active_bench_dir)"

  if path_is_dir "${bench_dir}" && path_is_dir "${bench_dir}/apps/frappe" && path_is_dir "${bench_dir}/apps/erpnext" && path_is_dir "${bench_dir}/sites/${SITE_NAME}"; then
    if site_app_installed erpnext || [[ -f "${bench_dir}/sites/apps.txt" ]]; then
      echo "Installed"
    else
      echo "Installed files found; site app not confirmed"
    fi
  elif path_is_dir "${bench_dir}" || path_is_dir "${FRAPPE_HOME}"; then
    echo "Incomplete"
  else
    echo "Not installed"
  fi
}

runtime_state() {
  local ready_count cid state
  if declare -F deployment_engine_is_docker >/dev/null 2>&1 && deployment_engine_is_docker; then
    if declare -F docker_compose >/dev/null 2>&1; then
      cid="$(docker_compose ps -q frontend 2>/dev/null | tail -n1 || true)"
      if [[ -n "$cid" ]]; then
        state="$(${SUDO:-} docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
        if [[ "$state" == "running" ]]; then
          echo "Running via Docker ($(docker_mode_label 2>/dev/null || echo stack))"
        else
          echo "Stopped (Docker; frontend ${state})"
        fi
      else
        echo "Stopped (Docker)"
      fi
    else
      echo "Stopped (Docker; Compose unavailable)"
    fi
    return
  fi
  ready_count="$(bench_ready_count)"

  if runtime_is_production; then
    if production_runtime_configured && production_processes_running && bench_ports_ready; then
      echo "Running via supervisor (production)"
    elif production_runtime_configured && production_processes_running; then
      echo "Starting via supervisor (production)"
    elif production_runtime_configured; then
      echo "Stopped (production/supervisor)"
    else
      echo "Production runtime not set up"
    fi
    return
  fi

  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    if bench_ports_ready; then
      echo "Running via service"
    elif [[ "$ready_count" -gt 0 ]]; then
      echo "Starting / partially ready via service"
    else
      echo "Starting via service"
    fi
  elif port_listens 8000; then
    echo "Running in foreground"
  elif id "$FRAPPE_USER" >/dev/null 2>&1 && pgrep -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1; then
    echo "Starting / partially running"
  else
    echo "Stopped"
  fi
}

autostart_state() {
  if service_exists && systemctl is-enabled --quiet "${ERPNEXT_SERVICE_NAME}" 2>/dev/null; then
    echo "Enabled"
  elif service_exists; then
    echo "Disabled"
  else
    echo "Not configured"
  fi
}

service_state() {
  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    echo "Running"
  elif service_exists; then
    echo "Stopped"
  else
    echo "Not configured"
  fi
}

run_start() {
  require_sudo
  start_erpnext_service
}

run_stop() {
  require_sudo
  stop_erpnext_service
}

run_foreground_start() {
  require_sudo

  if service_exists && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}"; then
    warn "ERPNext service is already running in the background."
    if ! confirm "Start a foreground bench session anyway?"; then
      return 0
    fi
  fi

  start_erpnext_foreground
}

show_service_menu() {
  while true; do
    ui_submenu_header "Autostart / Service Manager" "systemd service control"
    print_two_column_menu \
      "1) Enable autostart on VM boot" \
      "2) Disable autostart" \
      "3) Start ERPNext service" \
      "4) Stop ERPNext service" \
      "5) Restart ERPNext service" \
      "6) Show service status" \
      "7) Show recent service logs" \
      "8) Follow service logs"
    ui_submenu_footer
    local service_choice=""
    menu_read_choice service_choice

    case "$service_choice" in
      1)
        enable_autostart_service
        pause_after_screen "Press Enter to return to Service Manager..."
        ;;
      2)
        disable_autostart_service
        pause_after_screen "Press Enter to return to Service Manager..."
        ;;
      3)
        start_erpnext_service
        pause_after_screen "Press Enter to return to Service Manager..."
        ;;
      4)
        stop_erpnext_service
        pause_after_screen "Press Enter to return to Service Manager..."
        ;;
      5)
        restart_erpnext_service
        pause_after_screen "Press Enter to return to Service Manager..."
        ;;
      6)
        show_erpnext_service_status
        pause_after_screen "Press Enter to return to Service Manager..."
        ;;
      7)
        show_erpnext_service_logs
        pause_after_screen "Press Enter to return to Service Manager..."
        ;;
      8)
        follow_erpnext_service_logs
        pause_after_screen "Press Enter to return to Service Manager..."
        ;;
      b | B | "") return 0 ;;
      q | Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

# ============================================================
# Production runtime (supervisor: gunicorn + workers + scheduler + socket.io)
#
# In production the toolkit does NOT use `bench start` (a development server
# with a live-reload watcher and debugger). Instead it uses Frappe's own
# `bench setup supervisor` to generate the correct, version-matched process set
# and runs it under supervisord. The toolkit's existing Nginx/TLS layer stays in
# front, proxying :443/:80 to gunicorn (:8000) and socket.io (:9000) exactly as
# it already does for the dev runtime.
# ============================================================

supervisor_conf_link() {
  echo "/etc/supervisor/conf.d/frappe-bench.conf"
}

supervisorctl_bin() {
  command -v supervisorctl 2>/dev/null || echo /usr/bin/supervisorctl
}

production_runtime_configured() {
  [[ -L "$(supervisor_conf_link)" || -f "$(supervisor_conf_link)" ]]
}

production_supervisor_status() {
  $SUDO "$(supervisorctl_bin)" status 2>/dev/null || true
}

production_processes_running() {
  production_supervisor_status | grep -q "RUNNING"
}

# HTTP-level readiness: gunicorn must actually answer, not just listen.
bench_http_ready() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${SITE_NAME}" \
    "http://127.0.0.1:8000/api/method/ping" 2>/dev/null || echo 000)"
  [[ "$code" == "200" ]]
}

production_runtime_start() {
  require_sudo
  if ! production_runtime_configured; then
    err "Production runtime is not set up. Run: $(toolkit_cmd setup-production-runtime)"
    return 1
  fi
  log "Starting production runtime (supervisor)"
  $SUDO "$(supervisorctl_bin)" start all >/dev/null 2>&1 || true
  if wait_for_erpnext_ready; then
    show_ready_summary
  else
    return 1
  fi
}

production_runtime_stop() {
  require_sudo
  log "Stopping production runtime (supervisor)"
  $SUDO "$(supervisorctl_bin)" stop all >/dev/null 2>&1 || true
  ok "Production processes stopped."
}

production_runtime_restart() {
  require_sudo
  if ! production_runtime_configured; then
    err "Production runtime is not set up. Run: $(toolkit_cmd setup-production-runtime)"
    return 1
  fi
  log "Restarting production runtime (supervisor)"
  $SUDO "$(supervisorctl_bin)" restart all >/dev/null 2>&1 || true
  if wait_for_erpnext_ready; then
    show_ready_summary
  else
    return 1
  fi
}

show_production_runtime_logs() {
  require_sudo
  local bench_dir logf
  bench_dir="$(active_bench_dir)"

  echo "Supervisor programs:"
  production_supervisor_status
  echo
  for logf in web.error.log web.log worker.error.log worker.log schedule.log; do
    if [[ -f "${bench_dir}/logs/${logf}" ]]; then
      echo "== ${bench_dir}/logs/${logf} (last 40 lines) =="
      $SUDO tail -n 40 "${bench_dir}/logs/${logf}" 2>/dev/null || true
      echo
    fi
  done
}

show_production_runtime_status() {
  require_sudo
  ui_box_start "Production Runtime Status"
  status_line "Runtime mode" "INFO" "$(runtime_mode)"
  status_line "Supervisor config" "$(production_runtime_configured && echo OK || echo WARN)" "$(supervisor_conf_link)"
  status_line "Web (gunicorn) :8000" "$(port_listens 8000 && echo OK || echo WARN)" "backend web workers"
  status_line "Socket.IO :9000" "$(port_listens 9000 && echo OK || echo WARN)" "realtime"
  status_line "HTTP ping" "$(bench_http_ready && echo OK || echo WARN)" "http://127.0.0.1:8000/api/method/ping"
  status_line "Static assets" "$(bench_static_assets_ready && echo OK || echo WARN)" "login CSS/JS Link probe"
  echo
  echo "Supervisor programs:"
  production_supervisor_status
  ui_box_end
}

# Convert an existing install from the dev bench-start runtime to a supervisor
# managed production runtime. Idempotent: safe to re-run.
setup_production_runtime() {
  require_sudo
  local bench_dir
  bench_dir="$(require_bench_dir)" || return 1

  if [[ "$(install_state)" != Installed* ]]; then
    err "ERPNext is not fully installed yet. Run the install first: $(toolkit_cmd install)"
    return 1
  fi

  ui_box_start "Set up production runtime (supervisor)"

  log "Installing supervisor package"
  if ! command -v supervisorctl >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y >/dev/null 2>&1 || true
    if ! DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y supervisor >/dev/null 2>&1; then
      err "Could not install the supervisor package."
      ui_box_end
      return 1
    fi
  fi
  $SUDO systemctl enable --now supervisor >/dev/null 2>&1 || true

  log "Generating supervisor config from bench (bench setup supervisor)"
  if ! frappe_login_bash <<EOF_PROD; then
set -Eeuo pipefail
export PATH="\$HOME/.local/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
cd "${bench_dir}"
bench setup supervisor --user "${FRAPPE_USER}" --yes
EOF_PROD
    err "bench setup supervisor failed. See the output above."
    ui_box_end
    return 1
  fi

  if [[ -f "${bench_dir}/config/supervisor.conf" ]]; then
    $SUDO ln -sf "${bench_dir}/config/supervisor.conf" "$(supervisor_conf_link)"
    ok "Linked supervisor config -> $(supervisor_conf_link)"
  else
    err "Expected ${bench_dir}/config/supervisor.conf was not generated."
    ui_box_end
    return 1
  fi

  # Stop and disable the development bench-start service; production must never
  # silently fall back to the dev server.
  if service_exists; then
    log "Disabling development bench-start service"
    $SUDO systemctl disable --now "${ERPNEXT_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
  if declare -F terminate_bench_reference_processes >/dev/null 2>&1; then
    terminate_bench_reference_processes || warn "Some development Bench processes required forced cleanup before production conversion."
  elif id "$FRAPPE_USER" >/dev/null 2>&1; then
    # Compatibility fallback for unusual partial module loads. Normal toolkit
    # execution uses the path-scoped helper from lib/install.sh.
    $SUDO pkill -u "$FRAPPE_USER" -f "bench start" >/dev/null 2>&1 || true
  fi

  # shellcheck disable=SC2034 # cross-module global read via runtime_mode()/config.sh
  RUNTIME_MODE="production"
  write_dev_config_file

  log "Reloading supervisor"
  $SUDO "$(supervisorctl_bin)" reread >/dev/null 2>&1 || true
  $SUDO "$(supervisorctl_bin)" update >/dev/null 2>&1 || true
  $SUDO "$(supervisorctl_bin)" start all >/dev/null 2>&1 || true

  if wait_for_erpnext_ready; then
    ok "Production runtime active: gunicorn + workers + scheduler + socket.io under supervisor."
  else
    warn "Production processes were started but readiness did not pass yet."
    echo "  Inspect with: $(toolkit_cmd production-runtime-status)"
  fi

  echo
  echo "The development bench-start service is now disabled; ERPNext runs under supervisor."
  echo "Nginx/TLS remain managed by the toolkit (proxying to 127.0.0.1:8000 / :9000)."
  echo "Manage the runtime with: $(toolkit_cmd service-status) / $(toolkit_cmd restart) / $(toolkit_cmd logs)"
  ui_box_end
}

run_setup_production_runtime() {
  require_sudo
  if runtime_is_production && production_runtime_configured; then
    warn "Production runtime already configured. Re-running to refresh the supervisor config."
  fi
  setup_production_runtime
}

# Revert from the supervisor production runtime back to the dev bench-start
# service. Does not touch the database or apps.
convert_to_dev_runtime() {
  require_sudo
  require_bench_dir >/dev/null || return 1

  ui_box_start "Convert back to development runtime (bench start)"

  if production_runtime_configured; then
    log "Stopping supervisor-managed processes"
    $SUDO "$(supervisorctl_bin)" stop all >/dev/null 2>&1 || true
    $SUDO rm -f "$(supervisor_conf_link)"
    $SUDO "$(supervisorctl_bin)" reread >/dev/null 2>&1 || true
    $SUDO "$(supervisorctl_bin)" update >/dev/null 2>&1 || true
    ok "Removed the supervisor program group."
  fi

  # shellcheck disable=SC2034 # cross-module global read via runtime_mode()/config.sh
  RUNTIME_MODE="dev"
  write_dev_config_file

  if create_erpnext_service; then
    ok "Development runtime restored. Start it with: $(toolkit_cmd start)"
  else
    ui_box_end
    return 1
  fi
  ui_box_end
}

run_convert_to_dev_runtime() {
  require_sudo
  convert_to_dev_runtime
}
