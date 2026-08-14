# shellcheck shell=bash
# Read-only application inventory and compatibility engine.
[[ -n "${_ERPNEXT_DEV_INVENTORY_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_INVENTORY_LOADED=1

declare -ag INVENTORY_RECORDS=()

inventory_probe_timeout_seconds() {
  local value="${ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT:-8}"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || return 1
  ((value <= 300)) || return 1
  printf '%s\n' "$value"
}

inventory_run_probe() {
  local timeout_seconds
  timeout_seconds="$(inventory_probe_timeout_seconds)" || return 125
  command -v timeout >/dev/null 2>&1 || return 125
  command timeout --signal=TERM --kill-after=2s "$timeout_seconds" "$@"
}

inventory_valid_name() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
}

inventory_safe_field() {
  [[ "${1:-}" != *"|"* && "${1:-}" != *$'\n'* && "${1:-}" != *$'\r'* && "${1:-}" != *$'\t'* ]]
}

inventory_current_uid() {
  printf '%s\n' "${EUID:-$(id -u)}"
}

inventory_run_git_probe() {
  local dir="$1"
  shift
  local current_uid owner_record owner_name owner_uid owner_home resolved_uid

  current_uid="$(inventory_current_uid)" || return 125
  owner_uid="$(inventory_run_probe stat -c '%u' -- "$dir" 2>/dev/null)" || return 125
  [[ "$owner_uid" =~ ^[0-9]+$ ]] || return 125

  if [[ "$owner_uid" == "$current_uid" ]]; then
    inventory_run_probe env \
      -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG_COUNT \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      GIT_OPTIONAL_LOCKS=0 GIT_PAGER=cat PAGER=cat \
      git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.pager=cat \
      -c pager.status=false -C "$dir" "$@"
    return
  fi

  # Never bypass Git's dubious-ownership protection with safe.directory. A
  # root-run inventory must inspect a repository as its actual filesystem
  # owner, just as Bench does. Unknown owners and non-root cross-user probes
  # fail closed and are reported as ambiguous by the caller.
  [[ "$current_uid" == 0 ]] || return 125
  command -v runuser >/dev/null 2>&1 || return 125
  command -v getent >/dev/null 2>&1 || return 125
  owner_record="$(inventory_run_probe getent passwd "$owner_uid" 2>/dev/null)" || return 125
  IFS=: read -r owner_name _ resolved_uid _ _ owner_home _ <<<"$owner_record"
  [[ -n "$owner_name" && "$resolved_uid" == "$owner_uid" && "$owner_home" == /* ]] || return 125

  inventory_run_probe runuser -u "$owner_name" -- env \
    -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG_COUNT \
    HOME="$owner_home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_OPTIONAL_LOCKS=0 GIT_PAGER=cat PAGER=cat \
    git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.pager=cat \
    -c pager.status=false -C "$dir" "$@"
}

inventory_git_proof_safe() {
  local dir="$1" git_dir="$1/.git" repo_uid proof_count path owner mode group_digit other_digit
  [[ -d "$dir" && ! -L "$dir" && -d "$git_dir" && ! -L "$git_dir" ]] || return 1
  repo_uid="$(stat -c %u -- "$dir" 2>/dev/null)" || return 1
  [[ "$repo_uid" =~ ^[0-9]+$ ]] || return 1
  proof_count="$(find -P "$git_dir" -xdev -mindepth 0 -maxdepth 32 -printf x 2>/dev/null)" || return 1
  ((${#proof_count} > 0 && ${#proof_count} <= 100000)) || return 1
  ! find -P "$git_dir" -xdev -mindepth 32 -maxdepth 32 -type d -print -quit 2>/dev/null | grep -q . || return 1
  while IFS= read -r -d '' path; do
    [[ ! -L "$path" && (-f "$path" || -d "$path") ]] || return 1
    owner="$(stat -c %u -- "$path" 2>/dev/null)" || return 1
    mode="$(stat -c %a -- "$path" 2>/dev/null)" || return 1
    [[ "$owner" == "$repo_uid" && "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    group_digit=$(((10#$mode / 10) % 10))
    other_digit=$((10#$mode % 10))
    (((group_digit & 2) == 0 && (other_digit & 2) == 0)) || return 1
  done < <(find -P "$git_dir" -xdev -mindepth 0 -maxdepth 32 -print0 2>/dev/null) || return 1
  [[ ! -e "$git_dir/commondir" && ! -e "$git_dir/objects/info/alternates" ]] || return 1
  [[ -f "$git_dir/HEAD" && ! -L "$git_dir/HEAD" ]] || return 1
  [[ ! -e "$git_dir/config" || (-f "$git_dir/config" && ! -L "$git_dir/config") ]] || return 1
  if [[ -f "$git_dir/config" ]]; then
    ! grep -Eiq '^[[:space:]]*\[(include|includeIf)([[:space:]]|\])|^[[:space:]]*(include|includeIf)\.' "$git_dir/config" || return 1
    ! grep -Eiq '^[[:space:]]*(insteadOf|pushInsteadOf)[[:space:]]*=' "$git_dir/config" || return 1
  fi
}

inventory_git_raw_source() {
  local dir="$1" config="$1/.git/config" value
  inventory_git_proof_safe "$dir" || return 1
  [[ -f "$config" ]] || return 1
  value="$(awk '
    BEGIN { section=""; count=0 }
    /^[[:space:]]*[#;]/ { next }
    /^[[:space:]]*\[/ {
      line=$0
      if (line ~ /^[[:space:]]*\[remote[[:space:]]+"(origin|upstream)"\][[:space:]]*$/) {
        sub(/^[[:space:]]*\[remote[[:space:]]+"/, "", line)
        sub(/"\][[:space:]]*$/, "", line); section=line
      } else section=""
      next
    }
    section != "" && /^[[:space:]]*url[[:space:]]*=/ {
      line=$0; sub(/^[^=]*=[[:space:]]*/, "", line)
      if (line == "" || line ~ /[[:cntrl:]]/) exit 2
      print section "\t" line; count++
    }
    END { if (count != 1) exit 3 }
  ' "$config")" || return 1
  printf '%s\n' "${value#*$'\t'}"
}

inventory_add_record() {
  local field record="" separator=""
  for field in "$@"; do
    inventory_safe_field "$field" || return 1
    record="${record}${separator}${field}"
    separator="|"
  done
  INVENTORY_RECORDS+=("$record")
}

inventory_catalog_classification() {
  local app="$1"
  if load_validated_app_catalog_record "$app" 2>/dev/null; then
    printf '%s|managed\n' "${LIB_APP_TRUST}"
  else
    printf 'unknown|unmanaged\n'
  fi
}

inventory_git_value() {
  local dir="$1" key="$2" value="" rc=0
  inventory_git_proof_safe "$dir" || return 0
  case "$key" in
    branch)
      if value="$(inventory_run_git_probe "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
        printf '%s\n' "$value"
      else
        rc=$?
        [[ "$rc" -eq 1 ]] && printf 'detached\n'
      fi
      ;;
    commit)
      value="$(inventory_run_git_probe "$dir" rev-parse --verify HEAD 2>/dev/null)" \
        && printf '%s\n' "$value"
      ;;
    source)
      inventory_git_raw_source "$dir" 2>/dev/null || true
      ;;
    state)
      if value="$(inventory_run_git_probe "$dir" status --porcelain --untracked-files=normal 2>/dev/null)"; then
        if [[ -n "$value" ]]; then
          printf 'dirty\n'
        else
          printf 'clean\n'
        fi
      fi
      ;;
  esac
  return 0
}

