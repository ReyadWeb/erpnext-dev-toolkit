# Changelog

## v1.1.39

### Improved

- Updated the local install finish flow to print the direct next HTTPS command: `sudo erpnext-dev local-ssl-wizard`.
- Kept the broader local SSL menu visible as a secondary option: `sudo erpnext-dev local-ssl-menu`.
- Added a clearer local fixed-IP follow-up command: `sudo erpnext-dev local-fixed-ip-guide`.
- Added aliases for the same stable-IP guidance: `fixed-ip-guide` and `kvm-fixed-ip-guide`.
- Updated README local install guidance so users see the post-install command order: verify HTTP, map host DNS, run local SSL, and optionally reserve a stable VM IP.

## v1.1.38

### Improved

- Reworked the README Start Here section so the first visible items are copy/paste commands.
- Added a general guided setup command using `start-here` so users can choose local or production from the wizard.
- Kept separate first-run commands for local VM installs and production VPS/cloud installs.
- Moved site-name guidance after each command: local defaults to `erp.test`; production uses a real domain such as `erp.example.com`.
- Kept bootstrap path details lower in the README instead of showing them before the install commands.


## v1.1.37 - README start-here cleanup

- Reworked the README **Start here** section so users see the practical install commands first.
- Moved the temporary bootstrap path explanation below the main quickstart commands so `/tmp` details do not distract first-time users.
- Clarified local VM domain behavior: the local wizard asks for a domain and defaults to `erp.test` when the user presses Enter.
- Updated local host DNS instructions to use dynamic toolkit commands (`local-domain-status`, `host-dns-guide`, and `local-access-doctor`) instead of sample IP addresses.
- Kept the stable toolkit path and CLI explanation, but moved it into a short follow-up note after the primary commands.

## v1.1.36 - Central menu navigation hardening

- Added a central `menu_read_choice` handler for all interactive menu prompts so `q`, `Q`, `b`, and `B` are handled consistently across menus and submenus.
- The shared handler trims accidental whitespace and accepts `quit`, `exit`, and `back` as friendly aliases.
- End-of-file / empty piped input is treated as quit so menus do not hang or leak back into the shell during scripted validation.
- Added `menu-self-test` / `menu-navigation-self-test` to safely smoke-test top-level menus, submenus, and nested menu paths for `q/Q` and `b/B` behavior.
- Updated testing coverage so menu navigation regressions are caught before release.

## v1.1.35 - Dynamic local host DNS and access doctor

- Added dynamic VM IP detection for local host mapping. The toolkit no longer assumes `192.168.122.x`; it detects the active VM IP from routing/interface data and supports KVM NAT, bridged LAN, VirtualBox/UTM-style NAT, and other private networks.
- Added `local-domain-status`, `local-access-doctor`, `host-dns-guide`, and `print-hosts-command` aliases for local VM DNS/access troubleshooting.
- Updated `verify-access`, `access`, `local-ssl-menu`, and local domain output to clearly separate VM service checks from host `/etc/hosts` mapping.
- Added safer host-side `/etc/hosts` commands that back up the file, remove old entries for the local domain, and append the current detected VM IP.
- Changed the Access command to open the access/networking submenu so local DNS, access doctor, fixed-IP guidance, and SSL checks are discoverable from one place.
- Documented that `curl: (6) Could not resolve host: erp.test` is a host DNS mapping issue, not an ERPNext/Frappe error.

## v1.1.34 - Environment-aware security profiles and setup lifecycle

- Replaced the generic security hardening flow with environment-aware security profiles so local `.test` VMs do not accidentally lose direct Bench access on ports `8000` and `9000`.
- Added `security-mode-status`, `local-firewall-profile`, `production-firewall-profile`, `repair-local-access`, and `firewall-rollback-snapshots`.
- Added UFW rollback snapshots before toolkit firewall changes under `/var/backups/erpnext-dev/firewall`.
- Changed `configure-vm-firewall` to choose the correct Local VM or Production firewall profile based on saved deployment config.
- Added a Local VM repair path that restores SSH, HTTP, HTTPS, and private-network Bench access after over-hardening.
- Added production hardening guards so production firewall rules require a real production domain and warn if HTTPS is not confirmed.
- Added a setup lifecycle plan covering requirements, domain, install, backup checkpoint, SSL, security profile, optional apps, post-app backups, and final QA.
- Added a core-install backup checkpoint prompt after guided setup verification.
- Added post-app backup checkpoints after every optional app install, controlled by `APP_BACKUP_AFTER_INSTALL`.
- Updated the public VM quickstart menu to follow the safer order: requirements, domain, install, backup, HTTPS, security profile, apps, final QA.

