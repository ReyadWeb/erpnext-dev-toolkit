# Roadmap

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
