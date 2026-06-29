# ROADMAP - ERPNext Developer Installer v0.8.8

## Current focus

v0.8.8 adds a production-domain and SSL planning foundation while keeping the current installer focused on local development.

## Completed in v0.8.x

- Fresh ERPNext developer VM setup
- Service/autostart management
- App Library for CRM, HRMS, Helpdesk, Telephony, and Insights
- Backup and maintenance commands
- KVM/network diagnostics
- Local HTTPS reverse proxy workflow
- Host/VM safety guards
- Custom site-name support and config repair
- Compact site-name prompt for small terminals
- Future production domain/SSL planning commands

## v0.8.8 additions

- `domain-config`
- `production-readiness`
- `production-domain-guide`
- `production-ssl-guide`
- Future config fields:
  - `DEPLOYMENT_MODE`
  - `PRODUCTION_DOMAIN`
  - `PRODUCTION_SSL_MODE`

## Next recommended work

1. Finish fresh VM regression testing with a custom `.test` site.
2. Install optional apps one by one and verify `doctor`.
3. Test self-signed local SSL against the custom site name.
4. Harden restore/uninstall flows before v1.0.
5. Start v0.9.0 production planning as a separate branch/track.
