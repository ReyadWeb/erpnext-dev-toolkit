# ERPNext Developer Toolkit Documentation

The repository documentation is organised by user goal. The main README remains the
visual product landing page and keeps its menu, operational sections, screenshots,
and architecture diagrams. Deeper implementation and maintenance details live in
focused documents.

## Start by goal

| I need to… | Read |
|---|---|
| Understand the toolkit and choose a deployment | [Project README](../README.md) |
| Validate a local VM or public server | [Validation runbook](../VALIDATION.md) |
| Test a change or release | [Testing guide](../TESTING.md) |
| Review historical test evidence | [Testing history](TESTING-HISTORY.md) |
| Review security policy and release trust | [Security policy](../SECURITY.md) |
| See active development priorities | [Roadmap](../ROADMAP.md) |
| Review release history | [Changelog](../CHANGELOG.md) |
| Contribute code or documentation | [Contributing guide](../CONTRIBUTING.md) |
| Prepare a useful support request | [Support guide](../SUPPORT.md) |

## Installation and environment guides

### Local virtual machines

- [Stable local VM addressing](LOCAL-VM-STABLE-IP.md)
- [Frappe frontend and asset troubleshooting](FRAPPE-FRONTEND-ASSETS.md)
- [Validation runbook](../VALIDATION.md)

The [README local VM section](../README.md#local-development-vm) remains the primary
quickstart and keeps the host mapping, HTTPS, host-OS, and stable-IP guidance visible.

### Public servers

- [Public VPS quickstart](../README.md#public-vps--cloud-vm)
- [Production validation](../VALIDATION.md)
- [Security policy](../SECURITY.md)
- [Health architecture](HEALTH-ARCHITECTURE.md)

### Native and Docker engines

- [Deployment engine overview](../README.md#deployment-engines)
- [Development guide](DEVELOPMENT.md)
- [Release validation](../TESTING.md)

The active testing guide defines automated validation, while the validation
runbook defines real-machine acceptance for native and Docker deployments. The
historical testing record is preserved separately so current guidance remains
concise.

## Operations and reliability

| Area | Reference |
|---|---|
| Credentials | [README credentials section](../README.md#credentials) |
| Backup and restore | [README backup section](../README.md#backups-and-restore-safety) |
| Off-VM backup server | [README off-VM section](../README.md#off-vm-backup-server) |
| Restore rehearsal | [README restore section](../README.md#restore-rehearsal) |
| Dashboard and incidents | [README dashboard section](../README.md#production-operations-dashboard) |
| Health monitoring | [Health architecture](HEALTH-ARCHITECTURE.md) |
| HTTPS and domains | [README HTTPS section](../README.md#https--ssl) |
| Updates and rollback | [README integrity section](../README.md#toolkit-integrity-and-updates) |
| Production acceptance | [Validation runbook](../VALIDATION.md) |

The full command inventory is always available through:

```bash
erpnext-dev --help
sudo erpnext-dev menu
```

## Security and release trust

Start with [SECURITY.md](../SECURITY.md). It is the repository-level security policy
and the authoritative entry point for vulnerability reporting.

Focused security guides:

- [Security documentation index](security/README.md)
- [Security architecture](security/SECURITY-ARCHITECTURE.md)
- [Release trust](security/RELEASE-TRUST.md)
- [Production hardening](security/PRODUCTION-HARDENING.md)
- [Security implementation history](security/SECURITY-HISTORY.md)

Maintainer and release references:

- [Release automation](RELEASE-AUTOMATION.md)
- [Release process](RELEASE-PROCESS.md)
- [Release-state contract](RELEASE-STATE.md)
- [Published signing key](erpnext-dev-signing-key.asc)

Stable releases use a complete archive, an authoritative release manifest,
whole-tree checksums, a detached checksum signature, and atomic versioned
installation slots.

## Development and maintenance

- [Development guide](DEVELOPMENT.md)
- [Repository workflow](REPOSITORY-WORKFLOW.md)
- [Release automation](RELEASE-AUTOMATION.md)
- [Release process](RELEASE-PROCESS.md)
- [Active roadmap](../ROADMAP.md)
- [Roadmap history](ROADMAP-HISTORY.md)
- [Testing history](TESTING-HISTORY.md)
- [Roadmap board](ROADMAP-BOARD.md)
- [Community board](COMMUNITY-BOARD.md)

Repository-level contributor policies:

- [Contributing](../CONTRIBUTING.md)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- [Support](../SUPPORT.md)

## Architecture and visual references

The README keeps the principal images so visitors can understand the toolkit
without navigating away from the landing page:

- Product banner
- Installation-to-go-live lifecycle
- Operations dashboard
- Incident history
- Multi-engine architecture
- Production backup architecture
- Local testing VM architecture

Supporting references:

- [Health architecture](HEALTH-ARCHITECTURE.md)
- [Stable local VM IP design](LOCAL-VM-STABLE-IP.md)
- [Frontend asset readiness](FRAPPE-FRONTEND-ASSETS.md)
- [`assets/`](assets/) for diagrams and screenshots

## Documentation organisation

The documentation structure follows these rules:

1. `README.md` remains the visual product landing page and quickstart.
2. The README keeps its menu, major user-facing sections, screenshots, and diagrams.
3. Root policy files define security, support, contribution, testing, validation,
   roadmap, and release history.
4. `docs/` contains focused technical, architecture, operations, troubleshooting,
   and maintainer guides.
5. Existing anchors remain available while detailed content is moved gradually.
6. Installation examples use published release assets and supported signed-bundle
   workflows.
7. Active documents must not contain stale current-version or readiness claims.

## Documentation ownership

When behaviour changes:

- Update the closest user-facing guide.
- Update `README.md` when the main product path, command, supported environment, or
  visual overview changes.
- Update `SECURITY.md` for security policy, guarantees, limitations, or reporting.
- Update `TESTING.md` and release evidence when validation changes.
- Update `ROADMAP.md` only for active planning.
- Record shipped changes in `CHANGELOG.md`.

Before merging documentation changes, run repository validation so manifest,
checksums, version references, packaged documentation, and links remain aligned.