inventory_git_ref_absent() {
  local dir="$1" ref="$2" rc
  if inventory_run_git_probe "$dir" rev-parse --quiet --verify "$ref" >/dev/null 2>&1; then
    return 1
  else
    rc=$?
  fi
  [[ "$rc" -eq 1 ]]
}

inventory_app_version_from_tree() {
  local dir="$1" value=""
  [[ -d "$dir" ]] || return 0
  value="$(sed -nE 's/^[[:space:]]*(__version__|version)[[:space:]]*=[[:space:]]*["'\'']([^"'\'']+)["'\''].*/\2/p' \
    "$dir"/*/__init__.py "$dir"/pyproject.toml 2>/dev/null | head -n 1 || true)"
  printf '%s\n' "${value:-unknown}"
}

inventory_fixture_meta() {
  local dir="$1" key="$2"
  [[ -f "$dir/.inventory-meta" ]] || return 0
  awk -F= -v key="$key" '$1 == key {v=$0; sub(/^[^=]*=/, "", v)} END {print v}' "$dir/.inventory-meta"
}

inventory_emit_app() {
  local stack="$1" app="$2" dir="$3" fixture="${4:-0}"
  local class trust management version branch commit source repo_state
  inventory_valid_name "$app" || return 1
  class="$(inventory_catalog_classification "$app")"
  trust="${class%%|*}"
  management="${class#*|}"
  if [[ "$fixture" == 1 ]]; then
    version="$(inventory_fixture_meta "$dir" VERSION)"
    version="${version:-unknown}"
    branch="$(inventory_fixture_meta "$dir" BRANCH)"
    branch="${branch:-unknown}"
    commit="$(inventory_fixture_meta "$dir" COMMIT)"
    commit="${commit:-unknown}"
    source="$(inventory_fixture_meta "$dir" SOURCE)"
    source="${source:-unknown}"
    repo_state="$(inventory_fixture_meta "$dir" STATE)"
    repo_state="${repo_state:-ambiguous}"
  else
    version="$(inventory_app_version_from_tree "$dir")"
    branch="$(inventory_git_value "$dir" branch)"
    branch="${branch:-unknown}"
    commit="$(inventory_git_value "$dir" commit)"
    commit="${commit:-unknown}"
    source="$(inventory_git_value "$dir" source)"
    source="${source:-unknown}"
    repo_state="$(inventory_git_value "$dir" state)"
    repo_state="${repo_state:-ambiguous}"
  fi
  inventory_add_record APP "$stack" "$app" available "$version" "$branch" "$commit" "$source" "$trust" "$management" "$repo_state"
}

