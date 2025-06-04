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
window := [] ; 转头检测速度的一个窗口数组

; --- 变量 ---
; 存储目标摇杆轴的上一次位置
prev_axisV_position := ''
prev_axisU_position := ''
prev_axisX_position := ''
prev_axisZ_position := ''
prev_w := ''
axis_temp := 50 ; 设置一个标记，防止重复触发导致连键
axisU_th := 45 ; 低头的阈值，看键盘的时候不触发。
l_act := 47
r_act := 53
x_l_edge := 42 ; X轴左右边界
X_r_edge := 58
flag_ot_reset := 0 ; opentrack复位标志 (在主循环中被注释掉了)
V_speed := 0.55 ; 转头速度阈值

; --- 函数：计算速度 ---
window_r(l, v, w) { ; 返回一个速度转头瞬时速度 和采样率负相关，采样越高这个值越小
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
    w_min := Min(w*) ; 初始最小值 (使用 v_min 避免与参数 v 冲突)

    ; 在 v2 中，for 循环遍历对象/数组的语法不变
    ; for index, value in w {
    ;     if (value > 50) {
    ;         u := value
    ;     } else if (value < 50) {
    ;         v_min := value
    ;     }
    ; }

    ; 在 v2 中，Length 是属性，不是方法 Length()
    k := (w_max-w_min)/w.Length ; 范围内找最值，并计算速度。

    ; MsgBox "u: " u ", v_min: " v_min ; v2 MsgBox 语法
    ToolTip(k)
    Return k
}

; --- 主循环：持续检查手柄状态 ---
Loop
{
    ; 获取当前目标摇杆轴的位置
    ; GetKeyState 在 v2 中是函数调用，参数顺序不同
    current_axisV_position := GetKeyState(JoystickNumber . TargetAxis)
    current_axisU_position := GetKeyState(JoystickNumber . TargetAxis2)
    current_axisX_position := GetKeyState(JoystickNumber . TargetAxis3)
    current_axisZ_position := GetKeyState(JoystickNumber . TargetAxis4)

    ; 在 v2 中，Length 是属性
    current_w_speed := window_r(window.Length, current_axisV_position, window)

    ; --- 检测位置变化 ---
    ; 如果当前位置与上一次位置不同
    ; 在 v2 中，if 条件必须用括号 () 包围
    if (current_axisV_position != prev_axisV_position || current_axisU_position != prev_axisU_position || prev_axisX_position != current_axisX_position || prev_axisZ_position != current_axisZ_position)
    {
        flag_ot_reset := 0

        ; --- 位置变化时执行的操作 ---
        ; 示例：显示一个 Tooltip 显示当前位置 (v2 Tooltip 是函数调用)
        ; Tooltip(Text, X?, Y?, WhichTooltip?)
        ; Tooltip(TargetAxis " 位置: V:" current_axisV_position " U:" current_axisU_position " X:" current_axisX_position " Z:" current_axisZ_position " W:" current_w_speed, , , 1) ; Tooltip ID 1

        ; 你可以在这里根据 current_axis_position 的值执行不同的操作
        ; 例如：
        ; 在 v2 中，if/else if 条件必须用括号 () 包围
        if (axis_temp > 40 && current_axisV_position <= l_act && current_axisU_position > axisU_th && current_axisX_position > x_l_edge && current_axisX_position < X_r_edge && current_w_speed > V_speed ) {
            Send '{LWin down}{1}{LWin up}' ; 如果摇杆向左移动超过阈值，发送左箭头键 (v2 Send 参数用单引号)
            ; MouseMove 800, 1000, 0 ; v2 命令语法
            axis_temp := 40
        } else if (current_axisV_position >= r_act && axis_temp < 60 && current_axisU_position > axisU_th && current_axisX_position > x_l_edge && current_w_speed > V_speed) {
            Send '{LWin down}{2}{LWin up}' ; 如果摇杆向右移动超过阈值，发送右箭头键
            ; MouseMove 800, 1000, 0
            axis_temp := 60
        } else if (current_axisV_position > 46 && current_axisV_position < 53 && axis_temp != 50 && current_axisU_position > axisU_th && current_w_speed > V_speed) {
            ; 摇杆回到中心附近
            axis_temp := 50
            Send '{LWin down}{3}{LWin up}'
            ; MouseMove 800, 1000, 0
        } else if ((current_axisZ_position > 65 || current_axisZ_position < 45) && current_axisU_position > axisU_th && current_axisU_position < 70) {
            ; sleep 500 ; v2 命令语法
            Send '^+/' ; 发送 Ctrl+Shift+/
            axis_temp := 50
            ; Send '{LWin down}{3}{LWin up}'
        } else {
            ; 没有满足条件的动作
        }

        ; 更新上一次的位置为当前位置
        prev_axisV_position := current_axisV_position
        prev_axisU_position := current_axisU_position
        prev_axisX_position := current_axisX_position
        prev_axisZ_position := current_axisZ_position
    } else {
        ; flag_ot_reset:=1
        ; Sleep 500 ; v2 命令语法
        ; Send '^+/' ; v2 Send 参数用单引号
        ; 位置没有变化
    }

    ; 注释掉的 OpenTrack 复位逻辑
    ; if(flag_ot_reset=0){
    ;    flag_ot_reset=1
    ;    Sleep 500 ; v2 命令语法
    ;    Send '^+/' ; v2 Send 参数用单引号
    ; }

    ; 暂停一小段时间，避免占用过多 CPU (v2 Sleep 是命令)
    Sleep PollingInterval
}

; --- 退出脚本的热键 (可选) ---
; 按下 Ctrl+Shift+Z 键暂停脚本并发送复位
^+z::
{   Pause -1
    Send '^+/' ; v2 Send 参数用单引号
Return
}
; 按下 Ctrl+Shift+K 键退出脚本
^+k::
{    ; 退出前隐藏 Tooltip (v2 Tooltip 是函数调用)
    Tooltip('', , , 1) ; 发送空字符串清除 Tooltip
    ExitApp
Return
}