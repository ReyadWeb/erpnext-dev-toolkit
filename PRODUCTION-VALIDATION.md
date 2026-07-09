# v1.1.84 production validation notes

v1.1.84 extends `lib/install.sh` with post-install checkpoint and summary helpers.

```bash
VERSION="v1.1.84"
sudo erpnext-dev version
scripts/validate-release.sh
```

---

# v1.1.83 production validation notes

v1.1.83 extracts the core install engine into `lib/install.sh`.

Production validation should confirm:

```bash
VERSION="v1.1.83"
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/validate-release.sh
sudo erpnext-dev install-preflight
sudo erpnext-dev install-status
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.83`.
- `/opt/erpnext-dev/lib/install.sh` exists after install/update reuse.
- Preflight and install-status commands still run.

---

# v1.1.82 production validation notes

v1.1.82 extracts ERPNext service and runtime helpers into `lib/service.sh`.

Production validation should confirm:

```bash
VERSION="v1.1.82"
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/validate-release.sh
sudo erpnext-dev runtime-status
sudo erpnext-dev service-summary
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.82`.
- `/opt/erpnext-dev/lib/service.sh` exists after install/update reuse.
- Service and runtime status commands still run.

---

# v1.1.81 production validation notes

v1.1.81 extracts root storage detection and expansion helpers into `lib/storage.sh`.

Production validation should confirm:

```bash
VERSION="v1.1.81"
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/validate-release.sh
sudo erpnext-dev storage-status
sudo erpnext-dev final-qa
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.81`.
- `/opt/erpnext-dev/lib/storage.sh` exists after install/update reuse.
- Storage status commands still run.

---

# v1.1.80 production validation notes

v1.1.80 extracts health monitoring and go-live readiness helpers into `lib/health.sh`.

Production validation should confirm:

```bash
VERSION="v1.1.80"
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/validate-release.sh
sudo erpnext-dev health-check-status
sudo erpnext-dev go-live-status
sudo erpnext-dev final-qa
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.80`.
- `/opt/erpnext-dev/lib/health.sh` exists after install/update reuse.
- Health and go-live commands still run.

---

# v1.1.79 production validation notes

v1.1.79 extracts curated app installation helpers into `lib/apps.sh`.

Production validation should confirm:

```bash
VERSION="v1.1.79"
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/validate-release.sh
sudo erpnext-dev app-status
sudo erpnext-dev final-qa
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.79`.
- `/opt/erpnext-dev/lib/apps.sh` exists after install/update reuse.
- App status and install commands still run.

---

# v1.1.78 production validation notes

v1.1.78 extracts SSL/HTTPS and firewall helpers into `lib/ssl.sh` and `lib/firewall.sh`.

Production validation should confirm:

```bash
VERSION="v1.1.78"
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/validate-release.sh
sudo erpnext-dev ssl-status
sudo erpnext-dev firewall-hardening-status
sudo erpnext-dev final-qa
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.78`.
- `/opt/erpnext-dev/lib/ssl.sh` and `/opt/erpnext-dev/lib/firewall.sh` exist after install/update reuse.
- SSL and firewall status commands still run.

Runtime/install/backup/health/go-live behavior is unchanged aside from modularization.

---

# v1.1.77 production validation notes

v1.1.77 extracts backup and restore helpers into `lib/backup.sh`.

Production validation should confirm:

```bash
VERSION="v1.1.77"
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/validate-release.sh
sudo erpnext-dev backup-status
sudo erpnext-dev off-vm-backup-status
sudo erpnext-dev restore-rehearsal-status
sudo erpnext-dev final-qa
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.77`.
- `/opt/erpnext-dev/lib/backup.sh` exists after install/update reuse.
- Backup and restore status commands still run.

Runtime/install/SSL/firewall/health/go-live behavior is unchanged aside from modularization.

---

# v1.1.76 production validation notes