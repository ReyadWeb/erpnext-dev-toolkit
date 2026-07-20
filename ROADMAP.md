# ERPNext Developer Toolkit — Roadmap

**Current release:** v1.19.11 (July 2026)  
**Theme for v1.18–v1.23:** security closure → local IP stability → repo governance → asset-readiness gaps → guarded auto-healing (v1.19+) → panel readiness.  
**Next up:** field-validate the v1.19.10 frontend-asset closure and v1.19.11 page UX, then continue to v1.20.0.  
**Deferred:** v1.20.0 External Watchdog until v1.19.10 + v1.19.11 are field-validated.

**Public roadmap board:** https://github.com/users/ReyadWeb/projects/3  
**Milestones / issues:** tracked on GitHub so progress stays visible (see [docs/ROADMAP-BOARD.md](docs/ROADMAP-BOARD.md)).

**Full history:** [`CHANGELOG.md`](CHANGELOG.md) · **Security:** [`SECURITY.md`](SECURITY.md) · **Health model:** [`docs/HEALTH-ARCHITECTURE.md`](docs/HEALTH-ARCHITECTURE.md) · **Testing:** [`TESTING.md`](TESTING.md)

---

## Current baseline

The toolkit is past “installer” status. It is a **single-node ERPNext/Frappe lifecycle and operations platform** with:

| Area | Status |
|------|--------|
| Native + Docker engines | Shipped (same CLI) |
| Local + production HTTPS | Shipped (separate menus) |
| Backup / off-VM / restore rehearsal | Shipped |
| Release signing + gated publish | Shipped |
| Operations dashboard + monitoring | Shipped (v1.16–v1.17; **monitor-only**) |
| CLI boxed menus / page lifecycle / status strip | Shipped (through v1.19.11) |
| Browser wait-ready asset probe | Shipped (v1.15.1 / v1.17.6 core gate) |
| Root-run `health.env` safety | Shipped (v1.18.0 allowlist parser + ownership gate) |
| Off-VM strict SSH host keys | Shipped (v1.18.0; opt-in strict mode) |
| CI secret / Scorecard / shfmt gates | Shipped (v1.18.0) |
| Local VM Stable IP CLI + docs | Shipped (v1.18.1) |
| Repo governance / Scorecard P0 | Shipped (v1.18.2) |
| Frontend asset verify/wait/repair | Shipped (v1.18.3) |
| Guarded auto-healing | Shipped (v1.19.0 MVP + v1.19.1 hardening) |

### Maturity (single-admin dedicated VM)

| Use case | Rating | Notes |
|----------|--------|-------|
| Local dev VM | **9.5 / 10** | Field-tested; Stable IP CLI + docs in v1.18.1 |
| Public VPS production | **9.4 / 10** | CI-proven; broader provider evidence still in progress |
| Supply chain / release trust | **9.6 / 10** | Signed releases, `release-signing` env, Actions SHA pins |
| Root-run config safety | **9.5 / 10** | Allowlist parser; no sourced `health.env` (v1.18.0) |
| Overall | **~9.5 / 10** | Enterprise-candidate; next gains from asset readiness + real VPS evidence |

**Positioning:** Native engine = Supervisor/Nginx on Debian-family hosts. Docker engine = upstream `frappe_docker` behind the same `erpnext-dev` CLI. Architecture: [`DEPLOYMENT-ARCHITECTURE.md`](DEPLOYMENT-ARCHITECTURE.md).

---

## Roadmap principles

1. **Secure by default** — root-run config is data, never executable shell.
2. **No false readiness** — do not claim browser-ready until HTML + CSS/JS assets pass.
3. **No destructive automation without guardrails** — healing stays off until modes, cooldowns, and lockouts exist.
4. **Native + Docker parity** for lifecycle operations that operators rely on.
5. **Human CLI + machine JSON** — panel/agent consumers must not scrape terminal text.
6. **Docs match shipped behavior** — no screenshots or promises for unreleased features.

---

## Shipped foundation (through v1.19.11)

Summary of what the active roadmap builds on. Detailed notes live in [`CHANGELOG.md`](CHANGELOG.md).

| Phase | Focus | Status |
|-------|--------|--------|
| **v1.10–v1.12** | Multi-engine contract; Docker prod; rebrand; object-storage parity; hard Docker CI gates | **implemented** |
| **v1.13.0** | Debian native CI coverage (no GitHub Debian runner today) | planned (field-validated) |
| **v1.14.0** | Community polish (CONTRIBUTING, CoC, templates, DEVELOPMENT/RELEASE-PROCESS) | **implemented** |
| **v1.15.x** | Guided UX; local HTTPS + asset probe; Debian parity; credentials menu; Firefox NSS helper | **implemented** |
| **v1.16.0** | Canonical health snapshot + Operations Dashboard | **implemented** |
| **v1.17.0–.2** | Incidents, would-heal dry-run, alerts, OpenMetrics; observe + release publish hardening | **implemented** |
| **v1.17.3–.9** | CLI menu UI, dashboard boxes, wait-ready asset gate, boxed submenus, shorter labels | **implemented** |

**CI matrix (intentional gaps):**

| Gap | Stance | Next step |
|-----|--------|-----------|
| Ubuntu 26.04 | Canary only (weekly/manual); omitted from tag release checks | Fix asset/build canary failure, then hard-gate on release |
| Debian 13 native | Field-validated | Disposable VPS validation and/or self-hosted runner |

---

## Active roadmap (v1.18–v1.23)

Sequence is intentional: **close root security → stabilize local identity → finish readiness gaps → then heal**.

```text
v1.18.0  Security hardening closure
v1.18.1  Local VM stable IP foundation
v1.18.2  Repository security & governance hardening
v1.18.3  Frontend asset readiness gaps
v1.19.0  Guarded auto-healing MVP
v1.19.1  Auto-healing hardening
v1.19.8  Browser asset consistency closure (P0)
v1.19.9  Bare HTTP port-80 browser path (P0)
v1.19.10 Frappe-aligned frontend assets (P0)
v1.19.11 CLI page UX architecture (P1)           ← current
v1.20.0  External watchdog foundation            ← deferred until 1.19.10+1.19.11
v1.21.0  CloudPanel / agent API foundation
v1.22.0  Real VPS validation matrix (bounded)
v1.23.0  Documentation and launch polish
```

### v1.18.0 — Security Hardening Closure

**Status:** Shipped as **v1.18.0**.

**Goal:** Close remaining root-toolkit security gaps **before** enabling real auto-healing.

**Scope**
- Replace unsafe config sourcing with a **strict allowlist parser** for `/etc/erpnext-dev/health.env` (and the same pattern for future healing policy files).
- Enforce **root ownership** and safe modes (`600`/`640`) on health/config files.
- Validate webhook URLs (HTTPS unless explicitly allowed for local test) and alert policy values.
- Replace remaining `eval` nameref array patterns with safer Bash, or justify with scoped comments + tests.
- Hermetic **risky-shell-pattern** tests (malicious `health.env` fixture must be ignored).
- CI: secret scanning (Gitleaks or TruffleHog), OpenSSF Scorecard, pinned-Actions check, `shfmt` check — land in this release when CI time stays reasonable; otherwise ship parser + host-keys first and scanners immediately after.
- **Strict off-VM SSH host-key mode** (production path):
  - `off-vm-trust-host-key` / `off-vm-verify-host-key` / `off-vm-strict-host-key-enable`
  - `StrictHostKeyChecking=yes` + `UserKnownHostsFile=/etc/erpnext-dev/off-vm-known_hosts`
  - First-setup may stay convenient; production docs push strict mode.

**Allowlisted `health.env` keys (initial set)**  
`HEALTH_ALERT_ON`, `HEALTH_ALERT_WEBHOOK_URL`, `HEALTH_ALERT_WEBHOOK_TIMEOUT_SEC`, `HEALTH_CONSECUTIVE_FAIL_THRESHOLD`, `HEALTH_COOLDOWN_SEC`, `HEALTH_HISTORY_RETENTION_DAYS`, `HEALTH_INCIDENT_RETENTION_DAYS` (extend only via explicit parser updates).

**Acceptance**
- [x] No root-run config file is sourced as shell code.
- [x] Malicious `health.env` fixture is ignored safely.
- [x] `eval` usage removed or explicitly justified + tested.
- [x] Off-VM strict host-key mode documented and hermetically tested.
- [x] Secret scanner + Scorecard workflows present (or tracked follow-up PR in the same minor window).

---

### v1.18.1 — Local VM Stable IP Foundation

**Status:** Shipped as **v1.18.1**.

**Goal:** Keep `erp.test` / local HTTPS / host mappings reliable when the guest IP changes after reboot.

**Lean CLI** (avoid one binary per hypervisor):

| Command | Purpose |
|---------|---------|
| `local-ip-status` | Current IP, DHCP vs static signals, saved mapping |
| `local-ip-plan` | Explain stable-IP options for this host |
| `local-ip-drift-check` | Saved IP vs current IP mismatch |
| `local-static-ip-wizard` | Guest Netplan static IP with backup |
| `local-static-ip-rollback` | Restore prior Netplan |
| (existing) hosts helper | Print correct host `/etc/hosts` repair command |

**Menu:** Local VM Network / Stable IP — status, plan, drift, hosts command, wizard, rollback, plus **doc-backed** guide entries for KVM, VirtualBox, Hyper-V, VMware/Proxmox (open `docs/LOCAL-VM-STABLE-IP.md` sections; no separate CLI per platform).

**Docs:** `docs/LOCAL-VM-STABLE-IP.md` — why `erp.test` breaks, platform recommendations, Netplan static IP, hosts repair, troubleshooting, rollback. Wire a checkpoint into local quickstart / guided setup.

**Acceptance**
- [x] Operator can see whether the guest IP looks stable or dynamic.
- [x] Drift between saved and current IP is detected.
- [x] Correct host `/etc/hosts` repair command is printed.
- [x] Local quickstart warns about dynamic IP risk.
- [x] Docs cover KVM, VirtualBox, Hyper-V, VMware/Proxmox.
- [x] Static IP wizard creates a backup and rollback path.

---

### v1.18.2 — Repository Security & Governance Hardening