## v1.1.33 - Local domain selection and rename workflow

- Added an interactive local VM domain prompt to `local-dev-quickstart`; pressing Enter keeps the default `erp.test`.
- Added `change-local-domain`, `local-domain-wizard`, `rename-local-site`, and `change-site-domain` command aliases.
- Added a menu entry under **Local VM HTTPS / SSL** to change the local domain after installation.
- Added an Advanced menu entry for the same workflow so domain changes are discoverable from both SSL and maintenance paths.
- The change workflow detects the current Frappe site, creates a safety backup when a site folder exists, runs `bench rename-site`, updates Bench default-site config, updates the toolkit config, disables the old local Nginx SSL site, and prints the host `/etc/hosts` replacement commands.
- Updated help and documentation so the default/fresh-install domain choice and after-install rename path are explicit.

## v1.1.32 - Comprehensive HTTPS menu and handler audit

- Fixed broken Local SSL menu actions by adding the missing central handlers for `local-ssl-wizard`, `ssl-status`, `install-local-ssl-cert`, `verify-local-ssl`, browser trust guidance, rollback guidance, and rollback verification.
- Added shared local SSL helpers so every local HTTPS status/check path uses the same certificate, key, Nginx site, and self-signed detection logic.
- Added a first-level **Production HTTPS / SSL** submenu instead of exposing only a production status check from the main menu.
- Added `production-ssl-menu`, `production-https`, and `production-https-menu` command aliases.
- Updated the main menu labels so local VM SSL and production SSL are clearly separated.
- Audited menu entries against real function handlers to prevent command-not-found failures from menu selections.

## v1.1.31 - Menu UX and local SSL visibility

- Promoted **Local VM HTTPS / SSL** to the main menu so local SSL is visible immediately after installation, alongside Optional Apps.
- Added a dedicated `local-ssl-menu` command and submenu for local SSL wizard, status, guide, mkcert guidance, browser trust checks, certificate install/replace, verification, disable, and rollback verification.
- Changed the long Advanced menu to render with the existing two-column menu helper so the full option list fits normal terminal windows.
- Updated the post-install prompt to show the local SSL menu, optional app wizard, and next-step command before opening the main menu.
- Updated help and documentation so local VM HTTPS is clearly separated from production HTTPS.

## v1.1.30 - Logging and lock permission hardening

- Fixed root/non-root log collisions by replacing timestamp-only `/tmp` log names with unique `mktemp` log files.
- Changed default root logs to `/var/log/erpnext-dev` and default normal-user logs to the user's state directory, with a safe `/tmp/erpnext-dev-<uid>-logs` fallback.
- Kept explicit `LOG_DIR` and `LOG_FILE` overrides supported while preventing accidental same-second collisions when `LOG_FILE` is not provided.
- Reworked toolkit locking to use a shared lock directory at `/tmp/erpnext-dev-locks` instead of the old root-owned `/tmp/erpnext-dev.lock` path.
- Changed generated README/help bootstrap commands to use `mktemp /tmp/erpnext-dev.XXXXXX.sh` instead of a fixed `/tmp/erpnext-dev.sh` path.
- Changed `update-toolkit` and scheduled-backup unit generation to use unique temporary files instead of fixed `/tmp` filenames.
- Added validation coverage for running `sudo erpnext-dev install-cli` followed immediately by non-root `erpnext-dev version` and `erpnext-dev where-installed`.

## v1.1.29 - Rename toolkit and add erpnext-dev CLI

- Standardized the canonical script as `erpnext-dev.sh` and promoted the package to a full toolkit identity.
- Added the stable root-owned toolkit path `/opt/erpnext-dev/erpnext-dev.sh`.
- Added the short user-facing command `/usr/local/bin/erpnext-dev`.
- Added `where-installed`, `install-cli`, `repair-cli`, and `update-toolkit`.
- Updated README, TESTING, and ROADMAP command examples to use `sudo erpnext-dev` after first run.
- Updated the default config directory to `/etc/erpnext-dev`.
- Updated the app name to `ERPNext Developer Toolkit` because the project now covers install, operations, backups, credentials, SSL, security, diagnostics, and optional apps.

