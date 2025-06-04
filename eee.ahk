#Requires AutoHotkey v2.0

; AutoHotkey v2 Script
#SingleInstance Force ; 防止重复运行脚本

; --- 配置 ---
JoystickNumber := 2  ; 你的手柄编号 (通常是 1)
TargetAxis := 'JoyV'   ; 航向你想监控的摇杆轴 (例如 JoyX, JoyY, JoyZ, JoyR, POV)
TargetAxis2 := 'JoyU' ; 仰俯
TargetAxis3 := 'JoyX' ; 滚转
TargetAxis4 := 'JoyZ' ; 使用z轴进行重置
PollingInterval := 20 ; 轮询间隔，单位毫秒 (例如 20ms 意味着每秒检查 50 次)

; --- 动态窗口配置 ---
Stillness_Speed_Threshold := 0.1 ; 判定头部“静止”的速度阈值 (低于此值认为静止)
Stillness_Duration_ms := 500   ; 头部需要保持静止的时间 (毫秒) 来更新中立位置
Yaw_Trigger_Threshold := 8     ; 航向轴 (JoyV) 偏离中立位置多少触发左右转 (例如，中立是50，阈值是8，则 <42 触发左，>58 触发右)
Yaw_Deadzone_HalfWidth := 3    ; 航向轴 (JoyV) 中立位置周围的死区半宽 (例如，中立是50，死区半宽是3，则 47-53 是死区)
Roll_Deadzone_HalfWidth := 10  ; 滚转轴 (JoyX) 中立位置周围的死区半宽 (用于检查是否在允许的滚转范围内)

; --- 变量 ---
; 存储目标摇杆轴的上一次位置
prev_axisV_position := ''
prev_axisU_position := ''
prev_axisX_position := ''
prev_axisZ_position := ''

; 动态中立位置
neutral_axisV := 50 ; 初始中立航向位置
neutral_axisX := 50 ; 初始中立滚转位置

; 静止检测变量
last_still_time := 0 ; 上次速度低于静止阈值的时间戳

; 状态标记，防止重复触发和控制状态转换
; 0: 中立/空闲
; 1: 已触发左转
; 2: 已触发右转
axis_state := 0

; 其他阈值 (保持不变或根据需要调整)
axisU_th := 45 ; 低头的阈值，看键盘的时候不触发。
V_speed := 0.55 ; 转头速度阈值 (用于触发动作，包括左右转和回中)

; 转头检测速度的一个窗口数组 (用于 window_r 函数)
window := []

; --- 函数：计算速度 ---
; 返回一个速度转头瞬时速度 和采样率负相关，采样越高这个值越小
window_r(l, v, w) {
    ; 在 v2 中，数组索引是 1-based
    if (l < 5) { ; 取一个5次采样的窗口作为计算速度的范围
        w.Push(v)
    } Else {
        w.RemoveAt(1) ; 移除第一个元素 (索引 1)
        w.Push(v)
    }

    ; 确保窗口不为空
    if (w.Length = 0) {
        Return 0
    }

    w_max := Max(w*) ; 初始最大值
    w_min := Min(w*) ; 初始最小值

    ; 在 v2 中，Length 是属性
    k := (w_max-w_min)/w.Length ; 范围内找最值，并计算速度。

    ; ToolTip(k) ; 调试用，显示速度
    Return k
}

; --- 初始化：读取初始中立位置 ---
; 延迟一小段时间，让追踪器稳定
Sleep 500
; 读取当前位置作为初始中立位置
neutral_axisV := GetKeyState(JoystickNumber . TargetAxis)
neutral_axisX := GetKeyState(JoystickNumber . TargetAxis3)
; Tooltip("初始中立位置 V:" neutral_axisV " X:" neutral_axisX, , , 2) ; 调试用

