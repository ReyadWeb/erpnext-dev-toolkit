# shellcheck shell=bash
# Canonical health snapshot and Operations Dashboard (v1.16).
# Read-only: no auto-healing. See docs/HEALTH-ARCHITECTURE.md.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_DASHBOARD_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_DASHBOARD_LOADED=1

: "${HEALTH_DISK_DEGRADED_PERCENT:=80}"
: "${HEALTH_DISK_CRITICAL_PERCENT:=90}"
: "${HEALTH_INODE_DEGRADED_PERCENT:=80}"
: "${HEALTH_INODE_CRITICAL_PERCENT:=90}"
: "${HEALTH_MEM_AVAILABLE_DEGRADED_PERCENT:=15}"
: "${HEALTH_MEM_AVAILABLE_CRITICAL_PERCENT:=5}"
: "${HEALTH_BACKUP_DEGRADED_HOURS:=30}"
: "${HEALTH_BACKUP_CRITICAL_HOURS:=48}"
: "${HEALTH_REHEARSAL_DEGRADED_DAYS:=30}"
: "${HEALTH_HTTPS_DEGRADED_DAYS:=30}"
: "${HEALTH_HTTPS_CRITICAL_DAYS:=7}"
: "${HEALTH_HTTP_TIMEOUT_SEC:=5}"
: "${HEALTH_LIB_DIR:=/var/lib/erpnext-dev}"

# --- Status model ------------------------------------------------------------

health_status_rank() {
  case "${1:-UNKNOWN}" in
    CRITICAL|critical) printf '3' ;;
    DEGRADED|degraded|WARN|warn|FAIL|fail) printf '2' ;;
    UNKNOWN|unknown) printf '1' ;;
    HEALTHY|healthy|OK|ok|INFO|info) printf '0' ;;
    *) printf '1' ;;
  esac
}

health_status_normalize() {
  case "${1:-UNKNOWN}" in
    CRITICAL|critical|FAIL|fail) printf 'CRITICAL' ;;
    DEGRADED|degraded|WARN|warn) printf 'DEGRADED' ;;
    UNKNOWN|unknown) printf 'UNKNOWN' ;;
    HEALTHY|healthy|OK|ok|INFO|info) printf 'HEALTHY' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

# Print the worse of two normalized statuses.
health_status_worst() {
  local a b ra rb
  a="$(health_status_normalize "${1:-UNKNOWN}")"
  b="$(health_status_normalize "${2:-UNKNOWN}")"
  ra="$(health_status_rank "$a")"
  rb="$(health_status_rank "$b")"
  if (( ra >= rb )); then
    printf '%s' "$a"
  else
    printf '%s' "$b"
  fi
}

health_status_glyph() {
  case "$(health_status_normalize "${1:-UNKNOWN}")" in
    HEALTHY) printf '*' ;;
    DEGRADED) printf '!' ;;
    CRITICAL) printf 'X' ;;
    *) printf '?' ;;
  esac
}

health_legacy_ok_warn() {
  case "$(health_status_normalize "${1:-UNKNOWN}")" in
    HEALTHY) printf 'OK' ;;
    CRITICAL) printf 'FAIL' ;;
    DEGRADED) printf 'WARN' ;;
    *) printf 'WARN' ;;
  esac
}

# --- Host probes (Layer 1) ---------------------------------------------------

health_probe_disk() {
  local pct status detail
  pct="$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5+0}')"
  if [[ ! "$pct" =~ ^[0-9]+$ ]]; then
    printf 'UNKNOWN|unable to read root disk usage|0'
    return 0
  fi
  detail="${pct}% used"
  if (( pct >= HEALTH_DISK_CRITICAL_PERCENT )); then
    status="CRITICAL"
  elif (( pct >= HEALTH_DISK_DEGRADED_PERCENT )); then
    status="DEGRADED"
  else
    status="HEALTHY"
  fi
  printf '%s|%s|%s' "$status" "$detail" "$pct"
}

health_probe_inodes() {
  local pct status detail
  pct="$(df -Pi / 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5+0}')"
  if [[ ! "$pct" =~ ^[0-9]+$ ]]; then
    printf 'UNKNOWN|unable to read inode usage|0'
    return 0
  fi
  detail="${pct}% inodes used"
  if (( pct >= HEALTH_INODE_CRITICAL_PERCENT )); then
    status="CRITICAL"
  elif (( pct >= HEALTH_INODE_DEGRADED_PERCENT )); then
    status="DEGRADED"
  else
    status="HEALTHY"
  fi
  printf '%s|%s|%s' "$status" "$detail" "$pct"
}

health_probe_memory() {
  local mem_total mem_available pct_avail status detail
  mem_total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  mem_available="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ ! "$mem_total" =~ ^[0-9]+$ || "$mem_total" -le 0 || ! "$mem_available" =~ ^[0-9]+$ ]]; then
    printf 'UNKNOWN|MemAvailable unavailable|0|0|0'
    return 0
  fi
  pct_avail=$(( (mem_available * 100) / mem_total ))
  detail="available ${pct_avail}% ($(awk -v k="$mem_available" 'BEGIN{printf "%.1f", k/1024/1024}')G / $(awk -v k="$mem_total" 'BEGIN{printf "%.1f", k/1024/1024}')G)"
  if (( pct_avail <= HEALTH_MEM_AVAILABLE_CRITICAL_PERCENT )); then
    status="CRITICAL"
  elif (( pct_avail <= HEALTH_MEM_AVAILABLE_DEGRADED_PERCENT )); then
    status="DEGRADED"
  else
    status="HEALTHY"
  fi
  printf '%s|%s|%s|%s|%s' "$status" "$detail" "$pct_avail" "$mem_available" "$mem_total"
}