## v1.1.27 - README command path clarification

- Clarified why first-run README commands download the installer to `/tmp/erpnext-dev.sh`.
- Clarified that `/tmp/erpnext-dev.sh` is only a temporary bootstrap copy and should not be used as the long-term command path.
- Clarified that `/opt/erpnext-dev/erpnext-dev.sh` is the stable root-owned script path after the first sudo run or after the existing-VM update command.
- Added guidance for users who copy follow-up commands before `/opt/erpnext-dev/erpnext-dev.sh` exists.
- Updated TESTING with README command-path validation checks.

## v1.1.26 - Credentials workflow hardening

- Added `credentials-show` with explicit confirmation before displaying generated passwords.
- Added `credentials-file-status` to report owner, group, mode, size, modified time, and recommended security state.
- Added `credentials-secure` to set the generated credentials file to `root:root` with mode `600`.
- Added `credentials-delete` for production handoff after credentials are saved in a password manager.
- Added `reset-admin-password` so users can safely reset the ERPNext Administrator password without manually entering the Bench directory or relying on the current user's `bench` PATH.
- Updated new installs to create the credentials file with root-only ownership and permissions.
- Updated README and TESTING with the safer credentials workflow.

## v1.1.25 - Education access guidance

- Added `access-info` / `desk-url` command to print the correct Desk, login, website root, and portal URLs.
- Added `education-access-info` / `portal-access-info` command for Education installs.
- Updated `verify-access` to print `/app` and `/login` paths, not only the website root.
- Added a post-install Education note explaining that the website root may open the Education portal and that ERPNext Desk remains available at `/app`.
- Updated README and TESTING notes so Education users are not confused by the portal redirect.


## v1.1.24 - Optional app service-readiness fix

- Fixed optional app installation post-maintenance for local VM installs by ensuring Bench services are running before commands that require Redis, including `bench migrate` and `bench clear-cache`.
- Added a service-readiness helper that starts or restarts `erpnext-dev.service` and waits for the required development ports before app install maintenance continues.
- Updated direct maintenance commands so `migrate` and `clear-cache` now check service readiness instead of failing with `Service redis_cache is not running`.
- Clarified the recovery path: users should use installer service commands or run Bench as the `frappe` user, not as the normal login user.

## v1.1.23 - README command and workflow refresh

- Refreshed README.md to document the current v1.1.22+ installer workflow.
- Added full one-command paths for install preflight, local VM quickstart, public VM quickstart, guided menu, existing VM script update, and optional app wizard.
- Updated post-install examples to use the stable `/opt/erpnext-dev/erpnext-dev.sh` path with `sudo`.
- Added blocking preflight behavior, root storage expansion flow, public SSL commands, local SSL commands, pre-app backup/checkpoint workflow, and current optional app list including Education and Learning / LMS.
- Clarified that the installer creates ERPNext backups from inside the VM, while true VM snapshots/checkpoints must be created from the host/hypervisor.

## v1.1.22 - Add Education app profile

- Added Frappe Education to the curated optional app library.
- Added `install-education` command.
- Added `EDUCATION_BRANCH=version-16` default branch support.
- Updated app library and app installation wizard menus to include Education separately from Learning / LMS.
- Updated optional app compatibility handling, status output, app registry order, help output, and command audit references.

## v1.1.21 - Fit-aware two-column app menus

- Fixed the App Installation Library and App Installation Wizard layout so two-column rendering is based on actual label length instead of a fixed 76-column threshold.
- Kept concise app menu labels from v1.1.19/v1.1.20 while making the layout work better in smaller terminal windows.
- Added `MENU_TERMINAL_COLS` testing support for menu layout validation and preserved one-column fallback when labels truly cannot fit.
- Kept Advanced App Tools behind the safer advanced submenu introduced in v1.1.20.

## v1.1.20 - Safer advanced app tools

