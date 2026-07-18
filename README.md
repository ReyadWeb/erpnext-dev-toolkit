# ERPNext Developer Toolkit

![ERPNext Developer Toolkit](docs/assets/erpnext_dev_toolkit_banner.png)

A guided installation and operations toolkit for **ERPNext / Frappe** on a fresh
**Ubuntu 24.04 / 26.04 LTS or Debian 13** host (native or Docker). One command installs the full stack; a single
`erpnext-dev` command then handles day-to-day operations: HTTPS, firewall
hardening, scheduled and off-VM backups, restore rehearsals, health checks,
optional apps, guarded upgrades, diagnostics, and redacted support bundles.

It supports two setup paths:

- **Local development VM** — a local test hostname such as `erp.test`.
- **Public VPS / cloud VM** — a real domain or subdomain such as `erp.example.com`.

> Version history lives in [`CHANGELOG.md`](CHANGELOG.md). Security posture and
> release-signing details live in [`SECURITY.md`](SECURITY.md). Planned work and
> the **v1.18–v1.23** plan (security → local IP → healing → panel readiness) are in [`ROADMAP.md`](ROADMAP.md). This README focuses on
> installation, operations, and usage.

**Current release:** v1.18.0 · **Readiness:** ~9.5/10 for single-admin local/public VM
(after VPS production validation). v1.10.0 turns the toolkit into a **multi-engine**
platform: choose a **native** VM install (default, unchanged) or a **Docker**
engine that wraps the official `frappe_docker`, behind the same `erpnext-dev` CLI.

> **OS support:** The native engine supports Ubuntu 24.04 / 26.04 LTS and Debian 13
> (trixie). The Docker engine runs on any Docker-capable host and formally tracks
> Ubuntu 24.04 / 26.04 and Debian 11 / 12 / 13. Automated integration coverage
> runs on **Ubuntu 24.04 (release-gating)** plus **Ubuntu 26.04 (GitHub public-preview
> runner, non-blocking)**; the 26.04 leg becomes a hard gate once that runner image
> reaches general availability. Debian 13 uses the same Debian-family apt/systemd
> install path (GitHub provides no Debian runner, so it is field-validated rather
> than gated in CI).

![From fresh host to validated go-live](docs/assets/toolkit_lifecycle_flow_diagram.png)

---

## Deployment engines

The toolkit is a multi-engine platform: the same `erpnext-dev` command drives two
first-class deployment engines. During `install` / `local-dev-quickstart` you pick
one; the choice is saved and every lifecycle command (`start`, `stop`, `status`,
`logs`, `backup`, app installs, `doctor`) routes to it automatically.

| Engine | What it does | Best for |
| --- | --- | --- |
| **Native** (default) | Installs ERPNext/Frappe directly on the VM (systemd, bench, host MariaDB/Redis/Nginx). Ubuntu 24.04/26.04, Debian 13. | Maximum host-level control and simplicity. |
| **Docker** | Containerized stack wrapping the official `frappe_docker` (`pwd.yml`), published on a local port. Ubuntu 24.04/26.04, Debian 11/12/13. | Isolation, portability, upstream production alignment. |

```bash
sudo erpnext-dev set-engine       # choose native or docker for a fresh setup
sudo erpnext-dev engine-status    # show the active engine and its settings
```

The Docker engine has two modes:

- **Development** (default) — disposable upstream `pwd.yml` stack for local
  testing (install / start / stop / status / logs / health / backup / apps).
- **Production** (`sudo erpnext-dev docker-production-setup`, or
  `DOCKER_MODE=production`) — wraps upstream `compose.yaml` with MariaDB/Redis
  overrides, an immutable image pin, and Traefik HTTPS (Let's Encrypt or
  Cloudflare Origin CA). The Docker Engine installs from Docker's official
  signed apt repository; the exact `frappe_docker` commit SHA + ERPNext image
  digest are recorded under `/opt/erpnext-dev/docker/erpnext-dev.pins`.

Native remains the longest-validated path. Docker **production** compose and
HTTPS are shipped and release-gated in CI; native **Debian 13** uses the same
Debian-family install path and is **field-validated** (GitHub has no Debian
runner). Ubuntu **26.04** runs in integration CI as a non-blocking preview leg
until the runner is generally available.

The guided Docker install finishes with the same post-install flow as native:
verify access, host-mapping checkpoint, optional apps / first backup, then the
main menu. Access output shows three URLs — a **Local URL**
(`http://localhost:PORT`), a **Network URL** (`http://VM_IP:PORT`), and a
**Friendly URL** (`http://SITE:PORT` after host mapping). If the published port
is already in use, the toolkit prompts for a free one (or auto-picks under
`-y`), persists it, and reuses it for `status` / `logs` / `verify-access`.

---

## Menu

