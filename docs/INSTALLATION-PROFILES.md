# Installation profiles architecture

This document describes the Phase 7 profile contract. The complete Native
advanced-installation slice is available in v1.21 development; Existing
adoption and Docker advanced mutation remain deferred.

## Baseline and architectural decision

The v1.20.4 baseline already has an end-to-end `recommended` / `frappe-only`
slice:

- `lib/profile.sh` normalizes those two values and derives required apps;
- `lib/install.sh` installs Frappe and conditionally acquires and installs
  ERPNext;
- `lib/docker.sh` omits ERPNext from Frappe-only development site creation and
  builds a cumulative immutable production image;
- `lib/inventory.sh` distinguishes stack, shared app code, site, and site app;
- `lib/planner.sh` can add ERPNext later and promote a Frappe-only intent to
  recommended after verification;
- `lib/removal.sh` owns destructive ERPNext-to-Frappe-only conversion and its
  recovery record.

Consequently the first Phase 7 implementation PR should be the **shared profile
contract and validation**, not another recommended/Frappe-only vertical slice.
The shared contract must first separate setup intent from observed state so that
advanced selection and existing-installation management do not overload the
two-value content helper or trust stale configuration.

## Canonical command contract

`--profile` is already the public installation-content option, so Phase 7 should
extend it instead of adding a negative boolean such as `--no-erpnext`:

```text
--profile recommended
--profile frappe-only
--profile advanced --apps APP[,APP...]
--profile existing
```

The setup command family supports read-only previews:

```bash
erpnext-dev install --profile recommended --preview
erpnext-dev install --profile frappe-only --preview --json
erpnext-dev install --profile advanced --apps crm,helpdesk --preview
erpnext-dev install --profile existing --preview
```

`setup` is an alias-equivalent placement for these previews. `existing` remains
preview-only. An advanced Native fresh install uses the same documented options:

```bash
sudo erpnext-dev install --profile advanced --apps crm,helpdesk --site dev.example.test
sudo erpnext-dev install --profile advanced --apps crm,helpdesk --site dev.example.test --yes
```

The explicit form requires `--apps` and an exact validated `--site`; interactive
use confirms the complete final plan, while `--yes` is the existing canonical
noninteractive confirmation. A site-less advanced preview such as `install
--profile advanced --apps crm,helpdesk --preview` reads validated configuration
and inventory, prints the shared schema-1 plan, and prominently reports that no
deployment mutation occurred. An executable fresh-install preview adds an exact
site:

```bash
erpnext-dev install --profile advanced --apps crm,helpdesk --site erp.test --preview
```

That form uses the Native advanced transaction planner, prints `Native Advanced
Installation Plan`, and exits with the planner preview status 11. Both preview
forms are read-only: neither acquires the mutation lock nor creates an operation
record, configuration, user, Bench, or other platform state. Docker advanced
mutation and executable preview remain unsupported; Docker production retains
only its deferred durable-image planning semantics.

The names are lowercase ASCII identifiers. Input normalization may retain the
documented legacy aliases for `recommended` and `frappe-only`, but new automation
should use only the canonical values. Profile and app identifiers are untrusted:
reject control characters, whitespace tricks, path separators, option-like
values, shell syntax, duplicates after normalization, unknown catalog IDs,
dependency cycles, conflicts, and unsupported engine/environment combinations
before writing configuration, fetching code, building an image, or invoking
Bench.

The option is setup-scoped. Supplying `advanced` without `--apps` is valid only
on an interactive terminal, where the operator selects from the validated
catalog. It fails closed in non-interactive use. `--apps` is valid only with
`advanced`; Frappe is implicit and must not be supplied. The resolved plan may
include ERPNext when explicitly selected or required by another selected app.

`existing` means discover and explicitly adopt a compatible deployment for
management. It is not a request to install an application set. It must never
silently select a bench, site, container project, or credentials source. With
multiple candidates, automation must provide an exact supported target selector
and interactive use must present the candidates without mutation.

No explicit new option changes existing CLI behaviour:

- interactive Quick remains recommended Native by default;
- existing `install`, `setup`, local quickstart, and public guided commands keep
  their current recommended Frappe + ERPNext result;
- non-interactive `--yes` with no explicit profile remains recommended;
- legacy `INSTALLATION_PROFILE=recommended|frappe-only` continues to work;
- app, site, status, backup, restore, update, and service commands retain their
  command names and output schemas unless a separately versioned schema is
  introduced.

## State model: intent, desired plan, and observed reality

A single profile string cannot safely represent all three. Phase 7 should use
three distinct layers:

1. **Intent** — the operator-selected canonical profile.
2. **Desired plan** — validated catalog applications, resolved dependencies,
   engine strategy, exact target stack/sites, and compatibility decisions.
3. **Observed state** — inventory records collected from the bench/image and
   each site.

The persisted non-secret configuration should use a schema version and fields
equivalent to:

```text
CONFIG_SCHEMA=2
INSTALLATION_PROFILE=recommended|frappe-only|advanced|existing
INSTALLATION_PROFILE_APPS=app1,app2
DEPLOYMENT_ENGINE=native|docker
DOCKER_MODE=development|production
```

`INSTALLATION_PROFILE_APPS` contains only canonical, sorted catalog IDs selected
for `advanced`; dependencies are recalculated from the current trusted catalog.
It is empty for the other profiles. Do not store repository credentials, database
passwords, administrator passwords, tokens, private URLs, free-form operator
input, or shell fragments in profile metadata, manifests, plans, or logs.

