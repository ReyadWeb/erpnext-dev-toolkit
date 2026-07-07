# ERPNext Developer Toolkit Testing Guide

This file validates the current toolkit release. Version history belongs in `CHANGELOG.md`.

## v1.1.30 toolkit rename and CLI validation

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
SCRIPT_VERSION="1.1.30"
ERPNext Developer Toolkit v1.1.30
```


## Root/non-root logging validation

Run this immediately after `install-cli` to verify that sudo/root commands and normal-user commands do not reuse the same log file:

```bash
sudo erpnext-dev install-cli
erpnext-dev version
erpnext-dev where-installed
```

Expected:

```text
No /tmp log permission error.
Root runs create unique logs under /var/log/erpnext-dev when writable.
Normal-user runs create unique logs under ~/.local/state/erpnext-dev/logs, or /tmp/erpnext-dev-<uid>-logs as a fallback.
The shared lock file uses /tmp/erpnext-dev-locks/toolkit.lock.
```

## Package file check

The release package should contain the canonical toolkit file `erpnext-dev.sh`.

```bash
unzip -l erpnext-dev-installer-v1.1.30.zip | grep "erpnext-dev.sh"
```

Expected:

```text
erpnext-dev.sh
```

## CLI install / repair validation

Run on a VM or disposable test machine:

```bash
tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)"
curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp"
chmod +x "$tmp"
sudo "$tmp" install-cli
erpnext-dev version
erpnext-dev --help
erpnext-dev where-installed
```

Expected installed paths:

```text
/opt/erpnext-dev/erpnext-dev.sh
/usr/local/bin/erpnext-dev
```

Repair/update checks:

```bash
sudo erpnext-dev repair-cli
sudo erpnext-dev update-toolkit
erpnext-dev where-installed
```

## Fresh VM preflight validation

Run inside a fresh Ubuntu/Debian-family VM:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" install-preflight
```

Expected:

```text
The VM passes preflight, or prints INSTALL BLOCKED with clear CPU/RAM/disk/tmp reasons.
The toolkit installs /opt/erpnext-dev/erpnext-dev.sh and /usr/local/bin/erpnext-dev after sudo execution.
```

## Fresh local VM install validation

Run inside a fresh local VM:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates && tmp="$(mktemp /tmp/erpnext-dev.XXXXXX.sh)" && curl -fsSL "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/erpnext-dev.sh?cache_bust=$(date +%s)" -o "$tmp" && chmod +x "$tmp" && sudo "$tmp" local-dev-quickstart
```

After install, validate with the short command:

```bash
erpnext-dev version
erpnext-dev where-installed
sudo erpnext-dev doctor --plain
sudo erpnext-dev verify-access
sudo erpnext-dev access-info
sudo erpnext-dev credentials-info
```

Expected:

```text
ERPNext/Frappe Desk is available at /app.
The root URL may be the website/portal landing page depending on installed apps.
Credentials are not printed by diagnostics or credentials-info.
```

## Credentials workflow validation

```bash
sudo erpnext-dev credentials-info
sudo erpnext-dev credentials-file-status
printf 'NO\n' | sudo erpnext-dev credentials-show || true
printf 'NO\n' | sudo erpnext-dev credentials-delete || true
sudo erpnext-dev --help | grep -E "credentials-show|credentials-file-status|credentials-secure|credentials-delete|reset-admin-password"
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
sudo erpnext-dev install-education
sudo erpnext-dev education-access-info
sudo erpnext-dev access-info
sudo erpnext-dev verify-access
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
sudo erpnext-dev app-status
sudo erpnext-dev install-payments
sudo erpnext-dev service-restart
sudo erpnext-dev wait-ready
sudo erpnext-dev migrate
sudo erpnext-dev build
sudo erpnext-dev clear-cache
sudo erpnext-dev app-status
sudo erpnext-dev doctor --plain
sudo erpnext-dev verify-access
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
grep -n "mktemp /tmp/erpnext-dev" README.md | head -20
grep -n "sudo erpnext-dev" README.md | head -30
grep -n "/opt/erpnext-dev/erpnext-dev.sh" README.md | head -20
```

Expected:

```text
Fresh VM commands use a unique /tmp/erpnext-dev.XXXXXX.sh bootstrap path.
Follow-up commands use sudo erpnext-dev.
```
