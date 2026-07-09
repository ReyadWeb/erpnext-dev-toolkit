# v1.1.73 production validation notes

v1.1.73 is a release-engineering and support-safety patch. It adds `support-bundle-audit` and expands `scripts/validate-release.sh` with a clean support-bundle audit fixture.

Production validation should confirm:

```bash
VERSION="v1.1.73"
# verified tag-pinned update using SHA256SUMS
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
sudo erpnext-dev support-bundle-audit
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.73`.
- `verify-toolkit` reports Active/Stable/CLI match OK.
- Final QA option 1 reports release state OK.
- Support bundle is created.
- `support-bundle-audit` reports `Audit result OK` for the newest bundle.

Runtime/install/backup/restore/SSL/firewall/health/go-live behavior is unchanged.

---

## v1.1.72 validation note - minimal CI and release validation

v1.1.72 is a release-engineering patch. It adds `.github/workflows/ci.yml` and `scripts/validate-release.sh`, and updates the `verify-toolkit` update example to use the stable installed path.

Production runtime behavior is unchanged from the already validated path:

- ERPNext install/runtime logic unchanged.
- HTTPS/Cloudflare Origin CA logic unchanged.
- UFW and Fail2Ban logic unchanged.
- Local backup, off-VM backup, restore rehearsal, health monitoring, go-live validation, and dashboard behavior unchanged.

Recommended production validation after installing v1.1.72:

```bash
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
sudo erpnext-dev final-qa
```

Inside Final QA, choose option `1` and confirm `Script version INFO 1.1.72` and `Release state OK ready for production use`.

# v1.1.71 verify-toolkit command

v1.1.71 is a release-trust hardening patch. It adds a read-only `verify-toolkit` command that reports installed toolkit paths, SHA256 values, and checksum match status when `SHA256SUMS` is available.

## Production behavior impact

```text
Install behavior: unchanged
Backup behavior: unchanged
Restore behavior: unchanged
SSL behavior: unchanged
Firewall/security behavior: unchanged
Health monitoring behavior: unchanged
Go-live validation behavior: unchanged
Dashboard behavior: support menu adds toolkit verification entry only
```

## Why this patch exists

v1.1.70 added tag-pinned downloads and checksum verification before install. v1.1.71 adds the matching post-install visibility command so an operator can verify what is currently installed or active on a VM.

## Validation commands

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
sha256sum -c SHA256SUMS
./erpnext-dev.sh verify-toolkit
printf '10\n10\n\nb\nq\n' | sudo ./erpnext-dev.sh production-ops-wizard
```

Expected version:

```text
ERPNext Developer Toolkit v1.1.71
```

Expected checksum result:

```text
erpnext-dev.sh: OK
Active match                 OK      active script matches SHA256SUMS
```

## Result

v1.1.71 should be treated as a release-trust hardening patch, not a production operations feature patch. Production alignment requires a verified tag-pinned update, `verify-toolkit`, and Final QA option 1.

---

# v1.1.70 SHA256 checksums and tag-pinned bootstrap documentation

v1.1.70 is a release-trust documentation/checksum patch. It adds `SHA256SUMS` for `erpnext-dev.sh` and updates the README to prefer pinned release-tag downloads with checksum verification before running the toolkit with `sudo`.

## Production behavior impact

```text
Install behavior: unchanged
Backup behavior: unchanged
Restore behavior: unchanged
SSL behavior: unchanged
Firewall/security behavior: unchanged
Health monitoring behavior: unchanged
Go-live validation behavior: unchanged
Dashboard behavior: unchanged
```

## Why this patch exists

The production path is already validated. The remaining P0 security gap is release trust during bootstrap. v1.1.70 starts closing that gap by making the recommended production bootstrap workflow tag-pinned and checksum-verified.

## Validation commands

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
sha256sum -c SHA256SUMS
grep -n "sha256sum -c SHA256SUMS" README.md SECURITY.md TESTING.md
```

Expected version:

```text
ERPNext Developer Toolkit v1.1.70
```

Expected checksum result:

```text
erpnext-dev.sh: OK
```

## Result

v1.1.70 should be treated as a release-trust hardening patch, not a production operations feature patch. Production alignment requires only a version check and Final QA option 1.

---

# v1.1.69 Security and reliability planning documentation

v1.1.69 is a documentation/planning patch created after v1.1.67 and v1.1.68 completed the Production Operations dashboard validation record. It adds `SECURITY.md` and `RELIABILITY-PLAN.md` and does not change production runtime behavior.

## Production behavior impact

