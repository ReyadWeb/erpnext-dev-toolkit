#!/usr/bin/env bash
# Canonical release identity helper for ERPNext Developer Toolkit.
#
# VERSION is the only independently maintained project-version value.
# Runtime identity is verified by executing the entrypoint. Release channel is
# derived from immutable build metadata, explicit validated release context, or
# an exact Git tag; an ordinary untagged checkout is development.
set -Eeuo pipefail

ROOT_DIR="${ERPNEXT_RELEASE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERSION_FILE="${ERPNEXT_VERSION_FILE:-${ROOT_DIR}/VERSION}"
ENTRYPOINT="${ERPNEXT_ENTRYPOINT:-${ROOT_DIR}/erpnext-dev.sh}"
BUILD_INFO_FILE="${ERPNEXT_BUILD_INFO_FILE:-${ROOT_DIR}/BUILD-INFO.json}"
BUILD_INFO_HELPER="${ERPNEXT_BUILD_INFO_HELPER:-${ROOT_DIR}/scripts/build-info.sh}"
GIT_ROOT="${ERPNEXT_GIT_ROOT:-${ROOT_DIR}}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

validate_project_version() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] \
    || fail "invalid project version: ${version}"
}

read_canonical_version() {
  local line_count raw_version version
  [[ -f "$VERSION_FILE" ]] || fail "VERSION file is missing: ${VERSION_FILE}"

  line_count="$(awk 'NF { count++ } END { print count + 0 }' "$VERSION_FILE")"
  [[ "$line_count" == "1" ]] || fail "VERSION must contain exactly one non-empty line"

  raw_version="$(awk 'NF { print; exit }' "$VERSION_FILE")"
  version="$(trim_value "$raw_version")"
  validate_project_version "$version"
  printf '%s\n' "$version"
}

verify_build_info_metadata() {
  [[ -f "$BUILD_INFO_FILE" ]] || return 0
  [[ -x "$BUILD_INFO_HELPER" ]] \
    || fail "BUILD-INFO.json exists but build-info helper is unavailable: ${BUILD_INFO_HELPER}"
  ERPNEXT_RELEASE_ROOT="$ROOT_DIR" \
    "$BUILD_INFO_HELPER" verify --root "$ROOT_DIR" --metadata-only >/dev/null
}

read_build_field() {
  local field="$1"
  [[ -f "$BUILD_INFO_FILE" ]] || return 1
  verify_build_info_metadata
  "$BUILD_INFO_HELPER" field "$field" --root "$ROOT_DIR"
}

runtime_version() {
  local output version
  [[ -f "$ENTRYPOINT" ]] || fail "entrypoint is missing: ${ENTRYPOINT}"

  if [[ -x "$ENTRYPOINT" ]]; then
    output="$("$ENTRYPOINT" version 2>&1)" \
      || fail "runtime version command failed: ${ENTRYPOINT} version"
  else
    output="$(bash "$ENTRYPOINT" version 2>&1)" \
      || fail "runtime version command failed: bash ${ENTRYPOINT} version"
  fi

  version="$(
    printf '%s\n' "$output" \
      | sed -nE 's/^ERPNext Developer Toolkit v([^[:space:]]+).*$/\1/p' \
      | tail -n 1
  )"
  [[ -n "$version" ]] || fail "runtime version output was not recognized: ${output}"
  validate_project_version "$version"
  printf '%s\n' "$version"
}

assert_runtime_match() {
  local canonical runtime
  verify_build_info_metadata
  canonical="$(read_canonical_version)"
  runtime="$(runtime_version)"
  [[ "$canonical" == "$runtime" ]] \
    || fail "VERSION (${canonical}) does not match runtime output (${runtime})"
  printf 'OK: VERSION matches runtime output (%s)\n' "$canonical"
}

channel_from_tag() {
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

validate_release_channel() {
  case "$1" in
    development | beta | rc | stable) ;;
    *) fail "invalid release channel: $1" ;;
  esac
}

