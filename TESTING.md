# Testing guide

**Current release:** v1.20.0

This is the active entry point for testing ERPNext Developer Toolkit changes and
releases. It describes the current validation layers, the evidence required at
each layer, and the boundary between automated checks and real-machine
acceptance.

Version-specific regression notes and historical field evidence are preserved in
[`docs/TESTING-HISTORY.md`](docs/TESTING-HISTORY.md). The production acceptance
procedure is maintained separately in [`VALIDATION.md`](VALIDATION.md).

## Testing principles

1. Use the repository workflow instead of assembling long validation command
   sequences manually.
2. Run the smallest safe local check for fast feedback, but treat protected
   pull-request CI as authoritative.
3. Use hermetic tests for deterministic code behaviour and real machines for
   networking, browser, TLS, reboot, provider, and recovery evidence.
4. Never call a release production-ready from port checks alone. HTTP, login
   frontend assets, runtime health, backup recovery, and exposure controls must
   all pass.
5. A successful backup command is not recovery proof. Verification and restore
   rehearsal are separate gates.
6. Stable-release publication is incomplete until the signed assets are
   downloaded and independently verified.
7. Preserve evidence for failures as well as passes. A rerun without the original
   diagnostic output weakens the audit trail.

## Quick contributor path

From a feature or documentation branch:

```bash
scripts/repo-workflow.sh status
scripts/repo-workflow.sh explain
scripts/repo-workflow.sh check
```

The default `check` mode is automatic:

- `fast` for bounded documentation and low-risk changes;
- `full` for release, security, update, manifest, workflow, and broad automation
  changes.

Force the complete local gate when reviewing release-sensitive work:

```bash
scripts/repo-workflow.sh check --full --no-cache
```

After the change is ready:

```bash
scripts/repo-workflow.sh publish \
  -m "Clear commit message"

scripts/repo-workflow.sh pr create
scripts/repo-workflow.sh pr checks --watch --required
```

Merge only after the required checks pass:

```bash
scripts/repo-workflow.sh pr merge \
  --admin \
  --delete-branch
```

`--admin` is an explicit solo-maintainer or emergency override. It does not
replace review of the successful required checks.

## Validation layers

| Layer | Purpose | Typical execution | Authority |
|---|---|---|---|
| 1. Static checks | Syntax, formatting, lint, unsafe patterns, version/docs alignment | Local and CI | Required |
| 2. Focused hermetic tests | Regressions related to changed paths | Local and CI | Required |
| 3. Full repository validation | Complete manifest, checksum, module, release, and bundle gate | Local and CI | Required for high-risk work |
| 4. Pull-request security and release CI | Protected repository checks | GitHub Actions | Authoritative merge gate |
| 5. Disposable integration | Real installation and lifecycle smoke in clean CI hosts | GitHub Actions | Authoritative release gate where configured |
| 6. Real VM/VPS acceptance | DNS, TLS, browser, provider firewall, reboot, backup destinations | Operator-run | Required before production claims |
| 7. Published-release verification | Tag, workflow, assets, checksums, signature, archive identity | Protected workflow plus independent verification | Required for stable release completion |

A lower layer cannot substitute for a higher one. For example, a hermetic HTTPS
test cannot prove that ACME, public DNS, and a cloud firewall work on a real VPS.

## Layer 1 — static checks

The repository workflow runs the applicable static checks automatically.
Diagnostic commands remain available:

```bash
bash -n erpnext-dev.sh
find lib scripts -type f -name '*.sh' -print0 |
  xargs -0 -n1 bash -n

scripts/check-shfmt.sh
scripts/run-shellcheck.sh
scripts/check-pinned-actions.sh
scripts/check-risky-shell-patterns.sh
scripts/check-module-consistency.sh
scripts/check-release-doc-alignment.sh
scripts/check-release-artifact-consistency.sh
git diff --check
```

Expected outcomes:

- all shell files parse;
- formatting and ShellCheck pass;
- GitHub Actions remain pinned;
- no prohibited risky shell pattern is introduced;
- module inventories agree;
- `VERSION`, `SCRIPT_VERSION`, release banners, manifest header, and current
  release pin agree;
- release manifest and checksum coverage are exact;
- no whitespace error remains in the diff.

## Layer 2 — focused hermetic regression tests

`repo-workflow.sh check` classifies changed paths and selects focused tests.
Representative suites include:

```bash
scripts/test-repo-workflow.sh
scripts/test-repo-workflow-pr.sh
scripts/test-repo-workflow-release.sh
scripts/test-repo-workflow-release-transaction.sh
scripts/test-repo-workflow-release-finalize.sh

scripts/test-static-asset-probe.sh
scripts/test-docker-access-routing.sh
scripts/test-reinstall-isolation.sh
scripts/test-healing.sh
scripts/test-local-ip.sh
scripts/test-update-channel.sh
scripts/test-release-manifest.sh
scripts/test-release-artifact-consistency.sh
```

