
## v0.8.14 - LVM storage detector fallback fix

- Improved generic LVM root detection for common Ubuntu layouts.
- Added lsblk PKNAME fallback for `/dev/mapper/<vg>--<lv>` root devices.
- Keeps storage expansion generic: no hardcoded `/dev/vda3` or Ubuntu LV names.
- `expand-root-storage` now reports unsupported layouts as WARN instead of incorrectly saying no expansion is needed.
- Setup can now ask the user to expand root storage when a larger VM disk is detected.

# Changelog v0.8.14

## Fixed

- Fixed root storage detection for common Ubuntu LVM installs where `/` is mounted from `/dev/mapper/<vg>--<lv>`.
- Added fallback LVM detection by scanning all logical volumes and matching canonical device paths such as `/dev/dm-*`.
- Improved PV detection for LVM roots by parsing the actual LV backing device before falling back to VG-level PV lookup.

## Improved

- `storage-status` should now correctly detect layouts like:
  - `/dev/vda3 -> LVM PV -> /dev/ubuntu-vg/ubuntu-lv -> /`
- `expand-root-storage` can now offer the quick storage fix for more fresh/cloned Ubuntu VMs.
- Storage output now shows the detected root logical volume when available.

## Safety

- Still only expands when a single growable backing partition is detected.
- Multi-PV or unclear LVM layouts remain non-automatic.
- Unknown layouts are skipped with no destructive changes.


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
