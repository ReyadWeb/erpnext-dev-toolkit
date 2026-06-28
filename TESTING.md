# Testing Guide v0.8.3

## Syntax and help

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh help
```

## Core health

```bash
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh list-apps
```

Expected optional apps when fully installed:

```text
crm
hrms
telephony
helpdesk
insights
```

## SSL status

```bash
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh verify-local-ssl
```

Expected when local SSL is enabled:

```text
Nginx service                OK
Nginx SSL config             OK
Nginx SSL enabled            OK
SSL certificate              OK
SSL private key              OK
HTTPS reverse proxy          OK
Bench web                    OK
Socket.io                    OK
```

## Self-signed SSL test

```bash
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh ssl-status
```

Host tests:

```bash
curl -I http://erp.test
curl -kI https://erp.test
curl -I http://erp.test:8000
```

Expected:

```text
http://erp.test        -> 301 redirect
https://erp.test       -> 200 OK with curl -k
http://erp.test:8000   -> 200 OK direct Bench fallback
```

## Trusted certificate replacement test

Copy trusted cert/key into the VM as `/tmp/erp.test.crt` and `/tmp/erp.test.key`, then run:

```bash
./install-erpnext-dev.sh install-local-ssl-cert
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh verify-local-ssl
```

Host trusted test:

```bash
curl -I https://erp.test
```

Expected for a trusted mkcert cert: `200 OK` without `-k`.

## Browser trust guide

```bash
./install-erpnext-dev.sh browser-trust-guide
```

Use this when HTTPS works with `curl -k` but the browser still shows a certificate warning.

## Rollback test

```bash
./install-erpnext-dev.sh disable-local-ssl
./install-erpnext-dev.sh verify-ssl-rollback
./install-erpnext-dev.sh runtime-status
```

Expected:

- Managed Nginx site disabled.
- Certificate files kept for reuse.
- Direct Bench fallback remains available on `:8000`.

Re-enable:

```bash
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh verify-local-ssl
```
