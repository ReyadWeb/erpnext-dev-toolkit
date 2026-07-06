# v1.1.14 validation

Validate the safer preflight command flow, storage-first install sequence, sudo/path command output, and version bump.

## v1.1.14 command-path validation

Run from a temporary path, matching the one-command install method:

```bash
cp ./install-erpnext-dev.sh /tmp/install-erpnext-dev.sh
chmod +x /tmp/install-erpnext-dev.sh
sudo /tmp/install-erpnext-dev.sh help | grep -E "sudo /tmp/install-erpnext-dev.sh|local-dev-quickstart"
```

Expected:

- Help and next-step examples include `sudo`.
- Commands reference the active script path when `/root/install-erpnext-dev.sh` is not installed yet.
- After a sudo preflight/quickstart run, follow-up commands prefer `/root/install-erpnext-dev.sh` when the self-copy succeeds.

Interactive VM test:

```bash
sudo /tmp/install-erpnext-dev.sh install-preflight
```

Expected:

- Preflight passes or blocks with clear red `INSTALL BLOCKED` rows.
- On pass, the user is offered to start `local-dev-quickstart` directly.
- The user does not need to copy `./install-erpnext-dev.sh local-dev-quickstart`.
- The actual install path offers root-storage expansion before the final blocking resource preflight.
- After successful guided install, the script prints a success message and asks whether to open the main menu.


```bash
chmod +x install-erpnext-dev.sh
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
./install-erpnext-dev.sh help | grep -E "install-preflight|environment-preflight|ERPNEXT_ALLOW_UNSAFE_INSTALL"
./install-erpnext-dev.sh command-audit | grep -E "Preflight|install-preflight"
```

Expected:

```text
SCRIPT_VERSION="1.1.14"
install-preflight is accepted by the dispatcher
environment-preflight is accepted as an alias
help shows the expert-only ERPNEXT_ALLOW_UNSAFE_INSTALL override
command-audit includes the Preflight command group
```

Fresh VM pre-install check:

```bash
sudo ./install-erpnext-dev.sh install-preflight
```

Expected on a healthy VM:

```text
CPU cores            OK/WARN
RAM                  OK/WARN
Root free disk        OK/WARN
/tmp free disk        OK
Blockers             OK      0
OK: Install environment preflight passed
```

Expected on an undersized VM:

```text
CPU/RAM/root disk or /tmp row shows FAIL
INSTALL BLOCKED appears in red on interactive terminals
The script exits before package installation, bench creation, user creation, or database changes
```

Developer override smoke test only, not recommended for real users:

```bash
ERPNEXT_ALLOW_UNSAFE_INSTALL=true sudo -E ./install-erpnext-dev.sh install-preflight
```

Expected: the preflight still shows FAIL rows, but prints an explicit unsafe-override warning.

---

# v1.1.10 validation

Validate the README Start here section, banner asset, and script version.

```bash
chmod +x install-erpnext-dev.sh
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
grep -n "Start here" README.md
grep -n "README menu" README.md
grep -n "erp_installer_readme_banner.png" README.md
test -f docs/assets/erp_installer_readme_banner.png
grep -n "apt-get update" README.md
grep -n "local-dev-quickstart" README.md
grep -n "public-vm-quickstart" README.md
grep -n "production-ops-wizard" README.md
```

Expected:

```text
SCRIPT_VERSION="1.1.10"
README contains the Start here section
README contains a menu/table of contents
README references docs/assets/erp_installer_readme_banner.png
README includes Debian-family system update/bootstrap commands
README includes one-command paths for menu, local VM, public VM, and operations
```

Quick smoke test for the guided menu command path:

```bash
printf 'q\n' | ./install-erpnext-dev.sh menu
```

Expected: the main menu opens and accepts `q`/`Q` to quit.

---

# v1.1.9 validation

Validate the credential-info command and docs update:

```bash
chmod +x install-erpnext-dev.sh
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
./install-erpnext-dev.sh help | grep -E "credentials-info|verify-access"
./install-erpnext-dev.sh command-audit | grep -E "Credentials|credentials-info"
./install-erpnext-dev.sh credentials-info
```

Expected:

```text
SCRIPT_VERSION="1.1.9"
credentials-info is accepted by the dispatcher
credentials-info shows the credentials file path
credentials-info does not print the generated password
README contains the credential lookup section
```

On an installed VM, validate:

```bash
/root/install-erpnext-dev.sh credentials-info
sudo test -f /home/frappe/erpnext-dev-credentials.txt
sudo cat /home/frappe/erpnext-dev-credentials.txt
```