inventory_native_site_db_apps() {
  local site_dir="$1" db_name db_password raw
  command -v mariadb >/dev/null 2>&1 || return 2
  db_name="$(sed -nE 's/^[[:space:]]*"db_name"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_]+)".*/\1/p' "$site_dir/site_config.json" | head -n 1)"
  db_password="$(sed -nE 's/^[[:space:]]*"db_password"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$site_dir/site_config.json" | head -n 1)"
  [[ "$db_name" =~ ^[A-Za-z0-9_]+$ && -n "$db_password" ]] || return 2
  raw="$(MYSQL_PWD="$db_password" inventory_run_probe mariadb --batch --skip-column-names "$db_name" \
    -e "SELECT defvalue FROM tabDefaultValue WHERE defkey='installed_apps' AND parent='__global' LIMIT 1" 2>/dev/null)" || return 2
  [[ -n "$raw" ]] || return 2
  printf '%s\n' "$raw" | grep -oE '"[A-Za-z0-9][A-Za-z0-9_-]*"' | tr -d '"'
}

inventory_collect_tree() {
  local engine="$1" mode="$2" root="$3" fixture="${4:-0}" requested_management="${5:-}"
  local stack management state site_dir site app_dir app site_state installed app_dirs="" site_dirs=""
  stack="${engine}:${root}"
  management="${requested_management:-${ERPNEXT_DEV_INVENTORY_FIXTURE_MANAGEMENT:-managed}}"
  state="clean"
  [[ -d "$root/apps" && -d "$root/sites" ]] || state="missing"
  inventory_add_record STACK "$stack" "$engine" "$mode" "$(effective_installation_profile)" "$management" "$state"
  [[ "$state" == clean ]] || return 0

  if ! app_dirs="$(inventory_run_probe find "$root/apps" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)"; then
    inventory_add_record ISSUE "$stack" apps discovery ambiguous
  fi
  while IFS= read -r app_dir; do
    [[ -n "$app_dir" ]] || continue
    app="${app_dir##*/}"
    if ! inventory_valid_name "$app"; then
      inventory_add_record ISSUE "$stack" app invalid-name malformed
      continue
    fi
    inventory_emit_app "$stack" "$app" "$app_dir" "$fixture" \
      || inventory_add_record ISSUE "$stack" app "$app" ambiguous
  done < <(printf '%s\n' "$app_dirs" | sed '/^$/d' | LC_ALL=C sort)

  if ! site_dirs="$(inventory_run_probe find "$root/sites" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)"; then
    inventory_add_record ISSUE "$stack" sites discovery ambiguous
  fi
  while IFS= read -r site_dir; do
    [[ -n "$site_dir" ]] || continue
    site="${site_dir##*/}"
    [[ "$site" != assets ]] || continue
    if ! inventory_valid_name "$site"; then
      inventory_add_record ISSUE "$stack" site invalid-name malformed
      continue
    fi
    site_state="known"
    if [[ "$fixture" == 1 && -f "$site_dir/apps.txt" ]]; then
      installed="$(sed '/^[[:space:]]*$/d' "$site_dir/apps.txt")"
    elif [[ "$engine" == native ]]; then
      installed="$(inventory_native_site_db_apps "$site_dir" 2>/dev/null)" || site_state="ambiguous"
    else
      installed=""
      site_state="ambiguous"
    fi
    inventory_add_record SITE "$stack" "$site" "$site_state"
    while IFS= read -r app; do
      [[ -n "$app" ]] || continue
      if inventory_valid_name "$app"; then
        inventory_add_record SITE_APP "$stack" "$site" "$app" installed
      else
        inventory_add_record ISSUE "$stack" site-app invalid-name malformed
      fi
    done <<<"$installed"
  done < <(printf '%s\n' "$site_dirs" | sed '/^$/d' | LC_ALL=C sort)
}