- Moved Custom Git app installation out of the main curated App Installation Library list and into a dedicated Advanced App Tools submenu.
- Changed the main app menu item from Custom Git app to Advanced tools so normal users are guided toward curated apps first.
- Added an Advanced App Tools submenu for Custom Git app, app registry repair, rollback guidance, and installed-app review.
- Added stronger warnings and a typed `I UNDERSTAND` confirmation before custom Git app installation can continue.
- Added `advanced-app-tools`, `app-advanced-tools`, and `custom-app-tools` command aliases.
- Kept `install-custom-app` available as an advanced direct command, but made it safer with the same warning and confirmation flow.

## v1.1.19 - Concise app installation menus

- Renamed the App Library heading to App Installation Library so the menu context carries the install meaning.
- Shortened App Library and App Installation Wizard labels by removing repeated “Install”, “Frappe”, and “Show” wording.
- Kept direct install actions and command names unchanged; only the terminal menu labels were simplified.
- Improved `print_two_column_menu` so column width adapts to the current terminal width and falls back to one column on very narrow terminals.
- Shortened long menu labels such as Raven Team Chat and Custom app from Git URL to reduce wrapping in small terminal windows.

## v1.1.18 - Expanded app library and compact two-column menus

- Added curated optional app profiles for Frappe Builder, Frappe Learning / LMS, Frappe Wiki, Frappe Print Designer, Frappe Drive, and Raven Team Chat.
- Added direct install commands: `install-builder`, `install-lms`, `install-wiki`, `install-print-designer`, `install-drive`, and `install-raven`.
- Expanded optional app status, doctor output, app compatibility matrix, app registry normalization, and branch override help to include the new profiles.
- Changed the App Library and Optional App Install Wizard to use a compact two-column terminal layout for smaller terminal windows.
- Kept the existing safe app-install workflow: one app at a time, backup checkpoint prompt, compatibility warning, app install, migrate/build/clear-cache, and post-install validation.

## v1.1.17 - Access verification helper correction

- Fixed `verify-access` by adding the missing `curl_head_status` helper.
- Kept HTTP/HTTPS verification safe: failed HTTP checks now show WARN/INFO instead of shell errors.
- Confirmed `version` / `--version` support remains available from v1.1.16.
- Kept README structure unchanged except for the version title.

## v1.1.16 - App Library menu and version command correction

- Fixed App Library labels so Payments and Webshop appear as direct menu items.
- Aligned App Library menu numbering with the underlying app install actions.
- Added `version` / `--version` command support so version checks do not fail with “Unknown argument”.
- Kept README structure unchanged except for the version title.


## v1.1.15

- Added Frappe Payments to the optional app library, install wizard, status checks, compatibility matrix, command parser, and direct `install-payments` command.
- Added Frappe Webshop / E-Commerce to the optional app library, install wizard, status checks, compatibility matrix, command parser, and direct `install-webshop` / `install-ecommerce` commands.
- Added `PAYMENTS_BRANCH` and `WEBSHOP_BRANCH` branch override documentation for safer repeatable app testing.
- Updated optional app compatibility notes so Payments uses the repository default branch by default and Webshop defaults to `develop` for current v16 testing.
- Cleaned up the App Library menu by removing a duplicate status entry and fixed a duplicate app dependency-preparation call.

## v1.1.14

- Fixed preflight follow-up commands so they use the real active installer path instead of `./erpnext-dev.sh` when the script was downloaded to `/tmp`.
- Updated printed follow-up commands to include `sudo` where installer actions require elevated permissions.
- Added automatic self-copy during install/preflight flows so reusable commands prefer `/opt/erpnext-dev/erpnext-dev.sh` after first sudo execution.
- Changed the install sequence so root-storage expansion is offered before the blocking resource preflight, allowing expanded VM disks to be used before disk checks block the install.
- Improved `install-preflight` so an interactive user can continue directly into `local-dev-quickstart` instead of copying a second command.
- Added a successful guided-install completion message and an optional prompt to open the main installer menu immediately after setup.

## v1.1.13

- Added a blocking install environment preflight for safer fresh VM installs.
- Added CPU checks before ERPNext installation; VMs below the safe minimum are now blocked.
- Changed low RAM and low root disk from warning-only to blocking failures when below safe minimums.
- Added `/tmp` free-space validation so package/build temp-space problems are caught before installation.
- Added `install-preflight` and `environment-preflight` commands for standalone validation before running a quickstart.
- Added a red `INSTALL BLOCKED` summary explaining exactly why installation cannot proceed and what VM resources to increase.
- Added an explicit expert-only override: `ERPNEXT_ALLOW_UNSAFE_INSTALL=true`.

