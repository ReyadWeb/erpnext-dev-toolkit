## v1.6.0 release governance and atomic self-update

v1.6.0 turns release integrity from "available" into "enforced":

- **Publishing is gated on the full test pipeline.** `release.yml` is now a
  single tag pipeline — `validate` (shellcheck + `validate-release.sh` + bundle
  quickstart) → `integration` (a real disposable-VM install + backup/restore
  round-trip + production-runtime conversion) → `publish`. The publish job
  `needs: [validate, integration]`, so a release can never be published unless
  both gates pass first. A compromised or broken tree fails before any artifact
  is shipped.
- **Signing is mandatory for stable tags.** A stable `vX.Y.Z` tag FAILS the
  release if the signing key is missing or signing/verification fails — it no
  longer silently publishes unsigned. The only unsigned path is an explicit
  emergency pre-release tag (e.g. `vX.Y.Z-unsigned`), which is marked as a
  GitHub pre-release.
- **Self-update is atomic and checksum-gated.** `update-toolkit` downloads the
  release bundle, verifies whole-tree checksums (`sha256sum -c`), extracts to
  `/opt/erpnext-dev/releases/<ver>/`, then flips `/opt/erpnext-dev/current` with
  a single atomic `rename`. The previous release is retained for instant
  `toolkit-rollback`. As of **v1.8.2**, staged signature verification on the tag
  channel matches bootstrap `verify-signature`: signature, gpg, bundled pubkey, and
  pinned maintainer fingerprint are all required (fail closed).
- **Symlink resolution fix.** The entry script resolves its own real path
  (`readlink -f`) before locating `lib/`, so running through the CLI symlink or
  the `current` release symlink always sources modules from the real, verified
  release directory.

## v1.3.0 signed releases (Phase C P0 milestone)

v1.3.0 adds maintainer-identity verification on top of the existing SHA256 integrity workflow: a `release.yml` workflow signs `SHA256SUMS` with the maintainer GPG key on every `v*` tag and attaches `SHA256SUMS.asc` to the GitHub Release, and a new `verify-signature` command verifies that signature. See "Verifying release signatures" below. This closes the gap noted under P0: SHA256-only verification cannot detect an attacker who controls both the script and its checksum, whereas a signature they cannot forge can.

## v1.2.0 Phase C security hardening

v1.2.0 adds `lib/security.sh` with `security-audit`, checksum-gated tag-pinned `update-toolkit`, production credential handoff prompts, and expanded support-bundle audit patterns.

## v1.1.90 ops module extraction — Phase B complete

v1.1.90 extracts the production operations dashboard into `lib/ops.sh`. Next: Phase C security hardening (v1.2.0).

## v1.1.89 status module extraction

v1.1.89 extracts install/runtime status helpers into `lib/status.sh`.

## v1.1.88 frappe module extraction and dispatcher thinning

v1.1.88 extracts Frappe/bench helpers into `lib/frappe.sh` and removes duplicate support/doctor code from the main script.

## v1.1.87 access module extraction

v1.1.87 extracts browser access, host DNS, networking guides, and credentials UI into `lib/access.sh`.

## v1.1.86 config module extraction

v1.1.86 extracts site and domain configuration into `lib/config.sh`.

## v1.1.85 install module complete (Tiers A–C)

v1.1.85 completes `lib/install.sh` with guided setup, local/public quickstarts, and first-run wizard workflows.

## v1.1.84 install Tier B extension

v1.1.84 extends `lib/install.sh` with post-install checkpoint and summary helpers.

## v1.1.83 install module extraction (Tier A)

v1.1.83 extracts install preflight, system package setup, Frappe stack bootstrap, and install/repair/uninstall commands into `lib/install.sh`. Install and update paths keep the full toolkit `lib/` tree under `/opt/erpnext-dev/lib/`.

## v1.1.82 service module extraction

v1.1.82 extracts ERPNext systemd service management and runtime state helpers into `lib/service.sh`. Install and update paths keep the full toolkit `lib/` tree under `/opt/erpnext-dev/lib/`.

## v1.1.81 storage module extraction

