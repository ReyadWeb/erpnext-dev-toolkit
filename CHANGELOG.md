# Changelog

## v0.8.2 - Trusted local SSL polish

### Added

- `mkcert-guide` command for browser-trusted local SSL workflow.
- `trusted-local-ssl-guide` alias for `mkcert-guide`.
- `verify-local-ssl` command to summarize SSL status and host test commands.
- `ssl-rollback-guide` command for safe local HTTPS rollback instructions.
- Advanced and Access menu entries for trusted SSL, verification, and rollback.

### Improved

- `ssl-status` now includes stronger certificate diagnostics:
  - certificate type indicator
  - self-signed detection
  - expiry/remaining days
  - private-key permission warning
- `local-ssl-guide` now points users to the dedicated mkcert workflow.
- SSL documentation now separates quick self-signed testing from trusted mkcert usage.

### Unchanged by design

- Existing ERPNext dev systemd service is not replaced.
- Bench direct access on `:8000` remains available.
- v0.8.0 Nginx reverse-proxy behavior remains intact.
- Production SSL remains a future separate production track.