Expected: `credentials-info` explains where the login password is stored, and the direct `sudo cat` command shows the generated credentials only when the admin intentionally asks for them.


## Local VM quickstart validation

Use this scenario for a fresh local VM test. Do not use a production domain.

```bash
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/install-erpnext-dev.sh
chmod +x /tmp/install-erpnext-dev.sh
sudo /tmp/install-erpnext-dev.sh local-dev-quickstart
```

Recommended site: `erp.test`.

Validate inside the VM:

```bash
/root/install-erpnext-dev.sh doctor --plain
/root/install-erpnext-dev.sh verify-access
/root/install-erpnext-dev.sh backup-files
/root/install-erpnext-dev.sh backup-status
/root/install-erpnext-dev.sh backup-verify
```

Validate from the host after adding a hosts entry:

```bash
curl -I http://LOCAL_VM_IP:8000
curl -I http://erp.test:8000
curl -Ik https://erp.test
```

Expected: install OK, runtime via service, direct HTTP working, friendly hostname working, and local HTTPS optional.

# TESTING

## v1.1.4 validation

```bash
chmod +x install-erpnext-dev.sh
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
./install-erpnext-dev.sh help | grep -E "off-vm-backup|run-off-vm-backup"
printf '17\n' | ./install-erpnext-dev.sh production-ops-wizard
```

Expected:

```text
SCRIPT_VERSION="1.1.4"
production-ops-wizard opens
off-VM backup commands are accepted
```

On a VM with a real backup target configured, validate:

```bash
/root/install-erpnext-dev.sh configure-rsync-backup-target
/root/install-erpnext-dev.sh off-vm-backup-dry-run
/root/install-erpnext-dev.sh run-off-vm-backup
/root/install-erpnext-dev.sh off-vm-backup-status
```

Expected: rsync uses a valid SSH transport command. If the remote host is unreachable, the error should be a normal SSH/DNS/authentication error, not `Failed to exec ssh#012-o...`.

## v1.1.1 validation

```bash
chmod +x install-erpnext-dev.sh
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
grep -n "production-ops-wizard" install-erpnext-dev.sh
./install-erpnext-dev.sh help | grep -E "production-ops-wizard|backup-schedule|restore-preflight"
printf '8\n' | ./install-erpnext-dev.sh production-ops-wizard
```

Expected:

```text
SCRIPT_VERSION="1.1.1"
production-ops-wizard is accepted and opens the operations wizard
```


## v1.0.0 validation

```bash
chmod +x install-erpnext-dev.sh
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
```

Expected:

```text
SCRIPT_VERSION="1.0.0"
```

Quickstart/final QA commands:

```bash
./install-erpnext-dev.sh help | grep -E "release-readiness|final-qa|command-audit"
./install-erpnext-dev.sh release-readiness
./install-erpnext-dev.sh command-audit
./install-erpnext-dev.sh release-notes-guide
./install-erpnext-dev.sh verify-access
/tmp/install-erpnext-dev.sh public-vm-quickstart   # should copy itself to /root on real quickstart runs
printf '7\n' | ./install-erpnext-dev.sh final-qa
```

Expected:

- `release-readiness` gives a compact final QA status across syntax, install, runtime, HTTPS, UFW, Fail2Ban, and latest backup completeness.
- `command-audit` lists the major command groups without making changes.
- `release-notes-guide` prints a compact v1.0.0 release-notes draft.
- `final-qa` opens and exits cleanly.
- In public VM mode, `verify-access` shows HTTPS and backend-port blocking tests.
- After a one-command quickstart run, `/root/install-erpnext-dev.sh` exists and is executable.
- Public VM validation should confirm HTTPS returns HTTP/2 200 and backend ports 8000/9000 time out externally.

## v1.0.0-rc2 validation

```bash
chmod +x install-erpnext-dev.sh
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
```

Expected:

```text
SCRIPT_VERSION="1.0.0-rc2"
```

Backup/restore hardening commands:

```bash
./install-erpnext-dev.sh help | grep -E "backup-status|backup-verify|off-vm-backup-guide|restore-rehearsal-guide|production-checklist|backup-hardening-wizard"
./install-erpnext-dev.sh backup-status
./install-erpnext-dev.sh backup-verify
./install-erpnext-dev.sh off-vm-backup-guide
./install-erpnext-dev.sh restore-rehearsal-guide
./install-erpnext-dev.sh production-checklist
printf '8\n' | ./install-erpnext-dev.sh backup-hardening-wizard
```

