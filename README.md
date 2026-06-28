# ERPNext Developer Installer

## v0.5.8 Notes

v0.5.8 is a polish release after the full App Library validation. It keeps the v0.5.8 Helpdesk → Telephony dependency handling and adds cleaner status UX for public beta preparation.

What changed:

- Added `./install-erpnext-dev.sh app-status` for a compact optional-app status report.
- Added optional app status lines to `doctor` / full health report.
- Reduced repeated full browser instructions after service start/restart; the script now shows a compact ready summary and points users to `./install-erpnext-dev.sh access` for full instructions.
- Normalizes `sites/apps.txt` in a predictable curated order: `frappe`, `erpnext`, `crm`, `hrms`, `telephony`, `helpdesk`, `insights`, then custom apps.
- Added `ROADMAP.md` to document future development toward public beta and v1.0.



## v0.5.8 Notes

This release fixes the App Registry Repair command and hardens `sites/apps.txt` normalization by using an external temporary Python repair script instead of embedding a Python here-document inside a generated shell command. This prevents `PY_APP_REGISTRY` here-document parsing errors and makes `./install-erpnext-dev.sh repair-app-registry` available from command mode.

## v0.5.8 reliability update

This release improves App Library resume behavior when an app folder was downloaded but the app was not registered in `sites/apps.txt`. The installer now checks downloaded apps against both site installation and Bench registration, safely adds a downloaded app to `sites/apps.txt` before `install-app`, and removes the noisy integer comparison warning in the app listing screen.


## v0.5.8 Reliability Fix

This release hardens the internal `run_as_frappe` command wrapper by running Frappe-user commands through a temporary shell script instead of passing long multi-line command strings directly through `bash -lc`. This prevents command-collapsing issues such as `set -eexport` or `if ... then` syntax errors during App Library installs.


A developer-friendly installer manager for setting up a local **Frappe + ERPNext** environment on Ubuntu.

This project is designed for local developer VMs, test labs, and evaluation environments. It is especially useful when running ERPNext inside KVM/libvirt, VirtualBox, VMware, or a similar virtualization platform.

> This installer is for **development environments only**.  
> Do **not** use this as-is for production servers.

---

## Current Version

```text
v0.5.8
```

This version builds on the verified App Library release with polish for status reporting, restart UX, and public-beta planning. It can show installed apps, summarize optional app status, and install selected Frappe apps such as CRM, HRMS, Telephony, Helpdesk, and Insights.

---

## v0.5.8 App Library

v0.5.8 adds an optional App Library for installing common Frappe ecosystem apps into the local ERPNext developer VM.

Included app profiles:

- Frappe CRM
- Frappe HR / HRMS
- Frappe Telephony
- Frappe Helpdesk
- Frappe Insights
- Custom trusted Frappe app from Git URL

The App Library is intentionally safety-focused:

- Shows currently installed apps before/after installation.
- Offers a database + files backup before app installation.
- Validates app names and branch names.
- Checks the requested Git branch before downloading when a branch is specified.
- Runs install-app, migrate, build, clear-cache, and service restart/readiness checks.
- Allows branch overrides through environment variables.

Example branch overrides:

```bash
CRM_BRANCH=main ./install-erpnext-dev.sh install-crm
HRMS_BRANCH=version-16 ./install-erpnext-dev.sh install-hrms
HELPDESK_BRANCH=main ./install-erpnext-dev.sh install-helpdesk
INSIGHTS_BRANCH=main ./install-erpnext-dev.sh install-insights
```

The previous v0.4.2 service readiness improvements remain available. Start/restart actions wait visibly for Bench web, Socket.io, Redis queue, and Redis cache ports before showing browser instructions.

The Backup / Restore / Maintenance tools also remain available:

- Create a database backup.
- Create a database + files backup.
- List available backups.
- Restore a database backup with strong confirmation.
- Restore database + files with strong confirmation.
- Run common maintenance tasks: migrate, build assets, clear cache, restart service.
- Keep restore operations protected with an emergency pre-restore backup attempt.

