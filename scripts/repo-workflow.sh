#!/usr/bin/env bash
# Safe, resumable repository workflow for ERPNext Developer Toolkit.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROGRAM="scripts/repo-workflow.sh"
STATE_DIR="$(git rev-parse --git-path erpnext-workflow 2>/dev/null || true)"
CACHE_DIR="${STATE_DIR}/cache"

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
  scripts/repo-workflow.sh release prepare-beta X.Y.Z-beta.N "Release title"
  scripts/repo-workflow.sh release promote-stable X.Y.Z "Release title"
  scripts/repo-workflow.sh release publish --confirm-reviewed -m "Commit message"
  scripts/repo-workflow.sh release pretag [vX.Y.Z[-prerelease]] [--offline]
  scripts/repo-workflow.sh release tag --confirm vX.Y.Z[-prerelease]
  scripts/repo-workflow.sh release watch [vX.Y.Z[-prerelease]] [--interval SECONDS] [--attempts N]
  scripts/repo-workflow.sh release verify [vX.Y.Z[-prerelease]]
  scripts/repo-workflow.sh resume
  scripts/repo-workflow.sh clean-cache

Commands:
  status       Show branch, sync, changes, risk, selected validation, and saved state.
  explain      Explain why the current tree selects fast or full validation.
  check        Regenerate checksums and run the minimum safe local validation.
  publish      Check, stage, commit, and push the current feature branch.
  work         Consolidated start, finish, and land workflow for routine changes.
  pr           Create, inspect, check, and merge the current branch pull request.
  release      Inspect, prepare, tag, watch, and verify protected releases.
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
    scripts/validate-release.sh | scripts/build-release-bundle.sh | scripts/generate-release-checksums.sh | scripts/release-manifest-files.sh | scripts/check-release-artifact-consistency.sh)
      echo "release integrity implementation"
      ;;
    scripts/release-*.sh | scripts/test-release-*.sh)
      echo "release transaction or release regression path"
      ;;
    scripts/repo-workflow.sh | scripts/test-repo-workflow.sh | scripts/test-repo-workflow-pr.sh | scripts/test-repo-workflow-release.sh | scripts/test-repo-workflow-release-transaction.sh | scripts/test-repo-workflow-release-finalize.sh)
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
  [[ -f "${STATE_DIR}/${name}" ]] && cat "${STATE_DIR}/${name}"
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
      timeout "${SHELLCHECK_FILE_TIMEOUT:-180}" shellcheck -x -S warning "$file"
    else
      shellcheck -x -S warning "$file"
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
      scripts/repo-workflow.sh | scripts/test-repo-workflow.sh | scripts/test-repo-workflow-pr.sh | scripts/test-repo-workflow-release.sh | scripts/test-repo-workflow-release-transaction.sh | scripts/test-repo-workflow-release-finalize.sh)
        add_focused_test scripts/test-repo-workflow.sh
        add_focused_test scripts/test-repo-workflow-pr.sh
        add_focused_test scripts/test-repo-workflow-release.sh
        add_focused_test scripts/test-repo-workflow-release-transaction.sh
        add_focused_test scripts/test-repo-workflow-release-finalize.sh
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

  pr_args=(--base "$WORK_BASE" --title "$WORK_PR_TITLE" --no-fill)
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
  gh pr checks "$number" --required \
    || fail "required pull request checks are not successful; rerun: ${PROGRAM} pr checks --watch --required"

  IFS='|' read -r state merge_status review < <(
    gh pr view "$number" --json state,mergeStateStatus,reviewDecision \
      --jq '"\(.state)|\(.mergeStateStatus)|\(.reviewDecision // \"\")"'
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
  local branch number
  (($# == 0)) || fail "pr status does not accept options"

  require_gh
  branch="$(branch_name)"
  ensure_pr_branch "$branch"
  number="$(require_open_pr_number "$branch")"

  heading "Pull Request Status"
  gh pr view "$number" \
    --json number,url,state,isDraft,mergeStateStatus,title,headRefName,baseRefName \
    --jq '"PR #\\(.number): \\(.title)\\nURL: \\(.url)\\nState: \\(.state)\\nDraft: \\(.isDraft)\\nMerge status: \\(.mergeStateStatus)\\nBranch: \\(.headRefName) -> \\(.baseRefName)"'
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

release_expected_branch() {
  local version="$1" channel="$2" base_version
  base_version="${version%%-*}"

  case "$channel" in
    stable) printf '%s\n' "main" ;;
    *) printf '%s\n' "release/v${base_version}" ;;
  esac
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
    0) RELEASE_REMOTE_TAG="exists" ;;
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

  if [[ "$RELEASE_GITHUB_RELEASE_STATE" == "published" ]]; then
    RELEASE_READINESS="complete"
    RELEASE_NEXT_ACTION="${PROGRAM} release verify ${RELEASE_TAG}"
    return 0
  fi

  if [[ "$RELEASE_REMOTE_TAG" == "exists" ]]; then
    RELEASE_READINESS="tag exists; release verification required"
    RELEASE_NEXT_ACTION="${PROGRAM} release watch ${RELEASE_TAG}"
    return 0
  fi

  if [[ "$RELEASE_LOCAL_TAG" == "exists" ]]; then
    RELEASE_READINESS="local tag exists; blocked"
    RELEASE_NEXT_ACTION="Inspect or remove the unpushed local ${RELEASE_TAG} tag before continuing."
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
  local changed_count fingerprint

  [[ -x scripts/release-version.sh ]] \
    || fail "scripts/release-version.sh is missing or not executable"

  RELEASE_VERSION="$(scripts/release-version.sh read)"
  RELEASE_RUNTIME_VERSION="$(scripts/release-version.sh script)"
  RELEASE_CHANNEL="$(scripts/release-version.sh channel)"
  RELEASE_TAG="$(scripts/release-version.sh tag)"
  RELEASE_BRANCH="$(branch_name)"
  RELEASE_EXPECTED_BRANCH="$(
    release_expected_branch "$RELEASE_VERSION" "$RELEASE_CHANNEL"
  )"

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
  else
    RELEASE_LOCAL_TAG="missing"
  fi

  release_collect_remote_tag_state
  release_collect_github_release_state

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

  [[ "$RELEASE_LOCAL_TAG" == "missing" ]] \
    || release_add_blocker "local tag already exists: ${RELEASE_TAG}"
  if [[ "$RELEASE_OFFLINE" == "0" ]]; then
    [[ "$RELEASE_REMOTE_TAG" != "exists" ]] \
      || release_add_blocker "remote tag already exists: ${RELEASE_TAG}"
  fi

  release_compute_next_action
}

