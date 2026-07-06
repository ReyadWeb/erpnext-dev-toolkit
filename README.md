# ERPNext Developer Installer v1.1.23

![ERPNext Installer Banner](docs/assets/erp_installer_readme_banner.png)

A guided installer and operations toolkit for ERPNext/Frappe on Ubuntu and Debian-family VMs.

It supports two main setup paths:

- **Local development VM** using a local test hostname such as `erp.test`.
- **Public VPS / cloud VM** using a real domain or subdomain such as `erp.example.com`.

The project also includes production operations helpers for SSL, firewall hardening, scheduled backups, backup retention, off-VM backup planning, health checks, restore preflight, optional app installation, diagnostics, support bundles, and safe maintenance workflows.

> Version history is maintained in [`CHANGELOG.md`](CHANGELOG.md). This README intentionally focuses on current installation, operations, and usage.

---

## Start here

Use this section when you want to install quickly without reading the full README first.

These commands assume a fresh **Debian-family Linux VM** such as Ubuntu or Debian, with `sudo` access.

### Option A — check the VM before installing

Use this first when testing a fresh VM. It checks OS, internet access, CPU, RAM, root disk, and `/tmp` free space before the heavy install begins:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh install-preflight
```

If the VM is clearly unsafe for ERPNext, the installer blocks the install and prints a red `INSTALL BLOCKED` summary explaining what to fix.

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

### Option D — open the guided installer menu

Use this if you want to choose the setup path interactively:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh menu
```

### Option E — update an existing VM to the latest script

Use this on a VM where the installer was already used:

```bash
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo cp /tmp/install-erpnext-dev.sh /root/install-erpnext-dev.sh && sudo chmod +x /root/install-erpnext-dev.sh && sudo /root/install-erpnext-dev.sh version
```

Then open the main menu or production operations wizard:

```bash
sudo /root/install-erpnext-dev.sh menu
sudo /root/install-erpnext-dev.sh production-ops-wizard
```

### Option F — optional apps wizard

Use this only after the core ERPNext install is healthy:

```bash
sudo /root/install-erpnext-dev.sh app-install-wizard
```

After any quickstart finishes, use this stable path for follow-up commands:

```bash
sudo /root/install-erpnext-dev.sh <command>
```

Common examples:

```bash
sudo /root/install-erpnext-dev.sh version
sudo /root/install-erpnext-dev.sh doctor --plain
sudo /root/install-erpnext-dev.sh verify-access
sudo /root/install-erpnext-dev.sh credentials-info
sudo /root/install-erpnext-dev.sh production-ops-wizard
```

---

## README menu

