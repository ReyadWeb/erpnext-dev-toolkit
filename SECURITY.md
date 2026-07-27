# Security Policy

**Current release:** v1.20.0

ERPNext Developer Toolkit performs privileged installation and operations work. This policy explains how to report vulnerabilities, which versions receive security attention, what the toolkit protects, and which responsibilities remain with the server operator.

> Report suspected vulnerabilities privately. Do not open a public GitHub issue for security-sensitive reports.

## Supported versions

| Version line | Security status |
|---|---|
| `v1.20.x` | Supported |
| Earlier releases | Upgrade to the current stable release before routine support. Security reports are still accepted when the issue may affect current code or prevents a safe upgrade. |
| Development branches and prereleases | Evaluation only unless a release note explicitly states otherwise |

Check the installed version with:

```bash
erpnext-dev version
```

Update to a specific signed release with:

```bash
sudo env \
  TOOLKIT_UPDATE_VERSION=v1.20.0 \
  erpnext-dev update-toolkit
```

## Reporting a vulnerability

Use GitHub private vulnerability reporting:

https://github.com/ReyadWeb/erpnext-dev-toolkit/security/advisories/new

Do not disclose the issue publicly until a fix and coordinated disclosure plan are ready.

### Include

- Toolkit version from `erpnext-dev version`
- Operating system and version
- Deployment engine: native, Docker development, or Docker production
- Environment type: local VM, public VPS, backup server, or restore VM
- Exact command or workflow involved
- Expected and observed behaviour
- Reproduction steps that do not expose real customer data
- Redacted logs, screenshots, or support-bundle audit output
- Your assessment of impact and whether the issue is actively exploitable

### Do not include

- Passwords
- Private keys
- API or access tokens
- Raw `site_config.json`
- Database dumps
- Customer records
- Unredacted configuration files
- Production backup archives

For ordinary bugs, questions, and compatibility reports, use [SUPPORT.md](SUPPORT.md).

## Response and disclosure

This is a maintainer-led community project and does not promise a formal response-time SLA. Security reports are prioritised over ordinary support requests.

The expected process is:

1. Confirm receipt and establish a private communication channel.
2. Reproduce and assess affected versions and deployment paths.
3. Prepare a fix, tests, documentation, and release plan.
4. Coordinate disclosure with the reporter.
5. Publish a signed release and security advisory when appropriate.

Do not test a suspected vulnerability against systems you do not own or have explicit permission to assess.

## Security model

The toolkit is designed for a dedicated ERPNext host administered by trusted operators. It reduces common installation and operations risks, but it does not replace the security controls of the operating system, cloud provider, DNS provider, ERPNext, Frappe, or the organisation using the system.

### Security boundaries

The toolkit assumes:

- The server administrator and `sudo` users are trusted.
- The operating system and package repositories are trusted and maintained.
- The selected GitHub release and maintainer signing-key fingerprint are verified.
- Provider accounts, DNS accounts, SSH keys, and off-site backup credentials are protected.
- ERPNext users, roles, permissions, and business data are governed separately.
- Operators review and test changes before applying them to production.

### What the toolkit protects

The toolkit provides controls for:

- Signed stable releases
- Whole-tree release checksums
- Canonical release-version and manifest validation
- Atomic versioned toolkit installation
- Rollback to a previously installed toolkit release
- Runtime-module integrity verification
- Guarded privileged workflows
- Private single-instance locks
- Environment-aware firewall and exposure checks
- Credential-file permission checks
- Redacted diagnostics and support bundles
- Backup verification and restore rehearsal
- CI validation, security scanning, and pinned GitHub Actions

Technical details are documented in [Security architecture](docs/security/SECURITY-ARCHITECTURE.md).

### What the toolkit does not guarantee

The toolkit cannot guarantee:

- Security of the cloud, DNS, GitHub, email, or password-manager account
- Correct ERPNext business permissions
- Protection from a compromised root account
- Protection from a compromised operating-system package repository
- Availability of the VPS, network, DNS, or backup provider
- That every secret will be detected by heuristic support-bundle redaction
- That a backup is recoverable unless restore testing succeeds
- Compatibility of every optional application or custom ERPNext modification
- Compliance with organisation-specific legal or regulatory requirements

## Privileged execution

Many commands require root privileges because they install packages, configure services, manage firewall rules, write under `/etc` and `/opt`, or control production runtimes.

The toolkit does not treat arbitrary remote shell execution as an application interface. Privileged operations are explicit toolkit commands with validation, environment checks, and bounded behaviour.

Before running an unfamiliar command:

```bash
erpnext-dev --help
sudo erpnext-dev doctor --plain
sudo erpnext-dev verify-toolkit
```

Review shell scripts before executing them as root, especially when using a development branch or unreviewed local modification.

## Release integrity

Stable releases publish:

```text
erpnext-dev-vX.Y.Z.tar.gz
erpnext-dev.sh
RELEASE-MANIFEST.txt
SHA256SUMS
SHA256SUMS.asc
RELEASE-ASSETS.sha256
RELEASE-ASSETS.sha256.asc
bootstrap-verify.sh
```

Use an exact release tag when referring to the complete published archive:

```bash
VERSION="vX.Y.Z"
archive="erpnext-dev-${VERSION}.tar.gz"
```

Stable tags require the release validation and integration gates to pass before publication. The checksum inventory is signed with the maintainer key, and the release archive contains the complete modular toolkit.

Pinned maintainer fingerprint:

```text
BFC1 0C79 427C F734 96EA  6F5A 30BF D17D D559 C8B6
```

Machine-readable fingerprint: `BFC10C79427CF73496EA6F5A30BFD17DD559C8B6`

