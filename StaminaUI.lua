-- 文件名: StarterPlayer/StarterPlayerScripts/StaminaUI.lua
-- 这是一个整合了体力、第一人称可见性和摄像机控制的客户端脚本。
-- 目标：实现正常走路时使用Roblox默认第一人称，眩晕时应用自定义晃动，并支持自定义物品列表。
task.wait(0.2) -- 增加等待时间，给脚本更多初始化时间 (从0.5s增加到1.0s)
print("StaminaUI 脚本开始执行！")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera -- 获取当前摄像机

local player = Players.LocalPlayer
local character -- 声明 character 和 humanoid 变量
local humanoid
local animator -- 用于管理动画的Animator
local rollAnimation -- 翻滚动画实例
local rollAnimationTrack -- 翻滚动画轨道

-- 体力设置 (客户端副本，用于显示)
local currentStamina = 100
local maxStamina = 100
local SPRINT_STAMINA_COST_PER_SECOND = 10 -- Stamina cost per second for sprinting (adjusted for 10s sprint)
local ROLL_STAMINA_COST = 50 -- Stamina cost per roll (adjusted for 2 rolls)

-- 新增：生命值设置
local currentHealth = 100
local maxHealth = 100 -- <<<<<< 确保这里是正确的最大生命值，通常是 Humanoid.MaxHealth
print("StaminaUI: 初始 maxHealth 设置为: " .. maxHealth) -- 调试日志

local SPRINT_SPEED = 24 -- 冲刺时的速度 (默认行走速度是16)
local DEFAULT_SPEED = 16 -- 默认行走速度

-- 暴冲/冲刺相关参数
local BURST_SPEED = 60 -- 暴冲时的超高速度
local BURST_DISTANCE = 9 -- 暴冲的距离 (与原翻滚位移相同)
local BURST_TIME = BURST_DISTANCE / BURST_SPEED -- 暴冲持续时间

-- 眩晕相关参数
local STUN_DURATION = 3 -- 眩晕持续时间 (秒)
local STUN_SPEED_MULTIPLIER = 0.5 -- 眩晕时速度乘数 (50% 速度)
local originalJumpPower -- 存储角色原始跳跃力

local isSprinting = false
local isRolling = false -- 仍然用于标记暴冲状态
local canRoll = true
local isStunned = false -- 玩家是否处于眩晕状态
local isInputBlocked = false -- 用于手动阻塞输入
local sprintKeyHeld = false -- 跟踪冲刺键是否被按下

-- 用于手动跟踪WASD键状态
local isWPressed = false
local isAPressed = false
local isSPressed = false
local isDPressed = false

-- 摄像机效果变量
local isCameraLocked = true -- 初始状态为锁定，鼠标控制视角 (用于切换默认第一人称/第三人称)
local stunStartTime = 0 -- 用于眩晕效果的计时器

-- 物品栏选择相关变量
local currentSlotIndex = 1 -- 当前选中的物品槽位 (1-9)
local inventorySlots = {} -- 存储物品槽位的UI Frame
local HIGHLIGHT_COLOR = Color3.new(1, 1, 1) -- 高亮颜色 (白色)
local DEFAULT_SLOT_COLOR = Color3.fromRGB(40, 40, 60) -- 默认槽位背景色
local DEFAULT_STROKE_COLOR = Color3.fromRGB(150, 140, 120) -- 默认槽位边框颜色
local DEFAULT_STROKE_THICKNESS = 1.5 -- 默认槽位边框粗细
local MAX_INVENTORY_SLOTS = 9 -- 最大物品栏槽位数量

-- 存储当前背包和角色中所有工具的列表
local currentToolsInInventory = {}

-- <<<<<< 新增辅助函数：获取当前装备的工具 >>>>>>
local function getEquippedTool()
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				return child
			end
		end
	end
	return nil
end

-- 函数：设置角色相关的变量 (在游戏开始和角色重生时调用)
local function setupCharacter()
	-- 等待玩家角色加载或重生
	character = player.Character or player.CharacterAdded:Wait()
	if not character then
		warn("StaminaUI: 无法获取玩家角色！脚本可能无法正常工作。")
		return
	end
	print("StaminaUI: 已获取玩家角色: " .. character.Name)

	-- 等待Humanoid加载
	humanoid = character:WaitForChild("Humanoid")
	if not humanoid then
		warn("StaminaUI: 无法获取Humanoid！脚本可能无法正常工作。")
		return
	end
	print("StaminaUI: 已获取Humanoid。")

	-- <<<<<< 关键修正：添加短暂等待，确保Humanoid属性完全初始化 >>>>>>
	task.wait(0.05) -- 给Roblox一个短暂的时间来初始化Humanoid的属性

	-- <<<<<< 修复：保存原始跳跃力 >>>>>>
	originalJumpPower = humanoid.JumpPower
	print("StaminaUI: 已保存原始跳跃力: " .. originalJumpPower)

	-- 获取或创建Animator
	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	print("StaminaUI: 已获取/创建Animator。")

	-- 加载翻滚动画 (只加载一次)
	if not rollAnimation then
		rollAnimation = Instance.new("Animation")
		-- 请替换为你的翻滚动画ID
		rollAnimation.AnimationId = "rbxassetid://507765000" -- 这是一个示例ID，请替换为你的实际动画ID
		print("StaminaUI: 尝试加载动画ID: " .. rollAnimation.AnimationId)
	end

	-- 如果动画轨道已存在，停止并销毁它，以防旧角色残留
	if rollAnimationTrack then
		rollAnimationTrack:Stop()
		rollAnimationTrack:Destroy()
		rollAnimationTrack = nil
		print("StaminaUI: 已清理旧的翻滚动画轨道。")
	end

	-- 加载动画轨道
	local success, message = pcall(function()
		rollAnimationTrack = animator:LoadAnimation(rollAnimation)
	end)
	if not success then
		warn("StaminaUI: 无法加载翻滚动画轨道！错误信息: " .. message)
		rollAnimationTrack = nil
	else
		print("StaminaUI: 成功加载翻滚动画轨道。")
	end

	-- 重置速度和状态，以防角色重生
	humanoid.WalkSpeed = DEFAULT_SPEED
	humanoid.JumpPower = originalJumpPower -- 确保跳跃力恢复原始值
	print("StaminaUI: 角色重生时，跳跃力已恢复到原始值: " .. originalJumpPower)
	isSprinting = false
	isRolling = false
	isStunned = false
	isInputBlocked = false -- 重置输入阻塞状态
	sprintKeyHeld = false -- 重置冲刺键状态
	print("StaminaUI: 角色变量已设置/重置。")

	-- 停止所有动画
	if animator then
		for _, track in pairs(animator:GetPlayingAnimationTracks()) do
			track:Stop()
		end
		print("StaminaUI: 已停止所有非默认动画。")
	end

	-- 摄像机初始化：始终设置为Custom，我们让Roblox控制
	task.defer(function()
		if humanoid then -- 确保humanoid存在
			if isCameraLocked then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				UserInputService.MouseIconEnabled = false
				print("StaminaUI: 初始鼠标行为设置为锁定和隐藏。")
			else
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
				print("StaminaUI: 初始鼠标行为设置为默认和显示。")
			end
		else
			warn("StaminaUI: Humanoid is nil during initial camera setup in task.defer.")
		end
	end)

	Camera.CameraType = Enum.CameraType.Custom -- 始终设置为Custom，让Roblox控制摄像机
	Camera.CameraSubject = humanoid -- 设置Subject为Humanoid
	Camera.FieldOfView = 70 -- 恢复默认FOV
	print("StaminaUI: 摄像机初始设置为 Custom 类型，Subject 为 Humanoid。")

	if humanoid then
		humanoid.AutoRotate = false -- <<<<<< 关键修改：禁用Humanoid的自动旋转，以便我们手动控制 >>>>>>
		print("StaminaUI: Humanoid.AutoRotate 已禁用。")
	end

	-- <<<<<< 确保 maxHealth 从 Humanoid 获取 >>>>>>
	maxHealth = humanoid.MaxHealth
	print("StaminaUI: Humanoid.MaxHealth 已获取并设置为 maxHealth: " .. maxHealth)
	print("StaminaUI: 角色变量和摄像机已设置/重置。")

	-- 隐藏左上角默认UI图标 (聊天和背包/菜单)
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	-- <<<<<< 修改：禁用 Roblox 默认背包/物品列表 >>>>>>
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	-- 禁用默认生命值显示
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	print("StaminaUI: 已禁用默认核心GUI (聊天、背包和生命值)。")

	-- <<<<<< 移除 Humanoid.AncestryChanged 事件连接，因为它与摄像机缩放设置相关 >>>>>>
	-- local ancestryChangedConnection
	-- ancestryChangedConnection = humanoid.AncestryChanged:Connect(function(child, parent)
	-- 	if parent == workspace and child == humanoid then
	-- 		print("StaminaUI: Humanoid AncestryChanged: Humanoid已添加到Workspace。")
	-- 		setCameraZoomProperties() -- 在Humanoid完全加载到Workspace后设置摄像机缩放
	-- 		if ancestryChangedConnection then
	-- 			ancestryChangedConnection:Disconnect() -- 只执行一次
	-- 			ancestryChangedConnection = nil
	-- 		end
	-- 	end
	-- end)
	-- -- 如果Humanoid已经存在于Workspace中，则立即设置
	-- if humanoid.Parent == workspace then
	-- 	print("StaminaUI: Humanoid已在Workspace中，立即设置摄像机缩放。")
	-- 	setCameraZoomProperties()
	-- end
