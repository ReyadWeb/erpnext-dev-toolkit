# Roadmap

## v1.1.0 — Production operations

Status: built.

- Scheduled local backups with systemd timer.
- Production operations wizard.
- Restore preflight and restore rehearsal guidance.
- Production checklist includes scheduled-backup status.

## Next candidates

- Off-VM backup automation targets such as rsync/SFTP or object storage.
- Safer restore automation on disposable VM targets.
- Monitoring and alerting integration.

# ROADMAP

## Current: v1.0.0

Stable v1.0.0 release with stable `/root/install-erpnext-dev.sh` reuse after one-command setup, initial backup prompt in public VM final status, production-mode access guidance, public-aware next-step recommendations, release-readiness summary, command audit, final QA wizard, release-notes guide, complete backup-set verification, Cloudflare-aware production checklist, and backup/restore hardening, production checklist, SSL mode guidance, setup effort/step-count reporting, first-run onboarding, quickstart status hotfixes, one-command GitHub quickstarts, terminal UX cleanup, compact menus/help, production readiness/planning classification, structured production domain planning, public VM readiness checks, production SSL/firewall planning, conservative Nginx/Let's Encrypt HTTPS implementation, staging-to-production certificate replacement hotfix, Cloudflare Origin CA SSL provider workflow, Cloudflare PEM paste UX hotfix, share-safe diagnostics, redacted support bundles, optional app compatibility preflight checks, and the first public cloud VM install hotfix.

Completed:

- stable reusable installer copy at `/root/install-erpnext-dev.sh` during quickstart
- public VM final status initial-backup prompt
- production-mode `verify-access` guidance using HTTPS and backend port-blocking tests
- public-aware `next-step` recommendations
- release-readiness final QA summary
- final QA wizard
- command audit of major workflows
- v1.0.0 release-notes guide
- latest complete backup-set selection
- `.tar` and `.tar.gz` public/private file backup verification
- Cloudflare-aware HTTPS status in production checklist
- post-backup result summary
- backup status inventory
- latest backup file verification without restore
- off-VM backup copy guidance
- restore rehearsal guide for disposable VMs
- production checklist for go-live readiness
- backup hardening wizard

- SSL mode status and compatibility guide
- setup effort / step-count guide for local VM, public Let’s Encrypt, public Cloudflare, and existing installs
- SSL provider wizard recommendation summary
- first-run onboarding wizard
- quickstart status hotfix for existing Cloudflare Origin CA installs
- automatic public-vm session classification when a real production domain is saved
- safer wizard handling when shell commands are pasted into menu prompts
- public VM quickstart for domain -> install -> HTTPS -> security
- local VM quickstart using `erp.test` defaults
- domain prompt and saved config workflow
- official one-command GitHub entry points
- terminal UX cleanup for small default terminal windows
- compact categorized `help` output
- shorter main menu with production/security shortcuts
- quieter production-domain workflow by suppressing local `.test` warning when `PRODUCTION_DOMAIN` is set
- compact bottom result summaries for UFW and Fail2Ban action commands
- ERPNext/Frappe v16 install
- custom local `.test` site names
- autostart service
- runtime and doctor checks
- `doctor --plain` safe copy/paste diagnostics
- `doctor --json` structured diagnostics
- `support-bundle` redacted troubleshooting archive
- `app-compatibility` optional app branch compatibility matrix
- compatibility warnings in `app-install-wizard`
- `production-readiness` environment classification
- `production-plan` planning checklist
- `production-domain-plan` structured DNS/domain planning
- root-run guided setup hotfix for fresh public/cloud VMs
- `public-vm-readiness` public DNS/access/listener readiness
- `production-ssl-plan` production SSL path planning
- `production-firewall-plan` public VM firewall exposure planning
- `configure-production-ssl` Nginx + Let's Encrypt HTTPS implementation
- `production-ssl-status` production HTTPS status checks
- `disable-production-ssl` managed production HTTPS rollback
- Let’s Encrypt staging-to-production replacement detection
- Cloudflare Origin CA SSL provider workflow
- Cloudflare Origin CA PEM paste UX hotfix
- Cloudflare-aware production SSL status
- `firewall-hardening-status` post-HTTPS listener checks
- Cloud firewall vs local listener wording and external validation guidance
- SSL provider wizard
- certificate issuer/status reporting for production SSL
- root storage expansion
- corrected post-expansion storage decision logic
- guided setup flow
- access verification
- local SSL wizard
- trusted mkcert replacement path
- optional app checkpoint workflow
- private installer logs and safer credential handling

## Next recommended work

### Post-v1.0.0

- backup retention policy helper
- scheduled backup helper
- restore automation improvements after additional rehearsal testing
