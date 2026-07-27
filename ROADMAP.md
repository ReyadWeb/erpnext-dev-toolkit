# ERPNext Developer Toolkit Roadmap

**Current release:** v1.20.0
**Current work:** v1.20.1 — Release Coherence and Public Testing Foundation
**Next product milestone:** v1.20.1 — Release Coherence and Public Testing Foundation
**Public roadmap board:** https://github.com/users/ReyadWeb/projects/3

The active roadmap contains current priorities and forward-looking commitments only. Completed plans and superseded sequencing are preserved in [Roadmap history](docs/ROADMAP-HISTORY.md), [CHANGELOG.md](CHANGELOG.md), and Git history.

## Product direction

ERPNext Developer Toolkit is a single-node ERPNext/Frappe installation and operations platform for local virtual machines and public servers.

The project is moving through three deliberate stages:

1. **Reliable operator toolkit** — installation, HTTPS, security, backup, restore, health, updates, rollback, and diagnostics.
2. **Stable machine interface** — versioned JSON contracts, bounded operations, auditable jobs, and a local privileged agent.
3. **Panel-ready node platform** — a stable interface that a separate web control panel can consume without scraping terminal output or exposing arbitrary root shell access.

The toolkit remains useful as a standalone CLI. A future panel is an additional interface, not a replacement for the CLI.

## Roadmap principles

1. **Reliability before feature breadth** — existing workflows must be predictable, recoverable, and testable before major expansion.
2. **Secure by default** — root-run configuration is data, privileged actions are bounded, and release integrity is mandatory.
3. **No false readiness** — runtime, HTTP, and login-critical frontend assets must pass before readiness is reported.
4. **Backup before change** — high-impact operations require a verified recovery point and a rollback or restore path.
5. **Native and Docker parity** — operators should receive consistent lifecycle outcomes across supported engines.
6. **Human CLI and machine contracts remain separate** — machine consumers use versioned JSON schemas and stable exit codes.
7. **No arbitrary privileged shell API** — agent and panel operations must be allowlisted, validated, authorised, logged, and bounded.
8. **Evidence over readiness scores** — confidence comes from CI, clean-environment testing, provider validation, restore rehearsal, and published evidence.
9. **Documentation matches shipped behaviour** — planned work is clearly labelled and current guidance reflects the stable release.
10. **History is preserved without obscuring current priorities** — completed and superseded plans belong in the changelog, roadmap history, issues, and Git history.

## Scope

### Current product scope

- Dedicated single-node ERPNext/Frappe hosts
- Local development and testing virtual machines
- Public VPS production deployments
- Native and Docker deployment engines
- Guided installation and configuration
- Local and production HTTPS
- Security hardening and exposure checks
- Local, off-VM, and object-storage backup workflows
- Backup verification and restore rehearsal
- Health snapshots, dashboard, incidents, and guarded healing
- Optional Frappe application workflows
- Signed toolkit updates and rollback
- Diagnostics and redacted support evidence

### Outside the current core scope

- General-purpose server control panel
- Arbitrary remote command execution
- Multi-tenant shared hosting
- Automatic high-availability clustering
- Multi-region database replication
- Unbounded self-healing
- Guaranteed compatibility with every custom Frappe application
- Replacement for provider monitoring, identity, firewall, or backup controls

These may be considered later only after the machine interface and node-agent contract are stable.

## Shipped foundation

The detailed release record is maintained in [CHANGELOG.md](CHANGELOG.md).

| Foundation | Current state |
|---|---|
| Guided local VM and public VPS workflows | Shipped |
| Native and Docker engines behind one CLI | Shipped |
| Local and production HTTPS workflows | Shipped |
| Backup, off-VM copy, verification, and restore rehearsal | Shipped |
| Production runtime and service management | Shipped |
| Frontend login-asset readiness and repair | Shipped |
| Dashboard, health snapshots, incidents, alerts, and guarded healing | Shipped |
| Local VM stable-IP planning, drift detection, and rollback | Shipped |
| Credentials handling and redacted support bundles | Shipped |
| Repository security scanning and workflow pinning | Shipped |
| Signed release publication and protected signing authority | Shipped |
| Atomic complete-tree toolkit update and rollback | Shipped |
| Canonical version, authoritative manifest, and exact checksums | Shipped in v1.20.0 |
| Transactional beta/stable promotion and strict pre-tag validation | Shipped in v1.20.0 |
| Signed complete-bundle bootstrap guidance | Shipped and regression-tested in v1.20.0 |

## Delivery sequence

