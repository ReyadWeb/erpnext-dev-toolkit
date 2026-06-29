# Roadmap v0.8.16

## Completed in v0.8.15

- Fresh VM storage expansion prompt before disk-space resource check.
- Generic Ubuntu LVM expansion flow confirmed on a resized/cloned VM.
- Runtime and doctor checks passed after install and reboot.

## Completed in v0.8.16

- Private installer logs.
- No generated password printed in terminal/log summary.
- Installer lock for mutating operations.
- Post-install validation summary.
- Clean release packaging direction.
- Stale docs updated.

## Next: v0.8.17 candidate

Focus on guided setup and smoother user progression:

1. Guided install checkpoints.
2. Host `/etc/hosts` verification workflow.
3. Local SSL wizard/checklist.
4. Optional app installation only after base access is confirmed.
5. More compact terminal messaging for small windows.

## Later production planning track

Production automation should remain separate from the local development installer.

Planned production topics:

- Real domain configuration.
- Nginx production reverse proxy.
- Supervisor/systemd production services.
- Let's Encrypt HTTP-01.
- Let's Encrypt DNS-01 with Cloudflare.
- Cloudflare Origin CA.
- Firewall rules.
- Backups and restore testing.
- Monitoring and update strategy.