```text
Install behavior: unchanged
Backup behavior: unchanged
Restore behavior: unchanged
SSL behavior: unchanged
Firewall/security behavior: unchanged
Health monitoring behavior: unchanged
Go-live validation behavior: unchanged
Dashboard behavior: unchanged
```

## Why this patch exists

The production path is now validated with runtime, HTTPS, UFW, Fail2Ban, local backups, off-VM backups, restore rehearsal, health monitoring, go-live validation, and the Production Operations dashboard. The remaining major gap is release trust and automated regression prevention.

v1.1.69 records the next hardening direction:

```text
v1.1.70: SHA256 checksums and tag-pinned bootstrap docs
v1.1.71: verify-toolkit command
v1.1.72: minimal CI and release validation script
Later: modularization after CI exists
```

## Validation commands

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
ls -1 SECURITY.md RELIABILITY-PLAN.md
grep -n "v1.1.69" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
```

Expected version:

```text
ERPNext Developer Toolkit v1.1.69
```

## Result

v1.1.69 should be treated as a repository governance and release-hardening planning patch, not as a production operations feature patch.

---

# v1.1.68 Final v1.1.67 production dashboard validation record

v1.1.68 records the completed field validation of the v1.1.67 Production Operations dashboard navigation polish on the real `erp.flowmaya.com` production VPS. This is a documentation/validation patch apart from the version bump.

## Validated production evidence

```text
Toolkit validated on production: v1.1.67
Production site: erp.flowmaya.com
Final QA: Release state OK, ready for production use
Support bundle: /tmp/erpnext-dev-support-bundle-20260709-071549.tar.gz
Top-level dashboard footer: q) Quit only
Health Monitoring breadcrumb: ERPNext Production Operations > Health Monitoring
Support and Diagnostics breadcrumb: ERPNext Production Operations > Support and Diagnostics
```

## Production state during validation

The Final QA summary on v1.1.67 reported the production release state as OK. The following areas remained healthy during validation:

```text
Install: OK
Runtime: OK, running via service
HTTPS: OK, Cloudflare Origin CA/Nginx HTTPS responding HTTP/2 200
UFW: OK, active
Fail2Ban: OK, sshd jail enabled
Latest backup: OK, complete
Restore rehearsal: OK, completed and login validated
Health monitoring: OK, timer active and last check OK
Go-live validation: OK, snapshot/firewall/Cloudflare/origin cert confirmations recorded
```

## Support bundle evidence

The v1.1.67 validation bundle was created at:

```text
/tmp/erpnext-dev-support-bundle-20260709-071549.tar.gz
```

It includes redacted operational evidence files such as:

```text
go-live-status.txt
health-check-status.txt
restore-rehearsal-status.txt
off-vm-backup-status.txt
backup-verify.txt
backup-status.txt
production-checklist.txt
recent-errors.txt
bench-status.txt
ssl-status.txt
storage-status.txt
port-status.txt
service-status.txt
system-summary.txt
doctor-json-validation.txt
doctor.json
doctor-plain.txt
manifest.txt
```

## Result

The v1.1.67 dashboard navigation polish is fully production-validated. The remaining future work is not a go-live blocker: safe status exports, optional health notifications, and later Docker-track work should be handled as separate milestones.

---

# v1.1.67 Production dashboard navigation polish validation plan

v1.1.67 is a UX/navigation patch on top of the already validated v1.1.66 Production Operations dashboard. The validated production state remains unchanged: runtime, HTTPS, security baseline, local backup, off-VM backup, restore rehearsal, health monitoring, go-live validation, and support bundle evidence were already passing.

## Field finding from v1.1.66

During the v1.1.66 smoke test, the dashboard opened correctly and showed all key production-state rows as OK. Option `6) Health monitoring` opened the Health Monitoring submenu; selecting `9` there produced `WARN: Invalid option` because the operator was inside the submenu, not the main dashboard. After returning to the main dashboard, option `9) Go-live validation`, option `10) Support and diagnostics`, and option `11) Final QA` routed correctly.

## v1.1.67 fix

- Top-level Production Operations dashboard shows only `q) Quit`.
- Nested sections show `b) Back` and `q) Quit`.
- Nested sections use breadcrumb titles such as `ERPNext Production Operations > Health Monitoring`.

## Production validation commands

After installing v1.1.67 on production:

```bash
sudo erpnext-dev production-ops-wizard
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
```

Validate:

```text
Top-level dashboard footer: q) Quit only
6) Health monitoring: breadcrumb title and b) Back work
10) Support and diagnostics: breadcrumb title and b) Back work
11) Final QA: opens as before
Final QA option 1: release state OK
Support bundle: created and still includes evidence files
```

---

# v1.1.66 Production operations dashboard validation plan

v1.1.66 adds the unified Production Operations dashboard. The core production path was already validated through v1.1.64/v1.1.65; this patch focuses on operator experience and safe command routing.

## Package validation

```text
Toolkit version: 1.1.66
Syntax check: passed
Dashboard command: production-ops-wizard
Dashboard aliases: production-ops-dashboard, operations-dashboard, ops-dashboard
Package contains GITHUB-UPDATE files: no
```

## Dashboard design

The dashboard shows a compact current-state summary before any operator action:

```text
Runtime
Install
HTTPS
Security
Local backup
Off-VM backup
Restore rehearsal
Health monitoring
Go-live validation
```

The action groups are:

```text
1) System health and readiness
2) Services and recovery
3) Local backups
4) Off-VM backups
5) Restore readiness and rehearsal
6) Health monitoring
7) Security and firewall
8) HTTPS and certificates
9) Go-live validation
10) Support and diagnostics
11) Final QA
```

## Production validation commands

After installing v1.1.66 on the production VPS, run:

```bash
sudo erpnext-dev production-ops-wizard
sudo erpnext-dev operations-dashboard
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
```

Expected result: the dashboard opens, shows the current production state, nested sections route to mature commands, and `q` exits cleanly without changing production state.

---

# v1.1.65 Final v1.1.64 production validation record

This section records the final field evidence collected after v1.1.64 was installed on the production ERPNext VPS and its go-live validation workflow was completed. v1.1.65 is documentation-only apart from the version bump; it does not change production behavior.

## Validated environment

```text
Toolkit version under field validation: 1.1.64
Documentation/package version recording evidence: 1.1.65
Production site: erp.flowmaya.com
Production VPS: 65.109.221.4
Backup server: 65.109.220.250
Off-VM target: erpbackup@65.109.220.250:/mnt/HC_Volume_106276869/erpnext-backups/erp.flowmaya.com/
Restored backup set: 20260709_055928-erp_flowmaya_com
Restore target: local-vm/local-kvm-restore-vm
Restore target IP/address: evidence only and may change with network changes
Snapshot: erp-flowmaya-v1.1.64-final-validated-20260709
Go-live record time: 2026-07-09T06:27:12+00:00
Final evidence bundle: /tmp/erpnext-dev-support-bundle-20260709-062951.tar.gz
```

## Go-live validation evidence

The production VPS reported:

```text
Go-live validation           OK      recorded 2026-07-09T06:27:12+00:00; snapshot erp-flowmaya-v1.1.64-final-validated-20260709; cloud firewall confirmed; Cloudflare proxied; Full strict confirmed; origin cert confirmed
```

Recorded metadata included:

```text
GO_LIVE_STATUS=OK
GO_LIVE_RECORDED_AT=2026-07-09T06:27:12+00:00
GO_LIVE_SITE=erp.flowmaya.com
GO_LIVE_SNAPSHOT_CONFIRMED=true
GO_LIVE_SNAPSHOT_NAME=erp-flowmaya-v1.1.64-final-validated-20260709
GO_LIVE_CLOUD_FIREWALL_CONFIRMED=true
GO_LIVE_CLOUDFLARE_PROXY_CONFIRMED=true
GO_LIVE_CLOUDFLARE_FULL_STRICT_CONFIRMED=true
GO_LIVE_CLOUDFLARE_ORIGIN_CERT_CONFIRMED=true
GO_LIVE_NOTES=snapshot-firewall-cloudflare-confirmed
GO_LIVE_RECORDED_BY_TOOLKIT_VERSION=1.1.64
```

## Production checklist evidence

The production checklist recognized the complete go-live record and reported all of the following as healthy during validation:

```text
Install                      OK      Installed
Runtime                      OK      Running via service
HTTPS                        OK      Cloudflare Origin CA/Nginx HTTPS responding: HTTP/2 200
UFW                          OK      active
Fail2Ban                     OK      sshd jail enabled
Local backups                OK      off-VM copy verified
Scheduled backups            OK      local timer active
Off-VM backup                OK      configured; last run OK
Restore rehearsal            OK      completed; login validated
Health timer                 OK      active
Health check                 OK      last check OK
Go-live validation           OK      snapshot/firewall/Cloudflare confirmations recorded
```

## Final QA and support-bundle evidence

Final QA option `9) Go-live validation status` passed and displayed the saved go-live record. The enhanced support bundle was then generated successfully:

```text
/tmp/erpnext-dev-support-bundle-20260709-062951.tar.gz
```

Its archive listing included the new redacted production evidence files:

```text
go-live-status.txt
health-check-status.txt
restore-rehearsal-status.txt
off-vm-backup-status.txt
backup-verify.txt
backup-status.txt
production-checklist.txt
recent-errors.txt
bench-status.txt
ssl-status.txt
storage-status.txt
port-status.txt
service-status.txt
system-summary.txt
doctor-json-validation.txt
doctor.json
doctor-plain.txt
manifest.txt
```

The bundle intentionally excludes credential files, private keys, raw `site_config.json` secrets, tokens, passwords, database backups, and private file backups.

## Validation conclusion

The production path is validated end to end for the tested environment. Remaining work is no longer a blocker for this validated path; future work should focus on operator experience, recurring policy decisions, notification integrations, broader environment coverage, and periodic revalidation after major changes.

Follow-up milestone: v1.1.66 implements the unified production operations dashboard/menu built on the existing tested commands rather than new duplicated logic.

---

# v1.1.64 Go-live validation record and evidence bundle plan

v1.1.64 records the external provider-side checks that cannot be fully proven from inside the ERPNext VM. It complements the already validated install, backup, off-VM backup, restore rehearsal, and health timer.

New go-live commands:

```bash
sudo erpnext-dev cloud-firewall-checklist
sudo erpnext-dev cloudflare-checklist
sudo erpnext-dev go-live-record
sudo erpnext-dev go-live-status
```

Production validation sequence:

```bash
sudo erpnext-dev cloud-firewall-checklist
sudo erpnext-dev cloudflare-checklist
sudo erpnext-dev go-live-record
sudo erpnext-dev go-live-status
sudo erpnext-dev production-checklist
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
```

Record file:

```text
/etc/erpnext-dev/go-live-validation.env
```

Provider-side items to confirm before recording:

```text
Snapshot: named cloud/provider snapshot created and verified
Cloud firewall: 22 restricted to admin IP where possible, 80/443 allowed, 8000/9000 blocked
Cloudflare DNS: erp.flowmaya.com proxied/orange-cloud
Cloudflare SSL/TLS: Full (strict)
Cloudflare Origin CA: certificate active on Nginx
```

Expected after recording:

```text
Go-live validation           OK      recorded ... snapshot ... cloud firewall confirmed; Cloudflare proxied; Full strict confirmed
Release state                OK      ready for production use
```

Support bundle improvement:

The redacted support bundle should now include operational evidence files in addition to doctor/system/service diagnostics:

```text
production-checklist.txt
backup-status.txt
backup-verify.txt
off-vm-backup-status.txt
restore-rehearsal-status.txt
health-check-status.txt
go-live-status.txt
```

---

# v1.1.63 Health monitoring validation plan

v1.1.63 adds the final optional monitoring workflow after the production path reached a validated backup/restore state in v1.1.62.

New monitoring commands:

```bash
sudo erpnext-dev health-monitoring-wizard
sudo erpnext-dev health-check
sudo erpnext-dev configure-health-check-timer
sudo erpnext-dev health-check-status
sudo erpnext-dev health-check-journal
sudo erpnext-dev disable-health-check-timer
```

Expected production validation sequence:

```bash
sudo erpnext-dev health-check
sudo erpnext-dev health-check-status
sudo erpnext-dev configure-health-check-timer
sudo erpnext-dev production-checklist
sudo erpnext-dev final-qa
```

The health check is read-only. It records its latest result in:

```text
/etc/erpnext-dev/health-check.state
```

The currently validated production baseline remains:

```text
Site: erp.flowmaya.com
Production VPS: 65.109.221.4
Backup server: 65.109.220.250
Restore rehearsal: recorded and login validated
Final QA: Release state OK
```

Remaining provider-side operational confirmations are still outside the VM: named cloud snapshot, provider firewall rules, and Cloudflare Full (strict) / orange-cloud state.

---

## v1.1.62 final production QA documentation record

This patch records the final validated state after v1.1.61 restore rehearsal tracking was installed, the completed restore drill was recorded on the production VPS, and Final QA was rerun.

Validated production environment:

```text
Toolkit version during field validation: 1.1.61
Documentation/package version recording validation: 1.1.62
Site: erp.flowmaya.com
Production VPS: 65.109.221.4
Backup server: 65.109.220.250
Off-VM target: erpbackup@65.109.220.250:/mnt/HC_Volume_106276869/erpnext-backups/erp.flowmaya.com/
Restored backup set: 20260709_055928-erp_flowmaya_com
Restore target: local-vm/local-kvm-restore-vm
Restore target IP/address: evidence only; recorded value may change with network changes
Support bundle: /tmp/erpnext-dev-support-bundle-20260709-050725.tar.gz
```

Final QA evidence:

```text
Script version               INFO    1.1.61
Syntax                       OK      bash syntax valid
Site                         INFO    erp.flowmaya.com (saved config)
Deployment mode              INFO    public-vm
Install                      OK      Installed
Runtime                      OK      Running via service
HTTPS                        OK      Cloudflare Origin CA/Nginx HTTPS responding: HTTP/2 200
UFW                          OK      active
Fail2Ban                     OK      sshd jail enabled
Latest backup                OK      complete
Restore rehearsal            OK      completed 2026-07-09T05:05:19+00:00; backup set 20260709_055928-erp_flowmaya_com; target local-vm/local-kvm-restore-vm; login validated
Release state                OK      ready for production use
```

Backup verification evidence after rehearsal record:

```text
Latest set state             OK      complete
Database                     OK      gzip readable
Public files                 OK      tar readable
Private files                OK      tar readable
Site config                  OK      json readable
Verification                 OK      backup files are readable; restore rehearsal is recorded
```

Production checklist no longer treats restore rehearsal as pending. It correctly reports the rehearsal as recorded and moves the remaining items to operational decisions only.

Remaining operational go-live decisions:

```text
- Confirm scheduled local backups and retention policy.
- Configure health timer if ongoing monitoring is required.
- Confirm cloud firewall: 22 admin IP, 80/443 allowed, 8000/9000 blocked.
- Confirm Cloudflare SSL mode and DNS proxy state.
- Create named cloud snapshot after final validation.
```

Readiness after this validation: 9.5/10. The remaining gap is provider-level snapshot/firewall confirmation and optional monitoring policy, not backup/restore capability.

## v1.1.61 restore rehearsal record/status validation

The restore rehearsal was technically completed in v1.1.60, but production status commands still showed stale warnings because the production VPS had no local record of the external restore drill. v1.1.61 adds explicit recording and status tracking.

New production-side record file:

```text
/etc/erpnext-dev/restore-rehearsal.env
```

New commands:

```bash
sudo erpnext-dev restore-rehearsal-report   # run on disposable restore VM
sudo erpnext-dev restore-rehearsal-record   # run on production ERPNext VM
sudo erpnext-dev restore-rehearsal-status   # run on production ERPNext VM
```

Important operational note: the restore VM IP/address is evidence only. It may change when the local restore VM uses a different network or internet connection. The rehearsal record should rely on site name, backup set, restore result, and validation status rather than treating the restore VM IP as a permanent trust anchor.

Cleanup validation after the local restore drill:

```text
Backup server authorized_keys after cleanup: only production VPS key remains
Local restore VM backup-server SSH after cleanup: Permission denied, expected
Production VPS off-vm-backup-status: OK
Production VPS off-vm-backup-dry-run: OK
```

## v1.1.60 local restore rehearsal validation record

A disposable local KVM restore VM was used to rehearse restoring from the off-VM backup server. This validates backup usability without touching production DNS or restoring onto the live ERPNext VPS.

```text
Production ERPNext VPS: 65.109.221.4
Production domain/site: erp.flowmaya.com
Backup VPS: 65.109.220.250
Backup volume path: /mnt/HC_Volume_106276869
Backup target path: /mnt/HC_Volume_106276869/erpnext-backups/erp.flowmaya.com/
Local restore VM: 192.168.122.215
Restore OS: Ubuntu 26.04 LTS
Restore resources observed: 14 GiB RAM, 4 GiB swap, 61 GB root disk
```

Validated sequence:

1. Prepared a clean local restore VM and removed MicroK8s/Calico conflicts.
2. Installed the toolkit and matching ERPNext/Frappe v16 stack using site `erp.flowmaya.com`.
3. Generated a temporary restore key on the restore VM.
4. Authorized that key on the backup server, restricted to the restore VM's outbound public IP.
5. Pulled the off-VM backup files by rsync to the restore VM backup folder.
6. Confirmed `list-backups`, `backup-verify`, and `restore-preflight` passed.
7. Ran `restore-full` on the restore VM only.
8. Confirmed database/files restore, post-restore migrate, asset build, cache clear, service restart, and readiness checks completed successfully.

Result:

```text
Off-VM backup copied: PASS
Backup files readable: PASS
Restore preflight: PASS
Full restore on disposable VM: PASS
Post-restore maintenance: PASS
Service/port readiness: PASS
Browser/login validation: pending user confirmation
Temporary restore-key cleanup: pending after browser/login validation
```

This moves the production backup/resilience path from copied backups to proven restorable backups. The remaining operational task is to make the workflow smoother and ensure temporary restore keys are removed after each drill.

## v1.1.59 off-VM backup validation record

The two-server off-VM backup flow has now been validated on the real Hetzner production test path.

```text
ERPNext VPS: 65.109.221.4
ERPNext domain: erp.flowmaya.com
Backup VPS: 65.109.220.250
Backup OS: Ubuntu 26.04 LTS
Backup volume: /dev/sdb mounted at /mnt/HC_Volume_106276869
Backup target: erpbackup@65.109.220.250:/mnt/HC_Volume_106276869/erpnext-backups/erp.flowmaya.com/
Delete mode: false
```

Validated commands:

```bash
sudo erpnext-dev generate-off-vm-backup-key
sudo erpnext-dev off-vm-backup-guided-setup
sudo erpnext-dev off-vm-backup-dry-run
sudo erpnext-dev run-off-vm-backup
sudo erpnext-dev off-vm-backup-status
sudo erpnext-dev production-checklist
```

Observed result:

- Backup server user `erpbackup` exists.
- Backup folder is owned by `erpbackup:erpbackup` on the attached 200 GB volume.
- Authorized key is restricted to the ERPNext VPS source IP and disables agent forwarding, X11 forwarding, port forwarding, and pseudo-terminal allocation.
- `off-vm-backup-dry-run` completed successfully.
- `run-off-vm-backup` copied the latest complete local backup set.
- Backup server contains database, public files, private files, and site config backup files.
- `off-vm-backup-status` reports last run OK.
- `production-checklist` reports off-VM backup OK.

Remaining required production validation:

```text
Rehearse restore from the off-VM backup on a disposable VM.
Confirm retention policy after real backup size is known.
Optionally configure health timer/monitoring.
Create a named cloud snapshot after final validation.
```

## v1.1.58 off-VM backup server setup validation plan

The next production validation target is off-VM backup. The toolkit now supports a two-server flow:

- ERPNext VPS: `generate-off-vm-backup-key` and `off-vm-backup-guided-setup`.
- Backup server: `backup-server-setup` / `prepare-backup-server`.

Backup server bootstrap command:

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" backup-server-setup
```

