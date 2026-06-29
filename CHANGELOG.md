# CHANGELOG

## v0.8.8 - Production Domain / SSL Readiness Foundation

### Added

- Added `domain-config` command.
- Added `production-readiness` command.
- Added `production-domain-guide` command.
- Added `production-ssl-guide` command.
- Added future production planning config fields:
  - `DEPLOYMENT_MODE`
  - `PRODUCTION_DOMAIN`
  - `PRODUCTION_SSL_MODE`
- Added production-domain validation helper for future use.

### Changed

- Developer/local `SITE_NAME` remains separate from future production domain planning.
- Config now prepares for production-domain workflows without enabling production automation.
- Access and Advanced menus now include production planning entries.

### Notes

- This is not a production installer.
- Production automation should remain a separate future track.
- Local development still uses Bench/service workflow and optional local SSL.
