# Release automation

ERPNext Developer Toolkit uses layered release automation with explicit human
review at irreversible boundaries.

The normal maintainer interface is:

```bash
scripts/repo-workflow.sh release ...
```

The lower-level scripts remain independently testable and are retained for
diagnosis.

## Canonical release identity

`VERSION` is the canonical repository version. `erpnext-dev.sh` embeds
`SCRIPT_VERSION` for runtime identity. Release validation requires exact
agreement.

```bash
scripts/release-version.sh read
scripts/release-version.sh script
scripts/release-version.sh channel
scripts/release-version.sh tag
scripts/release-version.sh assert-script
scripts/release-version.sh assert-tag vX.Y.Z
```

Supported forms include:

```text
X.Y.Z
X.Y.Z-beta.N
X.Y.Z-rc.N
```

The Git tag is the canonical version prefixed by `v`.

## Authoritative release contents

`RELEASE-MANIFEST.txt` defines:

- every tracked file copied into the release archive;
- every artifact represented in `SHA256SUMS`.

`SHA256SUMS` is packaged but does not checksum itself. Generated
`BUILD-INFO.json` is deliberately outside that inventory to avoid a checksum cycle.
Instead, its `tree_digest` is the SHA-256 digest of the exact `SHA256SUMS` bytes.
The bundle builder writes the same metadata as a standalone `.BUILD-INFO.json`
sidecar and independently verifies the extracted archive. Development bundles use
`vX.Y.Z-development`; beta, RC, and stable bundles use their exact release tag.

The manifest parser rejects duplicate, missing, absolute, traversing,
whitespace-unsafe, directory, and symbolic-link entries.

```bash
scripts/release-manifest-files.sh --include-checksum
scripts/release-manifest-files.sh --exclude-checksum
scripts/check-release-artifact-consistency.sh
```

## Repository workflow command map

| Command | Responsibility |
|---|---|
| `release status` | Read-only release state and next action |
| `release explain` | Explain blockers and branch/tag policy |
| `release doctor` | Authoritative phase, source, branch, proof, tag, publication, and next-action diagnosis |
| `release prepare-beta` | Transactionally prepare beta metadata |
| `release promote-stable` | Transactionally convert matching beta/RC metadata to stable |
| `release publish --confirm-reviewed` | Validate, commit, and push reviewed release metadata |
| `release recover` | Safely resume validation, publication, push, or workflow monitoring; stop before final verification |
| `release pretag` | Strict exact-tree validation and pre-tag proof |
| `release tag --confirm` | Create and push one guarded annotated tag |
| `release watch` | Watch the protected tag-triggered workflow |
| `release verify` | Verify the published tag, workflow, assets, checksums, and signature |
| `release run` | Start or resume the complete release state machine from any lifecycle phase |
| `release beta` | Phase-aware beta orchestration with explicit human gates |
| `release stable` | Phase-aware stable orchestration with explicit review, merge, and tag gates |

Read-only commands may use `--offline` when remote inspection is intentionally
unavailable. Offline status does not replace remote synchronization or tag checks
before publication.

## Transactional metadata preparation

### Beta

```bash
scripts/repo-workflow.sh release prepare-beta \
  X.Y.Z-beta.N \
  "Release title"
```

### Stable

```bash
scripts/repo-workflow.sh release promote-stable \
  X.Y.Z \
  "Release title"
```

The underlying transactions back up release metadata before editing. On any
metadata, checksum, release-test context-isolation, or validation failure, the
original files are restored.

Beta preparation injects the intended prerelease tag and channel into
`scripts/test-release-context-isolation.sh` before the normal full validator.
This reproduces the environment used by strict pre-tag qualification while the
transaction can still roll back safely.

Stable promotion validates the temporary untagged stable tree through the
strict `stable-promotion` lifecycle phase. The source beta or RC tag must exist,
match the target version, and point exactly at `HEAD`. The stable target tag must
not already exist.

Stable pre-tag validation uses the strict `stable-pretag` lifecycle phase while
the proposed stable tag is still absent. It requires clean `main`; branch
synchronisation and remote-tag checks remain enforced by the pre-tag wrapper.

Outside these controlled lifecycle phases, an untagged stable tree remains
invalid.

The wrapper persists the validated lifecycle context under
`.git/erpnext-workflow/release-state`. Publication and recovery automatically
restore the strict phase, source tag, channel, target tag, and strict-mode
environment from that state. The file is never sourced as executable shell
input.

The lifecycle phase and source prerelease tag are removed by the canonical
release-test environment boundary before synthetic fixtures execute.

A successful preparation intentionally leaves changes uncommitted. This creates
a review boundary before publication.

## Reviewed release publication

```bash
scripts/repo-workflow.sh release publish \
  --confirm-reviewed \
  -m "Release commit message"
```

The command is restricted to release-capable branches. It regenerates checksums,
validates the exact tree, stages all release changes, creates the commit, and
pushes the branch.

Routine `publish` remains blocked on protected and release branches so a release
cannot bypass the explicit review confirmation.

An interrupted confirmed publication resumes with:

```bash
scripts/repo-workflow.sh release recover
```

or, for the exact prepared-metadata path:

```bash
scripts/repo-workflow.sh release publish --resume-prepared
```

## Exact-tree validation and proof

```bash
scripts/repo-workflow.sh release pretag vX.Y.Z
```

The pre-tag command delegates to the strict release validator and records:

```text
Canonical tag
Commit
Repository tree fingerprint
Validation time
```

The proof lives under `.git/erpnext-workflow/` and is local state, not a
committed release artifact. Any commit or packaged-tree change invalidates it.

## Guarded tag transaction

```bash
scripts/repo-workflow.sh release tag \
  --confirm vX.Y.Z
```

Safety properties:

- exact canonical confirmation;
- clean synchronized expected branch;
- exact pre-tag proof;
- a missing tag is created once;
- an existing annotated tag is accepted only when it points to the exact
  approved commit;
- mismatched or lightweight tags fail closed;
- annotated tag only;
- no force update;
- remote tag must peel to the exact release commit;
- a failed push with no remote tag removes the newly created local tag so the
  guarded command can be retried.

## High-level orchestration

```bash
scripts/repo-workflow.sh release run beta \
  X.Y.Z-beta.N \
  "Release title"

scripts/repo-workflow.sh release run stable \
  X.Y.Z \
  --from vX.Y.Z-beta.N \
  "Release title"
```

`release run` creates or safely fast-forwards the release branch, prepares and
publishes metadata, creates or reuses the exact PR, waits for required checks,
verifies the resulting merge commit on synchronized `main`, records exact-tree
pre-tag proof, publishes the annotated tag, resumes transiently interrupted
workflow watching, and verifies the release.

The same invocation prompts for release-note review (`REVIEWED`), PR merge
approval (`MERGE`), the exact tag, and final published-asset verification
(`VERIFY`). Protected signing approval remains in GitHub. To resume after any
interruption, run:

```bash
scripts/repo-workflow.sh release run
```

The resume path uses the persisted target, release commit, PR number, merge
commit, proof, workflow run, and verification commit. It never reconstructs a
deleted release branch after merge, force-pushes a branch, or moves a tag.

For non-interactive test fixtures, the individual confirmations are available
as `--confirm-reviewed`, `--confirm-merge`, `--confirm-tag vX.Y.Z`, and
`--confirm-verify`. Routine maintainers should use the interactive gates.

## Protected GitHub workflow

A pushed release tag triggers `.github/workflows/release.yml`.

The protected pipeline is expected to enforce:

```text
Release validation
        ↓
Disposable integration
        ↓
Protected signing authority
        ↓
Release asset publication
        ↓
Post-upload asset assertions
```

Stable publication must fail closed when the required signature cannot be
created.

## Published-release verification

```bash
scripts/repo-workflow.sh release watch vX.Y.Z
scripts/repo-workflow.sh release verify vX.Y.Z
```

`release watch` binds the workflow run to the remote tag commit.

`release verify` independently checks:

- workflow conclusion;
- release metadata;
- required assets;
- stable Latest state;
- archive path safety;
- archive and standalone asset consistency;
- canonical/runtime version identity;
- whole-tree checksums;
- maintainer public-key fingerprint;
- detached signature.

## Generated checksums

Normal checks and publication regenerate checksums automatically:

```bash
scripts/repo-workflow.sh check
scripts/repo-workflow.sh publish -m "Commit message"
scripts/repo-workflow.sh release publish \
  --confirm-reviewed \
  -m "Release commit message"
```

Direct generation remains available for diagnosis:

```bash
scripts/generate-release-checksums.sh
```

A newly packaged file must first be added intentionally to
`RELEASE-MANIFEST.txt`.

## Validation suites

Release automation is covered by:

```bash
scripts/test-release-metadata.sh
scripts/test-release-prepare-beta.sh
scripts/test-release-promote-stable.sh
scripts/test-release-pretag-check.sh
scripts/test-release-manifest.sh
scripts/test-release-artifact-consistency.sh
scripts/test-release-test-env.sh
scripts/test-release-context-isolation.sh

scripts/test-repo-workflow-release.sh
scripts/test-repo-workflow-release-transaction.sh
scripts/test-repo-workflow-release-finalize.sh

scripts/validate-release.sh
```

The complete active test model is documented in [`../TESTING.md`](../TESTING.md).

## Manual intervention boundary

Human review remains required for:

- approving release content;
- confirming metadata publication;
- resolving protected branch requirements;
- approving the protected signing environment;
- confirming the exact tag;
- deciding whether real-machine evidence is sufficient;
- announcing the release.

Automation must not silently invent a version, overwrite a tag, weaken required
CI, or bypass signing policy.

## Related documents

- [`RELEASE-PROCESS.md`](RELEASE-PROCESS.md)
- [`REPOSITORY-WORKFLOW.md`](REPOSITORY-WORKFLOW.md)
- [`security/RELEASE-TRUST.md`](security/RELEASE-TRUST.md)
- [`../TESTING.md`](../TESTING.md)
- [`../VALIDATION.md`](../VALIDATION.md)
