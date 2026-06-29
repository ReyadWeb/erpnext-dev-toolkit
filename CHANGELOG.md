# Changelog

## v0.8.18

Added local SSL wizard workflow.

Changes:

- Added `local-ssl-wizard` command.
- Added `ssl-wizard` alias.
- Added local SSL wizard to the main menu.
- Added local SSL wizard to the Access submenu.
- Added local SSL wizard to Advanced Options.
- Wizard checks ERPNext direct HTTP before configuring SSL.
- Wizard supports quick self-signed local certificates.
- Wizard supports trusted mkcert workflow from the host.
- Wizard detects existing `/tmp/<site>.crt` and `/tmp/<site>.key` files for mkcert install.
- Wizard verifies HTTPS after configuration.
- `next-step` now points running systems toward `local-ssl-wizard` after access works.
- Documentation updated for the SSL wizard flow.

## v0.8.17

Added guided setup, next-step, and verify-access workflows.

## v0.8.16

Security and reliability cleanup:

- Private installer logs.
- Reduced credential exposure in terminal/logs.
- Installer lock for sensitive operations.
- Post-install validation summary.

## v0.8.15

Fixed setup-time root storage expansion decision logic.
