# shellcheck shell=bash
# Curated Frappe app library, install wizards, and compatibility helpers.
[[ -n "${_ERPNEXT_DEV_APPS_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_APPS_LOADED=1

# ============================================================
# App Library
# ============================================================

app_profile_list() {
  # Print one profile per line. The toolkit intentionally sets IFS to newline/tab
  # for safer parsing, so a space-separated echo would be treated as one item.
  printf '%s\n' \
    crm \
    hrms \
    education \
    payments \
    webshop \
    builder \
    lms \
    wiki \
    print_designer \
    drive \
    gameplan \
    lending \
    raven \
    insights \
    telephony \
    helpdesk \
    india_compliance
}

app_profile_branch_overrides() {
  echo "CRM_BRANCH, HRMS_BRANCH, EDUCATION_BRANCH, PAYMENTS_BRANCH, WEBSHOP_BRANCH, BUILDER_BRANCH, LMS_BRANCH, WIKI_BRANCH, PRINT_DESIGNER_BRANCH, DRIVE_BRANCH, GAMEPLAN_BRANCH, LENDING_BRANCH, RAVEN_BRANCH, INSIGHTS_BRANCH, TELEPHONY_BRANCH, HELPDESK_BRANCH, INDIA_COMPLIANCE_BRANCH"
}

# Human-readable publisher label for curated apps.
# shellcheck disable=SC2120  # arg is optional; most callers rely on LIB_APP_ORIGIN
app_origin_label() {
  local origin="${1:-${LIB_APP_ORIGIN:-frappe}}"
  case "$origin" in
    community|third-party|third_party) printf 'Community / third-party\n' ;;
    *) printf 'Frappe (official)\n' ;;
  esac
}

app_profile_defaults() {
  local profile="$1"

  LIB_APP_DISPLAY=""
  LIB_APP_NAME=""
  LIB_APP_REPO=""
  LIB_APP_BRANCH=""
  LIB_APP_NOTES=""
  # frappe = github.com/frappe/* maintained by Frappe Technologies
  # community = popular third-party / partner apps (still open source)
  LIB_APP_ORIGIN="frappe"

  case "$profile" in
    crm)
      LIB_APP_DISPLAY="Frappe CRM"
      LIB_APP_NAME="crm"
      LIB_APP_REPO="https://github.com/frappe/crm"
      LIB_APP_BRANCH="${CRM_BRANCH:-main}"
      LIB_APP_NOTES="Standalone modern CRM app. ERPNext already includes classic CRM features; install this if you want the separate Frappe CRM experience."
      ;;
    hrms|hr)
      LIB_APP_DISPLAY="Frappe HR / HRMS"
      LIB_APP_NAME="hrms"
      LIB_APP_REPO="https://github.com/frappe/hrms"
      LIB_APP_BRANCH="${HRMS_BRANCH:-version-16}"
      LIB_APP_NOTES="HR, payroll, attendance, leave, employee lifecycle, and HR operations app for Frappe/ERPNext."
      ;;
    education|school|school-erp)
      LIB_APP_DISPLAY="Frappe Education"
      LIB_APP_NAME="education"
      LIB_APP_REPO="https://github.com/frappe/education"
      LIB_APP_BRANCH="${EDUCATION_BRANCH:-version-16}"
      LIB_APP_NOTES="Education and school-management ERP app for admissions, students, teachers, attendance, fees, course scheduling, exams, and student portal. Defaults to EDUCATION_BRANCH=version-16."
      ;;
    telephony)
      LIB_APP_DISPLAY="Frappe Telephony"
      LIB_APP_NAME="telephony"
      LIB_APP_REPO="https://github.com/frappe/telephony"
      LIB_APP_BRANCH="${TELEPHONY_BRANCH:-develop}"
      LIB_APP_NOTES="Dependency app used by Frappe Helpdesk for telephony integrations. Installed automatically before Helpdesk when required."
      ;;
    helpdesk)
      LIB_APP_DISPLAY="Frappe Helpdesk"
      LIB_APP_NAME="helpdesk"
      LIB_APP_REPO="https://github.com/frappe/helpdesk"
      LIB_APP_BRANCH="${HELPDESK_BRANCH:-main}"
      LIB_APP_NOTES="Ticketing and customer support app. Requires the Frappe Telephony app; the toolkit handles that dependency automatically."
      ;;
    insights)
      LIB_APP_DISPLAY="Frappe Insights"
      LIB_APP_NAME="insights"
      LIB_APP_REPO="https://github.com/frappe/insights"
      LIB_APP_BRANCH="${INSIGHTS_BRANCH:-main}"
      LIB_APP_NOTES="Business intelligence, reporting, and dashboard app for Frappe sites."
      ;;
    payments|payment)
      LIB_APP_DISPLAY="Frappe Payments"
      LIB_APP_NAME="payments"
      LIB_APP_REPO="https://github.com/frappe/payments"
      LIB_APP_BRANCH="${PAYMENTS_BRANCH:-}"
      LIB_APP_NOTES="Payment gateway integrations for Frappe apps, including Stripe, PayPal, Razorpay, Braintree, and PayTM. Uses the repository default branch unless PAYMENTS_BRANCH is set."
      ;;
    webshop|ecommerce|e-commerce)
      LIB_APP_DISPLAY="Frappe Webshop / E-Commerce"
      LIB_APP_NAME="webshop"
      LIB_APP_REPO="https://github.com/frappe/webshop"
      LIB_APP_BRANCH="${WEBSHOP_BRANCH:-develop}"
      LIB_APP_NOTES="Open-source eCommerce storefront app for ERPNext-backed catalogs and orders. For Frappe/ERPNext v16, upstream guidance currently points to the develop branch."
      ;;
    builder|frappe-builder)
      LIB_APP_DISPLAY="Frappe Builder"
      LIB_APP_NAME="builder"
      LIB_APP_REPO="https://github.com/frappe/builder"
      LIB_APP_BRANCH="${BUILDER_BRANCH:-}"
      LIB_APP_NOTES="Low-code website builder for Frappe. Uses the repository default branch unless BUILDER_BRANCH is set."
      ;;
    lms|learning)
      LIB_APP_DISPLAY="Frappe Learning / LMS"
      LIB_APP_NAME="lms"
      LIB_APP_REPO="https://github.com/frappe/lms"
      LIB_APP_BRANCH="${LMS_BRANCH:-}"
      LIB_APP_NOTES="Learning management app for courses, lessons, batches, and knowledge sharing. Uses the repository default branch unless LMS_BRANCH is set."
      ;;
    wiki|frappe-wiki)
      LIB_APP_DISPLAY="Frappe Wiki"
      LIB_APP_NAME="wiki"
      LIB_APP_REPO="https://github.com/frappe/wiki"
      LIB_APP_BRANCH="${WIKI_BRANCH:-}"
      LIB_APP_NOTES="Documentation and knowledge-base app for text-heavy content, revisions, and publishing workflows. Uses the repository default branch unless WIKI_BRANCH is set."
      ;;
    print_designer|print-designer|printdesigner)
      LIB_APP_DISPLAY="Frappe Print Designer"
      LIB_APP_NAME="print_designer"
      LIB_APP_REPO="https://github.com/frappe/print_designer"
      LIB_APP_BRANCH="${PRINT_DESIGNER_BRANCH:-}"
      LIB_APP_NOTES="Visual print-format designer for ERPNext/Frappe invoices, quotes, delivery notes, and other print formats. Uses the repository default branch unless PRINT_DESIGNER_BRANCH is set."
      ;;
    drive|frappe-drive)
      LIB_APP_DISPLAY="Frappe Drive"
      LIB_APP_NAME="drive"
      LIB_APP_REPO="https://github.com/frappe/drive"
      LIB_APP_BRANCH="${DRIVE_BRANCH:-}"
      LIB_APP_NOTES="File storage, sharing, and collaboration app. Treat as advanced for ERPNext stacks and test on a disposable VM snapshot first."
      ;;
    gameplan|frappe-gameplan)
      LIB_APP_DISPLAY="Frappe Gameplan"
      LIB_APP_NAME="gameplan"
      LIB_APP_REPO="https://github.com/frappe/gameplan"
      LIB_APP_BRANCH="${GAMEPLAN_BRANCH:-}"
      LIB_APP_NOTES="Async discussions and project knowledge for remote teams (official Frappe product). Uses the repository default branch unless GAMEPLAN_BRANCH is set."
      ;;
    lending|frappe-lending)
      LIB_APP_DISPLAY="Frappe Lending"
      LIB_APP_NAME="lending"
      LIB_APP_REPO="https://github.com/frappe/lending"
      LIB_APP_BRANCH="${LENDING_BRANCH:-version-16}"
      LIB_APP_NOTES="Loan management system for NBFCs and lenders (official Frappe product). Niche compared with CRM/HRMS; defaults to LENDING_BRANCH=version-16."
      ;;
    raven|chat)
      LIB_APP_DISPLAY="Raven Team Chat"
      LIB_APP_NAME="raven"
      LIB_APP_REPO="https://github.com/The-Commit-Company/raven"
      LIB_APP_BRANCH="${RAVEN_BRANCH:-}"
      LIB_APP_ORIGIN="community"
      LIB_APP_NOTES="Community / third-party team messaging (The Commit Company), not a Frappe Technologies product. Open source with ERPNext/FrappeHR integrations. Treat as advanced and test notifications/access paths carefully."
      ;;
    india_compliance|india-compliance|gst|india-gst)
      LIB_APP_DISPLAY="India Compliance (GST)"
      LIB_APP_NAME="india_compliance"
      LIB_APP_REPO="https://github.com/resilient-tech/india-compliance"
      LIB_APP_BRANCH="${INDIA_COMPLIANCE_BRANCH:-version-16}"
      LIB_APP_ORIGIN="community"
      LIB_APP_NOTES="Community / third-party GST, e-invoice, and e-waybill compliance for Indian businesses (Resilient Tech) — the most-installed marketplace compliance app. Not a Frappe Technologies product. Defaults to INDIA_COMPLIANCE_BRANCH=version-16. Some GST API features need an India Compliance account."
      ;;
    *)
      return 1
      ;;
  esac
}