inventory_collect_native_live() {
  local active candidate management found=0
  active="$(active_bench_dir 2>/dev/null || true)"
  while IFS= read -r candidate; do
    [[ -n "$candidate" && -d "$candidate" ]] || continue
    found=1
    if [[ "$candidate" == "$active" ]]; then
      management="managed"
    else
      management="supported-unadopted"
    fi
    inventory_collect_tree native native "$candidate" 0 "$management"
  done < <(bench_dir_candidates 2>/dev/null | awk '!seen[$0]++')
  if ((found == 0)); then
    inventory_collect_tree native native "${active:-${BENCH_DIR:-unknown}}" 0 managed
  fi
}

inventory_docker_exec() {
  local timeout_seconds
  timeout_seconds="$(inventory_probe_timeout_seconds)" || return 125
  ERPNEXT_DEV_DOCKER_COMPOSE_TIMEOUT="$timeout_seconds" docker_compose exec -T "$@"
}

inventory_docker_read() {
  inventory_docker_exec backend "$@" 2>/dev/null | tr -d '\r'
}

inventory_docker_site_apps() {
  local site="$1" config db_name db_password raw
  inventory_valid_name "$site" || return 2
  config="$(inventory_docker_read cat "sites/${site}/site_config.json")" || return 2
  db_name="$(printf '%s\n' "$config" | sed -nE 's/^[[:space:]]*"db_name"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_]+)".*/\1/p' | head -n 1)"
  db_password="$(docker_db_root_password 2>/dev/null || true)"
  [[ "$db_name" =~ ^[A-Za-z0-9_]+$ && -n "$db_password" ]] || return 2
  raw="$(inventory_docker_exec -e "MYSQL_PWD=${db_password}" db mariadb -uroot --batch --skip-column-names "$db_name" \
    -e "SELECT defvalue FROM tabDefaultValue WHERE defkey='installed_apps' AND parent='__global' LIMIT 1" 2>/dev/null)" || return 2
  [[ -n "$raw" ]] || return 2
  printf '%s\n' "$raw" | grep -oE '"[A-Za-z0-9][A-Za-z0-9_-]*"' | tr -d '"'
}

inventory_emit_docker_app() {
  local stack="$1" app="$2" image_version="unknown" source="unknown" class trust management
  class="$(inventory_catalog_classification "$app")"
  trust="${class%%|*}"
  management="${class#*|}"
  if [[ "$app" == frappe || "$app" == erpnext ]]; then
    image_version="${DOCKER_ERPNEXT_IMAGE##*:}"
    [[ "$image_version" =~ ^v?[0-9]+(\.[0-9]+)*$ ]] || image_version="unknown"
    source="image:${DOCKER_ERPNEXT_IMAGE}"
    if [[ -f "${DOCKER_CUSTOM_IMAGE_CORE_FILE:-}" ]]; then
      if [[ "$app" == frappe ]]; then
        image_version="$(docker_env_value "$DOCKER_CUSTOM_IMAGE_CORE_FILE" DOCKER_CUSTOM_IMAGE_FRAPPE_VERSION 2>/dev/null || printf unknown)"
      else
        image_version="$(docker_env_value "$DOCKER_CUSTOM_IMAGE_CORE_FILE" DOCKER_CUSTOM_IMAGE_ERPNEXT_VERSION 2>/dev/null || printf unknown)"
      fi
    fi
  fi
  inventory_add_record APP "$stack" "$app" available "$image_version" unknown unknown "$source" "$trust" "$management" immutable
}

inventory_docker_manifest_trusts_app() {
  local app="$1" expected_repo
  deployment_engine_is_docker || return 1
  [[ -f "${DOCKER_APP_MANIFEST_FILE:-}" ]] || return 1
  docker_validate_app_manifest "$DOCKER_APP_MANIFEST_FILE" || return 1
  load_validated_app_catalog_record "$app" || return 1
  expected_repo="$LIB_APP_REPO"
  awk -F'\t' -v a="$app" -v r="$expected_repo" '$1=="APP"&&$2==a&&$3==r{found=1} END{exit !found}' "$DOCKER_APP_MANIFEST_FILE"
}