Persisted intent is a hint for read-only presentation and a constraint for a new
mutation, never proof of the installed state. Every status or mutation workflow
reconciles it with inventory:

| Reconciliation result | Meaning | Mutation policy |
|---|---|---|
| `consistent` | Observed required apps satisfy intent | Allowed after normal gates |
| `drift-extra` | Additional observed apps exist | Report; preserve them; do not remove implicitly |
| `drift-missing` | An intended required app is absent | Degraded; repair requires an explicit plan |
| `ambiguous` | Site/app/source/engine cannot be proven | Read-only only; mutation blocked |
| `unmanaged` | Compatible candidate not explicitly adopted | Discovery only |
| `incompatible` | Major, source, topology, or engine is unsupported | Refuse adoption/mutation |

Legacy configurations without `CONFIG_SCHEMA` or `INSTALLATION_PROFILE` keep the
historical recommended interpretation, but observed inventory must still report
contradictions. Read-only commands do not rewrite legacy files. Migration occurs
only during an already-authorized configuration mutation and uses atomic
replacement.

For Docker production, the root-controlled cumulative application manifest plus
verified image digest is the desired deployable artifact. The config profile is
not allowed to override a contradictory live manifest. For Native and Docker
development, the desired plan is journalled before mutation and verified against
post-operation inventory.

## Profile semantics

### Recommended (recommended)

- Required baseline: Frappe Framework and ERPNext.
- Marked **Recommended** in the wizard and remains the default.
- Optional apps may be added later without changing the profile.
- Missing ERPNext is profile drift, not evidence that the whole Frappe site is
  absent.

### Frappe-only (frappe-only)

- Required baseline: Frappe Framework and a functional site.
- ERPNext is absent by intent, but unrelated supported apps may be added later.
- Installing ERPNext through App Management uses the same dependency,
  compatibility, backup, immutable-image, verification, and recovery planner as
  any other core app. After successful verification, intent becomes
  `recommended`; failure retains `frappe-only` intent and records recovery.
- Removing ERPNext is never an installer toggle. It remains the protected stack
  conversion lifecycle with data-removal and profile-transition acknowledgements.

### Advanced (advanced)

- The operator selects supported catalog applications; Frappe is implicit.
- The planner computes the transitive dependency closure, rejects conflicts and
  unsupported combinations, and shows code/image scope, every affected site,
  exact branches/refs where known, backups, mutation order, verification, and
  rollback boundary before confirmation.
- The canonical selected set is persisted; resolved dependencies and observed
  state are recalculated rather than trusted from stale metadata.
- Arbitrary Git URLs and custom apps are excluded from the first Phase 7
  implementation. They remain in the existing advanced custom-app tooling and
  cannot be treated as verified profile members.

Native advanced mutation is fresh-install only. It refuses an existing bench,
site, deployment configuration, unsafe operation state, or changed preflight
fingerprint before platform mutation. Docker advanced mutation is unsupported
until Phase 7.5 and invokes no Docker command.

The displayed final plan names the profile, engine, exact site, requested and
resolved applications, deterministic dependency order, trusted catalog source
identity/ref, checkpoints, created artifacts/services, baseline backup boundary,
promotion point, verification, and failure recovery. Preview and cancellation
do not write state or configuration and execute no platform command.

The protected operation record lives under the Toolkit operation-state area.
Its directory is mode 0700 and regular state files are mode 0600; unsafe types,
links, ownership, or permissions fail closed. It records identifiers and verified
artifacts only—never credentials or private repository URLs. After site creation,
failure records `recovery-required`, preserves the site and backup evidence, and
directs the operator to inspect the record and repair the recorded checkpoint;
there is no broad automatic cleanup or unsafe resume.

Every Native advanced toolchain, Bench, site, backup, application, migration,
asset, inventory, and managed-start command runs from a controlled Frappe-owned
directory with `HOME` fixed to the configured Frappe home. The command runtime
resets inherited XDG, npm, Yarn, Python, uv, and Git configuration, uses private
Frappe-owned cache/config paths, sources the verified `nvm.sh`, and selects the
pinned Node version. `USER` and `LOGNAME` are reset to the configured Frappe
identity; inherited Node options and every npm/Yarn/Python/uv/Git configuration
variable are removed before the controlled values are established. Toolchain
completion is verified in a new noninteractive Frappe shell before Bench
creation starts. UV uses its supported `UV_NO_CONFIG=1` mode; the installer does
not point `UV_CONFIG_FILE` at a file that may not exist. NVM v0.40.3 is fetched
as an exact tag ref and its reviewed commit is verified before `nvm.sh` is
sourced. The reviewed production coordinates are Node 24, Yarn 1.22.22, uv
0.11.28, Python 3.14.6, pip 25.3 or newer within that series, and
frappe-bench 5.31.0.

The Phase 7.4 reviewed application set is immutable for an attempt: Frappe,
CRM, Telephony, and Helpdesk each have an official repository, approved history
branch, and exact 40-character commit in the trusted catalog. The installer
fetches the approved branch into an isolated Git repository, proves the reviewed
commit is an ancestor of that branch, and checks out the reviewed commit before
Bench can install dependencies or execute application-controlled code. A normal
branch advance therefore does not invalidate the pin. Rewritten history,
unrelated or unavailable commits, and conflicting repositories fail closed.
Only the snapshotted repository/ref/commit coordinates are used throughout the
attempt, and final verification requires the exact official origin and commit.
Telephony is acquired and installed before Helpdesk.

