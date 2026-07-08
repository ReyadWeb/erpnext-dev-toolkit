# Production VPS Validation

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
10. Run the production HTTPS wizard and select the Let's Encrypt path first.
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
sudo erpnext-dev final-qa
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
| Cloudflare Origin CA / Full strict | 6.0/10 | Requires separate Cloudflare test after Let's Encrypt baseline |
| Production firewall + Fail2Ban | 6.5/10 | UFW tested locally; cloud firewall and Fail2Ban need VPS validation |
| Off-VM backup | 5.5/10 | Workflow exists; remote target validation needed |
| Health timer / monitoring | 5.5/10 | Available; production-stage validation needed |
| Overall local readiness | 9.3/10 | Passed |
| Overall production readiness before VPS validation | 6.5/10 | Production-candidate only |

## Notes for the next development session

Focus on validating the existing production path before adding broad new functionality. The first goal is to identify real-world VPS issues: DNS timing, firewall conflicts, Let's Encrypt failures, Nginx config issues, Fail2Ban availability, exposed ports, and production checklist accuracy.