v1.1.81 extracts root storage detection, status, and expansion helpers into `lib/storage.sh`. Install and update paths keep the full toolkit `lib/` tree under `/opt/erpnext-dev/lib/`.

## v1.1.80 health module extraction

v1.1.80 extracts health checks, timers, go-live validation, and production readiness helpers into `lib/health.sh`. Install and update paths keep the full toolkit `lib/` tree under `/opt/erpnext-dev/lib/`.

## v1.1.79 app library module extraction

v1.1.79 extracts curated Frappe app profiles, install wizards, and compatibility helpers into `lib/apps.sh`. Install and update paths keep the full toolkit `lib/` tree under `/opt/erpnext-dev/lib/`.

## v1.1.78 SSL and firewall module extraction

v1.1.78 extracts production and local SSL/HTTPS helpers into `lib/ssl.sh` and firewall/UFW/Fail2Ban helpers into `lib/firewall.sh`. Install and update paths keep the full toolkit `lib/` tree under `/opt/erpnext-dev/lib/`.

## v1.1.77 backup module extraction

v1.1.77 extracts local backup, off-VM backup, restore, and rehearsal helpers into `lib/backup.sh`. Install and update paths keep the full toolkit `lib/` tree under `/opt/erpnext-dev/lib/`.

## v1.1.76 support module extraction

v1.1.76 extracts doctor, support-bundle, support-bundle audit, and command-audit helpers into `lib/support.sh`. Install and update paths keep `/opt/erpnext-dev/lib/support.sh` beside the stable toolkit script.

## v1.1.75 modularization and shellcheck

v1.1.75 extracts shared helpers into `lib/common.sh` and adds `scripts/run-shellcheck.sh` to CI. Install and update paths now keep `/opt/erpnext-dev/lib/common.sh` beside the stable toolkit script.

# Security Policy and Threat Model

## Scope

This document describes the security posture, assumptions, and improvement plan for the ERPNext Developer Toolkit. The toolkit is a Bash-based installer and operations toolkit for ERPNext/Frappe on Ubuntu 24.04 and Ubuntu 26.04 VMs.

The current validated production path includes:

```text
Production site: erp.flowmaya.com
Production VPS: 65.109.221.4
Backup server: 65.109.220.250
Cloudflare Origin CA / Nginx HTTPS
UFW and Fail2Ban
Local scheduled backups
Off-VM rsync backups
Disposable restore rehearsal
Health monitoring
Go-live validation record
Redacted support bundle evidence
```

The toolkit can help build and operate a production-candidate VM, but it is not a replacement for cloud-provider controls, password management, application-layer ERPNext security, or organization-specific security governance.

## Security model

### What the toolkit protects

The toolkit is designed to reduce common operational risks:

- accidental production exposure of Bench ports such as `8000`, `9000`, Redis ports, and MariaDB;
- missing local backup and off-VM backup workflows;
- untested disaster recovery;
- untracked restore rehearsal evidence;
- accidental sharing of private keys, credentials, tokens, or raw `site_config.json` values in support bundles;
- unclear distinction between local development VM, production VPS, backup server, and disposable restore VM;
- unsafe firewall changes without status and rollback awareness.

### What remains operator responsibility

Operators remain responsible for:

- cloud-provider account security;
- cloud firewall rules and provider snapshot policy;
- DNS and Cloudflare account security;
- SSH account policy and administrator IP restrictions;
- ERPNext users, roles, passwords, two-factor authentication, and business permissions;
- secure storage of generated credentials in a password manager;
- periodic restore drills after major upgrades, migration, or backup-policy changes;
- verifying release integrity before running toolkit updates as root.

## Key security findings

### P0: Bootstrap trust and release integrity

The highest-priority security gap is release trust. Convenience bootstrap commands that download from GitHub and run with `sudo` are powerful but high trust. A compromised repository, account, branch, network path, or operator copy/paste mistake could result in root execution on the target VM.

The preferred direction is now partially implemented:

