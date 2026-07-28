#!/usr/bin/env bash
# Audit or enforce v1.20.x release-state invariants.
set -Eeuo pipefail

ROOT_DIR="${ERPNEXT_RELEASE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT_DIR"

mode="${1:-audit}"
case "$mode" in
  audit | release-state | enforce) ;;
  *)
    echo "Usage: scripts/check-release-state-invariants.sh [audit|release-state|enforce]" >&2
    exit 2
    ;;
esac

gaps=0
rel_gaps=0
passes=0

pass() {
  printf 'OK:   %-34s %s\n' "$1" "$2"
  passes=$((passes + 1))
}

gap() {
  printf 'GAP:  %-34s %s\n' "$1" "$2"
  gaps=$((gaps + 1))
  if [[ "$1" == REL001_* ]]; then
    rel_gaps=$((rel_gaps + 1))
  fi
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || {
    gap "REQUIRED_FILE" "missing ${path}"
    return 1
  }
}

require_file VERSION || true
require_file erpnext-dev.sh || true
require_file scripts/release-version.sh || true
require_file README.md || true
require_file ROADMAP.md || true

if [[ -f VERSION ]]; then
  version="$(tr -d '[:space:]' <VERSION)"
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
    pass "REL001_VERSION_FORMAT" "VERSION=${version}"
  else
    gap "REL001_VERSION_FORMAT" "VERSION must contain one SemVer value"
  fi
else
  version="unknown"
fi

if [[ -f erpnext-dev.sh ]] && grep -Eq '^SCRIPT_VERSION="[0-9]' erpnext-dev.sh; then
  gap "REL001_DUPLICATE_VERSION" "erpnext-dev.sh still owns a literal SCRIPT_VERSION"
else
  pass "REL001_DUPLICATE_VERSION" "no independent runtime version literal"
fi

workflow_bypass=""
if [[ -d .github/workflows ]]; then
  workflow_bypass="$(
    grep -REn \
      --include='*.yml' \
      --include='*.yaml' \
      'SCRIPT_VERSION|grep[^\n]*VERSION' \
      .github/workflows 2>/dev/null || true
  )"
fi
if [[ -n "$workflow_bypass" ]]; then
  gap "REL001_WORKFLOW_BYPASS" "workflow parses version data outside release-version.sh"
else
  pass "REL001_WORKFLOW_BYPASS" "workflows use canonical release helpers"
fi

if [[ -x scripts/release-version.sh ]]; then
  channel="$(scripts/release-version.sh channel 2>/dev/null || printf 'unknown')"
  tag="$(scripts/release-version.sh tag 2>/dev/null || printf 'unknown')"

  exact_tag=0
  if [[ -d .git ]] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    if git tag --points-at HEAD 2>/dev/null | grep -Fxq "$tag"; then
      exact_tag=1
    fi
  fi

  release_phase="${ERPNEXT_RELEASE_PHASE:-}"
  strict_mode="${RELEASE_STRICT:-0}"
  source_tag="${ERPNEXT_RELEASE_SOURCE_TAG:-}"
  current_branch=""
  target_tag_exists=0

  if [[ -d .git ]]; then
    current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
      target_tag_exists=1
    fi
  fi

  stable_qualification=0
  stable_qualification_reason="missing authorised strict qualification phase"

  if [[ "$channel" == "stable" && "$exact_tag" -ne 1 ]]; then
    if [[ "$strict_mode" != "1" ]]; then
      stable_qualification_reason="strict mode is required"
    elif [[ -z "${ERPNEXT_RELEASE_TAG:-}" ||
      "${ERPNEXT_RELEASE_TAG}" != "$tag" ]]; then
      stable_qualification_reason="explicit stable target tag does not match ${tag}"
    elif [[ "$target_tag_exists" -eq 1 ]]; then
      stable_qualification_reason="stable target tag already exists: ${tag}"
    else
      case "$release_phase" in
        stable-promotion)
          version_regex="${version//./\\.}"

          if [[ "$current_branch" != "release/v${version}" ]]; then
            stable_qualification_reason="stable promotion requires branch release/v${version}"
          elif [[ ! "$source_tag" =~ ^v${version_regex}-(beta|rc)\.[0-9]+$ ]]; then
            stable_qualification_reason="source tag is not a matching beta or RC tag"
          elif ! git rev-parse -q --verify "refs/tags/${source_tag}" >/dev/null 2>&1; then
            stable_qualification_reason="source prerelease tag does not exist: ${source_tag}"
          elif ! git tag --points-at HEAD 2>/dev/null | grep -Fxq "$source_tag"; then
            stable_qualification_reason="source prerelease tag does not point exactly at HEAD"
          else
            stable_qualification=1
          fi
          ;;
        stable-pretag)
          if [[ "$current_branch" != "main" ]]; then
            stable_qualification_reason="stable pre-tag qualification requires main"
          elif [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            stable_qualification_reason="stable pre-tag qualification requires a clean working tree"
          else
            stable_qualification=1
          fi
          ;;
        *)
          stable_qualification_reason="unknown or missing qualification phase"
          ;;
      esac
    fi
  fi

  if [[ "$channel" == "stable" && "$exact_tag" -ne 1 && "$stable_qualification" -ne 1 ]]; then
    gap "REL001_CHANNEL_CONTEXT" "untagged/non-exact stable tree failed qualification (${tag}): ${stable_qualification_reason}"
  elif [[ "$channel" == "stable" && "$stable_qualification" -eq 1 ]]; then
    pass "REL001_CHANNEL_CONTEXT" "channel=${channel}; tag=${tag}; phase=${release_phase}"
  elif [[ "$channel" =~ ^(development|beta|rc|stable)$ ]]; then
    pass "REL001_CHANNEL_CONTEXT" "channel=${channel}; tag=${tag}"
  else
    gap "REL001_CHANNEL_CONTEXT" "invalid or unavailable channel: ${channel}"
  fi