Expected:

- `backup-status` reports backup folder, counts, latest set, and off-VM copy reminder.
- `backup-verify` checks latest database gzip and public/private tar files without restoring.
- `off-vm-backup-guide` prints workstation-side `rsync` and `scp` examples.
- `restore-rehearsal-guide` explicitly recommends a disposable test VM.
- `production-checklist` summarizes install/runtime, HTTPS, UFW, Fail2Ban, backups, and snapshot requirements.



## v0.9.14 validation

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh help
./install-erpnext-dev.sh ssl-mode-guide
./install-erpnext-dev.sh setup-effort-guide
./install-erpnext-dev.sh ssl-mode-status
printf '5\n6\n' | ./install-erpnext-dev.sh first-run
printf '7\n8\n' | ./install-erpnext-dev.sh public-vm-quickstart
```

Expected:

- `ssl-mode-guide` shows local self-signed/mkcert, Let’s Encrypt, and Cloudflare Origin CA modes.
- `setup-effort-guide` shows command/input counts for local VM, public Let’s Encrypt, public Cloudflare, and existing installs.
- Production SSL wizard shows a recommended SSL mode before provider selection.

# TESTING v0.9.13

## Syntax

```bash
chmod +x install-erpnext-dev.sh
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
```

Expected:

```text
SCRIPT_VERSION="0.9.12"
```

## First-run / quickstart UX

```bash
./install-erpnext-dev.sh help | grep -E "first-run|public-vm-quickstart|local-dev-quickstart|set-domain|show-config"
printf '5\n' | ./install-erpnext-dev.sh first-run
printf '7\n' | ./install-erpnext-dev.sh public-vm-quickstart
printf 'n\n' | ./install-erpnext-dev.sh local-dev-quickstart
```

Expected:

- Help lists the new onboarding commands.
- `first-run` shows Local VM, Public VM, Maintenance, config, and exit choices.
- `public-vm-quickstart` shows domain, install, HTTPS, security, and final-status steps.
- `local-dev-quickstart` shows a compact local setup summary and does not require a production domain.

## Saved domain config

```bash
printf 'erp.example.com\ny\n' | \
CONFIG_FILE=/tmp/erpnext-test-config.env \
LEGACY_CONFIG_FILE=/tmp/erpnext-test-legacy.env \
./install-erpnext-dev.sh set-domain
```

Expected:

- Saves `SITE_NAME=erp.example.com`.
- Saves `PRODUCTION_DOMAIN=erp.example.com`.
- Saves `DEPLOYMENT_MODE=public-vm`.
- Prints a compact result summary at the bottom.

## Help command

```bash
./install-erpnext-dev.sh help | grep -E "first-run|public-vm-quickstart|local-dev-quickstart|set-domain|show-config|doctor --plain|doctor --json|support-bundle|app-compatibility|production-plan|production-domain-plan|public-vm-readiness|production-ssl-plan|production-firewall-plan|firewall-hardening-status|production-ssl-wizard|configure-production-ssl|configure-cloudflare-origin-ssl|cloudflare-origin-ssl-status|cloudflare-origin-guide|production-ssl-status|disable-production-ssl|vm-firewall-plan|configure-vm-firewall|vm-firewall-status|configure-fail2ban|fail2ban-status|security-hardening-wizard"
```

Expected:

- Help lists `first-run`, `public-vm-quickstart`, `local-dev-quickstart`, `set-domain`, and `show-config`.
- Help lists `doctor --plain`.
- Help lists `doctor --json`.
- Help lists `support-bundle`.
- Help lists `app-compatibility`.
- Help lists `production-plan`.
- Help lists `production-domain-plan`.
- Help lists `public-vm-readiness`.
- Help lists `production-ssl-plan`.
- Help lists `production-firewall-plan`.
- Help lists `firewall-hardening-status`.
- Help lists `production-ssl-wizard`.
- Help lists `configure-production-ssl`.
- Help lists `configure-cloudflare-origin-ssl`.
- Help lists `cloudflare-origin-ssl-status`.
- Help lists `cloudflare-origin-guide`.
- Help lists `production-ssl-status`.
- Help lists `disable-production-ssl`.
- Help lists `vm-firewall-plan`.
- Help lists `configure-vm-firewall`.
- Help lists `vm-firewall-status`.
- Help lists `configure-fail2ban`.
- Help lists `fail2ban-status`.
- Help lists `security-hardening-wizard`.



## Production readiness / planning

```bash
./install-erpnext-dev.sh production-readiness
./install-erpnext-dev.sh production-plan
./install-erpnext-dev.sh prod-plan
./install-erpnext-dev.sh production-domain-plan
./install-erpnext-dev.sh prod-domain-plan
./install-erpnext-dev.sh public-vm-readiness
./install-erpnext-dev.sh public-readiness
./install-erpnext-dev.sh production-ssl-plan
./install-erpnext-dev.sh prod-ssl-plan
./install-erpnext-dev.sh production-firewall-plan
./install-erpnext-dev.sh prod-firewall-plan
./install-erpnext-dev.sh firewall-hardening-status
./install-erpnext-dev.sh firewall-status
./install-erpnext-dev.sh hardening-status
```

Expected:

- `production-readiness` shows a classification row.
- It reports CPU, RAM, root disk, install/runtime/service state, domain status, SSL planning status, and backup readiness.
- It remains planning-only and does not modify the VM.
- `production-plan` prints a checklist for architecture, domain, DNS/network path, SSL, backup/restore, and hardening.
- `prod-plan` works as an alias.
- `production-domain-plan` prints structured DNS/domain planning output.
- `prod-domain-plan` works as an alias.
- On an installed/running VM, `production-readiness` should not falsely report `Install state WARN Incomplete`.
- `public-vm-readiness` reports DNS match/mismatch, install/runtime/service state, Nginx, SSL, backups, HTTP `:8000` checks, and listener summary.
- `production-ssl-plan` prints the planning-only SSL path and distinguishes local/dev SSL from production SSL.
- `production-firewall-plan` prints the temporary test exposure and long-term production exposure recommendations.
- `firewall-hardening-status` explains that rows are local VM listeners and that cloud firewall rules control external exposure.
- It provides workstation-side validation commands for HTTPS and origin `8000/9000`.
- It describes `8000/9000` as backend listeners to block externally after HTTPS is working.
- `firewall-status` and `hardening-status` work as aliases.
- New aliases run the same corresponding commands.


## Cloudflare Origin CA SSL workflow

Guide/status checks:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh cloudflare-origin-guide
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh cloudflare-origin-ssl-status
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-wizard
```

