# ERPNext Developer Installer v1.1.15

![ERPNext Installer Banner](docs/assets/erp_installer_readme_banner.png)

A guided installer and operations toolkit for ERPNext/Frappe on Ubuntu and Debian-family VMs.

It supports two main setup paths:

- **Local development VM** using a local test hostname such as `erp.test`.
- **Public VPS / cloud VM** using a real domain or subdomain such as `erp.example.com`.

The project also includes production operations helpers for SSL, firewall hardening, scheduled backups, backup retention, off-VM backup planning, health checks, restore preflight, optional app installation, diagnostics, and support bundles.

> Version history is maintained in [`CHANGELOG.md`](CHANGELOG.md). This README intentionally focuses on installation, operations, and usage.

---

## Start here

Use this section when you want to install quickly without reading the full README first.

These commands assume a fresh **Debian-family Linux VM** such as Ubuntu or Debian, with `sudo` access.

### Option A — open the guided installer menu

Use this if you want the installer to guide you through the available setup paths:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh menu
```

### Option B — local VM development install

Use this inside a fresh local VM for testing or development:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh local-dev-quickstart
```

Recommended local hostname:

```text
erp.test
```

### Option C — public VPS / cloud VM install

Use this inside a fresh public VM when you have a real domain or subdomain ready:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh public-vm-quickstart
```

Recommended public hostname:

```text
erp.example.com
```

### Option D — existing install operations menu

Use this on a VM where the installer was already used and you want production operations, backups, health checks, SSL, or diagnostics:

```bash
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo cp /tmp/install-erpnext-dev.sh /root/install-erpnext-dev.sh && sudo chmod +x /root/install-erpnext-dev.sh && sudo /root/install-erpnext-dev.sh production-ops-wizard
```

### Option E — optional apps wizard

Use this only after the core ERPNext install is healthy:

```bash
sudo /root/install-erpnext-dev.sh app-install-wizard
```

After any quickstart finishes, use this stable path for follow-up commands:

```bash
/root/install-erpnext-dev.sh
```

Examples:

```bash
/root/install-erpnext-dev.sh doctor --plain
/root/install-erpnext-dev.sh verify-access
/root/install-erpnext-dev.sh credentials-info
/root/install-erpnext-dev.sh production-ops-wizard
```

---

## README menu

- [Start here](#start-here)
- [Architecture diagrams](#architecture-diagrams)
- [Quick decision guide](#quick-decision-guide)
- [Interactive menu navigation](#interactive-menu-navigation)
- [One-command local VM test](#one-command-local-vm-test)
- [One-command public VPS / cloud VM setup](#one-command-public-vps--cloud-vm-setup)
- [Reusable script path](#reusable-script-path)
- [Accessing ERPNext credentials](#accessing-erpnext-credentials)
- [Production operations](#production-operations)
- [Backups and restore safety](#backups-and-restore-safety)
- [Optional Frappe apps](#optional-frappe-apps)
- [SSL mode guide](#ssl-mode-guide)
- [Security hardening](#security-hardening)
- [Diagnostics and support](#diagnostics-and-support)
- [Documentation files](#documentation-files)
- [Production caution](#production-caution)

---

## Architecture diagrams

### Production backup architecture

![Production Backup Architecture](docs/assets/production_backup_architecture_diagram.png)

### Local testing VM architecture

![Local Testing VM Architecture](docs/assets/local_testing_vm_architecture_diagram.png)

---

## Quick decision guide

| Scenario | Command | Recommended hostname |
|---|---|---|
| Local VM testing/dev | `local-dev-quickstart` | `erp.test` |
| Public VPS/cloud VM | `public-vm-quickstart` | `erp.example.com` |
| Existing install operations | `production-ops-wizard` | saved site/domain |
| Optional Frappe apps | `app-install-wizard` | existing site |

Do not use a production domain for a local-only test VM unless you intentionally want that VM to act as a public deployment.

---

## Interactive menu navigation

Interactive menus use numbers for actions and letters for navigation:

```text
1) Run an action
2) Run another action
...
-----------------------------
b) Back                        q) Quit
```

Use:

```text
number = run the selected action
b or B = back to the previous menu
q or Q = quit the installer
```

The main menu shows only `q) Quit` because there is no parent menu to return to.

---

## One-command local VM test

Run this inside a fresh local Ubuntu/Debian-family VM:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh local-dev-quickstart
```

The quickstart copies the installer to a reusable path inside the VM:

```bash
/root/install-erpnext-dev.sh
```

Use that path for follow-up commands, including SSL setup and optional app installation. Do not use `./install-erpnext-dev.sh` unless you are in the directory that contains the script.

Recommended local site name:

```text
erp.test
```

After the installer finishes, validate inside the VM:

```bash
/root/install-erpnext-dev.sh doctor --plain
/root/install-erpnext-dev.sh verify-access
/root/install-erpnext-dev.sh backup-files
/root/install-erpnext-dev.sh backup-status
/root/install-erpnext-dev.sh backup-verify
/root/install-erpnext-dev.sh credentials-info
```

From the host machine, add a hosts entry. Replace `LOCAL_VM_IP` with the local VM IP:

```bash
sudo sed -i '/[[:space:]]erp\.test$/d' /etc/hosts
echo "LOCAL_VM_IP erp.test" | sudo tee -a /etc/hosts
```

Then test access from the host:

```bash
curl -I http://LOCAL_VM_IP:8000
curl -I http://erp.test:8000
```

If local HTTPS is enabled, also test:

```bash
curl -Ik https://erp.test
```

For trusted local HTTPS with mkcert, run the guide inside the VM:

```bash
/root/install-erpnext-dev.sh mkcert-guide
```

The guide separates HOST commands from VM commands. In short: generate and trust the certificate on the Linux HOST, copy the cert/key into the VM with `scp`, then run `/root/install-erpnext-dev.sh configure-local-ssl` inside the VM.

Expected local result:

```text
Install: OK
Runtime: Running via service
Site: erp.test
Direct URL: http://LOCAL_VM_IP:8000
Friendly URL: http://erp.test:8000
Local HTTPS: optional
```

Recommended local VM test order:

```text
1. local-dev-quickstart
2. doctor --plain
3. verify-access
4. backup-files
5. backup-verify
6. optional app wizard only after core passes
```

---

## One-command public VPS / cloud VM setup

