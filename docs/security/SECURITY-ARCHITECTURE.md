# Security Architecture

**Applies to:** ERPNext Developer Toolkit `v1.20.x`

This document explains the current technical security model. Policy and vulnerability reporting remain authoritative in [SECURITY.md](../../SECURITY.md).

## Scope

ERPNext Developer Toolkit is a privileged Bash-based installation and operations toolkit for ERPNext and Frappe. It supports native and Docker deployment engines on local virtual machines and public servers.

The toolkit manages host packages, configuration, services, HTTPS, firewall rules, backups, restore rehearsals, optional applications, diagnostics, updates, and rollback.

## Primary assumptions

The design assumes:

- A dedicated ERPNext host
- Trusted server administrators
- A maintained supported operating system
- Protected SSH and provider accounts
- Verified signed toolkit releases
- Explicit production change control
- Separate ERPNext application-level access governance

A compromised root account is outside the protection boundary.

## Trust boundaries

| Boundary | Trusted for | Operator requirement |
|---|---|---|
| Operating system | Kernel, package manager, filesystems, service manager | Apply security updates and restrict administrative access |
| GitHub release | Distribution of toolkit release assets | Verify signed checksums and the pinned fingerprint |
| Maintainer signing key | Authenticity of `SHA256SUMS` | Verify the fingerprint through a trusted channel |
| Cloud or hypervisor | Network, storage, snapshots, VM lifecycle | Secure account, firewall, snapshots, and recovery access |
| DNS and certificate provider | Domain routing and certificate issuance | Protect accounts and validate DNS changes |
| ERPNext/Frappe | Application authentication and business permissions | Configure users, roles, 2FA, and data policy |
| Backup provider | Off-site durability | Protect credentials, retention, encryption, and deletion policy |

## Privileged execution

The toolkit requires `sudo` or root for operations that change the host. Privileged commands are explicit, named workflows rather than a general-purpose remote shell API.

Examples include:

- Package installation
- Service and runtime configuration
- Nginx and certificate management
- Firewall and Fail2Ban changes
- Backup scheduling
- Versioned toolkit installation
- ERPNext/Frappe update operations

Interactive workflows present checkpoints before destructive or high-impact changes. Non-interactive execution is intended for controlled automation and still passes through validation gates.

## Modular integrity

The installed toolkit uses a thin `erpnext-dev.sh` dispatcher and runtime modules under `lib/`.

Release integrity is based on:

1. `RELEASE-MANIFEST.txt` as the allowed release inventory
2. `SHA256SUMS` as the exact checksum inventory
3. `SHA256SUMS.asc` as the detached signature over the checksum inventory
4. A pinned maintainer signing-key fingerprint
5. `verify-toolkit` checking the active script and runtime modules
6. Rejection of unexpected runtime modules

The manifest parser rejects unsafe entries including:

- Duplicates
- Absolute paths
- Parent-directory traversal
- Missing files
- Directories
- Symbolic links
- Whitespace-containing entries

The checksum inventory must match the manifest exactly, except that `SHA256SUMS` does not checksum itself.

## Atomic toolkit installation

A verified toolkit release is installed into:

```text
/opt/erpnext-dev/releases/<version>/
```

The active stable and CLI pointers change only after the new release passes its verification and installation gates.

Security properties:

- A corrupt archive is rejected.
- A missing or invalid stable signature is rejected.
- A signer-fingerprint mismatch is rejected.
- A checksum mismatch is rejected.
- A partially staged release does not become active.
- The previous release remains available for `toolkit-rollback`.

Toolkit rollback changes the toolkit version. It does not restore ERPNext business data.

## Concurrency and lock safety

Single-instance operations use a private lock directory selected by identity.

- Root uses `/run/lock/erpnext-dev/`.
- A normal user prefers `${XDG_RUNTIME_DIR}/erpnext-dev/`.
- The fallback is a UID-specific directory under `/tmp`.

The lock directory must be privately owned, and unsafe symbolic-link paths are refused. Lock files are not world writable.

This prevents unprivileged users on a multi-user host from pre-planting a shared lock path that a later root process would follow.

## Credential handling

Generated credentials are written to restricted files for installation handoff and recovery.

Controls include:

- Restrictive file permissions
- Dedicated status and hardening commands
- Direct terminal output for `credentials-show`
- Refusal to print credentials without a controlling terminal
- No `set -x` around secret handling
- Exclusion of known credential files from support bundles

