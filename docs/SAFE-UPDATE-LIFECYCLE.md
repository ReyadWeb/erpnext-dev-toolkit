# Safe update management and recovery

Phase 5 separates managed deployment updates from the Toolkit's own
`update-toolkit` command. Availability and preview commands are read-only and
resolve only catalog-trusted sources to exact target commits within the current
supported release line.

Three modes are available:

```bash
erpnext-dev app updates [APP]
erpnext-dev app update APP --site SITE --preview
erpnext-dev app update APP --site SITE --yes
erpnext-dev stack update --mode safe --preview
erpnext-dev stack update --mode safe --yes
erpnext-dev stack update --mode full --yes
```

An individual update changes only an already-managed app and necessary compatible
dependencies. Recommended / safe update covers policy-essential components.
Full managed-stack update resolves every managed application as one set. Full
never means an uncontrolled newest-version upgrade: major versions, unsupported
release lines, preview/nightly/development branches, unknown sources, additions,
removals, and profile transitions are rejected.

Native application code is shared by every site in a Bench. The plan lists and
backs up every affected site, records exact pre-update revisions, enters
maintenance, fast-forwards only to approved targets, migrates sites in stable
order, rebuilds assets, restores services, and verifies the complete inventory.
Dirty, detached, diverged, ambiguous, or incorrectly sourced repositories stop
before mutation; local work is never reset or stashed by Phase 5.

Docker production updates use the existing cumulative immutable-image manifest.
A candidate is built and verified before backups or deployment, its digest is
recorded, and the previous manifest, image digest, configuration, and backups
remain recovery checkpoints. The last-known-good manifest is promoted only after
stack verification. Development-container mutation is explicitly temporary and
is never described as production durability.

Operation records reuse the lifecycle journal and lock. They contain targets,
affected sites, checkpoints, backup references, previous revisions or image
identity, and recovery guidance, but no credentials or raw user commands. A
failed migration or verification is recovery-required; reversing code alone is
not claimed to reverse database or file changes.

Application removal, ERPNext removal, major-version upgrades, arbitrary custom
repositories, operating-system upgrades, automatic restoration, release
promotion, and Toolkit self-update changes are outside Phase 5.
