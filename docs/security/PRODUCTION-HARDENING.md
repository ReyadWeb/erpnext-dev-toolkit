# Production Hardening

This checklist is for a public ERPNext server managed by ERPNext Developer Toolkit.

It supplements [SECURITY.md](../../SECURITY.md) and [VALIDATION.md](../../VALIDATION.md). It is not a substitute for organisation-specific security policy.

## Before installation

- [ ] Use a fresh or snapshotted supported server.
- [ ] Apply operating-system updates.
- [ ] Protect the provider account with strong authentication.
- [ ] Restrict provider-console access.
- [ ] Create a real DNS record for the ERPNext domain.
- [ ] Restrict SSH to the administrator's trusted IP where practical.
- [ ] Allow public TCP `80` and `443`.
- [ ] Keep `8000`, `9000`, Redis, and MariaDB ports closed publicly.
- [ ] Record the provider snapshot or recovery-console procedure.
- [ ] Verify the toolkit release signature and complete checksums.

Run the read-only preflight:

```bash
sudo ./erpnext-dev.sh install-preflight
```

## Administrative access

- [ ] Use a named administrator account rather than routine root login.
- [ ] Use SSH keys.
- [ ] Disable unused accounts.
- [ ] Review `sudo` membership.
- [ ] Protect private SSH keys.
- [ ] Keep emergency console access documented.
- [ ] Do not paste credentials into chat, tickets, or shell-history notes.

## Deployment

- [ ] Use `public-vm-guided-setup`.
- [ ] Confirm the domain and site name.
- [ ] Use the production runtime rather than `bench start`.
- [ ] Confirm the selected native or Docker engine.
- [ ] Keep development ports private.
- [ ] Confirm Nginx or the production reverse proxy is the public entry point.
- [ ] Run the production checklist before go-live.

```bash
sudo erpnext-dev public-vm-guided-setup
sudo erpnext-dev production-runtime-status
sudo erpnext-dev production-checklist
```

## HTTPS

- [ ] Confirm DNS points to the intended server or proxy.
- [ ] Use Let's Encrypt for a direct-origin deployment.
- [ ] Use Cloudflare Origin CA only with the appropriate proxy and Full (strict) mode.
- [ ] Confirm HTTP redirects to HTTPS.
- [ ] Confirm certificate issuer, names, and expiry.
- [ ] Confirm renewal or replacement procedure.
- [ ] Confirm direct internal runtime ports are not public.

```bash
sudo erpnext-dev production-ssl-status
curl -I https://erp.example.com
```

## Host firewall and intrusion controls

- [ ] Review provider firewall rules.
- [ ] Review host firewall rules.
- [ ] Review Docker forwarding controls when using Docker.
- [ ] Enable the production security profile.
- [ ] Enable and review Fail2Ban where supported.
- [ ] Confirm SSH restrictions remain correct after provider changes.
- [ ] Confirm internal database and Redis ports are not listening publicly.

```bash
sudo erpnext-dev security-audit
sudo erpnext-dev doctor --plain
```

## ERPNext and Frappe access

- [ ] Change initial administrator credentials.
- [ ] Store credentials in a password manager.
- [ ] Use named user accounts.
- [ ] Apply least-privilege roles and permissions.
- [ ] Enable two-factor authentication where appropriate.
- [ ] Review integration users and API keys.
- [ ] Review email, payment, and third-party service credentials.
- [ ] Remove unused accounts and applications.

Application permissions are outside the toolkit's host-security boundary.

## Credentials and files

- [ ] Run `credentials-file-status`.
- [ ] Restrict the generated credential file.
- [ ] Delete local credential handoff files after secure storage.
- [ ] Review `/etc/erpnext-dev/` ownership and permissions.
- [ ] Protect `rclone` configuration separately.
- [ ] Protect SSH backup keys separately.
- [ ] Rotate any credential that may have appeared in a screenshot or shared log.

```bash
sudo erpnext-dev credentials-file-status
sudo erpnext-dev credentials-secure
sudo erpnext-dev credentials-delete
```

## Backups

- [ ] Create a verified local backup.
- [ ] Enable and inspect scheduled backups.
- [ ] Configure an off-VM or object-storage copy.
- [ ] Protect backup credentials.
- [ ] Define retention and deletion policy.
- [ ] Monitor the last successful backup.
- [ ] Rehearse restore on a disposable system.
- [ ] Confirm ERPNext health after restore.
- [ ] Document recovery-time and recovery-point objectives.

```bash
sudo erpnext-dev backup-files
sudo erpnext-dev backup-verify
sudo erpnext-dev restore-rehearsal-wizard
```

## Updates

- [ ] Take a verified backup before major changes.
- [ ] Review release notes.
- [ ] Test optional-application compatibility.
- [ ] Verify the toolkit before use.
- [ ] Use signed tag-pinned toolkit updates.
- [ ] Confirm the previous toolkit release remains available.
- [ ] Validate service and browser readiness after updates.
- [ ] Rehearse rollback before relying on it during an incident.

```bash
sudo erpnext-dev verify-toolkit
sudo erpnext-dev update-toolkit
sudo erpnext-dev toolkit-rollback
```

Toolkit rollback does not roll back ERPNext data or schema migrations.

## Monitoring and incident readiness

- [ ] Review dashboard status.
- [ ] Review health snapshot and incidents.
- [ ] Confirm storage headroom.
- [ ] Confirm certificate status.
- [ ] Confirm backup recency.
- [ ] Confirm external monitoring can detect an unreachable server.
- [ ] Document provider, DNS, and backup-provider escalation paths.
- [ ] Keep an incident communication plan.

```bash
sudo erpnext-dev dashboard
sudo erpnext-dev health-snapshot --plain
sudo erpnext-dev incidents
sudo erpnext-dev doctor --plain
```

## Support evidence

Before sharing diagnostics:

- [ ] Run the support-bundle audit.
- [ ] List the archive contents.
- [ ] Extract and inspect the bundle.
- [ ] Remove credentials, customer data, and unusual application secrets.
- [ ] Use private vulnerability reporting for security issues.

Support-bundle redaction is heuristic and requires operator review.

## Go-live gate

Do not consider the deployment ready until:

- [ ] HTTPS is valid.
- [ ] Internal ports are not public.
- [ ] Production runtime is healthy.
- [ ] Backup verification passes.
- [ ] Off-host backup is configured or an accepted risk is documented.
- [ ] Restore rehearsal passes.
- [ ] Toolkit integrity passes.
- [ ] Security audit and doctor output contain no unresolved critical finding.
- [ ] Provider snapshot and console recovery are available.
- [ ] ERPNext user and permission review is complete.

Run:

```bash
sudo erpnext-dev final-qa
```

Record the result using [VALIDATION.md](../../VALIDATION.md).
