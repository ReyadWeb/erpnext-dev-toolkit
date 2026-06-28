# Testing Guide

This file defines the regression checklist for the ERPNext Developer Installer public beta.

Use disposable VMs for destructive tests.

## Test environment matrix

| Environment | Required before v1.0 | Notes |
| --- | --- | --- |
| Ubuntu 24.04 LTS VM | Yes | primary LTS baseline |
| Ubuntu 26.04 LTS VM | Yes | newer supported target |
| KVM/libvirt NAT network | Yes | main local VM target |
| Reboot/autostart test | Yes | confirms service behavior |

## Fresh VM setup test

Inside a fresh Ubuntu VM:

```bash
sudo apt update
sudo apt install -y curl ca-certificates
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh setup
```

Expected:

- Ubuntu supported
- system packages installed
- Frappe user exists
- Bench exists
- ERPNext site exists
- service created
- optional autostart works if enabled

## Core runtime test

```bash
./install-erpnext-dev.sh start
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh doctor
```

Expected ports:

- 8000 web
- 9000 socket.io
- 11000 Redis queue
- 13000 Redis cache

## Backup test

```bash
./install-erpnext-dev.sh backup
./install-erpnext-dev.sh backup-files
./install-erpnext-dev.sh list-backups
```

Expected:

- database backup listed
- public files backup listed
- private files backup listed

## App Library test

```bash
./install-erpnext-dev.sh repair-app-registry
./install-erpnext-dev.sh install-crm
./install-erpnext-dev.sh install-hrms
./install-erpnext-dev.sh install-helpdesk
./install-erpnext-dev.sh install-insights
./install-erpnext-dev.sh list-apps
./install-erpnext-dev.sh doctor
```

Expected installed apps:

```text
frappe
erpnext
crm
hrms
telephony
helpdesk
insights
```

Expected registry state:

```text
Downloaded but not installed on erp.test:
  none

Downloaded but not registered in sites/apps.txt:
  none
```

## Helpdesk dependency test

On a VM with ERPNext, CRM, and HRMS but without Telephony or Helpdesk:

```bash
./install-erpnext-dev.sh install-helpdesk
```

Expected:

- Telephony is downloaded if missing
- Telephony is installed on the site if missing
- Helpdesk installs after Telephony

## Reboot/autostart test

```bash
sudo reboot
```

After reconnecting:

```bash
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh service-summary
```

Expected:

- service running
- autostart enabled
- all required ports listening

## Restore test

Use a disposable VM.

```bash
./install-erpnext-dev.sh backup-files
./install-erpnext-dev.sh restore-db
./install-erpnext-dev.sh restore-full
```

Expected:

- restore commands require strong confirmation
- emergency pre-restore backup is attempted
- site returns to working state after restore and restart

## Uninstall/reset test

Use a disposable VM only.

```bash
./install-erpnext-dev.sh uninstall
```

Expected:

- destructive action requires confirmation
- service removed or disabled
- environment cleanup behaves as documented

## Public beta pass criteria

Before publishing a beta release:

- `bash -n install-erpnext-dev.sh` passes
- `./install-erpnext-dev.sh help` works
- fresh VM setup passes
- doctor is clean after install
- app-status is accurate
- full app stack installs
- restart/readiness works
- README matches behavior
