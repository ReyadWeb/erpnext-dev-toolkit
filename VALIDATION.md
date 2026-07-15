# Combined go-live validation runbook

**Applies to:** v1.14.0+ · **Scope:** one end-to-end go-live test that validates
**both** deployment engines on real infrastructure:

- **Native engine** — ERPNext/Frappe installed directly on a fresh Ubuntu/Debian VPS.
- **Docker production engine** — the production `compose.yaml` stack (`DOCKER_MODE=production`).

This is the "full test" gate before declaring a release production-ready in the
field. CI already gates every release (native `install-smoke`, Docker dev
`docker-install-smoke`, and Docker `docker-production-smoke` are all hard gates);
this runbook proves the same lifecycle on a **real VPS + real domain**, which CI
cannot do (no public DNS, no ACME, no off-site targets).

> Execution is a manual operator task — it provisions real cloud resources and a
> real domain. Follow it verbatim and record evidence in the sign-off table at
> the end. Nothing in this file runs automatically.

---

## 0. Prerequisites and safety

| Item | Requirement |
|------|-------------|
| VPS | Fresh **Ubuntu 24.04 / 26.04 LTS** or **Debian 13**, 2 vCPU / 4 GB+ RAM, public IPv4 |
| Domain | A real domain with two records you control, e.g. `erp.example.com` (native) and `erp-docker.example.com` (Docker production) |
| DNS | `A` records pointing each hostname at the VPS public IP; confirm propagation (`dig +short erp.example.com`) before HTTPS steps |
| Cloud firewall | Allow inbound `22`, `80`, `443` only; take a **provider snapshot** before you start so you can roll back the whole VM |
| Off-site target | An SSH host for rsync (`user@host:/path`) **and/or** a configured `rclone` remote (`rclone config`) for object storage |
| Access | `sudo` on the VPS; a browser to confirm the login page renders over HTTPS |

Recommended: run native and Docker production on **separate VPSs** (cleanest,
no port contention). If you must reuse one VPS, run Phase A to completion, capture
its evidence, then tear it down before Phase B, since both bind `:80/:443`.

### 0.1 Integrity (do this first, on the VPS)

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates tar
VERSION="v1.14.0"
BASE="https://github.com/ReyadWeb/erpnext-dev-toolkit/releases/download/${VERSION}"
curl -fsSLO "${BASE}/erpnext-dev-${VERSION}.tar.gz"
tar -xzf "erpnext-dev-${VERSION}.tar.gz" && cd "erpnext-dev-${VERSION}"
sha256sum -c SHA256SUMS
sudo ./erpnext-dev.sh verify-signature   # expect GOODSIG
sudo ./erpnext-dev.sh verify-toolkit     # expect all modules OK
```

**Pass:** checksums match, `GOODSIG` from the release signing key, all modules OK.

---

## Phase A — Native engine go-live

Run on the native VPS. Use the hostname you pointed at it (examples use
`erp.example.com`).

```bash
export SITE_NAME=erp.example.com
sudo -E ./erpnext-dev.sh install-preflight
sudo -E ./erpnext-dev.sh public-vm-guided-setup    # guided; or public-vm-quickstart
sudo -E ./erpnext-dev.sh engine-status              # expect: Engine = Native (VM)
```

### A1. Runtime and access
```bash
sudo -E ./erpnext-dev.sh production-runtime-status  # supervisor RUNNING, no 'bench start'
sudo -E ./erpnext-dev.sh verify-access
```
**Pass:** site reachable on the hostname; production runtime under supervisor.

### A2. HTTPS
```bash
sudo -E ./erpnext-dev.sh production-ssl-wizard       # Let's Encrypt or Cloudflare Origin
sudo -E ./erpnext-dev.sh production-ssl-status
```
**Pass:** `https://erp.example.com` loads a styled, working login; valid chain.

### A3. Diagnostics (engine-agnostic contract verb)
```bash
sudo -E ./erpnext-dev.sh engine-diagnostics --plain  # or --json for machine-readable
```
**Pass:** all critical checks OK; no secrets in the output.