end

-- 处理角色重生事件：当玩家角色重生时，重新设置角色变量
-- <<<<<< 提前连接 CharacterAdded 事件 >>>>>>
player.CharacterAdded:Connect(function(newCharacter)
	print("StaminaUI: 玩家角色已重置/重生。重新设置角色变量。")
	setupCharacter() -- 重新运行设置函数以获取新的角色和Humanoid
end)

-- 首次设置角色变量
setupCharacter()

-- <<<<<< 修复 LobbyClientUI 错误：等待 PlayerGui >>>>>>
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
	warn("StaminaUI: 无法获取PlayerGui！脚本终止。")
	return
end
print("StaminaUI: 已获取PlayerGui。")

-- 创建UI (新设计) - **此部分已移至 RemoteEvent 连接之前**
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StaminaGui"
screenGui.Parent = playerGui
screenGui.IgnoreGuiInset = true -- 确保UI在屏幕底部
print("StaminaUI: 已创建ScreenGui。")

-- 自定义物品列表 (豪华风格，9个格子，横向排列)
local inventoryFrame = Instance.new("Frame")
inventoryFrame.Name = "InventoryFrame"
-- 9个槽位 (横向排列): 9 * 50 (槽位大小) + 8 * 5 (槽位间距) + 2 * 5 (边框内边距) = 450 + 40 + 10 = 500
-- 高度：1 * 50 (槽位大小) + 2 * 5 (边框内边距) = 50 + 10 = 60
inventoryFrame.Size = UDim2.new(0, 500, 0, 60)
-- 位置：水平居中，距离底部10像素
inventoryFrame.Position = UDim2.new(0.5, 0, 1, -10)
inventoryFrame.AnchorPoint = Vector2.new(0.5, 1) -- 锚点在底部中心
inventoryFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40) -- 深蓝灰色背景
inventoryFrame.BackgroundTransparency = 0.15 -- 略微透明
inventoryFrame.BorderSizePixel = 0 -- 移除默认边框
inventoryFrame.Parent = screenGui
inventoryFrame.ZIndex = 2 -- 确保在体力条下方，但高于默认UI

-- 豪华圆角
local uiCornerInventory = Instance.new("UICorner")
uiCornerInventory.CornerRadius = UDim.new(0, 12) -- 更大的圆角
uiCornerInventory.Parent = inventoryFrame

-- 豪华边框
local uiStrokeInventory = Instance.new("UIStroke")
uiStrokeInventory.Color = Color3.fromRGB(100, 90, 70) -- 边框颜色改为暗青铜/暗金色
uiStrokeInventory.Thickness = 2 -- 边框粗细
uiStrokeInventory.Parent = inventoryFrame

-- 豪华渐变
local uiGradientInventory = Instance.new("UIGradient")
uiGradientInventory.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 25)), -- 顶部更深
	ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 35, 50))  -- 底部略浅
})
uiGradientInventory.Rotation = 90 -- 垂直渐变
uiGradientInventory.Parent = inventoryFrame
print("StaminaUI: 已创建自定义物品列表容器 (豪华风格)。")

local inventoryLayout = Instance.new("UIGridLayout")
inventoryLayout.Name = "InventoryLayout"
inventoryLayout.CellSize = UDim2.new(0, 50, 0, 50) -- 每个槽位的大小
inventoryLayout.CellPadding = UDim2.new(0, 5, 0, 5) -- 槽位之间的间距
inventoryLayout.FillDirection = Enum.FillDirection.Horizontal -- 确保横向填充
inventoryLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
inventoryLayout.VerticalAlignment = Enum.VerticalAlignment.Center
inventoryLayout.Parent = inventoryFrame
print("StaminaUI: 已为物品列表容器添加UIGridLayout。")

