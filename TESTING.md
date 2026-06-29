# Testing v0.8.14

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


## v0.8.14 LVM regression test

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

### v0.8.14 LVM storage test

On a fresh Ubuntu VM with a larger virtual disk than root filesystem:

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh storage-status
df -h /
```

Expected: layout should be `lvm`, expansion should be recommended, and `/` should grow after confirmation.



## v0.8.14 Storage Expansion Fix

This release changes the storage expansion workflow to follow the proven Ubuntu LVM resize sequence generically:

```bash
sgdisk -e <disk> || true
partprobe <disk> || true
growpart <disk> <partition-number>
pvresize <physical-volume-partition>
lvextend -r -l +100%FREE <root-logical-volume>
```

The script derives `<disk>`, `<partition-number>`, `<physical-volume-partition>`, and `<root-logical-volume>` from `findmnt`, `lsblk`, and `lvs`; it does not hardcode `/dev/vda3` or `ubuntu-vg`.

New diagnostic command:

```bash
./install-erpnext-dev.sh storage-debug
```
