# ERPNext Developer Installer Roadmap

This roadmap tracks the planned development path after the verified v0.5.7/v0.5.8 App Library milestone.

## Project status

Current maturity: beta-quality for local developer VMs.

Target use case: Ubuntu-based local development, testing, and learning environments for ERPNext and selected Frappe apps.

Not yet targeted: production servers. Production should become a separate installer or separate mode after the developer workflow is stable.

## Verified baseline

The current validated stack is:

- Frappe Framework v16
- ERPNext v16
- Frappe CRM
- Frappe HR / HRMS
- Frappe Telephony
- Frappe Helpdesk
- Frappe Insights

Core workflows validated so far:

- Fresh ERPNext developer environment setup
- systemd service creation
- autostart on VM boot
- start / stop / restart
- service readiness wait
- browser access guidance
- backup with files
- app registry repair for `sites/apps.txt`
- optional Frappe App Library installs

## v0.5.8 — App Library polish

Goal: improve the already verified v0.5.7 App Library workflow before wider testing.

Included / planned items:

- Add compact optional app status command: `app-status`
- Add optional app status to the doctor/full health report
- Reduce repeated browser instructions after start/restart
- Keep `sites/apps.txt` in a predictable order
- Add this roadmap file
- Keep v0.5.7 Helpdesk dependency handling through Telephony

## v0.6.0 — Public beta documentation

Goal: prepare the project for public developer use.

Planned items:

- Rewrite README for public clarity
- Add a verified app matrix
- Add screenshots or terminal examples
- Add a known warnings section
- Add a troubleshooting section based on real test failures
- Add release notes / changelog
- Add clear “development only, not production” warnings
- Add fresh Ubuntu 24.04 and Ubuntu 26.04 regression checklist

## v0.7.0 — VM and networking improvements

Goal: make KVM/libvirt and local VM access smoother.

Planned items:

- Improve KVM fixed-IP guide
- Add host `/etc/hosts` helper output
- Add multi-environment naming guide
- Add clearer direct-IP vs friendly-hostname checks
- Document NAT vs bridged networking
- Improve local DNS guidance for multiple ERPNext VMs

## v0.8.0 — Backup and restore hardening

Goal: make experimentation safer.

Planned items:

- Fully test `restore-db`
- Fully test `restore-full`
- Add restore dry-run where possible
- Group backup sets by timestamp
- Add backup cleanup option
- Add backup export option
- Add stronger warnings before destructive restore actions
- Add app-install rollback guidance

## v0.9.0 — Production planning branch

Goal: research and design production support without destabilizing the developer installer.

Important direction:

- Keep the local development installer separate from production automation.
- Consider a separate script later, for example `install-erpnext-prod.sh`.

Production topics to research and design:

- Nginx / reverse proxy
- SSL / Let’s Encrypt
- DNS and domain setup
- firewall rules
- production process management
- MariaDB hardening
- Redis hardening
- backups and offsite backup policy
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
