# ERPNext Developer Toolkit v1.1.30

![ERPNext Toolkit Banner](docs/assets/erp_installer_readme_banner.png)

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

### Command path note — why `/tmp` first and `erpnext-dev` later

The first `curl` command downloads the toolkit to a unique temporary bootstrap file under `/tmp`, for example:

```bash
/tmp/erpnext-dev.A1b2C3.sh
```

That path is used only as a **temporary bootstrap copy**. The command uses `mktemp` so root-owned and normal-user runs cannot collide with each other during repeated tests.

After the toolkit runs with `sudo`, it saves the stable root-owned copy here:

```bash
/opt/erpnext-dev/erpnext-dev.sh
```

It also creates this short command:

```bash
/usr/local/bin/erpnext-dev
```

Use the paths this way:

```text
Fresh VM / first copied command:  sudo "$tmp" <command>
After first run or update:        sudo erpnext-dev <command>
Stable toolkit file:              /opt/erpnext-dev/erpnext-dev.sh
Short command:                    /usr/local/bin/erpnext-dev
```

If `erpnext-dev` does not exist yet, run one of the quickstart commands below or use **Option E** to install/repair the CLI command.

### Option A — check the VM before installing

Use this first when testing a fresh VM. It checks OS, internet access, CPU, RAM, root disk, and `/tmp` free space before the heavy install begins:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" install-preflight
```

If the VM is clearly unsafe for ERPNext, the installer blocks the install and prints a red `INSTALL BLOCKED` summary explaining what to fix.

### Option B — local VM development install

Use this inside a fresh local VM for testing or development:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" local-dev-quickstart
```

Recommended local hostname:

```text
erp.test
```

### Option C — public VPS / cloud VM install

Use this inside a fresh public VM when you have a real domain or subdomain ready:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" public-vm-quickstart
```

Recommended public hostname:

```text
erp.example.com
```

### Option D — open the guided installer menu

Use this if you want to choose the setup path interactively:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" menu
```

### Option E — update or repair the toolkit command

Use this on a VM where you want to update the toolkit and create/repair the short `erpnext-dev` command:

```bash
tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" install-cli && sudo erpnext-dev version
```

Then open the main menu or production operations wizard:

```bash
sudo erpnext-dev menu
sudo erpnext-dev production-ops-wizard
```

Useful toolkit command checks:

```bash
erpnext-dev --help
erpnext-dev version
erpnext-dev where-installed
sudo erpnext-dev update-toolkit
sudo erpnext-dev repair-cli
```

### Option F — optional apps wizard

Use this only after the core ERPNext install is healthy:

```bash
sudo erpnext-dev app-install-wizard
```

After any quickstart finishes, use this stable path for follow-up commands:

```bash
sudo erpnext-dev <command>
```

Common examples:

```bash
sudo erpnext-dev version
sudo erpnext-dev doctor --plain
sudo erpnext-dev verify-access
sudo erpnext-dev credentials-info
sudo erpnext-dev production-ops-wizard
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
- [Reusable toolkit command](#reusable-toolkit-command)
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
sudo "$tmp" install-preflight
```

or after the script has been copied to the reusable path:

```bash
sudo erpnext-dev install-preflight
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
ERPNEXT_ALLOW_UNSAFE_INSTALL=true sudo "$tmp" local-dev-quickstart
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
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" local-dev-quickstart
```

The quickstart installs the toolkit into the VM and creates the short command:

```bash
/opt/erpnext-dev/erpnext-dev.sh
/usr/local/bin/erpnext-dev
```

Use `sudo erpnext-dev` for follow-up commands, including SSL setup and optional app installation. Do not use `./erpnext-dev.sh` unless you are in the directory that contains the script.

Recommended local site name:

```text
erp.test
```

After the installer finishes, validate inside the VM:

```bash
sudo erpnext-dev version
sudo erpnext-dev doctor --plain
sudo erpnext-dev verify-access
sudo erpnext-dev access-info
sudo erpnext-dev backup-files
sudo erpnext-dev backup-status
sudo erpnext-dev backup-verify
sudo erpnext-dev credentials-info
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
sudo erpnext-dev mkcert-guide
```

The guide separates HOST commands from VM commands. In short: generate and trust the certificate on the Linux HOST, copy the cert/key into the VM with `scp`, then run the local SSL wizard inside the VM:

```bash
sudo erpnext-dev local-ssl-wizard
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
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" public-vm-quickstart
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
sudo erpnext-dev cloudflare-origin-guide
sudo erpnext-dev configure-cloudflare-origin-ssl
sudo erpnext-dev cloudflare-origin-ssl-status
```

For Let's Encrypt mode:

```text
DNS record: DNS-only / direct to VM
Port 80: reachable during certificate issuance
```

Helpful public SSL commands:

```bash
sudo erpnext-dev production-ssl-plan
sudo erpnext-dev production-ssl-wizard
sudo erpnext-dev production-ssl-status
```

After installation, validate:

```bash
sudo erpnext-dev release-readiness
sudo erpnext-dev production-checklist
sudo erpnext-dev backup-verify
sudo erpnext-dev support-bundle
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

## Reusable toolkit command

The toolkit intentionally uses a temporary bootstrap file first, then a stable installed command:

```text
/tmp/erpnext-dev.XXXXXX.sh           temporary bootstrap copy created by mktemp
/opt/erpnext-dev/erpnext-dev.sh     stable root-owned toolkit file
/usr/local/bin/erpnext-dev              short command for daily use
```

Why `/tmp` first? The README one-liners download to a unique `mktemp` file under `/tmp` because it is writable by a normal sudo user and avoids modifying system-owned paths until the toolkit is actually executed with `sudo`. The `/tmp` copy should not be treated as permanent because `/tmp` may be cleaned by the OS.

Why `/opt` later? During quickstart, preflight, and CLI repair flows, the toolkit copies itself to:

```bash
/opt/erpnext-dev/erpnext-dev.sh
```

Then it creates the short command:

```bash
/usr/local/bin/erpnext-dev
```

Use `sudo erpnext-dev` for follow-up maintenance, backups, SSL, app installs, diagnostics, and production operations:

```bash
sudo erpnext-dev version
sudo erpnext-dev status
sudo erpnext-dev doctor --plain
sudo erpnext-dev verify-access
sudo erpnext-dev production-ops-wizard
```

To update or repair the toolkit command from GitHub:

```bash
tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" install-cli && sudo erpnext-dev version
```

To check where the toolkit is installed:

```bash
erpnext-dev where-installed
```

---

## Accessing ERPNext credentials

After installation, the installer saves the generated ERPNext Administrator password and database credentials on the VM.

Use the safe overview command first. It shows where the credentials are stored, but it does **not** print passwords:

```bash
sudo erpnext-dev credentials-info
```

To display the generated password on a private VM console, use the guarded command below. It warns first and requires confirmation before printing secrets:

```bash
sudo erpnext-dev credentials-show
```

The ERPNext web login normally uses:

```text
Username: Administrator
Password: value shown by credentials-show
```

Check the credentials file owner and permissions:

```bash
sudo erpnext-dev credentials-file-status
```

Secure the credentials file with root-only permissions:

```bash
sudo erpnext-dev credentials-secure
```

After saving the credentials in a password manager or completing production handoff, remove the local plaintext credentials file:

```bash
sudo erpnext-dev credentials-delete
```

Reset the ERPNext Administrator password safely without manually changing directories or relying on the current user's `bench` PATH:

```bash
sudo erpnext-dev reset-admin-password
```

The credentials file is intentionally excluded from diagnostics, support bundles, shared logs, and generated support archives. Do not paste credentials into public tickets, GitHub issues, screenshots, or support chats.

---

## Production operations

Open the production operations wizard:

```bash
sudo erpnext-dev production-ops-wizard
```

Common operations commands:

```bash
sudo erpnext-dev release-readiness
sudo erpnext-dev production-checklist
sudo erpnext-dev health-check
sudo erpnext-dev configure-health-check-timer
sudo erpnext-dev health-check-status
sudo erpnext-dev service-recovery-plan
```

Health checks cover ERPNext runtime, Nginx, MariaDB, Redis, HTTPS, disk usage, latest backup state, UFW, Fail2Ban, scheduled backup timer, and off-VM backup state.

---

## Backups and restore safety

Create and verify a local database + files backup:

```bash
sudo erpnext-dev backup-files
sudo erpnext-dev backup-status
sudo erpnext-dev backup-verify
```

Scheduled local backups:

```bash
sudo erpnext-dev backup-schedule-plan
sudo erpnext-dev configure-backup-schedule
sudo erpnext-dev backup-schedule-status
```

Backup retention:

```bash
sudo erpnext-dev backup-retention-plan
sudo erpnext-dev backup-retention-status
sudo erpnext-dev cleanup-old-backups-dry-run
sudo erpnext-dev cleanup-old-backups
```

Off-VM backup planning and rsync target setup:

```bash
sudo erpnext-dev off-vm-backup-plan
sudo erpnext-dev configure-rsync-backup-target
sudo erpnext-dev off-vm-backup-dry-run
sudo erpnext-dev run-off-vm-backup
sudo erpnext-dev off-vm-backup-status
```

Restore safety checks:

```bash
sudo erpnext-dev restore-preflight
sudo erpnext-dev restore-rehearsal-guide
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
sudo erpnext-dev backup-files
sudo erpnext-dev backup-verify
sudo erpnext-dev backup-status
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
sudo erpnext-dev app-library
sudo erpnext-dev app-compatibility
sudo erpnext-dev app-install-wizard
sudo erpnext-dev app-status
```

Curated app library:

| App | Direct command |
|---|---|
| CRM | `sudo erpnext-dev install-crm` |
| HR / HRMS | `sudo erpnext-dev install-hrms` |
| Education | `sudo erpnext-dev install-education` |
| Payments | `sudo erpnext-dev install-payments` |
| Webshop / E-Commerce | `sudo erpnext-dev install-webshop` |
| Builder | `sudo erpnext-dev install-builder` |
| Learning / LMS | `sudo erpnext-dev install-lms` |
| Wiki | `sudo erpnext-dev install-wiki` |
| Print Designer | `sudo erpnext-dev install-print-designer` |
| Drive | `sudo erpnext-dev install-drive` |
| Raven Chat | `sudo erpnext-dev install-raven` |
| Helpdesk | `sudo erpnext-dev install-helpdesk` |
| Telephony | `sudo erpnext-dev install-telephony` |
| Insights | `sudo erpnext-dev install-insights` |


### Education app access note

After installing **Education**, the normal website root may open or redirect to the Education portal. This is expected behavior for an Education-focused site and does not mean ERPNext Desk is gone.

Use these paths:

```text
ERPNext / Frappe Desk: /app
Login page:            /login
Education portal:      /edu-portal/students
```

Helpful commands:

```bash
sudo erpnext-dev access-info
sudo erpnext-dev education-access-info
sudo erpnext-dev verify-access
```

For a local VM, examples are:

```text
http://LOCAL_VM_IP:8000/app
http://LOCAL_VM_IP:8000/login
http://LOCAL_VM_IP:8000/edu-portal/students
```

Advanced app tools are separated from the curated app list:

```bash
sudo erpnext-dev advanced-app-tools
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
sudo erpnext-dev ssl-mode-status
sudo erpnext-dev ssl-mode-guide
sudo erpnext-dev ssl-compatibility
sudo erpnext-dev production-ssl-wizard
```

| Mode | Best for | Notes |
|---|---|---|
| Local self-signed / mkcert-style | Local VM | Development only |
| Let's Encrypt | Public VM, DNS directly to VM | Requires HTTP-01 validation on port 80 |
| Cloudflare Origin CA | Public VM behind Cloudflare proxy | Requires Cloudflare proxy and Full (strict) |

Local SSL commands:

```bash
sudo erpnext-dev local-ssl-wizard
sudo erpnext-dev verify-local-ssl
sudo erpnext-dev disable-local-ssl
```

Production SSL commands:

```bash
sudo erpnext-dev production-ssl-wizard
sudo erpnext-dev configure-cloudflare-origin-ssl
sudo erpnext-dev production-ssl-status
sudo erpnext-dev disable-production-ssl
```

---

## Security hardening

```bash
sudo erpnext-dev security-hardening-wizard
sudo erpnext-dev configure-vm-firewall
sudo erpnext-dev vm-firewall-status
sudo erpnext-dev configure-fail2ban
sudo erpnext-dev fail2ban-status
sudo erpnext-dev firewall-hardening-status
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
sudo erpnext-dev doctor
sudo erpnext-dev doctor --plain
sudo erpnext-dev doctor --json
sudo erpnext-dev verify-access
sudo erpnext-dev support-bundle
sudo erpnext-dev command-audit
sudo erpnext-dev credentials-info
sudo erpnext-dev credentials-file-status
sudo erpnext-dev next-step
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
