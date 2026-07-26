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

`SHA256SUMS` is packaged but does not checksum itself.

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
| `release prepare-beta` | Transactionally prepare beta metadata |
| `release promote-stable` | Transactionally convert matching beta/RC metadata to stable |
| `release publish --confirm-reviewed` | Validate, commit, and push reviewed release metadata |
| `release pretag` | Strict exact-tree validation and pre-tag proof |
| `release tag --confirm` | Create and push one guarded annotated tag |
| `release watch` | Watch the protected tag-triggered workflow |
| `release verify` | Verify the published tag, workflow, assets, checksums, and signature |

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
metadata, checksum, or validation failure, the original files are restored.

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
- no local or remote target tag;
- annotated tag only;
- no force update;
- remote tag must peel to the exact release commit;
- a failed push with no remote tag removes the newly created local tag so the
  guarded command can be retried.

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
