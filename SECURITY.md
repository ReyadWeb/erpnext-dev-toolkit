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
5. GPG-signed releases; **implemented in v1.3.0** (`release.yml` signs `SHA256SUMS`; `verify-signature` checks it).

v1.1.70 implements items 1-3 for the `erpnext-dev.sh` script artifact by adding `SHA256SUMS` and tag-pinned README examples. v1.1.71 implements item 4 with `verify-toolkit`. v1.1.72 adds minimal CI and `scripts/validate-release.sh` so release checks are repeatable before publishing tags. v1.3.0 implements item 5. Operators should prefer the verified, signed tag workflow for production systems. The mutable `main` branch raw URL remains a development convenience path only.

With signing enabled, verification is no longer integrity-only: SHA256 proves the files match the checksum list, and the GPG signature proves the checksum list itself came from the maintainer. An attacker who changes both the script and its checksum can no longer defeat verification without also forging the maintainer signature.

### Verifying release signatures

**Operator (maintainer) one-time setup** — required to activate signing:

1. Generate a signing key (once): `gpg --full-generate-key` (Ed25519 or RSA 4096).
2. Export the private key and add it as the repository secret `GPG_PRIVATE_KEY` (and `GPG_PASSPHRASE` if the key is protected):
   `gpg --armor --export-secret-keys <KEYID>` → paste into the Actions secret.
3. Publish the public key and its fingerprint (in this file and/or the repository), so users can pin it:
   `gpg --armor --export <KEYID>` and `gpg --fingerprint <KEYID>`.

Once `GPG_PRIVATE_KEY` is set, `release.yml` signs `SHA256SUMS` on every `v*` tag and attaches `SHA256SUMS.asc` to the release. Until then, releases publish unsigned (with a CI warning).

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

### P1: Root-level monolithic script risk

The toolkit is currently a large Bash script. This keeps installation simple and portable, but it increases audit and regression risk. Modularization should happen after the release-integrity and CI foundations are in place.

Recommended direction:

```text
erpnext-dev.sh             thin entry point and command dispatcher
lib/common.sh              logging, prompts, locks, shared helpers
lib/install.sh             install and preflight
lib/ssl.sh                 local and production SSL
lib/firewall.sh            UFW, Fail2Ban, rollback helpers
lib/apps.sh                curated app install library
lib/health.sh              health check and timers
lib/storage.sh             root storage detection and expansion
lib/service.sh             ERPNext systemd service and runtime state
lib/install.sh             install and preflight (Tier A core engine)
lib/backup.sh              local backup and retention
lib/offvm-backup.sh        off-VM backup setup and rsync
lib/restore.sh             restore preflight and rehearsal
lib/support.sh             support bundle and diagnostics
```

## Recommended release-security roadmap

### v1.1.69

Add this `SECURITY.md` and the companion `RELIABILITY-PLAN.md`. Document the threat model, bootstrap trust issue, release verification plan, credential handling expectations, and support-bundle limitations.

### v1.1.70

Implemented: release checksum artifacts and tag-pinned install instructions for `erpnext-dev.sh`.

Current workflow:

```bash
VERSION="v1.1.72"
curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/${VERSION}/erpnext-dev.sh"
curl -fsSLO "https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/${VERSION}/SHA256SUMS"
sha256sum -c SHA256SUMS
chmod +x erpnext-dev.sh
sudo ./erpnext-dev.sh start-here
```

### v1.1.71

Adds `verify-toolkit`, which checks the active/installed toolkit hash and reports whether it matches a known checksum file when present.

### v1.1.72

Add minimal GitHub Actions CI:

- `bash -n erpnext-dev.sh`;
- version check;
- help output smoke test;
- menu self-test where safe;
- release package file audit;
- grep checks for accidentally included credentials or `GITHUB-UPDATE-v*.md` files.

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
