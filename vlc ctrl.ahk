#Persistent         ; 让脚本持续运行
#SingleInstance force ; 防止重复运行脚本

; --- 配置 ---
JoystickNumber = 2  ; 你的手柄编号 (通常是 1)
TargetAxis = JoyR   ; 你想监控的摇杆轴 (例如 JoyX, JoyY, JoyZ, JoyR, POV)
TargetAxis2 = JoyZ 
PollingInterval = 300 ; 轮询间隔，单位毫秒 (例如 20ms 意味着每秒检查 50 次)

; --- 变量 ---
; 存储目标摇杆轴的上一次位置
prev_axisV_position := ""
prev_axisU_position := ""
axis_temp=50
axisU_th=45
; --- 主循环：持续检查手柄状态 ---
Loop
{
    ; 获取当前目标摇杆轴的位置
    ; GetKeyState, OutputVar, KeyName
    ; KeyName 是 JoystickNumber + TargetAxis (例如 "1JoyX")
    GetKeyState, current_axisV_position, %JoystickNumber%%TargetAxis%
    GetKeyState, current_axisU_position, %JoystickNumber%%TargetAxis2%
    ; --- 检测位置变化 ---
    ; 如果当前位置与上一次位置不同
    if (current_axisV_position != prev_axisV_position || current_axisU_position != prev_axisU_position)
    {
        ; --- 位置变化时执行的操作 ---
        ; 示例：显示一个 Tooltip 显示当前位置
        ; Tooltip, Text [, X, Y, WhichTooltip]
         Tooltip, %TargetAxis% 位置: %current_axisV_position% %current_axisU_position% axis_temp:%axis_temp%, , , 1 ; Tooltip ID 1

        ; 你可以在这里根据 current_axis_position 的值执行不同的操作
        ; 例如：
             if (current_axisV_position <= 48 ) {
           Send, {LCtrl down}{LAlt down}{LEFT}{LCtrl up}{LAlt up} ; 如果摇杆向左移动超过阈值，发送左箭头键
           axis_temp=40
         } else if (current_axisV_position >= 51 ) {
            Send,{LCtrl down}{LAlt down}{RIGHT}{LCtrl up}{LAlt up} ; 如果摇杆向右移动超过阈值，发送右箭头键
             axis_temp=60
         }else {

         }


        ; 更新上一次的位置为当前位置
        prev_axisV_position := current_axisV_position
        prev_axisU_position := current_axisU_position
    }

    ; 暂停一小段时间，避免占用过多 CPU
    Sleep, %PollingInterval%
}

; --- 退出脚本的热键 (可选) ---
; 按下 Esc 键退出脚本
Esc::
    ; 退出前隐藏 Tooltip
    Tooltip, , , 1
    ExitApp
return