**Status:** Shipped as **v1.18.2** (epic [#82](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/82)).

**Goal:** Close OpenSSF Scorecard P0/P1 gaps in repository governance and CI token scope before more feature work. Does **not** weaken the signed-release / `release-signing` path.

**Scope**
- Least-privilege [`release.yml`](.github/workflows/release.yml): workflow `contents: read`; publish job keeps `contents: write`.
- Tighten classic `main` branch protection (expanded required CI checks); document Scorecard `enforce_admins` / Code-Review solo-maintainer gaps.
- Expand [`.github/CODEOWNERS`](.github/CODEOWNERS) for security/release-sensitive paths (no hard code-owner gate until a second maintainer).
- Dedicated [`security-analysis.yml`](.github/workflows/security-analysis.yml): CodeQL for GitHub Actions + hermetic adversarial-input suite (not Scorecard fuzz ecosystems).
- Document accepted Scorecard findings in [`SECURITY.md`](SECURITY.md).

**Acceptance**
- [x] Workflow-level `release.yml` is `contents: read`; only `publish` is `write`.
- [x] `main` requires PR + expanded CI checks; force-push/delete blocked.
- [x] CODEOWNERS covers security/release-sensitive paths.
- [x] `security-analysis.yml` runs on PR/`main`; adversarial suite green in validate-release.
- [x] Frontend Asset Readiness epic tracked as **v1.18.3**.
- [x] Signed v1.18.2 published; Scorecard findings reclassified.

---

### v1.18.3 — Frontend Asset Readiness Gaps

**Status:** Shipped as **v1.18.3**.

**Goal:** Close remaining “unstyled login after ready” holes. **Core gate already shipped** in v1.15.1 / v1.17.6 (`probe_login_static_asset`, `wait_for_erpnext_ready`). Epic [#59](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/59).

**Scope (gaps only — not a greenfield rewrite)**
- Explicit commands: `verify-frontend-assets`, `wait-frontend-assets`, `repair-frontend-assets`.
- Ensure the same probe runs on optional-app install, upgrade, and restore paths that still skip it.
- Tighten checks where needed (non-empty CSS/JS body, clear wait messaging).
- Repair path: rebuild assets, clear cache, reload services, re-verify.

**Acceptance**
- [x] Fresh local install does not print final ready until assets pass (`wait_for_erpnext_ready` / `docker_ready`).
- [x] Paths that previously skipped the probe now wait or fail clearly (ensure_bench, optional-app, restore, Docker verify).
- [x] Repair command rebuilds/verifies and explains failures (`repair-frontend-assets`).

---

### v1.19.0 — Guarded Auto-Healing MVP

**Status:** Shipped as **v1.19.0**.

**Goal:** Safe, controlled recovery **after** security + local identity + readiness gaps are solid. Default remains **monitor-only**.

**Modes:** `monitor` (default) · `safe` (component/stack restart, never host reboot) · `advanced` (stack recovery; host reboot only if explicitly enabled).

**First safe actions:** restart failed worker; restart scheduler/runtime; restart native app stack; restart Docker service/container group; reload Nginx after config/cert issue.

**Never by default:** reboot for high CPU/RAM alone; delete unknown files; unbounded restart loops; act on a single failed check.

**Controls:** action registry, cooldowns, max-actions window, lockout after repeated failure, before/after incident records, recovery verification. See [`docs/HEALTH-ARCHITECTURE.md`](docs/HEALTH-ARCHITECTURE.md).

**Commands:** `healing-status`, `healing-enable-safe`, `healing-disable`, `healing-unlock`.

**Acceptance**
- [x] Healing disabled unless explicitly enabled.
- [x] Every action creates an incident + cooldown bookkeeping.
- [x] Repeated failure locks healing until manual review.
- [x] Recovery verification records whether the action worked.

---

### v1.19.1 — Auto-Healing Hardening

**Status:** Shipped as **v1.19.1**.

**Goal:** Make the first healing implementation production-safe.

**Scope:** dedicated healing policy file with the **same safe parser pattern** as v1.18.0; per-action enable/disable; healing audit log; richer dashboard healing section; alert on lockout. (`HEALING_SIMULATE` / `HEALTH_HEALING_SIMULATE` for hermetic/operator dry-runs.)

**Commands:** `healing-policy`, `healing-history` (plus status/enable/disable/unlock from v1.19.0).

**Acceptance**
- [x] Operator can inspect a dedicated policy file and disable healing instantly.
- [x] Dashboard shows last action + lockout state.
- [x] Alerts include healing action and result.

---

### v1.19.8 — Browser Asset Consistency Closure (P0)

**Status:** Shipped as **v1.19.8**. Epic [#107](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/107).

**Goal:** The toolkit must not report browser-ready while any CSS/JS required by the actual `/login` page returns 404 or empty body. Discover assets from login HTML + `Link` headers (no `head -n 1`, no hardcoded bundle names); verify with real GET `size_download`; require two consecutive full passes.

**Commands / gates:** `verify-frontend-assets`, `wait-frontend-assets`, `repair-frontend-assets`, `bench_static_assets_ready`, install final gate.

**Acceptance**
- [x] Fresh install cannot report ready while any `/login`-referenced local asset 404s.
- [x] All discovered CSS/JS tested with real GET download sizes.
- [x] Two consecutive full checks before “ERPNext is ready”.
- [x] `:8000` and HTTPS independently diagnosable.
- [x] Hermetic multi-CSS fixture + integration zero-404 assert.

### v1.19.9 — Bare HTTP port-80 browser path (P0)

**Status:** Shipped as **v1.19.9**. Follow-on from [#107](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/107) field testing.

**Goal:** When `:443` / `:8000` assets are OK, bare `http://SITE` (port 80) must redirect to HTTPS (or serve the same working assets). Browsers open that URL by default; a broken `:80` path must not look “ready” while the login page stays unstyled.

**Commands / gates:** `ensure_local_http_redirects_to_https`, `verify-frontend-assets` port-80 section, `configure-local-ssl`, auto-repair after asset rebuild.

**Acceptance**
- [x] Local SSL nginx `:80` redirects to HTTPS by default (valid `location /` if proxy mode).
- [x] Debian nginx `default` site disabled when enabling local SSL.
- [x] `verify-frontend-assets` diagnoses `:80` and prints preferred browser URLs.
- [x] Asset rebuild / repair also repairs HTTP→HTTPS redirect.
- [ ] Field: host browser on `https://SITE/login` styled; bare `http://SITE` 301s.

### v1.19.10 — Frappe-aligned frontend assets (P0)

**Status:** Shipped as **v1.19.10** (field validation recommended). See [`docs/FRAPPE-FRONTEND-ASSETS.md`](docs/FRAPPE-FRONTEND-ASSETS.md).

**Goal:** Align toolkit asset serving and diagnosis with official Frappe contracts: disk `/assets` like `bench setup nginx`, complete login-critical bundles after build, Redis `assets_json` eviction, and `http://SITE:8000` as the primary local browser URL.

**Commands / gates:** `frappe-asset-checklist`, `disk_login_asset_bundles_present`, `clear_bench_assets_json_cache`, nginx `location /assets`, doctor disk/RAM checks.

**Acceptance**
- [x] Toolkit nginx serves `/assets` from `sites/assets` (local SSL + production).
- [x] Install/build require website/login/erpnext-web CSS + frappe-web JS on disk.
- [x] Post-build clears website-cache + `assets_json` / global cache.
- [x] `frappe-asset-checklist` + doctor prefer Frappe `:8000` path.
- [ ] Field: styled login on `http://SITE:8000/login` before trusting HTTPS.

### v1.19.11 — CLI Page UX Architecture (P1)

**Status:** Shipped as **v1.19.11**; field validation recommended. Epic [#108](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/108).

**Goal:** One interactive page lifecycle (clear → result → pause → parent) using existing `lib/ui.sh`; direct CLI stays print-and-exit; credentials become a focused secret page.

**Shipped**
- Numbered interactive selections clear only the live TTY before rendering the selected result/action page; log capture and direct CLI output are not cleared.
- Result pages use one compact return footer: **Enter = back to parent**, **q/Q = quit**.
- High-use menus now pause after direct actions instead of immediately redrawing over the result.
- 80-column terminals use two columns whenever labels fit; genuinely narrow terminals and long-label menus still fall back to one column automatically.
- Main-menu labels are shorter (`Start here`, `Production setup`, `Apps`, `Dashboard`, `Production ops`) and the 80-column status strip is split into calmer rows.
- Credentials are a focused page: short menu labels, concise safe login overview, and `credentials-show` prints only the ERPNext and MariaDB credential fields to `/dev/tty` rather than dumping the full generated environment file.
- Hermetic UI tests cover 80-column two-column rendering, 70-column fallback, `NO_COLOR`, and q/Q handling on the result-page footer.

---

### v1.20.0 — External Watchdog Foundation

**Status:** Deferred until v1.19.10 + v1.19.11 are field-validated.

**Goal:** Contract for Case B — frozen, powered-off, or unreachable VM (cannot self-heal from inside).

**Scope:** local heartbeat file; optional HTTP/status export; external monitor contract; provider API abstraction design; CloudPanel-ready heartbeat format; docs for external watchdog deployment.

**Commands (illustrative):** `heartbeat-status`, `heartbeat-export`, `watchdog-contract`.

**Acceptance**
- [ ] External system can read last healthy heartbeat.
- [ ] Heartbeat includes deployment id, site, engine, status, timestamp.
- [ ] Docs explain provider-side recovery clearly.

---

### v1.21.0 — CloudPanel / Agent API Foundation

**Goal:** Stable machine interface so a future web panel does not scrape human CLI output.

**Scope:** JSON contracts for status, health, backup, restore, incidents; non-interactive flags; job-style operation output; capabilities + stable exit codes; local privileged agent design (predefined ops only, not arbitrary shell).

**Stabilize / add:** `api-version --json`, `capabilities --json`, `deployment-info --json`, `dashboard --json`, `incidents --json`, backup/restore status `--json`.

**Acceptance**
- [ ] Every machine command has stable JSON + documented schema.
- [ ] Privileged operations are allowlisted, not free-form shell.

---

### v1.22.0 — Real VPS Validation Matrix

**Goal:** Public trust via evidence, not claims. **Bounded gate:** at least **three** providers with appendices; expand the living matrix over time.

**In scope for the release gate:** native Ubuntu 24.04 (+ 26.04 and/or Debian 13 as available); Docker production path; Let's Encrypt and/or Cloudflare Origin; off-VM backup; restore rehearsal; dashboard/monitoring smoke.

**Living matrix (fill as evidence lands):** Hetzner, DigitalOcean, Vultr, Linode/Akamai, AWS Lightsail/EC2, Azure, GCP, local KVM, VirtualBox, Hyper-V, Proxmox.

**Acceptance**
- [ ] `VALIDATION.md` has provider-specific evidence for ≥3 providers.
- [ ] Native and Docker production paths both represented.
- [ ] HTTPS, backup/restore, and monitoring checked in those appendices.

---

### v1.23.0 — Documentation and Launch Polish

**Goal:** Adoption clarity without overselling.

**Scope:** real terminal screenshots (replace concept art); menu/dashboard captures; Quick Start by persona (local developer, production VPS, Docker, contributor); troubleshooting trees; security hardening checklist; local stable-IP visual guide.

**Acceptance**
- [ ] README matches current version and shipped features only.
- [ ] Screenshots from real command output.
- [ ] New users can choose a path in under ~60 seconds.

---

## Backlog (after v1.23.0)

| Theme | Notes |
|-------|--------|
| Multi-site / multi-bench | Define single-node scope; do not overcomplicate the CLI early |
| Advanced Docker ops | Safer image upgrades, digest refresh, custom-app rebuild UX, rollback evidence |
| Restore laboratory | Disposable restore VM automation, rehearsal reminders, evidence reports |
| Enterprise support | Redacted support-bundle improvements; health export; upgrade risk report; readiness score |
| Stronger signing options | Sigstore/cosign or offline/HSM (optional, post supply-chain baseline) |

---

## Earlier security / supply-chain milestones (shipped)

Independent review blockers from v1.8.1 and follow-ons are **closed**: production runtime gates, module integrity, lock hardening, `verify-toolkit`, gated publish, stable signing, atomic self-update, support-bundle negatives, toolchain pins, self-update fingerprint gate (**v1.8.2**), `release-signing` environment (**v1.9.0**), Actions SHA pins + Dependabot (**v1.9.1**). Details: [`SECURITY.md`](SECURITY.md) and the historical archive below.

---

## Historical archive

Milestone notes from v1.1.x through earlier planning cycles are kept below for
traceability. **For current planning, use the Active roadmap (v1.18–v1.23) above.**

---

# v1.4.0 roadmap update - guarded ERPNext upgrades (E5)

Status: **implemented**.

Upgrades were the last unguarded high-risk operation: `bench update` pulls new upstream code, migrates the schema, rebuilds, and restarts — any step can take a healthy site down, and there was no toolkit path that made it safe. v1.4.0 adds `lib/update.sh`:

- **`update-preflight`** — read-only readiness report (environment, service state, free disk, uncommitted app changes, current versions, backup recency); returns non-zero on hard blockers.
- **`safe-update-wizard`** — preflight -> typed confirmation -> full backup -> record pre-upgrade commit state -> `bench update` -> migrate -> post-upgrade health gate, with a concrete rollback plan printed on any failure.
- **`update-rollback`** — checks out the recorded pre-upgrade commits and points to `restore-full` for the recorded database backup.

This completes the operator-trust arc: install (v1.2.x), verify/sign (v1.3.0), and now upgrade/rollback (v1.4.0) are all guarded, backup-first flows.

## Next milestones after v1.4.0

1. **Confirm the first live integration + restore run** on hosted runners; tune timing windows.
2. **Add an upgrade rehearsal to CI** — run `safe-update-wizard` against the freshly installed site so upstream breakage is caught automatically (extends D4).
3. **Enable the Ubuntu 26.04 matrix leg** once a hosted runner label exists (D2).
4. **F4/F6 — module-list single source of truth** + a CI consistency check (now four module lists: source chain, shellcheck, manifest, release lib files).
5. **F5 — raise shellcheck to `-S warning`** after triage.

---

# v1.3.0 roadmap update - "verified & signed" milestone

Status: **implemented** (signing active; maintainer key configured).

v1.3.0 closes the two highest-value maturity gaps from the professional evaluation: an unverified restore path and integrity-only (unsigned) releases.

- **Restore-rehearsal in CI (D4).** The integration job now runs a real backup -> restore round trip on the disposable-VM runner and re-asserts health afterward (`install_state=Installed` + `/api/method/ping`). Backups are now proven restorable in automation, not just creatable. A restore that has never been rehearsed is the single scariest gap for a data-stewardship tool; this converts it into a continuously exercised path.
- **Signed releases (A5 / P0 item 5).** `release.yml` signs `SHA256SUMS` on every `v*` tag and publishes the signature with the release; `verify-signature` checks it in a throwaway keyring with optional fingerprint pinning. This adds maintainer-identity verification on top of SHA256 integrity.

## Remaining to fully activate signing

1. Maintainer generates a signing key and adds `GPG_PRIVATE_KEY` (+ optional `GPG_PASSPHRASE`) as repository secrets.
2. Publish the public key and pin its fingerprint in `SECURITY.md` (there is a placeholder marker to replace).
3. First signed tag validates the end-to-end path; then document the pinned fingerprint in the README bootstrap.

## Next milestones after v1.3.0

1. **Confirm the first live integration run** (install + restore round trip) on hosted runners; tune the reachability/restore windows from real timing.
2. **Enable the Ubuntu 26.04 matrix leg** once a hosted runner label exists (D2).
3. **E5 — `update-preflight` + `safe-update-wizard`:** guarded, backup-first ERPNext version upgrades (the next big operator-trust item). **Done (v1.4.0).**
4. **F4/F6 — module-list single source of truth** + a CI consistency check.
5. **F5 — raise shellcheck to `-S warning`** after triage.

---

# v1.2.4 roadmap update - Phase D: reachability hard gate

Status: **implemented**.

v1.2.4 tightens the Phase D integration workflow before its first live run:

- **Site reachability is now a hard gate.** The job requires the installed site to answer `/api/method/ping` on `:8000`, probed with a `Host: <site>` header (so Frappe routes to the correct site) and polled up to 6 minutes after `wait-ready` to absorb first-boot warm-up.
- **Self-diagnosing failures.** On timeout the step dumps `systemctl status`, the service journal, and listening sockets before failing, so the first red run is debuggable directly from the log.

Both `install_state=Installed` and reachability are now required. The next data point is the first live run's warm-up timing, which will confirm or adjust the 6-minute window.

---

# v1.2.3 roadmap update - Phase D groundwork (disposable-VM integration testing)

Status: **first increment implemented**.

Phase D converts "field-validated by the maintainer" into "continuously verified in CI." v1.2.3 lands the first increment:

- **`.github/workflows/integration.yml`** — a dedicated workflow, separate from the fast `ci.yml` PR gate. It performs a real, non-interactive ERPNext install on an ephemeral GitHub-hosted runner (used as a disposable VM) and asserts post-install health.
- **Triggers:** manual (`workflow_dispatch` with a `site_name` input), weekly (`schedule`, Mondays 06:00 UTC), and release tags (`v*`). It does not run on pull requests, so PR latency is unchanged.
- **CI-safety env (verified against the install path):** `ERPNEXT_ALLOW_UNSAFE_INSTALL=true` (hosted runners are below the 30 GB preflight minimum), `AUTO_EXPAND_ROOT=false` (never grow the runner disk — the installer would otherwise auto-expand under `-y`), `AUTO_START=true`, `ENABLE_AUTOSTART=false`.
- **Smoke gate:** verify `SHA256SUMS`, run `install-preflight`, install with `-y`, then assert `doctor --json` reports `install_state=Installed`. `FAIL` checks are surfaced, `http://localhost:8000/api/method/ping` is probed, and toolkit logs plus the service journal are uploaded as artifacts.

## Phase D status

| Step | Deliverable | Status |
|---|---|---|
| D1 | Disposable VM integration job (on tag / weekly / manual) | Done (v1.2.3) |
| D2 | Ubuntu 24.04 + 26.04 matrix | 24.04 live; 26.04 entry present but commented until a hosted `ubuntu-26.04` label exists |
| D3 | Post-install smoke (`doctor --json` install_state gate) | Done (v1.2.3) |
| D4 | Optional restore-rehearsal job | Planned (P2) |

## Next Phase D increments

1. **Harden the smoke into a hard gate:** promote site reachability (`:8000` ping) from warning to required once the first live runs confirm timing on hosted runners.
2. **Enable the 26.04 matrix leg** when the hosted runner label is available (D2).
3. **Restore-rehearsal job (D4):** exercise `restore-preflight` / restore flow against a freshly installed site.
4. **Feed results back:** if upstream Frappe/ERPNext drift breaks installs, capture the failure signature in `TESTING.md`.

After Phase D stabilizes, the highest-ROI items remain the Phase F hygiene tasks (F4/F6 module-list single-source, F5 shellcheck `-S warning`), GPG-signed releases (A5), and operator-experience items (E1–E5).

---

# v1.2.1 roadmap update - professional evaluation and maintenance patch

Status: **implemented**.

## Where the project stands (July 2026)

A full professional evaluation was performed against the live tree at v1.2.0. Summary of evidence:

- **Structure:** `erpnext-dev.sh` is now a ~1,010-line bootstrap/dispatcher sourcing 16 `lib/*.sh` modules (~16,900 lines total). Phase B modularization is complete; the former monolith risk is retired.
- **Static checks:** `bash -n` passes for all 20 shell files. No duplicate function definitions across modules. No `eval`, no `TODO`/`FIXME`, no trailing whitespace. Zero SC2155-style `local x=$(...)` patterns across 257 `local` assignments — declaration and command-substitution are consistently separated.
- **Release integrity:** `scripts/validate-release.sh` passes end to end, including `SHA256SUMS` verification of every listed artifact, version-consistency checks, help-command coverage, and the support-bundle audit fixture.
- **Secrets:** no private keys or credential files are git-tracked; `.gitignore` covers `*.key`, `*.crt`, and credential files.

## Findings addressed in v1.2.1

1. **shellcheck coverage gap (fixed).** `scripts/run-shellcheck.sh` linted all 16 `lib/*.sh` modules and the 3 scripts but omitted the main `erpnext-dev.sh` entry point — even though that file already carries `# shellcheck source=...` directives. The largest dispatched surface was unlinted in CI. `erpnext-dev.sh` is now a shellcheck target.
2. **Duplicate `.gitignore` block (fixed).** The `# Local release handoff notes` / `GITHUB-UPDATE-v*.md` pair was listed twice; de-duplicated.
3. **Stale quality assessment (fixed).** `QUALITY-ASSESSMENT.md` still listed the "16,500-line monolith" as a live High/P1 risk after modularization was complete. The document now reflects the modular architecture and records the new hygiene backlog.

## Findings tracked as backlog (deferred, not bugs)

These are confirmed but intentionally deferred to avoid unverifiable churn in a single patch:

- **F3 — ~16 unreferenced helper functions. DONE (v1.2.2).** Confirmed dead (each had exactly one mention — its definition) and removed across 7 modules: `start_erpnext`, `ui_note`, `show_host_dns_guide`, `show_access_when_ready`, `read_multiline_secret_to_file`, `production_certificate_subject`, `production_ssl_is_configured`, `backup_find_latest`, `backup_schedule_unit_paths`, `off_vm_backup_rsync_command`, `firewall_latest_snapshot`, and five `storage_*` helpers. Re-analysis after removal confirmed 0 remaining dead functions (no cascade). No runtime impact.
- **F4/F6 — module-list drift.** The module list is hand-maintained in four places (the `source` block in `erpnext-dev.sh`, `generate-release-checksums.sh`, `run-shellcheck.sh`, and `toolkit_release_lib_files()` in `lib/security.sh`) plus `RELEASE-MANIFEST.txt`. They are currently consistent, but a single source of truth plus a CI consistency check would prevent future drift.
- **F5 — shellcheck severity.** CI gates at `-S error` only, which passes over warning-level findings (unquoted expansions, etc.). Raising to `-S warning` after triage would tighten the net.

## Next active milestone

1. **v1.2.x — Phase D integration testing** (disposable VM CI, Ubuntu 24.04 + 26.04, post-install smoke). This is the enterprise-confidence inflection point: it converts "field-validated by the maintainer" into "continuously verified on every tag."

Suggested Phase D increments:

| Step | Deliverable |
|---|---|
| D-prep | Split `validate-release.sh` smoke into a reusable job; document required VM secrets |
| D1 | Disposable VM integration job (on tag, optionally weekly) |
| D2 | Ubuntu 24.04 + 26.04 matrix |
| D3 | Post-install smoke (`doctor --json`, site reachable, service active) in CI |
| D4 | Optional restore-rehearsal job (P2) |

After Phase D, the highest-ROI items are the Phase F hygiene tasks (dead-code removal, module-list single-source), GPG-signed releases (A5), and operator-experience items (E1–E5).

---

# v1.2.0 roadmap update - Phase C security hardening

Status: **implemented**.

v1.2.0 adds Phase C security hardening:

- Production credential handoff prompts after install and public VM guided QA.
- Expanded support-bundle audit patterns.
- New `security-audit` command.
- Checksum-gated, tag-pinned `update-toolkit` with production guard against mutable `main`.
- Private security disclosure guidance in `SECURITY.md`.

Next active milestone:

1. **v1.2.x — Phase D integration testing** (disposable VM CI, Ubuntu 24.04 + 26.04, post-install smoke).

---

# v1.1.89 roadmap update - lib/status.sh extraction

Status: **implemented as the fourteenth careful modularization patch**.

v1.1.89 extracts install/runtime status helpers into `lib/status.sh`.

Next active milestones:

1. **v1.1.90+ — optional lib/ops.sh for production-ops menus or further menu thinning**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.88 roadmap update - lib/frappe.sh extraction and dispatcher thinning

Status: **implemented as the thirteenth careful modularization patch**.

v1.1.88 extracts Frappe/bench helpers into `lib/frappe.sh`, removes duplicate support/doctor code from `erpnext-dev.sh`, and leaves the main script as menus plus dispatcher glue (~1,900 lines).

Next active milestones:

1. **v1.1.89+ — optional lib/status.sh or further menu extraction**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.87 roadmap update - lib/access.sh extraction

Status: **implemented as the twelfth careful modularization patch**.

v1.1.87 extracts browser access, host DNS helpers, networking guides, and credentials UI into `lib/access.sh`.

Next active milestones:

1. **v1.1.88+ — thin dispatcher or shared frappe/bench helpers (Phase B5)**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.86 roadmap update - lib/config.sh extraction

Status: **implemented as the eleventh careful modularization patch**.

v1.1.86 extracts site-name validation, saved config loading, domain wizards, and production domain planning into `lib/config.sh`.

Next active milestones:

1. **v1.1.87+ — extract access/credentials helpers or thin dispatcher (Phase B5)**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.85 roadmap update - lib/install.sh Tier C completes install module

Status: **implemented — install module extraction complete (Tiers A–C)**.

v1.1.85 extends `lib/install.sh` with guided setup, quickstarts, and first-run wizard workflows.

Next active milestones:

1. **v1.1.86+ — extract config/access helpers or thin dispatcher (Phase B5)**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.84 roadmap update - lib/install.sh Tier B post-install summaries

Status: **implemented as the tenth careful modularization patch**.

v1.1.84 extends `lib/install.sh` with post-install checkpoint and summary helpers.

Next active milestone:

1. **v1.1.85 — install Tier C** (guided setup and quickstart workflows).

---

# v1.1.83 roadmap update - lib/install.sh Tier A extraction

Status: **implemented as the ninth careful modularization patch**.

v1.1.83 extracts the core install engine into `lib/install.sh` (preflight, packages, Frappe stack, repair, uninstall).

Completed in v1.1.83:

- Added `lib/install.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.84 — install Tier B** (post-install summaries and checkpoint).
2. **v1.1.85 — install Tier C** (guided setup and quickstart workflows).

---

# v1.1.82 roadmap update - lib/service.sh extraction

Status: **implemented as the eighth careful modularization patch**.

v1.1.82 extracts ERPNext systemd service management and runtime state helpers into `lib/service.sh`.

Completed in v1.1.82:

- Added `lib/service.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.83+ — extract install/setup helpers**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.81 roadmap update - lib/storage.sh extraction

Status: **implemented as the seventh careful modularization patch**.

v1.1.81 extracts root storage detection, status, and expansion helpers into `lib/storage.sh`.

Completed in v1.1.81:

- Added `lib/storage.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.82+ — extract install/setup helpers**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.80 roadmap update - lib/health.sh extraction

Status: **implemented as the sixth careful modularization patch**.

v1.1.80 extracts health monitoring, go-live validation, and production readiness helpers into `lib/health.sh`.

Completed in v1.1.80:

- Added `lib/health.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.81+ — extract storage or install/setup helpers**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.79 roadmap update - lib/apps.sh extraction

Status: **implemented as the fifth careful modularization patch**.

v1.1.79 extracts curated Frappe app profiles, install wizards, and compatibility helpers into `lib/apps.sh`.

Completed in v1.1.79:

- Added `lib/apps.sh` and wired `erpnext-dev.sh` to source it.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.80+ — extract health monitoring or install/setup helpers**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.78 roadmap update - lib/ssl.sh and lib/firewall.sh extraction

Status: **implemented as the fourth careful modularization patch**.

v1.1.78 extracts production and local SSL/HTTPS helpers into `lib/ssl.sh` and firewall/UFW/Fail2Ban helpers into `lib/firewall.sh`.

Completed in v1.1.78:

- Added `lib/ssl.sh` and `lib/firewall.sh` and wired `erpnext-dev.sh` to source them.
- Expanded `update-toolkit` to download the full toolkit lib module set.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.79+ — continue thinning `erpnext-dev.sh` toward a dispatcher**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.77 roadmap update - lib/backup.sh extraction

Status: **implemented as the third careful modularization patch**.

v1.1.77 extracts local backup, off-VM backup, restore, and rehearsal helpers into `lib/backup.sh`.

Completed in v1.1.77:

- Added `lib/backup.sh` and wired `erpnext-dev.sh` to source it.
- Simplified `update-toolkit` to download all toolkit lib modules.
- Expanded checksum, manifest, shellcheck, and validation coverage.

Next active milestones:

1. **v1.1.78 — extract SSL/firewall helpers into dedicated lib modules**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.76 roadmap update - lib/support.sh extraction

Status: **implemented as the second careful modularization patch**.

v1.1.76 extracts doctor, support-bundle, support-bundle audit, and command-audit helpers into `lib/support.sh`.

Completed in v1.1.76:

- Added `lib/support.sh` and wired `erpnext-dev.sh` to source it.
- Expanded checksum, manifest, shellcheck, and update-toolkit coverage for the new module.

Next active milestones:

1. **v1.1.77 — extract backup/restore helpers into lib/backup.sh**.
2. Later: optional GPG-signed release artifacts.

---

# v1.1.75 roadmap update - lib/common.sh and shellcheck in CI

Status: **implemented as the first careful modularization patch**.

v1.1.75 extracts shared logging, locking, UI/menu helpers, prompts, and command helpers into `lib/common.sh`, and adds shellcheck to CI.

Completed in v1.1.75:

- Added `lib/common.sh` and wired `erpnext-dev.sh` to source it.
- Updated install/update reuse paths to copy or download the toolkit `lib/` tree.
- Added `scripts/run-shellcheck.sh`.
- Added shellcheck installation and execution to `.github/workflows/ci.yml`.
- Expanded `SHA256SUMS` and `RELEASE-MANIFEST.txt` for the new module and script.

Next active milestones:

1. **v1.1.76 — extract support/diagnostics module**.
2. **v1.1.77+ — extract backup/restore modules**.
3. Later: optional GPG-signed release artifacts.

---

# v1.1.74 roadmap update - release manifest, expanded checksums, and quality assessment

Status: **implemented as the fifth release-trust hardening patch after v1.1.70 through v1.1.73**.

v1.1.74 adds structured quality assessment documentation, a release manifest, expanded checksum coverage, and stronger automated release validation.

Completed in v1.1.74:

- Added `QUALITY-ASSESSMENT.md` with reliability, security, and ease-of-use evaluation.
- Added `RELEASE-MANIFEST.txt` and manifest validation in `scripts/validate-release.sh`.
- Added `scripts/generate-release-checksums.sh`.
- Expanded `SHA256SUMS` to cover `erpnext-dev.sh`, `scripts/validate-release.sh`, and `RELEASE-MANIFEST.txt`.
- Added version-consistency checks across `SCRIPT_VERSION`, README, CHANGELOG, and manifest header.
- Added `menu-self-test` and `production-ops-wizard` quit smoke tests to release validation.

Next active milestones:

1. **v1.1.75 — begin careful modularization planning with shellcheck in CI**.
2. Later: optional GPG-signed release artifacts.
3. Later: disposable VM integration testing.

---

# v1.1.73 roadmap update - support-bundle audit and package validation expansion

Status: **implemented as the fourth release-trust hardening patch after v1.1.70, v1.1.71, and v1.1.72**.

v1.1.73 adds support-bundle audit coverage and expands `scripts/validate-release.sh` with a clean support-bundle fixture.

Completed in v1.1.73:

- Added `support-bundle-audit`, `audit-support-bundle`, and `support-bundle-audit-test`.
- Added a Support and Diagnostics dashboard option for support-bundle auditing.
- Added forbidden filename checks for credential files, private keys, database backups, and private-file backup archives.
- Added obvious secret-pattern scanning for private key blocks, bearer tokens, and password/token-style assignments.
- Added support-bundle audit fixture validation to `scripts/validate-release.sh`.

Next active milestones:

1. **v1.1.74 — release package manifest and checksum expansion**.
2. **v1.1.75+ — begin careful modularization planning with CI as a safety net**.
3. Later: optional GPG-signed release artifacts.

Important limitation:

- The audit is best-effort. It reduces accidental sharing risk but does not replace manual review of support bundles before sending outside the organization.

---

# v1.1.72 roadmap update - minimal CI and validate-release script

Status: **implemented as the third release-trust hardening patch after v1.1.70 and v1.1.71**.

v1.1.72 adds `.github/workflows/ci.yml` and `scripts/validate-release.sh` so release checks can run consistently before tags are published.

Completed in v1.1.72:

- Added GitHub Actions workflow for push, pull request, and version-tag validation.
- Added `scripts/validate-release.sh`.
- Added syntax, version, checksum, help, `verify-toolkit`, package hygiene, and basic secret-pattern checks.
- Updated `verify-toolkit` guidance to use the stable `/opt/erpnext-dev` install path.
- Updated README, SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, CHANGELOG.md, and PRODUCTION-VALIDATION.md.

Next active milestones:

1. **v1.1.73 — support-bundle audit test and package validation expansion**.
2. **v1.1.74+ — begin careful modularization planning with CI as a safety net**.
3. Later: optional GPG-signed release artifacts.

Important limitation:

- The v1.1.72 CI is intentionally minimal. It does not run a full ERPNext install in CI. It catches release/package regressions before heavier VM-level tests are added.

# v1.1.71 roadmap update - verify-toolkit command

Status: **implemented as the second release-trust hardening patch after v1.1.70**.

v1.1.71 adds `verify-toolkit` so operators can report the active script hash, stable toolkit hash, CLI target hash, and checksum match status when `SHA256SUMS` is available. This builds on the v1.1.70 tag-pinned checksum bootstrap workflow.

Completed in v1.1.71:

- Added `verify-toolkit`, `toolkit-verify`, and `verify-install` aliases.
- Added checksum-file discovery with `CHECKSUM_FILE` override support.
- Added active/stable/CLI SHA256 reporting.
- Added match/mismatch reporting against `SHA256SUMS`.
- Added a Support and Diagnostics dashboard entry for toolkit verification.
- Updated README, SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, CHANGELOG.md, and PRODUCTION-VALIDATION.md.

Next active milestones:

1. **v1.1.72 — minimal GitHub Actions CI and `scripts/validate-release.sh`**.
2. **v1.1.73+ — support-bundle audit test and package validation expansion**.
3. Later: begin careful modularization only after release integrity and CI are in place.

Important limitation:

- `verify-toolkit` validates file integrity when a trusted checksum file is available. It does not prove maintainer identity. GPG-signed releases remain a later optional milestone.

---

# v1.1.70 roadmap update - SHA256 checksums and tag-pinned bootstrap docs

Status: **implemented as the first release-trust hardening patch after v1.1.69**.

v1.1.70 adds a `SHA256SUMS` release artifact for `erpnext-dev.sh` and updates the README to prefer tag-pinned downloads with checksum verification before `sudo` execution. This directly addresses the P0 bootstrap-trust gap identified in the security review.

Completed in v1.1.70:

- Added `SHA256SUMS` for the release script artifact.
- Updated install examples to use `VERSION="v1.1.70"` and release-tag raw URLs.
- Added `sha256sum -c SHA256SUMS` before script execution in bootstrap examples.
- Updated SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, CHANGELOG.md, and PRODUCTION-VALIDATION.md.
- Kept runtime behavior unchanged.

Next active milestones:

1. **v1.1.72 — minimal GitHub Actions CI and `scripts/validate-release.sh`**.
2. **v1.1.73+ — support-bundle audit test and package validation expansion**.
3. Later: begin careful modularization only after release integrity and CI are in place.

Important limitation:

- SHA256 checksums provide file integrity, not maintainer identity. GPG-signed releases can be added later for stronger supply-chain assurance.

---

# v1.1.69 roadmap update - security and reliability planning docs

Status: **implemented as a planning/documentation patch after v1.1.67/v1.1.68 production dashboard validation**.

The production VM operations path is now strong and field-tested. The next priority is release trust and automated regression prevention. v1.1.69 adds `SECURITY.md` and `RELIABILITY-PLAN.md` so the project has a clear, tracked plan for the next security and reliability milestones.

Completed in v1.1.69:

- Added `SECURITY.md` covering threat model, bootstrap trust, credential handling, support-bundle safety, root-script risk, and responsible reporting guidance.
- Added `RELIABILITY-PLAN.md` covering release validation automation, package checks, CI, support-bundle audit direction, and modularization sequencing.
- Updated README, TESTING, CHANGELOG, and PRODUCTION-VALIDATION to reference the new planning docs.
- Kept runtime behavior unchanged.

Next active milestones:

1. **v1.1.72 — minimal GitHub Actions CI and `scripts/validate-release.sh`**.
2. **v1.1.73+ — support-bundle audit test and package validation expansion**.
3. Later: begin careful modularization only after release integrity and CI are in place.

Rationale:

- The highest-priority risk is not the current ERPNext VM workflow; it is release trust when running downloaded code with `sudo`.
- CI should exist before major script modularization, otherwise refactoring risk is too high.
- Docker installation remains a separate later track after VM operations and release engineering remain stable.

---

# v1.1.68 roadmap update - final v1.1.67 dashboard validation record

Status: **documentation/validation patch completed after v1.1.67 production validation passed**.

The v1.1.67 Production Operations dashboard navigation polish is now validated on `erp.flowmaya.com`. The top-level dashboard shows only `q) Quit`, nested operator sections show `b) Back` and `q) Quit`, and breadcrumb titles make submenu context clear.

Completed and recorded in v1.1.68:

- v1.1.67 installed on the production VPS and reported by `erpnext-dev version`.
- Final QA option `1) Release readiness summary` passed with `Release state OK`.
- Redacted support bundle created after v1.1.67 validation: `/tmp/erpnext-dev-support-bundle-20260709-071549.tar.gz`.
- Health Monitoring breadcrumb validated: `ERPNext Production Operations > Health Monitoring`.
- Support and Diagnostics breadcrumb validated: `ERPNext Production Operations > Support and Diagnostics`.
- The validated production state remains unchanged: runtime, HTTPS, UFW, Fail2Ban, local backup, off-VM backup, restore rehearsal, health monitoring, and go-live validation remain OK.

Next active milestone: **safe status exports and optional notification design after production dashboard validation**.

Planned next items:

1. Keep the production dashboard read-only/status-first by default.
2. Consider a simple redacted status export command for sharing operational state without a full support bundle.
3. Consider health-check notification targets such as email or webhook only after defining safe defaults and avoiding noisy alerts.
4. Keep provider-side validation records explicit and repeatable after snapshot, firewall, DNS, or SSL changes.
5. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.67 roadmap update - production dashboard navigation polish

Status: **implemented as a UX polish patch after v1.1.66 field validation**.

The v1.1.66 production dashboard passed core routing validation on `erp.flowmaya.com`, but the smoke test exposed one usability issue: the top-level dashboard advertised `b) Back` even when opened directly, and nested menus did not visually show enough context. The v1.1.67 patch addresses that without changing the underlying production operations logic.

Completed in v1.1.67:

- Top-level `production-ops-wizard` now advertises only `q) Quit`.
- Nested Production Operations sections still advertise `b) Back` and `q) Quit`.
- Production Operations submenus now use breadcrumb-style titles.
- Health Monitoring receives the breadcrumb title when opened from the dashboard.
- Documentation and validation plans were updated.

Next active milestone: **operator polish and safe status exports after v1.1.67 production validation**.

Planned next items:

1. Install v1.1.67 on the production VPS and validate the navigation polish.
2. Keep the production dashboard read-only/status-first by default.
3. Consider a simple read-only status export later, after dashboard navigation remains stable.
4. Defer health notifications until the dashboard and health timer have more runtime history.
5. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.66 roadmap update - production operations dashboard

Status: **implemented as the unified operator-experience layer over the validated production toolkit commands**.

Completed in v1.1.66:

- Rebuilt `production-ops-wizard` into a top-level Production Operations dashboard.
- Added a current-state summary so operators can see runtime, HTTPS, security, backup, restore rehearsal, health monitoring, and go-live state before choosing an action.
- Grouped operational actions into clear areas: services, local backups, off-VM backups, restore readiness, health monitoring, security/firewall, HTTPS/certificates, go-live validation, and support/diagnostics.
- Added aliases: `production-ops-dashboard`, `operations-dashboard`, and `ops-dashboard`.
- Reused existing tested command implementations instead of duplicating business logic.

Next active milestone: **production dashboard field validation and polish**.

Planned next items:

1. Install v1.1.66 on the production VPS and validate dashboard option routing.
2. Confirm support/diagnostics dashboard flow creates and reviews the enhanced support bundle.
3. Decide whether to add notification targets for health checks, such as email or webhook.
4. Consider a read-only HTML/status export later, but keep the Bash toolkit stable first.
5. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.65 roadmap update - final production validation record

Status: **documentation/validation patch completed after the v1.1.64 production go-live workflow passed**.

The production path is now validated end to end across install, HTTPS, security baseline, local backups, off-VM backup, restore rehearsal, health monitoring, go-live confirmations, and redacted evidence bundle generation.

Completed and recorded in v1.1.65:

- v1.1.64 go-live validation record passed on `erp.flowmaya.com`.
- Named snapshot recorded: `erp-flowmaya-v1.1.64-final-validated-20260709`.
- Cloud firewall confirmation recorded.
- Cloudflare proxied DNS, Full (strict), and Origin CA confirmation recorded.
- Production checklist reports go-live validation as `OK`.
- Final QA option `9) Go-live validation status` passed.
- Enhanced support bundle includes production evidence files for backups, restore rehearsal, monitoring, go-live status, and checklist state.

Completed follow-up milestone: **v1.1.66 production operations dashboard / unified operations experience**.

Implemented v1.1.66 goals:

1. Provide a clean top-level production operations dashboard with concise current-state summaries.
2. Group health, services, backups, off-VM backup, restore readiness, monitoring, security, HTTPS, go-live validation, and support actions into a coherent operator flow.
3. Prefer status-first screens and suggested next actions so operators do not need to remember command names.
4. Keep existing CLI commands as stable direct entry points.
5. Avoid duplicating logic; the dashboard orchestrates existing tested commands.
6. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.64 roadmap update - go-live validation record and evidence bundle

Status: **implemented as the next production-readiness polish patch**.

The install, backup, off-VM backup, restore rehearsal, restore status tracking, and health monitoring paths are now validated. v1.1.64 focuses on the provider-side confirmations that must be recorded outside the guest VM.

Completed in v1.1.64:

- `go-live-record` for snapshot, provider firewall, and Cloudflare confirmation.
- `go-live-status` for saved go-live validation evidence.
- `cloud-firewall-checklist` and `cloudflare-checklist` as guided provider-side checklists.
- Production checklist and Final QA awareness of go-live validation.
- Enhanced support bundles with redacted production evidence files.

Next roadmap items:

1. Validate `go-live-record` on the production VPS after the named snapshot and provider-side settings are confirmed.
2. Decide whether to add notification targets for health checks, such as email or webhook.
3. Add longer-term operations dashboard/menu polish if the command surface becomes too large.
4. Keep Docker installation as a separate later track after VM operations remain stable.

---

# v1.1.63 roadmap update - monitoring workflow

Status: **implemented as the next production-hardening patch**.

The restore and off-VM backup path is now validated. The current active focus is lightweight monitoring and operational visibility.

Completed in v1.1.63:

- Guided `health-monitoring-wizard`.
- Health check state record at `/etc/erpnext-dev/health-check.state`.
- Health timer schedule/delay prompts.
- Journal helper for health-check runs.
- Production checklist and Final QA awareness of monitoring state.

Next roadmap items:

1. Validate health timer on the production VPS.
2. Confirm Hetzner snapshot and provider firewall state.
3. Decide whether to add notification targets later, such as email/webhook, after local health timer behavior is stable.
4. Keep Docker installation as a later separate track after VM operations remain stable.

---

## v1.1.62 final production QA documentation record

Status: documentation/validation patch after final v1.1.61 production QA passed.

Completed production-readiness items now recorded:

- Production VPS install and runtime validation.
- Cloudflare Origin CA / Nginx HTTPS validation.
- UFW and Fail2Ban validation.
- Local backup and scheduled backup validation.
- Separate off-VM backup server validation.
- Real off-VM rsync dry run and real run validation.
- Disposable local restore VM rehearsal validation.
- Restore rehearsal record/status tracking validation.
- Final QA release readiness: `Release state OK ready for production use`.
- Redacted support bundle creation validation.

Updated readiness after final QA:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and stable |
| Public VPS guided production workflow | 9.5/10 | Real production path validated with HTTPS, security checks, backups, and final QA |
| Off-VM backup workflow | 9.4/10 | Separate backup server, real rsync run, cleanup, and dry-run revalidation passed |
| Restore rehearsal workflow | 9.4/10 | Disposable restore, login validation, cleanup, and production-side status tracking passed |
| Full production readiness | 9.5/10 | Remaining work is operational: cloud snapshot, provider firewall confirmation, Cloudflare setting confirmation, optional health timer |

Next active milestones:

1. Create/confirm named cloud provider snapshot after final validation.
2. Confirm provider-level firewall policy outside the VM.
3. Confirm Cloudflare DNS proxy state and SSL/TLS mode Full (strict).
4. Decide whether to enable the optional health timer.
5. Plan periodic restore drills after major upgrades, migrations, or backup-policy changes.

## v1.1.61 restore rehearsal status tracking

Status: focused production-readiness polish.

- Add restore rehearsal record/status/report commands.
- Update production checklist and final QA so completed restore rehearsals are recognized instead of repeatedly showing stale warnings.
- Store restore rehearsal metadata on the production VM in `/etc/erpnext-dev/restore-rehearsal.env`.
- Treat restore VM IP as optional evidence only, because local VM networking can change.
- Keep the next production hardening items focused on health timer monitoring, cloud snapshot policy, and periodic restore-drill repetition after major upgrades.

Updated readiness after v1.1.61:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and stable |
| Public VPS guided production workflow | 9.4/10 | Real production path validated |
| Off-VM backup workflow | 9.3/10 | Separate backup server and rsync dry/run validated |
| Restore rehearsal workflow | 9.1/10 | Restore works and now has record/status tracking |
| Full production readiness | 9.3/10 | Remaining items are operational: health timer, firewall policy confirmation, named snapshot policy |

## v1.1.60 completed restore rehearsal automation

Status: implementation package ready after successful local restore rehearsal.

- Added a guided restore rehearsal workflow for disposable local/cloud restore VMs.
- Added restore-key setup and backup-server temporary-key lifecycle commands.
- Added rsync pull helper for restore VMs.
- Improved restore-full to select the latest complete backup set by default.
- Improved database admin credential handling by using the local toolkit credentials file when available.
- Added restore VM preflight checks for resource sizing and Docker/Kubernetes/Calico conflicts.
- Documented the restore rehearsal workflow in the README menu and backup/restore section.

Updated readiness after restore rehearsal:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local development/testing use |
| Public VPS guided production workflow | 9.3/10 | Real production-candidate path validated with Let's Encrypt and Cloudflare Origin CA |
| Off-VM backup workflow | 9.2/10 | Real separate backup server and rsync copy validated |
| Restore rehearsal workflow | 8.7/10 | Local disposable VM restore passed; v1.1.60 reduces manual steps |
| Full production readiness | 9.2/10 | Core install, HTTPS, firewall, local/off-VM backups, and restore are proven; monitoring/snapshot policy remains operational |

Next milestones:

1. Complete browser/login validation on the restored local VM.
2. Remove the temporary restore key from the backup server.
3. Optionally configure the health timer for ongoing monitoring.
4. Add restore drill status tracking in a future patch if needed.

## v1.1.59 completed off-VM backup validation and onboarding polish

Status: real two-server off-VM backup validation passed.

- Confirmed dedicated SSH-key rsync from ERPNext VPS to a separate backup VPS.
- Confirmed backup files landed on the attached 200 GB backup volume.
- Confirmed `off-vm-backup-status` and `production-checklist` report the successful last off-VM run.
- Improved backup-server onboarding so the wizard tells the user to generate the ERPNext-side public key first.
- Improved Enter-to-accept defaults for backup root paths by detecting mounted Hetzner volumes.
- Improved status wording so the toolkit does not imply off-VM backup is still untested after a successful run.

Updated readiness target after validation:

- Local VM/developer workflow: 9.5/10, passed.
- Production VPS core workflow: 8.9/10, validated with Let’s Encrypt and Cloudflare Origin CA paths.
- Production backup/resilience workflow: 8.6/10, local backup + off-VM copy validated; restore rehearsal still required.

Active next milestone: rehearse restore from the off-VM backup on a disposable VM, then add optional health timer monitoring if needed.

## v1.1.58 completed guided off-VM backup setup foundation

Status: implementation package ready for validation.

- Added a backup-server command that can be pulled and run on a separate Linux backup server.
- Added ERPNext-side key generation and guided off-VM setup commands.
- Kept existing manual rsync target, dry-run, real-run, and status commands.
- Remaining readiness movement requires real two-server validation: dry run, real off-VM run, backup-server file verification, and restore rehearsal.

Updated readiness target after validation:

- Local VM/developer workflow: 9.3/10, passed.
- Production VPS core workflow: 8.7/10, validated with Let’s Encrypt and Cloudflare Origin CA paths.
- Production backup/resilience workflow: pending off-VM backup and restore rehearsal validation.

## v1.1.57 completed Cloudflare Origin CA validation record

- Recorded successful Cloudflare Origin CA / Full (strict) validation on the real Hetzner VPS production path.
- Confirmed Cloudflare orange-cloud/proxied DNS can be handled safely after the v1.1.56 guided DNS gate fix.
- Confirmed both production HTTPS paths are now validated:
  - Let's Encrypt direct DNS-only path: validated.
  - Cloudflare Origin CA / Full (strict): validated.
- Confirmed the production hardening follow-up after an interrupted guided flow: UFW active, Fail2Ban sshd jail enabled, scheduled local backups active, external backend ports blocked.

Current ratings after Cloudflare validation:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local development/testing use |
| Public VPS guided production workflow | 8.8/10 | Core production path validated on real Hetzner VPS with both Let's Encrypt and Cloudflare Origin CA HTTPS paths |
| Production HTTPS choices | 9.0/10 | Let's Encrypt direct DNS and Cloudflare Origin CA Full strict paths validated |
| Backup + restore foundation | 9.0/10 | Local backups and readable verification pass; production restore rehearsal still required |
| Off-VM backup / production monitoring | 6.0/10 | Planning and local timers exist; real off-VM target, real copy, restore rehearsal, and optional health timer remain open |

Active next milestone: validate off-VM backup target configuration, off-VM backup dry run/real run, and disposable-VM restore rehearsal. Avoid broad feature work until backup survivability is validated.

## v1.1.56 completed Cloudflare proxied DNS guided setup fix

- Fixed the guided production DNS gate so Cloudflare orange-cloud/proxied DNS can continue through the Cloudflare Origin CA path instead of failing because public DNS returns Cloudflare edge IPs.
- Kept Let's Encrypt as the default when DNS points directly to the VM.
- Remaining validation: run a clean guided Cloudflare Origin CA install from a fresh/rollback VPS and confirm final QA after proxy + Full (strict).

# Roadmap

## v1.1.55 completed production VPS validation record and polish fixes

- Recorded the successful fresh Hetzner VPS production validation with Ubuntu 26.04 LTS, real DNS, Let’s Encrypt HTTPS, UFW, Fail2Ban, scheduled local backups, external backend-port blocking, browser login testing, support bundle, and post-validation snapshot.
- Fixed UFW status wording/parser so explicit backend `DENY` rules are not reported as false allow warnings.
- Improved production access wording so `:8000` URLs are clearly troubleshooting/backend validation URLs, not normal public production access.
- Documented the interactive-menu shell behavior: commands pasted after `final-qa` run after the menu exits.

Updated readiness after real VPS validation:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local development/testing use |
| Core public VPS guided production path | 8.4/10 | Passed on fresh Hetzner VPS with real domain, Let’s Encrypt, UFW, Fail2Ban, backups, and external port checks |
| Backup + restore foundation | 9.0/10 local / 7.5/10 production | Local restore passed; production restore still needs disposable-VM rehearsal |
| Final QA and support bundle | 9.0/10 | Passed on local and production validation paths; support bundle contents reviewed |
| Off-VM backup / production monitoring | 5.8/10 | Planning and local timers exist; real off-VM target and health timer validation remain open |
| Cloudflare Origin CA SSL path | 9.0/10 | Validated through Cloudflare orange-cloud/proxied DNS with Origin CA and Full (strict) |

Active next milestone: validate off-VM backup target, off-VM backup dry run/real run, and disposable-VM restore rehearsal.

## v1.1.52 completed production guided setup UX fix

- Kept the existing Public VM menu for manual and advanced production tasks.
- Added `public-vm-guided-setup` as the README production bootstrap target.
- Routed the general setup wizard's Public VM path to the new guided production flow.
- The guided flow now walks the user through domain, DNS readiness, external cloud firewall/snapshot confirmation, install, backup checkpoint, HTTPS, production security profile, Fail2Ban, scheduled backups/off-VM backup review, optional apps, Final QA, support bundle, and post-validation snapshot reminder.
- Updated production validation documentation to allow Ubuntu 24.04 LTS or Ubuntu 26.04 LTS.

Active next milestone: continue real VPS/domain validation with the new guided production command.

## v1.1.51 completed production VPS validation handoff documentation

- Closed the local VM validation stage after v1.1.50 confirmed the final Local SSL firewall-guidance fix.
- Added a documented requirement that the next production-validation stage must use a fresh disposable VPS and a real test subdomain.
- Added the production VPS validation order: DNS, cloud firewall, clean snapshot, public quickstart, production firewall, Let's Encrypt HTTPS, external port exposure checks, backups, scheduled backups, production checklist, Final QA, and post-validation snapshot.
- Added readiness ratings so local/dev readiness is separated from production readiness.
- Added `PRODUCTION-VALIDATION.md` as the dedicated handoff checklist for the next test session.

Current ratings after local validation:

| Case | Rating | Interpretation |
| --- | ---: | --- |
| Local VM / developer workflow | 9.5/10 | Passed and ready for normal local development/testing use |
| Backup + restore foundation | 9.0/10 | Passed locally; production restore still requires disposable-VM rehearsal |
| Final QA and support bundle | 8.8/10 | Passed locally; production warnings are expected until VPS validation |
| Public VPS production-candidate workflow | 6.5/10 | Implemented but must be validated on real VPS + domain before production confidence rises |
| Off-VM backup / production monitoring | 5.5/10 | Workflows exist, but real target/timer validation remains open |

Active next milestone: **v1.1.52+ Production VPS validation**.

Required test environment:

```text
Fresh disposable Ubuntu 24.04 LTS or Ubuntu 26.04 LTS VPS
Public IPv4
Real test subdomain, for example erp-test.example.com
Cloud firewall control
Snapshot capability
SSH access from admin IP
```

The next milestone should not add broad new features until the real VPS path is tested end to end.

## v1.1.50 completed Local SSL firewall-guidance polish

- Fixed `verify-local-ssl` follow-up guidance so it no longer recommends applying the Local VM security profile when UFW is already active.
- Added a safe default for the internal `SUDO` command prefix so UFW/helper status checks do not falsely fail before `require_sudo` initializes it.
- `verify-local-ssl` now requires sudo explicitly, matching the protected nginx/UFW checks it performs.

## v1.1.49 completed Final QA/local-stage polish

- Final QA release notes now use the current toolkit version dynamically and no longer overstate untested production paths.
- Added `scheduled-backup-status` as a friendly alias for `backup-schedule-status`.
- Scheduled-backup disable now reports missing/unconfigured timers clearly and points users to configure/status commands.
- Local VM development workflow is now considered passed for install, local HTTPS, optional apps, backup/restore, scheduled backups, retention dry run, maintenance basics, and Final QA.
- Next major stage: production VM validation, including production domain, Let's Encrypt/Cloudflare SSL, cloud firewall, Fail2Ban, off-VM backup, health timer, and production operations.

## v1.1.48 completed restore and local HTTPS polish

- Post-restore maintenance now keeps the terminal readable by saving verbose migrate/build/cache output to step-specific log files.
- The ERPNext Ready screen now prioritizes HTTPS Desk/Login/Website URLs when local HTTPS is configured.
- Local HTTPS verification now detects an already-active Local VM firewall profile and avoids telling the user to apply it again.
- Local Firewall Access Check now includes an HTTPS host-side test when local SSL is configured.
- Remaining backup work: scheduled backup activation, retention cleanup validation, off-VM backup rehearsal, and disposable-VM restore testing.

## v1.1.47 completed restore UX and post-restore sequencing

- Restore prompts now use database-admin wording instead of MySQL/root wording.
- Restore flow reminds users to have the MariaDB Bench Admin credential ready before continuing.
- Restore now passes the toolkit database admin user/password to Bench restore.
- Post-restore maintenance now starts/waits for ERPNext services before running migrate, build, and cache cleanup.
- Remaining backup work: scheduled backup activation, retention cleanup validation, off-VM backup rehearsal, and disposable-VM restore testing.

## v1.1.46 completed README version hygiene

- Removed the stale hard-coded version from the README heading.
- The README now points users to `erpnext-dev version` for the installed toolkit version, avoiding future documentation drift.

## v1.1.45 completed app-status comparison hardening

- Replaced the app comparison temp scripts with a safer local comparison flow using downloaded, installed, and registered app lists.
- `app-status` and Advanced Tools -> Installed apps should now show `none` cleanly when every downloaded app is installed and registered.
- The optional-app workflow is considered passed after full batch install/browser testing, pending final backup/checkpoint review.

## v1.1.44 completed optional-app status polish

- Fixed optional-app status comparison output after large app batches.
- `app-status` should no longer show temporary shell syntax errors in the downloaded-but-not-installed or downloaded-but-not-registered sections.
- App wizard preflight now separates installed state from branch repeatability notes so working apps installed from `main`, `develop`, or default branches do not look failed.

## v1.1.37 completed README first-run UX cleanup

- The README now starts with the real local, production, guided menu, preflight, and update commands before explaining bootstrap internals.
- The `/tmp` bootstrap note is preserved but moved below the copyable commands.
- Local host DNS mapping instructions now emphasize dynamic VM IP detection and toolkit-generated host commands rather than static sample IPs.

## v1.1.36 completed menu navigation hardening

- All interactive menu prompts now use a shared input reader.
- `q`/`Q` quits consistently, `b`/`B` goes back where supported, and full words such as `quit`, `exit`, and `back` are normalized.
- Added a non-destructive `menu-self-test` command to validate top-level menus, submenus, and common nested menu paths before release.
- This reduces the risk of a submenu crash causing later typed menu numbers to be interpreted by the shell as commands.

## v1.1.35 completed local DNS/access root fix

- Local VM host mapping now uses dynamic VM IP detection instead of assuming a fixed `192.168.122.x` address.
- Added local domain status, local access doctor, and host DNS guide commands.
- Access and Local SSL menus now expose local DNS/host mapping diagnostics.
- The setup flow now treats host `/etc/hosts` mapping as a first-class local VM step, while still reminding users that the script cannot directly edit the separate host machine from inside the guest VM.

## v1.1.34 completed security profile and setup lifecycle hardening

- Added separate Local VM and Production firewall profiles.
- Added local access repair for over-hardened `.test` VMs.
- Added firewall rollback snapshots before UFW changes.
- Added setup lifecycle guidance for local and production installs.
- Added post-core and post-app backup checkpoints.

# Roadmap

## v1.1.33 completed local domain workflow

- Local quickstart now asks for the local VM domain at the beginning and defaults to `erp.test` when the user presses Enter.
- Existing installs now have a guided `change-local-domain` workflow that backs up, renames the Frappe site, updates Bench/toolkit config, and prompts for local SSL rebuild.


This roadmap is focused on making the ERPNext Developer Toolkit mature enough to install, manage, monitor, secure, back up, and maintain ERPNext/Frappe VMs reliably.

The current priority remains the **VM-based installer and production operations toolkit**. A Docker-based ERPNext/Frappe installation method is planned as a separate future track, but it should not distract from hardening the VM workflow first.

---

## v1.1.32 HTTPS menu baseline

The command naming baseline is `erpnext-dev.sh` for the bootstrap file and `erpnext-dev` for day-to-day operations. Local VM HTTPS / SSL, Production HTTPS / SSL, and Optional Apps are first-level menu actions after installation. Local HTTPS and production HTTPS must remain separate workflows with separate submenus, status checks, and rollback guidance. Future roadmap items should refer to the project as the ERPNext Developer Toolkit, not only an installer.

---

## Roadmap principles

- **VM reliability first:** the current installer must become a dependable production VM management toolkit before adding another install method.
- **Safe operations:** prefer preflight checks, dry-runs, summaries, confirmations, and rollback guidance before any risky action.
- **Separation of concerns:** installation, backup, restore, monitoring, security, updates, diagnostics, and documentation should each have clear commands.
- **Production clarity:** every command should clearly say whether it is intended for local testing, public production, or restore rehearsal.
- **Generic provider support:** avoid locking the workflow to one cloud provider; document provider-specific examples only as examples.
- **Docker later:** Docker support should be a separate approach with separate assumptions, backup logic, and operational checks.

---

## Current baseline

The current VM installer already covers the core install path and many first-layer operations.

Completed or available:

- Local VM quickstart using `.test` domains such as `erp.test`.
- Public VPS/cloud VM quickstart using a real domain or subdomain.
- Reusable toolkit command `erpnext-dev` backed by `/opt/erpnext-dev/erpnext-dev.sh`.
- ERPNext/Frappe install, runtime checks, and access verification.
- Local SSL guide and mkcert workflow.
- Production SSL paths, including Cloudflare Origin CA and public HTTPS checks.
- Firewall hardening, UFW status, and Fail2Ban checks.
- Local backups, backup verification, backup status, retention planning, and cleanup.
- Off-VM rsync backup configuration, dry-run, run, and status.
- Production health check and optional local health-check timer.
- Credentials-info helper and safer credential handling.
- Optional app wizard and compatibility checks.
- Diagnostics, `doctor`, command audit, and redacted support bundles.
- README start-here section, architecture diagrams, testing docs, and changelog separation.

Main gaps before calling the production VM operations mature:

- Better log review and failure diagnostics.
- More complete backup capacity planning and remote target checks.
- Safer restore rehearsal workflows.
- Update/upgrade preflight and controlled maintenance workflow.
- Alerting, notifications, and repeated monitoring beyond local status checks.
- Stronger VM security audit and hardening recommendations.
- Production maintenance reports for handover and ongoing operations.

---

## Active direction: production VM maturity

### Phase 1 — production diagnostics and maintainability

Goal: make it easy to understand the state of the VM and identify issues quickly.

Planned work:

- **Log review and diagnostics**
  - Add commands to review ERPNext, supervisor/systemd, Nginx, MariaDB, Redis, backup, and SSL-related logs.
  - Provide compact summaries instead of dumping large logs by default.
  - Include safe copy/paste modes for support.

- **VM state report**
  - Produce a single management report with site name, domain, services, ports, disk, memory, backup state, SSL state, firewall state, and health status.
  - Keep secrets redacted.

- **Maintenance dashboard / operations menu refinement**
  - Improve the production operations menu into a clear maintenance console.
  - Group tasks by Health, Backups, Restore, SSL, Security, Updates, Apps, and Diagnostics.

- **Backup capacity planning**
  - Estimate current complete-backup size.
  - Estimate required space for 3, 7, 14, and custom retention counts.
  - Warn when local or remote storage is too small for the configured policy.

Candidate commands:

```bash
sudo erpnext-dev log-review
sudo erpnext-dev vm-state-report
sudo erpnext-dev maintenance-dashboard
sudo erpnext-dev backup-size-estimate
sudo erpnext-dev backup-capacity-plan
```

---

### Phase 2 — backup and restore maturity

Goal: make backups trustworthy, testable, and easier to restore on a disposable VM.

Planned work:

- **Off-VM target improvements**
  - Support SSH port selection for storage boxes and providers that do not use port 22.
  - Improve SSH key guidance and remote directory checks.
  - Add remote free-space and permission checks.

- **Object storage track**
  - Add future support for `rclone`-based targets such as S3-compatible storage, Backblaze B2, Wasabi, or other object storage.
  - Keep this separate from rsync so each target type has a clear workflow.

- **Restore rehearsal workflow**
  - Guide restore testing on a separate VM, not on production.
  - Validate backup files, site name, database restore, files restore, app availability, and login.

- **Backup reports**
  - Show newest backup, backup age, complete set status, storage use, off-VM sync status, and restore-test status.

Candidate commands:

```bash
sudo erpnext-dev configure-rsync-backup-target
sudo erpnext-dev off-vm-capacity-check
sudo erpnext-dev configure-object-backup-target
sudo erpnext-dev restore-rehearsal-wizard
sudo erpnext-dev backup-report
```

---

### Phase 3 — monitoring, alerting, and security hardening

Goal: move from manual checks to reliable ongoing monitoring and practical security posture checks.

Planned work:

- **Monitoring and alerts**
  - Continue local health checks.
  - Add optional alert targets such as email/webhook later.
  - Track failures for services, HTTPS, disk usage, stale backups, and off-VM backup failures.

- **Service recovery planning**
  - Keep automatic recovery conservative.
  - Prefer status, guidance, and manual confirmation before restarting critical services.
  - Add optional controlled restart helpers where safe.

- **Security audit**
  - Review SSH exposure, root login status, password auth, UFW, Fail2Ban, open ports, Nginx exposure, SSL status, unattended upgrades, and reboot requirements.
  - Provide clear recommended fixes without applying destructive changes silently.

- **Patch/reboot awareness**
  - Detect pending security updates and required reboot.
  - Provide maintenance-window guidance.

Candidate commands:

```bash
sudo erpnext-dev monitoring-status
sudo erpnext-dev configure-alerts
sudo erpnext-dev security-audit
sudo erpnext-dev patch-status
sudo erpnext-dev reboot-plan
```

---

### Phase 4 — production lifecycle and updates

Goal: make production maintenance safer and more repeatable.

Planned work:

- **Update preflight**
  - Check disk space, backups, app branches, uncommitted customizations, service state, Python/Node/MariaDB compatibility, and snapshot recommendation before updates.

- **Controlled update workflow**
  - Guide through backup, snapshot reminder, app compatibility check, update, migrate, build, restart, and post-update validation.

- **App and customization inventory**
  - Report installed apps, branches, versions, custom apps, and potential compatibility risks.

- **Production handover report**
  - Generate a redacted operations report for client/internal handover.

Candidate commands:

```bash
sudo erpnext-dev update-preflight
sudo erpnext-dev safe-update-wizard
sudo erpnext-dev app-inventory
sudo erpnext-dev production-report
```

---

### Phase 5 — multi-VM and migration support

Goal: support more realistic operations where local, staging, restore, and production VMs coexist.

Planned work:

- Local-to-production planning.
- Production-to-restore VM validation.
- Staging VM update testing.
- Configuration export/import for installer settings.
- Multi-site awareness where appropriate.

Candidate commands:

```bash
sudo erpnext-dev config-export
sudo erpnext-dev config-import
sudo erpnext-dev staging-plan
sudo erpnext-dev migration-plan
```

---

## Later track: Docker-based ERPNext/Frappe installation

Docker support is planned, but it should be treated as a separate install and operations approach. It should not replace or complicate the current VM-based installer.

Planned Docker research and implementation items:

- Review the official ERPNext/Frappe Docker deployment path.
- Define supported Docker scenarios:
  - local Docker test environment,
  - single-server production Docker deployment,
  - reverse proxy and HTTPS with a real domain,
  - backup and restore for Docker volumes and database containers,
  - app installation and updates in a containerized stack.
- Compare Docker vs VM-native stack:
  - resource use,
  - operational complexity,
  - backup/restore approach,
  - update strategy,
  - troubleshooting experience,
  - production reliability.
- Build a separate Docker quickstart only after the VM production-operations workflow is mature enough.

Possible future commands:

```bash
sudo erpnext-dev docker-plan
sudo erpnext-dev docker-local-quickstart
sudo erpnext-dev docker-production-quickstart
sudo erpnext-dev docker-backup-plan
```

Target status: **later agenda item**.

---

## Near-term priority order

Recommended next patches:

1. **v1.1.13 — Log review and diagnostics**
   - Add compact log summaries and safe support output.

2. **v1.1.14 — VM state report and maintenance dashboard**
   - Add one command to show the complete operational state of the VM.

3. **v1.1.15 — Backup capacity and remote target preflight**
   - Estimate backup growth and validate remote storage before relying on it.

4. **v1.1.16 — Security audit and patch/reboot status**
   - Make VM security and maintenance posture easier to review.

5. **v1.2.0 — Restore rehearsal workflow**
   - Mature backup confidence by testing restores on a disposable VM.

6. **v1.2.x — Object storage backup target**
   - Add rclone/object-storage support after rsync flow is stable.

Docker work should start only after these VM production operations are stable.

---

## Definition of production-operations maturity

The VM track can be considered mature when the installer can clearly answer these questions:

- Is ERPNext running and reachable?
- Is HTTPS healthy?
- Are only intended ports exposed?
- Are local backups complete and recent?
- Are off-VM backups configured and recent?
- Is there enough storage for the retention policy?
- Has a restore rehearsal been completed recently?
- Are services healthy?
- Are logs clean enough or are there actionable warnings?
- Are security basics in place?
- Are updates pending?
- Is a reboot required?
- Is there a safe update plan?
- Can a redacted support bundle/report be generated?

Once these are reliably covered, the VM-based installer will be ready for broader production use and the Docker track can be started with a stable operations model already established.


## Local dev host mapping checkpoint

- Local development setup now treats host `/etc/hosts` mapping as a required checkpoint before local HTTPS.
- Future host-side companion tooling may automate KVM/libvirt DHCP reservations and host `/etc/hosts` updates directly from the host.
