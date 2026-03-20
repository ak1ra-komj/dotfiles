# mpv-grid Bash Implementation

Implemented a Bash port of `Invoke-Mpv-Grid.ps1` and fixed grid placement on KDE Plasma / Wayland.

## Summary

The user had a PowerShell script (`windows/bin/Invoke-Mpv-Grid.ps1`) that arranges multiple MPV
players in a configurable grid layout across a chosen monitor. The goal was to produce an equivalent
Bash script for Linux. The script was written as a full complex Bash CLI tool following the
`developing-bash-scripts` skill, then debugged after the user reported that the grid positioning was
silently broken under Debian 13 KDE Plasma (Wayland session). Root cause was that the Wayland
protocol does not allow client-side window placement; the fix was to force XWayland by prefixing the
`mpv` invocation with `WAYLAND_DISPLAY=''`.

## Changed files

- `dotsh/bin/mpv-grid.sh` — Created from scratch as a Bash port of the PowerShell original; then
  patched to prefix `mpv` with `WAYLAND_DISPLAY=''` to force XWayland so that `--geometry`
  placement is honoured by KWin.

## Git commits

- `d57dfce` feat: add mpv-grid script for arranging and playing videos in a grid layout

## Notes

- **Wayland blocks client window placement.** The `xdg_toplevel` Wayland protocol gives compositors
  (KWin, Mutter, etc.) full authority over window placement. Any X11 geometry hint a client sends is
  silently ignored. The only reliable workaround without compositor-specific APIs is to use
  XWayland.
- **Force XWayland per-process with `WAYLAND_DISPLAY=''`.** Setting the variable to empty in the
  command prefix causes the process to see no Wayland socket and fall back to X11. This is
  per-invocation and does not affect the calling shell or other processes.
- **shellcheck SC1007**: `WAYLAND_DISPLAY= cmd` is flagged as a potential typo. Use
  `WAYLAND_DISPLAY='' cmd` instead.
- **Monitor geometry via `xrandr --listmonitors`.** The output format
  `W/mmxH/mm+X+Y` can be parsed with a single `sed` invocation extracting four integers: `X Y W H`.
- **`find` with multiple `-iname` patterns** requires grouping with `\( -iname "*.mp4" -o -iname
  "*.mkv" ... \)` to correctly limit the alternation scope; the script builds this array
  programmatically to avoid hardcoding.
- **KDE Plasma + XWayland prerequisite.** The fix assumes XWayland is running (it is enabled by
  default in KDE Plasma sessions). Environments using pure Wayland without XWayland support would
  need a compositor-specific window placement API (e.g., a KWin script).
