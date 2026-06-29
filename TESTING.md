# Testing v0.8.10

## Version check

```bash
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
```

Expected:

```text
SCRIPT_VERSION="0.8.9"
```

## Storage tests

Inside the VM:

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh verify-storage
```

If expansion is recommended:

```bash
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh verify-storage
```

Expected after expansion:

```text
Expansion OK not needed
```

or root storage should show a larger size than before.

## Fresh install test

```bash
./install-erpnext-dev.sh setup
```

Expected behavior:

- Checks RAM and disk.
- If the VM disk is larger than root, offers to expand storage.
- Prompts for local site name.
- Installs ERPNext.
- Starts service and waits for ports.

## Post-install checks

```bash
./install-erpnext-dev.sh site-config
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh service-summary
./install-erpnext-dev.sh doctor
```

## Local SSL test

```bash
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh verify-local-ssl
```

From HOST:

```bash
curl -I http://YOUR-SITE.test
curl -kI https://YOUR-SITE.test
curl -I http://YOUR-SITE.test:8000
```


## v0.8.10 LVM regression test

On a fresh/cloned Ubuntu VM, run:

```bash
./install-erpnext-dev.sh storage-status
```

For common Ubuntu LVM layouts, expected output should identify:

```text
Layout: lvm
Backing disk: /dev/vda or equivalent
Root partition/PV: /dev/vda3 or equivalent
Root LV: /dev/<vg>/<lv>
Expansion: recommended, if free disk/VG space exists
```

Then test:

```bash
./install-erpnext-dev.sh expand-root-storage
df -h /
./install-erpnext-dev.sh verify-storage
```
