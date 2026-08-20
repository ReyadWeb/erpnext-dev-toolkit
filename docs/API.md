# Machine-readable API v1

`api-version --json`, `capabilities --json`, `deployment-info --json`, `dashboard --json`, `health-snapshot --json`, `incidents --json`, `backup-status --json`, and `restore-status --json` are covered by the stable API contract. `dashboard --json` now always uses the v1 envelope. Other registry records may advertise `json_available` because they have legacy JSON output; they are not stable v1 commands unless `stable_api_contract` is `true` and `api_contract_version` is `"1.0"`.

Every v1 response has `api_version`, a UTC RFC3339 `generated_at` ending in `Z`, the canonical `command`, `success`, `data`, and `error`. On success, `data` is an object and `error` is null. On failure, `data` is null and `error` is an object with a stable `id`, safe `message`, and object-valued `details`. JSON is written only to stdout; diagnostics are written only to stderr. Human output is not part of this contract.

## Error and exit classes

| Exit | Class | Stable error ID | Meaning |
|---:|---|---|---|
| 0 | success | n/a | Request completed successfully. |
| 64 | usage | `invalid_arguments` | Arguments are invalid for the command. |
| 69 | unavailable | `unavailable` | A required, non-secret capability is unavailable. |
| 70 | internal | `internal_error` | The command could not safely complete. |
| 77 | permission | `permission_denied` | Protected operational evidence cannot safely be read by the caller. |

These classes apply only to stable API commands. Legacy commands retain their existing output and exit behavior. Schemas are in `schemas/api/v1/` and examples used by compatibility tests are in `tests/fixtures/api/v1/`.

Stable discovery commands are dispatched before installation-profile, platform, lock, UI, and logging initialization. They accept only `--json` and the global `--no-color` option; every other token after the command is `invalid_arguments`. If the required JSON encoder is unavailable, no partial document can be produced and the command exits 69 with a concise stderr diagnostic. Registry and serialization failures exit 70; in JSON mode they return `internal_error` whenever the encoder remains usable.

`api-version --json` reports `current_api_version`, the array `supported_api_versions`, and `toolkit_version`. `capabilities --json` reports sorted public registry metadata. Handler names, paths, deployment values, URLs, credentials, and environment values are never included.

## `deployment-info`

`deployment-info` reports normalized intent from trusted Toolkit-owned configuration. It does not discover an installation or inspect filesystems beyond the configured primary and legacy configuration candidates. It never invokes Bench, Frappe, Docker, databases, services, Git, network clients, or privileged commands, and it never mutates the source configuration.

The successful `data` object always contains:

- `toolkit_version`: the Toolkit semantic version.
- `configuration`: `status`, `source`, and `schema_version` provenance.
- `deployment`: the canonical engine and profile intent, their `explicit` or `legacy-default` sources, a sorted curated application array, deployment/runtime/Docker modes, and validated hostname-only site/domain identifiers.
- `observation`: `management_scope`, plus `runtime_probed: false` and `inventory_probed: false`.
- `issues`: a sorted unique array of stable issue identifiers.

Every documented field remains present. Unknown or untrusted scalar values are null, while an empty application selection is `[]`. Native configurations always report a null `docker_mode`. When no trusted configuration is available, all deployment identity fields are null and `management_scope` is `none`.

Configuration `status` is one of `managed`, `legacy-compatible`, `missing`, `unreadable`, `unsafe`, `invalid`, or `conflict`. Configuration `source` is `primary`, `legacy`, or null; `schema_version` is `"2"`, `"legacy"`, or null. Trusted schema-2 and compatible legacy data use `configuration-only` management scope. This scope means only that compatible persisted configuration was parsed: it does not assert that an installation, site, application, container, database, or service exists or is managed, running, ready, or healthy.

The primary configuration takes precedence. Legacy fallback is considered only when the primary file is absent. A primary file that is unsafe, unreadable, or invalid is reported as such without fallback. Conflicting normalized public metadata in two trusted candidates produces `conflict`; compatible mirrors select `primary`. Historical legacy files may default an absent engine to `native` and profile to `recommended`; those values are labeled `legacy-default`, the status is `legacy-compatible`, and `legacy_configuration` is included in `issues`. Defaults are never invented for a missing or untrusted file.

Stable issue identifiers are `configuration_missing`, `configuration_unreadable`, `configuration_unsafe`, `configuration_invalid`, `configuration_conflict`, and `legacy_configuration`. Missing and rejected configuration are successfully reported states. API failure envelopes are reserved for invalid arguments (`invalid_arguments`, exit 64), an unavailable JSON runtime (`unavailable`, exit 69), or an internal safe-serialization failure (`internal_error`, exit 70).

Configuration files are handled as bounded data, never sourced or evaluated. Each candidate is inspected without following a final-component symlink, must be a readable regular file no larger than 64 KiB, and must not be group- or world-writable. One bounded snapshot is copied to a private temporary directory and parsed from an explicit key allowlist. Command substitutions, backticks, unknown keys, comments, rejected values, paths, credentials, tokens, private URLs, and other secrets are never emitted.

`deployment-info` is configuration-only: it never probes live runtime state. The Operations API below performs bounded live observation from trusted normalized configuration.

## Operations snapshots

`dashboard --json` and `health-snapshot --json` return the same canonical `data` object; only the envelope `command` differs. Both accept `--json` and `--no-color` before or after the command. They are read-only, non-interactive, require root for protected evidence, and never invoke sudo themselves. Human `dashboard`, human `incidents`, and the no-flag legacy `health-snapshot` interface retain their existing behavior.

