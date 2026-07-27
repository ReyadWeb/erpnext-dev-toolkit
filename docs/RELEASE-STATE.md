# Release-State Contract

**Status:** Accepted design for the v1.20.x reliability programme
**First implementation milestone:** v1.20.1 — Release Coherence and Public Testing Foundation

This document defines the authoritative release-state model for ERPNext Developer
Toolkit. It separates project development identity, release channel, published
stable identity, and immutable bundle identity so that one value cannot silently
stand in for several different concepts.

## Why this contract exists

The v1.20.0 release introduced strong release gates, signed checksum inventories,
transactional release preparation, guarded tagging, complete-tree bundles, and
atomic toolkit rollback. The remaining problem is semantic rather than a lack of
release protection: a source tree newer than the v1.20.0 release can still identify
itself as the already-published stable artifact, and some workflows still bypass
the canonical helper.

The v1.20.x programme completes that architecture without adding deployment
features.

## Authoritative concepts

### Project version

`VERSION` owns the next project version only.

Example after v1.20.0 is published:

```text
1.20.1
```

The project version does not, by itself, claim that the current tree is a beta,
release candidate, or published stable artifact.

### Release channel

The release channel is derived from release context, in this order:

1. immutable packaged build metadata;
2. an exact Git tag pointing at the current commit;
3. explicit, validated release-preparation context;
4. otherwise `development`.

Allowed channels are:

```text
development
beta
rc
stable
```

A plain `X.Y.Z` value in `VERSION` must never be sufficient evidence that an
untagged source tree is stable.

### Published stable release

The latest stable release is the newest successfully published, non-prerelease
GitHub release. It is not inferred from the source-tree version and should not be
hardcoded independently across several documents.

For the first v1.20.1 development cycle:

```text
Project version:         1.20.1
Source channel:          development
Latest published stable: v1.20.0
```

### Immutable bundle identity

Every packaged release must contain generated build metadata with at least:

```json
{
  "schema_version": 1,
  "project_version": "1.20.1",
  "channel": "stable",
  "tag": "v1.20.1",
  "commit": "FULL_COMMIT_SHA",
  "tree_digest": "SHA256_OF_SHA256SUMS",
  "archive": "erpnext-dev-v1.20.1.tar.gz",
  "built_at": "UTC_TIMESTAMP"
}
```

The metadata is generated only in the staged bundle and copied byte-for-byte to a
standalone release sidecar. It is never committed to the source tree.
`tree_digest` is the SHA-256 digest of the exact `SHA256SUMS` bytes, which binds the
metadata to the authoritative payload inventory without creating a checksum cycle.
The metadata must agree with the tag, archive name, project version, exact commit,
checksum inventory, and extracted payload. Development bundles use an empty `tag`
and the explicit artifact label `vX.Y.Z-development`.

## Required invariants

### REL-001-A — Single project-version owner

- `VERSION` is the only independently maintained project-version value.
- `erpnext-dev.sh` reads version identity from the installed toolkit tree or
  immutable build metadata.
- No workflow, test, documentation generator, or bundle step parses an independent
  `SCRIPT_VERSION` literal.

### REL-001-B — Development is not stable

- Untagged source commits report channel `development`.
- A stable channel requires an exact `vX.Y.Z` tag and matching immutable build
  identity.
- A beta channel requires an exact `vX.Y.Z-beta.N` tag.
- An RC channel requires an exact `vX.Y.Z-rc.N` tag.

### REL-001-C — Exact release identity

For any published bundle, these values must agree:

- project version;
- release channel;
- Git tag;
- Git commit;
- archive filename;
- release title;
- release-manifest identity;
- checksum inventory;
- generated build metadata.

### REL-001-D — Source and publication are distinct

- README and roadmap may show the latest published stable release.
- Development status must be stated separately.
- A post-release commit on `main` must not continue claiming to be the exact
  already-published stable artifact.

### REL-001-E — Stable promotion evidence

The preferred v1.20.2 model is exact-commit beta-to-stable promotion:

```text
v1.20.1-beta.1  -> accepted commit
v1.20.1         -> the same accepted commit
```

When exact-commit promotion is temporarily impossible, the release process must
prove an identical runtime-payload digest and allow only explicitly approved
metadata differences.

### REL-001-F — Fail-closed qualification

- Contributor mode may warn about optional local dependencies.
- Required PR mode may not skip required checks.
- Release-strict mode treats a missing dependency or skipped required test as a
  failure.

### REL-001-G — Authenticity before privilege

No downloaded toolkit code may execute with `sudo` before an already-installed
system toolchain has verified:

1. the pinned signing-key fingerprint;
2. the detached signature over the external asset inventory;
3. the archive digest;
4. safe archive paths;
5. the extracted internal whole-tree checksum inventory.

## Migration sequence

### R1A — Contract and measurable baseline

- Adopt this specification.
- Amend the active roadmap.
- Correct stale public status wording.
- Add executable audit checks and negative tests.
- Keep existing runtime/release behaviour unchanged while gaps are measured.

### R1B — Canonical runtime, channel, and bundle identity

- [x] Remove the independent `SCRIPT_VERSION` literal.
- [x] Make workflows call `scripts/release-version.sh`.
- [x] Derive channel from Git, validated release context, or generated metadata.
- [x] Generate and verify immutable bundle metadata and a matching sidecar.
- [x] Advance the source tree to project version 1.20.1 development state.
- [x] Enforce completed REL-001 invariants during release validation.

### R1C — Pre-privilege trust and CI supply chain

- [x] Publish an external signed release-asset inventory.
- [x] Add a non-privileged bootstrap verifier.
- [x] Replace every `curl | sudo tar` or equivalent CI pattern with a verified
  package-manager or checksum-verified installer.
- [x] Make normal install, recovery install, README, SECURITY, and release notes use
  one trust flow.

### R1D — Strict qualification and evidence

- [x] Required checks cannot skip in PR or release qualification.
- [x] Synthetic release fixtures re-execute through a canonical clean environment
  boundary, and beta preparation runs the prerelease-context matrix before full
  validation.
- [ ] High-risk paths require same-commit integration evidence.
- [ ] Native, Docker, upgrade, rollback, and public-reporting acceptance evidence
  is attached to the release candidate.

## v1.20.x programme

```text
v1.20.1  Release coherence, pre-sudo trust, current workflow/docs, public testing
v1.20.2  Promotion governance, attestations, immutable release evidence
v1.20.3  Typed configuration and argument-safe execution boundaries
v1.20.4  Shared transaction journal for toolkit update and restore
v1.20.5  Declarative command registry and standard result model
v1.21.0  Machine-readable API foundation
```

No broad ERPNext deployment feature belongs in v1.20.1 through v1.20.5.

## Acceptance criteria for completing REL-001

- `VERSION` is the only independent project-version source.
- An untagged source tree reports `development`.
- Every workflow uses the canonical release helper.
- A generated bundle contains immutable build identity.
- A tag/archive/build mismatch fails before publication.
- Current stable and current development are not conflated in documentation.
- The release-state invariant checker passes in enforcement mode.
