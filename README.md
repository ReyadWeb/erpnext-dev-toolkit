# ERPNext Developer Installer v0.8.8

A local ERPNext/Frappe developer VM installer and environment manager for Ubuntu 24.04 / 26.04 LTS.

## Quick start

Run this inside the ERPNext VM:

```bash
curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh setup
```

During setup, choose a local site name:

```text
Local site name [erp.test]:
```

Press Enter for `erp.test`, or type a custom name such as `erp208.test`.

## v0.8.8 focus

v0.8.8 prepares the project for future production-domain and SSL work without turning the developer installer into a production installer yet.

New planning commands:

```bash
./install-erpnext-dev.sh domain-config
./install-erpnext-dev.sh production-readiness
./install-erpnext-dev.sh production-domain-guide
./install-erpnext-dev.sh production-ssl-guide
```

## Local vs production naming

Local developer site:

```text
erp208.test
```

Future production domain:

```text
erp.company.com
```

The installer keeps these concepts separate so local development remains safe while production planning can reuse the domain-first workflow later.

## Future production config fields

The non-secret config can now carry future production planning values:

```text
/etc/erpnext-dev-installer/config.env
```

Example fields:

```text
SITE_NAME=erp208.test
DEPLOYMENT_MODE=development
PRODUCTION_DOMAIN=erp.company.com
PRODUCTION_SSL_MODE=planned
```

Credentials remain private:

```text
/home/frappe/erpnext-dev-credentials.txt
```

## Local HTTPS

Quick self-signed test:

```bash
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh verify-local-ssl
```

Host tests:

```bash
curl -I http://erp208.test
curl -kI https://erp208.test
curl -I http://erp208.test:8000
```

## Production SSL planning

Production SSL should be a separate future track. Planned options:

- Let's Encrypt HTTP-01
- Let's Encrypt DNS-01 with Cloudflare
- Cloudflare Origin CA
- Manual/private datacenter certificate install

Run:

```bash
./install-erpnext-dev.sh production-ssl-guide
```
