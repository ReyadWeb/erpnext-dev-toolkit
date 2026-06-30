# ERPNext Developer Installer v0.8.20

Local developer installer for ERPNext/Frappe on Ubuntu 24.04/26.04 VMs.

## Main workflow

```bash
curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh setup
```

## Important commands

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh verify-access
./install-erpnext-dev.sh local-ssl-wizard
./install-erpnext-dev.sh app-install-wizard
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh next-step
```

## v0.8.20 focus

v0.8.20 fixes the post-expansion storage status decision. Previous versions could still say `Expansion recommended` after the root LV had already been expanded, because they compared the whole disk size to the partition size. That counted earlier partitions such as `/boot` as if they were growable free space.

The storage planner now checks actual free space after the root partition/PV at the end of the disk using sysfs sector data. Expansion is recommended only when:

- LVM has free VG extents, or
- the root partition/PV has growable free space after it on disk.

## Local SSL

For quick local HTTPS:

```bash
./install-erpnext-dev.sh local-ssl-wizard
```

Self-signed certificates are useful for testing. For trusted browser SSL, use `mkcert` on the host and install the generated cert/key into the VM.

## Optional apps

Use the checkpoint workflow:

```bash
./install-erpnext-dev.sh app-install-wizard
```

The wizard shows a preflight, recommends backup checkpoints, installs one optional app at a time, and runs post-app validation.
