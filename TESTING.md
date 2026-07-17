# Testing guide

**Current release:** v1.17.3 · See [`ROADMAP.md`](ROADMAP.md) for what is CI-proven vs what requires field validation.

---

## v1.17.3 CLI menu UI foundation

Hermetic (no sudo):

```bash
scripts/test-ui-render.sh
./erpnext-dev.sh menu-render-test
NO_COLOR=1 TERM=dumb COLUMNS=80 ./erpnext-dev.sh menu-render-test | od -c | head
```

Expected:

- Title, all 17 main options, and “Choose an option” appear.
- With `NO_COLOR=1` / `TERM=dumb`, output contains **no** ANSI escapes.
- `scripts/test-ui-render.sh` also asserts OK/status `GREEN` survives the
  post-`tee` color re-init path (regression from v1.16–v1.17.3).
- Menu stays fast (cached metrics only; no live health probes).

Interactive smoke:

```bash
sudo erpnext-dev menu
# wide terminal: two-column boxed menu + status strip
# narrow / COLUMNS=80: single-column list
```

---

## v1.17.2 release publish alignment

After a stable tag’s release workflow finishes (and `release-signing` is approved):

```bash
scripts/assert-github-release-assets.sh v1.17.2 --require-latest
# expect: assert-github-release-assets: v1.17.2 OK

VERSION=v1.17.2
BASE="https://github.com/ReyadWeb/erpnext-dev-toolkit/releases/download/${VERSION}"
cd "$(mktemp -d)"
curl -fsSLO "${BASE}/erpnext-dev-${VERSION}.tar.gz"
tar -xzf "erpnext-dev-${VERSION}.tar.gz"
cd "erpnext-dev-${VERSION}"
sha256sum -c SHA256SUMS
./erpnext-dev.sh verify-signature
./erpnext-dev.sh version   # ERPNext Developer Toolkit v1.17.2
```

`/releases/latest` must redirect to `v1.17.2`. Do **not** install from the automatic
“Source code” archives on the tag page.

---

## v1.17.0 monitoring & incident engine

Hermetic (no install, no sudo): `scripts/test-health-snapshot.sh` covers status
normalization plus incident transitions, history append, and would-heal cooldown
dry-run under a temporary `HEALTH_LIB_DIR`.

```bash
scripts/test-health-snapshot.sh
./erpnext-dev.sh --help | grep -nE "incidents|health-history|health-metrics"
```

On an installed host:

```bash
sudo erpnext-dev health-check
sudo erpnext-dev incidents
sudo erpnext-dev incident-show
sudo erpnext-dev health-history 10
sudo erpnext-dev health-metrics | head
ls -la /var/lib/erpnext-dev/metrics /var/lib/erpnext-dev/incidents /var/lib/erpnext-dev/healing
```

Expected:

- History grows in `/var/lib/erpnext-dev/metrics/history.jsonl`.
- Status transitions create incident JSON under `/var/lib/erpnext-dev/incidents/`.
- Dashboard healing section shows streaks / would-heal text but **never** restarts services.
- Optional `/etc/erpnext-dev/health.env` can set `HEALTH_ALERT_WEBHOOK_URL` / thresholds.

---

## v1.10.0 multi-engine (Docker engine)

Hermetic check (no Docker daemon, no sudo, no network):
`scripts/test-engine-select.sh` asserts engine normalization, the native default,
config persistence round-trip, and the docker helper defaults. It runs inside
`scripts/validate-release.sh`.

```text
scripts/test-engine-select.sh
# expect: "engine-select tests: all checks passed"
```

Docker engine install is exercised by the **non-blocking** `docker-install-smoke`
job in `.github/workflows/integration.yml` (ubuntu-24.04, `continue-on-error`):
it forces `DEPLOYMENT_ENGINE=docker`, runs a real `install`, and probes
`http://localhost:8080`. It reports on every tag but does not gate releases; the
native `install-smoke` leg remains the release gate.

Manual local check on a Docker-capable host:

```bash
sudo DEPLOYMENT_ENGINE=docker erpnext-dev install
sudo erpnext-dev engine-status
sudo erpnext-dev status      # docker compose ps
curl -I http://localhost:8080
```

---

## VPS production validation (v1.9.0)

