# CHANGELOG

## v0.9.8

### Added

- Added `firewall-hardening-status` with aliases `firewall-status` and `hardening-status`.
- The new status command checks local listener exposure for `22`, `80`, `443`, `8000`, `9000`, `11000`, and `13000`.
- It marks `8000` and `9000` as safe to close or restrict once HTTPS is working.
- It warns if Redis ports `11000` or `13000` are ever listening on public interfaces.

### Improved

- `production-ssl-status` is now Cloudflare-aware. When the active provider is Cloudflare Origin CA and DNS returns Cloudflare IPs instead of the origin VM IP, the domain row is treated as expected/OK.
- `public-vm-readiness` now uses the same Cloudflare-aware domain interpretation.
- Help text and advanced menu now include the firewall hardening status command.

### Safety

- No firewall rules are changed automatically. The command is inspection/planning only.
- The output continues to recommend manual Hetzner/edge firewall changes after HTTPS is verified.

## v0.9.7

### Fixed

- Fixed the Cloudflare Origin CA paste workflow so it no longer requires artificial `END_CERT` and `END_KEY` markers.
- Certificate paste input now stops automatically at the real PEM ending line: `-----END CERTIFICATE-----`.
- Private key paste input now stops automatically at the real PEM ending line: `-----END PRIVATE KEY-----`, `-----END RSA PRIVATE KEY-----`, or `-----END EC PRIVATE KEY-----`.

### Improved

- Cloudflare Origin CA prompts now clearly explain the expected PEM start and end patterns.
- The input reader skips leading non-PEM text and starts recording only when the real PEM begin line is detected.
- Windows CRLF paste endings are normalized before validation.
- The Cloudflare Origin CA guide now explicitly shows the required certificate and private key endings.

### Safety

- Certificate and key contents are still hidden during paste input and are not printed into the installer log.
- File-based inputs via `CLOUDFLARE_ORIGIN_CERT_FILE` and `CLOUDFLARE_ORIGIN_KEY_FILE` remain supported and are still recommended for repeatable production work.

## v0.9.6

### Added

- Added `production-ssl-wizard` / `ssl-provider-wizard` to choose between Let's Encrypt and Cloudflare Origin CA.
- Added `configure-cloudflare-origin-ssl` with aliases `install-cloudflare-origin-cert` and `switch-to-cloudflare-origin-ssl`.
- Added `cloudflare-origin-ssl-status` for Cloudflare Origin CA certificate, key, Nginx, proxy-hint, and HTTPS checks.
- Added `cloudflare-origin-guide` with the dashboard workflow for Origin CA and Full (strict).
- Added optional file-based inputs: `CLOUDFLARE_ORIGIN_CERT_FILE` and `CLOUDFLARE_ORIGIN_KEY_FILE`.

### Improved

- `production-ssl-status` now detects the active Nginx certificate provider rather than assuming Let's Encrypt only.
- Production SSL runtime status now recognizes Cloudflare Origin CA and explains why direct DNS-only browser/curl trust may fail until Cloudflare proxy is enabled.
- Existing managed Nginx production config is backed up before switching to Cloudflare Origin CA.

### Safety

- Cloudflare Origin certificate and key are validated before installation.
- The script compares the certificate public key to the private key public key before writing them to `/etc/ssl/cloudflare-origin`.
- The private key is installed with mode `0600`.
- Paste prompts hide input and avoid printing certificate/key contents into the installer log.
- The command does not change Cloudflare DNS/proxy settings and does not change Hetzner firewall rules.

## v0.9.5

### Fixed

- Fixed the Let’s Encrypt staging-to-production transition in `configure-production-ssl`.
- If an installed certificate issuer contains `STAGING` and `LETSENCRYPT_STAGING` is not enabled, the script now adds `--force-renewal` so Certbot replaces the staging certificate with a real production certificate.
- After requesting a non-staging certificate, the script fails clearly if a staging certificate is still installed.

### Improved

- `production-ssl-status` now prints a `Certificate issuer` row.
- Production SSL runtime classification now warns when a staging certificate is installed instead of treating certificate presence alone as sufficient.
- `configure-production-ssl` now displays the existing certificate issuer before making changes.

### Notes

- This hotfix came from the first public Hetzner VM SSL test where a staging certificate successfully routed HTTPS but was not trusted by `curl` or browsers.

## v0.9.4

### Added

- Added `configure-production-ssl` to configure Nginx + Let's Encrypt for a public ERPNext domain.
- Added `production-ssl-status` to inspect DNS, Nginx, Certbot, certificate files, HTTP, HTTPS, and listener state.
- Added `disable-production-ssl` to disable the managed production Nginx site without deleting Let's Encrypt certificates or stopping ERPNext.
- Added `LETSENCRYPT_EMAIL`, `LETSENCRYPT_STAGING`, and `PRODUCTION_SSL_WEBROOT` environment overrides.

### Improved

- Production SSL readiness now recognizes an active Let's Encrypt/Nginx HTTPS setup as production SSL.
- Help text and advanced menu now include production SSL implementation commands.
- Public VM flow now moves from planning-only checks to a conservative HTTPS implementation while leaving Hetzner firewall changes manual.

### Safety

- `configure-production-ssl` validates that the production domain resolves to the current VM IP before requesting a certificate.
- The command requires ERPNext to be installed and running before configuring Nginx.
- The command prompts for confirmation unless `--yes` is used.
- The command does not automatically close ports `8000` or `9000`; firewall changes remain explicit/manual after HTTPS verification.

## v0.9.3

### Added

- Added `public-vm-readiness` command and `public-readiness` alias.
- Added `production-ssl-plan` command and `prod-ssl-plan` alias.
- Added `production-firewall-plan` command and `prod-firewall-plan` alias.
- Added public VM listener summaries for ports `22`, `80`, `443`, `8000`, `9000`, `11000`, and `13000`.
- Added DNS resolution checks comparing the production domain to the detected VM IP.