Validation checklist:

- Backup server user/folder created outside the ERPNext VM.
- ERPNext VM public key installed on backup server.
- `off-vm-backup-dry-run` succeeds.
- `run-off-vm-backup` succeeds.
- `off-vm-backup-status` shows last run OK.
- Backup server contains database, public files, private files, and site config backup files.
- Restore rehearsal is still required on a disposable VM after off-VM backup succeeds.

## v1.1.57 Cloudflare Origin CA validation record

Cloudflare Origin CA / Full (strict) has now been validated on the real Hetzner VPS production path.

```text
Validated release path: v1.1.56 fix confirmed and recorded in v1.1.57
Provider: Hetzner Cloud VPS
OS: Ubuntu 26.04 LTS
Domain: erp.flowmaya.com
Cloudflare DNS: proxied / orange-cloud
Public DNS: Cloudflare edge IPs, not origin VPS IP
Cloudflare SSL/TLS mode: Full (strict)
Origin certificate: Cloudflare Origin CA installed on VM
Nginx: Cloudflare Origin CA HTTPS config enabled
External HTTPS: HTTP/2 200 through Cloudflare
External backend ports: 8000/9000 timed out from workstation
UFW: active production profile
Fail2Ban: sshd jail enabled
Scheduled backups: local systemd timer active
```