inventory_collect_docker_live() {
  local stack mode site app installed sites apps site_state
  mode="$(docker_mode)"
  stack="docker:${DOCKER_PROJECT_NAME:-erpnext-dev}"
  inventory_add_record STACK "$stack" docker "$mode" "$(effective_installation_profile)" managed clean
  if ! docker_compose_available 2>/dev/null; then
    inventory_add_record ISSUE "$stack" stack docker "ambiguous"
    return 0
  fi
  if ! sites="$(inventory_docker_read find sites -mindepth 1 -maxdepth 1 -type d -printf '%f\n')"; then
    inventory_add_record ISSUE "$stack" sites docker "ambiguous"
    return 0
  fi
  if ! apps="$(inventory_docker_read find apps -mindepth 1 -maxdepth 1 -type d -printf '%f\n')"; then
    inventory_add_record ISSUE "$stack" apps docker "ambiguous"
    return 0
  fi
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if inventory_valid_name "$app"; then
      inventory_emit_docker_app "$stack" "$app"
    else
      inventory_add_record ISSUE "$stack" app invalid-name malformed
    fi
  done <<<"$apps"
  while IFS= read -r site; do
    [[ -n "$site" && "$site" != assets ]] || continue
    if ! inventory_valid_name "$site"; then
      inventory_add_record ISSUE "$stack" site invalid-name malformed
      continue
    fi
    site_state="known"
    installed="$(inventory_docker_site_apps "$site" 2>/dev/null)" || site_state="ambiguous"
    inventory_add_record SITE "$stack" "$site" "$site_state"
    while IFS= read -r app; do
      [[ -n "$app" ]] || continue
      if inventory_valid_name "$app"; then
        inventory_add_record SITE_APP "$stack" "$site" "$app" installed
      else
        inventory_add_record ISSUE "$stack" site-app invalid-name malformed
      fi
    done <<<"$installed"
  done <<<"$sites"
}

inventory_reconcile_site_apps() {
  local record stack app class trust management
  local -a snapshot=("${INVENTORY_RECORDS[@]}")
  for record in "${snapshot[@]}"; do
    [[ "${record%%|*}" == SITE_APP ]] || continue
    stack="$(printf '%s' "$record" | cut -d'|' -f2)"
    app="$(printf '%s' "$record" | cut -d'|' -f4)"
    if ! printf '%s\n' "${INVENTORY_RECORDS[@]}" \
      | awk -F'|' -v s="$stack" -v a="$app" '$1=="APP" && $2==s && $3==a {found=1} END {exit !found}'; then
      class="$(inventory_catalog_classification "$app")"
      trust="${class%%|*}"
      management="${class#*|}"
      inventory_add_record APP "$stack" "$app" missing unknown unknown unknown unknown "$trust" "$management" missing
    fi
  done
}

inventory_collect() {
  INVENTORY_RECORDS=()
  if [[ -n "${ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT:-}" ]]; then
    inventory_collect_tree "$(effective_deployment_engine)" \
      "$(deployment_engine_is_docker && docker_mode || printf native)" \
      "$ERPNEXT_DEV_INVENTORY_FIXTURE_ROOT" 1
  elif deployment_engine_is_docker; then
    inventory_collect_docker_live
  else
    inventory_collect_native_live
  fi
  inventory_reconcile_site_apps
}

inventory_records_sorted() {
  printf '%s\n' "${INVENTORY_RECORDS[@]}" | sed '/^$/d' | LC_ALL=C sort
}

inventory_usage_count() {
  local stack="$1" app="$2"
  inventory_records_sorted | awk -F'|' -v s="$stack" -v a="$app" '$1=="SITE_APP" && $2==s && $4==a {n++} END {print n+0}'
}