else
  gap "REL001_CHANNEL_CONTEXT" "release-version.sh is unavailable"
fi

if [[ -e BUILD-INFO.json ]]; then
  gap "REL001_BUILD_INFO_SOURCE" "generated BUILD-INFO.json is present in the source tree"
else
  pass "REL001_BUILD_INFO_SOURCE" "generated build metadata is absent from source"
fi

if [[ -x scripts/build-info.sh && -x scripts/test-build-info.sh ]] &&
  grep -Fq 'scripts/build-info.sh' scripts/build-release-bundle.sh 2>/dev/null &&
  { grep -Fq 'generate_args=(' scripts/build-release-bundle.sh 2>/dev/null ||
    grep -Fq 'scripts/build-info.sh generate' scripts/build-release-bundle.sh 2>/dev/null; } &&
  { grep -Fq 'verify_args=(' scripts/build-release-bundle.sh 2>/dev/null ||
    grep -Fq 'scripts/build-info.sh verify' scripts/build-release-bundle.sh 2>/dev/null; }; then
  pass "REL001_BUILD_INFO_TOOLING" "bundle generation and verification use the canonical helper"
else
  gap "REL001_BUILD_INFO_TOOLING" "canonical generated build identity is incomplete"
fi

if [[ -f README.md ]] && grep -Fq 'v1.20.1 release-state' README.md; then
  pass "REL001_README_STATUS" "README identifies v1.20.1 reliability work"
else
  gap "REL001_README_STATUS" "README current focus is not the v1.20.1 reliability programme"
fi

if [[ -f ROADMAP.md ]] && grep -Fq '**Current work:** v1.20.1' ROADMAP.md; then
  pass "REL001_ROADMAP_STATUS" "roadmap identifies v1.20.1 as current work"
else
  gap "REL001_ROADMAP_STATUS" "roadmap does not identify v1.20.1 as current work"
fi

project_tag="v${version}"
project_docs_ok=1
for file in README.md ROADMAP.md TESTING.md; do
  if [[ ! -f "$file" ]] || ! grep -qE "^\*\*Current project version:\*\* ${project_tag}([[:space:]]|$|\.|·)" "$file"; then
    project_docs_ok=0
  fi
done
if [[ "$project_docs_ok" == "1" ]]; then
  pass "REL001_PROJECT_DOCS" "active documents identify project version ${project_tag}"
else
  gap "REL001_PROJECT_DOCS" "active documents do not agree with project version ${project_tag}"
fi