### A4. Backup, verify, restore (engine-agnostic)
```bash
sudo -E ./erpnext-dev.sh backup-files
sudo -E ./erpnext-dev.sh backup-verify
sudo -E ./erpnext-dev.sh engine-restore              # native restore flow (guided)
```
**Pass:** a complete, verified backup set exists; restore completes cleanly.

### A5. Off-site shipment — pick one or both
```bash
# rsync off-VM
sudo -E ./erpnext-dev.sh configure-rsync-backup-target
sudo -E ./erpnext-dev.sh off-vm-backup-dry-run
sudo -E ./erpnext-dev.sh run-off-vm-backup
sudo -E ./erpnext-dev.sh off-vm-backup-status

# object storage (rclone) — engine-agnostic, native parity (post-v1.11.0)
sudo -E ./erpnext-dev.sh configure-object-backup
sudo -E ./erpnext-dev.sh object-backup-dry-run
sudo -E ./erpnext-dev.sh object-backup
sudo -E ./erpnext-dev.sh object-status               # expect: last OK, rclone check verified
```
**Pass:** artifacts land off the VM and, for object storage, `rclone check` verifies them.

### A6. Upgrade / rollback surface (contract verbs, non-destructive to review)
```bash
sudo -E ./erpnext-dev.sh update-preflight            # read-only readiness
# sudo -E ./erpnext-dev.sh engine-upgrade            # guarded safe update (optional; backup first)
# sudo -E ./erpnext-dev.sh engine-rollback           # only if an upgrade needs reverting
```
**Pass:** preflight reports readiness; contract verbs resolve for the native engine.

---

## Phase B — Docker production go-live

Run on the Docker VPS (or the same VPS after Phase A teardown). Uses the
production `compose.yaml` path with immutable pins.

```bash
export DEPLOYMENT_ENGINE=docker
export DOCKER_MODE=production
export SITE_NAME=erp-docker.example.com
sudo -E ./erpnext-dev.sh docker-production-setup      # provisions compose.yaml + overrides + pins
sudo -E ./erpnext-dev.sh engine-status                # Engine = Docker, mode = production, shows pins
```
**Pass:** stack up; `engine-status` shows `frappe_docker` SHA + ERPNext image digest.

### B1. Production HTTPS (Traefik)
```bash
sudo -E ./erpnext-dev.sh docker-https-wizard          # Let's Encrypt or Cloudflare Origin CA
sudo -E ./erpnext-dev.sh docker-https-status
```
**Pass:** `https://erp-docker.example.com` loads a styled, working login.

### B2. Production exposure guardrail
```bash
sudo -E ./erpnext-dev.sh docker-production-exposure
```
**Pass:** only intended ports are published; guardrail reports no unexpected exposure.

### B3. Backup, verify, restore rehearsal (DR — the P3 chain)
```bash
sudo -E ./erpnext-dev.sh backup-files                 # durable host artifact (routes to Docker)
sudo -E ./erpnext-dev.sh backup-verify                # gzip/tar/json + SHA256SUMS integrity
sudo -E ./erpnext-dev.sh docker-restore-rehearsal     # non-destructive restore to a throwaway site
sudo -E ./erpnext-dev.sh docker-restore-evidence      # show recorded rehearsal evidence
```
**Pass:** durable artifact verified; rehearsal restores to a throwaway site and records evidence.

### B4. Off-site shipment — pick one or both
```bash
sudo -E ./erpnext-dev.sh docker-offvm-backup          # rsync durable artifacts off-VM
sudo -E ./erpnext-dev.sh docker-offvm-status

sudo -E ./erpnext-dev.sh configure-object-backup      # engine-agnostic; routes to Docker
sudo -E ./erpnext-dev.sh object-backup
sudo -E ./erpnext-dev.sh object-status
```
**Pass:** artifacts land off the VM; object-storage upload verified with `rclone check`.

### B5. Diagnostics + upgrade/rollback surface
```bash
sudo -E ./erpnext-dev.sh engine-diagnostics --plain
sudo -E ./erpnext-dev.sh engine-upgrade               # container-native immutable re-deploy guidance
sudo -E ./erpnext-dev.sh engine-rollback              # redeploy previous pin / restore guidance
```
**Pass:** diagnostics clean; upgrade/rollback verbs print the container-native path.