## v1.1.12

- Reworked `ROADMAP.md` into a clearer production-maturity plan.
- Added a future Docker-based ERPNext/Frappe installation track as a separate later approach, not a replacement for the current VM installer.
- Prioritized VM management, monitoring, backup, restore, update, and security hardening work before expanding into Docker deployment.
- Organized upcoming work into staged phases: diagnostics, backup/restore maturity, monitoring/security, production lifecycle, fleet management, and later Docker support.

## v1.1.10

- Added a README hero/banner image for a cleaner project landing section.
- Added a dedicated `Start here` section for users who want to install quickly without reading the full README.
- Added one-command start paths for the guided menu, local VM quickstart, public VPS/cloud VM quickstart, existing-install operations, and optional apps.
- Added Debian-family system update/bootstrap commands using `apt-get update`, `apt-get upgrade`, `curl`, and `ca-certificates`.
- Added a README menu/table of contents so users can jump directly to the needed section.
- Updated quickstart documentation to make the stable `/opt/erpnext-dev/erpnext-dev.sh` follow-up path clearer.

## v1.1.9

- Standardized interactive menu navigation controls.
- Action choices remain numeric, while submenu navigation now uses `b/B` for Back and `q/Q` for Quit.
- Added a separated navigation footer under menu items:

  ```text
  -----------------------------
  b) Back                        q) Quit
  ```

- Main menu now shows `q) Quit` only, because there is no parent menu.
- Removed numbered Back/Exit items from interactive menus to keep menu navigation stable as features are added.
- Updated README and TESTING documentation for the new menu pattern.

## v1.1.8

- Added clear credential-access documentation to `README.md`.
- Added `credentials-info`, `credentials`, and `login-info` commands.
- `credentials-info` shows the ERPNext username, credentials-file path, and safe password-reset commands without printing the password.
- Post-install summary now points users to `credentials-info` and the stable `/opt/erpnext-dev/erpnext-dev.sh` follow-up path.
- Updated help output, command audit, and testing documentation for credential lookup.

## v1.1.7

- Improved local SSL and mkcert guide wording.
- Follow-up commands now use `/opt/erpnext-dev/erpnext-dev.sh` in local SSL instructions so users are not blocked by scripts downloaded to `/tmp`.
- Replaced distro-specific HOST wording with generic Linux HOST wording.
- Improved mkcert Option 2 checklist with clearer HOST vs VM steps.
- Replaced placeholder `USER@VM_IP` examples with a suggested VM SSH user when available.

## v1.1.6

- Reorganized `README.md` into a usage-focused guide instead of a version-history document.
- Moved release/history information fully into `CHANGELOG.md`.
- Added clear local VM testing instructions, including `local-dev-quickstart`, `erp.test`, host-file mapping, and validation commands.
- Kept production quickstart, backup, SSL, security, operations, and optional-app instructions in the README.
- Clarified documentation file responsibilities for README, CHANGELOG, TESTING, ROADMAP, and `docs/assets/`.

## v1.1.5

- Added production health check workflow.
- Added `health-check`, `configure-health-check-timer`, `health-check-status`, `disable-health-check-timer`, and `service-recovery-plan`.
- Added hourly systemd timer option for read-only local health checks.
- Health check summarizes install/runtime, ERPNext service, Nginx, MariaDB, Redis, HTTPS, disk usage, latest backup age/completeness, UFW, Fail2Ban, scheduled backup timer, and off-VM backup state.
- Updated production operations wizard, command audit, help output, and production checklist to include health monitoring.

## v1.1.4

- Hotfix: fixed off-VM rsync SSH command construction when Bash IFS does not use spaces.
- `off-vm-backup-dry-run` and `run-off-vm-backup` now pass a valid `ssh -o ...` command to `rsync -e`.
- Reject documentation placeholder targets such as `backup@example-backup-server:/path/` during target validation.
- Improved guidance to configure a real backup server before testing off-VM backup.

## v1.1.2