validate_app_name() {
  local app_name="$1"
  [[ "$app_name" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]
}

validate_branch_name() {
  local branch="$1"
  [[ -z "$branch" || "$branch" =~ ^[A-Za-z0-9._/-]+$ ]]
}

app_folder_exists() {
  local bench_dir="$1"
  local app_name="$2"
  path_is_dir "${bench_dir}/apps/${app_name}"
}

get_app_current_branch() {
  local bench_dir="$1"
  local app_name="$2"

  if app_folder_exists "$bench_dir" "$app_name"; then
    run_as_frappe "cd '${bench_dir}/apps/${app_name}' && git rev-parse --abbrev-ref HEAD 2>/dev/null" 2>/dev/null || true
  fi
}

branch_available() {
  local repo="$1"
  local branch="$2"
  local repo_q branch_q

  [[ -z "$branch" ]] && return 0

  repo_q="$(printf '%q' "$repo")"
  branch_q="$(printf '%q' "$branch")"
  git ls-remote --exit-code --heads "$repo" "$branch" >/dev/null 2>&1 || run_as_frappe "git ls-remote --exit-code --heads ${repo_q} ${branch_q} >/dev/null 2>&1"
}


ensure_app_library_node_tools() {
  log "Checking Node/Yarn environment for App Library"

  run_as_frappe '
set -e

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js was not found for the frappe user." >&2
  echo "Run Recommended Setup or repair the Node/nvm installation first." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm was not found for the frappe user." >&2
  exit 1
fi

if ! command -v yarn >/dev/null 2>&1; then
  echo "Yarn was not found. Installing Yarn globally with npm..."
  npm install -g yarn
fi

echo "Node: $(command -v node) $(node -v)"
echo "NPM:  $(command -v npm) $(npm -v)"
echo "Yarn: $(command -v yarn) $(yarn -v)"
' || fail "Node/Yarn preflight failed for App Library."

  ok "Node/Yarn environment ready"
}

prepare_downloaded_app_dependencies() {
  local bench_dir="$1"
  local app_name="$2"

  if ! app_folder_exists "$bench_dir" "$app_name"; then
    return 0
  fi

  log "Preparing dependencies for downloaded app: ${app_name}"

  run_as_frappe "
set -e
cd '${bench_dir}'

if [ -x './env/bin/python' ]; then
  echo 'Installing Python package in bench environment...'
  ./env/bin/python -m pip install -q -e 'apps/${app_name}'
fi

if [ -f 'apps/${app_name}/package.json' ]; then
  echo 'Installing frontend dependencies with Yarn...'
  cd 'apps/${app_name}'
  yarn install --check-files
fi
" || fail "Dependency preparation failed for ${app_name}. Check the app compatibility and logs."

  ok "Dependencies ready for ${app_name}"
}


normalize_apps_txt() {
  local bench_dir="$1"
  local required_app="${2:-}"
  local quiet="${3:-false}"
  local repair_py
  local bench_q repair_py_q required_q quiet_q

  bench_q="$(printf '%q' "$bench_dir")"
  required_q="$(printf '%q' "$required_app")"
  quiet_q="$(printf '%q' "$quiet")"

  if [[ "$quiet" != "true" ]]; then
    log "Normalizing Bench app registry: sites/apps.txt"
  fi

  repair_py="$(mktemp /tmp/erpnext-dev-app-registry.XXXXXX.py)" || return 1

  cat > "$repair_py" <<'PY_APP_REGISTRY'
from pathlib import Path
import sys

required = sys.argv[1] if len(sys.argv) > 1 else ""
quiet = (sys.argv[2].lower() == "true") if len(sys.argv) > 2 else False

apps_dir = Path("apps")
apps_txt = Path("sites/apps.txt")
apps_txt.parent.mkdir(parents=True, exist_ok=True)

valid = []
if apps_dir.exists():
    for d in sorted([x for x in apps_dir.iterdir() if x.is_dir()], key=lambda x: x.name):
        # A Frappe app folder normally contains a Python package with the same name.
        # setup.py / pyproject.toml are fallback signals for app repositories.
        if (d / d.name).is_dir() or (d / "pyproject.toml").exists() or (d / "setup.py").exists():
            valid.append(d.name)

valid_set = set(valid)
raw = apps_txt.read_text() if apps_txt.exists() else ""
original = raw

names_by_len = sorted(valid, key=len, reverse=True)

def split_concat(token: str):
    token = token.strip()
    if not token:
        return []
    if token in valid_set:
        return [token]

    out = []
    i = 0
    while i < len(token):
        match = None
        for name in names_by_len:
            if token.startswith(name, i):
                match = name
                break
        if match is None:
            # Unknown token. Returning it allows filtering below to drop it safely.
            return [token]
        out.append(match)
        i += len(match)
    return out

items = []
for token in raw.replace("\r", "\n").replace(",", "\n").split():
    for item in split_concat(token):
        if item and item not in items:
            items.append(item)

# Drop invalid entries like erpnextcrm. Frappe tries to import every entry in apps.txt.
items = [x for x in items if x in valid_set]

ordered = []
preferred = ("frappe", "erpnext", "crm", "hrms", "education", "payments", "webshop", "builder", "lms", "wiki", "print_designer", "drive", "gameplan", "lending", "raven", "insights", "telephony", "helpdesk", "india_compliance")

# Keep core and curated apps in a predictable order for cleaner diagnostics.
for name in preferred:
    if name in valid_set and name not in ordered:
        ordered.append(name)

# Preserve any custom app entries after the curated apps.
for item in items:
    if item in valid_set and item not in ordered:
        ordered.append(item)

if required and required in valid_set and required not in ordered:
    ordered.append(required)

# Register valid downloaded apps so partially interrupted get-app states are recoverable.
for item in valid:
    if item not in ordered:
        ordered.append(item)

new = "\n".join(ordered) + ("\n" if ordered else "")
if new != original:
    if apps_txt.exists():
        backup = apps_txt.with_name("apps.txt.bak.registry-repair")
        backup.write_text(original)
    apps_txt.write_text(new)
    if not quiet:
        print("Repaired sites/apps.txt:")
        print(new, end="")
else:
    if not quiet:
        print("sites/apps.txt already normalized")
PY_APP_REGISTRY

  chmod 644 "$repair_py" 2>/dev/null || true

  repair_py_q="$(printf '%q' "$repair_py")"

  run_as_frappe "set -e; cd ${bench_q}; python3 ${repair_py_q} ${required_q} ${quiet_q}"
  local rc=$?

  rm -f "$repair_py" 2>/dev/null || true
  return "$rc"
}

repair_app_registry() {
  require_sudo
  local bench_dir
  bench_dir="$(require_site_environment)" || return 1
  normalize_apps_txt "$bench_dir" "" "false" || fail "Could not repair sites/apps.txt."
  ok "Bench app registry repair completed"
  show_installed_apps
}

ensure_app_in_apps_txt() {
  local bench_dir="$1"
  local app_name="$2"
  local bench_q app_q

  if ! app_folder_exists "$bench_dir" "$app_name"; then
    fail "App folder apps/${app_name} is missing; cannot register it in sites/apps.txt."
  fi

  bench_q="$(printf '%q' "$bench_dir")"
  app_q="$(printf '%q' "$app_name")"

  normalize_apps_txt "$bench_dir" "$app_name" "false" || fail "Could not normalize sites/apps.txt before installing ${app_name}."

  run_as_frappe "cd ${bench_q} && grep -qxF ${app_q} sites/apps.txt" || fail "Could not register ${app_name} in sites/apps.txt."

  ok "${app_name} is registered in sites/apps.txt"
}

app_in_apps_txt() {
  local app="$1"
  local bench_dir bench_q app_q
  bench_dir="$(active_bench_dir)"
  bench_q="$(printf '%q' "$bench_dir")"
  app_q="$(printf '%q' "$app")"

  path_is_file "${bench_dir}/sites/apps.txt" || return 1
  run_as_frappe "cd ${bench_q} && grep -qxF ${app_q} sites/apps.txt" >/dev/null 2>&1
}


print_downloaded_app_comparisons() {
  local bench_q="$1"
  local site_q="$2"
  local downloaded_tmp installed_tmp registered_tmp diff_tmp

  downloaded_tmp="$(mktemp /tmp/erpnext-dev-downloaded-apps.XXXXXX)" || return 1
  installed_tmp="$(mktemp /tmp/erpnext-dev-installed-apps.XXXXXX)" || { rm -f "$downloaded_tmp"; return 1; }
  registered_tmp="$(mktemp /tmp/erpnext-dev-registered-apps.XXXXXX)" || { rm -f "$downloaded_tmp" "$installed_tmp"; return 1; }
  diff_tmp="$(mktemp /tmp/erpnext-dev-app-diff.XXXXXX)" || { rm -f "$downloaded_tmp" "$installed_tmp" "$registered_tmp"; return 1; }

  if ! run_as_frappe "cd ${bench_q} && find apps -maxdepth 1 -mindepth 1 -type d -printf '%f\\n' | sort -u" > "$downloaded_tmp"; then
    warn "Could not list downloaded app folders for comparison."
    : > "$downloaded_tmp"
  fi

  if ! run_as_frappe "cd ${bench_q} && bench --site ${site_q} list-apps 2>/dev/null | awk '{print \$1}' | sort -u" > "$installed_tmp"; then
    warn "Could not list installed site apps for comparison."
    : > "$installed_tmp"
  fi

  if ! run_as_frappe "cd ${bench_q} && { [ -f sites/apps.txt ] && sed '/^[[:space:]]*$/d' sites/apps.txt || true; } | sort -u" > "$registered_tmp"; then
    warn "Could not read sites/apps.txt for comparison."
    : > "$registered_tmp"
  fi

  echo "Downloaded but not installed on ${SITE_NAME}:"
  if comm -23 "$downloaded_tmp" "$installed_tmp" > "$diff_tmp"; then
    if [[ -s "$diff_tmp" ]]; then
      sed 's/^/  /' "$diff_tmp"
    else
      echo "  none"
    fi
  else
    warn "Could not compare downloaded apps with installed site apps."
  fi
  echo

  echo "Downloaded but not registered in sites/apps.txt:"
  if comm -23 "$downloaded_tmp" "$registered_tmp" > "$diff_tmp"; then
    if [[ -s "$diff_tmp" ]]; then
      sed 's/^/  /' "$diff_tmp"
    else
      echo "  none"
    fi
  else
    warn "Could not compare downloaded apps with sites/apps.txt."
  fi

  rm -f "$downloaded_tmp" "$installed_tmp" "$registered_tmp" "$diff_tmp"
}

run_app_status() {
  require_sudo

  local bench_dir bench_q site_q app label
  bench_dir="$(require_site_environment)" || return 1
  bench_q="$(printf '%q' "$bench_dir")"
  site_q="$(printf '%q' "$SITE_NAME")"

  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before app status."

  echo
  echo "============================================================"
  echo "App Status"
  echo "============================================================"
  echo "Site: ${SITE_NAME}"
  echo "Bench: ${bench_dir}"
  echo

  echo "Installed on site:"
  run_as_frappe "cd ${bench_q} && bench --site ${site_q} list-apps" || warn "Could not list installed apps."
  echo

  echo "Downloaded app folders:"
  run_as_frappe "cd ${bench_q} && find apps -maxdepth 1 -mindepth 1 -type d -printf '  %f\n' | sort" || warn "Could not list downloaded app folders."
  echo

  print_downloaded_app_comparisons "$bench_q" "$site_q"
  echo

  echo "Curated optional app status:"
  for profile in $(app_profile_list); do
    app_profile_defaults "$profile" || continue
    app="$LIB_APP_NAME"
    label="$LIB_APP_DISPLAY ($(app_origin_label))"

    if site_app_installed "$app"; then
      status_line "$label" "OK" "installed on ${SITE_NAME}"
    elif app_folder_exists "$bench_dir" "$app" && app_in_apps_txt "$app"; then
      status_line "$label" "WARN" "downloaded and registered, not installed on ${SITE_NAME}"
    elif app_folder_exists "$bench_dir" "$app"; then
      status_line "$label" "WARN" "downloaded, not registered in sites/apps.txt"
    else
      status_line "$label" "INFO" "not installed"
    fi
  done

  echo
  echo "Next after each app install:"
  echo "  $(toolkit_cmd verify-access)"
  echo "  $(toolkit_cmd verify-local-ssl)"
  echo "  $(toolkit_cmd local-access-doctor)"
  echo "  $(toolkit_cmd app-status)"
  echo "============================================================"
}

show_installed_apps() {
  require_sudo

  local bench_dir bench_q site_q
  bench_dir="$(require_site_environment)" || return 1
  bench_q="$(printf '%q' "$bench_dir")"
  site_q="$(printf '%q' "$SITE_NAME")"

  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before listing apps."

  echo
  echo "============================================================"
  echo "Frappe / ERPNext Apps"
  echo "============================================================"
  echo "Site: ${SITE_NAME}"
  echo "Bench: ${bench_dir}"
  echo
  echo "Installed on site:"
  run_as_frappe "cd ${bench_q} && bench --site ${site_q} list-apps" || warn "Could not list installed apps."
  echo
  echo "Downloaded app folders:"
  run_as_frappe "cd ${bench_q} && find apps -maxdepth 1 -mindepth 1 -type d -printf '  %f\\n' | sort" || warn "Could not list downloaded app folders."
  echo
  print_downloaded_app_comparisons "$bench_q" "$site_q"
  echo
  echo "============================================================"
}

print_app_profile() {
  local display="$1"
  local app_name="$2"
  local repo="$3"
  local branch="$4"
  local notes="$5"
  local origin="${6:-${LIB_APP_ORIGIN:-frappe}}"

  echo
  echo "App:       ${display}"
  echo "Name:      ${app_name}"
  echo "Publisher: $(app_origin_label "$origin")"
  echo "Repo:      ${repo}"
  if [[ -n "$branch" ]]; then
    echo "Branch:    ${branch}"
  else
    echo "Branch:    default repository branch"
  fi
  echo "Notes:     ${notes}"
  echo
}

version_major_from_branch() {
  local branch="$1"

  if [[ "$branch" =~ ^version-([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

branch_label() {
  local branch="$1"
  if [[ -n "$branch" ]]; then
    echo "$branch"
  else
    echo "default repository branch"
  fi
}

app_install_state_detail() {
  local bench_dir="$1"
  local app_name="$2"

  if site_app_installed "$app_name"; then
    echo "installed on ${SITE_NAME}"
  elif app_folder_exists "$bench_dir" "$app_name" && app_in_apps_txt "$app_name"; then
    echo "downloaded and registered, not installed"
  elif app_folder_exists "$bench_dir" "$app_name"; then
    echo "downloaded, not registered"
  else
    echo "not installed"
  fi
}

assess_app_compatibility() {
  local bench_dir="$1"
  local app_name="$2"
  local display="$3"
  local branch="$4"
  local repo="$5"
  local remote_check="${6:-false}"
  local frappe_branch erpnext_branch frappe_major erpnext_major target_major downloaded_branch branch_text

  APP_COMPAT_STATUS="INFO"
  APP_COMPAT_DETAIL="Compatibility cannot be fully verified automatically. Use a disposable VM snapshot or backup checkpoint first."
  APP_COMPAT_RECOMMENDATION="Install one app at a time, then run app-status and doctor."
  APP_COMPAT_FRAPPE_BRANCH=""
  APP_COMPAT_ERPNEXT_BRANCH=""
  APP_COMPAT_TARGET_BRANCH="$(branch_label "$branch")"
  APP_COMPAT_REMOTE_STATUS="not checked"

  frappe_branch="$(get_app_current_branch "$bench_dir" frappe | tail -1 | tr -d '[:space:]' || true)"
  erpnext_branch="$(get_app_current_branch "$bench_dir" erpnext | tail -1 | tr -d '[:space:]' || true)"
  frappe_branch="${frappe_branch:-${FRAPPE_BRANCH:-unknown}}"
  erpnext_branch="${erpnext_branch:-${ERPNEXT_BRANCH:-unknown}}"

  APP_COMPAT_FRAPPE_BRANCH="$frappe_branch"
  APP_COMPAT_ERPNEXT_BRANCH="$erpnext_branch"

  frappe_major="$(version_major_from_branch "$frappe_branch")"
  erpnext_major="$(version_major_from_branch "$erpnext_branch")"
  target_major="$(version_major_from_branch "$branch")"
  branch_text="$(branch_label "$branch")"

  if app_folder_exists "$bench_dir" "$app_name"; then
    downloaded_branch="$(get_app_current_branch "$bench_dir" "$app_name" | tail -1 | tr -d '[:space:]' || true)"
    if [[ -n "$branch" && -n "$downloaded_branch" && "$downloaded_branch" != "$branch" ]]; then
      APP_COMPAT_STATUS="WARN"
      APP_COMPAT_DETAIL="Downloaded branch is '${downloaded_branch}', but the requested target is '${branch}'. The script will not switch branches automatically."
      APP_COMPAT_RECOMMENDATION="Review the app Git branch manually before installing on the site."
      return 0
    fi
  fi

  if [[ "$remote_check" == "true" && -n "$branch" ]] && ! app_folder_exists "$bench_dir" "$app_name"; then
    if branch_available "$repo" "$branch"; then
      APP_COMPAT_REMOTE_STATUS="branch exists"
    else
      APP_COMPAT_STATUS="FAIL"
      APP_COMPAT_DETAIL="Target branch '${branch}' was not found for ${repo}, or the remote repository could not be reached."
      APP_COMPAT_RECOMMENDATION="Choose a valid branch override before installing."
      return 0
    fi
  fi

  if [[ -n "$target_major" && -n "$frappe_major" && "$target_major" != "$frappe_major" ]]; then
    APP_COMPAT_STATUS="WARN"
    APP_COMPAT_DETAIL="Target branch ${branch_text} does not match detected Frappe branch ${frappe_branch}."
    APP_COMPAT_RECOMMENDATION="Use a branch matching your Frappe/ERPNext major version when available."
    return 0
  fi

  case "$app_name" in
    hrms)
      if [[ "$branch" == "version-16" && "${frappe_major:-16}" == "16" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch version-16 matches the expected Frappe/ERPNext v16 developer stack."
        APP_COMPAT_RECOMMENDATION="Safe to test after a backup checkpoint."
      elif [[ "$branch" == main || "$branch" == develop ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="${display} is targeting a moving branch (${branch_text}) instead of a pinned version branch."
        APP_COMPAT_RECOMMENDATION="Prefer HRMS_BRANCH=version-16 for this toolkit unless you are intentionally testing upstream changes."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="${display} target is ${branch_text}; verify it matches your Frappe/ERPNext branch."
      fi
      ;;
    education)
      if [[ "$branch" == version-16 ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Frappe Education compatibility matrix lists version-16 for Frappe Framework version-16."
        APP_COMPAT_RECOMMENDATION="Safe to test after a backup checkpoint; validate admissions, student portal, fees, and course flows."
      elif [[ "$branch" == develop || -z "$branch" ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="Frappe Education is targeting a moving branch (${branch_text}); compatibility can change as upstream moves."
        APP_COMPAT_RECOMMENDATION="Prefer EDUCATION_BRANCH=version-16 for this toolkit unless intentionally testing upstream changes."
      elif [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="Frappe Education target is ${branch_text}; verify it matches your Frappe/ERPNext branch."
      fi
      ;;
    crm)
      if [[ "$branch" == main ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="Frappe CRM commonly tracks the moving main branch, so compatibility can change over time."
        APP_COMPAT_RECOMMENDATION="Continue only on a dev VM after a backup checkpoint; pin CRM_BRANCH if you need repeatable installs."
      elif [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="Frappe CRM target is ${branch_text}; verify upstream compatibility before important data."
      fi
      ;;
    insights)
      if [[ "$branch" == main ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="Frappe Insights is targeting the moving main branch; compatibility can change."
        APP_COMPAT_RECOMMENDATION="Use a backup checkpoint and test before relying on it."
      elif [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="Frappe Insights target is ${branch_text}; verify upstream compatibility before important data."
      fi
      ;;
    helpdesk)
      if [[ "$branch" == main ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="Frappe Helpdesk is targeting the moving main branch and also requires the Telephony dependency."
        APP_COMPAT_RECOMMENDATION="Install on a dev VM with a backup checkpoint; expect Telephony compatibility checks as well."
      elif [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="Frappe Helpdesk target is ${branch_text}; verify dependency compatibility before important data."
      fi
      ;;
    telephony)
      if [[ "$branch" == develop ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="Frappe Telephony targets the develop branch by default, which is experimental and can change."
        APP_COMPAT_RECOMMENDATION="Use only when required for Helpdesk testing, and keep a backup checkpoint."
      elif [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="Frappe Telephony target is ${branch_text}; verify upstream compatibility before use."
      fi
      ;;
    payments)
      if [[ -z "$branch" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Frappe Payments uses the repository default branch; Frappe Cloud Marketplace lists Payments as supporting Version 16."
        APP_COMPAT_RECOMMENDATION="Safe to test after a backup checkpoint. Set PAYMENTS_BRANCH only if you intentionally want a specific upstream branch."
      elif [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="Frappe Payments target is ${branch_text}; verify upstream compatibility before use."
      fi
      ;;
    webshop)
      if [[ "$branch" == develop ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="Frappe Webshop is targeting develop because upstream guidance for v16 points to develop; this branch can still change over time."
        APP_COMPAT_RECOMMENDATION="Use a VM snapshot or backup checkpoint first, then test catalog, cart, checkout, and ERPNext order flow."
      elif [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="Frappe Webshop target is ${branch_text}; verify upstream compatibility before use."
      fi
      ;;
    builder|lms|wiki|print_designer|gameplan)
      if [[ -z "$branch" ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="${display} uses the repository default branch, so compatibility can change as upstream moves."
        APP_COMPAT_RECOMMENDATION="Use on a dev VM or set a branch override after confirming the correct branch for your Frappe/ERPNext version."
      elif [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="${display} target is ${branch_text}; verify upstream compatibility before important data."
      fi
      ;;
    lending|india_compliance)
      if [[ -n "$target_major" ]]; then
        APP_COMPAT_STATUS="OK"
        APP_COMPAT_DETAIL="Target branch ${branch_text} is version-pinned and matches the detected core major version."
      elif [[ -z "$branch" ]]; then
        APP_COMPAT_STATUS="WARN"
        APP_COMPAT_DETAIL="${display} uses the repository default branch; pin a version-* branch for production."
        APP_COMPAT_RECOMMENDATION="Set a version-matched branch override after confirming upstream support for your Frappe/ERPNext version."
      else
        APP_COMPAT_STATUS="INFO"
        APP_COMPAT_DETAIL="${display} target is ${branch_text}; verify upstream compatibility before important data."
      fi
      ;;
    drive|raven)
      APP_COMPAT_STATUS="WARN"
      if [[ -z "$branch" ]]; then
        APP_COMPAT_DETAIL="${display} is an advanced/collaboration app using the repository default branch. Compatibility and operational requirements may change."
      else
        APP_COMPAT_DETAIL="${display} is an advanced/collaboration app targeting ${branch_text}. Verify compatibility and operational requirements before production use."
      fi
      APP_COMPAT_RECOMMENDATION="Install only on a disposable VM snapshot first; validate login, permissions, background jobs, assets, and notifications if applicable."
      ;;
    *)
      APP_COMPAT_STATUS="WARN"
      APP_COMPAT_DETAIL="Custom app compatibility cannot be verified by this toolkit."
      APP_COMPAT_RECOMMENDATION="Only install trusted apps after confirming the app supports your detected Frappe branch."
      ;;
  esac

  if [[ -n "$target_major" && -n "$erpnext_major" && "$target_major" != "$erpnext_major" ]]; then
    APP_COMPAT_STATUS="WARN"
    APP_COMPAT_DETAIL="Target branch ${branch_text} does not match detected ERPNext branch ${erpnext_branch}."
    APP_COMPAT_RECOMMENDATION="Use an app branch that matches ERPNext/Frappe v${erpnext_major} when available."
  fi
}

show_app_compatibility_card() {
  local bench_dir="$1"
  local app_name="$2"
  local display="$3"
  local repo="$4"
  local branch="$5"
  local notes="$6"
  local remote_check="${7:-false}"

  assess_app_compatibility "$bench_dir" "$app_name" "$display" "$branch" "$repo" "$remote_check"

  echo
  echo "Compatibility preflight: ${display}"
  status_line "Detected Frappe" "INFO" "${APP_COMPAT_FRAPPE_BRANCH}"
  status_line "Detected ERPNext" "INFO" "${APP_COMPAT_ERPNEXT_BRANCH}"
  status_line "Target branch" "INFO" "${APP_COMPAT_TARGET_BRANCH}"
  status_line "Install state" "INFO" "$(app_install_state_detail "$bench_dir" "$app_name")"
  if [[ "$remote_check" == "true" ]]; then
    status_line "Remote branch" "INFO" "${APP_COMPAT_REMOTE_STATUS}"
  fi
  status_line "Compatibility" "$APP_COMPAT_STATUS" "$APP_COMPAT_DETAIL"
  status_line "Recommendation" "INFO" "$APP_COMPAT_RECOMMENDATION"
  status_line "Publisher" "INFO" "$(app_origin_label "${LIB_APP_ORIGIN:-frappe}")"
  echo "Notes: ${notes}"
}

confirm_app_compatibility_before_install() {
  local bench_dir="$1"
  local app_name="$2"
  local display="$3"
  local repo="$4"
  local branch="$5"
  local notes="$6"

  show_app_compatibility_card "$bench_dir" "$app_name" "$display" "$repo" "$branch" "$notes" "false"

  case "$APP_COMPAT_STATUS" in
    FAIL)
      fail "Compatibility preflight failed for ${display}."
      ;;
    WARN)
      warn "Compatibility warning for ${display}: ${APP_COMPAT_DETAIL}"
      if ! confirm "Continue despite this compatibility warning?"; then
        warn "App installation cancelled."
        return 1
      fi
      ;;
  esac

  return 0
}

show_app_compatibility_matrix() {
  require_sudo

  local bench_dir profile app_state
  bench_dir="$(require_site_environment)" || return 1

  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before compatibility check."

  echo
  echo "============================================================"
  echo "Optional App Compatibility Matrix"
  echo "============================================================"
  echo "Site:  ${SITE_NAME}"
  echo "Bench: ${bench_dir}"
  echo
  echo "This check is a pre-install guide. It does not guarantee upstream app compatibility."
  echo "The selected app is checked locally first; bench get-app validates the requested remote branch during the actual download."
  echo

  for profile in $(app_profile_list); do
    app_profile_defaults "$profile" || continue
    assess_app_compatibility "$bench_dir" "$LIB_APP_NAME" "$LIB_APP_DISPLAY" "$LIB_APP_BRANCH" "$LIB_APP_REPO" "false"
    app_state="$(app_install_state_detail "$bench_dir" "$LIB_APP_NAME")"
    status_line "$LIB_APP_DISPLAY" "$APP_COMPAT_STATUS" "target=${APP_COMPAT_TARGET_BRANCH}; state=${app_state}; ${APP_COMPAT_DETAIL}"
  done

  echo
  echo "Detailed check for one app is shown automatically before install."
  echo "Branch overrides: $(app_profile_branch_overrides)."
  echo "============================================================"
}

print_app_compatibility_snapshot() {
  local bench_dir="$1"
  local profile state branch_safety status detail

  echo
  echo "Install / branch snapshot:"
  for profile in $(app_profile_list); do
    app_profile_defaults "$profile" || continue
    assess_app_compatibility "$bench_dir" "$LIB_APP_NAME" "$LIB_APP_DISPLAY" "$LIB_APP_BRANCH" "$LIB_APP_REPO" "false"
    state="$(app_install_state_detail "$bench_dir" "$LIB_APP_NAME")"

    case "$APP_COMPAT_STATUS" in
      OK) branch_safety="pinned/known target" ;;
      WARN) branch_safety="branch note: ${APP_COMPAT_TARGET_BRANCH} may move or be less stable" ;;
      FAIL) branch_safety="branch check failed" ;;
      *) branch_safety="review target branch" ;;
    esac

    if [[ "$state" == installed* ]]; then
      # In this preflight snapshot, the primary signal should be install state.
      # Moving-branch compatibility concerns are still shown in the detail text,
      # but they should not make an already-working installed app look failed.
      status="OK"
      detail="installed; target=${APP_COMPAT_TARGET_BRANCH}; ${branch_safety}"
    elif [[ "$state" == not\ installed ]]; then
      status="INFO"
      detail="not installed; target=${APP_COMPAT_TARGET_BRANCH}; ${branch_safety}"
    elif [[ "$APP_COMPAT_STATUS" == "FAIL" ]]; then
      status="FAIL"
      detail="${state}; target=${APP_COMPAT_TARGET_BRANCH}; ${branch_safety}"
    else
      status="WARN"
      detail="${state}; target=${APP_COMPAT_TARGET_BRANCH}; ${branch_safety}"
    fi

    status_line "$LIB_APP_DISPLAY" "$status" "$detail"
  done

  echo
  echo "Note: installed apps can still show a branch note when they use main/develop/default branches."
  echo "That is a repeatability warning, not an installation failure."
}


install_app_dependency_telephony() {
  local bench_dir="$1"
  local dep_name="telephony"
  local dep_display="Frappe Telephony"
  local dep_repo="https://github.com/frappe/telephony"
  local dep_branch="${TELEPHONY_BRANCH:-develop}"
  local repo_q branch_q downloaded_branch

  if site_app_installed "$dep_name"; then
    ok "${dep_display} dependency is already installed on ${SITE_NAME}"
    return 0
  fi

  echo
  log "Frappe Helpdesk requires ${dep_display}. Installing dependency first."

  if ! validate_branch_name "$dep_branch"; then
    fail "Invalid TELEPHONY_BRANCH value: ${dep_branch}"
  fi

  confirm_app_compatibility_before_install "$bench_dir" "$dep_name" "$dep_display" "$dep_repo" "$dep_branch" "Dependency app used by Frappe Helpdesk for telephony integrations." || return 1

  if app_folder_exists "$bench_dir" "$dep_name"; then
    downloaded_branch="$(get_app_current_branch "$bench_dir" "$dep_name" | tail -1 | tr -d '[:space:]')"
    ok "Dependency already downloaded: apps/${dep_name}"
    if [[ -n "$dep_branch" && -n "$downloaded_branch" && "$downloaded_branch" != "$dep_branch" ]]; then
      warn "Downloaded ${dep_name} branch is '${downloaded_branch}', requested '${dep_branch}'."
      warn "The script will not switch branches automatically. Use Git manually if needed."
    fi
  else
    repo_q="$(printf '%q' "$dep_repo")"
    branch_q="$(printf '%q' "$dep_branch")"

    log "Downloading ${dep_display}"
    run_as_frappe "cd '${bench_dir}' && bench get-app ${repo_q} --branch ${branch_q}" || fail "Could not download ${dep_display}."
  fi

  prepare_downloaded_app_dependencies "$bench_dir" "$dep_name"
  ensure_app_in_apps_txt "$bench_dir" "$dep_name"

  if site_app_installed "$dep_name"; then
    ok "${dep_display} dependency is already installed on ${SITE_NAME}"
  else
    log "Installing ${dep_display} dependency on ${SITE_NAME}"
    run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' install-app '${dep_name}'" || fail "Could not install ${dep_display} dependency."
    ok "${dep_display} dependency installed"
  fi
}

install_app_dependencies() {
  local bench_dir="$1"
  local app_name="$2"

  case "$app_name" in
    helpdesk)
      install_app_dependency_telephony "$bench_dir"
      ;;
  esac
}


show_app_install_guide() {
  echo
  echo "============================================================"
  echo "Optional App Install Guide"
  echo "============================================================"
  echo "Recommended order:"
  echo "  1) Payments before Webshop if you plan to test online checkout"
  echo "  2) Webshop / E-Commerce after ERPNext items and prices are ready"
  echo "  3) CRM, HRMS, Insights, Builder, LMS, Wiki, Print Designer, Gameplan, or Lending as needed"
  echo "  4) India Compliance (community) for Indian GST / e-invoice sites"
  echo "  5) Drive and Raven only on a disposable VM snapshot first"
  echo "  6) Telephony before Helpdesk, unless the wizard installs it"
  echo "  7) Helpdesk after Telephony dependency is ready"
  echo
  echo "Safety workflow:"
  echo "  - Install one optional app at a time."
  echo "  - Create a backup checkpoint before each app."
  echo "  - Run app-status and doctor after each install."
  echo "  - Take a VM snapshot before testing several apps together."
  echo
  echo "Commands:"
  echo "  $(toolkit_cmd app-install-wizard)"
  echo "  $(toolkit_cmd app-compatibility)"
  echo "  $(toolkit_cmd app-status)"
  echo "  $(toolkit_cmd app-rollback-guide)"
  echo "============================================================"
}

create_app_install_checkpoint() {
  local display="$1"
  local reply

  if [[ "${APP_BACKUP_BEFORE_INSTALL}" == "false" ]]; then
    warn "Pre-app backup skipped by APP_BACKUP_BEFORE_INSTALL=false."
    return 0
  fi

  echo
  echo "Backup checkpoint recommended before installing ${display}."

  if [[ "${APP_BACKUP_BEFORE_INSTALL}" == "true" || "$ASSUME_YES" -eq 1 ]]; then
    if ! create_site_backup true; then
      fail "Pre-app backup failed. Stop here or set APP_BACKUP_BEFORE_INSTALL=false only for disposable test VMs."
    fi
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -p "Create database + files backup now? [Y/n]: " reply
    reply="${reply:-Y}"
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      if ! create_site_backup true; then
        warn "Pre-app backup failed."
        if ! confirm "Continue installing ${display} without a verified backup?"; then
          fail "App installation cancelled because backup failed."
        fi
      fi
    else
      warn "Backup checkpoint skipped. This is OK only for disposable test VMs or VM snapshots."
      if ! confirm "Continue installing ${display} without a backup checkpoint?"; then
        fail "App installation cancelled."
      fi
    fi
  fi
}


create_post_app_install_checkpoint() {
  local display="$1"
  local reply

  if [[ "${APP_BACKUP_AFTER_INSTALL}" == "false" ]]; then
    warn "Post-app backup skipped by APP_BACKUP_AFTER_INSTALL=false."
    return 0
  fi

  echo
  echo "Post-app backup checkpoint recommended after installing ${display}."

  if [[ "${APP_BACKUP_AFTER_INSTALL}" == "true" || "$ASSUME_YES" -eq 1 ]]; then
    create_site_backup true || warn "Post-app backup failed. Create a manual checkpoint before installing another app."
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -p "Create database + files backup after ${display}? [Y/n]: " reply
    reply="${reply:-Y}"
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      create_site_backup true || warn "Post-app backup failed. Create a manual checkpoint before installing another app."
    else
      warn "Post-app backup skipped. Take a VM snapshot or backup before installing the next app."
    fi
  fi
}

run_post_app_validation() {
  local app_name="$1"
  local display="$2"

  echo
  echo "============================================================"
  echo "Post-App Validation"
  echo "============================================================"
  if site_app_installed "$app_name"; then
    status_line "$display" "OK" "installed on ${SITE_NAME}"
  else
    status_line "$display" "WARN" "not confirmed on ${SITE_NAME}"
  fi

  if [[ "$(runtime_state 2>/dev/null || echo Stopped)" == Running* ]]; then
    status_line "Runtime" "OK" "$(runtime_state 2>/dev/null || echo Running)"
  else
    status_line "Runtime" "WARN" "$(runtime_state 2>/dev/null || echo Stopped)"
  fi

  if port_listens 8000; then
    status_line "Bench web" "OK" "port 8000 listening"
  else
    status_line "Bench web" "WARN" "port 8000 not listening"
  fi

  if bench_static_assets_ready 2>/dev/null; then
    status_line "Static assets" "OK" "login CSS/JS probe passed"
  else
    status_line "Static assets" "WARN" "login CSS/JS not ready — run repair-frontend-assets"
  fi

  echo
  echo "Next checks:"
  echo "  $(toolkit_cmd app-status)"
  echo "  $(toolkit_cmd doctor)"
  echo "  $(toolkit_cmd verify-frontend-assets)"
  echo "  $(toolkit_cmd verify-access)"

  if [[ "$app_name" == "education" ]]; then
    print_education_access_note
  fi

  echo "============================================================"
}

show_app_rollback_guide() {
  cat <<EOF_APP_ROLLBACK

============================================================
Optional App Rollback Guide
============================================================

The safest rollback is to restore a backup created before the app install.
Do not rely on deleting app folders as a clean rollback because DocTypes,
patches, database changes, and assets may already be applied.

Recommended rollback flow:
  1) Stop the service if needed:
     $(toolkit_cmd stop)

  2) List available backups:
     $(toolkit_cmd list-backups)

  3) Restore the pre-app database/files backup:
     $(toolkit_cmd restore-full)

  4) Start and validate:
     $(toolkit_cmd start)
     $(toolkit_cmd app-status)
     $(toolkit_cmd doctor)

Best practice:
  - Take a VM snapshot before installing optional apps.
  - Install one app at a time.
  - Keep the pre-app backup until the app is fully tested.

============================================================
EOF_APP_ROLLBACK
}

app_wizard_preflight() {
  local bench_dir="$1"

  echo
  echo "============================================================"
  echo "Optional App Install Preflight"
  echo "============================================================"
  status_line "Site" "INFO" "${SITE_NAME}"
  status_line "Bench" "INFO" "$bench_dir"

  if [[ "$(install_state 2>/dev/null || echo Not installed)" == "Installed" ]]; then
    status_line "Core install" "OK" "ERPNext installed"
  else
    status_line "Core install" "WARN" "not fully confirmed; run doctor before app installs"
  fi

  if [[ "$(runtime_state 2>/dev/null || echo Stopped)" == Running* ]]; then
    status_line "Runtime" "OK" "$(runtime_state 2>/dev/null || echo Running)"
  else
    status_line "Runtime" "INFO" "ERPNext is not running; app install can still continue"
  fi

  if port_listens 443; then
    status_line "Local HTTPS" "OK" "port 443 listening"
  else
    status_line "Local HTTPS" "INFO" "not configured or not running; optional apps can still install"
  fi

  echo
  status_line "Compatibility" "INFO" "checked only for the selected app; use menu option 2 for the full matrix"
  status_line "Remote branch" "INFO" "validated once by bench get-app during download (no duplicate network pre-check)"

  echo
  echo "Pre-app backup policy: ${APP_BACKUP_BEFORE_INSTALL}"
  echo "Post-app backup policy: ${APP_BACKUP_AFTER_INSTALL}"
  echo "============================================================"
}

run_app_install_wizard() {
  require_sudo
  check_internet

  local bench_dir choice
  bench_dir="$(require_site_environment)" || return 1

  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before app wizard."
  app_wizard_preflight "$bench_dir"

  while true; do
    ui_submenu_header "App Wizard" \
      "Choose one app. Status and guide tools are listed first."
    print_two_column_menu \
      "1) Installed apps" \
      "2) Compatibility" \
      "3) CRM" \
      "4) HRMS" \
      "5) Education" \
      "6) Payments" \
      "7) Webshop" \
      "8) Builder" \
      "9) LMS" \
      "10) Wiki" \
      "11) Print Designer" \
      "12) Drive" \
      "13) Gameplan" \
      "14) Lending" \
      "15) Raven" \
      "16) Insights" \
      "17) Telephony" \
      "18) Helpdesk" \
      "19) India Compliance" \
      "20) Advanced tools" \
      "21) Rollback"
    echo
    ui_text muted "Install one app at a time. official=Frappe; community=third-party."
    printf '\n'
    ui_text muted "The wizard will offer a backup checkpoint first."
    printf '\n'
    menu_footer
    menu_read_choice choice

    case "$choice" in
      1) run_app_status; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      2) show_app_compatibility_matrix; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      3) install_app_profile crm; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      4) install_app_profile hrms; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      5) install_app_profile education; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      6) install_app_profile payments; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      7) install_app_profile webshop; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      8) install_app_profile builder; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      9) install_app_profile lms; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      10) install_app_profile wiki; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      11) install_app_profile print_designer; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      12) install_app_profile drive; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      13) install_app_profile gameplan; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      14) install_app_profile lending; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      15) install_app_profile raven; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      16) install_app_profile insights; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      17) install_app_profile telephony; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      18) install_app_profile helpdesk; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      19) install_app_profile india_compliance; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      20) show_advanced_app_tools_menu; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      21) show_app_rollback_guide; pause_after_screen "Press Enter to return to App Installation Wizard..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

