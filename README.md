# ERPNext Developer Installer v0.8.14

Local ERPNext/Frappe developer VM installer for Ubuntu 24.04/26.04.

## Quick start

Run inside the ERPNext VM:

```bash
curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh setup
```

During setup, choose a local site name:

```text
Local site name [erp.test]:
```

Press Enter for `erp.test`, or enter a custom local name such as `erp08.test`.

## v0.8.14 highlights

- Generic root storage detection and expansion.
- Improved Ubuntu LVM root detection for `/dev/mapper/*`, `/dev/<vg>/<lv>`, and `/dev/dm-*` aliases.
- Setup can detect when a cloned VM disk is larger than the Ubuntu root filesystem.
- Supports common Ubuntu layouts:
  - LVM + ext4 root
  - direct ext4 partition root
  - direct XFS partition root
- Adds clear storage commands:

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh verify-storage
```

## Local domain flow

After setup, run the shown `/etc/hosts` command on the HOST machine, not inside the VM.

Example:

```bash
sudo sed -i '/[[:space:]]erp08\.test$/d' /etc/hosts
echo "192.168.122.181 erp08.test" | sudo tee -a /etc/hosts
```

Then test from the host:

```bash
curl -I http://erp08.test:8000
```

## Local SSL flow

Inside the VM:

```bash
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh verify-local-ssl
```

Host tests:

```bash
curl -I http://erp08.test
curl -kI https://erp08.test
curl -I http://erp08.test:8000
```

For browser-trusted local SSL, use:

```bash
./install-erpnext-dev.sh mkcert-guide
./install-erpnext-dev.sh browser-trust-guide
```

## Optional apps

Install optional apps only after the base install and access are verified:

```bash
./install-erpnext-dev.sh app-library
```

Available app commands include:

```bash
./install-erpnext-dev.sh install-crm
./install-erpnext-dev.sh install-hrms
./install-erpnext-dev.sh install-helpdesk
./install-erpnext-dev.sh install-insights
```

## Health checks

```bash
./install-erpnext-dev.sh site-config
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh doctor
```


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
