# ERPNext Developer Toolkit Testing Guide

This file validates the current toolkit release. Version history belongs in `CHANGELOG.md`.

## v1.1.28 toolkit rename and CLI validation

Local syntax/version validation:

```bash
chmod +x erpnext-dev.sh
bash -n erpnext-dev.sh
grep -n "SCRIPT_VERSION" erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -E "where-installed|install-cli|repair-cli|update-toolkit"
./erpnext-dev.sh where-installed
```

Expected:

```text
SCRIPT_VERSION="1.1.28"
ERPNext Developer Toolkit v1.1.28
```

## Package file check

The release package should contain the canonical toolkit file `erpnext-dev.sh`.

```bash
unzip -l erpnext-dev-installer-v1.1.28.zip | grep "erpnext-dev.sh"
```

Expected:

```text
erpnext-dev.sh
```

## CLI install / repair validation

Run on a VM or disposable test machine:

```bash
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/erpnext-dev.sh
chmod +x /tmp/erpnext-dev.sh
sudo /tmp/erpnext-dev.sh install-cli
erp-dev version
erp-dev --help
erp-dev where-installed
```

Expected installed paths:

```text
/opt/erpnext-dev/erpnext-dev.sh
/usr/local/bin/erp-dev
```

Repair/update checks:

```bash
sudo erp-dev repair-cli
sudo erp-dev update-toolkit
erp-dev where-installed
```

## Fresh VM preflight validation

Run inside a fresh Ubuntu/Debian-family VM:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/erpnext-dev.sh && chmod +x /tmp/erpnext-dev.sh && sudo /tmp/erpnext-dev.sh install-preflight
```

Expected:

```text
The VM passes preflight, or prints INSTALL BLOCKED with clear CPU/RAM/disk/tmp reasons.
The toolkit installs /opt/erpnext-dev/erpnext-dev.sh and /usr/local/bin/erp-dev after sudo execution.
```

## Fresh local VM install validation

Run inside a fresh local VM:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o /tmp/erpnext-dev.sh && chmod +x /tmp/erpnext-dev.sh && sudo /tmp/erpnext-dev.sh local-dev-quickstart
```

After install, validate with the short command:

```bash
erp-dev version
erp-dev where-installed
sudo erp-dev doctor --plain
sudo erp-dev verify-access
sudo erp-dev access-info
sudo erp-dev credentials-info
```

Expected:

```text
ERPNext/Frappe Desk is available at /app.
The root URL may be the website/portal landing page depending on installed apps.
Credentials are not printed by diagnostics or credentials-info.
```

## Credentials workflow validation

```bash
sudo erp-dev credentials-info
sudo erp-dev credentials-file-status
printf 'NO\n' | sudo erp-dev credentials-show || true
printf 'NO\n' | sudo erp-dev credentials-delete || true
sudo erp-dev --help | grep -E "credentials-show|credentials-file-status|credentials-secure|credentials-delete|reset-admin-password"
```

Expected:

```text
credentials-info does not print passwords.
credentials-show refuses unless SHOW is typed.
credentials-delete refuses unless DELETE is typed.
credentials-file-status reports owner/mode and recommends root:root 600.
```

## Education access validation

After installing Education:

```bash
sudo erp-dev install-education
sudo erp-dev education-access-info
sudo erp-dev access-info
sudo erp-dev verify-access
```

Expected:

```text
ERPNext/Frappe Desk: /app
Login page: /login
Education portal: /edu-portal/students
```

The website root may route to the Education portal. This is expected; users should use `/app` for Desk.

## Optional app service-readiness validation

Install optional apps one at a time and validate service readiness after each app:

```bash
sudo erp-dev app-status
sudo erp-dev install-payments
sudo erp-dev service-restart
sudo erp-dev wait-ready
sudo erp-dev migrate
sudo erp-dev build
sudo erp-dev clear-cache
sudo erp-dev app-status
sudo erp-dev doctor --plain
sudo erp-dev verify-access
```

Expected:

```text
Bench web listens on 8000.
Socket.io listens on 9000.
Redis queue listens on 11000.
Redis cache listens on 13000.
No ModuleNotFoundError for partially registered apps.
```

## App menu validation

```bash
printf 'q\n' | ./erpnext-dev.sh app-library
printf 'q\n' | MENU_TERMINAL_COLS=60 ./erpnext-dev.sh app-library
printf 'q\n' | MENU_TERMINAL_COLS=50 ./erpnext-dev.sh app-library
printf 'q\n' | MENU_FORCE_ONE_COLUMN=true ./erpnext-dev.sh app-library
```

Expected:

```text
App Library uses compact labels and fits small terminals.
Forced one-column mode works.
```

## README command validation

```bash
grep -n "/tmp/erpnext-dev.sh" README.md | head -20
grep -n "sudo erp-dev" README.md | head -30
grep -n "/opt/erpnext-dev/erpnext-dev.sh" README.md | head -20
```

Expected:

```text
Fresh VM commands use /tmp/erpnext-dev.sh.
Follow-up commands use sudo erp-dev.
```
