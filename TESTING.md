# Testing Guide v0.8.2

## Syntax test

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh help
```

## Existing environment health

Inside the VM:

```bash
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh list-apps
```

Expected:

- ERPNext service running.
- Ports 8000, 9000, 11000, 13000 listening.
- Optional apps show OK if installed.
- App registry shows no downloaded-but-not-installed apps unless intentionally testing a partial install.

## SSL status and guides

Inside the VM:

```bash
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh local-ssl-guide
./install-erpnext-dev.sh mkcert-guide
./install-erpnext-dev.sh verify-local-ssl
./install-erpnext-dev.sh ssl-rollback-guide
```

Expected:

- Commands display guidance/status without breaking ERPNext.
- `ssl-status` shows cert/key/config/port status.
- `mkcert-guide` shows host-side trust workflow.
- `ssl-rollback-guide` shows safe rollback steps.

## Self-signed SSL quick test

Inside the VM:

```bash
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh ssl-status
```

From the host:

```bash
curl -I http://erp.test
curl -kI https://erp.test
curl -I http://erp.test:8000
```

Expected:

```text
http://erp.test        -> 301 redirect to https://erp.test/
https://erp.test       -> 200 OK through Nginx HTTPS reverse proxy
http://erp.test:8000   -> 200 OK direct Bench fallback
```

## Trusted mkcert test

Run `./install-erpnext-dev.sh mkcert-guide` and follow the host-to-VM instructions.

After installing mkcert-generated cert/key in the VM and re-running `configure-local-ssl`, test from the host:

```bash
curl -I https://erp.test
```

Expected:

- 200 OK without `-k`.
- Browser should not show a certificate warning if mkcert CA is trusted on the host/browser profile.

## Rollback test

Inside the VM:

```bash
./install-erpnext-dev.sh disable-local-ssl
./install-erpnext-dev.sh ssl-status
```

From the host:

```bash
curl -I http://erp.test:8000
```

Expected:

- Direct Bench access still works.
- HTTPS site is disabled or no longer responds through the local SSL Nginx site.