```text
Documentation consolidation     Complete after v1.20.0
v1.20.1                         Current — release coherence and pre-sudo trust
v1.20.2                         Promotion governance and release evidence
v1.20.3                         Configuration and execution boundaries
v1.20.4                         Transaction journal MVP
v1.20.5                         Declarative command architecture
v1.21.0                         Machine-readable API foundation
v1.21.1+                        Jobs, privileged agent, watchdog, panel contract
v1.22.0                         Real VPS validation matrix
v1.23.0                         Onboarding and launch polish
v2.0.0                          Stable panel-ready node-agent contract
```

Version assignments after v1.21.0 are planning targets. They may be adjusted through issues and pull requests when implementation evidence shows that a milestone should be split or delayed.

# Completed maintenance milestone

## Documentation consolidation

**Status:** Completed after v1.20.0

The documentation programme reorganised the project landing page, security
policy, active roadmap, repository workflow, testing model, and real-machine
validation guidance without changing the stable release identity.

Completed scope:

- D1 — README and goal-based documentation navigation
- D2 — current security policy plus focused architecture, trust, hardening, and
  history documents
- D3 — active roadmap reconciliation and preserved roadmap history
- D4 — concise active testing guide, preserved testing history, real-machine
  validation matrix, and release-workflow documentation alignment

Documentation consistency automation remains a normal maintenance improvement
and may be implemented during the v1.20.x reliability programme. It no longer
blocks the completed documentation milestone.

Completion evidence:

- repository and release validation pass;
- release manifest and checksums include the maintained documentation set;
- active release guidance uses the guarded repository workflow;
- version-specific testing evidence is preserved outside the active guide;
- the roadmap and README now identify v1.20.1 reliability work as current.

# Now

## v1.20.1 — Release Coherence and Public Testing Foundation

**Status:** In implementation
**Feature policy:** No new ERPNext deployment feature

**Goal:** Realign source state, published release state, trust guidance, strict
qualification, current repository workflow, and public testing before resuming the
machine-interface roadmap.

Authoritative design: [Release-State Contract](docs/RELEASE-STATE.md).

### R1 — Release-state invariant

- [x] Adopt the formal release-state contract.
- [x] Add measurable audit checks and negative tests.
- [x] Remove `SCRIPT_VERSION` as an independently maintained literal; the compatibility variable now derives canonical metadata.
- [x] Derive source channel from exact Git tag or validated release context; immutable bundle context follows in R1B-2.
- [ ] Generate immutable bundle metadata containing version, tag, channel, commit,
  tree digest, and build time.
- [x] Make workflows use `scripts/release-version.sh` for release identity.
- [ ] Distinguish current development from latest published stable in every active
  document and generated surface.

### R2 — Authenticity before privilege

- [ ] Publish `RELEASE-ASSETS.sha256` and its detached signature.
- [ ] Verify the pinned signing-key fingerprint with a temporary keyring.
- [ ] Verify signature, archive digest, archive paths, and internal checksums before
  any downloaded toolkit code executes with `sudo`.
- [ ] Make README, SECURITY, release notes, normal install, and recovery use the
  same non-privileged verifier.

### R3 — CI supply-chain consistency

- [ ] Replace `curl | sudo tar` with a repository-controlled verified installer.
- [ ] Pin every downloaded CI binary by version and SHA-256.
- [ ] Extract without privilege and install only the verified executable.

### R4 — Strict qualification

- [ ] Contributor mode may warn about optional local dependencies.
- [ ] Required PR and release modes may not skip required checks.
- [ ] High-risk paths require same-commit integration evidence.

### WF-001 — Workflow consolidation

- [x] Add consolidated routine work commands over the existing safe primitives.
- [x] Keep advanced commands available for recovery and diagnosis.
- [x] Refuse implicit administrator merge bypass.

### R5 — Package and public-testing alignment

- [ ] Ship W1–W3 repository workflow and D1–D4 documentation in v1.20.1.
- [ ] Verify issue or Discussion submission with a non-maintainer account.
- [ ] Keep security reports in private vulnerability reporting.
- [ ] Complete native, Docker, upgrade, rollback, and public-reporting gates.

## v1.20.2 — Promotion governance and release evidence

**Status:** Planned after v1.20.1

- Exact-commit beta-to-stable promotion where practical.
- Formally defined same-runtime-payload digest otherwise.
- Artifact attestation, provenance, immutable-release verification, and protected
  release-environment review.

## v1.20.3 — Configuration and execution safety

**Status:** Planned