Production HTTPS validation status:

```text
Let's Encrypt direct DNS-only path: validated.
Cloudflare Origin CA / Full (strict): validated.
```

Remaining required hardening before relying on a real client production system:

```text
Configure an off-VM backup target.
Run an off-VM backup dry run and real copy.
Rehearse restore on a disposable VM.
Optionally configure health timer/monitoring.
```

## v1.1.56 Cloudflare proxied DNS behavior

For Cloudflare Origin CA / Full (strict), orange-cloud/proxied DNS returns Cloudflare edge IPs, not the VPS origin IP. This is expected and must be handled differently from the default Let's Encrypt path.

Guided setup behavior:

- If DNS resolves directly to the VM IP, continue with the default Let's Encrypt path.
- If DNS resolves to a different IP and the user wants Let's Encrypt HTTP-01, stop and switch Cloudflare to DNS-only/gray-cloud first.
- If DNS resolves to a Cloudflare edge IP and the user wants Cloudflare Origin CA, continue only after the user confirms the hidden Cloudflare DNS record content points to the VM IP and proxy/orange-cloud is intended.

# Production VPS Validation

## Validated milestone

The core production VPS guided path has been validated successfully on a fresh Hetzner VPS.

```text
Toolkit path: public-vm-guided-setup
Validated release path: v1.1.53 core flow; v1.1.54/v1.1.55 polish afterward
Provider: Hetzner Cloud VPS
OS: Ubuntu 26.04 LTS
Domain: real public subdomain
HTTPS: Let’s Encrypt directly on the VM
Nginx: public 80/443 entrypoint
UFW: active production profile
Fail2Ban: sshd jail enabled
Backups: local database + public/private files backup verified readable
Scheduled backups: daily systemd timer active
External validation: HTTPS responds; 8000/9000 time out from workstation
Support bundle: redacted archive created and contents reviewed
Snapshot: post-validation provider snapshot required/confirmed during handoff
```