1. install from pinned release tags instead of `main`;
2. publish SHA256 checksums per release;
3. document checksum verification before `sudo` execution;
4. add a `verify-toolkit` command that reports installed path, installed version, installed SHA256, and match/mismatch against a known checksum when available; **implemented in v1.1.71**;
5. GPG-signed releases; **implemented in v1.3.0** and made **mandatory for stable tags in v1.6.0** (`release.yml` signs `SHA256SUMS`; `verify-signature` checks it), with publishing **gated on CI + a real integration run**. As of **v1.8.0**, the stable-tag signing decision is extracted into `scripts/release-signing-policy.sh` and unit-tested in CI (a stable tag without a signing key must fail; pre-release escape hatch tags may publish unsigned).

v1.1.70 implements items 1-3 for the `erpnext-dev.sh` script artifact by adding `SHA256SUMS` and tag-pinned README examples. v1.1.71 implements item 4 with `verify-toolkit`. v1.1.72 adds minimal CI and `scripts/validate-release.sh` so release checks are repeatable before publishing tags. v1.3.0 implements item 5. **v1.8.0** adds CI proof that atomic `update-toolkit` / `toolkit-rollback` flip the `current` symlink correctly and that a corrupt bundle is rejected without half-applying, plus negative `verify-toolkit` tamper tests on extracted bundles and live installs. Operators should prefer the verified, signed tag workflow for production systems. The mutable `main` branch raw URL remains a development convenience path only.

With signing enabled, verification is no longer integrity-only: SHA256 proves the files match the checksum list, and the GPG signature proves the checksum list itself came from the maintainer. An attacker who changes both the script and its checksum can no longer defeat verification without also forging the maintainer signature.

### Pinned bootstrap toolchain (reproducibility)

The install path still runs external bootstrap installers (nvm, uv), but every moving version is pinned so installs are reproducible and auditable: `NODE_VERSION`, `NVM_VERSION`, `UV_VERSION`, `PYTHON_VERSION`, `FRAPPE_BRANCH`, `ERPNEXT_BRANCH`, and (as of v1.7.0) `BENCH_VERSION` for the `frappe-bench` CLI. These live as a single source of truth in `erpnext-dev.sh` and are surfaced by `erpnext-dev versions`, `where-installed`, and the support bundle. Each is override-able by env var; `BENCH_VERSION=` (empty) intentionally unpins `frappe-bench`.

### Verifying release signatures

**Operator (maintainer) one-time setup** — required to activate signing:

1. Generate a signing key (once): `gpg --full-generate-key` (Ed25519 or RSA 4096).
2. Export the private key and add it as an **environment** secret `GPG_PRIVATE_KEY`
   (and `GPG_PASSPHRASE` if the key is protected) in the `release-signing` environment:
   `gpg --armor --export-secret-keys <KEYID>` → paste into the environment secret.
   See "Signing authority separation (v1.9.0)" below for the full environment setup.
3. Publish the public key and its fingerprint (in this file and/or the repository), so users can pin it:
   `gpg --armor --export <KEYID>` and `gpg --fingerprint <KEYID>`.

Once `GPG_PRIVATE_KEY` is available to the `publish` job, `release.yml` signs `SHA256SUMS` on every `v*` tag and attaches `SHA256SUMS.asc` to the release. As of v1.6.0 this is **required** for stable `vX.Y.Z` tags: if the key is missing, the release fails rather than shipping unsigned. An unsigned build is only possible via an explicit emergency pre-release tag such as `vX.Y.Z-unsigned`. As of v1.9.0 the key lives in the protected `release-signing` environment, so signing also requires the environment's reviewer approval.

**End-user verification** — before running the toolkit as root:

```bash
# Download the artifacts from the release (tag-pinned):
VERSION="vX.Y.Z"
base="https://github.com/ReyadWeb/erpnext-dev-installer/releases/download/${VERSION}"
curl -fsSLO "${base}/erpnext-dev.sh"
curl -fsSLO "${base}/SHA256SUMS"
curl -fsSLO "${base}/SHA256SUMS.asc"

# Import the maintainer public key once, then verify signature + checksums:
curl -fsSL "https://github.com/ReyadWeb.gpg" | gpg --import   # or the published key
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

Or use the toolkit, which runs the same check in a throwaway keyring and pins the fingerprint automatically. When run from a checkout (or the installed `/opt/erpnext-dev` tree) it uses the bundled public key at `docs/erpnext-dev-signing-key.asc` and the fingerprint baked into the script, so no configuration is needed:

```bash
sudo erpnext-dev verify-signature      # zero-config: bundled key + pinned fingerprint
sudo erpnext-dev verify-toolkit        # then confirm files match the signed checksums
```

To override (e.g. fetch the key from an independent channel), set `TOOLKIT_SIGNING_PUBKEY` (path or https URL) and/or `TOOLKIT_SIGNING_KEY_FINGERPRINT` before running.

**Maintainer signing key (pin this):**

```text
Key type:    Ed25519 (sign)
UID:         ERPNext Dev Installer Signing Key <235979268+ReyadWeb@users.noreply.github.com>
Fingerprint: BFC1 0C79 427C F734 96EA  6F5A 30BF D17D D559 C8B6
```

The public key is published in this repository at [`docs/erpnext-dev-signing-key.asc`](docs/erpnext-dev-signing-key.asc). Because it ships alongside the script, the real trust anchor is the fingerprint above (also baked into `lib/security.sh`): verify the fingerprint out-of-band before trusting a fresh download.

### P1: Plaintext credentials on disk

The toolkit creates credentials files for operator convenience. These files are useful during installation and recovery, but they should not become long-term secret storage.

Recommended operator workflow:

1. retrieve credentials only on the server console or trusted SSH session;
2. copy them to a password manager;
3. run the toolkit credential status/security commands;
4. remove or restrict local credential files after handoff;
5. never include credential files in tickets, chat, email, screenshots, or support bundles.

Relevant commands include:

```bash
sudo erpnext-dev credentials-info
sudo erpnext-dev credentials-file-status
sudo erpnext-dev credentials-secure
sudo erpnext-dev credentials-delete
```

The toolkit tees its stdout to a log file. To avoid persisting secrets there, `credentials-show` writes the credential block directly to the controlling terminal (`/dev/tty`), never to the logged stream; in a non-interactive session with no terminal it refuses to print and points to the file instead. Generated passwords are otherwise only written to the mode-`600` credentials file and passed to `bench`/`mariadb` as arguments/stdin (no `set -x`), so they do not reach the install log.

### P1: Redacted support bundles are defensive, not perfect

Support bundles intentionally exclude private keys, raw credential files, `site_config.json` secrets, tokens, and password-like values. Redaction is still heuristic. Operators should review archive contents before sharing externally.

Recommended review:

```bash
latest_bundle="$(ls -t /tmp/erpnext-dev-support-bundle-*.tar.gz | head -n 1)"
echo "$latest_bundle"
tar -tzf "$latest_bundle"
mkdir -p /tmp/erpnext-support-review
tar -xzf "$latest_bundle" -C /tmp/erpnext-support-review
```

### Resolved: root-level monolithic script risk

The toolkit was a single large Bash script. As of the Phase B work it is a thin
`erpnext-dev.sh` entry/dispatcher sourcing 17 `lib/*.sh` modules, each verified
against `SHA256SUMS` by `verify-toolkit`. The former monolith audit/regression
risk is retired.

### Resolved: lock-file hardening (multi-user hosts)

Earlier releases put the single-instance lock in a predictable, world-shared
path (`/tmp/erpnext-dev-locks/toolkit.lock`, dir mode `1777`, file mode `666`)
and created it with a truncate that followed symlinks — so on a multi-user host
an unprivileged user could pre-plant the path as a symlink and have a later root
run follow/truncate it.

As of v1.7.0 the lock lives in a private directory chosen by identity: root uses
`/run/lock/erpnext-dev/` (root-owned tmpfs), a normal user uses
`${XDG_RUNTIME_DIR}/erpnext-dev/`, falling back to `/tmp/erpnext-dev-<uid>-locks/`.
The directory is created mode `0700` and must be owned by us (or root); a
symlinked lock directory or lock file is refused before any open/truncate, and
the lock file itself is mode `0600` (no more `1777`/`666`). This closes the
shared-`/tmp` symlink-redirect risk.

## Release security status and roadmap

### External review summary (July 2026)

Independent review of v1.8.1 classifies the toolkit as **enterprise-candidate**
for dedicated single-admin Ubuntu VM deployments (**9.4 / 10** in that scope).
Ten prior architectural blockers are **resolved** — production Supervisor runtime,
CLI install/repair, full module integrity, lock hardening, gated CI integration,
stable signing at publish time, atomic updates, support-bundle negatives, and
pinned toolchain. Full detail: [`ROADMAP.md`](ROADMAP.md#external-security-review--resolved-blockers-v181).

**One P0 gap remains on the consumer (self-update) path** — documented below.

### Implemented (v1.6.0 – v1.9.1)

- **Gated publish:** validate → integration → sign → publish on every stable tag
- **Mandatory signing** for stable tags (`vX.Y.Z`); pre-release tags may publish unsigned
- **Full-tree integrity:** `verify-toolkit` checks entrypoint + all 17 modules
- **Atomic self-update:** bundle verify + signature/fingerprint gate + `releases/<ver>` + rollback
- **Self-update authenticity (v1.8.2):** tag-channel updates require the same signature
  and pinned-fingerprint bar as bootstrap `verify-signature`
- **CI supply-chain hardening (v1.9.1):** every GitHub Action is pinned to an immutable
  commit SHA (not a moving tag), Dependabot bumps those pins deliberately, and the
  Ubuntu 26.04 integration leg runs as a non-blocking preview leg alongside 24.04
- **Signing authority separation (v1.9.0):** signing key lives in the protected
  `release-signing` environment; a signed release requires reviewer approval, not just
  repository write access
- **CI proof:** staged signature matrix, atomic update smoke, signing policy tests, tamper negatives

**Current bootstrap workflow:**

```bash
VERSION="v1.8.2"
BASE="https://github.com/ReyadWeb/erpnext-dev-installer/releases/download/${VERSION}"
curl -fsSLO "${BASE}/erpnext-dev-${VERSION}.tar.gz"
tar -xzf "erpnext-dev-${VERSION}.tar.gz" && cd "erpnext-dev-${VERSION}"
sha256sum -c SHA256SUMS
sudo ./erpnext-dev.sh verify-signature
sudo ./erpnext-dev.sh verify-toolkit
```

### Self-update authenticity (v1.8.2)

Tag-channel `update-toolkit` uses `toolkit_gpg_verify_signature_files()` — the same
core as `verify-signature`. For stable release bundles:

| Condition | Policy |
|-----------|--------|
| Missing `SHA256SUMS.asc` | FAIL |
| Missing `gpg` | FAIL |
| Missing bundled pubkey | FAIL |
| Bad signature | FAIL |
| Signer fingerprint ≠ pinned maintainer key | FAIL |

Pinned fingerprint: `BFC10C79427CF73496EA6F5A30BFD17DD559C8B6`

CI runs `scripts/test-staged-signature.sh` (unit matrix) and signed-bundle atomic
update smoke (`scripts/test-atomic-update.sh`).

### Signing authority separation (v1.9.0)

Before v1.9.0 the signing key lived in ordinary **repository** Actions secrets, so
anyone (or any workflow) with repository write access could, in principle, run the
signing step. v1.9.0 separates *signing authority* from *repository write access*:
the `publish` job in [`release.yml`](.github/workflows/release.yml) now runs in a
protected GitHub **Environment** named `release-signing`. The GPG key is stored as an
**environment** secret and is only exposed to a job that clears the environment's
protection rules (a required human approval), so a signed release cannot be produced
by repository write access alone.

**Threat addressed:** a compromised repository token, a malicious workflow change, or
an unattended automation can no longer sign a release. A named reviewer must approve
the deployment to `release-signing` before the key is ever decrypted into a runner.

**One-time maintainer setup (GitHub → Settings → Environments):**

1. Create an environment named exactly `release-signing`.
2. **Required reviewers:** add yourself (and any co-maintainers). Every stable release
   then pauses at `publish` until a reviewer approves.
3. **Deployment tags rule:** restrict deployments to the tag pattern `v*` so only
   release tags can target this environment.
4. **Move the secrets:** add `GPG_PRIVATE_KEY` (and `GPG_PASSPHRASE` if the key is
   protected) as **environment** secrets, then **delete the repository-level**
   `GPG_PRIVATE_KEY` / `GPG_PASSPHRASE`. Environment secrets take precedence, and
   removing the repo-level copies ensures no other job can read the key.

Until the environment is configured, GitHub auto-creates it unprotected on the first
tagged run and signing falls back to the repository secrets — no regression, but also
no protection. Configure the reviewer + tag rule to activate the gate.

**Release flow after v1.9.0:** push a `vX.Y.Z` tag → `validate` and `integration`
run → `publish` shows **Waiting** for `release-signing` approval → an approver
reviews and approves → the key is imported, `SHA256SUMS` is signed, and the release
is published. Denying the approval blocks signing and publishing.

**Key-rotation runbook:**

1. Generate the new signing key offline: `gpg --full-generate-key` (Ed25519 preferred).
2. Update the pinned fingerprint in `lib/security.sh`
   (`TOOLKIT_SIGNING_FINGERPRINT_DEFAULT`) and the public key at
   [`docs/erpnext-dev-signing-key.asc`](docs/erpnext-dev-signing-key.asc), and refresh
   the fingerprint block in this file. Land these on `main` before tagging.
3. Replace the `GPG_PRIVATE_KEY` (and `GPG_PASSPHRASE`) **environment** secrets in
   `release-signing` with the new key material.
4. Revoke/retire the old key locally and publish its revocation if it was ever public.
5. Cut the next stable tag; `verify-signature` on the new release must report the new
   fingerprint. Signatures made by the retired key no longer validate, by design.

> Note: signatures made by an old key stop validating once the pinned fingerprint
> changes. This is intentional — communicate rotations in release notes so operators
> re-pin. Historical releases keep their original (now-untrusted) signatures.

### Implemented — v1.9.1 (CI supply-chain hardening)

- **Actions pinned to commit SHAs.** `actions/checkout` and `actions/upload-artifact`
  are pinned to immutable commit SHAs (with `# vX.Y.Z` comments) in all three
  workflows, so a compromised or retagged action version cannot silently enter CI.
- **Dependabot.** [`.github/dependabot.yml`](.github/dependabot.yml) opens weekly,
  grouped PRs that bump both the pinned SHA and its version comment — updates are
  deliberate and reviewable, never an implicit follow of a moving tag.
- **Ubuntu 26.04 integration leg.** Added to the integration matrix as a non-blocking
  preview leg (`continue-on-error` via `matrix.experimental`); Ubuntu 24.04 stays the
  mandatory release gate. Flip the 26.04 leg to blocking once the runner image is GA.

### Planned — v1.10.0 (object-storage backups)

S3-compatible off-site backup target alongside rsync — after v1.9.1.

### Historical milestones (implemented)

<details>
<summary>v1.1.69 – v1.1.72 release-trust foundation</summary>

- v1.1.70: SHA256 checksums and tag-pinned bootstrap
- v1.1.71: `verify-toolkit`
- v1.1.72: GitHub Actions CI and `scripts/validate-release.sh`

</details>

## Reporting security issues

Report suspected security issues **privately** before public disclosure.

1. Email or direct message the project maintainer with:
   - toolkit version (`erpnext-dev version`);
   - OS version (`/etc/os-release`);
   - command used;
   - redacted logs or support-bundle audit output;
   - environment type (local dev VM, production VPS, backup server, restore VM).
2. Do **not** include passwords, private keys, API tokens, raw `site_config.json`, database dumps, or customer data.
3. Allow reasonable time for investigation and a fix before public discussion.
4. For urgent production exposure (e.g. credentials left on a public-facing VM), run `sudo erpnext-dev security-audit` and `sudo erpnext-dev credentials-delete` after password-manager handoff while waiting for maintainer response.

## v1.2.0 Phase C security hardening
