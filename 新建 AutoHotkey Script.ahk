#Requires AutoHotkey v2.0

; ===============================================================================
; AutoHotkey v2 手柄轴控制脚本 (增强版 - 窗口绑定)
; -------------------------------------------------------------------------------
; 脚本功能：
;   持续读取指定手柄的特定轴 (JoyV, JoyU, JoyX, JoyZ) 的位置。
;   根据 JoyV 轴的位置、变化速度以及 JoyU 和 JoyX 轴的阈值，发送不同的按键组合。
;   JoyZ 轴用于触发一个特定的复位按键。
;   **新增：** 只有当指定的窗口处于活动状态时，上述手柄控制逻辑才生效。
;   包含用于暂停/复位和退出脚本的热键。
;
; 典型应用场景：
;   在游戏中使用手柄模拟头部转动（通过发送按键给头部追踪软件如 OpenTrack），
;   且只在游戏窗口激活时启用此功能。
;
; 注意：
;   请根据你的手柄、游戏/软件和窗口信息配置顶部的参数。
;   轴的位置值通常在 0 到 100 之间。
;   使用 AHK 自带的 Window Spy 工具可以方便地获取窗口的标题、类名和进程名。
; ===============================================================================

#SingleInstance Force ; 防止重复运行脚本

; --- 配置参数 ---
; 请根据你的手柄和需求修改以下参数

JoystickNumber := 2  ; 你的手柄编号 (通常是 1 或 2)。可以在 AHK 的 Help -> Window Spy 中查看。
TargetAxisV := 'JoyV'   ; 主要控制轴 (例如 JoyX, JoyY, JoyZ, JoyR, POV)。脚本用此轴检测左右转动和速度。
TargetAxisU := 'JoyU' ; 辅助轴，用作启用主控制轴动作的阈值 (例如，用于检测是否低头)。
TargetAxisX := 'JoyX' ; 辅助轴，用作启用主控制轴动作的阈值 (例如，用于检测是否头部倾斜)。
TargetAxisZ := 'JoyZ' ; 用于触发复位动作的轴。

PollingInterval := 20 ; 轮询间隔，单位毫秒 (例如 20ms 意味着每秒检查 50 次)。较低的值响应更快但可能占用更多 CPU。

; --- 目标窗口配置 ---
; 脚本只在以下指定的窗口处于活动状态时才工作。
; 你可以使用窗口标题、类名或进程名来指定窗口。
; 推荐使用标题或类名，如果它们是唯一的。如果标题或类名不稳定，可以使用进程名。
; **请只填写你需要用来匹配的那个字段，其他字段留空。**
; 例如，如果你想匹配标题为 "Microsoft Flight Simulator" 的窗口，就只填写 TargetWindowTitle。
TargetWindowTitle := "" ; 目标窗口的完整或部分标题 (留空则不按标题匹配)
TargetWindowClass := "" ; 目标窗口的类名 (留空则不按类名匹配)
TargetWindowProcessName := "" ; 目标窗口的进程名 (例如 "FlightSimulator.exe") (留空则不按进程名匹配)

; --- 轴阈值配置 ---
; JoyV 轴的阈值 (通常中心是 50)
JoyV_Left_Threshold := 47 ; JoyV 小于等于此值时视为向左
JoyV_Right_Threshold := 53 ; JoyV 大于等于此值时视为向右
JoyV_Center_Min := 46    ; JoyV 在此范围 (Min 到 Max) 内视为中心附近
JoyV_Center_Max := 53

; JoyU 轴的阈值 (用于启用 JoyV 动作)
JoyU_Enable_Threshold := 45 ; JoyU 大于此值时才启用 JoyV 相关的动作 (例如，防止低头时触发)
JoyU_Disable_Max := 70 ; JoyU 小于此值时才启用 JoyZ 相关的动作 (例如，防止抬头时触发)

; JoyX 轴的阈值 (用于启用 JoyV 动作)
JoyX_Enable_Min := 42 ; JoyX 大于此值时才启用 JoyV 相关的动作 (例如，防止头部向左倾斜时触发)
JoyX_Enable_Max := 58 ; JoyX 小于此值时才启用 JoyX 相关的动作 (例如，防止头部向右倾斜时触发)

; JoyZ 轴的阈值 (用于触发复位动作)
JoyZ_Reset_Min := 45 ; JoyZ 小于此值时触发复位
JoyZ_Reset_Max := 65 ; JoyZ 大于此值时触发复位

JoyV_Speed_Threshold := 0.55 ; JoyV 轴变化速度阈值。速度高于此值时才触发 JoyV 相关的动作。