-- 创建九个物品槽位
for i = 1, MAX_INVENTORY_SLOTS do -- 循环创建 MAX_INVENTORY_SLOTS 个槽位
	local slotFrame = Instance.new("Frame")
	slotFrame.Name = "Slot" .. i
	slotFrame.Size = UDim2.new(1, 0, 1, 0) -- 填充父级CellSize
	slotFrame.BackgroundColor3 = DEFAULT_SLOT_COLOR -- 槽位背景色 (略浅的蓝灰色)
	slotFrame.BackgroundTransparency = 0.1 -- 略微透明
	slotFrame.BorderSizePixel = 0 -- 移除默认边框
	slotFrame.Parent = inventoryFrame
	table.insert(inventorySlots, slotFrame) -- 将槽位添加到列表中

	-- 槽位圆角
	local uiCornerSlot = Instance.new("UICorner")
	uiCornerSlot.CornerRadius = UDim.new(0, 8) -- 槽位圆角
	uiCornerSlot.Parent = slotFrame

	-- 槽位边框
	local uiStrokeSlot = Instance.new("UIStroke")
	uiStrokeSlot.Name = "SlotStroke" -- 给边框命名，方便后续修改
	uiStrokeSlot.Color = DEFAULT_STROKE_COLOR -- 槽位边框颜色改为更亮的青铜/暗金色
	uiStrokeSlot.Thickness = DEFAULT_STROKE_THICKNESS -- 边框粗细
	uiStrokeSlot.Transparency = 0 -- 确保默认边框可见
	uiStrokeSlot.Parent = slotFrame

	-- 可以添加一个ImageLabel来显示物品图标
	local itemIcon = Instance.new("ImageLabel")
	itemIcon.Name = "ItemIcon"
	itemIcon.Size = UDim2.new(0.8, 0, 0.8, 0) -- 占槽位80%
	itemIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	itemIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	itemIcon.BackgroundTransparency = 1
	itemIcon.Image = "rbxassetid://0" -- 默认空图标，替换为实际物品图标
	itemIcon.Parent = slotFrame
	itemIcon.ZIndex = 3 -- 确保图标在背景和边框之上

	-- 物品名称标签 (可选，用于调试或显示名称)
	local itemNameLabel = Instance.new("TextLabel")
	itemNameLabel.Name = "ItemNameLabel"
	itemNameLabel.Size = UDim2.new(1, 0, 0.2, 0) -- 底部20%高度
	itemNameLabel.Position = UDim2.new(0, 0, 0.8, 0)
	itemNameLabel.BackgroundTransparency = 1
	itemNameLabel.TextColor3 = Color3.new(1, 1, 1) -- 白色文本
	itemNameLabel.TextScaled = true
	itemNameLabel.TextXAlignment = Enum.TextXAlignment.Center
	itemNameLabel.TextYAlignment = Enum.TextYAlignment.Center
	itemNameLabel.Font = Enum.Font.SourceSansBold
	itemNameLabel.Text = "" -- 初始为空
	itemNameLabel.ZIndex = 4 -- 确保文本在图标和背景之上
	itemNameLabel.Parent = slotFrame
end
print("StaminaUI: 已创建九个物品槽位 (豪华风格)。")

-- 体力条 (新位置和样式)
local STAMINA_HEALTH_BAR_WIDTH = 225 -- 4个格子宽度 (4*50 (格子大小) + 3*5 (格子间距) + 2*5 (边框内边距) = 200 + 15 + 10 = 225)
local STAMINA_HEALTH_BAR_HEIGHT = 20
local VERTICAL_GAP = 15 -- 0.3cm 约等于 15 像素

local staminaFrame = Instance.new("Frame")
staminaFrame.Name = "StaminaFrame"
staminaFrame.Size = UDim2.new(0, STAMINA_HEALTH_BAR_WIDTH, 0, STAMINA_HEALTH_BAR_HEIGHT)
-- 位置：水平居中，距离底部10像素
-- 物品栏中心X: 0.5, 0
-- 物品栏左边缘X: 0.5, -500/2 = 0.5, -250
-- 体力条中心X: 物品栏左边缘X + 体力条宽度/2 = 0.5, -250 + 225/2 = 0.5, -137.5
staminaFrame.Position = UDim2.new(0.5, -137.5, 1, -85)
staminaFrame.AnchorPoint = Vector2.new(0.5, 1) -- 锚点在底部中心
staminaFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40) -- 深蓝灰色背景
staminaFrame.BackgroundTransparency = 0.15 -- 略微透明
staminaFrame.BorderSizePixel = 0 -- 移除默认边框
staminaFrame.Parent = screenGui
print("StaminaUI: 已创建StaminaFrame。")

-- 添加圆角
local uiCornerStaminaFrame = Instance.new("UICorner")
uiCornerStaminaFrame.CornerRadius = UDim.new(0, 12) -- 更大的圆角
uiCornerStaminaFrame.Parent = staminaFrame

-- 添加边框
local uiStrokeStaminaFrame = Instance.new("UIStroke")
uiStrokeStaminaFrame.Color = Color3.fromRGB(100, 90, 70) -- 边框颜色改为暗青铜/暗金色
uiStrokeStaminaFrame.Thickness = 2 -- 边框粗细
uiStrokeStaminaFrame.Parent = staminaFrame

-- 添加渐变
local uiGradientStaminaFrame = Instance.new("UIGradient")
uiGradientStaminaFrame.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 25)), -- 顶部更深
	ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 35, 50))  -- 底部略浅
})
uiGradientStaminaFrame.Rotation = 90 -- 垂直渐变
uiGradientStaminaFrame.Parent = staminaFrame

local staminaBar = Instance.new("Frame")
staminaBar.Name = "StaminaBar"
staminaBar.Size = UDim2.new(1, 0, 1, 0) -- 填充StaminaFrame
staminaBar.Position = UDim2.new(0, 0, 0, 0)
staminaBar.BackgroundColor3 = Color3.new(0.2, 0.8, 0.2) -- 绿色
staminaBar.Parent = staminaFrame
print("StaminaUI: 已创建StaminaBar。")

-- 添加圆角
local uiCornerBar = Instance.new("UICorner")
uiCornerBar.CornerRadius = UDim.new(0, 8) -- 圆角半径
uiCornerBar.Parent = staminaBar

local staminaText = Instance.new("TextLabel")
staminaText.Name = "StaminaText"
staminaText.Size = UDim2.new(1, 0, 1, 0) -- 填充整个StaminaFrame
staminaText.Position = UDim2.new(0, 0, 0, 0)
staminaText.BackgroundTransparency = 1
staminaText.TextColor3 = Color3.new(1, 1, 1) -- 白色文本
staminaText.TextScaled = true
staminaText.TextXAlignment = Enum.TextXAlignment.Center
staminaText.TextYAlignment = Enum.TextYAlignment.Center
staminaText.Font = Enum.Font.SourceSansBold
staminaText.Text = "体力: 100/100"
staminaText.ZIndex = 2 -- 确保在体力条上方
staminaText.Parent = staminaFrame -- 文本现在是StaminaFrame的子元素
print("StaminaUI: 已创建StaminaText。")

