# ROADMAP

## Current: v0.9.8

Stable developer installer baseline with production readiness/planning classification, structured production domain planning, public VM readiness checks, production SSL/firewall planning, conservative Nginx/Let's Encrypt HTTPS implementation, staging-to-production certificate replacement hotfix, Cloudflare Origin CA SSL provider workflow, Cloudflare PEM paste UX hotfix, share-safe diagnostics, redacted support bundles, optional app compatibility preflight checks, and the first public cloud VM install hotfix.

Completed:

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
- `firewall-hardening-status` post-HTTPS listener exposure checks
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

### v0.9.9

- backup/restore hardening
- backup verification, restore warnings, off-VM backup guidance, and retention planning

### v1.0.0-rc1

- final QA pass
- documentation cleanup
- release checklist and GitHub tag workflow
