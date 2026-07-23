# shellcheck shell=bash
# Security audit, credential handoff, and checksum-gated toolkit updates.
# Sourced by the toolkit entry point; do not execute directly.

[[ -n "${_ERPNEXT_DEV_SECURITY_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_SECURITY_LOADED=1

TOOLKIT_RELEASE_REPO="${TOOLKIT_RELEASE_REPO:-https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit}"

# Fingerprint of the maintainer release-signing key. Trust anchor for verify-signature
# and for stable tag-channel update-toolkit (must match VALIDSIG from bundled pubkey).
TOOLKIT_SIGNING_FINGERPRINT_DEFAULT="BFC10C79427CF73496EA6F5A30BFD17DD559C8B6"

toolkit_release_lib_files() {
  printf '%s\n' \
    common.sh ui.sh config.sh access.sh local_ip.sh frappe.sh support.sh backup.sh ssl.sh firewall.sh \
    apps.sh health.sh storage.sh service.sh status.sh docker.sh engine.sh install.sh ops.sh \
    dashboard.sh healing.sh menu.sh security.sh update.sh
}

find_toolkit_checksum_file() {
  local active_dir stable_dir candidate
  active_dir="$(dirname "${ERPNEXT_DEV_ENTRY_SCRIPT:-${BASH_SOURCE[0]}}")"
  stable_dir="$(dirname "${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}")"

  for candidate in \
    "${CHECKSUM_FILE:-}" \
    "${TOOLKIT_CHECKSUM_FILE:-}" \
    "./SHA256SUMS" \
    "${active_dir}/SHA256SUMS" \
    "${stable_dir}/SHA256SUMS" \
    "/opt/erpnext-dev/SHA256SUMS"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

checksum_expected_for_release_path() {
  local checksum_file="$1"
  local rel_path="$2"

  awk -v p="$rel_path" '
    $2 == p || $2 == "./" p { print $1; found=1; exit }
    $2 ~ /\/erpnext-dev\.sh$/ && p == "erpnext-dev.sh" { print $1; found=1; exit }
    END { if (!found) exit 1 }
  ' "$checksum_file"
}

checksum_expected_for_toolkit() {
  checksum_expected_for_release_path "$1" "erpnext-dev.sh"
}

verify_release_file_checksum() {
  local checksum_file="$1"
  local rel_path="$2"
  local file_path="$3"
  local expected actual

  [[ -f "$file_path" ]] || fail "Downloaded file missing: ${rel_path}"
  expected="$(checksum_expected_for_release_path "$checksum_file" "$rel_path" 2>/dev/null || true)"
  [[ -n "$expected" ]] || fail "SHA256SUMS has no entry for ${rel_path}"
  actual="$(sha256sum "$file_path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "Checksum mismatch for ${rel_path}"
}

resolve_toolkit_update_version() {
  local version="${TOOLKIT_UPDATE_VERSION:-}"

  # Mutable main channel installs into releases/<slot> (default: main), never into
  # releases/vX.Y.Z — that would overwrite a signed tagged release directory.
  if toolkit_update_uses_mutable_branch; then
    local channel
    channel="$(toolkit_update_branch_name)"
    version="${TOOLKIT_UPDATE_SLOT:-${TOOLKIT_UPDATE_VERSION:-$channel}}"
    # Ignore accidental v* tags on mutable channels; slot names stay unversioned.
    if [[ "$version" == v* ]]; then
      version="${TOOLKIT_UPDATE_SLOT:-$channel}"
    fi
    [[ -n "$version" ]] || version="$channel"
    printf '%s\n' "$version"
    return 0
  fi

  if [[ -n "$version" ]]; then
    [[ "$version" == v* ]] || version="v${version}"
    printf '%s\n' "$version"
    return 0
  fi

  if [[ -t 0 && "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Release tag to install [v${SCRIPT_VERSION}]: " version || version=""
  fi
  version="${version:-v${SCRIPT_VERSION}}"
  [[ "$version" == v* ]] || version="v${version}"
  printf '%s\n' "$version"
}

toolkit_update_branch_name() {
  case "${TOOLKIT_UPDATE_CHANNEL:-tag}" in
    main) printf 'main\n' ;;
    beta) printf 'beta\n' ;;
    *) return 1 ;;
  esac
}

toolkit_update_uses_mutable_branch() {
  toolkit_update_branch_name >/dev/null 2>&1 || [[ "${TOOLKIT_UPDATE_FROM_MAIN:-0}" == "1" ]]
}

toolkit_update_uses_main_branch() {
  [[ "${TOOLKIT_UPDATE_CHANNEL:-tag}" == "main" ]] || [[ "${TOOLKIT_UPDATE_FROM_MAIN:-0}" == "1" ]]
}

toolkit_update_guard_production_channel() {
  local channel
  if ! toolkit_update_uses_mutable_branch; then
    return 0
  fi
  channel="$(toolkit_update_branch_name 2>/dev/null || printf 'main\n')"

  if is_public_vm_workflow && [[ "${TOOLKIT_UPDATE_ALLOW_MUTABLE:-${TOOLKIT_UPDATE_ALLOW_MAIN:-0}}" != "1" ]]; then
    fail "Refusing mutable ${channel}-branch update on production/public-vm workflow. Use a signed vX.Y.Z release, or set TOOLKIT_UPDATE_ALLOW_MUTABLE=1 to override for controlled testing."
  fi

  warn "Mutable ${channel} branch selected for testing. Do not treat this as a signed stable release."
}

verify_toolkit_integrity() {
  local active stable cli_target checksum_file expected active_hash stable_hash cli_hash match_state=0
  active="${ERPNEXT_DEV_ENTRY_SCRIPT:-$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")}"
  stable="${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"
  cli_target="$(readlink -f "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev}" 2>/dev/null || true)"

  ui_box_start "Verify ERPNext Toolkit Integrity"
  status_line "Toolkit version" "INFO" "${SCRIPT_VERSION}"
  status_line "Active script" "$([[ -f "$active" ]] && echo OK || echo WARN)" "$active"
  status_line "Stable toolkit" "$([[ -f "$stable" ]] && echo OK || echo WARN)" "$stable"
  if [[ -n "$cli_target" ]]; then
    status_line "CLI command" "OK" "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev} -> ${cli_target}"
  else
    status_line "CLI command" "WARN" "${TOOLKIT_CLI_PATH:-/usr/local/bin/erpnext-dev} not found"
  fi

  if ! command -v sha256sum >/dev/null 2>&1; then
    status_line "sha256sum" "FAIL" "sha256sum command not found"
    ui_box_end
    return 1
  fi

  if [[ -f "$active" ]]; then
    active_hash="$(sha256sum "$active" | awk '{print $1}')"
    status_line "Active SHA256" "INFO" "$active_hash"
  fi
  if [[ -f "$stable" ]]; then
    stable_hash="$(sha256sum "$stable" | awk '{print $1}')"
    status_line "Stable SHA256" "INFO" "$stable_hash"
  fi
  if [[ -n "$cli_target" && -f "$cli_target" ]]; then
    cli_hash="$(sha256sum "$cli_target" | awk '{print $1}')"
    status_line "CLI SHA256" "INFO" "$cli_hash"
  fi

  if checksum_file="$(find_toolkit_checksum_file 2>/dev/null)"; then
    status_line "Checksum file" "OK" "$checksum_file"
    if expected="$(checksum_expected_for_toolkit "$checksum_file" 2>/dev/null)"; then
      status_line "Expected SHA256" "INFO" "$expected"
      if [[ -n "${active_hash:-}" && "$active_hash" == "$expected" ]]; then
        status_line "Active match" "OK" "active script matches SHA256SUMS"
      else
        status_line "Active match" "FAIL" "active script does not match SHA256SUMS"
        match_state=1
      fi
      if [[ -n "${stable_hash:-}" ]]; then
        if [[ "$stable_hash" == "$expected" ]]; then
          status_line "Stable match" "OK" "stable toolkit matches SHA256SUMS"
        else
          status_line "Stable match" "WARN" "stable toolkit does not match SHA256SUMS"
        fi
      fi
      if [[ -n "${cli_hash:-}" ]]; then
        if [[ "$cli_hash" == "$expected" ]]; then
          status_line "CLI match" "OK" "CLI target matches SHA256SUMS"
        else
          status_line "CLI match" "WARN" "CLI target does not match SHA256SUMS"
        fi
      fi
    else
      status_line "Expected SHA256" "WARN" "no erpnext-dev.sh entry found in checksum file"
    fi

    # Verify every runtime module, not just the entrypoint. A modular toolkit
    # sources 17 lib/*.sh files; tampering with any one of them must be caught.
    local active_dir lib_dir mod mod_path mod_hash mod_expected
    local mods_total=0 mods_ok=0 mods_bad=0 mods_missing=0 mods_unlisted=0
    active_dir="$(cd "$(dirname "$active")" 2>/dev/null && pwd || dirname "$active")"
    lib_dir="${active_dir}/lib"

    while IFS= read -r mod; do
      mods_total=$((mods_total + 1))
      mod_path="${lib_dir}/${mod}"
      if [[ ! -f "$mod_path" ]]; then
        status_line "Module ${mod}" "FAIL" "missing at ${mod_path}"
        mods_missing=$((mods_missing + 1))
        match_state=1
        continue
      fi
      mod_expected="$(checksum_expected_for_release_path "$checksum_file" "lib/${mod}" 2>/dev/null || true)"
      if [[ -z "$mod_expected" ]]; then
        status_line "Module ${mod}" "WARN" "no lib/${mod} entry in checksum file"
        continue
      fi
      mod_hash="$(sha256sum "$mod_path" | awk '{print $1}')"
      if [[ "$mod_hash" == "$mod_expected" ]]; then
        mods_ok=$((mods_ok + 1))
      else
        status_line "Module ${mod}" "FAIL" "does not match SHA256SUMS"
        mods_bad=$((mods_bad + 1))
        match_state=1
      fi
    done < <(toolkit_release_lib_files)

    if (( mods_bad == 0 && mods_missing == 0 )); then
      status_line "Runtime modules" "OK" "${mods_ok}/${mods_total} match SHA256SUMS"
    else
      status_line "Runtime modules" "FAIL" "${mods_ok}/${mods_total} OK, ${mods_bad} mismatched, ${mods_missing} missing"
    fi

    # Flag any lib/*.sh that ships on disk but is not part of the signed release
    # list. Such a file would not be sourced, but its presence is suspicious.
    if [[ -d "$lib_dir" ]]; then
      local -A _known_mods=()
      local disk_mod disk_base unlisted=""
      while IFS= read -r disk_mod; do _known_mods["$disk_mod"]=1; done < <(toolkit_release_lib_files)
      for disk_mod in "$lib_dir"/*.sh; do
        [[ -e "$disk_mod" ]] || continue
        disk_base="$(basename "$disk_mod")"
        if [[ -z "${_known_mods[$disk_base]:-}" ]]; then
          unlisted+="${disk_base} "
          mods_unlisted=$((mods_unlisted + 1))
        fi
      done
      if (( mods_unlisted == 0 )); then
        status_line "Unexpected modules" "OK" "none"
      else
        status_line "Unexpected modules" "WARN" "not in release list: ${unlisted% }"
      fi
    fi
  else
    status_line "Checksum file" "WARN" "not found; download SHA256SUMS beside erpnext-dev.sh or set CHECKSUM_FILE=/path/SHA256SUMS"
  fi

  echo
  echo "Verified tag-pinned update example:"
  echo "  TOOLKIT_UPDATE_VERSION=v${SCRIPT_VERSION} sudo erpnext-dev update-toolkit"
  echo
  echo "Manual verified download:"
  echo "  VERSION=\"v${SCRIPT_VERSION}\""
  echo '  workdir="$(mktemp -d /tmp/erpnext-dev-update.XXXXXX)"; cd "$workdir" || exit 1'
  echo '  curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/${VERSION}/erpnext-dev.sh"'
  echo '  curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/${VERSION}/SHA256SUMS"'
  echo "  sha256sum -c SHA256SUMS"
  echo "  sudo mkdir -p /opt/erpnext-dev"
  echo "  sudo install -m 0755 erpnext-dev.sh /opt/erpnext-dev/erpnext-dev.sh"
  echo "  sudo install -m 0644 SHA256SUMS /opt/erpnext-dev/SHA256SUMS"
  echo "  sudo ln -sf /opt/erpnext-dev/erpnext-dev.sh /usr/local/bin/erpnext-dev"
  echo "  sudo erpnext-dev verify-toolkit"
  ui_box_end
  return "$match_state"
}

# ---- Atomic self-update: versioned release dirs + a `current` symlink --------
#
# Layout after an atomic update:
#   /opt/erpnext-dev/releases/<ver>/   (full verified tree)
#   /opt/erpnext-dev/current       -> releases/<ver>
#   /opt/erpnext-dev/erpnext-dev.sh -> current/erpnext-dev.sh
#   /usr/local/bin/erpnext-dev     -> /opt/erpnext-dev/erpnext-dev.sh
# The entry script resolves its own real path (readlink -f), so lib/ always
# loads from releases/<ver>. Switching the `current` symlink is a single atomic
# rename, so a crash mid-update can never leave a half-written live tree, and the
# previous release stays on disk for rollback.

TOOLKIT_RELEASE_GITHUB="${TOOLKIT_RELEASE_GITHUB:-https://github.com/ReyadWeb/erpnext-dev-toolkit}"
TOOLKIT_RELEASES_KEEP="${TOOLKIT_RELEASES_KEEP:-3}"

toolkit_stable_root() {
  dirname "${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}"
}

toolkit_releases_dir() {
  printf '%s/releases\n' "$(toolkit_stable_root)"
}

toolkit_current_link() {
  printf '%s/current\n' "$(toolkit_stable_root)"
}

# Atomically point <root>/current at a release directory. target_rel is relative
# to the stable root (e.g. "releases/v1.6.0") so the symlink stays valid if the
# root is ever moved.
toolkit_point_current() {
  local target_rel="$1"
  local root tmp
  root="$(toolkit_stable_root)"
  tmp="${root}/.current.tmp.$$"
  ln -sfn "$target_rel" "$tmp" || return 1
  mv -T "$tmp" "$(toolkit_current_link)"
}

# Replace the top-level convenience entries with symlinks into current/. The
# entry script (erpnext-dev.sh) is swapped atomically; the rest are best-effort
# mirrors and are not used at runtime (the resolved release dir is).
toolkit_link_into_current() {
  local root name tmp
  root="$(toolkit_stable_root)"

  tmp="${root}/.entry.tmp.$$"
  ln -sfn "current/erpnext-dev.sh" "$tmp"
  mv -T "$tmp" "${root}/erpnext-dev.sh"
  chmod 755 "${root}/erpnext-dev.sh" 2>/dev/null || true

  for name in lib SHA256SUMS SHA256SUMS.asc RELEASE-MANIFEST.txt docs; do
    [[ -e "${root}/current/${name}" ]] || continue
    rm -rf "${root:?}/${name}"
    ln -sfn "current/${name}" "${root}/${name}"
  done
}

# Keep only the newest N release directories plus whatever `current` and
# `.previous` reference.
toolkit_prune_releases() {
  local keep="${1:-3}"
  local releases_dir current_target prev keep_set d base count=0
  releases_dir="$(toolkit_releases_dir)"
  [[ -d "$releases_dir" ]] || return 0

  current_target="$(readlink "$(toolkit_current_link)" 2>/dev/null | xargs -r basename 2>/dev/null || true)"
  prev="$(cat "${releases_dir}/.previous" 2>/dev/null || true)"
  keep_set=" ${current_target} ${prev} "

  # Newest first by mtime.
  while IFS= read -r d; do
    [[ -d "$d" ]] || continue
    base="$(basename "$d")"
    if [[ "$keep_set" == *" ${base} "* ]]; then
      continue
    fi
    count=$((count + 1))
    if (( count > keep )); then
      rm -rf "$d"
    fi
  done < <(ls -1dt "${releases_dir}"/*/ 2>/dev/null)
}

