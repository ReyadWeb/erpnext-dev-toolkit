# shellcheck shell=bash disable=SC2034
# Existing-installation discovery and configuration-only adoption.

[[ -n "${_ERPNEXT_DEV_ADOPTION_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_ADOPTION_LOADED=1

declare -ag ADOPTION_CANDIDATES=()
declare -ag ADOPTION_OUTCOMES=()
ADOPTION_SELECTED_RECORD=""
ADOPTION_PROBE_STATUS="ambiguous"
ADOPTION_PROBE_REASON="validation-failed"

adoption_sha256() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }

adoption_valid_atom() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]
}

adoption_valid_path() {
  [[ "${1:-}" =~ ^/[A-Za-z0-9._/-]+$ && "${1:-}" != *'//'* \
    && "${1:-}" != */../* && "${1:-}" != */./* && "${1:-}" != */.. && "${1:-}" != */. ]]
}

adoption_mode_is_safe() {
  local mode="$1" owner="$2" path="$3" group_digit other_digit sticky_digit root_uid
  [[ "$mode" =~ ^[0-7]{3,4}$ && "$owner" =~ ^[0-9]+$ ]] || return 1
  group_digit=$(((10#$mode / 10) % 10)); other_digit=$((10#$mode % 10))
  if (( (group_digit & 2) == 0 && (other_digit & 2) == 0 )); then return 0; fi
  sticky_digit=$((10#$mode / 1000))
  root_uid="$(stat -c %u / 2>/dev/null)" || return 1
  [[ "$owner" == "$root_uid" && "$path" == /tmp ]] && (( (sticky_digit & 1) == 1 )) || return 1
}

adoption_path_safe() {
  local path="$1" expected_type="${2:-directory}" root="${3:-$1}" current="" component owner mode uid root_uid frappe_uid="" canonical
  adoption_valid_path "$path" && adoption_valid_path "$root" || return 1
  canonical="$(realpath -e -- "$path" 2>/dev/null)" || return 1
  [[ "$canonical" == "$path" && ("$path" == "$root" || "$path" == "$root/"*) ]] || return 1
  uid="${EUID:-$(id -u)}"
  root_uid="$(stat -c %u / 2>/dev/null)" || return 1
  [[ "$uid" != 0 || -z "${FRAPPE_USER:-}" ]] || frappe_uid="$(id -u "$FRAPPE_USER" 2>/dev/null || true)"
  IFS=/ read -r -a _adoption_parts <<<"${path#/}"
  for component in "${_adoption_parts[@]}"; do
    [[ -n "$component" ]] || continue
    current="${current}/${component}"
    [[ ! -L "$current" && -d "$current" ]] || {
      [[ "$current" == "$path" && "$expected_type" == file && -f "$current" && ! -L "$current" ]] || return 1
    }
    owner="$(stat -c %u -- "$current" 2>/dev/null)" || return 1
    mode="$(stat -c %a -- "$current" 2>/dev/null)" || return 1
    [[ "$owner" == "$uid" || "$owner" == "$root_uid" || (-n "$frappe_uid" && "$owner" == "$frappe_uid") ]] || return 1
    adoption_mode_is_safe "$mode" "$owner" "$current" || return 1
  done
  [[ "$expected_type" == directory && -d "$path" && ! -L "$path" ]] \
    || [[ "$expected_type" == file && -f "$path" && ! -L "$path" ]] || return 1
  owner="$(stat -c %u -- "$path" 2>/dev/null)" || return 1
  [[ "$owner" =~ ^[0-9]+$ ]] || return 1
  if [[ "$uid" == 0 ]]; then
    [[ "$owner" == 0 \
      || (-n "${FRAPPE_USER:-}" && "$(getent passwd "$owner" 2>/dev/null | cut -d: -f1)" == "$FRAPPE_USER") ]] || return 1
  else
    [[ "$owner" == "$uid" ]] || return 1
  fi
}

adoption_path_fact() {
  local path="$1"
  printf '%s:%s:%s' "$path" "$(stat -c %u -- "$path")" "$(stat -c %a -- "$path")"
}

adoption_probe_fail() { ADOPTION_PROBE_STATUS="$1"; return "${2:-1}"; }

adoption_outcome_add() {
  local engine="$1" id="$2" status="$3" reason="$4"
  adoption_valid_atom "$engine" && adoption_valid_atom "$id" && adoption_valid_atom "$status" && adoption_valid_atom "$reason" || return 1
  ADOPTION_OUTCOMES+=("$engine|$id|$status|$reason")
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
    adoption_path_safe "$bench/sites/$site/site_config.json" file "$bench" || return 1
    inventory_native_site_db_apps "$bench/sites/$site"
    return
  fi
  adoption_path_safe "$bench/sites/$site/apps.txt" file "$bench" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    app="${line%%[[:space:]]*}"
    [[ -z "$app" ]] && continue
    adoption_valid_atom "$app" || return 1
    printf '%s\n' "$app"
  done <"$bench/sites/$site/apps.txt"
}

adoption_native_probe() {
  local bench="$1" source state version major commit site apps app app_source app_state app_commit app_trust sites_seen=0 id apps_csv fingerprint snapshot=""
  local -a private_candidates=()
  ADOPTION_PROBE_STATUS=ambiguous
  ADOPTION_PROBE_REASON=unsafe-path
  adoption_path_safe "$bench" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
  if [[ "${EUID:-$(id -u)}" == 0 && "$(stat -c %u -- "$bench")" != "$(id -u "$FRAPPE_USER" 2>/dev/null)" ]]; then ADOPTION_PROBE_STATUS=incompatible; return 2; fi
  for path in "$bench/apps" "$bench/sites" "$bench/apps/frappe" "$bench/apps/frappe/.git"; do
    ADOPTION_PROBE_REASON=unsafe-proof-path
    adoption_path_safe "$path" directory "$bench" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
  done
  ADOPTION_PROBE_REASON=unsafe-version-proof
  adoption_path_safe "$bench/apps/frappe/frappe/__init__.py" file "$bench" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
  source="$(inventory_git_value "$bench/apps/frappe" source)"
  state="$(inventory_git_value "$bench/apps/frappe" state)"
  commit="$(inventory_git_value "$bench/apps/frappe" commit)"
  version="$(sed -nE 's/^[[:space:]]*(__version__|version)[[:space:]]*=[[:space:]]*["'\'']([^"'\'']+)["'\''].*/\2/p' "$bench/apps/frappe/frappe/__init__.py" | head -n 1)"
  major="${version#v}"; major="${major%%.*}"
  adoption_source_trusted "$source" || { ADOPTION_PROBE_STATUS=incompatible; ADOPTION_PROBE_REASON=untrusted-core; return 2; }
  [[ "$state" == clean && "$commit" =~ ^[a-f0-9]{40}$ ]] || { ADOPTION_PROBE_STATUS=dirty-unknown; ADOPTION_PROBE_REASON=unproven-core-state; return 3; }
  adoption_supported_frappe_major "$major" || { ADOPTION_PROBE_STATUS=incompatible; ADOPTION_PROBE_REASON=unsupported-major; return 2; }
  id="n-$(adoption_sha256 "$bench" | cut -c1-20)"
  snapshot+="engine=native\nenvironment=development\nbench=$(adoption_path_fact "$bench")\n"
  snapshot+="apps=$(adoption_path_fact "$bench/apps")\nsites=$(adoption_path_fact "$bench/sites")\n"
  snapshot+="frappe=$(adoption_path_fact "$bench/apps/frappe")\ngit=$(adoption_path_fact "$bench/apps/frappe/.git")\n"
  snapshot+="version_file=$(adoption_path_fact "$bench/apps/frappe/frappe/__init__.py")\n"
  snapshot+="frappe_commit=$commit\nfrappe_major=$major\nfrappe_source=trusted-official\nfrappe_state=clean\n"
  while IFS= read -r site; do
    [[ -n "$site" && "$site" != assets ]] || continue
    adoption_valid_atom "$site" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
    adoption_path_safe "$bench/sites/$site" directory "$bench" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
    apps="$(adoption_native_site_apps "$bench" "$site")" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
    printf '%s\n' "$apps" | grep -Fxq frappe || { ADOPTION_PROBE_STATUS=incompatible; return 2; }
    while IFS= read -r app; do
      adoption_valid_atom "$app" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
      adoption_path_safe "$bench/apps/$app" directory "$bench" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
      adoption_path_safe "$bench/apps/$app/.git" directory "$bench" || { ADOPTION_PROBE_STATUS=dirty-unknown; ADOPTION_PROBE_REASON=missing-code-record; return 3; }
      app_state="$(inventory_git_value "$bench/apps/$app" state)"
      app_commit="$(inventory_git_value "$bench/apps/$app" commit)"
      app_source="$(inventory_git_value "$bench/apps/$app" source)"
      [[ "$app_state" == clean && "$app_commit" =~ ^[a-f0-9]{40}$ ]] \
        || { ADOPTION_PROBE_STATUS=dirty-unknown; ADOPTION_PROBE_REASON=unproven-app-code; return 3; }
      app_trust=unknown-custom
      if load_validated_app_catalog_record "$app" >/dev/null 2>&1; then
        [[ "${app_source%.git}" == "${LIB_APP_REPO%.git}" ]] \
          || { ADOPTION_PROBE_STATUS=incompatible; ADOPTION_PROBE_REASON=untrusted-app-source; return 2; }
        app_trust=trusted-catalog
      fi
      snapshot+="code=$app:$(adoption_path_fact "$bench/apps/$app"):commit=$app_commit:state=clean:source=$app_trust:source_digest=$(adoption_sha256 "$app_source")\n"
    done <<<"$apps"
    apps_csv="$(printf '%s\n' "$apps" | LC_ALL=C sort -u | paste -sd, -)"
    snapshot+="site=$site:$(adoption_path_fact "$bench/sites/$site"):apps=$apps_csv\n"
    if [[ "${ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES:-0}" == 1 ]]; then
      snapshot+="registry=$site:$(adoption_path_fact "$bench/sites/$site/apps.txt")\n"
    else
      snapshot+="registry=$site:$(adoption_path_fact "$bench/sites/$site/site_config.json")\n"
    fi
    private_candidates+=("$site|$apps_csv")
    sites_seen=$((sites_seen + 1))
  done < <(find -P "$bench/sites" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort)
  ((sites_seen > 0)) || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
  snapshot="$(printf '%b' "$snapshot" | LC_ALL=C sort -u)"
  for record in "${private_candidates[@]}"; do
    site="${record%%|*}"; apps_csv="${record#*|}"
    fingerprint="$(adoption_sha256 "$snapshot"$'\n'"selected_site=$site")"
    adoption_candidate_add native development "$id" "$site" compatible "$major" "$apps_csv" "$fingerprint" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
    ADOPTION_CANDIDATE_PATHS["$id|$site"]="$bench"
    ADOPTION_CANDIDATE_STACK_FACTS["$id|$site"]="$snapshot"
  done
  ADOPTION_PROBE_STATUS=supported-unadopted
}

adoption_docker_probe_fixture() {
  # Test-only data adapter. It is disabled unless the explicit hermetic flag is
  # set and is never consulted by production discovery.
  local root="$1" file engine mode project site major digest apps reconstructible id
  ADOPTION_PROBE_STATUS=ambiguous
  ADOPTION_PROBE_REASON=invalid-test-descriptor
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
  ADOPTION_PROBE_STATUS=supported-unadopted
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

adoption_docker_site_apps() {
  local workdir="$1" project="$2" sites_source="$3" site="$4" line app
  : "$workdir" "$project"
  adoption_path_safe "$sites_source/$site/apps.txt" file "$sites_source" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    app="${line%%[[:space:]]*}"
    [[ -z "$app" ]] && continue
    adoption_valid_atom "$app" || return 1
    printf '%s\n' "$app"
  done <"$sites_source/$site/apps.txt"
}

adoption_docker_probe_live() {
  local root="$1" workdir ids id project="" observed_project="" service image_id app_image_id="" digest="" sites_source="" mount=""
  local mode=development site apps apps_csv major manifest_apps reconstructible=false candidate_id image_version repo_digest image_ref="" observed_image_ref=""
  local manifest_file="" manifest_hash=none manifest_image="" manifest_digest="" snapshot="" fingerprint record sites_seen=0
  local -A services=()
  local -a private_candidates=()
  ADOPTION_PROBE_STATUS=ambiguous
  ADOPTION_PROBE_REASON=incomplete-docker-inventory
  workdir="$(dirname "$root")"
  adoption_path_safe "$workdir" || return 1
  adoption_path_safe "$root" directory "$workdir" || return 1
  command -v docker >/dev/null 2>&1 || return 1
  [[ -f "$root/compose.yaml" ]] && mode=production
  ids="$(inventory_run_probe docker ps --filter "label=com.docker.compose.project.working_dir=$root" --format '{{.ID}}' 2>/dev/null)" || return 1
  [[ -n "$ids" ]] || return 1
  while IFS= read -r id; do
    mount=""
    [[ "$id" =~ ^[a-f0-9]{12,64}$ ]] || return 1
    project="$(inventory_run_probe docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$id" 2>/dev/null)" || return 1
    service="$(inventory_run_probe docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$id" 2>/dev/null)" || return 1
    adoption_valid_atom "$project" && adoption_valid_atom "$service" || return 1
    [[ -z "$observed_project" || "$observed_project" == "$project" ]] || { ADOPTION_PROBE_STATUS=incompatible; return 2; }
    observed_project="$project"
    case "$service" in backend|frontend|websocket|queue-short|queue-long|scheduler|configurator|db|redis-cache|redis-queue) ;; *) return 2 ;; esac
    [[ -z "${services[$service]:-}" ]] || return 2
    services["$service"]=1
    image_id="$(inventory_run_probe docker inspect --format '{{.Image}}' "$id" 2>/dev/null)" || return 1
    [[ "$image_id" =~ ^sha256:[a-f0-9]{64}$ ]] || { ADOPTION_PROBE_STATUS=ambiguous; ADOPTION_PROBE_REASON=unproven-image-id; return 1; }
    case "$service" in backend|frontend|websocket|queue-short|queue-long|scheduler)
      [[ -z "$app_image_id" || "$app_image_id" == "$image_id" ]] || return 2
      app_image_id="$image_id"
      image_ref="$(inventory_run_probe docker inspect --format '{{.Config.Image}}' "$id" 2>/dev/null)" || return 1
      [[ "$image_ref" =~ ^[A-Za-z0-9._/:@-]{1,255}$ ]] || { ADOPTION_PROBE_STATUS=ambiguous; ADOPTION_PROBE_REASON=unsafe-image-identity; return 1; }
      [[ -z "$observed_image_ref" || "$observed_image_ref" == "$image_ref" ]] || { ADOPTION_PROBE_STATUS=incompatible; return 2; }
      observed_image_ref="$image_ref"
      mount="$(inventory_run_probe docker inspect --format '{{range .Mounts}}{{if eq .Destination "/home/frappe/frappe-bench/sites"}}{{.Source}}{{end}}{{end}}' "$id" 2>/dev/null)" || return 1
      [[ -n "$mount" && (-z "$sites_source" || "$sites_source" == "$mount") ]] || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
      sites_source="$mount"
      ;;
    esac
    snapshot+="service=$service:id=$id:image=$image_id:mount=$mount\n"
  done <<<"$ids"
  project="$observed_project"
  [[ -n "$project" && -n "$app_image_id" && -n "$sites_source" ]] || return 1
  for service in backend frontend websocket queue-short queue-long scheduler db redis-cache redis-queue; do
    [[ -n "${services[$service]:-}" ]] || { ADOPTION_PROBE_STATUS=incompatible; return 2; }
  done
  adoption_path_safe "$sites_source" || return 1
  repo_digest="$(inventory_run_probe docker image inspect --format '{{index .RepoDigests 0}}' "$app_image_id" 2>/dev/null)" || return 1
  digest="${repo_digest##*@}"
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || { ADOPTION_PROBE_STATUS=incompatible; return 2; }
  image_version="$(inventory_run_probe docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$app_image_id" 2>/dev/null)" || return 1
  major="${image_version#v}"; major="${major%%.*}"
  adoption_supported_frappe_major "$major" || { ADOPTION_PROBE_STATUS=incompatible; return 2; }
  if [[ "$mode" == production ]]; then
    manifest_file="$workdir/erpnext-dev.app-manifest.tsv"
    adoption_path_safe "$manifest_file" file "$workdir" || { ADOPTION_PROBE_STATUS=ambiguous; return 1; }
    docker_validate_app_manifest "$manifest_file" || { ADOPTION_PROBE_STATUS=incompatible; return 2; }
    manifest_apps="$(adoption_docker_manifest_apps "$manifest_file" 2>/dev/null)" || return 2
    printf '%s\n' "$manifest_apps" | grep -Fxq frappe || return 2
    IFS=$'\t' read -r _ manifest_image manifest_digest < <(awk -F'\t' '$1=="IMAGE" {print; exit}' "$manifest_file")
    [[ -n "$manifest_image" && "$manifest_image" == "$observed_image_ref" && "$manifest_digest" == "$digest" ]] \
      || { ADOPTION_PROBE_STATUS=incompatible; return 2; }
    manifest_hash="$(sha256sum "$manifest_file" | awk '{print $1}')"
    reconstructible=true
  elif [[ "$repo_digest" != frappe/erpnext@* && "$repo_digest" != ghcr.io/frappe/*@* ]]; then
    return 2
  fi
  snapshot+="engine=docker\nenvironment=$mode\nworkdir=$(adoption_path_fact "$workdir")\nroot=$(adoption_path_fact "$root")\n"
  snapshot+="project=$project\nimage_id=$app_image_id\nimage_ref=$observed_image_ref\ndigest=$digest\n"
  snapshot+="sites_mount=$(adoption_path_fact "$sites_source")\nmanifest=$manifest_hash\nreconstructible=$reconstructible\nfrappe_major=$major\n"
  while IFS= read -r site; do
    [[ -n "$site" && "$site" != assets ]] || continue
    adoption_valid_atom "$site" || return 1
    adoption_path_safe "$sites_source/$site" directory "$sites_source" || return 1
    apps="$(adoption_docker_site_apps "$workdir" "$project" "$sites_source" "$site")" || return 1
    printf '%s\n' "$apps" | grep -Fxq frappe || return 2
    if [[ "$mode" == production ]]; then
      while IFS= read -r app; do printf '%s\n' "$manifest_apps" | grep -Fxq "$app" || return 2; done <<<"$apps"
    fi
    apps_csv="$(printf '%s\n' "$apps" | LC_ALL=C sort -u | paste -sd, -)"
    snapshot+="site=$site:$(adoption_path_fact "$sites_source/$site"):apps=$apps_csv\n"
    private_candidates+=("$site|$apps_csv")
    sites_seen=$((sites_seen + 1))
  done < <(find -P "$sites_source" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort)
  ((sites_seen > 0)) || return 1
  snapshot="$(printf '%b' "$snapshot" | LC_ALL=C sort -u)"
  candidate_id="d-$(adoption_sha256 "$root|$project" | cut -c1-20)"
  for record in "${private_candidates[@]}"; do
    site="${record%%|*}"; apps_csv="${record#*|}"
    fingerprint="$(adoption_sha256 "$snapshot"$'\n'"selected_site=$site")"
    adoption_candidate_add docker "$mode" "$candidate_id" "$site" compatible "$major" "$apps_csv" "$fingerprint" || return 1
    ADOPTION_CANDIDATE_PATHS["$candidate_id|$site"]="$root"
    ADOPTION_CANDIDATE_WORKDIRS["$candidate_id|$site"]="$workdir"
    ADOPTION_CANDIDATE_PROJECTS["$candidate_id|$site"]="$project"
    ADOPTION_CANDIDATE_STACK_FACTS["$candidate_id|$site"]="$snapshot"
  done
  ADOPTION_PROBE_STATUS=supported-unadopted
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
  local root canonical rc root_id engine
  ADOPTION_CANDIDATES=()
  ADOPTION_OUTCOMES=()
  declare -gA ADOPTION_CANDIDATE_PATHS=() ADOPTION_CANDIDATE_WORKDIRS=() ADOPTION_CANDIDATE_PROJECTS=() ADOPTION_CANDIDATE_STACK_FACTS=()
  while IFS= read -r root; do
    [[ -n "$root" && "$root" == /* && -d "$root" && ! -L "$root" ]] || continue
    root_id="x-$(adoption_sha256 "$root" | cut -c1-20)"
    canonical="$(realpath -e -- "$root" 2>/dev/null)" || { adoption_outcome_add unknown "$root_id" ambiguous unsafe-path; continue; }
    [[ "$canonical" == "$root" ]] || { adoption_outcome_add unknown "$root_id" ambiguous unsafe-path; continue; }
    if [[ -d "$root/apps/frappe" && -d "$root/sites" ]]; then
      engine=native; rc=0
      adoption_native_probe "$root" >/dev/null 2>&1 || rc=$?
    elif [[ -f "$root/compose.yaml" || -f "$root/pwd.yml" || -f "$root/.toolkit-adoption-fixture" ]]; then
      engine=docker; rc=0
      if [[ "${ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES:-0}" == 1 ]]; then
        adoption_docker_probe_fixture "$root" >/dev/null 2>&1 || rc=$?
      else
        adoption_docker_probe_live "$root" >/dev/null 2>&1 || rc=$?
      fi
    else
      continue
    fi
    if ((rc != 0)); then
      adoption_outcome_add "$engine" "${root_id/x-/$( [[ "$engine" == native ]] && printf n- || printf d- )}" \
        "${ADOPTION_PROBE_STATUS:-ambiguous}" "${ADOPTION_PROBE_REASON:-validation-failed}"
    fi
  done < <(adoption_discovery_roots | LC_ALL=C sort -u)
  if ((${#ADOPTION_CANDIDATES[@]})); then
    mapfile -t ADOPTION_CANDIDATES < <(printf '%s\n' "${ADOPTION_CANDIDATES[@]}" | LC_ALL=C sort)
  fi
  if ((${#ADOPTION_OUTCOMES[@]})); then
    mapfile -t ADOPTION_OUTCOMES < <(printf '%s\n' "${ADOPTION_OUTCOMES[@]}" | LC_ALL=C sort -u)
  fi
  adoption_classify_compatible_outcomes
}

adoption_classify_compatible_outcomes() {
  local record engine mode id site compatibility major apps fingerprint status=supported-unadopted
  local saved_profile saved_id saved_site saved_fp saved_engine saved_mode saved_path saved_workdir saved_project path workdir project
  saved_profile="$(read_config_key_from_file "$CONFIG_FILE" INSTALLATION_PROFILE 2>/dev/null || true)"
  saved_id="$(read_config_key_from_file "$CONFIG_FILE" ADOPTION_TARGET_ID 2>/dev/null || true)"
  saved_site="$(read_config_key_from_file "$CONFIG_FILE" ADOPTION_SITE 2>/dev/null || true)"
  saved_fp="$(read_config_key_from_file "$CONFIG_FILE" ADOPTION_INVENTORY_FINGERPRINT 2>/dev/null || true)"
  saved_engine="$(read_config_key_from_file "$CONFIG_FILE" DEPLOYMENT_ENGINE 2>/dev/null || true)"
  saved_mode="$(read_config_key_from_file "$CONFIG_FILE" DOCKER_MODE 2>/dev/null || true)"
  saved_path="$(read_config_key_from_file "$CONFIG_FILE" ADOPTION_BENCH_PATH 2>/dev/null || true)"
  saved_workdir="$(read_config_key_from_file "$CONFIG_FILE" ADOPTION_DOCKER_WORKDIR 2>/dev/null || true)"
  saved_project="$(read_config_key_from_file "$CONFIG_FILE" ADOPTION_DOCKER_PROJECT 2>/dev/null || true)"
  for record in "${ADOPTION_CANDIDATES[@]}"; do
    IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$record"
    path="${ADOPTION_CANDIDATE_PATHS["$id|$site"]:-}"; workdir="${ADOPTION_CANDIDATE_WORKDIRS["$id|$site"]:-}"; project="${ADOPTION_CANDIDATE_PROJECTS["$id|$site"]:-}"
    status=supported-unadopted
    if [[ "$saved_profile" == existing && -n "$saved_id" ]]; then
      if [[ "$saved_id" == "$id" && "$saved_site" == "$site" && "$saved_fp" == "$fingerprint" \
        && "$saved_engine" == "$engine" && "$saved_mode" == "$mode" \
        && ("$engine" != native || "$saved_path" == "$path") \
        && ("$engine" != docker || ("$saved_workdir" == "$workdir" && "$saved_project" == "$project")) ]]; then
        status=already-managed
      else
        status=conflicting
      fi
    fi
    adoption_outcome_add "$engine" "$id" "$status" validated
  done
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
  local record engine mode id site compatibility major apps fingerprint matches=0 path workdir project
  [[ "${PROFILE_METADATA_ADOPTION_VALID:-false}" == true ]] || return 1
  [[ -z "${DEPLOYMENT_ENGINE:-}" || "$DEPLOYMENT_ENGINE" == "$PROFILE_METADATA_ADOPTION_ENGINE" ]] || return 1
  if [[ "$PROFILE_METADATA_ADOPTION_ENGINE" == native ]]; then
    [[ "${BENCH_DIR:-}" == "$PROFILE_METADATA_ADOPTION_BENCH_PATH" ]] || return 1
  else
    [[ "${DOCKER_MODE:-}" == "$PROFILE_METADATA_ADOPTION_ENVIRONMENT" \
      && "${DOCKER_WORKDIR:-}" == "$PROFILE_METADATA_ADOPTION_DOCKER_WORKDIR" \
      && "${DOCKER_PROJECT_NAME:-}" == "$PROFILE_METADATA_ADOPTION_DOCKER_PROJECT" ]] || return 1
  fi
  adoption_discover
  for record in "${ADOPTION_CANDIDATES[@]}"; do
    IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$record"
    path="${ADOPTION_CANDIDATE_PATHS["$id|$site"]:-}"; workdir="${ADOPTION_CANDIDATE_WORKDIRS["$id|$site"]:-}"; project="${ADOPTION_CANDIDATE_PROJECTS["$id|$site"]:-}"
    if [[ "$id" == "$PROFILE_METADATA_ADOPTION_TARGET" \
      && "$site" == "$PROFILE_METADATA_ADOPTION_SITE" \
      && "$fingerprint" == "$PROFILE_METADATA_ADOPTION_FINGERPRINT" \
      && "$engine" == "$PROFILE_METADATA_ADOPTION_ENGINE" \
      && "$mode" == "$PROFILE_METADATA_ADOPTION_ENVIRONMENT" \
      && ("$engine" != native || "$path" == "$PROFILE_METADATA_ADOPTION_BENCH_PATH") \
      && ("$engine" != docker || ("$workdir" == "$PROFILE_METADATA_ADOPTION_DOCKER_WORKDIR" \
        && "$project" == "$PROFILE_METADATA_ADOPTION_DOCKER_PROJECT")) ]]; then
      matches=$((matches + 1))
    fi
  done
  ((matches == 1))
}

adoption_render_preview() {
  local record engine mode id site compatibility major apps fingerprint first=1 status reason
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
    printf '],"outcomes":['; first=1
    for record in "${ADOPTION_OUTCOMES[@]}"; do
      IFS='|' read -r engine id status reason <<<"$record"
      ((first)) || printf ','; first=0
      printf '{"engine":'; inventory_json_escape "$engine"
      printf ',"identity":'; inventory_json_escape "$id"
      printf ',"status":'; inventory_json_escape "$status"
      printf ',"reason":'; inventory_json_escape "$reason"
      printf '}'
    done
    printf '],"mutation":false}\n'
    return
  fi
  printf 'Existing-installation discovery (read-only)\n'
  if ((${#ADOPTION_CANDIDATES[@]} == 0 && ${#ADOPTION_OUTCOMES[@]} == 0)); then printf 'Discovery results: zero candidates\n'; fi
  for record in "${ADOPTION_CANDIDATES[@]}"; do
    IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$record"
    printf 'Target: %s:%s:%s\nEngine: %s\nEnvironment: %s\nSite: %s\nApplications: %s\nCompatibility: %s (Frappe %s)\nCapability: configuration-only; deployment mutation prohibited\nInventory fingerprint: %s\n\n' \
      "$engine" "$id" "$site" "$engine" "$mode" "$site" "$apps" "$compatibility" "$major" "$fingerprint"
  done
  for record in "${ADOPTION_OUTCOMES[@]}"; do
    IFS='|' read -r engine id status reason <<<"$record"
    printf 'Outcome: %s %s %s (%s)\n' "$engine" "$id" "$status" "$reason"
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
  local source="$1" output="$2" engine="$3" mode="$4" id="$5" site="$6" fingerprint="$7" path="$8" workdir="$9" project="${10}"
  local key line value
  : >"$output" || return 1
  chmod 600 "$output" || return 1
  if [[ -f "$source" && ! -L "$source" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
      key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
      case "$key" in CONFIG_SCHEMA|INSTALLATION_PROFILE|INSTALLATION_PROFILE_APPS|DEPLOYMENT_ENGINE|DOCKER_MODE|SITE_NAME|DOCKER_SITE_NAME|BENCH_PARENT|BENCH_NAME|BENCH_DIR|DOCKER_WORKDIR|DOCKER_PROJECT_NAME|ADOPTION_*|*PASSWORD*|*TOKEN*|*SECRET*|*CREDENTIAL*|*PRIVATE*) continue ;; esac
      adoption_config_value_safe "$value" || continue
      printf '%s=%s\n' "$key" "$value" >>"$output"
    done <"$source"
  fi
  {
    printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=existing\nINSTALLATION_PROFILE_APPS=\n'
    printf 'DEPLOYMENT_ENGINE=%s\nDOCKER_MODE=%s\nSITE_NAME=%s\n' "$engine" "$mode" "$site"
    [[ "$engine" == docker ]] && printf 'DOCKER_SITE_NAME=%s\n' "$site"
    if [[ "$engine" == native ]]; then
      printf 'BENCH_PARENT=%s\nBENCH_NAME=%s\nBENCH_DIR=%s\n' "$(dirname "$path")" "$(basename "$path")" "$path"
    else
      printf 'DOCKER_WORKDIR=%s\nDOCKER_PROJECT_NAME=%s\n' "$workdir" "$project"
    fi
    printf 'ADOPTION_TARGET_ID=%s\nADOPTION_ENGINE=%s\nADOPTION_ENVIRONMENT=%s\nADOPTION_SITE=%s\nADOPTION_INVENTORY_FINGERPRINT=%s\n' \
      "$id" "$engine" "$mode" "$site" "$fingerprint"
    [[ "$engine" == native ]] && printf 'ADOPTION_BENCH_PATH=%s\n' "$path"
    [[ "$engine" == docker ]] && printf 'ADOPTION_DOCKER_WORKDIR=%s\nADOPTION_DOCKER_PROJECT=%s\n' "$workdir" "$project"
  } >>"$output"
  return 0
}

adoption_remove_private_temps() {
  local file
  for file in "$@"; do [[ -z "$file" ]] || $SUDO rm -f -- "$file"; done
}

adoption_write_mirrors() {
  local staged="$1" primary_tmp legacy_tmp primary_rollback="" primary_existed=false
  primary_tmp="${CONFIG_FILE}.adopt.$$"
  legacy_tmp="${LEGACY_CONFIG_FILE}.adopt.$$"
  [[ ! -L "$CONFIG_FILE" && ! -L "$LEGACY_CONFIG_FILE" ]] || return 1
  $SUDO mkdir -p "$(dirname "$CONFIG_FILE")" "$(dirname "$LEGACY_CONFIG_FILE")" || return 1
  $SUDO cp -- "$staged" "$primary_tmp" || { adoption_remove_private_temps "$primary_tmp" "$legacy_tmp"; return 1; }
  $SUDO chmod 600 "$primary_tmp" || { adoption_remove_private_temps "$primary_tmp" "$legacy_tmp"; return 1; }
  if [[ "$LEGACY_CONFIG_FILE" != "$CONFIG_FILE" ]]; then
    $SUDO cp -- "$staged" "$legacy_tmp" || { adoption_remove_private_temps "$primary_tmp" "$legacy_tmp"; return 1; }
    $SUDO chmod 600 "$legacy_tmp" || { adoption_remove_private_temps "$primary_tmp" "$legacy_tmp"; return 1; }
  fi
  if [[ -f "$CONFIG_FILE" ]]; then
    primary_existed=true
    primary_rollback="${CONFIG_FILE}.rollback.$$"
    $SUDO cp -- "$CONFIG_FILE" "$primary_rollback" || { adoption_remove_private_temps "$primary_tmp" "$legacy_tmp" "$primary_rollback"; return 1; }
    $SUDO chmod 600 "$primary_rollback" || { adoption_remove_private_temps "$primary_tmp" "$legacy_tmp" "$primary_rollback"; return 1; }
  fi
  $SUDO mv -f "$primary_tmp" "$CONFIG_FILE" || { adoption_remove_private_temps "$primary_tmp" "$legacy_tmp" "$primary_rollback"; return 1; }
  if [[ "$LEGACY_CONFIG_FILE" != "$CONFIG_FILE" ]] && ! $SUDO mv -f "$legacy_tmp" "$LEGACY_CONFIG_FILE"; then
    $SUDO rm -f -- "$legacy_tmp"
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
  local reviewed="$ADOPTION_SELECTED_RECORD" engine mode id site compatibility major apps fingerprint path workdir project
  local previous previous_primary previous_legacy_fp config_stage recovery_dir previous_copy previous_legacy candidate_fp
  local write_rc=0
  IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$reviewed"
  previous_primary="$(adoption_file_fingerprint "$CONFIG_FILE")"
  previous_legacy_fp="$(adoption_file_fingerprint "$LEGACY_CONFIG_FILE")"
  previous="$(adoption_config_pair_fingerprint)"
  acquire_toolkit_lock
  adoption_discover
  adoption_select_exact "$engine:$id:$site" || return 34
  [[ "$ADOPTION_SELECTED_RECORD" == "$reviewed" ]] || return 34
  [[ "$(adoption_config_pair_fingerprint)" == "$previous" ]] || return 34
  path="${ADOPTION_CANDIDATE_PATHS["$id|$site"]}"; workdir="${ADOPTION_CANDIDATE_WORKDIRS["$id|$site"]:-}"; project="${ADOPTION_CANDIDATE_PROJECTS["$id|$site"]:-}"
  if [[ -f "$CONFIG_FILE" ]]; then
    read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1 || return 34
    if [[ "$PROFILE_METADATA_SCHEMA" == 2 && "$PROFILE_METADATA_PROFILE" == existing ]]; then
      [[ "$PROFILE_METADATA_ADOPTION_VALID" == true \
        && "$PROFILE_METADATA_ADOPTION_TARGET" == "$id" \
        && "$PROFILE_METADATA_ADOPTION_SITE" == "$site" \
        && "$PROFILE_METADATA_ADOPTION_FINGERPRINT" == "$fingerprint" \
        && "$PROFILE_METADATA_ADOPTION_ENGINE" == "$engine" \
        && "$PROFILE_METADATA_ADOPTION_ENVIRONMENT" == "$mode" \
        && ("$engine" != native || "$PROFILE_METADATA_ADOPTION_BENCH_PATH" == "$path") \
        && ("$engine" != docker || ("$PROFILE_METADATA_ADOPTION_DOCKER_WORKDIR" == "$workdir" \
          && "$PROFILE_METADATA_ADOPTION_DOCKER_PROJECT" == "$project")) ]] \
        && { ok "Exact complete target identity is already adopted; configuration was not rewritten."; return 0; }
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
  [[ "$previous_primary" == absent || "$(adoption_file_fingerprint "$previous_copy")" == "$previous_primary" ]] || return 34
  [[ "$previous_legacy_fp" == absent || "$(adoption_file_fingerprint "$previous_legacy")" == "$previous_legacy_fp" ]] || return 34
  [[ "$(adoption_config_pair_fingerprint)" == "$previous" ]] || return 34
  config_stage="$(mktemp "${TMPDIR:-/tmp}/erpnext-adoption.XXXXXX")" || return 31
  adoption_stage_config "$CONFIG_FILE" "$config_stage" "$engine" "$mode" "$id" "$site" "$fingerprint" "$path" "$workdir" "$project" || { rm -f -- "$config_stage"; return 31; }
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
  planner_record_write || { rm -f -- "$config_stage"; return 31; }
  planner_checkpoint configuration-staged adopting || { rm -f -- "$config_stage"; return 31; }
  adoption_write_mirrors "$config_stage" || write_rc=$?
  if ((write_rc != 0)); then
    rm -f -- "$config_stage"
    if ((write_rc == 3)); then
      planner_fail_record replace "Configuration mirror rollback could not be proven." "Recovery required; retain both protected prior artifacts." recovery-required
      return 33
    fi
    planner_fail_record replace "Configuration replacement failed; prior configuration remains authoritative." "Prior configuration: $previous_copy" failed-safe
    return 31
  fi
  if [[ "$(adoption_file_fingerprint "$CONFIG_FILE")" != "$candidate_fp" \
    || "$(adoption_file_fingerprint "$LEGACY_CONFIG_FILE")" != "$candidate_fp" ]] \
    || ! cmp -s "$CONFIG_FILE" "$LEGACY_CONFIG_FILE" \
    || ! read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1 \
    || [[ "$PROFILE_METADATA_ADOPTION_VALID" != true \
      || "$PROFILE_METADATA_ADOPTION_TARGET" != "$id" \
      || "$PROFILE_METADATA_ADOPTION_SITE" != "$site" \
      || "$PROFILE_METADATA_ADOPTION_FINGERPRINT" != "$fingerprint" \
      || "$PROFILE_METADATA_ADOPTION_ENGINE" != "$engine" \
      || "$PROFILE_METADATA_ADOPTION_ENVIRONMENT" != "$mode" ]] \
    || { load_adopted_operational_routing_if_available; \
      [[ "$engine" == native && "$BENCH_DIR" != "$path" ]] \
        || [[ "$engine" == docker && ("$DOCKER_WORKDIR" != "$workdir" || "$DOCKER_PROJECT_NAME" != "$project") ]]; } \
    || { adoption_discover; ! adoption_select_exact "$engine:$id:$site"; } \
    || [[ "$ADOPTION_SELECTED_RECORD" != "$reviewed" ]] \
    || ! printf '%s\n' "${ADOPTION_OUTCOMES[@]}" | grep -Fqx "$engine|$id|already-managed|validated"; then
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
