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
  scripts/repo-workflow.sh pr create [--base main] [--title TEXT] [--body TEXT|--body-file PATH] [--draft]
  scripts/repo-workflow.sh pr status
  scripts/repo-workflow.sh pr checks [--watch] [--required]
  scripts/repo-workflow.sh pr merge [--merge|--squash|--rebase] [--admin] [--delete-branch]
  scripts/repo-workflow.sh resume
  scripts/repo-workflow.sh clean-cache

Commands:
  status       Show branch, sync, changes, risk, selected validation, and saved state.
  explain      Explain why the current tree selects fast or full validation.
  check        Regenerate checksums and run the minimum safe local validation.
  publish      Check, stage, commit, and push the current feature branch.
  pr           Create, inspect, check, and merge the current branch pull request.
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
    scripts/repo-workflow.sh | scripts/test-repo-workflow.sh | scripts/test-repo-workflow-pr.sh)
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
      scripts/repo-workflow.sh | scripts/test-repo-workflow.sh | scripts/test-repo-workflow-pr.sh)
        add_focused_test scripts/test-repo-workflow.sh
        add_focused_test scripts/test-repo-workflow-pr.sh
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

require_gh() {
  command -v gh >/dev/null 2>&1 \
    || fail "GitHub CLI (gh) is required for pull request commands"
  gh auth status >/dev/null 2>&1 \
    || fail "GitHub CLI is not authenticated; run: gh auth login"
}

ensure_pr_branch() {
  local branch="$1"
  [[ -n "$branch" ]] || fail "cannot manage a pull request from detached HEAD"
  if is_protected_branch "$branch"; then
    fail "pull request operations require a feature or documentation branch; current branch: ${branch}"
  fi
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
    pr) cmd_pr "$@" ;;
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