# Verify a detached GPG signature over SHA256SUMS using a local public-key file.
# Enforces TOOLKIT_SIGNING_KEY_FINGERPRINT or TOOLKIT_SIGNING_FINGERPRINT_DEFAULT.
# Returns 0 on success; 1 on failure (messages via err()).
toolkit_gpg_verify_signature_files() {
  local checksum_file="$1" signature_file="$2" pubkey_file="$3"
  local gnupg_home verify_out want got

  if ! command -v gpg >/dev/null 2>&1; then
    err "gpg is not installed. Install gnupg to verify release signatures (Ubuntu: sudo apt-get install -y gnupg)."
    return 1
  fi

  if [[ ! -f "$checksum_file" ]]; then
    err "Missing checksum file: ${checksum_file}"
    return 1
  fi
  if [[ ! -f "$signature_file" ]]; then
    err "Missing detached signature ${signature_file}. Stable release updates require SHA256SUMS.asc."
    return 1
  fi
  if [[ ! -f "$pubkey_file" ]]; then
    err "Missing bundled signing public key: ${pubkey_file}"
    return 1
  fi

  gnupg_home="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-dev-gpg.XXXXXX")" || {
    err "Could not create temporary keyring."
    return 1
  }

  if ! GNUPGHOME="$gnupg_home" gpg --batch --import "$pubkey_file" >/dev/null 2>&1; then
    err "Could not import signing public key from ${pubkey_file}."
    rm -rf "$gnupg_home"
    return 1
  fi

  verify_out="$(GNUPGHOME="$gnupg_home" gpg --status-fd 1 --verify "$signature_file" "$checksum_file" 2>/dev/null || true)"
  rm -rf "$gnupg_home"

  if ! printf '%s\n' "$verify_out" | grep -q '^\[GNUPG:\] GOODSIG'; then
    err "Release signature verification failed (signature did not verify against the bundled key)."
    return 1
  fi

  want="$(printf '%s' "${TOOLKIT_SIGNING_KEY_FINGERPRINT:-$TOOLKIT_SIGNING_FINGERPRINT_DEFAULT}" | tr -d ' ' | tr '[:lower:]' '[:upper:]')"
  if [[ -n "$want" ]]; then
    got="$(printf '%s\n' "$verify_out" | awk '/^\[GNUPG:\] VALIDSIG/ { print $3; exit }')"
    if [[ -z "$got" || "$got" != *"$want"* ]]; then
      err "Signing key fingerprint ${got:-unknown} does not match pinned maintainer fingerprint ${want}."
      return 1
    fi
  fi

  return 0
}