- [Start here](#start-here) — the important command for each case
- [Deployment engines](#deployment-engines)
- [Project status and roadmap](#project-status-and-roadmap)
- [Install and verify](#install-and-verify)
- [Requirements and preflight](#requirements-and-preflight)
- [Local development VM](#local-development-vm)
- [Public VPS / cloud VM](#public-vps--cloud-vm)
- [The `erpnext-dev` command](#the-erpnext-dev-command)
- [Credentials](#credentials)
- [Backups and restore safety](#backups-and-restore-safety)
- [Off-VM backup server](#off-vm-backup-server)
- [Restore rehearsal](#restore-rehearsal)
- [Production operations dashboard](#production-operations-dashboard)
- [Health monitoring](#health-monitoring)
- [Go-live validation](#go-live-validation)
- [Optional Frappe apps](#optional-frappe-apps)
- [HTTPS / SSL](#https--ssl)
- [Security hardening](#security-hardening)
- [Guarded upgrades](#guarded-upgrades)
- [Toolkit integrity and updates](#toolkit-integrity-and-updates)
- [Diagnostics and support](#diagnostics-and-support)
- [Architecture diagrams](#architecture-diagrams)
- [Documentation files](#documentation-files)
- [Production caution](#production-caution)

---

## Start here

**Fresh local dev VM — download, verify, and install in one command:**

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates tar && \
REPO="ReyadWeb/erpnext-dev-toolkit" && \
VERSION="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
  "https://github.com/${REPO}/releases/latest" \
  | sed -n 's|.*/tag/\([^/]*\)$|\1|p')" && \
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Could not resolve latest release" >&2; exit 1; } && \
BASE="https://github.com/${REPO}/releases/download/${VERSION}" && \
cd ~ && \
curl -fsSLO "${BASE}/erpnext-dev-${VERSION}.tar.gz" && \
tar -xzf "erpnext-dev-${VERSION}.tar.gz" && \
cd "erpnext-dev-${VERSION}" && \
sha256sum -c SHA256SUMS && \
sudo ./erpnext-dev.sh local-dev-quickstart
```

Press **Enter** at the domain prompt to keep the default `erp.test`. Choose **Linux**
for host OS when asked (or your actual host OS). After install, run the printed
**host mapping** and **mkcert/scp** commands on your physical host machine — each
is a single copy-paste line.

**Debian tip:** if `sudo` is missing or your user is not in the `sudo` group, see
[Debian 13 notes](#debian-13-notes-native) first (bootstrap as root, then re-run
the block above as your normal user).

Or install step by step ([details below](#install-and-verify)):

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates tar
REPO="ReyadWeb/erpnext-dev-toolkit"
VERSION="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
  "https://github.com/${REPO}/releases/latest" \
  | sed -n 's|.*/tag/\([^/]*\)$|\1|p')"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Could not resolve latest release" >&2; exit 1; }
BASE="https://github.com/${REPO}/releases/download/${VERSION}"
curl -fsSLO "${BASE}/erpnext-dev-${VERSION}.tar.gz"
tar -xzf "erpnext-dev-${VERSION}.tar.gz"
cd "erpnext-dev-${VERSION}"
sha256sum -c SHA256SUMS
```

Pin a **specific published** release (only after its Assets exist):

```bash
VERSION="v1.18.0"
REPO="ReyadWeb/erpnext-dev-toolkit"
BASE="https://github.com/${REPO}/releases/download/${VERSION}"
curl -fsSLO "${BASE}/erpnext-dev-${VERSION}.tar.gz"
```

> **Use the release Assets, not “Source code”.** Install from
> `erpnext-dev-vX.Y.Z.tar.gz` on the GitHub Release (plus `SHA256SUMS` /
> `SHA256SUMS.asc`). The automatic “Source code (zip/tar.gz)” archives are not
> the supported install path.
>
> **Why the install block resolves `/releases/latest`:** during a release, `main`
> may advertise a new `SCRIPT_VERSION` before the signed bundle is uploaded.
> Resolving `/releases/latest` always downloads the last **published** release
> (GitHub only marks latest after Assets exist), so the copy-paste path does not
> 404 mid-pipeline. The banner **Current release** may briefly lead the install
> path until publish finishes.
>
> **Retrying after a failed download?** If an earlier attempt returned 404, left a
> partial tarball, or you switched versions (for example from `v1.9.5` to `v1.10.0`),
> remove leftovers from your home directory first so you do not mix old and new
> files, then re-run the block above:
>
> ```bash
> cd ~
> rm -rf erpnext-dev-v1.9.5 erpnext-dev-v1.10.0 erpnext-dev-v1.18.0
> rm -f erpnext-dev-v*.tar.gz SHA256SUMS SHA256SUMS.asc
> ```
>
> That only cleans the download folder — it does **not** uninstall an already
> installed ERPNext site. Use toolkit uninstall commands for that.

Then run the command for your case:

| I want to… | Command | Notes |
|---|---|---|
| Let the toolkit ask local vs. production | `sudo ./erpnext-dev.sh start-here` | Guided chooser |
| Check the VM is safe before installing | `sudo ./erpnext-dev.sh install-preflight` | Read-only |
| Install a **local dev** VM | `sudo ./erpnext-dev.sh local-dev-quickstart` | Defaults to `erp.test` |
| Install a **production** VM | `sudo ./erpnext-dev.sh public-vm-guided-setup` | Needs a real domain |
| Install / repair the `erpnext-dev` command | `sudo ./erpnext-dev.sh install-cli` | Then use `sudo erpnext-dev …` |

After install, everything else uses the stable `erpnext-dev` command:

| Task | Command |
|---|---|
| Operations health dashboard | `sudo erpnext-dev dashboard` |
| Daily operations menus | `sudo erpnext-dev production-ops-wizard` |
| Install optional Frappe apps | `sudo erpnext-dev app-install-wizard` |
| Create / verify a backup | `sudo erpnext-dev backup-files && sudo erpnext-dev backup-verify` |
| Set up an off-VM backup server | `sudo erpnext-dev backup-server-setup` (on the backup server) |
| Rehearse a restore on a disposable VM | `sudo erpnext-dev restore-rehearsal-wizard` |
| Upgrade ERPNext safely | `sudo erpnext-dev safe-update-wizard` |
| Show login credentials | `sudo erpnext-dev credentials-show` |
| Health / diagnostics | `sudo erpnext-dev doctor --plain` |
| Full command list | `erpnext-dev --help` |

> Run interactive menu commands (for example `production-ops-wizard`) on their
> own — don't chain other commands after them in the same line.

---

## Project status and roadmap

| Area | Rating | Notes |
|------|--------|--------|
| Local dev VM | 9.5 | Guided install, HTTPS, apps, backups — field-tested |
| Public VPS production | 9.5 | Production runtime, gated releases — **validate on your VPS** |
| Supply chain | 9.6 | Signed + gated CI; signing key gated by `release-signing` environment (v1.9.0); Actions pinned to commit SHAs + Dependabot (v1.9.1) |
| Path to 9.8+ | — | v1.10.0 object-storage backups → v1.11.0 community polish |

See [`ROADMAP.md`](ROADMAP.md) for the full plan and timeline. VPS production checklist:
[`TESTING.md` — VPS production validation](TESTING.md#vps-production-validation-v190).

---

## Install and verify

The toolkit is modular: `erpnext-dev.sh` sources `lib/*.sh` at runtime, so each
release ships as a **single self-contained bundle**, `erpnext-dev-<version>.tar.gz`,
containing the complete tree.

- `sha256sum -c SHA256SUMS` (run from the extracted directory) verifies **every**
  packaged file against the release checksum list.
- For production, also verify the maintainer **signature** before running as root.
  The signed bundle already includes `SHA256SUMS.asc`:

```bash
# Via the toolkit (bundled key + pinned fingerprint, throwaway keyring):
sudo ./erpnext-dev.sh verify-signature
# or manually, after importing the maintainer key:
gpg --verify SHA256SUMS.asc SHA256SUMS && sha256sum -c SHA256SUMS
```

The maintainer key ships at [`docs/erpnext-dev-signing-key.asc`](docs/erpnext-dev-signing-key.asc);
the pinned fingerprint is in [`SECURITY.md`](SECURITY.md).

---

## Requirements and preflight

The toolkit runs a **blocking preflight** so unsafe environments never reach
package installation, bench creation, or database changes.

```bash
sudo erpnext-dev install-preflight
```

| Check | Behavior |
|---|---|
| Unsupported OS (not Ubuntu 24.04 / 26.04 or Debian 13) | blocks |
| No sudo/root permission | blocks |
| No internet / GitHub access | blocks |
| CPU below 2 cores | blocks |
| RAM below 4096 MB | blocks |
| Root free disk below 30 GB | blocks |
| `/tmp` free space below 4 GB | blocks |
| RAM 4096–8191 MB, CPU 2–3 cores, or disk 30–59 GB | warning |

Recommended: 4 vCPU, 8 GB RAM, 60–80 GB SSD. If a VM is unsafe, the toolkit
prints a red `INSTALL BLOCKED` summary explaining what to fix. An expert-only
override (`ERPNEXT_ALLOW_UNSAFE_INSTALL=true`) exists for disposable test VMs and
should not be used otherwise.

### Debian 13 notes (native)

Debian 13 (trixie) uses the same Debian-family apt/systemd install path as Ubuntu
after you have `sudo`. A **fresh Debian install often does not ship `sudo`**, and
the first user is usually **not** in the `sudo` group (unlike typical Ubuntu
cloud images).

**1) Bootstrap `sudo` (as root)** — log in as `root`, or run `su -`:

```bash
apt-get update
apt-get install -y sudo curl ca-certificates tar
# Replace YOUR_USER with the login you will use day-to-day (not root):
usermod -aG sudo YOUR_USER
```

Log out and back in as `YOUR_USER` so group membership applies (`groups` should
list `sudo`).

**2) Fresh local install (as YOUR_USER)** — same as [Start here](#start-here):

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates tar && \
REPO="ReyadWeb/erpnext-dev-toolkit" && \
VERSION="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
  "https://github.com/${REPO}/releases/latest" \
  | sed -n 's|.*/tag/\([^/]*\)$|\1|p')" && \
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Could not resolve latest release" >&2; exit 1; } && \
BASE="https://github.com/${REPO}/releases/download/${VERSION}" && \
cd ~ && \
curl -fsSLO "${BASE}/erpnext-dev-${VERSION}.tar.gz" && \
tar -xzf "erpnext-dev-${VERSION}.tar.gz" && \
cd "erpnext-dev-${VERSION}" && \
sha256sum -c SHA256SUMS && \
sudo ./erpnext-dev.sh local-dev-quickstart
```

Other Debian notes:

- **Package names (v1.15.2+):** the native installer no longer requires Ubuntu-only
  `software-properties-common` (removed from Debian 13) and prefers
  `libfontconfig1` for fontconfig.
- **Local HTTPS / mkcert (on the HOST browser machine):** `apt install -y mkcert libnss3-tools` before `mkcert -install`. Firefox may still need `browser-trust-guide`.
- **Field validation:** use [`VALIDATION.md`](VALIDATION.md) for go-live checks on a real Debian VPS.
- **Docker on Debian:** the toolkit prefers Docker’s official apt repository; OS differences are largely abstracted once the daemon is up.

---

## Local development VM

Install with the local quickstart (press **Enter** to accept the default site
`erp.test`):

```bash
sudo ./erpnext-dev.sh local-dev-quickstart
```

Run interactively, `local-dev-quickstart` guides you end to end: it installs
ERPNext, then walks through the optional follow-ups — **trusted local HTTPS**,
the **local security profile / firewall**, and the **optional app installer** —
before opening the main menu. Each optional step is opt-in (press Enter to skip)
and can be run later from the commands below. (The non-interactive
`sudo ./erpnext-dev.sh -y install` only installs; use it for automation.)

After install, map the local domain and enable HTTPS:

```bash
sudo erpnext-dev local-host-checkpoint   # prints the /etc/hosts command for the HOST
sudo erpnext-dev local-domain-status
sudo erpnext-dev local-ssl-wizard        # option 2 = trusted mkcert (stay in wizard after scp)
sudo erpnext-dev local-access-doctor
```

From the interactive menu that is **Main menu > 8) Local HTTPS > 1) SSL Wizard**.
Press `b` to go back one level; reopen anytime with the command above (or
`sudo erpnext-dev local-ssl-menu` for the parent screen). Re-running a wizard
option continues safely when that step is already done.

A local `.test` name is not public DNS — your **host machine** must map it to the
VM's current IP. The IP is detected dynamically; run the printed hosts-file
command on the host, not inside the VM. It is safe to repeat after the VM's IP
changes.

### Choose your host OS (Linux, macOS, or Windows)

The toolkit prints host-side commands (hosts-file mapping, connectivity tests,
mkcert trust) tailored to your **host** machine's OS. `local-dev-quickstart`
asks once and remembers the choice; change it anytime:

```bash
sudo erpnext-dev set-host-os        # Linux / macOS / Windows / Windows+WSL2
```

Every host command then matches your OS:

| Host OS | Hosts file | Edit tool | Resolve test | mkcert install |
|---------|-----------|-----------|--------------|----------------|
| **Linux** | `/etc/hosts` | `sudo sed`/`tee` | `getent hosts` | `apt install -y mkcert libnss3-tools` |
| **macOS** | `/etc/hosts` | `sudo sed -i ''` | `dscacheutil` | `brew install mkcert nss` |
| **Windows** | `…\drivers\etc\hosts` | PowerShell (Admin) | `Resolve-DnsName` | `choco install mkcert` |
| **Windows + WSL2** | `…\drivers\etc\hosts` | PowerShell (Admin) | `Resolve-DnsName` | `choco install mkcert` |

**Use the friendly hostname, not the raw IP.** Open `http://erp.test:8000` after
the hosts file is set. Opening `http://<vm-ip>:8000` often shows an
unstyled/broken login page (Frappe Host-header mismatch).

- **Linux/macOS host:** edit `/etc/hosts` (macOS uses BSD `sed -i ''`), then test
  with `curl -I http://erp.test:8000` (`getent`/`dscacheutil` to confirm DNS).
- **Windows host:** in **PowerShell as Administrator**, back up and edit
  `C:\Windows\System32\drivers\etc\hosts` (the toolkit prints `Copy-Item` /
  `Set-Content` / `Add-Content` commands), then test with
  `Resolve-DnsName erp.test` and `curl.exe -I http://erp.test:8000`.
- **Windows + WSL2:** WSL2 services are reachable from Windows over `localhost`
  and the WSL2 IP changes each boot, so the toolkit maps `erp.test → 127.0.0.1`
  instead of chasing the VM IP.

Trusted local HTTPS order: (1) HOST hosts file — one copy-paste command from
`local-host-checkpoint`, (2) confirm styled `http://erp.test:8000`, (3) on the HOST
run the single mkcert line from `local-ssl-wizard` option 2 (installs CA, generates
cert, and `scp`s into the VM `/tmp/`), (4) stay in the wizard and press Enter after
scp — it installs Nginx HTTPS and you open **`https://erp.test`**. Self-signed
(wizard option 1) stays entirely in the VM but browsers will warn.

For a stable IP after reboot, use `sudo erpnext-dev local-ip-menu` (status, drift,
Netplan static wizard + rollback) and see [`docs/LOCAL-VM-STABLE-IP.md`](docs/LOCAL-VM-STABLE-IP.md).
`local-fixed-ip-guide` still prints hypervisor-specific reservation tips
(KVM/libvirt, UTM/VMware/Parallels, Hyper-V/VirtualBox/WSL2).
To rename the site later, use `sudo erpnext-dev change-local-domain` (then rebuild
local SSL).

Recommended local test order:

1. `local-dev-quickstart`
2. `doctor --plain`
3. `verify-access`
4. `backup-files` → `backup-verify`
5. optional apps, one at a time, with a checkpoint before each

---

## Public VPS / cloud VM

Use a fresh public VM with a real subdomain (for example `erp.example.com`) whose
DNS A record points to the VPS:

```bash
sudo ./erpnext-dev.sh public-vm-guided-setup
```

The guided flow: detect the public IP, confirm domain and site name, check DNS,
confirm the cloud-firewall baseline, install/repair ERPNext, offer to switch to
the production runtime, create a verified backup checkpoint, configure production
HTTPS, apply the production security profile + Fail2Ban, configure scheduled
backups, review the off-VM backup plan, optionally install apps, then run the
production checklist and Final QA.

### Production runtime (no `bench start`)

Development uses `bench start` — a development server with a live-reload watcher
and an active debugger. **Production must not** use it. Switch a public VM to a
supervisor-managed production runtime (gunicorn web workers, background workers,
scheduler, and the socket.io process):

```bash
sudo erpnext-dev setup-production-runtime   # convert to gunicorn + workers under supervisor
sudo erpnext-dev production-runtime-status   # supervisor programs, ports, HTTP readiness
sudo erpnext-dev convert-to-dev-runtime      # revert to the bench start dev runtime
```

The toolkit's Nginx/TLS layer is unchanged — it keeps proxying `:443/:80` to
gunicorn (`:8000`) and socket.io (`:9000`). After conversion, `start`, `stop`,
`restart`, `service-status`, and `logs` all operate on the supervisor stack, and
the development `erpnext-dev.service` is disabled.

**Cloud firewall baseline** (set at the provider before installing):

```text
22/tcp    allow from your admin IP only
80/tcp    allow from anywhere
443/tcp   allow from anywhere
8000/tcp  block from anywhere
9000/tcp  block from anywhere
```

**Production HTTPS** defaults to Let's Encrypt when DNS points directly to the VM.
If the site stays behind a Cloudflare proxy, use the SSL provider wizard and
choose Cloudflare Origin CA with SSL/TLS set to **Full (strict)**:

```bash
sudo erpnext-dev production-ssl-wizard
sudo erpnext-dev production-ssl-status
sudo erpnext-dev configure-cloudflare-origin-ssl   # Cloudflare proxied path
sudo erpnext-dev cloudflare-origin-ssl-status
```

Validate after install (replace `<VPS_PUBLIC_IP>` with the server IP):

```bash
sudo erpnext-dev release-readiness
sudo erpnext-dev production-checklist
curl -I https://erp.example.com                       # expect 200 / redirect
curl -I --connect-timeout 10 http://<VPS_PUBLIC_IP>:8000   # expect blocked/timeout
```

> Always validate production changes on a **fresh disposable VPS with a real test
> subdomain** — not on a client's production server, and not on the local test VM.

---

## The `erpnext-dev` command

The one-liner bootstraps from the extracted bundle, then installs a stable copy
and a short command:

```text
/opt/erpnext-dev/erpnext-dev.sh   stable root-owned toolkit
/usr/local/bin/erpnext-dev        short command for daily use
```

Use `sudo erpnext-dev <command>` for everything after install.

The interactive main menu (`sudo erpnext-dev` / `menu`) uses a Bash-native
polished layout: status strip + two-column options on wide terminals,
single-column on small SSH sessions. It supports `NO_COLOR=1` / `--no-color`,
`TERM=dumb`, and ASCII fallback. Status badges read the **cached** health
snapshot only — live probes stay on `dashboard` / `health-check`.

![Main menu UI mockup](docs/assets/menu-ui-mockup.png)

Handy basics:

```bash
erpnext-dev --help
erpnext-dev version
erpnext-dev where-installed
sudo erpnext-dev menu
sudo erpnext-dev status
sudo erpnext-dev doctor --plain
```

To (re)install or repair the command on an existing VM:

```bash
sudo erpnext-dev install-cli    # or: repair-cli
```

---

## Credentials

The toolkit saves the generated ERPNext Administrator password and database
credentials on the VM. The safe overview does **not** print passwords.

From the interactive menu: **Advanced → 50) Credentials / Login**, or open that
submenu directly:

```bash
sudo erpnext-dev credentials-menu        # Credentials / Login submenu
sudo erpnext-dev credentials-info        # where credentials are stored
sudo erpnext-dev credentials-show        # prints the password (private console only)
sudo erpnext-dev credentials-file-status # owner/permissions
sudo erpnext-dev credentials-secure      # root-only permissions
sudo erpnext-dev credentials-delete      # remove after saving to a password manager
sudo erpnext-dev reset-admin-password
```

The web login uses username `Administrator` and the password shown by
`credentials-show`. The credentials file is excluded from diagnostics, support
bundles, and logs — never paste credentials into tickets, issues, or screenshots.

---

## Backups and restore safety

The backup chain moves a verified copy of your data progressively further from
the VM, so a disk, VM, or account loss never means data loss:

```mermaid
graph LR
  site["ERPNext site"] --> local["Local backup + verify"]
  local --> offvm["Off-VM (rsync/SSH)"]
  local --> object["Object storage (rclone)"]
  local --> rehearsal["Restore rehearsal"]
  offvm --> remoteverify["Remote checksum verify"]
  object --> remoteverify
```

```bash
sudo erpnext-dev backup-files      # database + files backup
sudo erpnext-dev backup-status
sudo erpnext-dev backup-verify
```

Scheduled local backups and retention:

```bash
sudo erpnext-dev configure-backup-schedule
sudo erpnext-dev backup-schedule-status
sudo erpnext-dev backup-retention-plan
sudo erpnext-dev cleanup-old-backups-dry-run
sudo erpnext-dev cleanup-old-backups
```

**Backup model:** local backups are useful but not enough for production. Copy
backups off the VM, keep cloud snapshots for infrastructure rollback, and
rehearse a restore on a disposable VM before trusting any backup.

---

## Off-VM backup server

A second server (outside the ERPNext VM/account) stores backups over rsync/SSH.

1. On the ERPNext VPS, generate the dedicated key and copy the public line:

```bash
sudo erpnext-dev generate-off-vm-backup-key
```

2. On the **backup server**, install the toolkit and run the setup, pasting that
   public key when prompted:

```bash
sudo erpnext-dev backup-server-setup
```

Typical backup-server prompts (use your own values):

```text
Backup Linux user: erpbackup
Backup root folder: /mnt/<volume>/erpnext-backups
ERPNext site/domain folder: erp.example.com
Restrict SSH key to ERPNext VM source IP: <VPS_PUBLIC_IP>
```

3. Back on the ERPNext VPS, configure the target and validate (keep
   `rsync --delete` disabled for the first run):

```bash
sudo erpnext-dev off-vm-backup-guided-setup
# Production host-key hardening (recommended after first successful connect):
sudo erpnext-dev off-vm-trust-host-key
sudo erpnext-dev off-vm-verify-host-key
sudo erpnext-dev off-vm-strict-host-key-enable
sudo erpnext-dev off-vm-backup-dry-run
sudo erpnext-dev run-off-vm-backup
sudo erpnext-dev off-vm-backup-status
```

Default SSH policy is `accept-new` for first setup. Strict mode uses
`StrictHostKeyChecking=yes` with `/etc/erpnext-dev/off-vm-known_hosts`.

Off-VM backup does not replace a restore rehearsal.

---

## Restore rehearsal

A restore rehearsal proves the off-VM backup can actually recover ERPNext. Never
run the first rehearsal on the live production VM — use a disposable local or
cloud VM with the **same site name** as production.

```text
Production VM  → creates and pushes backups to the backup server
Backup server  → stores backups; temporarily authorizes the restore VM
Restore VM     → pulls, verifies, restores, and validates login
```

1. **Prepare the restore VM** — install a matching stack, then start the wizard:

```bash
sudo SITE_NAME=erp.example.com FRAPPE_BRANCH=version-16 ERPNEXT_BRANCH=version-16 \
     ENABLE_AUTOSTART=true AUTO_START=true erpnext-dev install
sudo erpnext-dev restore-rehearsal-wizard   # start with "Restore VM preflight"
```

2. **Generate a temporary restore key** on the restore VM (prints the exact
   command to run on the backup server):

```bash
sudo erpnext-dev restore-key-setup
```

3. **Authorize it** on the backup server (run the printed command, which uses
   `sudo erpnext-dev backup-server-add-restore-key`).

4. **Pull the backup** to the restore VM; enter the target URI when prompted,
   for example `erpbackup@<BACKUP_SERVER_IP>:/mnt/<volume>/erpnext-backups/erp.example.com/`:

```bash
sudo erpnext-dev pull-off-vm-backup
```

5. **Verify and restore** (auto-detects the latest complete backup set):

```bash
sudo erpnext-dev list-backups
sudo erpnext-dev backup-verify
sudo erpnext-dev restore-preflight
sudo erpnext-dev restore-full
sudo erpnext-dev doctor
```

Then open the restored site from your workstation using a local `/etc/hosts`
override (`<RESTORE_VM_IP> erp.example.com`) and confirm login works.

6. **Remove the temporary key** on the backup server and **record** the result on
   production:

```bash
# On the backup server:
sudo erpnext-dev backup-server-remove-restore-key
# On production:
sudo erpnext-dev restore-rehearsal-record
sudo erpnext-dev restore-rehearsal-status
```

Repeat a rehearsal after major upgrades, migrations, or backup-policy changes.

---

## Production operations dashboard

The **operations health dashboard** is the day-to-day status view for an
installed VM (canonical HEALTHY / DEGRADED / CRITICAL / UNKNOWN model). From
v1.17.5 the human view uses the same Bash UI section boxes as the main menu
(Overview / Resources / Application health / Protection / Monitoring).

![Operations health dashboard](docs/assets/dashboard-health.png)

> Screenshot may lag a patch behind the live renderer; trust
> `sudo erpnext-dev dashboard` / `dashboard-render-test` for current layout.

```bash
sudo erpnext-dev dashboard              # human snapshot
sudo erpnext-dev dashboard --watch 5    # refresh every 5s
sudo erpnext-dev dashboard --json       # CloudPanel / automation contract
sudo erpnext-dev health-snapshot        # alias for dashboard --json
sudo erpnext-dev dashboard --details    # extra resource cards
sudo erpnext-dev dashboard --no-color   # or NO_COLOR=1
./erpnext-dev.sh dashboard-render-test  # fixture layout (CI / no sudo)
```

![Health incidents](docs/assets/incident-history.png)

For menus that group tested maintenance commands:

```bash
sudo erpnext-dev production-ops-wizard
```

Architecture and future healing phases:
[`docs/HEALTH-ARCHITECTURE.md`](docs/HEALTH-ARCHITECTURE.md).

Example contracts:

- JSON snapshot shape: [`docs/assets/health-json-example.md`](docs/assets/health-json-example.md)
- OpenMetrics export: [`docs/assets/health-metrics-example.txt`](docs/assets/health-metrics-example.txt)

Monitoring (v1.17+):

```bash
sudo erpnext-dev incidents              # recent status transitions
sudo erpnext-dev incident-show          # latest incident JSON
sudo erpnext-dev health-history         # recent history samples
sudo erpnext-dev health-metrics         # OpenMetrics text export
```

Optional policy file `/etc/erpnext-dev/health.env` (example). The toolkit
**parses allowlisted keys only** (it never `source`s this file as shell). Prefer
root-owned mode `600` or `640`; webhook URLs must be `https://` (or localhost
`http://` for local tests):

```bash
HEALTH_ALERT_ON=CRITICAL
HEALTH_ALERT_WEBHOOK_URL=https://hooks.example.com/erpnext-dev
HEALTH_CONSECUTIVE_FAIL_THRESHOLD=3
HEALTH_COOLDOWN_SEC=600
```

---

## Health monitoring

A lightweight, **read-only** systemd health timer runs the same canonical
snapshot used by `dashboard` (it never restarts services or changes the site):

```bash
sudo erpnext-dev health-monitoring-wizard
sudo erpnext-dev health-check
sudo erpnext-dev configure-health-check-timer
sudo erpnext-dev health-check-status
```

It covers host resources (including MemAvailable), HTTP reachability/latency,
engine-aware runtime (native or Docker), HTTPS, firewall, Fail2Ban, backups,
and restore rehearsal. Results are recorded at
`/etc/erpnext-dev/health-check.state` (compat) and
`/var/lib/erpnext-dev/metrics/` (history + current). Status transitions create
incident files under `/var/lib/erpnext-dev/incidents/`.

---

## Go-live validation

Some readiness checks live outside the guest VM (cloud snapshot, provider
firewall, Cloudflare settings). Confirm them with the checklists, then record the
confirmed state on the production VM:

```bash
sudo erpnext-dev cloud-firewall-checklist
sudo erpnext-dev cloudflare-checklist
sudo erpnext-dev go-live-record
sudo erpnext-dev go-live-status
```

Once recorded, `production-checklist`, `final-qa`, and `support-bundle` include
the go-live state. Repeat after any snapshot, firewall, DNS, SSL/TLS, or origin
certificate change.

---

## Optional Frappe apps

Install optional apps only after the core install is healthy, one at a time, with
a backup/snapshot checkpoint before each:

```bash
sudo erpnext-dev app-library
sudo erpnext-dev app-install-wizard
sudo erpnext-dev app-status
```

| App | Publisher | Command |
|---|---|---|
| CRM | Frappe (official) | `install-crm` |
| HR / HRMS | Frappe (official) | `install-hrms` |
| Education | Frappe (official) | `install-education` |
| Payments | Frappe (official) | `install-payments` |
| Webshop / E-Commerce | Frappe (official) | `install-webshop` |
| Builder | Frappe (official) | `install-builder` |
| Learning / LMS | Frappe (official) | `install-lms` |
| Wiki | Frappe (official) | `install-wiki` |
| Print Designer | Frappe (official) | `install-print-designer` |
| Drive | Frappe (official) | `install-drive` |
| Gameplan | Frappe (official) | `install-gameplan` |
| Lending | Frappe (official) | `install-lending` |
| Helpdesk | Frappe (official) | `install-helpdesk` |
| Telephony | Frappe (official) | `install-telephony` |
| Insights | Frappe (official) | `install-insights` |
| India Compliance (GST) | Community (Resilient Tech) | `install-india-compliance` |
| Raven Team Chat | Community (The Commit Company) | `install-raven` |

Menus and install prompts label each app as **Frappe (official)** or **Community / third-party**.
Custom Git apps and registry repair live under `sudo erpnext-dev advanced-app-tools`
and carry stronger warnings, since unlisted third-party apps may be incompatible or unsafe.

> After installing **Education**, the site root may redirect to the Education
> portal. ERPNext Desk is still at `/app`; the login page is at `/login`.

---

## HTTPS / SSL

```bash
sudo erpnext-dev ssl-mode-status
sudo erpnext-dev ssl-mode-guide
```

| Mode | Best for | Notes |
|---|---|---|
| Local mkcert / self-signed | Local VM | Development only |
| Let's Encrypt | Public VM, DNS directly to VM | HTTP-01 validation on port 80 |
| Cloudflare Origin CA | Public VM behind Cloudflare proxy | Requires Full (strict) |

Local VM: `local-ssl-wizard`, `verify-local-ssl`, `change-local-domain`,
`disable-local-ssl`. Production: `production-ssl-wizard`,
`configure-cloudflare-origin-ssl`, `production-ssl-status`,
`disable-production-ssl`. The main menu separates **Local HTTPS** from
**Production HTTPS** — use local HTTPS only for `.test` domains.

---

## Security hardening

Apply the profile that matches the VM type. Do not apply the production firewall
profile to a local `.test` VM unless local HTTPS/Nginx has fully replaced direct
bench access.

```bash
sudo erpnext-dev security-hardening-wizard
sudo erpnext-dev local-firewall-profile        # local VM
sudo erpnext-dev production-firewall-profile    # production, after domain + HTTPS verified
sudo erpnext-dev repair-local-access            # if hardening blocked erp.test / :8000
sudo erpnext-dev firewall-rollback-snapshots
sudo erpnext-dev configure-fail2ban
sudo erpnext-dev fail2ban-status
```

Recommended public exposure: `22/tcp` restricted to your admin IP at the cloud
firewall, `80`/`443` public (or CDN/proxy ranges), and `8000`/`9000` (plus
`11000`/`13000`) blocked publicly. UFW keeps SSH open to reduce lockout risk;
restrict SSH at the cloud firewall layer first.

---

## Guarded upgrades

Upgrade ERPNext with a backup-first, verified, reversible workflow:

```bash
sudo erpnext-dev update-preflight       # read-only readiness report
sudo erpnext-dev safe-update-wizard     # backup, then verified bench update
sudo erpnext-dev update-rollback        # guided rollback if needed
```

`update-preflight` checks disk space, uncommitted app changes, and backup
recency. `safe-update-wizard` records the pre-upgrade app state, takes a full
backup, runs the update, migrates, verifies site health, and prints a rollback
plan on failure.

---

## Toolkit integrity and updates

```bash
erpnext-dev verify-toolkit       # active script + all modules match SHA256SUMS
erpnext-dev verify-signature     # GPG signature over SHA256SUMS (bundled key)
sudo erpnext-dev update-toolkit  # atomic self-update (releases/<ver> + current symlink)
sudo erpnext-dev toolkit-rollback # switch back to the previous release
sudo erpnext-dev command-audit   # list available commands
```

`update-toolkit` downloads the signed release bundle, verifies its checksums and
signature, extracts it to `/opt/erpnext-dev/releases/<ver>/`, then flips the
`/opt/erpnext-dev/current` symlink in a single atomic step. The previous release
is kept on disk, so `toolkit-rollback` restores it instantly.

**Field-test from `main` (no new tag):** unsigned raw-file channel for trying
unreleased fixes on a non-production / local VM. Installs into
`/opt/erpnext-dev/releases/main` (does **not** overwrite a signed `vX.Y.Z` slot).

If your installed toolkit is still **v1.17.4** (before the slot fix), set an
explicit non-`v*` version so the first pull does not replace `releases/v1.17.4`:

```bash
# Safe first pull from an older install (lands in releases/vmain or releases/main)
TOOLKIT_UPDATE_CHANNEL=main TOOLKIT_UPDATE_VERSION=main sudo -E erpnext-dev update-toolkit

# After the slot fix is on main, this is enough on local/non-public VMs:
TOOLKIT_UPDATE_CHANNEL=main sudo -E erpnext-dev update-toolkit

# Public/production workflow (explicit override required)
TOOLKIT_UPDATE_CHANNEL=main TOOLKIT_UPDATE_ALLOW_MAIN=1 sudo -E erpnext-dev update-toolkit

sudo erpnext-dev version
sudo erpnext-dev dashboard-render-test
sudo erpnext-dev dashboard
sudo erpnext-dev toolkit-rollback   # return to previous signed slot if needed
```

`verify-toolkit` looks for `SHA256SUMS` in the current directory, beside the
active/stable script, or in `/opt/erpnext-dev`; override with
`CHECKSUM_FILE=/path/to/SHA256SUMS`.

`verify-toolkit` checks the entrypoint and every runtime `lib/*.sh` module against
`SHA256SUMS`. CI also asserts that tampering any module causes `verify-toolkit` to
exit non-zero (negative fixture on extracted bundles and on live installs).

`update-toolkit` and `toolkit-rollback` are exercised in CI by
`scripts/test-atomic-update.sh`: a hermetic `file://` release server, synthetic
versioned bundles, update → rollback, and a corrupt-bundle negative that proves a
failed update never half-applies. Run locally with:

```bash
sudo -E scripts/test-atomic-update.sh
```

### Pinned toolchain (reproducible installs)

For reproducible installs the toolkit pins its whole bootstrap toolchain. Run
`erpnext-dev versions` to print the current compatibility matrix (it is also
included in `where-installed` and every support bundle):

| Component | Pinned via | Default |
| --- | --- | --- |
| Node.js | `NODE_VERSION` | `24` |
| nvm | `NVM_VERSION` | `0.40.3` |
| uv | `UV_VERSION` | `0.11.28` |
| Python | `PYTHON_VERSION` | `3.14` |
| Frappe branch | `FRAPPE_BRANCH` | `version-16` |
| ERPNext branch | `ERPNEXT_BRANCH` | `version-16` |
| frappe-bench | `BENCH_VERSION` | `5.31.0` |

Each is override-able via its environment variable. `BENCH_VERSION=` (empty)
intentionally unpins `frappe-bench` and installs the latest published release.

### Stale lock: "Another toolkit task is already running"

The toolkit uses a lock so two installs/menus cannot run at once. The lock lives
in a private, non-world-writable directory: `/run/lock/erpnext-dev/toolkit.lock`
when run as root, or `$XDG_RUNTIME_DIR/erpnext-dev/toolkit.lock` (falling back to
`/tmp/erpnext-dev-<uid>-locks/toolkit.lock`) for a normal user. The directory is
created mode `0700` and a symlinked lock file is refused, so another local user
cannot pre-plant the path. Seeing that error almost always means **another
`erpnext-dev` session is still open** (second SSH window, background menu, stuck
process) — not that the file itself is "stuck."

```bash
# See who holds the lock (also printed automatically on lock failure):
sudo fuser -v /run/lock/erpnext-dev/toolkit.lock
ps aux | grep -E '[e]rpnext-dev'

# Prefer the safe clearer (refuses if a live process still holds the lock):
sudo erpnext-dev clear-lock

# Only if clear-lock refuses and you are certain the listed PIDs are wrong:
sudo FORCE_CLEAR_LOCK=1 erpnext-dev clear-lock
```

Avoid `rm` on the lock file while a toolkit is still running — that can let two
copies run at once. Use `clear-lock` instead.

---

## Diagnostics and support

```bash
sudo erpnext-dev doctor            # human summary
sudo erpnext-dev doctor --plain
sudo erpnext-dev doctor --json
sudo erpnext-dev verify-access
sudo erpnext-dev support-bundle       # redacted evidence archive
sudo erpnext-dev support-bundle-audit # scans a bundle for secrets before sharing
sudo erpnext-dev next-step
```

Support bundles are redacted: they exclude credential files, private keys, raw
secrets, tokens, and passwords. The audit is best-effort and does not replace
manual review.

---

## Architecture diagrams

### One CLI, two deployment engines

![One CLI, two deployment engines](docs/assets/multi_engine_architecture_diagram.png)

The same `erpnext-dev` command drives both engines through one lifecycle
contract, so install, HTTPS, backup, restore, and diagnostics work the same way
whether you deploy natively or with Docker.

### Production backup architecture

![Production Backup Architecture](docs/assets/production_backup_architecture_diagram.png)

### Local testing VM architecture

![Local Testing VM Architecture](docs/assets/local_testing_vm_architecture_diagram.png)

---

## Documentation files

| File | Purpose |
|---|---|
| [`README.md`](README.md) | Setup and usage guide (this file) |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to contribute (docs, tests, engines) |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | Community standards |
| [`SUPPORT.md`](SUPPORT.md) | Where to ask for help vs file bugs |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Local development and validation |
| [`docs/RELEASE-PROCESS.md`](docs/RELEASE-PROCESS.md) | How maintainers cut signed releases |
| [`docs/COMMUNITY-BOARD.md`](docs/COMMUNITY-BOARD.md) | Community project board setup + seed issues |
| [`CHANGELOG.md`](CHANGELOG.md) | Version history and release notes |
| [`SECURITY.md`](SECURITY.md) | Threat model, credential handling, release signing |
| [`TESTING.md`](TESTING.md) | Validation scenarios and QA commands |
| [`VALIDATION.md`](VALIDATION.md) | Combined go-live runbook (native + Docker production) for a real VPS + domain |
| [`ROADMAP.md`](ROADMAP.md) | v1.18–v1.23 plan + historical milestones |
| [Roadmap board](https://github.com/users/ReyadWeb/projects/3) | Public Todo / In Progress / Done tracking ([docs/ROADMAP-BOARD.md](docs/ROADMAP-BOARD.md)) |
| [`RELEASE-MANIFEST.txt`](RELEASE-MANIFEST.txt) | Files expected in each release (validated in CI) |

---

## Production caution

This toolkit can prepare a production-candidate VM. After v1.9.0 the core path is
CI-proven (install, backup/restore, production runtime, signed releases), but
production readiness still requires **your** validation on a real VPS: domain/DNS,
cloud firewall, off-VM backup target, restore rehearsal, snapshot policy,
monitoring expectations, and an update process. Use the checklist in
[`TESTING.md`](TESTING.md#vps-production-validation-v190) before calling the site live.

---

## Additional resources

This toolkit installs and operates the stack; the resources below teach the
products and communities around it. Prefer official sources when you can.

### Learn (docs)

- ERPNext Documentation: https://docs.erpnext.com
- Frappe Framework Documentation: https://frappeframework.com/docs
- Frappe Framework User Guide: https://docs.frappe.io/framework
- ERPNext User Manual: https://docs.frappe.io/erpnext

### Train (courses)

- Frappe School (courses catalog): https://school.frappe.io
- Frappe School course list: https://school.frappe.io/lms/courses
- Frappe School overview: https://frappe.io/school
- Featured: [Full-stack App Development with Frappe Framework](https://school.frappe.io/lms/courses/frappe-developer-certification)

### Build (source & deployment)

- ERPNext on GitHub: https://github.com/frappe/erpnext
- Frappe Framework on GitHub: https://github.com/frappe/frappe
- Official Frappe Docker: https://github.com/frappe/frappe_docker
- Official Frappe Helm chart: https://github.com/frappe/helm
- Bench (CLI): https://github.com/frappe/bench

### Community & discovery

- Awesome Frappe (curated apps and tools): https://github.com/gavindsouza/awesome-frappe
- Frappe Forum: https://discuss.frappe.io
- Frappe Cloud (hosted option): https://frappecloud.com
- This toolkit — Discussions: https://github.com/ReyadWeb/erpnext-dev-toolkit/discussions
- This toolkit — Contributing: https://github.com/ReyadWeb/erpnext-dev-toolkit/blob/main/CONTRIBUTING.md

This toolkit wraps and complements those upstream projects; it does not replace
them. For accounting, HR, manufacturing, custom apps, the Frappe ORM/APIs, or
certification paths, use the official docs and Frappe School above as the source
of truth.

---

## A note to you

Thank you for using the ERPNext Developer Toolkit. It exists to take the friction
out of standing up ERPNext the right way — safely, repeatably, and with a clear
path from a fresh VM to a validated, backed-up, HTTPS-secured deployment on either
a native host or Docker.

If it saved you time, consider starring the repository, opening an issue with
ideas or rough edges, or sharing it with someone wrestling with their first
ERPNext install. Every bug report and suggestion makes the next person's setup
smoother.

Happy building, and may your migrations always be reversible.

Contributions of all sizes are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md)
and [`SUPPORT.md`](SUPPORT.md). You do not need to be an ERPNext infrastructure
expert to help.
