# Machine-readable API v1

`api-version --json` and `capabilities --json` are the first commands covered by the stable API contract. Other registry records may advertise `json_available` because they have legacy JSON output; they are not stable v1 commands unless `stable_api_contract` is `true` and `api_contract_version` is `"1.0"`.

Every v1 response has `api_version`, a UTC RFC3339 `generated_at` ending in `Z`, the canonical `command`, `success`, `data`, and `error`. On success, `data` is an object and `error` is null. On failure, `data` is null and `error` is an object with a stable `id`, safe `message`, and object-valued `details`. JSON is written only to stdout; diagnostics are written only to stderr. Human output is not part of this contract.

## Error and exit classes

| Exit | Class | Stable error ID | Meaning |
|---:|---|---|---|
| 0 | success | n/a | Request completed successfully. |
| 64 | usage | `invalid_arguments` | Arguments are invalid for the command. |
| 69 | unavailable | `unavailable` | A required, non-secret capability is unavailable. |
| 70 | internal | `internal_error` | The command could not safely complete. |

These classes apply only to stable API commands. Legacy commands retain their existing output and exit behavior. Schemas are in `schemas/api/v1/` and examples used by compatibility tests are in `tests/fixtures/api/v1/`.

`api-version --json` reports `current_api_version`, the array `supported_api_versions`, and `toolkit_version`. `capabilities --json` reports sorted public registry metadata. Handler names, paths, deployment values, URLs, credentials, and environment values are never included.