- Added backup retention planning for scheduled/local backups.
- Added `backup-retention-plan`, `backup-retention-status`, `cleanup-old-backups-dry-run`, and `cleanup-old-backups`.
- Retention keeps the newest complete backup sets and only deletes old complete backup sets after confirmation.
- Added disk usage warning support with `BACKUP_RETENTION_WARN_DISK_PERCENT`.
- Updated production operations, backup hardening, command audit, and production checklist to include retention status.

## v1.1.1

- Hotfix: ensure production operations commands are registered in the main command dispatcher.
- Verified aliases: `production-ops-wizard`, `operations-wizard`, `ops-wizard`.
- Verified scheduled backup commands: `backup-schedule-plan`, `configure-backup-schedule`, `backup-schedule-status`, `disable-backup-schedule`.
- Verified restore preflight command: `restore-preflight`.


## v1.1.0

- Added scheduled local backups using a systemd service and timer.
- Added `backup-schedule-plan`, `configure-backup-schedule`, `backup-schedule-status`, and `disable-backup-schedule`.
- Added `production-ops-wizard` for release readiness, scheduled backup operations, restore preflight, and support bundle creation.
- Added `restore-preflight` as a safe check-only restore readiness command.
- Updated production checklist and command audit to include scheduled backup operations.

# CHANGELOG

## v1.0.0

### Stable release

- Promoted v1.0.0-rc5 to v1.0.0 after clean public VM quickstart validation.
- Validated public VM flow: domain setup, ERPNext install, Cloudflare Origin CA HTTPS, UFW, Fail2Ban, optional apps, backup creation, backup verification, and release readiness.
- Validated that backend ports 8000 and 9000 remain blocked externally while HTTPS works through Cloudflare/Nginx.
- Keeps the stable reusable installer path at `/opt/erpnext-dev/erpnext-dev.sh` after one-command quickstart runs.
- Keeps provider-neutral cloud firewall wording.

### Production note

- Backup verification confirms files are readable; a real restore rehearsal on a disposable VM is still required before relying on backups for production recovery.

## v1.0.0-rc5

### Improved

- Public/local quickstart now copies the active script to `/opt/erpnext-dev/erpnext-dev.sh` so follow-up commands work after one-command installs from `/tmp`.
- `Next:` command rendering now prefers the stable installer path when available.
- Public VM final status can offer an initial database + files backup and immediately run backup verification/release readiness.
- `verify-access` now presents production-mode access guidance with `https://domain` and backend-port blocking tests instead of only local `:8000` host instructions.
- `next-step` now understands public VM workflows and recommends production SSL, initial backup, or release readiness instead of local HTTPS.

### Notes

- This is a quickstart polish patch. Core install, SSL, firewall, UFW, Fail2Ban, app install, and backup behavior are unchanged except for the optional initial-backup prompt.

## v1.0.0-rc4

### Improved

- Replaced cloud-provider-specific firewall wording with generic cloud provider / cloud firewall wording throughout the script.
- Updated security hardening, UFW, firewall status, production SSL, and production checklist messages so they apply to any cloud provider, not only one vendor.
- Updated README, TESTING, ROADMAP, and CHANGELOG wording for provider-neutral public VM deployments.

### Notes

- This is a wording/UX patch only. It does not change firewall, SSL, UFW, Fail2Ban, backup, or install behavior.

## v1.0.0-rc3

### Added

- Added `release-readiness` for a compact final QA summary before tagging v1.0.0.
- Added `final-qa` / `final-qa-wizard` to group release readiness, command audit, production checklist, backup verification, release notes draft, and support bundle creation.
- Added `command-audit` to summarize the major command groups and validate the user-facing workflow map.
- Added `release-notes-guide` as a compact v1.0.0 release-notes draft.

### Improved

- Added Final QA to the main menu.
- Updated help output with release-readiness commands and final QA workflow.
- Prepared documentation for the final v1.0.0 QA pass.

## v1.0.0-rc2

### Fixed

- Fixed backup status/verification to prefer the latest complete backup set instead of selecting a newer database-only partial set.
- Fixed public/private file archive detection to support both Bench formats: `-files.tar` / `-private-files.tar` and `-files.tar.gz` / `-private-files.tar.gz`.
- Fixed backup archive verification to use gzip-aware tar listing for `.tar.gz` archives and plain tar listing for `.tar` archives.
- Fixed `production-checklist` HTTPS detection so Cloudflare Origin CA / Nginx HTTPS can show `OK` instead of `WARN not confirmed`.