health_probe_swap() {
  local swap_total swap_free used_pct status detail
  swap_total="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  swap_free="$(awk '/^SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ ! "$swap_total" =~ ^[0-9]+$ ]]; then
    printf 'UNKNOWN|swap unavailable|0'
    return 0
  fi
  if (( swap_total == 0 )); then
    printf 'HEALTHY|no swap configured|0'
    return 0
  fi
  used_pct=$(( ((swap_total - swap_free) * 100) / swap_total ))
  detail="${used_pct}% swap used"
  if (( used_pct >= 75 )); then
    status="CRITICAL"
  elif (( used_pct >= 40 )); then
    status="DEGRADED"
  else
    status="HEALTHY"
  fi
  printf '%s|%s|%s' "$status" "$detail" "$used_pct"
}

health_probe_load() {
  local load1 cores per_core status detail
  load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "")"
  cores="$(nproc 2>/dev/null || echo 1)"
  [[ "$cores" =~ ^[0-9]+$ && "$cores" -gt 0 ]] || cores=1
  if [[ -z "$load1" ]]; then
    printf 'UNKNOWN|loadavg unavailable|0|%s' "$cores"
    return 0
  fi
  per_core="$(awk -v l="$load1" -v c="$cores" 'BEGIN{printf "%.2f", l/c}')"
  detail="load1 ${load1} / ${cores} cores (${per_core}/core)"
  if awk -v p="$per_core" 'BEGIN{exit !(p >= 2.0)}'; then
    status="CRITICAL"
  elif awk -v p="$per_core" 'BEGIN{exit !(p >= 1.0)}'; then
    status="DEGRADED"
  else
    status="HEALTHY"
  fi
  printf '%s|%s|%s|%s' "$status" "$detail" "$load1" "$cores"
}

health_probe_uptime() {
  local seconds days
  seconds="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
  if [[ ! "$seconds" =~ ^[0-9]+$ || "$seconds" -le 0 ]]; then
    printf 'UNKNOWN|uptime unavailable|0'
    return 0
  fi
  days=$(( seconds / 86400 ))
  printf 'HEALTHY|%sd uptime|%s' "$days" "$seconds"
}

health_probe_reboot_required() {
  if [[ -f /var/run/reboot-required ]]; then
    printf 'DEGRADED|reboot required'
  else
    printf 'HEALTHY|no reboot required'
  fi
}

# --- Application / engine probes (Layers 2–3) --------------------------------

health_probe_http() {
  local url ms code status detail curl_out
  if is_public_vm_workflow 2>/dev/null && [[ -n "${PRODUCTION_DOMAIN:-${SITE_NAME:-}}" ]]; then
    url="https://${PRODUCTION_DOMAIN:-$SITE_NAME}/api/method/ping"
  elif port_listens 443 2>/dev/null && [[ -n "${SITE_NAME:-}" ]]; then
    url="https://${SITE_NAME}/api/method/ping"
  else
    url="http://127.0.0.1:8000/api/method/ping"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf 'UNKNOWN|curl not available|0|0'
    return 0
  fi

  curl_out="$(curl -k -sS -o /dev/null -w '%{http_code} %{time_total}' \
    --connect-timeout "${HEALTH_HTTP_TIMEOUT_SEC}" \
    --max-time "${HEALTH_HTTP_TIMEOUT_SEC}" \
    "$url" 2>/dev/null || echo '000 0')"
  code="$(awk '{print $1}' <<<"$curl_out")"
  ms="$(awk '{printf "%d", ($2+0)*1000}' <<<"$curl_out")"
  [[ "$ms" =~ ^[0-9]+$ ]] || ms=0

  if [[ "$code" =~ ^2 ]]; then
    if (( ms >= 4000 )); then
      status="DEGRADED"
      detail="HTTP ${code} in ${ms}ms (slow)"
    else
      status="HEALTHY"
      detail="HTTP ${code} in ${ms}ms"
    fi
  elif [[ "$code" == "000" ]]; then
    status="CRITICAL"
    detail="HTTP unreachable (${url})"
  else
    status="CRITICAL"
    detail="HTTP ${code} (${url})"
  fi
  printf '%s|%s|%s|%s' "$status" "$detail" "$code" "$ms"
}

health_probe_port() {
  local port="$1" label="$2"
  if port_listens "$port" 2>/dev/null; then
    printf 'HEALTHY|%s port %s listening' "$label" "$port"
  else
    printf 'CRITICAL|%s port %s not listening' "$label" "$port"
  fi
}

health_probe_systemd_unit() {
  local unit="$1" label="$2" pair
  pair="$(systemd_service_active_detail "$unit" 2>/dev/null || echo 'WARN|unknown')"
  case "${pair%%|*}" in
    OK) printf 'HEALTHY|%s %s' "$label" "${pair#*|}" ;;
    WARN) printf 'DEGRADED|%s %s' "$label" "${pair#*|}" ;;
    *) printf 'UNKNOWN|%s %s' "$label" "${pair#*|}" ;;
  esac
}

