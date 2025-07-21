-- 文件名: StarterPack/MP5K/GunLocalScript.lua
-- 放置位置: Tool (例如 MP5K) 内部
-- 这是一个客户端脚本，处理枪械的装备、卸下、射击输入和视图模型定位。

print("GunLocalScript: 脚本文件开始加载。") -- 确认脚本是否被加载和执行

-- 增加一个短暂的等待，确保脚本有足够时间初始化
task.wait(0.05) 
print("GunLocalScript: 脚本已初始化，准备连接事件。")

local Tool = script.Parent -- 获取父级 Tool 对象

-- <<<<<< 关键修改：设置 Tool.RequiresHandle 为 false >>>>>>
-- 这会告诉 Roblox 不要尝试自动处理工具的握持和焊接，避免与我们自定义的视图模型逻辑冲突。
Tool.RequiresHandle = false
print("GunLocalScript: Tool.RequiresHandle 已设置为: " .. tostring(Tool.RequiresHandle))

local FireRemoteEvent = Tool:WaitForChild("RemoteEvent", 5) -- 获取 Tool 内部的 RemoteEvent，增加等待时间
if not FireRemoteEvent then
	warn("GunLocalScript: 警告：在工具 '" .. Tool.Name .. "' 中未找到名为 'RemoteEvent' 的 RemoteEvent。射击功能将无法工作。")
	return -- 如果找不到 RemoteEvent，则停止脚本执行
end
print("GunLocalScript: 已找到 RemoteEvent。")

local player = game:GetService("Players").LocalPlayer
local mouse = player:GetMouse() -- 获取玩家鼠标
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera -- 获取当前摄像机

local isEquipped = false
local isFiring = false -- 是否正在开火
local fireRate = 3 -- 每秒3发子弹
local fireDelay = 1 / fireRate -- 每发子弹的延迟时间
local lastFireTime = 0 -- 上次开火的时间

-- 获取 FirePoint 部件
local FirePoint = Tool:FindFirstChild("Handle"):FindFirstChild("FirePoint")
if not FirePoint then
	warn("GunLocalScript: 警告：在工具 '" .. Tool.Name .. "' 的 Handle 中未找到名为 'FirePoint' 的部件。射击功能将无法工作。")
	return
end
print("GunLocalScript: 已找到 FirePoint。")

-- 找到 Handle 部件
local Handle = Tool:FindFirstChild("Handle")
if not Handle then
	warn("GunLocalScript: 警告：在工具 '" .. Tool.Name .. "' 中未找到名为 'Handle' 的部件！视图模型将无法工作。")
	return
end
print("GunLocalScript: 已找到 Handle 部件。")

local renderSteppedConnection = nil -- 用于存储 RenderStepped 连接
local viewmodelAttachment = nil -- 新增：用于存储视图模型 Attachment
local viewmodelWeld = nil -- 新增：用于存储视图模型 WeldConstraint

-- <<<<<< 视图模型偏移量 (需要根据您的枪械模型进行微调) >>>>>>
-- 这些值是枪械相对于摄像机的局部偏移量和旋转。
-- 它们将决定枪械在屏幕上的最终位置和角度。
-- 调整为更低、更近的默认值，并重置倾斜和翻滚角度
local VIEWMODEL_OFFSET_CFrame = CFrame.new(
	0.5,    -- X: 左右 (正右，负左) - 稍微向右
	-0.8,   -- Y: 上下 (正上，负下) - 大幅度向下
	-0.5    -- Z: 前后 (正后，负前) - 大幅度向前 (靠近摄像机)
) * CFrame.Angles(
	math.rad(0), -- X旋转 (Roll): 绕枪械长度方向旋转 (正顺时针，负逆时针) - 设为0
	math.rad(90), -- Y旋转 (Yaw): 绕垂直轴旋转 (枪口向前通常是90度或-90度)
	math.rad(0)    -- Z旋转 (Pitch): 绕水平轴旋转 (正向上，负向下) - 设为0
)

