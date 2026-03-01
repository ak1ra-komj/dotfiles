# k8s/bin Script Review and Standardization

Reviewed and updated all seven shell scripts in `k8s/bin/` to align with the project's `developing-bash-scripts` skill guidelines.

## Summary

All scripts in `k8s/bin/` were carrying accumulated inconsistencies: wrong shebang (`#!/bin/bash`), `pipefail` included where `errtrace` is prescribed for complex scripts, verbose log wrapper functions with redundant local colour variables, `"$*"` / `"$@"` without braces, an inverted guard in `set_log_level`, simple (fail-on-first) `require_command` instead of the batch variant, `usage` missing an `exit_code` parameter, and getopt parse failures defaulting to exit 0.

Each script was reviewed according to the skill classification table. The one simple sourced script (`kube-config-selector.sh`) received only a bugfix. The six complex scripts received a standardised set of boilerplate improvements without touching any business logic.

## Changed files

- `k8s/bin/kube-config-selector.sh` — Fixed unanchored grep regex (`[1-9][0-9]?` → `^[1-9][0-9]?$`) to prevent false matches on arbitrary input strings.
- `k8s/bin/kube-append-ingress-rule.sh` — Applied full complex-script standard: shebang, set modes, log wrappers, `set_log_level` guard, batch `require_command`, `usage` exit code, getopt error exit.
- `k8s/bin/kube-check-tls-secret.sh` — Same as above.
- `k8s/bin/kube-deploy-history.sh` — `set -euo pipefail` → `set -o errexit -o nounset -o errtrace`; log wrappers compacted; `set_log_level` guard fixed; `"$*"` / `"$@"` braced.
- `k8s/bin/kube-dump.sh` — Same as kube-deploy-history.sh; already had batch `require_command` and cleanup handler.
- `k8s/bin/kube-iperf3.sh` — Full standard: shebang, set modes, log wrappers, `set_log_level`, batch `require_command`, `usage` exit code, getopt error exit.
- `k8s/bin/kube-reader.sh` — Same as above; `set_log_format` `"$1"` → `"${1}"` also fixed.

## Git commits

No commits were made in this session.

## Notes

- **`errtrace` vs `pipefail`**: The complex-script skill prescribes `set -o errexit -o nounset -o errtrace`. `pipefail` is explicitly excluded unless a script has critical pipe chains that need direct checking. Several scripts had `pipefail`; all were converted to `errtrace`.
- **Inverted `set_log_level` guard**: The old pattern was `if [[ -n ... ]]; then LOG_LEVEL=...; else error; fi`. The correct guard style is `if [[ -z ... ]]; then error; fi; LOG_LEVEL=...` — fail fast and keep the happy path un-nested.
- **`"$*"` → `"${*}"`**: Brace all special variables, including `$*`, `$@`, `$1` etc., for consistency and to avoid surprises when `nounset` is active.
- **Log wrapper compaction**: `log_error() { local RED=31; log_message "${RED}" "ERROR" "$@"; }` becomes `log_error() { log_message 31 "ERROR" "${@}"; }`. The colour is a compile-time constant — wrapping it in a local variable is noise.
- **`require_command` batch variant**: The single-fail variant exits on the first missing command, giving an incomplete picture. The batch variant collects all missing commands before exiting, producing a single actionable error message.
- **`usage` exit code**: The `usage()` function should accept `local exit_code="${1:-0}"` so callers can do `usage 0` (help) vs `usage 1` (parse error). Calling `usage` without a code after a getopt failure silently exits 0, masking the error.
- **Sourced scripts are exempt**: `kube-config-selector.sh` is sourced (not executed) in the user's shell via an alias. Adding `set -e` or `set -u` to a sourced script would propagate those modes to the parent shell, potentially breaking interactive use. No safety modes were added.