health_probe_native_runtime() {
  local overall="HEALTHY" detail="" p
  if service_exists 2>/dev/null && systemctl is-active --quiet "${ERPNEXT_SERVICE_NAME}" 2>/dev/null; then
    detail="service running"
  elif deployment_engine_is_docker 2>/dev/null; then
    printf 'UNKNOWN|native service N/A (docker engine)'
    return 0
  else
    overall="CRITICAL"
    detail="ERPNext service not running"
  fi
  p="$(health_probe_systemd_unit nginx.service Nginx)"
  overall="$(health_status_worst "$overall" "${p%%|*}")"
  p="$(health_probe_systemd_unit mariadb.service MariaDB)"
  overall="$(health_status_worst "$overall" "${p%%|*}")"
  p="$(health_probe_systemd_unit redis-server.service Redis)"
  overall="$(health_status_worst "$overall" "${p%%|*}")"
  printf '%s|%s' "$overall" "$detail"
}

health_probe_docker_runtime() {
  local running total unhealthy status detail
  if ! deployment_engine_is_docker 2>/dev/null; then
    printf 'UNKNOWN|docker engine not active|0|0'
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    printf 'CRITICAL|docker CLI missing|0|0'
    return 0
  fi
  running="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
  total="$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"
  unhealthy="$(docker ps --filter health=unhealthy -q 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$running" =~ ^[0-9]+$ ]] || running=0
  [[ "$total" =~ ^[0-9]+$ ]] || total=0
  [[ "$unhealthy" =~ ^[0-9]+$ ]] || unhealthy=0
  if (( total == 0 )); then
    status="CRITICAL"
    detail="no containers"
  elif (( unhealthy > 0 )); then
    status="CRITICAL"
    detail="${running}/${total} running; ${unhealthy} unhealthy"
  elif (( running < total )); then
    status="DEGRADED"
    detail="${running}/${total} running"
  else
    status="HEALTHY"
    detail="${running}/${total} containers healthy/running"
  fi
  printf '%s|%s|%s|%s' "$status" "$detail" "$running" "$total"
}

# --- Protection / DR (Layer 4) -----------------------------------------------

health_probe_https() {
  local pair status detail
  if is_public_vm_workflow 2>/dev/null; then
    pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not confirmed')"
  else
    pair="INFO|local mode; production HTTPS not required"
  fi
  status="$(health_status_normalize "${pair%%|*}")"
  detail="${pair#*|}"
  [[ "${pair%%|*}" == "INFO" ]] && status="HEALTHY"
  printf '%s|%s' "$status" "$detail"
}

health_probe_firewall() {
  if declare -F ufw_is_active >/dev/null 2>&1 && ufw_is_active; then
    printf 'HEALTHY|UFW active'
  else
    printf 'DEGRADED|UFW not active'
  fi
}

health_probe_fail2ban() {
  if command -v fail2ban-client >/dev/null 2>&1 && ${SUDO:-sudo} fail2ban-client status sshd >/dev/null 2>&1; then
    printf 'HEALTHY|sshd jail enabled'
  else
    printf 'DEGRADED|sshd jail not confirmed'
  fi
}

health_probe_local_backup() {
  local latest_lines completeness age status detail
  latest_lines="$(backup_latest_set_paths 2>/dev/null || true)"
  if [[ -n "$latest_lines" ]]; then
    completeness="$(printf '%s\n' "$latest_lines" | sed -n '6p')"
  else
    completeness="none"
  fi
  age="$(health_backup_age_hours 2>/dev/null || echo unknown)"
  if [[ "$completeness" != "complete" ]]; then
    printf 'CRITICAL|no complete local backup|%s' "$age"
    return 0
  fi
  detail="complete"
  if [[ "$age" =~ ^[0-9]+$ ]]; then
    detail="complete; ${age}h old"
    if (( age > HEALTH_BACKUP_CRITICAL_HOURS )); then
      status="CRITICAL"
    elif (( age > HEALTH_BACKUP_DEGRADED_HOURS )); then
      status="DEGRADED"
    else
      status="HEALTHY"
    fi
  else
    status="DEGRADED"
  fi
  printf '%s|%s|%s' "$status" "$detail" "$age"
}

health_probe_off_vm_backup() {
  local pair
  if declare -F off_vm_backup_configured >/dev/null 2>&1 && off_vm_backup_configured; then
    pair="$(off_vm_backup_summary_pair 2>/dev/null || echo 'DEGRADED|configured; status unknown')"
    printf '%s|%s' "$(health_status_normalize "${pair%%|*}")" "${pair#*|}"
  else
    printf 'UNKNOWN|not configured'
  fi
}

health_probe_object_backup() {
  local pair
  if declare -F object_backup_summary_pair >/dev/null 2>&1; then
    pair="$(object_backup_summary_pair 2>/dev/null || echo 'UNKNOWN|unavailable')"
    printf '%s|%s' "$(health_status_normalize "${pair%%|*}")" "${pair#*|}"
  elif [[ -f /etc/erpnext-dev/object-backup.env ]] || [[ -f /etc/erpnext-dev/docker-object-backup.env ]]; then
    printf 'DEGRADED|configured; run object-status for details'
  else
    printf 'UNKNOWN|not configured'
  fi
}

