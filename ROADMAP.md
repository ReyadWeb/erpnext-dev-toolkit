# Roadmap

## Completed beta milestones

- v0.5.x: App Library validation and app registry repair.
- v0.6.0: Public beta documentation.
- v0.7.0: VM/networking diagnostics and KVM helpers.
- v0.8.0: Local HTTPS reverse proxy foundation.
- v0.8.1: SSL diagnostics and self-signed cert workflow.
- v0.8.2: Trusted local SSL / mkcert guidance.
- v0.8.3: Final local SSL hardening, cert replacement helper, rollback verification.

## Next: v0.9.0 production planning release

Goal: design the production track without destabilizing the developer installer.

Planned work:

- Add production planning documentation.
- Add `production-roadmap` command.
- Add `production-preflight-guide` command.
- Define separate `install-erpnext-prod.sh` architecture.
- Compare Let's Encrypt HTTP-01, DNS-01 with Cloudflare, and Cloudflare Origin CA.
- Document required production services: Nginx, production workers, firewall, backups, monitoring, updates, and restore testing.

## Future production track

Production should be separate from this dev installer. Expected areas:

- Real domain / DNS validation.
- Nginx production config.
- Supervisor or production-grade systemd workers.
- Let's Encrypt or Cloudflare Origin SSL.
- Firewall hardening.
- Automated backups and tested restore.
- Update and maintenance strategy.
- Monitoring and logs.

## v1.0 target

Stable developer installer after clean fresh-VM regression testing, backup/restore validation, app library validation, local HTTPS validation, and documentation review.
