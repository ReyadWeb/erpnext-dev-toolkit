# Testing

## v1.1.39 local post-install follow-up polish

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -E "local-ssl-wizard|local-fixed-ip-guide|kvm-fixed-ip-guide"
./erpnext-dev.sh local-fixed-ip-guide | grep -E "KVM / libvirt Fixed IP Guide|Current VM IP|HOST machine"
printf 'n\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh local-dev-quickstart | grep -E "local-ssl-wizard|local-fixed-ip-guide|host-dns-guide"
```

Expected:

```text
ERPNext Developer Toolkit v1.1.39
```

Validation points:

- The local quickstart guidance shows the direct local HTTPS command `sudo erpnext-dev local-ssl-wizard`.
- The post-install follow-up summary shows both direct SSL wizard and broader SSL menu.
- `local-fixed-ip-guide`, `fixed-ip-guide`, `kvm-fixed-ip-guide`, and `kvm-guide` all route to the same fixed-IP guidance.
- README local install instructions list the recommended order: host DNS mapping, HTTP validation, local SSL wizard, then optional fixed-IP reservation.

## v1.1.37 README start-here cleanup

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
grep -n "## Start here" README.md
grep -n "Option A — fresh local VM install" README.md
grep -n "What the first command does" README.md
grep -n "local-domain-status" README.md
```

Expected:

```text
ERPNext Developer Toolkit v1.1.37
```

Validation points:

- The Start here section leads with copyable local, production, menu, preflight, update/repair, and optional-app commands.
- The `/tmp` bootstrap explanation appears after the main start commands, not before them.
- Local host DNS mapping uses toolkit-generated dynamic IP commands instead of a copied sample IP.
- Follow-up command examples use the stable `erpnext-dev` CLI.

## v1.1.36 menu navigation hardening

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -E "menu-self-test|local-domain-status|local-access-doctor"
./erpnext-dev.sh menu-self-test
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh menu
printf 'Q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh local-ssl-menu
printf 'b\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh production-ssl-menu
printf 'B\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh advanced
```

Expected:

```text
ERPNext Developer Toolkit v1.1.37
Menu navigation              OK
```

Validation points:

- `q` and `Q` exit cleanly from the main menu and all tested submenus.
- `b` and `B` return cleanly from submenus that support Back.
- Nested menu paths, such as main menu -> Local VM HTTPS / SSL -> `q`, do not drop numeric input back to the shell.
- The only remaining raw `read -r -p "Choose an option:"` call is inside `menu_read_choice`; all menu prompts use the shared handler.

## v1.1.35 dynamic local DNS and access checks

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -E "local-domain-status|local-access-doctor|host-dns-guide"
./erpnext-dev.sh local-domain-status
./erpnext-dev.sh local-access-doctor
./erpnext-dev.sh hosts-command
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh access
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh local-ssl-menu
```

Expected:

```text
ERPNext Developer Toolkit v1.1.37
```

Validation points:

- `get_vm_ip` detects the current VM IP dynamically; it must not print a hardcoded sample IP.
- `hosts-command` prints a host-side command with a backup of `/etc/hosts`, removal of old entries for the selected domain, and the current VM IP.
- `local-access-doctor` explains that `curl: (6) Could not resolve host: erp.test` means host DNS mapping is missing.
- The Access menu includes Local domain / host DNS status and Local access doctor.
- The Local VM HTTPS / SSL menu includes Local Domain / Host DNS Status, Local Access Doctor, and Print Host `/etc/hosts` Command.

Manual host validation after installing the patch inside a local VM:

```bash
sudo erpnext-dev host-dns-guide
```

Run the printed command on the host machine, then verify from the host:

```bash
getent hosts erp.test
curl -I http://erp.test:8000
```