`bench init` must return zero and produce a safe Bench directory, Frappe app,
Python environment, `sites/apps.txt`, common site configuration, Procfile, and
working Bench commands. A failed or incomplete initialization remains at the
`bench-created` checkpoint, records `partial-bench`, exits with mutation failure
(31), and does not proceed to site, backup, app acquisition, or configuration
promotion. The partial Bench is preserved; another attempt requires reverting
the disposable VM to its clean snapshot or a separately authorized recovery.

Immediately after verified site creation, the installer atomically persists the
Administrator and non-root MariaDB administration credentials to the canonical
`${FRAPPE_HOME}/erpnext-dev-credentials.txt` contract. The final file must be a
root-owned, non-symlink regular file with mode `0600`; only its path and the
`credentials-show` retrieval command are printed. A write failure is
`recovery-required`, preserves the site and any verified credential artifact,
and blocks backup and all later work. The installer then creates and safely
checks a baseline backup. Failure blocks all curated-app acquisition. Advanced schema-2
intent is staged privately, but active primary and compatibility configuration
remain unchanged until readiness and exact inventory/source/ref verification
pass. Promotion uses protected temp-file replacement for each configuration
output, records the attempt before changing either output, and refuses concurrent
configuration changes. A second configuration, exact-inventory, source/ref, and
readiness reconciliation is required before `completed`.

#### Native advanced checkpoint matrix

All Frappe-side rows below use `native_advanced_frappe_bash`: configured
`HOME`, `USER`, and `LOGNAME`; a Frappe-owned working directory; a fixed system
plus `$HOME/.local/bin` `PATH`; private XDG/npm/Yarn/Python/uv paths; disabled
system/global Git configuration; verified `$HOME/.nvm/nvm.sh`; and the pinned
Node selection. Each isolated script uses `set -Eeuo pipefail`, while the
transaction functions also propagate command status explicitly so a partial
postcondition cannot replace a failed command result.

| Boundary | Exact execution and required success proof | Ledger on mutation | Failure record and retry |
| --- | --- | --- | --- |
| Plan/preflight | Pure catalog resolution; Native engine; validated site; supported Frappe major and exact official commits; exact absence fingerprints for config, Bench, and protected records | None | No attempt record; planner input/unsupported/conflict exit. No later command. Retry only after resolving the reported preflight condition. |
| Time/APT/resources | Host read-only OS, network, system/RTC/provider consistency, APT metadata, approved repository/ref/pin ancestry, and resource probes | None | Exit 31, `failed/prerequisites/failed`, backup `none`. Exact retry is allowed only by the protected artifact-free prerequisite rule below. |
| Toolkit/packages/runtime/sysctl | Host commands, only after every read-only readiness gate returns zero; MariaDB 11.8, Redis 6+, responsive enabled services, compiler/headers/pkg-config/fonts/cron are verified | `toolkit-reuse`, `system-packages`, `pdf-capability:STATUS`, `redis-sysctl` before or after the represented check | Exit 31 at `prerequisites`; nonempty ledger prohibits automatic retry and blocks user/Bench/site work. |
| Frappe user/database identity | Host `useradd`/ownership and MariaDB administrative setup with explicit status checks | `frappe-user`, then `mariadb-admin`, before mutation | Exit 31 at `frappe-user`; retry prohibited. Toolchain and all later rows are skipped. |
| Isolated toolchain | Frappe home bootstrap with `UV_NO_CONFIG=1`; exact NVM commit, Node/Yarn, uv/Python/Bench install; a separate new isolated shell runs all six version commands and checks paths, ownership, executability, and pinned versions | `frappe-toolchain` before bootstrap | Exit 31 at `frappe-environment`; retry prohibited. Bench is not invoked. |
| Bench creation | A Frappe-owned isolated Git stage is fetched from the official origin, proves pin ancestry, and checks out the pin before exact `bench init --frappe-path STAGE`; then safe Bench/Frappe/env/sites/config/Procfile, Python 3.14.6/pip 25.3, working Bench commands, official final origin, and exact Frappe commit | `source-stage-attempt:frappe`, `source-stage:frappe@COMMIT`, then `bench` and `source:frappe@COMMIT` only after proof; `partial-bench` on failed/incomplete output | Exit 31 at `bench-created`; retry prohibited. Site, backup, apps, and config are skipped. |
| Site creation | Verified Bench directory; exact `bench new-site` status; safe exact site/config and successful `show-config`, then default-site commands | `site` after exact proof; `partial-site` for failed/incomplete output | Exit 31 before a verified site, otherwise 33 `recovery-required`, at `site-created`. All later rows are skipped. |
| Credential persistence | Root writes a mode-0600 same-directory temporary file with tracing disabled, verifies type/owner/mode/content contract, and atomically replaces the canonical credentials path | `credentials-file-attempt` before writing; `credentials-file` only after proof; cleanup/partial markers on failure | Exit 33 `recovery-required` at `credentials-persisted`; site and protected evidence remain, active config is absent, and backup/apps are skipped. Retry prohibited. |
| Baseline backup | Bench directory; exact `bench backup --with-files`; newly created complete set newer than operation start; nonempty gzip, both tar archives, and JSON parse | `baseline-backup` only after full proof | Exit 33 at `baseline-backup`, backup remains `none` unless verified. No staging or app acquisition. Retry prohibited. |
| Private config staging | Protected operation directory; unchanged config snapshot; new mode-0600 staged schema-2 file | `staged-config` after proof; `partial-staged-config` on incomplete output | Exit 33 at `configuration-staging`; active config unchanged. Retry prohibited. |
| Dependency-ordered acquisition | Each official approved branch is fetched into an isolated Frappe-owned stage, pin ancestry is proven, and the pin is checked out before `bench get-app --branch REF APP STAGE`; final origin is replaced with the official repository and HEAD must equal the immutable plan | `source-stage-attempt:APP`, `source-stage:APP@COMMIT`, then `code:APP` and `source:APP@COMMIT` after proof; `partial-code:APP` if failed or mismatched output exists | Exit 33 at `get-app:APP`; no later acquisition/install/migration. Retry prohibited. |
| Dependency-ordered installation | One isolated exact-site `bench install-app APP`; separate exact-site `list-apps` confirms membership | `site-app:APP` after proof; `partial-site-app:APP` on command failure | Exit 33 at `install-app:APP`; no later install/migration. Retry prohibited. |
| Migration/assets | Exact-site `bench migrate`; then isolated `bench build` plus exact-site cache clears | `migration-attempt`, `assets-attempt` before mutation | Exit 33 at `migration` or `assets`; services and promotion are skipped. Retry prohibited. |
| Service/readiness | Isolated start helper, managed unit/autostart/start, then HTTP and stable asset readiness | `services-attempt` before mutation | Exit 33 at `services` or `readiness`; inventory and promotion are skipped. Retry prohibited. |
| Exact inventory | Exact installed set equality (no missing, duplicate, or extra app), safe app directories, and catalog source/ref equality for Frappe and every resolved app | No new artifact | Exit 33 at `inventory`; configuration is not promoted. Retry prohibited. |
| Promotion/reconciliation | Unchanged config snapshot; protected per-file replacement; then schema/profile/request equality, exact inventory/source/ref, and readiness again | `configuration-promotion-attempt` before replacement; `active-config` only after both outputs | Exit 33 at `configuration-promotion` or `post-promotion-reconciliation`; evidence is retained for manual recovery. |
| Reboot/readiness acceptance | Outside the installer transaction: reboot the disposable VM, then repeat service, HTTP/assets, exact inventory, source/ref, backup, and record checks | None | A failure is a VM acceptance blocker. Revert the snapshot; never reinterpret the completed record as reboot proof. |

