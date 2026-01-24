---
name: developing-posix-shell-scripts
description: This skill defines mandatory guidelines for generating, modifying, or reviewing POSIX-compliant shell scripts to ensure portability and standard compliance.
---

# developing-posix-shell-scripts skill

This skill defines mandatory guidelines for generating, modifying, or reviewing POSIX-compliant shell scripts (`/bin/sh`) to ensure portability across different UNIX-like systems and standard compliance.

It MUST be applied whenever strict POSIX compliance is required or when targeting `/bin/sh`.

## Shell Version & Compatibility

- Scripts MUST be compliant with the POSIX shell standard (IEEE Std 1003.1).
- Shebang MUST be `#!/bin/sh` (or `#!/usr/bin/env sh` if specific environment requirements exist).
- Forbidden Bash/Zsh Features:
  - DO NOT use arrays (`declare -a`, `name[0]`).
  - DO NOT use `[[ ... ]]` (use `[ ... ]`).
  - DO NOT use `function name { ... }` syntax (use `name() { ... }`).
  - DO NOT use the `local` keyword (variables are global; use subshells or prefixed names if scope isolation is needed).
  - DO NOT use `source` (use `.` instead).
  - DO NOT use `<<<` (here-strings).
  - DO NOT use `<(...)` or `>(...)` (process substitution).
  - DO NOT use `let` or C-style `((...))` arithmetic (use `$((...))`).
  - DO NOT use `pipefail`.
  - DO NOT use `declare` or `typeset`.
  - DO NOT use substitution modifiers like `${var: -1}` or `${var^^}` (use `tr`, `sed`, or other utilities).

## Control Flow & Logic

- Guard Clauses: When using `if...else` constructs or validation logic, always check the incorrect/failure condition first and return/exit early.
- Use `[ ... ]` for conditional tests. Ensure variables inside are quoted: `[ "$var" = "value" ]`.
- Use `case` statements for pattern matching or multiple branches.
- Group related logic into well-named functions using standard syntax `name() { ... }`.
- Command Substitution: Use `$(...)` instead of backticks `` `...` ``.

## Variables & Style

- Variable Expansion: Always use `${var}` for variable expansion (including positional parameters like `${1}`).
- Quoting: Quote all variable expansions (`"${var}"`) to prevent unintended word splitting and globbing.
- Naming: Use descriptive variable names. Since `local` is not standard, consider namespacing function variables (e.g., `_func_var`) to avoid collisions.

## Error Handling & Robustness

- Enable strict error handling at the start: `set -o errexit` (or `set -e`) and `set -o nounset` (or `set -u`).
- Explicitly verify command exit codes where strictly necessary.
- Use `printf` instead of `echo` for predictable output, especially when printing variable content.
- Log meaningful messages to `stderr`.

## Tooling & Maintenance

- Argument Parsing: Use `getopts` (built-in) for argument parsing. Note that `getopts` supports short options only by standard.
- Validation:
  - Validate all scripts using `shellcheck` (ensure it targets `sh`, e.g., via directive `#!/bin/sh`).
- Format scripts consistently.

## Template Script

- All generated or reviewed scripts MUST be based on the provided [template.sh](template.sh).
- When defining arguments:
  - Fixed options (`-h`) MUST appear first in usage/help.
  - Script-specific arguments follow.
