# dotsh Script Review and Simplification

Reviewed and refactored all scripts under `dotsh/bin/` to fix code quality issues and remove over-engineering introduced by a previous refactoring pass.

## Summary

A previous refactoring had uniformly applied a "complex script" template (full logging subsystem, `getopt` arg parsing, `--log-level`/`--log-format` flags, cleanup handlers) to every script in `dotsh/bin/` regardless of actual complexity. This session reviewed each script against a skill-based classification framework, identified which scripts were genuinely complex vs. simple, and refactored accordingly. The key insight developed during the session: **counting flag quantity is insufficient for classifying script complexity — each flag must be assessed for whether it is a real runtime-variable input or just a hardcoded default wearing a CLI flag as a costume**.

## Changed files

- `dotsh/bin/apt-download.sh` — Review only (no changes applied); identified issues: shebang, missing safety modes, unnecessary function wrapper, `grep "^\w"` GNU dependency.
- `dotsh/bin/bash-history-archive.sh` — Complex→Simple reclassification; removed entire logging subsystem, `getopt`, `--log-level`/`--log-format`/`--max-lines`/`--history-file`/`--archive-file` flags (all were hardcoded constants); replaced with `readonly` constants and a 30-line linear script. Also fixed operation order for atomicity (`tail` first, then archive, then `mv`) and scoped `umask` with save/restore.
- `dotsh/bin/conntrack-tcp-count.sh` — Complex→Simple reclassification; removed all logging/arg-parsing scaffolding (none of the `log_*` functions were ever called); gawk logic preserved entirely; dependency check inlined as a 3-line loop.
- `dotsh/bin/crtsh-query.sh` — Simple script fixes: shebang, add `nounset`/`pipefail`, replace `test -n ... || algo=sha256` with `"${2:-sha256}"`, fix quoting, remove unnecessary wrapper function.
- `dotsh/bin/curl-header.sh` — Minimal wrapper fixes: shebang, replace `pipefail` with `nounset`, remove pointless subshell `( )`, move `set -x` to top level.
- `dotsh/bin/curl-time.sh` — Minimal wrapper fixes: shebang, add `set -o errexit -o nounset`, fix `"$@"` → `"${@}"`.
- `dotsh/bin/docker-rm.sh` — Genuine complex script; kept full structure but applied standard fixes: shebang, `log_*` single-line form, `set_log_level` guard clause, `require_command` accumulate-then-report, `usage()` exit code param, `parse_args` quoting throughout, removed unused `REST_ARGS` indirection.
- `dotsh/bin/find-list.sh` — Simple script rewrite: shebang, safety modes, remove function wrapper, replace `test -n` with default substitution, eliminate variable shadowing `realpath` command, guard clause for non-directory, `cd` moved into subshell, removed meaningless trailing `cd`.
- `dotsh/bin/mktrans` — Genuine complex script; standard fixes: shebang, `log_*` single-line, `set_log_level` guard clause, `set_log_format` quoting, `require_command` accumulate pattern, `usage()` exit code, `parse_args` quoting throughout.
- `dotsh/bin/pixiv-to-gif.sh` — Genuine complex script; same standard fixes as above; additionally removed `REST_ARGS` array that was declared with `# shellcheck disable=SC2034` but never actually used (inputs come from `find`, not positional args).
- `dotsh/bin/rsync-home-dir.sh` — Initially applied standard complex script fixes (`pipefail` → `errtrace`, logging single-line form, etc.); then reclassified as Simple after recognising the script ultimately runs one `rsync` command with a fixed exclude list. Full rewrite: load `REMOTE_DIR` from `.env`, run rsync with `"${@}"` passthrough, `set -x` for visibility. `--dry-run` delegated to rsync's own flag.
- `dotsh/bin/setfacl-dir.sh` — Partial reclassification: real flags (`-o/-d/-m/-u/-g`) kept with `getopt`; logging subsystem (`--log-level`/`--log-format` and all `log_*` functions), empty cleanup handler, and separate `check_root()`/`validate_user()`/`validate_group()` helper functions removed. Output replaced with plain `echo`/`err()`. `validate_user` and `validate_group` inlined into `validate_inputs()`.
- `dotsh/bin/smartctl.sh` — Genuine complex script; standard fixes: shebang, `pipefail` → `errtrace`, fix `COLOR_*=$'\e[...]'` (single-quote `\e` not expanded by `printf`), `"${*}"` braces, `log_message` case single-line + `date --utc --iso-8601=seconds`, log one-liners, `set_log_level` guard clause, `require_command` accumulate pattern, `usage()` exit code param, `parse_args` quoting throughout, `main "${@}"`.
- `dotsh/bin/video-frames-extractor.sh` — Genuine complex script; same standard fixes as smartctl.sh; additionally fixed bug: `${DRY_RUN:+DRY-RUN}${DRY_RUN:-EXECUTE}` always expanded to `DRY-RUNfalse` because `false` is a non-empty string — replaced with `[[ "${DRY_RUN}" == true ]] && mode="DRY-RUN" || mode="EXECUTE"`.
- `dotsh/bin/video-streams-extractor.sh` — Genuine complex script; same standard fixes + same `DRY_RUN` mode display bug fix.
- `dotsh/bin/wwn-ata-mapping.sh` — Genuine complex script; same standard fixes.
- `git/bin/git-clone` — Genuine complex script; same standard fixes applied to all logging/arg-parsing code.
- `git/bin/git-fetch` — Complex→Simple reclassification; script had 251 lines of boilerplate for a core task that is one `find | xargs git fetch` pipeline. Full rewrite to 22 lines: positional args `[DIRECTORY [JOBS]]`, guard clause for missing directory, `# shellcheck disable=SC2016` for intentional `$1` in `sh -c` single-quoted string.