The public key is stored at [`docs/erpnext-dev-signing-key.asc`](docs/erpnext-dev-signing-key.asc).

### Pre-privilege release verification

Do not ask downloaded toolkit code to verify itself under `sudo`. Use the
non-privileged release verifier first:

```bash
VERSION="vX.Y.Z"
curl -fsSLO \
  "https://github.com/ReyadWeb/erpnext-dev-toolkit/releases/download/${VERSION}/bootstrap-verify.sh"
chmod +x bootstrap-verify.sh
./bootstrap-verify.sh "$VERSION"
```

The verifier checks the pinned fingerprint, signed external asset inventory,
archive digest, safe archive paths, internal whole-tree checksums, and immutable
build identity before it prints any privileged command. Review the extracted
tree before running the selected command with `sudo`.

The complete verification workflow is in [Release trust](docs/security/RELEASE-TRUST.md).

### Signing authority separation

The release signing key is stored in the protected GitHub `release-signing` environment rather than ordinary repository secrets. The stable publish job reaches that environment only after its protection rules are satisfied.

Maintainer configuration and key rotation are documented in [Release trust](docs/security/RELEASE-TRUST.md).

## Updates and rollback

`update-toolkit` installs a verified release into:

```text
/opt/erpnext-dev/releases/<version>/
```

The active pointers are switched only after checksum and signature verification succeeds. The previous release remains available for rollback.

```bash
sudo erpnext-dev update-toolkit
sudo erpnext-dev toolkit-rollback
sudo erpnext-dev verify-toolkit
```

A failed download, extraction, signature check, checksum check, or installation gate must stop before the active release pointer changes.

## Credentials and secrets

Generated credentials are operational handoff material, not a long-term password store.

Recommended workflow:

1. Retrieve credentials through a trusted local console or SSH session.
2. Save them in a password manager.
3. Restrict or remove the local credential file.
4. Rotate credentials after suspected exposure.
5. Never place credentials in issues, chat, screenshots, or support bundles.

Relevant commands:

```bash
sudo erpnext-dev credentials-info
sudo erpnext-dev credentials-file-status
sudo erpnext-dev credentials-secure
sudo erpnext-dev credentials-delete
```

`credentials-show` writes sensitive output directly to the controlling terminal rather than the ordinary logged output stream. It refuses to print when no interactive terminal is available.

Backup transport secrets remain outside the toolkit's ordinary configuration files. SSH authentication uses an operator-managed key, and object-storage credentials remain in the standard `rclone` configuration.

## Network exposure

For a public VPS, the expected provider-firewall baseline is:

```text
22/tcp    administrator IP only where practical
80/tcp    public
443/tcp   public
8000/tcp  blocked publicly
9000/tcp  blocked publicly
Redis     blocked publicly
MariaDB   blocked publicly
```

Docker-published ports follow Docker forwarding rules and may require provider, hypervisor, or `DOCKER-USER` controls in addition to UFW.

Run:

```bash
sudo erpnext-dev security-audit
sudo erpnext-dev doctor --plain
sudo erpnext-dev production-checklist
```

The operational hardening checklist is in [Production hardening](docs/security/PRODUCTION-HARDENING.md).

## Backups and recovery

A backup is not considered reliable only because a file exists.

Production operators should:

- Create local backups
- Verify backup structure and readability
- Maintain an off-VM or object-storage copy
- Monitor scheduled backup execution
- Rehearse restore in a disposable environment
- Confirm application health after restore
- Protect backup credentials and encryption material separately

The toolkit supports backup verification and restore rehearsal, but retention policy, provider durability, encryption policy, and business recovery objectives remain operator responsibilities.

## Diagnostics and support bundles

Support bundles intentionally exclude known credential files, private keys, tokens, and raw secret values. Redaction is defensive and heuristic, not perfect.

Review every bundle before sharing:

```bash
latest_bundle="$(ls -t /tmp/erpnext-dev-support-bundle-*.tar.gz | head -n 1)"
tar -tzf "$latest_bundle"

rm -rf /tmp/erpnext-support-review
mkdir -p /tmp/erpnext-support-review
tar -xzf "$latest_bundle" -C /tmp/erpnext-support-review
```

Do not share a bundle that contains customer data or credentials.

## Known limitations

- Bash and operating-system tools remain part of the trusted computing base.
- External package installers and repositories are trusted according to the pinned toolkit configuration and the host's package policy.
- Support-bundle redaction cannot recognise every application-specific secret.
- Solo-maintainer governance cannot provide independent review for every emergency action.
- Pre-release tags may use an explicitly marked unsigned emergency path; stable `vX.Y.Z` tags must be signed.
- A valid signature proves the checksum inventory was signed by the pinned key; it does not prove that the host, GitHub account, or operator is uncompromised.
- Rollback restores a prior toolkit release, not ERPNext business data. Data recovery requires a verified backup and restore workflow.

## Security documentation

| Topic | Document |
|---|---|
| Security architecture and trust boundaries | [Security architecture](docs/security/SECURITY-ARCHITECTURE.md) |
| Release signatures, verification, signing environment, and key rotation | [Release trust](docs/security/RELEASE-TRUST.md) |
| Public-server hardening checklist | [Production hardening](docs/security/PRODUCTION-HARDENING.md) |
| Security implementation history | [Security history](docs/security/SECURITY-HISTORY.md) |
| Support routing | [SUPPORT.md](SUPPORT.md) |
| Production acceptance | [VALIDATION.md](VALIDATION.md) |
| Release history | [CHANGELOG.md](CHANGELOG.md) |