Every phase call returns immediately on failure. Hermetic fault injection asserts
that the next boundary is absent from its command log and that active
configuration is absent before promotion. Only the first, exact, protected,
empty-ledger `failed/prerequisites` case is retryable; every later or uncertain
state is fail-closed.

This status differs from `backup-status`, which observes metadata;
`backup-verify`, which performs deeper archive validation; restore preflight,
which assesses a chosen restore; and restore itself. The install transaction
creates only its required baseline backup and does not adopt or inspect an
existing deployment.

#### Disposable-VM acceptance (explicit opt-in)

Live acceptance is permitted only on a newly provisioned, disposable Native VM.
The operator must first create the root-owned marker
`/etc/erpnext-dev-disposable-vm` containing the VM change-ticket identifier and
must confirm that no Toolkit configuration, Bench directory, site, or database
exists. Never create this marker on a workstation or reusable host.

Before each attempt, verify UTC and the active synchronization provider with
`date -u`, `timedatectl status`, and (when Chrony is active) `chronyc tracking`.
If synchronization cannot be proven or APT reports that Release metadata is
“not valid yet,” the advanced transaction must stop at `prerequisites` with exit
31, an empty artifact ledger, and no baseline backup. Correct the VM clock or
repository access and rerun the exact same `install --profile advanced` request.
Never use `first-run` to recover an advanced transaction.

That exact retry is safe only when every preserved Native advanced record is a
protected, terminal `failed/prerequisites` record for the identical site,
requested applications, and resolved closure; its ledger is empty and backup is
`none`; and no configuration, Bench, site, acquired application, staged intent,
active transaction, or recovery-required state exists. Previous records remain
immutable evidence and the retry creates a new attempt record. If any condition
cannot be proven, revert the disposable VM to its clean snapshot instead of
editing records, deleting partial state, or forcing a retry.

On that marked VM, record a snapshot, then run these acceptance cases manually:

1. Install an ERPNext-free catalog set with the canonical advanced command;
   verify readiness, exact site inventory, the protected operation record, and
   baseline backup, then reboot and repeat readiness/inventory checks.
2. Revert the VM snapshot and install a multi-application catalog set whose
   closure includes dependencies; verify exact acquisition and installation
   order, sources/refs, readiness, inventory, backup, and reboot durability.
3. Revert again, set the test-only fault injection at a post-site checkpoint,
   run the same install, and verify a non-success exit, unchanged active config,
   preserved site/baseline evidence, and `recovery-required` guidance.
4. Destroy the VM after exporting only sanitized assertion results. Do not reuse
it and do not connect the procedure to any existing deployment.

Site creation uses the exact pinned Frappe prompt order: MariaDB administration
password first, then the site Administrator password. Python's `getpass` opens
`/dev/tty` before falling back to standard input, so an ordinary anonymous pipe
is insufficient when the installer itself has a controlling terminal. Phase
7.4 therefore runs the exact `bench new-site` command in a bounded new session
with no controlling terminal and supplies both generated credentials over a
private anonymous descriptor. Neither credential is placed in argv or the
exported environment. The supervising shell forwards termination to the whole
detached process group, waits for it, and returns Bench's exact exit status.
This behavior is pinned-source evidence, not a prompt-order assumption:
`frappe/database/mariadb/setup_db.py::get_root_connection` calls `getpass` for
the missing database password before connecting, while
`frappe/utils/install.py::get_admin_password` calls it later during database
bootstrap. Both files are verified at the reviewed Frappe commit recorded in
the operation plan. Python's standard-library `getpass` implementation attempts
the controlling terminal independently of redirected stdin; removing the child
session's controlling terminal is therefore the required isolation boundary.