## v1.1.34 environment-aware security and setup lifecycle checks

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -E "security-mode-status|local-firewall-profile|production-firewall-profile|repair-local-access|setup-lifecycle-plan"
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh security-hardening-wizard
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh public-vm-quickstart
./erpnext-dev.sh setup-lifecycle-plan
```

Expected:

```text
ERPNext Developer Toolkit v1.1.37
Security menu shows Local VM firewall profile, Production firewall profile, Repair local VM access, and rollback snapshots.
Public VM quickstart shows the lifecycle order: requirements, domain, install, backup, HTTPS, security, apps, final status.
```

Local VM recovery test after accidental hardening:

```bash
sudo erpnext-dev repair-local-access
sudo erpnext-dev vm-firewall-status
sudo erpnext-dev verify-access
```

Expected: UFW is active, `8000` and `9000` have local/private access rules, and the tool prints host-side curl tests for `erp.test`.

Production guard test on a local `.test` VM:

```bash
sudo erpnext-dev production-firewall-profile
```

Expected: the command refuses because no real production domain is configured.

# ERPNext Developer Toolkit Testing Guide

This file validates the current toolkit release. Version history belongs in `CHANGELOG.md`.

## v1.1.34 local domain workflow checks

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -E "local-dev-quickstart|change-local-domain"
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh local-ssl-menu | grep -E "Change Local Domain"
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh advanced | grep -E "47\) Change Local Domain"
```

Expected:

```text
SCRIPT_VERSION="1.1.35"
ERPNext Developer Toolkit v1.1.37
```

Manual VM validation after installing the patch:

```bash
sudo erpnext-dev domain-config
sudo erpnext-dev change-local-domain
sudo erpnext-dev domain-config
sudo erpnext-dev verify-access
```

Expected behavior:

- `local-dev-quickstart` asks for a local VM domain and Enter defaults to `erp.test`.
- `change-local-domain` shows the current site, asks for the new `.test` hostname, backs up and renames the Frappe site when a site exists, updates toolkit config, and prints the host `/etc/hosts` replacement commands.
- If local SSL was previously configured, the wizard disables the old local Nginx SSL site and tells the user to rebuild local SSL for the new hostname.


## v1.1.32 menu, SSL, and CLI validation

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
SCRIPT_VERSION="1.1.32"
ERPNext Developer Toolkit v1.1.37
```


## Menu UX validation

```bash
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh menu
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh advanced
printf 'q\n' | MENU_TERMINAL_COLS=80 ./erpnext-dev.sh local-ssl-menu
printf 'q\n' | MENU_TERMINAL_COLS=80 ./erpnext-dev.sh production-ssl-menu
printf 'q\n' | MENU_TERMINAL_COLS=80 ./erpnext-dev.sh local-ssl-wizard
printf 'q\n' | MENU_TERMINAL_COLS=80 ./erpnext-dev.sh advanced
printf 'q\n' | MENU_TERMINAL_COLS=60 ./erpnext-dev.sh advanced
```

Expected:

```text
Main menu shows Local VM HTTPS / SSL and Production HTTPS / SSL as separate first-level options.
Advanced menu renders in two columns on normal terminal widths and falls back cleanly on very narrow terminals.
Local SSL submenu shows wizard, status, guides, cert install/replace, verify, disable, and rollback options.
Production SSL submenu shows wizard, status, plan, guides, readiness checks, Let's Encrypt, Cloudflare Origin, SSL mode, and disable options.
Selecting Local SSL Wizard must not produce a command-not-found error.
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
unzip -l erpnext-dev-installer-v1.1.32.zip | grep "erpnext-dev.sh"
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


## README Start Here command order

Validate that the README opens with the three intended installation paths:

```bash
grep -n "General guided setup" README.md
grep -n "Local VM install" README.md
grep -n "Production VPS / cloud VM install" README.md
grep -n "sudo "\$tmp" start-here" README.md
grep -n "sudo "\$tmp" local-dev-quickstart" README.md
grep -n "sudo "\$tmp" public-vm-quickstart" README.md
```

The site-name guidance should appear after the corresponding command blocks, not before the first copy/paste command.
