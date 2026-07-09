## v1.1.77 reliability update

v1.1.77 extracts backup and restore helpers into `lib/backup.sh`, continuing modularization with unchanged command names and runtime behavior.

Next reliability milestone: extract SSL and firewall helpers into dedicated lib modules.

## v1.1.76 reliability update

v1.1.76 extracts support and diagnostics helpers into `lib/support.sh`, reducing monolith size for doctor, support-bundle, and audit workflows.

Next reliability milestone: extract backup/restore helpers into `lib/backup.sh`.

## v1.1.75 reliability update

v1.1.75 extracts `lib/common.sh` from the monolith and adds shellcheck to CI via `scripts/run-shellcheck.sh`. Install and update paths now copy or download the toolkit `lib/` tree into `/opt/erpnext-dev/lib`.

Next reliability milestone: extract support/diagnostics helpers into `lib/support.sh`.

## v1.1.74 reliability update

v1.1.74 adds `RELEASE-MANIFEST.txt`, `scripts/generate-release-checksums.sh`, expanded `SHA256SUMS` coverage, version-consistency checks, and menu smoke tests in `scripts/validate-release.sh`. See also [`QUALITY-ASSESSMENT.md`](QUALITY-ASSESSMENT.md) for the structured quality evaluation and improvement plan.

Next reliability milestone: begin careful modularization with shellcheck in CI.

## v1.1.73 reliability update

v1.1.73 expands release validation with support-bundle audit fixture coverage. `scripts/validate-release.sh` now verifies that a clean support-bundle archive passes the toolkit audit command, which improves regression coverage for support/evidence bundle safety.

Next reliability milestone: release package manifest and broader package checksum validation before beginning modularization.

# Reliability Plan

## Purpose

This plan tracks the reliability and regression-prevention work needed to move the ERPNext Developer Toolkit from a field-tested production-candidate toolkit toward a more repeatable release engineering model.

The production operations path is already validated on a real VM stack: installation, HTTPS, UFW, Fail2Ban, scheduled local backups, off-VM rsync backups, restore rehearsal, health monitoring, go-live validation, and redacted support bundles. The next reliability gap is not another isolated ERPNext VM feature; it is automated release validation and safer change management.

## Current validated strengths

The toolkit already has strong operational reliability features:

- blocking install preflight for VM resources and unsupported operating systems;
- local and production deployment paths;
- HTTPS validation for local and production modes;
- UFW and Fail2Ban workflows;
- scheduled local backups;
- off-VM backup target setup and status checks;
- restore preflight and full restore rehearsal on a disposable VM;
- restore rehearsal record and report commands;
- health-check timer and local state file;
- go-live validation record for snapshot, firewall, DNS proxy, Full strict SSL, and Origin CA;
- final QA and production checklist;
- redacted support bundles with evidence files.

The validated production evidence currently includes:

```text
Production site: erp.flowmaya.com
Production VPS: 65.109.221.4
Backup server: 65.109.220.250
Restore rehearsal: passed and login validated
Health monitoring: active and passing
Go-live validation: recorded
Dashboard navigation: validated through v1.1.67
```

## Reliability gaps

### Manual validation is still the main release gate

`TESTING.md` and `PRODUCTION-VALIDATION.md` contain strong field evidence, but every release should not depend only on manual operator testing. Manual validation remains necessary for production-impacting changes, but each tag should also pass automated static and smoke checks.

### Single-script change risk

The monolithic Bash script is effective for distribution, but the regression blast radius grows as more workflows are added. A small change to shared prompting, sudo handling, menu routing, or status formatting can affect unrelated areas.

### Release packaging needs repeatable checks

Each release should consistently verify:

- script syntax;
- version string;
- package file list;
- no `GITHUB-UPDATE-v*.md` files;
- no credential-like files;
- key help commands exist;
- safe menus open and exit;
- documentation mentions the release version.

## Reliability roadmap

### Phase 1 — release validation automation

Target versions: v1.1.70 to v1.1.72.

