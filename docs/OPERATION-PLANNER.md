# Operation planner and Quick installation

Phase 3 adds one mutation lifecycle driven by the Phase 2 inventory and
validated application catalog:

```text
Discover → Validate → Preview → Back up → Mutate → Verify → Record
```

Quick installation supports curated applications on a selected,
Toolkit-managed native Bench or Docker site. Native Bench uses validated code
acquisition and site installation. Docker production uses the Phase 4 verified,
cumulative replacement-image lifecycle; Docker development changes are clearly
reported as temporary container state.

## Commands

Interactive:

```bash
erpnext-dev app install hrms --site erp.test
```

Automation requires both the exact site and explicit confirmation:

```bash
erpnext-dev app install hrms --site erp.test --yes
```

Preview performs no backup, installation, operation-record write, or other
mutation:

```bash
erpnext-dev app install hrms --site erp.test --preview
erpnext-dev app install hrms --site erp.test --preview --json
```

The preview distinguishes shared Bench code from site installation, lists
ordered dependencies, identifies other sites sharing the Bench, and shows the
backup, availability impact, verification, and recovery checkpoint.

## Safety and recovery

The planner rejects unmanaged sources, catalog inconsistencies, unsupported
platforms, ambiguous stacks/sites, malformed identifiers, and inventory changes
between preview and mutation. Multiple sites require an explicit target. The
existing Toolkit lock prevents concurrent lifecycle mutations.

A database-and-files backup must be created, matched to the selected site, and
verified before code acquisition or site mutation. A failed backup stops the
operation. This is not described as automatic rollback: failures retain the
backup reference, last completed checkpoint, and explicit restore/inspection
guidance.

Records are stored as root-controlled, mode-0600 state files under
`/var/lib/erpnext-dev/operations`. They contain normalized identifiers,
checkpoints, timestamps, backup references, and recovery guidance—never
passwords, database credentials, tokens, private keys, or user-supplied shell
commands.

After mutation, the planner verifies installed applications and dependencies,
Bench doctor, runtime/HTTP readiness, assets, and refreshed Phase 2 inventory.
Failed verification produces `recovery-required`, never a false success.

## Adding ERPNext to Frappe-only

On a managed native or Docker Frappe-only site:

```bash
erpnext-dev app install erpnext --site erp.test
```

The planner resolves the pinned ERPNext catalog source, previews shared-stack
code and site-specific effects, verifies backups, installs and checks ERPNext,
then changes the managed profile to `recommended`. Docker production first
builds and verifies a cumulative immutable image and records the previous image
checkpoint. The profile changes only after verification. Re-running a healthy
completed installation reports it as already complete without repeating
mutation.

Application updates, uninstallation, existing-stack adoption, separate-Bench
placement, arbitrary custom applications, and automatic restoration remain out
of scope.
