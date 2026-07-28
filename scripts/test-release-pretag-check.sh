#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/release-test-env.sh
source "${ROOT_DIR}/scripts/release-test-env.sh"
release_test_env_reexec "$0" "$@"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d /tmp/erpnext-dev-pretag-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="${tmp_dir}/fixture"
mkdir -p "${fixture}/scripts"

cp scripts/release-version.sh "${fixture}/scripts/"
cp scripts/build-info.sh "${fixture}/scripts/"
cp scripts/release-pretag-check.sh "${fixture}/scripts/"

cat >"${fixture}/scripts/validate-release.sh" <<'EOF_VALIDATE'
#!/usr/bin/env bash
set -Eeuo pipefail

channel="${ERPNEXT_RELEASE_CHANNEL:-}"
tag="${ERPNEXT_RELEASE_TAG:-}"
phase="${ERPNEXT_RELEASE_PHASE:-}"

case "$channel" in
  stable)
    [[ "$tag" == "v1.20.0" ]] || exit 21
    [[ "$phase" == "stable-pretag" ]] || exit 22
    [[ "${RELEASE_STRICT:-0}" == "1" ]] || exit 23
    ;;
  beta)
    [[ "$tag" == "v1.20.0-beta.1" ]] || exit 24
    [[ -z "$phase" ]] || exit 25
    [[ "${RELEASE_STRICT:-0}" == "1" ]] || exit 26
    ;;
  *)
    exit 27
    ;;
esac
EOF_VALIDATE

cat >"${fixture}/scripts/check-release-artifact-consistency.sh" <<'EOF_PASS'
#!/usr/bin/env bash
exit 0
EOF_PASS

cat >"${fixture}/scripts/build-release-bundle.sh" <<'EOF_BUILD'
#!/usr/bin/env bash
set -Eeuo pipefail

channel="$(scripts/release-version.sh channel)"
phase="${ERPNEXT_RELEASE_PHASE:-}"

case "$channel" in
  stable)
    [[ "$phase" == "stable-pretag" ]] || exit 31
    ;;
  beta)
    [[ -z "$phase" ]] || exit 32
    ;;
esac
label="$(scripts/build-info.sh artifact-label)"
tag=""
[[ "$channel" == "development" ]] || tag="$(scripts/release-version.sh tag)"
stage="dist/erpnext-dev-${label}"
archive="erpnext-dev-${label}.tar.gz"
bundle="dist/${archive}"
commit="$(git rev-parse HEAD)"

rm -rf dist
mkdir -p "${stage}/scripts"

cp VERSION erpnext-dev.sh "${stage}/"
cp scripts/release-version.sh scripts/build-info.sh "${stage}/scripts/"

(
  cd "$stage"
  sha256sum VERSION erpnext-dev.sh scripts/release-version.sh scripts/build-info.sh >SHA256SUMS
)

args=(
  generate
  --source-root .
  --stage-root "$stage"
  --archive "$archive"
  --channel "$channel"
  --commit "$commit"
  --built-at 2026-07-27T00:00:00Z
)
[[ -z "$tag" ]] || args+=(--tag "$tag")
scripts/build-info.sh "${args[@]}" >/dev/null

tar -C dist -czf "$bundle" "erpnext-dev-${label}"
rm -rf "$stage"
EOF_BUILD

chmod +x "${fixture}/scripts/"*.sh

printf '%s\n' 'dist/' >"${fixture}/.gitignore"
printf '%s\n' '1.20.0-beta.1' >"${fixture}/VERSION"

cat >"${fixture}/erpnext-dev.sh" <<'EOF_ENTRY'
#!/usr/bin/env bash
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  version)
    printf 'ERPNext Developer Toolkit v%s\n' "$(tr -d '[:space:]' <"${root}/VERSION")"
    ;;
  verify-toolkit)
    echo "Active match                  OK"
    ;;
  *)
    exit 2
    ;;
esac
EOF_ENTRY

chmod +x "${fixture}/erpnext-dev.sh"

(
  cd "$fixture"
  git init -q
  git config user.name "Release Test"
  git config user.email "release-test@example.invalid"
  git add .
  git commit -qm "prerelease fixture"
  git switch -qc feature/v1.20-release-reliability
)

run_pretag() {
  ERPNEXT_RELEASE_ROOT="$fixture" \
    ERPNEXT_RELEASE_REMOTE_CHECK=0 \
    "${fixture}/scripts/release-pretag-check.sh" "$@"
}

run_pretag v1.20.0-beta.1 >/dev/null

(
  cd "$fixture"
  git switch -qc beta
)

run_pretag v1.20.0-beta.1 >/dev/null

(
  cd "$fixture"
  git switch -q feature/v1.20-release-reliability
)

if run_pretag v1.20.0-beta.2 >/dev/null 2>&1; then
  fail "mismatched tag was accepted"
fi

(
  cd "$fixture"
  git tag v1.20.0-beta.1
)

if run_pretag v1.20.0-beta.1 >/dev/null 2>&1; then
  fail "existing local tag was accepted"
fi

(
  cd "$fixture"
  git tag -d v1.20.0-beta.1 >/dev/null
)

printf '%s\n' 'dirty' >>"${fixture}/VERSION"
if run_pretag v1.20.0-beta.1 >/dev/null 2>&1; then
  fail "dirty working tree was accepted"
fi
(
  cd "$fixture"
  git reset --hard -q HEAD
)

python3 - "${fixture}" <<'PY_STABLE'
from pathlib import Path
import sys

root = Path(sys.argv[1])
(root / "VERSION").write_text("1.20.0\n")
PY_STABLE

(
  cd "$fixture"
  git add VERSION
  git commit -qm "stable fixture"
)

if run_pretag v1.20.0 >/dev/null 2>&1; then
  fail "stable tag from feature branch was accepted"
fi

(
  cd "$fixture"
  git switch -qc main
)

run_pretag v1.20.0 >/dev/null

echo "pre-tag validation tests: all checks passed"
