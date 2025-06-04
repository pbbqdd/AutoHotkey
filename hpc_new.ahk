#Requires AutoHotkey v2.0
;使用动态回中算法。可以动态调整回中。避免长期使用后漂移问题。
; 脚本名称: 头部姿态控制多窗口切换
; 描述: 这是一个 AutoHotkey v2 脚本，用于通过头部追踪器（模拟为游戏手柄轴）控制 Windows 窗口的切换。
;       它实现了动态中立点、速度检测、死区以及基于状态的动作触发，以提供更稳定和直观的体验。
; 作者: [根据需要填写你的名字或保持匿名]
; 版本: 1.0

#SingleInstance Force ; 确保脚本只运行一个实例。如果脚本已在运行，新启动的实例会替换旧实例。

; --- 配置参数 ---
; 这些参数可以根据你的头部追踪器设置、个人偏好和使用场景进行调整。

JoystickNumber := 2  ; 指定你的头部追踪器在系统中的手柄编号。通常是 1 或 2。
TargetAxis := 'JoyV'   ; 监控的航向轴 (Yaw)。例如 'JoyX', 'JoyY', 'JoyZ', 'JoyR', 'POV'。
TargetAxis2 := 'JoyU' ; 监控的仰俯轴 (Pitch)。用于判断头部是否在允许的俯仰范围内。
TargetAxis3 := 'JoyX' ; 监控的滚转轴 (Roll)。用于判断头部是否在允许的滚转范围内。
TargetAxis4 := 'JoyZ' ; 监控的Z轴。用于触发重置追踪器（例如，按下Ctrl+Shift+/）。
PollingInterval := 20 ; 轮询间隔，单位毫秒。脚本每隔此时间检查一次手柄状态。
                      ; 较小的值响应更快但可能占用更多CPU；较大的值更平滑但有延迟。

; --- 动态窗口切换逻辑配置 ---
; 这些参数定义了头部姿态如何被解释为动作。

Stillness_Speed_Threshold := 0.1 ; 判定头部“静止”的速度阈值。当航向速度低于此值时，认为头部处于静止状态。
Stillness_Duration_ms := 500   ; 头部需要保持静止的时间 (毫秒)。如果头部在此时间内保持静止，
                               ; 并且当前处于“中立”状态 (axis_state = 0)，则更新中立位置。
Yaw_Trigger_Threshold := 8     ; 航向轴 (JoyV) 偏离中立位置多少时触发左右转动作。
                               ; 例如，中立是50，阈值是8，则 <42 触发左转，>58 触发右转。
Yaw_Deadzone_HalfWidth := 3    ; 航向轴 (JoyV) 中立位置周围的死区半宽。
                               ; 例如，中立是50，死区半宽是3，则 47-53 是中立死区。
                               ; 头部在此区域内不会触发左右转，且是回中动作的目标区域。
Roll_Deadzone_HalfWidth := 10  ; 滚转轴 (JoyX) 中立位置周围的死区半宽。
                               ; 用于检查头部滚转是否在允许的范围内，超出此范围将阻止左右转和回中动作。

; --- 内部变量 ---
; 这些变量用于脚本内部的状态管理和数据存储。

; 存储目标摇杆轴的上一次位置，用于检测位置变化和计算速度。
prev_axisV_position := ''
prev_axisU_position := ''
prev_axisX_position := ''
prev_axisZ_position := ''

; 动态中立位置：头部航向 (JoyV) 和滚转 (JoyX) 的“中心”点。
; 这个点会在头部静止且处于中立状态时自动学习更新，以适应用户坐姿或追踪器位置的变化。
neutral_axisV := 50 ; 初始中立航向位置 (JoyV)。
neutral_axisX := 50 ; 初始中立滚转位置 (JoyX)。

; 静止检测变量：用于判断头部是否保持静止足够长时间以更新中立点。
last_still_time := 0 ; 上次头部速度低于静止阈值的时间戳 (A_TickCount)。

