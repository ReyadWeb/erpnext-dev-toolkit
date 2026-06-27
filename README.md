# ERPNext Developer Installer

**Current script version:** `0.2.1`

A developer-friendly installer manager for setting up a local **Frappe + ERPNext** environment on Ubuntu Server.

This project is intended for developers, testers, lab environments, and KVM/VM-based local ERPNext evaluation.

> This installer is for **development environments only**.  
> Do **not** use it as-is for production servers.

---

## What It Installs

The installer can set up:

- Frappe Framework
- ERPNext
- Frappe Bench
- MariaDB
- Redis
- Node.js
- Yarn
- Python via `uv`
- Local ERPNext site

Default site:

```text
erp.test
```

Default bench path:

```text
/home/frappe/frappe/frappe-bench
```

Default development start command:

```bash
bench start
```

---

## Supported Environment

Supported operating systems:

```text
Ubuntu Server 24.04 LTS
Ubuntu Server 26.04 LTS
```

Recommended VM resources:

```text
CPU: 4 cores minimum
RAM: 8 GB recommended
Disk: 60 GB minimum
Network: NAT or bridged
```

The script intentionally exits if it detects an unsupported OS. Run it inside the **Ubuntu Server VM**, not on your Linux Mint/desktop host.

---

## Quick Start: Menu Mode

Run this inside the Ubuntu Server VM:

```bash
sudo apt update && sudo apt install -y curl ca-certificates && curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh && chmod +x install-erpnext-dev.sh && ./install-erpnext-dev.sh
```

The script opens an interactive menu:

```text
1) Install / Reinstall ERPNext Development Environment
2) Repair / Health Check
3) Uninstall ERPNext Development Environment
4) Show Status
5) Start ERPNext
6) Show Browser / Hostname Instructions
7) Help
8) Exit
```

---

## Command-Line Mode

Advanced users can run actions directly:

```bash
./install-erpnext-dev.sh install
./install-erpnext-dev.sh repair
./install-erpnext-dev.sh status
./install-erpnext-dev.sh start
./install-erpnext-dev.sh uninstall
./install-erpnext-dev.sh access
./install-erpnext-dev.sh help
```

Install and start ERPNext automatically after completion:

```bash
AUTO_START=true ./install-erpnext-dev.sh install
```

For unattended confirmation prompts:

```bash
./install-erpnext-dev.sh install --yes
```

---

## Fresh Install

Interactive:

```bash
./install-erpnext-dev.sh
```

Then choose:

```text
1) Install / Reinstall ERPNext Development Environment
```

Direct command:

```bash
./install-erpnext-dev.sh install
```

Install with custom values:

```bash
SITE_NAME=erp.test \
FRAPPE_USER=frappe \
ADMIN_PASSWORD='ChangeThisAdminPassword' \
./install-erpnext-dev.sh install
```

Common variables:

| Variable | Default | Purpose |
|---|---|---|
| `SITE_NAME` | `erp.test` | Local Frappe/ERPNext site name |
| `FRAPPE_USER` | `frappe` | Linux user used for Bench |
| `BENCH_NAME` | `frappe-bench` | Bench folder name |
| `FRAPPE_BRANCH` | `version-16` | Frappe branch |
| `ERPNEXT_BRANCH` | `version-16` | ERPNext branch |
| `ADMIN_PASSWORD` | Generated if empty | ERPNext Administrator password |
| `DB_ADMIN_USER` | `frappe_db_admin` | MariaDB admin user created for Bench |
| `DB_ADMIN_PASSWORD` | Generated if empty | MariaDB admin password |

---

## Repair / Health Check

Run:

```bash
./install-erpnext-dev.sh repair
```

Repair mode performs safe fixes such as:

- Start/enable MariaDB
- Start/enable Redis
- Configure Redis memory overcommit
- Ensure the `frappe` Linux user exists
- Fix ownership of `/home/frappe`
- Recreate the start helper script
- Repair bench site defaults when a bench exists
- Optionally run migrate/build/clear-cache

Use status mode to inspect the environment without changing it:

```bash
./install-erpnext-dev.sh status
```

Status mode checks the OS, services, Bench folder, app files, site-level app installation, helper script, credentials file, runtime ports, VM IP, and browser URLs.

---

## Start ERPNext

Run:

```bash
./install-erpnext-dev.sh start
```

Or manually:

```bash
sudo -iu frappe
export PATH="$HOME/.local/bin:$PATH"
cd /home/frappe/frappe/frappe-bench
bench start
```

Do **not** use `su - frappe` unless you manually set a password for the `frappe` Linux user. The installer creates the `frappe` user without password login.

---

## Browser Access

There are two ways to open the local ERPNext site from your host browser.

### 1. Direct IP URL

This works as soon as ERPNext is running with `bench start`:

```text
http://VM_IP:8000
```

Example:

```text
http://192.168.122.66:8000
```

### 2. Friendly local domain

The friendly local domain is:

```text
http://erp.test:8000
```

This only works after **both** conditions are true:

1. ERPNext/Bench is running inside the VM.
2. Your host machine maps `erp.test` to the VM IP in `/etc/hosts`.

Start ERPNext inside the VM:

```bash
./install-erpnext-dev.sh start
```

Or manually:

```bash
sudo -iu frappe
export PATH="$HOME/.local/bin:$PATH"
cd /home/frappe/frappe/frappe-bench
bench start
```

After `bench start`, look for a line like:

```text
Running on http://192.168.122.66:8000
```

Then run the access helper inside the VM:

```bash
./install-erpnext-dev.sh access
```

It prints the exact `/etc/hosts` command to run on your Linux Mint host.

Example host machine entry:

```text
192.168.122.66 erp.test
```

If `erp.test` does not open yet, use the direct IP URL first:

```text
http://192.168.122.66:8000
```

Important: the `/etc/hosts` command must be run on the **host machine**, not inside the VM.

---

## Login Credentials

The installer writes credentials to:

```text
/home/frappe/erpnext-dev-credentials.txt
```

Read it from the VM with:

```bash
sudo cat /home/frappe/erpnext-dev-credentials.txt
```

ERPNext web login:

```text
Username: Administrator
Password: shown in erpnext-dev-credentials.txt
```

---

## Uninstall Options

Run:

```bash
./install-erpnext-dev.sh uninstall
```

Available uninstall levels:

```text
1) Soft uninstall: stop Bench and archive /home/frappe/frappe
2) Remove bench files only
3) Full purge: remove bench, frappe user, MariaDB/Redis packages
```

Recommended for development testing:

```text
Soft uninstall
```

It archives the bench folder instead of deleting it immediately.

For the cleanest test, use a fresh VM or roll back to a KVM snapshot.

---

## KVM Fixed IP Recommendation

For KVM/libvirt users, reserve a fixed IP for the VM so `erp.test` does not break after reboot.

On the host machine:

```bash
virsh list --all
virsh domiflist "YOUR_VM_NAME"
```

Then reserve the IP using the VM MAC address:

```bash
sudo virsh net-update default add ip-dhcp-host "<host mac='YOUR_VM_MAC' name='erpnext-dev' ip='192.168.122.66'/>" --live --config
```

Restart the VM after adding the reservation.

---

## Useful Bench Commands

Run as the `frappe` user:

```bash
sudo -iu frappe
export PATH="$HOME/.local/bin:$PATH"
cd /home/frappe/frappe/frappe-bench
```

Useful commands:

```bash
bench --site erp.test list-apps
bench --site erp.test migrate
bench build
bench --site erp.test clear-cache
bench --site erp.test backup
```

Expected apps:

```text
frappe
erpnext
```

---

## Troubleshooting

### Browser cannot resolve erp.test

Run this inside the VM:

```bash
./install-erpnext-dev.sh access
```

Then run the printed `/etc/hosts` commands on the Linux Mint host.

### `su - frappe` asks for a password

Use this instead:

```bash
sudo -iu frappe
```

The installer creates the `frappe` user without a login password.

### `wkhtmltopdf` is not available

On newer Ubuntu releases, `wkhtmltopdf` may not be available from apt.

The installer treats it as optional and continues. ERPNext can still install, but PDF generation may require a separate manual setup later.

### Redis Queue error

If you see:

```text
Error 111 connecting to 127.0.0.1:11000. Connection refused.
```

Run repair:

```bash
./install-erpnext-dev.sh repair
```

Or start Bench manually:

```bash
./install-erpnext-dev.sh start
```

### Show environment status

```bash
./install-erpnext-dev.sh status
```

---

## Safety Notes

Do not commit generated credentials, backups, logs, `.env` files, database dumps, or site backups.

Recommended `.gitignore` entries:

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

## License

This project is licensed under the GPL-3.0 license.