The marker is authorization to follow this procedure, not a bypass in the
installer. Hermetic CI never creates it. The required pull-request integration
job instead runs the exact production advanced entry point on a fresh ephemeral
Ubuntu 26.04 hosted runner, performs the real Bench/site/backup/app/migration/
asset/service/readiness/promotion path, and emits only a sanitized checkpoint
summary. Hermetic command stubs remain fault-injection evidence and are not
described as real installation coverage.

#### PDF capability on Ubuntu 26.04

Frappe requires wkhtmltopdf 0.12.6 with patched Qt for supported PDF output.
Phase 7.4 does not download an unverified third-party binary. After package
installation it executes `wkhtmltopdf --version` and records
`PDF_CAPABILITY=available` only when both `0.12.6` and `patched qt` are proven.
Otherwise installation remains safe but explicitly records
`PDF_CAPABILITY=unavailable`; PDF generation is not a claimed capability. Use a
distribution or vendor package only after its origin, checksum, Ubuntu 26.04
compatibility, and patched-Qt build are independently reviewed, then rerun the
capability check. Do not substitute an arbitrary binary from a mirror.

### Existing installation management (existing)

- Inventory first discovers candidates without executing their application code
  or changing them.
- Adoption requires one unambiguous compatible stack, explicit operator consent,
  exact site inventory, supported Frappe major, trusted core source/image, a clean
  managed code state, and a supported runtime topology.
- Adoption records intent and identifiers atomically; it does not reinstall
  Frappe, ERPNext, dependencies, services, or sites.
- Observed applications remain authoritative. Unknown/custom apps are displayed
  and preserved, but block operations that would rebuild or remove shared code
  unless their durability can be proven.
- “Existing” remains provenance/management intent; it does not falsely imply a
  required ERPNext set.

## State transitions and mutation boundaries

```text
unconfigured
  -> planned (validated profile, target, dependency closure, inventory fingerprint)
  -> confirmed
  -> provisioning/adopting
  -> verifying
  -> managed-consistent | managed-drift | recovery-required

planned/confirmed -> cancelled                 (no mutation, status 0 interactively)
planning failure  -> rejected                  (no config/deployment mutation)
pre-deploy failure -> failed-safe              (active deployment unchanged)
post-deploy failure -> recovery-required       (journal and prior artifacts retained)
```

The plan includes a fingerprint of the inventory used to make it. If inventory
changes before mutation, rebuild and reconfirm the plan. Configuration should be
staged before deployment but promoted as current intent only after verification;
the operation journal retains prior and candidate configuration throughout.

Native fresh-install boundaries:

- package/toolchain or Bench acquisition failure before site creation may clean
  only transaction-created artifacts that the journal proves were absent before;
- once a site/database exists, never claim automatic rollback without a verified
  pre-mutation backup or a provably transaction-created disposable site;
- an existing bench is never archived/replaced through the `existing` profile;
- post-site failure is recovery-required and preserves logs, credentials file,
  bench, database, and the exact next recovery action.

Docker boundaries:

- image construction and verification occur before deployment and leave the
  active stack unchanged on failure;
- production always builds a cumulative image containing Frappe plus the resolved
  app set; it never fetches durable code into a running container;
- every application service must use the verified digest before site mutation;
- backup failure blocks deployment; after deployment begins, retain the prior
  image/digest, manifest, config, service state, and verified site backups;
- Docker development mutations are labelled non-durable unless represented by a
  rebuildable custom image contract.

Recovery reuses the operation journal and the existing backup/restore foundation.
It verifies absence of intervening mutation before automatic action and otherwise
prints a manual recovery plan. Secrets are never copied into operation state.

## User-visible representation

A Frappe-only site is a normal Frappe site, not an incomplete ERPNext site:

- `site list`: lists the site with `frappe` in installed apps and no `erpnext`;
  discovery remains `known` when the database proof succeeds.
- `app list`: lists Frappe code/site usage; ERPNext is `missing`/absent by intent,
  not a warning. Shared code and per-site installation remain separate.
- status and Doctor: show profile, reconciliation state, Frappe/site readiness,
  runtime, HTTP, workers, scheduler, queue, Redis, assets, and backups. ERPNext is
  `INFO absent by profile`, not failed health.
- setup wizard: Quick is visibly Recommended; Advanced presents all four setup
  choices, then engine/environment and, for advanced, the supported app selector.
  Existing discovery happens before any save or install prompt.
- Operations Dashboard: header includes profile and reconciliation state; health
  remains Frappe/runtime based. An optional ERPNext row is informational unless
  required by resolved intent.
- Optional Apps / App Management: show ERPNext prominently as the recommended
  later addition on Frappe-only sites. Each app shows dependency, compatibility,
  engine strategy, shared-image impact, and install state. ERPNext-specific apps
  are disabled with an explanation until a plan includes ERPNext.
- setup completion: use Frappe onboarding for Frappe-only. ERPNext’s setup wizard
  is expected only after ERPNext is installed; installation must not mark the
  profile verified until required migrations and onboarding readiness are proven.

