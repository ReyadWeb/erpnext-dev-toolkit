# v1.1.75 production validation notes

v1.1.75 is a modularization and static-analysis patch. It extracts shared helpers into `lib/common.sh` and adds shellcheck to CI.

Production validation should confirm:

```bash
VERSION="v1.1.75"
# verified tag-pinned update using SHA256SUMS
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/run-shellcheck.sh
scripts/validate-release.sh
sudo erpnext-dev final-qa
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.75`.
- `/opt/erpnext-dev/lib/common.sh` exists after `install-cli` or quickstart reuse.
- `verify-toolkit` reports Active/Stable/CLI match OK.
- `scripts/run-shellcheck.sh` and `scripts/validate-release.sh` pass on the release tree.
- Final QA option 1 reports release state OK.

Runtime/install/backup/restore/SSL/firewall/health/go-live behavior is unchanged.

---

# v1.1.74 production validation notes