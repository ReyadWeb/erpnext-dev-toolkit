# ERPNext Developer Installer v1.0.0

Local developer installer for ERPNext/Frappe on Ubuntu 24.04/26.04 VMs.

## v1.1.0 production operations

After v1.0.0 deployment is validated, v1.1.0 adds safer production operations:

```bash
/root/install-erpnext-dev.sh production-ops-wizard
/root/install-erpnext-dev.sh backup-schedule-plan
/root/install-erpnext-dev.sh configure-backup-schedule
/root/install-erpnext-dev.sh backup-schedule-status
/root/install-erpnext-dev.sh restore-preflight
```

Scheduled backups use a local systemd timer. They create database + files backups inside the VM. You still need an off-VM backup copy and a restore rehearsal on a disposable VM before trusting production data.


## One-command start

Public VM / production-candidate setup:

```bash
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh public-vm-quickstart
```

Local development VM setup:

```bash
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh && chmod +x /tmp/install-erpnext-dev.sh && sudo /tmp/install-erpnext-dev.sh local-dev-quickstart
```

During quickstart, the script also installs a reusable copy at `/root/install-erpnext-dev.sh`, so later status and maintenance commands can be run from a stable path.

Manual workflow:

```bash
curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh first-run
```

## Important commands

```bash
./install-erpnext-dev.sh first-run
./install-erpnext-dev.sh public-vm-quickstart
./install-erpnext-dev.sh local-dev-quickstart
./install-erpnext-dev.sh set-domain
./install-erpnext-dev.sh show-config
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh verify-access
./install-erpnext-dev.sh local-ssl-wizard
./install-erpnext-dev.sh app-install-wizard
./install-erpnext-dev.sh app-compatibility
./install-erpnext-dev.sh production-readiness
./install-erpnext-dev.sh production-plan
./install-erpnext-dev.sh production-ssl-wizard
./install-erpnext-dev.sh ssl-mode-status
./install-erpnext-dev.sh ssl-mode-guide
./install-erpnext-dev.sh setup-effort-guide
./install-erpnext-dev.sh backup-hardening-wizard
./install-erpnext-dev.sh backup-status
./install-erpnext-dev.sh backup-verify
./install-erpnext-dev.sh off-vm-backup-guide
./install-erpnext-dev.sh restore-rehearsal-guide
./install-erpnext-dev.sh production-checklist
./install-erpnext-dev.sh release-readiness
./install-erpnext-dev.sh final-qa
./install-erpnext-dev.sh security-hardening-wizard
./install-erpnext-dev.sh vm-firewall-status
./install-erpnext-dev.sh fail2ban-status
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh doctor --plain
./install-erpnext-dev.sh doctor --json
./install-erpnext-dev.sh support-bundle
./install-erpnext-dev.sh next-step
```

## v1.0.0 focus

v1.0.0 is the first stable release candidate promoted to final after a fresh public VM rebuild validation. It provides one-command public and local quickstarts, guided domain setup, ERPNext/Frappe v16 installation, production HTTPS choices, Cloudflare Origin CA support, UFW/Fail2Ban hardening, optional app installation, backup verification, release readiness checks, and redacted support bundles.

The public VM path was validated with Cloudflare Origin CA HTTPS, backend ports blocked externally, optional apps installed, and complete backups verified.

Final QA commands:

```bash
./install-erpnext-dev.sh release-readiness
./install-erpnext-dev.sh final-qa
./install-erpnext-dev.sh command-audit
./install-erpnext-dev.sh release-notes-guide
```

## v1.0.0-rc2 focus

v1.0.0-rc2 fixes backup verification for Bench `.tar` file archives, prefers the latest complete backup set, and makes the production checklist Cloudflare-aware. v1.0.0-rc1 added the backup/restore hardening and production checklist commands. It does not make restore automatic or silent; it verifies latest backup files, explains off-VM backup copying, and provides a safe restore rehearsal workflow for disposable test VMs.

