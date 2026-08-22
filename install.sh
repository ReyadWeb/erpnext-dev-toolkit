#!/usr/bin/env bash
# Small public bootstrap for exact, signed ERPNext Developer Toolkit releases.
set -Eeuo pipefail

readonly INSTALLER_REPO="ReyadWeb/erpnext-dev-toolkit"
readonly INSTALLER_FINGERPRINT="BFC10C79427CF73496EA6F5A30BFD17DD559C8B6"
readonly INSTALLER_API="https://api.github.com/repos/${INSTALLER_REPO}"
readonly INSTALLER_RELEASES="https://github.com/${INSTALLER_REPO}/releases/download"
readonly INSTALLER_MAX_METADATA=1048576

CHANNEL=stable
CHANNEL_SET=0
EXACT_TAG=""
NO_START=0
ASSUME_YES=0
WORK=""
GPG_HOME=""

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}
usage() {
  cat <<'EOF'
Usage: install.sh [--stable|--beta] [--tag TAG] [--no-start] [--yes]

  --stable    Install a signed stable vX.Y.Z release (default)
  --beta      Install the newest signed vX.Y.Z-beta.N prerelease
  --tag TAG   Install this exact signed tag within the selected channel
  --no-start  Install/repair the Toolkit CLI without launching first-run
  --yes       Accept the beta warning and noninteractive bootstrap prompts
  --help      Show this help

Do not run this bootstrap with sudo. It verifies everything as your user and
requests sudo only for fixed prerequisites and verified Toolkit actions.
EOF
}
cleanup() {
  local item
  for item in "$WORK" "$GPG_HOME"; do
    [[ -n "$item" && "$item" == /tmp/erpnext-dev-one-command.* && -d "$item" && ! -L "$item" ]] || continue
    rm -rf -- "$item"
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tty_available() { { : </dev/tty >/dev/tty; } 2>/dev/null; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stable | --beta)
      ((CHANNEL_SET == 0)) || fail "channel option may be supplied only once"
      CHANNEL="${1#--}"
      CHANNEL_SET=1
      shift
      ;;
    --tag)
      [[ -z "$EXACT_TAG" ]] || fail "--tag may be supplied only once"
      shift
      (($# > 0)) || fail "--tag requires a value"
      EXACT_TAG="$1"
      shift
      ;;
    --tag=*)
      [[ -z "$EXACT_TAG" ]] || fail "--tag may be supplied only once"
      EXACT_TAG="${1#*=}"
      [[ -n "$EXACT_TAG" ]] || fail "--tag requires a value"
      shift
      ;;
    --no-start)
      ((NO_START == 0)) || fail "--no-start may be supplied only once"
      NO_START=1
      shift
      ;;
    --yes)
      ((ASSUME_YES == 0)) || fail "--yes may be supplied only once"
      ASSUME_YES=1
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *) fail "unknown option: $1" ;;
  esac
done