1. Add checksum artifacts and tag-pinned install documentation. **Implemented in v1.1.70 for `erpnext-dev.sh`.**
2. Add a `verify-toolkit` command for installed hash verification. **Implemented in v1.1.71.**
3. Add `scripts/validate-release.sh` to run local package checks consistently.
4. Add minimal GitHub Actions CI.
5. Keep CI conservative at first: warn where appropriate, fail only on high-signal errors.

Initial validation script should check:

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help
printf 'q\n' | sudo ./erpnext-dev.sh production-ops-wizard
printf '10\nb\nq\n' | sudo ./erpnext-dev.sh production-ops-wizard
```

The CI version should avoid destructive commands and should not require a real ERPNext installation unless running in an integration-test VM.

### Phase 2 — package and support-bundle regression checks

Add automated checks for release packages and support bundles:

- package contains only expected release files;
- package contains no per-release GitHub update instruction files;
- support bundle excludes private keys, credential files, raw `site_config.json`, database dumps, and backup tarballs;
- redacted evidence files are included when available;
- docs reference the current version and validation status.

### Phase 3 — modularization

After CI and release verification are stable, begin reducing monolith risk. Do not modularize everything at once.

Recommended order:

1. extract common logging, prompt, status, lock, and sudo helpers;
2. extract support-bundle and diagnostics functions;
3. extract backup/off-VM backup functions;
4. extract restore rehearsal functions;
5. extract SSL and firewall functions;
6. keep a thin `erpnext-dev.sh` entry point for compatibility.

Each extraction should preserve existing command names and be covered by CI and field smoke tests.

### Phase 4 — integration testing

Longer-term, add an optional integration-test track:

- disposable Ubuntu VM;
- install-preflight;
- local-dev install smoke test;
- menu self-test;
- backup creation;
- restore preflight;
- support bundle creation;
- teardown.

This should remain separate from the normal fast CI because full ERPNext installs are slower and depend on upstream package availability.

## Operational reliability policy

### Before production changes

Run:

```bash
sudo erpnext-dev production-ops-wizard
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
```

Confirm:

```text
Runtime: OK
HTTPS: OK
UFW/Fail2Ban: OK
Latest backup: OK
Off-VM backup: OK
Restore rehearsal: OK or intentionally scheduled
Health monitoring: OK
Go-live validation: OK or intentionally being re-recorded
```

### After production changes

Repeat:

```bash
sudo erpnext-dev health-check
sudo erpnext-dev production-checklist
sudo erpnext-dev final-qa
sudo erpnext-dev support-bundle
```

Re-record go-live validation after snapshot, firewall, DNS, Cloudflare, or SSL changes.

Repeat restore rehearsal after major ERPNext upgrades, migration work, backup-policy changes, or any incident involving storage or database recovery.

## Version targets

| Version | Reliability goal |
|---|---|
| v1.1.69 | Add security and reliability planning docs |
| v1.1.70 | Add checksum artifacts and tag-pinned bootstrap docs — implemented for `erpnext-dev.sh` |
| v1.1.71 | Add `verify-toolkit` command — implemented |
| v1.1.72 | Add minimal CI and release validation script |
| Later | Begin low-risk modularization after CI exists |

## Definition of done for release hardening

The release-hardening track should be considered complete when:

- users can install from a tagged release;
- users can verify SHA256 before running as root;
- the installed toolkit can verify its own file hash;
- every pull request or tag runs automated syntax and smoke tests;
- packages are automatically checked for unwanted files and obvious secret leaks;
- manual field QA remains documented for production-impacting behavior.

## v1.1.72 implementation note

The first automated validation layer is now present:

```bash
scripts/validate-release.sh
```

GitHub Actions runs the same script from `.github/workflows/ci.yml`. The checks are intentionally conservative: syntax, version, checksum, help smoke checks, `verify-toolkit`, package hygiene, and basic secret-pattern scanning. Full VM install tests remain a later milestone.