- Typed configuration registry and data classification.
- Ownership, mode, canonical-path, and symlink policy.
- Argument-safe execution wrappers and adversarial argument tests.

## v1.20.4 — Transaction journal MVP

**Status:** Planned

Start with toolkit update and restore: preflight, capture, recovery point, mutation,
verification, commit, rollback, recovery evidence, SIGTERM handling, resume, and
idempotency.

## v1.20.5 — Declarative command architecture

**Status:** Planned

Create one command registry to drive or validate dispatch, root policy, locking,
destructive confirmation, help, menu consistency, audit class, supported engines,
and future capability metadata.

# After the reliability foundations

## v1.21.0 — Machine-readable API foundation

**Status:** Planned
**Goal:** Define a stable machine interface before building a web panel or network-facing agent.

A future panel must not parse human terminal output. The first machine interface remains local and command based.

### Initial command contracts

Planned read-only commands:

```text
api-version --json
capabilities --json
deployment-info --json
dashboard --json
health-snapshot --json
incidents --json
backup-status --json
restore-status --json
```

Exact names may be refined during contract review, but compatibility rules must be established before public use.

### Common response envelope

```json
{
  "api_version": "1",
  "command": "deployment-info",
  "success": true,
  "timestamp": "2026-07-25T21:18:29Z",
  "data": {},
  "warnings": [],
  "errors": []
}
```

### Contract requirements

- Versioned API envelope
- Defined field types and nullability
- Stable machine-readable error identifiers
- Stable exit-code classes
- UTC ISO-8601 timestamps
- No ANSI colour or interactive prompts
- No secrets in normal output
- Explicit capability discovery
- Native and Docker parity where the underlying capability exists
- JSON Schema fixtures and compatibility tests
- Human CLI output remains independent from the JSON contract

### Acceptance

- [ ] `api-version --json` publishes the contract version.
- [ ] `capabilities --json` reports supported engine and operation capabilities.
- [ ] Deployment, health, incident, backup, and restore status are available as valid JSON.
- [ ] Schemas and examples are packaged with the release.
- [ ] CI validates output against schemas.
- [ ] Machine mode never emits terminal formatting.
- [ ] Sensitive values are absent or explicitly redacted.
- [ ] Stable exit-code behaviour is documented and tested.
- [ ] Human-readable output can change without breaking the machine contract.

## v1.21.1 — Operation and job model

**Status:** Planned after the read-only contract
**Goal:** Represent long-running and privileged operations without holding a fragile interactive request open.

Candidate operations include backup creation and verification, restore rehearsal, toolkit update, guarded ERPNext/Frappe update, optional application installation, frontend asset repair, and selected runtime repair actions.

### Planned model

```json
{
  "job_id": "job-20260725-001",
  "operation": "backup-create",
  "state": "queued",
  "created_at": "2026-07-25T21:18:29Z"
}
```

Planned job queries:

```text
operation-status JOB_ID --json
operation-log JOB_ID --json
operation-cancel JOB_ID --json
```

### Requirements

- Unique job identifiers
- Explicit lifecycle states
- Structured progress and result data
- Bounded log retention
- Redacted output
- Per-operation timeout
- Single-instance or concurrency policy
- Safe cancellation semantics
- Recovery after process restart
- Audit event for every state transition
- Idempotency strategy for retried requests

### Acceptance

- [ ] Long-running operations return a job identifier.
- [ ] Job state survives client disconnect.
- [ ] Duplicate requests do not silently repeat destructive work.
- [ ] Cancellation is supported only where safe.
- [ ] Results and failures are structured and auditable.
- [ ] A job cannot bypass the operation's existing safety gates.

## v1.21.2 — Local privileged agent MVP

**Status:** Planned after job contracts stabilise
**Goal:** Provide a narrow local authority boundary for a future panel or orchestration service.

### Initial architecture

- Listen on a Unix domain socket.
- Do not expose a TCP listener by default.
- Accept only predefined operations.
- Validate requests against schemas.
- Map each operation to an allowlisted toolkit action.
- Run with least privilege possible for the operation.
- Record an audit event for every request.
- Reuse existing locks, backup gates, readiness checks, and rollback controls.
- Start with read-only operations before enabling write operations.

### Security requirements

- No arbitrary shell, command strings, or script upload
- Peer identity verification on the local socket
- Explicit authorisation policy
- Request-size and field limits
- Timeouts and concurrency limits
- Replay and duplicate-request strategy
- Secret-free default responses
- Separate audit and operational logs
- Safe failure when the agent or toolkit version is incompatible
- Disabled network exposure unless a later reviewed transport is added