; --- 发送的按键配置 ---
Key_Turn_Left := '{LWin down}{1}{LWin up}' ; JoyV 向左时发送的按键 (例如，模拟向左转头)
Key_Turn_Right := '{LWin down}{2}{LWin up}' ; JoyV 向右时发送的按键 (例如，模拟向右转头)
Key_Turn_Center := '{LWin down}{3}{LWin up}' ; JoyV 回到中心时发送的按键 (例如，模拟回中)
Key_Reset_View := '^+/' ; JoyZ 触发时发送的按键 (例如，OpenTrack 复位)

; --- 内部变量 ---
; 存储 JoyV 轴最近几次采样的位置，用于计算速度
JoyV_Position_Window := []
Window_Size := 5 ; 用于计算速度的采样窗口大小

; 状态标记，用于防止 JoyV 动作重复触发 (40: 左, 50: 中, 60: 右)
JoyV_Action_State := 50

; --- 函数：计算 JoyV 轴在最近窗口内的位置范围 (作为速度的近似) ---
; 参数:
;   current_value: 当前 JoyV 轴的位置
;   window_array: 存储最近 JoyV 位置的数组
;   window_size: 窗口的最大大小
; 返回:
;   最近窗口内 JoyV 位置的最大值与最小值之差除以窗口大小。
;   这个值越大，表示在最近的采样中 JoyV 轴变化越剧烈。
CalculateJoyVRangeSpeed(current_value, window_array, window_size) {
    ; 在 v2 中，数组索引是 1-based
    ; 维护滑动窗口
    if (window_array.Length < window_size) {
        window_array.Push(current_value)
    } Else {
        window_array.RemoveAt(1) ; 移除最旧的元素 (索引 1)
        window_array.Push(current_value) ; 添加最新的元素
    }

    ; 如果窗口未满，无法计算范围，返回 0
    if (window_array.Length < window_size) {
        Return 0
    }

    ; 找到窗口内的最大值和最小值
    maxValue := window_array[1]
    minValue := window_array[1]

    for index, value in window_array {
        if (value > maxValue) {
            maxValue := value
        } else if (value < minValue) {
            minValue := value
        }
    }

    ; 计算范围并除以窗口大小作为速度的近似
    Return (maxValue - minValue) / window_size
}

; --- 函数：检查当前活动窗口是否匹配目标窗口配置 ---
; 返回: True 如果匹配，False 如果不匹配
IsTargetWindowActive() {
    ; 获取当前活动窗口的标题、类名和进程名
    active_window_title := WinGetTitle("A")
    active_window_class := WinGetClass("A")
    active_window_process := WinGetProcessName("A")

    ; 如果没有配置任何目标窗口信息，则始终返回 True (即不进行窗口绑定)
    if (TargetWindowTitle == "" && TargetWindowClass == "" && TargetWindowProcessName == "") {
        Return True
    }

    ; 检查标题匹配 (如果配置了 TargetWindowTitle)
    if (TargetWindowTitle != "") {
        ; StringInStr 检查 TargetWindowTitle 是否包含在 active_window_title 中 (更灵活)
        ; 或者使用 active_window_title == TargetWindowTitle 进行精确匹配
        if (InStr(active_window_title, TargetWindowTitle)) {
            Return True
        }
    }

    ; 检查类名匹配 (如果配置了 TargetWindowClass)
    if (TargetWindowClass != "") {
        if (active_window_class == TargetWindowClass) {
            Return True
        }
    }

    ; 检查进程名匹配 (如果配置了 TargetWindowProcessName)
    if (TargetWindowProcessName != "") {
        if (active_window_process == TargetWindowProcessName) {
            Return True
        }
    }

    ; 如果配置了目标窗口信息，但当前活动窗口不匹配任何一个，则返回 False
    Return False
}