---

## 2. Cross-engine contract parity

Confirm both engines answered the **same** lifecycle contract during the test:

| Verb | Native | Docker production |
|------|--------|-------------------|
| `engine-status` | A0 | B0 |
| `engine-diagnostics` | A3 | B5 |
| `backup-files` + `backup-verify` | A4 | B3 |
| `engine-restore` / restore rehearsal | A4 | B3 |
| off-VM + `object-backup` / `object-status` | A5 | B4 |
| `engine-upgrade` / `engine-rollback` | A6 | B5 |

**Pass:** every row exercised on both engines with the documented result.

---

## 3. Evidence bundle

Collect, per engine, and attach to the go-live record:

```bash
sudo -E ./erpnext-dev.sh engine-diagnostics --json > diagnostics-<engine>.json
sudo -E ./erpnext-dev.sh support-bundle                 # redacted support archive
sudo -E ./erpnext-dev.sh go-live-record                 # records go-live sign-off
sudo -E ./erpnext-dev.sh go-live-status
```

Keep: the two `diagnostics-*.json`, both support bundles, HTTPS screenshots for
each hostname, `object-status` / `off-vm-backup-status` output, and the
`docker-restore-evidence` record.

---

## 4. Go-live sign-off

| # | Check | Native | Docker prod |
|---|-------|:------:|:-----------:|
| 1 | Integrity: `verify-signature` GOODSIG + `verify-toolkit` OK | ☐ | ☐ |
| 2 | Install + runtime healthy | ☐ | ☐ |
| 3 | Site reachable on hostname | ☐ | ☐ |
| 4 | HTTPS valid + styled login | ☐ | ☐ |
| 5 | `engine-diagnostics` clean | ☐ | ☐ |
| 6 | Backup created + verified | ☐ | ☐ |
| 7 | Restore / restore rehearsal succeeded | ☐ | ☐ |
| 8 | Off-site (rsync and/or object storage) verified | ☐ | ☐ |
| 9 | Exposure guardrail / firewall correct | ☐ | ☐ |
| 10 | Upgrade/rollback contract verbs behave as documented | ☐ | ☐ |
| 11 | Evidence bundle collected | ☐ | ☐ |

**Abort / rollback criteria:** if any of checks 1–4 fail, stop and restore the
provider snapshot. For checks 6–8 failures, do not declare go-live until backups
are proven recoverable (restore or rehearsal must pass). Record the outcome with
`go-live-record`.

---

See [`TESTING.md`](TESTING.md) for the broader per-feature test matrix and
hermetic checks, and [`DEPLOYMENT-ARCHITECTURE.md`](DEPLOYMENT-ARCHITECTURE.md)
§5 for the engine contract these commands implement.

---

## 5. Example provider sign-off (fictional / redacted)

Use this as a template when filing a [compatibility report](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/new?template=compatibility-report.yml)
or a Discussions → Show and tell installation report. **Never include secrets.**

- **Provider:** DigitalOcean
- **Plan:** Basic Droplet (2 vCPU / 4 GB RAM)
- **OS:** Debian 13
- **Engine:** Native
- **Off-site:** Object storage via rclone (provider Spaces / S3-compatible)
- **Toolkit:** v1.14.0+
- **Outcome:** PASS (example only)

| # | Check | Result |
|---|-------|:------:|
| 1 | Integrity: `verify-signature` GOODSIG + `verify-toolkit` OK | PASS |
| 2 | Install + runtime healthy | PASS |
| 3 | Site reachable on hostname | PASS |
| 4 | HTTPS valid + styled login | PASS |
| 5 | `engine-diagnostics` clean | PASS |
| 6 | Backup created + verified | PASS |
| 7 | Restore / restore rehearsal succeeded | PASS |
| 8 | Off-site (rsync and/or object storage) verified | PASS |
| 9 | Exposure guardrail / firewall correct | PASS |
| 10 | Upgrade/rollback contract verbs behave as documented | PASS |
| 11 | Evidence bundle collected | PASS |
