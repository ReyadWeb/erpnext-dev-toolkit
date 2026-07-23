# shellcheck shell=bash
# Docker deployment engine: wraps the official frappe_docker project (pwd.yml)
# to run a containerized ERPNext stack behind the same erpnext-dev CLI as the
# native engine. Sourced by the toolkit entry point; do not execute directly.
#
# Design: we do NOT hand-roll a compose file. We clone frappe_docker at a pinned
# ref and use its upstream pwd.yml as the base, then overlay a small generated
# override (published port, pinned image tag, chosen site name + admin password)
# via a second -f file plus an --env-file. This keeps us aligned with upstream
# while honoring the operator's chosen site/port.

[[ -n "${_ERPNEXT_DEV_DOCKER_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_DOCKER_LOADED=1

# ------------------------------------------------------------
# Paths / pins (overridable via environment)
# ------------------------------------------------------------
DOCKER_WORKDIR="${DOCKER_WORKDIR:-/opt/erpnext-dev/docker}"
FRAPPE_DOCKER_REPO="${FRAPPE_DOCKER_REPO:-https://github.com/frappe/frappe_docker.git}"
# Pin the frappe_docker checkout for reproducible provisioning. Default is an
# audited immutable commit SHA. Override with FRAPPE_DOCKER_REF=main (or another
# branch/tag/SHA) when you intentionally want a different tip; the resolved
# commit SHA is always recorded at provision time (see docker_write_pins).
FRAPPE_DOCKER_REF="${FRAPPE_DOCKER_REF:-c004361e790125ed13aaa933d11f7838711a8960}"
# Pinned production-ready image published by the Frappe team. For maximum
# reproducibility pin by DIGEST rather than tag, e.g.
# DOCKER_ERPNEXT_IMAGE=frappe/erpnext@sha256:<digest>. The digest actually pulled
# is recorded at provision time (see docker_write_pins).
DOCKER_ERPNEXT_IMAGE="${DOCKER_ERPNEXT_IMAGE:-frappe/erpnext:v16.26.2}"
DOCKER_PROJECT_NAME="${DOCKER_PROJECT_NAME:-erpnext-dev}"
DOCKER_PUBLISH_PORT="${DOCKER_PUBLISH_PORT:-8080}"
DOCKER_READY_TIMEOUT="${DOCKER_READY_TIMEOUT:-900}"
# How long to wait for the one-shot create-site job (site + erpnext install) to
# complete before treating the install as failed.
DOCKER_CREATE_SITE_TIMEOUT="${DOCKER_CREATE_SITE_TIMEOUT:-900}"
DOCKER_CREDENTIALS_FILE="${DOCKER_CREDENTIALS_FILE:-${DOCKER_WORKDIR}/erpnext-dev-docker-credentials.txt}"
# Immutable-pin audit record: the exact frappe_docker commit SHA checked out and
# the resolved ERPNext image digest, captured at provision time.
DOCKER_PINS_FILE="${DOCKER_PINS_FILE:-${DOCKER_WORKDIR}/erpnext-dev.pins}"
DOCKER_FRAPPE_DOCKER_SHA="${DOCKER_FRAPPE_DOCKER_SHA:-}"
DOCKER_ERPNEXT_IMAGE_DIGEST="${DOCKER_ERPNEXT_IMAGE_DIGEST:-}"

# Disaster recovery (P3): every Docker backup is exported out of the sites volume
# to a durable, root-owned host artifact directory (db + files + site config +
# manifest + SHA256SUMS). Restore consumes those host artifacts, and a restore
# rehearsal proves the artifact restores into a clean site of the SAME image.
DOCKER_BACKUP_DIR="${DOCKER_BACKUP_DIR:-/var/backups/erpnext-dev/docker}"
DOCKER_RESTORE_REHEARSAL_FILE="${DOCKER_RESTORE_REHEARSAL_FILE:-/etc/erpnext-dev/docker-restore-rehearsal.env}"

# Off-site shipment (P6): durable host artifact -> off-VM (rsync/SSH, reusing the
# native OFF_VM_BACKUP_* config/keys) -> object storage (rclone, any S3/GCS/Azure/
# B2 remote). Object-storage settings live in their own root-owned config/state.
DOCKER_OBJECT_BACKUP_CONFIG_FILE="${DOCKER_OBJECT_BACKUP_CONFIG_FILE:-/etc/erpnext-dev/docker-object-backup.env}"
DOCKER_OBJECT_BACKUP_STATE_FILE="${DOCKER_OBJECT_BACKUP_STATE_FILE:-/etc/erpnext-dev/docker-object-backup.state}"

# Production HTTPS / reverse proxy (P5): the production stack fronts the frontend
# with upstream Traefik. HTTPS mode (http|letsencrypt|cloudflare-origin) is kept
# in a small state file so the mode-aware compose file list picks the right proxy
# override on every invocation. Cloudflare Origin CA material lives root-owned.
DOCKER_HTTPS_STATE_FILE="${DOCKER_HTTPS_STATE_FILE:-${DOCKER_WORKDIR}/erpnext-dev.https.env}"
DOCKER_CF_ORIGIN_DIR="${DOCKER_CF_ORIGIN_DIR:-${DOCKER_WORKDIR}/cloudflare-origin}"

# Durable custom-app images (P4): build an immutable image containing the base
# ERPNext plus selected apps (via frappe_docker's layered Containerfile), then
# deploy it by RECREATING the stack on the new image. Running containers are
# never mutated; app code ships in the image and only the site DB install-app
# step (data, not container) runs on deploy.
DOCKER_CUSTOM_IMAGE_STATE_FILE="${DOCKER_CUSTOM_IMAGE_STATE_FILE:-${DOCKER_WORKDIR}/erpnext-dev.custom-image.env}"
DOCKER_CUSTOM_IMAGE_APPS_FILE="${DOCKER_CUSTOM_IMAGE_APPS_FILE:-${DOCKER_WORKDIR}/erpnext-dev.apps.json}"
DOCKER_CUSTOM_IMAGE_PROFILES_FILE="${DOCKER_CUSTOM_IMAGE_PROFILES_FILE:-${DOCKER_WORKDIR}/erpnext-dev.custom-image-profiles}"
DOCKER_CUSTOM_IMAGE_REPO="${DOCKER_CUSTOM_IMAGE_REPO:-erpnext-dev/custom}"

docker_clone_dir() { printf '%s/frappe_docker\n' "$DOCKER_WORKDIR"; }
docker_overrides_dir() { printf '%s/frappe_docker/overrides\n' "$DOCKER_WORKDIR"; }
docker_compose_base_file() { printf '%s/frappe_docker/pwd.yml\n' "$DOCKER_WORKDIR"; }
docker_override_file() { printf '%s/erpnext-dev.override.yml\n' "$DOCKER_WORKDIR"; }
docker_env_file() { printf '%s/erpnext-dev.env\n' "$DOCKER_WORKDIR"; }
# Production (compose.yaml) artifacts, generated by the toolkit and kept OUTSIDE
# the clone so `git reset --hard` on the checkout never wipes them.
docker_prod_base_file() { printf '%s/frappe_docker/compose.yaml\n' "$DOCKER_WORKDIR"; }
docker_prod_env_file() { printf '%s/erpnext-dev.prod.env\n' "$DOCKER_WORKDIR"; }
docker_prod_image_override_file() { printf '%s/erpnext-dev.prod.image.yml\n' "$DOCKER_WORKDIR"; }

# The Docker engine serves whatever site name is configured. Default to the
# toolkit SITE_NAME (e.g. erp.test) so local host mapping stays consistent.
docker_site_name() { printf '%s\n' "${DOCKER_SITE_NAME:-${SITE_NAME:-erp.test}}"; }

# Public routing domain can differ from the internal Frappe site name. Traefik
# must match the real production hostname, while FRAPPE_SITE_NAME_HEADER can
# still force requests into a differently named site.
docker_public_domain() {
  if [[ -n "${PRODUCTION_DOMAIN:-}" ]]; then
    printf '%s\n' "$PRODUCTION_DOMAIN"
  else
    docker_site_name
  fi
}

# Direct host-published HTTP endpoint. The official quick/demo and noproxy
# production layouts expose the frontend container's 8080 through the selected
# host DOCKER_PUBLISH_PORT (8080 by default).
docker_direct_http_url() {
  local host="${1:-localhost}"
  printf 'http://%s:%s\n' "$host" "${DOCKER_PUBLISH_PORT:-8080}"
}

# ------------------------------------------------------------
# Deployment mode (development pwd.yml vs production compose.yaml)
# ------------------------------------------------------------
docker_mode() {
  case "$(printf '%s' "${DOCKER_MODE:-development}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    prod|production|public|public-vm) printf 'production\n' ;;
    *) printf 'development\n' ;;
  esac
}
docker_is_production() { [[ "$(docker_mode)" == "production" ]]; }
docker_mode_label() { docker_is_production && printf 'production\n' || printf 'development\n'; }

# Parse the image tag out of DOCKER_ERPNEXT_IMAGE for ERPNEXT_VERSION. When the
# image is pinned by digest (repo@sha256:...) there is no tag, so fall back to a
# harmless default (the generated image override sets the exact image anyway).
docker_image_tag() {
  local img="${DOCKER_ERPNEXT_IMAGE:-frappe/erpnext:latest}"
  case "$img" in
    *@sha256:*) printf 'latest\n' ;;
    *:*) printf '%s\n' "${img##*:}" ;;
    *) printf 'latest\n' ;;
  esac
}

# ------------------------------------------------------------
# Capability detection
# ------------------------------------------------------------
docker_binary_present() { command -v docker >/dev/null 2>&1; }

docker_daemon_ready() {
  docker_binary_present || return 1
  ${SUDO:-} docker info >/dev/null 2>&1
}

# Resolve the compose program into the caller-named array (default: DOCKER_COMPOSE_CMD).
# Prefers the modern "docker compose" plugin, falls back to the legacy
# "docker-compose" binary. Returns non-zero when neither is available.
#
# NOTE: we deliberately populate an array rather than echoing a "docker compose"
# string. The toolkit runs with IFS=$'\n\t' (no space), so an unquoted string
# containing a space would NOT word-split and bash would try to exec a single
# command literally named "docker compose".
# Uses a nameref (no eval) so the destination array name cannot execute code.
docker_compose_resolve() {
  local __out_name="${1:-DOCKER_COMPOSE_CMD}"
  # Nameref destination is an array in callers; SC2178 is a false positive here.
  # shellcheck disable=SC2178
  local -n __out="$__out_name"
  if docker compose version >/dev/null 2>&1; then
    __out=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    __out=(docker-compose)
  else
    return 1
  fi
}

# Human-readable label for the detected compose program (used in preflight output).
docker_compose_program() {
  local -a __cmd=()
  local IFS=' '
  docker_compose_resolve __cmd || return 1
  printf '%s' "${__cmd[*]}"
}

docker_compose_available() {
  local -a __cmd=()
  docker_compose_resolve __cmd
}

host_arch_label() {
  case "$(uname -m 2>/dev/null || echo unknown)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) printf '%s\n' "$(uname -m 2>/dev/null || echo unknown)" ;;
  esac
}

# ------------------------------------------------------------
# Published-port conflict handling
# ------------------------------------------------------------
# True (returns 0) when nothing is listening on the given host TCP port.
# Uses ss, then netstat, then a bash /dev/tcp connect probe -- dependency-light
# and works before Docker itself has published anything.
docker_port_available() {
  local port="${1:-}"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  if command -v ss >/dev/null 2>&1; then
    ! ${SUDO:-} ss -Hltn "sport = :${port}" 2>/dev/null | grep -q .
    return
  fi
  if command -v netstat >/dev/null 2>&1; then
    ! ${SUDO:-} netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
    return
  fi
  # Last resort: if a TCP connection opens, something is already listening.
  if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
    exec 3>&- 2>/dev/null || true
    return 1
  fi
  return 0
}

# Ensure DOCKER_PUBLISH_PORT is free before we publish it. Interactive sessions
# are prompted for a replacement; non-interactive / -y runs auto-pick the next
# free port scanning upward. Sets DOCKER_PUBLISH_PORT to the resolved value.
docker_ensure_publish_port() {
  local port="${DOCKER_PUBLISH_PORT:-8080}" reply candidate tries=0
  if docker_port_available "$port"; then
    return 0
  fi
  warn "Host port ${port} is already in use by another process."
  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    while :; do
      read -r -p "Choose a different host port for ERPNext [1024-65535]: " reply
      if [[ ! "$reply" =~ ^[0-9]+$ ]] || (( reply < 1 || reply > 65535 )); then
        echo "Please enter a valid port number (1-65535)."
        continue
      fi
      if ! docker_port_available "$reply"; then
        echo "Port ${reply} is also in use; pick another."
        continue
      fi
      DOCKER_PUBLISH_PORT="$reply"
      ok "Using host port ${DOCKER_PUBLISH_PORT}."
      return 0
    done
  fi
  candidate="$port"
  while (( tries < 200 )); do
    candidate=$(( candidate + 1 ))
    (( candidate > 65535 )) && candidate=1024
    if docker_port_available "$candidate"; then
      DOCKER_PUBLISH_PORT="$candidate"
      warn "Auto-selected free host port ${DOCKER_PUBLISH_PORT} (was ${port})."
      return 0
    fi
    tries=$(( tries + 1 ))
  done
  fail "Could not find a free host port near ${port}. Set DOCKER_PUBLISH_PORT to an open port and retry."
}

# Read /etc/os-release and classify Docker-host support. Prints "STATUS|Pretty".
# Docker is OS-agnostic for the workload, so the officially supported Docker
# Engine hosts we track -- Ubuntu 24.04/26.04 and Debian 11/12/13 -- are OK;
# anything else is a soft WARN (still allowed) rather than a hard fail.
docker_host_os_eval() {
  local id="" ver="" pretty="unknown"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    ver="${VERSION_ID:-}"
    pretty="${PRETTY_NAME:-unknown}"
  fi
  case "${id}:${ver}" in
    ubuntu:24.04|ubuntu:26.04) printf 'OK|%s\n' "$pretty" ;;
    debian:11|debian:12|debian:13) printf 'OK|%s\n' "$pretty" ;;
    *) printf 'WARN|%s\n' "$pretty" ;;
  esac
}

# ------------------------------------------------------------
# Compose wrapper (mode-aware)
# ------------------------------------------------------------
# Ordered list of compose -f files for the active DOCKER_MODE, one per line.
#   development -> upstream pwd.yml + our generated override
#   production  -> upstream compose.yaml + mariadb + redis overrides + our
#                  generated image-pin override + the HTTP (noproxy) override.
#                  (P5 swaps the noproxy override for the Traefik https override.)
docker_compose_file_list() {
  local overrides
  overrides="$(docker_overrides_dir)"
  if docker_is_production; then
    printf '%s\n' "$(docker_prod_base_file)"
    printf '%s\n' "${overrides}/compose.mariadb.yaml"
    printf '%s\n' "${overrides}/compose.redis.yaml"
    printf '%s\n' "$(docker_prod_image_override_file)"
    printf '%s\n' "$(docker_prod_proxy_override)"
  else
    printf '%s\n' "$(docker_compose_base_file)"
    printf '%s\n' "$(docker_override_file)"
  fi
}

# Which reverse-proxy override the production stack composes, by HTTPS mode:
#   http               -> upstream noproxy (frontend published on HTTP_PUBLISH_PORT)
#   letsencrypt        -> upstream Traefik HTTP-01 override (compose.https.yaml)
#   cloudflare-origin  -> toolkit Traefik override serving the provided origin cert
docker_prod_proxy_override() {
  local overrides
  overrides="$(docker_overrides_dir)"
  case "$(docker_https_mode)" in
    letsencrypt) printf '%s\n' "${overrides}/compose.https.yaml" ;;
    cloudflare-origin) printf '%s\n' "$(docker_prod_https_cf_override_file)" ;;
    *) printf '%s\n' "${overrides}/compose.noproxy.yaml" ;;
  esac
}

docker_active_env_file() {
  if docker_is_production; then docker_prod_env_file; else docker_env_file; fi
}

# Run docker compose with the project name, the mode-appropriate file set, and
# the mode-appropriate env file. All extra args are passed straight through.
docker_compose() {
  local envf primary f
  local -a compose_cmd=() file_args=()
  docker_compose_resolve compose_cmd || { err "Docker Compose is not available."; return 1; }
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    file_args+=(-f "$f")
  done < <(docker_compose_file_list)
  primary="${file_args[1]:-}"
  if [[ ! -f "$primary" ]]; then
    err "Compose base not found: ${primary}. Run the Docker install first ($(toolkit_cmd install))."
    return 1
  fi
  envf="$(docker_active_env_file)"
  # $SUDO is a single token ("sudo" or empty) so it is safe to leave unquoted;
  # the compose program is expanded from an array to survive the restricted IFS.
  # shellcheck disable=SC2086
  ${SUDO:-} "${compose_cmd[@]}" -p "$DOCKER_PROJECT_NAME" --env-file "$envf" "${file_args[@]}" "$@"
}

# ------------------------------------------------------------
# Host engine install (Docker Engine + compose plugin)
# ------------------------------------------------------------
# Install from Docker's official apt repository using a signed keyring and
# distribution-pinned packages. This is the hardened path: packages are
# GPG-verified by apt against Docker's published key, rather than executing an
# arbitrary remote script as root. Returns non-zero (so the caller can fall
# back) on any distro/repo problem -- e.g. a brand-new Debian codename whose
# packages Docker has not published yet. Only apt-based hosts (Ubuntu/Debian)
# are attempted here.
docker_install_engine_apt_repo() {
  require_sudo
  local id="" codename="" arch keyring list url
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    codename="${VERSION_CODENAME:-}"
  fi
  case "$id" in
    ubuntu|debian) ;;
    *) return 1 ;;
  esac
  [[ -n "$codename" ]] || codename="$(lsb_release -cs 2>/dev/null || true)"
  [[ -n "$codename" ]] || return 1

  url="https://download.docker.com/linux/${id}"
  keyring="/etc/apt/keyrings/docker.gpg"
  list="/etc/apt/sources.list.d/docker.list"

  log "Installing Docker Engine from the official Docker apt repository (${id} ${codename})"

  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -y >/dev/null 2>&1 || true
  $SUDO apt-get install -y ca-certificates curl gnupg >/dev/null 2>&1 || return 1

  $SUDO install -m 0755 -d /etc/apt/keyrings || return 1
  # Re-fetch the key each time so a rotated key is picked up; dearmor to a keyring.
  if ! curl -fsSL "${url}/gpg" | $SUDO gpg --batch --yes --dearmor -o "$keyring" 2>/dev/null; then
    return 1
  fi
  $SUDO chmod a+r "$keyring" || true

  arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  printf 'deb [arch=%s signed-by=%s] %s %s stable\n' "$arch" "$keyring" "$url" "$codename" \
    | $SUDO tee "$list" >/dev/null || return 1

  if ! $SUDO apt-get update -y >/dev/null 2>&1; then
    # Bad/empty repo for this codename: drop the source so a later apt-get on the
    # host is not left broken, then signal fallback.
    $SUDO rm -f "$list"
    return 1
  fi
  if ! $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# Legacy fallback: the official convenience script. Kept only for hosts where the
# apt repository path is unavailable (e.g. a Debian codename Docker has not yet
# published). We download first, then run, so the script is not piped straight
# from curl into a root shell.
docker_install_engine_convenience() {
  require_sudo
  warn "Falling back to the Docker convenience script (get.docker.com)."
  warn "This is less hardened than the signed apt repository; used only because the repository path was unavailable."
  local tmp
  tmp="$(mktemp /tmp/erpnext-dev-get-docker.XXXXXX.sh)" || return 1
  if ! curl -fsSL https://get.docker.com -o "$tmp"; then
    rm -f "$tmp"
    err "Could not download the Docker installation script. Check internet access and retry."
    return 1
  fi
  if ! $SUDO sh "$tmp"; then
    rm -f "$tmp"
    err "Docker Engine installation failed. Install Docker manually, then re-run."
    return 1
  fi
  rm -f "$tmp"
  return 0
}

