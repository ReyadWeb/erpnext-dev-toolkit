# v1.1.74 production validation notes

v1.1.74 is a release-engineering patch. It adds `QUALITY-ASSESSMENT.md`, `RELEASE-MANIFEST.txt`, expanded `SHA256SUMS` coverage, and stronger `scripts/validate-release.sh` checks.

Production validation should confirm:

```bash
VERSION="v1.1.74"
# verified tag-pinned update using SHA256SUMS
sudo erpnext-dev version
sudo erpnext-dev verify-toolkit
scripts/validate-release.sh
sudo erpnext-dev final-qa
```

Expected:

- Version prints `ERPNext Developer Toolkit v1.1.74`.
- `verify-toolkit` reports Active/Stable/CLI match OK.
- `scripts/validate-release.sh` passes on the release tree.
- Final QA option 1 reports release state OK.

Runtime/install/backup/restore/SSL/firewall/health/go-live behavior is unchanged.

---

# v1.1.73 production validation notes