unsafe_bootstrap=""
for file in README.md SECURITY.md docs/security/RELEASE-TRUST.md .github/workflows/release.yml; do
  [[ -f "$file" ]] || continue
  if grep -Eq 'sudo[[:space:]]+\./erpnext-dev\.sh[[:space:]]+verify-signature|Stronger \(authenticity\).*sudo' "$file"; then
    unsafe_bootstrap+="${file} "
  fi
done
if [[ -n "$unsafe_bootstrap" ]]; then
  gap "SEC001_PRE_SUDO_TRUST" "downloaded toolkit verifies itself under sudo: ${unsafe_bootstrap% }"
else
  pass "SEC001_PRE_SUDO_TRUST" "no downloaded toolkit execution before authenticity verification"
fi

unsafe_ci=""
if [[ -d .github/workflows ]]; then
  unsafe_ci="$(
    python3 - <<'PY_SCAN_UNSAFE_CI'
from pathlib import Path
import re

for path in sorted(Path(".github/workflows").glob("*.y*ml")):
    text = path.read_text(errors="replace")
    normalized = re.sub(r"\\\s*\n\s*", " ", text)
    if re.search(
        r"\bcurl\b.{0,800}?\|\s*sudo\s+(?:tar|bash|sh)\b",
        normalized,
        flags=re.S,
    ):
        print(path)
PY_SCAN_UNSAFE_CI
  )"
fi
if [[ -n "$unsafe_ci" ]]; then
  gap "SEC002_CI_DOWNLOAD" "CI pipes a download into a privileged consumer"
else
  pass "SEC002_CI_DOWNLOAD" "CI downloads are not piped into privileged consumers"
fi

if [[ -f scripts/validate-release.sh ]]; then
  strict_shellcheck_guard="$(
    python3 - <<'PY_SCAN_STRICT_SHELLCHECK'
from pathlib import Path
import re

text = Path("scripts/validate-release.sh").read_text(errors="replace")
normalized = re.sub(r"\\\s*\n\s*", " ", text)

fail_action = re.compile(r"(?:\bfail\b|\bexit\s+[1-9][0-9]*\b)", re.I)
found = False

combined = re.compile(
    r"if\s+\[\[.{0,260}?RELEASE_STRICT.{0,160}?(?:==|=).{0,50}?1.{0,160}?\]\]"
    r"\s*&&\s*!\s*command\s+-v\s+shellcheck.{0,160}?;?\s*then"
    r"(?P<body>.{0,700}?)\n\s*fi\b",
    re.S | re.I,
)
for match in combined.finditer(normalized):
    if fail_action.search(match.group("body")):
        found = True
        break

if not found:
    availability = re.compile(
        r"if\s+command\s+-v\s+shellcheck.{0,160}?;?\s*then"
        r"(?P<success>.*?)\n\s*else(?P<failure>.*?)\n\s*fi\b",
        re.S | re.I,
    )
    for match in availability.finditer(normalized):
        failure = match.group("failure")
        if "RELEASE_STRICT" in failure and fail_action.search(failure):
            found = True
            break

if not found:
    missing_guard = re.compile(
        r"if\s+!\s*command\s+-v\s+shellcheck.{0,160}?;?\s*then"
        r"(?P<body>.{0,900}?)\n\s*fi\b",
        re.S | re.I,
    )
    for match in missing_guard.finditer(normalized):
        body = match.group("body")
        if "RELEASE_STRICT" in body and fail_action.search(body):
            found = True
            break

if found:
    print("yes")
PY_SCAN_STRICT_SHELLCHECK
  )"

  if [[ "$strict_shellcheck_guard" == "yes" ]]; then
    pass "TEST_STRICT_NO_SKIP" "release validator fails when strict ShellCheck is unavailable"
  else
    gap "TEST_STRICT_NO_SKIP" "release-strict mode can still accept missing ShellCheck"
  fi
else
  gap "TEST_STRICT_NO_SKIP" "release validator is unavailable"
fi

printf '\nRelease-state audit: %d pass(es), %d gap(s).\n' "$passes" "$gaps"

if [[ "$mode" == "release-state" && "$rel_gaps" -ne 0 ]]; then
  exit 1
fi
if [[ "$mode" == "enforce" && "$gaps" -ne 0 ]]; then
  exit 1
fi