docker_install_engine() {
  require_sudo

  if docker_daemon_ready && docker_compose_available; then
    ok "Docker Engine and Compose already present."
    return 0
  fi

  if docker_binary_present && ! docker_daemon_ready; then
    log "Docker is installed but the daemon is not reachable. Attempting to start it."
    $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
    if docker_daemon_ready && docker_compose_available; then
      ok "Docker daemon started."
      return 0
    fi
  fi

  # Prefer the official signed apt repository; fall back to the convenience
  # script only if that path is unavailable for this host.
  if docker_install_engine_apt_repo; then
    ok "Docker Engine installed from the official Docker apt repository."
  else
    warn "Official Docker apt repository unavailable for this host."
    docker_install_engine_convenience || fail "Docker Engine installation failed. Install Docker manually, then re-run."
  fi

  $SUDO systemctl enable --now docker >/dev/null 2>&1 || true

  if docker_daemon_ready && docker_compose_available; then
    ok "Docker Engine and Compose installed."
    return 0
  fi
  fail "Docker was installed but the daemon or compose plugin is still unavailable."
}

# ------------------------------------------------------------
# Preflight (engine-aware summary block)
# ------------------------------------------------------------
docker_preflight() {
  local os_eval os_status os_pretty compat_status compat_detail

  os_eval="$(docker_host_os_eval)"
  os_status="${os_eval%%|*}"
  os_pretty="${os_eval#*|}"

  if docker_daemon_ready && docker_compose_available; then
    compat_status="OK"
    compat_detail="Docker daemon reachable, Compose available"
  elif docker_binary_present; then
    compat_status="WARN"
    compat_detail="Docker present; will start daemon / install Compose during setup"
  else
    compat_status="INFO"
    compat_detail="Docker not installed; will install during setup"
  fi

  local mode base_label
  mode="$(docker_mode_label)"
  if docker_is_production; then
    case "$(docker_https_mode)" in
      letsencrypt) base_label="compose.yaml + mariadb/redis + Traefik HTTPS (Let's Encrypt)" ;;
      cloudflare-origin) base_label="compose.yaml + mariadb/redis + Traefik HTTPS (Cloudflare Origin CA)" ;;
      *) base_label="compose.yaml + mariadb/redis + HTTP (noproxy)" ;;
    esac
  else
    base_label="pwd.yml (disposable dev stack)"
  fi

  ui_box_start "Docker Deployment Preflight"
  status_line "Operating system" "$os_status" "$os_pretty"
  status_line "Deployment engine" "INFO" "Docker"
  status_line "Deployment mode" "INFO" "$mode"
  status_line "Compose base" "INFO" "$base_label"
  status_line "Architecture" "INFO" "$(host_arch_label)"
  status_line "Docker compatibility" "$compat_status" "$compat_detail"
  status_line "ERPNext image" "INFO" "$DOCKER_ERPNEXT_IMAGE"
  status_line "Upstream pin" "INFO" "frappe_docker @ ${FRAPPE_DOCKER_REF}"
  status_line "Published port" "INFO" "${DOCKER_PUBLISH_PORT} -> 8080 (container)"
  status_line "Site name" "INFO" "$(docker_site_name)"
  ui_box_end

  if [[ "$os_status" == "WARN" ]]; then
    warn "Host OS is outside the tested set (Ubuntu 24.04/26.04, Debian 13). Docker install may still work."
  fi
  return 0
}

# ------------------------------------------------------------
# Provisioning
# ------------------------------------------------------------
docker_frappe_ref_is_sha() {
  [[ "${1:-}" =~ ^[0-9a-f]{7,40}$ ]]
}

docker_checkout_frappe_ref() {
  # Fetch/checkout FRAPPE_DOCKER_REF whether it is a branch, tag, or commit SHA.
  local clone="$1"
  if docker_frappe_ref_is_sha "$FRAPPE_DOCKER_REF"; then
    $SUDO git -C "$clone" fetch --depth 1 origin "$FRAPPE_DOCKER_REF" >/dev/null 2>&1 \
      || $SUDO git -C "$clone" fetch --depth 1 origin >/dev/null 2>&1 \
      || true
    if ! $SUDO git -C "$clone" checkout -q "$FRAPPE_DOCKER_REF" 2>/dev/null; then
      $SUDO git -C "$clone" checkout -q FETCH_HEAD 2>/dev/null \
        || fail "Could not check out frappe_docker SHA ${FRAPPE_DOCKER_REF}"
    fi
  else
    $SUDO git -C "$clone" fetch --depth 1 origin "$FRAPPE_DOCKER_REF" >/dev/null 2>&1 || true
    $SUDO git -C "$clone" checkout -q "$FRAPPE_DOCKER_REF" 2>/dev/null || true
    $SUDO git -C "$clone" reset --hard "origin/${FRAPPE_DOCKER_REF}" >/dev/null 2>&1 || true
  fi
}

