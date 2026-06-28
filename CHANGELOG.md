# Changelog

## v0.8.3

Final local SSL hardening release.

### Added

- `install-local-ssl-cert` command.
- `replace-local-ssl-cert` alias.
- `browser-trust-guide` command.
- `verify-ssl-rollback` command.
- Safe cert/key installation from `/tmp` or `LOCAL_SSL_CERT_SOURCE` / `LOCAL_SSL_KEY_SOURCE`.
- Automatic backup of existing local SSL cert/key before replacement.
- Nginx reload after certificate replacement when the local SSL site is enabled.
- Clear host-side trusted certificate checks.

### Improved

- Corrected SSL entries in the Advanced menu.
- Expanded Access menu SSL options.
- Improved mkcert workflow to use the installer cert import helper.
- Added trust guidance to `ssl-status`.
- Improved rollback guidance and verification.

### Preserved

- Existing `http://erp.test:8000` direct Bench access.
- Existing Nginx reverse proxy behavior.
- Existing full app stack support.

## v0.8.2

Trusted local SSL polish with mkcert guide, richer certificate diagnostics, expiry checks, and rollback guide.
