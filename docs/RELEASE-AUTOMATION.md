# Release Automation

ERPNext Developer Toolkit releases use explicit, reviewable version and
artifact metadata.

## Canonical version source

`VERSION` is the canonical repository version.

The runtime version remains embedded in `erpnext-dev.sh` as
`SCRIPT_VERSION`, but release validation requires both values to match.

Examples:

```bash
scripts/release-version.sh read
scripts/release-version.sh tag
scripts/release-version.sh channel
scripts/release-version.sh assert-script
scripts/release-version.sh assert-tag v1.20.0-beta.1
```

## Version formats

Supported examples:

```text
1.20.0
1.20.0-beta.1
1.20.0-rc.1
```

The associated Git tag is the canonical version prefixed with `v`:

```text
v1.20.0
v1.20.0-beta.1
v1.20.0-rc.1
```

## Canonical release-content source

`RELEASE-MANIFEST.txt` is the authoritative inventory for both:

- files copied into the release bundle;
- files represented in `SHA256SUMS`.

`SHA256SUMS` is included in the bundle but does not contain a checksum of
itself.

The manifest parser rejects:

- duplicate entries;
- absolute paths;
- `.` and `..` traversal components;
- unsafe whitespace or unsupported characters;
- directory entries;
- symbolic links;
- missing files.

Examples:

```bash
scripts/release-manifest-files.sh --include-checksum
scripts/release-manifest-files.sh --exclude-checksum
scripts/check-release-artifact-consistency.sh
scripts/test-release-manifest.sh
scripts/test-release-artifact-consistency.sh
```

## Release requirements

A release must be rejected when:

- `VERSION` is missing;
- `VERSION` contains multiple values;
- the version format is invalid;
- `VERSION` and `SCRIPT_VERSION` differ;
- the requested Git tag does not match `VERSION`;
- documentation banners do not match the canonical version;
- the changelog or release manifest uses another version;
- a manifest path is unsafe;
- a manifest entry is duplicated or missing;
- `SHA256SUMS` and the manifest do not have exact artifact coverage;
- any release checksum is stale or invalid.

Later v1.20 development stages add:

- automated beta preparation;
- automated stable promotion;
- pre-tag repository checks.

## Transactional beta preparation

Prepare beta release metadata with:

```bash
scripts/release-prepare-beta.sh   1.20.0-beta.1   "Release reliability foundation"
```

The command requires a clean matching release or feature branch, a beta
version using `X.Y.Z-beta.N`, and no existing local target tag.

It updates canonical version metadata, documentation banners, the README exact
pin, the release-manifest header, and the changelog. It then regenerates
`SHA256SUMS` and runs full release validation.

All modified metadata is backed up before editing. Any edit, checksum, or
validation failure restores the exact pre-command files.

```bash
scripts/test-release-metadata.sh
scripts/test-release-prepare-beta.sh
```
