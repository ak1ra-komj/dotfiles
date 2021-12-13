
;;;;;;;;;;;;;;;;; Global ;;;;;;;;;;;;;;;;
; Reload this script
<!r::
    Reload
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;; Functions ;;;;;;;;;;;;;;;
MouseIsOver(WinTitle) {
    MouseGetPos,,, WinId
    return WinExist(WinTitle . " ahk_id " . WinId)
}
Return
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; 当鼠标处于任务栏时, 使用滚轮调节音量
#If MouseIsOver("ahk_class Shell_TrayWnd")
{
    WheelUp::Send {Volume_Up}
    WheelDown::Send {Volume_Down}
}

; 雷电模拟器, 尼禄祭抽奖池, 别的模拟器用 Window Spy 改下 ahk_class 就行
#IfWinExist, ahk_class LDPlayerMainFrame
{
    ;; 相关信息
    ;; 相对 Window 的像素值
    ;; 关闭(左上角返回)按钮 150, 90
    ;; 活动报酬 1600, 90

    NeroClick() {
        Loop, 250
        {
            If GetKeyState("Esc", "P")
                Break
            Click 600, 600
            Sleep, 200
        }
    }
    Return

    NeroReset() {
        ; 单纯的大括号是不允许 K&R 模式的
        ; 重置奖池
        Click 1550, 360
        Sleep 2000
        ; 执行
        Click 1150, 800
        ; 否
        ;Click 600, 800
        Sleep, 2000
        ; 道具已补充，关闭
        Click 850, 800
    }
    Return

    <!1:: WinActivate
    <!2:: NeroClick()
    <!3:: NeroReset()
    <!`::
    Loop
    {
        If GetKeyState("Esc", "P")
            Break
        NeroReset()
        Sleep, 3000
        ; 抽池
        Loop, 250
        {
            If GetKeyState("Esc", "P")
                ; 考虑这里需要 Break, 2 不能调用 NeroClick()
                Break, 2
            Click 600, 600
            Sleep, 200
        }
        Sleep, 5000
    }
    Return
}