docker_provision_workdir() {
  require_sudo
  local clone
  clone="$(docker_clone_dir)"

  $SUDO mkdir -p "$DOCKER_WORKDIR" || fail "Could not create ${DOCKER_WORKDIR}"

  if [[ -d "${clone}/.git" ]]; then
    log "Updating frappe_docker checkout (${FRAPPE_DOCKER_REF})"
    docker_checkout_frappe_ref "$clone"
  else
    log "Cloning frappe_docker (${FRAPPE_DOCKER_REF}) into ${clone}"
    $SUDO rm -rf "$clone"
    if docker_frappe_ref_is_sha "$FRAPPE_DOCKER_REF"; then
      $SUDO mkdir -p "$clone"
      $SUDO git -C "$clone" init -q >/dev/null 2>&1 \
        || fail "Could not init frappe_docker checkout at ${clone}"
      $SUDO git -C "$clone" remote add origin "$FRAPPE_DOCKER_REPO" >/dev/null 2>&1 \
        || fail "Could not add frappe_docker remote"
      $SUDO git -C "$clone" fetch --depth 1 origin "$FRAPPE_DOCKER_REF" >/dev/null 2>&1 \
        || fail "Could not fetch frappe_docker SHA ${FRAPPE_DOCKER_REF}"
      $SUDO git -C "$clone" checkout -q FETCH_HEAD >/dev/null 2>&1 \
        || fail "Could not check out frappe_docker SHA ${FRAPPE_DOCKER_REF}"
    elif ! $SUDO git clone --depth 1 --branch "$FRAPPE_DOCKER_REF" "$FRAPPE_DOCKER_REPO" "$clone" >/dev/null 2>&1; then
      # Fallback: full clone then checkout (unusual branch/tag shapes).
      $SUDO rm -rf "$clone"
      $SUDO git clone "$FRAPPE_DOCKER_REPO" "$clone" >/dev/null 2>&1 || fail "Could not clone frappe_docker from ${FRAPPE_DOCKER_REPO}"
      $SUDO git -C "$clone" checkout -q "$FRAPPE_DOCKER_REF" 2>/dev/null || warn "Could not check out ref ${FRAPPE_DOCKER_REF}; using default branch."
    fi
  fi

  if [[ ! -f "$(docker_compose_base_file)" ]]; then
    fail "frappe_docker did not provide pwd.yml at $(docker_compose_base_file)."
  fi

  if docker_is_production; then
    local overrides missing=()
    overrides="$(docker_overrides_dir)"
    [[ -f "$(docker_prod_base_file)" ]] || missing+=("compose.yaml")
    [[ -f "${overrides}/compose.mariadb.yaml" ]] || missing+=("overrides/compose.mariadb.yaml")
    [[ -f "${overrides}/compose.redis.yaml" ]] || missing+=("overrides/compose.redis.yaml")
    [[ -f "${overrides}/compose.noproxy.yaml" ]] || missing+=("overrides/compose.noproxy.yaml")
    [[ -f "${overrides}/compose.https.yaml" ]] || missing+=("overrides/compose.https.yaml")
    if [[ ${#missing[@]} -gt 0 ]]; then
      fail "frappe_docker checkout is missing production files: ${missing[*]}. Try a different FRAPPE_DOCKER_REF."
    fi
  fi

  # Record the exact commit actually checked out so the provision is auditable /
  # reproducible even when FRAPPE_DOCKER_REF is a moving branch like main.
  DOCKER_FRAPPE_DOCKER_SHA="$($SUDO git -C "$clone" rev-parse HEAD 2>/dev/null || echo unknown)"
  ok "frappe_docker ready at ${clone} (commit ${DOCKER_FRAPPE_DOCKER_SHA})"
}

# Best-effort: record the immutable RepoDigest of the pulled ERPNext image so the
# exact bits can be reproduced/audited later. No-op when docker or the image is
# not available yet.
docker_record_image_digest() {
  local digest
  docker_binary_present || return 0
  digest="$(${SUDO:-} docker inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$DOCKER_ERPNEXT_IMAGE" 2>/dev/null || true)"
  [[ -n "$digest" ]] && DOCKER_ERPNEXT_IMAGE_DIGEST="$digest"
  return 0
}

# Persist immutable identifiers for the provisioned stack (audit / reproducibility).
# Written after images are pulled so the digest can be resolved.
docker_write_pins() {
  require_sudo
  docker_record_image_digest
  $SUDO mkdir -p "$DOCKER_WORKDIR"
  $SUDO tee "$DOCKER_PINS_FILE" >/dev/null <<EOF_DOCKER_PINS
# ERPNext Developer Toolkit - Docker immutable pins (audit / reproducibility)
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# To reproduce this exact stack, set these in the environment before install:
#   FRAPPE_DOCKER_REF=<FRAPPE_DOCKER_SHA below>
#   DOCKER_ERPNEXT_IMAGE=<DOCKER_ERPNEXT_IMAGE_DIGEST below, if recorded>
FRAPPE_DOCKER_REPO=${FRAPPE_DOCKER_REPO}
FRAPPE_DOCKER_REF=${FRAPPE_DOCKER_REF}
FRAPPE_DOCKER_SHA=${DOCKER_FRAPPE_DOCKER_SHA:-unknown}
DOCKER_ERPNEXT_IMAGE=${DOCKER_ERPNEXT_IMAGE}
DOCKER_ERPNEXT_IMAGE_DIGEST=${DOCKER_ERPNEXT_IMAGE_DIGEST:-unrecorded}
EOF_DOCKER_PINS
  $SUDO chmod 644 "$DOCKER_PINS_FILE" 2>/dev/null || true
  ok "Recorded immutable pins to ${DOCKER_PINS_FILE}"
}

# Write the Docker credential record in the same structured format used by the
# native engine so the shared Credentials / Login menu can parse either engine.
docker_write_credentials_record() {
  require_sudo
  local admin_pw="$1" db_pw="$2" mode="${3:-$(docker_mode_label)}" site domain
  site="$(docker_site_name)"
  domain="$(docker_public_domain)"

  $SUDO mkdir -p "$DOCKER_WORKDIR"
  $SUDO tee "$DOCKER_CREDENTIALS_FILE" >/dev/null <<EOF_DOCKER_CREDS
ERPNext Developer Toolkit - Docker Credentials

Site:
  ${site}

Deployment:
  Engine: Docker
  Mode: ${mode}

Login:
  Username: Administrator
  Password: ${admin_pw}

MariaDB Root:
  User: root
  Password: ${db_pw}

Browser access:
  Direct Docker HTTP: $(docker_direct_http_url localhost)
  Friendly local HTTP: http://${site}:${DOCKER_PUBLISH_PORT}
  Production domain: ${domain}
EOF_DOCKER_CREDS
  $SUDO chown root:root "$DOCKER_CREDENTIALS_FILE" 2>/dev/null || true
  $SUDO chmod 600 "$DOCKER_CREDENTIALS_FILE" 2>/dev/null || true
}

# Recreate a missing Docker credentials record from the root-only Compose env
# files when the secrets are still recoverable there. This repairs beta.1-style
# installations whose shared Credentials menu looked only at the native path.

# Keep the root-only Docker env record and the human-readable credentials record
# aligned after an Administrator password reset from the shared credentials menu.
docker_update_credentials_admin_password() {
  require_sudo
  local new_password="$1" envf tmp db_pw had_credentials=0
  path_is_file "$DOCKER_CREDENTIALS_FILE" && had_credentials=1

  # The development compose env carries the generated Administrator password for
  # create-site. Keep it aligned if it exists so a later dev->production promotion
  # does not re-advertise the old password. Production env does not retain this
  # application login secret after provisioning.
  envf="$(docker_env_file)"
  if [[ -f "$envf" ]]; then
    tmp="$(mktemp /tmp/erpnext-dev-docker-env.XXXXXX)" || return 1
    $SUDO awk '$0 !~ /^DOCKER_ADMIN_PASSWORD=/' "$envf" >"$tmp" || { rm -f "$tmp"; return 1; }
    printf 'DOCKER_ADMIN_PASSWORD=%s\n' "$new_password" >>"$tmp"
    $SUDO install -o root -g root -m 600 "$tmp" "$envf"
    rm -f "$tmp"
  fi

  # Respect an intentional credentials-delete handoff. Refresh the record only
  # when it was present before the password reset.
  if [[ "$had_credentials" -eq 1 ]]; then
    db_pw="$(docker_db_root_password)"
    docker_write_credentials_record "$new_password" "$db_pw" "$(docker_mode_label)"
  fi
}

# Generate the env file consumed by compose interpolation. Admin/db passwords are
# kept here (root-owned, 600) instead of on the compose command line.
docker_write_env() {
  require_sudo
  local envf admin_pw db_pw
  envf="$(docker_env_file)"
  admin_pw="${DOCKER_ADMIN_PASSWORD:-$(random_password)}"
  db_pw="${DOCKER_DB_ROOT_PASSWORD:-admin}"
  DOCKER_ADMIN_PASSWORD="$admin_pw"

  $SUDO mkdir -p "$DOCKER_WORKDIR"
  $SUDO tee "$envf" >/dev/null <<EOF_DOCKER_ENV
DOCKER_ERPNEXT_IMAGE=${DOCKER_ERPNEXT_IMAGE}
DOCKER_PUBLISH_PORT=${DOCKER_PUBLISH_PORT}
DOCKER_SITE_NAME=$(docker_site_name)
DOCKER_ADMIN_PASSWORD=${admin_pw}
DOCKER_DB_ROOT_PASSWORD=${db_pw}
EOF_DOCKER_ENV
  $SUDO chown root:root "$envf" 2>/dev/null || true
  $SUDO chmod 600 "$envf" 2>/dev/null || true

  docker_write_credentials_record "$admin_pw" "$db_pw" "development"
}

# Overlay that pins the image, publishes the chosen port, forces the site header,
# and recreates the site with the configured name + admin password. Written with
# a quoted heredoc so ${...} stays literal for compose interpolation and $$ keeps
# its runtime-shell meaning inside the create-site command (as in upstream).
#
# NOTE: the create-site `until` condition is kept on a SINGLE physical line. In a
# YAML `>` folded scalar, backslash line-continuations become `\ ` (escaped space)
# once lines are folded, which turns the following `[[` from a bash keyword into a
# missing command ("[[: command not found") so the wait loop never completes and
# the site is never created. Do not reintroduce `\` continuations here.
docker_write_override() {
  require_sudo
  local override
  override="$(docker_override_file)"

  $SUDO mkdir -p "$DOCKER_WORKDIR"
  $SUDO tee "$override" >/dev/null <<'EOF_DOCKER_OVERRIDE'
services:
  backend:
    image: ${DOCKER_ERPNEXT_IMAGE}
  configurator:
    image: ${DOCKER_ERPNEXT_IMAGE}
  create-site:
    image: ${DOCKER_ERPNEXT_IMAGE}
    environment:
      SITE_NAME: ${DOCKER_SITE_NAME}
      ADMIN_PASSWORD: ${DOCKER_ADMIN_PASSWORD}
      DB_ROOT_PASSWORD: ${DOCKER_DB_ROOT_PASSWORD}
    entrypoint:
      - bash
      - -c
    command:
      - >
        wait-for-it -t 120 db:3306;
        wait-for-it -t 120 redis-cache:6379;
        wait-for-it -t 120 redis-queue:6379;
        export start=`date +%s`;
        until [[ -n `grep -hs ^ sites/common_site_config.json | jq -r ".db_host // empty"` ]] && [[ -n `grep -hs ^ sites/common_site_config.json | jq -r ".redis_cache // empty"` ]] && [[ -n `grep -hs ^ sites/common_site_config.json | jq -r ".redis_queue // empty"` ]];
        do
          echo "Waiting for sites/common_site_config.json to be created";
          sleep 5;
          if (( `date +%s`-start > 120 )); then
            echo "could not find sites/common_site_config.json with required keys";
            exit 1
          fi
        done;
        echo "sites/common_site_config.json found";
        if [ -d "sites/$$SITE_NAME" ]; then
          echo "Site $$SITE_NAME already exists; skipping create-site";
          exit 0;
        fi;
        bench new-site --mariadb-user-host-login-scope='%' --admin-password="$$ADMIN_PASSWORD" --db-root-username=root --db-root-password="$$DB_ROOT_PASSWORD" --install-app erpnext --set-default "$$SITE_NAME";
  db:
    image: mariadb:11.8
  frontend:
    image: ${DOCKER_ERPNEXT_IMAGE}
    environment:
      FRAPPE_SITE_NAME_HEADER: ${DOCKER_SITE_NAME}
    ports:
      - "${DOCKER_PUBLISH_PORT}:8080"
  queue-long:
    image: ${DOCKER_ERPNEXT_IMAGE}
  queue-short:
    image: ${DOCKER_ERPNEXT_IMAGE}
  scheduler:
    image: ${DOCKER_ERPNEXT_IMAGE}
  websocket:
    image: ${DOCKER_ERPNEXT_IMAGE}
EOF_DOCKER_OVERRIDE
  $SUDO chown root:root "$override" 2>/dev/null || true
  $SUDO chmod 644 "$override" 2>/dev/null || true
}

# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------
docker_compose_up() {
  require_sudo
  log "Starting the Docker stack (pulling images may take several minutes on first run)"
  docker_compose up -d
}

# Wait for the one-shot create-site job to finish and confirm it succeeded.
#
# `docker compose up -d` returns as soon as containers START, not when the
# one-shot create-site job COMPLETES. Without this check a failed site creation
# looks like a successful install and the published port then answers 404
# forever (the frontend is up but the backend has no such site). This blocks
# until create-site exits, surfaces its logs on failure, and returns non-zero so
# the caller can fail loudly with the real root cause.
docker_wait_for_site_creation() {
  require_sudo
  local deadline now cid state code
  deadline=$(( $(date +%s) + DOCKER_CREATE_SITE_TIMEOUT ))
  log "Waiting for the create-site job to finish (site: $(docker_site_name))"
  while :; do
    cid="$(docker_compose ps -aq create-site 2>/dev/null | tail -n1)"
    if [[ -n "$cid" ]]; then
      state="$(${SUDO:-} docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
      if [[ "$state" == "exited" ]]; then
        code="$(${SUDO:-} docker inspect -f '{{.State.ExitCode}}' "$cid" 2>/dev/null || echo 1)"
        if [[ "$code" == "0" ]]; then
          ok "Site created: $(docker_site_name)"
          return 0
        fi
        err "create-site job failed (exit ${code}). Recent create-site logs:"
        docker_compose logs --no-color --tail 120 create-site 2>/dev/null || true
        return 1
      fi
    fi
    now="$(date +%s)"
    if [[ "$now" -ge "$deadline" ]]; then
      warn "create-site did not finish within ${DOCKER_CREATE_SITE_TIMEOUT}s. Recent create-site logs:"
      docker_compose logs --no-color --tail 120 create-site 2>/dev/null || true
      return 1
    fi
    sleep 5
  done
}

docker_runtime_start() {
  require_sudo
  if [[ ! -f "$(docker_compose_base_file)" ]]; then
    fail "Docker stack is not provisioned yet. Run: $(toolkit_cmd install)"
  fi
  docker_compose up -d && docker_ready && docker_print_access
}

docker_runtime_stop() {
  require_sudo
  docker_compose stop
}

docker_runtime_restart() {
  require_sudo
  docker_compose restart
}

docker_runtime_status() {
  require_sudo
  docker_compose ps
}

docker_runtime_logs() {
  require_sudo
  docker_compose logs --tail 160
}

# Poll published HTTP until ping + login static assets answer (or timeout).
docker_ready() {
  local url deadline now site route_host route_port route_ip probe_rc=1 curl_code
  site="$(docker_site_name 2>/dev/null || echo localhost)"
  deadline=$(( $(date +%s) + DOCKER_READY_TIMEOUT ))

  if docker_is_production && docker_https_enabled; then
    route_host="$(docker_public_domain)"
    route_port=443
    route_ip=127.0.0.1
    url="https://${route_host}/api/method/ping"
    log "Waiting for ERPNext ping + static assets on https://${route_host}"
  else
    route_host="$site"
    route_port="${DOCKER_PUBLISH_PORT:-8080}"
    route_ip=127.0.0.1
    url="http://${site}:${route_port}/api/method/ping"
    log "Waiting for ERPNext ping + static assets on http://localhost:${route_port}"
  fi

  while :; do
    if [[ "$url" == https://* ]]; then
      curl_code="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 5 \
        --resolve "${route_host}:${route_port}:${route_ip}" "$url" 2>/dev/null || true)"
    else
      curl_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
        -H "Host: ${site}" "http://127.0.0.1:${route_port}/api/method/ping" 2>/dev/null || true)"
    fi

    if [[ "$curl_code" =~ ^(200|401|403)$ ]]; then
      set +e
      if [[ "$url" == https://* ]]; then
        probe_login_frontend_assets_all \
          "https://${route_host}/login" \
          "$route_host" \
          "$route_port" \
          "$route_ip" >/dev/null
      else
        probe_login_frontend_assets_all \
          "http://${site}:${route_port}/login" \
          "$site" \
          "$route_port" \
          "$route_ip" >/dev/null
      fi
      probe_rc=$?
      set -e
      if [[ "$probe_rc" -eq 0 ]]; then
        if [[ "$url" == https://* ]]; then
          ok "ERPNext is responding through Docker HTTPS (HTTP + CSS/JS assets)."
        else
          ok "ERPNext is responding on port ${route_port} (HTTP + CSS/JS assets)."
        fi
        return 0
      fi
    fi

    now="$(date +%s)"
    if [[ "$now" -ge "$deadline" ]]; then
      warn "ERPNext did not become fully ready within ${DOCKER_READY_TIMEOUT}s."
      echo "Next steps:"
      echo "  Status:       $(toolkit_cmd engine-status)"
      echo "  Access:       $(toolkit_cmd verify-access)"
      echo "  Logs:         $(toolkit_cmd logs)"
      echo "  Diagnostics:  $(toolkit_cmd doctor)"
      echo "  Cold start?   Increase DOCKER_READY_TIMEOUT (current ${DOCKER_READY_TIMEOUT}s) and retry."
      return 1
    fi
    sleep 5
  done
}

# Run a bench command inside the backend container. Mirrors run_as_frappe for the
# native engine (this is the engine_bench seam).
docker_bench() {
  require_sudo
  docker_compose exec -T backend bench "$@"
}

# ------------------------------------------------------------
# Disaster recovery (P3): durable host artifacts + restore + rehearsal
# ------------------------------------------------------------
# Absolute bench dir inside the frappe/erpnext image (WORKDIR of every service).
docker_container_bench_dir() { printf '/home/frappe/frappe-bench\n'; }
# `docker compose cp` preserves the host file's (root) ownership, but bench runs
# as the unprivileged `frappe` user inside the container, so a staged backup
# lands unreadable. Make it world-readable so `bench restore` can open it.
docker_make_container_readable() {
  local path="$1"
  docker_compose exec -T -u root backend chmod 0644 "$path" >/dev/null 2>&1 || true
}
# Per-site root for exported host artifacts: <DOCKER_BACKUP_DIR>/<site>/<prefix>/.
docker_backup_site_root() { printf '%s/%s\n' "$DOCKER_BACKUP_DIR" "$(docker_site_name)"; }

# Read a single KEY=value from a root-owned env file, permission-safe under sudo.
docker_env_value() {
  local envf="$1" key="$2"
  ${SUDO:-} awk -F= -v k="$key" '$1==k{v=$0; sub(/^[^=]*=/,"",v)} END{print v}' "$envf" 2>/dev/null || true
}

# Resolve the MariaDB root password used by restore/rehearsal. Production stores a
# generated password in the prod env file (DB_PASSWORD); development uses
# DOCKER_DB_ROOT_PASSWORD (default "admin").
docker_db_root_password() {
  local envf val
  envf="$(docker_active_env_file)"
  if docker_is_production; then
    val="$(docker_env_value "$envf" DB_PASSWORD)"
  else
    val="$(docker_env_value "$envf" DOCKER_DB_ROOT_PASSWORD)"
  fi
  printf '%s\n' "${val:-admin}"
}

# Newest exported host artifact directory for the current site (empty if none).
docker_latest_host_dir() {
  local root
  root="$(docker_backup_site_root)"
  ${SUDO:-} test -d "$root" || return 1
  ${SUDO:-} find "$root" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -n1 | cut -d' ' -f2-
}

# Write MANIFEST.txt + SHA256SUMS into an exported artifact directory.
docker_backup_write_manifest() {
  local dir="$1" prefix="$2" site="$3"
  ${SUDO:-} tee "${dir}/MANIFEST.txt" >/dev/null <<EOF_DOCKER_BK_MANIFEST
# ERPNext Developer Toolkit - Docker backup manifest
site=${site}
prefix=${prefix}
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
engine=docker
mode=$(docker_mode_label)
image=${DOCKER_ERPNEXT_IMAGE}
image_digest=${DOCKER_ERPNEXT_IMAGE_DIGEST:-unrecorded}
frappe_docker_sha=${DOCKER_FRAPPE_DOCKER_SHA:-unrecorded}
compose_project=${DOCKER_PROJECT_NAME}
toolkit_version=${SCRIPT_VERSION:-unknown}
EOF_DOCKER_BK_MANIFEST
  # Checksums over every component (excluding SHA256SUMS itself) for verify/restore.
  ${SUDO:-} sh -c "cd '$dir' && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs -r sha256sum > SHA256SUMS" 2>/dev/null || true
  ${SUDO:-} chmod -R go-rwx "$dir" 2>/dev/null || true
}

# Take a backup inside the backend container, then EXPORT the newest set out of
# the sites volume to a durable, root-owned host artifact directory. This is the
# heart of P3: a Docker volume alone is not a backup, so every backup lands as a
# self-describing host artifact that verify/restore/rehearsal can consume.
docker_backup() {
  require_sudo
  local include_files="${1:-false}"
  local site bench db_rel db_base prefix host_dir f copied=0

  site="$(docker_site_name)"
  bench="$(docker_container_bench_dir)"

  if [[ "$include_files" == "true" ]]; then
    log "Creating database + files backup for ${site} (Docker)"
    docker_bench --site "$site" backup --with-files || { err "bench backup failed."; return 1; }
  else
    log "Creating database backup for ${site} (Docker)"
    docker_bench --site "$site" backup || { err "bench backup failed."; return 1; }
  fi

  # Identify the newest database file inside the container (relative to bench dir).
  db_rel="$(docker_compose exec -T backend bash -c "ls -1t sites/${site}/private/backups/*-database.sql.gz 2>/dev/null | head -n1" 2>/dev/null | tr -d '\r')"
  if [[ -z "$db_rel" ]]; then
    err "Could not locate the new database backup inside the container."
    return 1
  fi
  db_base="$(basename "$db_rel")"
  prefix="${db_base%-database.sql.gz}"

  host_dir="$(docker_backup_site_root)/${prefix}"
  $SUDO mkdir -p "$host_dir" || { err "Could not create host artifact dir ${host_dir}"; return 1; }
  log "Exporting backup set ${prefix} to ${host_dir}"

  for f in "${prefix}-database.sql.gz" \
           "${prefix}-site_config_backup.json" \
           "${prefix}-files.tar" "${prefix}-files.tar.gz" \
           "${prefix}-private-files.tar" "${prefix}-private-files.tar.gz"; do
    if docker_compose exec -T backend test -f "sites/${site}/private/backups/${f}" >/dev/null 2>&1; then
      if docker_compose cp "backend:${bench}/sites/${site}/private/backups/${f}" "${host_dir}/${f}" >/dev/null 2>&1; then
        copied=$((copied+1))
      else
        warn "Could not copy ${f} out of the container."
      fi
    fi
  done

  if [[ "$copied" -eq 0 ]]; then
    err "No backup files were exported to the host."
    return 1
  fi

  docker_backup_write_manifest "$host_dir" "$prefix" "$site"
  ok "Durable host backup exported: ${host_dir}"
  echo "Verify with:  $(toolkit_cmd backup-verify)"
  echo "Restore with: $(toolkit_cmd restore-full)"
  return 0
}

docker_list_backups() {
  require_sudo
  local site root
  site="$(docker_site_name)"
  root="$(docker_backup_site_root)"

  echo
  echo "============================================================"
  echo "ERPNext Backups (Docker)"
  echo "============================================================"
  echo "Site: ${site}"
  echo "Host artifact folder: ${root}"
  echo
  echo "Durable host backup sets (newest first):"
  if $SUDO test -d "$root"; then
    $SUDO find "$root" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
      | sort -nr | head -20 \
      | while read -r _ts dir; do
          printf '  %s  (%s)\n' "$(basename "$dir")" "$($SUDO du -sh "$dir" 2>/dev/null | awk '{print $1}')"
        done
  else
    echo "  none — create one with: $(toolkit_cmd backup)"
  fi
  echo
  echo "In-container backups (sites volume, not durable on their own):"
  docker_bench --site "$site" list-backups 2>/dev/null | sed 's/^/  /' || echo "  (stack not running)"
  echo
  echo "Tip: restore consumes a host backup set folder from above."
  echo "============================================================"
}

# Readability test for an exported tar/tar.gz component.
docker_backup_tar_ok() {
  local file="$1"
  if [[ "$file" == *.gz ]]; then
    $SUDO tar -tzf "$file" >/dev/null 2>&1
  else
    $SUDO tar -tf "$file" >/dev/null 2>&1
  fi
}

# Verify an exported host artifact (default: newest). Checks gzip/tar/json
# integrity and, when present, the SHA256SUMS manifest. No restore is performed.
docker_backup_verify() {
  require_sudo
  local dir="${1:-}" prefix fail_count=0 f
  [[ -n "$dir" ]] || dir="$(docker_latest_host_dir || true)"

  ui_box_start "Backup Verification (Docker)"
  status_line "Mode" "INFO" "checks exported host artifact; no restore is performed"
  status_line "Site" "INFO" "$(docker_site_name)"

  if [[ -z "$dir" ]] || ! $SUDO test -d "$dir"; then
    status_line "Host backup" "FAIL" "no durable host backup found; run $(toolkit_cmd backup)"
    ui_box_end
    return 1
  fi
  prefix="$(basename "$dir")"
  status_line "Artifact" "INFO" "$dir"
  status_line "Backup set" "INFO" "$prefix"

  if $SUDO test -f "${dir}/${prefix}-database.sql.gz" && $SUDO gzip -t "${dir}/${prefix}-database.sql.gz" >/dev/null 2>&1; then
    status_line "Database" "OK" "gzip readable ($($SUDO du -h "${dir}/${prefix}-database.sql.gz" 2>/dev/null | awk '{print $1}'))"
  else
    status_line "Database" "FAIL" "missing or unreadable"
    fail_count=$((fail_count+1))
  fi

  for f in "${prefix}-files.tar" "${prefix}-files.tar.gz"; do
    if $SUDO test -f "${dir}/${f}"; then
      if docker_backup_tar_ok "${dir}/${f}"; then
        status_line "Public files" "OK" "$f readable"
      else
        status_line "Public files" "FAIL" "$f unreadable"
        fail_count=$((fail_count+1))
      fi
      break
    fi
  done
  for f in "${prefix}-private-files.tar" "${prefix}-private-files.tar.gz"; do
    if $SUDO test -f "${dir}/${f}"; then
      if docker_backup_tar_ok "${dir}/${f}"; then
        status_line "Private files" "OK" "$f readable"
      else
        status_line "Private files" "FAIL" "$f unreadable"
        fail_count=$((fail_count+1))
      fi
      break
    fi
  done

  if $SUDO test -f "${dir}/${prefix}-site_config_backup.json"; then
    status_line "Site config" "OK" "present"
  else
    status_line "Site config" "WARN" "not exported"
  fi

  if $SUDO test -f "${dir}/SHA256SUMS"; then
    if $SUDO sh -c "cd '$dir' && sha256sum -c SHA256SUMS >/dev/null 2>&1"; then
      status_line "Checksums" "OK" "SHA256SUMS verified"
    else
      status_line "Checksums" "FAIL" "SHA256SUMS mismatch"
      fail_count=$((fail_count+1))
    fi
  else
    status_line "Checksums" "WARN" "no SHA256SUMS in artifact"
  fi

  if [[ "$fail_count" -eq 0 ]]; then
    status_line "Verification" "OK" "artifact is readable and consistent"
  else
    status_line "Verification" "FAIL" "${fail_count} problem(s); do not rely on this backup"
  fi
  echo
  echo "This is not a restore test. Prove restore end-to-end with: $(toolkit_cmd docker-restore-rehearsal)"
  ui_box_end
  [[ "$fail_count" -eq 0 ]]
}

# Interactively pick a host artifact directory (default: newest). Non-interactive
# / -y runs always use the newest set.
docker_pick_host_dir() {
  local latest reply root
  latest="$(docker_latest_host_dir || true)"
  root="$(docker_backup_site_root)"
  if [[ -z "$latest" ]]; then
    return 1
  fi
  if [[ ! -t 0 || "${ASSUME_YES:-0}" -eq 1 ]]; then
    printf '%s\n' "$latest"
    return 0
  fi
  read -r -p "Backup set to restore [$(basename "$latest")]: " reply >&2
  if [[ -z "$reply" ]]; then
    printf '%s\n' "$latest"
  elif [[ "$reply" = /* ]]; then
    printf '%s\n' "$reply"
  else
    printf '%s/%s\n' "$root" "$reply"
  fi
}

# Restore the current site from an exported host artifact. kind: db|full.
# Copies the artifact back into the container backups dir, then runs bench
# restore. Takes an emergency backup first (destructive operation).
docker_restore() {
  require_sudo
  local kind="${1:-full}" site bench dir prefix pw
  local db_base f
  site="$(docker_site_name)"
  bench="$(docker_container_bench_dir)"

  docker_list_backups
  echo
  dir="$(docker_pick_host_dir || true)"
  if [[ -z "$dir" ]] || ! $SUDO test -d "$dir"; then
    err "No host backup set selected. Create one with: $(toolkit_cmd backup)"
    return 1
  fi
  prefix="$(basename "$dir")"

  if ! $SUDO test -f "${dir}/${prefix}-database.sql.gz"; then
    err "Selected set has no database file: ${dir}/${prefix}-database.sql.gz"
    return 1
  fi

  echo
  warn "Restore OVERWRITES the running ${site} database (Docker engine, ${prefix})."
  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    local answer
    read -r -p "Type the site name (${site}) to confirm restore: " answer
    [[ "$answer" == "$site" ]] || { err "Confirmation did not match. Restore cancelled."; return 1; }
  fi

  pw="$(docker_db_root_password)"
  db_base="${prefix}-database.sql.gz"

  log "Creating emergency backup before restore"
  docker_backup true || warn "Emergency backup failed; continuing only because restore was explicitly confirmed."

  # Copy the chosen artifact into the container backups dir so bench can read it.
  docker_compose cp "${dir}/${db_base}" "backend:${bench}/sites/${site}/private/backups/${db_base}" >/dev/null 2>&1 \
    || { err "Could not copy the database backup into the container."; return 1; }
  docker_make_container_readable "${bench}/sites/${site}/private/backups/${db_base}"

  # --force is a `restore` subcommand option (not a bench-group option), so it
  # must follow the subcommand; an absolute path avoids any exec-CWD ambiguity.
  local -a restore_args=(--site "$site" restore
                         --db-root-username root --db-root-password "$pw" --force
                         "$(docker_container_bench_dir)/sites/${site}/private/backups/${db_base}")

  if [[ "$kind" == "full" ]]; then
    for f in "${prefix}-files.tar" "${prefix}-files.tar.gz"; do
      if $SUDO test -f "${dir}/${f}"; then
        if docker_compose cp "${dir}/${f}" "backend:${bench}/sites/${site}/private/backups/${f}" >/dev/null 2>&1; then
          docker_make_container_readable "${bench}/sites/${site}/private/backups/${f}"
          restore_args+=(--with-public-files "${bench}/sites/${site}/private/backups/${f}")
        fi
        break
      fi
    done
    for f in "${prefix}-private-files.tar" "${prefix}-private-files.tar.gz"; do
      if $SUDO test -f "${dir}/${f}"; then
        if docker_compose cp "${dir}/${f}" "backend:${bench}/sites/${site}/private/backups/${f}" >/dev/null 2>&1; then
          docker_make_container_readable "${bench}/sites/${site}/private/backups/${f}"
          restore_args+=(--with-private-files "${bench}/sites/${site}/private/backups/${f}")
        fi
        break
      fi
    done
  fi

  log "Restoring ${kind} backup ${prefix} into ${site}"
  if ! docker_compose exec -T backend bench "${restore_args[@]}"; then
    err "bench restore failed. Inspect with: $(toolkit_cmd logs)"
    return 1
  fi

  log "Running post-restore migrate"
  docker_bench --site "$site" migrate || warn "migrate reported an issue; review the logs."
  docker_bench --site "$site" clear-cache >/dev/null 2>&1 || true
  docker_runtime_restart || true

  ok "Restore completed for ${site} from set ${prefix}."
  docker_verify_access
  return 0
}

# Sanitize a value for the flat evidence record.
docker_rehearsal_sanitize() {
  printf '%s' "${1:-}" | tr '\n\t' '  ' | sed -E 's/[^A-Za-z0-9._:@/+=, -]/-/g' | cut -c1-240
}

# Automated Docker restore rehearsal (the containerized analog of the native
# disposable-VM rehearsal). Proves the exported artifact actually restores into a
# CLEAN, throwaway site running on the SAME image, WITHOUT touching the live site,
# then records dated evidence. Safe to run on the production stack because the
# rehearsal uses a temporary site that is dropped afterward.
docker_restore_rehearsal() {
  require_sudo
  local site bench dir prefix pw temp_site db_base rc=0 apps="" recorded_at result

  site="$(docker_site_name)"
  bench="$(docker_container_bench_dir)"

  ui_box_start "Docker Restore Rehearsal"
  status_line "Site" "INFO" "$site"
  status_line "Mode" "INFO" "$(docker_mode_label)"
  echo "Restores an exported backup into a throwaway site on the same image, then drops it."
  echo

  if ! docker_wait_service_running backend 60; then
    status_line "Stack" "FAIL" "backend container is not running; start it first ($(toolkit_cmd start))"
    ui_box_end
    return 1
  fi

  # Use the newest verified artifact; take a fresh one when none exists yet.
  dir="$(docker_latest_host_dir || true)"
  if [[ -z "$dir" ]]; then
    log "No host backup yet; taking one for the rehearsal"
    docker_backup false || { status_line "Backup" "FAIL" "could not create a backup to rehearse"; ui_box_end; return 1; }
    dir="$(docker_latest_host_dir || true)"
  fi
  if [[ -z "$dir" ]] || ! $SUDO test -d "$dir"; then
    status_line "Backup" "FAIL" "no host backup available"
    ui_box_end
    return 1
  fi
  prefix="$(basename "$dir")"
  status_line "Backup set" "OK" "$prefix"

  if ! docker_backup_verify "$dir" >/dev/null 2>&1; then
    status_line "Artifact integrity" "FAIL" "verification failed; aborting rehearsal"
    ui_box_end
    return 1
  fi
  status_line "Artifact integrity" "OK" "database/tar/checksums verified"

  pw="$(docker_db_root_password)"
  db_base="${prefix}-database.sql.gz"
  temp_site="rehearsal-$(date +%s).localhost"
  status_line "Rehearsal site" "INFO" "$temp_site (temporary)"

  # Copy the artifact DB into the container so bench can read it.
  if ! docker_compose cp "${dir}/${db_base}" "backend:${bench}/sites/${site}/private/backups/${db_base}" >/dev/null 2>&1; then
    status_line "Prepare" "FAIL" "could not stage the backup into the container"
    ui_box_end
    return 1
  fi
  docker_make_container_readable "${bench}/sites/${site}/private/backups/${db_base}"

  log "Creating throwaway site ${temp_site}"
  if ! docker_compose exec -T backend bench new-site \
      --mariadb-user-host-login-scope='%' \
      --admin-password "rehearsal-$(date +%s)" \
      --db-root-username root \
      --db-root-password "$pw" \
      --no-mariadb-socket \
      "$temp_site" >/dev/null 2>&1; then
    # Retry without --no-mariadb-socket for older bench versions.
    docker_compose exec -T backend bench new-site \
      --mariadb-user-host-login-scope='%' \
      --admin-password "rehearsal-$(date +%s)" \
      --db-root-username root \
      --db-root-password "$pw" \
      "$temp_site" >/dev/null 2>&1 || rc=1
  fi

  if [[ "$rc" -eq 0 ]]; then
    log "Restoring ${prefix} into ${temp_site}"
    local restore_log restore_path
    restore_log="$(mktemp)" || restore_log=""
    # Use an absolute path so the restore never depends on the exec CWD, and put
    # --force after the subcommand where the restore command defines it.
    restore_path="${bench}/sites/${site}/private/backups/${db_base}"
    if docker_compose exec -T backend bench --site "$temp_site" restore \
        --db-root-username root --db-root-password "$pw" --force \
        "$restore_path" >"${restore_log:-/dev/null}" 2>&1; then
      apps="$(docker_compose exec -T backend bench --site "$temp_site" list-apps 2>/dev/null | tr -d '\r' | tr '\n' ' ' | sed -E 's/ +/ /g; s/^ +| +$//g')"
      if printf '%s' "$apps" | grep -qi 'erpnext'; then
        status_line "Restore into clean site" "OK" "erpnext present after restore"
      else
        status_line "Restore into clean site" "WARN" "restored, but erpnext not detected (apps: ${apps:-none})"
        rc=1
      fi
    else
      status_line "Restore into clean site" "FAIL" "bench restore failed on the rehearsal site"
      if [[ -n "$restore_log" ]] && $SUDO test -s "$restore_log"; then
        echo "---- bench restore output (tail) ----"
        tail -n 30 "$restore_log" | sed 's/^/  /'
        echo "-------------------------------------"
      fi
      rc=1
    fi
    [[ -n "$restore_log" ]] && rm -f "$restore_log"
  else
    status_line "Rehearsal site" "FAIL" "could not create the throwaway site"
  fi

  # Always try to drop the throwaway site so no residue is left behind.
  log "Dropping throwaway site ${temp_site}"
  if docker_compose exec -T backend bench drop-site "$temp_site" \
      --db-root-username root --db-root-password "$pw" --force --no-backup >/dev/null 2>&1; then
    status_line "Cleanup" "OK" "throwaway site dropped"
  else
    status_line "Cleanup" "WARN" "could not drop ${temp_site}; drop it manually"
  fi

  recorded_at="$(date -Is 2>/dev/null || date)"
  if [[ "$rc" -eq 0 ]]; then
    result="full_restore_into_clean_site_completed"
    status_line "Rehearsal" "OK" "backup restores into a clean site of the same image"
  else
    result="restore_rehearsal_failed"
    status_line "Rehearsal" "FAIL" "see messages above"
  fi

  $SUDO mkdir -p "$(dirname "$DOCKER_RESTORE_REHEARSAL_FILE")"
  $SUDO tee "$DOCKER_RESTORE_REHEARSAL_FILE" >/dev/null <<EOF_DOCKER_REHEARSAL
DOCKER_RESTORE_REHEARSAL_STATUS=$([[ "$rc" -eq 0 ]] && echo OK || echo FAIL)
DOCKER_RESTORE_REHEARSAL_RECORDED_AT=${recorded_at}
DOCKER_RESTORE_REHEARSAL_SITE=${site}
DOCKER_RESTORE_REHEARSAL_MODE=$(docker_mode_label)
DOCKER_RESTORE_REHEARSAL_BACKUP_SET=${prefix}
DOCKER_RESTORE_REHEARSAL_TEMP_SITE=${temp_site}
DOCKER_RESTORE_REHEARSAL_IMAGE=${DOCKER_ERPNEXT_IMAGE}
DOCKER_RESTORE_REHEARSAL_IMAGE_DIGEST=${DOCKER_ERPNEXT_IMAGE_DIGEST:-unrecorded}
DOCKER_RESTORE_REHEARSAL_APPS=$(docker_rehearsal_sanitize "$apps")
DOCKER_RESTORE_REHEARSAL_RESULT=${result}
DOCKER_RESTORE_REHEARSAL_TOOLKIT_VERSION=${SCRIPT_VERSION:-unknown}
EOF_DOCKER_REHEARSAL
  $SUDO chown root:root "$DOCKER_RESTORE_REHEARSAL_FILE" 2>/dev/null || true
  $SUDO chmod 600 "$DOCKER_RESTORE_REHEARSAL_FILE" 2>/dev/null || true
  status_line "Evidence" "INFO" "$DOCKER_RESTORE_REHEARSAL_FILE"
  ui_next "$(toolkit_cmd docker-restore-evidence)" "$(toolkit_cmd backup-status)"
  ui_box_end
  [[ "$rc" -eq 0 ]]
}

# Show the recorded Docker restore-rehearsal evidence.
docker_show_restore_evidence() {
  require_sudo
  ui_box_start "Docker Restore Rehearsal Evidence"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "Record file" "$($SUDO test -f "$DOCKER_RESTORE_REHEARSAL_FILE" && echo OK || echo WARN)" "$DOCKER_RESTORE_REHEARSAL_FILE"
  if $SUDO test -f "$DOCKER_RESTORE_REHEARSAL_FILE"; then
    local status
    status="$(docker_env_value "$DOCKER_RESTORE_REHEARSAL_FILE" DOCKER_RESTORE_REHEARSAL_STATUS)"
    status_line "Last rehearsal" "$([[ "$status" == OK ]] && echo OK || echo WARN)" "${status:-unknown}"
    echo
    echo "Recorded metadata:"
    $SUDO sed -E 's/(PASSWORD|SECRET|TOKEN|KEY)=.*/=[REDACTED]/' "$DOCKER_RESTORE_REHEARSAL_FILE" | sed 's/^/  /'
  else
    echo
    echo "No Docker restore rehearsal recorded yet. Run:"
    echo "  $(toolkit_cmd docker-restore-rehearsal)"
  fi
  ui_box_end
}

# ------------------------------------------------------------
# Off-site shipment (P6): host artifact -> off-VM (rsync) -> object storage
# ------------------------------------------------------------
# The source shipped off-VM is the per-site durable host artifact tree from P3
# (DOCKER_BACKUP_DIR/<site>/<set>/...). Each set carries its own SHA256SUMS, so
# shipment can be verified at the destination rather than trusted blindly.
docker_offvm_source_dir() { docker_backup_site_root; }

# Build the ssh command array used for remote verification (mirrors native
# off_vm_append_ssh_security_opts; nameref — no eval).
docker_offvm_ssh_cmd() {
  local __out_name="${1:-DOCKER_OFFVM_SSH_CMD}"
  # shellcheck disable=SC2178
  local -n __out="$__out_name"
  local identity="${OFF_VM_BACKUP_SSH_IDENTITY:-}"
  if declare -F off_vm_backup_load_config >/dev/null 2>&1; then
    off_vm_backup_load_config
  fi
  __out=(ssh)
  if declare -F off_vm_append_ssh_security_opts >/dev/null 2>&1; then
    off_vm_append_ssh_security_opts __out
  else
    __out+=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
  fi
  if [[ -n "$identity" ]]; then
    __out+=(-i "$identity")
  fi
}

# Verify SHA256SUMS of every shipped set at the rsync destination. Best-effort:
# a picky remote shell should not fail the whole run (local sets are already
# checksummed), so callers treat a non-zero return as a soft WARN.
docker_offvm_remote_verify() {
  local target="$1" host remote_path
  local -a ssh_cmd=()
  host="${target%%:*}"
  remote_path="${target#*:}"
  [[ -n "$host" && -n "$remote_path" && "$host" != "$target" ]] || return 1
  docker_offvm_ssh_cmd ssh_cmd
  ${SUDO:-} "${ssh_cmd[@]}" "$host" \
    "cd '${remote_path}' 2>/dev/null || exit 3; rc=0; for d in */; do [ -f \"\${d}SHA256SUMS\" ] || continue; ( cd \"\$d\" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ) || rc=1; done; exit \$rc" \
    >/dev/null 2>&1
}

# Off-VM rsync of the durable host artifacts for the Docker engine. Reuses the
# native OFF_VM_BACKUP_* configuration (configure-rsync-backup-target, keys,
# backup-server-setup, delete mode, state file). mode: dry-run|run.
docker_offvm_rsync() {
  require_sudo
  local mode="${1:-run}" src target ssh_cmd_str
  local -a rsync_cmd=()

  off_vm_backup_load_config
  validate_off_vm_backup_target "${OFF_VM_BACKUP_TARGET:-}" \
    || fail "Off-VM target not configured/invalid. Run: $(toolkit_cmd configure-rsync-backup-target)"
  target="$OFF_VM_BACKUP_TARGET"
  src="$(docker_offvm_source_dir)"
  $SUDO test -d "$src" || fail "No durable host backups at ${src}. Run $(toolkit_cmd backup) first."
  off_vm_backup_ensure_rsync

  ssh_cmd_str="$(off_vm_backup_ssh_command_string)"
  rsync_cmd=(rsync -az --human-readable --info=stats2 -e "$ssh_cmd_str")
  [[ "$mode" == "dry-run" ]] && rsync_cmd+=(--dry-run)
  [[ "${OFF_VM_BACKUP_RSYNC_DELETE:-false}" == "true" ]] && rsync_cmd+=(--delete)
  rsync_cmd+=("${src}/" "$target")

  ui_box_start "$([[ "$mode" == "dry-run" ]] && echo "Docker Off-VM Backup Dry Run" || echo "Docker Off-VM Backup")"
  status_line "Engine" "INFO" "Docker ($(docker_mode_label))"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "Source" "INFO" "${src}/ (durable host artifacts)"
  status_line "Target" "INFO" "$target"
  status_line "Delete mode" "INFO" "${OFF_VM_BACKUP_RSYNC_DELETE:-false}"
  echo
  if [[ "$mode" == "dry-run" ]]; then
    echo "Running rsync dry run. No files are copied or deleted."
  else
    echo "Ships durable host backup artifacts off this VM. Local backups are not removed."
    if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
      if ! confirm "Run off-VM rsync backup now?"; then
        warn "Off-VM backup cancelled."
        ui_box_end
        return 0
      fi
    fi
  fi

  echo
  log "Starting rsync ${mode}"
  # Artifacts are root-owned (0700), so rsync must run as root to read them.
  if ${SUDO:-} "${rsync_cmd[@]}"; then
    if [[ "$mode" == "dry-run" ]]; then
      status_line "Dry run" "OK" "rsync dry run completed"
    elif docker_offvm_remote_verify "$target"; then
      status_line "Remote verify" "OK" "SHA256SUMS verified at destination"
      off_vm_backup_write_state "OK" "rsync completed; remote checksums verified"
      status_line "Off-VM backup" "OK" "shipped and verified"
    else
      status_line "Remote verify" "WARN" "could not verify remote checksums (shipment completed)"
      off_vm_backup_write_state "OK" "rsync completed; remote verify unavailable"
      status_line "Off-VM backup" "OK" "shipped (verify destination manually)"
    fi
  else
    [[ "$mode" != "dry-run" ]] && off_vm_backup_write_state "FAIL" "rsync failed"
    status_line "Off-VM backup" "FAIL" "rsync command failed"
  fi
  ui_next "$(toolkit_cmd off-vm-backup-status)" "$(toolkit_cmd docker-object-backup)"
  ui_box_end
}

# Off-VM plan/status for the Docker engine (parity with the native screens, but
# reporting the durable host-artifact source instead of a bench backup folder).
docker_offvm_plan() {
  require_sudo
  off_vm_backup_load_config
  ui_box_start "Docker Off-VM Backup Plan"
  status_line "Mode" "INFO" "planning only; no files are copied"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "Host artifact source" "INFO" "$(docker_offvm_source_dir)/"
  status_line "Target" "$([[ -n "${OFF_VM_BACKUP_TARGET:-}" ]] && echo INFO || echo WARN)" "$(off_vm_backup_target_display)"
  status_line "Transport" "INFO" "rsync over SSH (destination checksum-verified)"
  status_line "Delete mode" "INFO" "${OFF_VM_BACKUP_RSYNC_DELETE:-false}"
  echo
  echo "Chain: container backup -> durable host artifact -> off-VM -> object storage."
  echo "  1) Take a durable host backup:      $(toolkit_cmd backup-files)"
  echo "  2) Configure the rsync target:      $(toolkit_cmd configure-rsync-backup-target)"
  echo "  3) Dry run, then real off-VM copy:  $(toolkit_cmd off-vm-backup-dry-run) / $(toolkit_cmd run-off-vm-backup)"
  echo "  4) Also push to object storage:     $(toolkit_cmd docker-object-config) then $(toolkit_cmd docker-object-backup)"
  ui_next "$(toolkit_cmd configure-rsync-backup-target)" "$(toolkit_cmd off-vm-backup-dry-run)" "$(toolkit_cmd docker-object-config)"
  ui_box_end
}

docker_offvm_status() {
  require_sudo
  local target_status target_detail last_status last_run last_detail src set_count
  off_vm_backup_load_config
  if off_vm_backup_configured; then
    target_status="OK"; target_detail="$OFF_VM_BACKUP_TARGET"
  else
    target_status="WARN"; target_detail="not configured"
  fi
  last_status="$(off_vm_backup_last_state LAST_STATUS 2>/dev/null || echo none)"
  last_run="$(off_vm_backup_last_state LAST_RUN_AT 2>/dev/null || echo never)"
  last_detail="$(off_vm_backup_last_state LAST_DETAIL 2>/dev/null || echo "no previous run")"
  src="$(docker_offvm_source_dir)"
  set_count=0
  if $SUDO test -d "$src"; then
    set_count="$($SUDO find "$src" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | awk '{print $1+0}')"
  fi

  ui_box_start "Docker Off-VM Backup Status"
  status_line "Engine" "INFO" "Docker ($(docker_mode_label))"
  status_line "Host artifact sets" "$([[ "$set_count" -gt 0 ]] && echo OK || echo WARN)" "${set_count} set(s) in ${src}"
  status_line "Target" "$target_status" "$target_detail"
  status_line "Config file" "$($SUDO test -f "$OFF_VM_BACKUP_CONFIG_FILE" && echo OK || echo WARN)" "$OFF_VM_BACKUP_CONFIG_FILE"
  case "$last_status" in
    OK) status_line "Last off-VM run" "OK" "${last_run}; ${last_detail}" ;;
    FAIL) status_line "Last off-VM run" "FAIL" "${last_run}; ${last_detail}" ;;
    *) status_line "Last off-VM run" "INFO" "${last_run}; ${last_detail}" ;;
  esac
  echo
  docker_object_backup_status_line
  echo
  echo "Off-site backup protects against VM/disk loss only when the destination is"
  echo "outside this VM and, ideally, this cloud account."
  ui_next "$(toolkit_cmd off-vm-backup-dry-run)" "$(toolkit_cmd run-off-vm-backup)" "$(toolkit_cmd docker-object-backup)"
  ui_box_end
}

# ---- Object storage (rclone) --------------------------------------------------
docker_object_backup_load_config() {
  local v
  if [[ -z "${DOCKER_OBJECT_RCLONE_REMOTE:-}" ]]; then
    v="$(docker_env_value "$DOCKER_OBJECT_BACKUP_CONFIG_FILE" DOCKER_OBJECT_RCLONE_REMOTE)"; [[ -n "$v" ]] && DOCKER_OBJECT_RCLONE_REMOTE="$v"
  fi
  if [[ -z "${DOCKER_OBJECT_BUCKET:-}" ]]; then
    v="$(docker_env_value "$DOCKER_OBJECT_BACKUP_CONFIG_FILE" DOCKER_OBJECT_BUCKET)"; [[ -n "$v" ]] && DOCKER_OBJECT_BUCKET="$v"
  fi
  if [[ -z "${DOCKER_OBJECT_PREFIX:-}" ]]; then
    v="$(docker_env_value "$DOCKER_OBJECT_BACKUP_CONFIG_FILE" DOCKER_OBJECT_PREFIX)"; [[ -n "$v" ]] && DOCKER_OBJECT_PREFIX="$v"
  fi
}

docker_object_backup_configured() {
  docker_object_backup_load_config
  [[ -n "${DOCKER_OBJECT_RCLONE_REMOTE:-}" && -n "${DOCKER_OBJECT_BUCKET:-}" ]]
}

# Full rclone destination: <remote>:<bucket>/<prefix>/<site>.
docker_object_dest() {
  docker_object_backup_load_config
  local prefix="${DOCKER_OBJECT_PREFIX:-}"
  prefix="${prefix#/}"; prefix="${prefix%/}"
  if [[ -n "$prefix" ]]; then
    printf '%s:%s/%s/%s\n' "$DOCKER_OBJECT_RCLONE_REMOTE" "$DOCKER_OBJECT_BUCKET" "$prefix" "$(docker_site_name)"
  else
    printf '%s:%s/%s\n' "$DOCKER_OBJECT_RCLONE_REMOTE" "$DOCKER_OBJECT_BUCKET" "$(docker_site_name)"
  fi
}

docker_object_ensure_rclone() {
  command -v rclone >/dev/null 2>&1 && return 0
  log "Installing rclone"
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -y >/dev/null 2>&1 || true
  $SUDO apt-get install -y rclone >/dev/null 2>&1 || return 1
  command -v rclone >/dev/null 2>&1
}

docker_object_backup_write_state() {
  require_sudo
  local status="$1" detail="$2" now
  now="$(date -Is 2>/dev/null || date)"
  $SUDO mkdir -p "$(dirname "$DOCKER_OBJECT_BACKUP_STATE_FILE")"
  $SUDO tee "$DOCKER_OBJECT_BACKUP_STATE_FILE" >/dev/null <<EOF_DOCKER_OBJ_STATE
LAST_RUN_AT=${now}
LAST_STATUS=${status}
LAST_DETAIL=${detail}
LAST_DEST=$(docker_object_dest 2>/dev/null || echo unknown)
SITE_NAME=$(docker_site_name)
EOF_DOCKER_OBJ_STATE
  $SUDO chown root:root "$DOCKER_OBJECT_BACKUP_STATE_FILE" 2>/dev/null || true
  $SUDO chmod 600 "$DOCKER_OBJECT_BACKUP_STATE_FILE" 2>/dev/null || true
}

# One-line object-storage summary used inside docker_offvm_status.
docker_object_backup_status_line() {
  local last_status last_run
  if docker_object_backup_configured; then
    last_status="$(docker_env_value "$DOCKER_OBJECT_BACKUP_STATE_FILE" LAST_STATUS)"
    last_run="$(docker_env_value "$DOCKER_OBJECT_BACKUP_STATE_FILE" LAST_RUN_AT)"
    case "${last_status:-none}" in
      OK) status_line "Object storage" "OK" "$(docker_object_dest); last OK ${last_run:-?}" ;;
      FAIL) status_line "Object storage" "WARN" "$(docker_object_dest); last run FAILED ${last_run:-?}" ;;
      *) status_line "Object storage" "INFO" "$(docker_object_dest); no successful run yet" ;;
    esac
  else
    status_line "Object storage" "WARN" "not configured; run $(toolkit_cmd docker-object-config)"
  fi
}

configure_docker_object_backup() {
  require_sudo
  local remote bucket prefix
  docker_object_backup_load_config

  if ! docker_object_ensure_rclone; then
    fail "rclone is required for object-storage backups but could not be installed. Install rclone, then retry."
  fi

  ui_box_start "Configure Object-Storage Backup (rclone)"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "Tool" "INFO" "rclone $(rclone version 2>/dev/null | awk 'NR==1{print $2}')"
  echo
  echo "Uses an existing rclone remote. Create one first with:  rclone config"
  echo "(supports S3, Cloudflare R2, Backblaze B2, GCS, Azure, MinIO, and more)."
  echo
  echo "Configured rclone remotes:"
  rclone listremotes 2>/dev/null | sed 's/^/  /' || echo "  (none — run 'rclone config' first)"
  echo

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    read -r -p "rclone remote name (e.g. r2): " remote
    remote="${remote%:}"
    read -r -p "Bucket / container name: " bucket
    read -r -p "Path prefix inside the bucket [erpnext-backups]: " prefix
    prefix="${prefix:-erpnext-backups}"
  else
    remote="${DOCKER_OBJECT_RCLONE_REMOTE:-}"
    bucket="${DOCKER_OBJECT_BUCKET:-}"
    prefix="${DOCKER_OBJECT_PREFIX:-erpnext-backups}"
    [[ -n "$remote" && -n "$bucket" ]] || fail "Set DOCKER_OBJECT_RCLONE_REMOTE and DOCKER_OBJECT_BUCKET before using --yes."
  fi

  [[ -n "$remote" && -n "$bucket" ]] || fail "Remote name and bucket are required."
  if ! rclone listremotes 2>/dev/null | grep -qx "${remote}:"; then
    warn "rclone remote '${remote}:' is not in 'rclone listremotes'. Save anyway; create it with 'rclone config'."
  fi

  $SUDO mkdir -p "$(dirname "$DOCKER_OBJECT_BACKUP_CONFIG_FILE")"
  $SUDO tee "$DOCKER_OBJECT_BACKUP_CONFIG_FILE" >/dev/null <<EOF_DOCKER_OBJ_CONFIG
# ERPNext Developer Toolkit - Docker object-storage backup (rclone) configuration
# Non-secret only. rclone credentials live in the rclone config (rclone config).
DOCKER_OBJECT_RCLONE_REMOTE=${remote}
DOCKER_OBJECT_BUCKET=${bucket}
DOCKER_OBJECT_PREFIX=${prefix}
SITE_NAME=$(docker_site_name)
EOF_DOCKER_OBJ_CONFIG
  $SUDO chown root:root "$DOCKER_OBJECT_BACKUP_CONFIG_FILE" 2>/dev/null || true
  $SUDO chmod 600 "$DOCKER_OBJECT_BACKUP_CONFIG_FILE" 2>/dev/null || true
  DOCKER_OBJECT_RCLONE_REMOTE="$remote"
  DOCKER_OBJECT_BUCKET="$bucket"
  DOCKER_OBJECT_PREFIX="$prefix"

  ui_box_start "Object-Storage Backup Configured"
  status_line "Destination" "OK" "$(docker_object_dest)"
  status_line "Config file" "OK" "$DOCKER_OBJECT_BACKUP_CONFIG_FILE"
  ui_next "$(toolkit_cmd docker-object-backup-dry-run)" "$(toolkit_cmd docker-object-backup)"
  ui_box_end
}

# Upload durable host artifacts to object storage with rclone. mode: dry-run|run.
# Uploads are checksum-based (rclone --checksum) and verified with rclone check.
run_docker_object_backup() {
  require_sudo
  local mode="${1:-run}" src dest
  local -a rclone_cmd=()

  docker_object_backup_load_config
  docker_object_backup_configured || fail "Object storage not configured. Run: $(toolkit_cmd docker-object-config)"
  docker_object_ensure_rclone || fail "rclone is not available. Install rclone, then retry."
  src="$(docker_offvm_source_dir)"
  $SUDO test -d "$src" || fail "No durable host backups at ${src}. Run $(toolkit_cmd backup) first."
  dest="$(docker_object_dest)"

  ui_box_start "$([[ "$mode" == "dry-run" ]] && echo "Object-Storage Backup Dry Run" || echo "Object-Storage Backup")"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "Source" "INFO" "${src}/ (durable host artifacts)"
  status_line "Destination" "INFO" "$dest"
  echo

  rclone_cmd=(rclone copy "$src" "$dest" --checksum --transfers 4 --stats-one-line)
  [[ "$mode" == "dry-run" ]] && rclone_cmd+=(--dry-run)

  if [[ "$mode" != "dry-run" && -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    if ! confirm "Upload durable host backups to ${dest} now?"; then
      warn "Object-storage backup cancelled."
      ui_box_end
      return 0
    fi
  fi

  log "Starting rclone ${mode}"
  if ${SUDO:-} "${rclone_cmd[@]}"; then
    if [[ "$mode" == "dry-run" ]]; then
      status_line "Dry run" "OK" "rclone dry run completed"
    elif ${SUDO:-} rclone check "$src" "$dest" --one-way --checksum >/dev/null 2>&1; then
      status_line "Remote verify" "OK" "rclone check confirmed all files present"
      docker_object_backup_write_state "OK" "rclone copy + check verified"
      status_line "Object storage" "OK" "uploaded and verified"
    else
      status_line "Remote verify" "WARN" "rclone check reported differences"
      docker_object_backup_write_state "OK" "rclone copy completed; check reported differences"
      status_line "Object storage" "WARN" "uploaded (verify manually with rclone check)"
    fi
  else
    [[ "$mode" != "dry-run" ]] && docker_object_backup_write_state "FAIL" "rclone copy failed"
    status_line "Object storage" "FAIL" "rclone command failed"
  fi
  ui_next "$(toolkit_cmd docker-object-status)" "$(toolkit_cmd off-vm-backup-status)"
  ui_box_end
}

show_docker_object_backup_status() {
  require_sudo
  docker_object_backup_load_config
  ui_box_start "Object-Storage Backup Status"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "rclone" "$(command -v rclone >/dev/null 2>&1 && echo OK || echo WARN)" "$(command -v rclone >/dev/null 2>&1 && rclone version 2>/dev/null | awk 'NR==1{print $2}' || echo 'not installed')"
  status_line "Config file" "$($SUDO test -f "$DOCKER_OBJECT_BACKUP_CONFIG_FILE" && echo OK || echo WARN)" "$DOCKER_OBJECT_BACKUP_CONFIG_FILE"
  if docker_object_backup_configured; then
    status_line "Destination" "OK" "$(docker_object_dest)"
  else
    status_line "Destination" "WARN" "not configured"
  fi
  docker_object_backup_status_line
  ui_next "$(toolkit_cmd docker-object-backup-dry-run)" "$(toolkit_cmd docker-object-backup)"
  ui_box_end
}

# ------------------------------------------------------------
# Production HTTPS / reverse proxy (P5): Traefik in front of the frontend
# ------------------------------------------------------------
docker_prod_https_cf_override_file() { printf '%s/erpnext-dev.prod.https.cloudflare.yml\n' "$DOCKER_WORKDIR"; }
docker_prod_https_cf_dynamic_file() { printf '%s/erpnext-dev.prod.traefik-dynamic.yml\n' "$DOCKER_WORKDIR"; }
docker_cf_origin_cert_path() { printf '%s/origin.crt\n' "$DOCKER_CF_ORIGIN_DIR"; }
docker_cf_origin_key_path() { printf '%s/origin.key\n' "$DOCKER_CF_ORIGIN_DIR"; }

# Resolved HTTPS mode (env override wins, else the persisted state, else http).
docker_https_mode() {
  local m="${DOCKER_HTTPS_MODE:-}"
  [[ -n "$m" ]] || m="$(docker_env_value "$DOCKER_HTTPS_STATE_FILE" DOCKER_HTTPS_MODE)"
  case "$(printf '%s' "${m:-http}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    letsencrypt|le|lets-encrypt|acme) printf 'letsencrypt\n' ;;
    cloudflare-origin|cloudflare|cf|origin) printf 'cloudflare-origin\n' ;;
    *) printf 'http\n' ;;
  esac
}
docker_https_enabled() { [[ "$(docker_https_mode)" != "http" ]]; }