Expected:

- The guide explains Origin Server certificate creation, proxied/orange-cloud DNS, and Full (strict).
- `cloudflare-origin-ssl-status` reports missing cert/key before configuration.
- The wizard offers Let's Encrypt, Cloudflare Origin CA, status, and guide options.

File-input configuration test:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com CLOUDFLARE_ORIGIN_CERT_FILE=/root/cf-origin.pem CLOUDFLARE_ORIGIN_KEY_FILE=/root/cf-origin.key ./install-erpnext-dev.sh configure-cloudflare-origin-ssl
```

Expected:

- The certificate and key are validated as a pair.
- The key is installed under `/etc/ssl/cloudflare-origin` with mode `0600`.
- Existing managed production Nginx config is backed up.
- Nginx is rewritten to use the Cloudflare Origin CA certificate.
- The command does not alter Cloudflare DNS/proxy settings or cloud firewall rules.

Paste-input configuration test:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh configure-cloudflare-origin-ssl
```

Expected:

- The command asks whether the Cloudflare Origin CA certificate/private key have been generated.
- The command prompts for the certificate and private key using the real PEM boundaries, not artificial markers.
- Certificate input stops at `-----END CERTIFICATE-----`.
- Private key input stops at `-----END PRIVATE KEY-----`, `-----END RSA PRIVATE KEY-----`, or `-----END EC PRIVATE KEY-----`.
- Input is hidden and not printed into the installer log.
- Invalid or mismatched key material fails before Nginx is changed.


Manual paste UX check:

```text
Paste the Cloudflare Origin Certificate PEM block now.
Expected start pattern: ^-----BEGIN CERTIFICATE-----$
Expected end pattern:   ^-----END CERTIFICATE-----$
```

Expected:

- No `END_CERT` marker is required.
- The prompt advances automatically after `-----END CERTIFICATE-----`.
- The key prompt advances automatically after the matching private-key end line.

## Production HTTPS implementation

Planning/status checks:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-plan
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-status
```

Expected before configuration:

- `production-ssl-status` reports Nginx/Certbot/certificate as missing or not enabled.
- It does not modify the VM.

Real public VM configuration test:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh configure-production-ssl
curl -I https://erp.flowmaya.com
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-status
```