Remaining production hardening before relying on a real client system:

```text
Configure and test an off-VM backup target.
Run off-VM backup dry run and real run.
Rehearse restore on a disposable VM.
Cloudflare Origin CA / Full (strict) has been validated; continue with off-VM backup and restore rehearsal validation.
Optionally configure health timer/monitoring.
```

This checklist starts after the local VM validation stage has passed. Use it to test the ERPNext Developer Toolkit on a real public VPS with a real test domain or subdomain before trusting the toolkit for production handoff.

## Validation position

Local VM validation is complete. The following paths are considered passed for local/developer use:

- Local VM quickstart with `erp.test` or another `.test` hostname.
- Host `/etc/hosts` mapping guidance.
- Local HTTPS with mkcert.
- Local VM firewall/security profile.
- Optional app installation and app-status reporting.
- Manual database + files backups.
- Backup readable-file verification.
- Database restore.
- Full database + public/private files restore.
- Scheduled local backups with systemd timer.
- Backup retention status and cleanup dry run.
- Maintenance menu: logs, clear cache, restart, safe repair.
- Final QA: readiness summary, command audit, backup verify, production checklist, support bundle.

The production stage is not closed yet. A local `.test` VM cannot validate public DNS, Let's Encrypt, Cloudflare proxy behavior, provider firewalls, public port exposure, or production Fail2Ban behavior.