### Acceptance

- [ ] The agent exposes only documented allowlisted operations.
- [ ] Requests failing schema or authorisation checks are rejected before execution.
- [ ] Read-only mode can be deployed independently.
- [ ] Privileged write operations remain disabled until explicitly enabled.
- [ ] Every request records actor, operation, time, result, and job identifier where applicable.
- [ ] Agent and toolkit compatibility is machine-checkable.
- [ ] Threat model and deployment documentation are reviewed before release.

## v1.21.3 — External watchdog and heartbeat contract

**Status:** Planned after the local agent foundation
**Goal:** Make powered-off, frozen, or unreachable nodes observable from outside the VM.

An internal healing process cannot recover a VM that is no longer running. This milestone defines evidence an external monitor can consume.

### Planned heartbeat fields

```text
schema version
deployment identifier
site identifier
deployment engine
toolkit version
overall health state
last successful readiness time
last successful backup time
healing lockout state
timestamp
```

### Delivery options

- Local heartbeat file
- Agent status endpoint over the local socket
- Optional authenticated export designed for an external collector
- Reference integration for a separate watchdog service
- Provider-recovery abstraction design, without embedding provider credentials into the core toolkit

### Acceptance

- [ ] Heartbeat schema is versioned and documented.
- [ ] An external system can distinguish healthy, stale, and unreachable states.
- [ ] Staleness thresholds are explicit.
- [ ] Heartbeat output contains no credentials.
- [ ] Documentation explains that external recovery requires provider-side authority.
- [ ] Provider actions remain disabled until separately configured and reviewed.
- [ ] The contract works for native and Docker deployments.

## v1.21.4 — Panel integration contract

**Status:** Planned after API, jobs, agent, and heartbeat
**Goal:** Provide the stable integration boundary for a separate control-panel repository.

### Scope

- Consolidated JSON Schema or OpenAPI documentation
- Compatibility and deprecation policy
- Authentication and authorisation model
- Agent discovery and version negotiation
- Job and audit interfaces
- Read-only dashboard reference client
- Redacted diagnostics interface
- Upgrade and rollback compatibility rules
- Panel-facing error catalogue
- Sample integration tests

### Acceptance

- [ ] A reference client can discover and read node state without parsing terminal text.
- [ ] Unsupported capabilities are reported explicitly.
- [ ] Panel and agent version mismatch fails safely.
- [ ] Authentication does not rely on passing root credentials.
- [ ] Write operations remain allowlisted and auditable.
- [ ] A compatibility policy defines additive and breaking changes.
- [ ] The standalone CLI remains fully supported.

# Later

## v1.22.0 — Real VPS validation matrix

**Status:** Planned
**Goal:** Publish repeatable production evidence across multiple providers and deployment engines.

### Bounded release target

At least three providers, selected to represent different infrastructure families. Initial candidates:

- Hetzner
- DigitalOcean
- Vultr or Akamai/Linode

The living matrix may later include AWS, Azure, Google Cloud, local KVM, VirtualBox, Hyper-V, and Proxmox.

### Required coverage

- Ubuntu 24.04 LTS
- Ubuntu 26.04 LTS where provider images are suitable
- Debian 13 where supported by the selected path
- Native production deployment
- Docker production deployment
- Real DNS and HTTPS
- Provider and host firewall checks
- Scheduled backup
- Off-VM or object-storage copy
- Restore rehearsal
- Dashboard and health smoke tests
- Toolkit update and rollback
- Frontend asset readiness
- Reboot persistence

### Acceptance

- [ ] At least three provider appendices are published.
- [ ] Native and Docker production paths are both represented.
- [ ] Every appendix records image, resources, engine, domain method, and validation date.
- [ ] HTTPS, backup, restore, monitoring, update, and rollback evidence is included.
- [ ] Known provider-specific differences are documented.
- [ ] Failures and limitations are recorded, not hidden.
- [ ] The evidence can be repeated by another operator.

## v1.23.0 — Onboarding and launch polish

**Status:** Planned after the validation matrix
**Goal:** Make the supported paths easy to choose without overselling maturity.

### Scope

- Real terminal screenshots
- Current menu and dashboard captures
- Persona-based quickstarts
- Local VM visual guide
- Public VPS visual guide
- Native versus Docker decision guide
- Troubleshooting decision trees
- Production hardening checklist refinement
- Backup and restore visual workflow
- Provider-validation summary
- Clear support boundaries
- Website and repository presentation consistency

### Acceptance

