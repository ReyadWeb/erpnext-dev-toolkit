# shellcheck shell=bash
# Explicit, read-only external installation connections. No discovery or runtime probes.

connect_meta_file() { printf '%s.connection\n' "${CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/erpnext-dev-toolkit/config}"; }
connect_valid_atom() { [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; }
connect_valid_path() {
  local p="$1" parent
  [[ "$p" == /* && ! -L "$p" && -d "$p" ]] || return 1
  parent="$(dirname -- "$p")"
  [[ "$(realpath -e -- "$p" 2>/dev/null)" == "$p" ]] || return 1
  [[ ! -L "$parent" ]] || return 1
  [[ "$(stat -c %u -- "$p" 2>/dev/null)" =~ ^[0-9]+$ ]] || return 1
  [[ "$(stat -c %a -- "$p" 2>/dev/null)" =~ ^[0-7]{3,4}$ ]] || return 1
}
connect_write_atomic() {
  local file="$1" tmp
  mkdir -p -- "$(dirname -- "$file")" || return 1
  chmod 700 -- "$(dirname -- "$file")" 2>/dev/null || true
  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
  chmod 600 -- "$tmp"
  cat >"$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$file"
}
connect_existing() {
  local engine="$1" path="$2" project="$3" site="$4" file
  connect_valid_atom "$engine" && connect_valid_path "$path" && connect_valid_atom "$site" || return 2
  if [[ "$engine" == docker ]]; then connect_valid_atom "$project" || return 2; else [[ -z "$project" ]] || return 2; fi
  file="$(connect_meta_file)"
  if [[ -f "$file" ]] && cmp -s <(printf 'engine=%s\npath=%s\nproject=%s\nsite=%s\nmode=external\nmanaged=false\nreadonly=true\n' "$engine" "$path" "$project" "$site") "$file"; then return 0; fi
  connect_write_atomic "$file" <<EOF
engine=$engine
path=$path
project=$project
site=$site
mode=external
managed=false
readonly=true
EOF
}
connect_existing_disconnect() { local f; f="$(connect_meta_file)"; [[ ! -e "$f" || ! -L "$f" ]] || return 1; rm -f -- "$f"; }
connect_existing_preview() {
  local engine="$1" path="$2" project="$3" site="$4"
  connect_valid_atom "$engine" && connect_valid_path "$path" && connect_valid_atom "$site" || return 2
  [[ "$engine" == docker && "$project" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ || "$engine" == native && -z "$project" ]] || return 2
  if [[ "${DOCTOR_FORMAT:-human}" == json ]]; then
    printf '{"external":true,"unmanaged":true,"read_only":true,"engine":"%s","path":"%s","project":"%s","site":"%s","mutation":false}\n' "$engine" "$path" "$project" "$site"
  else
    printf 'External / Unmanaged / Read-only connection\nEngine: %s\nPath: %s\nProject: %s\nSite: %s\n' "$engine" "$path" "${project:-none}" "$site"
  fi
}