# Traefik Host(...) router rule for the configured production site.
docker_https_sites_rule() {
  local domain
  domain="$(docker_public_domain)"
  printf 'Host(`%s`)\n' "$domain"
}

docker_https_write_state() {
  require_sudo
  local mode="$1" domain="$2" email="$3"
  $SUDO mkdir -p "$DOCKER_WORKDIR"
  $SUDO tee "$DOCKER_HTTPS_STATE_FILE" >/dev/null <<EOF_DOCKER_HTTPS_STATE
# ERPNext Developer Toolkit - Docker production HTTPS state
DOCKER_HTTPS_MODE=${mode}
DOCKER_HTTPS_DOMAIN=${domain}
DOCKER_HTTPS_EMAIL=${email}
DOCKER_HTTPS_UPDATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF_DOCKER_HTTPS_STATE
  $SUDO chown root:root "$DOCKER_HTTPS_STATE_FILE" 2>/dev/null || true
  $SUDO chmod 600 "$DOCKER_HTTPS_STATE_FILE" 2>/dev/null || true
}

# Record the default (http) state on first production setup so the mode is
# explicit and surfaced everywhere; never clobbers an existing state.
docker_write_https_state_if_absent() {
  $SUDO test -f "$DOCKER_HTTPS_STATE_FILE" && return 0
  docker_https_write_state http "$(docker_public_domain)" ""
}

