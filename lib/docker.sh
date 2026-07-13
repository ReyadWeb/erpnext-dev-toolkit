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
# Pin the frappe_docker checkout for reproducible provisioning. The image tag
# below is the stronger reproducibility anchor; the repo only supplies pwd.yml.
FRAPPE_DOCKER_REF="${FRAPPE_DOCKER_REF:-main}"
# Pinned production-ready image published by the Frappe team.
DOCKER_ERPNEXT_IMAGE="${DOCKER_ERPNEXT_IMAGE:-frappe/erpnext:v16.26.2}"
DOCKER_PROJECT_NAME="${DOCKER_PROJECT_NAME:-erpnext-dev}"
DOCKER_PUBLISH_PORT="${DOCKER_PUBLISH_PORT:-8080}"
DOCKER_READY_TIMEOUT="${DOCKER_READY_TIMEOUT:-900}"
# How long to wait for the one-shot create-site job (site + erpnext install) to
# complete before treating the install as failed.
DOCKER_CREATE_SITE_TIMEOUT="${DOCKER_CREATE_SITE_TIMEOUT:-900}"
DOCKER_CREDENTIALS_FILE="${DOCKER_CREDENTIALS_FILE:-${DOCKER_WORKDIR}/erpnext-dev-docker-credentials.txt}"

docker_clone_dir() { printf '%s/frappe_docker\n' "$DOCKER_WORKDIR"; }
docker_compose_base_file() { printf '%s/frappe_docker/pwd.yml\n' "$DOCKER_WORKDIR"; }
docker_override_file() { printf '%s/erpnext-dev.override.yml\n' "$DOCKER_WORKDIR"; }
docker_env_file() { printf '%s/erpnext-dev.env\n' "$DOCKER_WORKDIR"; }