# Verify the detached signature over a staged SHA256SUMS using the bundled public key
# in the same release tree. Stable tag-channel updates require signature, gpg, pubkey,
# and a signer fingerprint matching the pinned maintainer key.
toolkit_verify_staged_signature() {
  local tree="$1"
  local sig="${tree}/SHA256SUMS.asc"
  local sums="${tree}/SHA256SUMS"
  local pubkey="${tree}/docs/erpnext-dev-signing-key.asc"

  if toolkit_gpg_verify_signature_files "$sums" "$sig" "$pubkey"; then
    ok "Release signature verified; signing key matches pinned maintainer fingerprint."
    return 0
  fi
  return 1
}

update_toolkit() {
  require_sudo

  local version release_base workdir tree stable_root releases_dir new_release
  local prev_version current_target lib_file checksum_file

  command -v curl >/dev/null 2>&1 || fail "curl is required. Install it with: sudo apt-get install -y curl ca-certificates"
  command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required for checksum-gated updates."

  toolkit_update_guard_production_channel
  version="$(resolve_toolkit_update_version)"

  stable_root="$(toolkit_stable_root)"
  releases_dir="${stable_root}/releases"
  mkdir -p "$releases_dir" || fail "Could not create ${releases_dir}."

  # Stage on the SAME filesystem as releases/ so the promotion is an atomic rename.
  workdir="$(mktemp -d "${stable_root}/.staging.XXXXXX")" || fail "Could not create staging directory under ${stable_root}."

  ui_box_start "Update ERPNext Toolkit (atomic)"
  if toolkit_update_uses_mutable_branch; then
    status_line "Install slot" "INFO" "$version"
  else
    status_line "Release tag" "INFO" "$version"
  fi
  status_line "Stable root" "INFO" "$stable_root"
  status_line "Model" "INFO" "releases/<ver> + current symlink (rollback-capable)"
  status_line "Checksum gate" "OK" "whole-tree sha256sum -c required"

  if toolkit_update_uses_mutable_branch; then
    # Mutable branch channels (main/beta): no signed release bundle exists;
    # assemble the tree from checksum-gated raw files.
    local mutable_branch
    mutable_branch="$(toolkit_update_branch_name 2>/dev/null || printf 'main\n')"
    release_base="${TOOLKIT_RELEASE_REPO}/${mutable_branch}"
    tree="${workdir}/tree"
    mkdir -p "${tree}/lib"
    status_line "Channel" "INFO" "${mutable_branch} (raw files, unsigned beta/testing channel) → releases/${version}"

    log "Downloading SHA256SUMS"
    curl -fsSL "${release_base}/SHA256SUMS" -o "${tree}/SHA256SUMS" || fail "Failed to download SHA256SUMS from ${mutable_branch}."
    checksum_file="${tree}/SHA256SUMS"

    log "Downloading erpnext-dev.sh"
    curl -fsSL "${release_base}/erpnext-dev.sh" -o "${tree}/erpnext-dev.sh" || fail "Failed to download erpnext-dev.sh from ${mutable_branch}."
    verify_release_file_checksum "$checksum_file" "erpnext-dev.sh" "${tree}/erpnext-dev.sh"

    while IFS= read -r lib_file; do
      [[ -n "$lib_file" ]] || continue
      curl -fsSL "${release_base}/lib/${lib_file}" -o "${tree}/lib/${lib_file}" || fail "Failed to download lib/${lib_file} from main."
      verify_release_file_checksum "$checksum_file" "lib/${lib_file}" "${tree}/lib/${lib_file}"
    done < <(toolkit_release_lib_files)
  else
    # tag channel: download the signed, self-contained release bundle.
    command -v tar >/dev/null 2>&1 || fail "tar is required to extract the release bundle."
    release_base="${TOOLKIT_RELEASE_GITHUB}/releases/download/${version}"
    status_line "Channel" "INFO" "tag ${version} (signed bundle)"

    log "Downloading release bundle erpnext-dev-${version}.tar.gz"
    curl -fsSL "${release_base}/erpnext-dev-${version}.tar.gz" -o "${workdir}/bundle.tar.gz" \
      || fail "Failed to download release bundle for ${version}. Does the release exist?"

    log "Extracting bundle"
    tar -C "$workdir" -xzf "${workdir}/bundle.tar.gz" || fail "Failed to extract the release bundle."
    tree="${workdir}/erpnext-dev-${version}"
    [[ -d "$tree" && -f "${tree}/erpnext-dev.sh" && -f "${tree}/SHA256SUMS" ]] \
      || fail "Release bundle layout unexpected; missing erpnext-dev.sh or SHA256SUMS."

    log "Verifying whole-tree checksums"
    ( cd "$tree" && sha256sum -c SHA256SUMS >/dev/null ) || fail "Checksum verification failed for the ${version} bundle."
    status_line "Checksums" "OK" "every packaged file matches SHA256SUMS"

    command -v gpg >/dev/null 2>&1 || fail "gpg is required for stable release updates. Install gnupg (Ubuntu: sudo apt-get install -y gnupg)."
    status_line "Signature gate" "INFO" "SHA256SUMS.asc + pinned maintainer fingerprint required"

    toolkit_verify_staged_signature "$tree" || fail "Refusing to install a release with an invalid or untrusted signature."
  fi

  bash -n "${tree}/erpnext-dev.sh" || fail "Downloaded toolkit failed bash syntax validation."
  chmod 755 "${tree}/erpnext-dev.sh" 2>/dev/null || true

  # Promote the verified tree into releases/<ver> (atomic rename, same fs).
  new_release="${releases_dir}/${version}"
  rm -rf "$new_release"
  mv -T "$tree" "$new_release" || fail "Could not move the verified tree into ${new_release}."
  chown -R root:root "$new_release" 2>/dev/null || true

  # Remember what we are replacing so rollback can restore it.
  if [[ -L "$(toolkit_current_link)" ]]; then
    current_target="$(readlink "$(toolkit_current_link)" 2>/dev/null || true)"
    prev_version="$(basename "$current_target" 2>/dev/null || true)"
  else
    prev_version=""
  fi

  # Atomic switchover.
  toolkit_point_current "releases/${version}" || fail "Could not switch the current symlink."
  toolkit_link_into_current

  if [[ -n "$prev_version" && "$prev_version" != "$version" ]]; then
    printf '%s\n' "$prev_version" > "${releases_dir}/.previous"
  fi

  rm -rf "$workdir"
  toolkit_prune_releases "$TOOLKIT_RELEASES_KEEP"

  install_toolkit_cli_entry || warn "Updated toolkit, but could not recreate ${TOOLKIT_CLI_PATH}. Run: $(toolkit_cmd install-cli)"

  ok "Toolkit updated to ${version} (atomic). Previous release kept for rollback."
  if [[ -n "$prev_version" && "$prev_version" != "$version" ]]; then
    echo "  Roll back with: $(toolkit_cmd toolkit-rollback)"
  fi
  "$(toolkit_current_link)/erpnext-dev.sh" version || true
  ui_box_end
}

