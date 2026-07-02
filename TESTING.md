# TESTING

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
