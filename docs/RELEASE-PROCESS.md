# Release process

How stable releases of the **ERPNext Developer Toolkit** are produced. Operators
verifying a downloaded release should follow [`SECURITY.md`](../SECURITY.md)
(`verify-signature`, `verify-toolkit`). Contributors normally do **not** cut
releases; this document is for maintainers and curious reviewers.

---

## What a release is

A release is a **git tag** `vX.Y.Z` (or a pre-release tag such as
`vX.Y.Z-unsigned`) on `main` that triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml):

```text
validate  (ci.yml: shellcheck + validate-release + bundle smoke)
    →
integration  (integration.yml: native + Docker smoke gates)
    →
publish  (sign SHA256SUMS when required; attach bundle; GitHub Release)
```

`publish` **needs** both prior jobs. A failing gate never publishes a stable
artifact.

---

## Version sources that must agree

Before tagging, ensure these match `SCRIPT_VERSION` in `erpnext-dev.sh`:

- `CHANGELOG.md` heading `## vX.Y.Z …`
- README bootstrap `VERSION="vX.Y.Z"` pins
- `RELEASE-MANIFEST.txt` header comment `# … Manifest vX.Y.Z`
- Regenerated `SHA256SUMS` after code/manifest edits:

```bash
bash scripts/generate-release-checksums.sh
./scripts/validate-release.sh
```

---

## Maintainer checklist (stable tag)

1. **Land the work on `main`** (CI green on the commit you intend to tag).
2. **Changelog** complete for the version; ROADMAP status updated if needed.
   Keep README / ROADMAP / TESTING **Current release** banners and
   `SCRIPT_VERSION` in sync (`scripts/check-release-doc-alignment.sh`).
3. **Local gate:** `./scripts/validate-release.sh` passes on a clean tree.
4. **Tag and push immediately after merge** (lightweight tags match project history).
   Do not leave `main` advertising a new `SCRIPT_VERSION` for a long time without
   a tag — the README install path follows `/releases/latest` (last *published*
   Assets), but banners still show the in-tree version:

```bash
git checkout main
git pull --ff-only origin main
git tag vX.Y.Z
git push origin vX.Y.Z
```

5. **Watch** the [Release workflow](https://github.com/ReyadWeb/erpnext-dev-toolkit/actions).
6. **Approve** the `release-signing` environment deployment when prompted (signing
   authority separation — see SECURITY.md). Stable tags **require** a successful
   signature.
7. **Do not announce the version until publish finishes.** Pushing the tag creates
   a tag page immediately, but until `publish` completes the page may only show
   GitHub’s automatic Source code archives (no `erpnext-dev-vX.Y.Z.tar.gz`).
   `/releases/latest` is flipped only after Assets upload, so the README
   “Start here” block keeps serving the previous good release until then.
8. **Spot-check** the published GitHub Release assets (`erpnext-dev-vX.Y.Z.tar.gz`,
   `SHA256SUMS`, `SHA256SUMS.asc`), that `/releases/latest` redirects to this tag,
   and that `verify-signature` works from the extracted bundle:

```bash
scripts/assert-github-release-assets.sh vX.Y.Z --require-latest
scripts/resolve-latest-release-tag.sh   # should print vX.Y.Z
```

The release workflow runs that assertion automatically after upload and marks
the stable release with `gh release edit --latest`.

---

## Signing policy (summary)

| Tag shape | Signing |
| --- | --- |
| Stable `vX.Y.Z` | **Required** — publish fails closed without key / signature |
| Pre-release `vX.Y.Z-…` (e.g. `-unsigned`) | May publish unsigned as an escape hatch |

GPG material lives in the **`release-signing` GitHub Environment** (not as
ordinary repository secrets). Repository write access alone must not be enough
to produce a signed release.

Public verification key: [`docs/erpnext-dev-signing-key.asc`](erpnext-dev-signing-key.asc).

---

## What integration must prove (high level)

Exact jobs evolve; today the release-gating legs include:

- Native install smoke (Ubuntu 24.04 hard gate; 26.04 may be preview)
- Docker development (`pwd.yml`) smoke — hard gate
- Docker production (`compose.yaml`) smoke — hard gate (backup/verify/rehearsal)

Do not weaken these without an explicit ROADMAP decision.

---

## Hotfix / docs-only follow-ups

Small commits on `main` after a tag (banner/docs) are fine; they are **not** in
the already-published tag. Ship them in the next patch (`vX.Y.Z+1`) if the
signed bundle must include them.

---

## Related docs

- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — PR validation for contributors
- [`docs/DEVELOPMENT.md`](DEVELOPMENT.md) — local development
- [`SECURITY.md`](../SECURITY.md) — trust model and key rotation
- [`VALIDATION.md`](../VALIDATION.md) — field go-live (not a substitute for CI)