## Required environment

Use a fresh disposable VPS, not a client production server and not the already-tested local VM.

Recommended minimum:

```text
Ubuntu 24.04 LTS or Ubuntu 26.04 LTS
2 vCPU minimum; 4 vCPU preferred
4 GB RAM minimum; 8 GB preferred
60-80 GB SSD minimum
Public IPv4
Snapshot support
Cloud firewall support
SSH access from your admin IP
```

Use a real test subdomain:

```text
erp-test.example.com
```

DNS:

```text
A record: erp-test.example.com -> VPS_PUBLIC_IP
```

When using Cloudflare, begin with **DNS only** for the first Let's Encrypt test. After normal public HTTPS works, test Cloudflare proxy / Full strict separately.

## Baseline cloud firewall

Before installing, configure the provider firewall like this:

```text
22/tcp    allow from admin IP only
80/tcp    allow from anywhere
443/tcp   allow from anywhere
8000/tcp  block from anywhere
9000/tcp  block from anywhere
```

Do not publicly expose Bench development ports 8000 or 9000 during production validation.

## Production HTTPS provider choice

For the first real VPS validation, prefer the default **Let's Encrypt directly on the VM** path when the DNS A record resolves to the VPS public IP and ports 80/443 are open. This proves the plain public HTTPS/Nginx path.