The previous health-report polish remains: the installer checks helper files, credentials, and `common_site_config.json` using the resolved bench path and sudo-aware file checks.

The previous v0.3.3 reliability fix also remains: the installer uses shared bench-path detection to prevent false errors when the bench folder exists under:

```text
/home/frappe/frappe/frappe-bench
```

but the installer is being run from another Linux user such as `test`.

Important behavior change:

```text
ERPNext installation success is separate from optional service/autostart/start success.
```

If ERPNext installs correctly but the service cannot be created or started automatically, the installer now shows a warning and keeps the environment usable. You can still start ERPNext with:

```bash
./install-erpnext-dev.sh start
```

or manually:

```bash
sudo -iu frappe
cd /home/frappe/frappe/frappe-bench
bench start
```


## What This Installer Does

The recommended setup can install and configure:

- Frappe Framework
- ERPNext
- Frappe Bench
- MariaDB
- Redis
- Node.js through nvm
- Yarn
- Python through uv
- Local ERPNext site
- Start helper script
- Optional ERPNext development systemd service
- Optional autostart on VM boot
- Backup / restore tools
- Maintenance tasks for migrate/build/cache/restart
- Optional App Library for Frappe CRM, HRMS, Helpdesk, Insights, and custom apps

Default local site:

```text
erp.test
```

Default local development URL:

```text
http://erp.test:8000
```

Direct IP fallback:

```text
http://VM_IP:8000
```

---


### v0.5.8 readiness polish

v0.5.8 makes service start and restart clearer. After `start`, `restart`, `service-start`, or `service-restart`, the script shows visible waiting output while checking required development ports. This prevents confusion when systemd reports the service as running but Bench is still starting internally.

### v0.4.1 backup listing polish

v0.4.1 fixed the backup listing display so public file backups and private file backups are categorized separately. It also added backup counts and shows `none` when a category has no files yet.

Correct backup grouping:

```text
Database backups
  *-database.sql.gz

Public file backups
  *-files.tar

Private file backups
  *-private-files.tar
```

## Target Environment

Recommended environment:

```text
OS: Ubuntu 24.04 LTS or Ubuntu 26.04 LTS
Use case: Local development / KVM VM / test environment
Mode: Development, not production
```

Recommended VM resources:

```text
CPU: 4 cores minimum
RAM: 8 GB recommended
Disk: 60 GB recommended
Network: NAT or bridged
```

---

## Important: Run Inside the Ubuntu VM

Run this installer inside the **target Ubuntu Server VM**, not on your Linux Mint/Desktop host machine.

Correct:

```text
Ubuntu Server VM → run installer here
```

Incorrect:

```text
Linux Mint host → do not run installer here
```

The script intentionally exits if it detects an unsupported operating system.

---

## Quick Start

Inside the fresh Ubuntu Server VM:

```bash
sudo apt update
sudo apt install -y curl ca-certificates
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh
```

Then choose:

```text
1) Recommended Setup
```

---

## One-Command Recommended Setup

Inside the Ubuntu VM:

```bash
sudo apt update && sudo apt install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o install-erpnext-dev.sh && chmod +x install-erpnext-dev.sh && ./install-erpnext-dev.sh setup
```

---

## Menu Layout

v0.5.8 keeps the main menu simple:

```text
1) Recommended Setup
2) Start ERPNext
3) Stop ERPNext
4) Status
5) Access Instructions
6) Backup / Maintenance
7) App Library
8) Advanced Options
9) Help
10) Exit
```

The main menu is intended for normal daily use.

The Status option opens a focused status submenu instead of dumping every diagnostic check at once:

```text
1) Status Summary
2) Runtime Status
3) Installation Status
4) Service / Autostart Status
5) Full Health Report
6) Back
```

Status is intentionally split into separate concepts:

```text
Installed / not installed      = files, bench, apps, and site exist
Running / stopped              = web/service/bench runtime state
Autostart enabled / disabled   = whether systemd starts ERPNext on VM boot
```

