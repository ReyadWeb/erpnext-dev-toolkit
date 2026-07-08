# Testing

## v1.1.48 Restore and local HTTPS polish regression test

After updating the VM to v1.1.48, run:

```bash
erpnext-dev version
sudo erpnext-dev restore-full
```

Expected restore UX:

- Version prints `ERPNext Developer Toolkit v1.1.48`.
- Restore still prints the database admin credential reminder.
- Restore still asks for `Enter database admin user [frappe_db_admin]:` and `Database admin password:`.
- Post-restore maintenance no longer floods the terminal with the full migrate/build output.
- Each quiet maintenance step prints an `Output log:` path.
- Restore finishes with `OK: Post-restore maintenance completed` and `OK: Full restore completed`.

Then run:

```bash
sudo erpnext-dev verify-access
sudo erpnext-dev verify-local-ssl
sudo erpnext-dev local-firewall-profile
```

Expected local HTTPS/security UX:

- `verify-local-ssl` passes.
- If the Local VM firewall profile is already active, `verify-local-ssl` says `Local VM security profile: already active`.
- `local-firewall-profile` host-side tests include `curl -kI https://<site>` when local HTTPS is configured.
- After any service restart/wait-ready flow, the ERPNext Ready screen shows HTTPS Desk/Login/Website URLs first when HTTPS is configured.

## v1.1.47 Restore credential and post-restore maintenance regression test

Before running a destructive restore, make sure the database admin credential is available:

```bash
sudo erpnext-dev credentials-info
sudo erpnext-dev credentials-show
```

Then run a restore rehearsal on a disposable/local VM:

```bash
sudo erpnext-dev list-backups
sudo erpnext-dev restore-full
```

Expected restore UX:

- Restore prints a database credential reminder before destructive action.
- Prompt says `Enter database admin user [frappe_db_admin]:`.
- Prompt says `Database admin password:`.
- Prompt does not say `Enter mysql super user [root]` from the toolkit flow.
- Prompt does not say `MySQL root password` from the toolkit flow.
- Emergency backup is created before restore.
- ERPNext service is started/waited for before post-restore migrate/cache cleanup.
- `bench migrate`, `bench build`, and `bench clear-cache` run after services are ready.

Post-restore verification:

```bash
sudo erpnext-dev verify-access
sudo erpnext-dev verify-local-ssl
sudo erpnext-dev local-access-doctor
sudo erpnext-dev app-status
```

Expected:

- Access verification passes.
- Local HTTPS verification passes.
- App status still shows installed apps and no downloaded/registered mismatch.

## v1.1.46 README version hygiene regression test

After updating the VM to v1.1.46, run:

```bash
erpnext-dev version
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.46`.
- `README.md` title is `# ERPNext Developer Toolkit` without a stale hard-coded release number.
- The README tells users to run `erpnext-dev version` for the installed toolkit version.

## v1.1.45 App status comparison regression test

After updating the VM to v1.1.45, run:

```bash
erpnext-dev version
sudo erpnext-dev app-status
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.45`.
- `Installed on site` shows frappe, erpnext, and installed optional apps.
- `Downloaded app folders` shows the app folders.
- `Downloaded but not installed on <site>` prints `none` when all downloaded apps are installed.
- `Downloaded but not registered in sites/apps.txt` prints `none` when all downloaded apps are registered.
- No `/tmp/erpnext-dev-frappe-run... syntax error` appears.

Also test:

```bash
sudo erpnext-dev app-install-wizard
```

Expected:

- The preflight heading remains `Install / branch snapshot`.
- Installed apps show `OK`; moving branch notes are repeatability warnings only.

## v1.1.44 App status compare regression test

After installing several optional apps, run:

```bash
sudo erpnext-dev app-status
```

Expected:

- `Installed on site` shows frappe, erpnext, and installed optional apps.
- `Downloaded app folders` shows the app folders.
- `Downloaded but not installed on <site>` prints either a list or `none`; it must not show a temp-script syntax error.
- `Downloaded but not registered in sites/apps.txt` prints either a list or `none`; it must not show a temp-script syntax error.
- The curated optional app status marks installed apps as `OK`.

Then open the app wizard:

```bash
sudo erpnext-dev app-install-wizard
```

Expected:

- The preflight heading says `Install / branch snapshot`.
- Installed apps show `OK` even if their branch is `main`, `develop`, or default.
- The detail text may still include a branch note, but it is clearly presented as a repeatability warning, not an app failure.


## v1.1.40 local host mapping checkpoint

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -E "local-host-checkpoint|host-dns-checkpoint|host-mapping-checkpoint"
./erpnext-dev.sh local-host-checkpoint | grep -E "Required Local Host Mapping Checkpoint|HOST machine|safe to repeat|local-ssl-wizard"
printf 'n\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh local-dev-quickstart | grep -E "local-host-checkpoint|host-dns-guide|local-ssl-wizard"
```

Expected:

```text
ERPNext Developer Toolkit v1.1.40
```

Validation points:

- `local-host-checkpoint`, `host-dns-checkpoint`, and `host-mapping-checkpoint` all print the same required host DNS mapping checkpoint.
- The checkpoint uses the dynamically detected VM IP and never hardcodes a sample `192.168.122.x` value.
- The printed host command backs up `/etc/hosts`, removes only the selected local domain entry, and appends the current mapping.
- The checkpoint explicitly says to run the command on the host machine, not inside the VM.
- The local install summary shows the host mapping checkpoint before the local SSL wizard.
- The workflow tells users to rerun the checkpoint after deleting/recreating a VM or when DHCP assigns a new IP.

Manual host validation after local install:

```bash
sudo erpnext-dev local-host-checkpoint
```

Run the printed command on the host machine, then verify from the host:

```bash
getent hosts erp.test
curl -I http://erp.test:8000
```

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
## v1.1.41 Local SSL Wizard mkcert regression test

Run inside a local ERPNext VM after the local HTTP install passes:

```bash
sudo erpnext-dev local-ssl-wizard
```

Checklist:

- Select `2) Trusted mkcert setup`.
- Confirm a guided mkcert setup screen appears.
- Confirm it prints HOST vs VM responsibilities.
- Confirm it prints the HOST-side `mkcert -install`, `mkcert -cert-file ...`, and `scp ...:/tmp/` commands.
- Confirm the wizard pauses long enough to read the output before returning to the menu.
- If `/tmp/<site>.crt` and `/tmp/<site>.key` are missing, it should say they are not found yet and explain the next host action.
- If the files are present, it should offer to install the copied certificate and enable local HTTPS.

Direct command smoke test:

```bash
sudo erpnext-dev trusted-mkcert-setup
sudo erpnext-dev mkcert-setup
```


## v1.1.42 Local SSL navigation and next-step test

Run inside a local ERPNext VM after HTTP access is confirmed.

Standalone wizard navigation:

```bash
printf 'b\nq\n' | sudo erpnext-dev local-ssl-wizard
```

Expected: `b` opens the main menu, then `q` exits cleanly. It should not drop silently back to the shell before the user sees the main menu.

Nested SSL menu navigation:

```bash
printf '1\nb\nb\nq\n' | sudo erpnext-dev menu
```

Expected: main menu -> Local VM HTTPS / SSL -> Local SSL Wizard -> `b` returns to SSL menu -> `b` returns to main menu -> `q` exits.

After a successful trusted mkcert or self-signed HTTPS verification:

```bash
sudo erpnext-dev verify-local-ssl
```

Expected: if HTTPS is healthy, the output recommends:

```text
sudo erpnext-dev verify-access
sudo erpnext-dev local-access-doctor
sudo erpnext-dev security-hardening-wizard
Choose: 2) Local VM firewall profile
sudo erpnext-dev app-install-wizard
```

The Local SSL Wizard should also include:

```text
9) Local security profile
```

The Local VM HTTPS / SSL menu should include:

```text
17) Local Security Profile
```


## v1.1.43 App status regression test

After installing CRM or another optional app, run:

```bash
sudo erpnext-dev app-status
```

Expected:

- The output shows an `Installed on site` section containing frappe, erpnext, and the installed optional app.
- The output shows downloaded app folders.
- The curated optional app status section marks the installed app as `OK`.
- The App Installation Wizard option 1 is labeled `Installed apps / status`.

Also verify from the menu:

```bash
sudo erpnext-dev app-install-wizard
# choose 1
```