health_probe_restore_rehearsal() {
  local pair status detail recorded age_days now epoch
  pair="$(restore_rehearsal_summary_pair 2>/dev/null || echo 'WARN|not recorded')"
  status="$(health_status_normalize "${pair%%|*}")"
  detail="${pair#*|}"
  if [[ "$detail" == *"not recorded"* || "$detail" == *"never"* ]]; then
    printf 'CRITICAL|never tested'
    return 0
  fi
  recorded="$(grep -E '^REHEARSAL_RECORDED_AT=' /etc/erpnext-dev/restore-rehearsal.env 2>/dev/null | cut -d= -f2- || true)"
  if [[ -n "$recorded" ]]; then
    epoch="$(date -d "$recorded" +%s 2>/dev/null || echo 0)"
    now="$(date +%s)"
    if [[ "$epoch" =~ ^[0-9]+$ && "$epoch" -gt 0 ]]; then
      age_days=$(( (now - epoch) / 86400 ))
      detail="${detail}; ${age_days}d ago"
      if (( age_days > HEALTH_REHEARSAL_DEGRADED_DAYS )); then
        status="DEGRADED"
      fi
    fi
  fi
  printf '%s|%s' "$status" "$detail"
}

health_probe_toolkit_integrity() {
  if [[ -f "${_ERPNEXT_DEV_ROOT:-.}/SHA256SUMS" ]] || [[ -f /opt/erpnext-dev/SHA256SUMS ]]; then
    printf 'HEALTHY|checksum file present (run verify-toolkit for full check)'
  else
    printf 'DEGRADED|SHA256SUMS not found beside toolkit'
  fi
}

# --- Snapshot assembly -------------------------------------------------------