New commands:

```bash
./install-erpnext-dev.sh backup-status
./install-erpnext-dev.sh backup-verify
./install-erpnext-dev.sh off-vm-backup-guide
./install-erpnext-dev.sh restore-rehearsal-guide
./install-erpnext-dev.sh production-checklist
./install-erpnext-dev.sh backup-hardening-wizard
```

Production backup verification model:

- Prefer the newest complete backup set containing database, public files, private files, and site config.
- Accept both Bench file archive formats: `.tar` and `.tar.gz`.
- Verify archive readability only; a real restore rehearsal is still required before relying on backups.

Production backup model:

- Create database + public/private files backup.
- Verify latest backup files are readable.
- Copy backups off the VM.
- Rehearse restore on a disposable VM before trusting backups.
- Keep cloud snapshots as infrastructure rollback points.

## v0.9.14 focus

v0.9.14 adds SSL mode guidance and setup effort reporting before the backup/restore release candidate. The installer can now show which SSL path fits the current deployment: local self-signed/mkcert for local VMs, Let’s Encrypt for public DNS-only VMs, or Cloudflare Origin CA for Cloudflare-proxied VMs. It also shows how many shell commands and guided inputs are expected for each setup type.

New commands:

```bash
./install-erpnext-dev.sh ssl-mode-status
./install-erpnext-dev.sh ssl-mode-guide
./install-erpnext-dev.sh ssl-compatibility
./install-erpnext-dev.sh setup-effort-guide
./install-erpnext-dev.sh setup-step-count
```

## v0.9.13 focus

v0.9.13 adds first-run onboarding and one-command quickstarts. Users can now start from GitHub with a single command that opens a guided wizard. Public VM setup prompts for the real ERPNext domain, saves it to `/etc/erpnext-dev-installer/config.env`, then guides the user through DNS planning, install, HTTPS provider selection, and security hardening. Local VM setup stays separate and uses `erp.test` defaults to reduce prompts.

New commands:

```bash
./install-erpnext-dev.sh first-run
./install-erpnext-dev.sh public-vm-quickstart
./install-erpnext-dev.sh local-dev-quickstart
./install-erpnext-dev.sh set-domain
./install-erpnext-dev.sh show-config
```

## v0.9.11 focus

v0.9.11 improves terminal UX for small default terminal windows. It adds a compact categorized help screen, a shorter main menu, quieter production-domain workflows, and bottom-of-command result summaries for UFW and Fail2Ban actions so users do not need to scroll upward to confirm what happened.

UX principles now used by the installer:

- important result summaries appear at the bottom after actions complete
- menus stay short and grouped by task
- long explanations stay in guide/status commands
- production-domain commands do not repeatedly warn that `.test` is recommended for local development
- security/status commands distinguish local VM listeners from external cloud-firewall exposure

Important UX/status commands:

```bash
./install-erpnext-dev.sh help
./install-erpnext-dev.sh menu
./install-erpnext-dev.sh security-hardening-wizard
./install-erpnext-dev.sh vm-firewall-status
./install-erpnext-dev.sh firewall-hardening-status
```

## v0.9.10 focus

v0.9.10 adds optional VM-level hardening with UFW and Fail2Ban. The new safe default UFW profile denies incoming traffic by default, allows outgoing traffic, allows `22/80/443`, and does not allow backend ports `8000/9000/11000/13000`. SSH remains open at the UFW layer by default to avoid lockout caused by dynamic admin IPs; SSH IP restriction should normally be enforced in the cloud provider firewall. Fail2Ban can be enabled for the `sshd` jail to reduce repeated unauthorized SSH login attempts.

New commands:

```bash
./install-erpnext-dev.sh vm-firewall-plan
./install-erpnext-dev.sh configure-vm-firewall
./install-erpnext-dev.sh vm-firewall-status
./install-erpnext-dev.sh configure-fail2ban
./install-erpnext-dev.sh fail2ban-status
./install-erpnext-dev.sh security-hardening-wizard
./install-erpnext-dev.sh ufw-ssh-admin-only   # advanced, lockout risk
```

v0.9.9 improves firewall hardening output after the first real cloud VM + Cloudflare production test. `firewall-hardening-status` now clearly separates **local listeners inside the VM** from **external exposure controlled by the cloud provider firewall**. It no longer implies that `8000/9000` are publicly reachable just because Bench and Socket.io are bound locally; instead it gives workstation-side validation commands to confirm those ports are blocked externally.

v0.9.8 added Cloudflare-aware SSL status and post-HTTPS firewall hardening checks. When Cloudflare Origin CA is active and DNS returns Cloudflare IPs instead of the origin VM IP, `production-ssl-status` now treats that as expected instead of warning.

v0.9.7 fixed and improved the Cloudflare Origin CA paste workflow. The installer now stops reading the certificate automatically at `-----END CERTIFICATE-----` and stops reading the private key automatically at `-----END PRIVATE KEY-----`, `-----END RSA PRIVATE KEY-----`, or `-----END EC PRIVATE KEY-----`. Artificial `END_CERT` and `END_KEY` markers are no longer required.

v0.9.6 added the guided production SSL provider workflow. The installer can help choose between direct Let's Encrypt HTTPS and Cloudflare Origin CA for Cloudflare Full (strict).

The Cloudflare Origin CA path can prompt for the Origin Certificate and Private Key, validate that they match, install them safely under `/etc/ssl/cloudflare-origin`, back up the existing managed Nginx production config, and switch Nginx to the Cloudflare origin certificate.

v0.9.5 remains included as the Let's Encrypt staging-to-production hotfix. It detects installed Let's Encrypt staging certificates and forces replacement with a real production certificate when `LETSENCRYPT_STAGING` is not enabled.

It still does **not** change DNS or firewall rules automatically. Keep cloud firewall changes manual: allow `80/443`, then restrict/close public `8000/9000` only after HTTPS is verified.

Run:

```bash
./install-erpnext-dev.sh production-readiness
./install-erpnext-dev.sh production-plan
./install-erpnext-dev.sh production-ssl-wizard
./install-erpnext-dev.sh ssl-mode-status
./install-erpnext-dev.sh ssl-mode-guide
./install-erpnext-dev.sh setup-effort-guide
./install-erpnext-dev.sh backup-hardening-wizard
./install-erpnext-dev.sh backup-status
./install-erpnext-dev.sh backup-verify
./install-erpnext-dev.sh off-vm-backup-guide
./install-erpnext-dev.sh restore-rehearsal-guide
./install-erpnext-dev.sh production-checklist
./install-erpnext-dev.sh release-readiness
./install-erpnext-dev.sh final-qa
./install-erpnext-dev.sh security-hardening-wizard
./install-erpnext-dev.sh vm-firewall-status
./install-erpnext-dev.sh fail2ban-status
./install-erpnext-dev.sh production-domain-plan
./install-erpnext-dev.sh public-vm-readiness
./install-erpnext-dev.sh production-ssl-plan
./install-erpnext-dev.sh production-firewall-plan
./install-erpnext-dev.sh firewall-hardening-status
./install-erpnext-dev.sh vm-firewall-plan
./install-erpnext-dev.sh configure-vm-firewall
./install-erpnext-dev.sh vm-firewall-status
./install-erpnext-dev.sh configure-fail2ban
./install-erpnext-dev.sh fail2ban-status
./install-erpnext-dev.sh security-hardening-wizard
./install-erpnext-dev.sh production-ssl-wizard
./install-erpnext-dev.sh ssl-mode-status
./install-erpnext-dev.sh ssl-mode-guide
./install-erpnext-dev.sh setup-effort-guide
./install-erpnext-dev.sh configure-production-ssl
./install-erpnext-dev.sh configure-cloudflare-origin-ssl
./install-erpnext-dev.sh cloudflare-origin-ssl-status
./install-erpnext-dev.sh production-ssl-status
```

