# shellcheck shell=bash disable=SC2034
# Existing-installation discovery and configuration-only adoption.

[[ -n "${_ERPNEXT_DEV_ADOPTION_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_ADOPTION_LOADED=1

declare -ag ADOPTION_CANDIDATES=()
ADOPTION_SELECTED_RECORD=""

adoption_sha256() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }

adoption_valid_atom() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]
}

adoption_path_safe() {
  local path="$1" current="" component owner mode uid group_digit other_digit
  [[ "$path" == /* && -d "$path" && ! -L "$path" ]] || return 1
  [[ "$(realpath -e -- "$path" 2>/dev/null)" == "$path" ]] || return 1
  IFS=/ read -r -a _adoption_parts <<<"${path#/}"
  for component in "${_adoption_parts[@]}"; do
    [[ -n "$component" ]] || continue
    current="${current}/${component}"
    [[ ! -L "$current" ]] || return 1
  done
  owner="$(stat -c %u -- "$path" 2>/dev/null)" || return 1
  mode="$(stat -c %a -- "$path" 2>/dev/null)" || return 1
  uid="${EUID:-$(id -u)}"
  [[ "$owner" =~ ^[0-9]+$ ]] || return 1
  if [[ "$uid" == 0 ]]; then
    [[ "$owner" == 0 \
      || (-n "${FRAPPE_USER:-}" && "$(getent passwd "$owner" 2>/dev/null | cut -d: -f1)" == "$FRAPPE_USER") ]] || return 1
  else
    [[ "$owner" == "$uid" ]] || return 1
  fi
  # A candidate root must not be writable by group or other.
  group_digit=$(((10#$mode / 10) % 10))
  other_digit=$((10#$mode % 10))
  (( (group_digit & 2) == 0 && (other_digit & 2) == 0 )) || return 1
}

adoption_source_trusted() {
  case "${1%.git}" in
    https://github.com/frappe/frappe|git@github.com:frappe/frappe) return 0 ;;
    *) return 1 ;;
  esac
}

adoption_supported_frappe_major() {
  case "$1" in 14|15|16) return 0 ;; *) return 1 ;; esac
}

adoption_candidate_add() {
  [[ $# -eq 8 ]] || return 1
  adoption_valid_atom "$1" && adoption_valid_atom "$2" && adoption_valid_atom "$3" \
    && adoption_valid_atom "$4" && adoption_valid_atom "$5" && [[ "$6" =~ ^[0-9]+$ ]] \
    && [[ "$7" =~ ^[a-z0-9_.-]+(,[a-z0-9_.-]+)*$ ]] && [[ "$8" =~ ^[a-f0-9]{64}$ ]] || return 1
  ADOPTION_CANDIDATES+=("$(IFS='|'; printf '%s' "$*")")
}

adoption_native_site_apps() {
  local bench="$1" site="$2" line app
  if [[ "${ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES:-0}" != 1 ]]; then
    inventory_native_site_db_apps "$bench/sites/$site"
    return
  fi
  [[ -f "$bench/sites/$site/apps.txt" && ! -L "$bench/sites/$site/apps.txt" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    app="${line%%[[:space:]]*}"
    [[ -z "$app" ]] && continue
    adoption_valid_atom "$app" || return 1
    printf '%s\n' "$app"
  done <"$bench/sites/$site/apps.txt"
}

adoption_native_probe() {
  local bench="$1" source state version major site apps app sites_seen=0 id apps_csv
  adoption_path_safe "$bench" || return 1
  if [[ "${EUID:-$(id -u)}" == 0 && "$(stat -c %u -- "$bench")" != "$(id -u "$FRAPPE_USER" 2>/dev/null)" ]]; then return 1; fi
  [[ -d "$bench/apps/frappe/.git" && ! -L "$bench/apps" && ! -L "$bench/sites" ]] || return 1
  source="$(inventory_git_value "$bench/apps/frappe" source)"
  state="$(inventory_git_value "$bench/apps/frappe" state)"
  version="$(inventory_app_version_from_tree "$bench/apps/frappe")"
  major="${version#v}"; major="${major%%.*}"
  adoption_source_trusted "$source" || return 2
  [[ "$state" == clean ]] || return 3
  adoption_supported_frappe_major "$major" || return 2
  while IFS= read -r site; do
    [[ -n "$site" && "$site" != assets ]] || continue
    adoption_valid_atom "$site" || return 1
    [[ -d "$bench/sites/$site" && ! -L "$bench/sites/$site" ]] || return 1
    apps="$(adoption_native_site_apps "$bench" "$site")" || return 1
    printf '%s\n' "$apps" | grep -Fxq frappe || return 2
    while IFS= read -r app; do
      [[ -d "$bench/apps/$app" && ! -L "$bench/apps/$app" ]] || return 1
    done <<<"$apps"
    apps_csv="$(printf '%s\n' "$apps" | LC_ALL=C sort -u | paste -sd, -)"
    id="n-$(adoption_sha256 "$bench" | cut -c1-20)"
    adoption_candidate_add native development "$id" "$site" compatible "$major" "$apps_csv" \
      "$(adoption_sha256 "native|$bench|$site|$major|$apps_csv")" || return 1
    ADOPTION_CANDIDATE_PATHS["$id|$site"]="$bench"
    sites_seen=$((sites_seen + 1))
  done < <(find -P "$bench/sites" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort)
  ((sites_seen > 0))
}

adoption_docker_probe_fixture() {
  # Test-only data adapter. It is disabled unless the explicit hermetic flag is
  # set and is never consulted by production discovery.
  local root="$1" file engine mode project site major digest apps reconstructible id
  file="$root/.toolkit-adoption-fixture"
  [[ "${ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES:-0}" == 1 && -f "$file" && ! -L "$file" ]] || return 1
  engine="$(read_config_key_from_file "$file" ENGINE 2>/dev/null || true)"
  mode="$(read_config_key_from_file "$file" MODE 2>/dev/null || true)"
  project="$(read_config_key_from_file "$file" PROJECT 2>/dev/null || true)"
  site="$(read_config_key_from_file "$file" SITE 2>/dev/null || true)"
  major="$(read_config_key_from_file "$file" FRAPPE_MAJOR 2>/dev/null || true)"
  digest="$(read_config_key_from_file "$file" IMAGE_DIGEST 2>/dev/null || true)"
  apps="$(read_config_key_from_file "$file" APPS 2>/dev/null || true)"
  reconstructible="$(read_config_key_from_file "$file" RECONSTRUCTIBLE 2>/dev/null || true)"
  [[ "$engine" == docker && ("$mode" == development || "$mode" == production) ]] || return 2
  adoption_valid_atom "$project" && adoption_valid_atom "$site" || return 1
  adoption_supported_frappe_major "$major" || return 2
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ && "$apps" =~ ^[a-z0-9_.-]+(,[a-z0-9_.-]+)*$ ]] || return 1
  [[ "$mode" != production || "$reconstructible" == true ]] || return 2
  id="d-$(adoption_sha256 "$root|$project" | cut -c1-20)"
  adoption_candidate_add docker "$mode" "$id" "$site" compatible "$major" "$apps" \
    "$(adoption_sha256 "docker|$root|$project|$site|$major|$digest|$apps|$reconstructible")" || return 1
  ADOPTION_CANDIDATE_PATHS["$id|$site"]="$root"
  ADOPTION_CANDIDATE_PROJECTS["$id|$site"]="$project"
}

adoption_docker_manifest_apps() {
  local file="$1" kind app repo ref
  [[ -f "$file" && ! -L "$file" ]] || return 1
  while IFS=$'\t' read -r kind app repo ref _; do
    [[ "$kind" == APP ]] || continue
    adoption_valid_atom "$app" || return 1
    [[ "$repo" == https://github.com/* && "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
    printf '%s\n' "$app"
  done <"$file"
}

adoption_docker_probe_live() {
  local root="$1" ids id project="" service image_id app_image_id="" digest="" sites_source=""
  local mode=development site apps apps_csv major manifest_apps reconstructible=false candidate_id image_version repo_digest
  local -A services=()
  adoption_path_safe "$root" || return 1
  command -v docker >/dev/null 2>&1 || return 1
  ids="$(inventory_run_probe docker ps --filter "label=com.docker.compose.project.working_dir=$root" --format '{{.ID}}' 2>/dev/null)" || return 1
  [[ -n "$ids" ]] || return 1
  while IFS= read -r id; do
    [[ "$id" =~ ^[a-f0-9]{12,64}$ ]] || return 1
    project="$(inventory_run_probe docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$id" 2>/dev/null)" || return 1
    service="$(inventory_run_probe docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$id" 2>/dev/null)" || return 1
    adoption_valid_atom "$project" && adoption_valid_atom "$service" || return 1
    case "$service" in backend|frontend|websocket|queue-short|queue-long|scheduler|configurator|db|redis-cache|redis-queue) ;; *) return 2 ;; esac
    [[ -z "${services[$service]:-}" ]] || return 2
    services["$service"]=1
    image_id="$(inventory_run_probe docker inspect --format '{{.Image}}' "$id" 2>/dev/null)" || return 1
    case "$service" in backend|frontend|websocket|queue-short|queue-long|scheduler)
      [[ -z "$app_image_id" || "$app_image_id" == "$image_id" ]] || return 2
      app_image_id="$image_id"
      ;;
    esac
    if [[ "$service" == backend ]]; then
      sites_source="$(inventory_run_probe docker inspect --format '{{range .Mounts}}{{if eq .Destination "/home/frappe/frappe-bench/sites"}}{{.Source}}{{end}}{{end}}' "$id" 2>/dev/null)" || return 1
    fi
  done <<<"$ids"
  [[ -n "$project" && -n "$app_image_id" && -n "$sites_source" ]] || return 1
  [[ -n "${services[backend]:-}" && -n "${services[frontend]:-}" ]] || return 2
  adoption_path_safe "$sites_source" || return 1
  repo_digest="$(inventory_run_probe docker image inspect --format '{{index .RepoDigests 0}}' "$app_image_id" 2>/dev/null)" || return 1
  digest="${repo_digest##*@}"
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || return 2
  image_version="$(inventory_run_probe docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$app_image_id" 2>/dev/null)" || return 1
  major="${image_version#v}"; major="${major%%.*}"
  adoption_supported_frappe_major "$major" || return 2
  [[ -f "$root/compose.yaml" ]] && mode=production
  if [[ "$mode" == production ]]; then
    manifest_apps="$(adoption_docker_manifest_apps "$root/erpnext-dev.app-manifest.tsv" 2>/dev/null)" || return 2
    printf '%s\n' "$manifest_apps" | grep -Fxq frappe || return 2
    reconstructible=true
  elif [[ "$repo_digest" != frappe/erpnext@* && "$repo_digest" != ghcr.io/frappe/*@* ]]; then
    return 2
  fi
  while IFS= read -r site; do
    [[ -n "$site" && "$site" != assets ]] || continue
    adoption_valid_atom "$site" || return 1
    [[ -d "$sites_source/$site" && ! -L "$sites_source/$site" ]] || return 1
    apps="$(adoption_native_site_apps "${sites_source%/sites}" "$site")" || return 1
    printf '%s\n' "$apps" | grep -Fxq frappe || return 2
    if [[ "$mode" == production ]]; then
      while IFS= read -r app; do printf '%s\n' "$manifest_apps" | grep -Fxq "$app" || return 2; done <<<"$apps"
    fi
    apps_csv="$(printf '%s\n' "$apps" | LC_ALL=C sort -u | paste -sd, -)"
    candidate_id="d-$(adoption_sha256 "$root|$project" | cut -c1-20)"
    adoption_candidate_add docker "$mode" "$candidate_id" "$site" compatible "$major" "$apps_csv" \
      "$(adoption_sha256 "docker|$root|$project|$site|$major|$digest|$apps_csv|$reconstructible")" || return 1
    ADOPTION_CANDIDATE_PATHS["$candidate_id|$site"]="$root"
    ADOPTION_CANDIDATE_PROJECTS["$candidate_id|$site"]="$project"
  done < <(find -P "$sites_source" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort)
}

adoption_discovery_roots() {
  local root
  if [[ -n "${ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS:-}" ]]; then
    tr ':' '\n' <<<"$ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS"
    return
  fi
  bench_dir_candidates 2>/dev/null || true
  root="${DOCKER_WORKDIR:-/opt/erpnext-dev/docker}/frappe_docker"
  printf '%s\n' "$root"
}

adoption_discover() {
  local root canonical
  ADOPTION_CANDIDATES=()
  declare -gA ADOPTION_CANDIDATE_PATHS=() ADOPTION_CANDIDATE_PROJECTS=()
  while IFS= read -r root; do
    [[ -n "$root" && "$root" == /* && -d "$root" && ! -L "$root" ]] || continue
    canonical="$(realpath -e -- "$root" 2>/dev/null)" || continue
    [[ "$canonical" == "$root" ]] || continue
    if [[ -d "$root/apps/frappe" && -d "$root/sites" ]]; then
      adoption_native_probe "$root" >/dev/null 2>&1 || true
    elif [[ -f "$root/compose.yaml" || -f "$root/pwd.yml" || -f "$root/.toolkit-adoption-fixture" ]]; then
      if [[ "${ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES:-0}" == 1 ]]; then
        adoption_docker_probe_fixture "$root" >/dev/null 2>&1 || true
      else
        adoption_docker_probe_live "$root" >/dev/null 2>&1 || true
      fi
    fi
  done < <(adoption_discovery_roots | LC_ALL=C sort -u)
  if ((${#ADOPTION_CANDIDATES[@]})); then
    mapfile -t ADOPTION_CANDIDATES < <(printf '%s\n' "${ADOPTION_CANDIDATES[@]}" | LC_ALL=C sort)
  fi
}

adoption_select_exact() {
  local selector="$1" record engine mode id site rest matches=0
  [[ "$selector" =~ ^(native|docker):([nd]-[a-f0-9]{20}):([A-Za-z0-9][A-Za-z0-9_.-]{0,127})$ ]] || return 20
  for record in "${ADOPTION_CANDIDATES[@]}"; do
    IFS='|' read -r engine mode id site rest <<<"$record"
    if [[ "$selector" == "$engine:$id:$site" ]]; then ADOPTION_SELECTED_RECORD="$record"; matches=$((matches + 1)); fi
  done
  ((matches == 1)) || return 21
}

adoption_metadata_matches_discovery() {
  local record engine mode id site compatibility major apps fingerprint matches=0
  [[ "${PROFILE_METADATA_ADOPTION_VALID:-false}" == true ]] || return 1
  adoption_discover
  for record in "${ADOPTION_CANDIDATES[@]}"; do
    IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$record"
    if [[ "$id" == "$PROFILE_METADATA_ADOPTION_TARGET" \
      && "$site" == "$PROFILE_METADATA_ADOPTION_SITE" \
      && "$fingerprint" == "$PROFILE_METADATA_ADOPTION_FINGERPRINT" ]]; then
      matches=$((matches + 1))
    fi
  done
  ((matches == 1))
}

adoption_render_preview() {
  local record engine mode id site compatibility major apps fingerprint first=1
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    printf '{"schema_version":2,"operation":"existing-adoption","read_only":true,"candidates":['
    for record in "${ADOPTION_CANDIDATES[@]}"; do
      IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$record"
      ((first)) || printf ','; first=0
      printf '{"selector":'; inventory_json_escape "$engine:$id:$site"
      printf ',"engine":'; inventory_json_escape "$engine"
      printf ',"environment":'; inventory_json_escape "$mode"
      printf ',"site":'; inventory_json_escape "$site"
      printf ',"applications":'; inventory_json_escape "$apps"
      printf ',"compatibility":'; inventory_json_escape "$compatibility"
      printf ',"capability":"configuration-only","inventory_fingerprint":'; inventory_json_escape "$fingerprint"
      printf '}'
    done
    printf '],"mutation":false}\n'
    return
  fi
  printf 'Existing-installation discovery (read-only)\n'
  if ((${#ADOPTION_CANDIDATES[@]} == 0)); then printf 'Candidates: none\n'; fi
  for record in "${ADOPTION_CANDIDATES[@]}"; do
    IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$record"
    printf 'Target: %s:%s:%s\nEngine: %s\nEnvironment: %s\nSite: %s\nApplications: %s\nCompatibility: %s (Frappe %s)\nCapability: configuration-only; deployment mutation prohibited\nInventory fingerprint: %s\n\n' \
      "$engine" "$id" "$site" "$engine" "$mode" "$site" "$apps" "$compatibility" "$major" "$fingerprint"
  done
  printf 'NO DEPLOYMENT MUTATION OCCURRED.\n'
}

adoption_file_fingerprint() {
  local file="$1"
  [[ -f "$file" && ! -L "$file" ]] && sha256sum "$file" | awk '{print $1}' || printf absent
}

adoption_config_pair_fingerprint() {
  adoption_sha256 "primary=$(adoption_file_fingerprint "$CONFIG_FILE")|legacy=$(adoption_file_fingerprint "$LEGACY_CONFIG_FILE")"
}

adoption_config_value_safe() {
  [[ "${1:-}" != *$'\n'* && "${1:-}" != *$'\r'* && "${1:-}" != *$'\t'* \
    && "${1:-}" != *'$('* && "${1:-}" != *'`'* ]]
}

adoption_stage_config() {
  local source="$1" output="$2" engine="$3" mode="$4" id="$5" site="$6" fingerprint="$7" path="$8" project="$9"
  local key line value
  : >"$output" || return 1
  chmod 600 "$output" || return 1
  if [[ -f "$source" && ! -L "$source" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
      key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
      case "$key" in CONFIG_SCHEMA|INSTALLATION_PROFILE|INSTALLATION_PROFILE_APPS|DEPLOYMENT_ENGINE|DOCKER_MODE|SITE_NAME|DOCKER_SITE_NAME|BENCH_DIR|ADOPTION_*|*PASSWORD*|*TOKEN*|*SECRET*|*CREDENTIAL*|*PRIVATE*) continue ;; esac
      adoption_config_value_safe "$value" || continue
      printf '%s=%s\n' "$key" "$value" >>"$output"
    done <"$source"
  fi
  {
    printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=existing\nINSTALLATION_PROFILE_APPS=\n'
    printf 'DEPLOYMENT_ENGINE=%s\nDOCKER_MODE=%s\nSITE_NAME=%s\n' "$engine" "$mode" "$site"
    [[ "$engine" == docker ]] && printf 'DOCKER_SITE_NAME=%s\n' "$site"
    [[ "$engine" == native ]] && printf 'BENCH_DIR=%s\n' "$path"
    printf 'ADOPTION_TARGET_ID=%s\nADOPTION_SITE=%s\nADOPTION_INVENTORY_FINGERPRINT=%s\n' "$id" "$site" "$fingerprint"
    [[ -n "$project" ]] && printf 'ADOPTION_DOCKER_PROJECT=%s\n' "$project"
  } >>"$output"
  return 0
}

adoption_write_mirrors() {
  local staged="$1" primary_tmp legacy_tmp primary_rollback="" primary_existed=false
  primary_tmp="${CONFIG_FILE}.adopt.$$"
  legacy_tmp="${LEGACY_CONFIG_FILE}.adopt.$$"
  [[ ! -L "$CONFIG_FILE" && ! -L "$LEGACY_CONFIG_FILE" ]] || return 1
  $SUDO mkdir -p "$(dirname "$CONFIG_FILE")" "$(dirname "$LEGACY_CONFIG_FILE")" || return 1
  $SUDO cp -- "$staged" "$primary_tmp" || return 1
  $SUDO chmod 600 "$primary_tmp" || return 1
  if [[ "$LEGACY_CONFIG_FILE" != "$CONFIG_FILE" ]]; then
    $SUDO cp -- "$staged" "$legacy_tmp" || return 1
    $SUDO chmod 600 "$legacy_tmp" || return 1
  fi
  if [[ -f "$CONFIG_FILE" ]]; then
    primary_existed=true
    primary_rollback="${CONFIG_FILE}.rollback.$$"
    $SUDO cp -- "$CONFIG_FILE" "$primary_rollback" || return 1
    $SUDO chmod 600 "$primary_rollback" || return 1
  fi
  $SUDO mv -f "$primary_tmp" "$CONFIG_FILE" || return 1
  if [[ "$LEGACY_CONFIG_FILE" != "$CONFIG_FILE" ]] && ! $SUDO mv -f "$legacy_tmp" "$LEGACY_CONFIG_FILE"; then
    if [[ -n "$primary_rollback" ]]; then $SUDO mv -f "$primary_rollback" "$CONFIG_FILE" || return 3; fi
    if [[ "$primary_existed" == false ]]; then $SUDO rm -f -- "$CONFIG_FILE" || return 3; fi
    return 2
  fi
  [[ -z "$primary_rollback" ]] || $SUDO rm -f -- "$primary_rollback"
}

adoption_restore_prior_config() {
  local prior="$1" prior_legacy="$2" prior_primary_fp="$3" prior_legacy_fp="$4" candidate_fingerprint="$5" primary_tmp legacy_tmp
  [[ "$(adoption_file_fingerprint "$CONFIG_FILE")" == "$candidate_fingerprint" \
    && "$(adoption_file_fingerprint "$LEGACY_CONFIG_FILE")" == "$candidate_fingerprint" ]] || return 1
  primary_tmp="${CONFIG_FILE}.restore.$$"; legacy_tmp="${LEGACY_CONFIG_FILE}.restore.$$"
  if [[ "$prior_primary_fp" != absent ]]; then
    [[ "$(adoption_file_fingerprint "$prior")" == "$prior_primary_fp" ]] || return 1
    $SUDO cp -- "$prior" "$primary_tmp" || return 1
  fi
  if [[ "$prior_legacy_fp" != absent ]]; then
    [[ "$(adoption_file_fingerprint "$prior_legacy")" == "$prior_legacy_fp" ]] || return 1
    $SUDO cp -- "$prior_legacy" "$legacy_tmp" || return 1
  fi
  if [[ "$prior_primary_fp" == absent ]]; then $SUDO rm -f -- "$CONFIG_FILE"; else $SUDO mv -f "$primary_tmp" "$CONFIG_FILE" || return 1; fi
  if [[ "$prior_legacy_fp" == absent ]]; then $SUDO rm -f -- "$LEGACY_CONFIG_FILE"; else $SUDO mv -f "$legacy_tmp" "$LEGACY_CONFIG_FILE" || return 1; fi
}

adoption_transaction() {
  local reviewed="$ADOPTION_SELECTED_RECORD" engine mode id site compatibility major apps fingerprint path project
  local previous previous_primary previous_legacy_fp config_stage recovery_dir previous_copy previous_legacy candidate_fp
  IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$reviewed"
  previous_primary="$(adoption_file_fingerprint "$CONFIG_FILE")"
  previous_legacy_fp="$(adoption_file_fingerprint "$LEGACY_CONFIG_FILE")"
  previous="$(adoption_config_pair_fingerprint)"
  acquire_toolkit_lock
  adoption_discover
  adoption_select_exact "$engine:$id:$site" || return 34
  [[ "$ADOPTION_SELECTED_RECORD" == "$reviewed" ]] || return 34
  [[ "$(adoption_config_pair_fingerprint)" == "$previous" ]] || return 34
  path="${ADOPTION_CANDIDATE_PATHS["$id|$site"]}"; project="${ADOPTION_CANDIDATE_PROJECTS["$id|$site"]:-}"
  if [[ -f "$CONFIG_FILE" ]]; then
    read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1 || return 34
    if [[ "$PROFILE_METADATA_SCHEMA" == 2 && "$PROFILE_METADATA_PROFILE" == existing ]]; then
      [[ "$(read_config_key_from_file "$CONFIG_FILE" ADOPTION_TARGET_ID 2>/dev/null || true)" == "$id" \
        && "$(read_config_key_from_file "$CONFIG_FILE" ADOPTION_SITE 2>/dev/null || true)" == "$site" ]] && { ok "Exact target is already adopted; configuration was not rewritten."; return 0; }
      return 34
    fi
  fi
  recovery_dir="${ADOPTION_RECOVERY_DIR:-$(dirname "$CONFIG_FILE")/adoption-recovery}"
  $SUDO mkdir -p "$recovery_dir" || return 31; $SUDO chmod 700 "$recovery_dir" || return 31
  previous_copy="$recovery_dir/prior-${id}-$(date -u +%Y%m%dT%H%M%SZ).conf"
  previous_legacy="${previous_copy}.legacy"
  if [[ -f "$CONFIG_FILE" ]]; then $SUDO cp -- "$CONFIG_FILE" "$previous_copy" || return 31; else $SUDO touch "$previous_copy" || return 31; fi
  if [[ -f "$LEGACY_CONFIG_FILE" ]]; then $SUDO cp -- "$LEGACY_CONFIG_FILE" "$previous_legacy" || return 31; else $SUDO touch "$previous_legacy" || return 31; fi
  $SUDO chmod 600 "$previous_copy" || return 31
  $SUDO chmod 600 "$previous_legacy" || return 31
  config_stage="$(mktemp "${TMPDIR:-/tmp}/erpnext-adoption.XXXXXX")" || return 31
  adoption_stage_config "$CONFIG_FILE" "$config_stage" "$engine" "$mode" "$id" "$site" "$fingerprint" "$path" "$project" || return 31
  candidate_fp="$(sha256sum "$config_stage" | awk '{print $1}')"
  OPERATION_TYPE=existing-adoption
  OPERATION_TARGET_SET="$engine:$id:$site"
  OPERATION_SELECTED_SITES="$site"
  PLAN_INVENTORY_FINGERPRINT="$fingerprint"
  PLAN_STARTED_AT="$(planner_timestamp)"
  OPERATION_STATUS=adopting
  OPERATION_BACKUP_REFERENCE="$previous_copy"
  OPERATION_PREVIOUS_REVISIONS="$previous"
  OPERATION_REPLACEMENT_IMAGE="$candidate_fp"
  OPERATION_ADOPTION_ENGINE="$engine"
  OPERATION_ADOPTION_ENVIRONMENT="$mode"
  OPERATION_ADOPTION_FINGERPRINT="$fingerprint"
  OPERATION_PREVIOUS_CONFIG_FINGERPRINT="$previous"
  OPERATION_CANDIDATE_CONFIG_FINGERPRINT="$candidate_fp"
  OPERATION_RECOVERY="Restore the protected prior configuration only after proving this mutation boundary."
  OPERATION_ID="${OPERATION_ID_OVERRIDE:-$(date -u +%Y%m%dT%H%M%SZ)-$$-adoption}"
  OPERATION_FILE="${OPERATION_STATE_DIR}/${OPERATION_ID}.state"
  OPERATION_CHECKPOINTS=confirmed
  PLAN_APP=""
  PLAN_CATALOG_ID=""
  PLAN_INSTALL_NAME=""
  PLAN_STACK="$engine:$id"
  PLAN_BENCH="$path"
  PLAN_SITE="$site"
  PLAN_CURRENT_PROFILE="${PROFILE_METADATA_PROFILE:-unmanaged}"
  PLAN_RESULT_PROFILE=existing
  PLAN_CODE_STATE=observed
  PLAN_SITE_STATE=known
  PLAN_DEPENDENCIES=""
  PLAN_COMPATIBILITY="$compatibility"
  PLAN_TRUST=validated
  PLAN_SHARED_SITES=""
  PLAN_ACTIONS=replace-toolkit-configuration
  PLAN_VERIFICATION=inventory-and-configuration-reconciliation
  planner_record_write || return 31
  planner_checkpoint configuration-staged adopting || return 31
  adoption_write_mirrors "$config_stage" || { planner_fail_record replace "Atomic configuration replacement failed." "Prior configuration: $previous_copy" failed-safe; return 31; }
  if ! read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1 \
    || { adoption_discover; ! adoption_select_exact "$engine:$id:$site"; } \
    || [[ "$ADOPTION_SELECTED_RECORD" != "$reviewed" ]]; then
    if adoption_restore_prior_config "$previous_copy" "$previous_legacy" "$previous_primary" "$previous_legacy_fp" "$candidate_fp"; then
      planner_fail_record verify "Post-write verification failed; prior configuration was restored." \
        "Create a fresh preview before retrying." verification-failed
      return 32
    fi
    planner_fail_record verify "Post-write verification failed and the safe restoration boundary could not be proven." \
      "Recovery required; retain active and prior configuration artifacts." recovery-required
    return 33
  fi
  OPERATION_STATUS=complete
  PLAN_COMPLETED_AT="$(planner_timestamp)"
  planner_checkpoint verified complete || return 32
  rm -f -- "$config_stage"
  ok "Existing deployment adopted for Toolkit management; deployment state was not changed."
}

run_existing_installation_workflow() {
  local reply record engine mode id site rest
  adoption_discover
  if [[ "$QUICK_INSTALL_PREVIEW" -eq 1 ]]; then
    if [[ -n "$EXISTING_TARGET_SELECTOR" ]]; then
      adoption_select_exact "$EXISTING_TARGET_SELECTOR" || { err "The exact target is invalid, stale, or ambiguous."; return 21; }
      ADOPTION_CANDIDATES=("$ADOPTION_SELECTED_RECORD")
    fi
    adoption_render_preview
    return 0
  fi
  if ! setup_input_is_interactive && [[ "${ASSUME_YES:-0}" -ne 1 ]]; then
    err "Non-interactive adoption requires --yes and an exact --target."
    return 21
  fi
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
    [[ -n "$EXISTING_TARGET_SELECTOR" ]] || { err "Non-interactive adoption requires --yes and an exact --target."; return 21; }
    adoption_select_exact "$EXISTING_TARGET_SELECTOR" || { err "The exact target is invalid, stale, or ambiguous."; return 21; }
  else
    adoption_render_preview
    ((${#ADOPTION_CANDIDATES[@]})) || return 21
    if [[ -n "$EXISTING_TARGET_SELECTOR" ]]; then adoption_select_exact "$EXISTING_TARGET_SELECTOR" || return 21
    else
      read -r -p "Enter the exact Target shown above (or B/Q): " reply || { echo "Adoption cancelled before any write."; return 0; }
      case "${reply,,}" in b|back|q|quit|'') echo "Adoption cancelled before any write."; return 0 ;; esac
      adoption_select_exact "$reply" || { err "Invalid or stale target selection."; return 21; }
    fi
    IFS='|' read -r engine mode id site rest <<<"$ADOPTION_SELECTED_RECORD"
    read -r -p "Adopt exactly $engine:$id:$site by replacing Toolkit configuration only? [y/N]: " reply || { echo "Adoption cancelled before any write."; return 0; }
    [[ "${reply,,}" == y || "${reply,,}" == yes ]] || { echo "Adoption cancelled before any write."; return 0; }
  fi
  adoption_transaction
}