The snapshot always includes `toolkit_version`, UTC `observed_at`, safe deployment identity, installation profile and reconciliation state when available, `overall_status`, `resources`, `application`, `runtime`, `protection`, backup summary, observation-only `healing`, concise allowlisted `checks`, and stable `issues`. Every documented field is present. Measurements are numbers or null, booleans are booleans, arrays remain arrays, and non-applicable Native/Docker fields are null. Status values are exactly `HEALTHY`, `DEGRADED`, `CRITICAL`, or `UNKNOWN`. A degraded or critical observation is still a successful API response.

Details are sanitized, bounded to 240 characters, and exclude paths, full endpoints, command output, container IDs, database identities, credentials, tokens, private repository URLs, ANSI, and control characters. Fixed read-only host, service, Docker, certificate, and bounded HTTP probes may be used. Missing or failed evidence becomes `UNKNOWN`, null, and a stable `<check>_<status>` issue. Every potentially blocking probe has a finite timeout and the intended ordinary-failure budget is at most 30 seconds. Database queries, container shells, Git discovery, adoption, and mutation commands are excluded.

Stable snapshot collection does not record incidents, update monitoring history or cooldown state, create locks or logs, send alerts or webhooks, or plan/execute healing. It does not change files, modes, ownership, timestamps, symlinks, services, containers, or deployment state.

## Incidents

`incidents --json` reads existing Toolkit incident records only. Its data fields are `toolkit_version`, fixed `limit: 20`, returned `count`, `truncated`, newest-first `incidents`, and `issues`. Each incident exposes only `id`, `timestamp`, `previous_status`, `status`, `site`, `host_status`, `application_status`, `http_status`, `protection_status`, and `would_heal`; raw JSON and `http_detail` are never returned.

Missing or empty history succeeds with an empty array. Records must be bounded regular files with safe permissions and stable metadata, must not be symlinks, and must contain unique JSON keys plus valid IDs, UTC timestamps, types, and status values. `latest.json` is ignored. Rejected records are omitted and reported using `incident_directory_unreadable`, `incident_name_invalid`, `incident_not_regular`, `incident_permissions_unsafe`, `incident_oversized`, `incident_changed_during_read`, or `incident_invalid`; contents and paths are never exposed. Pagination is intentionally not part of v1.21.

## Backup and restore status

`backup-status --json` and `restore-status --json` are root-required, non-interactive metadata observations with Native/Docker parity. Options may precede or follow the command; only `--json` and `--no-color` are accepted. Human `backup-status` and `restore-preflight` remain independent legacy interfaces and are never parsed to construct JSON.

Both responses include `toolkit_version`, UTC `observed_at`, a deployment object containing only normalized `engine` and validated hostname `site`, `overall_status`, and sorted unique stable `issues`. Status is exactly `HEALTHY`, `DEGRADED`, `CRITICAL`, or `UNKNOWN`. Missing, partial, old, failed, or unproven backup evidence is a successful observation expressed in data; inability to read caller-protected evidence is `permission_denied` (77). All nullable fields are always present and use JSON null, never placeholder text.

`backup-status` reports:

- `local`: storage kind, bounded-scan/truncation state, observed and complete set counts, and the latest set. The latest set has an ephemeral SHA-256 ID, UTC creation time, integer age, completeness, aggregate metadata size, and presence/size metadata for database, public files, private files, site configuration, and checksum manifest. `present` does not mean readable, valid, or verified.
- `schedule`: whether fixed-unit schedule observation is supported/configured, enabled and active booleans or null, and the next UTC run or null. It uses finite `systemctl` status queries and never reads the journal.
- `retention`: configured complete-set keep count, complete/candidate counts or null, and backup-filesystem utilization or null. It never enumerates deletion targets or deletes anything.
- `off_vm` and `object_storage`: configured state, `success`/`failed`/`unknown` last result, and UTC last-run time or null. Destinations and remote identities are never returned or contacted.

`restore-status` reports the newest safely observed candidate, trusted rehearsal evidence, and readiness booleans. Candidate component fields are availability observations only. `deep_verification_performed`, `deep_integrity_verified`, and `live_restore_performed` are always false. A database candidate means database metadata exists; a full candidate satisfies the Toolkit's four-component definition. `matching_rehearsal_proven` requires successful trusted evidence matching both the current site and opaque candidate identity. A complete candidate is never described as integrity-verified.

Stable issues include configuration/directory unavailability, unsafe or truncated scans, missing/partial sets, disabled/inactive schedules, unconfigured or failed off-VM/object runs, missing/failed/unsafe/mismatched rehearsal evidence, changed evidence, and `deep_verification_not_performed`. Issue IDs are allowlisted and never derived from file contents.

Configuration, state, and rehearsal records are treated as bounded data: no `source` or `eval`, no final-component symlinks, regular files only, 64 KiB maximum, trusted ownership, non-writable group/world permissions, unique allowlisted keys, valid UTF-8, no controls, and stable metadata across the read. Backup artifacts are inspected by no-follow metadata only with a 256-entry scan bound. Archive content is never opened, decompressed, or hashed; the opaque set digest is derived in memory from safe internal identity and is not persisted.

These commands do not run Bench/Frappe, container commands, database queries, Git discovery, SSH/rsync/rclone, remote reachability tests, backup verification, rehearsal recording, backup creation, or restore. They create no logs, locks, state, evidence, or other files and do not change services. Use human `backup-verify` for deep archive verification, `restore-preflight` for the interactive preflight workflow, and an explicitly authorized restore command for a live restore.
