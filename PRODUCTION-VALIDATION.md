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