; --- 主循环：持续检查手柄状态 ---
Loop
{
    ; 获取当前目标摇杆轴的位置
    current_axisV_position := GetKeyState(JoystickNumber . TargetAxis)
    current_axisU_position := GetKeyState(JoystickNumber . TargetAxis2)
    current_axisX_position := GetKeyState(JoystickNumber . TargetAxis3)
    current_axisZ_position := GetKeyState(JoystickNumber . TargetAxis4)

    ; 计算航向速度
    current_w_speed := window_r(window.Length, current_axisV_position, window)

    ; --- 动态更新中立位置 ---
    ; 如果航向速度低于静止阈值
    if (current_w_speed < Stillness_Speed_Threshold) {
        ; 如果是刚进入静止状态，记录时间
        if (last_still_time = 0) {
            last_still_time := A_TickCount
        }
        ; 如果静止时间超过设定的持续时间
        if (A_TickCount - last_still_time >= Stillness_Duration_ms) {
            ; 更新中立位置为当前位置
            neutral_axisV := current_axisV_position
            neutral_axisX := current_axisX_position
            ; Tooltip("中立位置更新 V:" neutral_axisV " X:" neutral_axisX, , , 2) ; 调试用
        }
    } Else {
        ; 如果速度高于静止阈值，重置静止计时器
        last_still_time := 0
    }

    ; --- 检测位置变化并触发动作 ---
    ; 只有当任何一个轴的位置发生变化时才进行判断，减少不必要的计算
    if (current_axisV_position != prev_axisV_position || current_axisU_position != prev_axisU_position || prev_axisX_position != current_axisX_position || prev_axisZ_position != current_axisZ_position)
    {
        ; 计算动态边界
        yaw_left_trigger_boundary := neutral_axisV - Yaw_Trigger_Threshold
        yaw_right_trigger_boundary := neutral_axisV + Yaw_Trigger_Threshold
        yaw_center_min_boundary := neutral_axisV - Yaw_Deadzone_HalfWidth
        yaw_center_max_boundary := neutral_axisV + Yaw_Deadzone_HalfWidth
        roll_min_boundary := neutral_axisX - Roll_Deadzone_HalfWidth
        roll_max_boundary := neutral_axisX + Roll_Deadzone_HalfWidth

        ;Tooltip("V:" current_axisV_position " U:" current_axisU_position " X:" current_axisX_position " Z:" current_axisZ_position " Speed:" current_w_speed "`nNeutral V:" neutral_axisV " X:" neutral_axisX "`nState:" axis_state, , , 1) ; 调试用

        ; --- 根据当前状态和位置/速度判断动作 ---
        ; 检查是否在允许的仰俯和滚转范围内 (这是所有 V/X/U 动作的前提)
        if (current_axisU_position > axisU_th && current_axisX_position > roll_min_boundary && current_axisX_position < roll_max_boundary) {

            ; 根据当前状态决定检查哪些转换
            if (axis_state == 0) { ; 当前是中立状态，只检查是否触发左转或右转
                ; 检测左转动作
                if (current_axisV_position <= yaw_left_trigger_boundary && current_w_speed > V_speed) {
                    Send '{LWin down}{1}{LWin up}' ; 发送 Win+1
                    axis_state := 1 ; 切换到左转状态
                    ; Tooltip("触发左转 Win+1", , , 3) ; 调试用
                }
                ; 检测右转动作
                else if (current_axisV_position >= yaw_right_trigger_boundary && current_w_speed > V_speed) {
                    Send '{LWin down}{2}{LWin up}' ; 发送 Win+2
                    axis_state := 2 ; 切换到右转状态
                    ; Tooltip("触发右转 Win+2", , , 3) ; 调试用
                }
                ; else: 如果不在中立状态且不满足左右转条件，保持中立状态
            }
            else if (axis_state == 1) { ; 当前是左转状态，只检查是否触发回中
                ; 检测回中动作 (从左转状态回到中立死区，且速度够快)
                if (current_axisV_position > yaw_center_min_boundary && current_axisV_position < yaw_center_max_boundary && current_w_speed > V_speed) {
                    Send '{LWin down}{3}{LWin up}' ; 发送 Win+3
                    axis_state := 0 ; 切换回中立状态
                    ; Tooltip("触发回中 Win+3", , , 3) ; 调试用
                }
                ; else: 如果在左转状态且不满足回中条件，保持左转状态
            }
            else if (axis_state == 2) { ; 当前是右转状态，只检查是否触发回中
                ; 检测回中动作 (从右转状态回到中立死区，且速度够快)
                if (current_axisV_position > yaw_center_min_boundary && current_axisV_position < yaw_center_max_boundary && current_w_speed > V_speed) {
                    Send '{LWin down}{3}{LWin up}' ; 发送 Win+3
                    axis_state := 0 ; 切换回中立状态
                    ; Tooltip("触发回中 Win+3", , , 3) ; 调试用
                }
                ; else: 如果在右转状态且不满足回中条件，保持右转状态
            }
            ; else {
            ;     ; 在允许的范围内，但没有触发特定动作 (根据当前状态决定)
            ;     ; Tooltip("在允许范围内，无动作", , , 3) ; 调试用
            ; }
        }
        ; else {
        ;     ; 不在允许的仰俯或滚转范围内
        ;     ; Tooltip("不在允许的仰俯/滚转范围内", , , 3) ; 调试用
        ;     ; 注意：当头部移出允许范围时，状态保持不变，只是动作被阻止。
        ; }

        ; 检测 Z 轴重置动作 (不受仰俯/滚转范围限制，但可以根据需要添加)
        ; 保持原有的 Z 轴触发逻辑
        if ((current_axisZ_position > 65 || current_axisZ_position < 45) && current_axisU_position > axisU_th && current_axisU_position < 70) {
            Send '^+/' ; 发送 Ctrl+Shift+/
            axis_state := 0 ; 重置状态为中立
            ; Tooltip("触发 Z 轴重置", , , 3) ; 调试用
        }


        ; 更新上一次的位置为当前位置
        prev_axisV_position := current_axisV_position
        prev_axisU_position := current_axisU_position
        prev_axisX_position := current_axisX_position
        prev_axisZ_position := current_axisZ_position
    } else {
        ; 位置没有变化，不执行动作判断
    }

    ; 暂停一小段时间，避免占用过多 CPU
    Sleep PollingInterval
}

; --- 退出脚本的热键 (可选) ---
; 按下 Ctrl+Shift+Z 键暂停脚本并发送复位
^+z::
{
    Pause -1
    Send '^+/' ; 发送 Ctrl+Shift+/
    axis_state := 0 ; 重置状态
    ; Tooltip("脚本暂停/恢复并重置追踪器", , , 3) ; 调试用
    Return
}
; 按下 Ctrl+Shift+K 键退出脚本
^+k::
{
    ; 退出前隐藏 Tooltip
    Tooltip('', , , 1)
    Tooltip('', , , 2)
    Tooltip('', , , 3)
    ExitApp
    Return
}
