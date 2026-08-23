# Real-machine validation runbook

This is the authoritative field-acceptance runbook for ERPNext Developer
Toolkit. It covers real local virtual machines and public servers across the
native and Docker engines.

Automated testing is defined in [`TESTING.md`](TESTING.md). Historical
version-specific evidence is preserved in
[`docs/TESTING-HISTORY.md`](docs/TESTING-HISTORY.md).

## Purpose and boundary

Use this runbook when a change or release must be proven on infrastructure that
repository tests cannot reproduce reliably:

- host and public DNS;
- browser trust and public certificate issuance;
- cloud firewall behaviour;
- Docker port publication;
- provider reboot and snapshot behaviour;
- real off-VM and object-storage destinations;
- production backup recovery;
- upgrade and rollback.

This runbook does not replace protected CI. A release requires both automated
gates and the applicable field-acceptance paths.

## Acceptance matrix

Select every path affected by the change:

| Path | Typical purpose | Engine | Access model |
|---|---|---|---|
| Local native VM | Development and native lifecycle acceptance | Native | VM IP, local hostname, optional trusted local HTTPS |
| Local Docker VM | Container development acceptance | Docker | Published frontend port, local hostname, optional trusted local HTTPS |
| Public native VPS | Production native acceptance | Native | Real domain and public HTTPS |
| Public Docker VPS | Production Compose acceptance | Docker | Real domain, Traefik, public HTTPS |

For release-wide reliability claims, validate all four paths. For a bounded
change, document why unaffected paths were not rerun.

### v1.21 profile-aware readiness and recovery matrix

| Profile/path | Installation | Readiness evidence | Backup/recovery | Restart/reboot evidence | Qualification |
|---|---|---|---|---|---|
| Local Native Recommended | Supported | Frappe, ERPNext, site, services, HTTP and login assets | Native backup/restore suites | Native service and Phase 7.4 VM evidence | tested |
| Local Native Frappe-only | Supported | Frappe required; ERPNext absence valid; exact inventory | Native backup/restore suites | Native service tests | tested |
| Local Native Advanced | Supported | Promoted Phase 7.4 intent, exact resolved apps, source, backup, services, HTTP/assets | Phase 7.4 transaction/recovery suite | Native PTY/non-TTY and reboot evidence | qualified |
| Public Native Recommended | Supported | Native production services, site, HTTP/assets and inventory | Native backup/recovery contract | Public reboot remains field validation | not-qualified |
| Public Native Frappe-only | Supported where selected | Frappe-only inventory and runtime evidence | Native backup/recovery contract | Public reboot remains field validation | not-qualified |
| Local Docker Recommended | Supported | Compose runtime, site, image/manifest, volumes, HTTP/assets | Docker durability/restore suites | Docker restart tests | tested |
| Local Docker Frappe-only | Supported | Compose runtime, Frappe inventory, image/manifest and assets | Docker durability/restore suites | Docker restart tests | tested |
| Public Docker Recommended | Supported | Production Compose, routing, image and site evidence | Docker production backup contract | Public reboot remains field validation | not-qualified |
| Public Docker Frappe-only | Supported where selected | Production Compose and Frappe-only inventory | Docker production backup contract | Public reboot remains field validation | not-qualified |
| Existing installation | Read-only/deferred | No managed-readiness claim; reconciliation is informational | No automatic recovery authority | No managed restart claim | deferred |
| Docker Advanced | Unsupported/deferred | Exit 23; no Docker mutation | No recovery path entered | Not applicable | unsupported |

The Phase 7.7 readiness closure is read-only: it consumes validated
reconciliation evidence and never repairs, rebuilds assets, promotes
configuration, or guesses from profile metadata alone. Missing, extra,
conflicting, ambiguous, stale, or unsupported evidence fails closed.

## Safety prerequisites

Before changing a real machine:

- use a dedicated test VM/VPS;
- take a provider or hypervisor snapshot;
- confirm console or rescue access;
- record the current toolkit and ERPNext/Frappe versions;
- preserve existing backup and off-VM configuration;
- confirm the intended firewall policy;
- prepare a rollback decision point;
- use a domain or local hostname that does not affect production traffic;
- keep credentials out of terminal logs and public evidence.

Recommended minimum public-server resources are 2 vCPU and 4 GB RAM. Production
sizing still depends on workload, applications, users, database growth, and
provider characteristics.

## Install the published release safely

Use the complete release archive. Do not install from GitHub's automatic source
archives or from a raw entrypoint file.

```bash
sudo apt-get update
sudo apt-get install -y curl ca-certificates gnupg tar

REPO="ReyadWeb/erpnext-dev-toolkit"
VERSION="$(
  curl -fsSL -o /dev/null -w '%{url_effective}' \
    "https://github.com/${REPO}/releases/latest" |
  sed -n 's|.*/tag/\([^/]*\)$|\1|p'
)"

[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Could not resolve the latest stable release." >&2
  exit 1
}

workdir="$(mktemp -d /tmp/erpnext-dev-validation.XXXXXX)"
cd "$workdir" || exit 1

base="https://github.com/${REPO}/releases/download/${VERSION}"
archive="erpnext-dev-${VERSION}.tar.gz"

curl -fsSLO "${base}/${archive}"

if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  echo "Unsafe path detected in release archive." >&2
  exit 1
fi

tar --no-same-owner --no-same-permissions -xzf "$archive"
cd "erpnext-dev-${VERSION}" || exit 1

sudo ./erpnext-dev.sh verify-signature
sha256sum -c SHA256SUMS
sudo ./erpnext-dev.sh verify-toolkit
```

Pass criteria:

- the bundled signing key matches the pinned maintainer fingerprint;
- the detached checksum signature verifies;
- all checksums pass;
- toolkit integrity reports every packaged module as expected;
- `./erpnext-dev.sh version` reports the selected release.

## Baseline record

Before installation or upgrade, record:

```bash
uname -a
cat /etc/os-release
ip -brief address
ip route
df -h /
free -h
date -u
```

Record separately:

```text
Validation date
Operator
Commit or tag
Provider or hypervisor
VM plan/resources
OS image
Deployment path
Domain or local hostname
Snapshot identifier
Expected public ports
Evidence location
```

Do not place secrets in this record.

## Shared acceptance checks

Run the applicable commands after installation, restart, restore, and upgrade:

```bash
sudo erpnext-dev version
sudo erpnext-dev where-installed
sudo erpnext-dev verify-toolkit
sudo erpnext-dev engine-status
sudo erpnext-dev status
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
sudo erpnext-dev doctor --plain
sudo erpnext-dev dashboard
```

Pass criteria:

- canonical toolkit identity is correct;
- the selected engine is correct;
- required services or containers are healthy;
- readiness includes HTTP and login-critical frontend assets;
- the styled login page renders;
- required CSS and JavaScript return successfully and are non-empty;
- diagnostics do not expose secrets;
- no unexpected degraded or critical condition remains.

## Path A — local native VM

### A1. Install and direct access

```bash
sudo ./erpnext-dev.sh local-dev-quickstart
sudo erpnext-dev engine-status
sudo erpnext-dev verify-access
```

Pass criteria:

- the engine is native;
- the site responds at the documented native development endpoint;
- the local site name maps to the VM IP on the host;
- `wait-ready` and `verify-frontend-assets` pass without requiring a reboot.

### A2. Local hostname and HTTPS

Use the toolkit's local-domain and trusted-certificate workflow:

```bash
sudo erpnext-dev local-ssl-wizard
sudo erpnext-dev verify-local-ssl
sudo erpnext-dev local-access-doctor
```

Pass criteria:

- host mapping is correct;
- the certificate is trusted by the chosen browser/profile;
- HTTPS loads the correct site;
- HTTP redirect behaviour matches the configured policy;
- no login CSS/JS request fails.

