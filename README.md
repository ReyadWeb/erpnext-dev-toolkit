# ERPNext Developer Installer v0.8.3

Beta-quality local developer VM installer for ERPNext/Frappe on Ubuntu-based VMs.

This release keeps the v0.8.x local HTTPS reverse proxy workflow and adds final SSL hardening: trusted certificate install helpers, host/browser trust checks, rollback verification, and corrected SSL menu numbering.

## Current verified stack

- Frappe / ERPNext development install
- systemd service and autostart
- readiness wait for web/socket/Redis ports
- backups and maintenance commands
- optional App Library: CRM, HRMS, Telephony, Helpdesk, Insights
- VM networking diagnostics
- local HTTPS reverse proxy with Nginx
- self-signed and mkcert/trusted local SSL workflows

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh setup
```

Then open the direct developer URL while Bench is running:

```text
http://VM_IP:8000
http://erp.test:8000
```

For local HTTPS after SSL configuration:

```text
https://erp.test
```

## Common commands

```bash
./install-erpnext-dev.sh status
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh start
./install-erpnext-dev.sh restart
./install-erpnext-dev.sh access
./install-erpnext-dev.sh app-library
./install-erpnext-dev.sh backup-files
```

## App Library

Verified optional apps:

| App | Command | Status |
|---|---|---|
| Frappe CRM | `install-crm` | Verified |
| Frappe HR / HRMS | `install-hrms` | Verified |
| Frappe Telephony | `install-telephony` | Verified |
| Frappe Helpdesk | `install-helpdesk` | Verified; installs Telephony dependency |
| Frappe Insights | `install-insights` | Verified |

Check apps:

```bash
./install-erpnext-dev.sh list-apps
./install-erpnext-dev.sh app-status
```

## Local HTTPS / SSL

Local HTTPS uses Nginx inside the VM as a reverse proxy:

```text
Browser HTTPS :443
  -> Nginx inside VM
    -> Bench web 127.0.0.1:8000
    -> Socket.io 127.0.0.1:9000
```

Direct Bench access remains available on `:8000`.

Useful SSL commands:

```bash
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh local-ssl-guide
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh verify-local-ssl
./install-erpnext-dev.sh mkcert-guide
./install-erpnext-dev.sh browser-trust-guide
./install-erpnext-dev.sh install-local-ssl-cert
./install-erpnext-dev.sh disable-local-ssl
./install-erpnext-dev.sh verify-ssl-rollback
```

### Self-signed quick test

```bash
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh ssl-status
```

Host test:

```bash
curl -I http://erp.test
curl -kI https://erp.test
curl -I http://erp.test:8000
```

A browser warning is expected with self-signed certificates.

### Trusted mkcert workflow

Run the guide:

```bash
./install-erpnext-dev.sh mkcert-guide
```

Generate the certificate on the host, copy it into the VM, then install it safely:

```bash
./install-erpnext-dev.sh install-local-ssl-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh verify-local-ssl
```

Trust must be installed on the host/browser machine, not only inside the VM.

## VM networking

```bash
./install-erpnext-dev.sh network-status
./install-erpnext-dev.sh hosts-command
./install-erpnext-dev.sh host-test
./install-erpnext-dev.sh kvm-identify
```

Use `.test` names for local environments and avoid `.local`.

## Scope

This project is for local development, learning, and VM-based testing. It is not a production installer. Production should use a separate architecture with Nginx, Supervisor/systemd production workers, firewalling, backups, SSL renewal, monitoring, and a real domain.
