# Release Automation

ERPNext Developer Toolkit releases use explicit and reviewable version
metadata.

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

## Release requirements

A release must be rejected when:

- `VERSION` is missing;
- `VERSION` contains multiple values;
- the version format is invalid;
- `VERSION` and `SCRIPT_VERSION` differ;
- the requested Git tag does not match `VERSION`;
- documentation banners do not match the canonical version;
- the changelog or release manifest uses another version;
- release checksums are stale.

Later v1.20 development stages add:

- automated beta preparation;
- automated stable promotion;
- pre-tag repository checks;
- manifest-driven release checksums.
