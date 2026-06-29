# Changelog v0.8.10

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
