# Testing Guide v0.8.0

## Syntax and help

```bash
bash -n install-erpnext-dev.sh
./install-erpnext-dev.sh help
```

## Existing environment regression

```bash
./install-erpnext-dev.sh network-status
./install-erpnext-dev.sh app-status
./install-erpnext-dev.sh restart
./install-erpnext-dev.sh doctor
```

Expected:

- ERPNext service running.
- Ports 8000, 9000, 11000, 13000 listening.
- Optional apps show installed if previously installed.

## SSL status before configuration

```bash
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh local-ssl-guide
```

Expected before cert/key are installed:

- SSL certificate/key warnings.
- HTTPS port 443 may be not listening.
- Guide prints mkcert and certificate copy instructions.

## Local SSL setup test

On the host machine, generate a local certificate with mkcert:

```bash
mkcert -install
mkcert -cert-file erp.test.crt -key-file erp.test.key erp.test VM_IP localhost 127.0.0.1
scp erp.test.crt erp.test.key USER@VM_IP:/tmp/
```

Inside the VM:

```bash
sudo mkdir -p /etc/erpnext-dev-ssl
sudo cp /tmp/erp.test.crt /etc/erpnext-dev-ssl/erp.test.crt
sudo cp /tmp/erp.test.key /etc/erpnext-dev-ssl/erp.test.key
sudo chown root:root /etc/erpnext-dev-ssl/erp.test.crt /etc/erpnext-dev-ssl/erp.test.key
sudo chmod 644 /etc/erpnext-dev-ssl/erp.test.crt
sudo chmod 600 /etc/erpnext-dev-ssl/erp.test.key

./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh ssl-status
```

From the host:

```bash
curl -kI https://erp.test
```

Expected:

- Nginx config test passes.
- Nginx service starts/reloads.
- Port 443 listens.
- `https://erp.test` opens in browser.
- `http://erp.test:8000` still works.

## Disable SSL test

```bash
./install-erpnext-dev.sh disable-local-ssl
./install-erpnext-dev.sh ssl-status
```

Expected:

- Nginx site symlink removed.
- Direct Bench access remains available.