; 状态标记：这是脚本的核心状态管理变量，用于防止重复触发和控制动作的转换逻辑。
; 0: 中立/空闲状态。此时脚本监听左右转动作。
; 1: 已触发左转状态。此时脚本只监听回中动作。
; 2: 已触发右转状态。此时脚本只监听回中动作。
axis_state := 0

; 其他阈值：
axisU_th := 45 ; 仰俯轴 (JoyU) 的低头阈值。当头部低于此阈值时（例如，低头看键盘），
               ; 将阻止左右转和回中动作，避免误触。
V_speed := 0.55 ; 转头速度阈值。头部移动速度必须高于此值才能触发左右转和回中动作。
                ; 这有助于区分有意的快速转头和无意的缓慢晃动。

; 转头检测速度的滑动窗口数组。用于 `window_r` 函数计算瞬时速度。
window := []

; --- 函数：计算瞬时速度 ---
; window_r(l, v, w)
; 参数:
;   l: 当前窗口数组的长度。
;   v: 当前的摇杆轴位置值。
;   w: 存储历史摇杆轴位置的窗口数组。
; 返回: 基于窗口内最大值和最小值的航向瞬时速度。
;       此速度与采样率负相关，采样率越高，计算出的速度值越小。
window_r(l, v, w) {
    ; 在 AutoHotkey v2 中，数组索引是 1-based。
    ; 维护一个包含最近5次采样数据的滑动窗口。
    if (l < 5) { ; 如果窗口未满5个数据点，则直接添加。
        w.Push(v)
    } Else { ; 如果窗口已满，移除最旧的数据点 (索引 1)，然后添加新的数据点。
        w.RemoveAt(1)
        w.Push(v)
    }

    ; 确保窗口不为空，避免计算错误。
    if (w.Length = 0) {
        Return 0
    }

    ; 计算窗口内位置的最大值和最小值。
    w_max := Max(w*)
    w_min := Min(w*)

    ; 计算速度：窗口内的位置变化范围除以窗口大小。
    ; 较大的 k 值表示更快的头部移动。
    k := (w_max-w_min)/w.Length

    ; ToolTip(k) ; 调试用，取消注释可在屏幕上显示实时速度值。
    Return k
}

; --- 初始化脚本 ---
; 脚本启动时执行一次，用于设置初始状态。

Sleep 500 ; 延迟一小段时间，让头部追踪器有时间稳定并发送初始数据。
; 读取当前头部位置作为初始中立点。
neutral_axisV := GetKeyState(JoystickNumber . TargetAxis)
neutral_axisX := GetKeyState(JoystickNumber . TargetAxis3)
; Tooltip("初始中立位置 V:" neutral_axisV " X:" neutral_axisX, , , 2) ; 调试用，显示初始中立点。

