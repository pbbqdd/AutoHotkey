#Persistent         ; 让脚本持续运行
#SingleInstance force ; 防止重复运行脚本
; --- 配置 ---
JoystickNumber = 2  ; 你的手柄编号 (通常是 1)
TargetAxis = JoyV   ; 航向你想监控的摇杆轴 (例如 JoyX, JoyY, JoyZ, JoyR, POV)
TargetAxis2 = JoyU ;仰俯，
TargetAxis3 = JoyX
TargetAxis4 = JoyZ ;使用z轴进行重置
PollingInterval = 20 ; 轮询间隔，单位毫秒 (例如 20ms 意味着每秒检查 50 次)
window := [] ;转头检测速度的一个窗口数组
;window.SetCapacity(10)

; --- 变量 ---
; 存储目标摇杆轴的上一次位置
prev_axisV_position := ""
prev_axisU_position := ""
prev_axisX_position := ""
prev_axisZ_position := ""
prev_w :=""
axis_temp=50 ;设置一个标记，防止重复触发导致连键
axisU_th=45;低头的阈值，看键盘的时候不触发。
l_act=47
r_act =53
x_l_edge=42;X轴左右边界
X_r_edge=58
flag_ot_reset=0 ;opentrack复位标志
V_speed=0.55 ;转头速度阈值
window_r(l,v,w){ ;返回一个速度转头瞬时速度 和采样率负相关，采样越高这个值越小
    if(l < 5){ ;取一个5次采样的窗口作为计算速度的范围,这个值相对一般使用足够小，人不可能疯狂摇头。
        w.Push(v)
    }Else
    {
        w.RemoveAt(0)
        w.push(v)
    }
    u :=w[0]
    v :=w[0]
    a=0
    for a,b in w {
        if (b>u){
            u := b
        } else if (b < v){
            v := b
        } 
    }
    k := (u-v)/w.Length() ;范围内找最值，并计算速度。

    ; MsgBox, % u v
    Return k
}
; --- 主循环：持续检查手柄状态 ---
Loop
{

    ; 获取当前目标摇杆轴的位置
    ; GetKeyState, OutputVar, KeyName
    ; KeyName 是 JoystickNumber + TargetAxis (例如 "1JoyX")
    GetKeyState, current_axisV_position, %JoystickNumber%%TargetAxis%
    GetKeyState, current_axisU_position, %JoystickNumber%%TargetAxis2%
    GetKeyState, current_axisX_position, %JoystickNumber%%TargetAxis3%
    GetKeyState, current_axisZ_position, %JoystickNumber%%TargetAxis4%
    prev_w :=window_r(window.Length(),current_axisV_position,window)
    
    ; --- 检测位置变化 ---
    ; 如果当前位置与上一次位置不同
    ;if (current_axisZ_position != prev_axisZ_position || current_axisV_position != prev_axisV_position || current_axisU_position != prev_axisU_position || current_axisX_position != prev_axisX_position)
    if (current_axisV_position != prev_axisV_position || current_axisU_position != prev_axisU_position || prev_axisX_position != current_axisX_position || prev_axisZ_position != current_axisZ_position)
    
    {   flag_ot_reset=0
        ; --- 位置变化时执行的操作 ---
        ; 示例：显示一个 Tooltip 显示当前位置
        ; Tooltip, Text [, X, Y, WhichTooltip]
        w:=window_r(window.Length(),current_axisV_position,window)

        ; Tooltip, %TargetAxis% 位置: V:%current_axisV_position% U:%current_axisU_position% X:%current_axisX_position% Z:%current_axisZ_position% W:%w% , , , 1 ; Tooltip ID 1


        ; 你可以在这里根据 current_axis_position 的值执行不同的操作
        ; 例如：
             if ( axis_temp > 40 and current_axisV_position <= l_act && current_axisU_position >axisU_th && current_axisX_position >x_l_edge && current_axisX_position <X_r_edge && w>V_speed) {
           Send, {LWin down}{1}{LWin up} ; 如果摇杆向左移动超过阈值，发送左箭头键
           ;MouseMove, 800, 1000, 0
           axis_temp=40
         } else if (current_axisV_position >= r_act and axis_temp < 60 && current_axisU_position >axisU_th &&  current_axisX_position >x_l_edge && w >V_speed) {
            Send, {LWin down}{2}{LWin up} ; 如果摇杆向右移动超过阈值，发送右箭头键
            ;MouseMove, 800, 1000, 0
             axis_temp=60
         } else if (current_axisV_position > 46 && current_axisV_position < 53 && axis_temp !=50 && current_axisU_position >axisU_th && w > V_speed){
             ; 摇杆回到中心附近,这里设置一个47和53的左右回正补偿，防止看后视镜头部微小扭动。
            axis_temp=50
            Send, {LWin down}{3}{LWin up}
            ;MouseMove, 800, 1000, 0
         } else if ((current_axisZ_position > 65 || current_axisZ_position< 45) && current_axisU_position > axisU_th && current_axisU_position < 70){
            ;sleep 500
            Send,^+/ 
            axis_temp=50
            ;Send, {LWin down}{3}{LWin up}       

         } else {

         }


        ; 更新上一次的位置为当前位置
        prev_axisV_position := current_axisV_position
        prev_axisU_position := current_axisU_position
        prev_axisX_position := current_axisX_position
        prev_axisZ_position := current_axisZ_position
    } else
    {}
    ;  if(flag_ot_reset=0){
    ;     flag_ot_reset=1
    ;     sleep 500 ;加入一个遮脸延迟，防止手臂干扰
    ;     Send,^+/
    ; }

    ; 暂停一小段时间，避免占用过多 CPU
    Sleep, %PollingInterval%
}

; --- 退出脚本的热键 (可选) ---
; 按下 Esc 键退出脚本
^+z::
    Pause
    Send,^+/ ;
return
^+k::
    ; 退出前隐藏 Tooltip
    Tooltip, , , 1
    ExitApp
return