-- 新增：体力警告文本 (位置已自动跟随StaminaFrame)
local staminaWarningText = Instance.new("TextLabel")
staminaWarningText.Name = "StaminaWarningText"
staminaWarningText.Size = UDim2.new(0, 500, 0, 20) -- 与体力条同宽，高20
-- 位置：位于体力条上方5像素 (相对体力条的底部锚点)
staminaWarningText.Position = UDim2.new(staminaFrame.Position.X.Scale, staminaFrame.Position.X.Offset, staminaFrame.Position.Y.Scale, staminaFrame.Position.Y.Offset - staminaFrame.Size.Y.Offset - 5)
staminaWarningText.AnchorPoint = Vector2.new(0.5, 1) -- 锚点在底部中心，与体力条对齐
staminaWarningText.BackgroundTransparency = 1
staminaWarningText.TextColor3 = Color3.new(1, 0, 0) -- 红色文本
staminaWarningText.TextScaled = true
staminaWarningText.TextXAlignment = Enum.TextXAlignment.Center
staminaWarningText.TextYAlignment = Enum.TextYAlignment.Center
staminaWarningText.Font = Enum.Font.SourceSansBold
staminaWarningText.Text = "警告:体力无法负荷将造成短暂晕眩"
staminaWarningText.Visible = false -- 初始隐藏
staminaWarningText.ZIndex = 3 -- 确保在最上层
staminaWarningText.Parent = screenGui
print("StaminaUI: 已创建StaminaWarningText。")

-- 新增：生命值条
local healthFrame = Instance.new("Frame")
healthFrame.Name = "HealthFrame"
healthFrame.Size = UDim2.new(0, STAMINA_HEALTH_BAR_WIDTH, 0, STAMINA_HEALTH_BAR_HEIGHT) -- Same size as stamina bar
-- 位置：与物品栏右侧对齐，与体力条同高
-- 物品栏右边缘X: 0.5, 500/2 = 0.5, 250
-- 生命值条中心X: 物品栏右边缘X - 生命值条宽度/2 = 0.5, 250 - 225/2 = 0.5, 137.5
healthFrame.Position = UDim2.new(0.5, 137.5, 1, -85) -- Aligned right with inventory, same Y as stamina
healthFrame.AnchorPoint = Vector2.new(0.5, 1)
healthFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40) -- Dark blue-grey background
healthFrame.BackgroundTransparency = 0.15
healthFrame.BorderSizePixel = 0
healthFrame.Parent = screenGui
print("StaminaUI: 已创建HealthFrame。")

-- 添加圆角、边框、渐变
local uiCornerHealthFrame = Instance.new("UICorner")
uiCornerHealthFrame.CornerRadius = UDim.new(0, 12)
uiCornerHealthFrame.Parent = healthFrame

local uiStrokeHealthFrame = Instance.new("UIStroke")
uiStrokeHealthFrame.Color = Color3.fromRGB(100, 90, 70)
uiStrokeHealthFrame.Thickness = 2
uiStrokeHealthFrame.Parent = healthFrame

local uiGradientHealthFrame = Instance.new("UIGradient")
uiGradientHealthFrame.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 25)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 35, 50))
})
uiGradientHealthFrame.Rotation = 90
uiGradientHealthFrame.Parent = healthFrame

-- Health Bar (fill)
local healthBar = Instance.new("Frame")
healthBar.Name = "HealthBar"
healthBar.Size = UDim2.new(1, 0, 1, 0) -- Fills HealthFrame
healthBar.Position = UDim2.new(0, 0, 0, 0)
healthBar.BackgroundColor3 = Color3.new(0.8, 0.2, 0.2) -- Red color for health
healthBar.Parent = healthFrame
print("StaminaUI: 已创建HealthBar。")

-- Add UICorner for HealthBar
local uiCornerHealthBar = Instance.new("UICorner")
uiCornerHealthBar.CornerRadius = UDim.new(0, 8)
uiCornerHealthBar.Parent = healthBar

-- Health Text
local healthText = Instance.new("TextLabel")
healthText.Name = "HealthText"
healthText.Size = UDim2.new(1, 0, 1, 0)
healthText.Position = UDim2.new(0, 0, 0, 0)
healthText.BackgroundTransparency = 1
healthText.TextColor3 = Color3.new(1, 1, 1) -- White text
healthText.TextScaled = true
healthText.TextXAlignment = Enum.TextXAlignment.Center
healthText.TextYAlignment = Enum.TextYAlignment.Center
healthText.Font = Enum.Font.SourceSansBold
healthText.Text = "生命: 100/100"
staminaText.ZIndex = 2
healthText.Parent = healthFrame
print("StaminaUI: 已创建HealthText。")

-- 右下角装饰图案
local cornerImage = Instance.new("ImageLabel")
cornerImage.Name = "CornerImage"
cornerImage.Size = UDim2.new(0, 100, 0, 100) -- 调整大小
cornerImage.Position = UDim2.new(1, -10, 1, -10) -- 调整位置，稍微向内偏移
cornerImage.AnchorPoint = Vector2.new(1, 1) -- 锚点在右下角
cornerImage.BackgroundTransparency = 1
cornerImage.Image = "rbxassetid://0" -- 请替换为你的图片ID，例如 "rbxassetid://[你的图片ID]"
cornerImage.Parent = screenGui
print("StaminaUI: 已创建右下角装饰图案占位符。")

-- <<<<<< 新增：十字準星 >>>>>>
local crosshairFrame = Instance.new("Frame")
crosshairFrame.Name = "CrosshairFrame"
crosshairFrame.Size = UDim2.new(0, 20, 0, 20) -- 准星的整体大小
crosshairFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshairFrame.AnchorPoint = Vector2.new(0.5, 0.5)
crosshairFrame.BackgroundTransparency = 1 -- 使父框架透明
crosshairFrame.BorderSizePixel = 0
crosshairFrame.Parent = screenGui
crosshairFrame.ZIndex = 5 -- 确保在最上层

-- 水平条
local horizontalBar = Instance.new("Frame")
horizontalBar.Name = "HorizontalBar"
horizontalBar.Size = UDim2.new(1, 0, 0, 2) -- 填充父框架宽度，2像素高
horizontalBar.Position = UDim2.new(0.5, 0, 0.5, 0)
horizontalBar.AnchorPoint = Vector2.new(0.5, 0.5)
horizontalBar.BackgroundColor3 = Color3.new(1, 1, 1) -- 白色
horizontalBar.BorderSizePixel = 0
horizontalBar.Parent = crosshairFrame

-- 垂直条
local verticalBar = Instance.new("Frame")
verticalBar.Name = "VerticalBar"
verticalBar.Size = UDim2.new(0, 2, 1, 0) -- 2像素宽，填充父框架高度
verticalBar.Position = UDim2.new(0.5, 0, 0.5, 0)
verticalBar.AnchorPoint = Vector2.new(0.5, 0.5)
verticalBar.BackgroundColor3 = Color3.new(1, 1, 1) -- 白色
verticalBar.BorderSizePixel = 0
verticalBar.Parent = crosshairFrame

print("StaminaUI: 已创建十字準星。")