The guided production setup should still allow the user to choose another SSL provider during the HTTPS step. Use **Cloudflare Origin CA** when the site will remain Cloudflare-proxied/orange-cloud and Cloudflare SSL/TLS mode will be set to **Full (strict)**.

Validation expectations:

```text
Let's Encrypt path: DNS-only/direct DNS to VM; browser/curl trusts the certificate directly.
Cloudflare Origin CA path: Cloudflare proxy ON; Full (strict); browser/curl should validate through Cloudflare, not directly to the origin certificate.
```

## Production validation order

1. Create a fresh disposable VPS.
2. Point the test subdomain A record to the VPS public IP.
3. Configure the cloud firewall baseline.
4. Take a clean initial snapshot.
5. Install the toolkit CLI.
6. Run `erpnext-dev version`.
7. Run `sudo erpnext-dev public-vm-guided-setup`.
8. Confirm site/domain config.
9. Apply or verify the production firewall profile.
10. Run the guided production HTTPS step. Use the default Let's Encrypt path first when DNS points directly to the VM, or open the SSL provider wizard for Cloudflare Origin CA when validating a proxied Cloudflare Full (strict) path.
11. Verify public HTTPS from outside the VM.
12. Confirm 8000/9000 are not publicly reachable.
13. Confirm Fail2Ban sshd jail status.
14. Create database + files backup.
15. Verify latest backup.
16. Configure scheduled local backups.
17. Confirm scheduled backup status.
18. Review off-VM backup plan or configure a test rsync target.
19. Run the production checklist.
20. Run Final QA.
21. Create a redacted support bundle.
22. Take a named post-validation snapshot.

