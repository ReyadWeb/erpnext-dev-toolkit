#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ERPNEXT_RELEASE_CHANNEL=beta \
  ERPNEXT_RELEASE_TAG=v1.20.1-beta.1 \
  scripts/test-release-version.sh >/dev/null \
  || fail "release-version tests were influenced by inherited pre-tag context"

tmp_dir="$(mktemp -d /tmp/erpnext-dev-pretag-test.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="${tmp_dir}/fixture"
mkdir -p "${fixture}/scripts"

cp scripts/release-version.sh "${fixture}/scripts/"
cp scripts/build-info.sh "${fixture}/scripts/"
cp scripts/release-pretag-check.sh "${fixture}/scripts/"

for helper in \
  validate-release.sh \
  check-release-artifact-consistency.sh; do
  cat >"${fixture}/scripts/${helper}" <<'EOF_PASS'
#!/usr/bin/env bash
exit 0
EOF_PASS
done

cat >"${fixture}/scripts/build-release-bundle.sh" <<'EOF_BUILD'
#!/usr/bin/env bash
set -Eeuo pipefail

channel="$(scripts/release-version.sh channel)"
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