-- 获取RemoteEvent
local UpdateStaminaEventSuccess, UpdateStaminaEvent = pcall(function()
	return ReplicatedStorage:WaitForChild("UpdateStamina", 30) -- 增加超时时间
end)
if not UpdateStaminaEventSuccess or not UpdateStaminaEvent then
	warn("StaminaUI: 无法获取 ReplicatedStorage.UpdateStamina RemoteEvent。请检查ReplicatedStorage中是否存在名为'UpdateStamina'的RemoteEvent。脚本终止。")
	return
end
print("StaminaUI: 已获取 UpdateStamina RemoteEvent。")

-- <<<<<< 立即连接体力更新事件 >>>>>>
UpdateStaminaEvent.OnClientEvent:Connect(function(newStamina, newMaxStamina)
	print("StaminaUI: 收到服务器体力更新！ newStamina: " .. newStamina .. ", newMaxStamina: " .. newMaxStamina)
	currentStamina = newStamina
	-- 修复：确保 maxStamina 使用 newMaxStamina，并添加nil/0检查
	if newMaxStamina and newMaxStamina > 0 then
		maxStamina = newMaxStamina
	else
		maxStamina = 100 -- 默认值，以防万一
		warn("StaminaUI: newMaxStamina 为 nil 或 0，已使用默认值 100。")
	end
	local percent = currentStamina / maxStamina
	staminaBar:TweenSize(UDim2.new(percent, 0, 1, 0), "Out", "Quad", 0.1, true)
	staminaText.Text = string.format("体力: %d/%d", math.floor(currentStamina), maxStamina)

	-- 根据体力百分比改变颜色
	if percent < 0.2 then
		staminaBar.BackgroundColor3 = Color3.new(0.8, 0.2, 0.2) -- 红色
	elseif percent < 0.5 then
		staminaBar.BackgroundColor3 = Color3.new(0.8, 0.8, 0.2) -- 黄色
	else
		staminaBar.BackgroundColor3 = Color3.new(0.2, 0.8, 0.2) -- 绿色
	end

	-- 根据体力更新翻滚状态
	if currentStamina < ROLL_STAMINA_COST then -- 体力不足以翻滚
		canRoll = false
	else
		canRoll = true
	end

	-- 体力耗尽后的眩晕逻辑
	if currentStamina <= 0 then -- 体力耗尽
		if isSprinting then -- 强制停止冲刺
			isSprinting = false
			print("StaminaUI: 体力耗尽，强制停止冲刺。")
		end
		sprintKeyHeld = false -- 强制重置冲刺键状态，要求玩家重新按下Shift
		print("StaminaUI: 体力耗尽，强制重置冲刺键状态。")

		-- 立即清除所有按键状态并停止移动
		isWPressed = false
		isAPressed = false
		isSPressed = false
		isDPressed = false
		if humanoid then
			humanoid:Move(Vector3.new(0,0,0)) -- 强制停止移动
			print("StaminaUI: 体力耗尽，已强制停止角色移动并清除按键状态。")
		end
		-- 模拟极短的W键检测来刷新状态 (在体力耗尽时立即执行)
		isWPressed = true
		if humanoid then
			humanoid:Move(Vector3.new(0,0,-1).Unit) -- 模拟向前移动
		end
		task.wait(0.001) -- 极短时间
		isWPressed = false
		if humanoid then
			humanoid:Move(Vector3.new(0,0,0)) -- 强制停止移动
			print("StaminaUI: 体力耗尽，已通过模拟W键刷新并强制停止角色移动。")
		end
		-- 确保其他按键状态也重置，以防万一
		isAPressed = false
		isSPressed = false
		isDPressed = false

		if not isStunned then -- 如果尚未眩晕
			isStunned = true
			stunStartTime = tick()
			if humanoid then
				humanoid.WalkSpeed = DEFAULT_SPEED * STUN_SPEED_MULTIPLIER
				humanoid.JumpPower = 0 -- 眩晕时禁用跳跃
				print("StaminaUI: 眩晕时已禁用跳跃。")
			end -- 速度减少50%
			print("StaminaUI: 体力耗尽！玩家眩晕 " .. STUN_DURATION .. " 秒，速度减少50%。")
			print("StaminaUI: 眩晕开始，摄像机类型保持为 Custom。")

			-- 延迟后解除眩晕
			task.delay(STUN_DURATION, function()
				if isStunned then -- 只有当眩晕状态仍然激活时才解除
					isStunned = false
					print("StaminaUI: 眩晕解除 (通过延迟)。")
					if humanoid then
						humanoid.JumpPower = originalJumpPower -- 眩晕解除时恢复原始跳跃力
						print("StaminaUI: 眩晕解除时已恢复原始跳跃力: " .. originalJumpPower)
					end
				end
			end)
		end
	end
	-- 警告文本显示逻辑
	if currentStamina <= 20 and currentStamina > 0 then
		staminaWarningText.Visible = true
	else
		staminaWarningText.Visible = false
	end
end)

-- 获取用于请求消耗体力的RemoteEvent
local RequestStaminaConsumptionEventSuccess, RequestStaminaConsumptionEvent = pcall(function()
	return ReplicatedStorage:WaitForChild("RequestStaminaConsumption", 30) -- 增加超时时间
end)
if not RequestStaminaConsumptionEventSuccess or not RequestStaminaConsumptionEvent then
	warn("StaminaUI: 无法获取 ReplicatedStorage.RequestStaminaConsumption RemoteEvent。冲刺功能和翻滚功能可能无法正常工作。请检查ReplicatedStorage中是否存在名为'RequestStaminaConsumption'的RemoteEvent。脚本终止。")
	return
else
	print("StaminaUI: 成功获取 RequestStaminaConsumption RemoteEvent。")
end

-- 更新生命值UI的函数
local function updateHealthUI(newHealth)
	currentHealth = newHealth
	local percent = currentHealth / maxHealth -- <<<<<< 修正：使用 maxHealth
	healthBar:TweenSize(UDim2.new(percent, 0, 1, 0), "Out", "Quad", 0.1, true)
	healthText.Text = string.format("生命: %d/%d", math.floor(currentHealth), math.floor(maxHealth)) -- <<<<<< 修正：使用 maxHealth 并对 maxHealth 进行取整
	print("StaminaUI: 更新生命值UI: " .. currentHealth .. "/" .. maxHealth) -- 调试日志
	-- 生命值条始终为红色
	healthBar.BackgroundColor3 = Color3.new(0.8, 0.2, 0.2) -- 红色
end

-- 监听Humanoid的HealthChanged事件
if humanoid then
	humanoid.HealthChanged:Connect(function(newHealth)
		updateHealthUI(newHealth)
	end)
	-- 首次更新生命值显示，直接调用函数
	updateHealthUI(humanoid.Health)
end

