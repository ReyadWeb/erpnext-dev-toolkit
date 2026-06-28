# ERPNext Developer Installer v0.8.0 Beta

A menu-driven Bash installer for creating a local ERPNext / Frappe developer VM on Ubuntu 24.04 or Ubuntu 26.04.

This project is intended for local development, learning, evaluation, and repeatable VM setup. It is not a production installer.

## Status

v0.8.0 builds on the verified v0.7.0 VM/networking foundation and adds the first local SSL / HTTPS reverse proxy implementation.

Verified app stack from the v0.5.x/v0.6.x/v0.7.x test cycle:

| App | Status |
|---|---|
| Frappe | Verified |
| ERPNext | Verified |
| Frappe CRM | Verified |
| Frappe HR / HRMS | Verified |
| Frappe Telephony | Verified |
| Frappe Helpdesk | Verified |
| Frappe Insights | Verified |

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh
```

Recommended flow:

```bash
./install-erpnext-dev.sh setup
./install-erpnext-dev.sh start
./install-erpnext-dev.sh access
```

## New in v0.8.0

- Added `ssl-status` command.
- Added `local-ssl-guide` command.
- Added `configure-local-ssl` command.
- Added `disable-local-ssl` command.
- Added guarded Nginx reverse proxy configuration for local HTTPS.
- Added mkcert/local CA workflow guidance.
- Kept direct Bench access on `:8000` unchanged.
- Added SSL options to Access and Advanced menus.

## Browser access

Direct IP access:

```text
http://VM_IP:8000
```

Friendly local access:

```text
http://erp.test:8000
```

Optional local HTTPS access after SSL setup:

```text
https://erp.test
```

The friendly URL requires a host `/etc/hosts` entry on your Linux Mint / Ubuntu host:

```bash
sudo sed -i '/[[:space:]]erp\.test$/d' /etc/hosts
echo "VM_IP erp.test" | sudo tee -a /etc/hosts
```

## Local SSL / HTTPS

v0.8.0 adds a local HTTPS reverse proxy foundation. It does not remove or replace the existing development service.

Architecture:

```text
Browser HTTPS :443
  -> Nginx inside the VM
    -> Bench web on 127.0.0.1:8000
    -> Socket.io on 127.0.0.1:9000
```

Commands:

```bash
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh local-ssl-guide
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh disable-local-ssl
```

Expected certificate paths inside the VM:

```text
/etc/erpnext-dev-ssl/erp.test.crt
/etc/erpnext-dev-ssl/erp.test.key
```

Recommended local certificate workflow:

1. Use `mkcert` on the host machine.
2. Trust the local CA on the host/browser machine.
3. Generate a certificate for `erp.test` and the VM IP.
4. Copy the certificate and key into the VM.
5. Run `configure-local-ssl`.

The certificate must be trusted by the host browser machine. A certificate trusted only inside the VM is not enough.

## Common commands

```bash
./install-erpnext-dev.sh status
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh start
./install-erpnext-dev.sh restart
./install-erpnext-dev.sh stop
./install-erpnext-dev.sh access
./install-erpnext-dev.sh network-status
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh list-apps
./install-erpnext-dev.sh app-status
```

## Optional app library

```bash
./install-erpnext-dev.sh install-crm
./install-erpnext-dev.sh install-hrms
./install-erpnext-dev.sh install-helpdesk
./install-erpnext-dev.sh install-insights
./install-erpnext-dev.sh list-apps
./install-erpnext-dev.sh app-status
```

Helpdesk requires Telephony. The installer handles this dependency automatically.

## VM and hostname commands

```bash
./install-erpnext-dev.sh access
./install-erpnext-dev.sh hosts-command
./install-erpnext-dev.sh network-status
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

## Production warning

This script is for local developer VM use. It does not yet configure a production architecture with production Nginx/Supervisor workers, hardened MariaDB/Redis, firewall rules, public-domain SSL renewal, monitoring, or disaster recovery.

Production should become a separate track, likely with a future `install-erpnext-prod.sh` script.
