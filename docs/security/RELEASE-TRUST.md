# Release Trust

**Current stable example:** `v1.20.0`

This guide explains how ERPNext Developer Toolkit releases are validated, signed, verified, installed, and rotated.

The policy-level summary is in [SECURITY.md](../../SECURITY.md).

## Published assets

A normal stable release publishes:

```text
erpnext-dev-vX.Y.Z.tar.gz
erpnext-dev-vX.Y.Z.BUILD-INFO.json
erpnext-dev.sh
RELEASE-MANIFEST.txt
SHA256SUMS
SHA256SUMS.asc
RELEASE-ASSETS.sha256
RELEASE-ASSETS.sha256.asc
erpnext-dev-signing-key.asc
bootstrap-verify.sh
```

The `.tar.gz` archive is the supported complete toolkit. GitHub's automatically generated source archives are not the release bundle.

## Trust chain

The stable release chain is:

```text
canonical VERSION
→ release manifest
→ exact SHA256 inventory
→ release validation
→ disposable integration
→ protected signing environment
→ detached signature
→ complete release archive
→ clean-extract verification
→ GitHub release publication
→ published-asset assertion
```

A stable `vX.Y.Z` release must not publish when the signing key is missing or signature verification fails.

Pre-release tags may use an explicitly marked unsigned emergency path. Treat unsigned prereleases as evaluation artifacts, not ordinary production updates.

## Maintainer identity

The bundled public key is:

```text
docs/erpnext-dev-signing-key.asc
```

Pinned fingerprint:

```text
BFC1 0C79 427C F734 96EA  6F5A 30BF D17D D559 C8B6
```

Key type:

```text
Ed25519 signing key
```

The public key can travel with the release archive. The fingerprint is the trust anchor and should be checked through an independent trusted channel when establishing trust for the first time.

## Verify a downloaded release before privilege

Replace `vX.Y.Z` with the exact release tag. The verifier runs as the ordinary
user and does not execute toolkit code with `sudo`.

```bash
VERSION="vX.Y.Z"
curl -fsSLO \
  "https://github.com/ReyadWeb/erpnext-dev-toolkit/releases/download/${VERSION}/bootstrap-verify.sh"
chmod +x bootstrap-verify.sh
./bootstrap-verify.sh "$VERSION"
```

Before printing a privileged command, the verifier uses the already-installed
system toolchain to check:

1. the pinned signing-key fingerprint;
2. the detached signature over `RELEASE-ASSETS.sha256`;
3. the exact archive digest from that signed external inventory;
4. archive paths and link policy;
5. the extracted internal `SHA256SUMS`;
6. immutable `BUILD-INFO.json` tag, channel, archive and payload identity.

For first-use trust establishment, inspect `bootstrap-verify.sh` and confirm the
pinned fingerprint through an independent trusted channel. The verifier itself
never requests privilege. Only after verification succeeds should an operator
review the extracted tree and run the required toolkit command explicitly.

## Verify an already installed toolkit

```bash
sudo erpnext-dev verify-toolkit
```

Expected integrity status includes:

```text
Active match                 OK
Stable match                 OK
CLI match                    OK
Runtime modules              all match
Unexpected modules           none
```

## Install a selected tag

```bash
sudo env \
  TOOLKIT_UPDATE_VERSION=v1.20.0 \
  erpnext-dev update-toolkit
```

The updater:

1. Downloads the tag-specific release archive.
2. Extracts to a temporary staging location.
3. Verifies complete checksums.
4. Requires the stable detached signature.
5. Requires the signer to match the pinned fingerprint.
6. Installs the release into a versioned directory.
7. Switches active pointers atomically.
8. Retains the previous release.

## Roll back

```bash
sudo erpnext-dev toolkit-rollback
sudo erpnext-dev verify-toolkit
```

Rollback changes only the toolkit release slot. It does not revert ERPNext/Frappe packages, database schema, site data, custom applications, or business data.

Use backup and restore procedures for data recovery.

## Stable release policy

A stable tag is exactly:

```text
vX.Y.Z
```

Stable publication requires:

- Canonical version and runtime version alignment
- Tag and version alignment
- Clean release manifest
- Exact checksum coverage
- Release validator success
- Integration success
- Signing-key availability
- Successful detached signing and verification
- Clean-extract bundle verification
- Required release assets
- Stable release marked as GitHub Latest

## Pre-release policy

A pre-release tag contains a suffix:

```text
vX.Y.Z-beta.N
vX.Y.Z-rc.N
vX.Y.Z-unsigned
```

Pre-releases are marked as GitHub prereleases.

The workflow supports an explicitly marked unsigned emergency prerelease when no signing key is available. Operators should not treat that path as equivalent to a normal signed stable release.

## Signing authority separation

The private signing key is stored in the protected GitHub environment:

```text
release-signing
```

The environment should have:

- Required reviewer approval
- Deployment restricted to `v*` tags
- Administrator bypass disabled for the signing environment
- `GPG_PRIVATE_KEY` stored only as an environment secret
- Optional `GPG_PASSPHRASE` stored only as an environment secret
- No repository-level duplicate of the signing secrets

The publish workflow defaults to read-only permissions. Only the publish job receives `contents: write` for release creation and asset upload.

Repository write access alone should not expose the signing key.

## Maintainer setup

1. Create an offline signing key, preferably Ed25519.
2. Export the public key into `docs/erpnext-dev-signing-key.asc`.
3. Update the pinned fingerprint in the toolkit security module and documentation.
4. Create the `release-signing` GitHub environment.
5. Add required reviewers.
6. Restrict environment deployment to release tags.
7. Add the private key and passphrase as environment secrets.
8. Remove repository-level copies of those secrets.
9. Validate a prerelease before cutting the next stable tag.

Never commit the private key.

## Key rotation

1. Generate the new signing key offline.
2. Export and review the new public key.
3. Update the bundled public key.
4. Update the pinned fingerprint in code and documentation.
5. Merge those changes before using the new key.
6. Replace the protected environment secrets.
7. Revoke or retire the old key.
8. Publish rotation details in release notes.
9. Verify the next signed release reports the new fingerprint.

Historical signatures made with the retired key no longer satisfy the new pinned fingerprint. This is intentional and must be communicated clearly.

## Incident response

When the signing key may be compromised:

1. Stop stable publication.
2. Protect or disable the signing environment.
3. Revoke the affected key.
4. Audit workflow, environment, repository, and account activity.
5. Rotate the key and pinned fingerprint.
6. Publish a security advisory.
7. Release a newly signed fixed version.
8. Instruct operators to verify and upgrade.

Do not silently replace or move an existing release tag.
