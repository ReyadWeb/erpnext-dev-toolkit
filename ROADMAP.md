# ERPNext Developer Installer Roadmap

## Current baseline: v0.8.18

v0.8.18 focuses on the local SSL wizard and improves the user path after ERPNext access is verified.

Completed:

- Ubuntu 24.04 / 26.04 support
- Frappe v16 + ERPNext v16 install
- Custom `.test` site name support
- Systemd service and autostart
- Runtime and doctor checks
- Generic root storage expansion
- Private installer logs
- Safer credential output
- Guided setup flow
- Verify access workflow
- Next-step workflow
- Local SSL wizard

## Next recommended patch: v0.8.19

Focus: optional app checkpointing and app-install reliability.

Targets:

- Pre-app installation validation
- Optional app compatibility notes
- Automatic backup checkpoint before optional apps
- Clear app install recovery guidance
- Better app install summary

## Future v0.9.x

Focus: production-readiness planning without mixing dev and production automation.

Targets:

- Production domain planning
- Production SSL planning
- Production Nginx architecture checklist
- Backup/restore validation checklist
- Firewall and monitoring checklist

## v1.x goal

Stable developer installer suitable for repeated fresh VM installs, local testing, and demo environments.