### Improved

- Added `Latest set state` to backup status and verification output, showing `complete` or `partial`.
- Added a compact bottom `Backup Result Summary` after database + files backup creation.

## v1.0.0-rc1

### Added

- Added `backup-status` to show backup folder, counts, latest backup set, and local backup size summary.
- Added `backup-verify` / `verify-backups` to verify the latest database gzip, public files archive, private files archive, and site config JSON without performing a restore.
- Added `off-vm-backup-guide` with workstation-side `rsync` / `scp` examples and checksum guidance.
- Added `restore-rehearsal-guide` with a safe restore test workflow for disposable VMs.
- Added `production-checklist` for go-live readiness across install/runtime, HTTPS, UFW, Fail2Ban, backups, off-VM copy, and snapshots.
- Added `backup-hardening-wizard` / `backup-wizard` to group backup creation, verification, off-VM guidance, restore rehearsal, and production checklist in one compact menu.

### Improved

- Expanded Backup / Restore / Maintenance menu with backup status, verification, off-VM backup guidance, and restore rehearsal steps.
- Kept restore commands destructive and explicit; no automatic restore is performed by status or verification commands.

### Safety

- Backup verification checks file readability only; it clearly states that a real restore rehearsal is still required.
- Restore rehearsal guidance recommends testing on a disposable VM, not the live production VM.


## v0.9.14

### Added

- Added `ssl-mode-status` to show the current SSL provider, DNS state, active certificate path, and recommended SSL mode for the current deployment.
- Added `ssl-mode-guide` / `ssl-compatibility` with a compact SSL compatibility matrix for local self-signed/mkcert, Let’s Encrypt, and Cloudflare Origin CA.
- Added `setup-effort-guide` / `setup-step-count` to show how many shell commands and guided inputs are expected for local VM, public Let’s Encrypt, public Cloudflare, and existing-install workflows.

### Improved

- Production SSL wizard now displays the recommended SSL mode before asking the user to choose a provider.
- Public VM quickstart now includes a quick link to SSL mode guidance and setup step counts.
- First-run wizard now includes setup effort and SSL mode guidance.

## v0.9.13

### Fixed

- Fixed public VM quickstart HTTPS summary so existing Cloudflare Origin CA installs show HTTPS as OK instead of not configured.
- Fixed public VM quickstart domain summary so Cloudflare proxied DNS is treated as expected when Cloudflare Origin CA is active.
- Fixed existing public-domain installs that still had `DEPLOYMENT_MODE=development` in older config files by inferring `public-vm` when a valid production domain is saved.
- Added missing SSL summary helper functions used by the quickstart status card.

### Improved

- Improved interactive menu invalid input handling. If a shell command is pasted into a wizard prompt, the script now explains that the menu expects a number and exits back to the shell instead of repeatedly printing invalid option messages.

## v0.9.12

### Added

- Added first-run onboarding with `first-run`, `setup-wizard`, and `quickstart` aliases.
- Added `public-vm-quickstart` / `public-setup` for a guided public VM flow: domain, DNS plan, install, HTTPS, security, and final status.
- Added `local-dev-quickstart` / `local-setup` for a minimal-input local VM setup using `erp.test`.
- Added `set-domain` to prompt for a production domain and save `SITE_NAME`, `PRODUCTION_DOMAIN`, and deployment mode to the installer config.
- Added `show-config` for a compact saved configuration summary.
- Added official one-command GitHub entry points for public VM and local VM onboarding.

### Improved

- Reduced the need to prefix every command with `SITE_NAME=... PRODUCTION_DOMAIN=...` by saving the domain/site choice in `/etc/erpnext-dev/config.env`.
- Main menu now starts with setup/onboarding options before advanced operations.
- Public VM quickstart prevents users from starting install/HTTPS without first setting a real production domain.

### Safety

- One-command GitHub entry points open guided wizards; they do not silently install production services without prompts.
- Local and public VM setup paths are separated to avoid mixing `.test` development workflows with real public domains.

## v0.9.11

### Improved