-- 暴冲函数 (原翻滚函数)
local function doBurst()
	print("StaminaUI: doBurst 函数被调用。")
	-- 增加对 humanoid 的 nil 检查，以及眩晕状态检查
	-- 只有在不暴冲、体力充足、角色在移动且不眩晕时才能暴冲
	if isRolling or not canRoll or (not humanoid or humanoid.MoveDirection.Magnitude == 0) or isStunned then
		print("StaminaUI: 无法暴冲。isRolling: " .. tostring(isRolling) .. ", canRoll: " .. tostring(canRoll) .. ", MoveDirection.Magnitude: " .. (humanoid and humanoid.MoveDirection.Magnitude or 'nil humanoid') .. ", isStunned: " .. tostring(isStunned))
		return
	end
	isRolling = true -- 标记为暴冲状态

	-- 消耗体力：通过RemoteEvent请求服务器消耗
	RequestStaminaConsumptionEvent:FireServer(ROLL_STAMINA_COST)
	print("StaminaUI: 已向服务器发送暴冲体力消耗请求。消耗量: " .. ROLL_STAMINA_COST)

	local rootPart = character:WaitForChild("HumanoidRootPart")
	if not rootPart then
		warn("StaminaUI: 无法获取HumanoidRootPart进行暴冲！")
		isRolling = false
		if humanoid then humanoid.WalkSpeed = DEFAULT_SPEED end
		return
	end
	print("StaminaUI: 获取到HumanoidRootPart。")

	-- 播放暴冲动画 (如果存在)
	if rollAnimationTrack then
		rollAnimationTrack:Play()
		print("StaminaUI: 播放暴冲动画。")
	else
		warn("StaminaUI: 暴冲动画轨道不存在，无法播放动画。")
	end

	-- 临时提高速度实现暴冲
	local originalWalkSpeed = humanoid.WalkSpeed -- 记录当前速度
	humanoid.WalkSpeed = BURST_SPEED
	print("StaminaUI: 暴冲开始，速度设置为: " .. BURST_SPEED)

	-- 临时阻塞输入，防止在暴冲期间进行其他操作
	isInputBlocked = true
	task.wait(BURST_TIME) -- 等待暴冲持续时间

	isRolling = false -- 暴冲结束
	-- 恢复输入
	isInputBlocked = false

	-- 恢复到暴冲前的速度，或者根据当前状态（冲刺/眩晕）调整
	if isStunned then
		humanoid.WalkSpeed = DEFAULT_SPEED * STUN_SPEED_MULTIPLIER
	elseif sprintKeyHeld then
		humanoid.WalkSpeed = SPRINT_SPEED
	else
		humanoid.WalkSpeed = DEFAULT_SPEED
	end
	print("StaminaUI: 暴冲完成，速度恢复到: " .. humanoid.WalkSpeed)

	-- 停止暴冲动画
	if rollAnimationTrack then
		rollAnimationTrack:Stop()
		print("StaminaUI: 停止暴冲动画。")
	end
end