# Populate global SNAPSHOT_* variables used by JSON/CLI renderers.
health_snapshot_collect() {
  local pair overall="HEALTHY" engine_label install_value runtime_value

  SNAPSHOT_SCHEMA_VERSION="1"
  SNAPSHOT_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  SNAPSHOT_SITE="${PRODUCTION_DOMAIN:-${SITE_NAME:-unknown}}"
  SNAPSHOT_ENGINE="$(effective_deployment_engine 2>/dev/null || echo native)"
  engine_label="$(deployment_engine_label 2>/dev/null || echo "$SNAPSHOT_ENGINE")"
  SNAPSHOT_ENGINE_LABEL="$engine_label"
  SNAPSHOT_OS="$(. /etc/os-release 2>/dev/null; echo "${NAME:-Linux} ${VERSION_ID:-}")"
  SNAPSHOT_TOOLKIT_VERSION="${SCRIPT_VERSION:-unknown}"
  install_value="$(install_state 2>/dev/null || echo Unknown)"
  runtime_value="$(runtime_state 2>/dev/null || echo Unknown)"
  SNAPSHOT_INSTALL="$install_value"
  SNAPSHOT_RUNTIME="$runtime_value"

  pair="$(health_probe_disk)"; SNAPSHOT_DISK_STATUS="${pair%%|*}"; SNAPSHOT_DISK_DETAIL="$(echo "$pair" | cut -d'|' -f2)"; SNAPSHOT_DISK_PERCENT="$(echo "$pair" | cut -d'|' -f3)"
  pair="$(health_probe_inodes)"; SNAPSHOT_INODE_STATUS="${pair%%|*}"; SNAPSHOT_INODE_DETAIL="$(echo "$pair" | cut -d'|' -f2)"; SNAPSHOT_INODE_PERCENT="$(echo "$pair" | cut -d'|' -f3)"
  pair="$(health_probe_memory)"; SNAPSHOT_MEM_STATUS="${pair%%|*}"; SNAPSHOT_MEM_DETAIL="$(echo "$pair" | cut -d'|' -f2)"; SNAPSHOT_MEM_AVAIL_PCT="$(echo "$pair" | cut -d'|' -f3)"; SNAPSHOT_MEM_AVAILABLE_KB="$(echo "$pair" | cut -d'|' -f4)"; SNAPSHOT_MEM_TOTAL_KB="$(echo "$pair" | cut -d'|' -f5)"
  pair="$(health_probe_swap)"; SNAPSHOT_SWAP_STATUS="${pair%%|*}"; SNAPSHOT_SWAP_DETAIL="$(echo "$pair" | cut -d'|' -f2)"; SNAPSHOT_SWAP_PERCENT="$(echo "$pair" | cut -d'|' -f3)"
  pair="$(health_probe_load)"; SNAPSHOT_LOAD_STATUS="${pair%%|*}"; SNAPSHOT_LOAD_DETAIL="$(echo "$pair" | cut -d'|' -f2)"; SNAPSHOT_LOAD1="$(echo "$pair" | cut -d'|' -f3)"; SNAPSHOT_CORES="$(echo "$pair" | cut -d'|' -f4)"
  pair="$(health_probe_uptime)"; SNAPSHOT_UPTIME_STATUS="${pair%%|*}"; SNAPSHOT_UPTIME_DETAIL="$(echo "$pair" | cut -d'|' -f2)"; SNAPSHOT_UPTIME_SEC="$(echo "$pair" | cut -d'|' -f3)"
  pair="$(health_probe_reboot_required)"; SNAPSHOT_REBOOT_STATUS="${pair%%|*}"; SNAPSHOT_REBOOT_DETAIL="${pair#*|}"

  pair="$(health_probe_http)"; SNAPSHOT_HTTP_STATUS="${pair%%|*}"; SNAPSHOT_HTTP_DETAIL="$(echo "$pair" | cut -d'|' -f2)"; SNAPSHOT_HTTP_CODE="$(echo "$pair" | cut -d'|' -f3)"; SNAPSHOT_HTTP_MS="$(echo "$pair" | cut -d'|' -f4)"
  pair="$(health_probe_port 8000 'Bench web')"; SNAPSHOT_WEB_PORT_STATUS="${pair%%|*}"; SNAPSHOT_WEB_PORT_DETAIL="${pair#*|}"
  pair="$(health_probe_port 9000 'Socket.IO')"; SNAPSHOT_SOCKET_STATUS="${pair%%|*}"; SNAPSHOT_SOCKET_DETAIL="${pair#*|}"
  pair="$(health_probe_systemd_unit mariadb.service MariaDB)"; SNAPSHOT_DB_STATUS="${pair%%|*}"; SNAPSHOT_DB_DETAIL="${pair#*|}"
  pair="$(health_probe_systemd_unit redis-server.service Redis)"; SNAPSHOT_REDIS_STATUS="${pair%%|*}"; SNAPSHOT_REDIS_DETAIL="${pair#*|}"

  if deployment_engine_is_docker 2>/dev/null; then
    pair="$(health_probe_docker_runtime)"
    SNAPSHOT_RUNTIME_LAYER_STATUS="${pair%%|*}"
    SNAPSHOT_RUNTIME_LAYER_DETAIL="$(echo "$pair" | cut -d'|' -f2)"
    SNAPSHOT_DOCKER_RUNNING="$(echo "$pair" | cut -d'|' -f3)"
    SNAPSHOT_DOCKER_TOTAL="$(echo "$pair" | cut -d'|' -f4)"
    # Docker often owns DB/Redis — soften host unit CRITICAL to UNKNOWN when units missing
    if [[ "$SNAPSHOT_DB_STATUS" == "DEGRADED" && "$SNAPSHOT_DB_DETAIL" == *"not found"* ]]; then
      SNAPSHOT_DB_STATUS="UNKNOWN"
      SNAPSHOT_DB_DETAIL="MariaDB via Docker (host unit not found)"
    fi
    if [[ "$SNAPSHOT_REDIS_STATUS" == "DEGRADED" && "$SNAPSHOT_REDIS_DETAIL" == *"not found"* ]]; then
      SNAPSHOT_REDIS_STATUS="UNKNOWN"
      SNAPSHOT_REDIS_DETAIL="Redis via Docker (host unit not found)"
    fi
  else
    pair="$(health_probe_native_runtime)"
    SNAPSHOT_RUNTIME_LAYER_STATUS="${pair%%|*}"
    SNAPSHOT_RUNTIME_LAYER_DETAIL="${pair#*|}"
    SNAPSHOT_DOCKER_RUNNING=""
    SNAPSHOT_DOCKER_TOTAL=""
  fi

  pair="$(health_probe_https)"; SNAPSHOT_HTTPS_STATUS="${pair%%|*}"; SNAPSHOT_HTTPS_DETAIL="${pair#*|}"
  pair="$(health_probe_firewall)"; SNAPSHOT_FIREWALL_STATUS="${pair%%|*}"; SNAPSHOT_FIREWALL_DETAIL="${pair#*|}"
  pair="$(health_probe_fail2ban)"; SNAPSHOT_FAIL2BAN_STATUS="${pair%%|*}"; SNAPSHOT_FAIL2BAN_DETAIL="${pair#*|}"
  pair="$(health_probe_local_backup)"; SNAPSHOT_BACKUP_STATUS="${pair%%|*}"; SNAPSHOT_BACKUP_DETAIL="$(echo "$pair" | cut -d'|' -f2)"; SNAPSHOT_BACKUP_AGE="$(echo "$pair" | cut -d'|' -f3)"
  pair="$(health_probe_off_vm_backup)"; SNAPSHOT_OFFVM_STATUS="${pair%%|*}"; SNAPSHOT_OFFVM_DETAIL="${pair#*|}"
  pair="$(health_probe_object_backup)"; SNAPSHOT_OBJECT_STATUS="${pair%%|*}"; SNAPSHOT_OBJECT_DETAIL="${pair#*|}"
  pair="$(health_probe_restore_rehearsal)"; SNAPSHOT_REHEARSAL_STATUS="${pair%%|*}"; SNAPSHOT_REHEARSAL_DETAIL="${pair#*|}"
  pair="$(health_probe_toolkit_integrity)"; SNAPSHOT_INTEGRITY_STATUS="${pair%%|*}"; SNAPSHOT_INTEGRITY_DETAIL="${pair#*|}"

  SNAPSHOT_HEALING_MODE="monitor"
  SNAPSHOT_HEALING_STATE="not_armed"
  SNAPSHOT_HEALING_DETAIL="Auto-healing not enabled in v1.16 (observe only)"

  # Host rollup (CPU alone is not collected as a hard overall driver — load used as pressure proxy)
  SNAPSHOT_HOST_STATUS="HEALTHY"
  for pair in "$SNAPSHOT_DISK_STATUS" "$SNAPSHOT_INODE_STATUS" "$SNAPSHOT_MEM_STATUS" "$SNAPSHOT_SWAP_STATUS" "$SNAPSHOT_LOAD_STATUS" "$SNAPSHOT_REBOOT_STATUS"; do
    SNAPSHOT_HOST_STATUS="$(health_status_worst "$SNAPSHOT_HOST_STATUS" "$pair")"
  done

  SNAPSHOT_APP_STATUS="HEALTHY"
  for pair in "$SNAPSHOT_HTTP_STATUS" "$SNAPSHOT_WEB_PORT_STATUS" "$SNAPSHOT_SOCKET_STATUS" "$SNAPSHOT_DB_STATUS" "$SNAPSHOT_REDIS_STATUS"; do
    # UNKNOWN app probes do not force CRITICAL overall when optional
    if [[ "$pair" != "UNKNOWN" ]]; then
      SNAPSHOT_APP_STATUS="$(health_status_worst "$SNAPSHOT_APP_STATUS" "$pair")"
    fi
  done
  [[ "$install_value" == "Installed" ]] || SNAPSHOT_APP_STATUS="$(health_status_worst "$SNAPSHOT_APP_STATUS" DEGRADED)"
  [[ "$runtime_value" == Running* ]] || SNAPSHOT_APP_STATUS="$(health_status_worst "$SNAPSHOT_APP_STATUS" DEGRADED)"

  SNAPSHOT_PROTECTION_STATUS="HEALTHY"
  for pair in "$SNAPSHOT_HTTPS_STATUS" "$SNAPSHOT_FIREWALL_STATUS" "$SNAPSHOT_FAIL2BAN_STATUS" "$SNAPSHOT_BACKUP_STATUS" "$SNAPSHOT_REHEARSAL_STATUS" "$SNAPSHOT_INTEGRITY_STATUS"; do
    if [[ "$pair" != "UNKNOWN" ]]; then
      SNAPSHOT_PROTECTION_STATUS="$(health_status_worst "$SNAPSHOT_PROTECTION_STATUS" "$pair")"
    fi
  done
  # Off-VM / object optional
  if [[ "$SNAPSHOT_OFFVM_STATUS" != "UNKNOWN" ]]; then
    SNAPSHOT_PROTECTION_STATUS="$(health_status_worst "$SNAPSHOT_PROTECTION_STATUS" "$SNAPSHOT_OFFVM_STATUS")"
  fi

  overall="HEALTHY"
  overall="$(health_status_worst "$overall" "$SNAPSHOT_HOST_STATUS")"
  overall="$(health_status_worst "$overall" "$SNAPSHOT_APP_STATUS")"
  overall="$(health_status_worst "$overall" "$SNAPSHOT_RUNTIME_LAYER_STATUS")"
  overall="$(health_status_worst "$overall" "$SNAPSHOT_PROTECTION_STATUS")"
  SNAPSHOT_OVERALL="$overall"
}