`production-readiness` checks CPU, RAM, disk, install/runtime/service state, production domain configuration, local SSL assumptions, and backup readiness. It classifies the VM as dev-only, production candidate, or not recommended.

`production-plan` prints the planning checklist for architecture, domain, DNS/network path, SSL, backups, and hardening.

`production-domain-plan` prints a structured DNS/domain plan, including the local `.test` site, planned production domain, recommended A record, provider notes, and warnings when the current VM IP is private/NAT.

`public-vm-readiness` checks the public VM shape: domain resolution, install/runtime state, service/autostart state, Nginx, SSL readiness, backups, HTTP reachability on `:8000`, and current listeners.

`production-ssl-plan` separates development SSL from production SSL and explains the recommended path for a public VM: DNS-only first, Let's Encrypt for the real domain, Nginx on `80/443`, then closing or restricting public `:8000`.

`production-firewall-plan` prints the intended cloud/edge firewall posture: SSH restricted, `80/443` public, `8000` temporary/restricted, and Redis/socket/internal ports closed publicly.

`firewall-hardening-status` checks local listeners after HTTPS is working and explains that the cloud provider firewall controls external exposure. It confirms Redis ports are local-only or closed, marks backend `8000/9000` listeners as internal backend listeners to validate externally, and prints workstation-side curl tests for the origin IP. It does not change firewall rules automatically.

## v0.8.24 optional app compatibility

Check the optional app matrix with:

```bash
./install-erpnext-dev.sh app-compatibility
```

The compatibility check shows:

- detected Frappe branch
- detected ERPNext branch
- target optional app branch
- current app install/download state
- compatibility status and recommendation

The app install wizard also shows a compact compatibility snapshot before the menu, and each app install shows a detailed preflight card before confirmation. Moving branches such as `main` and experimental branches such as `develop` are clearly marked with warnings.

Branch overrides remain available:

```bash
CRM_BRANCH=main
HRMS_BRANCH=version-16
HELPDESK_BRANCH=main
TELEPHONY_BRANCH=develop
INSIGHTS_BRANCH=main
```


## Production SSL provider wizard

Use the provider wizard when you want a smooth SSL choice instead of remembering separate commands:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-wizard
./install-erpnext-dev.sh ssl-mode-status
./install-erpnext-dev.sh ssl-mode-guide
./install-erpnext-dev.sh setup-effort-guide
```

Options:

1. Let's Encrypt directly on the VM. Best when `erp.flowmaya.com` is DNS-only while issuing the certificate.
2. Cloudflare Origin CA. Best when Cloudflare will stay proxied/orange-cloud and Cloudflare SSL/TLS mode will be `Full (strict)`.

### Cloudflare Origin CA path

First create an Origin CA certificate in Cloudflare:

```text
Cloudflare dashboard -> SSL/TLS -> Origin Server -> Create Certificate
Hostname: erp.flowmaya.com
```

Cloudflare shows two values:

- Origin Certificate
- Private Key

Then run:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh configure-cloudflare-origin-ssl
```

The script will ask you to confirm that the certificate has been generated, then prompts you to paste the certificate and private key. The pasted input is not printed to the installer log.

For paste input, paste the exact PEM blocks from Cloudflare:

```text
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
```

and:

```text
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
```

The installer detects the real PEM ending lines automatically. Do not add `END_CERT` or `END_KEY`.

For file-based input instead of paste prompts:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com CLOUDFLARE_ORIGIN_CERT_FILE=/root/cf-origin.pem CLOUDFLARE_ORIGIN_KEY_FILE=/root/cf-origin.key ./install-erpnext-dev.sh configure-cloudflare-origin-ssl
```

After installation, set Cloudflare:

```text
DNS record: erp.flowmaya.com -> Proxied / orange-cloud
SSL/TLS mode: Full (strict)
```

Check with:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh cloudflare-origin-ssl-status
```

