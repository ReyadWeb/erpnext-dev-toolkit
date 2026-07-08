# ERPNext Developer Toolkit v1.1.40

![ERPNext Toolkit Banner](docs/assets/erp_installer_readme_banner.png)

A guided installer and operations toolkit for ERPNext/Frappe on Ubuntu and Debian-family VMs.

It supports two main setup paths:

- **Local development VM** using a local test hostname such as `erp.test`.
- **Public VPS / cloud VM** using a real domain or subdomain such as `erp.example.com`.

The project also includes production operations helpers for SSL, firewall hardening, scheduled backups, backup retention, off-VM backup planning, health checks, restore preflight, optional app installation, diagnostics, support bundles, and safe maintenance workflows.

The day-to-day menu exposes **Local VM HTTPS / SSL**, **Production HTTPS / SSL**, and **Optional apps** as first-level actions after installation.

Interactive menus use a shared navigation reader: `q`/`Q` quits, `b`/`B` goes back where supported, and `sudo erpnext-dev menu-self-test` validates the menu navigation paths without running destructive actions.

> Version history is maintained in [`CHANGELOG.md`](CHANGELOG.md). This README intentionally focuses on current installation, operations, and usage.

---

## Start here

Copy one command into a fresh **Debian-family Linux VM** such as Ubuntu or Debian. The VM needs `sudo` access and internet access.

Most users should start with the **general guided setup** because it lets them choose local or production from the installer menu.

### General guided setup — choose local or production

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" start-here
```

Use this when you want the toolkit to ask which path to follow. The wizard offers:

```text
1) Local development VM
2) Public VM / production-candidate
3) Existing install / maintenance menu
```

Site name guidance after the command:

```text
Local VM default:        erp.test
Production example:     erp.example.com
```

For local VMs, the installer prints the correct host `/etc/hosts` command using the VM IP it detects on that machine. Do not copy another user's sample IP.

### Local VM install

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" local-dev-quickstart
```

Use this inside a local VM for development, testing, or app evaluation. The wizard asks for the local domain near the beginning. Press **Enter** to use:

```text
erp.test
```

After the local install finishes, the toolkit prints the direct IP URL, the friendly local URL, and a required host mapping checkpoint before local HTTPS. The most common follow-up commands are:

```bash
sudo erpnext-dev local-host-checkpoint
sudo erpnext-dev local-ssl-wizard
sudo erpnext-dev local-domain-status
sudo erpnext-dev local-access-doctor
sudo erpnext-dev local-fixed-ip-guide
```

Run the printed `/etc/hosts` command on the **host machine**, not inside the VM. It is safe to repeat because the command backs up `/etc/hosts`, removes only the old entry for the selected local domain, and adds the current VM IP. Then run the local SSL wizard when HTTP access is confirmed.

### Production VPS / cloud VM install

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" public-vm-quickstart
```

Use this inside a fresh public VM when you have a real domain or subdomain ready. Example production site name:

```text
erp.example.com
```

Before production HTTPS, make sure DNS points to the VM or your Cloudflare/proxy setup is ready.

### Check the VM before installing

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" install-preflight
```

Use this when you only want to verify OS, internet access, CPU, RAM, disk, and temporary storage before starting the full install.

If the VM is clearly unsafe for ERPNext, the installer blocks the install and prints a red `INSTALL BLOCKED` summary explaining what to fix.

### Update or repair the `erpnext-dev` command

```bash
tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" install-cli && erpnext-dev version
```

Use this on an existing VM to install, update, or repair the reusable toolkit command.

Then use the stable command:

```bash
sudo erpnext-dev menu
sudo erpnext-dev production-ops-wizard
```

### Optional apps wizard

```bash
sudo erpnext-dev app-install-wizard
```

Use this only after the core ERPNext install is healthy.

### Common follow-up commands

After the first quickstart or `install-cli` run, use `erpnext-dev` for normal operations:

```bash
erpnext-dev --help
erpnext-dev version
erpnext-dev where-installed
sudo erpnext-dev menu
sudo erpnext-dev doctor --plain
sudo erpnext-dev verify-access
sudo erpnext-dev credentials-info
sudo erpnext-dev update-toolkit
sudo erpnext-dev repair-cli
```

### What the first command does

The long first-run command downloads a temporary bootstrap copy, runs it with `sudo`, then installs the stable toolkit command.

After the first run, the stable files are:

```text
Toolkit file:  /opt/erpnext-dev/erpnext-dev.sh
CLI command:   /usr/local/bin/erpnext-dev
Daily command: sudo erpnext-dev <command>
```

The temporary file under `/tmp` is only used for the first bootstrap or update. It is not the long-term toolkit location.

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
| Local VM testing/dev | `local-dev-quickstart` | prompts; Enter defaults to `erp.test` |
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

For local VM domain access, print the required host-side mapping checkpoint from inside the VM:

```bash
sudo erpnext-dev local-host-checkpoint
sudo erpnext-dev local-domain-status
sudo erpnext-dev host-dns-guide
```

Run the printed `/etc/hosts` command on the **host machine**. This is safe to repeat after VM recreation or DHCP IP changes. Then test access from the host:

```bash
getent hosts erp.test
curl -I http://erp.test:8000
```

The VM IP is detected dynamically. Do not copy a sample IP from another machine.

If the VM is deleted and recreated, rerun `sudo erpnext-dev local-host-checkpoint` from inside the VM and apply the printed command on the host. This prevents `erp.test` from pointing to an old VM.

If local HTTPS is enabled, also test:

```bash
curl -Ik https://erp.test
```