Expected after configuration:

- Nginx is installed and active.
- Certbot is installed.
- Let's Encrypt certificate exists under `/etc/letsencrypt/live/erp.flowmaya.com/`.
- `https://erp.flowmaya.com` returns an HTTP status.
- `production-readiness` recognizes production SSL as OK.


Staging-to-production replacement test:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com LETSENCRYPT_STAGING=true ./install-erpnext-dev.sh configure-production-ssl
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-status
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com LETSENCRYPT_EMAIL=admin@example.com ./install-erpnext-dev.sh configure-production-ssl
curl -I https://erp.flowmaya.com
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-status
```

Expected:

- After the staging run, `production-ssl-status` shows `Certificate issuer WARN` and indicates a staging certificate.
- The non-staging run detects the staging certificate and forces production replacement.
- After replacement, `curl -I https://DOMAIN` works without `-k`.
- `production-ssl-status` shows a non-staging issuer and `Overall OK`.

Rollback test:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh disable-production-ssl
```

Expected:

- Managed production Nginx site symlink is removed.
- Let's Encrypt certificate files are not deleted.
- ERPNext on `:8000` is not stopped.

## Optional app compatibility

```bash
./install-erpnext-dev.sh app-compatibility
```

Expected:

- Command shows the detected Frappe branch.
- Command shows the detected ERPNext branch.
- Command lists CRM, HRMS, Insights, Telephony, and Helpdesk.
- Each app row shows target branch, current state, compatibility status, and recommendation detail.
- Moving branches such as `main` show a warning or informational compatibility note.
- Experimental branches such as `develop` show a warning.

Alias checks:

```bash
./install-erpnext-dev.sh app-compat
./install-erpnext-dev.sh app-preflight
```

Expected:

- Aliases run the same compatibility matrix.

## App wizard compatibility snapshot

```bash
./install-erpnext-dev.sh app-install-wizard
```

Expected:

- Wizard preflight shows a compatibility snapshot before the menu.
- The menu includes `Show optional app compatibility`.
- Selecting an app shows a detailed compatibility card before the final install confirmation.
- Warning-level compatibility findings ask for an extra confirmation before install continues.

## Doctor plain/json diagnostics

```bash
./install-erpnext-dev.sh doctor --plain
./install-erpnext-dev.sh doctor --json > /tmp/erpnext-doctor.json
python3 -m json.tool /tmp/erpnext-doctor.json >/tmp/erpnext-doctor.pretty.json
```

Expected:

- `doctor --plain` prints a readable diagnostics report without ANSI color codes.
- `doctor --json` prints valid JSON.
- Both modes include OS, Python, Node, MariaDB, Redis, Bench, site, service, port, storage, SSL, and optional app status summaries.
- Neither mode prints passwords, tokens, private keys, raw credential contents, or raw site config secrets.

## Doctor argument order

```bash
./install-erpnext-dev.sh --plain doctor
./install-erpnext-dev.sh --json doctor > /tmp/erpnext-doctor-order.json
python3 -m json.tool /tmp/erpnext-doctor-order.json >/dev/null
./install-erpnext-dev.sh --json > /tmp/erpnext-doctor-default.json
python3 -m json.tool /tmp/erpnext-doctor-default.json >/dev/null
```

Expected:

- Diagnostic format flags work before or after the `doctor` action.
- `--json` alone defaults to the doctor action and produces valid JSON.

## Support bundle

```bash
./install-erpnext-dev.sh support-bundle
```

Expected:

- Command creates `/tmp/erpnext-dev-support-bundle-YYYYMMDD-HHMMSS.tar.gz` unless `SUPPORT_BUNDLE_DIR` is overridden.
- Command prints the final archive path.
- Archive permissions are private, usually `600`.
- Temporary bundle directory is removed after packaging.

Inspect the archive:

```bash
BUNDLE="$(ls -1t /tmp/erpnext-dev-support-bundle-*.tar.gz | head -1)"
tar -tzf "$BUNDLE"
mkdir -p /tmp/erpnext-support-review
rm -rf /tmp/erpnext-support-review/*
tar -xzf "$BUNDLE" -C /tmp/erpnext-support-review
find /tmp/erpnext-support-review -type f -maxdepth 2 -print
python3 -m json.tool /tmp/erpnext-support-review/*/doctor.json >/dev/null
```

Expected archive files:

```text
manifest.txt
doctor-plain.txt
doctor.json
doctor-json-validation.txt
system-summary.txt
service-status.txt
port-status.txt
storage-status.txt
ssl-status.txt
bench-status.txt
recent-errors.txt
```

Expected safety behavior:

- Archive does not include `erpnext-dev-credentials.txt`.
- Archive does not include raw `site_config.json`.
- Archive does not include `.key` files or TLS private keys.
- Archive does not include raw database credentials.
- Included text files are redacted before packaging.

Optional redaction smoke test after extraction:

```bash
grep -RInE "password[=:]|token[=:]|secret[=:]|api[_-]?key[=:]|BEGIN .*PRIVATE KEY" /tmp/erpnext-support-review || true
```

Expected:

- No unredacted secrets should appear.
- Safe explanatory text such as “passwords are excluded” may still appear.

## Support alias

```bash
./install-erpnext-dev.sh support
```

Expected:

- Same behavior as `support-bundle`.

## Next-step regression test after storage expansion

On a VM whose root filesystem is already expanded:

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh next-step
```

