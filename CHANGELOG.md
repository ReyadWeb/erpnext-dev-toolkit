# Changelog

## v0.6.0

Public beta documentation release.

Added:

- Public-facing README rewrite
- Verified app matrix
- Quick start and common command sections
- KVM/libvirt access notes
- Known warnings section
- Troubleshooting section based on real test failures
- Fresh VM regression checklist
- CHANGELOG.md
- TESTING.md
- Updated ROADMAP.md

Changed:

- Bumped installer version to `0.6.0`
- Kept v0.5.8 code behavior as the tested beta baseline

## v0.5.8

App Library polish release.

Added:

- `app-status` command
- Optional app checks in `doctor`
- Compact ERPNext Ready summary after start/restart
- Predictable `sites/apps.txt` ordering
- ROADMAP.md

## v0.5.7

Helpdesk dependency handling release.

Added:

- Frappe Telephony app profile
- `install-telephony` command
- Helpdesk dependency flow: install Telephony before Helpdesk when needed

## v0.5.6

App registry repair command fix.

Fixed:

- `repair-app-registry` command parser support
- Fragile Python heredoc behavior by using an external temporary Python repair script

## v0.5.5

Bench app registry hardening release.

Added:

- `sites/apps.txt` normalization
- Repair for concatenated app names such as `erpnextcrm`
- Backup failure detection improvements

## v0.5.4

App Library resume fix.

Fixed:

- Downloaded app folder exists but app missing from `sites/apps.txt`
- Noisy integer comparison warning in app listing

## v0.5.3

Frappe command runner hardening.

Fixed:

- Long multiline commands collapsing inside `bash -lc`
- App Library command reliability when running as the `frappe` user

## v0.5.0

Initial App Library release.

Added:

- Frappe CRM installer
- HRMS installer
- Helpdesk installer
- Insights installer
- Custom Git app installer
- Installed/downloaded app listing

## v0.4.x

Backup, maintenance, and readiness releases.

Added:

- Backup commands
- Backup listing
- Restore commands
- Maintenance menu
- Service readiness waiting after start/restart

## v0.3.x

Installer manager and service releases.

Added:

- Interactive menu
- Status screens
- systemd development service
- autostart support
- access instructions

## v0.2.x

Initial installer hardening.

Added:

- Ubuntu version checks
- Frappe user setup
- Bench path fixes
- early install/status improvements
