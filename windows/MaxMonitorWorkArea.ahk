#Requires AutoHotkey v2.0

#+Up:: {
    activeWin := WinGetID("A")
    WinRestore(activeWin)

    ; retrieves the bounding coordinates of its working area for all monitors
    monitors := []
    loop MonitorGetCount() {
        if MonitorGetWorkArea(A_Index, &L, &T, &R, &B) {
            monitors.Push({left:L, top:T, right:R, bottom:B})
        }
    }

    ; calculating max bounding coordinates of working area
    workArea := monitors[1]
    for m in monitors {
        if A_Index = 1
            continue
        workArea.left   := Min(workArea.left, m.left)
        workArea.top    := Min(workArea.top, m.top)
        workArea.right  := Max(workArea.right, m.right)
        workArea.bottom := Max(workArea.bottom, m.bottom)
    }

    WinMove(
        workArea.left,
        workArea.top,
        workArea.right - workArea.left,
        workArea.bottom - workArea.top,
        activeWin
    )
}