This prevents a stopped ERPNext service from being incorrectly reported as "not installed".

In interactive mode, each status screen waits for Enter before returning to the Status menu. This avoids pushing the useful output out of view in small terminal windows.

Advanced tools are under:

```text
7) Advanced Options
```

Advanced Options include repair, uninstall/reset, full diagnostics, autostart service management, KVM fixed IP guidance, and multi-environment guidance.

---

## Recommended Setup

Recommended Setup installs ERPNext and then offers to:

```text
- Enable ERPNext autostart when the VM boots
- Start ERPNext now in the background service
```

Command mode:

```bash
./install-erpnext-dev.sh setup
```

`install` is an alias:

```bash
./install-erpnext-dev.sh install
```

Optional non-interactive style:

```bash
AUTO_START=true ENABLE_AUTOSTART=true ./install-erpnext-dev.sh setup
```

Disable both prompts:

```bash
AUTO_START=false ENABLE_AUTOSTART=false ./install-erpnext-dev.sh setup
```

---

## Start / Stop ERPNext

Start ERPNext in the background service:

```bash
./install-erpnext-dev.sh start
```

Stop ERPNext:

```bash
./install-erpnext-dev.sh stop
```

Show quick status:

```bash
./install-erpnext-dev.sh status
```

Open the interactive status menu:

```bash
./install-erpnext-dev.sh status-menu
```

Show full diagnostics:

```bash
./install-erpnext-dev.sh doctor
```

Show recent service logs:

```bash
./install-erpnext-dev.sh logs
```

Follow service logs live:

```bash
./install-erpnext-dev.sh logs-follow
```

---

## Status Commands

Status summary in command mode:

```bash
./install-erpnext-dev.sh status
```

Interactive status submenu with readable screens and Back option:

```bash
./install-erpnext-dev.sh status-menu
```

Runtime and port status:

```bash
./install-erpnext-dev.sh runtime-status
```

Installation and site status:

```bash
./install-erpnext-dev.sh install-status
```

Service and autostart summary:

```bash
./install-erpnext-dev.sh service-summary
```

Full health report:

```bash
./install-erpnext-dev.sh doctor
```

Useful interpretation:

```text
Installed + Stopped      → run ./install-erpnext-dev.sh start
Installed + Running      → open the browser URL
Autostart Disabled       → optional: run ./install-erpnext-dev.sh enable-autostart
Not installed            → run ./install-erpnext-dev.sh setup
Incomplete               → run repair or perform a clean setup
```


### v0.5.8 reliability note

v0.5.8 fixes a shell-prefix formatting issue in App Library commands. In v0.5.1, some `sudo -iu frappe bash -lc` calls could collapse environment setup commands together, causing errors such as `syntax error near unexpected token then`. The command runner now uses a semicolon-separated Frappe shell prefix so `bench`, `node`, `npm`, and `yarn` commands run reliably as the `frappe` user.

## App Library

Open the App Library menu:

```bash
./install-erpnext-dev.sh app-library
```

Alias:

```bash
./install-erpnext-dev.sh apps
```

Show installed and downloaded apps:

```bash
./install-erpnext-dev.sh list-apps
```

Curated app install commands:

```bash
./install-erpnext-dev.sh install-crm
./install-erpnext-dev.sh install-hrms
./install-erpnext-dev.sh install-helpdesk
./install-erpnext-dev.sh install-insights
```

Interactive custom app installer:

```bash
./install-erpnext-dev.sh install-custom-app
```

App Library menu:

```text
1) Show installed apps
2) Install Frappe CRM
3) Install Frappe HR / HRMS
4) Install Frappe Helpdesk
5) Install Frappe Insights
6) Install custom app from Git URL
7) Back
```

Important notes:

- ERPNext already includes classic CRM features. Frappe CRM is a separate modern CRM app.
- Optional apps can take several minutes to download, install, migrate, and build.
- Use VM snapshots before testing optional apps on an important environment.
- For production or business use, confirm app compatibility before installing.
- The script offers a backup before installing an optional app.

## Backup / Restore / Maintenance

Open the backup and maintenance menu:

```bash
./install-erpnext-dev.sh backup-menu
```

The main menu also includes:

```text
6) Backup / Maintenance
```

Common backup commands:

```bash
./install-erpnext-dev.sh backup
./install-erpnext-dev.sh backup-files
./install-erpnext-dev.sh list-backups
```

Available backup menu options:

```text
1) Create database backup
2) Create database + files backup
3) List backups
4) Restore database backup
5) Restore database + files backup
6) Maintenance tasks
7) Back
```

Backups are stored under the site private backups folder:

```text
/home/frappe/frappe/frappe-bench/sites/erp.test/private/backups
```

Restore actions are intentionally protected. Before restoring, the script:

```text
- Shows the available backups
- Requires the user to type RESTORE
- Attempts an emergency backup before restore
- Stops the ERPNext service during restore
- Runs migrate, build, and clear-cache after restore
- Restarts the service if it was running before restore
```

Maintenance command shortcuts:

```bash
./install-erpnext-dev.sh maintenance
./install-erpnext-dev.sh migrate
./install-erpnext-dev.sh build
./install-erpnext-dev.sh clear-cache
./install-erpnext-dev.sh restart
./install-erpnext-dev.sh wait-ready
```

Maintenance menu options:

```text
1) Run migrate
2) Build assets
3) Clear cache
4) Restart ERPNext service
5) Run safe repair
6) Show recent service logs
7) Back
```

> For real business or production use, backup/restore must be tested before relying on the system. A backup is only useful if it can be restored successfully.

---

## Autostart on VM Boot

v0.5.8 can create a local development systemd service:

```text
erpnext-dev.service
```

Enable autostart:

```bash
./install-erpnext-dev.sh enable-autostart
```

Disable autostart:

```bash
./install-erpnext-dev.sh disable-autostart
```

Start service:

```bash
./install-erpnext-dev.sh service-start
```

Stop service:

```bash
./install-erpnext-dev.sh service-stop
```

Restart service:

```bash
./install-erpnext-dev.sh service-restart
```

Show service status:

```bash
./install-erpnext-dev.sh service-status
```

> This service runs `bench start` for local development convenience. It is not a production deployment model.

---

## Browser Access Notes

The friendly local URL:

```text
http://erp.test:8000
```

only works after **both** of these are true:

1. ERPNext is running inside the VM.
2. Your host machine maps `erp.test` to the VM IP in `/etc/hosts`.

The direct IP URL works while ERPNext is running even before the friendly hostname is configured:

```text
http://VM_IP:8000
```

To print the current access instructions:

```bash
./install-erpnext-dev.sh access
```

Example host machine `/etc/hosts` command:

```bash
sudo sed -i '/[[:space:]]erp\.test$/d' /etc/hosts
echo "192.168.122.55 erp.test" | sudo tee -a /etc/hosts
```

Run that command on your **Linux Mint host**, not inside the Ubuntu VM.

---

## KVM Fixed IP Guide

If the VM IP changes after reboot, reserve a fixed IP on the KVM/libvirt host.

Show the guide:

```bash
./install-erpnext-dev.sh kvm-guide
```

Typical host-side workflow:

```bash
virsh list --all
virsh domiflist "YOUR_VM_NAME"
sudo virsh net-update default add ip-dhcp-host "<host mac='YOUR_VM_MAC' name='erpnext-dev' ip='192.168.122.55'/>" --live --config
virsh shutdown "YOUR_VM_NAME"
virsh start "YOUR_VM_NAME"
sudo virsh net-dhcp-leases default
```

Then update the host `/etc/hosts` entry.

---

## Multiple Local ERPNext Environments

Use one VM, one site name, and one fixed IP per environment.

Example plan:

```text
192.168.122.61  erp1.test
192.168.122.62  erp2.test
192.168.122.63  school.test
192.168.122.64  client-a.test
```

Install examples inside each VM:

```bash
SITE_NAME=erp1.test ./install-erpnext-dev.sh setup
SITE_NAME=school.test ./install-erpnext-dev.sh setup
SITE_NAME=client-a.test ./install-erpnext-dev.sh setup
```

Show the guide:

```bash
./install-erpnext-dev.sh multi-env-guide
```

Recommended rule:

```text
Local development: use .test domains
Avoid: .local because it conflicts with mDNS/Avahi and tools like LocalWP
Cloud/production: use a real domain and HTTPS
```

---

## Advanced Options

Open the advanced menu:

```bash
./install-erpnext-dev.sh advanced
```

Available advanced commands:

```bash
./install-erpnext-dev.sh backup-menu
./install-erpnext-dev.sh backup
./install-erpnext-dev.sh backup-files
./install-erpnext-dev.sh list-backups
./install-erpnext-dev.sh restore-db
./install-erpnext-dev.sh restore-full
./install-erpnext-dev.sh maintenance
./install-erpnext-dev.sh migrate
./install-erpnext-dev.sh build
./install-erpnext-dev.sh clear-cache
./install-erpnext-dev.sh restart
./install-erpnext-dev.sh repair
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh status-menu
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh install-status
./install-erpnext-dev.sh service-summary
./install-erpnext-dev.sh uninstall
./install-erpnext-dev.sh foreground-start
./install-erpnext-dev.sh access-menu
./install-erpnext-dev.sh kvm-guide
./install-erpnext-dev.sh multi-env-guide
```

---

## Credentials

The installer writes credentials to:

```text
/home/frappe/erpnext-dev-credentials.txt
```

View them from the Ubuntu VM:

```bash
sudo cat /home/frappe/erpnext-dev-credentials.txt
```

ERPNext web login:

```text
Username: Administrator
Password: shown in credentials file
```

---

## Safety Notes

Do not commit generated credentials, `.env` files, database dumps, backups, or logs.

The included `.gitignore` excludes common sensitive/runtime files:

```gitignore
*.log
.env
*.env
erpnext-dev-credentials.txt
credentials.txt
secrets.txt
*.sql
*.sql.gz
*.tar.gz
sites/*/private/backups/
.DS_Store
```

---

## Production / Cloud Note

This installer currently targets local development.

Future versions may add a separate small-business local production mode and a separate cloud production mode. Production should not use the development `bench start` workflow.

Production should eventually be handled as a separate mode using:

```text
real domain
DNS A record
Nginx
Supervisor/system services
HTTPS
firewall
backup strategy
```

Do not expose a local `bench start` development server directly to the public internet.

---


## v0.5.8 App Registry Reliability

This release hardens the App Library after testing interrupted optional app installs. It adds automatic normalization of `sites/apps.txt` before app listing, backup, and app installation. This repairs common registry damage such as concatenated entries like `erpnextcrm`, ensures one app per line, and verifies downloaded app folders are registered correctly.

New command:

```bash
./install-erpnext-dev.sh repair-app-registry
```

The backup workflow now treats Bench backup errors, tracebacks, and module import errors as real failures instead of reporting `OK` when Bench printed a failure message.

## License

This project is licensed under the GPL-3.0 license.


## v0.5.8 Notes

This release adds dependency handling for Frappe Helpdesk. Helpdesk requires the Frappe Telephony app, so the installer now downloads, registers, and installs Telephony before installing Helpdesk when needed.

New/updated command:

```bash
./install-erpnext-dev.sh install-telephony
./install-erpnext-dev.sh install-helpdesk
```

Relevant environment override:

```bash
TELEPHONY_BRANCH=develop
```


## Roadmap

Future development is tracked in `ROADMAP.md`. The next milestones focus on fresh-VM regression, public beta documentation, VM networking improvements, backup/restore hardening, and a separate production track later.