## Git commits

No commits were made in this session.

## Notes

### Core insight: flag purpose analysis before complexity classification

Do not count flags — analyse their purpose. A flag that is never passed a different value in practice is a constant. The test:

> "If this flag were removed and its value hardcoded, would any real invocation of the script change?"

If no: it is a constant, not a flag, and does not contribute to complexity.

### Pattern: over-engineering via uniform template application

The scripts in this repo were all refactored in a single pass that applied the same "complex script" template to every file. This is a common failure mode: the template looked professional, so it was applied everywhere. The result was scripts with 200–300 lines of boilerplate that did 10 lines of real work.

### When `--dry-run` belongs to the wrapped tool, not the wrapper

`rsync` already has `--dry-run`. A wrapper script that adds its own `--apply`/ dry-run abstraction is duplicating semantics that already exist. Prefer transparent passthrough (`"${@}"`) over re-implementing tool flags.

### `pipefail` vs `errtrace`

- Complex scripts should use `errtrace` (ERR trap inherited by functions), not `pipefail`.
- `pipefail` is only warranted when the script has a critical pipeline whose intermediate failure must be caught.
- Simple scripts need neither; `errexit` + `nounset` is sufficient.

### `require_command` scope

Only non-standard external commands need checking. POSIX tools (`wc`, `head`, `sed`, `tail`, `date`, `readlink`, `sort`, etc.) are universally available wherever bash runs and should never appear in `require_command`.

### Atomicity in file manipulation

When trimming a file in-place:

1. Write the trimmed content to a temp file **first** (original untouched on failure).
2. Append old lines to archive **second** (temp file cleaned by trap on failure).
3. `mv` temp → original **last** (atomic on same filesystem).

The original `bash-history-archive.sh` had steps 1 and 2 reversed, risking duplicate archive entries on partial failure.

### `umask` scope

`umask` is process-global. Setting it inside a function affects all subsequent file operations in the script. Always save and restore: `old=$(umask); umask 077; ...; umask "$old"`.

### `${VAR:+X}${VAR:-Y}` is not a ternary for boolean flags

When a variable holds the string `"false"` (e.g. `DRY_RUN=false`), `${DRY_RUN:+DRY-RUN}` expands to `DRY-RUN` (non-empty string is truthy), and `${DRY_RUN:-EXECUTE}` also expands to `false` (variable is set). The full expression becomes `DRY-RUNfalse`. This pattern only works when the variable is either empty or unset. For boolean string flags, use an explicit conditional: `[[ "${flag}" == true ]] && val="YES" || val="NO"`.

### `SC2016` false positive with `sh -c` and `xargs`

When passing a shell snippet to `sh -c` via `xargs -I{}`, the placeholder `$1` inside single quotes is intentional (it will be filled by the `sh` interpreter, not by bash). `shellcheck` flags this as SC2016 ("expressions don't expand in single quotes"). Suppress with `# shellcheck disable=SC2016` placed **before the entire pipeline** (not mid-pipeline — shellcheck directives mid-pipe are a parse error).

### `COLOR_*` constants with escape sequences

`readonly COLOR_RED='\e[31m'` does not work with `printf` — single quotes prevent escape interpretation. Use `$'...'` ANSI-C quoting: `readonly COLOR_RED=$'\e[31m'`. Alternatively use the numeric colour approach adopted in the logging subsystem (pass raw ANSI codes as integers to `printf "\x1b[0;%sm"`).

### `git-fetch` as a case study of template over-application

The original `git-fetch` had 251 lines: full logging subsystem, `getopt` parsing, `--log-level`/`--log-format`/`--jobs` flags, a `require_command` call, a `parse_args` function, a `git_fetch` function, and a `main` function. The actual logic was one `find … | xargs git fetch` pipeline. Rewritten to 22 lines. The `--jobs` flag is a legitimate runtime variable but does not justify the full complex-script scaffold — a positional argument or env-var default is sufficient at this scale.
