#!/usr/bin/env bash
# Safe, resumable repository workflow for ERPNext Developer Toolkit.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROGRAM="scripts/repo-workflow.sh"
STATE_DIR="$(git rev-parse --git-path erpnext-workflow 2>/dev/null || true)"
CACHE_DIR="${STATE_DIR}/cache"
RELEASE_STATE_FILE="${STATE_DIR}/release-state"

CURRENT_ACTION=""
CURRENT_MODE="auto"
CURRENT_MESSAGE=""
CURRENT_STAGE=""

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

heading() {
  printf '\n============================================================\n%s\n============================================================\n' "$1"
}

info() {
  printf '  %-28s %s\n' "$1" "$2"
}

ok() {
  echo "OK: $*"
}

warn() {
  echo "WARNING: $*" >&2
}

usage() {
  cat <<'USAGE'
ERPNext Developer Toolkit repository workflow

Usage:
  scripts/repo-workflow.sh status
  scripts/repo-workflow.sh explain
  scripts/repo-workflow.sh check [--fast|--full|--mode auto|fast|full] [--no-cache]
  scripts/repo-workflow.sh publish -m "Commit message" [--fast|--full] [--dry-run] [--no-push]
  scripts/repo-workflow.sh work start BRANCH [--base main]
  scripts/repo-workflow.sh work finish -m "Commit message" [--pr-title TEXT] [--pr-body TEXT|--pr-body-file PATH] [--base main] [--fast|--full] [--no-cache] [--no-watch] [--dry-run]
  scripts/repo-workflow.sh work land --confirm [--delete-branch] [--base main]
  scripts/repo-workflow.sh pr create [--base main] [--title TEXT] [--body TEXT|--body-file PATH] [--draft]
  scripts/repo-workflow.sh pr status
  scripts/repo-workflow.sh pr checks [--watch] [--required]
  scripts/repo-workflow.sh pr merge [--merge|--squash|--rebase] [--admin] [--delete-branch]
  scripts/repo-workflow.sh release status [--offline]
  scripts/repo-workflow.sh release explain [--offline]
  scripts/repo-workflow.sh release doctor [--offline]
  scripts/repo-workflow.sh release prepare-beta X.Y.Z-beta.N "Release title"
  scripts/repo-workflow.sh release promote-stable X.Y.Z "Release title"
  scripts/repo-workflow.sh release publish --confirm-reviewed -m "Commit message"
  scripts/repo-workflow.sh release publish --resume-prepared
  scripts/repo-workflow.sh release recover [--rollback-prepared --confirm]
  scripts/repo-workflow.sh release pretag [vX.Y.Z[-prerelease]] [--offline]
  scripts/repo-workflow.sh release tag --confirm vX.Y.Z[-prerelease]
  scripts/repo-workflow.sh release watch [vX.Y.Z[-prerelease]] [--interval SECONDS] [--attempts N]
  scripts/repo-workflow.sh release verify [vX.Y.Z[-prerelease]]
  scripts/repo-workflow.sh release run beta X.Y.Z-beta.N "Release title"
  scripts/repo-workflow.sh release run stable X.Y.Z --from vX.Y.Z-beta.N "Release title"
  scripts/repo-workflow.sh release run
  scripts/repo-workflow.sh release beta X.Y.Z-beta.N "Release title" [--confirm-reviewed] [--confirm-merge] [--confirm-tag vX.Y.Z-beta.N] [--confirm-verify]
  scripts/repo-workflow.sh release stable X.Y.Z --from vX.Y.Z-beta.N "Release title" [--confirm-reviewed] [--confirm-merge] [--confirm-tag vX.Y.Z]
  scripts/repo-workflow.sh resume
  scripts/repo-workflow.sh clean-cache

Commands:
  status       Show branch, sync, changes, risk, selected validation, and saved state.
  explain      Explain why the current tree selects fast or full validation.
  check        Regenerate checksums and run the minimum safe local validation.
  publish      Check, stage, commit, and push the current feature branch.
  work         Consolidated start, finish, and land workflow for routine changes.
  pr           Create, inspect, check, and merge the current branch pull request.
  release      Diagnose, prepare, recover, orchestrate, tag, watch, and verify protected releases.
  resume       Resume the last failed check or publish operation.
  clean-cache  Remove cached full-validation results and saved resume state.

Validation:
  auto         Select full validation for high-risk paths; otherwise use fast.
  fast         Changed-file syntax/lint, focused tests, docs, manifest, checksums.
  full         Canonical validate-release.sh plus release-bundle construction.
USAGE
}

require_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "not inside a Git repository"
  [[ "$(git rev-parse --show-toplevel)" == "$ROOT_DIR" ]] \
    || fail "run from the ERPNext Developer Toolkit repository"
  [[ -n "$STATE_DIR" ]] || fail "cannot resolve Git workflow state directory"
  mkdir -p "$STATE_DIR" "$CACHE_DIR"
  chmod 700 "$STATE_DIR" "$CACHE_DIR" 2>/dev/null || true
}

branch_name() {
  git branch --show-current
}