# Set (update or append) a KEY=value in the production env file without touching
# the other (secret) values. Avoids sed so backticks in values are never
# re-evaluated by the shell.
docker_prod_env_set() {
  require_sudo
  local key="$1" val="$2" envf tmp
  envf="$(docker_prod_env_file)"
  $SUDO test -f "$envf" || fail "Production env file not found: ${envf}. Run $(toolkit_cmd docker-production-setup) first."
  tmp="$(mktemp)" || return 1
  $SUDO grep -v "^${key}=" "$envf" 2>/dev/null > "$tmp" || true
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  $SUDO cp "$tmp" "$envf"
  rm -f "$tmp"
  $SUDO chown root:root "$envf" 2>/dev/null || true
  $SUDO chmod 600 "$envf" 2>/dev/null || true
}

# Sanity checks before switching a production stack to HTTPS.
docker_https_preflight() {
  local domain="$1" mode="$2" issues=0
  ui_box_start "Docker HTTPS Preflight"
  status_line "Mode" "INFO" "$mode"
  status_line "Domain" "INFO" "$domain"

  if ! docker_is_production; then
    status_line "Engine mode" "FAIL" "HTTPS applies to the production stack; run $(toolkit_cmd docker-production-setup)"
    issues=$((issues+1))
  fi

  case "$domain" in
    *.*)
      case "$domain" in
        *.test|*.localhost|*.local|localhost)
          status_line "Domain" "WARN" "${domain} is not a public FQDN; Let's Encrypt will fail for it"
          [[ "$mode" == "letsencrypt" ]] && issues=$((issues+1)) ;;
        *) status_line "Public FQDN" "OK" "$domain" ;;
      esac ;;
    *)
      status_line "Domain" "WARN" "${domain} has no dot; not a valid public domain"
      [[ "$mode" == "letsencrypt" ]] && issues=$((issues+1)) ;;
  esac

  local p
  for p in 80 443; do
    if docker_port_available "$p"; then
      status_line "Host port ${p}" "OK" "free to publish"
    else
      # The running noproxy stack may already hold 80/443 if HTTPS was on; that
      # is fine. Only warn so a genuinely conflicting service is visible.
      status_line "Host port ${p}" "WARN" "in use (ok if it is this stack's proxy)"
    fi
  done

  if [[ "$mode" == "letsencrypt" ]]; then
    local pub
    pub="$(detect_outbound_public_ipv4 2>/dev/null || true)"
    status_line "Outbound public IP" "INFO" "${pub:-unknown} (point ${domain} A/AAAA here)"
    echo
    echo "Let's Encrypt HTTP-01 requires ${domain} to resolve to THIS host and ports"
    echo "80/443 reachable from the internet. Cloud/provider firewalls must allow them."
  fi
  ui_box_end
  [[ "$issues" -eq 0 ]]
}

# Toolkit-generated Traefik override for Cloudflare Origin CA: Traefik terminates
# TLS with the operator-provided origin certificate (no ACME) and redirects HTTP
# to HTTPS. Cloudflare proxies the public domain and trusts this origin cert.
docker_write_prod_https_cf_override() {
  require_sudo
  local f dyn cert key
  f="$(docker_prod_https_cf_override_file)"
  dyn="$(docker_prod_https_cf_dynamic_file)"
  cert="$(docker_cf_origin_cert_path)"
  key="$(docker_cf_origin_key_path)"

  $SUDO mkdir -p "$DOCKER_WORKDIR"
  $SUDO tee "$dyn" >/dev/null <<'EOF_DOCKER_TRAEFIK_DYNAMIC'
tls:
  certificates:
    - certFile: /etc/traefik/certs/origin.crt
      keyFile: /etc/traefik/certs/origin.key
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/certs/origin.crt
        keyFile: /etc/traefik/certs/origin.key
EOF_DOCKER_TRAEFIK_DYNAMIC
  $SUDO chmod 644 "$dyn" 2>/dev/null || true

  # Unquoted heredoc: host paths (${cert}/${key}/${dyn}) expand now; compose
  # interpolation tokens are escaped so they stay literal for `docker compose`.
  $SUDO tee "$f" >/dev/null <<EOF_DOCKER_CF_OVERRIDE
services:
  frontend:
    labels:
      - traefik.enable=true
      - traefik.http.services.frontend.loadbalancer.server.port=8080
      - traefik.http.routers.frontend-http.entrypoints=websecure
      - traefik.http.routers.frontend-http.tls=true
      - "traefik.http.routers.frontend-http.rule=\${SITES_RULE:?SITES_RULE not set}"
  proxy:
    image: traefik:v3.6
    restart: unless-stopped
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.file.filename=/etc/traefik/dynamic.yml
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.scheme=https
      - --entrypoints.websecure.address=:443
    ports:
      - \${HTTP_PUBLISH_PORT:-80}:80
      - \${HTTPS_PUBLISH_PORT:-443}:443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${cert}:/etc/traefik/certs/origin.crt:ro
      - ${key}:/etc/traefik/certs/origin.key:ro
      - ${dyn}:/etc/traefik/dynamic.yml:ro
EOF_DOCKER_CF_OVERRIDE
  $SUDO chown root:root "$f" 2>/dev/null || true
  $SUDO chmod 644 "$f" 2>/dev/null || true
}

# Install the Cloudflare Origin CA certificate + private key. Reads from
# CF_ORIGIN_CERT/CF_ORIGIN_KEY paths (default /tmp/cloudflare-origin.{crt,key}),
# or interactively pastes PEM blocks. Validated as a matching pair.
docker_install_cloudflare_origin_material() {
  require_sudo
  local cert_src="${CF_ORIGIN_CERT:-/tmp/cloudflare-origin.crt}"
  local key_src="${CF_ORIGIN_KEY:-/tmp/cloudflare-origin.key}"
  local cert_dst key_dst
  cert_dst="$(docker_cf_origin_cert_path)"
  key_dst="$(docker_cf_origin_key_path)"

  $SUDO mkdir -p "$DOCKER_CF_ORIGIN_DIR"
  $SUDO chmod 700 "$DOCKER_CF_ORIGIN_DIR" 2>/dev/null || true

  if $SUDO test -r "$cert_src" && $SUDO test -r "$key_src"; then
    log "Installing Cloudflare Origin certificate from ${cert_src} / ${key_src}"
    $SUDO cp "$cert_src" "$cert_dst"
    $SUDO cp "$key_src" "$key_dst"
  elif [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    read_pem_block_to_file "Cloudflare Origin certificate" \
      "BEGIN CERTIFICATE" "END CERTIFICATE" "$cert_dst" \
      "-----BEGIN CERTIFICATE-----" "-----END CERTIFICATE-----"
    read_pem_block_to_file "Cloudflare Origin private key" \
      "BEGIN( RSA| EC| PRIVATE)? PRIVATE KEY" "END( RSA| EC| PRIVATE)? PRIVATE KEY" "$key_dst" \
      "-----BEGIN PRIVATE KEY-----" "-----END PRIVATE KEY-----"
  else
    fail "Cloudflare Origin cert/key not found. Place PEM at ${cert_src} and ${key_src}, or set CF_ORIGIN_CERT/CF_ORIGIN_KEY."
  fi

  if ! validate_certificate_and_key_pair "$cert_dst" "$key_dst"; then
    $SUDO rm -f "$cert_dst" "$key_dst"
    fail "Certificate and key do not match, or are not valid PEM. Nothing was installed."
  fi
  $SUDO chown root:root "$cert_dst" "$key_dst" 2>/dev/null || true
  $SUDO chmod 644 "$cert_dst" 2>/dev/null || true
  $SUDO chmod 600 "$key_dst" 2>/dev/null || true
  ok "Cloudflare Origin certificate installed and validated."
}

# Bring the stack up with the current (this-process) HTTPS mode applied.
docker_https_apply() {
  require_sudo
  # Recreate so the proxy service is added and stale proxies (from a previous
  # mode) are removed as orphans.
  docker_compose up -d --remove-orphans
}

docker_enable_letsencrypt() {
  require_sudo
  docker_is_production || fail "Production Let's Encrypt requires the Docker production stack. Run $(toolkit_cmd docker-https-wizard) to promote this installation safely."
  local domain email
  domain="$(docker_public_domain)"
  email="${LETSENCRYPT_EMAIL:-$(docker_env_value "$DOCKER_HTTPS_STATE_FILE" DOCKER_HTTPS_EMAIL)}"
  if [[ -z "$email" && -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    read -r -p "Let's Encrypt contact email: " email
  fi
  [[ -n "$email" ]] || fail "A contact email is required for Let's Encrypt. Set LETSENCRYPT_EMAIL or run interactively."

  docker_https_preflight "$domain" letsencrypt || fail "HTTPS preflight failed. Resolve the issues above and retry."

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    confirm "Switch ${domain} to Traefik + Let's Encrypt HTTPS on ports 80/443 now?" || { warn "Cancelled."; return 0; }
  fi

  docker_prod_env_set SITES_RULE "$(docker_https_sites_rule)"
  docker_prod_env_set LETSENCRYPT_EMAIL "$email"
  docker_prod_env_set HTTP_PUBLISH_PORT 80
  docker_prod_env_set HTTPS_PUBLISH_PORT 443
  docker_https_write_state letsencrypt "$domain" "$email"
  DOCKER_HTTPS_MODE="letsencrypt"

  log "Applying Let's Encrypt HTTPS (Traefik will request a certificate for ${domain})"
  docker_https_apply || fail "docker compose up failed. Inspect with: $(toolkit_cmd logs)"
  ok "HTTPS (Let's Encrypt) applied. Certificate issuance can take a short time."
  docker_https_status
}

docker_configure_cloudflare_origin() {
  require_sudo
  docker_is_production || fail "Cloudflare Origin HTTPS requires the Docker production stack. Run $(toolkit_cmd docker-https-wizard) to promote this installation safely."
  local domain
  domain="$(docker_public_domain)"

  docker_install_cloudflare_origin_material
  docker_write_prod_https_cf_override
  docker_https_preflight "$domain" cloudflare-origin || warn "Preflight reported warnings; continuing (Cloudflare fronts the public domain)."

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    confirm "Switch ${domain} to Traefik + Cloudflare Origin CA HTTPS on ports 80/443 now?" || { warn "Cancelled."; return 0; }
  fi

  docker_prod_env_set SITES_RULE "$(docker_https_sites_rule)"
  docker_prod_env_set HTTP_PUBLISH_PORT 80
  docker_prod_env_set HTTPS_PUBLISH_PORT 443
  docker_https_write_state cloudflare-origin "$domain" ""
  DOCKER_HTTPS_MODE="cloudflare-origin"

  log "Applying Cloudflare Origin CA HTTPS"
  docker_https_apply || fail "docker compose up failed. Inspect with: $(toolkit_cmd logs)"
  ok "HTTPS (Cloudflare Origin CA) applied."
  echo "Set the Cloudflare SSL/TLS mode for ${domain} to 'Full (strict)' and proxy the DNS record."
  docker_https_status
}

# Revert to loopback-only HTTP on the host (removes the Traefik proxy).
docker_https_rollback() {
  require_sudo
  docker_is_production || fail "Production HTTPS rollback applies only to the Docker production stack."
  local domain
  domain="$(docker_public_domain)"
  if [[ "$(docker_https_mode)" == "http" ]]; then
    warn "HTTPS is already disabled (mode: http)."
  fi
  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    confirm "Roll back to loopback-only HTTP on 127.0.0.1:${DOCKER_PUBLISH_PORT} and remove the Traefik proxy?" || { warn "Cancelled."; return 0; }
  fi
  docker_prod_env_set HTTP_PUBLISH_PORT "127.0.0.1:${DOCKER_PUBLISH_PORT}"
  docker_https_write_state http "$domain" ""
  DOCKER_HTTPS_MODE="http"
  log "Rolling back to HTTP (noproxy)"
  docker_https_apply || fail "docker compose up failed. Inspect with: $(toolkit_cmd logs)"
  ok "Rolled back to loopback-only HTTP on 127.0.0.1:${DOCKER_PUBLISH_PORT}."
  docker_https_status
}

docker_https_status() {
  require_sudo
  if ! docker_is_production; then
    ui_box_start "Docker Local HTTPS Status"
    status_line "Engine mode" "INFO" "Docker development"
    status_line "Direct HTTP" "INFO" "$(docker_direct_http_url localhost)"
    if declare -F local_ssl_is_configured >/dev/null 2>&1 && local_ssl_is_configured; then
      status_line "Friendly HTTPS" "OK" "https://$(docker_site_name)"
      echo "Local Docker HTTPS is terminated by host Nginx and proxies to port ${DOCKER_PUBLISH_PORT}."
    else
      status_line "Friendly HTTPS" "WARN" "not configured"
      echo "Configure trusted local HTTPS with: $(toolkit_cmd local-ssl-wizard)"
    fi
    ui_box_end
    return 0
  fi

  local mode domain email proxy_state cert_line issuer dates redirect
  mode="$(docker_https_mode)"
  domain="$(docker_env_value "$DOCKER_HTTPS_STATE_FILE" DOCKER_HTTPS_DOMAIN)"
  [[ -n "$domain" ]] || domain="$(docker_public_domain)"
  email="$(docker_env_value "$DOCKER_HTTPS_STATE_FILE" DOCKER_HTTPS_EMAIL)"

  ui_box_start "Docker Production HTTPS Status"
  status_line "Engine mode" "OK" "Docker production"
  case "$mode" in
    letsencrypt) status_line "HTTPS mode" "OK" "Traefik + Let's Encrypt" ;;
    cloudflare-origin) status_line "HTTPS mode" "OK" "Traefik + Cloudflare Origin CA" ;;
    *) status_line "HTTPS mode" "WARN" "disabled (loopback HTTP on 127.0.0.1:${DOCKER_PUBLISH_PORT})" ;;
  esac
  status_line "Public domain" "INFO" "$domain"
  status_line "Internal site" "INFO" "$(docker_site_name)"
  [[ "$mode" == "letsencrypt" && -n "$email" ]] && status_line "ACME email" "INFO" "$email"

  if [[ "$mode" == "http" ]]; then
    echo
    echo "Enable HTTPS with: $(toolkit_cmd docker-https-wizard)"
    ui_box_end
    return 0
  fi

  proxy_state="$(docker_compose ps -q proxy 2>/dev/null | tail -n1)"
  if [[ -n "$proxy_state" ]]; then
    proxy_state="$(${SUDO:-} docker inspect -f '{{.State.Status}}' "$proxy_state" 2>/dev/null || echo unknown)"
    status_line "Traefik proxy" "$([[ "$proxy_state" == running ]] && echo OK || echo WARN)" "$proxy_state"
  else
    status_line "Traefik proxy" "WARN" "not running (try: $(toolkit_cmd start))"
  fi

  if command -v openssl >/dev/null 2>&1; then
    cert_line="$(echo | ${SUDO:-} openssl s_client -connect 127.0.0.1:443 -servername "$domain" 2>/dev/null | openssl x509 -noout -issuer -dates 2>/dev/null || true)"
    if [[ -n "$cert_line" ]]; then
      issuer="$(printf '%s\n' "$cert_line" | sed -n 's/^issuer=//p')"
      dates="$(printf '%s\n' "$cert_line" | grep -E '^(notBefore|notAfter)=' | tr '\n' ' ')"
      status_line "Certificate issuer" "OK" "${issuer:-unknown}"
      status_line "Certificate validity" "INFO" "${dates:-unknown}"
    else
      status_line "Certificate" "WARN" "no TLS answer on 127.0.0.1:443 yet"
    fi
  fi

  redirect="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 -H "Host: ${domain}" "http://127.0.0.1:80/" 2>/dev/null || true)"
  case "$redirect" in
    30[0-9]) status_line "HTTP->HTTPS redirect" "OK" "HTTP ${redirect}" ;;
    "") status_line "HTTP->HTTPS redirect" "WARN" "no response on port 80" ;;
    *) status_line "HTTP->HTTPS redirect" "WARN" "HTTP ${redirect} (expected 3xx redirect)" ;;
  esac

  echo
  echo "Public URL: https://${domain}"
  ui_next "$(toolkit_cmd docker-production-exposure)" "$(toolkit_cmd docker-https-rollback)"
  ui_box_end
}

