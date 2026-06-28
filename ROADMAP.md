# ERPNext Developer Installer Roadmap

## Current baseline: v0.8.0

v0.8.0 is a beta local developer VM installer with an optional local HTTPS reverse proxy foundation.

Verified core capabilities:

- Ubuntu 24.04 / 26.04 support path
- ERPNext v16 local dev setup
- systemd service/autostart
- readiness wait
- status/doctor reports
- backup/list-backups
- App Library
- CRM, HRMS, Telephony, Helpdesk, Insights install flow
- VM/networking diagnostics
- KVM/libvirt helper commands
- Local SSL guide/status/configuration commands

## v0.8.x — Local SSL hardening

Planned refinements:

- Improve local SSL error handling.
- Add clearer `ssl-status` diagnostics.
- Add rollback verification after disabling local SSL.
- Add optional self-signed certificate helper for testing only.
- Add mkcert copy/trust troubleshooting.
- Add Nginx log helper for SSL issues.
- Confirm websocket/socket.io behavior through HTTPS.

## v0.9.0 — Production planning branch

Production should not be mixed into the current development `bench start` workflow.

Planned production research/design:

- Separate `install-erpnext-prod.sh` concept.
- Production Nginx and Supervisor/systemd worker design.
- Domain/DNS preflight checks.
- Let's Encrypt HTTP-01 plan.
- Let's Encrypt DNS-01 with Cloudflare plan.
- Cloudflare Origin CA plan.
- Firewall profile.
- Backup/restore schedule.
- Update and rollback strategy.
- Monitoring and log rotation.

## v1.0.0 — Stable developer installer criteria

Required before v1.0.0:

- Fresh Ubuntu 24.04 VM test passes.
- Fresh Ubuntu 26.04 VM test passes.
- Reboot/autostart passes.
- Start/stop/restart passes.
- Doctor/status passes.
- Backup/list-backups passes.
- Restore database tested.
- Restore full backup tested.
- CRM install passes.
- HRMS install passes.
- Helpdesk + Telephony install passes.
- Insights install passes.
- Local SSL test passes.
- Uninstall/reset passes on disposable VM.
- README/CHANGELOG/TESTING complete.
- Known limitations documented.
