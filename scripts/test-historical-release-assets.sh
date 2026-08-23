#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
work="$(mktemp -d /tmp/erpnext-historical-assets.XXXXXX)"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
remote="$work/remote.git"
bin="$work/bin"
mkdir -p "$bin"
git init --bare -q "$remote"
git init -q -b main "$repo"
cd "$repo"
git config user.name fixture
git config user.email fixture@example.invalid
git remote add origin "$remote"
mkdir -p scripts
cp "$ROOT/scripts/assert-github-release-assets.sh" scripts/
cp "$ROOT/scripts/release-manifest-files.sh" scripts/
chmod +x scripts/*.sh

cat >erpnext-dev.sh <<'EOF'
fixture
EOF
for f in SHA256SUMS RELEASE-MANIFEST.txt; do printf '%s\n' "$f" >"$f"; done
cat >RELEASE-MANIFEST.txt <<'EOF'
erpnext-dev.sh
SHA256SUMS
RELEASE-MANIFEST.txt
EOF
git add . && git commit -qm historical
git tag -a v1.20.4 -m historical
git push -q origin main v1.20.4

cat >install.sh <<'EOF'
fixture installer
EOF
cat >RELEASE-MANIFEST.txt <<'EOF'
erpnext-dev.sh
install.sh
SHA256SUMS
RELEASE-MANIFEST.txt
EOF
git add . && git commit -qm current
git tag -a v1.21.0-beta.1 -m current
git push -q origin main v1.21.0-beta.1
git tag v1.21.1
git push -q origin v1.21.1

cat >"$bin/gh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$*" in
  *".draft"*) echo false ;;
  *".prerelease"*) [[ "${GH_TAG:-}" == v1.20.4 ]] && echo false || echo true ;;
  *".assets | length"*) [[ "${GH_TAG:-}" == v1.20.4 ]] && echo 10 || echo 11 ;;
  *".assets[].name"*)
    printf '%s\n' "${GH_ASSETS:?}" ;;
  *"releases/latest"*) echo v1.20.4 ;;
  *) echo "unexpected gh request: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$bin/gh"
export PATH="$bin:$PATH" GH_TAG=v1.20.4
export GH_ASSETS=$'erpnext-dev-v1.20.4.tar.gz\nerpnext-dev-v1.20.4.BUILD-INFO.json\nSHA256SUMS\nerpnext-dev.sh\nRELEASE-MANIFEST.txt\nRELEASE-ASSETS.sha256\nerpnext-dev-signing-key.asc\nbootstrap-verify.sh\nSHA256SUMS.asc\nRELEASE-ASSETS.sha256.asc'
scripts/assert-github-release-assets.sh v1.20.4 --require-latest >/dev/null \
  || fail "historical 10-asset contract was rejected"

export GH_TAG=v1.21.0-beta.1
export GH_ASSETS=$'erpnext-dev-v1.21.0-beta.1.tar.gz\nerpnext-dev-v1.21.0-beta.1.BUILD-INFO.json\nSHA256SUMS\nerpnext-dev.sh\nRELEASE-MANIFEST.txt\nRELEASE-ASSETS.sha256\nerpnext-dev-signing-key.asc\nbootstrap-verify.sh\ninstall.sh\nSHA256SUMS.asc\nRELEASE-ASSETS.sha256.asc'
scripts/assert-github-release-assets.sh v1.21.0-beta.1 >/dev/null \
  || fail "current 11-asset contract was rejected"
export GH_ASSETS="${GH_ASSETS//$'\n'install.sh/}"
if scripts/assert-github-release-assets.sh v1.21.0-beta.1 >/dev/null 2>&1; then
  fail "current contract missing install.sh was accepted"
fi
if scripts/assert-github-release-assets.sh v1.21.1 >/dev/null 2>&1; then
  fail "lightweight tag was accepted"
fi

echo "historical release asset-contract tests: all checks passed"