# Roll the `current` symlink back to the previously installed release. Optional
# TOOLKIT_ROLLBACK_VERSION overrides the recorded previous version.
rollback_toolkit() {
  require_sudo

  local stable_root releases_dir target target_dir
  stable_root="$(toolkit_stable_root)"
  releases_dir="${stable_root}/releases"

  target="${TOOLKIT_ROLLBACK_VERSION:-}"
  if [[ -z "$target" ]]; then
    target="$(cat "${releases_dir}/.previous" 2>/dev/null || true)"
  fi

  ui_box_start "Roll Back ERPNext Toolkit"
  if [[ -z "$target" ]]; then
    err "No previous release recorded. Set TOOLKIT_ROLLBACK_VERSION=vX.Y.Z to pick one."
    echo "Available releases:"
    local rel found=0
    for rel in "${releases_dir}"/v*/; do
      [[ -d "$rel" ]] || continue
      echo "  $(basename "$rel")"
      found=1
    done
    (( found )) || echo "  (none)"
    ui_box_end
    return 1
  fi

  [[ "$target" == v* ]] || target="v${target}"
  target_dir="${releases_dir}/${target}"
  if [[ ! -d "$target_dir" || ! -f "${target_dir}/erpnext-dev.sh" ]]; then
    err "Release ${target} is not present under ${releases_dir}."
    ui_box_end
    return 1
  fi

  status_line "Rolling back to" "INFO" "$target"
  toolkit_point_current "releases/${target}" || { err "Could not switch the current symlink."; ui_box_end; return 1; }
  toolkit_link_into_current
  install_toolkit_cli_entry || warn "Rolled back, but could not recreate ${TOOLKIT_CLI_PATH}."

  ok "Rolled back to ${target}."
  "$(toolkit_current_link)/erpnext-dev.sh" version || true
  ui_box_end
}