-- 当工具被装备时
Tool.Equipped:Connect(function()
	isEquipped = true
	print("GunLocalScript: Tool.Equipped 事件被触发！枪械已装备。")
	isFiring = false -- 确保装备时停止开火

	-- <<<<<< 销毁所有 Motor6D、Weld 以及其他常见物理约束实例 >>>>>>
	local function destroyPhysicsInstances(instance)
		for _, child in ipairs(instance:GetChildren()) do
			if child:IsA("Motor6D") or child:IsA("Weld") or 
				child:IsA("WeldConstraint") or child:IsA("BallSocketConstraint") or
				child:IsA("HingeConstraint") or child:IsA("PrismaticConstraint") or
				child:IsA("CylindricalConstraint") or child:IsA("SpringConstraint") then
				print("GunLocalScript: (Equipped) 销毁冲突连接/约束: " .. child.Name .. " (" .. child.ClassName .. ") 在 " .. instance.Name)
				child:Destroy()
			end
		end
	end

	destroyPhysicsInstances(Handle) -- 销毁 Handle 中的物理实例
	destroyPhysicsInstances(Tool)    -- 销毁 Tool 中的物理实例 (以防万一)

	-- <<<<<< 关键修改：创建 Attachment 和 WeldConstraint >>>>>>
	-- 创建一个 Attachment 并父级化到 Camera
	viewmodelAttachment = Instance.new("Attachment")
	viewmodelAttachment.Name = "ViewModelAttachment"
	viewmodelAttachment.Parent = Camera
	print("GunLocalScript: (Equipped) ViewModelAttachment 已创建并父级设置为 Camera。")

	-- 创建 WeldConstraint 连接 Handle 和 ViewModelAttachment
	viewmodelWeld = Instance.new("WeldConstraint")
	viewmodelWeld.Name = "ViewModelWeld"
	viewmodelWeld.Part0 = Handle
	viewmodelWeld.Part1 = viewmodelAttachment
	viewmodelWeld.Parent = Handle -- 将 WeldConstraint 父级设置为 Handle
	print("GunLocalScript: (Equipped) ViewModelWeld 已创建并连接 Handle 和 ViewModelAttachment。")

	-- 确保 Handle 的物理属性正确设置
	Handle.Anchored = false -- WeldConstraint 会处理连接，Handle 不需要锚定
	Handle.CanCollide = false
	Handle.Massless = true
	Handle.Transparency = 0 -- 确保可见

	print("GunLocalScript: (Equipped) Handle.CanCollide: " .. tostring(Handle.CanCollide) .. 
		", Handle.Massless: " .. tostring(Handle.Massless))

	-- 连接 RenderStepped 事件，每帧更新 Attachment 的 CFrame
	renderSteppedConnection = RunService.RenderStepped:Connect(function()
		if Camera and viewmodelAttachment and viewmodelAttachment.Parent == Camera then -- 确保 Attachment 仍然是 Camera 的子级
			-- 持续确保 Handle 的 CanCollide 为 false
			if Handle and Handle.CanCollide then
				Handle.CanCollide = false
				-- print("GunLocalScript: (RenderStepped) 强制 Handle.CanCollide 为 false。") -- 减少日志刷屏
			end

			-- 更新 ViewModelAttachment 的 CFrame，Handle 会通过 WeldConstraint 跟随
			viewmodelAttachment.CFrame = Camera.CFrame * VIEWMODEL_OFFSET_CFrame
		else
			-- 如果 Attachment 不存在或不再是 Camera 的子级，断开连接以避免错误
			if renderSteppedConnection then
				renderSteppedConnection:Disconnect()
				renderSteppedConnection = nil
				print("GunLocalScript: ViewModelAttachment 不存在或已移除/父级改变，断开 RenderStepped 连接。")
			end
		end
	end)
	print("GunLocalScript: 已启动 RenderStepped 连接以更新视图模型。")
end)