((EUID != 0)) || fail "refusing to run as root; run the public command without sudo"
case "$CHANNEL:$EXACT_TAG" in
  stable:"") ;;
  stable:v[0-9]*.[0-9]*.[0-9]*) [[ "$EXACT_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--tag does not match the stable channel" ;;
  beta:"") ;;
  beta:v[0-9]*.[0-9]*.[0-9]*-beta.*) [[ "$EXACT_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[1-9][0-9]*$ ]] || fail "--tag does not match the beta channel" ;;
  *) fail "--tag does not match the selected ${CHANNEL} channel" ;;
esac

if ((NO_START == 0)) && ! tty_available; then
  fail "first-run requires a usable /dev/tty; rerun from a terminal or use --no-start"
fi

missing_commands=()
for command_name in curl gpg awk grep sha256sum tar mktemp python3; do
  command -v "$command_name" >/dev/null 2>&1 || missing_commands+=("$command_name")
done
[[ -r /etc/ssl/certs/ca-certificates.crt ]] || missing_commands+=(ca-certificates)
if ((${#missing_commands[@]} > 0)); then
  printf 'Missing bootstrap prerequisites: %s\n' "${missing_commands[*]}" >&2
  distro_id=""
  distro_like=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091 # trusted operating-system identity file
    . /etc/os-release
    distro_id="${ID:-}"
    distro_like="${ID_LIKE:-}"
  fi
  if command -v apt-get >/dev/null 2>&1 \
    && [[ " $distro_id $distro_like " == *" debian "* || " $distro_id $distro_like " == *" ubuntu "* ]]; then
    printf 'Installing the fixed verification prerequisite allowlist.\n'
    sudo apt-get update
    sudo apt-get install --yes --no-install-recommends curl ca-certificates gnupg gawk grep coreutils tar python3
  else
    fail "install the missing commands on this supported Debian/Ubuntu host, then retry"
  fi
fi
for command_name in curl gpg awk grep sha256sum tar mktemp python3; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command remains unavailable: $command_name"
done
[[ -r /etc/ssl/certs/ca-certificates.crt ]] || fail "ca-certificates remains unavailable"

WORK="$(mktemp -d /tmp/erpnext-dev-one-command.XXXXXX)"
GPG_HOME="$(mktemp -d /tmp/erpnext-dev-one-command.gpg.XXXXXX)"
[[ -d "$WORK" && ! -L "$WORK" && -d "$GPG_HOME" && ! -L "$GPG_HOME" ]] || fail "unsafe temporary directory"
chmod 0700 "$WORK" "$GPG_HOME"
umask 077

approved_url() {
  [[ "$1" =~ ^https://(api\.github\.com|github\.com|release-assets\.githubusercontent\.com|objects\.githubusercontent\.com)/[^[:space:][:cntrl:]]+$ ]]
}
download() {
  local url="$1" output="$2" effective
  approved_url "$url" || fail "refusing unapproved download URL"
  [[ "$output" == "$WORK/"* && ! -e "$output" && ! -L "$output" ]] || fail "unsafe temporary download target"
  effective="$(curl --fail --silent --show-error --location --max-redirs 3 \
    --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 90 \
    --max-filesize "$INSTALLER_MAX_METADATA" --output "$output" \
    --write-out '%{url_effective}' "$url")" || fail "download failed"
  approved_url "$effective" || fail "download redirected to an unapproved host"
  [[ -f "$output" && ! -L "$output" ]] || fail "download did not create a regular file"
  chmod 0600 "$output"
}

metadata="$WORK/release.json"
if [[ -n "$EXACT_TAG" ]]; then
  download "${INSTALLER_API}/releases/tags/${EXACT_TAG}" "$metadata"
elif [[ "$CHANNEL" == stable ]]; then
  download "${INSTALLER_API}/releases/latest" "$metadata"
else
  download "${INSTALLER_API}/releases?per_page=100" "$metadata"
fi

TAG="$(
  python3 - "$CHANNEL" "$EXACT_TAG" "$metadata" "$INSTALLER_MAX_METADATA" <<'PY'
import json,os,re,sys
limit=int(sys.argv[4])
channel,exact,path=sys.argv[1:4]
if os.path.getsize(path) > limit:
    raise SystemExit("release metadata exceeds the size limit")
try:
    data=json.load(open(path,encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"invalid release metadata: {exc}")
stable=re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
beta=re.compile(r"^v(\d+)\.(\d+)\.(\d+)-beta\.([1-9]\d*)$")
items=data if isinstance(data,list) else [data]
valid=[]
for item in items:
    if not isinstance(item,dict): continue
    tag=item.get("tag_name","")
    pattern=stable if channel=="stable" else beta
    match=pattern.fullmatch(tag)
    if not match or item.get("draft") is not False: continue
    if channel=="stable" and item.get("prerelease") is not False: continue
    if channel=="beta" and item.get("prerelease") is not True: continue
    if tag.endswith("-unsigned"): continue
    valid.append((tuple(map(int,match.groups())),tag))
if exact:
    valid=[entry for entry in valid if entry[1]==exact]
if not valid:
    raise SystemExit(f"no signed-compatible published {channel} release metadata found")
print(max(valid)[1])
PY
)" || fail "could not resolve a valid published ${CHANNEL} release"

if [[ "$CHANNEL" == beta ]]; then
  cat >&2 <<EOF
WARNING: ${TAG} is prerelease software for disposable testing only.
It may be incomplete or destructive and never falls back to stable.
EOF
  if ((ASSUME_YES == 0)); then
    tty_available || fail "beta installation requires terminal confirmation or --yes"
    printf 'Type BETA to install this exact signed prerelease: ' >/dev/tty
    IFS= read -r beta_reply </dev/tty || fail "beta confirmation failed"
    [[ "$beta_reply" == BETA ]] || fail "beta installation cancelled"
  fi
fi

base="${INSTALLER_RELEASES}/${TAG}"
inventory="$WORK/RELEASE-ASSETS.sha256"
signature="$WORK/RELEASE-ASSETS.sha256.asc"
key="$WORK/erpnext-dev-signing-key.asc"
bootstrap="$WORK/bootstrap-verify.sh"
download "$base/RELEASE-ASSETS.sha256" "$inventory"
download "$base/RELEASE-ASSETS.sha256.asc" "$signature"
download "$base/erpnext-dev-signing-key.asc" "$key"

actual_fingerprint="$(gpg --batch --with-colons --show-keys "$key" 2>/dev/null | awk -F: '$1=="fpr" {print $10; exit}')"
[[ "$actual_fingerprint" == "$INSTALLER_FINGERPRINT" ]] || fail "signing-key fingerprint mismatch"
GNUPGHOME="$GPG_HOME" gpg --batch --quiet --import "$key"
GNUPGHOME="$GPG_HOME" gpg --batch --verify "$signature" "$inventory" \
  || fail "signed external asset inventory verification failed"
grep -Eq '^[0-9a-f]{64}  bootstrap-verify\.sh$' "$inventory" \
  || fail "bootstrap-verify.sh is absent from the signed inventory"
download "$base/bootstrap-verify.sh" "$bootstrap"
expected_bootstrap="$(awk '$2=="bootstrap-verify.sh" {print $1}' "$inventory")"
[[ "$expected_bootstrap" =~ ^[0-9a-f]{64}$ ]] || fail "invalid bootstrap digest in signed inventory"
actual_bootstrap="$(sha256sum "$bootstrap" | awk '{print $1}')"
[[ "$actual_bootstrap" == "$expected_bootstrap" ]] || fail "bootstrap-verify.sh checksum mismatch"

destination="$WORK/verified"
mkdir -m 0700 "$destination"
printf 'Verifying exact signed release %s...\n' "$TAG"
env -u ERPNEXT_BOOTSTRAP_REPO bash "$bootstrap" "$TAG" "$destination" \
  || fail "verified release bootstrap failed"
release_root="$destination/erpnext-dev-${TAG}"
[[ -d "$release_root" && ! -L "$release_root" && -x "$release_root/erpnext-dev.sh" ]] \
  || fail "verified bootstrap did not produce the expected release tree"

printf 'Installing verified release %s atomically...\n' "$TAG"
sudo env -u TOOLKIT_UPDATE_CHANNEL -u TOOLKIT_UPDATE_FROM_MAIN -u TOOLKIT_UPDATE_ALLOW_MUTABLE \
  -u TOOLKIT_RELEASE_REPO -u TOOLKIT_RELEASE_GITHUB -u TOOLKIT_SIGNING_KEY_FINGERPRINT \
  TOOLKIT_UPDATE_VERSION="$TAG" "$release_root/erpnext-dev.sh" update-toolkit \
  || fail "atomic Toolkit installation failed"
sudo erpnext-dev install-cli || fail "CLI installation or repair failed"

if ((NO_START == 0)); then
  printf 'Launching the verified setup wizard...\n'
  # shellcheck disable=SC2024 # redirects intentionally attach the invoking user's terminal
  sudo erpnext-dev first-run </dev/tty >/dev/tty || fail "first-run wizard failed"
else
  printf 'Toolkit %s installed; first-run was skipped by --no-start.\n' "$TAG"
fi