Use this checklist on a **fresh Ubuntu 24.04 or 26.04 LTS VPS** with a real domain,
mimicking production. Install from the signed bundle:

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates tar
VERSION="v1.9.0"
BASE="https://github.com/ReyadWeb/erpnext-dev-toolkit/releases/download/${VERSION}"
curl -fsSLO "${BASE}/erpnext-dev-${VERSION}.tar.gz"
tar -xzf "erpnext-dev-${VERSION}.tar.gz" && cd "erpnext-dev-${VERSION}"
sha256sum -c SHA256SUMS
sudo ./erpnext-dev.sh verify-signature
sudo ./erpnext-dev.sh install-preflight
sudo ./erpnext-dev.sh public-vm-guided-setup   # or public-vm-quickstart
```

### Checklist

| # | Area | Pass criteria |
|---|------|----------------|
| 1 | Integrity | `verify-signature` GOODSIG; `verify-toolkit` all modules OK |
| 2 | Install | Site reachable on **hostname** (not raw IP for normal use) |
| 3 | Production runtime | `production-runtime-status` → supervisor RUNNING; **no** `bench start` |
| 4 | HTTPS | Production SSL wizard; browser login styled and working |
| 5 | Security | UFW + optional Fail2Ban; `security-audit` acceptable |
| 6 | Backups | `backup-files` + `backup-verify` |
| 7 | Restore | Restore rehearsal or `restore-full` on disposable clone/snapshot |
| 8 | Off-VM backup | rsync target configured; dry-run + real run (if using) |
| 9 | Toolkit update | `update-toolkit` then `toolkit-rollback` once |
| 10 | ERPNext upgrade | `update-preflight` + `safe-update-wizard` (maintenance window) |
| 11 | Ops | `production-ops-wizard`, `doctor`, `support-bundle` + audit |
| 12 | Go-live | `go-live-record`, cloud firewall + DNS/proxy confirmed |

Record failures with command output; open issues or patch v1.8.x before production traffic.

---

## CI and developer validation (v1.8.x – v1.9.x)

### Ubuntu 26.04 integration leg (sudo-rs / install_self_for_reuse)

GitHub's `ubuntu-26.04` runner image ships **sudo-rs**, which ignores `sudo -E`
(preserving the environment). Integration already passes `CHECKSUM_FILE` via
`sudo env VAR=val` for `verify-toolkit` — not `sudo -E`.

**Failure mode (fixed in v1.9.4+):** `install_self_for_reuse` used
`readlink -f "${BASH_SOURCE[0]}"` when copying the checkout into
`/opt/erpnext-dev/`. On the 26.04 leg, that can return empty for a relative
invoke path (`sudo ./erpnext-dev.sh -y install`). The copy was skipped silently,
ERPNext still installed, but integration's `verify-toolkit` step failed with
`installed toolkit not found at /opt/erpnext-dev/erpnext-dev.sh`.

**Fix:** fall back to `ERPNEXT_DEV_ENTRY_SCRIPT` (resolved at bootstrap) and
absolute-path the invoke location; fail install if `/opt` copy fails. Integration
adds an explicit **Assert stable toolkit at /opt** step before verify-toolkit.

**Second failure mode (exit 141 / SIGPIPE):** under `set -o pipefail`, piping
`verify-toolkit` into `grep -q` makes grep exit as soon as it matches and close
the pipe. The writer then gets SIGPIPE (exit 141). That race is reliable on
Ubuntu 26.04 / sudo-rs. CI must **capture output to a file, then grep** — never
`cmd | grep -q` under `pipefail`.

Hermetic regression: `scripts/test-install-self-path.sh` (wired into
`validate-release.sh`).

The 26.04 matrix leg stays **non-blocking** until the preview runner reaches GA;
then flip `experimental: false` in `.github/workflows/integration.yml`.

### v1.9.2 cross-platform local host support (host-mapping regression matrix)

Hermetic check (no VM, no sudo): `scripts/test-host-os-output.sh` asserts the
per-host-OS markers for the DNS/mapping and connectivity-test emitters. It also
runs inside `scripts/validate-release.sh`.

```text
scripts/test-host-os-output.sh
# expect: "host-os output tests: all checks passed"
```

Manual matrix — set the host OS, then confirm the printed commands match:

| `set-host-os` choice | `local-host-checkpoint` mapping | `host-dns-guide` test line | mkcert install (`local-ssl-wizard`) |
|----------------------|---------------------------------|----------------------------|-------------------------------------|
| Linux | `sudo sed -i "/…/d" /etc/hosts` + `tee -a /etc/hosts` | `getent hosts <site>` | `apt install -y libnss3-tools` |
| macOS | `sudo sed -i '' "/…/d" /etc/hosts` (BSD form) | `dscacheutil -q host -a name <site>` | `brew install mkcert nss` |
| Windows | PowerShell `Set-Content`/`Add-Content` on `…\drivers\etc\hosts` | `Resolve-DnsName <site>` / `curl.exe -I` | `choco install mkcert` |
| Windows + WSL2 | same PowerShell block, but `VM_IP = "127.0.0.1"` | `Resolve-DnsName <site>` | `choco install mkcert` |

```text
1. sudo erpnext-dev set-host-os   # pick each option in turn
2. sudo erpnext-dev local-host-checkpoint   # mapping block matches the row above
3. sudo erpnext-dev host-dns-guide          # resolve/test line matches
4. sudo erpnext-dev local-fixed-ip-guide    # hypervisor guidance matches host OS
5. Empty/unset HOST_OS falls back to the Linux row (existing behavior).
```

### v1.9.0 signing authority separation (release-signing environment)

This is a GitHub-side control; validate it once after configuring the environment.

Setup (GitHub → Settings → Environments → `release-signing`): required reviewer(s),
deployment tag rule `v*`, and `GPG_PRIVATE_KEY` / `GPG_PASSPHRASE` as **environment**
secrets (repository-level copies deleted). See `SECURITY.md`.

Validation on the next stable tag:

```text
1. Push a vX.Y.Z tag.
2. validate + integration run to completion.
3. The "Sign and publish" job shows "Waiting" for release-signing approval.
4. Without approval: signing/publishing does NOT proceed.
5. After a reviewer approves: SHA256SUMS is signed and the release publishes.
6. verify-signature on the published bundle reports the pinned maintainer fingerprint.
```

Negative check (optional): with repository-level GPG secrets removed and no approval,
confirm the job cannot access the key and the release is not signed/published.

### v1.8.2 staged signature verification (self-update authenticity)

```bash
scripts/test-staged-signature.sh    # unit matrix: sig/pubkey/fingerprint/gpg negatives
scripts/validate-release.sh         # includes staged-signature matrix
sudo -E scripts/test-atomic-update.sh   # signed bundles; unsigned update rejected
```

Expected:

```text
valid signed bundle: PASS
missing SHA256SUMS.asc: FAIL
missing bundled public key: FAIL
tampered SHA256SUMS: FAIL
valid signature, wrong pinned fingerprint: FAIL
valid signature against mismatched bundled pubkey: FAIL
missing gpg: FAIL
atomic update smoke: signed v9.9.8 → v9.9.9 → rollback; corrupt/unsigned rejected
```

### v1.8.0 reliability proof (atomic update + gate enforcement)

```bash
scripts/validate-release.sh          # includes release-signing-policy unit matrix
sudo -E scripts/test-atomic-update.sh   # hermetic update → rollback + corrupt-bundle negative
```

Expected:

```text
release-signing-policy: stable tag without key fails
release-signing-policy: pre-release without key allows publish-unsigned
release-signing-policy: stable tag with key requires sign
atomic update smoke: v9.9.8 → v9.9.9 → rollback; corrupt v9.9.9 rejected; current unchanged
CI quickstart step: verify-toolkit passes on extract, fails after lib/common.sh tamper
CI integration step: verify-toolkit passes on /opt install, fails after lib/common.sh tamper
```

## v1.2.0 Phase C security hardening

```bash
bash -n lib/security.sh
scripts/validate-release.sh
sudo erpnext-dev security-audit
TOOLKIT_UPDATE_VERSION=v1.2.0 sudo erpnext-dev update-toolkit
```

## v1.1.90 lib/ops.sh extraction — Phase B complete

```bash
bash -n lib/ops.sh
scripts/validate-release.sh
sudo erpnext-dev production-ops-wizard
```

## v1.1.89 lib/status.sh extraction

```bash
bash -n lib/status.sh
scripts/validate-release.sh
```

## v1.1.88 lib/frappe.sh extraction and duplicate cleanup

```bash
bash -n lib/frappe.sh
scripts/validate-release.sh
```

## v1.1.87 lib/access.sh extraction

```bash
bash -n lib/access.sh
scripts/validate-release.sh
```

## v1.1.86 lib/config.sh extraction

```bash
bash -n lib/config.sh
scripts/validate-release.sh
```

## v1.1.85 lib/install.sh Tier C extraction

```bash
bash -n lib/install.sh
scripts/validate-release.sh
sudo erpnext-dev first-run
sudo erpnext-dev local-dev-quickstart  # on test VM only
```

## v1.1.84 lib/install.sh Tier B extraction

Purpose: extend `lib/install.sh` with post-install checkpoint and summary helpers.

```bash
bash -n lib/install.sh
scripts/validate-release.sh
```

Expected: version prints v1.1.84; `print_summary` and checkpoint behavior unchanged after install.

## v1.1.83 lib/install.sh Tier A extraction

Purpose: move install preflight, package setup, Frappe stack bootstrap, and install/repair/uninstall into `lib/install.sh`.

Package checks:

```bash
bash -n lib/install.sh
./erpnext-dev.sh version
scripts/validate-release.sh
sudo erpnext-dev install-preflight
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.83`.
- `lib/install.sh` exists and is sourced by `erpnext-dev.sh`.
- Install and repair commands remain available in help output.

## v1.1.82 lib/service.sh extraction

Purpose: move ERPNext systemd service management and runtime state helpers into `lib/service.sh`.

Package checks:

```bash
bash -n lib/service.sh
./erpnext-dev.sh version
scripts/validate-release.sh
sudo erpnext-dev runtime-status
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.82`.
- `lib/service.sh` exists and is sourced by `erpnext-dev.sh`.
- Service and runtime commands remain available in help output.

## v1.1.81 lib/storage.sh extraction

Purpose: move root storage detection, status, and expansion helpers into `lib/storage.sh`.

Package checks:

```bash
bash -n lib/storage.sh
./erpnext-dev.sh version
scripts/validate-release.sh
sudo erpnext-dev storage-status
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.81`.
- `lib/storage.sh` exists and is sourced by `erpnext-dev.sh`.
- Storage commands remain available in help output.

## v1.1.80 lib/health.sh extraction

Purpose: move health checks, timers, go-live validation, and production readiness helpers into `lib/health.sh`.

Package checks:

```bash
bash -n lib/health.sh
./erpnext-dev.sh version
scripts/validate-release.sh
sudo erpnext-dev health-check-status
sudo erpnext-dev go-live-status
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.80`.
- `lib/health.sh` exists and is sourced by `erpnext-dev.sh`.
- Health and go-live commands remain available in help output.

## v1.1.79 lib/apps.sh extraction

Purpose: move curated app installation, compatibility checks, and app library menus into `lib/apps.sh`.

Package checks:

```bash
bash -n erpnext-dev.sh
bash -n lib/apps.sh
./erpnext-dev.sh version
scripts/validate-release.sh
sudo erpnext-dev app-status
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.79`.
- `lib/apps.sh` exists and is sourced by `erpnext-dev.sh`.
- App library commands remain available in help output.

## v1.1.78 lib/ssl.sh and lib/firewall.sh extraction

Purpose: move production/local SSL and firewall/security helpers into dedicated library modules.

Package checks:

```bash
bash -n erpnext-dev.sh
bash -n lib/common.sh
bash -n lib/support.sh
bash -n lib/backup.sh
bash -n lib/ssl.sh
bash -n lib/firewall.sh
./erpnext-dev.sh version
scripts/validate-release.sh
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.78`.
- `lib/ssl.sh` and `lib/firewall.sh` exist and are sourced by `erpnext-dev.sh`.
- SSL and firewall commands remain available in help output.

## v1.1.77 lib/backup.sh extraction

Purpose: move local backup, off-VM backup, restore, and rehearsal helpers into `lib/backup.sh`.

Package checks:

```bash
bash -n erpnext-dev.sh
bash -n lib/common.sh
bash -n lib/support.sh
bash -n lib/backup.sh
./erpnext-dev.sh version
scripts/validate-release.sh
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.77`.
- `lib/backup.sh` exists and is sourced by `erpnext-dev.sh`.
- Backup-related commands remain available in help output.

## v1.1.76 lib/support.sh extraction

Purpose: move doctor, support-bundle, support-bundle audit, and command-audit helpers into `lib/support.sh`.

Package checks:

```bash
bash -n erpnext-dev.sh
bash -n lib/common.sh
bash -n lib/support.sh
./erpnext-dev.sh version
scripts/run-shellcheck.sh
scripts/validate-release.sh
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.76`.
- `lib/support.sh` exists and is sourced by `erpnext-dev.sh`.
- Support-bundle audit fixture still passes in release validation.

## v1.1.75 lib/common.sh and shellcheck

Purpose: begin careful modularization and add static analysis for release scripts and the first extracted module.

Package checks:

```bash
bash -n erpnext-dev.sh
bash -n lib/common.sh
./erpnext-dev.sh version
scripts/run-shellcheck.sh
scripts/validate-release.sh
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.75`.
- `lib/common.sh` exists and is sourced by `erpnext-dev.sh`.
- `scripts/run-shellcheck.sh` passes when shellcheck is installed.
- `scripts/validate-release.sh` passes locally.

## v1.1.74 release manifest, expanded checksums, and quality assessment

Purpose: add release manifest validation, expanded checksum coverage, version consistency checks, menu smoke tests, and a tracked quality assessment document.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
sha256sum -c SHA256SUMS
scripts/validate-release.sh
scripts/generate-release-checksums.sh
./erpnext-dev.sh menu-self-test

grep -n "v1.1.74" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md QUALITY-ASSESSMENT.md
grep -n "RELEASE-MANIFEST" README.md RELIABILITY-PLAN.md SECURITY.md
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.74`.
- `sha256sum -c SHA256SUMS` reports OK for `erpnext-dev.sh`, `scripts/validate-release.sh`, and `RELEASE-MANIFEST.txt`.
- `scripts/validate-release.sh` reports manifest, version, menu, and support-bundle audit checks passed.
- `QUALITY-ASSESSMENT.md` and `RELEASE-MANIFEST.txt` exist.