prompt_production_credential_handoff_if_needed() {
  local cred_file reply

  is_public_vm_workflow || return 0

  cred_file="$(credentials_file_path)"
  path_is_file "$cred_file" || return 0

  echo
  echo "============================================================"
  echo "Production Credential Handoff"
  echo "============================================================"
  warn "Plaintext credentials remain on this VM at ${cred_file}."
  echo
  echo "Before treating this system as production-ready:"
  echo "  1. Save credentials in a password manager or secure handoff vault."
  echo "  2. Run: $(toolkit_cmd credentials-secure)"
  echo "  3. Remove the local plaintext file: $(toolkit_cmd credentials-delete)"
  echo
  echo "The toolkit never prints passwords in support bundles or shared logs."
  echo "============================================================"

  if [[ ! -t 0 || "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi

  if ! confirm "Have you saved the credentials outside this VM?"; then
    warn "Complete credential handoff before go-live. Run: $(toolkit_cmd credentials-info)"
    return 0
  fi

  echo
  warn "Optional: remove the local plaintext credentials file now."
  echo "This does not change the ERPNext Administrator password."
  read -r -p "Type DELETE to remove ${cred_file} now: " reply || reply=""
  if [[ "$reply" == "DELETE" ]]; then
    credentials_delete
  else
    echo "Skipped deletion. Remove the file before external handoff: $(toolkit_cmd credentials-delete)"
  fi
}

security_audit_sshd_setting() {
  local key="$1"
  local file="$2"
  awk -v k="$key" '
    $1 ~ /^[[:space:]]*#/ { next }
    $1 == k { print $2; found=1; exit }
    END { if (!found) exit 1 }
  ' "$file" 2>/dev/null
}

run_security_audit() {
  require_sudo

  local cred_file sshd_config root_login password_auth ufw_detail
  local ssl_pair ssl_state ssl_detail pending_upgrades

  ui_box_start "ERPNext VM Security Audit"
  status_line "Mode" "INFO" "read-only checks; no changes applied automatically"
  status_line "Environment" "INFO" "$(security_environment_label 2>/dev/null || echo unknown)"

  cred_file="$(credentials_file_path)"
  if path_is_file "$cred_file"; then
    status_line "Credentials file" "WARN" "plaintext file still present at ${cred_file}"
    echo "  Recommended: $(toolkit_cmd credentials-delete) after password-manager handoff"
  else
    status_line "Credentials file" "OK" "no plaintext credentials file detected"
  fi

  sshd_config="/etc/ssh/sshd_config"
  if [[ -r "$sshd_config" ]]; then
    root_login="$(security_audit_sshd_setting PermitRootLogin "$sshd_config" 2>/dev/null || echo unknown)"
    password_auth="$(security_audit_sshd_setting PasswordAuthentication "$sshd_config" 2>/dev/null || echo unknown)"
    if [[ "$root_login" == "no" || "$root_login" == "prohibit-password" ]]; then
      status_line "SSH PermitRootLogin" "OK" "$root_login"
    else
      status_line "SSH PermitRootLogin" "WARN" "${root_login:-not set}; prefer no or prohibit-password"
    fi
    if [[ "$password_auth" == "no" ]]; then
      status_line "SSH PasswordAuthentication" "OK" "disabled"
    else
      status_line "SSH PasswordAuthentication" "WARN" "${password_auth:-enabled or unset}; prefer key-based SSH"
    fi
  else
    status_line "SSH config" "INFO" "${sshd_config} not readable"
  fi

  if ufw_is_active; then
    ufw_detail="$(ufw status 2>/dev/null | head -n 1 | sed 's/^Status: //' || echo active)"
    status_line "UFW firewall" "OK" "$ufw_detail"
  else
    status_line "UFW firewall" "WARN" "inactive; run $(toolkit_cmd security-hardening-wizard)"
  fi

  if command -v fail2ban-client >/dev/null 2>&1 && systemctl is-active --quiet fail2ban 2>/dev/null; then
    status_line "Fail2Ban" "OK" "active"
  else
    status_line "Fail2Ban" "WARN" "not active; run $(toolkit_cmd configure-fail2ban)"
  fi

  if port_listens 22; then
    status_line "SSH port 22" "INFO" "listening (expected for admin access)"
  fi
  if deployment_engine_is_docker; then
    if docker_is_production; then
      if docker_production_exposure >/dev/null 2>&1; then
        status_line "Docker exposure" "OK" "Compose bindings match the production policy"
      else
        status_line "Docker exposure" "WARN" "run $(toolkit_cmd docker-production-exposure)"
      fi
    elif docker_local_firewall_filter_status; then
      status_line "Docker port ${DOCKER_PUBLISH_PORT}" "OK" "private-source DOCKER-USER filter active"
    else
      status_line "Docker port ${DOCKER_PUBLISH_PORT}" "WARN" "Docker-aware forwarding filter not confirmed"
    fi
  else
    if port_listens 8000; then
      if is_public_vm_workflow; then
        status_line "Bench port 8000" "WARN" "listening; should be blocked externally on production"
      else
        status_line "Bench port 8000" "INFO" "listening"
      fi
    else
      status_line "Bench port 8000" "INFO" "not listening"
    fi
  fi
  if port_listens 443; then
    status_line "HTTPS port 443" "OK" "listening"
  else
    status_line "HTTPS port 443" "INFO" "not listening"
  fi

  if deployment_engine_is_docker; then
    if docker_is_production && docker_https_enabled; then
      ssl_state="OK"
      ssl_detail="Docker $(docker_https_mode) via Traefik for $(docker_public_domain)"
    elif docker_is_production; then
      ssl_state="WARN"
      ssl_detail="Docker production HTTPS not configured"
    elif declare -F local_ssl_is_configured >/dev/null 2>&1 && local_ssl_is_configured; then
      ssl_state="OK"
      ssl_detail="local Docker HTTPS via host Nginx"
    else
      ssl_state="INFO"
      ssl_detail="local Docker HTTPS not configured"
    fi
  else
    ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not configured')"
    ssl_state="${ssl_pair%%|*}"
    ssl_detail="${ssl_pair#*|}"
  fi
  status_line "Production HTTPS" "$ssl_state" "$ssl_detail"

  if [[ -f /var/run/reboot-required ]]; then
    status_line "Reboot required" "WARN" "$(cat /var/run/reboot-required 2>/dev/null | head -n 1 || echo yes)"
  else
    status_line "Reboot required" "OK" "no"
  fi

  if command -v apt-get >/dev/null 2>&1; then
    pending_upgrades="$(apt-get -s upgrade 2>/dev/null | awk '/^Inst / { c++ } END { print c+0 }')"
    if [[ "${pending_upgrades:-0}" -gt 0 ]]; then
      status_line "Pending apt upgrades" "WARN" "${pending_upgrades} package(s)"
    else
      status_line "Pending apt upgrades" "OK" "none reported"
    fi
  fi

  if dpkg -l unattended-upgrades 2>/dev/null | awk '$2=="unattended-upgrades" && $1=="ii" { found=1 } END { exit !found }'; then
    status_line "Unattended upgrades" "OK" "package installed"
  else
    status_line "Unattended upgrades" "INFO" "unattended-upgrades not installed"
  fi

  echo
  echo "Recommended follow-up commands:"
  echo "  $(toolkit_cmd firewall-hardening-status)"
  echo "  $(toolkit_cmd fail2ban-status)"
  if deployment_engine_is_docker; then
    echo "  $(toolkit_cmd docker-https-status)"
    echo "  $(toolkit_cmd docker-production-exposure)"
  else
    echo "  $(toolkit_cmd production-ssl-status)"
  fi
  echo "  $(toolkit_cmd credentials-file-status)"
  echo "  $(toolkit_cmd verify-toolkit)"
  echo "  $(toolkit_cmd support-bundle-audit)"
  ui_box_end
}

# Locate the maintainer public key bundled with the toolkit.
find_toolkit_pubkey_file() {
  local active_dir stable_dir candidate
  active_dir="$(dirname "${ERPNEXT_DEV_ENTRY_SCRIPT:-${BASH_SOURCE[0]}}")"
  stable_dir="$(dirname "${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}")"
  for candidate in \
    "./docs/erpnext-dev-signing-key.asc" \
    "${active_dir}/docs/erpnext-dev-signing-key.asc" \
    "${active_dir}/erpnext-dev-signing-key.asc" \
    "${stable_dir}/docs/erpnext-dev-signing-key.asc" \
    "/opt/erpnext-dev/docs/erpnext-dev-signing-key.asc"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

# Locate the detached signature that accompanies SHA256SUMS. Release artifacts
# publish SHA256SUMS.asc next to SHA256SUMS; operators download both.
find_toolkit_signature_file() {
  local checksum_file active_dir stable_dir candidate
  checksum_file="$(find_toolkit_checksum_file 2>/dev/null || true)"
  active_dir="$(dirname "${ERPNEXT_DEV_ENTRY_SCRIPT:-${BASH_SOURCE[0]}}")"
  stable_dir="$(dirname "${INSTALLER_CANONICAL_PATH:-/opt/erpnext-dev/erpnext-dev.sh}")"

  for candidate in \
    "${TOOLKIT_SIGNATURE_FILE:-}" \
    "${checksum_file:+${checksum_file}.asc}" \
    "./SHA256SUMS.asc" \
    "${active_dir}/SHA256SUMS.asc" \
    "${stable_dir}/SHA256SUMS.asc" \
    "/opt/erpnext-dev/SHA256SUMS.asc"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

# Verify the GPG signature over SHA256SUMS.
#
# Optional configuration:
#   TOOLKIT_SIGNING_PUBKEY          path or https URL to the maintainer public key (.asc)
#   TOOLKIT_SIGNING_KEY_FINGERPRINT expected primary-key fingerprint to pin identity
#   TOOLKIT_SIGNATURE_FILE          explicit path to SHA256SUMS.asc
#
# Verification runs in a throwaway keyring so it never mutates the operator's
# GnuPG state. This complements verify-toolkit (which proves file integrity):
# the signature proves the checksums themselves came from the maintainer.
verify_toolkit_signature() {
  local checksum_file signature_file pubkey gnupg_home verify_out rc=0

  if ! command -v gpg >/dev/null 2>&1; then
    fail "gpg is not installed. Install gnupg to verify release signatures (Ubuntu: sudo apt-get install -y gnupg)."
  fi

  checksum_file="$(find_toolkit_checksum_file 2>/dev/null || true)"
  [[ -n "$checksum_file" ]] || fail "Could not find SHA256SUMS to verify. Download it alongside the toolkit."

  signature_file="$(find_toolkit_signature_file 2>/dev/null || true)"
  if [[ -z "$signature_file" ]]; then
    warn "No SHA256SUMS.asc signature found next to ${checksum_file}."
    echo "Signed releases attach SHA256SUMS.asc to the GitHub release. Download it and re-run,"
    echo "or set TOOLKIT_SIGNATURE_FILE=/path/to/SHA256SUMS.asc."
    return 1
  fi

  pubkey="${TOOLKIT_SIGNING_PUBKEY:-}"
  if [[ -z "$pubkey" ]]; then
    pubkey="$(find_toolkit_pubkey_file 2>/dev/null || true)"
  fi
  if [[ -z "$pubkey" ]]; then
    warn "No signing public key found."
    echo "Set TOOLKIT_SIGNING_PUBKEY to the maintainer public key (path or https URL),"
    echo "or run from a checkout that ships docs/erpnext-dev-signing-key.asc. See SECURITY.md."
    return 1
  fi

  gnupg_home="$(mktemp -d /tmp/erpnext-dev-gpg.XXXXXX)" || fail "Could not create temporary keyring."
  # shellcheck disable=SC2064
  trap "rm -rf '$gnupg_home'" RETURN
  chmod 700 "$gnupg_home"

  ui_box_start "Verify Release Signature"
  status_line "Checksums" "INFO" "$checksum_file"
  status_line "Signature" "INFO" "$signature_file"

  local pubkey_file=""
  if [[ "$pubkey" =~ ^https:// ]]; then
    pubkey_file="${gnupg_home}/imported.pub.asc"
    if ! curl -fsSL "$pubkey" >"$pubkey_file"; then
      status_line "Public key" "FAIL" "could not download key from ${pubkey}"
      ui_box_end
      return 1
    fi
  elif [[ -f "$pubkey" ]]; then
    pubkey_file="$pubkey"
  else
    status_line "Public key" "FAIL" "not a readable file or https URL: ${pubkey}"
    ui_box_end
    return 1
  fi
  status_line "Public key" "OK" "resolved for verification"

  if ! toolkit_gpg_verify_signature_files "$checksum_file" "$signature_file" "$pubkey_file"; then
    status_line "Signature" "FAIL" "verification or fingerprint pin failed"
    ui_box_end
    return 1
  fi
  status_line "Signature" "OK" "GOOD signature over SHA256SUMS"
  status_line "Key fingerprint" "OK" "matches pinned maintainer fingerprint"

  ok "Release signature verified."
  echo "Next: $(toolkit_cmd verify-toolkit) confirms the installed files match these signed checksums."
  ui_box_end
  return "$rc"
}