is_protected_branch() {
  local branch="$1"
  case "$branch" in
    main | master | beta | release/*) return 0 ;;
    *) return 1 ;;
  esac
}

collect_changed_files() {
  local -a files=()
  local file
  declare -A seen=()

  while IFS= read -r -d '' file; do
    [[ -n "$file" ]] || continue
    seen["$file"]=1
  done < <(
    {
      git diff --name-only -z --diff-filter=ACDMRTUXB
      git diff --cached --name-only -z --diff-filter=ACDMRTUXB
      git ls-files --others --exclude-standard -z
    }
  )

  if ((${#seen[@]} > 0)); then
    while IFS= read -r file; do
      [[ -n "$file" ]] && files+=("$file")
    done < <(printf '%s\n' "${!seen[@]}" | LC_ALL=C sort)
  fi

  CHANGED_FILES=("${files[@]}")
}

has_changes() {
  collect_changed_files
  ((${#CHANGED_FILES[@]} > 0))
}

risk_reason_for() {
  local file="$1"
  case "$file" in
    VERSION)
      echo "canonical release version"
      ;;
    erpnext-dev.sh)
      echo "privileged CLI entrypoint"
      ;;
    RELEASE-MANIFEST.txt)
      echo "authoritative release inventory"
      ;;
    .github/*)
      echo "repository automation or security workflow"
      ;;
    lib/security.sh | lib/update.sh)
      echo "release trust or self-update path"
      ;;
    scripts/validate-release.sh | scripts/build-release-bundle.sh | scripts/build-info.sh | scripts/test-build-info.sh | scripts/generate-release-checksums.sh | scripts/release-manifest-files.sh | scripts/check-release-artifact-consistency.sh)
      echo "release integrity implementation"
      ;;
    scripts/release-*.sh | scripts/test-release-*.sh)
      echo "release transaction or release regression path"
      ;;
    scripts/repo-workflow.sh | scripts/test-repo-workflow.sh | scripts/test-repo-workflow-pr.sh | scripts/test-repo-workflow-release.sh | scripts/test-repo-workflow-release-transaction.sh | scripts/test-repo-workflow-release-finalize.sh | scripts/test-repo-workflow-release-run.sh)
      echo "repository workflow implementation"
      ;;
    SECURITY.md | docs/security/RELEASE-TRUST.md | docs/RELEASE-AUTOMATION.md | docs/RELEASE-PROCESS.md)
      echo "security or release authority documentation"
      ;;
    *)
      return 1
      ;;
  esac
}

classify_mode() {
  local file reason
  RISK_REASONS=()
  SELECTED_MODE="fast"

  collect_changed_files
  for file in "${CHANGED_FILES[@]}"; do
    if reason="$(risk_reason_for "$file")"; then
      SELECTED_MODE="full"
      RISK_REASONS+=("${file}: ${reason}")
    fi
  done
}

resolve_mode() {
  local requested="$1"
  classify_mode
  case "$requested" in
    auto) ;;
    fast | full) SELECTED_MODE="$requested" ;;
    *) fail "invalid validation mode: $requested" ;;
  esac
}

upstream_status() {
  local upstream counts behind ahead
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]]; then
    echo "no upstream"
    return 0
  fi
  counts="$(git rev-list --left-right --count "${upstream}...HEAD")"
  behind="${counts%%[[:space:]]*}"
  ahead="${counts##*[[:space:]]}"
  echo "${upstream}; ahead ${ahead}, behind ${behind}"
}

state_write() {
  local action="$1" mode="$2" stage="$3" message="${4:-}"
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$action" >"${STATE_DIR}/action"
  printf '%s\n' "$mode" >"${STATE_DIR}/mode"
  printf '%s\n' "$stage" >"${STATE_DIR}/stage"
  printf '%s' "$message" >"${STATE_DIR}/message"
  chmod 600 "${STATE_DIR}/action" "${STATE_DIR}/mode" \
    "${STATE_DIR}/stage" "${STATE_DIR}/message" 2>/dev/null || true
}

state_clear() {
  rm -f "${STATE_DIR}/action" "${STATE_DIR}/mode" \
    "${STATE_DIR}/stage" "${STATE_DIR}/message"
}

state_value() {
  local name="$1"
  if [[ -f "${STATE_DIR}/${name}" ]]; then
    cat "${STATE_DIR}/${name}"
  fi
}

release_state_key_allowed() {
  case "$1" in
    schema | phase | channel | target_version | target_tag | source_tag | \
      source_commit | release_branch | title | commit_message | \
      prepared_fingerprint | review_confirmed | publication_commit | \
      pr_number | merge_commit | workflow_run | verified_commit)
      return 0
      ;;
    *) return 1 ;;
  esac
}

release_state_value_valid() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && ${#value} -le 2048 ]]
}

release_state_value() {
  local key="$1"
  release_state_key_allowed "$key" || fail "invalid release-state key: ${key}"
  [[ -f "$RELEASE_STATE_FILE" ]] || return 0
  sed -n "s/^${key}=//p" "$RELEASE_STATE_FILE" | tail -n 1
}

release_state_update() {
  local key value tmp
  local -A values=()

  if [[ -f "$RELEASE_STATE_FILE" ]]; then
    while IFS='=' read -r key value; do
      release_state_key_allowed "$key" || continue
      release_state_value_valid "$value" || continue
      values["$key"]="$value"
    done <"$RELEASE_STATE_FILE"
  fi

  while (($# > 0)); do
    (($# >= 2)) || fail "release-state update requires key/value pairs"
    key="$1"
    value="$2"
    shift 2
    release_state_key_allowed "$key" || fail "invalid release-state key: ${key}"
    release_state_value_valid "$value" || fail "invalid release-state value for ${key}"
    values["$key"]="$value"
  done

  values[schema]=1
  tmp="$(mktemp "${STATE_DIR}/release-state.XXXXXX")"
  for key in schema phase channel target_version target_tag source_tag \
    source_commit release_branch title commit_message prepared_fingerprint \
    review_confirmed publication_commit pr_number merge_commit workflow_run \
    verified_commit; do
    [[ -v "values[$key]" ]] || continue
    printf '%s=%s\n' "$key" "${values[$key]}" >>"$tmp"
  done
  chmod 600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$RELEASE_STATE_FILE"
}

release_state_clear() {
  rm -f "$RELEASE_STATE_FILE"
}

release_state_matches_target() {
  local target_tag="$1"
  [[ "$(release_state_value schema)" == "1" &&
  "$(release_state_value target_tag)" == "$target_tag" ]]
}

release_state_prepare_verified() {
  local target_tag="$1" remote_commit="$2" phase prefix key value
  local -A seen=()

  if [[ -f "$RELEASE_STATE_FILE" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^[a-z_]+$ ]] \
        || fail "saved release state is malformed; manual review required"
      release_state_key_allowed "$key" \
        || fail "saved release state contains an unsupported field; manual review required"
      release_state_value_valid "$value" \
        || fail "saved release state contains an unsafe value; manual review required"
      [[ -z "${seen[$key]:-}" ]] \
        || fail "saved release state contains a duplicate field; manual review required"
      seen["$key"]=1
    done <"$RELEASE_STATE_FILE"
    [[ "$(release_state_value schema)" == "1" ]] \
      || fail "saved release state has an unsupported schema; manual review required"
    [[ "$(release_state_value target_tag)" == "$target_tag" ]] \
      || fail "saved release transaction targets a different tag; refusing to overwrite it"
    phase="$(release_state_value phase)"
    case "$phase" in
      beta-published | beta-verified | stable-published | stable-verified) ;;
      *) fail "saved release transaction is unfinished at phase ${phase:-unknown}; refusing to overwrite it" ;;
    esac
  fi

  [[ "$remote_commit" =~ ^[0-9a-f]{40}$ ]] \
    || fail "verified release commit is malformed"
  if [[ "$target_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    prefix=stable
  else
    prefix=beta
  fi
  printf '%s\n' "$prefix"
}

release_worktree_tag() {
  local version
  version="$(scripts/release-version.sh read)"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(beta|rc)\.[1-9][0-9]*)?$ ]] \
    || fail "working-tree VERSION is not a canonical release version: ${version}"
  printf 'v%s\n' "$version"
}

saved_state_summary() {
  local action stage mode
  action="$(state_value action)"
  [[ -n "$action" ]] || {
    echo "none"
    return 0
  }
  stage="$(state_value stage)"
  mode="$(state_value mode)"
  echo "${action}; stage ${stage:-unknown}; mode ${mode:-auto}"
}

tree_fingerprint() {
  local file mode hash
  {
    while IFS= read -r -d '' file; do
      if [[ -L "$file" ]]; then
        printf 'L\t%s\t%s\n' "$file" "$(readlink -- "$file")"
      elif [[ -f "$file" ]]; then
        mode="$(stat -c '%a' -- "$file" 2>/dev/null || echo unknown)"
        hash="$(git hash-object -- "$file")"
        printf 'F\t%s\t%s\t%s\n' "$file" "$mode" "$hash"
      else
        printf 'M\t%s\n' "$file"
      fi
    done < <(git ls-files -co --exclude-standard -z | LC_ALL=C sort -z)
  } | sha256sum | awk '{print $1}'
}

cache_file_for() {
  local mode="$1"
  echo "${CACHE_DIR}/${mode}.fingerprint"
}

cache_matches() {
  local mode="$1" fingerprint="$2" file
  file="$(cache_file_for "$mode")"
  [[ -f "$file" ]] && [[ "$(cat "$file")" == "$fingerprint" ]]
}

cache_store() {
  local mode="$1" fingerprint="$2" file
  file="$(cache_file_for "$mode")"
  printf '%s\n' "$fingerprint" >"$file"
  chmod 600 "$file" 2>/dev/null || true
}

run_step() {
  local label="$1"
  shift
  CURRENT_STAGE="$label"
  state_write "$CURRENT_ACTION" "$CURRENT_MODE" "$CURRENT_STAGE" "$CURRENT_MESSAGE"
  heading "$label"
  if ! "$@"; then
    echo >&2
    echo "FAILED: ${label}" >&2
    echo "Resume with:" >&2
    echo "  ${PROGRAM} resume" >&2
    exit 1
  fi
}

generate_checksums() {
  [[ -x scripts/generate-release-checksums.sh ]] \
    || fail "scripts/generate-release-checksums.sh is missing or not executable"
  scripts/generate-release-checksums.sh
}

check_whitespace() {
  git diff --check
  git diff --cached --check
}

check_version() {
  [[ -x scripts/release-version.sh ]] \
    || fail "scripts/release-version.sh is missing or not executable"
  scripts/release-version.sh assert-script
}

check_docs() {
  [[ -x scripts/check-release-doc-alignment.sh ]] \
    || fail "scripts/check-release-doc-alignment.sh is missing or not executable"
  scripts/check-release-doc-alignment.sh
}

check_artifacts() {
  [[ -x scripts/check-release-artifact-consistency.sh ]] \
    || fail "scripts/check-release-artifact-consistency.sh is missing or not executable"
  scripts/check-release-artifact-consistency.sh >/dev/null
  ok "release manifest and checksum inventory are aligned"
}

changed_shell_files() {
  local file
  for file in "${CHANGED_FILES[@]}"; do
    [[ "$file" == *.sh ]] || continue
    [[ -f "$file" ]] || continue
    printf '%s\n' "$file"
  done
}

check_changed_shell_syntax() {
  local -a shell_files=()
  local file
  mapfile -t shell_files < <(changed_shell_files)
  if ((${#shell_files[@]} == 0)); then
    ok "no changed shell files require syntax checks"
    return 0
  fi
  for file in "${shell_files[@]}"; do
    echo "bash -n: ${file}"
    bash -n "$file"
  done
  ok "bash syntax passed for ${#shell_files[@]} changed file(s)"
}

check_changed_shellcheck() {
  local -a shell_files=()
  local file
  mapfile -t shell_files < <(changed_shell_files)
  if ((${#shell_files[@]} == 0)); then
    ok "no changed shell files require ShellCheck"
    return 0
  fi
  if ! command -v shellcheck >/dev/null 2>&1; then
    warn "shellcheck is not installed; CI will run the authoritative lint gate"
    return 0
  fi
  for file in "${shell_files[@]}"; do
    if [[ "$file" == "erpnext-dev.sh" ]]; then
      echo "shellcheck: ${file} skipped (entrypoint sources the complete module tree)"
      continue
    fi
    echo "shellcheck: ${file}"
    if command -v timeout >/dev/null 2>&1; then
      if ! timeout "${SHELLCHECK_FILE_TIMEOUT:-180}" shellcheck -x -S warning "$file"; then
        return 1
      fi
    else
      if ! shellcheck -x -S warning "$file"; then
        return 1
      fi
    fi
  done
  ok "changed-file ShellCheck passed"
}

add_focused_test() {
  local test="$1"
  [[ -x "$test" ]] || return 0
  FOCUSED_TESTS["$test"]=1
}

select_focused_tests() {
  local file
  declare -gA FOCUSED_TESTS=()
  for file in "${CHANGED_FILES[@]}"; do
    case "$file" in
      scripts/repo-workflow.sh | scripts/test-repo-workflow.sh | scripts/test-repo-workflow-pr.sh | scripts/test-repo-workflow-work.sh | scripts/test-repo-workflow-release.sh | scripts/test-repo-workflow-release-transaction.sh | scripts/test-repo-workflow-release-finalize.sh)
        add_focused_test scripts/test-repo-workflow.sh
        add_focused_test scripts/test-repo-workflow-pr.sh
        add_focused_test scripts/test-repo-workflow-work.sh
        add_focused_test scripts/test-repo-workflow-release.sh
        add_focused_test scripts/test-repo-workflow-release-transaction.sh
        add_focused_test scripts/test-repo-workflow-release-finalize.sh
        ;;
      scripts/release-test-env.sh | scripts/test-release-test-env.sh | scripts/test-release-context-isolation.sh | scripts/build-info.sh | scripts/test-build-info.sh | scripts/release-prepare-beta.sh | scripts/test-release-prepare-beta.sh | scripts/release-pretag-check.sh | scripts/test-release-pretag-check.sh)
        add_focused_test scripts/test-release-test-env.sh
        add_focused_test scripts/test-release-context-isolation.sh
        ;;
      VERSION | erpnext-dev.sh | scripts/release-version.sh | scripts/test-release-version.sh)
        add_focused_test scripts/test-release-version.sh
        ;;
      RELEASE-MANIFEST.txt | SHA256SUMS | scripts/release-manifest-files.sh | scripts/check-release-artifact-consistency.sh | scripts/generate-release-checksums.sh | scripts/test-release-manifest.sh | scripts/test-release-artifact-consistency.sh)
        add_focused_test scripts/test-release-manifest.sh
        add_focused_test scripts/test-release-artifact-consistency.sh
        ;;
      README.md | SECURITY.md | TESTING.md | docs/security/* | scripts/test-release-bootstrap-guidance.sh)
        add_focused_test scripts/test-release-bootstrap-guidance.sh
        ;;
      lib/local_ip.sh | scripts/test-local-ip.sh)
        add_focused_test scripts/test-local-ip.sh
        ;;
      lib/healing.sh | scripts/test-healing.sh)
        add_focused_test scripts/test-healing.sh
        ;;
      lib/dashboard.sh | scripts/test-dashboard-render.sh)
        add_focused_test scripts/test-dashboard-render.sh
        ;;
      lib/ui.sh | lib/menu.sh | scripts/test-ui-render.sh)
        add_focused_test scripts/test-ui-render.sh
        ;;
      lib/update.sh | scripts/test-update-channel.sh)
        add_focused_test scripts/test-update-channel.sh
        ;;
      .github/* | scripts/check-pinned-actions.sh)
        add_focused_test scripts/check-pinned-actions.sh
        ;;
    esac
  done
}

run_focused_tests() {
  local test
  select_focused_tests
  if ((${#FOCUSED_TESTS[@]} == 0)); then
    ok "no focused regression test selected"
    return 0
  fi
  while IFS= read -r test; do
    echo "test: ${test}"
    "$test"
  done < <(printf '%s\n' "${!FOCUSED_TESTS[@]}" | LC_ALL=C sort)
  ok "focused regression tests passed"
}

run_fast_checks() {
  collect_changed_files
  run_step "Whitespace validation" check_whitespace
  run_step "Version alignment" check_version
  run_step "Documentation alignment" check_docs
  run_step "Manifest and checksum validation" check_artifacts
  run_step "Changed shell syntax" check_changed_shell_syntax
  run_step "Changed shell lint" check_changed_shellcheck
  run_step "Focused regression tests" run_focused_tests
}

run_full_checks() {
  local no_cache="$1" fingerprint
  fingerprint="$(tree_fingerprint)"
  if [[ "$no_cache" != "1" ]] && cache_matches full "$fingerprint"; then
    ok "full validation already passed for this exact repository tree"
    return 0
  fi
  [[ -x scripts/validate-release.sh ]] \
    || fail "scripts/validate-release.sh is missing or not executable"
  [[ -x scripts/build-release-bundle.sh ]] \
    || fail "scripts/build-release-bundle.sh is missing or not executable"
  run_step "Complete release validation" scripts/validate-release.sh
  run_step "Release bundle construction" scripts/build-release-bundle.sh
  fingerprint="$(tree_fingerprint)"
  cache_store full "$fingerprint"
  ok "cached full validation for the current repository tree"
}

perform_check() {
  local requested_mode="$1" no_cache="$2" clear_on_success=0
  if [[ -z "$CURRENT_ACTION" ]]; then
    CURRENT_ACTION="check"
    CURRENT_MESSAGE=""
    clear_on_success=1
  elif [[ "$CURRENT_ACTION" == "check" ]]; then
    clear_on_success=1
  fi
  CURRENT_MODE="$requested_mode"

  collect_changed_files
  if ((${#CHANGED_FILES[@]} == 0)); then
    if [[ "$requested_mode" == "full" ]]; then
      CURRENT_MODE="full"
      run_full_checks "$no_cache"
    else
      ok "working tree is clean; nothing requires local validation"
    fi
    ((clear_on_success == 0)) || state_clear
    return 0
  fi

  run_step "Regenerate release checksums" generate_checksums
  collect_changed_files
  resolve_mode "$requested_mode"
  CURRENT_MODE="$SELECTED_MODE"
  state_write "$CURRENT_ACTION" "$CURRENT_MODE" "fast validation" "$CURRENT_MESSAGE"
  run_fast_checks

  if [[ "$SELECTED_MODE" == "full" ]]; then
    run_full_checks "$no_cache"
  else
    ok "fast validation passed; protected PR CI remains the complete gate"
  fi
  ((clear_on_success == 0)) || state_clear
}

cmd_status() {
  local branch
  branch="$(branch_name)"
  collect_changed_files
  classify_mode
  heading "Repository Workflow Status"
  info "Repository" "$ROOT_DIR"
  info "Branch" "${branch:-detached HEAD}"
  info "Upstream" "$(upstream_status)"
  info "Working tree" "${#CHANGED_FILES[@]} changed file(s)"
  info "Validation mode" "$SELECTED_MODE"
  info "Saved operation" "$(saved_state_summary)"
  if ((${#CHANGED_FILES[@]} > 0)); then
    echo
    echo "Changed files:"
    printf '  %s\n' "${CHANGED_FILES[@]}"
  fi
}

cmd_explain() {
  collect_changed_files
  classify_mode
  heading "Validation Selection"
  info "Selected mode" "$SELECTED_MODE"
  if ((${#CHANGED_FILES[@]} == 0)); then
    info "Reason" "working tree is clean"
  elif ((${#RISK_REASONS[@]} == 0)); then
    info "Reason" "no high-risk release, security, workflow, or automation path changed"
  else
    echo "Reasons:"
    printf '  %s\n' "${RISK_REASONS[@]}"
  fi
}

parse_mode_options() {
  PARSED_MODE="auto"
  PARSED_NO_CACHE=0
  PARSED_DRY_RUN=0
  PARSED_NO_PUSH=0
  PARSED_MESSAGE=""
  while (($# > 0)); do
    case "$1" in
      --fast) PARSED_MODE="fast" ;;
      --full) PARSED_MODE="full" ;;
      --mode)
        shift
        (($# > 0)) || fail "--mode requires auto, fast, or full"
        PARSED_MODE="$1"
        ;;
      --no-cache) PARSED_NO_CACHE=1 ;;
      --dry-run) PARSED_DRY_RUN=1 ;;
      --no-push) PARSED_NO_PUSH=1 ;;
      -m | --message)
        shift
        (($# > 0)) || fail "--message requires a commit message"
        PARSED_MESSAGE="$1"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown option: $1" ;;
    esac
    shift
  done
  case "$PARSED_MODE" in
    auto | fast | full) ;;
    *) fail "invalid validation mode: $PARSED_MODE" ;;
  esac
}

ensure_publish_branch() {
  local branch="$1"
  [[ -n "$branch" ]] || fail "cannot publish from detached HEAD"
  if is_protected_branch "$branch"; then
    fail "publish is blocked on protected branch '${branch}'; use a feature or documentation branch"
  fi
  return 0
}

fetch_and_check_sync() {
  local branch="$1" upstream counts behind
  git fetch origin --prune
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [[ -n "$upstream" ]] || return 0
  counts="$(git rev-list --left-right --count "${upstream}...HEAD")"
  behind="${counts%%[[:space:]]*}"
  [[ "$behind" == "0" ]] \
    || fail "branch is ${behind} commit(s) behind ${upstream}; update it before publishing"
  [[ "$upstream" == "origin/${branch}" ]] \
    || warn "upstream is ${upstream}, not origin/${branch}"
}

push_branch() {
  local branch="$1"
  git push -u origin "$branch"
}

cmd_check() {
  parse_mode_options "$@"
  CURRENT_ACTION="check"
  CURRENT_MODE="$PARSED_MODE"
  CURRENT_MESSAGE=""
  perform_check "$PARSED_MODE" "$PARSED_NO_CACHE"
}

cmd_publish() {
  local branch
  parse_mode_options "$@"
  [[ -n "$PARSED_MESSAGE" ]] || fail "publish requires -m \"Commit message\""
  branch="$(branch_name)"
  ensure_publish_branch "$branch"

  CURRENT_ACTION="publish"
  CURRENT_MODE="$PARSED_MODE"
  CURRENT_MESSAGE="$PARSED_MESSAGE"
  state_write "$CURRENT_ACTION" "$CURRENT_MODE" "preflight" "$CURRENT_MESSAGE"

  collect_changed_files
  if ((${#CHANGED_FILES[@]} == 0)); then
    fail "working tree is clean; there is nothing to commit"
  fi

  run_step "Remote synchronization" fetch_and_check_sync "$branch"

  # perform_check clears state on success, so restore publish state afterward.
  perform_check "$PARSED_MODE" "$PARSED_NO_CACHE"
  resolve_mode "$PARSED_MODE"
  CURRENT_ACTION="publish"
  CURRENT_MODE="$SELECTED_MODE"
  CURRENT_MESSAGE="$PARSED_MESSAGE"
  state_write "$CURRENT_ACTION" "$CURRENT_MODE" "stage" "$CURRENT_MESSAGE"

  heading "Stage repository changes"
  git add -A
  git diff --cached --check
  git diff --cached --quiet \
    && fail "no staged changes remain after validation"
  git diff --cached --stat

  if [[ "$PARSED_DRY_RUN" == "1" ]]; then
    ok "dry run complete; changes are staged but not committed or pushed"
    state_clear
    return 0
  fi

  run_step "Create commit" git commit -m "$PARSED_MESSAGE"

  if [[ "$PARSED_NO_PUSH" == "1" ]]; then
    ok "commit created; push skipped by --no-push"
    state_clear
    return 0
  fi

  run_step "Push branch" push_branch "$branch"
  state_clear
  heading "Repository update complete"
  info "Branch" "$branch"
  info "Commit" "$(git rev-parse --short HEAD)"
  info "Upstream" "origin/${branch}"
  ok "validated, committed, and pushed"
}

cmd_work_start() {
  local branch="${1:-}" base="main"
  [[ -n "$branch" ]] || fail "work start requires a branch name"
  shift || true

  while (($# > 0)); do
    case "$1" in
      --base)
        shift
        (($# > 0)) || fail "--base requires a branch name"
        base="$1"
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *) fail "unknown work start option: $1" ;;
    esac
    shift
  done

  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree must be clean before starting work"
  is_protected_branch "$branch" \
    && fail "work branch must not be protected: ${branch}"

  heading "Start Work"
  git fetch --prune origin
  git switch "$base"
  git pull --ff-only origin "$base"

  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    fail "local branch already exists: ${branch}"
  fi
  if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    fail "remote branch already exists: origin/${branch}"
  fi

  git switch -c "$branch"
  heading "Work Branch Ready"
  info "Branch" "$branch"
  info "Base" "$base"
  info "Validation" "automatic risk-based selection"
  ok "start making changes, then run: ${PROGRAM} work finish -m \"Commit message\""
}

parse_work_finish_options() {
  WORK_MESSAGE=""
  WORK_PR_TITLE=""
  WORK_PR_BODY=""
  WORK_PR_BODY_FILE=""
  WORK_BASE="main"
  WORK_MODE="auto"
  WORK_NO_CACHE=0
  WORK_NO_WATCH=0
  WORK_DRY_RUN=0

  while (($# > 0)); do
    case "$1" in
      -m | --message)
        shift
        (($# > 0)) || fail "$1 requires text"
        WORK_MESSAGE="$1"
        ;;
      --pr-title)
        shift
        (($# > 0)) || fail "--pr-title requires text"
        WORK_PR_TITLE="$1"
        ;;
      --pr-body)
        shift
        (($# > 0)) || fail "--pr-body requires text"
        WORK_PR_BODY="$1"
        ;;
      --pr-body-file)
        shift
        (($# > 0)) || fail "--pr-body-file requires a path"
        WORK_PR_BODY_FILE="$1"
        ;;
      --base)
        shift
        (($# > 0)) || fail "--base requires a branch name"
        WORK_BASE="$1"
        ;;
      --fast) WORK_MODE="fast" ;;
      --full) WORK_MODE="full" ;;
      --mode)
        shift
        (($# > 0)) || fail "--mode requires auto, fast, or full"
        WORK_MODE="$1"
        ;;
      --no-cache) WORK_NO_CACHE=1 ;;
      --no-watch) WORK_NO_WATCH=1 ;;
      --dry-run) WORK_DRY_RUN=1 ;;
      -h | --help)
        usage
        return 0
        ;;
      *) fail "unknown work finish option: $1" ;;
    esac
    shift
  done

  [[ -n "$WORK_MESSAGE" ]] || fail "work finish requires -m \"Commit message\""
  [[ -z "$WORK_PR_BODY" || -z "$WORK_PR_BODY_FILE" ]] \
    || fail "--pr-body and --pr-body-file cannot be used together"
  [[ -z "$WORK_PR_BODY_FILE" || -f "$WORK_PR_BODY_FILE" ]] \
    || fail "PR body file does not exist: $WORK_PR_BODY_FILE"
  case "$WORK_MODE" in auto | fast | full) ;; *) fail "invalid validation mode: $WORK_MODE" ;; esac
  [[ -n "$WORK_PR_TITLE" ]] || WORK_PR_TITLE="$WORK_MESSAGE"
}

cmd_work_finish() {
  local -a check_args publish_args pr_args
  parse_work_finish_options "$@"

  heading "Finish Work"
  if [[ "$WORK_DRY_RUN" == "1" ]]; then
    info "Mode" "$WORK_MODE"
    info "Commit" "$WORK_MESSAGE"
    info "PR title" "$WORK_PR_TITLE"
    check_args=(--mode "$WORK_MODE")
    [[ "$WORK_NO_CACHE" == "0" ]] || check_args+=(--no-cache)
    cmd_check "${check_args[@]}"
    ok "dry run complete; no commit, push, or pull request was created"
    return 0
  fi

  publish_args=(--mode "$WORK_MODE" -m "$WORK_MESSAGE")
  [[ "$WORK_NO_CACHE" == "0" ]] || publish_args+=(--no-cache)
  cmd_publish "${publish_args[@]}"

  pr_args=(--base "$WORK_BASE" --title "$WORK_PR_TITLE")
  [[ -z "$WORK_PR_BODY" ]] || pr_args+=(--body "$WORK_PR_BODY")
  [[ -z "$WORK_PR_BODY_FILE" ]] || pr_args+=(--body-file "$WORK_PR_BODY_FILE")
  cmd_pr_create "${pr_args[@]}"

  if [[ "$WORK_NO_WATCH" == "0" ]]; then
    cmd_pr_checks --watch --required
  fi

  heading "Work Ready to Land"
  info "Branch" "$(branch_name)"
  info "Commit" "$(git rev-parse --short HEAD)"
  info "Next" "${PROGRAM} work land --confirm --delete-branch"
  ok "publication and pull-request workflow completed"
}

repository_name_with_owner() {
  gh repo view --json nameWithOwner --jq '.nameWithOwner'
}

branch_requires_linear_history() {
  local repo="$1" base="$2" value
  value="$(gh api "repos/${repo}/branches/${base}/protection" --jq '.required_linear_history.enabled // false' 2>/dev/null || printf 'false')"
  [[ "$value" == "true" ]]
}

cmd_work_land() {
  local confirm=0 delete_branch=0 base="main" branch number repo strategy="merge" state merge_status review
  while (($# > 0)); do
    case "$1" in
      --confirm) confirm=1 ;;
      --delete-branch) delete_branch=1 ;;
      --base)
        shift
        (($# > 0)) || fail "--base requires a branch name"
        base="$1"
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *) fail "unknown work land option: $1" ;;
    esac
    shift
  done
  [[ "$confirm" == "1" ]] || fail "work land requires --confirm"

  require_gh
  branch="$(branch_name)"
  ensure_pr_branch "$branch"
  ensure_clean_tree_for_pr
  number="$(require_open_pr_number "$branch")"

  heading "Land Work"
  pr_show_check_summary "$number"
  gh pr checks "$number" --required \
    || fail "required pull request checks are not successful; rerun: ${PROGRAM} pr checks --watch --required"

  IFS='|' read -r state merge_status review < <(
    gh pr view "$number" --json state,mergeStateStatus,reviewDecision \
      --jq '"\(.state)|\(.mergeStateStatus)|\(.reviewDecision // "")"'
  )
  [[ "$state" == "OPEN" ]] || fail "pull request is not open: ${state}"
  if [[ "$review" == "REVIEW_REQUIRED" ]]; then
    fail "pull request still requires an independent review; adjust the documented single-maintainer policy or obtain approval"
  fi
  case "$merge_status" in
    BLOCKED | DIRTY | BEHIND)
      fail "pull request cannot be landed yet (merge status: ${merge_status})"
      ;;
  esac

  repo="$(repository_name_with_owner)"
  if branch_requires_linear_history "$repo" "$base"; then
    strategy="squash"
  fi

  local -a merge_args=(pr merge "$number" "--${strategy}")
  [[ "$delete_branch" == "0" ]] || merge_args+=(--delete-branch)
  gh "${merge_args[@]}"

  git switch "$base"
  git pull --ff-only origin "$base"
  git fetch --prune origin

  heading "Work Landed"
  info "PR" "#${number}"
  info "Strategy" "$strategy"
  info "Branch" "$base"
  info "Commit" "$(git rev-parse --short HEAD)"
  ok "pull request merged and local ${base} synchronized"
}

cmd_work() {
  local subcommand="${1:-}"
  [[ -n "$subcommand" ]] || fail "work requires start, finish, or land"
  shift || true
  case "$subcommand" in
    start) cmd_work_start "$@" ;;
    finish) cmd_work_finish "$@" ;;
    land) cmd_work_land "$@" ;;
    -h | --help | help) usage ;;
    *) fail "unknown work command: $subcommand" ;;
  esac
}

require_gh() {
  command -v gh >/dev/null 2>&1 \
    || fail "GitHub CLI (gh) is required for pull request commands"
  gh auth status >/dev/null 2>&1 \
    || fail "GitHub CLI is not authenticated; run: gh auth login"
}

ensure_pr_branch() {
  local branch="$1"
  [[ -n "$branch" ]] || fail "cannot manage a pull request from detached HEAD"
  case "$branch" in
    main | master | beta)
      fail "pull request operations require a feature, documentation, or release branch; current branch: ${branch}"
      ;;
  esac
}

ensure_clean_tree_for_pr() {
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree is not clean; publish or commit changes before creating a PR"
}

ensure_remote_branch() {
  local branch="$1"
  git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1 \
    || fail "origin/${branch} does not exist; publish or push the branch first"
}

pr_number_for_branch() {
  local branch="$1"
  gh pr list \
    --head "$branch" \
    --state open \
    --json number \
    --limit 1 \
    --jq '.[0].number // empty'
}

pr_url_for_branch() {
  local branch="$1"
  gh pr list \
    --head "$branch" \
    --state open \
    --json url \
    --limit 1 \
    --jq '.[0].url // empty'
}

require_open_pr_number() {
  local branch="$1" number
  number="$(pr_number_for_branch "$branch")"
  [[ -n "$number" ]] \
    || fail "no open pull request exists for branch '${branch}'; create one with: ${PROGRAM} pr create"
  printf '%s\n' "$number"
}

pr_check_counts_from_text() {
  local output="$1" line name state remainder
  local cancelled=0 failed=0 passed=0 skipped=0 pending=0 total=0

  while IFS= read -r line; do
    [[ "$line" == *$'\t'* ]] || continue
    IFS=$'\t' read -r name state remainder <<<"$line"
    [[ -n "$name" && -n "$remainder" ]] || continue

    case "${state,,}" in
      pass)
        passed=$((passed + 1))
        ;;
      pending)
        pending=$((pending + 1))
        ;;
      fail)
        failed=$((failed + 1))
        ;;
      cancel)
        cancelled=$((cancelled + 1))
        ;;
      skipping)
        skipped=$((skipped + 1))
        ;;
      *)
        continue
        ;;
    esac
    total=$((total + 1))
  done <<<"$output"

  if ((total > 0)); then
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$total" "$passed" "$pending" "$((cancelled + failed))" "$skipped"
    return 0
  fi

  while IFS= read -r line; do
    if [[ "$line" =~ ^([0-9]+)[[:space:]]+cancelled,[[:space:]]+([0-9]+)[[:space:]]+failing,[[:space:]]+([0-9]+)[[:space:]]+successful,[[:space:]]+([0-9]+)[[:space:]]+skipped,[[:space:]]+and[[:space:]]+([0-9]+)[[:space:]]+pending[[:space:]]+checks?$ ]]; then
      cancelled="${BASH_REMATCH[1]}"
      failed="${BASH_REMATCH[2]}"
      passed="${BASH_REMATCH[3]}"
      skipped="${BASH_REMATCH[4]}"
      pending="${BASH_REMATCH[5]}"
      total=$((cancelled + failed + passed + skipped + pending))
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$total" "$passed" "$pending" "$((cancelled + failed))" "$skipped"
      return 0
    fi

    if [[ "$line" =~ ^([0-9]+)[[:space:]]+failing,[[:space:]]+([0-9]+)[[:space:]]+successful,[[:space:]]+([0-9]+)[[:space:]]+skipped,[[:space:]]+and[[:space:]]+([0-9]+)[[:space:]]+pending[[:space:]]+checks?$ ]]; then
      failed="${BASH_REMATCH[1]}"
      passed="${BASH_REMATCH[2]}"
      skipped="${BASH_REMATCH[3]}"
      pending="${BASH_REMATCH[4]}"
      total=$((failed + passed + skipped + pending))
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$total" "$passed" "$pending" "$failed" "$skipped"
      return 0
    fi

    if [[ "${line,,}" == *"no checks reported"* ]]; then
      printf '0\t0\t0\t0\t0\n'
      return 0
    fi
  done <<<"$output"

  return 1
}

pr_check_counts() {
  local number="$1" scope="$2" output
  local -a args=(
    pr checks "$number"
    --json bucket
    --jq '[length,
      (map(select(.bucket == "pass")) | length),
      (map(select(.bucket == "pending")) | length),
      (map(select(.bucket == "fail" or .bucket == "cancel")) | length),
      (map(select(.bucket == "skipping")) | length)] | @tsv'
  )
  [[ "$scope" == "all" ]] || args+=(--required)
  output="$(gh "${args[@]}" 2>/dev/null || true)"
  if [[ "$output" =~ ^[0-9]+$'\t'[0-9]+$'\t'[0-9]+$'\t'[0-9]+$'\t'[0-9]+$ ]]; then
    printf '%s\n' "$output"
    return 0
  fi

  args=(pr checks "$number")
  [[ "$scope" == "all" ]] || args+=(--required)
  output="$(NO_COLOR=1 LC_ALL=C gh "${args[@]}" 2>&1 || true)"
  pr_check_counts_from_text "$output" \
    || fail "could not calculate ${scope} pull request check counts"
}

pr_show_check_summary() {
  local number="$1"
  local all_total all_pass all_pending all_fail all_skipped
  local required_total required_pass required_pending required_fail required_skipped
  local informational

  IFS=$'\t' read -r all_total all_pass all_pending all_fail all_skipped < <(
    pr_check_counts "$number" all
  )
  IFS=$'\t' read -r required_total required_pass required_pending required_fail required_skipped < <(
    pr_check_counts "$number" required
  )
  informational=$((all_total - required_total))
  ((informational >= 0)) \
    || fail "required check count exceeds all reported checks"

  info "Checks" "${all_pass} passed, ${all_pending} pending, ${all_fail} failed, ${all_skipped} skipped (${all_total} reported)"
  info "Required checks" "${required_pass} passed, ${required_pending} pending, ${required_fail} failed, ${required_skipped} skipped (${required_total} required)"
  info "Informational checks" "${informational} reported"

  PR_REQUIRED_PENDING="$required_pending"
  PR_REQUIRED_FAIL="$required_fail"
}

parse_pr_create_options() {
  PR_BASE="main"
  PR_TITLE=""
  PR_BODY=""
  PR_BODY_FILE=""
  PR_DRAFT=0
  PR_FILL=1

  while (($# > 0)); do
    case "$1" in
      --base)
        shift
        (($# > 0)) || fail "--base requires a branch name"
        PR_BASE="$1"
        ;;
      --title)
        shift
        (($# > 0)) || fail "--title requires text"
        PR_TITLE="$1"
        ;;
      --body)
        shift
        (($# > 0)) || fail "--body requires text"
        PR_BODY="$1"
        ;;
      --body-file)
        shift
        (($# > 0)) || fail "--body-file requires a path"
        PR_BODY_FILE="$1"
        ;;
      --draft) PR_DRAFT=1 ;;
      --fill) PR_FILL=1 ;;
      --no-fill) PR_FILL=0 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown pr create option: $1" ;;
    esac
    shift
  done

  [[ -z "$PR_BODY" || -z "$PR_BODY_FILE" ]] \
    || fail "--body and --body-file cannot be used together"
  if [[ -n "$PR_BODY_FILE" ]]; then
    [[ -f "$PR_BODY_FILE" ]] || fail "PR body file does not exist: $PR_BODY_FILE"
  fi
  if [[ "$PR_FILL" == "0" && -z "$PR_TITLE" ]]; then
    fail "pr create --no-fill requires --title"
  fi
}

cmd_pr_create() {
  local branch existing_url url
  local -a args

  parse_pr_create_options "$@"
  require_gh
  branch="$(branch_name)"
  ensure_pr_branch "$branch"
  ensure_clean_tree_for_pr

  heading "Pull Request Preflight"
  fetch_and_check_sync "$branch"
  ensure_remote_branch "$branch"

  existing_url="$(pr_url_for_branch "$branch")"
  if [[ -n "$existing_url" ]]; then
    heading "Pull Request"
    info "Branch" "$branch"
    info "Status" "already open"
    info "URL" "$existing_url"
    ok "reusing existing pull request"
    return 0
  fi

  args=(pr create --base "$PR_BASE" --head "$branch")
  [[ "$PR_FILL" == "0" ]] || args+=(--fill)
  [[ -z "$PR_TITLE" ]] || args+=(--title "$PR_TITLE")
  [[ -z "$PR_BODY" ]] || args+=(--body "$PR_BODY")
  [[ -z "$PR_BODY_FILE" ]] || args+=(--body-file "$PR_BODY_FILE")
  [[ "$PR_DRAFT" == "0" ]] || args+=(--draft)

  url="$(gh "${args[@]}")"

  heading "Pull Request Created"
  info "Branch" "$branch"
  info "Base" "$PR_BASE"
  info "URL" "$url"
  ok "pull request ready for CI"
}

cmd_pr_status() {
  local branch number metadata
  local pr_number title url state draft merge_status head base next_action
  local -a metadata_fields
  (($# == 0)) || fail "pr status does not accept options"

  require_gh
  branch="$(branch_name)"
  ensure_pr_branch "$branch"
  number="$(require_open_pr_number "$branch")"

  heading "Pull Request Status"
  metadata="$(
    gh pr view "$number" \
      --json number,url,state,isDraft,mergeStateStatus,title,headRefName,baseRefName \
      --jq '[.number, .title, .url, .state, .isDraft, .mergeStateStatus, .headRefName, .baseRefName] | .[]'
  )"
  mapfile -t metadata_fields <<<"$metadata"
  ((${#metadata_fields[@]} == 8)) || fail "GitHub returned incomplete pull request metadata"
  pr_number="${metadata_fields[0]}"
  title="${metadata_fields[1]}"
  url="${metadata_fields[2]}"
  state="${metadata_fields[3]}"
  draft="${metadata_fields[4]}"
  merge_status="${metadata_fields[5]}"
  head="${metadata_fields[6]}"
  base="${metadata_fields[7]}"

  printf 'PR #%s: %s\n' "$pr_number" "$title"
  info "URL" "$url"
  info "State" "$state"
  info "Draft" "$draft"
  info "Branch" "${head} → ${base}"
  pr_show_check_summary "$number"
  info "Merge state" "$merge_status"

  if [[ "$state" != "OPEN" ]]; then
    next_action="No action; pull request state is ${state}."
  elif ((PR_REQUIRED_FAIL > 0)); then
    next_action="${PROGRAM} pr checks --required"
  elif ((PR_REQUIRED_PENDING > 0)); then
    next_action="${PROGRAM} pr checks --watch --required"
  elif [[ "$merge_status" == "CLEAN" || "$merge_status" == "HAS_HOOKS" ]]; then
    next_action="${PROGRAM} pr merge --delete-branch"
  else
    next_action="Resolve merge state ${merge_status}, then rerun ${PROGRAM} pr status."
  fi
  info "Next action" "$next_action"
}

cmd_pr_checks() {
  local branch number watch=0 required=0
  local -a args

  while (($# > 0)); do
    case "$1" in
      --watch) watch=1 ;;
      --required) required=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown pr checks option: $1" ;;
    esac
    shift
  done

  require_gh
  branch="$(branch_name)"
  ensure_pr_branch "$branch"
  number="$(require_open_pr_number "$branch")"

  args=(pr checks "$number")
  [[ "$watch" == "0" ]] || args+=(--watch)
  [[ "$required" == "0" ]] || args+=(--required)

  heading "Pull Request Checks"
  gh "${args[@]}"
}

cmd_pr_merge() {
  local branch number strategy="merge" admin=0 delete_branch=0
  local -a args

  while (($# > 0)); do
    case "$1" in
      --merge) strategy="merge" ;;
      --squash) strategy="squash" ;;
      --rebase) strategy="rebase" ;;
      --admin) admin=1 ;;
      --delete-branch) delete_branch=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown pr merge option: $1" ;;
    esac
    shift
  done

  require_gh
  branch="$(branch_name)"
  ensure_pr_branch "$branch"
  ensure_clean_tree_for_pr
  number="$(require_open_pr_number "$branch")"

  heading "Required Pull Request Checks"
  pr_show_check_summary "$number"
  if ! gh pr checks "$number" --required; then
    fail "required pull request checks are not successful; rerun: ${PROGRAM} pr checks --watch --required"
  fi

  args=(pr merge "$number" "--${strategy}")
  [[ "$admin" == "0" ]] || args+=(--admin)
  [[ "$delete_branch" == "0" ]] || args+=(--delete-branch)

  heading "Merge Pull Request"
  gh "${args[@]}"
  ok "pull request merge completed"
}

cmd_pr() {
  local subcommand="${1:-status}"
  if (($# > 0)); then
    shift
  fi

  case "$subcommand" in
    create) cmd_pr_create "$@" ;;
    status) cmd_pr_status "$@" ;;
    checks) cmd_pr_checks "$@" ;;
    merge) cmd_pr_merge "$@" ;;
    -h | --help | help) usage ;;
    *) fail "unknown pr command: $subcommand" ;;
  esac
}

parse_release_read_options() {
  RELEASE_OFFLINE=0

  while (($# > 0)); do
    case "$1" in
      --offline) RELEASE_OFFLINE=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown release status option: $1" ;;
    esac
    shift
  done
}

release_saved_phase() {
  local target_tag="$1" phase
  if release_state_matches_target "$target_tag"; then
    phase="$(release_state_value phase)"
    case "$phase" in
      beta-preparation | beta-pr | beta-pretag | beta-tagged | beta-published | beta-verified | \
        stable-promotion | stable-pr | stable-pretag | stable-tagged | stable-published | stable-verified)
        printf '%s\n' "$phase"
        return 0
        ;;
    esac
  fi
  return 1
}

release_github_release_exists() {
  [[ "$RELEASE_GITHUB_RELEASE_STATE" == "published" ||
    "$RELEASE_GITHUB_RELEASE_STATE" == "prerelease" ]]
}

release_resolve_phase() {
  local saved="" prefix tag_channel
  saved="$(release_saved_phase "$RELEASE_TAG" || true)"
  tag_channel="$(scripts/release-version.sh channel-for-tag "$RELEASE_TAG" 2>/dev/null || true)"
  if [[ "$tag_channel" == "stable" ]]; then
    prefix="stable"
  else
    prefix="beta"
  fi

  if release_github_release_exists; then
    if [[ "$(release_state_value verified_commit)" == "$RELEASE_REMOTE_TAG_COMMIT" &&
    -n "$RELEASE_REMOTE_TAG_COMMIT" ]]; then
      printf '%s\n' "${prefix}-verified"
    else
      printf '%s\n' "${prefix}-published"
    fi
  elif [[ "$RELEASE_REMOTE_TAG" == "exists" || "$RELEASE_LOCAL_TAG" == "exists" ]]; then
    printf '%s\n' "${prefix}-tagged"
  elif [[ "$RELEASE_CHANNEL" == "stable" && "$RELEASE_BRANCH" == "main" ]]; then
    printf '%s\n' "stable-pretag"
  elif [[ -n "$saved" ]]; then
    printf '%s\n' "$saved"
  elif [[ "$RELEASE_CHANNEL" == "stable" ]]; then
    if [[ "$RELEASE_BRANCH" == "release/v${RELEASE_VERSION%%-*}" ]]; then
      printf '%s\n' "stable-promotion"
    else
      printf '%s\n' "stable-pretag"
    fi
  else
    printf '%s\n' "beta-preparation"
  fi
}

release_expected_branch() {
  local version="$1" channel="$2" phase="${3:-}" base_version
  base_version="${version%%-*}"

  case "$phase" in
    beta-preparation | beta-pr | stable-promotion | stable-pr)
      printf '%s\n' "release/v${base_version}"
      ;;
    beta-pretag | beta-tagged | beta-published | beta-verified | \
      stable-pretag | stable-tagged | stable-published | stable-verified)
      printf '%s\n' "main"
      ;;
    *)
      case "$channel" in
        stable) printf '%s\n' "main" ;;
        *) printf '%s\n' "release/v${base_version}" ;;
      esac
      ;;
  esac
}

release_validation_phase() {
  case "$(release_state_value phase)" in
    stable-promotion | stable-pr) printf '%s\n' "stable-promotion" ;;
    stable-pretag | stable-tagged | stable-published | stable-verified)
      printf '%s\n' "stable-pretag"
      ;;
    *) printf '%s\n' "" ;;
  esac
}

release_run_with_context() {
  local phase channel target_tag source_tag
  phase="$(release_validation_phase)"
  channel="$(release_state_value channel)"
  target_tag="$(release_state_value target_tag)"
  source_tag="$(release_state_value source_tag)"

  (
    [[ -z "$phase" ]] || export ERPNEXT_RELEASE_PHASE="$phase"
    [[ -z "$channel" ]] || export ERPNEXT_RELEASE_CHANNEL="$channel"
    [[ -z "$target_tag" ]] || export ERPNEXT_RELEASE_TAG="$target_tag"
    [[ -z "$source_tag" ]] || export ERPNEXT_RELEASE_SOURCE_TAG="$source_tag"
    [[ -z "$phase" ]] || export RELEASE_STRICT=1
    "$@"
  )
}

release_refresh_remote() {
  if [[ "$RELEASE_OFFLINE" == "1" ]]; then
    RELEASE_REMOTE_REFRESH="skipped (--offline)"
    return 0
  fi

  if ! git remote get-url origin >/dev/null 2>&1; then
    RELEASE_REMOTE_REFRESH="unavailable (origin is missing)"
    return 0
  fi

  if git fetch --quiet origin --prune --tags; then
    RELEASE_REMOTE_REFRESH="updated"
  else
    RELEASE_REMOTE_REFRESH="failed"
  fi
}

release_collect_sync_state() {
  local counts

  RELEASE_UPSTREAM="$(
    git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' \
      2>/dev/null || true
  )"
  RELEASE_AHEAD="unknown"
  RELEASE_BEHIND="unknown"
  RELEASE_SYNC="no upstream"

  if [[ -n "$RELEASE_UPSTREAM" ]]; then
    counts="$(git rev-list --left-right --count "${RELEASE_UPSTREAM}...HEAD")"
    RELEASE_BEHIND="${counts%%[[:space:]]*}"
    RELEASE_AHEAD="${counts##*[[:space:]]}"
    RELEASE_SYNC="${RELEASE_UPSTREAM}; ahead ${RELEASE_AHEAD}, behind ${RELEASE_BEHIND}"
  fi
}

release_collect_remote_tag_state() {
  local rc

  RELEASE_REMOTE_TAG_COMMIT=""
  if [[ "$RELEASE_OFFLINE" == "1" ]]; then
    RELEASE_REMOTE_TAG="unchecked (--offline)"
    return 0
  fi

  if ! git remote get-url origin >/dev/null 2>&1; then
    RELEASE_REMOTE_TAG="unavailable (origin is missing)"
    return 0
  fi

  set +e
  git ls-remote --exit-code --tags origin \
    "refs/tags/${RELEASE_TAG}" >/dev/null 2>&1
  rc=$?
  set -e

  case "$rc" in
    0)
      RELEASE_REMOTE_TAG="exists"
      RELEASE_REMOTE_TAG_COMMIT="$(release_remote_tag_commit "$RELEASE_TAG")"
      ;;
    2) RELEASE_REMOTE_TAG="missing" ;;
    *) RELEASE_REMOTE_TAG="unavailable" ;;
  esac
}

release_collect_github_release_state() {
  local output rc url is_draft is_prerelease published_at state

  if [[ "$RELEASE_OFFLINE" == "1" ]]; then
    RELEASE_GITHUB_RELEASE="unchecked (--offline)"
    RELEASE_GITHUB_RELEASE_STATE="unchecked"
    return 0
  fi

  if ! command -v gh >/dev/null 2>&1; then
    RELEASE_GITHUB_RELEASE="unavailable (gh is not installed)"
    RELEASE_GITHUB_RELEASE_STATE="unavailable"
    return 0
  fi

  if ! gh auth status >/dev/null 2>&1; then
    RELEASE_GITHUB_RELEASE="unavailable (gh is not authenticated)"
    RELEASE_GITHUB_RELEASE_STATE="unavailable"
    return 0
  fi

  set +e
  output="$(
    gh release view "$RELEASE_TAG" \
      --json url,isDraft,isPrerelease,publishedAt \
      --jq '"\(.url)|\(.isDraft)|\(.isPrerelease)|\(.publishedAt // "")"' \
      2>/dev/null
  )"
  rc=$?
  set -e

  if ((rc != 0)); then
    RELEASE_GITHUB_RELEASE="missing"
    RELEASE_GITHUB_RELEASE_STATE="missing"
    return 0
  fi

  IFS='|' read -r url is_draft is_prerelease published_at <<<"$output"
  if [[ "$is_draft" == "true" ]]; then
    state="draft"
  elif [[ "$is_prerelease" == "true" ]]; then
    state="prerelease"
  else
    state="published"
  fi

  RELEASE_GITHUB_RELEASE_STATE="$state"
  RELEASE_GITHUB_RELEASE="${state}"
  [[ -z "$published_at" ]] || RELEASE_GITHUB_RELEASE+="; ${published_at}"
  [[ -z "$url" ]] || RELEASE_GITHUB_RELEASE+="; ${url}"
}

release_add_blocker() {
  RELEASE_BLOCKERS+=("$1")
}

release_compute_next_action() {
  local pretag_command

  pretag_command="${PROGRAM} release pretag ${RELEASE_TAG}"
  [[ "$RELEASE_OFFLINE" == "0" ]] || pretag_command+=" --offline"

  if release_github_release_exists; then
    RELEASE_READINESS="complete"
    if [[ "$RELEASE_PHASE" == *-verified ]]; then
      RELEASE_NEXT_ACTION="No action required; ${RELEASE_TAG} is published and verified."
    else
      RELEASE_NEXT_ACTION="${PROGRAM} release verify ${RELEASE_TAG}"
    fi
    return 0
  fi

  if [[ "$RELEASE_REMOTE_TAG" == "exists" ]]; then
    if [[ -z "$RELEASE_REMOTE_TAG_COMMIT" ]]; then
      RELEASE_READINESS="blocked; remote tag is not annotated"
      RELEASE_NEXT_ACTION="Inspect ${RELEASE_TAG}; protected releases require an annotated tag."
    elif [[ "$RELEASE_REMOTE_TAG_COMMIT" != "$RELEASE_HEAD_COMMIT" ]]; then
      RELEASE_READINESS="blocked; remote tag points to another commit"
      RELEASE_NEXT_ACTION="Inspect ${RELEASE_TAG}; never move or overwrite a published tag."
    else
      RELEASE_READINESS="tag exists; release verification required"
      RELEASE_NEXT_ACTION="${PROGRAM} release watch ${RELEASE_TAG}"
    fi
    return 0
  fi

  if [[ "$RELEASE_LOCAL_TAG" == "exists" ]]; then
    if [[ "$RELEASE_LOCAL_TAG_TYPE" != "tag" ]]; then
      RELEASE_READINESS="blocked; local tag is not annotated"
      RELEASE_NEXT_ACTION="Inspect the local ${RELEASE_TAG}; protected releases require an annotated tag."
    elif [[ "$RELEASE_LOCAL_TAG_COMMIT" != "$RELEASE_HEAD_COMMIT" ]]; then
      RELEASE_READINESS="blocked; local tag points to another commit"
      RELEASE_NEXT_ACTION="Inspect the local ${RELEASE_TAG}; it does not match HEAD."
    else
      RELEASE_READINESS="matching local tag is ready to push"
      RELEASE_NEXT_ACTION="${PROGRAM} release tag --confirm ${RELEASE_TAG}"
    fi
    return 0
  fi

  if [[ "$RELEASE_PHASE" == "beta-pr" || "$RELEASE_PHASE" == "stable-pr" ]]; then
    RELEASE_READINESS="release commit is ready for exact PR reconciliation"
    RELEASE_NEXT_ACTION="${PROGRAM} release run"
    return 0
  fi

  if ((${#RELEASE_BLOCKERS[@]} > 0)); then
    RELEASE_READINESS="blocked (${#RELEASE_BLOCKERS[@]} condition(s))"

    if [[ "$RELEASE_WORKTREE" != "clean" ]]; then
      RELEASE_NEXT_ACTION='Publish or commit the current changes before release validation.'
    elif [[ "$RELEASE_BRANCH" != "$RELEASE_EXPECTED_BRANCH" ]]; then
      if [[ "$RELEASE_CHANNEL" == "stable" ]]; then
        RELEASE_NEXT_ACTION="Merge the current branch, then switch to synchronized main."
      else
        RELEASE_NEXT_ACTION="Switch to or create ${RELEASE_EXPECTED_BRANCH}."
      fi
    elif [[ "$RELEASE_UPSTREAM" == "" ]]; then
      RELEASE_NEXT_ACTION="Push ${RELEASE_BRANCH} and configure origin/${RELEASE_BRANCH} as its upstream."
    elif [[ "$RELEASE_BEHIND" != "0" || "$RELEASE_AHEAD" != "0" ]]; then
      RELEASE_NEXT_ACTION="Synchronize ${RELEASE_BRANCH} with ${RELEASE_UPSTREAM}."
    else
      RELEASE_NEXT_ACTION="Resolve the blocking conditions listed by: ${PROGRAM} release explain"
    fi
    return 0
  fi

  if [[ "$RELEASE_PRETAG_PROOF" == "valid for exact commit" ]]; then
    RELEASE_READINESS="pre-tag validation passed for exact commit"
    RELEASE_NEXT_ACTION="${PROGRAM} release tag --confirm ${RELEASE_TAG}"
    return 0
  fi

  if [[ "$RELEASE_OFFLINE" == "1" ]]; then
    RELEASE_READINESS="offline static checks passed"
  elif [[ "$RELEASE_REMOTE_TAG" == "unavailable" ||
    "$RELEASE_REMOTE_REFRESH" == "failed" ]]; then
    RELEASE_READINESS="remote state unavailable"
    RELEASE_NEXT_ACTION="Restore access to origin, then rerun: ${PROGRAM} release status"
    return 0
  else
    RELEASE_READINESS="static checks passed"
  fi

  RELEASE_NEXT_ACTION="$pretag_command"
}

release_collect_state() {
  local changed_count fingerprint source_tag source_commit

  [[ -x scripts/release-version.sh ]] \
    || fail "scripts/release-version.sh is missing or not executable"

  RELEASE_VERSION="$(scripts/release-version.sh read)"
  RELEASE_RUNTIME_VERSION="$(scripts/release-version.sh script)"
  RELEASE_CHANNEL="$(scripts/release-version.sh channel)"
  RELEASE_TAG="$(release_worktree_tag)"
  RELEASE_BRANCH="$(branch_name)"
  RELEASE_HEAD_COMMIT="$(git rev-parse HEAD)"

  collect_changed_files
  changed_count="${#CHANGED_FILES[@]}"
  if ((changed_count == 0)); then
    RELEASE_WORKTREE="clean"
  else
    RELEASE_WORKTREE="${changed_count} changed file(s)"
  fi

  if [[ "$RELEASE_VERSION" == "$RELEASE_RUNTIME_VERSION" ]]; then
    RELEASE_VERSION_ALIGNMENT="OK"
  else
    RELEASE_VERSION_ALIGNMENT="MISMATCH"
  fi

  release_refresh_remote
  release_collect_sync_state

  if git rev-parse -q --verify "refs/tags/${RELEASE_TAG}" >/dev/null; then
    RELEASE_LOCAL_TAG="exists"
    RELEASE_LOCAL_TAG_TYPE="$(git cat-file -t "refs/tags/${RELEASE_TAG}")"
    RELEASE_LOCAL_TAG_COMMIT="$(git rev-parse "refs/tags/${RELEASE_TAG}^{}")"
  else
    RELEASE_LOCAL_TAG="missing"
    RELEASE_LOCAL_TAG_TYPE="missing"
    RELEASE_LOCAL_TAG_COMMIT=""
  fi

  release_collect_remote_tag_state
  release_collect_github_release_state
  RELEASE_PHASE="$(release_resolve_phase)"
  RELEASE_EXPECTED_BRANCH="$(
    release_expected_branch "$RELEASE_VERSION" "$RELEASE_CHANNEL" "$RELEASE_PHASE"
  )"

  source_tag="$(release_state_value source_tag)"
  source_commit="$(release_state_value source_commit)"
  RELEASE_SOURCE_TAG="${source_tag:-none}"
  RELEASE_SOURCE_VERIFIED="not applicable"
  if [[ -n "$source_tag" ]]; then
    if [[ -n "$source_commit" &&
      "$(git rev-parse -q --verify "${source_tag}^{commit}" 2>/dev/null || true)" == "$source_commit" ]]; then
      RELEASE_SOURCE_VERIFIED="yes"
    else
      RELEASE_SOURCE_VERIFIED="no"
    fi
  fi

  fingerprint="$(tree_fingerprint)"
  if cache_matches full "$fingerprint"; then
    RELEASE_FULL_VALIDATION="cached for exact tree"
  else
    RELEASE_FULL_VALIDATION="not cached for exact tree"
  fi
  RELEASE_PRETAG_PROOF="$(release_pretag_proof_state "$RELEASE_TAG" "$fingerprint")"

  RELEASE_BLOCKERS=()
  [[ "$RELEASE_VERSION_ALIGNMENT" == "OK" ]] \
    || release_add_blocker \
      "VERSION ${RELEASE_VERSION} does not match SCRIPT_VERSION ${RELEASE_RUNTIME_VERSION}"
  [[ "$RELEASE_WORKTREE" == "clean" ]] \
    || release_add_blocker "working tree is not clean"
  [[ -n "$RELEASE_BRANCH" ]] \
    || release_add_blocker "repository is in detached HEAD state"
  [[ "$RELEASE_BRANCH" == "$RELEASE_EXPECTED_BRANCH" ]] \
    || release_add_blocker \
      "current branch ${RELEASE_BRANCH:-detached HEAD} does not match expected ${RELEASE_EXPECTED_BRANCH}"

  if [[ -z "$RELEASE_UPSTREAM" ]]; then
    release_add_blocker "current branch has no upstream"
  else
    [[ "$RELEASE_UPSTREAM" == "origin/${RELEASE_BRANCH}" ]] \
      || release_add_blocker \
        "upstream ${RELEASE_UPSTREAM} is not origin/${RELEASE_BRANCH}"
    [[ "$RELEASE_BEHIND" == "0" ]] \
      || release_add_blocker \
        "current branch is ${RELEASE_BEHIND} commit(s) behind ${RELEASE_UPSTREAM}"
    [[ "$RELEASE_AHEAD" == "0" ]] \
      || release_add_blocker \
        "current branch is ${RELEASE_AHEAD} commit(s) ahead of ${RELEASE_UPSTREAM}"
  fi

  if [[ "$RELEASE_LOCAL_TAG" == "exists" ]]; then
    [[ "$RELEASE_LOCAL_TAG_TYPE" == "tag" ]] \
      || release_add_blocker "local tag is not annotated: ${RELEASE_TAG}"
    [[ "$RELEASE_LOCAL_TAG_COMMIT" == "$RELEASE_HEAD_COMMIT" ]] \
      || release_add_blocker "local tag does not point to HEAD: ${RELEASE_TAG}"
  fi
  if [[ "$RELEASE_OFFLINE" == "0" && "$RELEASE_REMOTE_TAG" == "exists" ]]; then
    [[ -n "$RELEASE_REMOTE_TAG_COMMIT" ]] \
      || release_add_blocker "remote tag is not annotated: ${RELEASE_TAG}"
    [[ "$RELEASE_REMOTE_TAG_COMMIT" == "$RELEASE_HEAD_COMMIT" ]] \
      || release_add_blocker "remote tag does not point to HEAD: ${RELEASE_TAG}"
  fi

  release_compute_next_action
}

cmd_release_status() {
  parse_release_read_options "$@"
  release_collect_state

  heading "Release Status"
  info "Version" "$RELEASE_VERSION"
  info "Phase" "$RELEASE_PHASE"
  info "Runtime version" "$RELEASE_RUNTIME_VERSION"
  info "Version alignment" "$RELEASE_VERSION_ALIGNMENT"
  info "Channel" "$RELEASE_CHANNEL"
  info "Expected tag" "$RELEASE_TAG"
  info "Current branch" "${RELEASE_BRANCH:-detached HEAD}"
  info "Expected branch" "$RELEASE_EXPECTED_BRANCH"
  info "Source beta/RC" "$RELEASE_SOURCE_TAG"
  info "Source verified" "$RELEASE_SOURCE_VERIFIED"
  info "Working tree" "$RELEASE_WORKTREE"
  info "Upstream" "${RELEASE_UPSTREAM:-none}"
  info "Branch sync" "$RELEASE_SYNC"
  info "Remote refresh" "$RELEASE_REMOTE_REFRESH"
  info "Full validation" "$RELEASE_FULL_VALIDATION"
  info "Pre-tag proof" "$RELEASE_PRETAG_PROOF"
  info "Local tag" "$RELEASE_LOCAL_TAG"
  info "Remote tag" "$RELEASE_REMOTE_TAG"
  info "GitHub release" "$RELEASE_GITHUB_RELEASE"
  info "Static readiness" "$RELEASE_READINESS"
  info "Next action" "$RELEASE_NEXT_ACTION"
}

cmd_release_doctor() {
  local branch_sync stable_tag

  parse_release_read_options "$@"
  release_collect_state

  if [[ -n "$RELEASE_UPSTREAM" &&
    "$RELEASE_UPSTREAM" == "origin/${RELEASE_BRANCH}" &&
    "$RELEASE_AHEAD" == "0" && "$RELEASE_BEHIND" == "0" ]]; then
    branch_sync="exact"
  else
    branch_sync="$RELEASE_SYNC"
  fi
  if [[ "$RELEASE_LOCAL_TAG" == "exists" || "$RELEASE_REMOTE_TAG" == "exists" ]]; then
    stable_tag="present"
  else
    stable_tag="absent"
  fi

  heading "Release Doctor"
  info "Version" "$RELEASE_VERSION"
  info "Phase" "$RELEASE_PHASE"
  info "Current branch" "${RELEASE_BRANCH:-detached HEAD}"
  info "Expected branch" "$RELEASE_EXPECTED_BRANCH"
  info "Source beta/RC" "$RELEASE_SOURCE_TAG"
  info "Source verified" "$RELEASE_SOURCE_VERIFIED"
  info "Working tree" "$RELEASE_WORKTREE"
  info "Branch sync" "$branch_sync"
  info "Pre-tag proof" "$RELEASE_PRETAG_PROOF"
  info "Stable tag" "$stable_tag"
  info "GitHub release" "$RELEASE_GITHUB_RELEASE"
  info "Readiness" "$RELEASE_READINESS"
  info "Next safe action" "$RELEASE_NEXT_ACTION"
}

cmd_release_explain() {
  local blocker

  parse_release_read_options "$@"
  release_collect_state

  heading "Release Readiness Explanation"
  info "Version" "$RELEASE_VERSION"
  info "Phase" "$RELEASE_PHASE"
  info "Channel" "$RELEASE_CHANNEL"
  info "Expected identity" "${RELEASE_TAG} from ${RELEASE_EXPECTED_BRANCH}"
  info "Static readiness" "$RELEASE_READINESS"
  info "Pre-tag proof" "$RELEASE_PRETAG_PROOF"

  echo
  if release_github_release_exists; then
    echo "The current canonical version already has a published GitHub release."
  elif [[ "$RELEASE_REMOTE_TAG" == "exists" ]]; then
    echo "The release tag already exists remotely. Tag recreation is blocked."
  elif ((${#RELEASE_BLOCKERS[@]} == 0)); then
    echo "No static release blockers were detected."
    echo "The strict pre-tag validator must still verify the complete release tree."
  else
    echo "Blocking conditions:"
    for blocker in "${RELEASE_BLOCKERS[@]}"; do
      printf '  - %s\n' "$blocker"
    done
  fi

  echo
  info "Recommended next action" "$RELEASE_NEXT_ACTION"
}

release_clear_pretag_proof() {
  rm -rf "${STATE_DIR}/release-pretag"
}

release_pretag_proof_state() {
  local tag="$1" fingerprint="$2" dir
  local proof_tag proof_commit proof_fingerprint

  dir="${STATE_DIR}/release-pretag"
  if [[ ! -f "${dir}/tag" || ! -f "${dir}/commit" || ! -f "${dir}/fingerprint" ]]; then
    printf '%s\n' "missing"
    return 0
  fi

  proof_tag="$(cat "${dir}/tag")"
  proof_commit="$(cat "${dir}/commit")"
  proof_fingerprint="$(cat "${dir}/fingerprint")"

  if [[ "$proof_tag" == "$tag" &&
    "$proof_commit" == "$(git rev-parse HEAD)" &&
    "$proof_fingerprint" == "$fingerprint" ]]; then
    printf '%s\n' "valid for exact commit"
  else
    printf '%s\n' "stale"
  fi
}

release_record_pretag_proof() {
  local tag="$1" fingerprint="$2" dir
  dir="${STATE_DIR}/release-pretag"
  mkdir -p "$dir"
  printf '%s\n' "$tag" >"${dir}/tag"
  printf '%s\n' "$(git rev-parse HEAD)" >"${dir}/commit"
  printf '%s\n' "$fingerprint" >"${dir}/fingerprint"
  chmod 600 "${dir}/tag" "${dir}/commit" "${dir}/fingerprint" 2>/dev/null || true
}

release_require_clean_transaction_tree() {
  local branch
  branch="$(branch_name)"
  [[ -n "$branch" ]] || fail "release transaction cannot run from detached HEAD"
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree must be clean before a release metadata transaction"
  fetch_and_check_sync "$branch"
}

release_cache_validated_tree() {
  local fingerprint
  [[ -x scripts/build-release-bundle.sh ]] \
    || fail "scripts/build-release-bundle.sh is missing or not executable"
  heading "Release bundle construction"
  scripts/build-release-bundle.sh
  fingerprint="$(tree_fingerprint)"
  cache_store full "$fingerprint"
  ok "cached full validation for the prepared release tree"
}

release_show_review_gate() {
  local version="$1" message="$2"
  heading "Release Metadata Prepared"
  info "Version" "$version"
  info "Working tree" "review required before publication"
  echo
  echo "Review the release metadata and changelog:"
  echo "  git diff -- VERSION erpnext-dev.sh README.md ROADMAP.md TESTING.md CHANGELOG.md RELEASE-MANIFEST.txt SHA256SUMS"
  echo
  echo "After review, publish with the explicit review gate:"
  echo "  ${PROGRAM} release publish --confirm-reviewed -m \"${message}\""
  echo
  echo "If publication is interrupted after confirmation:"
  echo "  ${PROGRAM} release recover"
  echo
  git status --short
}

cmd_release_prepare_beta() {
  local target_version="${1:-}" release_title="${2:-}" target_tag fingerprint branch expected_branch
  (($# == 2)) || fail "usage: ${PROGRAM} release prepare-beta X.Y.Z-beta.N \"Release title\""
  [[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[1-9][0-9]*$ ]] \
    || fail "beta version must use X.Y.Z-beta.N with N greater than zero"
  [[ -n "$release_title" && "$release_title" != *$'\n'* && "$release_title" != *$'\r'* ]] \
    || fail "release title must be non-empty and one line"
  [[ -x scripts/release-prepare-beta.sh ]] \
    || fail "scripts/release-prepare-beta.sh is missing or not executable"

  target_tag="v${target_version}"
  branch="$(branch_name)"
  expected_branch="release/v${target_version%%-*}"
  [[ "$branch" == "$expected_branch" ]] \
    || fail "beta preparation for ${target_tag} requires ${expected_branch}; current branch is ${branch:-detached HEAD}"
  if release_state_matches_target "$target_tag" \
    && [[ "$(release_state_value phase)" == "beta-preparation" ]] \
    && [[ "$(release_state_value prepared_fingerprint)" == "$(tree_fingerprint)" ]] \
    && [[ "$(release_worktree_tag)" == "$target_tag" ]]; then
    heading "Beta Metadata Already Prepared"
    info "Tag" "$target_tag"
    info "State" "exact prepared tree matches saved transaction"
    info "Next action" "review, then release publish --confirm-reviewed"
    ok "no preparation changes were repeated"
    release_show_review_gate "$target_version" "Release: prepare v${target_version}"
    return 0
  fi

  release_require_clean_transaction_tree
  release_clear_pretag_proof
  heading "Prepare Beta Metadata"
  if ! scripts/release-prepare-beta.sh "$target_version" "$release_title"; then
    release_state_clear
    return 1
  fi
  release_state_update \
    phase beta-preparation \
    channel beta \
    target_version "$target_version" \
    target_tag "$target_tag" \
    source_tag "" \
    source_commit "$(git rev-parse HEAD)" \
    release_branch "$branch" \
    title "$release_title" \
    commit_message "Release: prepare v${target_version}" \
    review_confirmed 0 \
    publication_commit "" \
    pr_number "" \
    merge_commit "" \
    workflow_run "" \
    verified_commit ""
  release_run_with_context release_cache_validated_tree
  fingerprint="$(tree_fingerprint)"
  release_state_update prepared_fingerprint "$fingerprint"
  release_show_review_gate "$target_version" "Release: prepare v${target_version}"
}

cmd_release_promote_stable() {
  local target_version="${1:-}" release_title="${2:-}"
  local target_tag source_tag source_commit fingerprint branch expected_branch
  (($# == 2)) || fail "usage: ${PROGRAM} release promote-stable X.Y.Z \"Release title\""
  [[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "stable version must use X.Y.Z"
  [[ -n "$release_title" && "$release_title" != *$'\n'* && "$release_title" != *$'\r'* ]] \
    || fail "release title must be non-empty and one line"
  [[ -x scripts/release-promote-stable.sh ]] \
    || fail "scripts/release-promote-stable.sh is missing or not executable"

  target_tag="v${target_version}"
  branch="$(branch_name)"
  expected_branch="release/v${target_version}"
  [[ "$branch" == "$expected_branch" ]] \
    || fail "stable promotion for ${target_tag} requires ${expected_branch}; current branch is ${branch:-detached HEAD}"
  if release_state_matches_target "$target_tag" \
    && [[ "$(release_state_value phase)" == "stable-promotion" ]] \
    && [[ "$(release_state_value prepared_fingerprint)" == "$(tree_fingerprint)" ]] \
    && [[ "$(release_worktree_tag)" == "$target_tag" ]]; then
    heading "Stable Metadata Already Prepared"
    info "Tag" "$target_tag"
    info "Source" "$(release_state_value source_tag)"
    info "State" "exact prepared tree matches saved transaction"
    info "Next action" "review, then release publish --confirm-reviewed"
    ok "no promotion changes were repeated"
    release_show_review_gate "$target_version" "Release: promote v${target_version} stable"
    return 0
  fi

  release_require_clean_transaction_tree
  release_clear_pretag_proof
  source_tag="$(scripts/release-version.sh tag)"
  source_commit="$(git rev-parse -q --verify "${source_tag}^{commit}" 2>/dev/null || true)"
  [[ -n "$source_commit" ]] \
    || fail "source prerelease tag does not resolve to a commit: ${source_tag}"
  heading "Promote Stable Metadata"
  if ! scripts/release-promote-stable.sh "$target_version" "$release_title"; then
    release_state_clear
    return 1
  fi
  release_state_update \
    phase stable-promotion \
    channel stable \
    target_version "$target_version" \
    target_tag "$target_tag" \
    source_tag "$source_tag" \
    source_commit "$source_commit" \
    release_branch "$branch" \
    title "$release_title" \
    commit_message "Release: promote v${target_version} stable" \
    review_confirmed 0 \
    publication_commit "" \
    pr_number "" \
    merge_commit "" \
    workflow_run "" \
    verified_commit ""
  release_run_with_context release_cache_validated_tree
  fingerprint="$(tree_fingerprint)"
  release_state_update prepared_fingerprint "$fingerprint"
  release_show_review_gate "$target_version" "Release: promote v${target_version} stable"
}

parse_release_publish_options() {
  RELEASE_PUBLISH_MESSAGE=""
  RELEASE_PUBLISH_CONFIRMED=0
  RELEASE_PUBLISH_RESUME=0

  while (($# > 0)); do
    case "$1" in
      -m | --message)
        shift
        (($# > 0)) || fail "--message requires a commit message"
        RELEASE_PUBLISH_MESSAGE="$1"
        ;;
      --confirm-reviewed) RELEASE_PUBLISH_CONFIRMED=1 ;;
      --resume-prepared) RELEASE_PUBLISH_RESUME=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown release publish option: $1" ;;
    esac
    shift
  done

  if [[ "$RELEASE_PUBLISH_RESUME" == "0" ]]; then
    [[ -n "$RELEASE_PUBLISH_MESSAGE" ]] \
      || fail "release publish requires -m \"Commit message\""
    [[ "$RELEASE_PUBLISH_CONFIRMED" == "1" ]] \
      || fail "release publish requires --confirm-reviewed after reviewing the metadata and changelog"
  fi
}

ensure_release_publish_branch() {
  local branch="$1"
  case "$branch" in
    release/v*) ;;
    *)
      fail "release publish is limited to release/vX.Y.Z branches; current branch: ${branch:-detached HEAD}"
      ;;
  esac
}

cmd_release_publish() {
  local branch phase target_tag canonical_tag publication_commit upstream_commit fingerprint
  local target_version channel expected_branch
  parse_release_publish_options "$@"
  branch="$(branch_name)"
  ensure_release_publish_branch "$branch"
  canonical_tag="$(release_worktree_tag)"
  release_state_matches_target "$canonical_tag" \
    || fail "no matching prepared release transaction exists for ${canonical_tag}; rerun release prepare-beta or release promote-stable"

  phase="$(release_state_value phase)"
  target_tag="$(release_state_value target_tag)"
  target_version="$(release_state_value target_version)"
  channel="$(release_state_value channel)"
  publication_commit="$(release_state_value publication_commit)"
  [[ "$canonical_tag" == "$target_tag" && "v${target_version}" == "$target_tag" ]] \
    || fail "prepared release identity is inconsistent: VERSION ${canonical_tag}, transaction ${target_tag}"
  [[ "$(scripts/release-version.sh channel-for-tag "$canonical_tag")" == "$channel" ]] \
    || fail "prepared release channel does not match the working tree"
  expected_branch="$(release_expected_branch "$target_version" "$channel" "$phase")"
  [[ "$branch" == "$expected_branch" ]] \
    || fail "release phase ${phase:-missing} requires ${expected_branch}; current branch is ${branch:-detached HEAD}"

  if [[ "$RELEASE_PUBLISH_RESUME" == "1" ]]; then
    [[ "$(release_state_value review_confirmed)" == "1" ]] \
      || fail "saved release metadata has not passed the review confirmation gate"
    RELEASE_PUBLISH_MESSAGE="$(release_state_value commit_message)"
    [[ -n "$RELEASE_PUBLISH_MESSAGE" ]] \
      || fail "saved release transaction has no commit message"
    RELEASE_PUBLISH_CONFIRMED=1
  else
    release_state_update \
      review_confirmed 1 \
      commit_message "$RELEASE_PUBLISH_MESSAGE"
  fi

  if [[ "$phase" == "beta-pr" || "$phase" == "stable-pr" ]]; then
    [[ -n "$publication_commit" && "$publication_commit" == "$(git rev-parse HEAD)" ]] \
      || fail "saved publication commit does not match HEAD"
    fetch_and_check_sync "$branch"
    upstream_commit="$(git rev-parse "origin/${branch}" 2>/dev/null || true)"
    [[ "$upstream_commit" == "$publication_commit" ]] \
      || fail "origin/${branch} does not match the saved publication commit; run: ${PROGRAM} release recover"
    heading "Release Metadata Already Published"
    info "Tag" "$target_tag"
    info "Branch" "$branch"
    info "Commit" "$publication_commit"
    info "Next action" "${PROGRAM} release run"
    ok "exact release commit is already pushed; no action required"
    return 0
  fi

  case "$phase" in
    beta-preparation | stable-promotion) ;;
    *) fail "release transaction phase ${phase:-missing} cannot be published" ;;
  esac

  CURRENT_ACTION="release-publish"
  CURRENT_MODE="full"
  CURRENT_MESSAGE="$RELEASE_PUBLISH_MESSAGE"
  state_write "$CURRENT_ACTION" "$CURRENT_MODE" "preflight" "$CURRENT_MESSAGE"

  collect_changed_files
  ((${#CHANGED_FILES[@]} > 0)) \
    || fail "working tree is clean; there is no reviewed release metadata to publish"

  run_step "Remote synchronization" fetch_and_check_sync "$branch"
  release_run_with_context perform_check full 0
  fingerprint="$(tree_fingerprint)"
  release_state_update prepared_fingerprint "$fingerprint"

  CURRENT_ACTION="release-publish"
  CURRENT_MODE="full"
  CURRENT_MESSAGE="$RELEASE_PUBLISH_MESSAGE"
  state_write "$CURRENT_ACTION" "$CURRENT_MODE" "stage" "$CURRENT_MESSAGE"

  heading "Stage Reviewed Release Metadata"
  git add -A
  git diff --cached --check
  git diff --cached --quiet \
    && fail "no staged release changes remain after validation"
  git diff --cached --stat

  run_step "Create release commit" git commit -m "$RELEASE_PUBLISH_MESSAGE"
  publication_commit="$(git rev-parse HEAD)"
  if [[ "$phase" == "stable-promotion" ]]; then
    release_state_update phase stable-pr publication_commit "$publication_commit"
  else
    release_state_update phase beta-pr publication_commit "$publication_commit"
  fi
  run_step "Push release branch" push_branch "$branch"
  state_clear

  heading "Release Metadata Published"
  info "Branch" "$branch"
  info "Commit" "$(git rev-parse --short HEAD)"
  info "Upstream" "origin/${branch}"
  info "Next action" "${PROGRAM} release run"
  ok "reviewed release metadata validated, committed, and pushed"
}

parse_release_pretag_options() {
  RELEASE_PRETAG_TAG=""
  RELEASE_PRETAG_OFFLINE=0

  while (($# > 0)); do
    case "$1" in
      --offline) RELEASE_PRETAG_OFFLINE=1 ;;
      v*)
        [[ -z "$RELEASE_PRETAG_TAG" ]] || fail "only one tag may be supplied"
        RELEASE_PRETAG_TAG="$1"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown release pretag option: $1" ;;
    esac
    shift
  done
}

cmd_release_pretag() {
  local target_tag fingerprint channel version branch expected_branch proof_state phase prefix
  local -a args

  parse_release_pretag_options "$@"
  [[ -x scripts/release-version.sh ]] \
    || fail "scripts/release-version.sh is missing or not executable"
  [[ -x scripts/release-pretag-check.sh ]] \
    || fail "scripts/release-pretag-check.sh is missing or not executable"
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree must be clean before pre-tag validation"

  target_tag="${RELEASE_PRETAG_TAG:-$(scripts/release-version.sh tag)}"
  scripts/release-version.sh assert-tag "$target_tag"
  version="$(scripts/release-version.sh read)"
  channel="$(scripts/release-version.sh channel-for-tag "$target_tag")"
  branch="$(branch_name)"
  [[ "$channel" == "stable" ]] && prefix="stable" || prefix="beta"
  phase="${prefix}-pretag"
  expected_branch="$(release_expected_branch "$version" "$channel" "$phase")"
  [[ "$branch" == "$expected_branch" ]] \
    || fail "${channel} pre-tag validation for ${target_tag} requires ${expected_branch}; current branch is ${branch:-detached HEAD}"

  fingerprint="$(tree_fingerprint)"
  proof_state="$(release_pretag_proof_state "$target_tag" "$fingerprint")"
  if [[ "$proof_state" == "valid for exact commit" ]]; then
    heading "Pre-Tag Proof Already Valid"
    info "Tag" "$target_tag"
    info "Commit" "$(git rev-parse HEAD)"
    info "Proof" "$proof_state"
    info "Next action" "${PROGRAM} release tag --confirm ${target_tag}"
    ok "exact-tree pre-tag validation is already recorded; no action required"
    return 0
  fi

  if release_state_matches_target "$target_tag"; then
    release_state_update phase "$phase"
  else
    release_state_update \
      phase "$phase" \
      channel "$channel" \
      target_version "$version" \
      target_tag "$target_tag" \
      source_tag "" \
      source_commit "" \
      release_branch "$expected_branch" \
      title "" \
      commit_message "" \
      review_confirmed 0 \
      publication_commit "$(git rev-parse HEAD)" \
      pr_number "" \
      merge_commit "" \
      workflow_run "" \
      verified_commit ""
  fi

  args=("$target_tag")
  [[ "$RELEASE_PRETAG_OFFLINE" == "0" ]] || args+=(--offline)

  heading "Strict Pre-Tag Validation"
  scripts/release-pretag-check.sh "${args[@]}"

  fingerprint="$(tree_fingerprint)"
  cache_store full "$fingerprint"
  release_record_pretag_proof "$target_tag" "$fingerprint"
  if [[ -n "$(release_state_value publication_commit)" ]]; then
    release_state_update phase "$phase"
  else
    release_state_update phase "$phase" publication_commit "$(git rev-parse HEAD)"
  fi

  heading "Pre-Tag Proof Recorded"
  info "Tag" "$target_tag"
  info "Commit" "$(git rev-parse HEAD)"
  info "Proof" "valid for exact commit"
  info "Next action" "${PROGRAM} release tag --confirm ${target_tag}"
  ok "strict pre-tag validation passed; no tag was created"
}

release_remote_tag_commit() {
  local tag="$1"
  git ls-remote origin "refs/tags/${tag}^{}" 2>/dev/null \
    | awk 'NR == 1 {print $1}'
}

release_require_exact_pretag_proof() {
  local tag="$1" fingerprint proof_state
  fingerprint="$(tree_fingerprint)"
  proof_state="$(release_pretag_proof_state "$tag" "$fingerprint")"
  [[ "$proof_state" == "valid for exact commit" ]] \
    || fail "strict pre-tag proof is ${proof_state}; run: ${PROGRAM} release pretag ${tag}"
}

parse_release_tag_options() {
  RELEASE_TAG_CONFIRMATION=""
  while (($# > 0)); do
    case "$1" in
      --confirm)
        shift
        (($# > 0)) || fail "--confirm requires the exact canonical tag"
        RELEASE_TAG_CONFIRMATION="$1"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown release tag option: $1" ;;
    esac
    shift
  done
  [[ -n "$RELEASE_TAG_CONFIRMATION" ]] \
    || fail "release tag requires: --confirm vX.Y.Z[-prerelease]"
}

cmd_release_tag() {
  local target_tag branch expected_branch channel version prefix phase
  local local_commit local_type remote_commit rc upstream counts behind ahead
  local created_local=0

  parse_release_tag_options "$@"
  [[ -x scripts/release-version.sh ]] \
    || fail "scripts/release-version.sh is missing or not executable"

  target_tag="$(scripts/release-version.sh tag)"
  [[ "$RELEASE_TAG_CONFIRMATION" == "$target_tag" ]] \
    || fail "confirmation ${RELEASE_TAG_CONFIRMATION} does not match canonical tag ${target_tag}"
  scripts/release-version.sh assert-script
  scripts/release-version.sh assert-tag "$target_tag"

  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree must be clean before tag creation"

  branch="$(branch_name)"
  [[ -n "$branch" ]] || fail "release tag cannot be created from detached HEAD"
  version="$(scripts/release-version.sh read)"
  channel="$(scripts/release-version.sh channel-for-tag "$target_tag")"
  [[ "$channel" == "stable" ]] && prefix="stable" || prefix="beta"
  phase="${prefix}-pretag"
  expected_branch="$(release_expected_branch "$version" "$channel" "$phase")"
  [[ "$branch" == "$expected_branch" ]] \
    || fail "tag ${target_tag} must be created from ${expected_branch}; current branch is ${branch}"

  heading "Release Tag Preflight"
  fetch_and_check_sync "$branch"
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [[ "$upstream" == "origin/${branch}" ]] \
    || fail "tag source branch upstream must be origin/${branch}; current upstream is ${upstream:-none}"
  counts="$(git rev-list --left-right --count "${upstream}...HEAD")"
  behind="${counts%%[[:space:]]*}"
  ahead="${counts##*[[:space:]]}"
  [[ "$behind" == "0" && "$ahead" == "0" ]] \
    || fail "tag source branch must be synchronized with ${upstream}; ahead ${ahead}, behind ${behind}"

  local_commit=""
  local_type=""
  if git rev-parse -q --verify "refs/tags/${target_tag}" >/dev/null; then
    local_type="$(git cat-file -t "refs/tags/${target_tag}")"
    local_commit="$(git rev-parse "refs/tags/${target_tag}^{}")"
    [[ "$local_type" == "tag" ]] \
      || fail "existing local ${target_tag} is not an annotated tag"
    [[ "$local_commit" == "$(git rev-parse HEAD)" ]] \
      || fail "existing local ${target_tag} points to ${local_commit}, not the approved HEAD"
  fi
  remote_commit="$(release_remote_tag_commit "$target_tag")"
  if git ls-remote --exit-code --tags origin "refs/tags/${target_tag}" >/dev/null 2>&1; then
    [[ -n "$remote_commit" ]] \
      || fail "existing remote ${target_tag} is not an annotated tag"
    [[ "$remote_commit" == "$(git rev-parse HEAD)" ]] \
      || fail "existing remote ${target_tag} points to ${remote_commit}, not the approved HEAD"
    if [[ -n "$local_commit" ]]; then
      heading "Release Tag Already Published"
      info "Tag" "$target_tag"
      info "Commit" "$remote_commit"
      info "Type" "annotated"
      info "Next action" "${PROGRAM} release watch ${target_tag}"
      release_state_update phase "${prefix}-tagged" publication_commit "$remote_commit"
      ok "${target_tag} already exists and points to the approved commit; no action required"
      return 0
    fi
    heading "Release Tag Already Published"
    info "Tag" "$target_tag"
    info "Commit" "$remote_commit"
    info "Type" "annotated on origin"
    info "Next action" "${PROGRAM} release watch ${target_tag}"
    release_state_update phase "${prefix}-tagged" publication_commit "$remote_commit"
    ok "${target_tag} already exists on origin and points to the approved commit; no action required"
    return 0
  fi

  release_require_exact_pretag_proof "$target_tag"

  if [[ -z "$local_commit" ]]; then
    heading "Create Annotated Release Tag"
    git tag -a "$target_tag" "$(git rev-parse HEAD)" -m "ERPNext Developer Toolkit ${target_tag}"
    created_local=1
  else
    heading "Publish Existing Approved Tag"
    info "Tag" "$target_tag"
    info "Commit" "$local_commit"
  fi

  set +e
  git push origin "refs/tags/${target_tag}:refs/tags/${target_tag}"
  rc=$?
  set -e

  if ((rc != 0)); then
    remote_commit="$(release_remote_tag_commit "$target_tag")"
    if [[ "$remote_commit" == "$(git rev-parse HEAD)" ]]; then
      warn "tag push returned an error, but origin has the expected exact tag commit"
    elif [[ -z "$remote_commit" ]]; then
      if ((created_local == 1)); then
        git tag -d "$target_tag" >/dev/null 2>&1 || true
        fail "tag push failed; the newly created local tag was removed so the operation can be retried"
      fi
      fail "tag push failed; the existing approved local tag was preserved for retry"
    else
      fail "tag push failed and origin/${target_tag} points to an unexpected commit; inspect before continuing"
    fi
  fi

  remote_commit="$(release_remote_tag_commit "$target_tag")"
  [[ "$remote_commit" == "$(git rev-parse HEAD)" ]] \
    || fail "origin/${target_tag} does not peel to the current release commit"
  release_state_update phase "${prefix}-tagged" publication_commit "$remote_commit"

  heading "Release Tag Published"
  info "Tag" "$target_tag"
  info "Commit" "$remote_commit"
  info "Type" "annotated"
  info "Next action" "${PROGRAM} release watch ${target_tag}"
  ok "annotated release tag created and pushed"
}

parse_release_watch_options() {
  RELEASE_WATCH_TAG=""
  RELEASE_WATCH_INTERVAL=5
  RELEASE_WATCH_ATTEMPTS=12

  while (($# > 0)); do
    case "$1" in
      --interval)
        shift
        (($# > 0)) || fail "--interval requires seconds"
        RELEASE_WATCH_INTERVAL="$1"
        ;;
      --attempts)
        shift
        (($# > 0)) || fail "--attempts requires a count"
        RELEASE_WATCH_ATTEMPTS="$1"
        ;;
      v*)
        [[ -z "$RELEASE_WATCH_TAG" ]] || fail "only one release tag may be supplied"
        RELEASE_WATCH_TAG="$1"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown release watch option: $1" ;;
    esac
    shift
  done

  [[ "$RELEASE_WATCH_INTERVAL" =~ ^[1-9][0-9]*$ ]] \
    || fail "--interval must be a positive integer"
  [[ "$RELEASE_WATCH_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] \
    || fail "--attempts must be a positive integer"
  ((RELEASE_WATCH_INTERVAL <= 60)) || fail "--interval cannot exceed 60 seconds"
  ((RELEASE_WATCH_ATTEMPTS <= 120)) || fail "--attempts cannot exceed 120"
}

release_resolve_canonical_tag() {
  local supplied="${1:-}" expected
  expected="$(scripts/release-version.sh tag)"
  if [[ -n "$supplied" ]]; then
    scripts/release-version.sh assert-tag "$supplied" >/dev/null
    printf '%s\n' "$supplied"
  else
    printf '%s\n' "$expected"
  fi
}

release_find_workflow_run() {
  local tag="$1"
  gh run list \
    --workflow release.yml \
    --branch "$tag" \
    --event push \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty'
}

release_gh_run_field() {
  local run_id="$1" jq_filter="$2" label="$3" interval="$4" attempts="$5"
  local attempt output rc

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    set +e
    output="$(gh run view "$run_id" --json headSha,conclusion,url --jq "$jq_filter" 2>/dev/null)"
    rc=$?
    set -e
    if ((rc == 0)); then
      printf '%s\n' "$output"
      return 0
    fi
    warn "GitHub API could not read ${label} for workflow ${run_id} (attempt ${attempt}/${attempts}); retrying"
    sleep "$interval"
  done
  return 1
}

cmd_release_watch() {
  local target_tag run_id="" attempt remote_commit run_head conclusion run_url channel prefix
  local watch_attempt watch_rc

  parse_release_watch_options "$@"
  require_gh
  target_tag="$(release_resolve_canonical_tag "$RELEASE_WATCH_TAG")"
  remote_commit="$(release_remote_tag_commit "$target_tag")"
  [[ -n "$remote_commit" ]] \
    || fail "remote annotated tag is missing or cannot be resolved: ${target_tag}"

  heading "Locate Protected Release Workflow"
  for ((attempt = 1; attempt <= RELEASE_WATCH_ATTEMPTS; attempt++)); do
    run_id="$(release_find_workflow_run "$target_tag" 2>/dev/null || true)"
    [[ -z "$run_id" ]] || break
    echo "Attempt ${attempt}/${RELEASE_WATCH_ATTEMPTS}: release workflow is not visible yet"
    sleep "$RELEASE_WATCH_INTERVAL"
  done
  [[ -n "$run_id" ]] || fail "no release.yml workflow run was found for ${target_tag}"

  run_head="$(
    release_gh_run_field \
      "$run_id" \
      '.headSha' \
      "head commit" \
      "$RELEASE_WATCH_INTERVAL" \
      "$RELEASE_WATCH_ATTEMPTS"
  )" || fail "could not read release workflow head after ${RELEASE_WATCH_ATTEMPTS} attempts"
  [[ "$run_head" == "$remote_commit" ]] \
    || fail "release workflow head ${run_head} does not match ${target_tag} commit ${remote_commit}"
  run_url="$(
    release_gh_run_field \
      "$run_id" \
      '.url' \
      "URL" \
      "$RELEASE_WATCH_INTERVAL" \
      "$RELEASE_WATCH_ATTEMPTS"
  )" || fail "could not read release workflow URL after ${RELEASE_WATCH_ATTEMPTS} attempts"

  info "Tag" "$target_tag"
  info "Workflow run" "$run_id"
  info "Commit" "$run_head"
  info "URL" "$run_url"

  conclusion="$(
    release_gh_run_field \
      "$run_id" \
      '.conclusion // empty' \
      "conclusion" \
      "$RELEASE_WATCH_INTERVAL" \
      "$RELEASE_WATCH_ATTEMPTS"
  )" || fail "could not read release workflow conclusion after ${RELEASE_WATCH_ATTEMPTS} attempts"
  if [[ "$conclusion" == "success" ]]; then
    heading "Protected Release Workflow Already Complete"
    ok "workflow ${run_id} already completed successfully; no wait required"
  elif [[ -n "$conclusion" ]]; then
    fail "release workflow conclusion is ${conclusion}"
  else
    heading "Watch Protected Release Workflow"
    for ((watch_attempt = 1; watch_attempt <= RELEASE_WATCH_ATTEMPTS; watch_attempt++)); do
      set +e
      gh run watch "$run_id" --exit-status
      watch_rc=$?
      set -e
      conclusion="$(gh run view "$run_id" --json conclusion --jq '.conclusion // empty' 2>/dev/null || true)"
      if [[ "$conclusion" == "success" ]]; then
        break
      fi
      if [[ -n "$conclusion" ]]; then
        fail "release workflow conclusion is ${conclusion}"
      fi
      if ((watch_rc != 0)); then
        warn "workflow watch was interrupted (attempt ${watch_attempt}/${RELEASE_WATCH_ATTEMPTS}); GitHub state is unchanged and the watch will resume"
      fi
      sleep "$RELEASE_WATCH_INTERVAL"
    done
  fi
  [[ "$conclusion" == "success" ]] || fail "release workflow conclusion is ${conclusion:-unknown}"
  channel="$(scripts/release-version.sh channel-for-tag "$target_tag")"
  [[ "$channel" == "stable" ]] && prefix="stable" || prefix="beta"
  if release_state_matches_target "$target_tag"; then
    release_state_update \
      phase "${prefix}-published" \
      workflow_run "$run_id" \
      publication_commit "$remote_commit"
  fi

  heading "Release Workflow Complete"
  info "Tag" "$target_tag"
  info "Conclusion" "$conclusion"
  info "Next action" "${PROGRAM} release verify ${target_tag}"
  ok "release workflow completed successfully"
}

release_verify_signature() {
  local root="$1" tag="$2" fingerprint expected gnupg
  expected="BFC10C79427CF73496EA6F5A30BFD17DD559C8B6"

  if [[ ! -f "${root}/SHA256SUMS.asc" ]]; then
    if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      fail "stable release is missing SHA256SUMS.asc"
    fi
    warn "prerelease is unsigned; checksum integrity was verified without maintainer authenticity"
    return 0
  fi

  command -v gpg >/dev/null 2>&1 || fail "gpg is required to verify the release signature"
  [[ -f "${root}/docs/erpnext-dev-signing-key.asc" ]] \
    || fail "release bundle is missing the maintainer public key"

  gnupg="$(mktemp -d /tmp/erpnext-release-gpg.XXXXXX)"
  chmod 700 "$gnupg"
  gpg --homedir "$gnupg" --batch --import "${root}/docs/erpnext-dev-signing-key.asc" >/dev/null 2>&1
  fingerprint="$(gpg --homedir "$gnupg" --batch --with-colons --fingerprint | awk -F: '$1 == "fpr" {print $10; exit}')"
  [[ "$fingerprint" == "$expected" ]] || {
    rm -rf "$gnupg"
    fail "maintainer key fingerprint mismatch: ${fingerprint:-missing}"
  }
  gpg --homedir "$gnupg" --batch --verify "${root}/SHA256SUMS.asc" "${root}/SHA256SUMS"
  rm -rf "$gnupg"
  ok "maintainer signing-key fingerprint verified"
}

cmd_release_verify() {
  local supplied_tag="${1:-}" target_tag remote_commit run_id run_head conclusion
  local metadata meta_tag is_draft is_prerelease release_url verify_dir archive list_file root stable=0
  local tagged_root tagged_manifest
  local channel prefix
  local -a asset_check_args

  (($# <= 1)) || fail "usage: ${PROGRAM} release verify [vX.Y.Z[-prerelease]]"
  require_gh
  [[ -x scripts/release-version.sh ]] \
    || fail "scripts/release-version.sh is missing or not executable"
  [[ -x scripts/assert-github-release-assets.sh ]] \
    || fail "scripts/assert-github-release-assets.sh is missing or not executable"

  target_tag="$(release_resolve_canonical_tag "$supplied_tag")"
  [[ "$target_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && stable=1

  remote_commit="$(release_remote_tag_commit "$target_tag")"
  [[ -n "$remote_commit" ]] \
    || fail "remote annotated tag is missing or cannot be resolved: ${target_tag}"

  run_id="$(release_find_workflow_run "$target_tag")"
  [[ -n "$run_id" ]] || fail "no release.yml workflow run was found for ${target_tag}"
  run_head="$(gh run view "$run_id" --json headSha --jq '.headSha')"
  conclusion="$(gh run view "$run_id" --json conclusion --jq '.conclusion // empty')"
  [[ "$run_head" == "$remote_commit" ]] || fail "release workflow head does not match the remote tag commit"
  [[ "$conclusion" == "success" ]] || fail "release workflow has not completed successfully"
  if release_state_matches_target "$target_tag" \
    && [[ "$(release_state_value verified_commit)" == "$remote_commit" ]]; then
    ok "${target_tag} was already verified at this exact commit; rechecking published assets safely"
  fi

  asset_check_args=("$target_tag")
  ((stable == 0)) || asset_check_args+=(--require-latest)
  scripts/assert-github-release-assets.sh "${asset_check_args[@]}"

  metadata="$(gh release view "$target_tag" --json tagName,isDraft,isPrerelease,url --jq '"\(.tagName)|\(.isDraft)|\(.isPrerelease)|\(.url)"')"
  IFS='|' read -r meta_tag is_draft is_prerelease release_url <<<"$metadata"
  [[ "$meta_tag" == "$target_tag" ]] || fail "GitHub release tag identity mismatch"
  [[ "$is_draft" == "false" ]] || fail "GitHub release is still a draft"
  if ((stable == 1)); then
    [[ "$is_prerelease" == "false" ]] || fail "stable release is incorrectly marked as prerelease"
  else
    [[ "$is_prerelease" == "true" ]] || fail "prerelease tag is not marked as a GitHub prerelease"
  fi

  verify_dir="$(mktemp -d /tmp/erpnext-release-verify.XXXXXX)"
  heading "Download Published Release Assets"
  if ! gh release download "$target_tag" --dir "$verify_dir" --clobber; then
    warn "release downloads retained for inspection: ${verify_dir}"
    fail "could not download published release assets"
  fi

  archive="${verify_dir}/erpnext-dev-${target_tag}.tar.gz"
  build_info_asset="${verify_dir}/erpnext-dev-${target_tag}.BUILD-INFO.json"
  [[ -f "$archive" ]] || fail "published release archive is missing"
  [[ -f "$build_info_asset" ]] || fail "published BUILD-INFO sidecar is missing"
  [[ -f "${verify_dir}/SHA256SUMS" ]] || fail "published SHA256SUMS is missing"
  [[ -f "${verify_dir}/erpnext-dev.sh" ]] || fail "published entrypoint asset is missing"
  [[ -f "${verify_dir}/RELEASE-MANIFEST.txt" ]] || fail "published release manifest asset is missing"
  if ((stable == 1)); then
    [[ -f "${verify_dir}/SHA256SUMS.asc" ]] || fail "stable release signature asset is missing"
  fi

  list_file="${verify_dir}/archive.list"
  tar -tzf "$archive" >"$list_file"
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "$list_file"; then
    fail "release archive contains an unsafe path"
  fi
  tar --no-same-owner --no-same-permissions -C "$verify_dir" -xzf "$archive"

  root="${verify_dir}/erpnext-dev-${target_tag}"
  [[ -d "$root" ]] || fail "release archive root is missing or misnamed"
  tagged_root="$(mktemp -d /tmp/erpnext-release-tag.XXXXXX)"
  git archive "refs/tags/${target_tag}^{commit}" | tar -x -C "$tagged_root"
  tagged_manifest="${tagged_root}/RELEASE-MANIFEST.txt"
  git show "${target_tag}^{commit}:RELEASE-MANIFEST.txt" >"$tagged_manifest" \
    || fail "tagged release manifest is missing"
  ERPNEXT_RELEASE_ROOT="$tagged_root" \
    ERPNEXT_RELEASE_MANIFEST="$tagged_manifest" \
    scripts/release-manifest-files.sh --include-checksum >/dev/null \
    || fail "tagged release manifest is malformed or unsafe"
  cmp -s "${verify_dir}/RELEASE-MANIFEST.txt" "$tagged_manifest" \
    || fail "published release manifest differs from tagged manifest"
  cmp -s "${verify_dir}/SHA256SUMS" "${root}/SHA256SUMS" || fail "standalone and bundled SHA256SUMS differ"
  cmp -s "${verify_dir}/erpnext-dev.sh" "${root}/erpnext-dev.sh" || fail "standalone and bundled entrypoints differ"
  cmp -s "${verify_dir}/RELEASE-MANIFEST.txt" "${root}/RELEASE-MANIFEST.txt" || fail "standalone and bundled manifests differ"
  cmp -s "$build_info_asset" "${root}/BUILD-INFO.json" || fail "standalone and bundled BUILD-INFO differ"
  if [[ -f "${verify_dir}/SHA256SUMS.asc" ]]; then
    cmp -s "${verify_dir}/SHA256SUMS.asc" "${root}/SHA256SUMS.asc" || fail "standalone and bundled signatures differ"
  fi

  (
    cd "$root"
    scripts/release-version.sh assert-script
    scripts/release-version.sh assert-tag "$target_tag"
    scripts/build-info.sh verify \
      --root . \
      --archive "erpnext-dev-${target_tag}.tar.gz" \
      --expected-tag "$target_tag" \
      --expected-channel "$(scripts/release-version.sh channel-for-tag "$target_tag")" \
      --expected-commit "$remote_commit"
    sha256sum -c SHA256SUMS
  )
  ok "release bundle checksums verified"
  release_verify_signature "$root" "$target_tag"

  rm -rf "$tagged_root" "$verify_dir"
  channel="$(scripts/release-version.sh channel-for-tag "$target_tag")"
  prefix="$(release_state_prepare_verified "$target_tag" "$remote_commit")"
  release_state_update \
    phase "${prefix}-verified" \
    channel "$channel" \
    target_version "${target_tag#v}" \
    target_tag "$target_tag" \
    workflow_run "$run_id" \
    verified_commit "$remote_commit"
  heading "Published Release Verified"
  info "Tag" "$target_tag"
  info "Commit" "$remote_commit"
  info "Workflow" "success"
  info "Release" "$release_url"
  ok "published release ${target_tag} verified"
}

cmd_release_recover() {
  local rollback=0 confirm=0 phase action stage branch target_tag message
  local -a managed_files=(
    VERSION
    erpnext-dev.sh
    README.md
    ROADMAP.md
    TESTING.md
    CHANGELOG.md
    RELEASE-MANIFEST.txt
    SHA256SUMS
  )

  while (($# > 0)); do
    case "$1" in
      --rollback-prepared) rollback=1 ;;
      --confirm) confirm=1 ;;
      -h | --help)
        usage
        return 0
        ;;
      *) fail "unknown release recover option: $1" ;;
    esac
    shift
  done

  phase="$(release_state_value phase)"
  target_tag="$(release_state_value target_tag)"
  message="$(release_state_value commit_message)"
  action="$(state_value action)"
  stage="$(state_value stage)"
  branch="$(branch_name)"

  heading "Release Recovery"
  info "Phase" "${phase:-unknown}"
  info "Tag" "${target_tag:-unknown}"
  info "Branch" "${branch:-detached HEAD}"
  info "Saved operation" "${action:-none}; stage ${stage:-none}"

  if ((rollback == 1)); then
    ((confirm == 1)) \
      || fail "prepared-metadata rollback requires --confirm"
    case "$phase" in
      beta-preparation | stable-promotion) ;;
      *) fail "phase ${phase:-missing} has no rollback-safe prepared metadata" ;;
    esac
    [[ -n "$(git status --porcelain --untracked-files=all)" ]] \
      || fail "working tree is already clean; there is no prepared metadata to roll back"
    [[ -n "$(release_state_value prepared_fingerprint)" &&
    "$(release_state_value prepared_fingerprint)" == "$(tree_fingerprint)" ]] \
      || fail "prepared tree has changed since validation; inspect it instead of rolling back automatically"
    git restore --staged --worktree -- "${managed_files[@]}"
    release_clear_pretag_proof
    release_state_clear
    state_clear
    heading "Prepared Metadata Rolled Back"
    ok "release-managed files were restored to HEAD; the rollback is complete"
    return 0
  fi

  if [[ "$action" == "release-publish" && "$stage" == "Push release branch" &&
    -z "$(git status --porcelain --untracked-files=all)" ]]; then
    cmd_resume
    return 0
  fi

  case "$phase" in
    beta-preparation | stable-promotion)
      if [[ "$(release_state_value review_confirmed)" == "1" ]]; then
        info "Prepared metadata" "intact"
        info "Safe recovery" "${PROGRAM} release publish --resume-prepared"
        cmd_release_publish --resume-prepared
      else
        info "Prepared metadata" "intact; review confirmation still required"
        info "Safe recovery" "${PROGRAM} release publish --confirm-reviewed -m \"${message}\""
        ok "no action taken before the human review gate"
      fi
      ;;
    beta-pr | stable-pr)
      info "Safe recovery" "${PROGRAM} release run"
      info "Reason" "the resumable command reconciles the exact PR and merge commit"
      ok "no branch reconstruction or release mutation was attempted"
      ;;
    beta-pretag | stable-pretag)
      if [[ "$(release_pretag_proof_state "$target_tag" "$(tree_fingerprint)")" == "valid for exact commit" ]]; then
        info "Pre-tag proof" "valid for exact commit"
        info "Human gate" "${PROGRAM} release tag --confirm ${target_tag}"
        ok "no action taken before tag confirmation"
      else
        cmd_release_pretag "$target_tag"
      fi
      ;;
    beta-tagged | stable-tagged)
      cmd_release_watch "$target_tag"
      ;;
    beta-published | stable-published)
      info "Published release" "workflow completed successfully"
      info "Human gate" "${PROGRAM} release verify ${target_tag}"
      ok "no action taken before final published-asset verification"
      ;;
    beta-verified | stable-verified)
      ok "${target_tag} is already published and verified; no action required"
      ;;
    "")
      info "Safe recovery" "${PROGRAM} release doctor"
      cmd_release_doctor
      ;;
    *) fail "unknown saved release phase: $phase" ;;
  esac
}

parse_release_run_options() {
  RELEASE_RUN_KIND=""
  RELEASE_RUN_VERSION=""
  RELEASE_RUN_TITLE=""
  RELEASE_RUN_FROM=""
  RELEASE_RUN_CONFIRM_REVIEWED=0
  RELEASE_RUN_CONFIRM_MERGE=0
  RELEASE_RUN_CONFIRM_TAG=""
  RELEASE_RUN_CONFIRM_VERIFY=0
  RELEASE_RUN_NON_INTERACTIVE=0
  RELEASE_RUN_INTERVAL=5
  RELEASE_RUN_ATTEMPTS=120

  while (($# > 0)); do
    case "$1" in
      beta | stable)
        [[ -z "$RELEASE_RUN_KIND" ]] \
          || fail "release run accepts only one release kind"
        RELEASE_RUN_KIND="$1"
        ;;
      --from)
        shift
        (($# > 0)) || fail "--from requires the exact source prerelease tag"
        RELEASE_RUN_FROM="$1"
        ;;
      --confirm-reviewed) RELEASE_RUN_CONFIRM_REVIEWED=1 ;;
      --confirm-merge) RELEASE_RUN_CONFIRM_MERGE=1 ;;
      --confirm-tag)
        shift
        (($# > 0)) || fail "--confirm-tag requires the exact release tag"
        RELEASE_RUN_CONFIRM_TAG="$1"
        ;;
      --confirm-verify) RELEASE_RUN_CONFIRM_VERIFY=1 ;;
      --non-interactive) RELEASE_RUN_NON_INTERACTIVE=1 ;;
      --interval)
        shift
        (($# > 0)) || fail "--interval requires seconds"
        RELEASE_RUN_INTERVAL="$1"
        ;;
      --attempts)
        shift
        (($# > 0)) || fail "--attempts requires a count"
        RELEASE_RUN_ATTEMPTS="$1"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        fail "unknown release run option: $1"
        ;;
      *)
        if [[ -z "$RELEASE_RUN_VERSION" ]]; then
          RELEASE_RUN_VERSION="$1"
        elif [[ -z "$RELEASE_RUN_TITLE" ]]; then
          RELEASE_RUN_TITLE="$1"
        else
          fail "release run accepts one version and one release title"
        fi
        ;;
    esac
    shift
  done

  [[ "$RELEASE_RUN_INTERVAL" =~ ^[1-9][0-9]*$ ]] \
    || fail "--interval must be a positive integer"
  [[ "$RELEASE_RUN_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] \
    || fail "--attempts must be a positive integer"
  ((RELEASE_RUN_INTERVAL <= 60)) || fail "--interval cannot exceed 60 seconds"
  ((RELEASE_RUN_ATTEMPTS <= 120)) || fail "--attempts cannot exceed 120"

  if [[ -n "$RELEASE_RUN_KIND" ]]; then
    [[ -n "$RELEASE_RUN_VERSION" && -n "$RELEASE_RUN_TITLE" ]] \
      || fail "new release run requires a release kind, version, and title"
    case "$RELEASE_RUN_KIND" in
      beta)
        [[ "$RELEASE_RUN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[1-9][0-9]*$ ]] \
          || fail "beta release run requires X.Y.Z-beta.N"
        [[ -z "$RELEASE_RUN_FROM" ]] \
          || fail "--from is valid only for a stable release run"
        ;;
      stable)
        [[ "$RELEASE_RUN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
          || fail "stable release run requires X.Y.Z"
        [[ "$RELEASE_RUN_FROM" =~ ^v${RELEASE_RUN_VERSION//./\\.}-(beta\.[1-9][0-9]*|rc\.[1-9][0-9]*)$ ]] \
          || fail "stable release run requires --from v${RELEASE_RUN_VERSION}-beta.N or -rc.N"
        ;;
    esac
  elif [[ -n "$RELEASE_RUN_VERSION" || -n "$RELEASE_RUN_TITLE" ||
    -n "$RELEASE_RUN_FROM" ]]; then
    fail "release run resume accepts no release identity; use: ${PROGRAM} release run"
  fi
}

release_run_pause() {
  local gate="$1" expected="$2" supplied="$3" response=""

  if [[ "$supplied" == "1" ]]; then
    return 0
  fi

  heading "${gate} Confirmation Required"
  info "Required response" "$expected"
  info "Resume command" "${PROGRAM} release run"

  if [[ "$RELEASE_RUN_NON_INTERACTIVE" == "1" || ! -t 0 ]]; then
    ok "release paused safely before ${gate,,}"
    return 1
  fi

  read -r -p "Type ${expected} to continue, or press Enter to pause: " response
  if [[ "$response" != "$expected" ]]; then
    ok "release paused safely before ${gate,,}"
    return 1
  fi
}

release_run_pause_tag() {
  local target_tag="$1" response=""

  if [[ -n "$RELEASE_RUN_CONFIRM_TAG" ]]; then
    [[ "$RELEASE_RUN_CONFIRM_TAG" == "$target_tag" ]] \
      || fail "tag confirmation must exactly match ${target_tag}"
    return 0
  fi

  heading "Release Tag Confirmation Required"
  info "Tag" "$target_tag"
  info "Resume command" "${PROGRAM} release run"

  if [[ "$RELEASE_RUN_NON_INTERACTIVE" == "1" || ! -t 0 ]]; then
    ok "release paused safely before tag creation"
    return 1
  fi

  read -r -p "Type ${target_tag} to create the immutable tag, or press Enter to pause: " response
  if [[ "$response" != "$target_tag" ]]; then
    ok "release paused safely before tag creation"
    return 1
  fi
}

release_run_remote_branch_exists() {
  git show-ref --verify --quiet "refs/remotes/origin/$1"
}

release_run_local_branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

release_run_prepare_branch() {
  local release_branch="$1" main_commit local_commit remote_commit current

  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree must be clean before starting a release run"

  git fetch origin --prune --tags
  main_commit="$(git rev-parse -q --verify refs/remotes/origin/main 2>/dev/null || true)"
  [[ -n "$main_commit" ]] || fail "origin/main is missing"

  current="$(branch_name)"
  if release_run_remote_branch_exists "$release_branch"; then
    remote_commit="$(git rev-parse "refs/remotes/origin/${release_branch}")"
    git merge-base --is-ancestor "$remote_commit" "$main_commit" \
      || fail "origin/${release_branch} contains commits not present on origin/main; inspect the existing release work instead of replacing it"

    if release_run_local_branch_exists "$release_branch"; then
      local_commit="$(git rev-parse "refs/heads/${release_branch}")"
      if [[ "$local_commit" != "$remote_commit" ]]; then
        git merge-base --is-ancestor "$local_commit" "$remote_commit" \
          || fail "local ${release_branch} has unpushed or divergent commits; no branch was moved"
        if [[ "$current" == "$release_branch" ]]; then
          git merge --ff-only "origin/${release_branch}"
        else
          git branch -f "$release_branch" "$remote_commit"
        fi
      fi
      git switch "$release_branch"
    else
      git switch -c "$release_branch" --track "origin/${release_branch}"
    fi
  elif release_run_local_branch_exists "$release_branch"; then
    local_commit="$(git rev-parse "refs/heads/${release_branch}")"
    git merge-base --is-ancestor "$local_commit" "$main_commit" \
      || fail "local ${release_branch} contains commits not present on origin/main; no branch was moved"
    [[ "$current" != "$release_branch" ]] \
      || git switch main
    git branch -f "$release_branch" "$main_commit"
    git switch "$release_branch"
  else
    git switch -c "$release_branch" "origin/main"
  fi

  git merge --ff-only "origin/main"
  if release_run_remote_branch_exists "$release_branch"; then
    git push origin "$release_branch"
    git branch --set-upstream-to="origin/${release_branch}" "$release_branch" >/dev/null
  else
    git push -u origin "$release_branch"
  fi

  [[ "$(git rev-parse HEAD)" == "$main_commit" ]] \
    || fail "${release_branch} does not match the verified origin/main start commit"
  heading "Release Branch Ready"
  info "Branch" "$release_branch"
  info "Commit" "$main_commit"
  ok "release branch was created or safely fast-forwarded without force-push"
}

release_run_checkout_publication_branch() {
  local branch="$1" publication_commit="$2"

  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree must be clean before continuing the release pull request"
  git fetch origin --prune --tags
  release_run_remote_branch_exists "$branch" \
    || return 1
  [[ "$(git rev-parse "refs/remotes/origin/${branch}")" == "$publication_commit" ]] \
    || fail "origin/${branch} does not match the saved release commit"

  if release_run_local_branch_exists "$branch"; then
    [[ "$(branch_name)" == "$branch" ]] || git switch "$branch"
    git merge --ff-only "origin/${branch}"
  else
    git switch -c "$branch" --track "origin/${branch}"
  fi
  [[ "$(git rev-parse HEAD)" == "$publication_commit" ]] \
    || fail "${branch} does not match the saved release commit"
}

release_run_find_pr_number() {
  local branch="$1" publication_commit="$2" repo owner
  repo="$(repository_name_with_owner)"
  owner="${repo%%/*}"
  gh api --method GET "repos/${repo}/pulls" \
    -f state=all \
    -f head="${owner}:${branch}" \
    -f base=main \
    -f per_page=100 \
    --jq "map(select(.head.sha == \"${publication_commit}\")) | sort_by(.number) | last | .number // empty"
}

release_run_pr_metadata() {
  local number="$1" repo
  repo="$(repository_name_with_owner)"
  gh api "repos/${repo}/pulls/${number}" \
    --jq '"\(.state)|\(.merged_at // "")|\(.head.sha)|\(.merge_commit_sha // "")|\(.html_url)"'
}

release_run_ensure_pr() {
  local branch="$1" publication_commit="$2" target_tag="$3" title="$4"
  local number metadata state merged_at head_commit merge_commit url

  require_gh
  number="$(release_state_value pr_number)"
  if [[ -z "$number" ]]; then
    number="$(release_run_find_pr_number "$branch" "$publication_commit")"
  fi

  if [[ -z "$number" ]]; then
    release_run_checkout_publication_branch "$branch" "$publication_commit" \
      || fail "origin/${branch} is missing and no exact pull request exists for the saved release commit"
    cmd_pr_create \
      --base main \
      --title "Release ${target_tag}: ${title}" \
      --body "Automated release transaction for ${target_tag}. Human review, merge, tag, and verification gates remain enforced."
    number="$(release_run_find_pr_number "$branch" "$publication_commit")"
    [[ -n "$number" ]] || fail "created pull request could not be resolved to the exact release commit"
  fi

  metadata="$(release_run_pr_metadata "$number")"
  IFS='|' read -r state merged_at head_commit merge_commit url <<<"$metadata"
  [[ "$head_commit" == "$publication_commit" ]] \
    || fail "PR #${number} head does not match the saved release commit"
  release_state_update pr_number "$number"

  RELEASE_RUN_PR_NUMBER="$number"
  RELEASE_RUN_PR_STATE="$state"
  RELEASE_RUN_PR_MERGED_AT="$merged_at"
  RELEASE_RUN_PR_MERGE_COMMIT="$merge_commit"
  RELEASE_RUN_PR_URL="$url"
}

release_run_sync_merged_pr() {
  local prefix="$1" publication_commit="$2" merge_commit="$3" number="$4"
  local main_commit

  [[ -n "$merge_commit" ]] || fail "PR #${number} is merged but GitHub did not return its merge commit"
  git fetch origin --prune --tags
  main_commit="$(git rev-parse -q --verify refs/remotes/origin/main 2>/dev/null || true)"
  [[ "$main_commit" == "$merge_commit" ]] \
    || fail "origin/main advanced beyond PR #${number}; no release tag was created"
  git cat-file -e "${merge_commit}^{commit}" 2>/dev/null \
    || fail "merge commit ${merge_commit} is not available locally after fetch"
  git diff --quiet "$publication_commit" "$merge_commit" -- \
    || fail "PR #${number} merge tree differs from the reviewed release commit"

  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree must be clean before synchronizing main"
  if release_run_local_branch_exists main; then
    git switch main
  else
    git switch -c main --track origin/main
  fi
  git pull --ff-only origin main
  [[ "$(git rev-parse HEAD)" == "$merge_commit" ]] \
    || fail "local main does not match the exact PR #${number} merge commit"

  release_state_update \
    phase "${prefix}-pretag" \
    merge_commit "$merge_commit"
  heading "Merged Release Synchronized"
  info "PR" "#${number}"
  info "Main commit" "$merge_commit"
  info "Release branch" "no reconstruction required"
  ok "post-merge release stages will run from synchronized main"
}

release_run_load_saved_identity() {
  local channel

  RELEASE_RUN_VERSION="$(release_state_value target_version)"
  RELEASE_RUN_TITLE="$(release_state_value title)"
  RELEASE_RUN_FROM="$(release_state_value source_tag)"
  channel="$(release_state_value channel)"

  [[ -n "$RELEASE_RUN_VERSION" && -n "$RELEASE_RUN_TITLE" ]] \
    || fail "saved release transaction is incomplete; run: ${PROGRAM} release doctor"
  case "$channel" in
    beta | rc | prerelease) RELEASE_RUN_KIND="beta" ;;
    stable) RELEASE_RUN_KIND="stable" ;;
    *) fail "saved release transaction has an unsupported channel: ${channel:-missing}" ;;
  esac
}

release_run_start_transaction() {
  local target_tag release_branch saved_tag saved_phase

  target_tag="v${RELEASE_RUN_VERSION}"
  release_branch="release/v${RELEASE_RUN_VERSION%%-*}"
  saved_tag="$(release_state_value target_tag)"
  saved_phase="$(release_state_value phase)"

  if [[ -n "$saved_tag" && "$saved_tag" != "$target_tag" ]]; then
    case "$saved_phase" in
      beta-verified | stable-verified)
        [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
          || fail "working tree must be clean before replacing a completed release transaction"
        release_state_clear
        release_clear_pretag_proof
        ;;
      *)
        fail "unfinished release transaction ${saved_tag} exists in phase ${saved_phase:-unknown}; resume it with: ${PROGRAM} release run"
        ;;
    esac
  fi

  if release_state_matches_target "$target_tag"; then
    [[ "$(release_state_value title)" == "$RELEASE_RUN_TITLE" ]] \
      || fail "release title does not match the saved ${target_tag} transaction"
    if [[ "$RELEASE_RUN_KIND" == "stable" ]]; then
      [[ "$(release_state_value source_tag)" == "$RELEASE_RUN_FROM" ]] \
        || fail "--from does not match the saved ${target_tag} transaction"
    fi
    return 0
  fi

  release_run_prepare_branch "$release_branch"
  if [[ "$RELEASE_RUN_KIND" == "beta" ]]; then
    cmd_release_prepare_beta "$RELEASE_RUN_VERSION" "$RELEASE_RUN_TITLE"
  else
    [[ "$(scripts/release-version.sh tag)" == "$RELEASE_RUN_FROM" ]] \
      || fail "origin/main canonical prerelease does not match ${RELEASE_RUN_FROM}"
    [[ "$(git rev-parse -q --verify "${RELEASE_RUN_FROM}^{commit}" 2>/dev/null || true)" == "$(git rev-parse HEAD)" ]] \
      || fail "source prerelease ${RELEASE_RUN_FROM} does not point exactly at origin/main"
    cmd_release_promote_stable "$RELEASE_RUN_VERSION" "$RELEASE_RUN_TITLE"
    [[ "$(release_state_value source_tag)" == "$RELEASE_RUN_FROM" ]] \
      || fail "saved stable source tag does not match ${RELEASE_RUN_FROM}"
  fi
}

cmd_release_run() {
  local phase target_tag release_branch prefix publication_commit
  local metadata state merged_at head_commit merge_commit url
  local -a watch_args

  parse_release_run_options "$@"
  if [[ -n "$RELEASE_RUN_KIND" ]]; then
    release_run_start_transaction
  else
    [[ -f "$RELEASE_STATE_FILE" ]] \
      || fail "no release transaction exists to resume"
    release_run_load_saved_identity
  fi

  target_tag="$(release_state_value target_tag)"
  release_branch="$(release_state_value release_branch)"
  [[ -n "$target_tag" && -n "$release_branch" ]] \
    || fail "saved release transaction lacks a target tag or release branch"
  [[ "$RELEASE_RUN_KIND" == "stable" ]] && prefix="stable" || prefix="beta"

  while true; do
    phase="$(release_state_value phase)"
    case "$phase" in
      beta-preparation | stable-promotion)
        if [[ "$(release_state_value review_confirmed)" == "1" ]]; then
          cmd_release_publish --resume-prepared
        else
          release_show_review_gate \
            "$(release_state_value target_version)" \
            "$(release_state_value commit_message)"
          release_run_pause \
            "Metadata Review" \
            "REVIEWED" \
            "$RELEASE_RUN_CONFIRM_REVIEWED" \
            || return 0
          cmd_release_publish \
            --confirm-reviewed \
            -m "$(release_state_value commit_message)"
        fi
        ;;
      beta-pr | stable-pr)
        publication_commit="$(release_state_value publication_commit)"
        [[ -n "$publication_commit" ]] \
          || fail "saved release transaction has no publication commit"
        release_run_ensure_pr \
          "$release_branch" \
          "$publication_commit" \
          "$target_tag" \
          "$(release_state_value title)"
        info "Release pull request" "#${RELEASE_RUN_PR_NUMBER}; ${RELEASE_RUN_PR_URL}"

        if [[ -n "$RELEASE_RUN_PR_MERGED_AT" ]]; then
          release_run_sync_merged_pr \
            "$prefix" \
            "$publication_commit" \
            "$RELEASE_RUN_PR_MERGE_COMMIT" \
            "$RELEASE_RUN_PR_NUMBER"
          continue
        fi
        [[ "$RELEASE_RUN_PR_STATE" == "open" ]] \
          || fail "PR #${RELEASE_RUN_PR_NUMBER} is ${RELEASE_RUN_PR_STATE} without a merge"

        release_run_checkout_publication_branch "$release_branch" "$publication_commit" \
          || fail "open PR #${RELEASE_RUN_PR_NUMBER} has no matching remote release branch"
        cmd_pr_checks --watch --required
        release_run_pause \
          "Pull Request Merge" \
          "MERGE" \
          "$RELEASE_RUN_CONFIRM_MERGE" \
          || return 0
        cmd_pr_merge --delete-branch

        metadata="$(release_run_pr_metadata "$RELEASE_RUN_PR_NUMBER")"
        IFS='|' read -r state merged_at head_commit merge_commit url <<<"$metadata"
        [[ "$head_commit" == "$publication_commit" && -n "$merged_at" ]] \
          || fail "PR #${RELEASE_RUN_PR_NUMBER} did not report an exact successful merge"
        release_run_sync_merged_pr \
          "$prefix" \
          "$publication_commit" \
          "$merge_commit" \
          "$RELEASE_RUN_PR_NUMBER"
        ;;
      beta-pretag | stable-pretag)
        [[ "$(branch_name)" == "main" ]] \
          || fail "post-merge pre-tag validation must run from synchronized main"
        [[ "$(git rev-parse HEAD)" == "$(release_state_value merge_commit)" ]] \
          || fail "main no longer matches the saved release merge commit"
        if [[ "$(release_pretag_proof_state "$target_tag" "$(tree_fingerprint)")" != "valid for exact commit" ]]; then
          cmd_release_pretag "$target_tag"
        fi
        release_run_pause_tag "$target_tag" || return 0
        cmd_release_tag --confirm "$target_tag"
        ;;
      beta-tagged | stable-tagged)
        watch_args=(
          "$target_tag"
          --interval "$RELEASE_RUN_INTERVAL"
          --attempts "$RELEASE_RUN_ATTEMPTS"
        )
        cmd_release_watch "${watch_args[@]}"
        ;;
      beta-published | stable-published)
        release_run_pause \
          "Published Asset Verification" \
          "VERIFY" \
          "$RELEASE_RUN_CONFIRM_VERIFY" \
          || return 0
        cmd_release_verify "$target_tag"
        ;;
      beta-verified | stable-verified)
        heading "Resumable Release Complete"
        info "Tag" "$target_tag"
        info "Commit" "$(release_state_value verified_commit)"
        info "Result" "published assets verified"
        ok "${target_tag} completed through the single resumable release command"
        return 0
        ;;
      *)
        fail "saved release phase ${phase:-missing} cannot be resumed by release run"
        ;;
    esac
  done
}

parse_release_beta_options() {
  RELEASE_BETA_VERSION=""
  RELEASE_BETA_TITLE=""
  RELEASE_BETA_CONFIRM_REVIEWED=0
  RELEASE_BETA_CONFIRM_MERGE=0
  RELEASE_BETA_CONFIRM_TAG=""
  RELEASE_BETA_CONFIRM_VERIFY=0

  while (($# > 0)); do
    case "$1" in
      --confirm-reviewed) RELEASE_BETA_CONFIRM_REVIEWED=1 ;;
      --confirm-merge) RELEASE_BETA_CONFIRM_MERGE=1 ;;
      --confirm-tag)
        shift
        (($# > 0)) || fail "--confirm-tag requires the exact beta tag"
        RELEASE_BETA_CONFIRM_TAG="$1"
        ;;
      --confirm-verify) RELEASE_BETA_CONFIRM_VERIFY=1 ;;
      -*)
        fail "unknown release beta option: $1"
        ;;
      *)
        if [[ -z "$RELEASE_BETA_VERSION" ]]; then
          RELEASE_BETA_VERSION="$1"
        elif [[ -z "$RELEASE_BETA_TITLE" ]]; then
          RELEASE_BETA_TITLE="$1"
        else
          fail "release beta accepts one version and one release title"
        fi
        ;;
    esac
    shift
  done

  [[ "$RELEASE_BETA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[1-9][0-9]*$ ]] \
    || fail "release beta requires X.Y.Z-beta.N"
  [[ -n "$RELEASE_BETA_TITLE" ]] || fail "release beta requires a release title"
}

cmd_release_beta() {
  local base_version target_tag branch phase
  local -a args

  parse_release_beta_options "$@"
  base_version="${RELEASE_BETA_VERSION%%-*}"
  target_tag="v${RELEASE_BETA_VERSION}"
  branch="$(branch_name)"
  phase="$(release_state_value phase)"

  if [[ "$(release_worktree_tag)" != "$target_tag" ]]; then
    [[ "$branch" == "release/v${base_version}" ]] \
      || fail "beta preparation requires release/v${base_version}; current branch is ${branch:-detached HEAD}"
    cmd_release_prepare_beta "$RELEASE_BETA_VERSION" "$RELEASE_BETA_TITLE"
    return 0
  fi

  case "$phase" in
    beta-preparation)
      if ((RELEASE_BETA_CONFIRM_REVIEWED == 0)); then
        release_show_review_gate \
          "$RELEASE_BETA_VERSION" \
          "Release: prepare v${RELEASE_BETA_VERSION}"
        return 0
      fi
      cmd_release_publish \
        --confirm-reviewed \
        -m "Release: prepare v${RELEASE_BETA_VERSION}"
      phase="beta-pr"
      ;;
    beta-verified)
      ok "${target_tag} is already published and verified; no action required"
      return 0
      ;;
  esac

  if [[ "$phase" == "beta-pr" && "$RELEASE_BETA_CONFIRM_MERGE" == "0" &&
    -z "$RELEASE_BETA_CONFIRM_TAG" && "$RELEASE_BETA_CONFIRM_VERIFY" == "0" ]]; then
    heading "Beta Pull Request Gate"
    info "Tag" "$target_tag"
    info "Next command" "${PROGRAM} release run"
    ok "release metadata is published; continue with the resumable command so it can create, check, and merge the exact PR"
    return 0
  fi

  args=(--non-interactive)
  ((RELEASE_BETA_CONFIRM_MERGE == 0)) || args+=(--confirm-merge)
  [[ -z "$RELEASE_BETA_CONFIRM_TAG" ]] \
    || args+=(--confirm-tag "$RELEASE_BETA_CONFIRM_TAG")
  ((RELEASE_BETA_CONFIRM_VERIFY == 0)) || args+=(--confirm-verify)
  cmd_release_run "${args[@]}"
}

parse_release_stable_options() {
  RELEASE_STABLE_VERSION=""
  RELEASE_STABLE_TITLE=""
  RELEASE_STABLE_FROM=""
  RELEASE_STABLE_CONFIRM_REVIEWED=0
  RELEASE_STABLE_CONFIRM_MERGE=0
  RELEASE_STABLE_CONFIRM_TAG=""
  RELEASE_STABLE_ADMIN=0

  while (($# > 0)); do
    case "$1" in
      --from)
        shift
        (($# > 0)) || fail "--from requires the exact source prerelease tag"
        RELEASE_STABLE_FROM="$1"
        ;;
      --confirm-reviewed) RELEASE_STABLE_CONFIRM_REVIEWED=1 ;;
      --confirm-merge) RELEASE_STABLE_CONFIRM_MERGE=1 ;;
      --admin) RELEASE_STABLE_ADMIN=1 ;;
      --confirm-tag)
        shift
        (($# > 0)) || fail "--confirm-tag requires the exact stable tag"
        RELEASE_STABLE_CONFIRM_TAG="$1"
        ;;
      -*)
        fail "unknown release stable option: $1"
        ;;
      *)
        if [[ -z "$RELEASE_STABLE_VERSION" ]]; then
          RELEASE_STABLE_VERSION="$1"
        elif [[ -z "$RELEASE_STABLE_TITLE" ]]; then
          RELEASE_STABLE_TITLE="$1"
        else
          fail "release stable accepts one version and one release title"
        fi
        ;;
    esac
    shift
  done

  [[ "$RELEASE_STABLE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "release stable requires X.Y.Z"
  [[ -n "$RELEASE_STABLE_TITLE" ]] || fail "release stable requires a release title"
  [[ "$RELEASE_STABLE_FROM" =~ ^v${RELEASE_STABLE_VERSION//./\\.}-(beta\.[1-9][0-9]*|rc\.[1-9][0-9]*)$ ]] \
    || fail "--from must be a matching v${RELEASE_STABLE_VERSION}-beta.N or -rc.N tag"
  ((RELEASE_STABLE_ADMIN == 0 || RELEASE_STABLE_CONFIRM_MERGE == 1)) \
    || fail "--admin is valid only with --confirm-merge"
}

cmd_release_stable() {
  local target_tag release_branch branch phase proof
  local -a merge_args=(--delete-branch)

  parse_release_stable_options "$@"
  target_tag="v${RELEASE_STABLE_VERSION}"
  release_branch="release/v${RELEASE_STABLE_VERSION}"
  branch="$(branch_name)"

  if [[ "$(release_worktree_tag)" != "$target_tag" ]]; then
    [[ "$branch" == "$release_branch" ]] \
      || fail "stable promotion requires ${release_branch}; current branch is ${branch:-detached HEAD}"
    [[ "$(scripts/release-version.sh tag)" == "$RELEASE_STABLE_FROM" ]] \
      || fail "current canonical prerelease does not match --from ${RELEASE_STABLE_FROM}"
    [[ "$(git rev-parse -q --verify "${RELEASE_STABLE_FROM}^{commit}" 2>/dev/null || true)" == "$(git rev-parse HEAD)" ]] \
      || fail "source prerelease ${RELEASE_STABLE_FROM} does not point exactly at HEAD"
    cmd_release_promote_stable "$RELEASE_STABLE_VERSION" "$RELEASE_STABLE_TITLE"
    return 0
  fi

  release_state_matches_target "$target_tag" \
    || fail "no saved stable transaction exists for ${target_tag}"
  [[ "$(release_state_value source_tag)" == "$RELEASE_STABLE_FROM" ]] \
    || fail "saved source tag does not match --from ${RELEASE_STABLE_FROM}"
  phase="$(release_state_value phase)"
  case "$phase" in
    stable-tagged)
      cmd_release_watch "$target_tag"
      heading "Final Verification Gate"
      info "Next command" "${PROGRAM} release verify ${target_tag}"
      ok "stable publication completed; final asset verification remains manual"
      return 0
      ;;
    stable-published)
      heading "Final Verification Gate"
      info "Next command" "${PROGRAM} release verify ${target_tag}"
      ok "stable publication is complete; final asset verification remains manual"
      return 0
      ;;
    stable-verified)
      ok "${target_tag} is already published and verified; no action required"
      return 0
      ;;
  esac

  if [[ "$phase" == "stable-promotion" ]]; then
    if ((RELEASE_STABLE_CONFIRM_REVIEWED == 0)); then
      release_show_review_gate "$RELEASE_STABLE_VERSION" "Release: promote v${RELEASE_STABLE_VERSION} stable"
      return 0
    fi
    cmd_release_publish \
      --confirm-reviewed \
      -m "Release: promote v${RELEASE_STABLE_VERSION} stable"
    cmd_pr_create --base main --title "Release ${target_tag}: ${RELEASE_STABLE_TITLE}"
    cmd_pr_checks --watch --required
    heading "Stable PR Merge Confirmation Required"
    info "Next command" "${PROGRAM} release stable ${RELEASE_STABLE_VERSION} --from ${RELEASE_STABLE_FROM} \"${RELEASE_STABLE_TITLE}\" --confirm-merge"
    ok "required checks passed; the PR was not merged"
    return 0
  fi

  if [[ "$phase" == "stable-pr" && "$branch" == "$release_branch" ]]; then
    if ((RELEASE_STABLE_CONFIRM_MERGE == 0)); then
      cmd_pr_status
      heading "Stable PR Merge Confirmation Required"
      info "Next command" "${PROGRAM} release stable ${RELEASE_STABLE_VERSION} --from ${RELEASE_STABLE_FROM} \"${RELEASE_STABLE_TITLE}\" --confirm-merge"
      ok "the PR was not merged"
      return 0
    fi
    ((RELEASE_STABLE_ADMIN == 0)) || merge_args+=(--admin)
    cmd_pr_merge "${merge_args[@]}"
    git switch main
    git pull --ff-only origin main
    git fetch --prune origin
    release_state_update phase stable-pretag publication_commit "$(git rev-parse HEAD)"
    branch="main"
  elif [[ "$phase" == "stable-pr" && "$branch" == "main" ]]; then
    release_state_update phase stable-pretag publication_commit "$(git rev-parse HEAD)"
    branch="main"
  fi

  [[ "$branch" == "main" ]] \
    || fail "stable pre-tag orchestration requires synchronized main; current branch is ${branch}"
  proof="$(release_pretag_proof_state "$target_tag" "$(tree_fingerprint)")"
  [[ "$proof" == "valid for exact commit" ]] || cmd_release_pretag "$target_tag"

  if [[ -z "$RELEASE_STABLE_CONFIRM_TAG" ]]; then
    heading "Stable Tag Confirmation Required"
    info "Tag" "$target_tag"
    info "Proof" "valid for exact commit"
    info "Next command" "${PROGRAM} release stable ${RELEASE_STABLE_VERSION} --from ${RELEASE_STABLE_FROM} \"${RELEASE_STABLE_TITLE}\" --confirm-tag ${target_tag}"
    ok "no tag was created"
    return 0
  fi
  [[ "$RELEASE_STABLE_CONFIRM_TAG" == "$target_tag" ]] \
    || fail "stable tag confirmation must exactly match ${target_tag}"
  cmd_release_tag --confirm "$target_tag"
  cmd_release_watch "$target_tag"
  heading "Final Verification Gate"
  info "Next command" "${PROGRAM} release verify ${target_tag}"
  ok "stable publication completed; final asset verification remains manual"
}

cmd_release() {
  local subcommand="${1:-status}"
  if (($# > 0)); then
    shift
  fi

  case "$subcommand" in
    status) cmd_release_status "$@" ;;
    explain) cmd_release_explain "$@" ;;
    doctor) cmd_release_doctor "$@" ;;
    prepare-beta) cmd_release_prepare_beta "$@" ;;
    promote-stable) cmd_release_promote_stable "$@" ;;
    publish) cmd_release_publish "$@" ;;
    recover) cmd_release_recover "$@" ;;
    pretag) cmd_release_pretag "$@" ;;
    tag) cmd_release_tag "$@" ;;
    watch) cmd_release_watch "$@" ;;
    verify) cmd_release_verify "$@" ;;
    run) cmd_release_run "$@" ;;
    beta) cmd_release_beta "$@" ;;
    stable) cmd_release_stable "$@" ;;
    -h | --help | help) usage ;;
    *) fail "unknown release command: $subcommand" ;;
  esac
}

cmd_resume() {
  local action mode stage message branch
  action="$(state_value action)"
  mode="$(state_value mode)"
  stage="$(state_value stage)"
  message="$(state_value message)"
  [[ -n "$action" ]] || fail "no saved operation is available"

  heading "Resume Repository Workflow"
  info "Action" "$action"
  info "Stage" "${stage:-unknown}"
  info "Mode" "${mode:-auto}"

  case "$action" in
    check)
      cmd_check --mode "${mode:-auto}"
      ;;
    publish)
      if [[ "$stage" == "Push branch" ]] && [[ -z "$(git status --porcelain --untracked-files=all)" ]]; then
        branch="$(branch_name)"
        ensure_publish_branch "$branch"
        CURRENT_ACTION="publish"
        CURRENT_MODE="${mode:-auto}"
        CURRENT_MESSAGE="$message"
        run_step "Push branch" push_branch "$branch"
        state_clear
        ok "saved publish operation completed"
      else
        [[ -n "$message" ]] || fail "saved publish operation has no commit message"
        cmd_publish --mode "${mode:-auto}" -m "$message"
      fi
      ;;
    release-publish)
      if [[ "$stage" == "Push release branch" ]] && [[ -z "$(git status --porcelain --untracked-files=all)" ]]; then
        branch="$(branch_name)"
        ensure_release_publish_branch "$branch"
        CURRENT_ACTION="release-publish"
        CURRENT_MODE="full"
        CURRENT_MESSAGE="$message"
        run_step "Push release branch" push_branch "$branch"
        state_clear
        ok "saved release publication completed"
      else
        echo "Prepared metadata is intact." >&2
        echo "Safe recovery:" >&2
        echo "  ${PROGRAM} release publish --resume-prepared" >&2
        fail "release publication requires the dedicated prepared-metadata recovery path"
      fi
      ;;
    *) fail "unknown saved action: $action" ;;
  esac
}

cmd_clean_cache() {
  rm -rf "$STATE_DIR"
  mkdir -p "$STATE_DIR" "$CACHE_DIR"
  chmod 700 "$STATE_DIR" "$CACHE_DIR" 2>/dev/null || true
  ok "repository workflow cache and resume state cleared"
}

main() {
  require_repo
  local command="${1:-status}"
  if (($# > 0)); then
    shift
  fi
  case "$command" in
    status) cmd_status "$@" ;;
    explain) cmd_explain "$@" ;;
    check) cmd_check "$@" ;;
    publish) cmd_publish "$@" ;;
    work) cmd_work "$@" ;;
    pr) cmd_pr "$@" ;;
    release) cmd_release "$@" ;;
    resume) cmd_resume "$@" ;;
    clean-cache) cmd_clean_cache "$@" ;;
    -h | --help | help) usage ;;
    *)
      usage >&2
      fail "unknown command: $command"
      ;;
  esac
}

main "$@"
