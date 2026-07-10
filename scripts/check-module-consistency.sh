#!/usr/bin/env bash
# Guards against the two drift classes that shipped real defects:
#
#   1. Module-list drift: the runtime source chain, the self-update/release lib
#      list, the checksum generator, the shellcheck targets, SHA256SUMS, and
#      RELEASE-MANIFEST.txt must all describe the SAME set of lib/*.sh modules.
#      (lib/update.sh was once sourced at runtime but absent from the checksum
#      and self-update chain, so a tampered update.sh was invisible.)
#
#   2. Broken dispatcher commands: every function invoked from the main command
#      dispatcher must actually be defined somewhere in the toolkit.
#      (install-cli/repair-cli dispatched to functions that did not exist.)
#
# The runtime `source` chain in erpnext-dev.sh is treated as the single source
# of truth; every other list is verified to agree with it.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail_count=0
note_fail() {
  echo "FAIL: $*" >&2
  fail_count=$((fail_count + 1))
}

sorted_unique() { tr ' ' '\n' | sed '/^$/d' | sort -u; }

# --- Canonical list: the modules actually sourced by the entrypoint ----------
canonical="$(sed -nE 's#^source "\$\{_ERPNEXT_DEV_ROOT\}/lib/([a-z0-9_]+\.sh)".*#\1#p' erpnext-dev.sh | sorted_unique)"
if [[ -z "$canonical" ]]; then
  note_fail "could not extract the runtime source chain from erpnext-dev.sh"
  echo "module consistency: ABORTED" >&2
  exit 1
fi
canonical_count="$(printf '%s\n' "$canonical" | wc -l | tr -d ' ')"

compare_list() {
  local label="$1" actual="$2"
  actual="$(printf '%s\n' "$actual" | sorted_unique)"
  if [[ "$actual" != "$canonical" ]]; then
    note_fail "${label} does not match the runtime source chain"
    echo "  only in source chain: $(comm -23 <(printf '%s\n' "$canonical") <(printf '%s\n' "$actual") | tr '\n' ' ')" >&2
    echo "  only in ${label}:     $(comm -13 <(printf '%s\n' "$canonical") <(printf '%s\n' "$actual") | tr '\n' ' ')" >&2
  else
    echo "OK: ${label} matches (${canonical_count} modules)"
  fi
}

compare_list "toolkit_release_lib_files()" \
  "$(sed -n '/^toolkit_release_lib_files()/,/^}/p' lib/security.sh | grep -oE '[a-z0-9_]+\.sh')"
compare_list "generate-release-checksums.sh" \
  "$(grep -oE 'lib/[a-z0-9_]+\.sh' scripts/generate-release-checksums.sh | sed 's#lib/##')"
compare_list "run-shellcheck.sh targets" \
  "$(grep -oE 'lib/[a-z0-9_]+\.sh' scripts/run-shellcheck.sh | sed 's#lib/##')"
compare_list "SHA256SUMS" \
  "$(grep -oE 'lib/[a-z0-9_]+\.sh' SHA256SUMS | sed 's#lib/##')"
compare_list "RELEASE-MANIFEST.txt" \
  "$(grep -oE '^lib/[a-z0-9_]+\.sh' RELEASE-MANIFEST.txt | sed 's#lib/##')"

# --- Dispatcher function resolution -----------------------------------------
# Set of every function defined in the toolkit.
defined_functions="$(grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' erpnext-dev.sh lib/*.sh \
  | sed -E 's/[[:space:]]*\(\)$//' | sort -u)"

# Shell builtins / keywords that legitimately appear as the first token of a
# dispatcher arm (not project functions).
builtin_allow=" echo printf exit return cd read true false eval "

# The main command dispatcher: from the ACTION case to its closing esac.
dispatcher="$(sed -n '/case "${ACTION:-menu}" in/,/^  esac/p' erpnext-dev.sh)"
if [[ -z "$dispatcher" ]]; then
  note_fail "could not locate the command dispatcher in erpnext-dev.sh"
else
  missing=""
  while IFS= read -r fn; do
    [[ -n "$fn" ]] || continue
    [[ "$builtin_allow" == *" $fn "* ]] && continue
    printf '%s\n' "$defined_functions" | grep -qx "$fn" && continue
    missing="${missing} ${fn}"
  done < <(printf '%s\n' "$dispatcher" \
    | sed -nE "s/^[[:space:]]*[A-Za-z0-9|_\"'*.-]+\)[[:space:]]+([a-z_][A-Za-z0-9_]*).*/\1/p" | sort -u)

  if [[ -n "${missing// /}" ]]; then
    note_fail "dispatcher calls undefined function(s):${missing}"
  else
    echo "OK: every dispatcher function resolves to a definition"
  fi
fi

if [[ "$fail_count" -gt 0 ]]; then
  echo "module consistency: ${fail_count} problem(s) found" >&2
  exit 1
fi
echo "module consistency: all checks passed"
