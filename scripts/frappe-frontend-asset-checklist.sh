#!/usr/bin/env bash
# Frappe-first frontend asset checklist (disk, RAM/OOM, :8000 Host path).
# Prefer this before changing nginx. Can be run standalone or via:
#   sudo erpnext-dev frappe-asset-checklist
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# When sourced from erpnext-dev, SITE_NAME / helpers already exist.
if [[ -z "${_ERPNEXT_DEV_ACCESS_LOADED:-}" ]]; then
  # Minimal standalone mode: source toolkit if present next to this script.
  if [[ -f "${ROOT_DIR}/erpnext-dev.sh" ]]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/lib/common.sh" 2>/dev/null || true
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/lib/config.sh" 2>/dev/null || true
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/lib/access.sh" 2>/dev/null || true
  fi
fi

SITE_NAME="${SITE_NAME:-erp.test}"
BENCH_DIR="${BENCH_DIR:-}"
if [[ -z "$BENCH_DIR" ]] && declare -F active_bench_dir >/dev/null 2>&1; then
  BENCH_DIR="$(active_bench_dir 2>/dev/null || true)"
fi
BENCH_DIR="${BENCH_DIR:-/home/frappe/frappe/frappe-bench}"
SITES="${BENCH_DIR}/sites"
ASSETS="${SITES}/assets"

fail_n=0
warn_n=0

line() {
  local label="$1" state="$2" detail="$3"
  printf "  %-32s %-7s %s\n" "$label" "$state" "$detail"
}

echo
echo "============================================================"
echo "Frappe frontend asset checklist"
echo "============================================================"
echo "Site:  ${SITE_NAME}"
echo "Bench: ${BENCH_DIR}"
echo "Docs:  docs/FRAPPE-FRONTEND-ASSETS.md"
echo
echo "Official primary URL (local/dev): http://${SITE_NAME}:8000/login"
echo

# --- RAM / OOM (incomplete builds) ---
mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
if [[ "$mem_mb" =~ ^[0-9]+$ ]] && ((mem_mb > 0 && mem_mb < 4096)); then
  line "RAM" "WARN" "${mem_mb} MB (< 4096; yarn/esbuild often OOMs)"
  warn_n=$((warn_n + 1))
elif [[ "$mem_mb" =~ ^[0-9]+$ ]] && ((mem_mb >= 4096)); then
  line "RAM" "OK" "${mem_mb} MB"
else
  line "RAM" "INFO" "could not detect"
fi

oom_hit=0
if dmesg 2>/dev/null | grep -qiE 'killed process|out of memory|oom-kill'; then
  oom_hit=1
elif journalctl -k -n 200 --no-pager 2>/dev/null | grep -qiE 'killed process|out of memory|oom-kill'; then
  oom_hit=1
fi
if ((oom_hit == 1)); then
  line "Kernel OOM" "WARN" "OOM signatures in dmesg/journal (builds may be incomplete)"
  warn_n=$((warn_n + 1))
else
  line "Kernel OOM" "OK" "no recent OOM signatures found"
fi

# --- Disk bundles (Frappe contract) ---
check_glob() {
  local label="$1" dir="$2" name_glob="$3"
  local matches
  # shellcheck disable=SC2012,SC2086 # ls + unquoted glob for hashed bundle names
  matches="$(ls -1 ${dir}/${name_glob} 2>/dev/null | head -n 3 || true)"
  if [[ -n "$matches" ]]; then
    line "$label" "OK" "$(basename "$(printf '%s\n' "$matches" | head -n 1)")"
  else
    line "$label" "FAIL" "missing (${dir}/${name_glob})"
    fail_n=$((fail_n + 1))
  fi
}

if [[ -d "$ASSETS" ]]; then
  line "sites/assets" "OK" "$ASSETS"
  check_glob "website.bundle CSS" "${ASSETS}/frappe/dist/css" "website.bundle.*.css"
  check_glob "login.bundle CSS" "${ASSETS}/frappe/dist/css" "login.bundle.*.css"
  check_glob "erpnext-web CSS" "${ASSETS}/erpnext/dist/css" "erpnext-web.bundle.*.css"
  check_glob "frappe-web JS" "${ASSETS}/frappe/dist/js" "frappe-web.bundle.*.js"
else
  line "sites/assets" "FAIL" "directory missing: ${ASSETS}"
  fail_n=$((fail_n + 1))
fi

# assets.json on disk (bench also caches in Redis as assets_json)
if [[ -f "${ASSETS}/assets.json" ]]; then
  line "assets.json (disk)" "OK" "${ASSETS}/assets.json"
else
  line "assets.json (disk)" "WARN" "missing — run bench build"
  warn_n=$((warn_n + 1))
fi

# --- :8000 Host path (official local URL) ---
if command -v curl >/dev/null 2>&1; then
  head8000="$(curl -k -sS -I --max-time 8 --resolve "${SITE_NAME}:8000:127.0.0.1" \
    "http://${SITE_NAME}:8000/login" 2>/dev/null | tr -d '\r' | head -n 1 || true)"
  if [[ "$head8000" == HTTP/* ]]; then
    code="$(printf '%s' "$head8000" | awk '{print $2}')"
    if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
      line "HTTP :8000 /login" "OK" "$head8000"
    else
      line "HTTP :8000 /login" "FAIL" "$head8000"
      fail_n=$((fail_n + 1))
    fi
  else
    line "HTTP :8000 /login" "FAIL" "no response (is bench start / service up?)"
    fail_n=$((fail_n + 1))
  fi

  # Sample one disk CSS via :8000 if present
  # shellcheck disable=SC2012
  sample_css="$(ls -1 "${ASSETS}/frappe/dist/css/"login.bundle.*.css 2>/dev/null | head -n 1 || true)"
  if [[ -n "$sample_css" ]]; then
    rel="/assets/frappe/dist/css/$(basename "$sample_css")"
    code="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 8 \
      --resolve "${SITE_NAME}:8000:127.0.0.1" \
      "http://${SITE_NAME}:8000${rel}" 2>/dev/null || echo 000)"
    if [[ "$code" == "200" ]]; then
      line "Asset via :8000" "OK" "HTTP ${code} ${rel}"
    else
      line "Asset via :8000" "FAIL" "HTTP ${code} ${rel}"
      fail_n=$((fail_n + 1))
    fi
  fi
else
  line "curl" "WARN" "curl not installed; skipped HTTP probes"
  warn_n=$((warn_n + 1))
fi

echo
echo "Open on the HOST (after /etc/hosts maps ${SITE_NAME}):"
echo "  Preferred (Frappe local):  http://${SITE_NAME}:8000/login"
if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ':443 '; then
  echo "  Optional HTTPS:           https://${SITE_NAME}/login"
fi
echo "  Avoid until verified:      http://${SITE_NAME}  (bare port 80)"
echo
echo "Repair if disk/HTTP FAIL:"
echo "  sudo erpnext-dev repair-frontend-assets"
echo "  sudo erpnext-dev verify-frontend-assets"
echo

if ((fail_n > 0)); then
  line "Checklist" "FAIL" "${fail_n} failure(s), ${warn_n} warning(s)"
  echo "============================================================"
  exit 1
fi
if ((warn_n > 0)); then
  line "Checklist" "WARN" "0 failures, ${warn_n} warning(s)"
else
  line "Checklist" "OK" "disk + :8000 path look healthy"
fi
echo "============================================================"
exit 0