Expected storage status:

```text
Expansion OK not needed
```

Expected `next-step` behavior:

- It should show storage as OK / not needing expansion.
- It should recommend the next real workflow step: setup, start, enable autostart, local SSL, or optional app wizard.
- It should not recommend `expand-root-storage` unless actual VG free space or growable disk tail space exists.

## Fresh cloned VM storage test

On a cloned VM where the virtual disk is larger than the root partition:

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh storage-status
df -h /
```

Expected before expansion:

```text
Expansion WARN recommended
```

Expected after expansion:

```text
Expansion OK not needed
```

## Local SSL replacement test

With local HTTPS already configured using a self-signed certificate:

```bash
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh local-ssl-wizard
```

Expected:

- `ssl-status` prints a certificate trust hint.
- `local-ssl-wizard` detects that HTTPS is already configured.
- The wizard offers to keep the current SSL, replace/install mkcert files from `/tmp`, regenerate self-signed SSL, or show status only.

For the trusted replacement path:

```bash
# on HOST
mkcert -install
mkcert -cert-file erp.test.crt -key-file erp.test.key erp.test VM_IP localhost 127.0.0.1
scp erp.test.crt erp.test.key USER@VM_IP:/tmp/

# inside VM
./install-erpnext-dev.sh local-ssl-wizard
./install-erpnext-dev.sh ssl-status
```

Expected:

- Existing VM cert/key files are backed up.
- Cert/key permissions are enforced as root:root 644/600.
- Nginx is tested and reloaded when SSL is already enabled.

## Runtime validation

```bash
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh app-compatibility
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh doctor --plain
./install-erpnext-dev.sh doctor --json
./install-erpnext-dev.sh support-bundle
./install-erpnext-dev.sh verify-access
./install-erpnext-dev.sh ssl-status
```

## v0.9.2 hotfix test

Fresh public/root VM scenario:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh guided-setup
```

Expected:

- system package installation can complete
- `frappe` user is prepared
- installer enters the Node/Python/Bench/Frappe/ERPNext phase as the `frappe` user
- it must not fail with `-H: command not found` when launched as root

Regression checks:

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh production-domain-plan
./install-erpnext-dev.sh production-readiness
./install-erpnext-dev.sh doctor --json > /tmp/doctor.json
python3 -m json.tool /tmp/doctor.json
```


## v0.9.9 Cloudflare/firewall validation

On a Cloudflare Origin CA deployment where DNS returns Cloudflare IPs instead of the origin VM IP:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh production-ssl-status
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh cloudflare-origin-ssl-status
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh firewall-hardening-status
```

Expected:

- `production-ssl-status` does not warn merely because DNS returns Cloudflare IPs while Cloudflare Origin CA is active.
- `cloudflare-origin-ssl-status` reports Cloudflare proxy as likely active.
- `firewall-hardening-status` should label listener rows as local VM listeners.
- It should not imply cloud firewall is bypassed when `8000/9000` are locally bound.
- It should print external tests to run from the workstation: `curl -I https://erp.flowmaya.com`, `curl -I --connect-timeout 10 http://ORIGIN_IP:8000`, and `curl -I --connect-timeout 10 http://ORIGIN_IP:9000`.
- Redis ports `11000/13000` are reported as OK when local-only or closed.
- No command changes firewall rules automatically.


## VM firewall / Fail2Ban hardening

```bash
./install-erpnext-dev.sh vm-firewall-plan
./install-erpnext-dev.sh vm-firewall-status
./install-erpnext-dev.sh fail2ban-status
./install-erpnext-dev.sh security-hardening-wizard
```

