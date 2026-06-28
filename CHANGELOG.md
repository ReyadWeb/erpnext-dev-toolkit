# Changelog

## v0.8.0 Beta

### Added

- Added `ssl-status` command.
- Added `local-ssl-guide` command.
- Added `configure-local-ssl` command.
- Added `disable-local-ssl` command.
- Added Nginx reverse proxy config generation for local HTTPS.
- Added mkcert/local CA workflow guidance.
- Added local SSL options to Access and Advanced menus.
- Added documentation for local HTTPS architecture.

### Preserved

- Direct Bench access on `http://SITE_NAME:8000` remains unchanged.
- Existing `erpnext-dev.service` behavior remains unchanged.
- App Library behavior from v0.7.0 remains unchanged.

### Notes

- This is a local developer SSL foundation, not a production SSL implementation.
- Production SSL remains a separate future track.