-- 当工具被卸下时
Tool.Unequipped:Connect(function()
	isEquipped = false
	print("GunLocalScript: Tool.Unequipped 事件被触发！枪械已卸下。")
	isFiring = false -- 卸下时停止开火

	-- <<<<<< 视图模型清理逻辑 >>>>>>
	if renderSteppedConnection then
		renderSteppedConnection:Disconnect() -- 断开 RenderStepped 连接
		renderSteppedConnection = nil
		print("GunLocalScript: 已断开 RenderStepped 连接。")
	end

	-- 销毁创建的 Attachment 和 WeldConstraint
	if viewmodelWeld then
		viewmodelWeld:Destroy()
		viewmodelWeld = nil
		print("GunLocalScript: ViewModelWeld 已销毁。")
	end
	if viewmodelAttachment then
		viewmodelAttachment:Destroy()
		viewmodelAttachment = nil
		print("GunLocalScript: ViewModelAttachment 已销毁。")
	end

	-- 恢复 Handle 的物理属性，使其可以被 Roblox 默认工具系统处理 (如果需要)
	if Handle then
		Handle.Anchored = false -- 恢复为非固定
		Handle.Parent = Tool -- 恢复父级到 Tool
		print("GunLocalScript: (Unequipped) Handle.Anchored 已恢复为 false，父级恢复为 Tool。")
	end
end)

-- 监听鼠标左键按下
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 and isEquipped then
		isFiring = true
		print("GunLocalScript: 鼠标左键按下，开始尝试开火。")
	end
end)

-- 监听鼠标左键松开
UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isFiring = false
		print("GunLocalScript: 鼠标左键松开，停止开火。")
	end
end)

-- 每帧检查是否需要开火 (RenderStepped 确保在渲染前更新)
RunService.RenderStepped:Connect(function()
	if isFiring and isEquipped then
		local currentTime = tick()
		if currentTime - lastFireTime >= fireDelay then
			-- 向服务器发送射击请求，并传递鼠标在世界中的位置 和 FirePoint 的世界位置
			-- FirePoint.WorldPosition 即使 Handle 父级为 Camera 也能正常工作
			FireRemoteEvent:FireServer(mouse.Hit.p, FirePoint.WorldPosition) -- <<<<<< 关键修改
			print("GunLocalScript: 已发送射击请求到服务器。鼠标位置: " .. tostring(mouse.Hit.p) .. ", FirePoint位置: " .. tostring(FirePoint.WorldPosition))
			lastFireTime = currentTime

			-- <<<<<< 客户端调试：可视化客户端射线 (修改为逐渐淡化的白色轨迹) >>>>>>
			local debugPart = Instance.new("Part")
			debugPart.Name = "ClientBulletTrail" -- 更名为轨迹
			debugPart.BrickColor = BrickColor.new("White") -- 白色
			debugPart.Transparency = 0.5 -- 初始透明度
			debugPart.CanCollide = false
			debugPart.Anchored = true
			debugPart.Massless = true

			local startPos = FirePoint.WorldPosition
			local endPos = mouse.Hit.p
			local direction = (endPos - startPos).Unit
			local distance = (endPos - startPos).Magnitude

			debugPart.Size = Vector3.new(0.1, 0.1, distance) -- 细长的轨迹
			debugPart.CFrame = CFrame.new(startPos:Lerp(endPos, 0.5), endPos)
			debugPart.Parent = workspace

			-- 使用 TweenService 实现渐变消失效果
			local TweenService = game:GetService("TweenService")
			local tweenInfo = TweenInfo.new(
				0.3, -- 持续时间 (例如 0.3 秒)
				Enum.EasingStyle.Linear, -- 缓动样式
				Enum.EasingDirection.Out, -- 缓动方向
				0, -- 重复次数
				false, -- 是否反向
				0 -- 延迟
			)
			local goal = {Transparency = 1} -- 目标透明度为完全透明

			local transparencyTween = TweenService:Create(debugPart, tweenInfo, goal)
			transparencyTween:Play()

			-- 在动画结束后销毁部件
			transparencyTween.Completed:Connect(function()
				if debugPart and debugPart.Parent then
					debugPart:Destroy()
				end
			end)

			print("GunLocalScript: 客户端调试轨迹已创建并开始淡化。")
		end
	end
end)

print("GunLocalScript: 脚本文件已加载完成。")