health_snapshot_write_compat_state() {
  local overall_legacy disk_percent backup_state backup_age off_status
  overall_legacy="$(health_legacy_ok_warn "${SNAPSHOT_OVERALL:-UNKNOWN}")"
  disk_percent="${SNAPSHOT_DISK_PERCENT:-0}"
  backup_state="$(health_legacy_ok_warn "${SNAPSHOT_BACKUP_STATUS:-UNKNOWN}")"
  backup_age="${SNAPSHOT_BACKUP_AGE:-unknown}"
  off_status="${SNAPSHOT_OFFVM_STATUS:-unknown}"
  if declare -F health_check_write_state >/dev/null 2>&1; then
    health_check_write_state \
      "$overall_legacy" \
      "${SNAPSHOT_INSTALL:-Unknown}" \
      "${SNAPSHOT_RUNTIME:-Unknown}" \
      "$(health_legacy_ok_warn "${SNAPSHOT_HTTPS_STATUS:-UNKNOWN}")" \
      "$disk_percent" \
      "$backup_state" \
      "$backup_age" \
      "$off_status"
  fi

  mkdir -p "${HEALTH_LIB_DIR}/metrics" 2>/dev/null || true
  if [[ -d "${HEALTH_LIB_DIR}/metrics" && -w "${HEALTH_LIB_DIR}/metrics" ]]; then
    health_snapshot_emit_json >"${HEALTH_LIB_DIR}/metrics/current.json" 2>/dev/null || true
    chmod 600 "${HEALTH_LIB_DIR}/metrics/current.json" 2>/dev/null || true
  fi
}

