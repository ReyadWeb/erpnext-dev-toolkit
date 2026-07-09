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
5. optionally add GPG-signed releases after the checksum workflow is stable.

v1.1.70 implements items 1-3 for the `erpnext-dev.sh` script artifact by adding `SHA256SUMS` and tag-pinned README examples. v1.1.71 implements item 4 with `verify-toolkit`. v1.1.72 adds minimal CI and `scripts/validate-release.sh` so release checks are repeatable before publishing tags. Operators should prefer the verified tag workflow for production systems. The mutable `main` branch raw URL remains a development convenience path only.

This is integrity verification, not maintainer identity verification. A malicious actor who can change both the script and checksum in the release can still defeat SHA256-only verification. GPG-signed releases remain a later optional hardening milestone.

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
lib/backup.sh              local backup and retention
lib/offvm-backup.sh        off-VM backup setup and rsync
lib/restore.sh             restore preflight and rehearsal
lib/health.sh              health check and timers
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

For now, report suspected security issues privately to the project maintainer before public disclosure. Include:

- toolkit version;
- operating system version;
- command used;
- redacted logs or support bundle evidence;
- whether the system is local development, production VPS, backup server, or disposable restore VM.

Do not include passwords, private SSH keys, API tokens, raw `site_config.json`, database dumps, or unredacted customer data.
