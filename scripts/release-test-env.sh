#!/usr/bin/env bash
# Canonical environment isolation for hermetic release-engineering tests.
set -Eeuo pipefail

release_test_env_names=(
  ERPNEXT_RELEASE_CHANNEL
  ERPNEXT_RELEASE_TAG
  ERPNEXT_RELEASE_ROOT
  ERPNEXT_VERSION_FILE
  ERPNEXT_ENTRYPOINT
  ERPNEXT_BUILD_INFO_FILE
  ERPNEXT_BUILD_INFO_HELPER
  ERPNEXT_GIT_ROOT
  ERPNEXT_RELEASE_REMOTE_CHECK
  ERPNEXT_RELEASE_REMOTE_NAME
  ERPNEXT_RELEASE_MANIFEST
  ERPNEXT_RELEASE_CHECKSUMS
  ERPNEXT_RELEASE_MANIFEST_HELPER
  ERPNEXT_TEST_RUNTIME_VERSION
  RELEASE_STRICT
  SKIP_SHELLCHECK
  SOURCE_DATE_EPOCH
  FIXTURE_VALIDATE_EXIT
  FIXTURE_CONTEXT_EXIT
)

release_test_env_command() {
  local -n output_ref="$1"
  local name

  output_ref=(env)
  for name in "${release_test_env_names[@]}"; do
    output_ref+=(-u "$name")
  done
}

release_test_env_exec_clean() {
  local -a command

  release_test_env_command command
  command+=("$@")
  "${command[@]}"
}

release_test_env_reexec() {
  local script="$1"
  local -a command
  shift

  [[ "${ERPNEXT_RELEASE_TEST_ISOLATED:-0}" != "1" ]] || return 0

  release_test_env_command command
  command+=(ERPNEXT_RELEASE_TEST_ISOLATED=1 "$script" "$@")
  exec "${command[@]}"
}

release_test_env_usage() {
  cat >&2 <<'EOF_USAGE'
Usage:
  scripts/release-test-env.sh clean COMMAND [ARG ...]
  scripts/release-test-env.sh list

The clean command removes release qualification, fixture-control, and
reproducible-build variables before executing COMMAND. Tests may explicitly add
fixture-specific values after `clean`, for example:

  scripts/release-test-env.sh clean env \
    ERPNEXT_RELEASE_CHANNEL=beta \
    ERPNEXT_RELEASE_TAG=v1.2.3-beta.1 \
    command ...
EOF_USAGE
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    clean)
      shift
      (($# > 0)) || {
        release_test_env_usage
        exit 2
      }
      release_test_env_exec_clean "$@"
      ;;
    list)
      printf '%s\n' "${release_test_env_names[@]}"
      ;;
    -h | --help)
      release_test_env_usage
      ;;
    *)
      release_test_env_usage
      exit 2
      ;;
  esac
fi