health_snapshot_emit_json() {
  printf '{\n'
  printf '  "schema_version": ' ; json_escape "${SNAPSHOT_SCHEMA_VERSION:-1}" ; printf ',\n'
  printf '  "overall_status": ' ; json_escape "${SNAPSHOT_OVERALL:-UNKNOWN}" ; printf ',\n'
  printf '  "timestamp": ' ; json_escape "${SNAPSHOT_GENERATED_AT:-}" ; printf ',\n'
  printf '  "deployment": {\n'
  printf '    "engine": ' ; json_escape "${SNAPSHOT_ENGINE:-native}" ; printf ',\n'
  printf '    "engine_label": ' ; json_escape "${SNAPSHOT_ENGINE_LABEL:-}" ; printf ',\n'
  printf '    "os": ' ; json_escape "${SNAPSHOT_OS:-}" ; printf ',\n'
  printf '    "site": ' ; json_escape "${SNAPSHOT_SITE:-}" ; printf ',\n'
  printf '    "install_state": ' ; json_escape "${SNAPSHOT_INSTALL:-}" ; printf ',\n'
  printf '    "runtime_state": ' ; json_escape "${SNAPSHOT_RUNTIME:-}" ; printf ',\n'
  printf '    "toolkit_version": ' ; json_escape "${SNAPSHOT_TOOLKIT_VERSION:-}" ; printf '\n'
  printf '  },\n'
  printf '  "resources": {\n'
  printf '    "status": ' ; json_escape "${SNAPSHOT_HOST_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "disk_percent": %s,\n' "${SNAPSHOT_DISK_PERCENT:-0}"
  printf '    "inode_percent": %s,\n' "${SNAPSHOT_INODE_PERCENT:-0}"
  printf '    "memory_available_percent": %s,\n' "${SNAPSHOT_MEM_AVAIL_PCT:-0}"
  printf '    "memory_available_kb": %s,\n' "${SNAPSHOT_MEM_AVAILABLE_KB:-0}"
  printf '    "memory_total_kb": %s,\n' "${SNAPSHOT_MEM_TOTAL_KB:-0}"
  printf '    "swap_percent": %s,\n' "${SNAPSHOT_SWAP_PERCENT:-0}"
  printf '    "load1": ' ; json_escape "${SNAPSHOT_LOAD1:-}" ; printf ',\n'
  printf '    "cpu_cores": %s,\n' "${SNAPSHOT_CORES:-0}"
  printf '    "uptime_seconds": %s,\n' "${SNAPSHOT_UPTIME_SEC:-0}"
  printf '    "reboot_required": ' ; json_escape "${SNAPSHOT_REBOOT_DETAIL:-}" ; printf '\n'
  printf '  },\n'
  printf '  "application": {\n'
  printf '    "status": ' ; json_escape "${SNAPSHOT_APP_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "http": ' ; json_escape "${SNAPSHOT_HTTP_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "http_detail": ' ; json_escape "${SNAPSHOT_HTTP_DETAIL:-}" ; printf ',\n'
  printf '    "http_code": ' ; json_escape "${SNAPSHOT_HTTP_CODE:-}" ; printf ',\n'
  printf '    "http_latency_ms": %s,\n' "${SNAPSHOT_HTTP_MS:-0}"
  printf '    "database": ' ; json_escape "${SNAPSHOT_DB_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "redis": ' ; json_escape "${SNAPSHOT_REDIS_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "web_port": ' ; json_escape "${SNAPSHOT_WEB_PORT_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "socketio": ' ; json_escape "${SNAPSHOT_SOCKET_STATUS:-UNKNOWN}" ; printf '\n'
  printf '  },\n'
  printf '  "runtime": {\n'
  printf '    "status": ' ; json_escape "${SNAPSHOT_RUNTIME_LAYER_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "detail": ' ; json_escape "${SNAPSHOT_RUNTIME_LAYER_DETAIL:-}" ; printf ',\n'
  printf '    "docker_running": ' ; json_escape "${SNAPSHOT_DOCKER_RUNNING:-}" ; printf ',\n'
  printf '    "docker_total": ' ; json_escape "${SNAPSHOT_DOCKER_TOTAL:-}" ; printf '\n'
  printf '  },\n'
  printf '  "protection": {\n'
  printf '    "status": ' ; json_escape "${SNAPSHOT_PROTECTION_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "https": ' ; json_escape "${SNAPSHOT_HTTPS_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "https_detail": ' ; json_escape "${SNAPSHOT_HTTPS_DETAIL:-}" ; printf ',\n'
  printf '    "firewall": ' ; json_escape "${SNAPSHOT_FIREWALL_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "fail2ban": ' ; json_escape "${SNAPSHOT_FAIL2BAN_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "backup": ' ; json_escape "${SNAPSHOT_BACKUP_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "backup_detail": ' ; json_escape "${SNAPSHOT_BACKUP_DETAIL:-}" ; printf ',\n'
  printf '    "offsite": ' ; json_escape "${SNAPSHOT_OFFVM_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "object_storage": ' ; json_escape "${SNAPSHOT_OBJECT_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "restore_rehearsal": ' ; json_escape "${SNAPSHOT_REHEARSAL_STATUS:-UNKNOWN}" ; printf ',\n'
  printf '    "toolkit_integrity": ' ; json_escape "${SNAPSHOT_INTEGRITY_STATUS:-UNKNOWN}" ; printf '\n'
  printf '  },\n'
  printf '  "healing": {\n'
  printf '    "mode": ' ; json_escape "${SNAPSHOT_HEALING_MODE:-monitor}" ; printf ',\n'
  printf '    "state": ' ; json_escape "${SNAPSHOT_HEALING_STATE:-not_armed}" ; printf ',\n'
  printf '    "detail": ' ; json_escape "${SNAPSHOT_HEALING_DETAIL:-}" ; printf '\n'
  printf '  }\n'
  printf '}\n'
}

dashboard_status_line() {
  local label="$1" status="$2" detail="$3"
  local glyph legacy
  glyph="$(health_status_glyph "$status")"
  legacy="$(health_legacy_ok_warn "$status")"
  # Reuse status_line colors via legacy OK/WARN/FAIL mapping; CRITICAL→FAIL
  case "$(health_status_normalize "$status")" in
    CRITICAL) legacy="FAIL" ;;
  esac
  status_line "[${glyph}] ${label}" "$legacy" "${detail} ($(health_status_normalize "$status"))"
}

show_operations_dashboard() {
  local details="${1:-0}"

  health_snapshot_collect
  health_snapshot_write_compat_state

  ui_box_start "${APP_NAME:-ERPNext Developer Toolkit}  v${SCRIPT_VERSION}"
  printf '  %s  %-10s  %s  %s  %s\n' \
    "$(health_status_glyph "$SNAPSHOT_OVERALL")" \
    "$(health_status_normalize "$SNAPSHOT_OVERALL")" \
    "$SNAPSHOT_SITE" \
    "$SNAPSHOT_ENGINE_LABEL" \
    "$SNAPSHOT_OS"
  echo "  Last check: ${SNAPSHOT_GENERATED_AT}    Auto-healing: ${SNAPSHOT_HEALING_MODE} (${SNAPSHOT_HEALING_STATE})"
  ui_box_end

  ui_box_start "RESOURCES"
  dashboard_status_line "Disk" "$SNAPSHOT_DISK_STATUS" "$SNAPSHOT_DISK_DETAIL"
  dashboard_status_line "Memory" "$SNAPSHOT_MEM_STATUS" "$SNAPSHOT_MEM_DETAIL"
  dashboard_status_line "Load" "$SNAPSHOT_LOAD_STATUS" "$SNAPSHOT_LOAD_DETAIL"
  if [[ "$details" == "1" ]]; then
    dashboard_status_line "Inodes" "$SNAPSHOT_INODE_STATUS" "$SNAPSHOT_INODE_DETAIL"
    dashboard_status_line "Swap" "$SNAPSHOT_SWAP_STATUS" "$SNAPSHOT_SWAP_DETAIL"
    dashboard_status_line "Uptime" "$SNAPSHOT_UPTIME_STATUS" "$SNAPSHOT_UPTIME_DETAIL"
    dashboard_status_line "Reboot" "$SNAPSHOT_REBOOT_STATUS" "$SNAPSHOT_REBOOT_DETAIL"
  fi
  ui_box_end

  ui_box_start "APPLICATION HEALTH"
  dashboard_status_line "Web / HTTP" "$SNAPSHOT_HTTP_STATUS" "$SNAPSHOT_HTTP_DETAIL"
  dashboard_status_line "Database" "$SNAPSHOT_DB_STATUS" "$SNAPSHOT_DB_DETAIL"
  dashboard_status_line "Redis" "$SNAPSHOT_REDIS_STATUS" "$SNAPSHOT_REDIS_DETAIL"
  dashboard_status_line "Bench web" "$SNAPSHOT_WEB_PORT_STATUS" "$SNAPSHOT_WEB_PORT_DETAIL"
  dashboard_status_line "Socket.IO" "$SNAPSHOT_SOCKET_STATUS" "$SNAPSHOT_SOCKET_DETAIL"
  dashboard_status_line "Engine runtime" "$SNAPSHOT_RUNTIME_LAYER_STATUS" "$SNAPSHOT_RUNTIME_LAYER_DETAIL"
  ui_box_end

  ui_box_start "PROTECTION & RECOVERY"
  dashboard_status_line "HTTPS" "$SNAPSHOT_HTTPS_STATUS" "$SNAPSHOT_HTTPS_DETAIL"
  dashboard_status_line "Firewall" "$SNAPSHOT_FIREWALL_STATUS" "$SNAPSHOT_FIREWALL_DETAIL"
  dashboard_status_line "Fail2Ban" "$SNAPSHOT_FAIL2BAN_STATUS" "$SNAPSHOT_FAIL2BAN_DETAIL"
  dashboard_status_line "Local backup" "$SNAPSHOT_BACKUP_STATUS" "$SNAPSHOT_BACKUP_DETAIL"
  dashboard_status_line "Off-VM" "$SNAPSHOT_OFFVM_STATUS" "$SNAPSHOT_OFFVM_DETAIL"
  dashboard_status_line "Object storage" "$SNAPSHOT_OBJECT_STATUS" "$SNAPSHOT_OBJECT_DETAIL"
  dashboard_status_line "Restore rehearsal" "$SNAPSHOT_REHEARSAL_STATUS" "$SNAPSHOT_REHEARSAL_DETAIL"
  dashboard_status_line "Toolkit integrity" "$SNAPSHOT_INTEGRITY_STATUS" "$SNAPSHOT_INTEGRITY_DETAIL"
  ui_box_end

  ui_box_start "AUTO-HEALING"
  status_line "Mode" "INFO" "$SNAPSHOT_HEALING_MODE"
  status_line "Monitor" "INFO" "$SNAPSHOT_HEALING_STATE"
  status_line "Note" "INFO" "$SNAPSHOT_HEALING_DETAIL"
  echo
  echo "  Architecture: docs/HEALTH-ARCHITECTURE.md"
  echo "  Healing modes (safe/advanced) ship in v1.18 — not armed in v1.16."
  ui_box_end

  ui_next "$(toolkit_cmd dashboard --json)" "$(toolkit_cmd health-check)" "$(toolkit_cmd production-ops-wizard)"
}

run_operations_dashboard() {
  local watch_sec="${DASHBOARD_WATCH_SEC:-0}"
  local details="${DASHBOARD_DETAILS:-0}"
  local format="${DASHBOARD_FORMAT:-human}"

  require_sudo

  if [[ "$format" == "json" ]]; then
    health_snapshot_collect
    health_snapshot_write_compat_state
    health_snapshot_emit_json
    return 0
  fi

  if [[ "$watch_sec" =~ ^[0-9]+$ && "$watch_sec" -gt 0 ]]; then
    while true; do
      clear 2>/dev/null || true
      show_operations_dashboard "$details"
      echo
      echo "Refreshing every ${watch_sec}s — Ctrl+C to stop"
      sleep "$watch_sec" || break
    done
    return 0
  fi

  show_operations_dashboard "$details"
}

run_health_snapshot_command() {
  DASHBOARD_FORMAT="${DASHBOARD_FORMAT:-json}"
  run_operations_dashboard
}