install_frappe_app() {
  require_sudo
  check_internet

  local app_name="$1"
  local display="$2"
  local repo="$3"
  local branch="$4"
  local notes="$5"
  local bench_dir repo_q branch_q downloaded_branch

  if deployment_engine_is_docker; then
    docker_install_app "$app_name" "$display" "$repo" "$branch"
    return
  fi

  bench_dir="$(require_site_environment)" || return 1

  if ! validate_app_name "$app_name"; then
    fail "Invalid app name: ${app_name}"
  fi

  if ! validate_branch_name "$branch"; then
    fail "Invalid branch name: ${branch}"
  fi

  print_app_profile "$display" "$app_name" "$repo" "$branch" "$notes" "${LIB_APP_ORIGIN:-frappe}"
  confirm_app_compatibility_before_install "$bench_dir" "$app_name" "$display" "$repo" "$branch" "$notes" || return 1

  # Repair any existing apps.txt corruption before backups or bench site commands.
  # A prior interrupted app install can create concatenated entries like erpnextcrm.
  normalize_apps_txt "$bench_dir" "" "true" || warn "Could not normalize sites/apps.txt before app install."

  if site_app_installed "$app_name"; then
    ok "${display} is already installed on ${SITE_NAME}"
    return 0
  fi

  if ! confirm "Install ${display} on ${SITE_NAME}?"; then
    warn "App installation cancelled."
    return 0
  fi

  create_app_install_checkpoint "$display"

  ensure_app_library_node_tools
  install_app_dependencies "$bench_dir" "$app_name"

  if app_folder_exists "$bench_dir" "$app_name"; then
    downloaded_branch="$(get_app_current_branch "$bench_dir" "$app_name" | tail -1 | tr -d '[:space:]')"
    ok "App already downloaded: apps/${app_name}"
    if [[ -n "$branch" && -n "$downloaded_branch" && "$downloaded_branch" != "$branch" ]]; then
      warn "Downloaded app branch is '${downloaded_branch}', requested '${branch}'."
      warn "The script will not switch branches automatically. Use Git manually if needed."
    fi
  else
    repo_q="$(printf '%q' "$repo")"
    branch_q="$(printf '%q' "$branch")"

    log "Downloading ${display}"
    if [[ -n "$branch" ]]; then
      run_as_frappe "cd '${bench_dir}' && bench get-app ${repo_q} --branch ${branch_q}"
    else
      run_as_frappe "cd '${bench_dir}' && bench get-app ${repo_q}"
    fi
  fi

  prepare_downloaded_app_dependencies "$bench_dir" "$app_name"
  ensure_app_in_apps_txt "$bench_dir" "$app_name"

  ensure_bench_services_for_site_commands "installing ${display}" || fail "Bench services were not ready, so ${display} installation was stopped safely."

  if site_app_installed "$app_name"; then
    ok "${display} is already installed on ${SITE_NAME}"
  else
    log "Installing ${display} on ${SITE_NAME}"
    run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' install-app '${app_name}'"
  fi

  log "Running post-app maintenance"
  ensure_bench_services_for_site_commands "post-app migrate for ${display}" || fail "Bench services were not ready for post-app maintenance."
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' migrate"
  run_as_frappe "cd '${bench_dir}' && bench build"
  ensure_bench_services_for_site_commands "post-app clear-cache for ${display}" || fail "Bench services were not ready for cache cleanup."
  run_as_frappe "cd '${bench_dir}' && bench --site '${SITE_NAME}' clear-cache"

  restart_erpnext_service || fail "${display} installed, but the service could not be restarted automatically."
  if ! bench_static_assets_ready 2>/dev/null; then
    warn "${display} installed, but login static assets are not ready yet."
    echo "Repair: $(toolkit_cmd repair-frontend-assets)"
    echo "Wait:   $(toolkit_cmd wait-frontend-assets)"
  fi

  ok "${display} installation workflow completed"
  show_installed_apps
  run_post_app_validation "$app_name" "$display"
  create_post_app_install_checkpoint "$display"
}