### Improved

- Production planning now gives a clearer next step after a successful public cloud VM install.
- `production-readiness` and `production-plan` now point to public VM, SSL, and firewall planning commands.
- Help text and advanced menu now include the new production planning commands.

### Safety

- The new production commands are planning/check-only. They do not issue certificates, change DNS, or alter firewall rules.
- Firewall guidance explicitly keeps Redis ports private and treats public `:8000` as temporary testing exposure only.

## v0.9.2

### Fixed

- Fixed root-run guided setup on fresh public/cloud VMs.
- The Frappe/Bench installation phase no longer expands an empty `$SUDO` prefix into an invalid `-H` command when the installer is launched as `root`.
- Added a dedicated `frappe_login_bash` helper so stdin heredoc install blocks run correctly both as root and as a sudo-capable non-root user.

### Notes

- This is a hotfix from the first real Hetzner VM test.
- Production SSL planning moves to the next roadmap patch.

## v0.9.1

### Added

- Added `production-domain-plan` command and `prod-domain-plan` alias.
- Added structured production DNS/domain planning output with local site, planned production domain, VM IP, recommended A record, provider notes, and validation checklist.

### Fixed

- Fixed `production-readiness` false `Incomplete` install state when the Bench folder is under the `frappe` user home and requires sudo traversal.
- Production readiness now uses the same sudo-aware install detection as `doctor` and `status`.
- Backup readiness now checks the backup folder through the sudo-aware path helpers.

### Improved

- `production-plan` and `production-readiness` now resolve saved/detected site config through sudo before reporting.
- Production domain guide now points to the structured `production-domain-plan` command.
- Help text and examples now include `production-domain-plan`.

## v0.9.0

### Added

- Added `production-plan` command and `prod-plan` alias.
- Expanded `production-readiness` from a preview into a production planning classifier.
- Added checks for CPU, RAM, root disk, install state, runtime/service state, production domain setting, local SSL assumptions, Nginx presence, and backup readiness.

### Improved

- Production readiness now classifies the VM as `Dev-only`, `Production candidate`, or `Not recommended`.
- Help text and examples now include `production-plan`.
- The production commands are planning-only and do not apply production changes.

## v0.8.24

### Added

- Added `app-compatibility` command for an optional app compatibility matrix.
- Added aliases `app-compat` and `app-preflight`.
- Added detailed compatibility cards before optional app install confirmation.
- Added compatibility snapshot inside `app-install-wizard`.

### Improved

- App install flow now shows detected Frappe branch, detected ERPNext branch, target app branch, install state, compatibility status, and recommendation before download/install.
- Moving branches such as `main` and experimental branches such as `develop` are now clearly warned before installation.
- Help text and app install guide now document the compatibility command.

### Safety

- Optional app installs now require an extra confirmation when the compatibility preflight returns a warning.
- Remote branch availability is checked before backup/download when a target branch is specified and the app is not already downloaded.

## v0.8.23

### Added

- Added `support-bundle` command for generating a redacted troubleshooting archive.
- Support bundle includes `doctor --plain`, `doctor --json`, JSON validation, system summary, service status, port status, storage status, SSL status, Bench status, recent warnings/errors, and a manifest.
- Added `support` as a short alias for `support-bundle`.

### Safety

- Support bundle generation excludes credential files, TLS private keys, raw `site_config.json` secrets, tokens, and database passwords.
- Bundle text outputs are passed through a redaction step before packaging.
- Generated support archives are written with private file permissions.

### Improved

- Help text now documents `support-bundle`.
- The support workflow builds directly on the v0.8.22 plain and JSON diagnostic primitives.
- Replaced the internal GiB formatter with an `awk` implementation to avoid depending on Python during support/status collection.

## v0.8.22

### Added

- Added `doctor --plain` for share-safe copy/paste diagnostics without ANSI colors.
- Added `doctor --json` for structured share-safe diagnostics.
- Diagnostic output now includes OS, Python, Node, MariaDB, Redis, Bench, site, service, port, storage, SSL, and optional app status summaries.

### Improved

- `active_bench_dir` no longer prints duplicate fallback paths when the expected Bench folder is missing.
- Help text now documents `doctor --plain` and `doctor --json`.

### Safety

- Plain and JSON doctor modes intentionally exclude passwords, tokens, private keys, raw credential contents, and raw site config secrets.

## v0.8.21

### Improved

- `next-step` now shows the decision inputs it used: storage, install, runtime, autostart, and local SSL state.
- `next-step` now moves forward after storage is already expanded instead of making the storage phase feel unresolved.
- Local SSL wizard now supports replacing an already-configured certificate with trusted mkcert files copied into `/tmp`.
- Local SSL wizard now identifies whether the installed certificate appears self-signed.
- `ssl-status` now prints a certificate trust hint to make self-signed vs mkcert-style certificates clearer.
- Missing mkcert source-file guidance now reuses the same HOST/VM instructions and explains replacement backups.

## v0.8.20

### Fixed

- Fixed storage status showing `Expansion recommended` after the root filesystem was already expanded.
- Replaced unsafe whole-disk-vs-partition-size expansion decision with actual partition tail-free-space detection.
- Avoids treating `/boot`, BIOS partitions, and partition start offsets as growable space.
- `expand-root-storage` now skips `growpart` when no growable disk tail exists and only uses existing LVM free space when available.

### Improved

- `storage-debug` now prints both detector and evaluator output.
- `storage-status` can display growable disk tail space when present.

## v0.8.19

- Added optional app checkpoint workflow.
- Added app install wizard and rollback guidance.