cmd_release_status() {
  parse_release_read_options "$@"
  release_collect_state

  heading "Release Status"
  info "Version" "$RELEASE_VERSION"
  info "Runtime version" "$RELEASE_RUNTIME_VERSION"
  info "Version alignment" "$RELEASE_VERSION_ALIGNMENT"
  info "Channel" "$RELEASE_CHANNEL"
  info "Expected tag" "$RELEASE_TAG"
  info "Current branch" "${RELEASE_BRANCH:-detached HEAD}"
  info "Expected branch" "$RELEASE_EXPECTED_BRANCH"
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

cmd_release_explain() {
  local blocker

  parse_release_read_options "$@"
  release_collect_state

  heading "Release Readiness Explanation"
  info "Version" "$RELEASE_VERSION"
  info "Channel" "$RELEASE_CHANNEL"
  info "Expected identity" "${RELEASE_TAG} from ${RELEASE_EXPECTED_BRANCH}"
  info "Static readiness" "$RELEASE_READINESS"
  info "Pre-tag proof" "$RELEASE_PRETAG_PROOF"

  echo
  if [[ "$RELEASE_GITHUB_RELEASE_STATE" == "published" ]]; then
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
  git status --short
}

cmd_release_prepare_beta() {
  local target_version="${1:-}" release_title="${2:-}"
  (($# == 2)) || fail "usage: ${PROGRAM} release prepare-beta X.Y.Z-beta.N \"Release title\""
  [[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[1-9][0-9]*$ ]] \
    || fail "beta version must use X.Y.Z-beta.N with N greater than zero"
  [[ -n "$release_title" && "$release_title" != *$'\n'* && "$release_title" != *$'\r'* ]] \
    || fail "release title must be non-empty and one line"
  [[ -x scripts/release-prepare-beta.sh ]] \
    || fail "scripts/release-prepare-beta.sh is missing or not executable"

  release_require_clean_transaction_tree
  release_clear_pretag_proof
  heading "Prepare Beta Metadata"
  scripts/release-prepare-beta.sh "$target_version" "$release_title"
  release_cache_validated_tree
  release_show_review_gate "$target_version" "Release: prepare v${target_version}"
}

cmd_release_promote_stable() {
  local target_version="${1:-}" release_title="${2:-}"
  (($# == 2)) || fail "usage: ${PROGRAM} release promote-stable X.Y.Z \"Release title\""
  [[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "stable version must use X.Y.Z"
  [[ -n "$release_title" && "$release_title" != *$'\n'* && "$release_title" != *$'\r'* ]] \
    || fail "release title must be non-empty and one line"
  [[ -x scripts/release-promote-stable.sh ]] \
    || fail "scripts/release-promote-stable.sh is missing or not executable"

  release_require_clean_transaction_tree
  release_clear_pretag_proof
  heading "Promote Stable Metadata"
  scripts/release-promote-stable.sh "$target_version" "$release_title"
  release_cache_validated_tree
  release_show_review_gate "$target_version" "Release: promote v${target_version} stable"
}

parse_release_publish_options() {
  RELEASE_PUBLISH_MESSAGE=""
  RELEASE_PUBLISH_CONFIRMED=0

  while (($# > 0)); do
    case "$1" in
      -m | --message)
        shift
        (($# > 0)) || fail "--message requires a commit message"
        RELEASE_PUBLISH_MESSAGE="$1"
        ;;
      --confirm-reviewed) RELEASE_PUBLISH_CONFIRMED=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown release publish option: $1" ;;
    esac
    shift
  done

  [[ -n "$RELEASE_PUBLISH_MESSAGE" ]] \
    || fail "release publish requires -m \"Commit message\""
  [[ "$RELEASE_PUBLISH_CONFIRMED" == "1" ]] \
    || fail "release publish requires --confirm-reviewed after reviewing the metadata and changelog"
}

ensure_release_publish_branch() {
  local branch="$1"
  case "$branch" in
    release/v* | feature/v* | beta) ;;
    *)
      fail "release publish is limited to release/v*, feature/v*, or beta branches; current branch: ${branch:-detached HEAD}"
      ;;
  esac
}

cmd_release_publish() {
  local branch
  parse_release_publish_options "$@"
  branch="$(branch_name)"
  ensure_release_publish_branch "$branch"

  CURRENT_ACTION="release-publish"
  CURRENT_MODE="full"
  CURRENT_MESSAGE="$RELEASE_PUBLISH_MESSAGE"
  state_write "$CURRENT_ACTION" "$CURRENT_MODE" "preflight" "$CURRENT_MESSAGE"

  collect_changed_files
  ((${#CHANGED_FILES[@]} > 0)) \
    || fail "working tree is clean; there is no reviewed release metadata to publish"

  run_step "Remote synchronization" fetch_and_check_sync "$branch"
  perform_check full 0

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
  run_step "Push release branch" push_branch "$branch"
  state_clear

  heading "Release Metadata Published"
  info "Branch" "$branch"
  info "Commit" "$(git rev-parse --short HEAD)"
  info "Upstream" "origin/${branch}"
  info "Next action" "${PROGRAM} pr create"
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
  local target_tag fingerprint
  local -a args

  parse_release_pretag_options "$@"
  [[ -x scripts/release-version.sh ]] \
    || fail "scripts/release-version.sh is missing or not executable"
  [[ -x scripts/release-pretag-check.sh ]] \
    || fail "scripts/release-pretag-check.sh is missing or not executable"
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "working tree must be clean before pre-tag validation"

  target_tag="${RELEASE_PRETAG_TAG:-$(scripts/release-version.sh tag)}"
  args=("$target_tag")
  [[ "$RELEASE_PRETAG_OFFLINE" == "0" ]] || args+=(--offline)

  heading "Strict Pre-Tag Validation"
  scripts/release-pretag-check.sh "${args[@]}"

  fingerprint="$(tree_fingerprint)"
  cache_store full "$fingerprint"
  release_record_pretag_proof "$target_tag" "$fingerprint"

  heading "Pre-Tag Proof Recorded"
  info "Tag" "$target_tag"
  info "Commit" "$(git rev-parse HEAD)"
  info "Proof" "valid for exact commit"
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
  local target_tag branch expected_branch fingerprint
  local remote_commit rc upstream counts behind ahead

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
  expected_branch="$(release_expected_branch "$(scripts/release-version.sh read)" "$(scripts/release-version.sh channel)")"
  [[ "$branch" == "$expected_branch" ]] \
    || fail "tag ${target_tag} must be created from ${expected_branch}; current branch is ${branch}"

  heading "Release Tag Preflight"
  fetch_and_check_sync "$branch"
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [[ "$upstream" == "origin/${branch}" ]] \
    || fail "release branch upstream must be origin/${branch}; current upstream is ${upstream:-none}"
  counts="$(git rev-list --left-right --count "${upstream}...HEAD")"
  behind="${counts%%[[:space:]]*}"
  ahead="${counts##*[[:space:]]}"
  [[ "$behind" == "0" && "$ahead" == "0" ]] \
    || fail "release branch must be synchronized with ${upstream}; ahead ${ahead}, behind ${behind}"

  if git rev-parse -q --verify "refs/tags/${target_tag}" >/dev/null; then
    fail "local tag already exists: ${target_tag}"
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/${target_tag}" >/dev/null 2>&1; then
    fail "remote tag already exists: ${target_tag}"
  fi

  fingerprint="$(tree_fingerprint)"
  release_require_exact_pretag_proof "$target_tag"

  heading "Create Annotated Release Tag"
  git tag -a "$target_tag" "$(git rev-parse HEAD)" -m "ERPNext Developer Toolkit ${target_tag}"

  set +e
  git push origin "refs/tags/${target_tag}:refs/tags/${target_tag}"
  rc=$?
  set -e

  if ((rc != 0)); then
    remote_commit="$(release_remote_tag_commit "$target_tag")"
    if [[ "$remote_commit" == "$(git rev-parse HEAD)" ]]; then
      warn "tag push returned an error, but origin has the expected exact tag commit"
    elif [[ -z "$remote_commit" ]]; then
      git tag -d "$target_tag" >/dev/null 2>&1 || true
      fail "tag push failed; the newly created local tag was removed so the operation can be retried"
    else
      fail "tag push failed and origin/${target_tag} points to an unexpected commit; inspect before continuing"
    fi
  fi

  remote_commit="$(release_remote_tag_commit "$target_tag")"
  [[ "$remote_commit" == "$(git rev-parse HEAD)" ]] \
    || fail "origin/${target_tag} does not peel to the current release commit"

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

cmd_release_watch() {
  local target_tag run_id="" attempt remote_commit run_head conclusion run_url

  parse_release_watch_options "$@"
  require_gh
  target_tag="$(release_resolve_canonical_tag "$RELEASE_WATCH_TAG")"
  remote_commit="$(release_remote_tag_commit "$target_tag")"
  [[ -n "$remote_commit" ]] \
    || fail "remote annotated tag is missing or cannot be resolved: ${target_tag}"

  heading "Locate Protected Release Workflow"
  for ((attempt = 1; attempt <= RELEASE_WATCH_ATTEMPTS; attempt++)); do
    run_id="$(release_find_workflow_run "$target_tag")"
    [[ -z "$run_id" ]] || break
    echo "Attempt ${attempt}/${RELEASE_WATCH_ATTEMPTS}: release workflow is not visible yet"
    sleep "$RELEASE_WATCH_INTERVAL"
  done
  [[ -n "$run_id" ]] || fail "no release.yml workflow run was found for ${target_tag}"

  run_head="$(gh run view "$run_id" --json headSha --jq '.headSha')"
  [[ "$run_head" == "$remote_commit" ]] \
    || fail "release workflow head ${run_head} does not match ${target_tag} commit ${remote_commit}"
  run_url="$(gh run view "$run_id" --json url --jq '.url')"

  info "Tag" "$target_tag"
  info "Workflow run" "$run_id"
  info "Commit" "$run_head"
  info "URL" "$run_url"

  heading "Watch Protected Release Workflow"
  gh run watch "$run_id" --exit-status

  conclusion="$(gh run view "$run_id" --json conclusion --jq '.conclusion // empty')"
  [[ "$conclusion" == "success" ]] || fail "release workflow conclusion is ${conclusion:-unknown}"

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
  [[ -f "$archive" ]] || fail "published release archive is missing"
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
  cmp -s "${verify_dir}/SHA256SUMS" "${root}/SHA256SUMS" || fail "standalone and bundled SHA256SUMS differ"
  cmp -s "${verify_dir}/erpnext-dev.sh" "${root}/erpnext-dev.sh" || fail "standalone and bundled entrypoints differ"
  cmp -s "${verify_dir}/RELEASE-MANIFEST.txt" "${root}/RELEASE-MANIFEST.txt" || fail "standalone and bundled manifests differ"
  if [[ -f "${verify_dir}/SHA256SUMS.asc" ]]; then
    cmp -s "${verify_dir}/SHA256SUMS.asc" "${root}/SHA256SUMS.asc" || fail "standalone and bundled signatures differ"
  fi

  (
    cd "$root"
    scripts/release-version.sh assert-script
    scripts/release-version.sh assert-tag "$target_tag"
    sha256sum -c SHA256SUMS
  )
  ok "release bundle checksums verified"
  release_verify_signature "$root" "$target_tag"

  rm -rf "$verify_dir"
  heading "Published Release Verified"
  info "Tag" "$target_tag"
  info "Commit" "$remote_commit"
  info "Workflow" "success"
  info "Release" "$release_url"
  ok "published release ${target_tag} verified"
}

cmd_release() {
  local subcommand="${1:-status}"
  if (($# > 0)); then
    shift
  fi

  case "$subcommand" in
    status) cmd_release_status "$@" ;;
    explain) cmd_release_explain "$@" ;;
    prepare-beta) cmd_release_prepare_beta "$@" ;;
    promote-stable) cmd_release_promote_stable "$@" ;;
    publish) cmd_release_publish "$@" ;;
    pretag) cmd_release_pretag "$@" ;;
    tag) cmd_release_tag "$@" ;;
    watch) cmd_release_watch "$@" ;;
    verify) cmd_release_verify "$@" ;;
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
        fail "release publication cannot be resumed before the push stage; inspect the prepared metadata and rerun release publish --confirm-reviewed"
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