This list is illustrative, not the authoritative inventory. The complete release
validator determines the suites required for the current tree.

Hermetic tests must:

- use temporary directories and fixtures;
- avoid modifying the operator's real installation;
- avoid requiring production credentials;
- clean temporary resources on success and failure;
- fail closed when a required fixture or dependency is absent;
- test rejection paths, rollback behaviour, and duplicate-operation safety where
  applicable.

## Layer 3 — complete repository validation

Run:

```bash
scripts/repo-workflow.sh check --full --no-cache
```

The full gate includes the fast checks, canonical release validation, and release
bundle construction. It verifies, among other things:

- canonical version alignment;
- release-manifest safety and exact file coverage;
- regenerated whole-tree checksums;
- shell syntax, formatting, and ShellCheck;
- module-list and dispatcher consistency;
- release metadata transactions and rollback;
- repository workflow transactions;
- release bundle construction and clean extraction;
- packaged runtime identity and toolkit integrity.

A local bundle may report that `SHA256SUMS.asc` is absent. That is expected for a
normal local build because protected stable signing occurs in GitHub's
`release-signing` environment. The unsigned local bundle is a validation
artifact, not a published stable release.

## Layer 4 — pull-request CI

Every change must be proposed through a pull request unless an explicitly
documented emergency procedure applies.

The protected check set currently covers release validation and security
analysis, including formatting, secret scanning, pinned-action policy, CodeQL,
and adversarial input checks. Exact job names may evolve; repository branch
protection is the source of truth.

Use:

```bash
scripts/repo-workflow.sh pr status
scripts/repo-workflow.sh pr checks --watch --required
```

A PR is mergeable only when:

- required checks are successful;
- the branch contains the intended diff only;
- generated checksums are committed;
- documentation and release metadata agree;
- any required human review or explicit solo-maintainer override is resolved.

## Layer 5 — disposable integration

Disposable integration validates behaviour that static and hermetic tests cannot
prove. Depending on the change and release channel, it should exercise:

- fresh native installation;
- fresh Docker development installation;
- Docker production Compose installation;
- frontend CSS and JavaScript readiness;
- production runtime conversion;
- backup creation and verification;
- restore or restore rehearsal;
- clean same-path reinstall isolation;
- reboot or service restart persistence where supported by the CI environment.

Integration failures must retain enough diagnostics to identify:

- service state and logs;
- environment and engine selection;
- frontend manifest and failed asset paths;
- container or process state;
- backup/restore artifacts;
- the exact commit and release identity.

## Layer 6 — real local-VM and public-VPS acceptance

Use [`VALIDATION.md`](VALIDATION.md) for the authoritative matrix.

Real-machine acceptance is required when a change affects:

- networking, DNS, routes, host mapping, or static IP;
- browser access, HTTPS, certificates, redirects, or frontend assets;
- UFW, cloud firewalls, Docker port publication, or exposure controls;
- production runtime, reboot persistence, or autostart;
- backup destinations, off-VM transfer, object storage, or restore;
- provider-specific behaviour;
- upgrades, rollback, or signed toolkit updates;
- native/Docker parity claims.

At minimum, select the affected paths from:

```text
Local native VM
Local Docker VM
Public native VPS
Public Docker VPS
```

Record the OS image, resources, engine, domain method, toolkit commit/tag,
commands, results, and evidence location.

## Layer 7 — beta and stable release acceptance

### Beta preparation

On the intended release branch:

```bash
scripts/repo-workflow.sh release status

scripts/repo-workflow.sh release prepare-beta \
  X.Y.Z-beta.N \
  "Release title"
```

Review the metadata diff, then use the explicit review gate:

```bash
scripts/repo-workflow.sh release publish \
  --confirm-reviewed \
  -m "Release: prepare X.Y.Z-beta.N"
```

Create the appropriate PR, wait for required CI, and complete any real-machine
beta acceptance identified by the change risk.

A beta is acceptable only when:

- release metadata and bundle identity are correct;
- blocking CI succeeds;
- affected real-machine paths pass;
- rollback or recovery behaviour is demonstrated;
- known limitations are documented.

### Stable promotion

Promote only a validated beta or RC:

```bash
scripts/repo-workflow.sh release promote-stable \
  X.Y.Z \
  "Release title"
```

Review and publish the stable metadata, merge its PR, update the required target
branch, and run the strict pre-tag gate:

```bash
scripts/repo-workflow.sh release pretag vX.Y.Z
```

