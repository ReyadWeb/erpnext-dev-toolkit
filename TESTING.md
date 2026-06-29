# Testing Guide v0.8.18

## 1. Syntax check

```bash
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
```

Expected:

```text
SCRIPT_VERSION="0.8.18"
```

## 2. Existing VM validation

```bash
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh verify-access
./install-erpnext-dev.sh next-step
```

Expected:

- Runtime OK
- Service OK
- Autostart OK when enabled
- Bench web on 8000 OK
- Socket.io on 9000 OK
- Redis queue/cache ports OK

## 3. Local SSL wizard: self-signed path

Inside the VM:

```bash
./install-erpnext-dev.sh local-ssl-wizard
```

Choose:

```text
1) Quick self-signed certificate
```

Expected:

- Self-signed certificate is created.
- Nginx is installed if needed.
- Local SSL site is enabled.
- `verify-local-ssl` reports HTTPS OK.

Host tests:

```bash
curl -I http://erp.test
curl -kI https://erp.test
curl -I http://erp.test:8000
```

Expected:

- HTTP redirects to HTTPS.
- HTTPS returns 200 with `curl -kI`.
- Direct Bench port remains available.

## 4. Local SSL wizard: mkcert path

On the host:

```bash
sudo apt update
sudo apt install -y libnss3-tools mkcert
mkcert -install
mkcert -cert-file erp.test.crt -key-file erp.test.key erp.test VM_IP localhost 127.0.0.1
scp erp.test.crt erp.test.key USER@VM_IP:/tmp/
```

Inside the VM:

```bash
./install-erpnext-dev.sh local-ssl-wizard
```

Choose:

```text
2) Trusted mkcert certificate from HOST
```

Expected:

- Wizard detects files in `/tmp`.
- Cert/key are installed into `/etc/erpnext-dev-ssl`.
- Nginx reloads successfully.
- `curl -I https://erp.test` works from the host without `-k`.

## 5. Rollback test

```bash
./install-erpnext-dev.sh disable-local-ssl
./install-erpnext-dev.sh verify-ssl-rollback
```

Expected:

- Local SSL Nginx site is disabled.
- Direct Bench access on `:8000` remains available.

## 6. Log permissions check

```bash
ls -l /tmp/erpnext-dev-installer-*.log | tail -1
```

Expected:

```text
-rw-------
```
