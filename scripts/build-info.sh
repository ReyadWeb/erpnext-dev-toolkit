#!/usr/bin/env bash
# Generate and verify immutable release-bundle identity metadata.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF_USAGE'
Usage:
  scripts/build-info.sh artifact-label [--root PATH]
  scripts/build-info.sh payload-digest [--root PATH]
  scripts/build-info.sh assert-source-clean [--root PATH]
  scripts/build-info.sh field FIELD [--root PATH]
  scripts/build-info.sh generate --source-root PATH --stage-root PATH \
    --archive NAME [--tag TAG] [--channel CHANNEL] [--commit SHA] [--built-at UTC]
  scripts/build-info.sh verify [--root PATH] [--metadata-only] \
    [--archive NAME] [--expected-tag TAG] [--expected-channel CHANNEL] \
    [--expected-commit SHA]
EOF_USAGE
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

canonical_root() {
  local root="$1"
  [[ -d "$root" ]] || fail "root directory does not exist: ${root}"
  (cd "$root" && pwd)
}

read_version() {
  local root="$1" version_file line_count version
  version_file="${root}/VERSION"
  [[ -f "$version_file" ]] || fail "VERSION is missing: ${version_file}"
  line_count="$(awk 'NF { count++ } END { print count + 0 }' "$version_file")"
  [[ "$line_count" == "1" ]] || fail "VERSION must contain exactly one non-empty line"
  version="$(awk 'NF { print; exit }' "$version_file")"
  version="${version#"${version%%[![:space:]]*}"}"
  version="${version%"${version##*[![:space:]]}"}"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] \
    || fail "invalid project version: ${version}"
  printf '%s\n' "$version"
}

payload_digest() {
  local root="$1" sums
  sums="${root}/SHA256SUMS"
  [[ -f "$sums" ]] || fail "SHA256SUMS is missing: ${sums}"
  sha256sum "$sums" | awk '{print $1}'
}

resolve_commit() {
  local source_root="$1" explicit="$2" commit
  if [[ -n "$explicit" ]]; then
    commit="$explicit"
  else
    [[ -d "${source_root}/.git" ]] \
      || fail "exact commit identity requires a Git working tree or --commit"
    commit="$(git -C "$source_root" rev-parse HEAD)"
  fi
  [[ "$commit" =~ ^[0-9a-fA-F]{40,64}$ ]] || fail "invalid commit identity: ${commit}"
  printf '%s\n' "${commit,,}"
}

resolve_built_at() {
  local explicit="$1"
  if [[ -n "$explicit" ]]; then
    [[ "$explicit" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
      || fail "built_at must use UTC RFC3339 form YYYY-MM-DDTHH:MM:SSZ"
    printf '%s\n' "$explicit"
    return 0
  fi

  if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
    [[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || fail "SOURCE_DATE_EPOCH must be an integer"
    date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ'
  else
    date -u '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

channel_for_tag() {
  local tag="$1"
  if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[1-9][0-9]*$ ]]; then
    printf '%s\n' beta
  elif [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[1-9][0-9]*$ ]]; then
    printf '%s\n' rc
  elif [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' stable
  else
    return 1
  fi
}

validate_channel_tag() {
  local version="$1" channel="$2" tag="$3" base expected
  base="${version%%-*}"
  case "$channel" in
    development)
      [[ -z "$tag" ]] || fail "development build metadata must not claim a release tag"
      ;;
    beta | rc | stable)
      [[ -n "$tag" ]] || fail "${channel} build metadata requires an exact release tag"
      expected="$(channel_for_tag "$tag" 2>/dev/null || true)"
      [[ "$expected" == "$channel" ]] \
        || fail "tag ${tag} does not represent channel ${channel}"
      [[ "$tag" == "v${base}" || "$tag" =~ ^v${base//./\.}-(beta|rc)\.[1-9][0-9]*$ ]] \
        || fail "tag ${tag} does not belong to project version ${base}"
      ;;
    *) fail "invalid release channel: ${channel}" ;;
  esac
}

artifact_label() {
  local root="$1" version channel tag
  version="$(read_version "$root")"
  [[ -x "${root}/scripts/release-version.sh" ]] \
    || fail "release-version helper is unavailable: ${root}/scripts/release-version.sh"
  channel="$(ERPNEXT_RELEASE_ROOT="$root" "${root}/scripts/release-version.sh" channel)"
  if [[ "$channel" == "development" ]]; then
    printf 'v%s-development\n' "$version"
  else
    tag="$(ERPNEXT_RELEASE_ROOT="$root" "${root}/scripts/release-version.sh" tag)"
    validate_channel_tag "$version" "$channel" "$tag"
    printf '%s\n' "$tag"
  fi
}

json_field() {
  local root="$1" field="$2" info
  info="${root}/BUILD-INFO.json"
  [[ -f "$info" ]] || fail "BUILD-INFO.json is missing: ${info}"
  python3 - "$info" "$field" <<'PY_FIELD'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
field = sys.argv[2]
try:
    data = json.loads(path.read_text())
except Exception as exc:
    raise SystemExit(f"FAIL: invalid BUILD-INFO.json: {exc}")
if field not in data:
    raise SystemExit(f"FAIL: BUILD-INFO.json field is missing: {field}")
value = data[field]
if value is None:
    print("")
elif isinstance(value, (str, int)):
    print(value)
else:
    raise SystemExit(f"FAIL: BUILD-INFO.json field is not scalar: {field}")
PY_FIELD
}

assert_source_clean() {
  local root="$1" info
  info="${root}/BUILD-INFO.json"
  [[ ! -e "$info" ]] || fail "source tree must not contain generated BUILD-INFO.json"
  if [[ -d "${root}/.git" ]] && git -C "$root" ls-files --error-unmatch BUILD-INFO.json >/dev/null 2>&1; then
    fail "BUILD-INFO.json must never be committed"
  fi
  printf 'OK: source tree contains no generated BUILD-INFO.json\n'
}

generate_info() {
  local source_root="$1" stage_root="$2" archive="$3" tag="$4" channel="$5"
  local commit_arg="$6" built_at_arg="$7"
  local version commit digest built_at output expected_archive label

  source_root="$(canonical_root "$source_root")"
  stage_root="$(canonical_root "$stage_root")"
  assert_source_clean "$source_root" >/dev/null
  version="$(read_version "$stage_root")"

  if [[ -z "$channel" ]]; then
    channel="$(ERPNEXT_RELEASE_ROOT="$source_root" "${source_root}/scripts/release-version.sh" channel)"
  fi
  if [[ -z "$tag" && "$channel" != "development" ]]; then
    tag="$(ERPNEXT_RELEASE_ROOT="$source_root" "${source_root}/scripts/release-version.sh" tag)"
  fi
  if [[ "$channel" == "development" ]]; then
    tag=""
    label="v${version}-development"
  else
    validate_channel_tag "$version" "$channel" "$tag"
    label="$tag"
  fi

  expected_archive="erpnext-dev-${label}.tar.gz"
  [[ "$archive" == "$expected_archive" ]] \
    || fail "archive identity ${archive} does not match ${expected_archive}"

  commit="$(resolve_commit "$source_root" "$commit_arg")"
  digest="$(payload_digest "$stage_root")"
  built_at="$(resolve_built_at "$built_at_arg")"
  output="${stage_root}/BUILD-INFO.json"
  [[ ! -e "$output" ]] || fail "refusing to overwrite existing BUILD-INFO.json in staged tree"

  python3 - "$output" "$version" "$channel" "$tag" "$commit" "$digest" "$archive" "$built_at" <<'PY_GENERATE'
import json
from pathlib import Path
import sys

output = Path(sys.argv[1])
data = {
    "schema_version": 1,
    "project_version": sys.argv[2],
    "channel": sys.argv[3],
    "tag": sys.argv[4],
    "commit": sys.argv[5],
    "tree_digest": sys.argv[6],
    "archive": sys.argv[7],
    "built_at": sys.argv[8],
}
output.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY_GENERATE
  chmod 0644 "$output"
  printf '%s\n' "$output"
}

verify_info() {
  local root="$1" metadata_only="$2" archive="$3" expected_tag="$4"
  local expected_channel="$5" expected_commit="$6"
  local info

  root="$(canonical_root "$root")"
  info="${root}/BUILD-INFO.json"
  [[ -f "$info" ]] || fail "BUILD-INFO.json is missing: ${info}"
  [[ -f "${root}/VERSION" ]] || fail "VERSION is missing from build tree"
  [[ -f "${root}/SHA256SUMS" ]] || fail "SHA256SUMS is missing from build tree"

  python3 - "$root" "$archive" "$expected_tag" "$expected_channel" "$expected_commit" <<'PY_VERIFY'
import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
archive_arg = sys.argv[2]
expected_tag = sys.argv[3]
expected_channel = sys.argv[4]
expected_commit = sys.argv[5].lower()
required = {
    "schema_version",
    "project_version",
    "channel",
    "tag",
    "commit",
    "tree_digest",
    "archive",
    "built_at",
}
try:
    data = json.loads((root / "BUILD-INFO.json").read_text())
except Exception as exc:
    raise SystemExit(f"FAIL: invalid BUILD-INFO.json: {exc}")
if not isinstance(data, dict):
    raise SystemExit("FAIL: BUILD-INFO.json must contain one object")
if set(data) != required:
    missing = sorted(required - set(data))
    extra = sorted(set(data) - required)
    raise SystemExit(f"FAIL: BUILD-INFO.json keys differ; missing={missing} extra={extra}")
if data["schema_version"] != 1:
    raise SystemExit("FAIL: unsupported BUILD-INFO schema_version")
version = (root / "VERSION").read_text().strip()
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?", version):
    raise SystemExit("FAIL: invalid VERSION in build tree")
if data["project_version"] != version:
    raise SystemExit("FAIL: BUILD-INFO project_version does not match VERSION")
channel = data["channel"]
tag = data["tag"]
if channel not in {"development", "beta", "rc", "stable"}:
    raise SystemExit("FAIL: invalid BUILD-INFO channel")
base = version.split("-", 1)[0]
if channel == "development":
    if tag != "":
        raise SystemExit("FAIL: development BUILD-INFO must not claim a release tag")
    label = f"v{version}-development"
else:
    if not isinstance(tag, str) or not tag:
        raise SystemExit("FAIL: release BUILD-INFO requires a tag")
    stable = re.fullmatch(r"v([0-9]+\.[0-9]+\.[0-9]+)", tag)
    beta = re.fullmatch(r"v([0-9]+\.[0-9]+\.[0-9]+)-beta\.([1-9][0-9]*)", tag)
    rc = re.fullmatch(r"v([0-9]+\.[0-9]+\.[0-9]+)-rc\.([1-9][0-9]*)", tag)
    detected = "stable" if stable else "beta" if beta else "rc" if rc else ""
    match = stable or beta or rc
    if not match or detected != channel or match.group(1) != base:
        raise SystemExit("FAIL: BUILD-INFO tag, channel, and project version disagree")
    label = tag
archive = data["archive"]
expected_archive = f"erpnext-dev-{label}.tar.gz"
if archive != expected_archive:
    raise SystemExit("FAIL: BUILD-INFO archive identity is inconsistent")
if archive_arg and archive_arg != archive:
    raise SystemExit("FAIL: supplied archive identity does not match BUILD-INFO")
commit = data["commit"]
if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40,64}", commit):
    raise SystemExit("FAIL: invalid BUILD-INFO commit identity")
if expected_commit and commit != expected_commit:
    raise SystemExit("FAIL: BUILD-INFO commit does not match expected commit")
digest = data["tree_digest"]
actual_digest = hashlib.sha256((root / "SHA256SUMS").read_bytes()).hexdigest()
if digest != actual_digest:
    raise SystemExit("FAIL: BUILD-INFO tree_digest does not match SHA256SUMS")
if not isinstance(data["built_at"], str) or not re.fullmatch(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
    data["built_at"],
):
    raise SystemExit("FAIL: invalid BUILD-INFO built_at timestamp")
if expected_tag and tag != expected_tag:
    raise SystemExit("FAIL: BUILD-INFO tag does not match expected tag")
if expected_channel and channel != expected_channel:
    raise SystemExit("FAIL: BUILD-INFO channel does not match expected channel")
for line in (root / "SHA256SUMS").read_text().splitlines():
    parts = line.split()
    if len(parts) >= 2 and parts[-1].lstrip("*") == "BUILD-INFO.json":
        raise SystemExit("FAIL: BUILD-INFO.json must not create a checksum cycle")
PY_VERIFY

  if [[ "$metadata_only" == "0" ]]; then
    (
      cd "$root"
      sha256sum -c SHA256SUMS >/dev/null
    ) || fail "build payload checksum verification failed"
  fi

  printf 'OK: BUILD-INFO.json verified (%s)\n' "$(json_field "$root" channel)"
}

command="${1:-}"
[[ -n "$command" ]] || {
  usage
  exit 2
}
shift

case "$command" in
  artifact-label | payload-digest | assert-source-clean)
    root="$DEFAULT_ROOT"
    while (($# > 0)); do
      case "$1" in
        --root)
          shift
          (($# > 0)) || fail "--root requires a path"
          root="$1"
          ;;
        -h | --help)
          usage
          exit 0
          ;;
        *) fail "unknown ${command} option: $1" ;;
      esac
      shift
    done
    root="$(canonical_root "$root")"
    case "$command" in
      artifact-label) artifact_label "$root" ;;
      payload-digest) payload_digest "$root" ;;
      assert-source-clean) assert_source_clean "$root" ;;
    esac
    ;;
  field)
    field="${1:-}"
    [[ -n "$field" ]] || fail "field requires a field name"
    shift
    root="$DEFAULT_ROOT"
    while (($# > 0)); do
      case "$1" in
        --root)
          shift
          (($# > 0)) || fail "--root requires a path"
          root="$1"
          ;;
        *) fail "unknown field option: $1" ;;
      esac
      shift
    done
    json_field "$(canonical_root "$root")" "$field"
    ;;
  generate)
    source_root="$DEFAULT_ROOT"
    stage_root=""
    archive=""
    tag=""
    channel=""
    commit=""
    built_at=""
    while (($# > 0)); do
      case "$1" in
        --source-root)
          shift
          (($# > 0)) || fail "--source-root requires a path"
          source_root="$1"
          ;;
        --stage-root)
          shift
          (($# > 0)) || fail "--stage-root requires a path"
          stage_root="$1"
          ;;
        --archive)
          shift
          (($# > 0)) || fail "--archive requires a name"
          archive="$1"
          ;;
        --tag)
          shift
          (($# > 0)) || fail "--tag requires a tag"
          tag="$1"
          ;;
        --channel)
          shift
          (($# > 0)) || fail "--channel requires a channel"
          channel="$1"
          ;;
        --commit)
          shift
          (($# > 0)) || fail "--commit requires a SHA"
          commit="$1"
          ;;
        --built-at)
          shift
          (($# > 0)) || fail "--built-at requires a timestamp"
          built_at="$1"
          ;;
        *) fail "unknown generate option: $1" ;;
      esac
      shift
    done
    [[ -n "$stage_root" ]] || fail "generate requires --stage-root"
    [[ -n "$archive" ]] || fail "generate requires --archive"
    generate_info "$source_root" "$stage_root" "$archive" "$tag" "$channel" "$commit" "$built_at"
    ;;
  verify)
    root="$DEFAULT_ROOT"
    metadata_only=0
    archive=""
    expected_tag=""
    expected_channel=""
    expected_commit=""
    while (($# > 0)); do
      case "$1" in
        --root)
          shift
          (($# > 0)) || fail "--root requires a path"
          root="$1"
          ;;
        --metadata-only) metadata_only=1 ;;
        --archive)
          shift
          (($# > 0)) || fail "--archive requires a name"
          archive="$1"
          ;;
        --expected-tag)
          shift
          (($# > 0)) || fail "--expected-tag requires a tag"
          expected_tag="$1"
          ;;
        --expected-channel)
          shift
          (($# > 0)) || fail "--expected-channel requires a channel"
          expected_channel="$1"
          ;;
        --expected-commit)
          shift
          (($# > 0)) || fail "--expected-commit requires a SHA"
          expected_commit="$1"
          ;;
        *) fail "unknown verify option: $1" ;;
      esac
      shift
    done
    verify_info "$root" "$metadata_only" "$archive" "$expected_tag" "$expected_channel" "$expected_commit"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage
    fail "unknown command: ${command}"
    ;;
esac