For trusted local HTTPS with mkcert, use the guided setup inside the VM:

```bash
sudo erpnext-dev trusted-mkcert-setup
```

The wizard prints the HOST-side `mkcert` commands, checks whether the certificate/key were copied into `/tmp/` on the VM, and can install/configure/verify HTTPS when they are present. The full reference guide is still available:

```bash
sudo erpnext-dev mkcert-guide
```

The guide separates HOST commands from VM commands. In short: generate and trust the certificate on the Linux HOST, copy the cert/key into the VM with `scp`, then run the local SSL wizard inside the VM:

```bash
sudo erpnext-dev local-ssl-wizard
```

When the Local SSL Wizard is launched directly, `b`/`B` returns to the main menu. When it is launched from the Local VM HTTPS / SSL menu, `b`/`B` returns to that SSL menu.

After HTTPS is verified, continue with the safe local profile:

```bash
sudo erpnext-dev security-hardening-wizard
```

Choose `2) Local VM firewall profile`. Do not choose the production firewall profile for a local `erp.test` VM.

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

### Local VM domain selection and rename

During `local-dev-quickstart`, the toolkit asks for the local VM domain / Frappe site name. Press Enter to use the default:

```text
erp.test
```

To change it after installation, use:

```bash
sudo erpnext-dev change-local-domain
```

The wizard backs up the existing site when possible, runs the Frappe site rename, updates the Bench default site, updates the toolkit config, disables the old local SSL Nginx site, and prints the exact `/etc/hosts` commands to run on the host machine. Rebuild local SSL after a domain change because certificates are domain-specific.

### Local VM host DNS mapping

A local `.test` name such as `erp.test` is not public DNS. Your **host machine** must map the chosen local domain to the VM's current IP. The IP is not hardcoded because every user environment can be different: KVM may use `192.168.122.x`, bridged networking may use your LAN range, and other hypervisors may use `10.x` or another private range.

Use the toolkit to print the correct host-side command for the current VM. Run this checkpoint after every fresh local VM install, after deleting/recreating a VM, and before local HTTPS:

```bash
sudo erpnext-dev local-host-checkpoint
sudo erpnext-dev local-domain-status
sudo erpnext-dev host-dns-guide
sudo erpnext-dev local-access-doctor
```

If the host shows this error:

```text
curl: (6) Could not resolve host: erp.test
```

that is a host DNS mapping issue. Run the command printed by `host-dns-guide` on the **host machine**, then test again with:

```bash
getent hosts erp.test
curl -I http://erp.test:8000
```

For KVM/libvirt, a fixed DHCP reservation is recommended so the VM IP does not change after reboot. The toolkit cannot safely edit the host's libvirt network from inside the guest VM, but it can print the host-side reservation steps:

```bash
sudo erpnext-dev network-status
sudo erpnext-dev local-fixed-ip-guide
```

Aliases for the same guide:

```bash
sudo erpnext-dev kvm-guide
sudo erpnext-dev kvm-fixed-ip-guide
sudo erpnext-dev fixed-ip-guide
```

Local SSL commands:

```bash
sudo erpnext-dev local-ssl-menu
sudo erpnext-dev local-ssl-wizard
sudo erpnext-dev change-local-domain
sudo erpnext-dev verify-local-ssl
sudo erpnext-dev disable-local-ssl
```

Local security command after HTTPS works:

```bash
sudo erpnext-dev security-hardening-wizard
# choose: 2) Local VM firewall profile
```

The main menu has separate **Local VM HTTPS / SSL** and **Production HTTPS / SSL** options. Use local HTTPS for VM domains such as `erp.test`; use production HTTPS only for public domains.

Production SSL commands:

```bash
sudo erpnext-dev production-ssl-menu
sudo erpnext-dev production-ssl-wizard
sudo erpnext-dev configure-cloudflare-origin-ssl
sudo erpnext-dev production-ssl-status
sudo erpnext-dev disable-production-ssl
```

---

## Security hardening

### Environment-aware security profiles

Use the profile that matches the VM type. Do not apply the production firewall profile to a local `.test` VM unless local HTTPS/Nginx has fully replaced direct Bench access.

```bash
sudo erpnext-dev security-mode-status
sudo erpnext-dev security-hardening-wizard

# Local VM / erp.test profile
sudo erpnext-dev local-firewall-profile

# Repair local access if hardening blocked erp.test or port 8000
sudo erpnext-dev repair-local-access

# Production profile, only after real domain + HTTPS are verified
sudo erpnext-dev production-firewall-profile

# Inspect rollback snapshots created before UFW changes
sudo erpnext-dev firewall-rollback-snapshots
```

Local VM profile keeps `8000` and `9000` reachable from private networks for development. Production profile blocks direct backend ports and leaves only SSH, HTTP, and HTTPS open at the VM firewall layer.

### Recommended setup lifecycle

```bash
sudo erpnext-dev setup-lifecycle-plan
```

The intended order is: requirements, domain, install, verification, backup checkpoint, SSL, security profile, optional apps, backup after every app, final QA and credentials handoff.


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


### Checking installed optional apps

After installing each optional app, run:

```bash
sudo erpnext-dev app-status
```

The App Installation Wizard also has `Installed apps / status` as the first option. It lists the apps installed on the site, downloaded app folders, and any downloaded app that is not installed or not registered.

Recommended verification after each optional app install:

```bash
sudo erpnext-dev verify-access
sudo erpnext-dev verify-local-ssl
sudo erpnext-dev local-access-doctor
sudo erpnext-dev app-status
```