validate_tag_for_project() {
  local tag="$1" version base
  version="$(read_canonical_version)"
  base="${version%%-*}"

  if [[ "$version" == *-* ]]; then
    [[ "$tag" == "v${version}" ]] \
      || fail "tag ${tag} does not match canonical prerelease version v${version}"
    return 0
  fi

  [[ "$tag" == "v${base}" || "$tag" =~ ^v${base//./\.}-(beta|rc)\.[1-9][0-9]*$ ]] \
    || fail "tag ${tag} does not belong to project version ${base}"
}

exact_matching_tag() {
  local version base tag
  version="$(read_canonical_version)"
  base="${version%%-*}"
  [[ -d "${GIT_ROOT}/.git" ]] || return 1
  git -C "$GIT_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 || return 1

  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    if [[ "$version" == *-* ]]; then
      [[ "$tag" == "v${version}" ]] && {
        printf '%s\n' "$tag"
        return 0
      }
    elif [[ "$tag" == "v${base}" || "$tag" =~ ^v${base//./\.}-(beta|rc)\.[1-9][0-9]*$ ]]; then
      printf '%s\n' "$tag"
      return 0
    fi
  done < <(git -C "$GIT_ROOT" tag --points-at HEAD 2>/dev/null | LC_ALL=C sort -V)

  return 1
}

print_tag() {
  local explicit build_tag exact
  explicit="${ERPNEXT_RELEASE_TAG:-}"
  if [[ -n "$explicit" ]]; then
    validate_tag_for_project "$explicit"
    printf '%s\n' "$explicit"
    return 0
  fi

  build_tag="$(read_build_field tag 2>/dev/null || true)"
  if [[ -n "$build_tag" ]]; then
    validate_tag_for_project "$build_tag"
    printf '%s\n' "$build_tag"
    return 0
  fi

  exact="$(exact_matching_tag 2>/dev/null || true)"
  if [[ -n "$exact" ]]; then
    printf '%s\n' "$exact"
    return 0
  fi

  printf 'v%s\n' "$(read_canonical_version)"
}

print_channel() {
  local explicit build_channel build_version canonical exact channel
  explicit="${ERPNEXT_RELEASE_CHANNEL:-}"
  if [[ -n "$explicit" ]]; then
    validate_release_channel "$explicit"
    if [[ "$explicit" == "stable" || "$explicit" == "beta" || "$explicit" == "rc" ]]; then
      [[ -n "${ERPNEXT_RELEASE_TAG:-}" ]] \
        || fail "${explicit} release context requires ERPNEXT_RELEASE_TAG"
      validate_tag_for_project "$ERPNEXT_RELEASE_TAG"
      [[ "$(channel_from_tag "$ERPNEXT_RELEASE_TAG")" == "$explicit" ]] \
        || fail "release tag ${ERPNEXT_RELEASE_TAG} does not represent channel ${explicit}"
    fi
    printf '%s\n' "$explicit"
    return 0
  fi

  build_channel="$(read_build_field channel 2>/dev/null || true)"
  if [[ -n "$build_channel" ]]; then
    validate_release_channel "$build_channel"
    build_version="$(read_build_field project_version 2>/dev/null || true)"
    canonical="$(read_canonical_version)"
    [[ -n "$build_version" && "$build_version" == "$canonical" ]] \
      || fail "BUILD-INFO project_version does not match VERSION"
    printf '%s\n' "$build_channel"
    return 0
  fi

  exact="$(exact_matching_tag 2>/dev/null || true)"
  if [[ -n "$exact" ]]; then
    channel="$(channel_from_tag "$exact")" \
      || fail "exact tag has an unsupported release channel: ${exact}"
    printf '%s\n' "$channel"
    return 0
  fi

  printf '%s\n' development
}

assert_tag_match() {
  local supplied_tag="${1:-}"
  [[ -n "$supplied_tag" ]] || fail "assert-tag requires a tag argument"
  validate_tag_for_project "$supplied_tag"
  printf 'OK: tag belongs to canonical project version (%s)\n' "$supplied_tag"
}

case "${1:-read}" in
  read) read_canonical_version ;;
  tag) print_tag ;;
  runtime | script) runtime_version ;;
  channel) print_channel ;;
  assert-runtime | assert-script) assert_runtime_match ;;
  assert-tag) assert_tag_match "${2:-}" ;;
  channel-for-tag)
    [[ -n "${2:-}" ]] || fail "channel-for-tag requires a tag argument"
    validate_tag_for_project "$2"
    channel_from_tag "$2" \
      || fail "tag $2 has an unsupported release channel"
    ;;
  *)
    cat >&2 <<'EOF_USAGE'
Usage:
  scripts/release-version.sh read
  scripts/release-version.sh tag
  scripts/release-version.sh runtime
  scripts/release-version.sh channel
  scripts/release-version.sh assert-runtime
  scripts/release-version.sh assert-tag vX.Y.Z[-beta.N|-rc.N]
  scripts/release-version.sh channel-for-tag vX.Y.Z[-beta.N|-rc.N]

Compatibility aliases retained during v1.20.x migration:
  script        -> runtime
  assert-script -> assert-runtime
EOF_USAGE
    exit 2
    ;;
esac