Production validation scope:

- This patch does not change ERPNext install, backup, restore, SSL, firewall, health-monitoring, go-live, or dashboard behavior.
- Production validation should include verified tag-pinned update, `verify-toolkit`, Final QA option 1, and `scripts/validate-release.sh` passing on the release tree.

## v1.1.73 support-bundle audit and package validation expansion

Purpose: add a best-effort support-bundle audit command and expand the repeatable release validation script.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
sha256sum -c SHA256SUMS
scripts/validate-release.sh
./erpnext-dev.sh --help | grep -n "support-bundle-audit"

printf '10\n11\n\nb\nq\n' | sudo ./erpnext-dev.sh production-ops-wizard

unzip -l erpnext-dev-toolkit-v1.1.73.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.73`.
- `sha256sum -c SHA256SUMS` reports `erpnext-dev.sh: OK`.
- `scripts/validate-release.sh` reports `support-bundle-audit clean fixture passed` and `release validation complete`.
- Help exposes `support-bundle-audit`.
- Production Operations > Support and Diagnostics includes `11) Audit latest support bundle`.
- Package contains no `GITHUB-UPDATE-v*.md` files.

Production validation scope:

- This patch does not change ERPNext install, backup, restore, SSL, firewall, health-monitoring, go-live, or dashboard summary behavior.
- Production validation should include verified tag-pinned update, `verify-toolkit`, Final QA option 1, creation of a support bundle, and `support-bundle-audit`.

## v1.1.72 minimal CI and release validation script

Purpose: add a repeatable release validation entrypoint and a minimal GitHub Actions workflow before larger structural changes.

Local validation:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
sha256sum -c SHA256SUMS
scripts/validate-release.sh

grep -n "v1.1.72" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
grep -n "validate-release.sh" README.md SECURITY.md RELIABILITY-PLAN.md TESTING.md CHANGELOG.md
grep -n "Release validation" .github/workflows/ci.yml

unzip -l erpnext-dev-toolkit-v1.1.72.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.72`.
- `sha256sum -c SHA256SUMS` reports `erpnext-dev.sh: OK`.
- `scripts/validate-release.sh` reports release validation complete.
- `.github/workflows/ci.yml` exists and runs `scripts/validate-release.sh`.
- Package contains no `GITHUB-UPDATE-v*.md` files.