### A3. Stable-IP and reboot acceptance

When static/stable IP behaviour is in scope:

```bash
sudo erpnext-dev local-ip-plan
sudo erpnext-dev local-ip-status
sudo erpnext-dev local-ip-drift-check
```

Reboot the VM, then verify:

```bash
sudo erpnext-dev status
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
sudo erpnext-dev local-ip-drift-check
```

Pass criteria:

- the intended IP, default route, and DNS survive reboot;
- ERPNext starts automatically;
- the host mapping still reaches the correct site;
- HTTPS and frontend assets remain healthy.

## Path B — local Docker VM

### B1. Install and published-port access

Choose Docker during guided setup or set the engine explicitly for the
documented install path.

```bash
sudo erpnext-dev engine-status
sudo erpnext-dev status
sudo erpnext-dev verify-access
```

Pass criteria:

- the engine is Docker;
- the direct frontend uses the configured published port, `8080` by default;
- native `8000/9000` guidance is not presented as the Docker browser endpoint;
- containers are healthy;
- login assets pass.

### B2. Local hostname, trusted HTTPS, and exposure

```bash
sudo erpnext-dev local-ssl-wizard
sudo erpnext-dev verify-local-ssl
sudo erpnext-dev local-firewall-status
```

Pass criteria:

- the local hostname reaches the Docker frontend;
- trusted HTTPS works;
- the local Docker forwarding policy is active where required;
- the published frontend is reachable only from the intended network scope;
- no unexpected port is exposed.

### B3. Container persistence

For a stack created before v1.20.2-beta.2, reconcile the persistence policy
once before rebooting:

```bash
sudo erpnext-dev docker-reconcile-restart-policy
sudo erpnext-dev doctor
```

Reboot the VM and verify:

```bash
sudo erpnext-dev engine-status
sudo erpnext-dev doctor
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
```

Pass criteria:

- Doctor reports all nine required services ready and all nine persistent
  services using `unless-stopped`;
- the intended Compose project returns automatically without a manual
  `erpnext-dev start`;
- no required service is missing, exited, restarting, health-starting, or
  unhealthy;
- volumes, credentials, site state, and installed applications persist;
- frontend assets and login remain healthy.

## Path C — public native VPS

### C1. Provider and DNS gate

Before installation:

- create the intended DNS record;
- verify it resolves to the server;
- allow only the intended administrative and web ports at the cloud firewall;
- do not expose development ports publicly;
- take a provider snapshot.

Record:

```bash
dig +short erp.example.com
sudo ss -lntup
```

### C2. Guided production setup

```bash
sudo ./erpnext-dev.sh install-preflight
sudo ./erpnext-dev.sh public-vm-guided-setup
sudo erpnext-dev engine-status
sudo erpnext-dev production-runtime-status
```

Pass criteria:

- the engine is native;
- production runtime is used instead of `bench start`;
- boot autostart is enabled;
- direct development ports are not publicly required.

### C3. Public HTTPS and browser acceptance

```bash
sudo erpnext-dev production-ssl-wizard
sudo erpnext-dev production-ssl-status
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
```

Pass criteria:

- the real domain serves a valid certificate chain;
- HTTPS redirects and host routing are correct;
- the styled login renders in a normal browser;
- required CSS and JavaScript have no 404, empty body, or wrong-site response;
- certificate renewal configuration is present.

## Path D — public Docker VPS

### D1. Production Compose setup

Choose Docker before the public guided install, or use the documented Docker
production setup command:

```bash
sudo erpnext-dev docker-production-setup
sudo erpnext-dev engine-status
sudo erpnext-dev status
```

Pass criteria:

- production Compose, not the development stack, is active;
- immutable image and source/version pins are recorded;
- application-bearing services use the intended image;
- credentials and durable volumes remain consistent.

### D2. Traefik HTTPS and exposure guard