# Promote an existing quick/dev Docker installation to the durable production
# Compose layout without changing the project name or persistent volumes.
docker_promote_to_production() {
  require_sudo
  docker_is_production && return 0

  local domain
  domain="$(docker_public_domain)"
  [[ -n "${PRODUCTION_DOMAIN:-}" ]] || fail "Set a real production domain first: $(toolkit_cmd set-domain)"
  validate_production_domain_value "$domain" >/dev/null 2>&1 || fail "Invalid production domain: ${domain}"

  ui_box_start "Promote Docker Stack to Production"
  status_line "Current stack" "INFO" "Docker development / pwd.yml"
  status_line "Target stack" "INFO" "Docker production / compose.yaml"
  status_line "Internal site" "INFO" "$(docker_site_name)"
  status_line "Public domain" "INFO" "$domain"
  echo "The Compose project and persistent volumes are retained."
  echo "A durable backup is attempted before the stack is recreated."
  ui_box_end

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    confirm "Promote this Docker installation to the production stack now?" || return 1
  fi

  docker_backup true || warn "Pre-promotion backup did not complete; the current stack remains unchanged until recreation begins."

  DOCKER_MODE="production"
  DOCKER_MODE_ENV_PROVIDED=1
  DEPLOYMENT_ENGINE="docker"
  DEPLOYMENT_ENGINE_ENV_PROVIDED=1
  DEPLOYMENT_MODE="public-vm"
  SITE_NAME="$(docker_site_name)"

  # Re-check the pinned upstream checkout in production mode so all required
  # compose.yaml overrides exist before switching the running project.
  docker_provision_workdir
  docker_write_prod_env
  docker_write_prod_image_override
  docker_write_https_state_if_absent
  write_dev_config_file

  log "Recreating the Docker project with the production Compose layout"
  docker_compose up -d --remove-orphans || fail "Production compose startup failed. The pre-promotion backup remains under ${DOCKER_BACKUP_DIR}."
  docker_prod_create_site || fail "The production stack started but site verification/creation failed. Inspect: $(toolkit_cmd logs)"
  docker_ready || warn "Production stack is running but readiness has not passed yet."
  docker_write_pins || warn "Could not refresh immutable pin metadata."
  ok "Docker stack promoted to production mode."
}

docker_https_wizard() {
  require_sudo

  if ! docker_is_production && ! is_public_vm_workflow; then
    ui_box_start "Docker Local HTTPS"
    status_line "Direct HTTP" "OK" "$(docker_direct_http_url localhost)"
    status_line "Friendly domain" "INFO" "$(docker_site_name)"
    echo "Local Docker HTTPS uses the same trusted local SSL workflow as native installs."
    echo "Nginx proxies https://$(docker_site_name) to Docker port ${DOCKER_PUBLISH_PORT}."
    ui_box_end
    run_local_ssl_wizard main
    return
  fi

  if ! docker_is_production; then
    docker_promote_to_production || return 1
  fi

  local choice
  ui_box_start "Docker Production HTTPS"
  status_line "Public domain" "INFO" "$(docker_public_domain)"
  status_line "Internal site" "INFO" "$(docker_site_name)"
  status_line "Current mode" "INFO" "$(docker_https_mode)"
  echo "Choose how the production stack terminates TLS with Traefik:"
  echo "  1) Let's Encrypt (automatic; public DNS and ports 80/443 must reach this host)"
  echo "  2) Cloudflare Origin CA (provide origin certificate; Cloudflare proxies DNS)"
  echo "  3) Disable HTTPS (roll back to loopback-only HTTP on 127.0.0.1:${DOCKER_PUBLISH_PORT})"
  echo "  b) Back"
  ui_box_end
  if [[ ! -t 0 || "${ASSUME_YES:-0}" -eq 1 ]]; then
    echo "Non-interactive: use $(toolkit_cmd docker-enable-letsencrypt), $(toolkit_cmd docker-configure-cloudflare-origin), or $(toolkit_cmd docker-https-rollback)."
    return 0
  fi
  read -r -p "Select [b]: " choice
  case "$choice" in
    1) docker_enable_letsencrypt ;;
    2) docker_configure_cloudflare_origin ;;
    3) docker_https_rollback ;;
    b|B|"") return 0 ;;
    q|Q) exit 0 ;;
    *) warn "Invalid option" ;;
  esac
}

# Validate that only the intended web ports are published to the host, and that
# backend/data ports are NOT publicly exposed. A production-exposure guardrail.
docker_production_exposure() {
  require_sudo
  local ports_raw problems=0 public_ports all_bindings p bad="" pp

  ui_box_start "Docker Production Exposure Check"
  status_line "Engine mode" "$(docker_is_production && echo OK || echo WARN)" "Docker $(docker_mode_label)"
  status_line "HTTPS mode" "$([[ "$(docker_https_mode)" != http ]] && echo OK || echo INFO)" "$(docker_https_mode)"

  ports_raw="$(${SUDO:-} docker ps --filter "label=com.docker.compose.project=${DOCKER_PROJECT_NAME}" --format '{{.Names}} {{.Ports}}' 2>/dev/null || true)"
  if [[ -z "$ports_raw" ]]; then
    status_line "Published ports" "WARN" "no running containers for project ${DOCKER_PROJECT_NAME}"
    ui_box_end
    return 1
  fi

  all_bindings="$(printf '%s\n' "$ports_raw" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+|\[::\]:[0-9]+|:::[0-9]+' | sort -u | tr '\n' ' ' || true)"
  public_ports="$(printf '%s\n' "$ports_raw" | grep -oE '0\.0\.0\.0:[0-9]+|\[::\]:[0-9]+|:::[0-9]+' | grep -oE '[0-9]+$' | sort -un | tr '\n' ' ' || true)"
  status_line "Host bindings" "INFO" "${all_bindings:-none}"
  status_line "Public host ports" "INFO" "${public_ports:-none}"

  for p in 3306 5432 6379 8000 9000 11000 12000 13000; do
    if printf ' %s ' "$public_ports" | grep -q " ${p} "; then
      bad="${bad}${p} "
      problems=$((problems + 1))
    fi
  done
  if [[ -n "$bad" ]]; then
    status_line "Backend/data ports" "FAIL" "publicly published: ${bad}(must be internal only)"
  else
    status_line "Backend/data ports" "OK" "container-internal only"
  fi

  if docker_https_enabled; then
    for pp in 80 443; do
      if printf ' %s ' "$public_ports" | grep -q " ${pp} "; then
        status_line "Web port ${pp}" "OK" "published by Traefik"
      else
        status_line "Web port ${pp}" "WARN" "not publicly published (proxy may be down)"
        problems=$((problems + 1))
      fi
    done
    if printf ' %s ' "$public_ports" | grep -q " ${DOCKER_PUBLISH_PORT} "; then
      status_line "Direct Docker port" "FAIL" "${DOCKER_PUBLISH_PORT} is still publicly published after HTTPS"
      problems=$((problems + 1))
    else
      status_line "Direct Docker port" "OK" "${DOCKER_PUBLISH_PORT} is not publicly published after HTTPS"
    fi
  else
    if printf '%s\n' "$ports_raw" | grep -qE "127\\.0\\.0\\.1:${DOCKER_PUBLISH_PORT}->8080|127\\.0\\.0\\.1:${DOCKER_PUBLISH_PORT}-[0-9]+->8080"; then
      status_line "Temporary HTTP" "OK" "127.0.0.1:${DOCKER_PUBLISH_PORT} only; not public"
    elif printf ' %s ' "$public_ports" | grep -q " ${DOCKER_PUBLISH_PORT} "; then
      status_line "Temporary HTTP" "FAIL" "${DOCKER_PUBLISH_PORT} is publicly published before HTTPS"
      problems=$((problems + 1))
    else
      status_line "Temporary HTTP" "WARN" "loopback binding not detected"
      problems=$((problems + 1))
    fi
    status_line "HTTPS" "INFO" "not enabled yet; run $(toolkit_cmd docker-https-wizard)"
  fi

  ui_box_end
  [[ "$problems" -eq 0 ]]
}

# ------------------------------------------------------------
# Durable custom-app images (P4)
# ------------------------------------------------------------
# Frappe base/build image branch, derived from the pinned ERPNext image tag
# (v16.x -> version-16); overridable via FRAPPE_BRANCH.
docker_frappe_branch() {
  local override="${FRAPPE_BRANCH:-}"
  [[ -n "$override" ]] && { printf '%s\n' "$override"; return 0; }
  local tag major
  tag="$(docker_image_tag)"
  major="$(printf '%s' "$tag" | sed -n 's/^v\([0-9]\{1,\}\).*/\1/p')"
  if [[ -n "$major" ]]; then
    printf 'version-%s\n' "$major"
  else
    printf 'version-16\n'
  fi
}

# Resolve a repo's default branch (for library apps that pin no explicit branch),
# so generated apps.json entries are always reproducible.
docker_resolve_default_branch() {
  local repo="$1" ref
  ref="$(git ls-remote --symref "$repo" HEAD 2>/dev/null | sed -n 's#^ref: refs/heads/\([^\t ]*\).*#\1#p' | head -n1)"
  printf '%s\n' "${ref:-main}"
}

docker_env_value_from_state() { docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" "$1"; }

# Write apps.json (base erpnext + selected library profiles). Args: profile names.
docker_profile_for_app_name() {
  local wanted="$1" profile

  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    app_profile_defaults "$profile" >/dev/null 2>&1 || continue

    if [[ "$LIB_APP_NAME" == "$wanted" ]]; then
      printf '%s\n' "$profile"
      return 0
    fi
  done < <(app_profile_list)

  return 1
}

docker_profile_dependency_list() {
  local profile="$1"

  case "$profile" in
    helpdesk)
      printf '%s
' telephony
      ;;
  esac
}

docker_custom_image_selected_app_names() {
  require_sudo
  local profile names=""

  $SUDO test -f "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE" || return 0

  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    app_profile_defaults "$profile" >/dev/null 2>&1 || continue
    names="${names}${names:+ }${LIB_APP_NAME}"
  done < <($SUDO cat "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE")

  printf '%s\n' "$names"
}

docker_collect_installed_optional_profiles() {
  require_sudo
  local site app profile
  local unknown=0

  site="$(docker_site_name)"

  while IFS=$' 	' read -r app _; do
    [[ -n "$app" ]] || continue

    case "$app" in
      frappe|erpnext)
        continue
        ;;
    esac

    if profile="$(docker_profile_for_app_name "$app")"; then
      printf '%s\n' "$profile"
    else
      printf 'ERROR: Installed Docker app "%s" is not in the curated app catalog.\n' "$app" >&2
      printf '       Its repository cannot be reconstructed safely for a custom image.\n' >&2
      unknown=1
    fi
  done < <(docker_bench --site "$site" list-apps 2>/dev/null)

  [[ "$unknown" -eq 0 ]]
}

docker_collect_desired_app_profiles() {
  require_sudo
  local requested="${1:-}"
  local profile dependency installed_profiles=""
  local -A selected=()

  if $SUDO test -f "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE"; then
    while IFS= read -r profile; do
      [[ -n "$profile" ]] || continue
      selected["$profile"]=1
    done < <($SUDO cat "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE")
  fi

  installed_profiles="$(docker_collect_installed_optional_profiles)" || return 1

  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    selected["$profile"]=1
  done <<< "$installed_profiles"

  if [[ -n "$requested" ]]; then
    while IFS= read -r dependency; do
      [[ -n "$dependency" ]] || continue
      selected["$dependency"]=1
    done < <(docker_profile_dependency_list "$requested")

    selected["$requested"]=1
  fi

  # Emit in canonical app-library order for deterministic apps.json output.
  while IFS= read -r profile; do
    [[ -n "${selected[$profile]:-}" ]] && printf '%s\n' "$profile"
  done < <(app_profile_list)

  return 0
}

docker_write_apps_json() {
  require_sudo
  local frappe_branch erpnext_branch tmp profiles_tmp profile repo branch
  local -A seen=()

  frappe_branch="$(docker_frappe_branch)"
  erpnext_branch="${ERPNEXT_BRANCH:-$frappe_branch}"

  tmp="$(mktemp)" || return 1
  profiles_tmp="$(mktemp)" || {
    rm -f "$tmp"
    return 1
  }

  {
    printf '[\n'
    printf '  {"url": "https://github.com/frappe/erpnext", "branch": "%s"}' "$erpnext_branch"

    for profile in "$@"; do
      [[ -n "$profile" ]] || continue

      if ! app_profile_defaults "$profile" >/dev/null 2>&1; then
        warn "Unknown app '${profile}', skipping."
        continue
      fi

      [[ -n "${seen[$LIB_APP_NAME]:-}" ]] && continue
      seen["$LIB_APP_NAME"]=1

      repo="$LIB_APP_REPO"
      branch="$LIB_APP_BRANCH"
      [[ -n "$branch" ]] || branch="$(docker_resolve_default_branch "$repo")"

      printf ',\n  {"url": "%s", "branch": "%s"}' "$repo" "$branch"
      printf '%s\n' "$profile" >> "$profiles_tmp"

    done

    printf '\n]\n'
  } > "$tmp"

  $SUDO mkdir -p "$DOCKER_WORKDIR"

  $SUDO cp "$tmp" "$DOCKER_CUSTOM_IMAGE_APPS_FILE"
  $SUDO cp "$profiles_tmp" "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE"

  rm -f "$tmp" "$profiles_tmp"

  $SUDO chown root:root \
    "$DOCKER_CUSTOM_IMAGE_APPS_FILE" \
    "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE" \
    2>/dev/null || true

  $SUDO chmod 644 \
    "$DOCKER_CUSTOM_IMAGE_APPS_FILE" \
    "$DOCKER_CUSTOM_IMAGE_PROFILES_FILE" \
    2>/dev/null || true

}

docker_custom_image_verify_image() {
  require_sudo
  local image="$1" apps="$2" app
  local -a app_list=()

  IFS=' ' read -r -a app_list <<< "$apps"

  for app in "${app_list[@]}"; do
    [[ -n "$app" ]] || continue

    if ! ${SUDO:-} docker run --rm \
      --entrypoint sh \
      "$image" \
      -lc "test -d '/home/frappe/frappe-bench/apps/${app}'"; then
      err "Custom image verification failed: ${app} code is missing from ${image}."
      return 1
    fi
  done

  return 0
}

docker_custom_image_verify_runtime() {
  require_sudo
  local apps="$1" svc app cid
  local -a app_list=()
  local -a services=(
    backend
    frontend
    websocket
    queue-short
    queue-long
    scheduler
  )

  IFS=' ' read -r -a app_list <<< "$apps"

  for svc in "${services[@]}"; do
    cid="$(docker_compose ps -q "$svc" 2>/dev/null | tail -n1)"

    if [[ -z "$cid" ]]; then
      err "Custom-image verification failed: ${svc} container was not found."
      return 1
    fi

    for app in "${app_list[@]}"; do
      [[ -n "$app" ]] || continue

      if ! ${SUDO:-} docker exec "$cid" \
        test -d "/home/frappe/frappe-bench/apps/${app}"; then
        err "Custom-image verification failed: ${app} is missing from ${svc}."
        return 1
      fi
    done
  done

  # Apps with frontend/public source trees must expose their built asset tree
  # through the frontend service. This catches the production defect where only
  # the backend container was mutated.
  for app in "${app_list[@]}"; do
    [[ -n "$app" ]] || continue

    if docker_compose exec -T frontend sh -lc \
      "test -d '/home/frappe/frappe-bench/apps/${app}/frontend' || test -d '/home/frappe/frappe-bench/apps/${app}/public'"; then

      if ! docker_compose exec -T frontend sh -lc \
        "test -e '/home/frappe/frappe-bench/assets/${app}' || test -e '/home/frappe/frappe-bench/sites/assets/${app}'"; then
        err "Custom-image verification failed: frontend assets for ${app} are missing."
        return 1
      fi
    fi
  done

  return 0
}

# Select apps for the custom image and generate apps.json. Non-interactive/-y
# reads DOCKER_CUSTOM_APPS (space separated). erpnext is always included.
docker_custom_image_config() {
  require_sudo
  local selection profile
  local -a chosen=()

  ui_box_start "Configure Custom-App Image"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "Base" "INFO" "erpnext @ $(docker_frappe_branch)"
  echo "Select apps to bake into a durable, immutable image (in addition to ERPNext)."
  echo "Available apps:"
  while IFS= read -r profile; do
    app_profile_defaults "$profile" >/dev/null 2>&1 && printf '  %-16s %s\n' "$profile" "$LIB_APP_DISPLAY"
  done < <(app_profile_list)
  ui_box_end

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    read -r -p "Apps (space separated, blank = ERPNext only): " selection
  else
    selection="${DOCKER_CUSTOM_APPS:-}"
  fi

  # shellcheck disable=SC2206  # deliberate word-split of the space-separated reply
  IFS=' ' read -r -a chosen <<< "$selection"

  docker_write_apps_json "${chosen[@]}"
  ui_box_start "Custom-App Image Configured"
  status_line "apps.json" "OK" "$DOCKER_CUSTOM_IMAGE_APPS_FILE"
  local selected_apps
  selected_apps="$(docker_custom_image_selected_app_names)"
  status_line "Apps" "INFO" "erpnext ${selected_apps:-(none extra)}"
  echo
  echo "apps.json contents:"
  $SUDO sed 's/^/  /' "$DOCKER_CUSTOM_IMAGE_APPS_FILE"
  ui_next "$(toolkit_cmd docker-build-custom-image)"
  ui_box_end
}