## Bootstrap commands

Install or update the CLI on the VPS:

```bash
tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" install-cli
```

Start the guided production setup:

```bash
erpnext-dev version
sudo erpnext-dev public-vm-guided-setup
```


Manual production menu remains available:

```bash
sudo erpnext-dev public-vm-quickstart
```

Common production-stage validation commands:

```bash
sudo erpnext-dev production-checklist
sudo erpnext-dev production-ssl-wizard
sudo erpnext-dev production-ssl-status
sudo erpnext-dev vm-firewall-status
sudo erpnext-dev fail2ban-status
sudo erpnext-dev verify-access
sudo erpnext-dev backup-files
sudo erpnext-dev backup-verify
sudo erpnext-dev configure-backup-schedule
sudo erpnext-dev backup-schedule-status
```

Run interactive menu commands by themselves:

```bash
sudo erpnext-dev final-qa
```

Quit with `q`, then run follow-up commands separately:

```bash
sudo erpnext-dev support-bundle
```


## Troubleshooting: SSH host key changed after a fresh VPS rebuild

If you rebuild the VPS or restore a clean provider image while keeping the same public IP or domain, SSH from your workstation may stop with:

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
Host key verification failed.
```

Classify this as an expected warning only when the VPS was intentionally rebuilt or replaced. If the server was not intentionally changed, stop and verify the server identity from the provider console before connecting.

Fix it from the **local/admin machine**:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R "VPS_PUBLIC_IP"
ssh-keygen -f ~/.ssh/known_hosts -R "erp.example.com"
ssh root@VPS_PUBLIC_IP
```

For the FlowMaya validation example, replace the placeholders with the current VPS IP and `erp.flowmaya.com`.

## Acceptance criteria

The production VPS validation stage should not be marked passed until all of these are true:

- Public VM quickstart completes on a fresh VPS.
- Real test domain resolves to the VPS.
- Public HTTPS works with a valid certificate.
- HTTP redirects or serves as expected according to the selected HTTPS mode.
- Cloud firewall and UFW are aligned.
- SSH is restricted to the admin IP at the provider firewall where possible.
- 80 and 443 are reachable publicly.
- 8000 and 9000 are not reachable publicly.
- Fail2Ban sshd jail is confirmed or a documented exception is recorded.
- Backup creation and readable-file verification pass.
- Scheduled backups are active.
- Retention status is sane.
- Off-VM backup plan is reviewed; production cannot be considered complete without an off-VM copy strategy.
- Final QA does not show unexpected production blockers.
- A named cloud snapshot is taken after validation.

## Current readiness ratings

| Case | Rating | Status |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local/dev use |
| Optional app workflow | 9.0/10 | Passed locally with curated apps |
| Local backup, restore, scheduled backup, retention | 9.0/10 | Passed locally; production restore rehearsal still required |
| Maintenance / Final QA / support bundle | 8.8/10 | Passed locally |
| Public VPS quickstart | 6.5/10 | Implemented, requires real VPS validation |
| Let's Encrypt production HTTPS | 6.5/10 | Implemented, requires real DNS/domain validation |
| Cloudflare Origin CA / Full strict | 9.0/10 | Validated through Cloudflare orange-cloud/proxied DNS with Origin CA and Full (strict) |
| Production firewall + Fail2Ban | 6.5/10 | UFW tested locally; cloud firewall and Fail2Ban need VPS validation |
| Off-VM backup | 5.5/10 | Workflow exists; remote target validation needed |
| Health timer / monitoring | 5.5/10 | Available; production-stage validation needed |
| Overall local readiness | 9.3/10 | Passed |
| Overall production readiness before VPS validation | 6.5/10 | Production-candidate only |

## Notes for the next development session

Focus on validating the existing production path before adding broad new functionality. The first goal is to identify real-world VPS issues: DNS timing, firewall conflicts, Let's Encrypt failures, Nginx config issues, Fail2Ban availability, exposed ports, and production checklist accuracy.