Generic labels should say Frappe stack/site/service. Compatibility output may say
“ERPNext not installed” rather than inventing an ERPNext branch. Existing service
and variable names such as `erpnext-dev.service` and `DOCKER_ERPNEXT_IMAGE` remain
compatibility identifiers during Phase 7; renaming them is a separate migration.

## Supported combination matrix

| Profile | Native dev/prod | Docker development | Docker production | Existing adoption |
|---|---|---|---|---|
| recommended | Supported | Supported | Supported using pinned base/cumulative image | Supported when topology and inventory are compatible |
| frappe-only | Supported | Supported | Supported only with verified Frappe-only custom image | Supported when Frappe/site proof is complete |
| advanced | Supported for curated compatible apps | Supported; direct mutation is explicitly non-durable | Supported only through cumulative custom image | Not an adoption mode; use App Management after adoption |
| existing | Discover/adopt compatible Bench | Discover/adopt compatible project | Adopt only if image/app set is reconstructible and immutable | Profile purpose |

Initially unsupported and fail-closed:

- missing Frappe, mixed unsupported core majors, incompatible database/runtime,
  ambiguous multi-bench selection, or incomplete site inventory;
- silently adopting externally managed Supervisor/Compose layouts;
- converting engines during adoption;
- treating unknown/custom code as safe to rebuild into Docker production;
- profile-wide app removal, cascades, site deletion, or data cleanup;
- arbitrary Git application selection in `advanced`;
- secrets in profile metadata or command-line app/repository values.

## Current mandatory-ERPNext assumptions to remove or constrain

The following are evidence locations, not all runtime defects. Conditional uses
that already respect `installation_profile_requires_erpnext` should remain:

| Area | Current evidence | Phase 7 impact |
|---|---|---|
| Profile contract | `lib/profile.sh` accepts only recommended/Frappe-only and treats the value as required-app policy | Add four setup intents and separate reconciliation helpers |
| CLI | `erpnext-dev.sh` documents/validates only two `--profile` values; global parsing also reuses `--profile` for stack conversion | Scope validation by command and add deterministic `--apps` parsing |
| Setup | `lib/install.sh` calls Quick/Advanced installation modes while the product also needs an Advanced profile; lifecycle/public guided text says “Install ERPNext” | Disambiguate UI mode from canonical profile and make guided flow profile-neutral |
| Existing deployment | `setup_has_existing_deployment` bypasses fresh selection; inventory labels compatible candidates `supported-unadopted` but there is no adoption transaction | Add explicit read-only discovery and atomic adoption |
| Native install | `install_frappe_stack_as_user` has hard-coded recommended/Frappe-only branches | Execute a resolved app plan rather than profile-specific conditionals |
| App wizard | `lib/apps.sh:app_wizard_preflight` reports “ERPNext installed” and the legacy compatibility evaluator substitutes an ERPNext branch when absent | Use inventory/reconciliation and expose ERPNext as a later install target |
| Status/Doctor | Several headings still say “ERPNext Developer/Installation Status”; `run_app_status` warns whenever the ERPNext site app is absent | Keep product name but make stack health/profile rows neutral and absence profile-aware |
| Production/SSL | `lib/service.sh:setup_production_runtime`, guided production helpers, and `lib/ssl.sh` failure text say ERPNext must be installed/running even though their gate is `install_state` | Describe and validate a ready Frappe stack |
| Docker base | `DOCKER_ERPNEXT_IMAGE`, image-tag parsing, preflight/status labels, backup manifests, and Compose overrides assume the official ERPNext image is the universal base | Preserve variable compatibility, but derive a profile-aware base artifact and verify actual apps |
| Docker core capture | `docker_custom_image_capture_core_state` is organized around ERPNext versions and must not query an empty ERPNext ref for Frappe-only | Make Frappe mandatory and ERPNext optional in exact-ref verification |
| Docker custom UI | `docker_custom_image_config` comments/default prompt/status say ERPNext is always included | Render the resolved profile plan and complete dependency set |
| Inventory trust | Docker built-in image trust special-cases `image:frappe/erpnext:*` | Trust the verified digest/manifest and actual core set, not an image name alone |
| Readiness/docs | help, lifecycle, access, SSL, final-QA, and validation prose often uses ERPNext as the stack synonym | Change only claims whose gate is actually Frappe/runtime-wide; retain genuinely ERPNext-specific paths |
| Tests | platform/profile, interactive, Docker, inventory, planner, app-removal, status/UI, and release validation encode the two-profile matrix and ERPNext-labelled output | Extend fixtures across four intents and negative/security matrices |

## Ordered implementation PRs

Each PR must keep `VERSION` unchanged until a separately authorized release.

### PR 7.1 — Shared profile contract, reconciliation, and plan schema

- **Scope:** extend canonical profile validation; add untrusted `--apps` parsing,
  profile/app-set validation, dependency closure, intent-versus-inventory
  reconciliation, config schema reading, and a read-only plan representation.
- **Expected files:** `erpnext-dev.sh`, `lib/profile.sh`, `lib/config.sh`,
  `lib/apps.sh`, `lib/inventory.sh`, `lib/planner.sh`, focused new/updated profile
  tests, `scripts/validate-release.sh`, manifest/checksums, and closest docs.
- **Behaviour:** existing commands retain defaults; explicit advanced/existing can
  validate and preview but do not install/adopt yet; JSON uses a new explicit
  schema version if fields change.
- **Native/Docker:** one engine-neutral contract; adapter capability checks are
  data returned in the plan.