Credentials should be transferred to a password manager and removed or restricted locally.

## Backup transport credentials

The toolkit separates backup destinations from authentication secrets.

### SSH and rsync

Toolkit configuration stores:

- Destination coordinates
- Remote path
- SSH identity-file path

The SSH private key remains operator managed.

### Object storage

Toolkit configuration stores:

- `rclone` remote name
- Bucket or container
- Prefix

Cloud credentials remain in the standard `rclone` configuration. The toolkit does not copy them into ordinary toolkit environment files.

## Network exposure

The toolkit distinguishes:

- Local development VM
- Public production VPS
- Backup server
- Disposable restore environment

Public production should expose only the required public services. Bench, Redis, MariaDB, and internal runtime ports should not be internet accessible.

Docker requires special attention because published container ports can bypass assumptions based only on ordinary UFW input rules. Provider, hypervisor, and `DOCKER-USER` controls may also be required.

Security checks report configuration state, but provider firewall state remains an external control that must be verified separately.

## HTTPS and domain trust

Production HTTPS depends on:

- Correct DNS
- Protected DNS-provider access
- Correct reverse-proxy configuration
- Certificate issuance and renewal
- Appropriate Cloudflare or direct-origin mode
- Blocking direct exposure of internal runtime ports

Local `.test` HTTPS is a development convenience and depends on trust installed on the host browser machine. It is not a substitute for public DNS or production certificate policy.

## Backup and restore security

Backups may contain all ERPNext business data and must be treated as sensitive.

Controls and expectations:

- Restrict backup directories and transfer credentials.
- Keep at least one off-host copy.
- Verify archive structure and readability.
- Rehearse restore in an isolated environment.
- Confirm application health after restore.
- Do not expose backup servers or storage credentials publicly.
- Define retention, deletion, and encryption policies outside the toolkit.

Restore rehearsal reduces recovery uncertainty but does not replace an organisational disaster-recovery plan.

## Diagnostics and redaction

Support bundles collect operational evidence while excluding known high-risk files and values.

Redaction covers common patterns, but it is heuristic. Application-specific secrets, custom fields, customer data, or unusual tokens may not be recognised.

Operators must inspect both the archive inventory and extracted content before sharing.

## CI and repository controls

The project uses:

- ShellCheck
- Hermetic shell tests
- Release-tree validation
- Release-manifest consistency checks
- Whole-tree bundle verification
- Atomic update and rollback smoke tests
- Gitleaks
- CodeQL for supported workflow content
- OpenSSF Scorecard
- Pinned GitHub Actions
- Dependabot updates for action pins
- Pull-request checks on protected branches
- Tag-triggered validation and integration before publication

Workflow permissions default to read-only. The publish job receives `contents: write` only for release creation and asset upload.

## Threat summary

| Threat | Primary control | Residual risk |
|---|---|---|
| Modified release artifact | Signed checksum inventory and whole-tree verification | Compromised maintainer signing key |
| Partial toolkit update | Versioned staging and atomic pointer switch | Compromised root host |
| Unexpected runtime module | Manifest and `verify-toolkit` inventory checks | Malicious code already trusted in a signed release |
| Shared lock-path attack | Private owned lock directories and symlink rejection | Compromised privileged user |
| Credential leakage in logs | Direct TTY output and restricted credential files | Screenshots, terminal recording, operator copying |
| Public internal ports | Firewall profiles and exposure diagnostics | External provider rules or Docker forwarding misconfiguration |
| Unrecoverable backup | Verification and restore rehearsal | Provider loss, missing encryption key, stale rehearsal |
| Secret leakage in support bundle | Exclusions, redaction, operator review | Unrecognised custom secret |
| Malicious CI dependency movement | Actions pinned to immutable commits | Compromised pinned upstream commit or GitHub platform |
| Unauthorised signed release | Protected signing environment and fingerprint pin | Signing-key theft or authorised-account compromise |

## Design limitations

The toolkit is not a sandbox. It performs real privileged host changes.

It does not provide:

- Host intrusion detection
- Endpoint protection
- Secret-manager hosting
- Cloud account governance
- ERPNext role design
- Database encryption-key custody
- Legal or regulatory compliance certification
- High-availability orchestration
- Protection from a malicious trusted administrator

Use layered controls and treat the toolkit as one part of the production security model.