Production validation scope:

- This patch does not change ERPNext install, backup, restore, SSL, firewall, health-monitoring, go-live, or dashboard behavior.
- Production validation can be limited to the verified tag-pinned update, `verify-toolkit`, and Final QA option 1.

## v1.1.71 verify-toolkit command

Purpose: add installed-file integrity reporting after the v1.1.70 tag-pinned checksum workflow. This patch adds a read-only `verify-toolkit` command and exposes it from the Production Operations > Support and Diagnostics menu.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
sha256sum -c SHA256SUMS
./erpnext-dev.sh verify-toolkit

grep -n "v1.1.71" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
grep -n "verify-toolkit" README.md SECURITY.md RELIABILITY-PLAN.md TESTING.md CHANGELOG.md
grep -n 'VERSION="v1.1.71"' README.md SECURITY.md

printf '10\n10\n\nb\nq\n' | sudo ./erpnext-dev.sh production-ops-wizard

unzip -l erpnext-dev-toolkit-v1.1.71.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.71`.
- `bash -n erpnext-dev.sh` passes.
- `sha256sum -c SHA256SUMS` reports `erpnext-dev.sh: OK`.
- `verify-toolkit` prints active/stable/CLI SHA256 details.
- When run beside the matching v1.1.71 `SHA256SUMS`, `verify-toolkit` reports `Active match OK`.
- Production Operations > Support and Diagnostics includes `10) Verify toolkit integrity`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Validation focus:

```text
Installed toolkit integrity reporting added.
Production operations behavior unchanged.
Runtime/install/backup/restore/SSL/firewall/monitoring/go-live logic unchanged.
```

---

## v1.1.70 SHA256 checksums and tag-pinned bootstrap documentation

Purpose: add checksum verification for the release script artifact and update bootstrap documentation to prefer pinned release tags rather than the mutable `main` branch. This patch does not change production runtime behavior.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
sha256sum -c SHA256SUMS
ls -1 SECURITY.md RELIABILITY-PLAN.md SHA256SUMS
grep -n "v1.1.70" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
grep -n "sha256sum -c SHA256SUMS" README.md SECURITY.md TESTING.md
grep -n 'VERSION="v1.1.70"' README.md SECURITY.md
unzip -l erpnext-dev-toolkit-v1.1.70.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.70`.
- `bash -n erpnext-dev.sh` passes.
- `sha256sum -c SHA256SUMS` reports `erpnext-dev.sh: OK`.
- README bootstrap examples use tag-pinned `VERSION="v1.1.70"` commands and run checksum verification before `sudo`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Validation focus:

```text
Release integrity documentation improved.
Production operations behavior unchanged.
Runtime/install/backup/restore/SSL/firewall/monitoring/go-live logic unchanged.
```

---

## v1.1.69 security and reliability planning documentation

Purpose: add repository-level security and reliability planning documents after the v1.1.67/v1.1.68 production dashboard validation sequence. This patch is documentation/planning only apart from the version bump; it does not change install, backup, restore, SSL, firewall, monitoring, go-live, or dashboard behavior.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version

ls -1 SECURITY.md RELIABILITY-PLAN.md

grep -n "v1.1.69" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
grep -n "Bootstrap trust" SECURITY.md
grep -n "Reliability roadmap" RELIABILITY-PLAN.md
grep -n "SECURITY.md" README.md CHANGELOG.md
grep -n "RELIABILITY-PLAN.md" README.md CHANGELOG.md

unzip -l erpnext-dev-toolkit-v1.1.69.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.69`.
- `bash -n erpnext-dev.sh` passes.
- `SECURITY.md` is present.
- `RELIABILITY-PLAN.md` is present.
- README, ROADMAP, CHANGELOG, TESTING, and PRODUCTION-VALIDATION mention the v1.1.69 planning patch.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Validation focus:

```text
No runtime behavior changed.
No install behavior changed.
No backup/restore behavior changed.
No firewall/SSL/monitoring behavior changed.
The patch records the next release-hardening priorities: checksum artifacts, tag-pinned bootstrap, verify-toolkit, minimal CI, and later modularization.
```

---

## v1.1.68 final v1.1.67 production validation documentation

Purpose: record the completed production validation of v1.1.67 dashboard navigation polish. This patch is documentation/validation only apart from the version bump; it does not change install, backup, restore, SSL, security, monitoring, go-live, or dashboard behavior.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
grep -n "v1.1.68" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
grep -n "20260709-071549" README.md PRODUCTION-VALIDATION.md CHANGELOG.md
grep -n "ERPNext Production Operations > Support and Diagnostics" README.md TESTING.md PRODUCTION-VALIDATION.md CHANGELOG.md
unzip -l erpnext-dev-toolkit-v1.1.68.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.68`.
- `bash -n erpnext-dev.sh` passes.
- Documentation records the final v1.1.67 production validation evidence.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Recorded production evidence:

```text
Production site: erp.flowmaya.com
Installed toolkit during validation: v1.1.67
Final QA: Release state OK, ready for production use
Final validation support bundle: /tmp/erpnext-dev-support-bundle-20260709-071549.tar.gz
Top-level dashboard footer: q) Quit only
Health Monitoring breadcrumb: ERPNext Production Operations > Health Monitoring
Support and Diagnostics breadcrumb: ERPNext Production Operations > Support and Diagnostics
```

---

## v1.1.67 production dashboard navigation polish validation