- **Migration:** legacy missing/two-value config remains read-only and recommended
  by compatibility; schema upgrades only on authorized writes.
- **Security/recovery:** strict identifiers, catalog-only apps, no eval, no secrets,
  no mutation, inventory fingerprint.
- **Hermetic tests:** canonical/alias/bad-input matrix, option scoping, duplicates,
  cycles/conflicts, dependency order, legacy config, stale profile drift, ambiguous
  inventory, deterministic text/JSON, native/Docker capability matrix.
- **Live acceptance:** read-only preview/status on retained recommended and
  Frappe-only Native/Docker fixtures; prove files/services/sites unchanged.
- **Exclusions:** no installer adapter changes, adoption, image build, app/site
  mutation, uninstall, restore, or service-name rename.

### PR 7.2 — Profile-aware status, health, dashboard, and App Management

- **Scope:** make all read-only surfaces represent Frappe-only, advanced, and
  existing intent accurately; expose ERPNext as a planned later addition.
- **Expected files:** `lib/status.sh`, `lib/support.sh`, `lib/health.sh`,
  `lib/dashboard.sh`, `lib/menu.sh`, `lib/apps.sh`, `lib/access.sh`, UI/status/
  health tests and docs.
- **Behaviour:** profile and reconciliation appear consistently; Frappe-only is
  healthy without ERPNext; dependency-blocked apps explain how to include ERPNext.
- **Native/Docker:** same vocabulary and schema; engine-specific runtime details
  remain adapter owned.
- **Migration:** no config write; old output headings may remain aliases while
  machine-readable schema changes are versioned.
- **Security/recovery:** read-only inventory only; redact paths/values consistently;
  no application imports.
- **Hermetic tests:** Frappe-only/recommended/advanced/existing render fixtures,
  absent ERPNext, stale metadata, ambiguous inventory, narrow/wide UI and JSON.
- **Live acceptance:** status, Doctor, dashboard, site/app list on non-mutated
  Frappe-only and recommended installations for both engines where available.
- **Exclusions:** no install/adoption or app mutation.

Machine-readable Doctor and health/dashboard output use schema version 2 when
profile context is present. Version 2 preserves the version 1 fields and adds
canonical intent, desired and observed application sets, reconciliation,
capability, durability, and the secret-free inventory fingerprint. Runtime
health and profile reconciliation remain separate values even when missing
required applications make the aggregate application health degraded.

### PR 7.3 — Existing-installation discovery and explicit adoption

- **Scope:** implement `--profile existing` discovery, selection, compatibility
  gate, preview, confirmation, and atomic configuration adoption.
- **Expected files:** `lib/profile.sh`, `lib/inventory.sh`, `lib/config.sh`,
  `lib/engine.sh`, `lib/install.sh`, dispatcher/menu, operation journal helpers,
  adoption tests and docs.
- **Behaviour:** compatible bench/site becomes managed without reinstall; multiple,
  dirty, unknown, or incompatible candidates stop safely.
- **Native/Docker:** Native validates owner/path/core remotes/runtime; Docker
  validates project topology, image digest, manifest reconstructibility, sites,
  and volumes.
- **Migration:** does not rewrite application state; preserves existing toolkit
  settings unless explicitly superseded in the confirmed plan.
- **Security/recovery:** canonical paths, symlink/ownership checks, exact target,
  no sourced candidate config, secrets remain in their existing stores; config
  replacement is the only mutation and retains the prior file for recovery.
- **Hermetic tests:** zero/one/many candidates, hostile names/paths/config,
  supported-unadopted to managed, unknown apps, custom images, cancellation and
  atomic-write failure.
- **Live acceptance:** adopt disposable compatible Native and Docker deployments;
  compare apps/sites/databases/services/images/volumes before and after.
- **Exclusions:** no package install, Bench commands that mutate, image build,
  engine conversion, app install/uninstall, or site creation.

### PR 7.4 — Native advanced installation vertical slice

- **Scope:** drive fresh Native install from the resolved advanced plan and show
  final plan before mutation.
- **Expected files:** `lib/install.sh`, `lib/profile.sh`, `lib/planner.sh`,
  `lib/apps.sh`, `lib/backup.sh`, config/journal helpers, interactive/native tests,
  validation and docs.
- **Behaviour:** installs Frappe, creates site, acquires dependency-ordered curated
  apps, installs them on the exact site, migrates/builds, verifies, then promotes
  intent config.
- **Native/Docker:** Native only; Docker explicitly reports not implemented for
  advanced mutation until PR 7.5.
- **Migration:** recommended/Frappe-only paths are regression-identical; no existing
  bench replacement.
- **Security/recovery:** escaped fixed argv construction, trusted repos only,
  preflight before mutation, transaction-created-artifact ledger, backup boundary,
  recovery-required after site creation.
- **Hermetic tests:** plan-to-command order with mocked Bench, dependency closure,
  already-present code, staged config promotion, failure at every checkpoint,
  cancellation, no secret logging.
- **Live acceptance:** disposable Native VM for Frappe-only-equivalent advanced
  set and a multi-app set; reboot, readiness, inventory, backup, and failure
  recovery drill.
- **Exclusions:** Docker implementation, custom Git apps, existing adoption,
  destructive conversion.

### PR 7.5 — Docker advanced immutable-image vertical slice

- **Scope:** consume the same advanced plan in Docker development and production;
  repair remaining Frappe-only core-ref/base-image assumptions.
