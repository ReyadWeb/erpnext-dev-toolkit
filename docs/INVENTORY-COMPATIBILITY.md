# Inventory and compatibility architecture

Phase 2 adds strictly read-only discovery and policy evaluation. It does not
install, fetch, update, uninstall, migrate, restart, adopt, or rebuild anything.

## Normalized model

The inventory keeps four facts separate:

- `STACK` identifies the native Bench or Docker development/production stack,
  its installation profile, management classification, and discovery state.
- `APP` means application code is available at shared Bench/image scope. It
  includes safely observable version, branch, commit, source, trust, management,
  and clean/dirty/ambiguous repository state.
- `SITE` means a site belongs to the stack. Its discovery state is explicit.
- `SITE_APP` means an application is installed on one specific site.

Code availability never implies site installation. In a multi-site Bench or
image, changing shared code can affect every site that uses it; `app list`
therefore reports the number of sites using each available application.

## Trust and compatibility

The existing curated catalog in `lib/apps.sh` remains the only application
catalog. Catalog records declare canonical identity, source, supported platform
majors, dependencies/conflicts, native and Docker support, production strategy,
uninstall classification, trust, risk, and verification requirements. Records
are validated before compatibility policy uses them.

`official` and `community` describe validated catalog provenance. Code absent
from the catalog is `unknown` and `unmanaged`; the toolkit does not execute or
fetch it. A source mismatch, missing platform version, incomplete site
discovery, or other ambiguity produces `UNKNOWN`, never a compatibility claim.

`COMPATIBLE` proves only that the locally observable catalog, platform-major,
dependency, profile, deployment-method, and source checks passed. It does not
prove application behavior, data migration safety, or upstream correctness.

## Commands

```bash
erpnext-dev app list
erpnext-dev app status
erpnext-dev app compatibility APP
erpnext-dev site list
```

Add `--json` for the stable schema-versioned machine-readable representation.
The commands are discovery-only and do not silently adopt an existing stack.

Native site-level installation discovery reads the site database directly when
safe local credentials and the MariaDB client are available; it never invokes
Bench or imports Frappe applications. Docker discovery executes filesystem
inspection in the existing backend container and a fixed read-only `SELECT`
through the existing database container. If safe site-level proof is
unavailable, the site is reported as `ambiguous`.
