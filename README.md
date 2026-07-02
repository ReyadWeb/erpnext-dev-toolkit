# ERPNext Developer Installer v0.9.8

Local developer installer for ERPNext/Frappe on Ubuntu 24.04/26.04 VMs.

## Main workflow

```bash
curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh setup
```

## Important commands

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh verify-access
./install-erpnext-dev.sh local-ssl-wizard
./install-erpnext-dev.sh app-install-wizard
./install-erpnext-dev.sh app-compatibility
./install-erpnext-dev.sh production-readiness
./install-erpnext-dev.sh production-plan
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh doctor --plain
./install-erpnext-dev.sh doctor --json
./install-erpnext-dev.sh support-bundle
./install-erpnext-dev.sh next-step
```

## v0.9.8 focus

v0.9.8 adds Cloudflare-aware SSL status and post-HTTPS firewall hardening checks. When Cloudflare Origin CA is active and DNS returns Cloudflare IPs instead of the origin VM IP, `production-ssl-status` now treats that as expected instead of warning. A new `firewall-hardening-status` command reviews backend listener exposure after HTTPS is working and clearly marks `8000/9000` as safe to close or restrict.

v0.9.7 fixed and improved the Cloudflare Origin CA paste workflow. The installer now stops reading the certificate automatically at `-----END CERTIFICATE-----` and stops reading the private key automatically at `-----END PRIVATE KEY-----`, `-----END RSA PRIVATE KEY-----`, or `-----END EC PRIVATE KEY-----`. Artificial `END_CERT` and `END_KEY` markers are no longer required.

v0.9.6 added the guided production SSL provider workflow. The installer can help choose between direct Let's Encrypt HTTPS and Cloudflare Origin CA for Cloudflare Full (strict).

The Cloudflare Origin CA path can prompt for the Origin Certificate and Private Key, validate that they match, install them safely under `/etc/ssl/cloudflare-origin`, back up the existing managed Nginx production config, and switch Nginx to the Cloudflare origin certificate.

v0.9.5 remains included as the Let's Encrypt staging-to-production hotfix. It detects installed Let's Encrypt staging certificates and forces replacement with a real production certificate when `LETSENCRYPT_STAGING` is not enabled.

It still does **not** change DNS or firewall rules automatically. Keep Hetzner firewall changes manual: allow `80/443`, then restrict/close public `8000/9000` only after HTTPS is verified.

Run:

```bash
./install-erpnext-dev.sh production-readiness
./install-erpnext-dev.sh production-plan
./install-erpnext-dev.sh production-domain-plan
./install-erpnext-dev.sh public-vm-readiness
./install-erpnext-dev.sh production-ssl-plan
./install-erpnext-dev.sh production-firewall-plan
./install-erpnext-dev.sh firewall-hardening-status
./install-erpnext-dev.sh production-ssl-wizard
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

`production-firewall-plan` prints the intended Hetzner/edge firewall posture: SSH restricted, `80/443` public, `8000` temporary/restricted, and Redis/socket/internal ports closed publicly.

`firewall-hardening-status` checks the current local listener exposure after HTTPS is working. It warns if `8000` or `9000` are still listening on public interfaces and confirms Redis ports are local-only or closed. It does not change firewall rules automatically.

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

After `https://erp.flowmaya.com` works, restrict or close public access to `8000` and `9000` at the Hetzner firewall.

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
