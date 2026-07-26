# Repository Workflow

ERPNext Developer Toolkit uses one repository command for routine validation,
commit, push, and failure recovery:

```bash
scripts/repo-workflow.sh
```

The wrapper preserves the existing release-integrity gates. It reduces repeated
manual work by selecting the minimum safe local validation, regenerating
`SHA256SUMS`, caching successful full validation for the exact repository tree,
and delegating the complete protected gate to pull-request CI.

## Daily commands

### Show current state

```bash
scripts/repo-workflow.sh status
```

This reports:

- Current branch
- Upstream synchronization
- Changed files
- Selected validation mode
- Saved resumable operation

Explain why a mode was selected:

```bash
scripts/repo-workflow.sh explain
```

### Validate current changes

```bash
scripts/repo-workflow.sh check
```

The default `auto` mode selects:

- `fast` for normal documentation and isolated low-risk changes
- `full` for release, security, update, workflow, manifest, and GitHub automation paths

Force a mode when diagnosing the workflow:

```bash
scripts/repo-workflow.sh check --fast
scripts/repo-workflow.sh check --full
```

A forced fast check does not replace protected pull-request CI. Security-sensitive
and release-facing changes should use the automatically selected full mode.

### Validate, commit, and push

```bash
scripts/repo-workflow.sh publish \
  -m "Docs: improve repository guidance"
```

`publish` performs one controlled sequence:

1. Blocks direct routine publication from `main`, `master`, `beta`, and `release/*`.
2. Fetches `origin` and refuses to publish a branch that is behind its upstream.
3. Regenerates release checksums.
4. Runs automatic risk-based validation.
5. Stages the complete working-tree change.
6. Creates the commit.
7. Pushes the current branch.

Useful review modes:

```bash
scripts/repo-workflow.sh publish \
  --dry-run \
  -m "Docs: preview staged update"

scripts/repo-workflow.sh publish \
  --no-push \
  -m "Docs: create local commit only"
```

`--dry-run` leaves the validated files staged and creates no commit.

## Pull-request workflow

After `publish` pushes the branch, manage the pull request through the same
repository command.

Create a pull request:

```bash
scripts/repo-workflow.sh pr create
```

The command:

- Requires an authenticated GitHub CLI session
- Requires a clean feature or documentation branch
- Confirms the branch is synchronized and present on `origin`
- Reuses an existing open pull request instead of creating a duplicate
- Uses `main` as the default base branch

Optional creation controls:

```bash
scripts/repo-workflow.sh pr create \\
  --base main \\
  --title "Dev: improve repository workflow" \\
  --body "Summary of the change"

scripts/repo-workflow.sh pr create --draft
scripts/repo-workflow.sh pr create --body-file /path/to/pr-body.md
```

Show the current branch pull request:

```bash
scripts/repo-workflow.sh pr status
```

Show checks once or watch them until completion:

```bash
scripts/repo-workflow.sh pr checks
scripts/repo-workflow.sh pr checks --watch --required
```

Merge only after required checks pass:

```bash
scripts/repo-workflow.sh pr merge
```

The default strategy is a merge commit. Other supported controls are:

```bash
scripts/repo-workflow.sh pr merge --squash
scripts/repo-workflow.sh pr merge --rebase
scripts/repo-workflow.sh pr merge --admin
scripts/repo-workflow.sh pr merge --delete-branch
```

`--admin` is explicit because it bypasses repository merge restrictions. Use it
only after reviewing the successful required checks and confirming that the
remaining restriction is an intentional solo-maintainer or emergency override.

## Validation modes

| Mode | Intended use | Local work |
|---|---|---|
| `fast` | Documentation and bounded low-risk changes | Generated checksums, whitespace, versions, docs, manifest, changed-shell syntax/lint, focused tests |
| `full` | Security, release, update, workflow, manifest, or broad automation changes | Fast checks, canonical release validator, release-bundle construction |
| `auto` | Normal use | Selects `fast` or `full` from the changed paths |

Full mode is selected automatically when changes include areas such as:

```text
VERSION
erpnext-dev.sh
RELEASE-MANIFEST.txt
.github/
lib/security.sh
lib/update.sh
scripts/release-*.sh
scripts/validate-release.sh
scripts/build-release-bundle.sh
scripts/repo-workflow.sh
SECURITY.md
release trust and release process documentation
```

The path classifier is conservative. Pull-request CI remains authoritative.

## Generated checksums

`check` and `publish` run:

```bash
scripts/generate-release-checksums.sh
```

before validation. Contributors no longer need to remember a separate checksum
generation step.

A new packaged file must still be added intentionally to
`RELEASE-MANIFEST.txt`. The workflow will then include it in `SHA256SUMS`.

## Full-validation cache

A successful full validation is cached under:

```text
.git/erpnext-workflow/cache/
```

The cache key is calculated from the exact tracked and untracked non-ignored
repository content, including file modes. A content change invalidates the cached
result automatically.

When the tree is unchanged:

```text
OK: full validation already passed for this exact repository tree
```

Force a fresh run:

```bash
scripts/repo-workflow.sh check --full --no-cache
```

Clear all workflow state:

```bash
scripts/repo-workflow.sh clean-cache
```

## Failure recovery

A failed operation records only local workflow state under:

```text
.git/erpnext-workflow/
```

The state contains the action, validation mode, current stage, and commit message.
It is not committed or pushed.

After correcting the reported problem:

```bash
scripts/repo-workflow.sh resume
```

Examples:

- A failed validation reruns the saved check or publish flow.
- A failed pre-commit step reuses the saved commit message.
- A push failure after a successful commit resumes at the push stage without
  creating a duplicate commit.

Inspect the saved state with:

```bash
scripts/repo-workflow.sh status
```

## Branch safety

Routine `publish` is intentionally blocked on:

```text
main
master
beta
release/*
```

Release preparation and tag publication continue to use the dedicated
transactional release scripts and protected GitHub workflows. The repository
workflow wrapper does not create or publish release tags.

## CI responsibility

Local fast validation is a developer feedback loop, not a weaker release policy.

Protected pull-request CI still runs the complete repository gate. Stable release
publication continues to require:

- Exact version and tag alignment
- Authoritative manifest and whole-tree checksums
- Complete release validation
- Disposable integration validation
- Protected signing authority
- Published-asset verification

## Troubleshooting

Show help:

```bash
scripts/repo-workflow.sh --help
```

Run the hermetic workflow regression suite:

```bash
scripts/test-repo-workflow.sh
```

Inspect the current change before publishing:

```bash
git status --short
git diff --check
scripts/repo-workflow.sh status
scripts/repo-workflow.sh explain
```

The low-level scripts remain available for diagnosis, but normal branch work
should use `repo-workflow.sh` instead of assembling long manual command blocks.