docker_custom_image_write_state() {
  require_sudo
  local image="$1" image_id="$2" apps="$3"
  $SUDO mkdir -p "$DOCKER_WORKDIR"
  $SUDO tee "$DOCKER_CUSTOM_IMAGE_STATE_FILE" >/dev/null <<EOF_DOCKER_CUSTOM_IMG
# ERPNext Developer Toolkit - Docker custom-app image state
DOCKER_CUSTOM_IMAGE=${image}
DOCKER_CUSTOM_IMAGE_ID=${image_id}
DOCKER_CUSTOM_IMAGE_APPS=${apps}
DOCKER_CUSTOM_IMAGE_FRAPPE_BRANCH=$(docker_frappe_branch)
DOCKER_CUSTOM_IMAGE_BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DOCKER_CUSTOM_IMAGE_TOOLKIT_VERSION=${SCRIPT_VERSION:-unknown}
EOF_DOCKER_CUSTOM_IMG
  $SUDO chown root:root "$DOCKER_CUSTOM_IMAGE_STATE_FILE" 2>/dev/null || true
  $SUDO chmod 644 "$DOCKER_CUSTOM_IMAGE_STATE_FILE" 2>/dev/null || true
}

# Build the immutable custom image via frappe_docker's layered Containerfile.
docker_build_custom_image() {
  require_sudo
  local clone containerfile tag image image_id branch apps

  clone="$(docker_clone_dir)"
  containerfile="${clone}/images/layered/Containerfile"
  if [[ ! -f "$containerfile" ]]; then
    log "frappe_docker checkout not ready; provisioning it first"
    docker_provision_workdir
  fi
  [[ -f "$containerfile" ]] || fail "Layered Containerfile not found at ${containerfile}."
  $SUDO test -s "$DOCKER_CUSTOM_IMAGE_APPS_FILE" || fail "No apps.json. Run $(toolkit_cmd docker-custom-image-config) first."

  docker_binary_present || fail "Docker is not installed. Run $(toolkit_cmd install) first."
  branch="$(docker_frappe_branch)"
  tag="$(date +%Y%m%d%H%M%S)"
  image="${DOCKER_CUSTOM_IMAGE_REPO}:${tag}"

  ui_box_start "Build Custom-App Image"
  status_line "Image" "INFO" "$image"
  status_line "Frappe branch" "INFO" "$branch"
  status_line "apps.json" "INFO" "$DOCKER_CUSTOM_IMAGE_APPS_FILE"
  status_line "Context" "INFO" "$clone"
  echo
  echo "apps.json:"
  $SUDO sed 's/^/  /' "$DOCKER_CUSTOM_IMAGE_APPS_FILE"
  echo
  echo "Building an immutable image. Running containers are NOT modified."
  ui_box_end

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    confirm "Build ${image} now? (this can take several minutes)" || { warn "Build cancelled."; return 0; }
  fi

  log "Building ${image} (BuildKit)"
  if ! ${SUDO:-} env DOCKER_BUILDKIT=1 docker build \
      --secret "id=apps_json,src=${DOCKER_CUSTOM_IMAGE_APPS_FILE}" \
      --build-arg "FRAPPE_BRANCH=${branch}" \
      --build-arg "FRAPPE_PATH=https://github.com/frappe/frappe" \
      --tag "$image" \
      --file "$containerfile" \
      "$clone"; then
    fail "Custom image build failed. Review the build output above."
  fi

  image_id="$(${SUDO:-} docker inspect --format '{{.Id}}' "$image" 2>/dev/null || echo unknown)"
  apps="$(docker_custom_image_selected_app_names)"

  docker_custom_image_verify_image "$image" "$apps" \
    || fail "Custom image was built, but required app code is missing."

  docker_custom_image_write_state "$image" "$image_id" "$apps"

  ui_box_start "Custom-App Image Built"
  status_line "Image" "OK" "$image"
  status_line "Image ID" "INFO" "$image_id"
  status_line "Apps" "INFO" "erpnext ${apps:-}"
  ui_next "$(toolkit_cmd docker-deploy-custom-image)" "$(toolkit_cmd docker-custom-image-status)"
  ui_box_end
}

# Set (update or append) a KEY=value in any env file without disturbing others.
docker_env_file_set() {
  require_sudo
  local envf="$1" key="$2" val="$3" tmp
  $SUDO test -f "$envf" || return 1
  tmp="$(mktemp)" || return 1
  $SUDO grep -v "^${key}=" "$envf" 2>/dev/null > "$tmp" || true
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  $SUDO cp "$tmp" "$envf"
  rm -f "$tmp"
  $SUDO chown root:root "$envf" 2>/dev/null || true
  $SUDO chmod 600 "$envf" 2>/dev/null || true
}

# Deploy the built custom image by RECREATING the stack on the new image, then
# installing the baked apps onto the site (data step only). No running container
# is mutated in place.
docker_deploy_custom_image() {
  require_sudo
  local image apps site app installed svc
  local -a app_list=()
  local -a services=(
    backend
    frontend
    websocket
    queue-short
    queue-long
    scheduler
  )

  docker_object_backup_load_config >/dev/null 2>&1 || true

  image="$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE)"
  apps="$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE_APPS)"

  [[ -n "$image" ]] \
    || fail "No custom image built yet. Run $(toolkit_cmd docker-build-custom-image) first."

  site="$(docker_site_name)"
  IFS=' ' read -r -a app_list <<< "$apps"

  ui_box_start "Deploy Custom-App Image"
  status_line "Image" "INFO" "$image"
  status_line "Apps to install" "INFO" "${apps:-none extra}"
  status_line "Stack" "INFO" "recreate every application service on one immutable image"
  echo
  echo "Recommended: take a backup first ($(toolkit_cmd backup-files))."
  ui_box_end

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    confirm "Recreate the stack on ${image} and reconcile apps on ${site}?" \
      || {
        warn "Deploy cancelled."
        return 0
      }
  fi

  docker_custom_image_verify_image "$image" "$apps" \
    || fail "The custom image failed pre-deployment verification."

  DOCKER_ERPNEXT_IMAGE="$image"

  if docker_is_production; then
    docker_write_prod_image_override
    docker_env_file_set "$(docker_prod_env_file)" ERPNEXT_VERSION "$(docker_image_tag)" || true
  else
    docker_env_file_set "$(docker_env_file)" DOCKER_ERPNEXT_IMAGE "$image" || true
  fi

  log "Recreating the stack on ${image}"

  docker_compose up -d --remove-orphans --force-recreate \
    || fail "docker compose up failed. Inspect with: $(toolkit_cmd logs)"

  for svc in "${services[@]}"; do
    docker_wait_service_running "$svc" 300 \
      || fail "${svc} did not reach running state after custom-image deployment."
  done

  installed="$(
    docker_bench --site "$site" list-apps 2>/dev/null \
      | tr -d '\r' \
      | awk '{print $1}'
  )"

  for app in "${app_list[@]}"; do
    [[ -n "$app" ]] || continue

    if printf '%s\n' "$installed" | grep -qx "$app"; then
      status_line "install-app ${app}" "OK" "already installed"
      continue
    fi

    if docker_bench --site "$site" install-app "$app"; then
      status_line "install-app ${app}" "OK" "installed"
    else
      fail "Could not install ${app} on ${site}."
    fi
  done

  docker_bench --site "$site" migrate \
    || fail "Site migration failed after custom-image deployment."

  docker_bench --site "$site" clear-cache \
    || warn "clear-cache reported an issue."

  docker_runtime_restart \
    || fail "The Docker runtime could not be restarted after app deployment."

  for svc in "${services[@]}"; do
    docker_wait_service_running "$svc" 300 \
      || fail "${svc} did not return to running state after restart."
  done

  docker_custom_image_verify_runtime "$apps" \
    || fail "Custom-image runtime consistency verification failed."

  docker_write_pins || true

  ok "Deployed custom image ${image} and reconciled apps on ${site}."
  docker_verify_access
}

docker_reconcile_app_image() {
  require_sudo
  local profiles=""
  local -a desired_profiles=()

  docker_is_production \
    || fail "App-image reconciliation is intended for Docker production deployments."

  profiles="$(docker_collect_desired_app_profiles)" \
    || fail "Could not safely reconstruct the installed optional-app set."

  if [[ -z "$profiles" ]]; then
    ok "No optional apps are installed. The standard ERPNext image is already sufficient."
    return 0
  fi

  mapfile -t desired_profiles <<< "$profiles"

  ui_box_start "Reconcile Docker Optional Apps"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "Profiles" "INFO" "$(printf '%s ' "${desired_profiles[@]}" | sed -E 's/ +$//')"
  echo
  echo "The toolkit will:"
  echo "  1. Generate a cumulative apps.json."
  echo "  2. Build one immutable image containing every installed curated app."
  echo "  3. Recreate backend, frontend, workers, scheduler, and websocket on that image."
  echo "  4. Migrate the site and verify app code/assets across the runtime."
  ui_box_end

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    confirm "Build and deploy the reconciled custom image now?" \
      || {
        warn "Reconciliation cancelled."
        return 0
      }
  fi

  docker_write_apps_json "${desired_profiles[@]}"

  ASSUME_YES=1 docker_build_custom_image || return 1
  ASSUME_YES=1 docker_deploy_custom_image || return 1
}

docker_custom_image_status() {
  require_sudo
  ui_box_start "Custom-App Image Status"
  status_line "Site" "INFO" "$(docker_site_name)"
  status_line "apps.json" "$($SUDO test -f "$DOCKER_CUSTOM_IMAGE_APPS_FILE" && echo OK || echo WARN)" "$DOCKER_CUSTOM_IMAGE_APPS_FILE"
  if $SUDO test -f "$DOCKER_CUSTOM_IMAGE_STATE_FILE"; then
    status_line "Built image" "OK" "$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE)"
    status_line "Image ID" "INFO" "$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE_ID)"
    status_line "Apps" "INFO" "erpnext $(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE_APPS)"
    status_line "Frappe branch" "INFO" "$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE_FRAPPE_BRANCH)"
    status_line "Built at" "INFO" "$(docker_env_value "$DOCKER_CUSTOM_IMAGE_STATE_FILE" DOCKER_CUSTOM_IMAGE_BUILT_AT)"
    status_line "Active image" "INFO" "$DOCKER_ERPNEXT_IMAGE"
  else
    status_line "Built image" "WARN" "none built yet"
  fi
  if $SUDO test -f "$DOCKER_CUSTOM_IMAGE_APPS_FILE"; then
    echo
    echo "apps.json:"
    $SUDO sed 's/^/  /' "$DOCKER_CUSTOM_IMAGE_APPS_FILE"
  fi
  ui_next "$(toolkit_cmd docker-custom-image-config)" "$(toolkit_cmd docker-build-custom-image)" "$(toolkit_cmd docker-deploy-custom-image)"
  ui_box_end
}

# Install an app for the active Docker deployment.
# Development mode may mutate the disposable runtime. Production mode must
# rebuild/redeploy one immutable image shared by all application services.
docker_install_app() {
  require_sudo
  local app_name="$1" display="$2" repo="$3" branch="$4"
  local site profile profiles=""
  local -a desired_profiles=()

  site="$(docker_site_name)"

  if docker_is_production; then
    profile="$(docker_profile_for_app_name "$app_name")" \
      || fail "Production Docker app installs require a curated app profile. Custom Git apps must be added through a custom-image workflow."

    profiles="$(docker_collect_desired_app_profiles "$profile")" \
      || fail "Could not safely reconstruct the desired Docker app image."

    mapfile -t desired_profiles <<< "$profiles"

    ui_box_start "Install ${display} - Docker Production"
    status_line "Site" "INFO" "$site"
    status_line "Deployment" "INFO" "immutable custom image"
    status_line "Requested app" "INFO" "$app_name"
    status_line "Image profiles" "INFO" "$(printf '%s ' "${desired_profiles[@]}" | sed -E 's/ +$//')"
    echo
    echo "Production Docker apps are baked into one shared image so backend,"
    echo "frontend, workers, scheduler, and websocket always run identical code."
    ui_box_end

    if ! confirm "Build and deploy the production image containing ${display}?"; then
      warn "App installation cancelled."
      return 0
    fi

    docker_write_apps_json "${desired_profiles[@]}"

    ASSUME_YES=1 docker_build_custom_image || return 1
    ASSUME_YES=1 docker_deploy_custom_image || return 1

    ok "${display} is deployed through the production custom-image workflow."
    return 0
  fi

  warn "Docker development mode: installing the app into the running container."
  warn "This runtime mutation is intended for disposable development environments."

  if ! confirm "Install ${display} into the development container now?"; then
    warn "App installation cancelled."
    return 0
  fi

  if [[ -n "$branch" ]]; then
    docker_bench get-app "$repo" --branch "$branch" \
      || fail "Could not fetch ${display} in the container."
  else
    docker_bench get-app "$repo" \
      || fail "Could not fetch ${display} in the container."
  fi

  docker_bench --site "$site" install-app "$app_name" \
    || fail "Could not install ${display} on ${site}."

  docker_bench --site "$site" migrate \
    || warn "migrate reported an issue."

  docker_runtime_restart || true

  ok "${display} installed into the Docker development container."
}

docker_print_access() {
  local site domain vm_ip
  site="$(docker_site_name)"
  domain="$(docker_public_domain)"
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"

  ui_box_start "ERPNext (Docker) Access"
  status_line "Internal site" "OK" "$site"
  if docker_is_production && docker_https_enabled; then
    status_line "Preferred URL" "OK" "https://${domain}"
    status_line "Public ports" "INFO" "80/443 via Traefik"
    status_line "Direct Docker port" "INFO" "${DOCKER_PUBLISH_PORT} not published in HTTPS mode"
  elif docker_is_production; then
    status_line "Temporary local HTTP" "INFO" "$(docker_direct_http_url localhost)"
    status_line "Public domain" "INFO" "${domain} (HTTPS pending)"
    status_line "Direct Docker port" "WARN" "${DOCKER_PUBLISH_PORT} is temporary; do not expose it publicly"
  else
    status_line "Local URL" "INFO" "$(docker_direct_http_url localhost)"
    if [[ "$vm_ip" != "unknown" && -n "$vm_ip" ]]; then
      status_line "Network URL" "INFO" "$(docker_direct_http_url "$vm_ip")"
    fi
    status_line "Friendly HTTP" "INFO" "http://${site}:${DOCKER_PUBLISH_PORT}"
    if declare -F local_ssl_is_configured >/dev/null 2>&1 && local_ssl_is_configured; then
      status_line "Preferred HTTPS" "OK" "https://${site}"
    fi
  fi
  status_line "Login" "INFO" "Administrator"
  status_line "Credentials" "INFO" "$DOCKER_CREDENTIALS_FILE"
  status_line "Compose project" "INFO" "$DOCKER_PROJECT_NAME"
  ui_box_end

  if docker_is_production; then
    if docker_https_enabled; then
      echo "Open: https://${domain}"
    else
      echo "Temporary pre-HTTPS access uses Docker port ${DOCKER_PUBLISH_PORT}."
      echo "Next: $(toolkit_cmd docker-https-wizard)"
    fi
    return 0
  fi

  echo "Docker publishes its frontend on host port ${DOCKER_PUBLISH_PORT} (8080 by default), not native Bench port 8000."
  echo "For the friendly hostname, map ${site} to this machine's IP on the HOST:"
  print_host_dns_commands_for_site "$site" "$vm_ip"
  echo "Then open: http://${site}:${DOCKER_PUBLISH_PORT}"
  echo "Trusted local HTTPS: $(toolkit_cmd local-ssl-wizard)"
}

# Single programmatic URL (doctor / engine_site_url). Prefer the network IP so
# it is reachable from the host; fall back to loopback when the IP is unknown.
docker_site_url() {
  local vm_ip
  if docker_is_production && docker_https_enabled; then
    printf 'https://%s\n' "$(docker_public_domain)"
    return
  fi
  if ! docker_is_production && declare -F local_ssl_is_configured >/dev/null 2>&1 && local_ssl_is_configured; then
    printf 'https://%s\n' "$(docker_site_name)"
    return
  fi
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  if [[ "$vm_ip" != "unknown" && -n "$vm_ip" ]]; then
    docker_direct_http_url "$vm_ip"
  else
    docker_direct_http_url localhost
  fi
}

# Docker-specific host-mapping checkpoint. Reuses the accurate, port-agnostic
# host DNS command generator (maps the domain to this machine's IP) but prints
# guidance for the Docker published port rather than the native 8000.
docker_host_mapping_checkpoint() {
  require_sudo
  if docker_is_production || is_public_vm_workflow; then
    echo "Production Docker uses public DNS for $(docker_public_domain), not a HOST-file mapping."
    echo "Verify DNS with: getent hosts $(docker_public_domain)"
    return 0
  fi

  local site vm_ip
  site="$(docker_site_name)"
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  echo
  echo "============================================================"
  echo "Host Mapping Checkpoint (friendly domain)"
  echo "============================================================"
  echo
  echo "Docker serves direct HTTP on host port ${DOCKER_PUBLISH_PORT}."
  status_line "Local domain" "INFO" "$site"
  status_line "Detected VM IP" "$([[ "$vm_ip" != unknown ]] && echo OK || echo WARN)" "$vm_ip"
  status_line "Host OS" "INFO" "$(host_os_label)"
  echo
  echo "Run this on your $(host_os_label) HOST machine (not inside the VM):"
  print_host_dns_commands_for_site "$site" "$vm_ip"
  echo
  echo "Then open: http://${site}:${DOCKER_PUBLISH_PORT}"
  echo "For trusted HTTPS, run: $(toolkit_cmd local-ssl-wizard)"
  echo "============================================================"
}

# Interactive checkpoint used by the local Docker guided flow. HTTPS is offered
# only after the operator confirms the friendly hostname works over direct HTTP,
# matching the native local setup contract while using Docker's published port.
docker_guided_host_mapping_checkpoint() {
  [[ -t 0 ]] || return 0
  [[ "${ASSUME_YES:-0}" -eq 1 ]] && return 0
  docker_is_production && return 0
  is_public_vm_workflow && return 0

  local site reply
  site="$(docker_site_name)"
  docker_host_mapping_checkpoint

  while true; do
    echo
    if confirm "Have you applied the HOST mapping and confirmed http://${site}:${DOCKER_PUBLISH_PORT}/login works?"; then
      ok "Docker friendly-hostname HTTP checkpoint confirmed."
      return 0
    fi

    echo
    echo "Trusted HTTPS will not be offered until the friendly hostname works over HTTP."
    echo "Test from the HOST browser: http://${site}:${DOCKER_PUBLISH_PORT}/login"
    echo "Toolkit verification: $(toolkit_cmd verify-access)"
    echo
    read -r -p "Press Enter to show the HOST mapping again, or type skip to continue without HTTPS: " reply || reply="skip"
    reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
    case "$reply" in
      skip|s|q|quit)
        warn "Friendly hostname was not confirmed; skipping guided local HTTPS."
        echo "Complete it later with: $(toolkit_cmd access)"
        return 1
        ;;
      *) docker_host_mapping_checkpoint ;;
    esac
  done
}