Expected:

- `vm-firewall-plan` explains the safe UFW defaults.
- `vm-firewall-status` reports whether UFW is installed/active and whether expected port rules exist.
- `fail2ban-status` reports whether Fail2Ban and the `sshd` jail are active.
- `security-hardening-wizard` shows options for UFW and Fail2Ban and exits cleanly when choosing Back.

Manual destructive/configuration tests on a disposable VM:

```bash
./install-erpnext-dev.sh configure-vm-firewall
./install-erpnext-dev.sh configure-fail2ban
./install-erpnext-dev.sh vm-firewall-status
./install-erpnext-dev.sh fail2ban-status
```

Expected after configuration:

- UFW is active.
- Incoming default is deny.
- Outgoing default is allow.
- UFW allows `22/tcp`, `80/tcp`, and `443/tcp`.
- UFW has no explicit allow rules for `8000`, `9000`, `11000`, or `13000`.
- Fail2Ban service is running.
- The `sshd` jail is active.
- SSH remains open at the UFW layer by default; admin-IP SSH restriction is handled in cloud provider firewall unless the advanced `ufw-ssh-admin-only` command is intentionally used.

## Terminal UX checks

```bash
./install-erpnext-dev.sh help
printf '12\n' | ./install-erpnext-dev.sh menu
printf '8\n' | SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh security-hardening-wizard
```

Expected:

- `help` is categorized and compact.
- Main menu fits in a small terminal and includes production HTTPS/security entries.
- Security hardening wizard uses short menu labels.
- No repeated `.test` warning appears when `PRODUCTION_DOMAIN` is set.

## Action result summary checks

Run in a disposable VM or after a snapshot:

```bash
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh configure-vm-firewall
SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com ./install-erpnext-dev.sh configure-fail2ban
```

Expected:

- Each action ends with a compact `Result Summary` box.
- The bottom of the output shows the next command to run.
- The user does not need to scroll up to confirm whether the action succeeded.


## v1.0.0-rc2 backup verification hotfix checks

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh backup-status
./install-erpnext-dev.sh backup-verify
./install-erpnext-dev.sh production-checklist
./install-erpnext-dev.sh backup-hardening-wizard
```

Expected:

- `backup-status` shows the latest complete set when available.
- Public/private file backups are detected as `.tar` or `.tar.gz`.
- `backup-verify` reads database gzip, public tar archive, private tar archive, and site config JSON.
- `production-checklist` shows HTTPS OK when Cloudflare Origin CA / Nginx HTTPS is responding.

## v1.1.0 scheduled backup validation

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh backup-schedule-plan
./install-erpnext-dev.sh backup-schedule-status
./install-erpnext-dev.sh production-ops-wizard
./install-erpnext-dev.sh restore-preflight
./install-erpnext-dev.sh command-audit
./install-erpnext-dev.sh production-checklist
```

After enabling scheduled backups:

```bash
systemctl list-timers erpnext-dev-backup.timer --all
journalctl -u erpnext-dev-backup.service --no-pager -n 80
./install-erpnext-dev.sh backup-status
./install-erpnext-dev.sh backup-verify
```



## v1.1.2 backup retention validation

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh help | grep -E "backup-retention|cleanup-old-backups"
printf '12\n' | ./install-erpnext-dev.sh production-ops-wizard
./install-erpnext-dev.sh backup-retention-plan
./install-erpnext-dev.sh backup-retention-status
./install-erpnext-dev.sh cleanup-old-backups-dry-run
```

Expected:

- Production Operations menu includes retention options.
- Retention status shows complete backup set count, cleanup candidates, backup folder size, and disk usage.
- Dry run lists old complete backup sets without deleting files.
- `cleanup-old-backups` requires confirmation before deleting old complete sets.

## v1.1.3 Off-VM Backup Test Checklist

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh help | grep -E "off-vm|rsync"
./install-erpnext-dev.sh production-ops-wizard
./install-erpnext-dev.sh off-vm-backup-plan
./install-erpnext-dev.sh off-vm-backup-status
```

On a real VM with a configured backup server:

```bash
/root/install-erpnext-dev.sh configure-rsync-backup-target
/root/install-erpnext-dev.sh off-vm-backup-dry-run
/root/install-erpnext-dev.sh run-off-vm-backup
/root/install-erpnext-dev.sh off-vm-backup-status
/root/install-erpnext-dev.sh production-checklist
```