Cloudflare Origin CA certificates are not meant to be trusted directly by browsers. Direct DNS-only access to the origin may show a certificate warning; browser traffic should go through Cloudflare.

## Production HTTPS on a public VM

After the public VM is installed, DNS points to the VM, backups are created, and a provider snapshot exists, configure HTTPS with:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh configure-production-ssl
```

Optional environment variables:

```bash
LETSENCRYPT_EMAIL=admin@example.com
LETSENCRYPT_STAGING=true   # dry-run/staging certificate test
```


### Staging-to-production certificate replacement

If you first tested with:

```bash
LETSENCRYPT_STAGING=true SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh configure-production-ssl
```

then switch to the real certificate with:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com LETSENCRYPT_EMAIL=admin@example.com ./install-erpnext-dev.sh configure-production-ssl
```

v0.9.5 detects the installed staging issuer and adds `--force-renewal` automatically so Certbot replaces the staging certificate with a trusted production certificate.

Check status with:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-status
```

Rollback the managed Nginx site without deleting certificates or stopping ERPNext:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh disable-production-ssl
```

After `https://erp.flowmaya.com` works, restrict or close public access to `8000` and `9000` at the cloud firewall.

## Support bundle

Create a redacted support archive with:

```bash
./install-erpnext-dev.sh support-bundle
```

The command creates an archive like:

```text
erpnext-dev-support-bundle-YYYYMMDD-HHMMSS.tar.gz
```

The bundle includes `doctor-plain.txt`, `doctor.json`, JSON validation, system/service/port/storage/SSL/Bench status, recent errors, and a manifest.

The support bundle intentionally excludes credential files, private keys, raw `site_config.json` secrets, tokens, and passwords. Bundle text files are also passed through a redaction step before packaging.

## Diagnostics

The regular `doctor` command shows the existing full health report:

```bash
./install-erpnext-dev.sh doctor
```

For copy/paste support output without ANSI colors, use:

```bash
./install-erpnext-dev.sh doctor --plain
```

For structured tooling and support-bundle generation, use:

```bash
./install-erpnext-dev.sh doctor --json
```

The plain and JSON diagnostic modes intentionally exclude secrets, passwords, tokens, private keys, and credential file contents. They report paths and presence checks only.

## Local SSL

For quick local HTTPS:

```bash
./install-erpnext-dev.sh local-ssl-wizard
```

Self-signed certificates are useful for testing. For trusted browser SSL, use `mkcert` on the host and install the generated cert/key into the VM.

Typical trusted replacement flow:

```bash
# on the HOST
mkcert -install
mkcert -cert-file erp.test.crt -key-file erp.test.key erp.test VM_IP localhost 127.0.0.1
scp erp.test.crt erp.test.key USER@VM_IP:/tmp/

# inside the VM
./install-erpnext-dev.sh local-ssl-wizard
```

Existing VM cert/key files are backed up before replacement.

## Optional apps

Use the checkpoint workflow:

```bash
./install-erpnext-dev.sh app-compatibility
./install-erpnext-dev.sh app-install-wizard
```

The wizard shows a preflight, a compatibility snapshot, backup checkpoint prompts, one-app-at-a-time installation, and post-app validation.

## Quickstart status notes

For public VM setups, the quickstart reads the saved config from `/etc/erpnext-dev-installer/config.env`. If an older install saved `DEPLOYMENT_MODE=development` but also has a valid `PRODUCTION_DOMAIN`, the script treats the current session as a public VM workflow. This avoids confusing status cards on upgraded installations.

Interactive wizards expect menu numbers only. If a shell command is pasted into a wizard prompt by mistake, the wizard exits so the command can be run normally at the shell.
