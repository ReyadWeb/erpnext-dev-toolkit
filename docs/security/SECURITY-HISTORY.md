# Security Implementation History

This document preserves the important security milestones that were previously mixed into the repository-level security policy.

It is historical context, not the active policy. Use [SECURITY.md](../../SECURITY.md) for current support, reporting, guarantees, and limitations.

## Release-trust foundation

| Milestone | Security change |
|---|---|
| `v1.1.69–v1.1.72` | Tag-pinned downloads, SHA256 checksums, `verify-toolkit`, CI, and repeatable release validation |
| `v1.3.0` | GPG-signed checksum inventory and `verify-signature` |
| `v1.6.0` | Stable signing became mandatory and publication became gated by validation and integration |
| `v1.7.0` | Private identity-specific lock directories and symbolic-link rejection |
| `v1.8.x` | Atomic update and rollback smoke tests, tamper negatives, and self-update signature enforcement |
| `v1.9.0` | Signing key moved to the protected `release-signing` environment |
| `v1.9.1` | GitHub Actions pinned to immutable commits and managed through Dependabot |
| `v1.18.0` | Gitleaks, CodeQL-supported workflow analysis, OpenSSF Scorecard, and pinned-action checks |
| `v1.18.2` | Repository rules, required checks, CODEOWNERS, and governance improvements |
| `v1.20.0` | Canonical `VERSION`, authoritative release manifest, exact checksum coverage, transactional beta/stable promotion, strict pre-tag gate, and regression-tested signed bootstrap guidance |

## Modularisation and integrity

The toolkit evolved from a large single script into a dispatcher plus runtime modules.

Important stages included extraction of:

- Shared helpers
- Support and diagnostics
- Backup and restore
- HTTPS and firewall
- Applications
- Health
- Storage
- Service management
- Installation
- Configuration
- Access and credentials
- Frappe helpers
- Status
- Operations
- Docker and engine routing
- Dashboard, healing, menu, security, and update logic

The current release verifies runtime modules against the release checksum inventory and reports unexpected modules.

## Retired risks

### Shared lock path

Earlier versions used a predictable world-shared lock location under `/tmp`. The current design uses a private owned lock directory and rejects unsafe symbolic-link paths.

### Monolithic privileged script

Earlier versions concentrated most behaviour in one large root-level script. The current modular tree improves reviewability and allows runtime-module integrity checking.

### Checksum-only release trust

Checksums alone do not authenticate the checksum publisher. Stable releases now require a detached signature and pinned maintainer fingerprint.

### Partial self-update

The current updater stages a complete verified tree and changes the active pointer only after verification succeeds.

### Raw two-file bootstrap guidance

Earlier instructions downloaded only `erpnext-dev.sh` and `SHA256SUMS`, which was incompatible with the modular release inventory. `v1.20.0` replaced that model with complete signed release-archive guidance and regression tests.

## Credential and diagnostic improvements

Security work added:

- Restricted credential files
- Direct controlling-terminal output for secret display
- Credential status, hardening, and deletion commands
- Backup transport configuration that avoids storing cloud credentials in ordinary toolkit files
- Support-bundle exclusions and redaction
- Negative tests for common secret patterns
- Operator review guidance before sharing diagnostic archives

## CI and governance history

The repository added:

- ShellCheck
- Hermetic regression tests
- Release-tree validation
- Disposable installation and recovery tests
- Gitleaks
- OpenSSF Scorecard
- CodeQL-supported workflow analysis
- Pinned GitHub Actions
- Dependabot
- Required pull-request checks
- Protected release-signing environment
- Stable-tag publication gates

Some governance controls remain constrained by the project's solo-maintainer model. Required automated checks and an auditable pull-request flow remain the primary review controls when independent approval is unavailable.

## Historical evidence

Detailed release-by-release history remains in:

- [CHANGELOG.md](../../CHANGELOG.md)
- [Release automation](../RELEASE-AUTOMATION.md)
- [Testing guide](../../TESTING.md)
- Git history and release records

Historical infrastructure addresses, temporary production examples, and obsolete future-version plans were intentionally removed from the active security documentation.
