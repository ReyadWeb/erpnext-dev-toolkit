# ERPNext Developer Installer

A menu-driven installer for building a local **Frappe + ERPNext developer environment** on an Ubuntu VM.

This project is intended for developers, implementers, testers, students, and ERPNext learners who want a repeatable local environment with optional Frappe ecosystem apps.

> **Status:** v0.6.0 public beta documentation release  
> **Target:** local development and learning environments  
> **Not for production:** do not use this installer as-is for public production servers

---

## Current Version

```text
v0.6.0
```

v0.6.0 keeps the tested v0.5.8 installer behavior and focuses on public beta readiness: clearer README, verified app matrix, troubleshooting notes, regression checklist, changelog, testing guide, and roadmap.

---

## Verified Local Stack

The following stack was validated in a local Ubuntu 26.04 VM after the v0.5.x App Library work:

| Component | Status | Notes |
| --- | --- | --- |
| Frappe Framework | Verified | version-16 |
| ERPNext | Verified | version-16 |
| Frappe CRM | Verified | `main` branch |
| Frappe HR / HRMS | Verified | `version-16` branch |
| Frappe Telephony | Verified | `develop` branch; required by Helpdesk |
| Frappe Helpdesk | Verified | `main` branch; depends on Telephony |
| Frappe Insights | Verified | `main` branch |

The installer also validates service status, runtime ports, app registry health, backups, and optional app installation state.

---

## What This Installer Does

The recommended setup can install and configure:

- Frappe Framework
- ERPNext
- Frappe Bench
- MariaDB
- Redis
- Python through `uv`
- Node.js through `nvm`
- Yarn
- A local ERPNext site
- Development systemd service
- Optional autostart on VM boot
- Start/stop/restart helpers
- Readiness checks for Bench ports
- Backup and restore helpers
- Maintenance commands
- Optional App Library

Default local site:

```text
erp.test
```

Default direct development URL:

```text
http://VM_IP:8000
```

Default friendly local URL:

```text
http://erp.test:8000
```

---

## Target Environment

Recommended VM environment:

```text
OS: Ubuntu 24.04 LTS or Ubuntu 26.04 LTS
Mode: Local development
Virtualization: KVM/libvirt, VirtualBox, VMware, Proxmox lab VM, or similar
```

Recommended VM resources:

```text
CPU: 4 cores minimum
RAM: 8 GB recommended
Disk: 60 GB recommended
Network: NAT or bridged
```

Run the installer **inside the Ubuntu VM**, not on the Linux Mint/Desktop host.

---

## Quick Start

Inside a fresh Ubuntu VM:

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

After installation:

```bash
./install-erpnext-dev.sh start
./install-erpnext-dev.sh status
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh access
```

---

## Login Information

The installer writes local credentials to:

```text
/home/frappe/erpnext-dev-credentials.txt
```

Default login user:

```text
Administrator
```

Read credentials inside the VM:

```bash
sudo cat /home/frappe/erpnext-dev-credentials.txt
```

Do not commit credential files to Git.

---

## Accessing ERPNext from the Host

The direct IP URL works when ERPNext is running:

```text
http://VM_IP:8000
```

The friendly URL requires a host `/etc/hosts` entry on your Linux Mint/Desktop host:

```bash
sudo sed -i '/[[:space:]]erp\.test$/d' /etc/hosts
echo "VM_IP erp.test" | sudo tee -a /etc/hosts
```

Example:

```bash
sudo sed -i '/[[:space:]]erp\.test$/d' /etc/hosts
echo "192.168.122.215 erp.test" | sudo tee -a /etc/hosts
```

Then open:

```text
http://erp.test:8000
```

If the friendly URL does not work, use the direct IP first and run:

```bash
./install-erpnext-dev.sh access
```

---

## Common Commands

```bash
./install-erpnext-dev.sh setup              # recommended setup
./install-erpnext-dev.sh start              # start ERPNext service
./install-erpnext-dev.sh stop               # stop ERPNext service and dev processes
./install-erpnext-dev.sh restart            # restart and wait until ready
./install-erpnext-dev.sh status             # quick status
./install-erpnext-dev.sh doctor             # full health report
./install-erpnext-dev.sh access             # browser/IP/hostname instructions
./install-erpnext-dev.sh logs               # recent service logs
./install-erpnext-dev.sh logs-follow        # follow service logs
```

Runtime readiness checks include:

- Bench web: port `8000`
- Socket.io: port `9000`
- Redis queue: port `11000`
- Redis cache: port `13000`

---

## App Library

Open the interactive App Library:

```bash
./install-erpnext-dev.sh app-library
```

Show app status:

```bash
./install-erpnext-dev.sh app-status
./install-erpnext-dev.sh list-apps
```

Install optional apps:

```bash
./install-erpnext-dev.sh install-crm
./install-erpnext-dev.sh install-hrms
./install-erpnext-dev.sh install-telephony
./install-erpnext-dev.sh install-helpdesk
./install-erpnext-dev.sh install-insights
```

Helpdesk dependency behavior:

```text
Helpdesk requires Telephony.
The installer checks Telephony first and installs it before Helpdesk if needed.
```

Branch override examples:

```bash
CRM_BRANCH=main ./install-erpnext-dev.sh install-crm
HRMS_BRANCH=version-16 ./install-erpnext-dev.sh install-hrms
TELEPHONY_BRANCH=develop ./install-erpnext-dev.sh install-telephony
HELPDESK_BRANCH=main ./install-erpnext-dev.sh install-helpdesk
INSIGHTS_BRANCH=main ./install-erpnext-dev.sh install-insights
```

Custom trusted Frappe app:

```bash
./install-erpnext-dev.sh install-custom-app
```

Only install custom apps you trust.

---

## App Registry Repair

Bench uses `sites/apps.txt` to know which apps are part of the bench. Interrupted installs can leave downloaded apps unregistered or, in rare cases, corrupt the file.

Repair and normalize the app registry:

```bash
./install-erpnext-dev.sh repair-app-registry
```

The expected curated order is:

```text
frappe
erpnext
crm
hrms
telephony
helpdesk
insights
```

Custom apps are preserved after the curated apps.

---

## Backup and Restore

```bash
./install-erpnext-dev.sh backup        # database backup
./install-erpnext-dev.sh backup-files  # database + public/private files
./install-erpnext-dev.sh list-backups
./install-erpnext-dev.sh restore-db
./install-erpnext-dev.sh restore-full
```

Before app installation, the installer offers a database + files backup. Restore workflows include strong confirmation prompts.

---

## Maintenance

```bash
./install-erpnext-dev.sh migrate
./install-erpnext-dev.sh build
./install-erpnext-dev.sh clear-cache
./install-erpnext-dev.sh maintenance
./install-erpnext-dev.sh repair
```

---

## KVM / libvirt Notes

Show KVM fixed-IP guidance:

```bash
./install-erpnext-dev.sh kvm-guide
```

Useful host-side commands:

```bash
virsh list --all
virsh net-dhcp-leases default
virsh domifaddr VM_NAME
virsh domiflist VM_NAME
```

If the VM IP changes, update the host `/etc/hosts` mapping or configure a libvirt DHCP reservation.

---

## Known Non-Blocking Warnings

During app builds, you may see warnings like:

- `Browserslist: caniuse-lite is outdated`
- `Some chunks are larger than 500 kBs`
- Font references that remain unchanged to resolve at runtime
- Vite/Rollup CSS or chunk-size warnings

These warnings are common in frontend builds and do not necessarily mean installation failed.

The important checks are:

```bash
./install-erpnext-dev.sh list-apps
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh runtime-status
```

---

## Troubleshooting

### The friendly URL does not open

```bash
./install-erpnext-dev.sh access
./install-erpnext-dev.sh runtime-status
```

Use the direct IP URL first:

```text
http://VM_IP:8000
```

### ERPNext service says running but browser is not ready

```bash
./install-erpnext-dev.sh wait-ready
./install-erpnext-dev.sh runtime-status
```

### Optional app folder exists but app is not installed

```bash
./install-erpnext-dev.sh repair-app-registry
./install-erpnext-dev.sh list-apps
```

Then retry the app install.

### Helpdesk fails with missing Telephony

Use v0.5.7 or newer:

```bash
./install-erpnext-dev.sh install-helpdesk
```

The script should install Telephony first if needed.

### Yarn or Node missing during app install

```bash
./install-erpnext-dev.sh repair
./install-erpnext-dev.sh doctor
```

Then retry the app install.

### Bench folder not found

```bash
./install-erpnext-dev.sh install-status
```

The normal bench path is:

```text
/home/frappe/frappe/frappe-bench
```

### I accidentally ran the script on Linux Mint host

The installer is intended to exit on unsupported operating systems. Remove the downloaded script if needed:

```bash
rm -f install-erpnext-dev.sh
```

---

## Fresh VM Regression Checklist

Before calling a release stable, test on a disposable Ubuntu VM:

```bash
./install-erpnext-dev.sh setup
./install-erpnext-dev.sh start
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh backup-files
./install-erpnext-dev.sh install-crm
./install-erpnext-dev.sh install-hrms
./install-erpnext-dev.sh install-helpdesk
./install-erpnext-dev.sh install-insights
./install-erpnext-dev.sh list-apps
./install-erpnext-dev.sh restart
./install-erpnext-dev.sh runtime-status
```

Expected optional app stack:

```text
crm
hrms
telephony
helpdesk
insights
```

---

## Project Files

```text
erpnext-dev-installer/
├── install-erpnext-dev.sh
├── README.md
├── ROADMAP.md
├── CHANGELOG.md
├── TESTING.md
├── LICENSE
└── .gitignore
```

---

## Development Status

```text
v0.6.0 = public beta documentation release
v0.7.0 = VM/networking improvements
v0.8.0 = backup/restore hardening
v0.9.0 = production planning branch
v1.0.0 = stable local developer installer
```

---

## License

This project is licensed under the GPL-3.0 license.