Run this inside a fresh public Ubuntu/Debian-family VM:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh public-vm-quickstart
```

Use a real subdomain, for example:

```text
erp.example.com
```

Typical public setup flow:

```text
1. Set/change domain
2. Check DNS/domain plan
3. Install or repair ERPNext
4. Configure HTTPS
5. Security hardening
6. Final status / support bundle
7. SSL mode guide / setup steps
```

For Cloudflare Origin CA mode:

```text
DNS record: Proxied / orange-cloud
SSL/TLS mode: Full (strict)
Origin certificate: installed on the VM
```

For Let's Encrypt mode:

```text
DNS record: DNS-only / direct to VM
Port 80: reachable during certificate issuance
```

After installation, validate:

```bash
/root/install-erpnext-dev.sh release-readiness
/root/install-erpnext-dev.sh production-checklist
/root/install-erpnext-dev.sh backup-verify
/root/install-erpnext-dev.sh support-bundle
```

From your workstation, replace `PUBLIC_VM_IP` with the public server IP:

```bash
curl -I https://erp.example.com
curl -I --connect-timeout 10 http://PUBLIC_VM_IP:8000
curl -I --connect-timeout 10 http://PUBLIC_VM_IP:9000
```

Expected public result:

```text
https://erp.example.com -> HTTP 200/redirect through Nginx/CDN/proxy
PUBLIC_VM_IP:8000 -> timeout or blocked
PUBLIC_VM_IP:9000 -> timeout or blocked
```

---

## Reusable script path

During quickstart, the installer copies itself to:

```bash
/root/install-erpnext-dev.sh
```

Use this stable path for follow-up commands:

```bash
/root/install-erpnext-dev.sh status
/root/install-erpnext-dev.sh doctor --plain
/root/install-erpnext-dev.sh production-ops-wizard
```


---

## Accessing ERPNext credentials

After installation, the installer saves the generated ERPNext and database credentials on the VM.

Run this inside the VM to see where the credentials are stored and how to reset the Administrator password:

```bash
/root/install-erpnext-dev.sh credentials-info
```

To view the generated password directly on the VM:

```bash
sudo cat /home/frappe/erpnext-dev-credentials.txt
```

The ERPNext web login normally uses:

```text
Username: Administrator
Password: value shown in /home/frappe/erpnext-dev-credentials.txt
```

The credentials file is intentionally excluded from diagnostics, support bundles, shared logs, and generated support archives. Do not paste the file contents into public tickets or GitHub issues.

If the Administrator password needs to be reset, run this inside the VM:

```bash
cd /home/frappe/frappe/frappe-bench
sudo -u frappe bench --site erp.test set-admin-password
```

For a public/production site, replace `erp.test` with the actual site name or domain, for example:

```bash
sudo -u frappe bench --site erp.example.com set-admin-password
```
---

## Production operations

Open the production operations wizard:

```bash
/root/install-erpnext-dev.sh production-ops-wizard
```

Common operations commands:

```bash
/root/install-erpnext-dev.sh release-readiness
/root/install-erpnext-dev.sh production-checklist
/root/install-erpnext-dev.sh health-check
/root/install-erpnext-dev.sh configure-health-check-timer
/root/install-erpnext-dev.sh health-check-status
/root/install-erpnext-dev.sh service-recovery-plan
```

Health checks cover ERPNext runtime, Nginx, MariaDB, Redis, HTTPS, disk usage, latest backup state, UFW, Fail2Ban, scheduled backup timer, and off-VM backup state.

---

## Backups and restore safety

Create and verify a local database + files backup:

```bash
/root/install-erpnext-dev.sh backup-files
/root/install-erpnext-dev.sh backup-status
/root/install-erpnext-dev.sh backup-verify
```

Scheduled local backups:

```bash
/root/install-erpnext-dev.sh backup-schedule-plan
/root/install-erpnext-dev.sh configure-backup-schedule
/root/install-erpnext-dev.sh backup-schedule-status
```

Backup retention:

```bash
/root/install-erpnext-dev.sh backup-retention-plan
/root/install-erpnext-dev.sh backup-retention-status
/root/install-erpnext-dev.sh cleanup-old-backups-dry-run
/root/install-erpnext-dev.sh cleanup-old-backups
```

Off-VM backup planning and rsync target setup:

```bash
/root/install-erpnext-dev.sh off-vm-backup-plan
/root/install-erpnext-dev.sh configure-rsync-backup-target
/root/install-erpnext-dev.sh off-vm-backup-dry-run
/root/install-erpnext-dev.sh run-off-vm-backup
/root/install-erpnext-dev.sh off-vm-backup-status
```

Restore safety checks:

```bash
/root/install-erpnext-dev.sh restore-preflight
/root/install-erpnext-dev.sh restore-rehearsal-guide
```

Important backup model:

```text
Local backups are useful but not enough for production.
Copy backups off the VM.
Keep cloud snapshots for infrastructure rollback.
Rehearse restore on a disposable VM before trusting backups.
```

---

## Optional Frappe apps

Install optional apps only after the core ERPNext install is healthy:

```bash
/root/install-erpnext-dev.sh app-compatibility
/root/install-erpnext-dev.sh app-install-wizard
/root/install-erpnext-dev.sh app-status
```

Supported optional app workflow:

```text
Frappe CRM
Frappe HR / HRMS
Frappe Insights
Frappe Telephony
Frappe Helpdesk
Custom trusted Frappe app from Git URL
```

Install one optional app at a time and take a backup/snapshot checkpoint before major changes.

---

## SSL mode guide

```bash
/root/install-erpnext-dev.sh ssl-mode-status
/root/install-erpnext-dev.sh ssl-mode-guide
/root/install-erpnext-dev.sh ssl-compatibility
/root/install-erpnext-dev.sh production-ssl-wizard
```

| Mode | Best for | Notes |
|---|---|---|
| Local self-signed / mkcert-style | Local VM | Development only |
| Let’s Encrypt | Public VM, DNS directly to VM | Requires HTTP-01 validation on port 80 |
| Cloudflare Origin CA | Public VM behind Cloudflare proxy | Requires Cloudflare proxy and Full (strict) |

---

## Security hardening

```bash
/root/install-erpnext-dev.sh security-hardening-wizard
/root/install-erpnext-dev.sh configure-vm-firewall
/root/install-erpnext-dev.sh vm-firewall-status
/root/install-erpnext-dev.sh configure-fail2ban
/root/install-erpnext-dev.sh fail2ban-status
/root/install-erpnext-dev.sh firewall-hardening-status
```

Recommended public exposure:

```text
22/tcp     allow only admin IP or VPN at the cloud firewall layer
80/tcp     public, or CDN/proxy IP ranges if applicable
443/tcp    public, or CDN/proxy IP ranges if applicable
8000/tcp   blocked publicly
9000/tcp   blocked publicly
11000/tcp  blocked publicly
13000/tcp  blocked publicly
```

UFW keeps SSH open by default to reduce lockout risk. Restrict SSH at the cloud firewall layer first.

---

## Diagnostics and support

```bash
/root/install-erpnext-dev.sh doctor
/root/install-erpnext-dev.sh doctor --plain
/root/install-erpnext-dev.sh doctor --json
/root/install-erpnext-dev.sh support-bundle
/root/install-erpnext-dev.sh command-audit
/root/install-erpnext-dev.sh credentials-info
/root/install-erpnext-dev.sh next-step
```

Support bundles are redacted. They intentionally exclude credential files, private keys, raw secrets, tokens, and passwords.

---

## Documentation files

| File | Purpose |
|---|---|
| `README.md` | Setup and usage guide |
| `CHANGELOG.md` | Version history and release notes |
| `TESTING.md` | Validation scenarios and QA commands |
| `ROADMAP.md` | Planned future improvements |
| `docs/assets/` | README diagrams and visual documentation |

---

## Production caution

This installer can prepare a production-candidate VM, but production readiness still requires operational decisions outside the script:

```text
Off-VM backup target
Restore rehearsal
Cloud snapshot policy
Cloud firewall rules
DNS/proxy/SSL ownership
Update process
Monitoring and alerting expectations
```
