---
name: developing-bash-scripts
description: This skill defines mandatory guidelines for generating, modifying, or reviewing Bash shell scripts to ensure consistency, robustness, and compliance with project standards.
---

# developing-bash-scripts skill

This skill defines mandatory guidelines for generating, modifying, or reviewing Bash shell scripts to ensure consistency, robustness, and compliance with project standards.

It MUST be applied whenever Bash scripts are involved.

## Bash Version & Compatibility

- Scripts are expected to run under standard Bash environments (Bash 4.0+ is generally assumed unless otherwise specified).
- Use `#!/usr/bin/env bash` as the shebang line for portability.
- Explicitly allowed and encouraged features:
  - Bash Arrays: Use indexed arrays (`declare -a`) and associative arrays (`declare -A`) for managing collections of data.
  - Process Substitution: Use `<(command)` or `>(command)` to handle command output as files, avoiding temporary files.
  - Here Strings: Use `<<< "string"` for passing short strings to commands (small here docstrings).
  - Parameter Expansion: Use Bash's rich parameter expansion features for string manipulation (e.g., defaults `:-`, substring, search/replace).
- Clearly document any non-standard dependencies, required Bash versions, or environment assumptions.

## Control Flow & Logic

- Guard Clauses: When using `if...else` constructs or validation logic, always check the incorrect/failure condition first and return/exit early. This reduces nesting and makes the "happy path" code clearer.
  - _Bad_: `if [[ success ]]; then do_work; else exit 1; fi`
  - _Good_: `if [[ ! success ]]; then exit 1; fi; do_work`
- Use `[[ ... ]]` for all conditional tests (more robust than `[ ... ]`).
- Use `case` statements for pattern matching or multiple condition branches where applicable.
- Group related logic into well-named, reusable functions.

## Variables & Style

- Variable Expansion: Always use `${var}` instead of `$var` for variable expansion to improve readability and avoid ambiguity.
  - This rule also applies to positional parameters (e.g. `${1}` instead of `$1`).
- Quoting: Quote all variable expansions (`"${var}"`) to prevent unintended word splitting and globbing.
- Naming: Use descriptive variable names and avoid unexplained magic numbers.
- Idempotency: Preserve idempotency whenever possible.

## Error Handling & Robustness

- Enable strict error handling at the start of the script: `set -o errexit -o nounset -o errtrace`
- Do NOT enable `pipefail` globally unless specifically required for a critical pipe chain.
- Explicitly verify command exit codes where failure handling is non-trivial.
- Implement clear and consistent error handling and logging.
- Log meaningful messages for both normal operations and error conditions.

## Tooling & Maintenance

- Argument Parsing: Use `getopt` (not `getopts`) for all command-line argument parsing to support long options.
- Validation:
  - Validate all scripts using `shellcheck`, and address all warnings.
  - Format scripts consistently using `shfmt`.
- Ensure scripts pass all linting, formatting, and validation checks before acceptance.

## Template Script

- All generated or reviewed scripts MUST be based on the provided [template.sh](template.sh).
- When defining arguments:
  - Fixed options (`--help`, `--log-level`, `--log-format`) MUST appear first.
  - Script-specific arguments must follow.
- Ensure the argument order is consistent between:
  - Usage output
  - `parse_args` implementation
