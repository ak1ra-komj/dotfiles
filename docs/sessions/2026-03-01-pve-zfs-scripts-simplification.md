# pve/bin and zfs/bin Script Simplification

Review and simplify all shell scripts in `pve/bin` and `zfs/bin`, removing over-engineered boilerplate while preserving all business logic.

## Summary

The four scripts in `pve/bin` and `zfs/bin` had all been generated with the same complex-script template — a full logging subsystem (`log_color`, `log_message`, `log_error`, `log_info`, `log_warning`, `log_debug`, `log_critical`, `set_log_level`, `set_log_format`), `--log-level`/`--log-format` CLI flags, and verbose `main()`/`parse_args()` scaffolding. A flag audit (per the `developing-bash-scripts` skill) found that `--log-level` and `--log-format` are never meaningfully varied by callers, making them template artifacts rather than genuine flags.

`pvehost-backup.sh` was the most egregious case: 415 lines wrapping what is essentially one `tar` call, a `sha256sum`, and a `find`-based cleanup. It was rewritten as a 47-line simple script with constants instead of flags. The remaining three ZFS scripts had real complexity (`--apply` dry-run gates, cross-pool send/receive, config file manipulation) so they kept structured code, but the logging framework was replaced with three-line `info`/`warn`/`err` helpers.

## Changed files

- `pve/bin/pvehost-backup.sh` — Rewritten as a simple script (415 → 47 lines). All flags (`--path`, `--retention`, `--verify`, `--no-cleanup`, `--dry-run`, `--log-level`, `--log-format`) replaced by `readonly` constants. Backup paths inlined as a Bash array. Logic: `mkdir`, filter existing paths, `tar`, `sha256sum`, `find`-based retention cleanup.
- `zfs/bin/zfs-release.sh` — Rewritten as a simple script (265 → 20 lines). No genuine flags; positional `<rootfs>` validated with `${1:?}`. Full body is two nested `while read` loops over `zfs list` and `zfs holds`.
- `zfs/bin/zfs-dedup-zvol.sh` — Simplified (321 → 110 lines). Removed logging framework and `--log-level`/`--log-format`; replaced with inline `info`/`warn`/`err`. Retained `--apply` flag (callers genuinely pass it or omit it) and the interactive confirmation prompt.
- `zfs/bin/zfs-rename-vmid.sh` — Simplified (458 → 185 lines). Removed logging framework; retained `--apply` and `--backup-dir` flags. Business logic (cross-pool `zfs send|receive` vs same-pool `zfs rename`, config sed + diff + rm) preserved intact.

## Git commits

No commits were made in this session.

## Notes

- **Flag audit before refactoring**: Always ask _"would a real caller pass a different value here in practice?"_ before counting a flag. `--log-level` and `--log-format` consistently fail this test — they were set at template-generation time and never changed.
- **The logging subsystem trap**: The complex-script template's logging subsystem (~80 lines) is appropriate for long-running production daemons but adds enormous noise to scripts whose entire logic fits in 30–60 lines. Prefer `info()/warn()/err()` one-liners for scripts that don't need log levels.
- **`pvehost-backup.sh` pattern**: A script that only runs one command with a fixed set of arguments should be expressed as a simple script with `readonly` constants, never with a `getopt`-based CLI. The test: _if converting all flags to constants doesn't change how anyone calls the script, they are not flags_.
- **Bash array for path lists**: Using a Bash array (`BACKUP_PATHS=(...)`) and iterating with `[[ -e "${path}" ]] && existing_paths+=("${path}")` is cleaner than a heredoc + subshell pipe for inline path filtering.
- **`readarray -t` without `2>&1`**: The original `zfs-dedup-zvol.sh` piped `2>&1` into `readarray`, which would include error messages as array elements — a subtle bug. Removed in the rewrite.
- **Cross-pool rename consistency**: `zfs-rename-vmid.sh` correctly handles same-pool (`zfs rename`) vs cross-pool (`zfs snapshot` + `zfs send | zfs receive`) cases. This logic is genuinely complex and justified the retained function structure.