```bash
sudo erpnext-dev docker-https-wizard
sudo erpnext-dev docker-https-status
sudo erpnext-dev docker-production-exposure
```

Pass criteria:

- the real domain serves valid HTTPS;
- only intended public web ports are exposed;
- the direct Docker frontend is not publicly exposed after production HTTPS;
- container-internal application ports remain internal;
- cloud firewall and host/container rules agree.

### D3. Optional-application image consistency

When optional applications are affected:

- verify installed applications are represented in the desired production image;
- verify backend, frontend, websocket, queue workers, and scheduler use the same
  intended custom image;
- verify application code exists in every required service;
- verify application frontend assets and routes load;
- reboot and confirm the image selection persists.

## Frontend acceptance

A release is not browser-ready merely because one HTTP request returns 200.

For each affected path:

```bash
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
```

Then use a browser:

1. open the documented login URL;
2. hard refresh;
3. confirm the expected site and branding;
4. confirm the page is styled;
5. inspect the network panel for required CSS/JS failures;
6. confirm redirects do not switch to another hostname or port;
7. repeat after restart, restore, and upgrade when applicable.

When assets fail:

```bash
sudo erpnext-dev frappe-asset-checklist
sudo erpnext-dev repair-frontend-assets
sudo erpnext-dev verify-frontend-assets
sudo erpnext-dev support-bundle
```

Preserve the first failure evidence before repair.

## Security and exposure acceptance

Validate both provider and host/container boundaries:

- administrative access is limited to the intended source where practical;
- public HTTP/HTTPS are open only when required;
- development and internal service ports are not exposed publicly;
- HTTPS is active before applying a production hardening profile that depends on
  it;
- credentials remain private;
- support output is redacted;
- security status contains no unexplained failure;
- disabling a protection requires an explicit operator action.

Useful commands include:

```bash
sudo erpnext-dev security-status
sudo erpnext-dev production-ssl-status
sudo erpnext-dev local-firewall-status
sudo erpnext-dev docker-production-exposure
sudo ss -lntup
```

Also test from a second machine or external scanner under your control. A
localhost-only check cannot prove cloud exposure.

## Backup, restore, and off-host acceptance

### Backup creation and verification

```bash
sudo erpnext-dev backup-files
sudo erpnext-dev backup-verify
```

Pass criteria:

- the backup belongs to the intended site;
- expected database, files, private files, and metadata are present as
  applicable;
- compression/archive and checksum verification pass;
- the artifact is stored outside ephemeral containers.

### Restore or restore rehearsal

Use the engine-appropriate guided restore or rehearsal command. For Docker
production:

```bash
sudo erpnext-dev docker-restore-rehearsal
sudo erpnext-dev docker-restore-evidence
```

After restore:

```bash
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
sudo erpnext-dev doctor --plain
```

Pass criteria:

- restore completes to the intended target;
- the site, runtime, and frontend are healthy;
- the source environment remains safe when the rehearsal is documented as
  non-destructive;
- evidence identifies the backup and target.

### Off-VM or object-storage copy

Rsync path:

```bash
sudo erpnext-dev configure-rsync-backup-target
sudo erpnext-dev off-vm-backup-dry-run
sudo erpnext-dev run-off-vm-backup
sudo erpnext-dev off-vm-backup-status
```

Object-storage path:

```bash
sudo erpnext-dev configure-object-backup
sudo erpnext-dev object-backup-dry-run
sudo erpnext-dev object-backup
sudo erpnext-dev object-status
```

Pass criteria:

- the remote destination receives the complete intended backup;
- host-key or remote identity checks are enforced;
- remote verification succeeds;
- retention/deletion behaviour matches the configuration;
- a remote artifact can be selected for recovery.

## Upgrade and rollback acceptance

Before upgrading:

```bash
sudo erpnext-dev update-preflight
sudo erpnext-dev backup-files
sudo erpnext-dev backup-verify
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
```