The pre-tag proof is bound to the exact tag, commit, and repository tree. Any
change invalidates it.

Create the guarded annotated tag only after pre-tag proof succeeds:

```bash
scripts/repo-workflow.sh release tag \
  --confirm vX.Y.Z
```

Then watch and independently verify publication:

```bash
scripts/repo-workflow.sh release watch vX.Y.Z
scripts/repo-workflow.sh release verify vX.Y.Z
```

A stable release is complete only after the protected workflow succeeds and
`release verify` confirms the published assets, checksums, signing-key
fingerprint, and detached signature.

## Backup and restore testing

For every backup-affecting change, test all applicable stages separately:

1. backup creation;
2. backup artifact verification;
3. restore to the intended target;
4. application/runtime readiness after restore;
5. frontend asset readiness after restore;
6. off-VM or object-storage transfer;
7. evidence that the remote copy is complete;
8. cleanup and retention behaviour;
9. recovery from an interrupted or failed operation.

Production acceptance requires a restore or restore rehearsal. A compressed file
that merely exists is not sufficient evidence.

## Upgrade and rollback testing

For toolkit or ERPNext upgrade changes:

1. record the current toolkit and application versions;
2. create and verify a recovery point;
3. run read-only update preflight;
4. perform the guarded update;
5. verify toolkit integrity, runtime, HTTP, frontend assets, HTTPS, and scheduled
   services;
6. test the dedicated rollback path;
7. verify the previous version and complete runtime inventory;
8. restore the new version when the release is being accepted;
9. preserve logs and slot identities.

For Docker production changes, also verify immutable image identity and
application-code parity across backend, frontend, websocket, workers, and
scheduler.

## Evidence requirements

A useful acceptance record includes:

| Field | Required evidence |
|---|---|
| Identity | Commit, branch, canonical version, release tag when applicable |
| Environment | Provider/hypervisor, OS image, CPU/RAM/disk |
| Deployment | Native or Docker; local or public |
| Network | IP model, domain/hosts mapping, public DNS, exposed ports |
| Runtime | Service/container state and boot persistence |
| Browser | Styled login and zero required CSS/JS failures |
| Security | HTTPS status, firewall/exposure result, secret-safe diagnostics |
| Recovery | Backup verification and restore/rehearsal outcome |
| Update | Upgrade and rollback result when affected |
| Automation | Local gate, PR checks, integration run, release workflow |
| Artifacts | Redacted support bundle, logs, screenshots, validation record |

Never include passwords, private keys, tokens, database secrets, or unredacted
configuration in an issue or public evidence bundle.

## Failure handling

When a workflow command fails:

```bash
scripts/repo-workflow.sh status
scripts/repo-workflow.sh resume
```

Use `resume` only after correcting the reported cause. Clear local workflow state
when the saved operation is no longer relevant:

```bash
scripts/repo-workflow.sh clean-cache
```

Do not repeatedly rerun an irreversible operation such as tag creation. Inspect
the local and remote state first with:

```bash
scripts/repo-workflow.sh release status
scripts/repo-workflow.sh release explain
```

For a field failure:

1. stop the acceptance sequence;
2. preserve logs and evidence;
3. restore the provider snapshot or documented rollback point when required;
4. open a focused issue with redacted diagnostics;
5. add a hermetic regression test when the failure can be reproduced without real
   infrastructure;
6. rerun the complete affected acceptance path after the fix.

## Test ownership and documentation

When behaviour changes:

- update the closest regression suite;
- update this guide when the validation model changes;
- update [`VALIDATION.md`](VALIDATION.md) when operator acceptance changes;
- update release-process documentation when release controls change;
- record shipped behaviour and evidence in [`CHANGELOG.md`](CHANGELOG.md);
- preserve version-specific historical evidence in
  [`docs/TESTING-HISTORY.md`](docs/TESTING-HISTORY.md), not at the top of the
  active guide.

Before publication, run:

```bash
scripts/repo-workflow.sh check --full --no-cache
```

## Signed release archive verification

Published stable releases must be installed and tested from the complete signed
release archive, not from an automatic source archive or a standalone raw script.

Canonical release artifact:

```text
erpnext-dev-${VERSION}.tar.gz
```

Stable-release verification requires:

```text
SHA256SUMS
SHA256SUMS.asc
docs/erpnext-dev-signing-key.asc
```

The bundled maintainer signing key must match this pinned fingerprint:

```text
BFC10C79427CF73496EA6F5A30BFD17DD559C8B6
```

Verification must confirm the detached signature before trusting the checksum
inventory:

```bash
gpg --batch --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

The extracted toolkit must then pass canonical version and whole-tree integrity
checks before installation or acceptance.
