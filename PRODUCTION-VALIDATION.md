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