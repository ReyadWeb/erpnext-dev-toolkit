# Security Documentation

This directory contains the technical security documentation for ERPNext Developer Toolkit.

Start with the repository-level [Security Policy](../../SECURITY.md). It defines supported versions, private vulnerability reporting, current guarantees, operator responsibilities, and known limitations.

## Documents

| Document | Purpose |
|---|---|
| [Security architecture](SECURITY-ARCHITECTURE.md) | Trust boundaries, privileged execution, integrity, credentials, networking, backups, diagnostics, and CI controls |
| [Release trust](RELEASE-TRUST.md) | Signed-release chain, manual verification, atomic updates, signing authority, and key rotation |
| [Production hardening](PRODUCTION-HARDENING.md) | Operator checklist for a public ERPNext server |
| [Security history](SECURITY-HISTORY.md) | Historical milestones and retired security gaps |

## Audience

- **Operators** should read the root policy and production hardening guide.
- **Security reviewers** should read the architecture and release-trust documents.
- **Maintainers** should also review release automation and security history.

Related references:

- [Release automation](../RELEASE-AUTOMATION.md)
- [Release process](../RELEASE-PROCESS.md)
- [Production validation](../../VALIDATION.md)
- [Support policy](../../SUPPORT.md)
- [Published signing key](../erpnext-dev-signing-key.asc)