- [Start here](#start-here)
- [Architecture diagrams](#architecture-diagrams)
- [Quick decision guide](#quick-decision-guide)
- [Minimum VM expectations and blocking preflight](#minimum-vm-expectations-and-blocking-preflight)
- [Interactive menu navigation](#interactive-menu-navigation)
- [One-command local VM test](#one-command-local-vm-test)
- [One-command public VPS / cloud VM setup](#one-command-public-vps--cloud-vm-setup)
- [Reusable script path](#reusable-script-path)
- [Accessing ERPNext credentials](#accessing-erpnext-credentials)
- [Production operations](#production-operations)
- [Backups and restore safety](#backups-and-restore-safety)
- [Pre-app checkpoint workflow](#pre-app-checkpoint-workflow)
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
| VM safety check before install | `install-preflight` | not required yet |
| Local VM testing/dev | `local-dev-quickstart` | `erp.test` |
| Public VPS/cloud VM | `public-vm-quickstart` | `erp.example.com` |
| Existing install operations | `production-ops-wizard` | saved site/domain |
| Optional Frappe apps | `app-install-wizard` | existing site |
| Advanced custom app tools | `advanced-app-tools` | existing site |

Do not use a production domain for a local-only test VM unless you intentionally want that VM to act as a public deployment.

---

## Minimum VM expectations and blocking preflight

The installer includes a blocking install preflight so unsafe environments do not proceed into package installation, bench creation, or database changes.

Run it directly:

```bash
sudo /tmp/install-erpnext-dev.sh install-preflight
```

or after the script has been copied to the reusable path:

```bash
sudo /root/install-erpnext-dev.sh install-preflight
```

Current safety behavior:

| Check | Behavior |
|---|---|
| Unsupported OS | blocks install |
| No sudo/root permission | blocks install |
| No GitHub/internet access | blocks install |
| CPU below 2 cores | blocks install |
| RAM below 4096 MB | blocks install |
| Root free disk below 30 GB | blocks install |
| `/tmp` free space below 4 GB | blocks install |
| RAM 4096-8191 MB | warning |
| CPU 2-3 cores | warning |
| Root free disk 30-59 GB | warning |

The install flow offers root storage expansion before the final blocking resource preflight when supported by the VM disk layout.

There is an expert-only unsafe override for disposable test VMs:

```bash
ERPNEXT_ALLOW_UNSAFE_INSTALL=true sudo /tmp/install-erpnext-dev.sh local-dev-quickstart
```

Normal users should not use the unsafe override.

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

Some longer app menus use two columns when the terminal is wide enough, and fall back to one column when the terminal is too narrow.

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

Use that path with `sudo` for follow-up commands, including SSL setup and optional app installation. Do not use `./install-erpnext-dev.sh` unless you are in the directory that contains the script.

Recommended local site name:

```text
erp.test
```

After the installer finishes, validate inside the VM:

```bash
sudo /root/install-erpnext-dev.sh version
sudo /root/install-erpnext-dev.sh doctor --plain
sudo /root/install-erpnext-dev.sh verify-access
sudo /root/install-erpnext-dev.sh backup-files
sudo /root/install-erpnext-dev.sh backup-status
sudo /root/install-erpnext-dev.sh backup-verify
sudo /root/install-erpnext-dev.sh credentials-info
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
sudo /root/install-erpnext-dev.sh mkcert-guide
```

The guide separates HOST commands from VM commands. In short: generate and trust the certificate on the Linux HOST, copy the cert/key into the VM with `scp`, then run the local SSL wizard inside the VM:

```bash
sudo /root/install-erpnext-dev.sh local-ssl-wizard
```

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
6. app-library / app-install-wizard only after core passes
7. install optional apps one at a time
8. reboot test
9. final doctor --plain and verify-access
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
1. Run install-preflight
2. Expand root storage if offered and needed
3. Set/change production domain
4. Check DNS/domain plan
5. Install or repair ERPNext
6. Configure HTTPS
7. Security hardening
8. Configure backups and health checks
9. Final status / support bundle
```

For Cloudflare Origin CA mode:

```text
DNS record: Proxied / orange-cloud
SSL/TLS mode: Full (strict)
Origin certificate: installed on the VM
```

Helpful Cloudflare commands:

```bash
sudo /root/install-erpnext-dev.sh cloudflare-origin-guide
sudo /root/install-erpnext-dev.sh configure-cloudflare-origin-ssl
sudo /root/install-erpnext-dev.sh cloudflare-origin-ssl-status
```

For Let's Encrypt mode:

```text
DNS record: DNS-only / direct to VM
Port 80: reachable during certificate issuance
```

Helpful public SSL commands:

```bash
sudo /root/install-erpnext-dev.sh production-ssl-plan
sudo /root/install-erpnext-dev.sh production-ssl-wizard
sudo /root/install-erpnext-dev.sh production-ssl-status
```

After installation, validate:

```bash
sudo /root/install-erpnext-dev.sh release-readiness
sudo /root/install-erpnext-dev.sh production-checklist
sudo /root/install-erpnext-dev.sh backup-verify
sudo /root/install-erpnext-dev.sh support-bundle
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

During quickstart and preflight flows, the installer copies itself to:

```bash
/root/install-erpnext-dev.sh
```

Use this stable path with `sudo` for follow-up commands:

```bash
sudo /root/install-erpnext-dev.sh version
sudo /root/install-erpnext-dev.sh status
sudo /root/install-erpnext-dev.sh doctor --plain
sudo /root/install-erpnext-dev.sh verify-access
sudo /root/install-erpnext-dev.sh production-ops-wizard
```

To update the stable script path from GitHub:

```bash
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo cp /tmp/install-erpnext-dev.sh /root/install-erpnext-dev.sh && sudo chmod +x /root/install-erpnext-dev.sh && sudo /root/install-erpnext-dev.sh version
```

---

## Accessing ERPNext credentials

After installation, the installer saves the generated ERPNext and database credentials on the VM.

Run this inside the VM to see where the credentials are stored and how to reset the Administrator password:

```bash
sudo /root/install-erpnext-dev.sh credentials-info
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
sudo /root/install-erpnext-dev.sh production-ops-wizard
```

Common operations commands:

```bash
sudo /root/install-erpnext-dev.sh release-readiness
sudo /root/install-erpnext-dev.sh production-checklist
sudo /root/install-erpnext-dev.sh health-check
sudo /root/install-erpnext-dev.sh configure-health-check-timer
sudo /root/install-erpnext-dev.sh health-check-status
sudo /root/install-erpnext-dev.sh service-recovery-plan
```

Health checks cover ERPNext runtime, Nginx, MariaDB, Redis, HTTPS, disk usage, latest backup state, UFW, Fail2Ban, scheduled backup timer, and off-VM backup state.

---

## Backups and restore safety

Create and verify a local database + files backup:

```bash
sudo /root/install-erpnext-dev.sh backup-files
sudo /root/install-erpnext-dev.sh backup-status
sudo /root/install-erpnext-dev.sh backup-verify
```

Scheduled local backups:

```bash
sudo /root/install-erpnext-dev.sh backup-schedule-plan
sudo /root/install-erpnext-dev.sh configure-backup-schedule
sudo /root/install-erpnext-dev.sh backup-schedule-status
```

Backup retention:

```bash
sudo /root/install-erpnext-dev.sh backup-retention-plan
sudo /root/install-erpnext-dev.sh backup-retention-status
sudo /root/install-erpnext-dev.sh cleanup-old-backups-dry-run
sudo /root/install-erpnext-dev.sh cleanup-old-backups
```

Off-VM backup planning and rsync target setup:

```bash
sudo /root/install-erpnext-dev.sh off-vm-backup-plan
sudo /root/install-erpnext-dev.sh configure-rsync-backup-target
sudo /root/install-erpnext-dev.sh off-vm-backup-dry-run
sudo /root/install-erpnext-dev.sh run-off-vm-backup
sudo /root/install-erpnext-dev.sh off-vm-backup-status
```

Restore safety checks:

```bash
sudo /root/install-erpnext-dev.sh restore-preflight
sudo /root/install-erpnext-dev.sh restore-rehearsal-guide
```

Important backup model:

```text
Local backups are useful but not enough for production.
Copy backups off the VM.
Keep VM/cloud snapshots for infrastructure rollback.
Rehearse restore on a disposable VM before trusting backups.
```

---

## Pre-app checkpoint workflow

Before installing an optional app, create an ERPNext backup and take a VM snapshot/checkpoint from the host/hypervisor when possible.

Inside the ERPNext VM:

```bash
sudo /root/install-erpnext-dev.sh backup-files
sudo /root/install-erpnext-dev.sh backup-verify
sudo /root/install-erpnext-dev.sh backup-status
```

Then create the VM snapshot from the host platform, for example KVM/virt-manager, Proxmox, VMware, VirtualBox, or your cloud provider.

The installer currently creates ERPNext backups from inside the VM. It does not create full VM snapshots because those are controlled by the host/hypervisor outside the guest VM.

Recommended optional app workflow:

```text
1. Run backup-files.
2. Verify the backup.
3. Take a VM snapshot/checkpoint from the host if available.
4. Install one app.
5. Run app-status, doctor --plain, and verify-access.
6. Continue to the next app only if healthy.
```

---

## Optional Frappe apps

Install optional apps only after the core ERPNext install is healthy:

```bash
sudo /root/install-erpnext-dev.sh app-library
sudo /root/install-erpnext-dev.sh app-compatibility
sudo /root/install-erpnext-dev.sh app-install-wizard
sudo /root/install-erpnext-dev.sh app-status
```

Curated app library:

| App | Direct command |
|---|---|
| CRM | `sudo /root/install-erpnext-dev.sh install-crm` |
| HR / HRMS | `sudo /root/install-erpnext-dev.sh install-hrms` |
| Education | `sudo /root/install-erpnext-dev.sh install-education` |
| Payments | `sudo /root/install-erpnext-dev.sh install-payments` |
| Webshop / E-Commerce | `sudo /root/install-erpnext-dev.sh install-webshop` |
| Builder | `sudo /root/install-erpnext-dev.sh install-builder` |
| Learning / LMS | `sudo /root/install-erpnext-dev.sh install-lms` |
| Wiki | `sudo /root/install-erpnext-dev.sh install-wiki` |
| Print Designer | `sudo /root/install-erpnext-dev.sh install-print-designer` |
| Drive | `sudo /root/install-erpnext-dev.sh install-drive` |
| Raven Chat | `sudo /root/install-erpnext-dev.sh install-raven` |
| Helpdesk | `sudo /root/install-erpnext-dev.sh install-helpdesk` |
| Telephony | `sudo /root/install-erpnext-dev.sh install-telephony` |
| Insights | `sudo /root/install-erpnext-dev.sh install-insights` |

Advanced app tools are separated from the curated app list:

```bash
sudo /root/install-erpnext-dev.sh advanced-app-tools
```

The advanced tools menu includes custom Git app installation and app registry repair. Custom Git app installation is intentionally protected with stronger warnings because third-party apps can be incompatible, untrusted, or unsafe for the current Frappe/ERPNext version.

Recommended optional app test order:

```text
1. Payments
2. HR / HRMS
3. CRM
4. Education
5. Learning / LMS
6. Webshop / E-Commerce
7. Builder
8. Helpdesk
9. Insights
10. Wiki
11. Print Designer
12. Drive
13. Raven Chat
14. Telephony
```

Install one optional app at a time and keep a backup/snapshot checkpoint before major changes.

---

## SSL mode guide

```bash
sudo /root/install-erpnext-dev.sh ssl-mode-status
sudo /root/install-erpnext-dev.sh ssl-mode-guide
sudo /root/install-erpnext-dev.sh ssl-compatibility
sudo /root/install-erpnext-dev.sh production-ssl-wizard
```

| Mode | Best for | Notes |
|---|---|---|
| Local self-signed / mkcert-style | Local VM | Development only |
| Let's Encrypt | Public VM, DNS directly to VM | Requires HTTP-01 validation on port 80 |
| Cloudflare Origin CA | Public VM behind Cloudflare proxy | Requires Cloudflare proxy and Full (strict) |

Local SSL commands:

```bash
sudo /root/install-erpnext-dev.sh local-ssl-wizard
sudo /root/install-erpnext-dev.sh verify-local-ssl
sudo /root/install-erpnext-dev.sh disable-local-ssl
```

Production SSL commands:

```bash
sudo /root/install-erpnext-dev.sh production-ssl-wizard
sudo /root/install-erpnext-dev.sh configure-cloudflare-origin-ssl
sudo /root/install-erpnext-dev.sh production-ssl-status
sudo /root/install-erpnext-dev.sh disable-production-ssl
```

---

## Security hardening

```bash
sudo /root/install-erpnext-dev.sh security-hardening-wizard
sudo /root/install-erpnext-dev.sh configure-vm-firewall
sudo /root/install-erpnext-dev.sh vm-firewall-status
sudo /root/install-erpnext-dev.sh configure-fail2ban
sudo /root/install-erpnext-dev.sh fail2ban-status
sudo /root/install-erpnext-dev.sh firewall-hardening-status
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
sudo /root/install-erpnext-dev.sh doctor
sudo /root/install-erpnext-dev.sh doctor --plain
sudo /root/install-erpnext-dev.sh doctor --json
sudo /root/install-erpnext-dev.sh verify-access
sudo /root/install-erpnext-dev.sh support-bundle
sudo /root/install-erpnext-dev.sh command-audit
sudo /root/install-erpnext-dev.sh credentials-info
sudo /root/install-erpnext-dev.sh next-step
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
VM/cloud snapshot policy
Cloud firewall rules
DNS/proxy/SSL ownership
Update process
Monitoring and alerting expectations
```
