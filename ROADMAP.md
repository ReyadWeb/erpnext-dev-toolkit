# Roadmap v0.8.14

## Completed in v0.8.14

- Generic root storage detection.
- Generic root storage expansion for common Ubuntu VM layouts.
- Setup-time expansion prompt.
- Storage status and verification commands.

## Next recommended patch

### v0.9.0 Guided Install Workflow

Planned flow:

1. Install ERPNext.
2. Register local domain on the HOST `/etc/hosts`.
3. Verify HTTP access.
4. Configure local SSL.
5. Verify HTTPS.
6. Configure trusted browser SSL with mkcert guidance.
7. Install optional apps after the base system is confirmed.

The goal is a step-by-step installer that tells the user exactly when to run commands inside the VM and when to run commands on the HOST.

## Later production track

- Keep the developer installer separate from production automation.
- Reuse the same domain-first design for future production domain and SSL workflows.


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