Purpose: validate the dashboard UX polish discovered during v1.1.66 production smoke testing. This patch changes navigation labels and submenu breadcrumbs only; it does not change install, backup, restore, SSL, security, monitoring, or go-live logic.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "production-ops-wizard"
printf 'q\n' | sudo ./erpnext-dev.sh production-ops-wizard
printf '6\nb\nq\n' | sudo ./erpnext-dev.sh production-ops-wizard
printf '10\nb\nq\n' | sudo ./erpnext-dev.sh production-ops-wizard
unzip -l erpnext-dev-toolkit-v1.1.67.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.67`.
- `bash -n erpnext-dev.sh` passes.
- The top-level Production Operations dashboard footer shows only `q) Quit`.
- Health Monitoring reached from the dashboard shows `ERPNext Production Operations > Health Monitoring`.
- Support and Diagnostics reached from the dashboard shows `ERPNext Production Operations > Support and Diagnostics`.
- Nested menus still show `b) Back` and return cleanly to the dashboard.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Production validation checklist after installing v1.1.67 on `erp.flowmaya.com`:

```bash
sudo erpnext-dev production-ops-wizard
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
```

In the dashboard, validate at minimum:

```text
Top-level footer shows only q) Quit
6) Health monitoring breadcrumb and Back behavior
10) Support and diagnostics breadcrumb and Back behavior
11) Final QA still opens
```

---

## v1.1.66 production operations dashboard validation

Purpose: validate the unified Production Operations dashboard without changing production state. The dashboard is an operator-experience layer over mature commands already validated in earlier releases.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "production-ops-wizard"
./erpnext-dev.sh --help | grep -n "production-ops-dashboard"
printf 'q\n' | sudo ./erpnext-dev.sh production-ops-wizard
printf 'q\n' | sudo ./erpnext-dev.sh operations-dashboard
unzip -l erpnext-dev-toolkit-v1.1.66.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.66`.
- `bash -n erpnext-dev.sh` passes.
- Help lists the unified operations dashboard command and alias.
- Dashboard opens with a current-state summary for runtime, install, HTTPS, security, backups, restore rehearsal, health monitoring, and go-live validation.
- Dashboard exits cleanly with `q`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Production validation checklist after installing v1.1.66 on `erp.flowmaya.com`:

```bash
sudo erpnext-dev production-ops-wizard
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
```

In the dashboard, validate at minimum:

```text
1) System health and readiness
6) Health monitoring
9) Go-live validation
10) Support and diagnostics
```

---

## v1.1.65 final v1.1.64 production validation documentation

Purpose: record the completed v1.1.64 production go-live evidence and prepare the roadmap for the next operator-experience milestone. This patch is documentation/validation only apart from the version bump.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
grep -n "v1.1.65" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
grep -n "Validated production state" README.md
grep -n "erp-flowmaya-v1.1.64-final-validated-20260709" README.md PRODUCTION-VALIDATION.md CHANGELOG.md
unzip -l erpnext-dev-toolkit-v1.1.65.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.65`.
- `bash -n erpnext-dev.sh` passes.
- Documentation records the final v1.1.64 production validation evidence.
- README reflects the validated snapshot, health monitoring, go-live record, and enhanced support bundle state.
- Roadmap names v1.1.66 unified production operations dashboard/menu as the next active milestone.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Recorded field evidence:

```text
Production site: erp.flowmaya.com
Production VPS: 65.109.221.4
Backup server: 65.109.220.250
Snapshot: erp-flowmaya-v1.1.64-final-validated-20260709
Go-live record: OK at 2026-07-09T06:27:12+00:00
Cloud firewall: confirmed
Cloudflare proxy/orange-cloud: confirmed
Cloudflare Full (strict): confirmed
Cloudflare Origin CA: confirmed
Restore rehearsal: recorded and login validated
Health timer: active
Health check: last recorded check OK during validation
Final evidence bundle: /tmp/erpnext-dev-support-bundle-20260709-062951.tar.gz
```

Support bundle evidence files expected from the validated v1.1.64 workflow:

```text
go-live-status.txt
health-check-status.txt
restore-rehearsal-status.txt
off-vm-backup-status.txt
backup-verify.txt
backup-status.txt
production-checklist.txt
```

---

## v1.1.64 go-live validation and evidence bundle validation

Purpose: record external go-live confirmations that the VM cannot fully verify by itself, and improve support bundles so they include redacted production evidence.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "go-live-record"
./erpnext-dev.sh --help | grep -n "go-live-status"
./erpnext-dev.sh --help | grep -n "cloud-firewall-checklist"
./erpnext-dev.sh --help | grep -n "cloudflare-checklist"
printf 'q
' | sudo ./erpnext-dev.sh final-qa
unzip -l erpnext-dev-toolkit-v1.1.64.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.64`.
- Help lists the new go-live validation commands.
- Final QA includes `9) Go-live validation status`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Production validation flow:

```bash
sudo erpnext-dev cloud-firewall-checklist
sudo erpnext-dev cloudflare-checklist
sudo erpnext-dev go-live-record
sudo erpnext-dev go-live-status
sudo erpnext-dev production-checklist
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
```

Expected production behavior:

- `go-live-record` saves `/etc/erpnext-dev/go-live-validation.env`.
- `go-live-status` reports snapshot, cloud firewall, Cloudflare proxy, Full (strict), and Origin CA status.
- `production-checklist` shows `Go-live validation OK` after all confirmations are recorded.
- Final QA includes go-live validation and remains `Release state OK` once the record is complete.
- Support bundle includes redacted evidence files such as `production-checklist.txt`, `backup-status.txt`, `off-vm-backup-status.txt`, `restore-rehearsal-status.txt`, `health-check-status.txt`, and `go-live-status.txt`.

## v1.1.63 health monitoring workflow validation

Purpose: add a smoother production monitoring workflow after backup, off-VM backup, and restore rehearsal validation are complete.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -nE "dashboard|health-snapshot|health-monitoring-wizard"
./erpnext-dev.sh --help | grep -n "health-check-run-now"
./erpnext-dev.sh --help | grep -n "health-check-journal"
scripts/test-health-snapshot.sh
printf 'q
' | sudo ./erpnext-dev.sh health-monitoring-wizard
printf 'q
' | sudo ./erpnext-dev.sh final-qa
sudo ./erpnext-dev.sh dashboard --json | grep -E '"overall_status"|"schema_version"'
unzip -l erpnext-dev-toolkit-v1.1.63.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.63`.
- Help lists the new health monitoring commands.
- Health monitoring wizard opens with options for running a check, configuring the timer, showing status, viewing journal output, disabling the timer, service recovery, and production checklist.
- Final QA includes `8) Health monitoring status`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Production follow-up validation:

```bash
sudo erpnext-dev health-monitoring-wizard
sudo erpnext-dev health-check
sudo erpnext-dev health-check-status
sudo erpnext-dev production-checklist
sudo erpnext-dev final-qa
```

Expected production behavior:

- `health-check` writes `/etc/erpnext-dev/health-check.state`.
- `health-check-status` shows the timer state and last recorded health check summary.
- `production-checklist` shows health timer as `OK active` after the timer is configured.
- Final QA remains `Release state OK` after monitoring is enabled.

## v1.1.62 final production QA documentation validation

Purpose: record the final field evidence after v1.1.61 successfully tracked the completed restore rehearsal and Final QA reported production readiness. This is a documentation/validation patch with no behavior changes.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "restore-rehearsal-status"
./erpnext-dev.sh --help | grep -n "restore-rehearsal-record"
./erpnext-dev.sh --help | grep -n "restore-rehearsal-report"
grep -n "Validated production state" README.md
grep -n "v1.1.62" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
unzip -l erpnext-dev-toolkit-v1.1.62.zip | grep "GITHUB-UPDATE" && echo "BAD" || echo "OK"
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.62`.
- README contains the validated production state section and menu anchor.
- Changelog, testing notes, roadmap, and production validation include v1.1.62.
- Package contains no `GITHUB-UPDATE-v*.md` file.

Recorded production field evidence:

```text
Production site: erp.flowmaya.com
Production VPS: 65.109.221.4
Backup server: 65.109.220.250
Restore rehearsal record: PASS
Final QA release summary: PASS
Production checklist: PASS
Backup verification: PASS
Support bundle creation: PASS
Support bundle path: /tmp/erpnext-dev-support-bundle-20260709-050725.tar.gz
```

Critical expected output from production Final QA:

```text
Restore rehearsal            OK      completed 2026-07-09T05:05:19+00:00; backup set 20260709_055928-erp_flowmaya_com; target local-vm/local-kvm-restore-vm; login validated
Release state                OK      ready for production use
Verification                 OK      backup files are readable; restore rehearsal is recorded
```

## v1.1.61 restore rehearsal record/status validation

Purpose: remove stale restore warnings after a successful disposable-VM restore rehearsal by recording the rehearsal result on the production VM.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "restore-rehearsal-status"
./erpnext-dev.sh --help | grep -n "restore-rehearsal-record"
./erpnext-dev.sh --help | grep -n "restore-rehearsal-report"
printf 'q
' | sudo ./erpnext-dev.sh final-qa
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.61`.
- Help lists `restore-rehearsal-status`, `restore-rehearsal-record`, and `restore-rehearsal-report`.
- Final QA includes restore rehearsal status.
- `backup-status`, `backup-verify`, `production-checklist`, and `release-readiness` show recorded restore rehearsal status after `/etc/erpnext-dev/restore-rehearsal.env` exists.

Validated field result after manual restore rehearsal:

```text
Temporary local restore key removed from backup server: PASS
Local restore VM SSH access to backup server after cleanup: denied as expected
Production ERPNext VPS off-VM backup status after cleanup: PASS
Production ERPNext VPS off-VM backup dry run after cleanup: PASS
Restore VM IP/address changed by network: treated as evidence only, not a trust dependency
```

## v1.1.60 restore rehearsal automation validation

Purpose: smooth and automate the off-VM restore rehearsal flow after proving that the manual local restore path works.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "restore-rehearsal-wizard"
./erpnext-dev.sh --help | grep -n "restore-key-setup"
./erpnext-dev.sh --help | grep -n "pull-off-vm-backup"
./erpnext-dev.sh --help | grep -n "backup-server-add-restore-key"
printf 'q
' | ./erpnext-dev.sh restore-rehearsal-wizard
printf 'q
' | ./erpnext-dev.sh off-vm-backup-wizard
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.60`.
- Help lists the new restore rehearsal commands.
- Restore rehearsal wizard opens without running destructive restore actions.
- Off-VM Backup menu includes restore rehearsal, restore-key setup, and backup-server temporary-key cleanup actions.
- `restore-full` offers the latest complete backup set before asking for individual filenames.
- Restore uses the local VM's MariaDB Bench Admin credential from `/home/frappe/erpnext-dev-credentials.txt` when available.

Validated manual path that informed this patch:

```text
Production ERPNext VPS: 65.109.221.4
Backup VPS: 65.109.220.250
Backup path: /mnt/HC_Volume_106276869/erpnext-backups/erp.flowmaya.com/
Local restore VM: 192.168.122.215
Restore site: erp.flowmaya.com
Backup set: 20260709_055928-erp_flowmaya_com
Result: restore-full completed successfully with files and post-restore maintenance
```

Post-restore browser/login validation and backup-server restore-key cleanup should be completed before marking the disaster-recovery drill fully closed.

## v1.1.59 off-VM backup validation and onboarding polish

Purpose: validate the real two-server off-VM backup result and the smoother backup-server wizard defaults.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "backup-server-setup"
./erpnext-dev.sh --help | grep -n "generate-off-vm-backup-key"
./erpnext-dev.sh --help | grep -n "off-vm-backup-guided-setup"
grep -n "Off-VM copy" erpnext-dev.sh
grep -n "backup_server_suggested_root" erpnext-dev.sh
grep -n "Do you already have the ERPNext VM public key ready" erpnext-dev.sh
printf 'q
' | ./erpnext-dev.sh off-vm-backup-wizard
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.59`.
- `backup-status` reports the actual off-VM status instead of always saying off-VM copy is still required.
- `production-checklist` marks off-VM backup as OK after a successful run and leaves restore rehearsal as the remaining production decision.
- `backup-server-setup` shows the ERPNext-side key generation command before prompting for backup server values.
- On a Hetzner backup server with `/mnt/HC_Volume_<id>` mounted, the suggested backup root becomes `/mnt/HC_Volume_<id>/erpnext-backups`.
- If the site/domain prompt is left blank and the generated public key has the standard `erpnext-offvm-backup-<site>` comment, the backup-server wizard infers the site/domain folder.

Validated real path:

```text
ERPNext VPS: 65.109.221.4
Backup VPS: 65.109.220.250
Backup user: erpbackup
Backup root: /mnt/HC_Volume_106276869/erpnext-backups
Site folder: erp.flowmaya.com
Rsync delete: false
Dry run: OK
Real run: OK
Production checklist: off-VM backup OK
```

Restore rehearsal on a disposable VM is still required before relying on the backup process for a real client production system.

## v1.1.58 guided off-VM backup setup validation

Purpose: validate the new two-server off-VM backup onboarding flow before relying on it for production.

Package checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "backup-server-setup"
./erpnext-dev.sh --help | grep -n "generate-off-vm-backup-key"
./erpnext-dev.sh --help | grep -n "off-vm-backup-guided-setup"
printf 'q\n' | ./erpnext-dev.sh off-vm-backup-wizard
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.58`.
- Off-VM Backup menu shows guided setup, key generation, rsync configuration, dry run, real run, status, disable config, and backup-server preparation.
- `backup-server-setup` is run only on a separate backup Linux server, not on the ERPNext application VM.

Production validation order:

1. On ERPNext VPS, run `sudo erpnext-dev generate-off-vm-backup-key`.
2. On backup server, run the GitHub bootstrap command ending in `backup-server-setup`.
3. Paste the ERPNext VM public key when prompted.
4. On ERPNext VPS, run `sudo erpnext-dev off-vm-backup-guided-setup` or `sudo erpnext-dev configure-rsync-backup-target`.
5. Run `sudo erpnext-dev off-vm-backup-dry-run`.
6. Run `sudo erpnext-dev run-off-vm-backup`.
7. Confirm `sudo erpnext-dev off-vm-backup-status` reports a successful last run.
8. Confirm copied files exist on the backup server under `/srv/erpnext-backups/<site>/`.

Do not enable rsync delete mode during first validation.

## v1.1.57 Cloudflare Origin CA validation record

This release records the successful real VPS validation of the Cloudflare Origin CA / Full (strict) SSL path after the v1.1.56 proxied-DNS gate fix.

Validated Cloudflare result:

```text
Toolkit path tested: public-vm-guided-setup + Production SSL Provider Wizard
Provider: Hetzner Cloud VPS
OS: Ubuntu 26.04 LTS
Domain: erp.flowmaya.com
Cloudflare DNS: proxied / orange-cloud
Public DNS result: Cloudflare edge IPs, not the origin VPS IP
Cloudflare SSL/TLS mode: Full (strict)
Origin SSL: Cloudflare Origin CA certificate + private key installed on the VM
HTTPS result: HTTP/2 200 through Cloudflare
External backend ports: 8000/9000 timed out from workstation
UFW: active after completing security hardening
Fail2Ban: sshd jail enabled
Scheduled local backups: timer active after completing backup schedule step
Support note: off-VM backup remains required before real go-live
```

Regression checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
grep -n "v1.1.57" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
grep -n "Cloudflare Origin CA / Full (strict): validated" README.md ROADMAP.md PRODUCTION-VALIDATION.md
grep -n "Cloudflare Origin CA validation record" CHANGELOG.md TESTING.md
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.57`.
- Documentation marks Let's Encrypt direct DNS and Cloudflare Origin CA Full strict as validated production HTTPS paths.
- Remaining required production work is still off-VM backup, real off-VM backup run, restore rehearsal, and optional health timer validation.
- If guided setup is interrupted after HTTPS, running `security-hardening-wizard` and `configure-backup-schedule` completes UFW, Fail2Ban, and scheduled backup validation.

## v1.1.56 Cloudflare proxied DNS guided setup check

Finding from real VPS testing: Cloudflare Origin CA can be installed and validated successfully, but public DNS returns Cloudflare edge IPs when the record is orange-cloud/proxied. The guided setup must not treat that as a hard DNS failure when the user intentionally chooses the Cloudflare Origin CA path.

Validation checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
grep -n "Continue with Cloudflare proxied" erpnext-dev.sh
grep -n "Cloudflare Origin CA path selected" erpnext-dev.sh
grep -n "v1.1.56" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
```

Expected behavior:

- DNS directly to VM continues to the default Let's Encrypt path.
- DNS returning Cloudflare edge IPs offers a safe choice instead of hard-stopping.
- Choosing Cloudflare Origin CA records the intended mode and continues, while reminding the user to verify the hidden Cloudflare origin A-record points to the VM IP.
- Non-interactive mode does not auto-accept proxied DNS because the toolkit cannot inspect Cloudflare dashboard origin settings without API credentials.

# Testing

## v1.1.55 Production VPS validation record and polish checks

This release records the successful fresh Hetzner VPS production validation and fixes polish issues discovered during that test.

Validated production result:

```text
Toolkit path tested: public-vm-guided-setup
Provider: Hetzner Cloud VPS
OS: Ubuntu 26.04 LTS
Domain: real public DNS record
HTTPS: Let’s Encrypt directly on the VM
Result: ERPNext browser login works over HTTPS
External backend ports: 8000/9000 timed out from workstation
UFW: active
Fail2Ban: sshd jail enabled
Scheduled local backups: timer active
Support bundle: created and reviewed
```

Regression checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "public-vm-guided-setup"
grep -n "explicit UFW DENY rule present" erpnext-dev.sh
grep -n "Backend validation URLs" erpnext-dev.sh
grep -n "Do not paste additional commands" README.md
grep -n "v1.1.55" CHANGELOG.md TESTING.md ROADMAP.md PRODUCTION-VALIDATION.md
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.55`.
- UFW status treats explicit `DENY` rules on backend ports as blocked, not as false allow warnings.
- Production ready/access output labels `:8000` URLs as troubleshooting/backend validation only.
- Docs record the successful production validation and the remaining off-VM backup / restore rehearsal work.
- Interactive commands such as `sudo erpnext-dev final-qa` are documented as commands to run by themselves.

Interactive command note:

```bash
sudo erpnext-dev production-checklist
sudo erpnext-dev final-qa
# Quit the menu with q, then run follow-up commands separately.
sudo erpnext-dev support-bundle
```

Do not paste follow-up commands after `sudo erpnext-dev final-qa` in the same shell block unless you intentionally want them to run after the menu exits.

## v1.1.54 Guided production SSL provider choice test

This focused release improves the production guided setup HTTPS step. Let's Encrypt remains the default when DNS resolves directly to the VPS, but the guided path now offers an explicit choice to open the SSL provider wizard for alternate providers such as Cloudflare Origin CA.

Regression checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "public-vm-guided-setup"
grep -n "Choose another SSL provider" erpnext-dev.sh
grep -n "Cloudflare Origin CA" README.md
grep -n "v1.1.54" CHANGELOG.md
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.54`.
- `public-vm-guided-setup` remains available and remains the production README bootstrap command.
- Production guided HTTPS Step 7 recommends Let's Encrypt by default when DNS points directly to the VM.
- The same step can open the SSL provider wizard for Cloudflare Origin CA / advanced SSL provider selection.
- Guided setup stops instead of continuing if production HTTPS is not verified after the SSL choice.

## v1.1.52 Production guided setup workflow test

This focused release keeps the existing Public VM menu, but adds a true guided production command for the README production bootstrap path. The goal is to make the production VPS path feel like the local VM quickstart: the user follows an ordered wizard instead of manually choosing menu items 2, 3, 4, 6, 7, and so on.

Regression checks:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "public-vm-guided-setup"
grep -n "public-vm-guided-setup" README.md
grep -n "public-vm-guided-setup" PRODUCTION-VALIDATION.md
grep -n "v1.1.52" CHANGELOG.md
printf 'q\n' | MENU_TERMINAL_COLS=100 ./erpnext-dev.sh public-vm-quickstart
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.52`.
- `public-vm-guided-setup` is listed in help and accepted by command dispatch.
- README production VPS bootstrap command uses `public-vm-guided-setup`.
- `public-vm-quickstart` still opens the manual Public VM menu.
- The guided production flow includes domain, DNS readiness, external cloud firewall/snapshot gate, install, backup checkpoint, HTTPS, production security profile, scheduled backups/off-VM backup review, optional apps, Final QA, support bundle, and post-validation snapshot reminder.

## v1.1.51 Production VPS validation planning test

This is a documentation and handoff release. It closes the local VM validation stage and defines the next required production-validation environment.

Local VM stage result:

```text
LOCAL VM VALIDATION: PASS
Backup/restore: PASS
Scheduled backups: PASS
Retention dry run: PASS
Maintenance checks: PASS
Final QA/support bundle: PASS
```

Production validation must use a fresh disposable VPS and a real test subdomain. A local `.test` VM cannot validate public DNS, Let's Encrypt HTTP challenges, cloud firewall behavior, Cloudflare proxy modes, or external exposure checks.


### SSH host key reset during repeated VPS tests

When a disposable VPS is rebuilt but reuses the same IP or domain, SSH may show `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`. This is expected only after an intentional rebuild. Remove the old local known-host entry from the admin workstation before reconnecting:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R "VPS_PUBLIC_IP"
ssh-keygen -f ~/.ssh/known_hosts -R "erp.example.com"
```