-- <<<<<< 物品栏选择逻辑 >>>>>>
-- 辅助函数：获取玩家背包和角色中所有工具的列表
local function getAllToolsInInventory()
	local tools = {}
	-- 从背包中获取工具
	for _, child in ipairs(player.Backpack:GetChildren()) do
		if child:IsA("Tool") then
			table.insert(tools, child)
		end
	end
	-- 从角色中获取当前装备的工具
	local equippedTool = getEquippedTool()
	if equippedTool and not table.find(tools, equippedTool) then -- 避免重复添加
		table.insert(tools, equippedTool)
	end
	print("StaminaUI: getAllToolsInInventory 找到 " .. #tools .. " 个工具。") -- 新增调试
	for i, tool in ipairs(tools) do
		print("StaminaUI: 工具[" .. i .. "]: " .. tool.Name) -- 新增调试
	end
	return tools
end

-- 更新物品栏UI显示 (高亮、图标、名称)
local function updateInventoryUI()
	print("StaminaUI: updateInventoryUI 函数被调用。") -- 新增调试
	-- 清除所有槽位的高亮和内容
	for _, slotFrame in ipairs(inventorySlots) do
		local uiStroke = slotFrame:FindFirstChild("SlotStroke")
		if uiStroke then
			uiStroke.Color = DEFAULT_STROKE_COLOR -- 默认边框颜色
			uiStroke.Transparency = 0 -- 确保默认边框可见
			uiStroke.Thickness = DEFAULT_STROKE_THICKNESS -- 默认边框粗细
		end
		slotFrame.BackgroundTransparency = 0.1 -- 默认透明度
		local itemIcon = slotFrame:FindFirstChild("ItemIcon")
		local itemNameLabel = slotFrame:FindFirstChild("ItemNameLabel")
		if itemIcon then itemIcon.Image = "rbxassetid://0" end
		if itemNameLabel then itemNameLabel.Text = "" end
	end

	-- 重新获取当前所有工具
	currentToolsInInventory = getAllToolsInInventory()
	print("StaminaUI: updateInventoryUI - currentToolsInInventory 包含 " .. #currentToolsInInventory .. " 个工具。") -- 新增调试

	-- 填充槽位并高亮当前选中的槽位
	for i = 1, MAX_INVENTORY_SLOTS do -- 循环遍历所有9个槽位
		local slotFrame = inventorySlots[i]
		local tool = currentToolsInInventory[i] -- 尝试获取对应槽位的工具
		if slotFrame then
			local itemIcon = slotFrame:FindFirstChild("ItemIcon")
			local itemNameLabel = slotFrame:FindFirstChild("ItemNameLabel")
			if tool then -- 如果有工具，则显示工具信息
				if itemIcon then
					itemIcon.Image = tool.TextureId or "rbxassetid://0" -- 使用工具的TextureId或默认图标
				end
				if itemNameLabel then
					itemNameLabel.Text = tool.Name -- 显示工具名称
				end
				print("StaminaUI: 槽位 " .. i .. " 填充工具: " .. tool.Name) -- 新增调试
			else -- 如果没有工具，则清空图标和名称
				if itemIcon then itemIcon.Image = "rbxassetid://0" end
				if itemNameLabel then itemNameLabel.Text = "" end
				print("StaminaUI: 槽位 " .. i .. " 没有工具。") -- 新增调试
			end
			-- 高亮当前选中的槽位 (无论是否有工具)
			if i == currentSlotIndex then
				local uiStroke = slotFrame:FindFirstChild("SlotStroke")
				if uiStroke then
					uiStroke.Color = HIGHLIGHT_COLOR -- 边框高亮 (白色)
					uiStroke.Transparency = 0 -- 确保边框可见
					uiStroke.Thickness = 2.5 -- 增加边框粗细，使其更明显
					print("StaminaUI: 槽位 " .. i .. " 已高亮。") -- 新增调试
				else
					warn("StaminaUI: 槽位 " .. i .. " 未找到 SlotStroke 进行高亮。") -- 新增警告
				end
				slotFrame.BackgroundTransparency = 0.05 -- 稍微降低透明度，使其更显眼
			end
		end
	end
end

-- 装备指定槽位的工具
local function equipToolInSlot(slotIndex)
	print("StaminaUI: equipToolInSlot 函数被调用，尝试装备槽位: " .. slotIndex) -- 新增调试
	local numTools = #currentToolsInInventory
	local toolToEquip = currentToolsInInventory[slotIndex] -- 尝试获取对应槽位的工具
	local currentlyEquipped = getEquippedTool()
	if toolToEquip then -- 如果该槽位有工具
		print("StaminaUI: 槽位 " .. slotIndex .. " 有工具: " .. toolToEquip.Name) -- 新增调试
		if currentlyEquipped ~= toolToEquip then -- 检查当前是否已经装备了该工具
			if humanoid and currentlyEquipped then -- 如果有当前装备的工具，先卸下
				humanoid:UnequipTools()
				print("StaminaUI: 已卸下当前工具: " .. currentlyEquipped.Name)
			end
			if humanoid then -- 确保humanoid存在再装备
				humanoid:EquipTool(toolToEquip)
				print("StaminaUI: 已装备工具: " .. toolToEquip.Name)
			else
				warn("StaminaUI: 无法装备工具，Humanoid不存在。")
			end
		else
			print("StaminaUI: 工具 '" .. toolToEquip.Name .. "' 已经装备。")
		end
	else -- 如果该槽位没有工具
		print("StaminaUI: 槽位 " .. slotIndex .. " 没有可装备的工具。") -- 新增调试
		if humanoid and currentlyEquipped then -- 如果当前有工具装备，则卸下
			humanoid:UnequipTools()
			print("StaminaUI: 槽位无工具，已卸下当前工具: " .. currentlyEquipped.Name)
		end
	end
	updateInventoryUI() -- 更新UI高亮
end

-- 初始更新物品栏UI
task.spawn(function()
	task.wait(0.5) -- 稍作等待，确保所有工具加载
	updateInventoryUI()
	equipToolInSlot(currentSlotIndex) -- 初始装备第一个槽位的工具
end)

-- 监听背包和角色变化，实时更新物品栏
player.Backpack.ChildAdded:Connect(function(child)
	if child:IsA("Tool") then
		print("StaminaUI: 背包新增工具: " .. child.Name .. "，更新物品栏。")
		updateInventoryUI()
	end
end)

player.Backpack.ChildRemoved:Connect(function(child)
	if child:IsA("Tool") then
		print("StaminaUI: 背包移除工具: " .. child.Name .. "，更新物品栏。")
		updateInventoryUI()
	end
end)

-- 监听角色子级变化，处理工具装备/卸下
if character then
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			print("StaminaUI: 角色装备工具: " .. child.Name .. "，更新物品栏。")
			updateInventoryUI()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			print("StaminaUI: 角色卸下工具: " .. child.Name .. "，更新物品栏。")
			updateInventoryUI()
		end
	end)
end

-- 监听玩家输入
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	-- 检查是否被游戏处理、是否被脚本阻塞
	if gameProcessedEvent and input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then -- 左Shift冲刺
		sprintKeyHeld = true -- 标记冲刺键被按下
		print("StaminaUI: LeftShift 按下。")
	elseif input.KeyCode == Enum.KeyCode.LeftControl then -- 左Ctrl暴冲
		doBurst() -- 调用暴冲函数
	elseif input.KeyCode == Enum.KeyCode.W then
		isWPressed = true
	elseif input.KeyCode == Enum.KeyCode.A then
		isAPressed = true
	elseif input.KeyCode == Enum.KeyCode.S then
		isSPressed = true
	elseif input.KeyCode == Enum.KeyCode.D then
		isDPressed = true
	elseif input.KeyCode.Value >= Enum.KeyCode.One.Value and input.KeyCode.Value <= Enum.KeyCode.Nine.Value then
		local slotNumber = input.KeyCode.Value - Enum.KeyCode.Zero.Value -- 将 KeyCode.One 转换为 1，KeyCode.Two 转换为 2，以此类推
		print("StaminaUI: 键盘数字键 " .. slotNumber .. " 输入检测到。")
		-- 允许选择任何槽位，无论是否有工具
		if slotNumber >= 1 and slotNumber <= MAX_INVENTORY_SLOTS then
			currentSlotIndex = slotNumber
			equipToolInSlot(currentSlotIndex)
		else
			print("StaminaUI: 槽位 " .. slotNumber .. " 超出有效槽位范围 (1-" .. MAX_INVENTORY_SLOTS .. ")。")
		end
	elseif input.KeyCode == Enum.KeyCode.CapsLock then -- CAPS LOCK 切换鼠标锁定状态
		isCameraLocked = not isCameraLocked
		if humanoid then -- <<<<<< 确保humanoid存在 >>>>>>
			-- <<<<<< 移除 pcall，因为不再设置 CameraMinZoomDistance/MaxZoomDistance >>>>>>
			if isCameraLocked then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				UserInputService.MouseIconEnabled = false
				print("StaminaUI: 摄像机锁定，鼠标隐藏 (切换到默认第一人称)。")
			else
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
				print("StaminaUI: 摄像机解锁，鼠标显示 (切换到默认第三人称)。")
			end
			-- <<<<<< 移除对 setCameraZoomProperties 的调用 >>>>>>
			-- setCameraZoomProperties()
		else
			warn("StaminaUI: Humanoid is nil when attempting to change camera properties via CapsLock.")
		end
	elseif input.KeyCode == Enum.KeyCode.Space then -- 空格键跳跃
		if isStunned then
			print("StaminaUI: 玩家处于眩晕状态，无法跳跃。")
			return -- 阻塞跳跃输入
		end
		-- <<<<<< 物品栏选择输入 >>>>>>
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		local scrollDelta = input.Position.Z -- 鼠标滚轮滚动方向 (正值向上，负值向下)
		print("StaminaUI: 鼠标滚轮输入检测到。Delta: " .. scrollDelta)
		if scrollDelta > 0 then -- 向上滚动 (格数-1)
			currentSlotIndex = (currentSlotIndex - 2 + MAX_INVENTORY_SLOTS) % MAX_INVENTORY_SLOTS + 1
		else -- 向下滚动 (格数+1)
			currentSlotIndex = (currentSlotIndex % MAX_INVENTORY_SLOTS) + 1
		end
		print("StaminaUI: 鼠标滚轮选择槽位: " .. currentSlotIndex)
		equipToolInSlot(currentSlotIndex)
	elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then -- 右箭头或D键 (下一个槽位)
		print("StaminaUI: 键盘右/D键输入检测到。")
		currentSlotIndex = (currentSlotIndex % MAX_INVENTORY_SLOTS) + 1
		print("StaminaUI: 键盘右/D键选择槽位: " .. currentSlotIndex)
		equipToolInSlot(currentSlotIndex)
	elseif input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then -- 左箭头或A键 (上一个槽位)
		print("StaminaUI: 键盘左/A键输入检测到。")
		currentSlotIndex = (currentSlotIndex - 2 + MAX_INVENTORY_SLOTS) % MAX_INVENTORY_SLOTS + 1
		print("StaminaUI: 键盘左/A键选择槽位: " .. currentSlotIndex)
		equipToolInSlot(currentSlotIndex)
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
	-- 检查是否被游戏处理、是否被脚本阻塞
	if gameProcessedEvent then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprintKeyHeld = false -- 标记冲刺键松开
	elseif input.KeyCode == Enum.KeyCode.W then
		isWPressed = false
	elseif input.KeyCode == Enum.KeyCode.A then
		isAPressed = false
	elseif input.KeyCode == Enum.KeyCode.S then
		isSPressed = false
	elseif input.KeyCode == Enum.KeyCode.D then
		isDPressed = false
	end
end)

