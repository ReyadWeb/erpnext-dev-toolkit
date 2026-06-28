# ERPNext Developer Installer v0.8.2

Public beta local developer installer for ERPNext/Frappe environments on Ubuntu VMs.

## Status

**Beta-quality for local developer VM use.**

This script is intended for local learning, development, testing, and VM-based ERPNext experimentation. It is **not a production installer**.

## Verified local stack

The installer has been validated with:

- Frappe Framework v16
- ERPNext v16
- Frappe CRM
- Frappe HR / HRMS
- Frappe Telephony
- Frappe Helpdesk
- Frappe Insights
- Local systemd service/autostart
- Backups and maintenance commands
- App registry repair
- KVM/libvirt networking diagnostics
- Local HTTPS via Nginx reverse proxy

## Quick start

```bash
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh" -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh setup
```

Then start ERPNext:

```bash
./install-erpnext-dev.sh start
./install-erpnext-dev.sh access
```

## Core commands

```bash
./install-erpnext-dev.sh status
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh start
./install-erpnext-dev.sh stop
./install-erpnext-dev.sh restart
./install-erpnext-dev.sh access
./install-erpnext-dev.sh network-status
```

## App Library

```bash
./install-erpnext-dev.sh app-library
./install-erpnext-dev.sh app-status
./install-erpnext-dev.sh install-crm
./install-erpnext-dev.sh install-hrms
./install-erpnext-dev.sh install-helpdesk
./install-erpnext-dev.sh install-insights
./install-erpnext-dev.sh list-apps
```

Helpdesk dependency handling includes Telephony.

## Local HTTPS / SSL

v0.8.x adds optional local HTTPS while keeping direct Bench access unchanged.

Current direct access remains available:

```text
http://erp.test:8000
http://VM_IP:8000
```

Optional local HTTPS target:

```text
https://erp.test
```

Architecture:

```text
Browser HTTPS :443
  -> Nginx inside VM
    -> Bench web 127.0.0.1:8000
    -> Socket.io 127.0.0.1:9000
```

SSL commands:

```bash
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh local-ssl-guide
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh verify-local-ssl
./install-erpnext-dev.sh mkcert-guide
./install-erpnext-dev.sh ssl-rollback-guide
./install-erpnext-dev.sh disable-local-ssl
```

### Quick self-signed test

Inside the VM:

```bash
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh ssl-status
```

From the host:

```bash
curl -I http://erp.test
curl -kI https://erp.test
curl -I http://erp.test:8000
```

Expected:

```text
http://erp.test        -> 301 redirect to https://erp.test/
https://erp.test       -> 200 OK through Nginx HTTPS reverse proxy
http://erp.test:8000   -> 200 OK direct Bench fallback
```

Self-signed certificates require browser exceptions. For trusted browser SSL, use:

```bash
./install-erpnext-dev.sh mkcert-guide
```

## KVM/libvirt networking

```bash
./install-erpnext-dev.sh network-status
./install-erpnext-dev.sh hosts-command
./install-erpnext-dev.sh host-test
./install-erpnext-dev.sh kvm-identify
./install-erpnext-dev.sh kvm-guide
./install-erpnext-dev.sh multi-env-guide
```

## Backups and maintenance

```bash
./install-erpnext-dev.sh backup
./install-erpnext-dev.sh backup-files
./install-erpnext-dev.sh list-backups
./install-erpnext-dev.sh maintenance
./install-erpnext-dev.sh migrate
./install-erpnext-dev.sh build
./install-erpnext-dev.sh clear-cache
```

## Important limitation

This is a developer installer. Production should be a separate track with production-ready Nginx/Supervisor/systemd worker configuration, firewall rules, domain/DNS validation, SSL renewal, backup/restore testing, monitoring, and a defined update strategy.
