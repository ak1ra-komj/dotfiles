---
applyTo: "**/*.sh"
---

- Use `#!/usr/bin/env bash` with `set -euo pipefail`.
- Quote all variable expansions.
- Use `[[ ... ]]` for tests; `case` for multiple conditions.
- Group logic into functions; avoid long inline sequences.
- Handle errors explicitly; check exit codes.
- Use meaningful names; avoid magic numbers.
- Prefer POSIX utils; document non-standard deps.
- Keep scripts idempotent; log actions and errors.
- Use `getopt` for multiple CLI Args.
- Pass `shellcheck`; format with `shfmt`.