Perform the guarded update using the documented stable or beta channel. Then
verify:

```bash
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
sudo erpnext-dev status
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
sudo erpnext-dev production-ssl-status
```

Test rollback:

```bash
sudo erpnext-dev toolkit-rollback
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
```

Pass criteria:

- update installs the exact expected release tree;
- all packaged modules match;
- application/runtime state remains healthy;
- rollback returns to the previous complete slot;
- restored release identity and module inventory are correct;
- a subsequent restoration to the candidate release succeeds when required for
  acceptance.

## Reboot persistence

Reboot every path for which boot persistence or network state matters.

After reboot, verify:

```bash
sudo erpnext-dev engine-status
sudo erpnext-dev status
sudo erpnext-dev wait-ready
sudo erpnext-dev verify-frontend-assets
sudo erpnext-dev production-ssl-status
sudo erpnext-dev backup-verify
```

Also confirm:

- IP, routes, and DNS;
- systemd/Supervisor or Compose autostart;
- certificate and proxy configuration;
- firewall/exposure policy;
- optional applications;
- scheduled backups and health timers;
- off-VM configuration.

## Evidence bundle

Collect redacted evidence:

```bash
sudo erpnext-dev doctor --plain
sudo erpnext-dev support-bundle
sudo erpnext-dev go-live-record
sudo erpnext-dev go-live-status
```

Recommended attachments:

- validation matrix and sign-off;
- command transcript with secrets removed;
- browser screenshots;
- failed and successful frontend network evidence;
- service/container status;
- firewall and exposure evidence;
- backup verification output;
- restore/rehearsal evidence;
- upgrade and rollback identities;
- reboot verification;
- relevant GitHub CI and release workflow links.

## Sign-off matrix

| Gate | Local native | Local Docker | Public native | Public Docker |
|---|:---:|:---:|:---:|:---:|
| Signed toolkit and whole-tree integrity | ☐ | ☐ | ☐ | ☐ |
| Install or upgrade completed | ☐ | ☐ | ☐ | ☐ |
| Correct engine and runtime | ☐ | ☐ | ☐ | ☐ |
| HTTP and styled login | ☐ | ☐ | ☐ | ☐ |
| Required frontend assets | ☐ | ☐ | ☐ | ☐ |
| HTTPS/domain or local trust | ☐ | ☐ | ☐ | ☐ |
| Firewall/exposure policy | ☐ | ☐ | ☐ | ☐ |
| Backup created and verified | ☐ | ☐ | ☐ | ☐ |
| Restore or rehearsal passed | ☐ | ☐ | ☐ | ☐ |
| Off-host copy verified | ☐ | ☐ | ☐ | ☐ |
| Upgrade and rollback passed when applicable | ☐ | ☐ | ☐ | ☐ |
| Reboot persistence | ☐ | ☐ | ☐ | ☐ |
| Redacted evidence retained | ☐ | ☐ | ☐ | ☐ |

Use `N/A` only with a written justification.

## Abort and rollback criteria

Stop the acceptance sequence when:

- version, signature, checksum, or toolkit integrity fails;
- the wrong site or domain is served;
- required frontend assets fail;
- a production runtime or database is unhealthy;
- unexpected public exposure is detected;
- no verified recovery point exists before a high-impact change;
- restore/rehearsal fails;
- upgrade identity is ambiguous;
- a rollback cannot be completed safely.

Preserve evidence, restore the snapshot or documented recovery point, and record
the failure before retrying.

## Production-ready decision

A production-ready decision requires:

- all required automated repository and integration gates;
- all applicable real-machine paths;
- valid HTTPS and browser readiness;
- verified backup and restore evidence;
- correct exposure controls;
- upgrade/rollback evidence when affected;
- reboot persistence;
- published stable-release verification;
- an explicit sign-off record.

Passing this runbook proves the tested configuration and release under the
recorded conditions. It is not a guarantee for every provider, custom
application, workload, or future upstream change.
