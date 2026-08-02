# Docker profiles and durable application images

Phase 4 supports both installation profiles in Docker development and
production. `recommended` remains the default and includes Frappe plus ERPNext.
`frappe-only` builds an explicit Frappe image and creates the site without
ERPNext; ERPNext can be added later with `app install erpnext --site SITE`.
Interactive fresh setup exposes Docker through Advanced installation, where the
profile is selected explicitly and confirmed before configuration is saved.

## Cumulative immutable manifest

Production changes never fetch application source into a running container and
call it durable. The Toolkit validates a root-controlled cumulative manifest,
builds a replacement image, verifies its application set and core versions,
records its `sha256` image identity, verifies backups, then recreates every
application service on that image. Adding another app preserves every earlier
managed app and its ordered dependencies.

The manifest distinguishes image inclusion from site installation. A shared
image affects every site using the stack, while `install-app` targets only the
confirmed site. Preview output identifies that multi-site impact.

## Development versus production

Docker development supports both profiles. Direct development-container app
changes are explicitly temporary and can disappear after recreation. Production
Quick installation always uses the immutable cumulative-image lifecycle.

```bash
erpnext-dev install --profile frappe-only
erpnext-dev app install erpnext --site frappe.test --preview
erpnext-dev app install erpnext --site frappe.test --yes
erpnext-dev app install hrms --site erp.test --yes
```

The operation journal records manifest validation, verified replacement-image
digest, verified site backups, previous image/digest, deployment, site actions,
and full-stack verification. The managed profile and last-known-good manifest
change only after verification succeeds.

Build or image-verification failure leaves the deployment unchanged. Backup
failure blocks deployment. Later failures are `recovery-required` and retain
the previous image and backup references. Recovery means redeploying the
recorded previous image and using the existing verified restore procedure when
needed; Phase 4 does not claim automatic rollback.

Existing recommended v1.20.4 Docker installations remain the default and are
imported into the next cumulative manifest from their installed curated apps
and existing custom-image profile state. Unknown applications stop the build
instead of being silently removed. Updates, uninstallation, arbitrary custom
apps, and major-version upgrades remain out of scope.