- [ ] A new user can choose the correct path quickly.
- [ ] Screenshots match a current stable release.
- [ ] Installation examples use signed published assets.
- [ ] Local, public, native, and Docker paths are clearly separated.
- [ ] Troubleshooting routes lead to actionable diagnostics.
- [ ] Claims link to current validation evidence.
- [ ] Documentation contains no stale version banners or future features presented as shipped.

## v2.0.0 — Stable panel-ready node-agent contract

**Status:** Future major milestone
**Goal:** Declare the machine interface and node-agent boundary stable enough for independent panel development.

A major-version release is appropriate only when:

- The machine API has operated through multiple minor releases.
- Compatibility and deprecation rules have been exercised.
- Agent upgrades and rollback have production evidence.
- Authentication, authorisation, audit, and job handling have independent security review.
- Real-provider validation covers the supported deployment paths.
- A reference panel client can operate without private implementation knowledge.
- The CLI remains reliable when the panel or agent is absent.

### v2.0 acceptance

- [ ] API v1 schemas are stable and documented.
- [ ] Breaking-change policy is tested.
- [ ] Agent transport and authorisation are production-reviewed.
- [ ] Read and write operations are allowlisted and auditable.
- [ ] Job persistence and failure recovery are validated.
- [ ] Upgrade and rollback compatibility is proven.
- [ ] External watchdog integration is documented.
- [ ] Three-provider evidence is current.
- [ ] Independent control-panel development can proceed against public contracts.

# Backlog

Backlog items are not committed to a release until an issue defines scope, security boundaries, and acceptance evidence.

| Theme | Direction |
|---|---|
| Multi-site and multi-bench | Define explicit single-node limits before expanding |
| Advanced Docker lifecycle | Safer image refresh, custom-app rebuild, and rollback evidence |
| Restore laboratory | Disposable restore environments, reminders, and evidence reports |
| External monitoring adapters | Integrations that consume the heartbeat contract |
| Provider recovery adapters | Optional, isolated, and least-privilege provider actions |
| Object-storage depth | Retention, immutability, encryption, and provider evidence |
| Upgrade risk reports | Application compatibility and pre-change evidence |
| Support diagnostics | Better redaction, structured reports, and privacy review |
| High availability | Architecture research only after the single-node contract is stable |
| Multi-node orchestration | Separate product layer rather than expanding root Bash control |
| Signing improvements | Optional Sigstore, hardware-backed, or offline operational models |
| Commercial panel | Separate repository consuming the stable public agent contract |

# Definition of readiness

A milestone is not considered shipped because its code exists on a feature branch.

## Code readiness

- Scope and threat boundaries are documented.
- Error handling and rollback behaviour are explicit.
- ShellCheck, formatting, and repository validation pass.
- New contracts have regression tests.
- Native and Docker behaviour is tested where applicable.
- Security-sensitive paths receive focused review.

## Release readiness

- Canonical version, manifest, checksums, changelog, and documentation align.
- Beta preparation and promotion are transactional.
- Required CI and integration checks pass on the exact release commit.
- Signed complete-tree assets are published.
- A clean installation or update verifies the release.
- Rollback remains available and tested.

## Operational readiness

- Installation, upgrade, failure, and recovery paths are exercised.
- Frontend assets and browser readiness pass.
- Backups are verified.
- Restore rehearsal succeeds.
- Reboot persistence is confirmed.
- Provider-specific risks are documented.
- Operator documentation matches actual output.

## Contract readiness

For machine-facing work:

- Schema is versioned.
- Field semantics and errors are documented.
- Compatibility behaviour is tested.
- Secrets are excluded.
- Unsupported capabilities are explicit.
- Human terminal output is not part of the contract.
- Privileged operations are allowlisted and auditable.

# Planning and governance

- Active progress is tracked through GitHub issues, milestones, and the [roadmap board](docs/ROADMAP-BOARD.md).
- Security-sensitive changes follow [SECURITY.md](SECURITY.md) and the focused [security documentation](docs/security/README.md).
- Release procedures follow [Release automation](docs/RELEASE-AUTOMATION.md) and [Release process](docs/RELEASE-PROCESS.md).
- Testing and production evidence are maintained in [TESTING.md](TESTING.md) and [VALIDATION.md](VALIDATION.md).
- Shipped changes are recorded in [CHANGELOG.md](CHANGELOG.md).
- Superseded plans are preserved in [Roadmap history](docs/ROADMAP-HISTORY.md).

Roadmap versions and order are planning tools, not promises. Reliability, security evidence, and compatibility gates take precedence over target numbering.