; --- 主循环：持续监控手柄状态并触发动作 ---
Loop
{
    ; 1. 获取当前头部追踪器（手柄）的轴位置。
    current_axisV_position := GetKeyState(JoystickNumber . TargetAxis)   ; 航向 (Yaw)
    current_axisU_position := GetKeyState(JoystickNumber . TargetAxis2)  ; 仰俯 (Pitch)
    current_axisX_position := GetKeyState(JoystickNumber . TargetAxis3)  ; 滚转 (Roll)
    current_axisZ_position := GetKeyState(JoystickNumber . TargetAxis4)  ; Z轴 (用于重置)

    ; 2. 计算当前航向的瞬时速度。
    current_w_speed := window_r(window.Length, current_axisV_position, window)

    ; --- 动态更新中立位置逻辑 ---
    ; 只有当头部静止且处于“中立”状态时，才允许更新中立点，防止中立点漂移到侧边窗口。
    if (current_w_speed < Stillness_Speed_Threshold) { ; 如果头部速度低于静止阈值
        if (last_still_time = 0) { ; 如果是刚进入静止状态，记录当前时间戳。
            last_still_time := A_TickCount
        }
        ; 如果头部静止时间超过设定持续时间，并且当前处于中立状态 (axis_state == 0)，则更新中立点。
        if (A_TickCount - last_still_time >= Stillness_Duration_ms && axis_state == 0) {
            neutral_axisV := current_axisV_position ; 更新航向中立点。
            neutral_axisX := current_axisX_position ; 更新滚转中立点。
            ; Tooltip("中立位置更新 V:" neutral_axisV " X:" neutral_axisX, , , 2) ; 调试用。
        }
    } Else { ; 如果头部速度高于静止阈值，重置静止计时器。
        last_still_time := 0
    }

    ; --- 检测位置变化并触发动作 ---
    ; 仅当任何一个轴的位置发生变化时才进行后续的动作判断，以减少不必要的计算。
    if (current_axisV_position != prev_axisV_position || current_axisU_position != prev_axisU_position || prev_axisX_position != current_axisX_position || prev_axisZ_position != current_axisZ_position)
    {
        ; 3. 计算基于当前中立点的动态边界。
        yaw_left_trigger_boundary := neutral_axisV - Yaw_Trigger_Threshold   ; 左转触发点
        yaw_right_trigger_boundary := neutral_axisV + Yaw_Trigger_Threshold  ; 右转触发点
        yaw_center_min_boundary := neutral_axisV - Yaw_Deadzone_HalfWidth    ; 中立死区左边界
        yaw_center_max_boundary := neutral_axisV + Yaw_Deadzone_HalfWidth    ; 中立死区右边界
        roll_min_boundary := neutral_axisX - Roll_Deadzone_HalfWidth         ; 滚转允许范围下限
        roll_max_boundary := neutral_axisX + Roll_Deadzone_HalfWidth         ; 滚转允许范围上限

        ; Tooltip("V:" current_axisV_position " U:" current_axisU_position " X:" current_axisX_position " Z:" current_axisZ_position " Speed:" current_w_speed "`nNeutral V:" neutral_axisV " X:" neutral_axisX "`nState:" axis_state, , , 1) ; 调试用，显示所有关键数据和当前状态。
        ; Tooltip( "Speed:" current_w_speed "`nNeutral V:" neutral_axisV " X:" neutral_axisX "`nState:" axis_state, , , 1)
        ; 4. 根据当前状态和头部姿态/速度判断并触发动作。
        ; 首先检查头部是否在允许的仰俯和滚转范围内。这是所有航向动作的前提条件。
        if (current_axisU_position > axisU_th && current_axisX_position > roll_min_boundary && current_axisX_position < roll_max_boundary) {

            ; 根据当前的 `axis_state` (状态标记) 来决定检查哪些动作。
            ; 这种状态机逻辑确保了动作的顺序性和防止误触。
            if (axis_state == 0) { ; 当前处于“中立/空闲”状态
                ; 检测左转动作：头部位置在左侧触发边界内，且转头速度足够快。
                if (current_axisV_position <= yaw_left_trigger_boundary && current_w_speed > V_speed) {
                    Send '{LWin down}{1}{LWin up}' ; 发送 Win+1 (切换到左侧窗口)
                    axis_state := 1 ; 切换到“已触发左转”状态。
                    ; Tooltip("触发左转 Win+1", , , 3) ; 调试用。
                }
                ; 检测右转动作：头部位置在右侧触发边界外，且转头速度足够快。
                else if (current_axisV_position >= yaw_right_trigger_boundary && current_w_speed > V_speed) {
                    Send '{LWin down}{2}{LWin up}' ; 发送 Win+2 (切换到右侧窗口)
                    axis_state := 2 ; 切换到“已触发右转”状态。
                    ; Tooltip("触发右转 Win+2", , , 3) ; 调试用。
                }
                ; 如果在中立状态，但未满足左右转条件，则保持中立状态。
            }
            else if (axis_state == 1) { ; 当前处于“已触发左转”状态
                ; 此时只检测回中动作：头部位置回到中立死区内，且回中速度足够快。
                if (current_axisV_position > yaw_center_min_boundary && current_axisV_position < yaw_center_max_boundary && current_w_speed > V_speed) {
                    Send '{LWin down}{3}{LWin up}' ; 发送 Win+3 (切换回中立窗口)
                    axis_state := 0 ; 切换回“中立/空闲”状态。
                    ; Tooltip("触发回中 Win+3", , , 3) ; 调试用。
                }
                ; 如果在左转状态，但未满足回中条件，则保持左转状态。
            }
            else if (axis_state == 2) { ; 当前处于“已触发右转”状态
                ; 此时只检测回中动作：头部位置回到中立死区内，且回中速度足够快。
                if (current_axisV_position > yaw_center_min_boundary && current_axisV_position < yaw_center_max_boundary && current_w_speed > V_speed) {
                    Send '{LWin down}{3}{LWin up}' ; 发送 Win+3 (切换回中立窗口)
                    axis_state := 0 ; 切换回“中立/空闲”状态。
                    ; Tooltip("触发回中 Win+3", , , 3) ; 调试用。
                }
                ; 如果在右转状态，但未满足回中条件，则保持右转状态。
            }
            ; else 块 (注释掉): 在允许的范围内，但没有触发特定动作。
            ; Tooltip("在允许范围内，无动作", , , 3) ; 调试用。
        }
        ; else 块 (注释掉): 不在允许的仰俯或滚转范围内。
        ; Tooltip("不在允许的仰俯/滚转范围内", , , 3) ; 调试用。
        ; 注意：当头部移出允许范围时，当前状态保持不变，只是动作被阻止。

        ; 5. 检测 Z 轴重置动作。
        ; 此动作独立于航向/仰俯/滚转的切换逻辑，但仍受仰俯阈值限制，防止低头时误触。
        ; if ((current_axisZ_position > 65 || current_axisZ_position < 45) && current_axisU_position > axisU_th && current_axisU_position < 70) {
        ;     Send '^+/' ; 发送 Ctrl+Shift+/ (通常用于重置头部追踪器视角)
        ;     axis_state := 0 ; 重置脚本状态为中立，确保下次动作从头开始判断。
        ;     ; Tooltip("触发 Z 轴重置", , , 3) ; 调试用。
        ; }

        ; 6. 更新上一次的位置为当前位置，为下一次循环做准备。
        prev_axisV_position := current_axisV_position
        prev_axisU_position := current_axisU_position
        prev_axisX_position := current_axisX_position
        prev_axisZ_position := current_axisZ_position
    } else {
        ; 如果所有轴的位置都没有变化，则不执行动作判断，节省CPU资源。
    }

    ; 7. 暂停一小段时间，避免占用过多 CPU 资源。
    Sleep PollingInterval
}

; --- 脚本控制热键 (可选) ---
; 这些热键提供了一种手动控制脚本运行和追踪器重置的方式。

; 按下 Ctrl+Shift+Z 键：暂停/恢复脚本，并发送追踪器重置命令。
^+z::
{
    Pause -1 ; 切换脚本的暂停状态 (如果暂停则恢复，如果运行则暂停)。
    Send '^+/' ; 发送 Ctrl+Shift+/ 命令，通常用于重置头部追踪器视角。
    axis_state := 0 ; 将脚本内部状态重置为中立。
    ; Tooltip("脚本暂停/恢复并重置追踪器", , , 3) ; 调试用。
    Return
}

; 按下 Ctrl+Shift+K 键：退出脚本。
^+k::
{
    ; 退出前隐藏所有调试用的 Tooltip，保持桌面整洁。
    Tooltip('', , , 1)
    Tooltip('', , , 2)
    Tooltip('', , , 3)
    ExitApp ; 退出 AutoHotkey 脚本。
    Return
}
