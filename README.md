# ERPNext Developer Installer

A developer-friendly installer manager for setting up a local **Frappe + ERPNext** environment on Ubuntu.

This project is designed for local developer VMs, test labs, and evaluation environments. It is especially useful when running ERPNext inside KVM/libvirt, VirtualBox, VMware, or a similar virtualization platform.

> This installer is for **development environments only**.  
> Do **not** use this as-is for production servers.

---

## Current Version

```text
v0.3.1
```

This version refines the status workflow so installation, runtime, and autostart states are reported separately. It keeps the cleaner basic/advanced menu structure and optional systemd autostart service from v0.3.0.

---

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

v0.3.1 keeps the main menu simple:

```text
1) Recommended Setup
2) Start ERPNext
3) Stop ERPNext
4) Status
5) Access Instructions
6) Advanced Options
7) Help
8) Exit
```

The main menu is intended for normal daily use.

The Status option opens a focused status submenu instead of dumping every diagnostic check at once:

```text
1) Quick Status
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

Advanced tools are under:

```text
6) Advanced Options
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

Quick status:

```bash
./install-erpnext-dev.sh status
```

Interactive status submenu:

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

## Autostart on VM Boot

v0.3.1 can create a local development systemd service:

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

Cloud/production should eventually be handled as a separate mode using:

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

## License

This project is licensed under the GPL-3.0 license.
