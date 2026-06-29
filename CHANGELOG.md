# Changelog

## v0.8.16 - Security, reliability, and release hygiene

### Security

- Installer logs are now created with private `600` permissions.
- Generated ERPNext Administrator passwords are no longer printed in the terminal summary.
- The terminal summary points users to the protected credentials file instead.

### Reliability

- Added an installer lock file to prevent overlapping setup/repair/service operations from changing the same VM at the same time.
- Added a compact post-install validation summary for storage, service state, autostart, and credentials file presence.

### Release hygiene

- Updated stale documentation references from older versions.
- Clean release ZIP should exclude `.git` and only include the distributable files.

## v0.8.15 - Storage expansion setup fix

- Fixed setup order so storage expansion is offered before the main disk-space resource warning.
- Fixed LVM expansion decision logic so existing VG free space and larger backing disks trigger expansion.
- Confirmed on a fresh Ubuntu LVM VM that root storage can expand before ERPNext install.

## v0.8.14 - Proven generic LVM root expansion flow

- Added generic storage expansion workflow based on the proven Ubuntu LVM resize sequence:
  - `sgdisk -e <disk> || true`
  - `partprobe <disk> || true`
  - `growpart <disk> <partition-number>`
  - `pvresize <physical-volume-partition>`
  - `lvextend -r -l +100%FREE <root-logical-volume>`
- Added `storage-debug` diagnostics.