Expected: dry run completes first; real sync completes after confirmation; production checklist reports off-VM backup configured/last-run state.


## v1.1.5 Health Monitoring Validation

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh help | grep -E "health-check|service-recovery|production-ops"
printf '21\n' | ./install-erpnext-dev.sh production-ops-wizard
./install-erpnext-dev.sh health-check
./install-erpnext-dev.sh health-check-status
./install-erpnext-dev.sh service-recovery-plan
```

On a production VM, optionally enable and validate the timer:

```bash
/root/install-erpnext-dev.sh configure-health-check-timer
/root/install-erpnext-dev.sh health-check-status
systemctl list-timers erpnext-dev-health-check.timer --all
journalctl -u erpnext-dev-health-check.service --no-pager -n 80
```

Expected: health check returns a compact status table; timer status shows enabled/active after configuration; service recovery plan is guidance-only and does not restart services.


## Local SSL guide validation

After a local VM install, validate that follow-up commands use the reusable installer path:

```bash
/root/install-erpnext-dev.sh local-ssl-guide
/root/install-erpnext-dev.sh mkcert-guide
```

Expected:

```text
Reusable installer path inside the VM: /root/install-erpnext-dev.sh
HOST commands and VM commands are separated clearly
No `USER@VM_IP` placeholder is shown for the scp example
HOST wording is generic and does not mention a specific Linux distribution
```
---

## Interactive menu navigation validation

Validate that Back/Quit controls use letters instead of numbered menu items:

```bash
printf 'q\n' | ./install-erpnext-dev.sh menu
printf '12\nb\nq\n' | ./install-erpnext-dev.sh menu
printf '14\nb\nq\n' | ./install-erpnext-dev.sh menu
```

Expected:

```text
Main menu: q) Quit
Submenus: b) Back                        q) Quit
No numbered Back/Exit entries in menus
```

Also check the script source:

```bash
grep -nE 'echo "[0-9]+\) (Back|Exit|Quit)"' install-erpnext-dev.sh || true
bash -n install-erpnext-dev.sh
```

Expected: no numbered `Back`, `Exit`, or `Quit` menu entries are printed from active menu definitions.



## Roadmap documentation validation

Use this after roadmap-only documentation patches:

```bash
grep -n "production VM maturity" ROADMAP.md
grep -n "Docker-based ERPNext/Frappe installation" ROADMAP.md
grep -n "Near-term priority order" ROADMAP.md
grep -n "Definition of production-operations maturity" ROADMAP.md
```

Expected:

- Docker is listed as a later, separate track.
- VM management, monitoring, security, backup, restore, and update safety remain the near-term priority.
- The roadmap does not mix changelog history into future planning.

## v1.1.15 optional app catalog validation

Validate that Payments and Webshop are visible in the command surface before testing installs on a disposable VM:

```bash
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
./install-erpnext-dev.sh help | grep -E "install-payments|install-webshop|PAYMENTS_BRANCH|WEBSHOP_BRANCH"
./install-erpnext-dev.sh command-audit | grep "Optional apps"
```

Expected:

```text
SCRIPT_VERSION="1.1.15"
install-payments is listed in help
install-webshop is listed in help
PAYMENTS_BRANCH and WEBSHOP_BRANCH are documented
Optional apps command audit still passes
```

On a fresh local VM after ERPNext is installed, validate the app menu and status view:

```bash
sudo /root/install-erpnext-dev.sh app-status
sudo /root/install-erpnext-dev.sh app-compatibility
sudo /root/install-erpnext-dev.sh app-install-wizard
```

Expected:

```text
Frappe Payments appears in app-status and compatibility output
Frappe Webshop / E-Commerce appears in app-status and compatibility output
The App Install Wizard offers separate install options for Payments and Webshop
The App Library menu has no duplicate numbered status item
```

Recommended install test order on a disposable VM:

```bash
sudo /root/install-erpnext-dev.sh install-payments
sudo /root/install-erpnext-dev.sh app-status
sudo /root/install-erpnext-dev.sh doctor --plain
sudo /root/install-erpnext-dev.sh verify-access

sudo /root/install-erpnext-dev.sh install-webshop
sudo /root/install-erpnext-dev.sh app-status
sudo /root/install-erpnext-dev.sh doctor --plain
sudo /root/install-erpnext-dev.sh verify-access
```

Expected: each app creates a backup checkpoint prompt, downloads the app, registers it in `sites/apps.txt`, installs it on the active site, runs migrate/build/clear-cache, and leaves the ERPNext desk accessible.