# Docker engine access verification (parity with native verify_access).
docker_verify_access() {
  require_sudo
  local site domain code url probe_rc=1
  site="$(docker_site_name)"
  domain="$(docker_public_domain)"

  echo
  echo "============================================================"
  echo "Access Verification (Docker)"
  echo "============================================================"

  if docker_compose ps 2>/dev/null | grep -qiE 'running|up'; then
    status_line "Containers" "OK" "compose services running"
  else
    status_line "Containers" "WARN" "no running services (try: $(toolkit_cmd start))"
  fi

  if docker_is_production && docker_https_enabled; then
    url="https://${domain}/api/method/ping"
    code="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 8 --resolve "${domain}:443:127.0.0.1" "$url" 2>/dev/null || true)"
    case "$code" in
      200|401|403) status_line "Production HTTPS" "OK" "https://${domain} (HTTP ${code})" ;;
      "") status_line "Production HTTPS" "WARN" "no response on local Traefik port 443" ;;
      *) status_line "Production HTTPS" "WARN" "HTTP ${code} from https://${domain}" ;;
    esac
  else
    url="$(docker_direct_http_url localhost)/api/method/ping"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: ${site}" "$url" 2>/dev/null || true)"
    case "$code" in
      200|401|403) status_line "Docker frontend" "OK" "$(docker_direct_http_url localhost) (HTTP ${code})" ;;
      "") status_line "Docker frontend" "WARN" "no response on $(docker_direct_http_url localhost)" ;;
      *) status_line "Docker frontend" "WARN" "HTTP ${code} on $(docker_direct_http_url localhost)" ;;
    esac

    set +e
    probe_login_frontend_assets \
      "http://${site}:${DOCKER_PUBLISH_PORT}/login" \
      "$site" \
      "${DOCKER_PUBLISH_PORT}" \
      "127.0.0.1" >/dev/null
    probe_rc=$?
    set -e
    case "$probe_rc" in
      0) status_line "Static assets" "OK" "login CSS+JS probe passed on port ${DOCKER_PUBLISH_PORT}" ;;
      2) status_line "Static assets" "WARN" "login missing CSS/JS preload — try $(toolkit_cmd repair-frontend-assets)" ;;
      *) status_line "Static assets" "WARN" "login CSS+JS not ready — try $(toolkit_cmd repair-frontend-assets)" ;;
    esac
  fi

  if ! docker_is_production && declare -F local_ssl_is_configured >/dev/null 2>&1 && local_ssl_is_configured; then
    code="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 8 --resolve "${site}:443:127.0.0.1" "https://${site}/login" 2>/dev/null || true)"
    case "$code" in
      200|30[0-9]|401|403) status_line "Friendly HTTPS" "OK" "https://${site} (HTTP ${code})" ;;
      *) status_line "Friendly HTTPS" "WARN" "https://${site} not ready locally (HTTP ${code:-none})" ;;
    esac
  fi

  docker_print_access
}

# Docker engine "what now" summary printed at the end of the guided install.
docker_show_next_steps() {
  echo
  echo "============================================================"
  echo "Docker Engine - Next Steps"
  echo "============================================================"
  if docker_is_production; then
    if docker_https_enabled; then
      echo "  Open ERPNext:        https://$(docker_public_domain)"
    else
      echo "  Temporary local HTTP: $(docker_direct_http_url localhost)"
      echo "  Public domain:        $(docker_public_domain) (HTTPS pending)"
      echo "  Configure HTTPS:      $(toolkit_cmd docker-https-wizard)"
    fi
  else
    echo "  Direct HTTP:         $(docker_direct_http_url localhost)"
    echo "  Network/friendly:    port ${DOCKER_PUBLISH_PORT} (8080 by default)"
    echo "  Trusted local HTTPS: $(toolkit_cmd local-ssl-wizard)"
  fi
  echo "  Verify access:       $(toolkit_cmd verify-access)"
  echo "  Start / stop:        $(toolkit_cmd start) / $(toolkit_cmd stop)"
  echo "  Status / logs:       $(toolkit_cmd status) / $(toolkit_cmd logs)"
  echo "  Backups:             $(toolkit_cmd backup)"
  echo "  Optional apps:       $(toolkit_cmd app-install-wizard)"
  echo "  Engine status:       $(toolkit_cmd engine-status)"
  if docker_is_production; then
    echo "  HTTPS status:        $(toolkit_cmd docker-https-status)"
    echo "  Exposure check:      $(toolkit_cmd docker-production-exposure)"
  fi
  echo "============================================================"
}

# Compact, Docker-safe app installer. The native run_app_install_wizard requires
# a host bench dir (require_site_environment), which does not exist for the
# Docker engine; install_app_profile -> install_frappe_app routes to
# docker_install_app (the container path) so we drive that directly here.
docker_app_install_wizard() {
  require_sudo
  local choice
  while true; do
    ui_submenu_header "Docker App Installation" \
      "Into the running container · durable: $(toolkit_cmd docker-build-custom-image)"
    print_two_column_menu \
      "1) CRM" \
      "2) HR / HRMS" \
      "3) Helpdesk" \
      "4) Payments" \
      "5) Learning / LMS" \
      "6) Webshop / E-Commerce" \
      "7) Builder" \
      "8) Insights" \
      "9) Print Designer" \
      "10) Wiki"
    menu_footer
    menu_read_choice choice
    case "$choice" in
      1) install_app_profile crm; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      2) install_app_profile hrms; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      3) install_app_profile helpdesk; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      4) install_app_profile payments; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      5) install_app_profile lms; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      6) install_app_profile webshop; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      7) install_app_profile builder; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      8) install_app_profile insights; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      9) install_app_profile print_designer; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      10) install_app_profile wiki; pause_after_screen "Press Enter to return to Docker App Wizard..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}

docker_prompt_open_main_menu() {
  local reply
  [[ -t 0 ]] || return 0
  echo
  read -r -p "Open the main toolkit menu now? [Y/n]: " reply
  reply="${reply:-Y}"
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    show_menu
  else
    echo "Open it later with: $(toolkit_cmd menu)"
  fi
}

docker_guided_credentials_checkpoint() {
  [[ -t 0 ]] || return 0
  [[ "${ASSUME_YES:-0}" -eq 1 ]] && return 0

  echo
  ui_box_start "Docker setup: login credentials"
  echo "Your ERPNext Administrator login is ready. Save it before security hardening."
  ui_box_end
  show_credentials_info || true

  echo
  if confirm "Reveal the generated Administrator password now (private console only)?"; then
    credentials_show || true
  else
    echo "Skipped. Reveal it later with: $(toolkit_cmd credentials-show)"
  fi
}

# Post-install continuation for the Docker engine, mirroring the native
# run_guided_setup tail but engine-appropriate. Interactive steps are skipped
# under -y / non-TTY (matching native local_guided_followups) so automation and
# CI stay non-interactive.
docker_guided_followups() {
  docker_verify_access

  # The outer Public VM guided wizard owns backup -> HTTPS -> security -> apps.
  # Do not inject the generic Docker post-install prompts into the middle of it.
  if [[ "${DOCKER_PUBLIC_GUIDED_ACTIVE:-0}" -eq 1 ]]; then
    return 0
  fi

  if ! docker_is_production && ! is_public_vm_workflow; then
    local hostname_http_confirmed=0
    if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
      if docker_guided_host_mapping_checkpoint; then
        hostname_http_confirmed=1
      fi
      if [[ "$hostname_http_confirmed" -eq 1 ]]; then
        if confirm "Set up trusted local HTTPS for https://$(docker_site_name) now?"; then
          run_trusted_mkcert_setup || warn "Local HTTPS did not complete. Retry with: $(toolkit_cmd local-ssl-wizard)"
        else
          echo "Skipped. Configure later with: $(toolkit_cmd local-ssl-wizard)"
        fi
      fi

      docker_guided_credentials_checkpoint

      echo
      if confirm "Apply the local security profile / firewall now?"; then
        configure_local_vm_firewall || warn "Local firewall profile did not complete. Retry with: $(toolkit_cmd local-firewall-profile)"
      else
        echo "Skipped. Run later with: $(toolkit_cmd local-firewall-profile)"
      fi
    else
      docker_host_mapping_checkpoint
    fi
  elif docker_is_production && [[ "${DOCKER_PUBLIC_GUIDED_ACTIVE:-0}" -ne 1 ]] && ! docker_https_enabled; then
    if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]] && confirm "Configure production HTTPS now?"; then
      docker_https_wizard || warn "Production HTTPS did not complete."
    fi
  fi

  if docker_is_production && [[ "${DOCKER_PUBLIC_GUIDED_ACTIVE:-0}" -ne 1 ]]; then
    docker_guided_credentials_checkpoint
  fi

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    if confirm "Install optional Frappe apps now?"; then
      docker_app_install_wizard
    fi
    if confirm "Take an initial durable Docker backup now?"; then
      docker_backup true || warn "Backup did not complete."
    fi
  fi

  docker_show_next_steps
  if [[ "${DOCKER_PUBLIC_GUIDED_ACTIVE:-0}" -ne 1 ]]; then
    docker_prompt_open_main_menu
  fi
}

# doctor rows for the Docker engine.
docker_doctor_detail() {
  local compat
  if docker_daemon_ready; then
    compat="daemon OK"
  elif docker_binary_present; then
    compat="installed, daemon down"
  else
    compat="not installed"
  fi
  doctor_add_check "Docker" "$([[ "$compat" == "daemon OK" ]] && echo OK || echo WARN)" "$compat"
  if [[ -f "$(docker_compose_base_file)" ]]; then
    doctor_add_check "Compose stack" "OK" "$(docker_clone_dir)"
  else
    doctor_add_check "Compose stack" "WARN" "not provisioned"
  fi
}

# ------------------------------------------------------------
# Production provisioning (compose.yaml + upstream overrides)
# ------------------------------------------------------------
# Generate the production env file consumed by compose interpolation. Uses a
# generated random DB root password (unlike the dev default) and forces the
# frontend to resolve the single configured site by host header.
docker_write_prod_env() {
  require_sudo
  local envf site admin_pw db_pw tag existing_admin existing_db
  envf="$(docker_prod_env_file)"
  site="$(docker_site_name)"

  existing_admin="$(docker_env_value "$(docker_env_file)" DOCKER_ADMIN_PASSWORD)"
  existing_db="$(docker_env_value "$(docker_env_file)" DOCKER_DB_ROOT_PASSWORD)"
  if [[ -f "$envf" && -z "$existing_db" ]]; then
    existing_db="$(docker_env_value "$envf" DB_PASSWORD)"
  fi
  admin_pw="${DOCKER_ADMIN_PASSWORD:-${existing_admin:-$(random_password)}}"
  db_pw="${DOCKER_DB_ROOT_PASSWORD:-${existing_db:-$(random_password)}}"
  DOCKER_ADMIN_PASSWORD="$admin_pw"
  DOCKER_DB_ROOT_PASSWORD="$db_pw"
  tag="$(docker_image_tag)"

  $SUDO mkdir -p "$DOCKER_WORKDIR"
  $SUDO tee "$envf" >/dev/null <<EOF_DOCKER_PROD_ENV
# ERPNext Developer Toolkit - Docker production env (compose.yaml interpolation)
ERPNEXT_VERSION=${tag}
DB_PASSWORD=${db_pw}
HTTP_PUBLISH_PORT=127.0.0.1:${DOCKER_PUBLISH_PORT}
FRAPPE_SITE_NAME_HEADER=${site}
EOF_DOCKER_PROD_ENV
  $SUDO chown root:root "$envf" 2>/dev/null || true
  $SUDO chmod 600 "$envf" 2>/dev/null || true

  docker_write_credentials_record "$admin_pw" "$db_pw" "production"
}

# Generated override that pins the ERPNext image across every customizable
# service in compose.yaml. Setting image: directly supports both tag and digest
# pins (the upstream CUSTOM_IMAGE/CUSTOM_TAG split cannot express a digest).
docker_write_prod_image_override() {
  require_sudo
  local f svc
  f="$(docker_prod_image_override_file)"
  $SUDO mkdir -p "$DOCKER_WORKDIR"
  {
    echo "services:"
    for svc in configurator backend frontend websocket queue-short queue-long scheduler; do
      echo "  ${svc}:"
      echo "    image: ${DOCKER_ERPNEXT_IMAGE}"
    done
  } | $SUDO tee "$f" >/dev/null
  $SUDO chown root:root "$f" 2>/dev/null || true
  $SUDO chmod 644 "$f" 2>/dev/null || true
}

# Wait for a named compose service container to reach "running".
docker_wait_service_running() {
  local svc="${1:-backend}" timeout="${2:-300}" deadline cid state
  deadline=$(( $(date +%s) + timeout ))
  while :; do
    cid="$(docker_compose ps -q "$svc" 2>/dev/null | tail -n1)"
    if [[ -n "$cid" ]]; then
      state="$(${SUDO:-} docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
      [[ "$state" == "running" ]] && return 0
    fi
    [[ "$(date +%s)" -ge "$deadline" ]] && return 1
    sleep 5
  done
}

# Create the site in production by exec'ing bench new-site into the backend.
# compose.yaml has no create-site container, so we wait for the configurator
# one-shot to complete (it writes common_site_config), then run new-site once.
docker_prod_create_site() {
  require_sudo
  local site deadline now cid state code
  site="$(docker_site_name)"

  log "Waiting for the configurator job to complete before creating ${site}"
  deadline=$(( $(date +%s) + DOCKER_CREATE_SITE_TIMEOUT ))
  while :; do
    cid="$(docker_compose ps -aq configurator 2>/dev/null | tail -n1)"
    if [[ -n "$cid" ]]; then
      state="$(${SUDO:-} docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
      if [[ "$state" == "exited" ]]; then
        code="$(${SUDO:-} docker inspect -f '{{.State.ExitCode}}' "$cid" 2>/dev/null || echo 1)"
        if [[ "$code" == "0" ]]; then
          break
        fi
        err "configurator job failed (exit ${code}). Recent logs:"
        docker_compose logs --no-color --tail 120 configurator 2>/dev/null || true
        return 1
      fi
    fi
    now="$(date +%s)"
    if [[ "$now" -ge "$deadline" ]]; then
      warn "configurator did not complete within ${DOCKER_CREATE_SITE_TIMEOUT}s. Recent logs:"
      docker_compose logs --no-color --tail 120 configurator 2>/dev/null || true
      return 1
    fi
    sleep 5
  done

  docker_wait_service_running backend 300 || { err "backend container did not reach running state."; return 1; }

  if docker_compose exec -T backend test -f "sites/${site}/site_config.json" >/dev/null 2>&1; then
    ok "Site ${site} already exists; skipping create-site."
    return 0
  fi

  log "Creating site ${site} (bench new-site inside the backend container)"
  if ! docker_compose exec -T backend bench new-site \
      --mariadb-user-host-login-scope='%' \
      --admin-password "$DOCKER_ADMIN_PASSWORD" \
      --db-root-username root \
      --db-root-password "$DOCKER_DB_ROOT_PASSWORD" \
      --install-app erpnext \
      --set-default "$site"; then
    err "bench new-site failed for ${site}. Inspect with: $(toolkit_cmd logs)"
    return 1
  fi
  ok "Site created: ${site}"
}

# Entry point for the docker-production-setup command: force the Docker engine
# in production mode, then run the guided install.
run_docker_production_setup() {
  require_sudo
  # These globals are consumed cross-file (effective_deployment_engine and the
  # config loader in lib/config.sh); shellcheck cannot see that use here.
  # shellcheck disable=SC2034
  DEPLOYMENT_ENGINE="docker"
  # shellcheck disable=SC2034
  DEPLOYMENT_ENGINE_ENV_PROVIDED=1
  DOCKER_MODE="production"
  # shellcheck disable=SC2034
  DOCKER_MODE_ENV_PROVIDED=1
  echo "Deployment engine: Docker (production mode)"
  docker_guided_install
}

# Production guided install: wraps compose.yaml + upstream overrides.
docker_prod_guided_install() {
  require_sudo
  install_self_for_reuse || fail "Could not install the toolkit to ${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"

  docker_ensure_publish_port
  docker_preflight

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    if ! confirm "Provision the PRODUCTION Docker ERPNext stack now?"; then
      echo "Next command:"
      echo "  $(toolkit_cmd install)"
      return 0
    fi
  fi

  docker_install_engine
  docker_provision_workdir
  docker_write_prod_env
  docker_write_prod_image_override

  # Persist engine + mode so lifecycle commands route to the production stack.
  # shellcheck disable=SC2034  # consumed by write_dev_config_file in lib/config.sh
  DEPLOYMENT_ENGINE="docker"
  DOCKER_MODE="production"
  SITE_NAME="$(docker_site_name)"
  write_dev_config_file

  docker_compose up -d --remove-orphans || fail "docker compose up failed. Inspect with: $(toolkit_cmd logs)"
  docker_prod_create_site || fail "Site creation failed. See the logs above, or run: $(toolkit_cmd logs)"
  docker_ready || warn "Stack started but readiness check timed out; it may still be initializing."
  docker_write_pins || warn "Could not record immutable pins."
  docker_write_https_state_if_absent
  ok "Docker production stack setup complete."
  echo
  if docker_https_enabled; then
    echo "HTTPS mode: $(docker_https_mode). Verify with: $(toolkit_cmd docker-https-status)"
  else
    echo "This stack currently serves over HTTP on the published port."
    echo "Enable trusted production HTTPS with: $(toolkit_cmd docker-https-wizard)"
  fi
  docker_guided_followups
}

# ------------------------------------------------------------
# Guided install (Docker engine entry point)
# ------------------------------------------------------------
docker_guided_install() {
  # Production mode wraps compose.yaml; development keeps the disposable pwd.yml
  # flow below (the one-keystroke default).
  if docker_is_production; then
    docker_prod_guided_install
    return
  fi

  require_sudo
  install_self_for_reuse || fail "Could not install the toolkit to ${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"

  # Resolve any published-port conflict before the preflight so the summary and
  # all downstream output reflect the port we will actually publish.
  docker_ensure_publish_port

  docker_preflight

  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    if ! confirm "Provision the Docker ERPNext stack now?"; then
      echo "Next command:"
      echo "  $(toolkit_cmd install)"
      return 0
    fi
  fi

  docker_install_engine
  docker_provision_workdir
  docker_write_env
  docker_write_override

  # Persist engine selection + docker settings so lifecycle commands route here.
  # shellcheck disable=SC2034  # consumed by write_dev_config_file in lib/config.sh
  DEPLOYMENT_ENGINE="docker"
  # shellcheck disable=SC2034  # consumed by write_dev_config_file in lib/config.sh
  DEPLOYMENT_MODE="development"
  SITE_NAME="$(docker_site_name)"
  write_dev_config_file

  docker_compose_up || fail "docker compose up failed. Inspect with: $(toolkit_cmd logs)"
  docker_wait_for_site_creation || fail "Site creation failed. See the create-site logs above, or run: $(toolkit_cmd logs)"
  docker_ready || warn "Stack started but readiness check timed out; it may still be initializing."
  docker_write_pins || warn "Could not record immutable pins."
  ok "Docker deployment engine setup complete."
  docker_guided_followups
}

# ------------------------------------------------------------
# Contract verbs: upgrade / rollback (container-native guidance)
# ------------------------------------------------------------
# A Docker upgrade is an immutable re-deploy (move the pinned image forward, then
# recreate + migrate) rather than an in-place `bench update` on a running
# container. This surfaces the supported path; it does not mutate the stack.
docker_upgrade() {
  require_sudo
  ui_box_start "Docker Upgrade (container-native)"
  status_line "Engine" "INFO" "Docker ($(docker_mode_label 2>/dev/null || echo development))"
  status_line "Current image" "INFO" "${DOCKER_ERPNEXT_IMAGE:-frappe/erpnext}"
  echo "Docker upgrades are immutable re-deploys, not in-place bench updates:"
  echo "  1. Back up first:               $(toolkit_cmd backup-files)"
  echo "  2. Choose the new pinned image (tag or @sha256 digest) via DOCKER_ERPNEXT_IMAGE,"
  echo "     or rebuild a custom image:    $(toolkit_cmd docker-build-custom-image)"
  echo "  3. Re-deploy (recreate on the new image): $(toolkit_cmd docker-deploy-custom-image)"
  echo "     or re-run production setup:   $(toolkit_cmd docker-production-setup)"
  echo "  4. The deploy runs 'bench migrate' and re-records immutable pins automatically."
  ui_next "$(toolkit_cmd backup-files)" "$(toolkit_cmd docker-deploy-custom-image)"
  ui_box_end
}

# Roll a Docker deployment back by re-deploying the previous immutable image
# and/or restoring data. Read-only guidance (no mutation).
docker_rollback() {
  require_sudo
  ui_box_start "Docker Rollback (container-native)"
  status_line "Engine" "INFO" "Docker ($(docker_mode_label 2>/dev/null || echo development))"
  status_line "Recorded pins" "INFO" "${DOCKER_PINS_FILE:-<pins file>}"
  echo "Roll back by re-deploying a known-good immutable image and/or restoring data:"
  echo "  - Previous image pin is recorded in: ${DOCKER_PINS_FILE:-<pins file>}"
  echo "  - Redeploy a known-good image: set DOCKER_ERPNEXT_IMAGE=<previous> then $(toolkit_cmd docker-deploy-custom-image)"
  echo "  - Restore site data from a backup:   $(toolkit_cmd docker-restore)"
  echo "  - Roll back HTTPS/proxy only:        $(toolkit_cmd docker-https-rollback)"
  ui_next "$(toolkit_cmd docker-restore)" "$(toolkit_cmd docker-https-rollback)"
  ui_box_end
}