; --- 主循环：持续检查手柄状态和窗口状态 ---
Loop
{
    ; 获取当前目标摇杆轴的位置
    current_axisV_position := GetKeyState(JoystickNumber . TargetAxisV)
    current_axisU_position := GetKeyState(JoystickNumber . TargetAxisU)
    current_axisX_position := GetKeyState(JoystickNumber . TargetAxisX)
    current_axisZ_position := GetKeyState(JoystickNumber . TargetAxisZ)

    ; 计算 JoyV 轴的当前速度 (基于最近的采样窗口)
    current_JoyV_speed := CalculateJoyVRangeSpeed(current_axisV_position, JoyV_Position_Window, Window_Size)

    ; --- 检查目标窗口是否活动 ---
    if (IsTargetWindowActive())
    {
        ; --- 目标窗口是活动的，执行手柄控制逻辑 ---

        ; --- 调试信息 (可选，取消注释可显示当前轴位置、速度和窗口状态) ---
        ; Tooltip("V:" current_axisV_position " U:" current_axisU_position " X:" current_axisX_position " Z:" current_axisZ_position " Speed:" Format("{:.2f}", current_JoyV_speed) "`nWindow: Active", , , 1) ; Tooltip ID 1

        ; --- 根据轴位置、阈值和速度判断要执行的动作 ---

        ; 检查是否满足启用 JoyV 动作的条件 (JoyU 和 JoyX 在指定范围内，且 JoyV 速度高于阈值)
        if (current_axisU_position > JoyU_Enable_Threshold && current_axisX_position > JoyX_Enable_Min && current_axisX_position < JoyX_Enable_Max && current_JoyV_speed > JoyV_Speed_Threshold)
        {
            ; 检查 JoyV 轴的左右和中心状态，并根据状态标记防止重复触发
            if (current_axisV_position <= JoyV_Left_Threshold && JoyV_Action_State != 40) {
                ; JoyV 向左移动且状态不是左
                Send Key_Turn_Left ; 发送向左转头的按键
                JoyV_Action_State := 40 ; 更新状态为左
                ; Tooltip("Left Action Triggered", , , 2) ; 调试信息
            } else if (current_axisV_position >= JoyV_Right_Threshold && JoyV_Action_State != 60) {
                ; JoyV 向右移动且状态不是右
                Send Key_Turn_Right ; 发送向右转头的按键
                JoyV_Action_State := 60 ; 更新状态为右
                ; Tooltip("Right Action Triggered", , , 2) ; 调试信息
            } else if (current_axisV_position > JoyV_Center_Min && current_axisV_position < JoyV_Center_Max && JoyV_Action_State != 50) {
                ; JoyV 回到中心附近且状态不是中
                Send Key_Turn_Center ; 发送回中的按键
                JoyV_Action_State := 50 ; 更新状态为中
                ; Tooltip("Center Action Triggered", , , 2) ; 调试信息
            }
        }
        ; Note: 如果不满足启用 JoyV 动作的条件，JoyV_Action_State 保持不变。

        ; 检查 JoyZ 轴是否触发复位动作 (独立于 JoyV 动作)
        if ((current_axisZ_position > JoyZ_Reset_Max || current_axisZ_position < JoyZ_Reset_Min) && current_axisU_position > JoyU_Enable_Threshold && current_axisU_position < JoyU_Disable_Max) {
            Send Key_Reset_View ; 发送复位按键
            JoyV_Action_State := 50 ; 复位时通常也将 JoyV 状态设为中
            ; Tooltip("Reset Action Triggered", , , 2) ; 调试信息
        }

    } else {
        ; --- 目标窗口不是活动的 ---
        ; 重置动作状态，防止切换回窗口时立即触发动作
        JoyV_Action_State := 50
        ; 清除任何与动作相关的 Tooltip
        Tooltip('', , , 2)
        ; 更新主 Tooltip 显示窗口状态 (可选)
        ; Tooltip("V:" current_axisV_position " U:" current_axisU_position " X:" current_axisX_position " Z:" current_axisZ_position " Speed:" Format("{:.2f}", current_JoyV_speed) "`nWindow: Inactive", , , 1) ; Tooltip ID 1
    }

    ; 暂停一小段时间，避免占用过多 CPU
    Sleep PollingInterval
}

; --- 退出脚本和复位视图的热键 ---

; 按下 Ctrl+Shift+Z 键暂停脚本并发送复位按键
; 用于临时禁用脚本并复位视图
^+z::
{
    Pause -1 ; 切换暂停状态 (-1 表示切换)
    ; Tooltip("Script Paused: " (A_IsPaused ? "Yes" : "No"), , , 3) ; 调试信息显示暂停状态

    ; 尝试激活目标窗口，然后发送复位按键
    ; 如果没有配置目标窗口，则直接发送到当前活动窗口
    if (TargetWindowTitle != "") {
        WinActivate(TargetWindowTitle)
        ; Optional: Add a small sleep to ensure window is active before sending keys
        ; Sleep 50
    } else if (TargetWindowClass != "") {
        WinActivate("ahk_class " TargetWindowClass)
        ; Sleep 50
    } else if (TargetWindowProcessName != "") {
         WinActivate("ahk_exe " TargetWindowProcessName)
         ; Sleep 50
    }
    ; else { ; 如果没有配置任何目标窗口，则发送到当前活动窗口 }

    Send Key_Reset_View ; 发送复位按键
    JoyV_Action_State := 50 ; 复位时通常也将 JoyV 状态设为中
    Return
}

; 按下 Ctrl+Shift+K 键退出脚本
^+k::
{
    ; 退出前清除所有 Tooltip (如果使用了的话)
    Tooltip('', , , 1)
    Tooltip('', , , 2)
    Tooltip('', , , 3)
    ExitApp ; 退出脚本
    Return
}