# The Docker engine serves whatever site name is configured. Default to the
# toolkit SITE_NAME (e.g. erp.test) so local host mapping stays consistent.
docker_site_name() { printf '%s\n' "${DOCKER_SITE_NAME:-${SITE_NAME:-erp.test}}"; }

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
docker_compose_resolve() {
  local __out_name="${1:-DOCKER_COMPOSE_CMD}"
  if docker compose version >/dev/null 2>&1; then
    eval "${__out_name}=(docker compose)"
  elif command -v docker-compose >/dev/null 2>&1; then
    eval "${__out_name}=(docker-compose)"
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
# Compose wrapper
# ------------------------------------------------------------
# Run docker compose with the project name, upstream base file, our override,
# and the generated env file. All extra args are passed straight through.
docker_compose() {
  local base override envf
  local -a compose_cmd=()
  docker_compose_resolve compose_cmd || { err "Docker Compose is not available."; return 1; }
  base="$(docker_compose_base_file)"
  override="$(docker_override_file)"
  envf="$(docker_env_file)"
  if [[ ! -f "$base" ]]; then
    err "frappe_docker base compose not found: ${base}. Run the Docker install first."
    return 1
  fi
  # $SUDO is a single token ("sudo" or empty) so it is safe to leave unquoted;
  # the compose program is expanded from an array to survive the restricted IFS.
  # shellcheck disable=SC2086
  ${SUDO:-} "${compose_cmd[@]}" -p "$DOCKER_PROJECT_NAME" --env-file "$envf" -f "$base" -f "$override" "$@"
}

# ------------------------------------------------------------
# Host engine install (Docker Engine + compose plugin)
# ------------------------------------------------------------
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

  log "Installing Docker Engine using the official convenience script (get.docker.com)"
  local tmp
  tmp="$(mktemp /tmp/erpnext-dev-get-docker.XXXXXX.sh)" || return 1
  if ! curl -fsSL https://get.docker.com -o "$tmp"; then
    rm -f "$tmp"
    fail "Could not download the Docker installation script. Check internet access and retry."
  fi
  if ! $SUDO sh "$tmp"; then
    rm -f "$tmp"
    fail "Docker Engine installation failed. Install Docker manually, then re-run."
  fi
  rm -f "$tmp"

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

  ui_box_start "Docker Deployment Preflight"
  status_line "Operating system" "$os_status" "$os_pretty"
  status_line "Deployment engine" "INFO" "Docker"
  status_line "Architecture" "INFO" "$(host_arch_label)"
  status_line "Docker compatibility" "$compat_status" "$compat_detail"
  status_line "ERPNext image" "INFO" "$DOCKER_ERPNEXT_IMAGE"
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
docker_provision_workdir() {
  require_sudo
  local clone
  clone="$(docker_clone_dir)"

  $SUDO mkdir -p "$DOCKER_WORKDIR" || fail "Could not create ${DOCKER_WORKDIR}"

  if [[ -d "${clone}/.git" ]]; then
    log "Updating frappe_docker checkout (${FRAPPE_DOCKER_REF})"
    $SUDO git -C "$clone" fetch --depth 1 origin "$FRAPPE_DOCKER_REF" >/dev/null 2>&1 || true
    $SUDO git -C "$clone" checkout -q "$FRAPPE_DOCKER_REF" 2>/dev/null || true
    $SUDO git -C "$clone" reset --hard "origin/${FRAPPE_DOCKER_REF}" >/dev/null 2>&1 || true
  else
    log "Cloning frappe_docker (${FRAPPE_DOCKER_REF}) into ${clone}"
    $SUDO rm -rf "$clone"
    if ! $SUDO git clone --depth 1 --branch "$FRAPPE_DOCKER_REF" "$FRAPPE_DOCKER_REPO" "$clone" >/dev/null 2>&1; then
      # Fallback: full clone then checkout (branch may be a commit/tag).
      $SUDO rm -rf "$clone"
      $SUDO git clone "$FRAPPE_DOCKER_REPO" "$clone" >/dev/null 2>&1 || fail "Could not clone frappe_docker from ${FRAPPE_DOCKER_REPO}"
      $SUDO git -C "$clone" checkout -q "$FRAPPE_DOCKER_REF" 2>/dev/null || warn "Could not check out ref ${FRAPPE_DOCKER_REF}; using default branch."
    fi
  fi

  if [[ ! -f "$(docker_compose_base_file)" ]]; then
    fail "frappe_docker did not provide pwd.yml at $(docker_compose_base_file)."
  fi
  ok "frappe_docker ready at ${clone}"
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

  $SUDO tee "$DOCKER_CREDENTIALS_FILE" >/dev/null <<EOF_DOCKER_CREDS
# ERPNext Developer Toolkit - Docker engine credentials
# Site:  $(docker_site_name)
# URL:   http://localhost:${DOCKER_PUBLISH_PORT}
Administrator password: ${admin_pw}
MariaDB root password:  ${db_pw}
EOF_DOCKER_CREDS
  $SUDO chown root:root "$DOCKER_CREDENTIALS_FILE" 2>/dev/null || true
  $SUDO chmod 600 "$DOCKER_CREDENTIALS_FILE" 2>/dev/null || true
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

# Poll the published HTTP endpoint until the site answers or timeout elapses.
docker_ready() {
  local url deadline now
  url="http://localhost:${DOCKER_PUBLISH_PORT}/api/method/ping"
  deadline=$(( $(date +%s) + DOCKER_READY_TIMEOUT ))
  log "Waiting for ERPNext to answer on http://localhost:${DOCKER_PUBLISH_PORT}"
  while :; do
    if curl -fsS -o /dev/null --max-time 5 "$url" 2>/dev/null; then
      ok "ERPNext is responding on port ${DOCKER_PUBLISH_PORT}"
      return 0
    fi
    now="$(date +%s)"
    if [[ "$now" -ge "$deadline" ]]; then
      warn "ERPNext did not respond within ${DOCKER_READY_TIMEOUT}s."
      echo "Check container logs with: $(toolkit_cmd logs)"
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

docker_backup() {
  require_sudo
  local include_files="${1:-false}"
  local site
  site="$(docker_site_name)"
  if [[ "$include_files" == "true" ]]; then
    log "Creating database + files backup for ${site} (Docker)"
    docker_bench --site "$site" backup --with-files
  else
    log "Creating database backup for ${site} (Docker)"
    docker_bench --site "$site" backup
  fi
  ok "Backup completed inside the sites volume (docker volume: ${DOCKER_PROJECT_NAME}_sites)."
  echo "List backups with: $(toolkit_cmd list-backups)"
}

docker_list_backups() {
  require_sudo
  local site
  site="$(docker_site_name)"
  docker_bench --site "$site" list-backups 2>/dev/null || {
    warn "Could not list backups. Is the stack running? ($(toolkit_cmd start))"
    return 1
  }
}

# Install an app inside the running container. Container app installs are not
# persisted across image upgrades (the recommended path is a custom image); we
# warn accordingly. args: app_name display repo branch notes
docker_install_app() {
  require_sudo
  local app_name="$1" display="$2" repo="$3" branch="$4"
  local site
  site="$(docker_site_name)"

  warn "Docker engine: apps are installed into the running container."
  warn "This is ideal for evaluation. For durable deployments, build a custom image (planned: docker-custom-image)."

  if ! confirm "Install ${display} into the ERPNext container now?"; then
    warn "App installation cancelled."
    return 0
  fi

  if [[ -n "$branch" ]]; then
    docker_bench get-app "$repo" --branch "$branch" || fail "Could not fetch ${display} in the container."
  else
    docker_bench get-app "$repo" || fail "Could not fetch ${display} in the container."
  fi
  docker_bench --site "$site" install-app "$app_name" || fail "Could not install ${display} on ${site}."
  docker_bench --site "$site" migrate || warn "migrate reported an issue."
  docker_runtime_restart || true
  ok "${display} installed into the ERPNext container."
}

docker_print_access() {
  local site
  site="$(docker_site_name)"
  ui_box_start "ERPNext (Docker) Access"
  status_line "Site" "OK" "$site"
  status_line "URL" "INFO" "http://localhost:${DOCKER_PUBLISH_PORT}"
  status_line "Login" "INFO" "Administrator"
  status_line "Credentials" "INFO" "$DOCKER_CREDENTIALS_FILE"
  status_line "Compose project" "INFO" "$DOCKER_PROJECT_NAME"
  ui_box_end
  echo "To reach it via ${site} in a browser, map it to 127.0.0.1 on your host:"
  echo "  echo '127.0.0.1 ${site}' | sudo tee -a /etc/hosts"
  echo "then open: http://${site}:${DOCKER_PUBLISH_PORT}"
}

docker_site_url() { printf 'http://localhost:%s\n' "$DOCKER_PUBLISH_PORT"; }

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
# Guided install (Docker engine entry point)
# ------------------------------------------------------------
docker_guided_install() {
  require_sudo
  install_self_for_reuse || fail "Could not install the toolkit to ${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"

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
  docker_print_access
  ok "Docker deployment engine setup complete."
}