- Added terminal UX cleanup for small default terminal windows.
- Replaced the long flat `help` screen with a compact categorized help screen.
- Shortened the main menu and added direct production HTTPS/security-hardening entries.
- Suppressed repeated local `.test` warnings when `PRODUCTION_DOMAIN` is set for public/production-domain workflows.
- Added compact bottom-of-action result summaries for `configure-vm-firewall`, `configure-fail2ban`, and advanced UFW SSH restriction.
- Shortened the security hardening wizard labels so the menu fits more comfortably in smaller terminals.
- Kept long explanations in guide/status commands instead of crowding action output.

### Safety

- No behavior change to firewall rules or SSL configuration.
- UFW still keeps SSH open at the VM layer by default to avoid accidental lockout.
- Backend ports remain blocked by UFW defaults and cloud provider firewall rules.

## v0.9.10

### Added

- Added `vm-firewall-plan` / `ufw-plan` to explain the VM-level UFW hardening model.
- Added `configure-vm-firewall` to install and enable safe UFW defaults.
- Added `vm-firewall-status` / `ufw-status` to inspect UFW status and expected ERPNext public-VM port policy.
- Added `configure-fail2ban` to install Fail2Ban and enable the `sshd` jail.
- Added `fail2ban-status` to inspect Fail2Ban and the `sshd` jail.
- Added `security-hardening-wizard` / `vm-firewall-wizard` to guide UFW and Fail2Ban setup.
- Added advanced `ufw-ssh-admin-only` for users who intentionally want UFW to restrict SSH to a specific admin IP.

### Safety

- `configure-vm-firewall` keeps SSH open at the UFW layer by default to avoid lockout from dynamic admin IPs.
- SSH source restriction remains recommended at the cloud provider firewall layer.
- UFW does not allow `8000`, `9000`, `11000`, or `13000` by default.
- The advanced UFW SSH restriction requires explicit confirmation and warns about lockout risk.

## v0.9.9

### Improved

- Improved `firewall-hardening-status` wording after real cloud firewall validation.
- The command now separates **local listeners inside the VM** from **external public exposure controlled by the cloud firewall**.
- Backend ports `8000` and `9000` are now described as local backend listeners that must be blocked externally, rather than automatically implying they are publicly reachable.
- Added explicit workstation-side validation commands for checking `https://<domain>`, `http://<origin-ip>:8000`, and `http://<origin-ip>:9000`.
- Clarified that `80/443` listeners are expected Nginx entrypoints and may later be restricted to Cloudflare IP ranges when staying proxied.

### Safety

- No firewall rules are changed automatically.
- The command remains inspection/planning only and avoids implying that a local listener bypasses the cloud provider firewall.

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
- The output continues to recommend manual cloud/edge firewall changes after HTTPS is verified.

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
- The command does not change Cloudflare DNS/proxy settings and does not change cloud firewall rules.

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

- This hotfix came from the first public cloud VM SSL test where a staging certificate successfully routed HTTPS but was not trusted by `curl` or browsers.

## v0.9.4

### Added

- Added `configure-production-ssl` to configure Nginx + Let's Encrypt for a public ERPNext domain.
- Added `production-ssl-status` to inspect DNS, Nginx, Certbot, certificate files, HTTP, HTTPS, and listener state.
- Added `disable-production-ssl` to disable the managed production Nginx site without deleting Let's Encrypt certificates or stopping ERPNext.
- Added `LETSENCRYPT_EMAIL`, `LETSENCRYPT_STAGING`, and `PRODUCTION_SSL_WEBROOT` environment overrides.

### Improved

- Production SSL readiness now recognizes an active Let's Encrypt/Nginx HTTPS setup as production SSL.
- Help text and advanced menu now include production SSL implementation commands.
- Public VM flow now moves from planning-only checks to a conservative HTTPS implementation while leaving cloud firewall changes manual.

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

- This is a hotfix from the first real cloud VM test.
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

## v1.1.3 - Off-VM backup automation

- Added rsync-over-SSH off-VM backup workflow.
- Added `off-vm-backup-plan`, `configure-rsync-backup-target`, `off-vm-backup-dry-run`, `run-off-vm-backup`, `off-vm-backup-status`, `disable-off-vm-backup`, and `off-vm-backup-wizard`.
- Integrated off-VM backup status into the production checklist.
- Added off-VM backup options to the Production Operations wizard.
- Keeps safe defaults: dry-run before sync, no remote deletion by default, and no secrets printed to logs.
