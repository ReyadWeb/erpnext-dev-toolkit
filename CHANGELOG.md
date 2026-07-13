## v1.10.2 - Docker create-site fix (site now provisions; no more silent 404)

### Fixed

- **create-site now completes so the site is actually provisioned.** The
  generated `erpnext-dev.override.yml` copied upstream's `until [[ ... ]] && \`
  wait loop with backslash line-continuations inside a YAML `>` folded scalar.
  Folding turns `&& \` + newline + `[[` into `&& \ [[` (an escaped space), which
  demotes `[[` from a bash keyword to a missing command (`[[: command not
  found`). The loop never saw `common_site_config.json`, exited 1, and the site
  was never created -- so the published port answered `404` forever. The wait
  condition is now a single physical line.
- **Docker install no longer reports success when site creation fails.**
  `docker compose up -d` returns as soon as containers *start*, not when the
  one-shot `create-site` job *completes*. So a failed `bench new-site` looked
  like a successful install, and the published port then answered `404` forever
  (the frontend nginx is up, but the backend has no such site). The guided
  Docker install now waits for the `create-site` job to exit, checks its exit
  code, and **fails loudly with the create-site logs** when it errors, instead
  of falling through to a warning. Tunable via `DOCKER_CREATE_SITE_TIMEOUT`
  (default 900s).

### Changed

- CI `docker-install-smoke` now sends the site `Host` header when probing the
  published port, mirroring the native smoke leg (defensive; the Docker
  frontend also pins the site via `FRAPPE_SITE_NAME_HEADER`).

## v1.10.1 - Docker Compose invocation fix + broader Debian host matrix

### Fixed

- **`docker compose: command not found` during Docker install.** The compose
  program was resolved into a `"docker compose"` string and expanded unquoted,
  but the toolkit runs with `IFS=$'\n\t'` (no space), so the string never
  word-split and bash tried to exec a single command literally named
  `docker compose`. The compose program is now resolved into a bash array
  (`docker_compose_resolve`), so both the modern `docker compose` plugin and the
  legacy `docker-compose` binary invoke correctly.

### Changed

- **Docker host OS matrix broadened to Debian 11 / 12 / 13** (was Debian 13 in
  v1.10.0), matching Docker Engine's official host support. Ubuntu 24.04 / 26.04
  remain OK; any other Docker-capable host still installs with a soft warning
  rather than a hard fail.

## v1.10.0 - Multi-engine architecture: Docker as a first-class engine

### Added

- **Deployment engine contract (`lib/engine.sh`).** The toolkit now runs ERPNext
  through one of two first-class engines behind the same CLI and operator
  experience: `native` (direct VM install, the default and unchanged) or
  `docker` (containerized). All routing lives in one place via `engine_*` verbs
  rather than scattered `if docker` branches.
- **Docker deployment engine (`lib/docker.sh`)** wrapping the official
  [`frappe_docker`](https://github.com/frappe/frappe_docker) project. It clones a
  pinned `frappe_docker` ref, uses its upstream `pwd.yml` as the base compose, and
  overlays a small generated override (published port, pinned image tag, chosen
  site name + admin password). Installs Docker Engine via the official
  convenience script when missing, then `docker compose up -d`, creates the site,
  installs ERPNext, and waits for the published port to answer.
- **Engine selection + persistence.** `install` / `local-dev-quickstart` now show
  a "Choose Deployment Engine" step; the choice is saved as `DEPLOYMENT_ENGINE`
  in the toolkit config. New commands: `set-engine` (choose engine) and
  `engine-status` (show the active engine and its settings). Advanced menu items
  48/49 expose the same.
- **Engine-aware lifecycle.** `start`, `stop`, `restart`, `status`, `logs`,
  `backup`, `list-backups`, app installs, and `doctor` route through the active
  engine, so the same commands work on both engines. Native behavior is
  byte-for-byte unchanged (the native path is the default and only runs when
  Docker is not explicitly selected).
- **Native Debian 13 (trixie) support.** `check_os` (and the read-only `doctor` /
  `status` OS checks) now accept Debian 13 in addition to Ubuntu 24.04 / 26.04.
  The native install path already uses Debian-family apt packages, MariaDB/Redis
  systemd units, and `useradd`, so Debian 13 installs through the same flow.
  Previously the toolkit hard-failed on Debian with "designed for Ubuntu Server".
- **Docker hosts:** Ubuntu 24.04 / 26.04 and Debian 13 are accepted as Docker
  hosts (containers are OS-agnostic).

### Testing

- New hermetic unit test `scripts/test-engine-select.sh` (engine normalization,
  native default, config round-trip, docker helper defaults) wired into
  `validate-release.sh` and shellcheck.
- New **non-blocking** `docker-install-smoke` CI job in `integration.yml`: runs a
  real Docker-engine install on ubuntu-24.04 and probes the published port.
  Experimental (`continue-on-error: true`) so it reports on every tag without
  gating releases; the native install leg remains the release gate.

### Notes

- Docker engine scope in this release is local-dev MVP. Production runtime, SSL /
  reverse-proxy parity, firewall/storage guidance, off-VM backups of Docker
  volumes, and durable custom-image app installs are planned for later phases
  (see `ROADMAP.md`).
- Native Debian 13 is supported via the shared Debian-family install path. GitHub
  hosted runners provide no Debian image, so it is not covered by an automated
  native integration leg yet; treat it as community/field-validated.

## v1.9.5 - App library: Gameplan, Lending, India Compliance

### Added

- **Gameplan, Lending, and India Compliance** in the curated app library:
  `install-gameplan`, `install-lending`, `install-india-compliance` (aliases
  `install-gst`, `install-india-gst`). India Compliance is the most-installed
  community GST/e-invoice app on Frappe Cloud; Gameplan and Lending are official
  Frappe products previously missing from the toolkit.
- **Official vs community publisher labels** on every curated app (`Frappe
  (official)` vs `Community / third-party`). Menus show `[official]` /
  `[community]`; install prompts and `app-status` surface the publisher.

## v1.9.4 - Ubuntu 26.04 integration: stable /opt install fix

### Fixed

- **Ubuntu 26.04 / sudo-rs: `/opt/erpnext-dev` not populated after install.**
  `install_self_for_reuse` relied on `readlink -f "${BASH_SOURCE[0]}"`, which
  can return empty when the toolkit is invoked as `sudo ./erpnext-dev.sh` on
  Ubuntu 26.04 (sudo-rs). The copy to `/opt` was skipped silently, ERPNext still
  installed, but integration's `verify-toolkit` step failed with
  `installed toolkit not found at /opt/erpnext-dev/erpnext-dev.sh`. The copy
  now falls back to `ERPNEXT_DEV_ENTRY_SCRIPT` and absolute-path resolution;
  `run_install` / `local-dev-quickstart` fail fast if `/opt` cannot be written.
- **CI verify-toolkit exit 141 (SIGPIPE) on Ubuntu 26.04.** Piping
  `verify-toolkit` into `grep -q` under `set -o pipefail` races: quiet grep
  closes the pipe on first match and the writer gets SIGPIPE. Integration /
  CI / release workflows now capture output to a file, then grep.

### Tests

- New hermetic `scripts/test-install-self-path.sh` asserts entry + `lib/` copy
  when `ERPNEXT_DEV_ENTRY_SCRIPT` is set. Integration adds **Assert stable toolkit
  at /opt** before verify-toolkit.

### Docs

- `TESTING.md`: Ubuntu 26.04 integration leg notes (sudo-rs, `sudo env` vs
  `sudo -E`, install_self failure mode, SIGPIPE/`grep -q` gotcha). Comment
  block in `integration.yml`.

## v1.9.3 - Local host setup friction reduction

### Improved

- **One-command fresh VM install.** README **Start here** now includes a single
  copy-paste block: download the release tarball, verify `SHA256SUMS`, and run
  `local-dev-quickstart`.
- **Copy-paste host commands.** Host `/etc/hosts` mapping and trusted mkcert setup
  (`mkcert -install`, generate cert/key, `scp` to VM `/tmp/`) are emitted as one
  line each with a short description, instead of numbered multi-line steps that
  were easy to copy incompletely.

### Fixed

- **Host `/etc/hosts` mapping: guarantee a trailing newline.** Before appending
  `VM_IP LOCAL_DOMAIN`, the emitted command ensures the hosts file ends with a
  newline so a prior line without one (e.g. a LocalWP `## Local - End ##` block)
  cannot glue the new entry onto the previous line and break resolution.

### Tests

- `scripts/test-host-os-output.sh` asserts the one-liner DNS and mkcert/scp output
  for Linux, macOS, and Windows host OS values.

### Docs

- README local HTTPS section updated to describe the single-line host mapping and
  mkcert/scp flow.

## v1.9.2 - Cross-platform local host support

### Added

- **Host-OS-aware local setup (Linux / macOS / Windows).** A new persisted
  `HOST_OS` setting tailors every host-side instruction the toolkit prints — the
  hosts-file mapping, connectivity tests, trusted mkcert HTTPS, and stable VM-IP
  guidance — to the operator's host machine instead of assuming Linux. The local
  quickstart asks once; change it anytime with `set-host-os` (aliases `host-os`,
  `choose-host-os`). Empty/unknown falls back to Linux, so existing Linux users
  are unaffected.
- **OS-specific host commands.** `print_host_dns_commands_for_site` /
  `print_host_dns_tests_for_site` now emit:
  - **Linux:** `/etc/hosts` via `sudo sed`/`tee`, `getent hosts`.
  - **macOS:** `/etc/hosts` via BSD `sudo sed -i ''` (fixes a latent bug where the
    GNU `sed -i` form fails on macOS), `dscacheutil` for resolution.
  - **Windows:** elevated PowerShell editing `…\drivers\etc\hosts`
    (`Copy-Item` / `Set-Content` / `Add-Content`), `Resolve-DnsName` + `curl.exe`.
  - **Windows + WSL2:** maps the domain to `127.0.0.1` (localhost forwarding)
    rather than the volatile WSL2 IP.
- **mkcert trust per host** in the SSL wizard, guide, browser-trust, and verify
  screens: `apt`+`libnss3-tools` (Linux), `brew install mkcert nss` (macOS),
  `choco install mkcert` (Windows); `mkcert -install` trusts the correct store
  per OS.
- **Stable VM-IP guidance beyond KVM.** `local-fixed-ip-guide` now branches by
  host OS (KVM/libvirt on Linux; UTM/VMware/Parallels on macOS;
  Hyper-V/VirtualBox/WSL2 on Windows) with a universal in-guest netplan fallback.
  `kvm-fixed-ip-guide` / `kvm-guide` remain as the Linux/KVM-specific aliases.

### Fixed

- **Ubuntu 26.04 / GitHub Actions: frappe user creation.** Prefer `useradd` /
  `userdel` over `adduser` / `deluser --remove-home`. On 26.04, `adduser`'s
  `sanitize_string` can abort when `sudo -E` preserves a caller `HOME` that
  contains nvm test filenames with quotes or Unicode (Actions runners). Same
  pattern applied to backup-user creation.

### Tests

- New hermetic `scripts/test-host-os-output.sh` asserts the per-OS DNS/test
  markers (e.g. `/etc/hosts` vs `drivers\etc\hosts`, `getent` vs `Resolve-DnsName`
  vs `dscacheutil`, and the macOS `sed -i ''` form). Wired into
  `validate-release.sh` and `run-shellcheck.sh`.

### Docs

- `README.md`: new "Choose your host OS" subsection with a per-OS command table,
  macOS/Windows/WSL2 notes, and the `set-host-os` command.
- `TESTING.md`: host-mapping regression matrix per host OS.

## v1.9.1 - CI supply-chain hardening

### Security

- **GitHub Actions pinned to immutable commit SHAs.** `actions/checkout` (v4.2.2 →
  `11bd71901bbe5b1630ceea73d27597364c9af683`) and `actions/upload-artifact` (v4.6.2 →
  `ea165f8d65b6e75b540449e92b4886f43607fa02`) are now pinned by commit SHA across
  [`ci.yml`](.github/workflows/ci.yml), [`integration.yml`](.github/workflows/integration.yml),
  and [`release.yml`](.github/workflows/release.yml). A retagged or compromised action
  release can no longer silently enter the pipeline that builds and signs releases.
- **Deliberate updates via Dependabot.** [`.github/dependabot.yml`](.github/dependabot.yml)
  opens weekly, grouped `github-actions` PRs that bump the pinned SHA and its
  `# vX.Y.Z` comment together, keeping updates reviewable instead of implicit.

### Changed

- **Ubuntu 26.04 integration leg enabled (non-blocking preview).** The integration
  matrix now runs `ubuntu-24.04` (mandatory, release-gating) and `ubuntu-26.04`
  (`continue-on-error` via `matrix.experimental`, since the 26.04 hosted image is a
  GitHub public preview). The 26.04 leg becomes a hard gate once the image is GA.

### Docs

- `README.md`, `ROADMAP.md`, `SECURITY.md`: OS-support wording clarified (24.04
  gating + 26.04 preview); v1.9.1 marked shipped; supply-chain rating raised to 9.6.

## v1.9.0 - Signing authority separation

### Security

- **Release signing is separated from repository write access.** The `publish` job in
  [`.github/workflows/release.yml`](.github/workflows/release.yml) now runs in a
  protected `release-signing` GitHub Environment. The GPG signing key is stored as an
  **environment** secret gated by a required-reviewer approval and a `v*` deployment
  tag rule, so a signed release can only be produced after a human approves the
  deployment — not by repository write access or an automated workflow alone.
- **Graceful rollout:** if the environment is not yet configured, GitHub creates it
  unprotected on the first tagged run and signing falls back to repository secrets
  (no regression); configuring the reviewer + tag rule activates the gate.

### Docs

- `SECURITY.md`: new "Signing authority separation (v1.9.0)" section with the one-time
  environment setup, the post-v1.9.0 release flow, and a key-rotation runbook.
- `ROADMAP.md`: v1.9.0 marked shipped; supply-chain rating raised to 9.5.

## v1.8.2 - Self-update authenticity hardening

### Security

- **`update-toolkit` tag-channel updates now match `verify-signature` strictness.**
  Stable release self-updates require `SHA256SUMS.asc`, `gpg`, the bundled maintainer
  public key, a valid detached signature, and a signer fingerprint matching the
  pinned maintainer key (`TOOLKIT_SIGNING_FINGERPRINT_DEFAULT`). Missing material
  or fingerprint mismatch fails closed instead of warn-and-continue.
- **Shared verification core:** `toolkit_gpg_verify_signature_files()` is used by
  both `verify-signature` and `toolkit_verify_staged_signature()` so bootstrap and
  self-update enforce the same identity bar.

### Added

- **`scripts/test-staged-signature.sh`**: hermetic unit matrix for staged signature
  verification (valid signed bundle, missing signature, missing pubkey, tampered
  sums, wrong fingerprint, mismatched pubkey, missing gpg). Runs in
  `validate-release.sh` without sudo.
- **Atomic update smoke** now builds **signed** synthetic bundles with an ephemeral
  test key and asserts unsigned bundles are rejected during update.

### Fixed

- **Atomic update corrupt-bundle negative:** tamper a module without re-signing
  (checksum gate must fail). Re-signing after tamper made the negative pass incorrectly.

## v1.8.1 - Fix integration tamper test (verify installed toolkit)

### Fixed

- Integration CI tamper negative now runs `verify-toolkit` via the **installed**
  `erpnext-dev` CLI (with `CHECKSUM_FILE` pinned), and tampers
  `/opt/erpnext-dev/lib/common.sh`. The previous step used `./erpnext-dev.sh`
  from the checkout, which verified the repo copy and ignored `/opt` tampering,
  causing the v1.8.0 release gate to fail.

## v1.8.0 - Reliability proof: atomic update CI + gate enforcement tests

### Added

- **`scripts/test-atomic-update.sh`**: hermetic smoke test for `update-toolkit` and
  `toolkit-rollback` using a local `file://` release server and synthetic bundles
  (v9.9.8 / v9.9.9). Asserts the `current` symlink flips correctly, rollback
  restores the previous release, and a corrupt bundle is rejected without
  half-applying. Runs in CI (`atomic-update-smoke` job) and locally with
  `sudo -E scripts/test-atomic-update.sh`.
- **`scripts/release-signing-policy.sh`**: extracted stable-vs-pre-release signing
  decision from `release.yml`. Unit-tested in `validate-release.sh` (stable tag
  without GPG key → fail; pre-release without key → publish-unsigned; stable with
  key → sign).

### Changed

- **Negative `verify-toolkit` assertions** in CI: tampering `lib/common.sh` on an
  extracted bundle or a live install must exit non-zero and report `FAIL`.
- `release.yml` calls `release-signing-policy.sh` instead of inlining the regex.

## v1.7.0 - Hardening: private lock path, secret-scan negative fixtures, pinned toolchain

### Security

- **Lock-file hardening.** The single-instance lock no longer uses a
  world-shared `/tmp/erpnext-dev-locks` directory (dir `1777`, file `666`).
  Root now uses `/run/lock/erpnext-dev/`, a normal user uses
  `$XDG_RUNTIME_DIR/erpnext-dev/` (falling back to `/tmp/erpnext-dev-<uid>-locks/`),
  the directory is created mode `0700` and must be owned by us or root, a
  symlinked lock directory/file is refused before any open, and the lock file
  is mode `0600`. This closes the shared-`/tmp` symlink-redirect risk on
  multi-user hosts. `clear-lock` no longer recreates a `666` file.

### Added

- **`versions`** (`version-matrix` / `toolchain` aliases): prints the pinned
  compatibility matrix (Toolkit/Node/nvm/uv/Python/Frappe/ERPNext/frappe-bench).
  The same matrix now appears in `where-installed` and every support bundle.
- **`BENCH_VERSION` pin** (default `5.31.0`): `frappe-bench` is installed at a
  pinned version for reproducible installs. `BENCH_VERSION=` (empty) unpins and
  installs the latest published release.
- **Negative secret-scan fixture** in `scripts/validate-release.sh`: CI now
  asserts `support-bundle-audit` exits non-zero and reports `FAIL` on a bundle
  containing planted secrets/forbidden filenames, so a regression that disabled
  the scanner can no longer pass green.

### Changed

- The pinned toolchain (Node/nvm/uv/Python/branches/bench) is a single source of
  truth in `erpnext-dev.sh`, documented in the README and `SECURITY.md`.

## v1.6.3 - Safer lock recovery + clearer busy-lock errors

### Added

- **`clear-lock`** (`unlock` / `force-unlock` aliases): clears a stale toolkit
  lock only when no process still holds it. Override with
  `FORCE_CLEAR_LOCK=1` if you are certain. Documented in the README.

### Changed

- Busy-lock errors now list **who holds the lock** (PID + command via `fuser` /
  `lsof`), write `pid=` / `started=` / `cmd=` metadata into the lock file, and
  tell users to prefer `sudo erpnext-dev clear-lock` over raw `rm` (which can
  allow two toolkits to run at once).

## v1.6.2 - Menu path consistency for Local / Production SSL

### Changed

- **SSL menus show where you are and how to get back.** Local VM HTTPS / SSL,
  Local SSL Wizard, and Production HTTPS / SSL now print a numbered path
  (`Main menu > 8) Local VM HTTPS / SSL > 1) Local SSL Wizard`), a copy-paste
  reopen command (`sudo erpnext-dev local-ssl-wizard`), and a labeled Back line
  (`b) Back to Local VM HTTPS / SSL`). Re-running the same wizard option is
  noted as the way to continue after leaving (completed steps are detected
  where possible).

## v1.6.1 - Local access + mkcert UX fix

### Fixed

- **Unstyled page via raw IP.** Access messaging (`access-info`, `desk-url`,
  ready summary, education URLs) now prefers the friendly hostname
  (`http://${SITE_NAME}:8000` or `https://${SITE_NAME}` when local HTTPS is up).
  Raw `http://<vm-ip>:8000` is labeled troubleshooting-only with an explicit
  warning that it often shows a broken/unstyled login (Host-header mismatch).
  `local-access-doctor` diagnoses the same symptom.
- **mkcert wizard no longer forces a menu exit.** `trusted-mkcert-setup` now:
  (0) prints the HOST `/etc/hosts` checkpoint and confirms it, (1) prints
  numbered HOST mkcert/scp commands, (2) **waits and rechecks** `/tmp` for the
  cert/key (Enter after scp, or `skip` / `guide`), then (3) installs, configures,
  and verifies HTTPS in the same session. Recommended browser URL is
  `https://${SITE_NAME}` only.
- **Wrong “Next:” path after `verify-signature`.** `active_toolkit_path` now
  prefers `ERPNEXT_DEV_ENTRY_SCRIPT` instead of `BASH_SOURCE[1]`, so hints no
  longer point at `lib/common.sh`.

## v1.6.0 - Gated & mandatory-signed releases, atomic self-update

### Changed

- **Releases are now gated on the full test pipeline.** `release.yml` no longer
  publishes independently of CI. On a `v*` tag it runs one pipeline: `validate`
  (reuses `ci.yml`: shellcheck + `validate-release.sh` + bundle quickstart) ->
  `integration` (reuses `integration.yml`: real disposable-VM install + backup/
  restore round-trip + production-runtime conversion) -> `publish`. The
  `publish` job `needs: [validate, integration]`, so a release can never be
  published unless both the static gate and the full integration run succeed
  first. `ci.yml` and `integration.yml` are now reusable (`workflow_call`) and no
  longer fire on tags themselves (release.yml orchestrates them), avoiding
  duplicate multi-hour runs per tag.
- **Release signing is mandatory for stable tags.** A stable `vX.Y.Z` tag now
  FAILS the release if the signing key is missing or signing/verification fails.
  An explicit escape hatch remains for emergencies: a pre-release tag
  (e.g. `vX.Y.Z-unsigned`) may publish unsigned and is marked as a GitHub
  pre-release. Previously any tag would silently publish unsigned when the key
  was absent.
- **Self-update is now atomic and rollback-capable.** `update-toolkit` downloads
  the signed release bundle, verifies whole-tree checksums and (offline) the
  detached signature against the bundled pinned key, extracts to
  `/opt/erpnext-dev/releases/<ver>/`, then flips `/opt/erpnext-dev/current` in a
  single atomic `rename`. A crash mid-update can no longer leave a half-written
  tree mixing modules from two versions. The previous release is retained
  (newest `TOOLKIT_RELEASES_KEEP=3` kept), and the new **`toolkit-rollback`**
  command restores it instantly.

### Fixed

- **Latent CLI/symlink bug:** the entry script now resolves its own real path
  (`readlink -f`) before locating `lib/`, so invoking the toolkit through the
  `/usr/local/bin/erpnext-dev` CLI symlink (or the new `current` release symlink)
  sources modules from the real release directory instead of failing to find
  `lib/` next to the symlink.

## v1.5.1 - Local guided setup now walks through HTTPS / hardening / apps

### Changed

- **`local-dev-quickstart` is now a true end-to-end guided experience.** After
  the core install it actively prompts through the local follow-ups — trusted
  local **HTTPS** (`local-ssl-wizard`), the local **security profile / firewall**
  (`security-hardening-wizard`), and the **optional app installer**
  (`app-install-wizard`) — mirroring how the public-vm guided setup chains its
  steps. Previously the local flow only printed these as recommendations.
- Each optional step is **opt-in** (the prompt defaults to "No"/skip). The chain
  only runs in an interactive session; `-y`/non-interactive `install` keeps the
  plain install-only behavior, so automation and CI are unaffected.

## v1.5.0 - Production runtime mode (no `bench start` in production)

### Added

- **A real production runtime.** Production no longer serves ERPNext with
  `bench start` (a development server with a live-reload watcher and an active
  debugger, which logs "do not use in a production deployment"). New commands:
  - `setup-production-runtime` (aliases: `convert-to-production`) — installs
    `supervisor`, runs Frappe's own `bench setup supervisor` to generate the
    correct, version-matched process set (**gunicorn** web workers, **scheduler**,
    background **workers**, and the **socket.io** node process), links it into
    `/etc/supervisor/conf.d/`, disables the dev `erpnext-dev.service`, and starts
    the supervised stack. The toolkit's existing Nginx/TLS layer is unchanged and
    keeps proxying `:443/:80` to gunicorn (`:8000`) and socket.io (`:9000`).
  - `convert-to-dev-runtime` — reverts to the `bench start` development runtime.
  - `production-runtime-status` — shows supervisor programs, gunicorn/socket.io
    ports, and HTTP readiness.
- The public-vm / production guided setup now offers to switch to the production
  runtime after install.
- A persisted `RUNTIME_MODE` (`dev` | `production`) in
  `/etc/erpnext-dev/config.env`, independent of `DEPLOYMENT_MODE`. `start`,
  `stop`, `restart`, `service-status`, `logs`, and `runtime_state` all route to
  the supervisor stack when `RUNTIME_MODE=production`.

### Changed

- `wait_for_erpnext_ready` additionally requires an HTTP `200` from
  `/api/method/ping` in production, so readiness is not reported while gunicorn
  is still booting workers.
- CI: the disposable-VM integration test now converts to the production runtime
  and asserts supervisor is up, gunicorn serves `:8000`, socket.io listens on
  `:9000`, and **no `bench start` process is running**.
- Bumped the toolkit version to v1.5.0 and regenerated `SHA256SUMS`.

## v1.4.6 - verify-toolkit now verifies the whole tree, not just the entrypoint

### Changed

- **`verify-toolkit` now verifies every runtime module.** Previously it only
  checked `erpnext-dev.sh` against `SHA256SUMS`, so a tampered `lib/*.sh` module
  passed verification. It now hashes all 17 modules from
  `toolkit_release_lib_files()` against `SHA256SUMS`, reports
  `Runtime modules OK N/N`, and fails (non-zero exit) on any mismatched or
  missing module. It also flags any `lib/*.sh` present on disk that is not part
  of the signed release list (`Unexpected modules`).
- Bumped the toolkit version to v1.4.6 and regenerated `SHA256SUMS`.

## v1.4.5 - Pre-create NVM_DIR so the nvm installer accepts it

### Fixed

- **The install still aborted at the Node step on a fresh VM** (a follow-on to
  the v1.4.4 fix). With `XDG_CONFIG_HOME` set, the nvm installer's default
  install dir is `$XDG_CONFIG_HOME/nvm`, and the installer only auto-creates
  `NVM_DIR` when it matches that default. Because we force `NVM_DIR=$HOME/.nvm`,
  the installer refused with `You have $NVM_DIR set to "/home/frappe/.nvm", but
  that directory does not exist`. The installer now `mkdir -p "$NVM_DIR"` before
  running the nvm installer, so nvm clones straight into `$HOME/.nvm`.

### Changed

- Bumped the toolkit version to v1.4.5 and regenerated `SHA256SUMS`.

## v1.4.4 - Fix nvm install location broken by the XDG pins

### Fixed

- **The install aborted at the Node step on a fresh VM.** The v1.4.1 XDG fix
  exports `XDG_CONFIG_HOME="$HOME/.config"`, and the nvm installer honors
  `XDG_CONFIG_HOME` when `NVM_DIR` is unset — so nvm was installed into
  `$HOME/.config/nvm`, while the rest of the toolkit (this installer, the
  systemd unit, `frappe.sh`, `apps.sh`) all source `$HOME/.nvm/nvm.sh`. The
  install failed with `/home/frappe/.nvm/nvm.sh: No such file or directory`.
  The installer now exports `NVM_DIR="$HOME/.nvm"` **before** running the nvm
  installer (and passes it through to the installer), so nvm always lands in
  `$HOME/.nvm` regardless of the XDG environment. The presence guard now checks
  for `$NVM_DIR/nvm.sh` instead of the `.nvm` directory.
- This was masked in CI because GitHub-hosted runners pre-set `NVM_DIR`, which
  happened to point nvm at the expected path; a genuinely fresh VM (no
  `NVM_DIR`) exposed it.

### Changed

- Bumped the toolkit version to v1.4.4 and regenerated `SHA256SUMS`.

## v1.4.3 - Integrity/self-update chain fixes, working CLI commands, and drift guards

### Fixed

- **The documented one-command install was broken since modularization.** The quickstarts downloaded only `erpnext-dev.sh` + `SHA256SUMS`, but the toolkit now sources `lib/*.sh` at runtime — so `sha256sum -c` failed on ~19 missing files and the script aborted with `Missing toolkit library: .../lib/common.sh`. Neither CI (which uses a full `git checkout`) nor the release workflow (which published only `erpnext-dev.sh`) exercised the actual download-and-run path, so it silently regressed. Fixed by shipping a complete bundle (below) and rewriting every README quickstart to download → verify → extract → run it.
- **`install-cli` / `repair-cli` now work.** Both were advertised in `--help` and the dispatcher but routed to `install_toolkit_cli` / `repair_toolkit_cli`, which did not exist — running either exited `127` with `command not found`, while `command-audit` still reported them "OK" (a false positive). Both are now implemented and (re)create the `erpnext-dev` command idempotently via `install_toolkit_cli_entry`.
- **`lib/update.sh` is now inside the integrity and self-update chain.** It was sourced at runtime (implementing the privileged `update-preflight` / `safe-update-wizard` / `update-rollback` paths) but was missing from `toolkit_release_lib_files()` and the checksum generator, so a tampered `update.sh` passed `sha256sum -c SHA256SUMS` and was never fetched by `update-toolkit`. It is now in `toolkit_release_lib_files()`, `SHA256SUMS`, the shellcheck targets, and the `validate-release.sh` syntax checks.

### Added

- **Self-contained release bundle.** `scripts/build-release-bundle.sh` packages the entire verified tree (everything in `RELEASE-MANIFEST.txt`, plus `SHA256SUMS.asc` when signed) into `erpnext-dev-<version>.tar.gz`. The release workflow builds it after signing and attaches it as a release asset; the internal signed `SHA256SUMS` anchors trust for every packaged file, and `verify-signature` works offline from the extracted directory. A CI step (and a release-workflow step) now builds the bundle, extracts it to a clean directory, and runs `sha256sum -c` + `verify-toolkit` from there, so an incomplete installer fails the build instead of a user's VM.
- **`scripts/check-module-consistency.sh`** — a CI guard that treats the runtime `source` chain in `erpnext-dev.sh` as the single source of truth and fails the build if `toolkit_release_lib_files()`, the checksum generator, the shellcheck targets, `SHA256SUMS`, or `RELEASE-MANIFEST.txt` describe a different set of `lib/*.sh` modules. It also verifies that every function invoked from the command dispatcher is actually defined (which would have caught the `install-cli`/`repair-cli` regression). Wired into `validate-release.sh` so it runs in both CI and the release workflow.
- **Version-discipline guard.** With `RELEASE_STRICT=1` (set by the release workflow) `validate-release.sh` now refuses to publish a stable tag whose newest `CHANGELOG.md` entry is not the released version (e.g. an open `## Unreleased` section). Development branches may keep an `Unreleased` section.

### Removed

- Deleted three stale/redundant docs: `QUALITY-ASSESSMENT.md` (assessed v1.2.1 — claimed no CI, no GPG signing, and a monolithic script, all long false), `PRODUCTION-VALIDATION.md` (a private field-evidence log with real domain/IPs), and `RELIABILITY-PLAN.md` (superseded by `ROADMAP.md` + `SECURITY.md`). Removed them from `RELEASE-MANIFEST.txt` and the `validate-release.sh` existence checks.
- **Rewrote `README.md`** into a clean, organized guide: banner + short description, a "Menu" table of contents whose first item is a per-case "Start here" command reference, no embedded version history, and all private testing data (real domain, VPS/backup IPs, cloud provider, volume IDs) replaced with placeholders. Corrected the supported OS to Ubuntu 24.04 / 26.04 and documented the guarded-upgrade commands. Trimmed from ~1760 to ~620 lines.

### Changed

- **Pinned bootstrap tool versions for reproducible installs.** Added `NVM_VERSION` (0.40.3) and `UV_VERSION` (0.11.28) config variables; the installer now fetches `uv` from the versioned `https://astral.sh/uv/${UV_VERSION}/install.sh` URL instead of the unversioned "latest" installer, and the pinned nvm version flows from `NVM_VERSION`. Override either via environment variable.
- Bumped the toolkit version to v1.4.3 and regenerated `SHA256SUMS`.

### Changed (lint hardening, behavior-preserving)

- `scripts/run-shellcheck.sh` now fails the build on shellcheck **warnings** (`-S warning`), not just errors. The full toolkit is clean at this level.

### Fixed / cleaned (behavior-preserving)

- **Deduplicated the command allowlists**: the argument-parser case in `erpnext-dev.sh` (332 -> 307 patterns) and the `action_requires_lock` case in `lib/common.sh` (213 -> 207 patterns) had repeated command tokens (SC2221/SC2222). A repeated `case` pattern (`a|a`) is a no-op, so this changes no behavior; it just removes the overlap that shellcheck flagged and makes the lists easier to audit.
- Fixed a quoting bug in `lib/service.sh` where the double quotes meant to appear in the printed `bench start` hint were consumed by the shell (SC2140); the hint now prints `export PATH="$HOME/.local/bin:$PATH"` verbatim.
- Removed dead `was_running` capture blocks in `lib/backup.sh` (x2) and `lib/apps.sh` that were written but never read; the surrounding restart logic is unchanged.
- Removed unused local declarations and dead assignments flagged by SC2034 (`lib/health.sh`, `lib/security.sh`, `lib/status.sh`, `lib/ssl.sh`, `lib/frappe.sh`, `lib/backup.sh`, `lib/support.sh`), dropped the unused `DIM` color, and removed the dead `LIB_APP_KEY` metadata column from `lib/apps.sh` (set for every app, read nowhere).
- Declared the menu `*_choice` variables `local` at their call sites so shellcheck can see they are assigned via `menu_read_choice` (SC2154); this also stops them leaking into the global scope between menu invocations.
- Annotated intentional patterns with scoped `# shellcheck disable` directives: cross-module globals `SUDO`/`PRODUCTION_SSL_MODE` (consumed by sourced modules), the optional-argument functions `wait_for_erpnext_ready`/`run_local_ssl_wizard` (SC2120), and the two `sudo ... > /tmp/...$$` redirects in `scripts/validate-release.sh` that intentionally write the invoking user's temp file (SC2024).

## v1.4.2 - Fix Node version selection for the bench service

### Fixed

- With the v1.4.1 install fix in place, the disposable-VM integration run got all the way to the site-readiness gate and surfaced the next latent bug: the `erpnext-dev.service` systemd unit (and any cold `bench start`) sources `nvm.sh` but never selected a Node version, so the service shell fell back to whatever Node was on `PATH` (Node 22 on the CI runner). Frappe's watcher refused to run (`The engine "node" is incompatible with this module. Expected version ">=24". Got "22.23.1"`), `bench start` exited, and nothing listened on `:8000`.
- The installer now runs `nvm alias default "${NODE_VERSION}"` after installing Node, so non-interactive login shells that only source `nvm.sh` (the systemd unit, `frappe_login_bash`) activate the correct Node version. The `ExecStart` of the bench service also explicitly runs `nvm use --silent default` after sourcing nvm as a belt-and-suspenders guard.
- This also hardens real deployments: a cold service restart on a fresh VM with no system Node (or an incompatible one) would have hit the same failure.

### Changed

- Bumped the toolkit version to v1.4.2 and regenerated `SHA256SUMS`.

### Validation scope

- `bash -n` passes for `lib/install.sh`, `lib/service.sh`, and `erpnext-dev.sh`; `scripts/validate-release.sh` passes locally. The end-to-end path (install -> service up -> site reachable on `:8000` -> backup/restore rehearsal) is exercised by the integration workflow on the next tag.

## v1.4.1 - Fix XDG environment leak in the installer

### Fixed

- The disposable-VM integration workflow caught a real install bug: when the toolkit runs the stack build as the `frappe` user it sets `HOME`, but a caller-inherited `XDG_CONFIG_HOME` (e.g. `/home/runner/.config` under the CI runner, or any `sudo` invocation whose env preserves it) leaked through unchanged. The `uv` installer derives its receipt directory from `XDG_CONFIG_HOME` and failed with `unable to create receipt directory at /home/runner/.config/uv` (`Permission denied`), aborting the install. On a normal fresh VM `XDG_CONFIG_HOME` is unset so the bug was invisible outside CI.
- The installer now pins `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, and `XDG_CACHE_HOME` under the `frappe` home (and pre-creates them) inside the frappe login shell, so tool state is written to a writable, deterministic location regardless of the invoking user's environment.

### Changed

- Bumped the toolkit version to v1.4.1 and regenerated `SHA256SUMS`.

### Validation scope

- `bash -n` passes for `lib/install.sh` and `erpnext-dev.sh`; `scripts/validate-release.sh` passes locally. The fix is exercised end-to-end by the next integration run.

## v1.4.0 - Guarded ERPNext upgrades (E5)

### Added

- **`lib/update.sh`** implementing a backup-first, verified upgrade flow for installed ERPNext/Frappe apps. `bench update` (pull + migrate + build + restart) is the riskiest routine operation on a working site; this module wraps it so an upgrade is always pre-checked, backed up, health-verified, and rollback-documented.
- **`update-preflight`** (aliases `upgrade-preflight`): read-only readiness report — environment/production caution, service state, free disk (needs >= 5 GiB), uncommitted changes in app working trees (a hard blocker), current app branch@commit, and backup recency. Returns non-zero on blockers.
- **`safe-update-wizard`** (aliases `safe-update`, `update-erpnext`, `upgrade-erpnext`): runs the preflight (abort on blockers unless `UPDATE_FORCE=1`), requires a typed `UPDATE` confirmation (bypassable with `-y`/`ASSUME_YES=1`), takes a full backup, records pre-upgrade commit state to a rollback file, runs `bench update`, then re-runs migrate and gates on a post-upgrade health check. Prints a concrete rollback plan on any failure.
- **`update-rollback`** (alias `rollback-update`): checks out the app commits recorded before the last upgrade (typed `ROLLBACK` confirmation), rebuilds, restarts, and points to `restore-full` for the recorded database backup.
- Registered `lib/update.sh` in the source chain, shellcheck targets, and `RELEASE-MANIFEST.txt`; documented the new commands in `help`.

### Changed

- Updated the toolkit version to v1.4.0 and regenerated `SHA256SUMS`.

### Security

- Rotated the release-signing key. The pinned maintainer fingerprint is now `BFC10C79427CF73496EA6F5A30BFD17DD559C8B6` (Ed25519); the previous key was retired. `SHA256SUMS.asc` on `v1.4.0`+ is produced by the new key, and `verify-signature` enforces the new fingerprint. Signatures made by the old key no longer validate by design.
- `credentials-show` no longer prints secrets to the logged stdout stream. Because the toolkit tees stdout to a log file, the credential block now goes directly to the controlling terminal (`/dev/tty`); in a non-interactive session it refuses to print rather than persist plaintext secrets in the log.

### Notes

- Code rollback does not by itself revert database schema migrations; the wizard and rollback both direct the operator to the recorded backup via `restore-full` for a full revert.

### Validation scope

- `bash -n` passes for `lib/update.sh` and `erpnext-dev.sh`; the toolkit sources cleanly and `version`/`help` expose the new commands.
- `scripts/validate-release.sh` passes locally. shellcheck runs in CI.

## v1.3.0 - Verified & signed: restore-rehearsal CI and GPG-signed releases

### Added

- **Restore-rehearsal in CI (Phase D, D4).** The integration workflow now performs a real backup -> restore round trip on the freshly installed disposable-VM runner: `backup-files`, `backup-verify`, then a non-interactive `restore-full` (auto-selects the latest complete set under `-y`, auto-detects DB credentials, and the required `RESTORE` confirmation is piped in). A post-restore hard gate re-asserts `doctor --json` `install_state=Installed` and that the site still answers `/api/method/ping`. This proves toolkit backups are actually restorable, not just creatable.
- **Signed releases (Phase C P0, item 5).** Added `.github/workflows/release.yml`: on every `v*` tag it validates the release tree, confirms the tag matches `SCRIPT_VERSION`, signs `SHA256SUMS` with the maintainer GPG key (when the `GPG_PRIVATE_KEY` secret is configured), and publishes a GitHub Release with `SHA256SUMS`, `SHA256SUMS.asc`, and the script attached.
- **`verify-signature` command.** Verifies the detached GPG signature over `SHA256SUMS` in a throwaway keyring (no changes to the operator's GnuPG state). Honours `TOOLKIT_SIGNING_PUBKEY` (path or https URL), an optional `TOOLKIT_SIGNING_KEY_FINGERPRINT` identity pin, and `TOOLKIT_SIGNATURE_FILE`. Aliases: `verify-release-signature`, `verify-sig`.
- Documented maintainer signing setup and end-user verification in `SECURITY.md` ("Verifying release signatures") and a production-verification note in `README.md`.
- Listed `.github/workflows/release.yml` in `RELEASE-MANIFEST.txt`.

### Changed

- Updated the toolkit version to v1.3.0.
- Regenerated `SHA256SUMS`.

### Security

- Signed releases add maintainer-identity verification on top of SHA256 integrity, closing the P0 gap where an attacker controlling both the script and its checksum could defeat SHA256-only verification.

### Notes

- Signing activates once the maintainer configures the `GPG_PRIVATE_KEY` (and optional `GPG_PASSPHRASE`) repository secret and publishes the public key fingerprint; until then `release.yml` publishes unsigned with a CI warning rather than failing.

### Validation scope

- `bash -n` passes for all shell files; `integration.yml` and `release.yml` parse as valid YAML.
- `erpnext-dev version` prints v1.3.0; `help` exposes `verify-signature`.
- `scripts/validate-release.sh` passes locally.

## v1.2.4 - Phase D: promote integration site reachability to a hard gate

### Changed

- The integration workflow (`integration.yml`) now treats site reachability as a hard gate rather than a warning. After install it requires the site to answer `/api/method/ping` on `:8000`.
  - The probe sends a `Host: <site>` header so Frappe routes to the installed site rather than a bare `localhost` (which can resolve to the wrong or a non-existent site).
  - It polls for up to 6 minutes (36 x 10s) after `wait-ready` to tolerate first-boot asset builds and migrations.
  - On failure the step emits a GitHub `::error::` and dumps `systemctl status`, the last 200 journal lines, and listening sockets on `:8000`/`:9000` for immediate diagnosis.

### Notes

- v1.2.3 shipped this smoke as a non-fatal warning; v1.2.4 makes both `install_state=Installed` and reachability required. Adjust the 6-minute window from real hosted-runner timing once the first live runs complete.

### Validation scope

- `integration.yml` parses as valid YAML.
- `erpnext-dev version` prints v1.2.4.
- `scripts/validate-release.sh` passes locally.

## v1.2.3 - Phase D groundwork: disposable-VM integration testing

### Added

- Added `.github/workflows/integration.yml`, a separate integration workflow that performs a real, non-interactive ERPNext install on an ephemeral GitHub-hosted runner (used as a disposable VM) and runs a post-install smoke check.
  - Triggers: `workflow_dispatch` (manual, with a `site_name` input), a weekly `schedule` (Mondays 06:00 UTC), and release tags (`v*`). It intentionally does not run on pull requests, so the fast `ci.yml` lint/validate gate remains the PR path.
  - CI-safety environment: `ERPNEXT_ALLOW_UNSAFE_INSTALL=true` (hosted runners are under the 30 GB preflight minimum), `AUTO_EXPAND_ROOT=false` (never grow the runner disk), `AUTO_START=true`, `ENABLE_AUTOSTART=false`.
  - Smoke assertions: verifies `SHA256SUMS`, runs `install-preflight`, installs with `-y`, then asserts `doctor --json` reports `install_state=Installed`, surfaces any `FAIL` checks, probes `http://localhost:8000/api/method/ping`, and uploads toolkit logs and the service journal as artifacts.
- Listed `.github/workflows/integration.yml` in `RELEASE-MANIFEST.txt`.

### Changed

- Updated the toolkit version to v1.2.3.
- Regenerated `SHA256SUMS` for the updated `erpnext-dev.sh` and `RELEASE-MANIFEST.txt`.

### Notes

- The Ubuntu 26.04 matrix entry is present but commented out until a GitHub-hosted `ubuntu-26.04` runner label is available; the steps are OS-agnostic and need no other change to enable it (roadmap D2).
- Site reachability is currently a non-fatal warning; the `install_state=Installed` assertion is the hard gate for this increment.

### Validation scope

- `bash -n` passes for all shell files.
- `integration.yml` parses as valid YAML.
- `erpnext-dev version` prints v1.2.3.
- `scripts/validate-release.sh` passes locally.

## v1.2.2 - Maintenance: remove dead code (Phase F3)

### Removed

- Removed 16 unreferenced helper functions flagged by the v1.2.1 evaluation, with no runtime behavior change:
  - `lib/storage.sh`: `storage_part_number`, `storage_parent_disk`, `storage_partition_is_growable`, `storage_infer_disk_from_partition`, `storage_root_lsblk_value`
  - `lib/ssl.sh`: `read_multiline_secret_to_file`, `production_certificate_subject`, `production_ssl_is_configured`
  - `lib/backup.sh`: `backup_find_latest`, `backup_schedule_unit_paths`, `off_vm_backup_rsync_command`
  - `lib/access.sh`: `show_access_when_ready`, `show_host_dns_guide`
  - `lib/common.sh`: `ui_note`
  - `lib/firewall.sh`: `firewall_latest_snapshot`
  - `lib/service.sh`: `start_erpnext`

### Changed

- Updated the toolkit version to v1.2.2.
- Regenerated `SHA256SUMS` for the seven affected modules and `erpnext-dev.sh`.

### Validation scope

- `bash -n` passes for all shell files.
- Re-ran dead-code cross-reference analysis: 560 -> 544 functions, 0 remaining dead functions (no cascading dead code introduced).
- `erpnext-dev version` prints v1.2.2.
- `scripts/validate-release.sh` passes locally.

## v1.2.1 - Maintenance: shellcheck coverage and repo hygiene

### Fixed

- `scripts/run-shellcheck.sh` now lints the main `erpnext-dev.sh` entry point. It was previously omitted from the shellcheck target list even though the file already carries `# shellcheck source=...` directives, leaving the toolkit's largest dispatched surface unlinted in CI.
- Removed duplicated `# Local release handoff notes` / `GITHUB-UPDATE-v*.md` block from `.gitignore`.

### Changed

- Updated the toolkit version to v1.2.1.
- Regenerated `SHA256SUMS` for the updated `erpnext-dev.sh` and `scripts/run-shellcheck.sh`.

### Notes

- No runtime behavior changes; this is a release-engineering and hygiene patch. A full professional evaluation (v1.2.1) recorded 16 unreferenced helper functions and module-list duplication across four files as tracked cleanup tasks in `ROADMAP.md`; these are deferred to avoid unverifiable churn in a single patch.

### Validation scope

- `bash -n` passes for all shell files.
- `erpnext-dev version` prints v1.2.1.
- `scripts/validate-release.sh` passes locally.

## v1.2.0 - Phase C security hardening

### Added

- Added `lib/security.sh` with `security-audit`, checksum-gated `update-toolkit`, and production credential handoff prompts.
- Added `security-audit` command for read-only SSH, firewall, HTTPS, credential, and patch posture review.

### Changed

- Updated the toolkit version to v1.2.0.
- `update-toolkit` now downloads tag-pinned releases (default `TOOLKIT_UPDATE_VERSION` or prompt) and verifies every downloaded artifact against `SHA256SUMS` before install.
- Production/public-vm workflows refuse mutable `main`-branch updates unless `TOOLKIT_UPDATE_ALLOW_MAIN=1`.
- Post-install and public VM guided QA now prompt operators to secure-handoff and optionally delete plaintext credentials.
- Expanded support-bundle audit forbidden filenames and secret-pattern detection.
- Documented private security disclosure expectations in `SECURITY.md`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and `lib/security.sh`.
- `erpnext-dev version` prints v1.2.0.
- `scripts/validate-release.sh` passes locally.

## v1.1.90 - Extract lib/ops.sh for production operations menus

### Added

- Added `lib/ops.sh` with the production operations dashboard summary, submenus, and wizard.

### Changed

- Updated the toolkit version to v1.1.90.
- `erpnext-dev.sh` now sources `lib/ops.sh` after `lib/install.sh`.
- `erpnext-dev.sh` is reduced to toolkit bootstrap, menus, help, and dispatcher logic (~1,180 lines).
- `update-toolkit` now downloads `ops.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/ops.sh`.
- Phase B modularization is complete; next milestone is Phase C security hardening (v1.2.0).

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and `lib/ops.sh`.
- `erpnext-dev version` prints v1.1.90.
- `scripts/validate-release.sh` passes locally.

## v1.1.89 - Extract lib/status.sh for install/runtime status helpers

### Added

- Added `lib/status.sh` with status summaries, runtime/install/service reports, status menu, and full health report.

### Changed

- Updated the toolkit version to v1.1.89.
- `erpnext-dev.sh` now sources `lib/status.sh` after `lib/service.sh`.
- `update-toolkit` now downloads `status.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/status.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and `lib/status.sh`.
- `erpnext-dev version` prints v1.1.89.
- `scripts/validate-release.sh` passes locally.

## v1.1.88 - Extract lib/frappe.sh and remove duplicate support/doctor code

### Added

- Added `lib/frappe.sh` with path helpers, bench detection, Frappe user execution, VM context guards, and site/app probes.

### Changed

- Updated the toolkit version to v1.1.88.
- `erpnext-dev.sh` now sources `lib/frappe.sh` after `lib/access.sh`.
- Removed duplicate doctor, support-bundle, and command-audit implementations from `erpnext-dev.sh`; `lib/support.sh` is now the single source.
- `erpnext-dev.sh` is reduced to menus, status glue, production-ops wizard, and dispatcher logic (~1,900 lines).
- `update-toolkit` now downloads `frappe.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/frappe.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and `lib/frappe.sh`.
- `erpnext-dev version` prints v1.1.88.
- `scripts/validate-release.sh` passes locally.

## v1.1.87 - Extract lib/access.sh for browser access and credentials UI

### Added

- Added `lib/access.sh` with VM IP detection, host DNS helpers, access verification, networking guides, access menu, and credentials workflows.

### Changed

- Updated the toolkit version to v1.1.87.
- `erpnext-dev.sh` now sources `lib/access.sh` after `lib/config.sh`.
- `update-toolkit` now downloads `access.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/access.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and `lib/access.sh`.
- `erpnext-dev version` prints v1.1.87.
- `scripts/validate-release.sh` passes locally.

## v1.1.86 - Extract lib/config.sh for site and domain configuration

### Added

- Added `lib/config.sh` with site-name validation, saved config loading, domain wizards, config file I/O, and production domain planning helpers.

### Changed

- Updated the toolkit version to v1.1.86.
- `erpnext-dev.sh` now sources `lib/config.sh` after `lib/common.sh`.
- `update-toolkit` now downloads `config.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/config.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and `lib/config.sh`.
- `erpnext-dev version` prints v1.1.86.
- `scripts/validate-release.sh` passes locally.

## v1.1.85 - lib/install.sh Tier C guided setup and quickstart workflows

### Changed

- Extended `lib/install.sh` with guided setup, local/public quickstarts, public VM guided flow, and first-run wizard.
- Updated the toolkit version to v1.1.85.
- `lib/install.sh` is now the complete install module (Tiers A–C).

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and `lib/install.sh`.
- `erpnext-dev version` prints v1.1.85.
- `scripts/validate-release.sh` passes locally.

## v1.1.84 - lib/install.sh Tier B post-install summaries

### Changed

- Extended `lib/install.sh` with `post_core_install_checkpoint`, `post_install_validation_summary`, and `print_summary`.
- Updated the toolkit version to v1.1.84.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and `lib/install.sh`.
- `erpnext-dev version` prints v1.1.84.
- `scripts/validate-release.sh` passes locally.

## v1.1.83 - Extract lib/install.sh Tier A for core install engine

### Added

- Added `lib/install.sh` with install preflight, system package setup, Frappe stack bootstrap, credential file writing, and install/repair/uninstall commands.

### Changed

- Updated the toolkit version to v1.1.83.
- `erpnext-dev.sh` now sources `lib/install.sh` after `lib/service.sh`.
- `update-toolkit` now downloads `install.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/install.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and all `lib/*.sh` modules.
- `erpnext-dev version` prints v1.1.83.
- `scripts/validate-release.sh` passes locally.

## v1.1.82 - Extract lib/service.sh for ERPNext service and runtime helpers

### Added

- Added `lib/service.sh` with systemd service management, bench readiness checks, runtime state helpers, and the service manager menu.

### Changed

- Updated the toolkit version to v1.1.82.
- `erpnext-dev.sh` now sources `lib/service.sh` after `lib/storage.sh`.
- `update-toolkit` now downloads `service.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/service.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and all `lib/*.sh` modules.
- `erpnext-dev version` prints v1.1.82.
- `scripts/validate-release.sh` passes locally.

## v1.1.81 - Extract lib/storage.sh for root storage detection and expansion

### Added

- Added `lib/storage.sh` with root storage detection, status reporting, expansion, and preflight offer helpers.

### Changed

- Updated the toolkit version to v1.1.81.
- Fixed a shellcheck issue in `lib/health.sh` where nginx health gating used `! is_public_vm_workflow` inside `[[ ]]`.
- `erpnext-dev.sh` now sources `lib/storage.sh` after `lib/health.sh`.
- `update-toolkit` now downloads `storage.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/storage.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and all `lib/*.sh` modules.
- `erpnext-dev version` prints v1.1.81.
- `scripts/validate-release.sh` passes locally.

## v1.1.80 - Extract lib/health.sh for health monitoring and go-live readiness

### Added

- Added `lib/health.sh` with health checks, timers, go-live validation, production checklist, release readiness, and final QA helpers.

### Changed

- Updated the toolkit version to v1.1.80.
- `erpnext-dev.sh` now sources `lib/health.sh` after `lib/apps.sh`.
- `update-toolkit` now downloads `health.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/health.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and all `lib/*.sh` modules.
- `erpnext-dev version` prints v1.1.80.
- `scripts/validate-release.sh` passes locally.

## v1.1.79 - Extract lib/apps.sh for curated app installation

### Added

- Added `lib/apps.sh` with curated Frappe app profiles, install wizards, compatibility checks, and app library menus.

### Changed

- Updated the toolkit version to v1.1.79.
- `erpnext-dev.sh` now sources `lib/apps.sh` after `lib/firewall.sh`.
- `update-toolkit` now downloads `apps.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/apps.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh` and all `lib/*.sh` modules.
- `erpnext-dev version` prints v1.1.79.
- `scripts/validate-release.sh` passes locally.

## v1.1.78 - Extract lib/ssl.sh and lib/firewall.sh for HTTPS and security

### Added

- Added `lib/ssl.sh` with production and local SSL/HTTPS planning, wizards, and certificate helpers.
- Added `lib/firewall.sh` with UFW, Fail2Ban, firewall rollback, and security-hardening helpers.

### Changed

- Updated the toolkit version to v1.1.78.
- `erpnext-dev.sh` now sources `lib/ssl.sh` and `lib/firewall.sh` after `lib/backup.sh`.
- `update-toolkit` now downloads `common.sh`, `support.sh`, `backup.sh`, `ssl.sh`, and `firewall.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for the new library modules.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh`, `lib/common.sh`, `lib/support.sh`, `lib/backup.sh`, `lib/ssl.sh`, and `lib/firewall.sh`.
- `erpnext-dev version` prints v1.1.78.
- `scripts/validate-release.sh` passes locally.

## v1.1.77 - Extract lib/backup.sh for backup and restore workflows

### Added

- Added `lib/backup.sh` with local backup, scheduled backup, retention, off-VM backup, restore, and rehearsal helpers.

### Changed

- Updated the toolkit version to v1.1.77.
- `erpnext-dev.sh` now sources `lib/backup.sh` after `lib/support.sh`.
- `update-toolkit` now downloads `common.sh`, `support.sh`, and `backup.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/backup.sh`.

### Validation scope

- `bash -n` passes for `erpnext-dev.sh`, `lib/common.sh`, `lib/support.sh`, and `lib/backup.sh`.
- `erpnext-dev version` prints v1.1.77.
- `scripts/validate-release.sh` passes locally.

## v1.1.76 - Extract lib/support.sh for diagnostics and support bundles

### Added

- Added `lib/support.sh` with doctor diagnostics, support-bundle creation, support-bundle audit, and command-audit helpers.

### Changed

- Updated the toolkit version to v1.1.76.
- `erpnext-dev.sh` now sources `lib/support.sh` after `lib/common.sh`.
- `update-toolkit` now downloads `lib/support.sh` into `/opt/erpnext-dev/lib/`.
- Expanded `SHA256SUMS`, `RELEASE-MANIFEST.txt`, and shellcheck targets for `lib/support.sh`.

### Validation scope

- `bash -n erpnext-dev.sh`, `bash -n lib/common.sh`, and `bash -n lib/support.sh` pass.
- `erpnext-dev version` prints v1.1.76.
- `scripts/validate-release.sh` passes locally.

## v1.1.75 - Begin modularization and add shellcheck to CI

### Added

- Added `lib/common.sh` with shared logging, locking, UI/menu helpers, prompts, and command helpers.
- Added `scripts/run-shellcheck.sh` and a shellcheck step in GitHub Actions CI.
- Expanded `SHA256SUMS` and `RELEASE-MANIFEST.txt` to include `lib/common.sh` and `scripts/run-shellcheck.sh`.

### Changed

- Updated the toolkit version to v1.1.75.
- `erpnext-dev.sh` now sources `lib/common.sh` from beside the active script path.
- `install-cli`, quickstart reuse, and `update-toolkit` now copy or download the toolkit `lib/` tree into `/opt/erpnext-dev/lib`.
- `scripts/validate-release.sh` now checks `lib/common.sh` syntax and runs shellcheck when available.

### Security and reliability impact

- Reduces monolith regression blast radius for shared logging, menu, and lock behavior.
- Adds static analysis for the first extracted module and release scripts before broader modularization.

### Validation scope

- `bash -n erpnext-dev.sh` and `bash -n lib/common.sh` pass.
- `erpnext-dev version` prints v1.1.75.
- `scripts/run-shellcheck.sh` passes when shellcheck is installed.
- `scripts/validate-release.sh` passes locally.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.74 - Release manifest, expanded checksums, and quality assessment

### Added

- Added `QUALITY-ASSESSMENT.md` with reliability, security, and ease-of-use evaluation plus an improvement plan.
- Added [`RELEASE-MANIFEST.txt`](RELEASE-MANIFEST.txt) listing expected files per release.
- Added `scripts/generate-release-checksums.sh` to regenerate `SHA256SUMS` for release artifacts.
- Expanded `scripts/validate-release.sh` with manifest checks, version consistency checks, `menu-self-test`, and a `production-ops-wizard` quit smoke test.

### Changed

- Updated the toolkit version to v1.1.74.
- Expanded `SHA256SUMS` to cover `erpnext-dev.sh`, `scripts/validate-release.sh`, and `RELEASE-MANIFEST.txt`.
- Improved `menu-self-test` so nested menu checks use `sudo` automatically when not already running as root.
- Updated README, SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, ROADMAP.md, and PRODUCTION-VALIDATION.md for the v1.1.74 release-engineering work.

### Security and reliability impact

- Release packages now have an explicit manifest and broader checksum coverage for validation tooling.
- CI/local validation now catches version drift between `SCRIPT_VERSION`, README bootstrap pins, CHANGELOG, and the manifest header.
- Menu navigation regressions are caught earlier through automated `menu-self-test` coverage.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.74.
- `sha256sum -c SHA256SUMS` passes for all listed artifacts.
- `scripts/validate-release.sh` passes locally, including manifest, version, menu, and support-bundle audit checks.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.73 - Support bundle audit and release validation expansion

### Added

- Added `support-bundle-audit` with aliases `audit-support-bundle` and `support-bundle-audit-test`.
- Added a Support and Diagnostics dashboard entry: `11) Audit latest support bundle`.
- Added support-bundle audit fixture coverage to `scripts/validate-release.sh`.

### Changed

- Updated the toolkit version to v1.1.73.
- Expanded release validation to verify that a clean support-bundle archive passes the audit command.
- Updated README, SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, ROADMAP.md, and PRODUCTION-VALIDATION.md for the new audit workflow.
- Updated `SHA256SUMS` for the v1.1.73 `erpnext-dev.sh` artifact.

### Security and reliability impact

- Operators now have a repeatable safety check for support bundles before external sharing.
- Release validation now covers support-bundle audit behavior in addition to syntax, checksum, help, toolkit verification, package hygiene, and basic secret-pattern checks.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.73.
- `sha256sum -c SHA256SUMS` passes.
- `scripts/validate-release.sh` passes locally, including the support-bundle audit fixture.
- `support-bundle-audit` reports `Audit result OK` for a clean archive.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.72 - Minimal GitHub Actions CI and release validation script

### Added

- Added `.github/workflows/ci.yml` for minimal release validation on pushes, pull requests, and version tags.
- Added `scripts/validate-release.sh` for local and CI release checks.
- Added checks for Bash syntax, version output, `SHA256SUMS`, required help commands, `verify-toolkit` active checksum matching, absence of `GITHUB-UPDATE-v*.md` files, and a basic secret-pattern scan.

### Changed

- Updated the toolkit version to v1.1.72.
- Updated the `verify-toolkit` verified update example to install through the stable `/opt/erpnext-dev` path and symlink `/usr/local/bin/erpnext-dev`.
- Updated README, SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, ROADMAP.md, and PRODUCTION-VALIDATION.md for the new release validation workflow.
- Updated `SHA256SUMS` for the v1.1.72 `erpnext-dev.sh` artifact.

### Reliability impact

- Releases now have a repeatable validation entrypoint that can run locally and in GitHub Actions.
- This starts closing the manual-validation gap identified in the project review while keeping the checks conservative and low-risk.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.72.
- `sha256sum -c SHA256SUMS` passes.
- `scripts/validate-release.sh` passes locally.
- GitHub Actions workflow file is included.
- Package contains no `GITHUB-UPDATE-v*.md` file.

# Changelog

## v1.1.71 - Verify installed toolkit integrity

### Added

- Added `verify-toolkit` command with aliases `toolkit-verify` and `verify-install`.
- Added installed SHA256 reporting for the active script, stable toolkit path, and CLI target when present.
- Added checksum-file discovery for `SHA256SUMS` via current directory, active script directory, stable toolkit directory, `/opt/erpnext-dev`, or `CHECKSUM_FILE=/path/SHA256SUMS`.
- Added `verify-toolkit` to the Production Operations > Support and Diagnostics menu as option 10.

### Changed

- Updated the toolkit version to v1.1.71.
- Updated README, SECURITY.md, RELIABILITY-PLAN.md, TESTING.md, ROADMAP.md, and PRODUCTION-VALIDATION.md for installed-file verification.
- Updated `SHA256SUMS` for the v1.1.71 `erpnext-dev.sh` artifact.

### Security impact

- Operators can now verify the installed or active toolkit file against the published checksum when a `SHA256SUMS` file is available.
- This improves post-install confidence after the tag-pinned checksum workflow introduced in v1.1.70.
- SHA256 verification still provides file integrity only; it does not prove maintainer identity.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.71.
- `sha256sum -c SHA256SUMS` passes.
- `erpnext-dev verify-toolkit` reports `Active match OK` when run beside the v1.1.71 `SHA256SUMS`.
- Production Operations > Support and Diagnostics exposes option 10 for toolkit verification.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.70 - SHA256 checksums and tag-pinned bootstrap docs

### Added

- Added `SHA256SUMS` release artifact for `erpnext-dev.sh`.
- Added verified, tag-pinned bootstrap examples to README install paths.
- Added testing instructions for checksum verification with `sha256sum -c SHA256SUMS`.

### Changed

- Updated the toolkit version to v1.1.70.
- Updated SECURITY.md to mark the checksum/tag-pinned bootstrap workflow as implemented for the script artifact.
- Updated RELIABILITY-PLAN.md and ROADMAP to move the next active milestone to `verify-toolkit`.
- Updated PRODUCTION-VALIDATION to record that v1.1.70 is a release-trust documentation/checksum patch with no production runtime behavior changes.

### Security impact

- New production bootstrap examples avoid downloading from the mutable `main` branch.
- Operators can verify the downloaded `erpnext-dev.sh` file before running it with `sudo`.
- This is SHA256 integrity verification, not maintainer identity verification. GPG signing remains a later optional milestone.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.70.
- `sha256sum -c SHA256SUMS` passes.
- Package includes `SHA256SUMS`, `SECURITY.md`, and `RELIABILITY-PLAN.md`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.69 - Security and reliability planning docs

### Added

- Added `SECURITY.md` with the toolkit threat model, bootstrap trust caveat, credential-handling expectations, support-bundle sharing guidance, and release-integrity roadmap.
- Added `RELIABILITY-PLAN.md` with the release automation, checksum, `verify-toolkit`, CI, package-audit, and modularization plan.

### Changed

- Updated the toolkit version to v1.1.69.
- Updated README documentation to point operators to the new security and reliability planning docs.
- Updated ROADMAP to pivot the next active milestones toward release trust and automation rather than more isolated VM features.
- Updated TESTING with package validation checks for the new documentation files.
- Updated PRODUCTION-VALIDATION to record that v1.1.69 is a planning/documentation patch with no production behavior changes.

### Rationale

- The production operations path is now strong and field-tested through v1.1.67/v1.1.68.
- The next major risk is release trust and automated regression prevention: tag-pinned installs, SHA256 checksums, `verify-toolkit`, and CI.
- Modularization remains important, but should happen after checksum and CI foundations are in place.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.69.
- Package includes `SECURITY.md` and `RELIABILITY-PLAN.md`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.68 - Final v1.1.67 production dashboard validation record

### Changed

- Updated the toolkit version to v1.1.68.
- Recorded the completed v1.1.67 production validation from `erp.flowmaya.com`.
- Documented that the top-level Production Operations dashboard footer now correctly shows only `q) Quit`.
- Documented that nested dashboard sections use breadcrumbs and keep `b) Back` plus `q) Quit`.
- Recorded successful Final QA option `1) Release readiness summary` on v1.1.67 with `Release state OK`.
- Recorded successful redacted support-bundle creation after v1.1.67 validation.
- Recorded successful breadcrumb validation for `ERPNext Production Operations > Health Monitoring`.
- Recorded successful breadcrumb validation for `ERPNext Production Operations > Support and Diagnostics` using the clean non-interactive routing test.
- Kept this as a documentation/validation patch only apart from the version bump; no install, backup, restore, SSL, security, monitoring, go-live, or dashboard behavior was changed.

### Validated production evidence

- Production site: `erp.flowmaya.com`.
- Installed toolkit during validation: v1.1.67.
- Final QA: `Release state OK, ready for production use`.
- Latest validation support bundle: `/tmp/erpnext-dev-support-bundle-20260709-071549.tar.gz`.
- Health Monitoring breadcrumb: `ERPNext Production Operations > Health Monitoring`.
- Support and Diagnostics breadcrumb: `ERPNext Production Operations > Support and Diagnostics`.
- Go-live record remained valid: snapshot `erp-flowmaya-v1.1.64-final-validated-20260709`, cloud firewall confirmed, Cloudflare proxied, Full strict confirmed, origin cert confirmed.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.67 - Production dashboard navigation polish

### Changed

- Updated the toolkit version to v1.1.67.
- Polished the Production Operations dashboard navigation after field validation on `erp.flowmaya.com`.
- Changed the top-level `production-ops-wizard` footer to show only `q) Quit`, because it is the direct operator entry point.
- Kept `b) Back` in nested dashboard submenus.
- Added breadcrumb-style submenu titles such as `ERPNext Production Operations > Health Monitoring` and `ERPNext Production Operations > Support and Diagnostics`.
- Preserved the hidden `b` handling at the top-level dashboard as a safe compatibility escape, but it is no longer advertised.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION to document the navigation polish and validation plan.

### Field evidence used

- v1.1.66 production dashboard opened on `erp.flowmaya.com` and showed all current-state rows as OK.
- Option `1) System health and readiness` routed to release readiness and returned to Production Operations.
- Option `6) Health monitoring` opened the Health Monitoring submenu; selecting `9` inside that submenu correctly produced `WARN: Invalid option`, confirming the confusion came from submenu context rather than broken routing.
- Returning to the main dashboard and selecting `9) Go-live validation`, `10) Support and diagnostics`, and `11) Final QA` routed correctly.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.67.
- `production-ops-wizard` top-level footer shows `q) Quit` without advertising `b) Back`.
- `production-ops-wizard -> 6` shows the breadcrumb title `ERPNext Production Operations > Health Monitoring`.
- `production-ops-wizard -> 10` shows the breadcrumb title `ERPNext Production Operations > Support and Diagnostics`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.66 - Production operations dashboard

### Changed

- Updated the toolkit version to v1.1.66.
- Rebuilt `production-ops-wizard` into a unified Production Operations dashboard.
- Added current-state summary rows for runtime, install state, HTTPS, UFW/security, local backups, off-VM backups, restore rehearsal, health monitoring, and go-live validation.
- Grouped mature operational commands into operator-focused sections: system readiness, services/recovery, local backups, off-VM backups, restore readiness, health monitoring, security/firewall, HTTPS/certificates, go-live validation, and support/diagnostics.
- Added dashboard aliases: `production-ops-dashboard`, `operations-dashboard`, and `ops-dashboard`.
- Added a support/diagnostics submenu helper to list the latest support bundle contents safely.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION to document the dashboard workflow.
- Kept existing direct commands stable; the dashboard orchestrates already validated commands instead of duplicating their logic.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.66.
- Help lists `production-ops-wizard` and `production-ops-dashboard`.
- `production-ops-wizard` opens, displays the current-state summary, and exits cleanly with `q`.
- `operations-dashboard` alias opens the same dashboard.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.65 - Final v1.1.64 production validation record

### Changed

- Updated the toolkit version to v1.1.65.
- Recorded the completed v1.1.64 production go-live validation from the real `erp.flowmaya.com` environment.
- Recorded the named cloud snapshot, provider firewall confirmation, Cloudflare proxied DNS, Full (strict), and Origin CA confirmation.
- Recorded successful production checklist integration and Final QA option `9) Go-live validation status`.
- Recorded successful enhanced support-bundle collection with production evidence files for backups, restore rehearsal, health monitoring, go-live validation, and production checklist state.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION to reflect the final validated v1.1.64 state and the next planned milestone: a unified production operations dashboard/menu.
- Kept this as a documentation/validation patch only; no install, backup, restore, firewall, SSL, monitoring, or go-live behavior was changed.

### Validated production evidence

- Production site: `erp.flowmaya.com`.
- Production VPS: `65.109.221.4`.
- Backup server: `65.109.220.250`.
- Snapshot: `erp-flowmaya-v1.1.64-final-validated-20260709`.
- Go-live record time: `2026-07-09T06:27:12+00:00`.
- Cloud firewall: confirmed.
- Cloudflare proxy/orange-cloud: confirmed.
- Cloudflare SSL/TLS Full (strict): confirmed.
- Cloudflare Origin CA on Nginx: confirmed.
- Restore rehearsal: recorded and login validated.
- Health monitoring: timer active and latest check OK during validation.
- Final evidence bundle: `/tmp/erpnext-dev-support-bundle-20260709-062951.tar.gz`.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.64 - Go-live validation record and evidence bundle polish

### Changed

- Updated the toolkit version to v1.1.64.
- Added `go-live-record` to record external go-live confirmations on the production VM.
- Added `go-live-status` to show the saved snapshot, cloud firewall, and Cloudflare validation record.
- Added `cloud-firewall-checklist` and `cloudflare-checklist` to guide provider-side checks that cannot be fully verified from inside the VM.
- Updated `production-checklist` and Final QA so go-live validation appears alongside backup, restore rehearsal, and health monitoring status.
- Added Final QA option `9) Go-live validation status`.
- Enhanced support bundles with redacted production evidence files: production checklist, backup status, backup verification, off-VM backup status, restore rehearsal status, health check status, and go-live status.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION with the go-live validation workflow.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.64.
- Help lists `go-live-record`, `go-live-status`, `cloud-firewall-checklist`, and `cloudflare-checklist`.
- Final QA includes `9) Go-live validation status`.
- `go-live-record` writes `/etc/erpnext-dev/go-live-validation.env` and `go-live-status` reads it.
- Support bundle collection includes the new redacted evidence files.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.63 - Health timer and production monitoring workflow

### Changed

- Updated the toolkit version to v1.1.63.
- Added `health-monitoring-wizard` as the guided entry point for production monitoring.
- Added `health-check-run-now` as an alias for `health-check`.
- Added `health-check-journal` to review the recent systemd journal output for the health-check service.
- Health checks now write a local status record to `/etc/erpnext-dev/health-check.state`.
- Improved `health-check-status` so it shows timer state, next run, last service result, and the last recorded health check summary.
- Improved `configure-health-check-timer` so the user can accept or adjust schedule and randomized delay from the prompt.
- Updated `production-checklist` and Final QA to surface health monitoring status when the timer is active.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION with the monitoring workflow.

### Validation scope

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` prints v1.1.63.
- Help lists `health-monitoring-wizard`, `health-check-run-now`, and `health-check-journal`.
- `health-monitoring-wizard` opens and supports safe `q` exit.
- Final QA includes health monitoring status as option 8.
- Package contains no `GITHUB-UPDATE-v*.md` file.

## v1.1.62 - Final production QA documentation record

### Changed

- Updated the toolkit version to v1.1.62.
- Documented the final v1.1.61 production QA evidence after restore rehearsal status tracking was recorded on the production VPS.
- Updated README with a dedicated validated production state section and menu anchor.
- Updated TESTING, ROADMAP, and PRODUCTION-VALIDATION so the repository reflects the completed backup, off-VM backup, restore rehearsal, restore-key cleanup, and final QA state.
- Kept this as a documentation/validation patch only; no backup, restore, SSH, firewall, or install behavior was changed.

### Validated

- Production VPS `erp.flowmaya.com` reports `Release state OK ready for production use` in Final QA.
- Restore rehearsal record is saved and recognized by `restore-rehearsal-status`, `production-checklist`, `backup-status`, `backup-verify`, and Final QA.
- Recorded restored backup set: `20260709_055928-erp_flowmaya_com`.
- Recorded restore target: `local-vm/local-kvm-restore-vm`; IP/address is evidence only and may change.
- Browser/login validation was recorded as complete.
- Support bundle creation completed: `/tmp/erpnext-dev-support-bundle-20260709-050725.tar.gz`.
- Remaining go-live decisions are operational: named cloud snapshot, provider firewall confirmation, Cloudflare SSL mode/proxy confirmation, and optional health timer.

## v1.1.61 - Restore rehearsal record/status tracking

### Changed

- Updated the toolkit version to v1.1.61.
- Added `restore-rehearsal-status` to show whether a successful disposable-VM restore rehearsal has been recorded on the production VM.
- Added `restore-rehearsal-record` to save restore rehearsal metadata in `/etc/erpnext-dev/restore-rehearsal.env`.
- Added `restore-rehearsal-report` to print restore evidence from the disposable restore VM and produce the production-side record command.
- Updated `backup-status`, `backup-verify`, `production-checklist`, and `release-readiness` so they no longer show stale restore warnings after a rehearsal is recorded.
- Treated restore VM IP/address as evidence only, because local restore VM IPs can change when using a different network.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION with the restore rehearsal record/status workflow.

### Validated

- Temporary local restore key was removed from the backup server after the manual restore rehearsal.
- Local restore VM authentication to the backup server failed after cleanup, as expected.
- Production ERPNext VPS still retained off-VM backup access after cleanup.
- `off-vm-backup-status` and `off-vm-backup-dry-run` passed on the production VPS after temporary-key cleanup.
- The remaining improvement is to record the completed rehearsal on the production VPS using `restore-rehearsal-record`.

## v1.1.60 - Guided restore rehearsal automation

### Changed

- Updated the toolkit version to v1.1.60.
- Added `restore-rehearsal-wizard` as a guided workflow for disposable local/cloud restore VMs.
- Added `restore-key-setup` to generate a temporary restore SSH key on the restore VM and print an exact backup-server command, avoiding placeholder copy/paste mistakes.
- Added `backup-server-add-restore-key`, `backup-server-list-restore-keys`, and `backup-server-remove-restore-key` to manage temporary restore keys on the backup server with marked `authorized_keys` blocks.
- Added `pull-off-vm-backup` to pull backups from the off-VM backup server into the restore VM backup folder with rsync and correct file ownership.
- Improved `restore-full` so it detects the latest complete backup set and lets the user press Enter instead of manually pasting database/public/private backup filenames.
- Improved restore credential handling so the local VM's `frappe_db_admin` password is read from the local toolkit credentials file when available.
- Added restore VM preflight warnings for Docker/Kubernetes/Calico-like service conflicts.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION with the successful local restore rehearsal and the new smoother command flow.

### Validated

- Local restore rehearsal succeeded on a disposable KVM VM using Ubuntu 26.04 LTS, site `erp.flowmaya.com`, and the off-VM backup copied from `65.109.220.250`.
- The restore VM pulled database, public files, private files, and site config backups from `/mnt/HC_Volume_106276869/erpnext-backups/erp.flowmaya.com/`.
- `backup-verify` and `restore-preflight` passed before restore.
- `restore-full` completed database and file restore, post-restore migrate, asset build, cache clear, service restart, and port readiness checks.
- The remaining restore validation item is browser/login confirmation and cleanup of the temporary restore key from the backup server.

## v1.1.59 - Off-VM backup validation and smoother onboarding

### Changed

- Updated the toolkit version to v1.1.59.
- Fixed `backup-status` so it no longer says off-VM copy is still required when off-VM backup is configured and the last rsync run succeeded.
- Updated `production-checklist` wording so completed off-VM backup validation is shown as verified, while restore rehearsal remains the remaining production decision.
- Improved `backup-server-setup` onboarding with stronger inline guidance before the prompts, including the ERPNext-side key-generation command the user should run first.
- Improved backup-server defaults so Enter can accept a detected Hetzner mounted volume path such as `/mnt/HC_Volume_.../erpnext-backups` instead of defaulting blindly to `/srv/erpnext-backups`.
- Allowed the backup-server wizard to infer the site/domain folder from the generated public-key comment when the site prompt is left blank.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION with the validated two-server off-VM backup flow.

### Validated

- Real two-server validation passed using ERPNext VPS `65.109.221.4` and separate backup VPS `65.109.220.250`.
- Backup target used dedicated user `erpbackup` and a 200 GB Hetzner volume mounted at `/mnt/HC_Volume_106276869`.
- Public key was installed with `from="65.109.221.4",no-agent-forwarding,no-X11-forwarding,no-port-forwarding,no-pty` restrictions.
- `off-vm-backup-dry-run` completed successfully.
- `run-off-vm-backup` completed successfully.
- `off-vm-backup-status` reported last run OK.
- `production-checklist` reported off-VM backup OK.
- Backup server contained database, public files, private files, and site config backup files after rsync.

## v1.1.58 - Guided off-VM backup server setup

### Changed

- Updated the toolkit version to v1.1.58.
- Added `backup-server-setup` / `prepare-backup-server` to prepare a separate Linux backup server from the same toolkit script.
- Added `generate-off-vm-backup-key` to create a dedicated rsync SSH key on the ERPNext VM and print only the public key for the backup server.
- Added `off-vm-backup-guided-setup` to guide the ERPNext VM side of off-VM backup configuration after the backup server is prepared.
- Updated the Off-VM Backup menu so users can run plan, guided setup, key generation, backup-server preparation, dry run, real run, status, and disable actions from one place.
- Documented the two-server backup flow in README, TESTING, ROADMAP, and PRODUCTION-VALIDATION.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.58.
- `erpnext-dev --help` lists `backup-server-setup`, `generate-off-vm-backup-key`, and `off-vm-backup-guided-setup`.
- `off-vm-backup-wizard` menu opens and shows the new off-VM backup actions without removing existing rsync commands.

## v1.1.57 - Cloudflare Origin CA validation record

### Changed

- Updated the toolkit version to v1.1.57.
- Documented the successful Cloudflare Origin CA / Cloudflare Full (strict) validation on the real Hetzner VPS path.
- Updated README, TESTING, ROADMAP, and PRODUCTION-VALIDATION to mark both supported production HTTPS paths as validated: direct Let's Encrypt and Cloudflare Origin CA behind orange-cloud/proxied DNS.
- Recorded that the v1.1.56 Cloudflare proxied DNS guided setup fix was validated with Cloudflare edge DNS, Origin CA certificate/key, Nginx, Cloudflare HTTPS `HTTP/2 200`, UFW, Fail2Ban, scheduled backups, and external 8000/9000 blocking.
- Kept remaining production-hardening work focused on off-VM backup, restore rehearsal, and optional health monitoring.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.57.
- Cloudflare Origin CA status reports active provider, certificate/key present, Nginx site enabled, and HTTPS `HTTP/2 200` through Cloudflare.
- External workstation tests confirmed `https://erp.flowmaya.com` returns through Cloudflare and direct backend ports `8000` and `9000` time out.
- Production checklist after completing interrupted steps shows UFW active, Fail2Ban sshd jail enabled, scheduled backups active, and only expected off-VM backup warnings.

## v1.1.56 - Cloudflare proxied DNS guided setup fix

### Changed

- Updated the toolkit version to v1.1.56.
- Fixed `public-vm-guided-setup` Step 3 so Cloudflare proxied/orange-cloud DNS no longer hard-stops the guided flow when the user intentionally chooses the Cloudflare Origin CA path.
- Added a guided DNS mismatch choice: stop for DNS-only/gray-cloud Let's Encrypt, continue with Cloudflare proxied / Origin CA, or view SSL mode guidance.
- When Cloudflare Origin CA is active or selected, public DNS returning Cloudflare edge IPs is treated as expected, while the user is reminded to confirm the hidden Cloudflare origin A-record points to the VM IP.
- Updated README, TESTING, PRODUCTION-VALIDATION, and ROADMAP with the Cloudflare proxied DNS validation finding.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.56.
- Cloudflare Origin CA manual wizard installs the origin certificate/key, writes Nginx config, and responds through the Cloudflare HTTPS route.

## v1.1.55 - Production validation record and polish fixes

### Changed

- Updated the toolkit version to v1.1.55.
- Documented the successful fresh Hetzner VPS production validation result in README, TESTING, PRODUCTION-VALIDATION, and ROADMAP.
- Clarified that `final-qa` is interactive and should be run separately from follow-up commands unless the user intentionally wants queued shell commands to run after quitting the menu.
- Improved production ready/access wording so production users are not presented with `:8000` browser URLs as normal public access after install.
- Fixed VM firewall status parsing so explicit UFW `DENY` rules for backend ports are reported as blocked instead of being mistaken for allow rules.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.55.
- Fresh VPS guided production path was validated on Hetzner with Ubuntu 26.04 LTS, real DNS, Let’s Encrypt HTTPS, UFW, Fail2Ban, scheduled local backups, support bundle, and external 8000/9000 blocking.
- Remaining production hardening items are off-VM backup configuration and disposable-VM restore rehearsal.

## v1.1.54 - Guided production SSL provider choice

### Changed

- Updated the toolkit version to v1.1.54.
- Improved `public-vm-guided-setup` Step 7 so Let's Encrypt remains the recommended/default HTTPS path when DNS points directly to the VPS, but the user can choose another SSL provider instead of being forced straight into Let's Encrypt.
- Added an explicit guided choice for the advanced SSL provider wizard, including Cloudflare Origin CA for Cloudflare-proxied Full (strict) deployments.
- Added a post-choice verification gate so guided production setup does not continue unless production HTTPS is verified.
- Updated README, TESTING, and PRODUCTION-VALIDATION notes to document the default Let's Encrypt path and the optional Cloudflare Origin CA path.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.54.
- `public-vm-guided-setup` still remains the README production bootstrap path.
- `production-ssl-wizard` remains available for manual provider selection.

## v1.1.53 - VPS rebuild SSH troubleshooting documentation

### Changed

- Updated the toolkit version to v1.1.53.
- Added an easy-to-find README troubleshooting section for `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` after intentional fresh VPS rebuilds.
- Added the same SSH known-hosts recovery guidance to `PRODUCTION-VALIDATION.md` and `TESTING.md` so repeated disposable VPS testing is easier to recover from safely.
- Kept the guidance security-focused: remove the old local `known_hosts` entry only after confirming the VPS was intentionally rebuilt or replaced.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.53.
- Documentation search now finds the SSH host key troubleshooting section from README, TESTING, and PRODUCTION-VALIDATION.

## v1.1.52 - Production guided setup workflow

### Changed

- Updated the toolkit version to v1.1.52.
- Added `public-vm-guided-setup` as the true guided production VPS setup command.
- Kept `public-vm-quickstart` as the manual Public VM menu for individual production actions.
- Routed the README production bootstrap command to `public-vm-guided-setup`.
- Routed the First Run wizard's Public VM choice to the guided production setup path.
- Added guided production gates for domain, DNS readiness, cloud firewall confirmation, clean provider snapshot confirmation, install, backup checkpoint, HTTPS, production UFW profile, Fail2Ban, scheduled backups, off-VM backup review, optional apps, Final QA, support bundle, and post-validation snapshot reminder.
- Updated production validation docs to allow Ubuntu 24.04 LTS or Ubuntu 26.04 LTS.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.52.
- `public-vm-guided-setup` is registered in command validation, help output, and command dispatch.
- README production VPS command uses `public-vm-guided-setup`.
- `public-vm-quickstart` remains available as the manual production menu.

## v1.1.51 - Production VPS validation handoff documentation

### Changed

- Updated the toolkit version to v1.1.51 for the documentation handoff release.
- Updated the release notes guide to mark the local VM stage as validated and to identify real VPS + real subdomain validation as the next stage.
- Updated README with a production-validation section, VPS requirements, DNS requirements, and baseline cloud firewall rules.
- Updated TESTING with the production VPS validation plan, required environment, ordered test sequence, and readiness ratings.
- Updated ROADMAP to close the local VM validation stage and make production VPS validation the active next milestone.
- Added `PRODUCTION-VALIDATION.md` as the dedicated handoff checklist for the next test session.

### Readiness after this release

- Local VM/developer workflow: 9.5/10, passed.
- Backup/restore foundation: 9.0/10, passed locally; production restore rehearsal still required.
- Public VPS production-candidate workflow: 6.5/10, implemented but not yet validated on real VPS + domain.
- Off-VM backup and production monitoring: 5.5/10, available but still require real-target validation.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.51.
- Documentation now clearly separates completed local validation from upcoming production VPS validation.

## v1.1.50 - Local SSL firewall guidance polish

- Fixed `verify-local-ssl` follow-up guidance so it no longer recommends applying the Local VM security profile when UFW is already active.
- Added a safe default for the internal `SUDO` command prefix so status helpers used outside `require_sudo` do not falsely fail under `set -u`.
- `verify-local-ssl` now requires sudo explicitly, matching the protected nginx/UFW checks it performs.

## v1.1.49

### Fixed

- Fixed the Final QA release notes draft so it uses the current script version dynamically instead of the stale `v1.1.5` label.
- Revised the release notes draft to separate what was actually validated in the local VM stage from production paths that still require dedicated testing.
- Added `scheduled-backup-status` as a convenience alias for `backup-schedule-status`.
- Improved scheduled-backup disable output so an unconfigured/missing timer is reported as informational instead of looking like a successful disable.
- Improved local HTTPS next-step guidance when UFW is active but the exact Local VM firewall profile rules are not fully confirmed.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.49.
- `erpnext-dev release-notes-guide` now prints `v1.1.49 Release Notes Draft` and accurate local-stage validation scope.

## v1.1.48

### Improved

- Reduced post-restore maintenance console noise by capturing detailed `bench migrate`, `bench build`, and `bench clear-cache` output into per-step log files while keeping concise restore progress on screen.
- Updated the ERPNext Ready screen to prefer HTTPS Desk/Login/Website URLs when local HTTPS is configured and port 443 is listening, while keeping direct Bench HTTP URLs as troubleshooting fallbacks.
- Updated local HTTPS verification next steps so the Local VM security profile is shown as already active when UFW rules are present, instead of always recommending that users apply it again.
- Added the HTTPS host-side curl check to the Local Firewall Access Check when local HTTPS is configured.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.48.
- Restore maintenance commands now use quiet log capture helpers and print the output log path.

## v1.1.47

### Fixed

- Improved restore prompts so they ask for `database admin user` and `Database admin password` instead of MySQL/root wording.
- Added a restore credential reminder before destructive restore actions, pointing users to `erpnext-dev credentials-show` and the generated credentials file.
- Changed restore flows to pass the toolkit database admin credentials to Bench restore instead of leaving Bench to prompt for a root user.
- Fixed post-restore sequencing: the toolkit now starts/waits for ERPNext services before running migrate, build, and cache cleanup.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.47.
- Restore flow text no longer contains the confusing `Enter mysql super user` or `MySQL root password` prompt strings in the toolkit code.

## v1.1.46

### Fixed

- Removed the stale hard-coded version from the README title so the README does not fall behind future script releases.
- Added a README version-check command using `erpnext-dev version` as the source of truth.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `erpnext-dev version` reports v1.1.46.

## v1.1.45

### Fixed

- Replaced the fragile multiline `run_as_frappe` app comparison snippets in `app-status` and Advanced Tools -> Installed apps with a safer tempfile + `comm` comparison flow.
- Fixed the remaining temp-script `unexpected end of file from if command` error in the downloaded-but-not-installed and downloaded-but-not-registered sections.
- Kept installed app listing and app wizard branch snapshot behavior from v1.1.44.

### Validated

- `bash -n erpnext-dev.sh` passes.
- `app-status` comparison logic no longer embeds multiline remote `if` blocks.

## v1.1.44

### Fixed

- Fixed a `run_as_frappe` temp-script generation bug that could corrupt commands containing backslash escapes such as `printf '%s\n'`. This caused `app-status` compare sections to fail with `syntax error: unexpected end of file from if command`.
- `app-status` should now correctly print `none` for downloaded-but-not-installed and downloaded-but-not-registered app comparisons when everything is clean.

### Improved

- Changed the app wizard preflight summary from `Compatibility snapshot` to `Install / branch snapshot`.
- Installed apps now show `OK` in the snapshot even when their branch is `main`, `develop`, or repository default. The branch warning is kept as a repeatability note instead of making working installed apps look broken.
- Added explanatory text that moving-branch notes are repeatability warnings, not installation failures.

## v1.1.43

### Fixed

- Fixed `app-status` so it shows installed site apps directly instead of requiring Advanced Tools -> Installed apps.
- Fixed curated app profile iteration under the toolkit newline/tab `IFS` setting. This affects app status, compatibility snapshots, and optional-app diagnostics.
- Updated the App Installation Wizard option label to `Installed apps / status`.

### Improved

- `app-status` now shows installed site apps, downloaded app folders, downloaded-but-not-installed apps, and downloaded-but-not-registered apps in one place.
- `app-status` now prints the recommended verification commands to run after each app install.
- Kept Advanced Tools -> Installed apps as a troubleshooting shortcut.

## v1.1.42

### Improved

- Updated standalone `local-ssl-wizard` and `local-ssl-menu` navigation so `b`/`B` opens the main menu instead of silently exiting when launched directly from the CLI.
- Preserved normal nested behavior: when the Local SSL Wizard is opened from the Local VM HTTPS / SSL menu, `b`/`B` still returns to that SSL menu.
- Added `9) Local security profile` to the Local SSL Wizard so users can continue to safe local hardening after HTTPS succeeds.
- Added `17) Local Security Profile` to the Local VM HTTPS / SSL menu.
- After successful local HTTPS verification, the toolkit now prints the recommended next steps: verify access, apply the Local VM firewall profile, then install optional apps.
- Clarified that local/dev VMs should use the Local VM security profile, not the Production firewall profile.

## v1.1.41

### Fixed

- Fixed the Local SSL Wizard option `2) Trusted mkcert setup` feeling like it did nothing.
- Option 2 now opens a real guided mkcert setup screen instead of only dumping the guide and immediately redrawing the menu.
- The guided mkcert setup explains HOST vs VM responsibilities, prints the exact host commands, checks for `/tmp/<site>.crt` and `/tmp/<site>.key`, and can install/configure/verify HTTPS when the files are already copied into the VM.
- Added a pause after Local SSL Wizard actions so users can read the result before the menu redraws.
- Added direct command aliases: `trusted-mkcert-setup` and `mkcert-setup`.

## v1.1.40

### Improved

- Added `local-host-checkpoint` as a required local-dev workflow checkpoint before local HTTPS.
- Added aliases `host-dns-checkpoint` and `host-mapping-checkpoint` for the same flow.
- The checkpoint prints the current detected VM IP, the selected local domain, safe host-side `/etc/hosts` commands, and host-side test commands.
- The local guided setup now prints the host mapping checkpoint automatically after install verification and backup checkpoint, before opening the main menu.
- Updated the local setup order so host DNS mapping and host HTTP validation happen before local HTTPS, local security hardening, or optional app installs.
- Updated local quickstart and final install summaries to make the host mapping step visible and safe to repeat after VM recreation or DHCP IP changes.

## v1.1.39

### Improved

- Updated the local install finish flow to print the direct next HTTPS command: `sudo erpnext-dev local-ssl-wizard`.
- Kept the broader local SSL menu visible as a secondary option: `sudo erpnext-dev local-ssl-menu`.
- Added a clearer local fixed-IP follow-up command: `sudo erpnext-dev local-fixed-ip-guide`.
- Added aliases for the same stable-IP guidance: `fixed-ip-guide` and `kvm-fixed-ip-guide`.
- Updated README local install guidance so users see the post-install command order: verify HTTP, map host DNS, run local SSL, and optionally reserve a stable VM IP.

## v1.1.38

### Improved

- Reworked the README Start Here section so the first visible items are copy/paste commands.
- Added a general guided setup command using `start-here` so users can choose local or production from the wizard.
- Kept separate first-run commands for local VM installs and production VPS/cloud installs.
- Moved site-name guidance after each command: local defaults to `erp.test`; production uses a real domain such as `erp.example.com`.
- Kept bootstrap path details lower in the README instead of showing them before the install commands.


## v1.1.37 - README start-here cleanup

- Reworked the README **Start here** section so users see the practical install commands first.
- Moved the temporary bootstrap path explanation below the main quickstart commands so `/tmp` details do not distract first-time users.
- Clarified local VM domain behavior: the local wizard asks for a domain and defaults to `erp.test` when the user presses Enter.
- Updated local host DNS instructions to use dynamic toolkit commands (`local-domain-status`, `host-dns-guide`, and `local-access-doctor`) instead of sample IP addresses.
- Kept the stable toolkit path and CLI explanation, but moved it into a short follow-up note after the primary commands.

## v1.1.36 - Central menu navigation hardening

- Added a central `menu_read_choice` handler for all interactive menu prompts so `q`, `Q`, `b`, and `B` are handled consistently across menus and submenus.
- The shared handler trims accidental whitespace and accepts `quit`, `exit`, and `back` as friendly aliases.
- End-of-file / empty piped input is treated as quit so menus do not hang or leak back into the shell during scripted validation.
- Added `menu-self-test` / `menu-navigation-self-test` to safely smoke-test top-level menus, submenus, and nested menu paths for `q/Q` and `b/B` behavior.
- Updated testing coverage so menu navigation regressions are caught before release.

## v1.1.35 - Dynamic local host DNS and access doctor

- Added dynamic VM IP detection for local host mapping. The toolkit no longer assumes `192.168.122.x`; it detects the active VM IP from routing/interface data and supports KVM NAT, bridged LAN, VirtualBox/UTM-style NAT, and other private networks.
- Added `local-domain-status`, `local-access-doctor`, `host-dns-guide`, and `print-hosts-command` aliases for local VM DNS/access troubleshooting.
- Updated `verify-access`, `access`, `local-ssl-menu`, and local domain output to clearly separate VM service checks from host `/etc/hosts` mapping.
- Added safer host-side `/etc/hosts` commands that back up the file, remove old entries for the local domain, and append the current detected VM IP.
- Changed the Access command to open the access/networking submenu so local DNS, access doctor, fixed-IP guidance, and SSL checks are discoverable from one place.
- Documented that `curl: (6) Could not resolve host: erp.test` is a host DNS mapping issue, not an ERPNext/Frappe error.

## v1.1.34 - Environment-aware security profiles and setup lifecycle

- Replaced the generic security hardening flow with environment-aware security profiles so local `.test` VMs do not accidentally lose direct Bench access on ports `8000` and `9000`.
- Added `security-mode-status`, `local-firewall-profile`, `production-firewall-profile`, `repair-local-access`, and `firewall-rollback-snapshots`.
- Added UFW rollback snapshots before toolkit firewall changes under `/var/backups/erpnext-dev/firewall`.
- Changed `configure-vm-firewall` to choose the correct Local VM or Production firewall profile based on saved deployment config.
- Added a Local VM repair path that restores SSH, HTTP, HTTPS, and private-network Bench access after over-hardening.
- Added production hardening guards so production firewall rules require a real production domain and warn if HTTPS is not confirmed.
- Added a setup lifecycle plan covering requirements, domain, install, backup checkpoint, SSL, security profile, optional apps, post-app backups, and final QA.
- Added a core-install backup checkpoint prompt after guided setup verification.
- Added post-app backup checkpoints after every optional app install, controlled by `APP_BACKUP_AFTER_INSTALL`.
- Updated the public VM quickstart menu to follow the safer order: requirements, domain, install, backup, HTTPS, security profile, apps, final QA.

## v1.1.33 - Local domain selection and rename workflow

- Added an interactive local VM domain prompt to `local-dev-quickstart`; pressing Enter keeps the default `erp.test`.
- Added `change-local-domain`, `local-domain-wizard`, `rename-local-site`, and `change-site-domain` command aliases.
- Added a menu entry under **Local VM HTTPS / SSL** to change the local domain after installation.
- Added an Advanced menu entry for the same workflow so domain changes are discoverable from both SSL and maintenance paths.
- The change workflow detects the current Frappe site, creates a safety backup when a site folder exists, runs `bench rename-site`, updates Bench default-site config, updates the toolkit config, disables the old local Nginx SSL site, and prints the host `/etc/hosts` replacement commands.
- Updated help and documentation so the default/fresh-install domain choice and after-install rename path are explicit.

## v1.1.32 - Comprehensive HTTPS menu and handler audit

- Fixed broken Local SSL menu actions by adding the missing central handlers for `local-ssl-wizard`, `ssl-status`, `install-local-ssl-cert`, `verify-local-ssl`, browser trust guidance, rollback guidance, and rollback verification.
- Added shared local SSL helpers so every local HTTPS status/check path uses the same certificate, key, Nginx site, and self-signed detection logic.
- Added a first-level **Production HTTPS / SSL** submenu instead of exposing only a production status check from the main menu.
- Added `production-ssl-menu`, `production-https`, and `production-https-menu` command aliases.
- Updated the main menu labels so local VM SSL and production SSL are clearly separated.
- Audited menu entries against real function handlers to prevent command-not-found failures from menu selections.

## v1.1.31 - Menu UX and local SSL visibility

- Promoted **Local VM HTTPS / SSL** to the main menu so local SSL is visible immediately after installation, alongside Optional Apps.
- Added a dedicated `local-ssl-menu` command and submenu for local SSL wizard, status, guide, mkcert guidance, browser trust checks, certificate install/replace, verification, disable, and rollback verification.
- Changed the long Advanced menu to render with the existing two-column menu helper so the full option list fits normal terminal windows.
- Updated the post-install prompt to show the local SSL menu, optional app wizard, and next-step command before opening the main menu.
- Updated help and documentation so local VM HTTPS is clearly separated from production HTTPS.

## v1.1.30 - Logging and lock permission hardening

- Fixed root/non-root log collisions by replacing timestamp-only `/tmp` log names with unique `mktemp` log files.
- Changed default root logs to `/var/log/erpnext-dev` and default normal-user logs to the user's state directory, with a safe `/tmp/erpnext-dev-<uid>-logs` fallback.
- Kept explicit `LOG_DIR` and `LOG_FILE` overrides supported while preventing accidental same-second collisions when `LOG_FILE` is not provided.
- Reworked toolkit locking to use a shared lock directory at `/tmp/erpnext-dev-locks` instead of the old root-owned `/tmp/erpnext-dev.lock` path.
- Changed generated README/help bootstrap commands to use `mktemp /tmp/erpnext-dev.XXXXXX.sh` instead of a fixed `/tmp/erpnext-dev.sh` path.
- Changed `update-toolkit` and scheduled-backup unit generation to use unique temporary files instead of fixed `/tmp` filenames.
- Added validation coverage for running `sudo erpnext-dev install-cli` followed immediately by non-root `erpnext-dev version` and `erpnext-dev where-installed`.

## v1.1.29 - Rename toolkit and add erpnext-dev CLI

- Standardized the canonical script as `erpnext-dev.sh` and promoted the package to a full toolkit identity.
- Added the stable root-owned toolkit path `/opt/erpnext-dev/erpnext-dev.sh`.
- Added the short user-facing command `/usr/local/bin/erpnext-dev`.
- Added `where-installed`, `install-cli`, `repair-cli`, and `update-toolkit`.
- Updated README, TESTING, and ROADMAP command examples to use `sudo erpnext-dev` after first run.
- Updated the default config directory to `/etc/erpnext-dev`.
- Updated the app name to `ERPNext Developer Toolkit` because the project now covers install, operations, backups, credentials, SSL, security, diagnostics, and optional apps.

## v1.1.27 - README command path clarification

- Clarified why first-run README commands download the installer to `/tmp/erpnext-dev.sh`.
- Clarified that `/tmp/erpnext-dev.sh` is only a temporary bootstrap copy and should not be used as the long-term command path.
- Clarified that `/opt/erpnext-dev/erpnext-dev.sh` is the stable root-owned script path after the first sudo run or after the existing-VM update command.
- Added guidance for users who copy follow-up commands before `/opt/erpnext-dev/erpnext-dev.sh` exists.
- Updated TESTING with README command-path validation checks.

## v1.1.26 - Credentials workflow hardening

- Added `credentials-show` with explicit confirmation before displaying generated passwords.
- Added `credentials-file-status` to report owner, group, mode, size, modified time, and recommended security state.
- Added `credentials-secure` to set the generated credentials file to `root:root` with mode `600`.
- Added `credentials-delete` for production handoff after credentials are saved in a password manager.
- Added `reset-admin-password` so users can safely reset the ERPNext Administrator password without manually entering the Bench directory or relying on the current user's `bench` PATH.
- Updated new installs to create the credentials file with root-only ownership and permissions.
- Updated README and TESTING with the safer credentials workflow.

## v1.1.25 - Education access guidance

- Added `access-info` / `desk-url` command to print the correct Desk, login, website root, and portal URLs.
- Added `education-access-info` / `portal-access-info` command for Education installs.
- Updated `verify-access` to print `/app` and `/login` paths, not only the website root.
- Added a post-install Education note explaining that the website root may open the Education portal and that ERPNext Desk remains available at `/app`.
- Updated README and TESTING notes so Education users are not confused by the portal redirect.


## v1.1.24 - Optional app service-readiness fix

- Fixed optional app installation post-maintenance for local VM installs by ensuring Bench services are running before commands that require Redis, including `bench migrate` and `bench clear-cache`.
- Added a service-readiness helper that starts or restarts `erpnext-dev.service` and waits for the required development ports before app install maintenance continues.
- Updated direct maintenance commands so `migrate` and `clear-cache` now check service readiness instead of failing with `Service redis_cache is not running`.
- Clarified the recovery path: users should use installer service commands or run Bench as the `frappe` user, not as the normal login user.

## v1.1.23 - README command and workflow refresh

- Refreshed README.md to document the current v1.1.22+ installer workflow.
- Added full one-command paths for install preflight, local VM quickstart, public VM quickstart, guided menu, existing VM script update, and optional app wizard.
- Updated post-install examples to use the stable `/opt/erpnext-dev/erpnext-dev.sh` path with `sudo`.
- Added blocking preflight behavior, root storage expansion flow, public SSL commands, local SSL commands, pre-app backup/checkpoint workflow, and current optional app list including Education and Learning / LMS.
- Clarified that the installer creates ERPNext backups from inside the VM, while true VM snapshots/checkpoints must be created from the host/hypervisor.

## v1.1.22 - Add Education app profile

- Added Frappe Education to the curated optional app library.
- Added `install-education` command.
- Added `EDUCATION_BRANCH=version-16` default branch support.
- Updated app library and app installation wizard menus to include Education separately from Learning / LMS.
- Updated optional app compatibility handling, status output, app registry order, help output, and command audit references.

## v1.1.21 - Fit-aware two-column app menus

- Fixed the App Installation Library and App Installation Wizard layout so two-column rendering is based on actual label length instead of a fixed 76-column threshold.
- Kept concise app menu labels from v1.1.19/v1.1.20 while making the layout work better in smaller terminal windows.
- Added `MENU_TERMINAL_COLS` testing support for menu layout validation and preserved one-column fallback when labels truly cannot fit.
- Kept Advanced App Tools behind the safer advanced submenu introduced in v1.1.20.

## v1.1.20 - Safer advanced app tools

- Moved Custom Git app installation out of the main curated App Installation Library list and into a dedicated Advanced App Tools submenu.
- Changed the main app menu item from Custom Git app to Advanced tools so normal users are guided toward curated apps first.
- Added an Advanced App Tools submenu for Custom Git app, app registry repair, rollback guidance, and installed-app review.
- Added stronger warnings and a typed `I UNDERSTAND` confirmation before custom Git app installation can continue.
- Added `advanced-app-tools`, `app-advanced-tools`, and `custom-app-tools` command aliases.
- Kept `install-custom-app` available as an advanced direct command, but made it safer with the same warning and confirmation flow.

## v1.1.19 - Concise app installation menus

- Renamed the App Library heading to App Installation Library so the menu context carries the install meaning.
- Shortened App Library and App Installation Wizard labels by removing repeated “Install”, “Frappe”, and “Show” wording.
- Kept direct install actions and command names unchanged; only the terminal menu labels were simplified.
- Improved `print_two_column_menu` so column width adapts to the current terminal width and falls back to one column on very narrow terminals.
- Shortened long menu labels such as Raven Team Chat and Custom app from Git URL to reduce wrapping in small terminal windows.

## v1.1.18 - Expanded app library and compact two-column menus

- Added curated optional app profiles for Frappe Builder, Frappe Learning / LMS, Frappe Wiki, Frappe Print Designer, Frappe Drive, and Raven Team Chat.
- Added direct install commands: `install-builder`, `install-lms`, `install-wiki`, `install-print-designer`, `install-drive`, and `install-raven`.
- Expanded optional app status, doctor output, app compatibility matrix, app registry normalization, and branch override help to include the new profiles.
- Changed the App Library and Optional App Install Wizard to use a compact two-column terminal layout for smaller terminal windows.
- Kept the existing safe app-install workflow: one app at a time, backup checkpoint prompt, compatibility warning, app install, migrate/build/clear-cache, and post-install validation.

## v1.1.17 - Access verification helper correction

- Fixed `verify-access` by adding the missing `curl_head_status` helper.
- Kept HTTP/HTTPS verification safe: failed HTTP checks now show WARN/INFO instead of shell errors.
- Confirmed `version` / `--version` support remains available from v1.1.16.
- Kept README structure unchanged except for the version title.

## v1.1.16 - App Library menu and version command correction

- Fixed App Library labels so Payments and Webshop appear as direct menu items.
- Aligned App Library menu numbering with the underlying app install actions.
- Added `version` / `--version` command support so version checks do not fail with “Unknown argument”.
- Kept README structure unchanged except for the version title.


## v1.1.15

- Added Frappe Payments to the optional app library, install wizard, status checks, compatibility matrix, command parser, and direct `install-payments` command.
- Added Frappe Webshop / E-Commerce to the optional app library, install wizard, status checks, compatibility matrix, command parser, and direct `install-webshop` / `install-ecommerce` commands.
- Added `PAYMENTS_BRANCH` and `WEBSHOP_BRANCH` branch override documentation for safer repeatable app testing.
- Updated optional app compatibility notes so Payments uses the repository default branch by default and Webshop defaults to `develop` for current v16 testing.
- Cleaned up the App Library menu by removing a duplicate status entry and fixed a duplicate app dependency-preparation call.

## v1.1.14

- Fixed preflight follow-up commands so they use the real active installer path instead of `./erpnext-dev.sh` when the script was downloaded to `/tmp`.
- Updated printed follow-up commands to include `sudo` where installer actions require elevated permissions.
- Added automatic self-copy during install/preflight flows so reusable commands prefer `/opt/erpnext-dev/erpnext-dev.sh` after first sudo execution.
- Changed the install sequence so root-storage expansion is offered before the blocking resource preflight, allowing expanded VM disks to be used before disk checks block the install.
- Improved `install-preflight` so an interactive user can continue directly into `local-dev-quickstart` instead of copying a second command.
- Added a successful guided-install completion message and an optional prompt to open the main installer menu immediately after setup.

## v1.1.13

- Added a blocking install environment preflight for safer fresh VM installs.
- Added CPU checks before ERPNext installation; VMs below the safe minimum are now blocked.
- Changed low RAM and low root disk from warning-only to blocking failures when below safe minimums.
- Added `/tmp` free-space validation so package/build temp-space problems are caught before installation.
- Added `install-preflight` and `environment-preflight` commands for standalone validation before running a quickstart.
- Added a red `INSTALL BLOCKED` summary explaining exactly why installation cannot proceed and what VM resources to increase.
- Added an explicit expert-only override: `ERPNEXT_ALLOW_UNSAFE_INSTALL=true`.

## v1.1.12

- Reworked `ROADMAP.md` into a clearer production-maturity plan.
- Added a future Docker-based ERPNext/Frappe installation track as a separate later approach, not a replacement for the current VM installer.
- Prioritized VM management, monitoring, backup, restore, update, and security hardening work before expanding into Docker deployment.
- Organized upcoming work into staged phases: diagnostics, backup/restore maturity, monitoring/security, production lifecycle, fleet management, and later Docker support.

## v1.1.10

- Added a README hero/banner image for a cleaner project landing section.
- Added a dedicated `Start here` section for users who want to install quickly without reading the full README.
- Added one-command start paths for the guided menu, local VM quickstart, public VPS/cloud VM quickstart, existing-install operations, and optional apps.
- Added Debian-family system update/bootstrap commands using `apt-get update`, `apt-get upgrade`, `curl`, and `ca-certificates`.
- Added a README menu/table of contents so users can jump directly to the needed section.
- Updated quickstart documentation to make the stable `/opt/erpnext-dev/erpnext-dev.sh` follow-up path clearer.

## v1.1.9

- Standardized interactive menu navigation controls.
- Action choices remain numeric, while submenu navigation now uses `b/B` for Back and `q/Q` for Quit.
- Added a separated navigation footer under menu items:

  ```text
  -----------------------------
  b) Back                        q) Quit
  ```

- Main menu now shows `q) Quit` only, because there is no parent menu.
- Removed numbered Back/Exit items from interactive menus to keep menu navigation stable as features are added.
- Updated README and TESTING documentation for the new menu pattern.

## v1.1.8

- Added clear credential-access documentation to `README.md`.
- Added `credentials-info`, `credentials`, and `login-info` commands.
- `credentials-info` shows the ERPNext username, credentials-file path, and safe password-reset commands without printing the password.
- Post-install summary now points users to `credentials-info` and the stable `/opt/erpnext-dev/erpnext-dev.sh` follow-up path.
- Updated help output, command audit, and testing documentation for credential lookup.

## v1.1.7

- Improved local SSL and mkcert guide wording.
- Follow-up commands now use `/opt/erpnext-dev/erpnext-dev.sh` in local SSL instructions so users are not blocked by scripts downloaded to `/tmp`.
- Replaced distro-specific HOST wording with generic Linux HOST wording.
- Improved mkcert Option 2 checklist with clearer HOST vs VM steps.
- Replaced placeholder `USER@VM_IP` examples with a suggested VM SSH user when available.

## v1.1.6

- Reorganized `README.md` into a usage-focused guide instead of a version-history document.
- Moved release/history information fully into `CHANGELOG.md`.
- Added clear local VM testing instructions, including `local-dev-quickstart`, `erp.test`, host-file mapping, and validation commands.
- Kept production quickstart, backup, SSL, security, operations, and optional-app instructions in the README.
- Clarified documentation file responsibilities for README, CHANGELOG, TESTING, ROADMAP, and `docs/assets/`.

## v1.1.5

- Added production health check workflow.
- Added `health-check`, `configure-health-check-timer`, `health-check-status`, `disable-health-check-timer`, and `service-recovery-plan`.
- Added hourly systemd timer option for read-only local health checks.
- Health check summarizes install/runtime, ERPNext service, Nginx, MariaDB, Redis, HTTPS, disk usage, latest backup age/completeness, UFW, Fail2Ban, scheduled backup timer, and off-VM backup state.
- Updated production operations wizard, command audit, help output, and production checklist to include health monitoring.

## v1.1.4

- Hotfix: fixed off-VM rsync SSH command construction when Bash IFS does not use spaces.
- `off-vm-backup-dry-run` and `run-off-vm-backup` now pass a valid `ssh -o ...` command to `rsync -e`.
- Reject documentation placeholder targets such as `backup@example-backup-server:/path/` during target validation.
- Improved guidance to configure a real backup server before testing off-VM backup.

## v1.1.2

- Added backup retention planning for scheduled/local backups.
- Added `backup-retention-plan`, `backup-retention-status`, `cleanup-old-backups-dry-run`, and `cleanup-old-backups`.
- Retention keeps the newest complete backup sets and only deletes old complete backup sets after confirmation.
- Added disk usage warning support with `BACKUP_RETENTION_WARN_DISK_PERCENT`.
- Updated production operations, backup hardening, command audit, and production checklist to include retention status.

## v1.1.1

- Hotfix: ensure production operations commands are registered in the main command dispatcher.
- Verified aliases: `production-ops-wizard`, `operations-wizard`, `ops-wizard`.
- Verified scheduled backup commands: `backup-schedule-plan`, `configure-backup-schedule`, `backup-schedule-status`, `disable-backup-schedule`.
- Verified restore preflight command: `restore-preflight`.


## v1.1.0

- Added scheduled local backups using a systemd service and timer.
- Added `backup-schedule-plan`, `configure-backup-schedule`, `backup-schedule-status`, and `disable-backup-schedule`.
- Added `production-ops-wizard` for release readiness, scheduled backup operations, restore preflight, and support bundle creation.
- Added `restore-preflight` as a safe check-only restore readiness command.
- Updated production checklist and command audit to include scheduled backup operations.

# CHANGELOG

## v1.0.0

### Stable release

- Promoted v1.0.0-rc5 to v1.0.0 after clean public VM quickstart validation.
- Validated public VM flow: domain setup, ERPNext install, Cloudflare Origin CA HTTPS, UFW, Fail2Ban, optional apps, backup creation, backup verification, and release readiness.
- Validated that backend ports 8000 and 9000 remain blocked externally while HTTPS works through Cloudflare/Nginx.
- Keeps the stable reusable installer path at `/opt/erpnext-dev/erpnext-dev.sh` after one-command quickstart runs.
- Keeps provider-neutral cloud firewall wording.

### Production note

- Backup verification confirms files are readable; a real restore rehearsal on a disposable VM is still required before relying on backups for production recovery.

## v1.0.0-rc5

### Improved

- Public/local quickstart now copies the active script to `/opt/erpnext-dev/erpnext-dev.sh` so follow-up commands work after one-command installs from `/tmp`.
- `Next:` command rendering now prefers the stable installer path when available.
- Public VM final status can offer an initial database + files backup and immediately run backup verification/release readiness.
- `verify-access` now presents production-mode access guidance with `https://domain` and backend-port blocking tests instead of only local `:8000` host instructions.
- `next-step` now understands public VM workflows and recommends production SSL, initial backup, or release readiness instead of local HTTPS.

### Notes

- This is a quickstart polish patch. Core install, SSL, firewall, UFW, Fail2Ban, app install, and backup behavior are unchanged except for the optional initial-backup prompt.

## v1.0.0-rc4

### Improved

- Replaced cloud-provider-specific firewall wording with generic cloud provider / cloud firewall wording throughout the script.
- Updated security hardening, UFW, firewall status, production SSL, and production checklist messages so they apply to any cloud provider, not only one vendor.
- Updated README, TESTING, ROADMAP, and CHANGELOG wording for provider-neutral public VM deployments.

### Notes

- This is a wording/UX patch only. It does not change firewall, SSL, UFW, Fail2Ban, backup, or install behavior.

## v1.0.0-rc3

### Added

- Added `release-readiness` for a compact final QA summary before tagging v1.0.0.
- Added `final-qa` / `final-qa-wizard` to group release readiness, command audit, production checklist, backup verification, release notes draft, and support bundle creation.
- Added `command-audit` to summarize the major command groups and validate the user-facing workflow map.
- Added `release-notes-guide` as a compact v1.0.0 release-notes draft.

### Improved

- Added Final QA to the main menu.
- Updated help output with release-readiness commands and final QA workflow.
- Prepared documentation for the final v1.0.0 QA pass.

## v1.0.0-rc2

### Fixed

- Fixed backup status/verification to prefer the latest complete backup set instead of selecting a newer database-only partial set.
- Fixed public/private file archive detection to support both Bench formats: `-files.tar` / `-private-files.tar` and `-files.tar.gz` / `-private-files.tar.gz`.
- Fixed backup archive verification to use gzip-aware tar listing for `.tar.gz` archives and plain tar listing for `.tar` archives.
- Fixed `production-checklist` HTTPS detection so Cloudflare Origin CA / Nginx HTTPS can show `OK` instead of `WARN not confirmed`.

### Improved

- Added `Latest set state` to backup status and verification output, showing `complete` or `partial`.
- Added a compact bottom `Backup Result Summary` after database + files backup creation.

## v1.0.0-rc1

### Added

- Added `backup-status` to show backup folder, counts, latest backup set, and local backup size summary.
- Added `backup-verify` / `verify-backups` to verify the latest database gzip, public files archive, private files archive, and site config JSON without performing a restore.
- Added `off-vm-backup-guide` with workstation-side `rsync` / `scp` examples and checksum guidance.
- Added `restore-rehearsal-guide` with a safe restore test workflow for disposable VMs.
- Added `production-checklist` for go-live readiness across install/runtime, HTTPS, UFW, Fail2Ban, backups, off-VM copy, and snapshots.
- Added `backup-hardening-wizard` / `backup-wizard` to group backup creation, verification, off-VM guidance, restore rehearsal, and production checklist in one compact menu.

### Improved

- Expanded Backup / Restore / Maintenance menu with backup status, verification, off-VM backup guidance, and restore rehearsal steps.
- Kept restore commands destructive and explicit; no automatic restore is performed by status or verification commands.

### Safety

- Backup verification checks file readability only; it clearly states that a real restore rehearsal is still required.
- Restore rehearsal guidance recommends testing on a disposable VM, not the live production VM.


## v0.9.14

### Added

- Added `ssl-mode-status` to show the current SSL provider, DNS state, active certificate path, and recommended SSL mode for the current deployment.
- Added `ssl-mode-guide` / `ssl-compatibility` with a compact SSL compatibility matrix for local self-signed/mkcert, Let’s Encrypt, and Cloudflare Origin CA.
- Added `setup-effort-guide` / `setup-step-count` to show how many shell commands and guided inputs are expected for local VM, public Let’s Encrypt, public Cloudflare, and existing-install workflows.

### Improved

- Production SSL wizard now displays the recommended SSL mode before asking the user to choose a provider.
- Public VM quickstart now includes a quick link to SSL mode guidance and setup step counts.
- First-run wizard now includes setup effort and SSL mode guidance.

## v0.9.13

### Fixed

- Fixed public VM quickstart HTTPS summary so existing Cloudflare Origin CA installs show HTTPS as OK instead of not configured.
- Fixed public VM quickstart domain summary so Cloudflare proxied DNS is treated as expected when Cloudflare Origin CA is active.
- Fixed existing public-domain installs that still had `DEPLOYMENT_MODE=development` in older config files by inferring `public-vm` when a valid production domain is saved.
- Added missing SSL summary helper functions used by the quickstart status card.

### Improved

- Improved interactive menu invalid input handling. If a shell command is pasted into a wizard prompt, the script now explains that the menu expects a number and exits back to the shell instead of repeatedly printing invalid option messages.

## v0.9.12

### Added

- Added first-run onboarding with `first-run`, `setup-wizard`, and `quickstart` aliases.
- Added `public-vm-quickstart` / `public-setup` for a guided public VM flow: domain, DNS plan, install, HTTPS, security, and final status.
- Added `local-dev-quickstart` / `local-setup` for a minimal-input local VM setup using `erp.test`.
- Added `set-domain` to prompt for a production domain and save `SITE_NAME`, `PRODUCTION_DOMAIN`, and deployment mode to the installer config.
- Added `show-config` for a compact saved configuration summary.
- Added official one-command GitHub entry points for public VM and local VM onboarding.

### Improved

- Reduced the need to prefix every command with `SITE_NAME=... PRODUCTION_DOMAIN=...` by saving the domain/site choice in `/etc/erpnext-dev/config.env`.
- Main menu now starts with setup/onboarding options before advanced operations.
- Public VM quickstart prevents users from starting install/HTTPS without first setting a real production domain.

### Safety

- One-command GitHub entry points open guided wizards; they do not silently install production services without prompts.
- Local and public VM setup paths are separated to avoid mixing `.test` development workflows with real public domains.

## v0.9.11

### Improved

- Added terminal UX cleanup for small default terminal windows.
- Replaced the long flat `help` screen with a compact categorized help screen.
- Shortened the main menu and added direct production HTTPS/security-hardening entries.
- Suppressed repeated local `.test` warnings when `PRODUCTION_DOMAIN` is set for public/production-domain workflows.
- Added compact bottom-of-action result summaries for `configure-vm-firewall`, `configure-fail2ban`, and advanced UFW SSH restriction.
- Shortened the security hardening wizard labels so the menu fits more comfortably in smaller terminals.
- Kept long explanations in guide/status commands instead of crowding action output.

### Safety

- No behavior change to firewall rules or SSL configuration.
- UFW still keeps SSH open at the VM layer by default to avoid accidental lockout.
- Backend ports remain blocked by UFW defaults and cloud provider firewall rules.

## v0.9.10

### Added

- Added `vm-firewall-plan` / `ufw-plan` to explain the VM-level UFW hardening model.
- Added `configure-vm-firewall` to install and enable safe UFW defaults.
- Added `vm-firewall-status` / `ufw-status` to inspect UFW status and expected ERPNext public-VM port policy.
- Added `configure-fail2ban` to install Fail2Ban and enable the `sshd` jail.
- Added `fail2ban-status` to inspect Fail2Ban and the `sshd` jail.
- Added `security-hardening-wizard` / `vm-firewall-wizard` to guide UFW and Fail2Ban setup.
- Added advanced `ufw-ssh-admin-only` for users who intentionally want UFW to restrict SSH to a specific admin IP.

### Safety

- `configure-vm-firewall` keeps SSH open at the UFW layer by default to avoid lockout from dynamic admin IPs.
- SSH source restriction remains recommended at the cloud provider firewall layer.
- UFW does not allow `8000`, `9000`, `11000`, or `13000` by default.
- The advanced UFW SSH restriction requires explicit confirmation and warns about lockout risk.

## v0.9.9

### Improved

- Improved `firewall-hardening-status` wording after real cloud firewall validation.
- The command now separates **local listeners inside the VM** from **external public exposure controlled by the cloud firewall**.
- Backend ports `8000` and `9000` are now described as local backend listeners that must be blocked externally, rather than automatically implying they are publicly reachable.
- Added explicit workstation-side validation commands for checking `https://<domain>`, `http://<origin-ip>:8000`, and `http://<origin-ip>:9000`.
- Clarified that `80/443` listeners are expected Nginx entrypoints and may later be restricted to Cloudflare IP ranges when staying proxied.

### Safety

- No firewall rules are changed automatically.
- The command remains inspection/planning only and avoids implying that a local listener bypasses the cloud provider firewall.

## v0.9.8

### Added

- Added `firewall-hardening-status` with aliases `firewall-status` and `hardening-status`.
- The new status command checks local listener exposure for `22`, `80`, `443`, `8000`, `9000`, `11000`, and `13000`.
- It marks `8000` and `9000` as safe to close or restrict once HTTPS is working.
- It warns if Redis ports `11000` or `13000` are ever listening on public interfaces.

### Improved

- `production-ssl-status` is now Cloudflare-aware. When the active provider is Cloudflare Origin CA and DNS returns Cloudflare IPs instead of the origin VM IP, the domain row is treated as expected/OK.
- `public-vm-readiness` now uses the same Cloudflare-aware domain interpretation.
- Help text and advanced menu now include the firewall hardening status command.

### Safety

- No firewall rules are changed automatically. The command is inspection/planning only.
- The output continues to recommend manual cloud/edge firewall changes after HTTPS is verified.

## v0.9.7

### Fixed

- Fixed the Cloudflare Origin CA paste workflow so it no longer requires artificial `END_CERT` and `END_KEY` markers.
- Certificate paste input now stops automatically at the real PEM ending line: `-----END CERTIFICATE-----`.
- Private key paste input now stops automatically at the real PEM ending line: `-----END PRIVATE KEY-----`, `-----END RSA PRIVATE KEY-----`, or `-----END EC PRIVATE KEY-----`.

### Improved

- Cloudflare Origin CA prompts now clearly explain the expected PEM start and end patterns.
- The input reader skips leading non-PEM text and starts recording only when the real PEM begin line is detected.
- Windows CRLF paste endings are normalized before validation.
- The Cloudflare Origin CA guide now explicitly shows the required certificate and private key endings.

### Safety

- Certificate and key contents are still hidden during paste input and are not printed into the installer log.
- File-based inputs via `CLOUDFLARE_ORIGIN_CERT_FILE` and `CLOUDFLARE_ORIGIN_KEY_FILE` remain supported and are still recommended for repeatable production work.

## v0.9.6

### Added

- Added `production-ssl-wizard` / `ssl-provider-wizard` to choose between Let's Encrypt and Cloudflare Origin CA.
- Added `configure-cloudflare-origin-ssl` with aliases `install-cloudflare-origin-cert` and `switch-to-cloudflare-origin-ssl`.
- Added `cloudflare-origin-ssl-status` for Cloudflare Origin CA certificate, key, Nginx, proxy-hint, and HTTPS checks.
- Added `cloudflare-origin-guide` with the dashboard workflow for Origin CA and Full (strict).
- Added optional file-based inputs: `CLOUDFLARE_ORIGIN_CERT_FILE` and `CLOUDFLARE_ORIGIN_KEY_FILE`.

### Improved

- `production-ssl-status` now detects the active Nginx certificate provider rather than assuming Let's Encrypt only.
- Production SSL runtime status now recognizes Cloudflare Origin CA and explains why direct DNS-only browser/curl trust may fail until Cloudflare proxy is enabled.
- Existing managed Nginx production config is backed up before switching to Cloudflare Origin CA.

### Safety

- Cloudflare Origin certificate and key are validated before installation.
- The script compares the certificate public key to the private key public key before writing them to `/etc/ssl/cloudflare-origin`.
- The private key is installed with mode `0600`.
- Paste prompts hide input and avoid printing certificate/key contents into the installer log.
- The command does not change Cloudflare DNS/proxy settings and does not change cloud firewall rules.

## v0.9.5

### Fixed

- Fixed the Let’s Encrypt staging-to-production transition in `configure-production-ssl`.
- If an installed certificate issuer contains `STAGING` and `LETSENCRYPT_STAGING` is not enabled, the script now adds `--force-renewal` so Certbot replaces the staging certificate with a real production certificate.
- After requesting a non-staging certificate, the script fails clearly if a staging certificate is still installed.

### Improved

- `production-ssl-status` now prints a `Certificate issuer` row.
- Production SSL runtime classification now warns when a staging certificate is installed instead of treating certificate presence alone as sufficient.
- `configure-production-ssl` now displays the existing certificate issuer before making changes.

### Notes

- This hotfix came from the first public cloud VM SSL test where a staging certificate successfully routed HTTPS but was not trusted by `curl` or browsers.

## v0.9.4

### Added

- Added `configure-production-ssl` to configure Nginx + Let's Encrypt for a public ERPNext domain.
- Added `production-ssl-status` to inspect DNS, Nginx, Certbot, certificate files, HTTP, HTTPS, and listener state.
- Added `disable-production-ssl` to disable the managed production Nginx site without deleting Let's Encrypt certificates or stopping ERPNext.
- Added `LETSENCRYPT_EMAIL`, `LETSENCRYPT_STAGING`, and `PRODUCTION_SSL_WEBROOT` environment overrides.

### Improved

- Production SSL readiness now recognizes an active Let's Encrypt/Nginx HTTPS setup as production SSL.
- Help text and advanced menu now include production SSL implementation commands.
- Public VM flow now moves from planning-only checks to a conservative HTTPS implementation while leaving cloud firewall changes manual.

### Safety

- `configure-production-ssl` validates that the production domain resolves to the current VM IP before requesting a certificate.
- The command requires ERPNext to be installed and running before configuring Nginx.
- The command prompts for confirmation unless `--yes` is used.
- The command does not automatically close ports `8000` or `9000`; firewall changes remain explicit/manual after HTTPS verification.

## v0.9.3

### Added

- Added `public-vm-readiness` command and `public-readiness` alias.
- Added `production-ssl-plan` command and `prod-ssl-plan` alias.
- Added `production-firewall-plan` command and `prod-firewall-plan` alias.
- Added public VM listener summaries for ports `22`, `80`, `443`, `8000`, `9000`, `11000`, and `13000`.
- Added DNS resolution checks comparing the production domain to the detected VM IP.

### Improved

- Production planning now gives a clearer next step after a successful public cloud VM install.
- `production-readiness` and `production-plan` now point to public VM, SSL, and firewall planning commands.
- Help text and advanced menu now include the new production planning commands.

### Safety

- The new production commands are planning/check-only. They do not issue certificates, change DNS, or alter firewall rules.
- Firewall guidance explicitly keeps Redis ports private and treats public `:8000` as temporary testing exposure only.

## v0.9.2

### Fixed

- Fixed root-run guided setup on fresh public/cloud VMs.
- The Frappe/Bench installation phase no longer expands an empty `$SUDO` prefix into an invalid `-H` command when the installer is launched as `root`.
- Added a dedicated `frappe_login_bash` helper so stdin heredoc install blocks run correctly both as root and as a sudo-capable non-root user.

### Notes

- This is a hotfix from the first real cloud VM test.
- Production SSL planning moves to the next roadmap patch.

## v0.9.1

### Added

- Added `production-domain-plan` command and `prod-domain-plan` alias.
- Added structured production DNS/domain planning output with local site, planned production domain, VM IP, recommended A record, provider notes, and validation checklist.

### Fixed

- Fixed `production-readiness` false `Incomplete` install state when the Bench folder is under the `frappe` user home and requires sudo traversal.
- Production readiness now uses the same sudo-aware install detection as `doctor` and `status`.
- Backup readiness now checks the backup folder through the sudo-aware path helpers.

### Improved

- `production-plan` and `production-readiness` now resolve saved/detected site config through sudo before reporting.
- Production domain guide now points to the structured `production-domain-plan` command.
- Help text and examples now include `production-domain-plan`.

## v0.9.0

### Added

- Added `production-plan` command and `prod-plan` alias.
- Expanded `production-readiness` from a preview into a production planning classifier.
- Added checks for CPU, RAM, root disk, install state, runtime/service state, production domain setting, local SSL assumptions, Nginx presence, and backup readiness.

### Improved

- Production readiness now classifies the VM as `Dev-only`, `Production candidate`, or `Not recommended`.
- Help text and examples now include `production-plan`.
- The production commands are planning-only and do not apply production changes.

## v0.8.24

### Added

- Added `app-compatibility` command for an optional app compatibility matrix.
- Added aliases `app-compat` and `app-preflight`.
- Added detailed compatibility cards before optional app install confirmation.
- Added compatibility snapshot inside `app-install-wizard`.

### Improved

- App install flow now shows detected Frappe branch, detected ERPNext branch, target app branch, install state, compatibility status, and recommendation before download/install.
- Moving branches such as `main` and experimental branches such as `develop` are now clearly warned before installation.
- Help text and app install guide now document the compatibility command.

### Safety

- Optional app installs now require an extra confirmation when the compatibility preflight returns a warning.
- Remote branch availability is checked before backup/download when a target branch is specified and the app is not already downloaded.

## v0.8.23

### Added

- Added `support-bundle` command for generating a redacted troubleshooting archive.
- Support bundle includes `doctor --plain`, `doctor --json`, JSON validation, system summary, service status, port status, storage status, SSL status, Bench status, recent warnings/errors, and a manifest.
- Added `support` as a short alias for `support-bundle`.

### Safety

- Support bundle generation excludes credential files, TLS private keys, raw `site_config.json` secrets, tokens, and database passwords.
- Bundle text outputs are passed through a redaction step before packaging.
- Generated support archives are written with private file permissions.

### Improved

- Help text now documents `support-bundle`.
- The support workflow builds directly on the v0.8.22 plain and JSON diagnostic primitives.
- Replaced the internal GiB formatter with an `awk` implementation to avoid depending on Python during support/status collection.

## v0.8.22

### Added

- Added `doctor --plain` for share-safe copy/paste diagnostics without ANSI colors.
- Added `doctor --json` for structured share-safe diagnostics.
- Diagnostic output now includes OS, Python, Node, MariaDB, Redis, Bench, site, service, port, storage, SSL, and optional app status summaries.

### Improved

- `active_bench_dir` no longer prints duplicate fallback paths when the expected Bench folder is missing.
- Help text now documents `doctor --plain` and `doctor --json`.

### Safety

- Plain and JSON doctor modes intentionally exclude passwords, tokens, private keys, raw credential contents, and raw site config secrets.

## v0.8.21

### Improved

- `next-step` now shows the decision inputs it used: storage, install, runtime, autostart, and local SSL state.
- `next-step` now moves forward after storage is already expanded instead of making the storage phase feel unresolved.
- Local SSL wizard now supports replacing an already-configured certificate with trusted mkcert files copied into `/tmp`.
- Local SSL wizard now identifies whether the installed certificate appears self-signed.
- `ssl-status` now prints a certificate trust hint to make self-signed vs mkcert-style certificates clearer.
- Missing mkcert source-file guidance now reuses the same HOST/VM instructions and explains replacement backups.

## v0.8.20

### Fixed

- Fixed storage status showing `Expansion recommended` after the root filesystem was already expanded.
- Replaced unsafe whole-disk-vs-partition-size expansion decision with actual partition tail-free-space detection.
- Avoids treating `/boot`, BIOS partitions, and partition start offsets as growable space.
- `expand-root-storage` now skips `growpart` when no growable disk tail exists and only uses existing LVM free space when available.

### Improved

- `storage-debug` now prints both detector and evaluator output.
- `storage-status` can display growable disk tail space when present.

## v0.8.19

- Added optional app checkpoint workflow.
- Added app install wizard and rollback guidance.

## v1.1.3 - Off-VM backup automation

- Added rsync-over-SSH off-VM backup workflow.
- Added `off-vm-backup-plan`, `configure-rsync-backup-target`, `off-vm-backup-dry-run`, `run-off-vm-backup`, `off-vm-backup-status`, `disable-off-vm-backup`, and `off-vm-backup-wizard`.
- Integrated off-VM backup status into the production checklist.
- Added off-VM backup options to the Production Operations wizard.
- Keeps safe defaults: dry-run before sync, no remote deletion by default, and no secrets printed to logs.
