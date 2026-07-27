# Release process

This is the maintainer runbook for beta, release-candidate, and stable ERPNext
Developer Toolkit releases.

Operators verifying a downloaded stable release should follow
[`SECURITY.md`](../SECURITY.md) and the signed bootstrap guidance in
[`README.md`](../README.md).

## Release model

A release is a canonical version, an authoritative release tree, and a guarded
annotated Git tag:

```text
VERSION
SCRIPT_VERSION
CHANGELOG.md
RELEASE-MANIFEST.txt
SHA256SUMS
vX.Y.Z[-prerelease]
```

The protected GitHub release workflow then performs validation, disposable
integration, signing when required, asset publication, and post-upload checks.

Stable publication is not complete until:

- the protected workflow succeeds;
- the release archive and required standalone assets are present;
- `SHA256SUMS.asc` exists;
- the stable release is marked Latest;
- independent `release verify` succeeds.

Do not create lightweight or manual tags. Use the guarded repository workflow.

## Normal maintainer interface

```bash
scripts/repo-workflow.sh release status
scripts/repo-workflow.sh release explain
```

The status command reports canonical identity, expected branch and tag, branch
synchronization, validation cache, pre-tag proof, local/remote tags, GitHub
release state, blockers, and the next safe command.

## Prepare a beta

Start from the intended release or proving branch defined by the release plan.

```bash
scripts/repo-workflow.sh release prepare-beta \
  X.Y.Z-beta.N \
  "Release title"
```

The transaction:

1. requires a clean synchronized allowed branch;
2. updates canonical version and release metadata;
3. regenerates checksums;
4. runs the hermetic release-fixture matrix under the intended beta tag/channel;
5. runs full release validation;
6. restores the exact previous metadata if either qualification stage fails;
7. leaves the successful metadata uncommitted for human review.

Review:

```bash
git status --short
git diff --stat
git diff
scripts/repo-workflow.sh release status
```

Publish only after the diff is reviewed:

```bash
scripts/repo-workflow.sh release publish \
  --confirm-reviewed \
  -m "Release: prepare X.Y.Z-beta.N"
```

Create the appropriate PR, then wait for required checks:

```bash
scripts/repo-workflow.sh pr create --base TARGET_BRANCH
scripts/repo-workflow.sh pr checks --watch --required
```

Merge according to the release plan after CI and required beta acceptance pass.

## Beta acceptance

Before stable promotion, record:

- Release Validation CI;
- applicable disposable integration gates;
- affected local native and Docker acceptance;
- affected public native and Docker acceptance;
- frontend asset readiness;
- backup and restore/rehearsal;
- upgrade and rollback;
- reboot persistence;
- known limitations.

The current acceptance model is defined in
[`TESTING.md`](../TESTING.md) and [`VALIDATION.md`](../VALIDATION.md).

## Promote to stable

On the matching stable release branch:

```bash
scripts/repo-workflow.sh release promote-stable \
  X.Y.Z \
  "Release title"
```

Stable promotion requires a matching beta or RC canonical version. It updates
stable metadata transactionally, regenerates checksums, and validates the
release tree. It does not create a tag.

Review and publish:

```bash
git diff
scripts/repo-workflow.sh release publish \
  --confirm-reviewed \
  -m "Release: promote X.Y.Z stable"
```

Create the stable PR to `main`, wait for required checks, and merge:

```bash
scripts/repo-workflow.sh pr create --base main
scripts/repo-workflow.sh pr checks --watch --required
scripts/repo-workflow.sh pr merge \
  --admin \
  --delete-branch
```

The explicit `--admin` option is for a reviewed solo-maintainer or emergency
override after required checks pass.

## Strict pre-tag proof

After the stable PR is merged:

```bash
git switch main
git pull --ff-only origin main
git status -sb

scripts/repo-workflow.sh release pretag vX.Y.Z
```

The strict gate requires:

- clean working tree;
- canonical/runtime/tag alignment;
- allowed target branch;
- synchronized upstream;
- no local or remote target tag;
- safe authoritative manifest;
- exact checksums;
- complete release validation;
- successful bundle construction and clean extraction;
- generated `BUILD-INFO.json` matching project version, proposed tag, channel,
  exact commit, archive name, and payload-inventory digest;
- byte-identical standalone and bundled build metadata;
- packaged version and toolkit integrity.

A successful run records proof under `.git/erpnext-workflow/` for the exact tag,
commit, and tree fingerprint. Any relevant change makes the proof stale.

## Guarded annotated tag

Create the tag only through:

```bash
scripts/repo-workflow.sh release tag \
  --confirm vX.Y.Z
```

The confirmation must exactly match the canonical tag. The command refuses an
existing local or remote tag and never force-updates one.

Tag creation is the irreversible boundary. Do not run it until pre-tag proof and
release approval are complete.

## Watch protected publication

```bash
scripts/repo-workflow.sh release watch vX.Y.Z
```

The command locates the tag-triggered `release.yml` run, verifies its commit
against the remote tag, waits for completion, and fails when the workflow does
not succeed.

Approve the protected `release-signing` environment when required. Stable tags
must fail closed when the signing authority is unavailable.

## Verify the published release

```bash
scripts/repo-workflow.sh release verify vX.Y.Z
```

Verification covers:

- remote annotated tag identity;
- release workflow commit and successful conclusion;
- GitHub release state;
- stable/prerelease classification;
- required release assets;
- Latest status for stable releases;
- safe archive paths;
- standalone/bundled checksum and build-identity equality;
- canonical version, tag, channel, commit, archive, and payload identity;
- whole-tree checksums;
- pinned maintainer signing-key fingerprint;
- detached checksum signature.

Do not announce the stable release until this command succeeds.

## Signing policy

| Tag | Policy |
|---|---|
| Stable `vX.Y.Z` | Detached checksum signature required |
| Prerelease `vX.Y.Z-*` | Policy follows the protected workflow; unsigned status must be explicit |

GPG material belongs in the protected `release-signing` GitHub Environment, not
ordinary repository secrets. Repository write access alone must not be enough to
produce a trusted stable release.

## Recovery and failure handling

Before tagging, release metadata transactions restore their original files when
they fail.

After a failed repository operation:

```bash
scripts/repo-workflow.sh status
scripts/repo-workflow.sh resume
```

Before retrying tag publication, inspect:

```bash
scripts/repo-workflow.sh release status
scripts/repo-workflow.sh release explain
git tag --list 'vX.Y.Z*'
git ls-remote --tags origin 'vX.Y.Z*'
```

Never delete, move, or force-push a published release tag as a routine recovery
method. Correct the issue in a new version unless the project's documented
security incident procedure requires otherwise.

## Low-level diagnostic commands

The wrapper delegates to hardened lower-level scripts. Use these for diagnosis
or development, not as the normal release path:

```text
scripts/release-prepare-beta.sh
scripts/release-promote-stable.sh
scripts/release-pretag-check.sh
scripts/release-version.sh
scripts/generate-release-checksums.sh
scripts/build-release-bundle.sh
scripts/assert-github-release-assets.sh
```

## Related documents

- [`RELEASE-AUTOMATION.md`](RELEASE-AUTOMATION.md)
- [`REPOSITORY-WORKFLOW.md`](REPOSITORY-WORKFLOW.md)
- [`../TESTING.md`](../TESTING.md)
- [`../VALIDATION.md`](../VALIDATION.md)
- [`security/RELEASE-TRUST.md`](security/RELEASE-TRUST.md)
- [`../SECURITY.md`](../SECURITY.md)