- **Expected files:** `lib/docker.sh`, `lib/planner.sh`, `lib/profile.sh`, Docker
  durability/reliability/routing tests, validation and docs.
- **Behaviour:** development declares durability limits; production builds and
  verifies a cumulative image, backs up sites, deploys one digest across all app
  services, installs site apps, verifies, then promotes manifest/config.
- **Native/Docker:** no Native changes beyond shared regression tests.
- **Migration:** imports all known installed apps into the candidate manifest;
  unknown apps block replacement; old ERPNext image variables remain readable.
- **Security/recovery:** trusted manifest, exact refs/digests, BuildKit secret-safe
  handling if ever needed, no secrets in build args/logs, prior image and backups
  retained.
- **Hermetic tests:** recommended/Frappe-only/advanced manifests, dependency order,
  Frappe-only exact-ref capture, unknown apps, multi-site impact, service image
  consistency, staged promotion, each failure boundary.
- **Live acceptance:** disposable Docker development and production VMs; image
  inspection, site app list, frontend assets, reboot, second app addition, and
  rollback/recovery drill.
- **Exclusions:** arbitrary custom apps, registry publication, image deletion,
  releases.

### PR 7.6 — Setup wizard and end-to-end profile UX

- **Scope:** present the four product choices coherently in first-run, local, and
  public wizards; integrate plan review, cancellation, setup completion, and docs.
- **Expected files:** `lib/install.sh`, `lib/menu.sh`, `lib/ui.sh`, `lib/apps.sh`,
  help/README/VALIDATION/TESTING and interactive/UI/adversarial tests.
- **Behaviour:** Recommended is the default and clearly marked; Frappe-only,
  Advanced, and Existing have accurate consequences; final confirmation is the
  last boundary before mutation; automation remains prompt-free with complete
  explicit options.
- **Native/Docker:** same choice flow, with unsupported combinations disabled and
  explained before confirmation.
- **Migration:** existing quick commands and default answers stay unchanged.
- **Security/recovery:** never echo secrets; terminal cancellation is status 0 and
  non-mutating; EOF fails before mutation; sanitized plan rendering.
- **Hermetic tests:** full stdin matrix, terminal/tee behaviour, Back/Quit/EOF,
  explicit automation, hostile identifiers, narrow/wide rendering.
- **Live acceptance:** one fresh path per supported engine/environment/profile
  combination affected, plus non-destructive existing adoption and cancellation.
- **Exclusions:** new app catalog entries, releases, engine conversion.

### PR 7.7 — Recovery and readiness closure

- **Scope:** close profile-aware restore/readiness/final-QA gaps and publish the
  complete field-acceptance matrix only after earlier slices pass.
- **Expected files:** `lib/backup.sh`, `lib/removal.sh`, `lib/health.sh`,
  `lib/ssl.sh`, `lib/service.sh`, `lib/update.sh`, recovery/readiness tests,
  `TESTING.md`, `VALIDATION.md`, and focused architecture docs.
- **Behaviour:** recovery restores prior intent/manifest/config only with proven
  checkpoints; readiness is Frappe-first and adds ERPNext gates only when required.
- **Native/Docker:** exercise native database/files/config/service recovery and
  Docker prior-image/manifest/volume/site recovery.
- **Migration:** old operation records remain inspectable; unsupported schema is
  manual-review, never guessed.
- **Security/recovery:** controlling-terminal confirmations, no secret logs,
  intervening-mutation detection, exact backup compatibility.
- **Hermetic tests:** every operation status, stale/intervening state, corrupt
  record, restore cancellation through tee, profile mismatch and service restore.
- **Live acceptance:** snapshot-backed failure injection and recovery for Native
  and Docker; verify inventory/config/service/HTTP before and after.
- **Exclusions:** release/tag/publication and automatic destructive rollback where
  proof is incomplete.

## Principal risks and mitigations

- **Profile metadata becomes false authority:** always reconcile against inventory;
  fingerprint before mutation and report drift.
- **“Advanced” means both UI mode and profile:** rename the internal UI concept to
  selection flow while preserving displayed wording; canonical `advanced` means
  selected app intent.
- **“Existing” accidentally mutates a production stack:** discovery is read-only,
  adoption is explicit and config-only, ambiguity blocks.
- **Docker Frappe-only inherits ERPNext image assumptions:** verify actual app set,
  exact core refs, digest, and all service images; keep legacy variable names only
  as compatibility plumbing.
- **Dependency catalog is incomplete or stale:** fail closed, show the resolved
  closure, keep catalog records validated, and require live acceptance for app
  combinations.
- **Multi-site shared-code blast radius:** plans enumerate every site and require
  all-site backup before shared native code or Docker image changes.
- **Partial install is misreported as rollback:** journal checkpoints and distinguish
  failed-safe from recovery-required; never delete unproven pre-existing state.
- **Automation regression:** preserve no-option defaults, provide deterministic
  explicit options/JSON, and test non-TTY, EOF, and `--yes` combinations.
- **Secret exposure:** persist identifiers only, use existing credential stores,
  redact plans/journals/support bundles, and prohibit credential-bearing URLs.

## Deferred acceptance after PR 7.1

PR 7.1 deliberately does not change the setup wizard, status wording, installer
adapters, or browser access behavior. Frappe-only web accessibility and remaining
ERPNext-specific stack labels stay as explicit acceptance work for PR 7.2 and the
later Native/Docker vertical slices. A successful read-only plan is not evidence
that those deferred runtime paths have passed live acceptance.
