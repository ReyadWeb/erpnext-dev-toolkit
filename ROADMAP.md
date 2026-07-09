# v1.1.85 roadmap update - lib/install.sh Tier C completes install module

Status: **implemented — install module extraction complete (Tiers A–C)**.

v1.1.85 extends `lib/install.sh` with guided setup, quickstarts, and first-run wizard workflows.

Next active milestones:

1. **v1.1.86+ — extract config/access helpers or thin dispatcher (Phase B5)**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.84 roadmap update - lib/install.sh Tier B post-install summaries

Status: **implemented as the tenth careful modularization patch**.

v1.1.84 extends `lib/install.sh` with post-install checkpoint and summary helpers.

Next active milestone:

1. **v1.1.85 — install Tier C** (guided setup and quickstart workflows).

---

# v1.1.83 roadmap update - lib/install.sh Tier A extraction

Status: **implemented as the ninth careful modularization patch**.

v1.1.83 extracts the core install engine into `lib/install.sh` (preflight, packages, Frappe stack, repair, uninstall).

Completed in v1.1.83:

- Added `lib/install.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.84 — install Tier B** (post-install summaries and checkpoint).
2. **v1.1.85 — install Tier C** (guided setup and quickstart workflows).

---

# v1.1.82 roadmap update - lib/service.sh extraction

Status: **implemented as the eighth careful modularization patch**.

v1.1.82 extracts ERPNext systemd service management and runtime state helpers into `lib/service.sh`.

Completed in v1.1.82:

- Added `lib/service.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.83+ — extract install/setup helpers**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.81 roadmap update - lib/storage.sh extraction

Status: **implemented as the seventh careful modularization patch**.

v1.1.81 extracts root storage detection, status, and expansion helpers into `lib/storage.sh`.

Completed in v1.1.81:

- Added `lib/storage.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.82+ — extract install/setup helpers**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.80 roadmap update - lib/health.sh extraction

Status: **implemented as the sixth careful modularization patch**.

v1.1.80 extracts health monitoring, go-live validation, and production readiness helpers into `lib/health.sh`.

Completed in v1.1.80:

- Added `lib/health.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.81+ — extract storage or install/setup helpers**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.79 roadmap update - lib/apps.sh extraction

Status: **implemented as the fifth careful modularization patch**.

v1.1.79 extracts curated Frappe app profiles, install wizards, and compatibility helpers into `lib/apps.sh`.

Completed in v1.1.79:

- Added `lib/apps.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.80+ — extract health monitoring or install/setup helpers**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.78 roadmap update - lib/ssl.sh and lib/firewall.sh extraction

Status: **implemented as the fourth careful modularization patch**.

v1.1.78 extracts production and local SSL/HTTPS helpers into `lib/ssl.sh` and firewall/UFW/Fail2Ban helpers into `lib/firewall.sh`.

Completed in v1.1.78:

- Added `lib/ssl.sh` and `lib/firewall.sh` and wired `erpnext-dev.sh` to source them.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.79+ — continue thinning `erpnext-dev.sh` toward a dispatcher**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.77 roadmap update - lib/backup.sh extraction

Status: **implemented as the third careful modularization patch**.

v1.1.77 extracts local backup, off-VM backup, restore, and rehearsal helpers into `lib/backup.sh`.

Completed in v1.1.77:

- Added `lib/backup.sh` and wired `erpnext-dev.sh` to source it.
- Simplified `update-toolkit` to download all toolkit lib modules.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.78 — extract SSL/firewall helpers into dedicated lib modules**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.76 roadmap update - lib/support.sh extraction

Status: **implemented as the second careful modularization patch**.

v1.1.76 extracts doctor, support-bundle, support-bundle audit, and command-audit helpers into `lib/support.sh`.

Completed in v1.1.76:

- Added `lib/support.sh` and wired `erpnext-dev.sh` to source it.
- Expanded checksum, manifest, shellcheck, and update-toolkit coverage for the new module.

Next active milestones:

1. **v1.1.77 — extract backup/restore helpers into lib/backup.sh**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.75 roadmap update - lib/common.sh and shellcheck in CI

Status: **implemented as the first careful modularization patch**.

v1.1.75 extracts shared logging, locking, UI/menu helpers, prompts, and command helpers into `lib/common.sh`, and adds shellcheck to CI.

Completed in v1.1.75:

- Added `lib/common.sh` and wired `erpnext-dev.sh` to source it.
- Updated install/update reuse paths to copy or download the toolkit `lib/` tree.
- Added `scripts/run-shellcheck.sh`.
- Added shellcheck installation and execution to `.github/workflows/ci.yml`.
- Expanded `SHA256SUMS` and `RELEASE-MANIFEST.txt` for the new module and script.

Next active milestones:

1. **v1.1.76 — extract support/diagnostics module**.
2. **v1.1.77+ — extract backup/restore modules**.
3. Later: optional GPG-signed release artifacts.

---

# v1.1.74 roadmap update - release manifest, expanded checksums, and quality assessment

Status: **implemented as the fifth release-trust hardening patch after v1.1.70 through v1.1.73**.

v1.1.74 adds structured quality assessment documentation, a release manifest, expanded checksum coverage, and stronger automated release validation.

Completed in v1.1.74:

- Added `QUALITY-ASSESSMENT.md` with reliability, security, and ease-of-use evaluation.
- Added `RELEASE-MANIFEST.txt` and manifest validation in `scripts/validate-release.sh`.
- Added `scripts/generate-release-checksums.sh`.
- Expanded `SHA256SUMS` to cover `erpnext-dev.sh`, `scripts/validate-release.sh`, and `RELEASE-MANIFEST.txt`.
- Added version-consistency checks across `SCRIPT_VERSION`, README, CHANGELOG, and manifest header.
- Added `menu-self-test` and `production-ops-wizard` quit smoke tests to release validation.

Next active milestones:

1. **v1.1.75 — begin careful modularization planning with shellcheck in CI**.
2. Later: optional GPG-signed release artifacts.
3. Later: disposable VM integration testing.

---

# v1.1.73 roadmap update - support-bundle audit and package validation expansion

Status: **implemented as the fourth release-trust hardening patch after v1.1.70, v1.1.71, and v1.1.72**.

v1.1.73 adds support-bundle audit coverage and expands `scripts/validate-release.sh` with a clean support-bundle fixture.

Completed in v1.1.73:

- Added `support-bundle-audit`, `audit-support-bundle`, and `support-bundle-audit-test`.
- Added a Support and Diagnostics dashboard option for support-bundle auditing.
- Added forbidden filename checks for credential files, private keys, database backups, and private-file backup archives.
- Added obvious secret-pattern scanning for private key blocks, bearer tokens, and password/token-style assignments.
- Added support-bundle audit fixture validation to `scripts/validate-release.sh`.

Next active milestones:

1. **v1.1.74 — release package manifest and checksum expansion**.
2. **v1.1.75+ — begin careful modularization planning with CI as a safety net**.
3. Later: optional GPG-signed release artifacts.

Important limitation:

- The audit is best-effort. It reduces accidental sharing risk but does not replace manual review of support bundles before sending outside the organization.

---

# v1.1.72 roadmap update - minimal CI and validate-release script

Status: **implemented as the third release-trust hardening patch after v1.1.70 and v1.1.71**.

v1.1.72 adds `.github/workflows/ci.yml` and `scripts/validate-release.sh` so release checks can run consistently before tags are published.

Completed in v1.1.72:

- Added GitHub Actions workflow for push, pull request, and version-tag validation.
- Added `scripts/validate-release.sh`.
- Added syntax, version, checksum, help, `verify-toolkit`, package hygiene, and basic secret-pattern checks.
- Updated `verify-toolkit` guidance to use the stable `/opt/erpnext-dev` install path.
- Updated README, SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, CHANGELOG.md, and PRODUCTION-VALIDATION.md.

Next active milestones:

1. **v1.1.73 — support-bundle audit test and package validation expansion**.
2. **v1.1.74+ — begin careful modularization planning with CI as a safety net**.
3. Later: optional GPG-signed release artifacts.

Important limitation:

- The v1.1.72 CI is intentionally minimal. It does not run a full ERPNext install in CI. It catches release/package regressions before heavier VM-level tests are added.

# v1.1.71 roadmap update - verify-toolkit command

Status: **implemented as the second release-trust hardening patch after v1.1.70**.

v1.1.71 adds `verify-toolkit` so operators can report the active script hash, stable toolkit hash, CLI target hash, and checksum match status when `SHA256SUMS` is available. This builds on the v1.1.70 tag-pinned checksum bootstrap workflow.

Completed in v1.1.71:

- Added `verify-toolkit`, `toolkit-verify`, and `verify-install` aliases.
- Added checksum-file discovery with `CHECKSUM_FILE` override support.
- Added active/stable/CLI SHA256 reporting.
- Added match/mismatch reporting against `SHA256SUMS`.
- Added a Support and Diagnostics dashboard entry for toolkit verification.
- Updated README, SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, CHANGELOG.md, and PRODUCTION-VALIDATION.md.

Next active milestones:

1. **v1.1.72 — minimal GitHub Actions CI and `scripts/validate-release.sh`**.
2. **v1.1.73+ — support-bundle audit test and package validation expansion**.
3. Later: begin careful modularization only after release integrity and CI are in place.

Important limitation:

- `verify-toolkit` validates file integrity when a trusted checksum file is available. It does not prove maintainer identity. GPG-signed releases remain a later optional milestone.

---

# v1.1.70 roadmap update - SHA256 checksums and tag-pinned bootstrap docs

Status: **implemented as the first release-trust hardening patch after v1.1.69**.

v1.1.70 adds a `SHA256SUMS` release artifact for `erpnext-dev.sh` and updates the README to prefer tag-pinned downloads with checksum verification before `sudo` execution. This directly addresses the P0 bootstrap-trust gap identified in the security review.

Completed in v1.1.70:

- Added `SHA256SUMS` for the release script artifact.
- Updated install examples to use `VERSION="v1.1.70"` and release-tag raw URLs.
- Added `sha256sum -c SHA256SUMS` before script execution in bootstrap examples.
- Updated SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, CHANGELOG.md, and PRODUCTION-VALIDATION.md.
- Kept runtime behavior unchanged.

Next active milestones:

1. **v1.1.72 — minimal GitHub Actions CI and `scripts/validate-release.sh`**.
2. **v1.1.73+ — support-bundle audit test and package validation expansion**.
3. Later: begin careful modularization only after release integrity and CI are in place.

Important limitation:

- SHA256 checksums provide file integrity, not maintainer identity. GPG-signed releases can be added later for stronger supply-chain assurance.

---

# v1.1.69 roadmap update - security and reliability planning docs

Status: **implemented as a planning/documentation patch after v1.1.67/v1.1.68 production dashboard validation**.

The production VM operations path is now strong and field-tested. The next priority is release trust and automated regression prevention. v1.1.69 adds `SECURITY.md` and `RELIABILITY-PLAN.md` so the project has a clear, tracked plan for the next security and reliability milestones.

Completed in v1.1.69:

- Added `SECURITY.md` covering threat model, bootstrap trust, credential handling, support-bundle safety, root-script risk, and responsible reporting guidance.
- Added `RELIABILITY-PLAN.md` covering release validation automation, package checks, CI, support-bundle audit direction, and modularization sequencing.
- Updated README, TESTING, CHANGELOG, and PRODUCTION-VALIDATION to reference the new planning docs.
- Kept runtime behavior unchanged.

Next active milestones:

1. **v1.1.72 — minimal GitHub Actions CI and `scripts/validate-release.sh`**.
2. **v1.1.73+ — support-bundle audit test and package validation expansion**.
3. Later: begin careful modularization only after release integrity and CI are in place.

Rationale:

- The highest-priority risk is not the current ERPNext VM workflow; it is release trust when running downloaded code with `sudo`.
- CI should exist before major script modularization, otherwise refactoring risk is too high.
- Docker installation remains a separate later track after VM operations and release engineering remain stable.

---

# v1.1.68 roadmap update - final v1.1.67 dashboard validation record

Status: **documentation/validation patch completed after v1.1.67 production validation passed**.

The v1.1.67 Production Operations dashboard navigation polish is now validated on `erp.flowmaya.com`. The top-level dashboard shows only `q) Quit`, nested operator sections show `b) Back` and `q) Quit`, and breadcrumb titles make submenu context clear.

Completed and recorded in v1.1.68:

- v1.1.67 installed on the production VPS and reported by `erpnext-dev version`.
- Final QA option `1) Release readiness summary` passed with `Release state OK`.
- Redacted support bundle created after v1.1.67 validation: `/tmp/erpnext-dev-support-bundle-20260709-071549.tar.gz`.
- Health Monitoring breadcrumb validated: `ERPNext Production Operations > Health Monitoring`.
- Support and Diagnostics breadcrumb validated: `ERPNext Production Operations > Support and Diagnostics`.
- The validated production state remains unchanged: runtime, HTTPS, UFW, Fail2Ban, local backup, off-VM backup, restore rehearsal, health monitoring, and go-live validation remain OK.

Next active milestone: **safe status exports and optional notification design after production dashboard validation**.

Planned next items:

1. Keep the production dashboard read-only/status-first by default.
2. Consider a simple redacted status export command for sharing operational state without a full support bundle.
3. Consider health-check notification targets such as email or webhook only after defining safe defaults and avoiding noisy alerts.
4. Keep provider-side validation records explicit and repeatable after snapshot, firewall, DNS, or SSL changes.
5. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.67 roadmap update - production dashboard navigation polish

Status: **implemented as a UX polish patch after v1.1.66 field validation**.

The v1.1.66 production dashboard passed core routing validation on `erp.flowmaya.com`, but the smoke test exposed one usability issue: the top-level dashboard advertised `b) Back` even when opened directly, and nested menus did not visually show enough context. The v1.1.67 patch addresses that without changing the underlying production operations logic.

Completed in v1.1.67:

- Top-level `production-ops-wizard` now advertises only `q) Quit`.
- Nested Production Operations sections still advertise `b) Back` and `q) Quit`.
- Production Operations submenus now use breadcrumb-style titles.
- Health Monitoring receives the breadcrumb title when opened from the dashboard.
- Documentation and validation plans were updated.

Next active milestone: **operator polish and safe status exports after v1.1.67 production validation**.

Planned next items:

1. Install v1.1.67 on the production VPS and validate the navigation polish.
2. Keep the production dashboard read-only/status-first by default.
3. Consider a simple read-only status export later, after dashboard navigation remains stable.
4. Defer health notifications until the dashboard and health timer have more runtime history.
5. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.66 roadmap update - production operations dashboard

Status: **implemented as the unified operator-experience layer over the validated production toolkit commands**.

Completed in v1.1.66:

- Rebuilt `production-ops-wizard` into a top-level Production Operations dashboard.
- Added a current-state summary so operators can see runtime, HTTPS, security, backup, restore rehearsal, health monitoring, and go-live state before choosing an action.
- Grouped operational actions into clear areas: services, local backups, off-VM backups, restore readiness, health monitoring, security/firewall, HTTPS/certificates, go-live validation, and support/diagnostics.
- Added aliases: `production-ops-dashboard`, `operations-dashboard`, and `ops-dashboard`.
- Reused existing tested command implementations instead of duplicating business logic.

Next active milestone: **production dashboard field validation and polish**.

Planned next items:

1. Install v1.1.66 on the production VPS and validate dashboard option routing.
2. Confirm support/diagnostics dashboard flow creates and reviews the enhanced support bundle.
3. Decide whether to add notification targets for health checks, such as email or webhook.
4. Consider a read-only HTML/status export later, but keep the Bash toolkit stable first.
5. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.65 roadmap update - final production validation record

Status: **documentation/validation patch completed after the v1.1.64 production go-live workflow passed**.

The production path is now validated end to end across install, HTTPS, security baseline, local backups, off-VM backup, restore rehearsal, health monitoring, go-live confirmations, and redacted evidence bundle generation.

Completed and recorded in v1.1.65:

- v1.1.64 go-live validation record passed on `erp.flowmaya.com`.
- Named snapshot recorded: `erp-flowmaya-v1.1.64-final-validated-20260709`.
- Cloud firewall confirmation recorded.
- Cloudflare proxied DNS, Full (strict), and Origin CA confirmation recorded.
- Production checklist reports go-live validation as `OK`.
- Final QA option `9) Go-live validation status` passed.
- Enhanced support bundle includes production evidence files for backups, restore rehearsal, monitoring, go-live status, and checklist state.

Completed follow-up milestone: **v1.1.66 production operations dashboard / unified operations experience**.

Implemented v1.1.66 goals:

1. Provide a clean top-level production operations dashboard with concise current-state summaries.
2. Group health, services, backups, off-VM backup, restore readiness, monitoring, security, HTTPS, go-live validation, and support actions into a coherent operator flow.
3. Prefer status-first screens and suggested next actions so operators do not need to remember command names.
4. Keep existing CLI commands as stable direct entry points.
5. Avoid duplicating logic; the dashboard orchestrates existing tested commands.
6. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.64 roadmap update - go-live validation record and evidence bundle

Status: **implemented as the next production-readiness polish patch**.

The install, backup, off-VM backup, restore rehearsal, restore status tracking, and health monitoring paths are now validated. v1.1.64 focuses on the provider-side confirmations that must be recorded outside the guest VM.

Completed in v1.1.64:

- `go-live-record` for snapshot, provider firewall, and Cloudflare confirmation.
- `go-live-status` for saved go-live validation evidence.
- `cloud-firewall-checklist` and `cloudflare-checklist` as guided provider-side checklists.
- Production checklist and Final QA awareness of go-live validation.
- Enhanced support bundles with redacted production evidence files.

Next roadmap items:

1. Validate `go-live-record` on the production VPS after the named snapshot and provider-side settings are confirmed.
2. Decide whether to add notification targets for health checks, such as email or webhook.
3. Add longer-term operations dashboard/menu polish if the command surface becomes too large.
4. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.63 roadmap update - monitoring workflow

Status: **implemented as the next production-hardening patch**.

The restore and off-VM backup path is now validated. The current active focus is lightweight monitoring and operational visibility.

Completed in v1.1.63:

- Guided `health-monitoring-wizard`.
- Health check state record at `/etc/erpnext-dev/health-check.state`.
- Health timer schedule/delay prompts.
- Journal helper for health-check runs.
- Production checklist and Final QA awareness of monitoring state.

Next roadmap items:

1. Validate health timer on the production VPS.
2. Confirm Hetzner snapshot and provider firewall state.
3. Decide whether to add notification targets later, such as email/webhook, after local health timer behavior is stable.
4. Keep Docker installation as a later separate track after VM operations remain stable.

---

## v1.1.62 final production QA documentation record

Status: documentation/validation patch after final v1.1.61 production QA passed.

Completed production-readiness items now recorded:

- Production VPS install and runtime validation.
- Cloudflare Origin CA / Nginx HTTPS validation.
- UFW and Fail2Ban validation.
- Local backup and scheduled backup validation.
- Separate off-VM backup server validation.
- Real off-VM rsync dry run and real run validation.
- Disposable local restore VM rehearsal validation.
- Restore rehearsal record/status tracking validation.
- Final QA release readiness: `Release state OK ready for production use`.
- Redacted support bundle creation validation.

Updated readiness after final QA:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and stable |
| Public VPS guided production workflow | 9.5/10 | Real production path validated with HTTPS, security checks, backups, and final QA |
| Off-VM backup workflow | 9.4/10 | Separate backup server, real rsync run, cleanup, and dry-run revalidation passed |
| Restore rehearsal workflow | 9.4/10 | Disposable restore, login validation, cleanup, and production-side status tracking passed |
| Full production readiness | 9.5/10 | Remaining work is operational: cloud snapshot, provider firewall confirmation, Cloudflare setting confirmation, optional health timer |

Next active milestones:

1. Create/confirm named cloud provider snapshot after final validation.
2. Confirm provider-level firewall policy outside the VM.
3. Confirm Cloudflare DNS proxy state and SSL/TLS mode Full (strict).
4. Decide whether to enable the optional health timer.
5. Plan periodic restore drills after major upgrades, migrations, or backup-policy changes.

## v1.1.61 restore rehearsal status tracking

Status: focused production-readiness polish.

- Add restore rehearsal record/status/report commands.
- Update production checklist and final QA so completed restore rehearsals are recognized instead of repeatedly showing stale warnings.
- Store restore rehearsal metadata on the production VM in `/etc/erpnext-dev/restore-rehearsal.env`.
- Treat restore VM IP as optional evidence only, because local VM networking can change.
- Keep the next production hardening items focused on health timer monitoring, cloud snapshot policy, and periodic restore-drill repetition after major upgrades.

Updated readiness after v1.1.61:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and stable |
| Public VPS guided production workflow | 9.4/10 | Real production path validated |
| Off-VM backup workflow | 9.3/10 | Separate backup server and rsync dry/run validated |
| Restore rehearsal workflow | 9.1/10 | Restore works and now has record/status tracking |
| Full production readiness | 9.3/10 | Remaining items are operational: health timer, firewall policy confirmation, named snapshot policy |

## v1.1.60 completed restore rehearsal automation

Status: implementation package ready after successful local restore rehearsal.

- Added a guided restore rehearsal workflow for disposable local/cloud restore VMs.
- Added restore-key setup and backup-server temporary-key lifecycle commands.
- Added rsync pull helper for restore VMs.
- Improved restore-full to select the latest complete backup set by default.
- Improved database admin credential handling by using the local toolkit credentials file when available.
- Added restore VM preflight checks for resource sizing and Docker/Kubernetes/Calico conflicts.
- Documented the restore rehearsal workflow in the README menu and backup/restore section.

Updated readiness after restore rehearsal:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local development/testing use |
| Public VPS guided production workflow | 9.3/10 | Real production-candidate path validated with Let's Encrypt and Cloudflare Origin CA |
| Off-VM backup workflow | 9.2/10 | Real separate backup server and rsync copy validated |
| Restore rehearsal workflow | 8.7/10 | Local disposable VM restore passed; v1.1.60 reduces manual steps |
| Full production readiness | 9.2/10 | Core install, HTTPS, firewall, local/off-VM backups, and restore are proven; monitoring/snapshot policy remains operational |

Next milestones:

1. Complete browser/login validation on the restored local VM.
2. Remove the temporary restore key from the backup server.
3. Optionally configure the health timer for ongoing monitoring.
4. Add restore drill status tracking in a future patch if needed.

## v1.1.59 completed off-VM backup validation and onboarding polish

Status: real two-server off-VM backup validation passed.

- Confirmed dedicated SSH-key rsync from ERPNext VPS to a separate backup VPS.
- Confirmed backup files landed on the attached 200 GB backup volume.
- Confirmed `off-vm-backup-status` and `production-checklist` report the successful last off-VM run.
- Improved backup-server onboarding so the wizard tells the user to generate the ERPNext-side public key first.
- Improved Enter-to-accept defaults for backup root paths by detecting mounted Hetzner volumes.
- Improved status wording so the toolkit does not imply off-VM backup is still untested after a successful run.

Updated readiness target after validation:

- Local VM/developer workflow: 9.5/10, passed.
- Production VPS core workflow: 8.9/10, validated with Let’s Encrypt and Cloudflare Origin CA paths.
- Production backup/resilience workflow: 8.6/10, local backup + off-VM copy validated; restore rehearsal still required.

Active next milestone: rehearse restore from the off-VM backup on a disposable VM, then add optional health timer monitoring if needed.

## v1.1.58 completed guided off-VM backup setup foundation

Status: implementation package ready for validation.

- Added a backup-server command that can be pulled and run on a separate Linux backup server.
- Added ERPNext-side key generation and guided off-VM setup commands.
- Kept existing manual rsync target, dry-run, real-run, and status commands.
- Remaining readiness movement requires real two-server validation: dry run, real off-VM run, backup-server file verification, and restore rehearsal.

Updated readiness target after validation:

- Local VM/developer workflow: 9.3/10, passed.
- Production VPS core workflow: 8.7/10, validated with Let’s Encrypt and Cloudflare Origin CA paths.
- Production backup/resilience workflow: pending off-VM backup and restore rehearsal validation.

## v1.1.57 completed Cloudflare Origin CA validation record

- Recorded successful Cloudflare Origin CA / Full (strict) validation on the real Hetzner VPS production path.
- Confirmed Cloudflare orange-cloud/proxied DNS can be handled safely after the v1.1.56 guided DNS gate fix.
- Confirmed both production HTTPS paths are now validated:
  - Let's Encrypt direct DNS-only path: validated.
  - Cloudflare Origin CA / Full (strict): validated.
- Confirmed the production hardening follow-up after an interrupted guided flow: UFW active, Fail2Ban sshd jail enabled, scheduled local backups active, external backend ports blocked.

Current ratings after Cloudflare validation:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local development/testing use |
| Public VPS guided production workflow | 8.8/10 | Core production path validated on real Hetzner VPS with both Let's Encrypt and Cloudflare Origin CA HTTPS paths |
| Production HTTPS choices | 9.0/10 | Let's Encrypt direct DNS and Cloudflare Origin CA Full strict paths validated |
| Backup + restore foundation | 9.0/10 | Local backups and readable verification pass; production restore rehearsal still required |
| Off-VM backup / production monitoring | 6.0/10 | Planning and local timers exist; real off-VM target, real copy, restore rehearsal, and optional health timer remain open |

Active next milestone: validate off-VM backup target configuration, off-VM backup dry run/real run, and disposable-VM restore rehearsal. Avoid broad feature work until backup survivability is validated.

## v1.1.56 completed Cloudflare proxied DNS guided setup fix

- Fixed the guided production DNS gate so Cloudflare orange-cloud/proxied DNS can continue through the Cloudflare Origin CA path instead of failing because public DNS returns Cloudflare edge IPs.
- Kept Let's Encrypt as the default when DNS points directly to the VM.
- Remaining validation: run a clean guided Cloudflare Origin CA install from a fresh/rollback VPS and confirm final QA after proxy + Full (strict).

# Roadmap

## v1.1.55 completed production VPS validation record and polish fixes

- Recorded the successful fresh Hetzner VPS production validation with Ubuntu 26.04 LTS, real DNS, Let’s Encrypt HTTPS, UFW, Fail2Ban, scheduled local backups, external backend-port blocking, browser login testing, support bundle, and post-validation snapshot.
- Fixed UFW status wording/parser so explicit backend `DENY` rules are not reported as false allow warnings.
- Improved production access wording so `:8000` URLs are clearly troubleshooting/backend validation URLs, not normal public production access.
- Documented the interactive-menu shell behavior: commands pasted after `final-qa` run after the menu exits.

Updated readiness after real VPS validation:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local development/testing use |
| Core public VPS guided production path | 8.4/10 | Passed on fresh Hetzner VPS with real domain, Let’s Encrypt, UFW, Fail2Ban, backups, and external port checks |
| Backup + restore foundation | 9.0/10 local / 7.5/10 production | Local restore passed; production restore still needs disposable-VM rehearsal |
| Final QA and support bundle | 9.0/10 | Passed on local and production validation paths; support bundle contents reviewed |
| Off-VM backup / production monitoring | 5.8/10 | Planning and local timers exist; real off-VM target and health timer validation remain open |
| Cloudflare Origin CA SSL path | 9.0/10 | Validated through Cloudflare orange-cloud/proxied DNS with Origin CA and Full (strict) |

Active next milestone: validate off-VM backup target, off-VM backup dry run/real run, and disposable-VM restore rehearsal.

## v1.1.52 completed production guided setup UX fix

- Kept the existing Public VM menu for manual and advanced production tasks.
- Added `public-vm-guided-setup` as the README production bootstrap target.
- Routed the general setup wizard's Public VM path to the new guided production flow.
- The guided flow now walks the user through domain, DNS readiness, external cloud firewall/snapshot confirmation, install, backup checkpoint, HTTPS, production security profile, Fail2Ban, scheduled backups/off-VM backup review, optional apps, Final QA, support bundle, and post-validation snapshot reminder.
- Updated production validation documentation to allow Ubuntu 24.04 LTS or Ubuntu 26.04 LTS.

Active next milestone: continue real VPS/domain validation with the new guided production command.

## v1.1.51 completed production VPS validation handoff documentation

- Closed the local VM validation stage after v1.1.50 confirmed the final Local SSL firewall-guidance fix.
- Added a documented requirement that the next production-validation stage must use a fresh disposable VPS and a real test subdomain.
- Added the production VPS validation order: DNS, cloud firewall, clean snapshot, public quickstart, production firewall, Let's Encrypt HTTPS, external port exposure checks, backups, scheduled backups, production checklist, Final QA, and post-validation snapshot.
- Added readiness ratings so local/dev readiness is separated from production readiness.
- Added `PRODUCTION-VALIDATION.md` as the dedicated handoff checklist for the next test session.

Current ratings after local validation:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local development/testing use |
| Backup + restore foundation | 9.0/10 | Passed locally; production restore still requires disposable-VM rehearsal |
| Final QA and support bundle | 8.8/10 | Passed locally; production warnings are expected until VPS validation |
| Public VPS production-candidate workflow | 6.5/10 | Implemented but must be validated on real VPS + domain before production confidence rises |
| Off-VM backup / production monitoring | 5.5/10 | Workflows exist, but real target/timer validation remains open |

Active next milestone: **v1.1.52+ Production VPS validation**.

Required test environment:

```text
Fresh disposable Ubuntu 24.04 LTS or Ubuntu 26.04 LTS VPS
Public IPv4
Real test subdomain, for example erp-test.example.com
Cloud firewall control
Snapshot capability
SSH access from admin IP
```

The next milestone should not add broad new features until the real VPS path is tested end to end.

## v1.1.50 completed Local SSL firewall-guidance polish

- Fixed `verify-local-ssl` follow-up guidance so it no longer recommends applying the Local VM security profile when UFW is already active.
- Added a safe default for the internal `SUDO` command prefix so UFW/helper status checks do not falsely fail before `require_sudo` initializes it.
- `verify-local-ssl` now requires sudo explicitly, matching the protected nginx/UFW checks it performs.

## v1.1.49 completed Final QA/local-stage polish

- Final QA release notes now use the current toolkit version dynamically and no longer overstate untested production paths.
- Added `scheduled-backup-status` as a friendly alias for `backup-schedule-status`.
- Scheduled-backup disable now reports missing/unconfigured timers clearly and points users to configure/status commands.
- Local VM development workflow is now considered passed for install, local HTTPS, optional apps, backup/restore, scheduled backups, retention dry run, maintenance basics, and Final QA.
- Next major stage: production VM validation, including production domain, Let's Encrypt/Cloudflare SSL, cloud firewall, Fail2Ban, off-VM backup, health timer, and production operations.

## v1.1.48 completed restore and local HTTPS polish

- Post-restore maintenance now keeps the terminal readable by saving verbose migrate/build/cache output to step-specific log files.
- The ERPNext Ready screen now prioritizes HTTPS Desk/Login/Website URLs when local HTTPS is configured.
- Local HTTPS verification now detects an already-active Local VM firewall profile and avoids telling the user to apply it again.
- Local Firewall Access Check now includes an HTTPS host-side test when local SSL is configured.
- Remaining backup work: scheduled backup activation, retention cleanup validation, off-VM backup rehearsal, and disposable-VM restore testing.

## v1.1.47 completed restore UX and post-restore sequencing

- Restore prompts now use database-admin wording instead of MySQL/root wording.
- Restore flow reminds users to have the MariaDB Bench Admin credential ready before continuing.
- Restore now passes the toolkit database admin user/password to Bench restore.
- Post-restore maintenance now starts/waits for ERPNext services before running migrate, build, and cache cleanup.
- Remaining backup work: scheduled backup activation, retention cleanup validation, off-VM backup rehearsal, and disposable-VM restore testing.

## v1.1.46 completed README version hygiene

- Removed the stale hard-coded version from the README heading.
- The README now points users to `erpnext-dev version` for the installed toolkit version, avoiding future documentation drift.

## v1.1.45 completed app-status comparison hardening

- Replaced the app comparison temp scripts with a safer local comparison flow using downloaded, installed, and registered app lists.
- `app-status` and Advanced Tools -> Installed apps should now show `none` cleanly when every downloaded app is installed and registered.
- The optional-app workflow is considered passed after full batch install/browser testing, pending final backup/checkpoint review.

## v1.1.44 completed optional-app status polish

- Fixed optional-app status comparison output after large app batches.
- `app-status` should no longer show temporary shell syntax errors in the downloaded-but-not-installed or downloaded-but-not-registered sections.
- App wizard preflight now separates installed state from branch repeatability notes so working apps installed from `main`, `develop`, or default branches do not look failed.

## v1.1.37 completed README first-run UX cleanup

- The README now starts with the real local, production, guided menu, preflight, and update commands before explaining bootstrap internals.
- The `/tmp` bootstrap note is preserved but moved below the copyable commands.
- Local host DNS mapping instructions now emphasize dynamic VM IP detection and toolkit-generated host commands rather than static sample IPs.

## v1.1.36 completed menu navigation hardening

- All interactive menu prompts now use a shared input reader.
- `q`/`Q` quits consistently, `b`/`B` goes back where supported, and full words such as `quit`, `exit`, and `back` are normalized.
- Added a non-destructive `menu-self-test` command to validate top-level menus, submenus, and common nested menu paths before release.
- This reduces the risk of a submenu crash causing later typed menu numbers to be interpreted by the shell as commands.

## v1.1.35 completed local DNS/access root fix

- Local VM host mapping now uses dynamic VM IP detection instead of assuming a fixed `192.168.122.x` address.
- Added local domain status, local access doctor, and host DNS guide commands.
- Access and Local SSL menus now expose local DNS/host mapping diagnostics.
- The setup flow now treats host `/etc/hosts` mapping as a first-class local VM step, while still reminding users that the script cannot directly edit the separate host machine from inside the guest VM.

## v1.1.34 completed security profile and setup lifecycle hardening

- Added separate Local VM and Production firewall profiles.
- Added local access repair for over-hardened `.test` VMs.
- Added firewall rollback snapshots before UFW changes.
- Added setup lifecycle guidance for local and production installs.
- Added post-core and post-app backup checkpoints.

# Roadmap

## v1.1.33 completed local domain workflow

- Local quickstart now asks for the local VM domain at the beginning and defaults to `erp.test` when the user presses Enter.
- Existing installs now have a guided `change-local-domain` workflow that backs up, renames the Frappe site, updates Bench/toolkit config, and prompts for local SSL rebuild.


This roadmap is focused on making the ERPNext Developer Toolkit mature enough to install, manage, monitor, secure, back up, and maintain ERPNext/Frappe VMs reliably.

The current priority remains the **VM-based installer and production operations toolkit**. A Docker-based ERPNext/Frappe installation method is planned as a separate future track, but it should not distract from hardening the VM workflow first.

---

## v1.1.32 HTTPS menu baseline

The command naming baseline is `erpnext-dev.sh` for the bootstrap file and `erpnext-dev` for day-to-day operations. Local VM HTTPS / SSL, Production HTTPS / SSL, and Optional Apps are first-level menu actions after installation. Local HTTPS and production HTTPS must remain separate workflows with separate submenus, status checks, and rollback guidance. Future roadmap items should refer to the project as the ERPNext Developer Toolkit, not only an installer.

---

## Roadmap principles

- **VM reliability first:** the current installer must become a dependable production VM management toolkit before adding another install method.
- **Safe operations:** prefer preflight checks, dry-runs, summaries, confirmations, and rollback guidance before any risky action.
- **Separation of concerns:** installation, backup, restore, monitoring, security, updates, diagnostics, and documentation should each have clear commands.
- **Production clarity:** every command should clearly say whether it is intended for local testing, public production, or restore rehearsal.
- **Generic provider support:** avoid locking the workflow to one cloud provider; document provider-specific examples only as examples.
- **Docker later:** Docker support should be a separate approach with separate assumptions, backup logic, and operational checks.

---

## Current baseline

The current VM installer already covers the core install path and many first-layer operations.

Completed or available:

- Local VM quickstart using `.test` domains such as `erp.test`.
- Public VPS/cloud VM quickstart using a real domain or subdomain.
- Reusable toolkit command `erpnext-dev` backed by `/opt/erpnext-dev/erpnext-dev.sh`.
- ERPNext/Frappe install, runtime checks, and access verification.
- Local SSL guide and mkcert workflow.
- Production SSL paths, including Cloudflare Origin CA and public HTTPS checks.
- Firewall hardening, UFW status, and Fail2Ban checks.
- Local backups, backup verification, backup status, retention planning, and cleanup.
- Off-VM rsync backup configuration, dry-run, run, and status.
- Production health check and optional local health-check timer.
- Credentials-info helper and safer credential handling.
- Optional app wizard and compatibility checks.
- Diagnostics, `doctor`, command audit, and redacted support bundles.
- README start-here section, architecture diagrams, testing docs, and changelog separation.

Main gaps before calling the production VM operations mature:

- Better log review and failure diagnostics.
- More complete backup capacity planning and remote target checks.
- Safer restore rehearsal workflows.
- Update/upgrade preflight and controlled maintenance workflow.
- Alerting, notifications, and repeated monitoring beyond local status checks.
- Stronger VM security audit and hardening recommendations.
- Production maintenance reports for handover and ongoing operations.

---

## Active direction: production VM maturity

### Phase 1 — production diagnostics and maintainability

Goal: make it easy to understand the state of the VM and identify issues quickly.

Planned work:

- **Log review and diagnostics**
  - Add commands to review ERPNext, supervisor/systemd, Nginx, MariaDB, Redis, backup, and SSL-related logs.
  - Provide compact summaries instead of dumping large logs by default.
  - Include safe copy/paste modes for support.

- **VM state report**
  - Produce a single management report with site name, domain, services, ports, disk, memory, backup state, SSL state, firewall state, and health status.
  - Keep secrets redacted.

- **Maintenance dashboard / operations menu refinement**
  - Improve the production operations menu into a clear maintenance console.
  - Group tasks by Health, Backups, Restore, SSL, Security, Updates, Apps, and Diagnostics.

- **Backup capacity planning**
  - Estimate current complete-backup size.
  - Estimate required space for 3, 7, 14, and custom retention counts.
  - Warn when local or remote storage is too small for the configured policy.

Candidate commands:

```bash
sudo erpnext-dev log-review
sudo erpnext-dev vm-state-report
sudo erpnext-dev maintenance-dashboard
sudo erpnext-dev backup-size-estimate
sudo erpnext-dev backup-capacity-plan
```

---

### Phase 2 — backup and restore maturity

Goal: make backups trustworthy, testable, and easier to restore on a disposable VM.

Planned work:

- **Off-VM target improvements**
  - Support SSH port selection for storage boxes and providers that do not use port 22.
  - Improve SSH key guidance and remote directory checks.
  - Add remote free-space and permission checks.

- **Object storage track**
  - Add future support for `rclone`-based targets such as S3-compatible storage, Backblaze B2, Wasabi, or other object storage.
  - Keep this separate from rsync so each target type has a clear workflow.

- **Restore rehearsal workflow**
  - Guide restore testing on a separate VM, not on production.
  - Validate backup files, site name, database restore, files restore, app availability, and login.

- **Backup reports**
  - Show newest backup, backup age, complete set status, storage use, off-VM sync status, and restore-test status.

Candidate commands:

```bash
sudo erpnext-dev configure-rsync-backup-target
sudo erpnext-dev off-vm-capacity-check
sudo erpnext-dev configure-object-backup-target
sudo erpnext-dev restore-rehearsal-wizard
sudo erpnext-dev backup-report
```

---

### Phase 3 — monitoring, alerting, and security hardening

Goal: move from manual checks to reliable ongoing monitoring and practical security posture checks.

Planned work:

- **Monitoring and alerts**
  - Continue local health checks.
  - Add optional alert targets such as email/webhook later.
  - Track failures for services, HTTPS, disk usage, stale backups, and off-VM backup failures.

- **Service recovery planning**
  - Keep automatic recovery conservative.
  - Prefer status, guidance, and manual confirmation before restarting critical services.
  - Add optional controlled restart helpers where safe.

- **Security audit**
  - Review SSH exposure, root login status, password auth, UFW, Fail2Ban, open ports, Nginx exposure, SSL status, unattended upgrades, and reboot requirements.
  - Provide clear recommended fixes without applying destructive changes silently.

- **Patch/reboot awareness**
  - Detect pending security updates and required reboot.
  - Provide maintenance-window guidance.

Candidate commands:

```bash
sudo erpnext-dev monitoring-status
sudo erpnext-dev configure-alerts
sudo erpnext-dev security-audit
sudo erpnext-dev patch-status
sudo erpnext-dev reboot-plan
```

---

### Phase 4 — production lifecycle and updates

Goal: make production maintenance safer and more repeatable.

Planned work:

- **Update preflight**
  - Check disk space, backups, app branches, uncommitted customizations, service state, Python/Node/MariaDB compatibility, and snapshot recommendation before updates.

- **Controlled update workflow**
  - Guide through backup, snapshot reminder, app compatibility check, update, migrate, build, restart, and post-update validation.

- **App and customization inventory**
  - Report installed apps, branches, versions, custom apps, and potential compatibility risks.

- **Production handover report**
  - Generate a redacted operations report for client/internal handover.

Candidate commands:

```bash
sudo erpnext-dev update-preflight
sudo erpnext-dev safe-update-wizard
sudo erpnext-dev app-inventory
sudo erpnext-dev production-report
```

---

### Phase 5 — multi-VM and migration support

Goal: support more realistic operations where local, staging, restore, and production VMs coexist.

Planned work:

- Local-to-production planning.
- Production-to-restore VM validation.
- Staging VM update testing.
- Configuration export/import for installer settings.
- Multi-site awareness where appropriate.

Candidate commands:

```bash
sudo erpnext-dev config-export
sudo erpnext-dev config-import
sudo erpnext-dev staging-plan
sudo erpnext-dev migration-plan
```

---

## Later track: Docker-based ERPNext/Frappe installation

Docker support is planned, but it should be treated as a separate install and operations approach. It should not replace or complicate the current VM-based installer.

Planned Docker research and implementation items:

- Review the official ERPNext/Frappe Docker deployment path.
- Define supported Docker scenarios:
  - local Docker test environment,
  - single-server production Docker deployment,
  - reverse proxy and HTTPS with a real domain,
  - backup and restore for Docker volumes and database containers,
  - app installation and updates in a containerized stack.
- Compare Docker vs VM-native stack:
  - resource use,
  - operational complexity,
  - backup/restore approach,
  - update strategy,
  - troubleshooting experience,
  - production reliability.
- Build a separate Docker quickstart only after the VM production-operations workflow is mature enough.

Possible future commands:

```bash
sudo erpnext-dev docker-plan
sudo erpnext-dev docker-local-quickstart
sudo erpnext-dev docker-production-quickstart
sudo erpnext-dev docker-backup-plan
```

Target status: **later agenda item**.

---

## Near-term priority order

Recommended next patches:

1. **v1.1.13 — Log review and diagnostics**
   - Add compact log summaries and safe support output.

2. **v1.1.14 — VM state report and maintenance dashboard**
   - Add one command to show the complete operational state of the VM.

3. **v1.1.15 — Backup capacity and remote target preflight**
   - Estimate backup growth and validate remote storage before relying on it.

4. **v1.1.16 — Security audit and patch/reboot status**
   - Make VM security and maintenance posture easier to review.

5. **v1.2.0 — Restore rehearsal workflow**
   - Mature backup confidence by testing restores on a disposable VM.

6. **v1.2.x — Object storage backup target**
   - Add rclone/object-storage support after rsync flow is stable.

Docker work should start only after these VM production operations are stable.

---

## Definition of production-operations maturity

The VM track can be considered mature when the installer can clearly answer these questions:

- Is ERPNext running and reachable?
- Is HTTPS healthy?
- Are only intended ports exposed?
- Are local backups complete and recent?
- Are off-VM backups configured and recent?
- Is there enough storage for the retention policy?
- Has a restore rehearsal been completed recently?
- Are services healthy?
- Are logs clean enough or are there actionable warnings?
- Are security basics in place?
- Are updates pending?
- Is a reboot required?
- Is there a safe update plan?
- Can a redacted support bundle/report be generated?

Once these are reliably covered, the VM-based installer will be ready for broader production use and the Docker track can be started with a stable operations model already established.


## Local dev host mapping checkpoint

- Local development setup now treats host `/etc/hosts` mapping as a required checkpoint before local HTTPS.
- Future host-side companion tooling may automate KVM/libvirt DHCP reservations and host `/etc/hosts` updates directly from the host.
