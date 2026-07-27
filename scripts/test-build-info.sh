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

pass() {
  echo "OK: $*"
}

work="$(mktemp -d /tmp/erpnext-dev-build-info-test.XXXXXX)"
trap 'rm -rf "$work"' EXIT
source_root="${work}/source"
stage_root="${work}/stage"
mkdir -p "${source_root}/scripts"

cp scripts/build-info.sh scripts/release-version.sh "${source_root}/scripts/"
chmod +x "${source_root}/scripts/"*.sh
printf '%s\n' '1.20.1' >"${source_root}/VERSION"
cat >"${source_root}/erpnext-dev.sh" <<'EOF_ENTRY'
#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  version) printf 'ERPNext Developer Toolkit v%s\n' "$(tr -d '[:space:]' <"${root}/VERSION")" ;;
  *) exit 2 ;;
esac
EOF_ENTRY
chmod +x "${source_root}/erpnext-dev.sh"
printf '%s\n' 'payload' >"${source_root}/payload.txt"
(
  cd "$source_root"
  sha256sum VERSION erpnext-dev.sh payload.txt scripts/build-info.sh scripts/release-version.sh >SHA256SUMS
  git init -q -b main
  git config user.name "Build Info Test"
  git config user.email "build-info@example.invalid"
  git add .
  git commit -qm "build-info fixture"
)
commit="$(git -C "$source_root" rev-parse HEAD)"

prepare_stage() {
  rm -rf "$stage_root"
  mkdir -p "${stage_root}/scripts"
  cp "${source_root}/VERSION" "${source_root}/erpnext-dev.sh" \
    "${source_root}/payload.txt" "${source_root}/SHA256SUMS" "$stage_root/"
  cp "${source_root}/scripts/build-info.sh" \
    "${source_root}/scripts/release-version.sh" "${stage_root}/scripts/"
}

run_build_info() {
  "${source_root}/scripts/build-info.sh" "$@"
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "${label} was accepted"
  fi
  pass "$label is rejected"
}

run_build_info assert-source-clean --root "$source_root" >/dev/null
[[ "$(run_build_info artifact-label --root "$source_root")" == "v1.20.1-development" ]] \
  || fail "development artifact label was incorrect"

prepare_stage
run_build_info generate \
  --source-root "$source_root" \
  --stage-root "$stage_root" \
  --archive erpnext-dev-v1.20.1-development.tar.gz \
  --channel development \
  --commit "$commit" \
  --built-at 2026-07-27T00:00:00Z >/dev/null
run_build_info verify \
  --root "$stage_root" \
  --archive erpnext-dev-v1.20.1-development.tar.gz \
  --expected-channel development \
  --expected-commit "$commit" >/dev/null
[[ "$(run_build_info field project_version --root "$stage_root")" == "1.20.1" ]] \
  || fail "project_version field was incorrect"
[[ "$(run_build_info field tag --root "$stage_root")" == "" ]] \
  || fail "development metadata claimed a release tag"
pass "development build metadata"

cp "${stage_root}/BUILD-INFO.json" "${work}/good.json"
python3 - "$stage_root" <<'PY_VERSION_TAMPER'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1]) / "BUILD-INFO.json"
data = json.loads(path.read_text())
data["project_version"] = "1.20.2"
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY_VERSION_TAMPER
expect_failure "mismatched project version" run_build_info verify --root "$stage_root" --metadata-only
cp "${work}/good.json" "${stage_root}/BUILD-INFO.json"

python3 - "$stage_root" <<'PY_DIGEST_TAMPER'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1]) / "BUILD-INFO.json"
data = json.loads(path.read_text())
data["tree_digest"] = "0" * 64
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY_DIGEST_TAMPER
expect_failure "mismatched tree digest" run_build_info verify --root "$stage_root" --metadata-only
cp "${work}/good.json" "${stage_root}/BUILD-INFO.json"

printf '%s\n' 'tamper' >>"${stage_root}/payload.txt"
expect_failure "tampered payload" run_build_info verify --root "$stage_root"
printf '%s\n' 'payload' >"${stage_root}/payload.txt"

python3 - "$stage_root" <<'PY_EXTRA_KEY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1]) / "BUILD-INFO.json"
data = json.loads(path.read_text())
data["unexpected"] = True
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY_EXTRA_KEY
expect_failure "unexpected metadata field" run_build_info verify --root "$stage_root" --metadata-only
cp "${work}/good.json" "${stage_root}/BUILD-INFO.json"

cp "${work}/good.json" "${source_root}/BUILD-INFO.json"
expect_failure "generated metadata in source tree" run_build_info assert-source-clean --root "$source_root"
rm -f "${source_root}/BUILD-INFO.json"

(
  cd "$source_root"
  git tag v1.20.1-beta.1
)
[[ "$(run_build_info artifact-label --root "$source_root")" == "v1.20.1-beta.1" ]] \
  || fail "beta artifact label was incorrect"
prepare_stage
run_build_info generate \
  --source-root "$source_root" \
  --stage-root "$stage_root" \
  --archive erpnext-dev-v1.20.1-beta.1.tar.gz \
  --tag v1.20.1-beta.1 \
  --channel beta \
  --commit "$commit" \
  --built-at 2026-07-27T00:00:00Z >/dev/null
run_build_info verify \
  --root "$stage_root" \
  --archive erpnext-dev-v1.20.1-beta.1.tar.gz \
  --expected-tag v1.20.1-beta.1 \
  --expected-channel beta \
  --expected-commit "$commit" >/dev/null
pass "beta build metadata"

expect_failure "beta metadata with stable archive" run_build_info verify \
  --root "$stage_root" \
  --archive erpnext-dev-v1.20.1.tar.gz \
  --metadata-only

(
  cd "$source_root"
  git tag -d v1.20.1-beta.1 >/dev/null
  git tag v1.20.1
)
[[ "$(run_build_info artifact-label --root "$source_root")" == "v1.20.1" ]] \
  || fail "stable artifact label was incorrect"

echo "build-info tests: all checks passed"
