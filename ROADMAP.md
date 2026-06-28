# Roadmap

## Current release: v0.8.2

Focus: trusted local SSL polish.

- Self-signed local SSL workflow for quick testing.
- mkcert trusted certificate guide for browser-trusted local SSL.
- SSL status, verification, and rollback guidance.
- Nginx reverse proxy remains optional and does not replace direct Bench access.

## v0.8.x remaining polish

- Add more robust SSL browser-trust troubleshooting.
- Improve Nginx config validation messages.
- Add optional certificate expiry warning in doctor.
- Consider optional `ssl-doctor` alias if SSL diagnostics grow further.

## v0.9.0 production planning branch

Production must remain a separate track from the developer installer.

Planned production topics:

- Production architecture decision.
- Nginx + production workers.
- Supervisor or production systemd units.
- Firewall and port exposure.
- Domain/DNS preflight checks.
- Let's Encrypt HTTP-01.
- Let's Encrypt DNS-01 with Cloudflare.
- Cloudflare Origin CA.
- SSL renewal checks.
- Production backup/restore policy.
- Monitoring and update strategy.

## Future v1.0.0 developer installer criteria

- Fresh Ubuntu 24.04 test passes.
- Fresh Ubuntu 26.04 test passes.
- Reboot/autostart passes.
- Backup and restore are fully tested.
- App Library installs pass cleanly.
- Local HTTPS is stable and documented.
- Uninstall/reset is tested on a disposable VM.
- README, TESTING, CHANGELOG, and ROADMAP are complete.