install_app_profile() {
  local profile="$1"

  app_profile_defaults "$profile" || fail "Unknown app profile: ${profile}"
  install_frappe_app "$LIB_APP_NAME" "$LIB_APP_DISPLAY" "$LIB_APP_REPO" "$LIB_APP_BRANCH" "$LIB_APP_NOTES"
}

install_custom_app_interactive() {
  require_sudo

  local app_name display repo branch notes

  echo
  echo "============================================================"
  echo "Advanced: Custom Git App"
  echo "============================================================"
  err "This is an advanced option for trusted Frappe apps only."
  warn "It can break the site if the app is untrusted, incompatible, or has unsafe install hooks."
  echo
  echo "Use the curated app library first whenever possible."
  echo "Continue only if you know the repository, branch, app name, and Frappe/ERPNext compatibility."
  echo

  if ! confirm "Continue to advanced custom Git app installation?"; then
    warn "Custom app installation cancelled."
    return 0
  fi

  read -r -p "Type I UNDERSTAND to confirm advanced custom app risk: " risk_ack
  if [[ "$risk_ack" != "I UNDERSTAND" ]]; then
    warn "Confirmation did not match. Custom app installation cancelled."
    return 0
  fi

  read -r -p "App name used by bench install-app, for example my_app: " app_name
  if ! validate_app_name "$app_name"; then
    fail "Invalid app name. Use letters, numbers, underscore, or hyphen only."
  fi

  read -r -p "Git repository URL: " repo
  if [[ -z "$repo" ]]; then
    fail "Repository URL is required."
  fi

  read -r -p "Branch [leave blank for repository default]: " branch
  if ! validate_branch_name "$branch"; then
    fail "Invalid branch name."
  fi

  read -r -p "Display name [${app_name}]: " display
  display="${display:-$app_name}"
  notes="Custom app provided by the user. Verify compatibility before using it with important data."

  install_frappe_app "$app_name" "$display" "$repo" "$branch" "$notes"
}