inventory_platform_major() {
  local app="$1" record version branch
  record="$(inventory_records_sorted | awk -F'|' -v a="$app" '$1=="APP" && $3==a {print; exit}')"
  version="$(printf '%s' "$record" | cut -d'|' -f5)"
  branch="$(printf '%s' "$record" | cut -d'|' -f6)"
  if [[ "$version" =~ ^v?([0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$branch" =~ ^version-([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

inventory_app_available() {
  local app="$1"
  inventory_records_sorted | awk -F'|' -v a="$app" '$1=="APP" && $3==a && $4=="available" {found=1} END {exit !found}'
}

inventory_catalog_dependents() {
  local target="$1" candidate dependency
  while IFS= read -r candidate; do
    load_validated_app_catalog_record "$candidate" 2>/dev/null || continue
    while IFS= read -r dependency; do
      if [[ "$dependency" == "$target" ]] && inventory_app_available "$candidate"; then
        printf '%s\n' "$candidate"
      fi
    done < <(printf '%s\n' "${LIB_APP_REQUIRES:-}" | tr ',' '\n')
  done < <(app_catalog_ids)
}

inventory_deployment_supported() {
  local engine="$1" mode="$2" native_support="$3" docker_dev_support="$4" docker_prod_strategy="$5"
  if [[ "$engine" == native ]]; then
    [[ "$native_support" == supported ]]
  elif [[ "$engine" == docker && "$mode" == development ]]; then
    [[ "$docker_dev_support" == supported ]]
  elif [[ "$engine" == docker && "$mode" == production ]]; then
    [[ "$docker_prod_strategy" != unsupported ]]
  else
    return 1
  fi
}

inventory_has_ambiguous_site() {
  inventory_records_sorted | awk -F'|' '$1=="SITE" && $4!="known" {found=1} END {exit !found}'
}

inventory_has_ambiguous_state() {
  inventory_records_sorted | awk -F'|' '
    $1=="ISSUE" {found=1}
    $1=="STACK" && $7!="clean" {found=1}
    $1=="SITE" && $4!="known" {found=1}
    $1=="APP" && $11=="ambiguous" {found=1}
    END {exit !found}
  '
}

inventory_dependency_rules_evaluate() {
  local requires="${1:-}" conflicts="${2:-}" dep
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    if ! inventory_app_available "$dep"; then
      INVENTORY_COMPAT_STATUS="INCOMPATIBLE"
      INVENTORY_COMPAT_DETAIL="Required application code is missing: ${dep}."
      return 1
    fi
  done < <(printf '%s\n' "$requires" | tr ',' '\n')
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    if inventory_app_available "$dep"; then
      INVENTORY_COMPAT_STATUS="INCOMPATIBLE"
      INVENTORY_COMPAT_DETAIL="Conflicting application code is available: ${dep}."
      return 1
    fi
  done < <(printf '%s\n' "$conflicts" | tr ',' '\n')

  return 0
}

inventory_compatibility_evaluate() {
  local app="$1" engine profile frappe_major erpnext_major record actual_source repo_state
  INVENTORY_COMPAT_STATUS="UNKNOWN"
  INVENTORY_COMPAT_DETAIL=""
  INVENTORY_COMPAT_DEPENDENTS=""
  inventory_valid_name "$app" || {
    INVENTORY_COMPAT_DETAIL="Malformed application identifier."
    return 2
  }
  if ! load_validated_app_catalog_record "$app" 2>/dev/null; then
    INVENTORY_COMPAT_DETAIL="Application is custom or unmanaged; trusted compatibility metadata is unavailable."
    return 2
  fi
  INVENTORY_COMPAT_DEPENDENTS="$(inventory_catalog_dependents "$app" | paste -sd, -)"
  load_validated_app_catalog_record "$app" 2>/dev/null || {
    INVENTORY_COMPAT_DETAIL="Catalog metadata became unavailable during evaluation."
    return 2
  }
  engine="$(effective_deployment_engine)"
  profile="$(effective_installation_profile)"
  frappe_major="$(inventory_platform_major frappe)"
  erpnext_major="$(inventory_platform_major erpnext)"
  [[ -n "$frappe_major" ]] || {
    INVENTORY_COMPAT_DETAIL="Frappe version is missing or ambiguous."
    return 2
  }
  [[ ",${LIB_APP_SUPPORTED_FRAPPE}," == *",${frappe_major},"* ]] || {
    INVENTORY_COMPAT_STATUS="INCOMPATIBLE"
    INVENTORY_COMPAT_DETAIL="Frappe ${frappe_major} is outside supported majors: ${LIB_APP_SUPPORTED_FRAPPE}."
    return 1
  }
  if [[ -n "$LIB_APP_SUPPORTED_ERPNEXT" && -n "$erpnext_major" ]] \
    && [[ ",${LIB_APP_SUPPORTED_ERPNEXT}," != *",${erpnext_major},"* ]]; then
    INVENTORY_COMPAT_STATUS="INCOMPATIBLE"
    INVENTORY_COMPAT_DETAIL="ERPNext ${erpnext_major} is outside supported majors: ${LIB_APP_SUPPORTED_ERPNEXT}."
    return 1
  fi
  inventory_dependency_rules_evaluate "${LIB_APP_REQUIRES:-}" "${LIB_APP_CONFLICTS:-}" || return 1
  if [[ "$profile" == frappe-only && ("$app" == erpnext || "$LIB_APP_REQUIRES" == *erpnext*) ]]; then
    INVENTORY_COMPAT_STATUS="INCOMPATIBLE"
    INVENTORY_COMPAT_DETAIL="Application requires ERPNext, which is excluded by the Frappe-only profile."
    return 1
  fi
  if ! inventory_deployment_supported "$engine" "$(docker_mode 2>/dev/null || printf native)" \
    "$LIB_APP_NATIVE_SUPPORT" "$LIB_APP_DOCKER_DEV_SUPPORT" "$LIB_APP_DOCKER_PROD_STRATEGY"; then
    INVENTORY_COMPAT_STATUS="INCOMPATIBLE"
    INVENTORY_COMPAT_DETAIL="Application is unsupported on the active deployment method."
    return 1
  fi
  if inventory_has_ambiguous_site; then
    INVENTORY_COMPAT_DETAIL="One or more site application inventories are ambiguous; shared-stack impact cannot be proven."
    return 2
  fi
  record="$(inventory_records_sorted | awk -F'|' -v a="$app" '$1=="APP" && $3==a {print; exit}')"
  actual_source="$(printf '%s' "$record" | cut -d'|' -f8)"
  repo_state="$(printf '%s' "$record" | cut -d'|' -f11)"
  if [[ -n "$record" ]]; then
    if [[ "$repo_state" == dirty || "$repo_state" == ambiguous ]]; then
      INVENTORY_COMPAT_DETAIL="Available application code state is ${repo_state}; compatibility cannot be proven."
      return 2
    fi
    if [[ "$actual_source" == unknown ]]; then
      INVENTORY_COMPAT_DETAIL="Available application source is unknown; trust cannot be proven."
      return 2
    fi
    if [[ "$actual_source" == image:* ]]; then
      if [[ "$engine" != docker ]] || { [[ "$actual_source" != image:frappe/erpnext:* || ("$app" != frappe && "$app" != erpnext) ]] \
        && ! inventory_docker_manifest_trusts_app "$app"; }; then
        INVENTORY_COMPAT_DETAIL="Available image source is not a trusted built-in platform source."
        return 2
      fi
    elif [[ "${actual_source%.git}" != "${LIB_APP_REPO%.git}" ]]; then
      INVENTORY_COMPAT_DETAIL="Available code source does not match the trusted catalog source."
      return 2
    fi
  fi
  INVENTORY_COMPAT_STATUS="COMPATIBLE"
  INVENTORY_COMPAT_DETAIL="Catalog, platform major, dependencies, profile, deployment method, and known source checks passed."
  return 0
}

inventory_json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

inventory_emit_json() {
  local first=1 record
  printf '{"schema_version":1,"read_only":true,"records":['
  while IFS= read -r record; do
    ((first)) || printf ','
    first=0
    inventory_json_escape "$record"
  done < <(inventory_records_sorted)
  printf ']}\n'
}

inventory_show_apps() {
  local record stack app usage support
  inventory_collect
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    inventory_emit_json
    return
  fi
  printf 'APPLICATION\tCODE\tSITE_USAGE\tTRUST\tMANAGEMENT\tSTATE\tDEPLOYMENT_SUPPORT\n'
  while IFS= read -r record; do
    [[ "${record%%|*}" == APP ]] || continue
    stack="$(printf '%s' "$record" | cut -d'|' -f2)"
    app="$(printf '%s' "$record" | cut -d'|' -f3)"
    usage="$(inventory_usage_count "$stack" "$app")"
    support="unknown"
    if load_validated_app_catalog_record "$app" 2>/dev/null; then
      if [[ "$(effective_deployment_engine)" == native ]]; then
        support="$LIB_APP_NATIVE_SUPPORT"
      elif [[ "$(docker_mode)" == production ]]; then
        support="$LIB_APP_DOCKER_PROD_STRATEGY"
      else
        support="$LIB_APP_DOCKER_DEV_SUPPORT"
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$app" "$(printf '%s' "$record" | cut -d'|' -f4)" "$usage" \
      "$(printf '%s' "$record" | cut -d'|' -f9)" "$(printf '%s' "$record" | cut -d'|' -f10)" \
      "$(printf '%s' "$record" | cut -d'|' -f11)" "$support"
  done < <(inventory_records_sorted)
}

inventory_show_sites() {
  local record stack site apps
  inventory_collect
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    inventory_emit_json
    return
  fi
  printf 'SITE\tSTACK\tINSTALLED_APPS\tDISCOVERY_STATE\n'
  while IFS= read -r record; do
    [[ "${record%%|*}" == SITE ]] || continue
    stack="$(printf '%s' "$record" | cut -d'|' -f2)"
    site="$(printf '%s' "$record" | cut -d'|' -f3)"
    apps="$(inventory_records_sorted | awk -F'|' -v s="$stack" -v site="$site" \
      '$1=="SITE_APP" && $2==s && $3==site {print $4}' | paste -sd, -)"
    printf '%s\t%s\t%s\t%s\n' "$site" "$stack" "${apps:-unknown}" "$(printf '%s' "$record" | cut -d'|' -f4)"
  done < <(inventory_records_sorted)
}

inventory_show_status() {
  inventory_collect
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    inventory_emit_json
  else
    printf 'TYPE\tSTACK\tSUBJECT\tSTATE\tDETAIL\n'
    inventory_records_sorted | awk -F'|' '
      $1=="STACK" {printf "STACK\t%s\t%s/%s\t%s\tprofile=%s; management=%s\n",$2,$3,$4,$7,$5,$6}
      $1=="APP" {printf "APP\t%s\t%s\tcode-%s\ttrust=%s; management=%s; repo=%s\n",$2,$3,$4,$9,$10,$11}
      $1=="SITE" {printf "SITE\t%s\t%s\t%s\tinstalled apps are separate SITE_APP records\n",$2,$3,$4}
      $1=="SITE_APP" {printf "SITE_APP\t%s\t%s/%s\t%s\tsite-level installation\n",$2,$3,$4,$5}
      $1=="ISSUE" {printf "ISSUE\t%s\t%s/%s\t%s\tdiscovery did not infer state\n",$2,$3,$4,$5}
    '
  fi
}

inventory_show_compatibility() {
  local app="$1" rc=0 record stack usage
  inventory_collect
  if inventory_compatibility_evaluate "$app"; then
    rc=0
  else
    rc=$?
  fi
  record="$(inventory_records_sorted | awk -F'|' -v a="$app" '$1=="APP" && $3==a {print; exit}')"
  stack="$(printf '%s' "$record" | cut -d'|' -f2)"
  usage=0
  [[ -n "$stack" ]] && usage="$(inventory_usage_count "$stack" "$app")"
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    printf '{"schema_version":1,"read_only":true,"application":'
    inventory_json_escape "$app"
    printf ',"status":'
    inventory_json_escape "$INVENTORY_COMPAT_STATUS"
    printf ',"detail":'
    inventory_json_escape "$INVENTORY_COMPAT_DETAIL"
    printf ',"site_usage":%s,"dependents":' "$usage"
    inventory_json_escape "${INVENTORY_COMPAT_DEPENDENTS:-}"
    printf '}\n'
  else
    printf 'Application: %s\nStatus: %s\nDetail: %s\nUsed by sites: %s\nDependents: %s\nEngine: %s\nProfile: %s\n' \
      "$app" "$INVENTORY_COMPAT_STATUS" "$INVENTORY_COMPAT_DETAIL" "$usage" \
      "${INVENTORY_COMPAT_DEPENDENTS:-none}" "$(effective_deployment_engine)" "$(effective_installation_profile)"
  fi
  return "$rc"
}

run_app_inventory_command() {
  local subcommand="${1:-status}" app="${2:-}"
  case "$subcommand" in
    list)
      [[ -z "$app" ]] || fail "Usage: $(toolkit_cmd app list)"
      inventory_show_apps
      ;;
    status)
      [[ -z "$app" ]] || fail "Usage: $(toolkit_cmd app status)"
      inventory_show_status
      ;;
    compatibility)
      [[ -n "$app" ]] || fail "Usage: $(toolkit_cmd app compatibility APP)"
      inventory_valid_name "$app" || fail "Invalid application identifier: ${app}"
      inventory_show_compatibility "$app"
      ;;
    *) fail "Unknown app inventory command: ${subcommand}" ;;
  esac
}

run_site_inventory_command() {
  local subcommand="${1:-list}" extra="${2:-}"
  case "$subcommand" in
    list)
      [[ -z "$extra" ]] || fail "Usage: $(toolkit_cmd site list)"
      inventory_show_sites
      ;;
    *) fail "Unknown site inventory command: ${subcommand}" ;;
  esac
}
