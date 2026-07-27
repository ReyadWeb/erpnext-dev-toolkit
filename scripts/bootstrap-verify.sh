#!/usr/bin/env bash
# Download and verify a release completely before any toolkit code runs with sudo.
set -Eeuo pipefail

REPO="${ERPNEXT_BOOTSTRAP_REPO:-ReyadWeb/erpnext-dev-toolkit}"
PINNED_FINGERPRINT="BFC10C79427CF73496EA6F5A30BFD17DD559C8B6"

fail() { echo "FAIL: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "required system command is unavailable: $1"; }
usage() { echo "Usage: $0 vX.Y.Z [destination-directory]" >&2; }

tag="${1:-}"
destination="${2:-$PWD}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(beta|rc)\.[1-9][0-9]*|-unsigned)?$ ]] || { usage; exit 2; }
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"

for cmd in curl gpg awk grep sha256sum tar mktemp python3; do need "$cmd"; done

base="https://github.com/${REPO}/releases/download/${tag}"
archive="erpnext-dev-${tag}.tar.gz"
inventory="RELEASE-ASSETS.sha256"
signature="RELEASE-ASSETS.sha256.asc"
key="erpnext-dev-signing-key.asc"
work="$(mktemp -d /tmp/erpnext-dev-bootstrap.XXXXXX)"
gpg_home="$(mktemp -d /tmp/erpnext-dev-bootstrap-gpg.XXXXXX)"
cleanup() { rm -rf "$work" "$gpg_home"; }
trap cleanup EXIT
chmod 700 "$gpg_home"

for name in "$inventory" "$signature" "$key"; do
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "${work}/${name}" "${base}/${name}"
done

actual_fpr="$(gpg --batch --with-colons --show-keys "${work}/${key}" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')"
[[ "$actual_fpr" == "$PINNED_FINGERPRINT" ]] || fail "signing-key fingerprint mismatch"
GNUPGHOME="$gpg_home" gpg --batch --quiet --import "${work}/${key}"
GNUPGHOME="$gpg_home" gpg --batch --verify "${work}/${signature}" "${work}/${inventory}"

grep -Eq "^[0-9a-f]{64}  ${archive//./\\.}$" "${work}/${inventory}" \
  || fail "archive is absent from signed release-asset inventory"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --output "${work}/${archive}" "${base}/${archive}"
(
  cd "$work"
  grep -E "^[0-9a-f]{64}  ${archive//./\\.}$" "$inventory" | sha256sum -c -
)

python3 - "${work}/${archive}" <<'PY'
import sys, tarfile
p=sys.argv[1]
with tarfile.open(p, "r:gz") as tf:
    for m in tf.getmembers():
        n=m.name
        if n.startswith("/") or any(part == ".." for part in n.split("/")):
            raise SystemExit(f"FAIL: unsafe archive path: {n}")
        if m.issym() or m.islnk():
            raise SystemExit(f"FAIL: archive links are not allowed: {n}")
PY

tar --no-same-owner --no-same-permissions -xzf "${work}/${archive}" -C "$destination"
root="${destination}/erpnext-dev-${tag}"
[[ -d "$root" ]] || fail "archive did not create expected directory: ${root}"
(
  cd "$root"
  sha256sum -c SHA256SUMS
  scripts/build-info.sh verify \
    --root . \
    --archive "$archive" \
    --expected-tag "$tag" \
    --expected-channel "$(scripts/release-version.sh channel-for-tag "$tag")"
)

cat <<EOF_OK
OK: release ${tag} passed pre-privilege verification.
Verified directory: ${root}

Review the extracted files, then run the required toolkit command explicitly, for example:
  cd '${root}'
  sudo ./erpnext-dev.sh local-dev-quickstart
EOF_OK