-- 每帧检查冲刺状态并消耗体力，并管理速度
RunService.Heartbeat:Connect(function(deltaTime)
	if not humanoid then return end -- 确保humanoid存在
	local isMoving = humanoid.MoveDirection.Magnitude > 0
	local shouldSprint = sprintKeyHeld and isMoving and currentStamina > 0 and not isStunned and not isRolling
	if shouldSprint then
		if not isSprinting then
			isSprinting = true
			print("StaminaUI: 开始冲刺 (Heartbeat)。")
		end
		humanoid.WalkSpeed = SPRINT_SPEED
		RequestStaminaConsumptionEvent:FireServer(SPRINT_STAMINA_COST_PER_SECOND * deltaTime)
	else
		if isSprinting then
			isSprinting = false
			print("StaminaUI: 停止冲刺 (Heartbeat)。")
		end
		-- 只有在不暴冲时才根据眩晕状态恢复速度
		if not isRolling then
			if isStunned then
				humanoid.WalkSpeed = DEFAULT_SPEED * STUN_SPEED_MULTIPLIER
			else
				humanoid.WalkSpeed = DEFAULT_SPEED
			end
		end
	end
end)

-- 移动向量计算和摄像机更新 (RenderStepped)
RunService.RenderStepped:Connect(function(deltaTime)
	if not humanoid or not humanoid.Parent or not Camera then return end
	local rootPart = humanoid.Parent:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart.CFrame then return end -- Ensure rootPart and its CFrame are valid

	-- Ensure Camera is Custom (default Roblox behavior)
	if Camera.CameraType ~= Enum.CameraType.Custom then
		Camera.CameraType = Enum.CameraType.Custom
		Camera.CameraSubject = humanoid
		print("StaminaUI: 摄像机类型设置为 Custom。")
	end

	-- <<<<<< 新增：角色跟随摄像机水平方向旋转 >>>>>>
	local cameraCFrame = Camera.CFrame
	local lookVector = cameraCFrame.LookVector
	-- 获取摄像机的水平朝向，忽略Y轴分量
	local flatLookVector = Vector3.new(lookVector.X, 0, lookVector.Z).Unit

	-- 创建一个新的CFrame，保持HumanoidRootPart的Y轴位置，并使其Z轴（前方）指向flatLookVector
	local newCFrame = CFrame.new(rootPart.Position, rootPart.Position + flatLookVector)
	rootPart.CFrame = newCFrame
	-- print("StaminaUI: 角色已旋转以跟随摄像机方向。") -- 调试日志，如果太频繁可以注释掉

	-- --- 手动构建原始输入向量 (局部坐标) ---
	local rawInputVector = Vector3.new(0,0,0)
	if isWPressed then rawInputVector = rawInputVector + Vector3.new(0,0,-1) end -- Forward
	if isSPressed then rawInputVector = rawInputVector + Vector3.new(0,0,1) end  -- Backward
	if isAPressed then rawInputVector = rawInputVector + Vector3.new(-1,0,0) end -- Left
	if isDPressed then rawInputVector = rawInputVector + Vector3.new(1,0,0) end  -- Right

	-- 归一化原始输入向量
	if rawInputVector.Magnitude > 0 then
		rawInputVector = rawInputVector.Unit
	end

	local cameraLookVector = Camera.CFrame.LookVector
	local cameraRightVector = Camera.CFrame.RightVector
	local flatCameraLookVector = Vector3.new(cameraLookVector.X, 0, cameraLookVector.Z).Unit
	local flatCameraRightVector = Vector3.new(cameraRightVector.X, 0, cameraRightVector.Z).Unit

	local worldMoveVector = Vector3.new(0,0,0)
	if rawInputVector.Z ~= 0 then
		worldMoveVector = worldMoveVector + flatCameraLookVector * -rawInputVector.Z
	end
	if rawInputVector.X ~= 0 then
		worldMoveVector = worldMoveVector + flatCameraRightVector * rawInputVector.X
	end
	if worldMoveVector.Magnitude > 0 then
		worldMoveVector = worldMoveVector.Unit
	end

	-- <<<<<< 预移动碰撞检测和移动向量调整 (实现沿墙滑动) >>>>>>
	local adjustedMoveVector = worldMoveVector
	local collisionResult = nil
	-- 从HumanoidRootPart中心稍微向上一点的位置发射射线
	local collisionRayOrigin = rootPart.Position + Vector3.new(0, 0.5, 0)
	-- 射线检测距离：略大于当前帧可能移动的距离，加上一个小的缓冲
	local collisionRayDistance = humanoid.WalkSpeed * deltaTime * 1.5 + 0.1
	local collisionRayDirection = worldMoveVector.Unit -- 使用单位向量作为方向
	if collisionRayDirection.Magnitude > 0 then -- 只有当有实际移动意图时才进行射线检测
		local collisionRaycastParams = RaycastParams.new()
		collisionRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
		collisionRaycastParams.FilterDescendantsInstances = {character} -- 排除玩家自己的角色
		collisionRaycastParams.IgnoreWater = true
		collisionResult = workspace:Raycast(collisionRayOrigin, collisionRayDirection * collisionRayDistance, collisionRaycastParams)
		if collisionResult then
			local hitNormal = collisionResult.Normal
			-- 将期望的移动向量投影到与碰撞法线垂直的平面上
			-- 这会移除直接撞向墙壁的移动分量，只保留沿墙滑动的分量
			adjustedMoveVector = worldMoveVector - (worldMoveVector:Dot(hitNormal)) * hitNormal
			-- 如果投影后的向量非常小，说明是直接撞墙，没有滑动空间
			if adjustedMoveVector.Magnitude < 0.01 then -- 设定一个阈值
				adjustedMoveVector = Vector3.new(0,0,0) -- 停止移动
			else
				adjustedMoveVector = adjustedMoveVector.Unit -- 投影后重新归一化
			end
			print("StaminaUI: 检测到碰撞，正在调整移动向量。原始: " .. tostring(worldMoveVector) .. ", 调整后: " .. tostring(adjustedMoveVector))
		end
	end
	humanoid:Move(adjustedMoveVector) -- 使用调整后的向量进行移动
end)

print("StaminaUI 客户端脚本已加载完成。")
