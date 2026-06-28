# ERPNext Developer Installer Roadmap

This roadmap tracks development after the verified full App Library milestone and the v0.6.0 public beta documentation release.

## Current project status

```text
Current release: v0.6.0
Maturity: public beta for local developer VMs
Target: Ubuntu-based local development, testing, and learning environments
Production status: not production-ready
```

## Verified baseline

Validated local stack:

- Frappe Framework v16
- ERPNext v16
- Frappe CRM
- Frappe HR / HRMS
- Frappe Telephony
- Frappe Helpdesk
- Frappe Insights

Validated workflows:

- Fresh ERPNext developer setup
- systemd service creation
- autostart on VM boot
- start / stop / restart
- visible readiness wait
- browser access guidance
- database backup
- database + files backup
- app registry repair for `sites/apps.txt`
- optional Frappe App Library installs
- optional app status in doctor report

## v0.6.0 — Public beta documentation

Included:

- Public-facing README rewrite
- Verified app matrix
- Quick start section
- VM access notes
- App Library documentation
- Known warnings section
- Troubleshooting section
- Fresh VM regression checklist
- CHANGELOG.md
- TESTING.md
- Updated ROADMAP.md

## v0.7.0 — VM and networking improvements

Goal: make KVM/libvirt and local VM access smoother.

Planned items:

- Improve KVM fixed-IP guide
- Add host `/etc/hosts` helper output
- Add multi-environment naming guide
- Add direct-IP vs friendly-hostname diagnostics
- Document NAT vs bridged networking
- Add guidance for multiple local ERPNext VMs
- Consider host-side helper script or generated commands for libvirt DHCP reservations

## v0.8.0 — Backup and restore hardening

Goal: make experimentation safer.

Planned items:

- Fully test `restore-db`
- Fully test `restore-full`
- Add restore dry-run where practical
- Group backup sets by timestamp
- Add backup cleanup option
- Add backup export option
- Add stronger warnings before destructive restore actions
- Add app-install rollback guidance
- Add restore regression checklist

## v0.9.0 — Production planning branch

Goal: research and design production support without destabilizing the developer installer.

Important direction:

- Keep local development automation separate from production automation.
- Consider a separate script later, for example `install-erpnext-prod.sh`.

Production topics to research:

- Nginx / reverse proxy
- SSL / Let’s Encrypt
- DNS and domain setup
- firewall rules
- production process management
- MariaDB hardening
- Redis hardening
- scheduled backups and offsite backup policy
- update strategy
- monitoring
- disaster recovery
- security baseline

## v1.0.0 release criteria

The project should not be called stable until all of these pass:

- Fresh Ubuntu 24.04 VM install
- Fresh Ubuntu 26.04 VM install
- Reboot/autostart test
- Start/stop/restart test
- Doctor/status test
- Backup/list-backups test
- Database restore test
- Full restore test
- CRM install test
- HRMS install test
- Telephony + Helpdesk dependency install test
- Insights install test
- Uninstall/reset test on disposable VM
- README complete
- Known limitations documented

## Development principle

Do not add major new features until the current milestone is regression-tested. Prefer small, testable releases that fix one class of issue at a time.