Then reconnect and accept the new fingerprint only after confirming the server is the rebuilt test VPS.

Required production-validation environment:

```text
Ubuntu 24.04 LTS or Ubuntu 26.04 LTS VPS
Public IPv4
Real test subdomain, for example erp-test.example.com
DNS A record: erp-test.example.com -> VPS_PUBLIC_IP
Cloud firewall control
Snapshot capability
SSH access from admin IP
```

Baseline cloud firewall before install:

```text
22/tcp    allow from admin IP only
80/tcp    allow public
443/tcp   allow public
8000/tcp  block public
9000/tcp  block public
```

Recommended production-validation order:

```text
1) Create fresh disposable VPS
2) Point test subdomain A record to VPS public IP
3) Configure cloud firewall baseline
4) Take initial clean snapshot
5) Install toolkit CLI
6) Run Public VM guided setup
7) Apply/check production firewall profile
8) Run Let's Encrypt production HTTPS
9) Verify public HTTPS externally
10) Confirm 8000/9000 are not publicly reachable
11) Confirm Fail2Ban sshd jail status
12) Create and verify backups
13) Configure scheduled local backups
14) Review off-VM backup plan or configure test rsync target
15) Run production checklist
16) Run Final QA
17) Take named post-validation snapshot
```

Readiness ratings after v1.1.50 local testing and before the production VPS test:

| Area | Rating | Status |
| --- | ---: | --- |
| Local VM quickstart and local HTTPS | 9.5/10 | Passed; release-candidate for local/dev use |
| Optional app installation/status | 9.0/10 | Passed on the curated app batch in local VM |
| Local backup, restore, scheduled backup, retention | 9.0/10 | Passed locally; restore still must be rehearsed separately for production |
| Maintenance and Final QA menus | 8.8/10 | Passed locally; production warning rows are expected until VPS validation |
| Public VPS guided setup | 6.5/10 | Implemented, not yet real-VPS validated in this stage |
| Let's Encrypt production HTTPS | 6.5/10 | Implemented, requires real domain validation |
| Cloudflare Origin CA / Full strict | 6.0/10 | Implemented/planned path, requires separate Cloudflare test |
| Production firewall + Fail2Ban | 6.5/10 | UFW logic tested locally; cloud firewall and Fail2Ban need VPS validation |
| Off-VM backup | 5.5/10 | Workflow exists; needs real remote-target validation |
| Health-check timer / production monitoring | 5.5/10 | Available, not yet production-stage validated |
| Overall local readiness | 9.3/10 | Passed |
| Overall production readiness before VPS validation | 6.5/10 | Production-candidate, not final production-ready |

Regression checks for this documentation release:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh release-notes-guide
grep -n "Production validation stage" README.md
grep -n "Production VPS validation" TESTING.md
grep -n "PRODUCTION-VALIDATION" README.md
test -f PRODUCTION-VALIDATION.md
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.51`.
- Release notes explain that production VPS validation is the next stage.
- README links to `PRODUCTION-VALIDATION.md`.
- TESTING includes the production VPS validation plan and readiness matrix.
- ROADMAP marks local VM validation as closed and production VPS validation as the active next stage.

## v1.1.50 Local SSL firewall-guidance regression test

After updating the VM to v1.1.50, run:

```bash
erpnext-dev version
sudo erpnext-dev verify-local-ssl
```

Expected results:

- Version prints `ERPNext Developer Toolkit v1.1.50`.
- `verify-local-ssl` passes when local HTTPS is configured.
- If the exact Local VM firewall profile is active, the next-step guidance says `Local VM security profile: already active`.
- If UFW is active but the exact profile cannot be confirmed, the next-step guidance says `Local firewall: UFW is active` and does not tell the user to apply the profile as a required next step.
- The command must not fall through to the old unconditional recommendation to apply the Local VM security profile when UFW is active.

## v1.1.49 Final QA and local-stage polish regression test

After updating the VM to v1.1.49 or later, run:

```bash
erpnext-dev version
sudo erpnext-dev release-notes-guide
sudo erpnext-dev scheduled-backup-status
sudo erpnext-dev backup-schedule-status
```

Expected results:

- Release notes draft heading uses the current toolkit version.
- Release notes distinguish local VM validated paths from production paths that still require testing.
- `scheduled-backup-status` and `backup-schedule-status` both show the scheduled backup status.

To test disable UX without deleting backups:

```bash
sudo erpnext-dev disable-backup-schedule
sudo erpnext-dev backup-schedule-status
```

Expected results:

- Existing backup files are not deleted.
- If no timer/service is configured, the disable screen reports that there is nothing to disable.
- If a timer exists, it is stopped/disabled and status points back to schedule status/configuration.

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
The lock file is private (dir mode 0700, symlink refused): root uses /run/lock/erpnext-dev/toolkit.lock; a normal user uses $XDG_RUNTIME_DIR/erpnext-dev/toolkit.lock, falling back to /tmp/erpnext-dev-<uid>-locks/toolkit.lock.
```

## Package file check

The release package should contain the canonical toolkit file `erpnext-dev.sh`.

```bash
unzip -l erpnext-dev-toolkit-v1.1.32.zip | grep "erpnext-dev.sh"
```

Expected:

```text
erpnext-dev.sh
```

## CLI install / repair validation

Run on a VM or disposable test machine:

```bash
VERSION="v1.1.70"
curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/${VERSION}/erpnext-dev.sh"
curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/${VERSION}/SHA256SUMS"
sha256sum -c SHA256SUMS
chmod +x erpnext-dev.sh
sudo ./erpnext-dev.sh install-cli
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

Run inside a fresh Ubuntu 24.04 or 26.04 LTS VM (the only supported targets):

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates
VERSION="v1.1.70"
curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/${VERSION}/erpnext-dev.sh"
curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/${VERSION}/SHA256SUMS"
sha256sum -c SHA256SUMS
chmod +x erpnext-dev.sh
sudo ./erpnext-dev.sh install-preflight
```

Expected:

```text
The VM passes preflight, or prints INSTALL BLOCKED with clear CPU/RAM/disk/tmp reasons.
The toolkit installs /opt/erpnext-dev/erpnext-dev.sh and /usr/local/bin/erpnext-dev after sudo execution.
```

## Fresh local VM install validation

Run inside a fresh local VM:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get install -y curl ca-certificates
VERSION="v1.1.70"
curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/${VERSION}/erpnext-dev.sh"
curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-toolkit/${VERSION}/SHA256SUMS"
sha256sum -c SHA256SUMS
chmod +x erpnext-dev.sh
sudo ./erpnext-dev.sh local-dev-quickstart
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
sudo erpnext-dev --help | grep -E "credentials-menu|credentials-show|credentials-file-status|credentials-secure|credentials-delete|reset-admin-password"
printf 'b\n' | sudo erpnext-dev credentials-menu
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
grep -n "sudo "\$tmp" public-vm-guided-setup" README.md
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
