#!/usr/bin/env bash
# Canonical release-version helper for ERPNext Developer Toolkit.
#
# VERSION is the authoritative repository version.
# SCRIPT_VERSION remains the runtime version embedded in erpnext-dev.sh.
# Both values must always match.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION_FILE="${ERPNEXT_VERSION_FILE:-${ROOT_DIR}/VERSION}"
ENTRYPOINT="${ERPNEXT_ENTRYPOINT:-${ROOT_DIR}/erpnext-dev.sh}"

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

read_canonical_version() {
  local line_count
  local raw_version
  local version

  [[ -f "$VERSION_FILE" ]] \
    || fail "VERSION file is missing: ${VERSION_FILE}"

  line_count="$(
    awk '
            NF {
                count++
            }
            END {
                print count + 0
            }
        ' "$VERSION_FILE"
  )"

  [[ "$line_count" == "1" ]] \
    || fail "VERSION must contain exactly one non-empty line"

  raw_version="$(
    awk '
            NF {
                print
                exit
            }
        ' "$VERSION_FILE"
  )"

  version="$(trim_value "$raw_version")"

  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] \
    || fail "invalid VERSION value: ${version}"

  printf '%s\n' "$version"
}

read_script_version() {
  local version

  [[ -f "$ENTRYPOINT" ]] \
    || fail "entrypoint is missing: ${ENTRYPOINT}"

  version="$(
    sed -nE \
      's/^SCRIPT_VERSION="([^"]+)".*/\1/p' \
      "$ENTRYPOINT" \
      | head -n 1
  )"

  [[ -n "$version" ]] \
    || fail "could not read SCRIPT_VERSION from ${ENTRYPOINT}"

  printf '%s\n' "$version"
}

assert_script_match() {
  local canonical_version
  local runtime_version

  canonical_version="$(read_canonical_version)"
  runtime_version="$(read_script_version)"

  [[ "$canonical_version" == "$runtime_version" ]] \
    || fail \
      "VERSION (${canonical_version}) does not match SCRIPT_VERSION (${runtime_version})"

  printf \
    'OK: VERSION matches SCRIPT_VERSION (%s)\n' \
    "$canonical_version"
}

assert_tag_match() {
  local supplied_tag="${1:-}"
  local expected_tag

  [[ -n "$supplied_tag" ]] \
    || fail "assert-tag requires a tag argument"

  expected_tag="v$(read_canonical_version)"

  [[ "$supplied_tag" == "$expected_tag" ]] \
    || fail \
      "tag ${supplied_tag} does not match canonical version ${expected_tag}"

  printf \
    'OK: tag matches canonical version (%s)\n' \
    "$expected_tag"
}

print_channel() {
  local version

  version="$(read_canonical_version)"

  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' stable
  elif [[ "$version" == *-beta.* ]]; then
    printf '%s\n' beta
  elif [[ "$version" == *-rc.* ]]; then
    printf '%s\n' rc
  else
    printf '%s\n' prerelease
  fi
}

case "${1:-read}" in
  read)
    read_canonical_version
    ;;

  tag)
    printf 'v%s\n' "$(read_canonical_version)"
    ;;

  script)
    read_script_version
    ;;

  channel)
    print_channel
    ;;

  assert-script)
    assert_script_match
    ;;

  assert-tag)
    assert_tag_match "${2:-}"
    ;;

  *)
    cat >&2 <<'EOF_USAGE'
Usage:
  scripts/release-version.sh read
  scripts/release-version.sh tag
  scripts/release-version.sh script
  scripts/release-version.sh channel
  scripts/release-version.sh assert-script
  scripts/release-version.sh assert-tag vX.Y.Z[-prerelease]
EOF_USAGE
    exit 2
    ;;
esac