show_advanced_app_tools_menu() {
  while true; do
    ui_submenu_header "Advanced App Tools" \
      "Troubleshooting and trusted custom apps only."
    print_two_column_menu       "1) Custom Git app"       "2) Repair app registry"       "3) Rollback guide"       "4) Installed apps"
    echo
    warn "Custom Git apps are not curated by this toolkit and may break the site if incompatible."
    menu_footer
    local advanced_app_choice=""
    menu_read_choice advanced_app_choice

    case "$advanced_app_choice" in
      1) install_custom_app_interactive; pause_after_screen "Press Enter to return to Advanced App Tools..." ;;
      2) repair_app_registry; pause_after_screen "Press Enter to return to Advanced App Tools..." ;;
      3) show_app_rollback_guide; pause_after_screen "Press Enter to return to Advanced App Tools..." ;;
      4) show_installed_apps; pause_after_screen "Press Enter to return to Advanced App Tools..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

show_app_library_menu() {
  while true; do
    ui_submenu_header "App Library" \
      "Install an app, or use status / guide tools."
    print_two_column_menu \
      "1) Wizard" \
      "2) Installed apps" \
      "3) Compatibility" \
      "4) Installed apps list" \
      "5) Guide" \
      "6) Rollback" \
      "7) CRM" \
      "8) HRMS" \
      "9) Education" \
      "10) Payments" \
      "11) Webshop" \
      "12) Builder" \
      "13) LMS" \
      "14) Wiki" \
      "15) Print Designer" \
      "16) Drive" \
      "17) Gameplan" \
      "18) Lending" \
      "19) Raven" \
      "20) Helpdesk" \
      "21) Telephony" \
      "22) Insights" \
      "23) India Compliance" \
      "24) Advanced tools"
    echo
    ui_text muted "Notes: one app at a time; keep a backup checkpoint."
    printf '\n'
    ui_text muted "official=Frappe Technologies; community=third-party open source."
    printf '\n'
    menu_footer
    local app_choice=""
    menu_read_choice app_choice

    case "$app_choice" in
      1) run_app_install_wizard ;;
      2) run_app_status; pause_after_screen "Press Enter to return to App Library..." ;;
      3) show_app_compatibility_matrix; pause_after_screen "Press Enter to return to App Library..." ;;
      4) show_installed_apps; pause_after_screen "Press Enter to return to App Library..." ;;
      5) show_app_install_guide; pause_after_screen "Press Enter to return to App Library..." ;;
      6) show_app_rollback_guide; pause_after_screen "Press Enter to return to App Library..." ;;
      7) install_app_profile crm; pause_after_screen "Press Enter to return to App Library..." ;;
      8) install_app_profile hrms; pause_after_screen "Press Enter to return to App Library..." ;;
      9) install_app_profile education; pause_after_screen "Press Enter to return to App Library..." ;;
      10) install_app_profile payments; pause_after_screen "Press Enter to return to App Library..." ;;
      11) install_app_profile webshop; pause_after_screen "Press Enter to return to App Library..." ;;
      12) install_app_profile builder; pause_after_screen "Press Enter to return to App Library..." ;;
      13) install_app_profile lms; pause_after_screen "Press Enter to return to App Library..." ;;
      14) install_app_profile wiki; pause_after_screen "Press Enter to return to App Library..." ;;
      15) install_app_profile print_designer; pause_after_screen "Press Enter to return to App Library..." ;;
      16) install_app_profile drive; pause_after_screen "Press Enter to return to App Library..." ;;
      17) install_app_profile gameplan; pause_after_screen "Press Enter to return to App Library..." ;;
      18) install_app_profile lending; pause_after_screen "Press Enter to return to App Library..." ;;
      19) install_app_profile raven; pause_after_screen "Press Enter to return to App Library..." ;;
      20) install_app_profile helpdesk; pause_after_screen "Press Enter to return to App Library..." ;;
      21) install_app_profile telephony; pause_after_screen "Press Enter to return to App Library..." ;;
      22) install_app_profile insights; pause_after_screen "Press Enter to return to App Library..." ;;
      23) install_app_profile india_compliance; pause_after_screen "Press Enter to return to App Library..." ;;
      24) show_advanced_app_tools_menu; pause_after_screen "Press Enter to return to App Library..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}
