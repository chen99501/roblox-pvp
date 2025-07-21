-- 文件名: StarterPack/MP5K/GunServerScript.lua
-- 放置位置: Tool (例如 MP5K) 内部
-- 这是一个服务器脚本，处理枪械的射击逻辑和伤害计算。

local Pistol = script.Parent -- 现在 Pistol 指向的是 Tool 对象
local FireRemoteEvent = Pistol:WaitForChild("RemoteEvent") -- 获取 Tool 内部的 RemoteEvent

local BULLET_SPEED = 200 -- 子弹飞行速度 (studs/秒)
local BULLET_LIFETIME = 5 -- 子弹存在时间 (秒)
local BULLET_DAMAGE = 40 -- 子弹伤害
local BULLET_INITIAL_NO_COLLIDE_TIME = 0.5 -- 不碰撞时间
local BULLET_SIZE = Vector3.new(0.1, 0.1, 0.3) -- 子弹大小

-- <<<<<< 关键修改：OnServerEvent 现在接收 FirePointWorldPosition >>>>>>
FireRemoteEvent.OnServerEvent:Connect(function(player, MousePosition, FirePointWorldPosition) -- 开火远程事件被触发
	print("--- GunServerScript: 收到射击请求 ---")
	print("玩家: " .. player.Name .. ", 鼠标位置: " .. tostring(MousePosition))
	print("客户端提供的 FirePoint 世界位置: " .. tostring(FirePointWorldPosition)) -- 打印客户端提供的 FirePoint 位置

	-- 确保 Handle 和 FireSound 存在 (FirePoint 不再需要服务器端查找，因为客户端已提供其位置)
	local Handle = Pistol:FindFirstChild("Handle")
	local FireSound = Handle:FindFirstChild("FireSound")

	if not Handle then
		warn("GunServerScript: 缺少 Handle 部件！")
		return
	end
	if not FireSound then
		warn("GunServerScript: 缺少 FireSound 部件！")
		return
	end

	FireSound:Play() -- 开火音效

	local StartPosition = FirePointWorldPosition -- <<<<<< 使用客户端提供的 FirePoint 世界位置
	local Direction = (MousePosition - StartPosition).Unit -- 子弹飞行方向

	print("子弹初始位置 (StartPosition): " .. tostring(StartPosition))
	print("子弹飞行方向 (Direction): " .. tostring(Direction))

	if Direction.Magnitude == 0 then
		warn("GunServerScript: 子弹方向向量为零，无法创建子弹。可能是鼠标位置与开火点相同。")
		return
	end

	-- <<<<<< 使用 Raycast 找到击中点 >>>>>>
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {player.Character, Pistol} -- 忽略玩家自身和枪
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	local raycastResult = workspace:Raycast(StartPosition, Direction * 500, raycastParams) -- 500 是射程
	local HitPosition = MousePosition -- 默认击中鼠标位置
	if raycastResult then
		HitPosition = raycastResult.Position -- 如果击中物体，则更新击中位置
		print("GunServerScript: Raycast 击中部件: " .. tostring(raycastResult.Instance.Name) .. " 位置: " .. tostring(HitPosition))
	else
		print("GunServerScript: Raycast 没有击中任何物体，使用鼠标位置。")
	end

	-- <<<<<< 创建子弹实体 (关键修改：先创建，设置属性，再父级化) >>>>>>
	local bullet = Instance.new("Part")
	bullet.Name = "DEBUG_BULLET" -- 调试修改：子弹名称改为 DEBUG_BULLET，方便在 Explorer 中查找
	bullet.BrickColor = BrickColor.new("Really red") -- 调试修改：改为最亮的红色
	bullet.Size = BULLET_SIZE -- 使用常量
	bullet.Shape = Enum.PartType.Block
	bullet.Massless = true -- 没有质量，不受重力影响
	bullet.Anchored = false -- 不固定，可以移动
	bullet.CanCollide = false -- 初始设置为 false，不与任何物体碰撞
	bullet.Transparency = 1 -- <<<<<< 关键修改：将子弹透明度设置为 1，使其不可见

	-- 在 FirePoint 位置基础上，向前偏移 0.5 Studs 生成子弹
	bullet.CFrame = CFrame.new(StartPosition + Direction * 0.5, StartPosition + Direction) -- 设置初始位置和朝向

	-- 先连接 Touched 事件，再设置父级，以确保事件监听器在子弹进入 Workspace 时就准备好
	local hasHit = false -- 标记是否已经击中过目标，防止重复伤害
	local touchedConnection -- 存储连接，以便之后断开

	touchedConnection = bullet.Touched:Connect(function(hitPart)
		print("--- 子弹触碰事件触发 ---")
		print("击中部件名称: " .. hitPart.Name)
		print("击中部件类名: " .. hitPart.ClassName) -- 增加类名打印
		if hitPart.Parent then
			print("击中部件父级名称: " .. hitPart.Parent.Name) -- 增加父级名称打印
			if hitPart.Parent.Parent then
				print("击中部件祖父级名称: " .. hitPart.Parent.Parent.Name) -- 增加祖父级名称打印
			end
		end

		if hasHit then
			print("子弹已击中过目标，跳过重复处理。")
			return
		end

		-- 检查是否击中了玩家角色，并且不是射击者自己
		local characterHit = hitPart.Parent
		local humanoidHit = characterHit:FindFirstChildWhichIsA("Humanoid")

		-- 确保忽略所有枪械部件，而不仅仅是 Handle
		local isGunPart = false
		if Pistol:IsAncestorOf(hitPart) then -- 检查 hitPart 是否是枪械的子孙
			isGunPart = true
		end

		if isGunPart or (characterHit and characterHit == player.Character) then
			print("GunServerScript: 忽略与枪械部件或射击者自身的碰撞。")
			return
		end

		if humanoidHit then -- 击中Humanoid，且不是射击者自己（已在上面过滤）
			humanoidHit:TakeDamage(BULLET_DAMAGE)
			print("GunServerScript: 子弹击中 " .. characterHit.Name .. "，造成 " .. BULLET_DAMAGE .. " 伤害。")
			hasHit = true
		else
			print("GunServerScript: 子弹击中非玩家角色部件。")
		end

		if bullet and bullet.Parent then
			bullet:Destroy()
			print("--- 子弹已销毁。---")
			if touchedConnection then touchedConnection:Disconnect() end -- 销毁时断开连接
		end
	end)

	bullet.Parent = workspace -- 最后将子弹放入 Workspace
	print("--- 子弹创建成功 ---")
	print("子弹名称: " .. bullet.Name)
	print("子弹父级: " .. tostring(bullet.Parent))
	print("子弹初始CFrame: " .. tostring(bullet.CFrame))
	print("子弹实际世界位置 (Parented): " .. tostring(bullet.Position))
	print("子弹实际CFrame (Parented): " .. tostring(bullet.CFrame))

	-- 持续打印子弹位置，用于调试 (暂时注释掉，避免刷屏)
	local debugConnection
	debugConnection = game:GetService("RunService").Heartbeat:Connect(function()
		if bullet and bullet.Parent == workspace then
			-- print("DEBUG_BULLET 位置: " .. tostring(bullet.Position))
		else
			if debugConnection then debugConnection:Disconnect() end -- 子弹不存在或不在 workspace 时停止打印
		end
	end)

	-- 在短暂延迟后重新启用 CanCollide
	task.delay(BULLET_INITIAL_NO_COLLIDE_TIME, function()
		if bullet and bullet.Parent then -- 确保子弹仍然存在
			bullet.CanCollide = true
			print("GunServerScript: 子弹 CanCollide 已重新启用。")
		end
	end)

	-- 为 LinearVelocity 添加 Attachment
	local attachment = Instance.new("Attachment")
	attachment.Parent = bullet
	print("GunServerScript: Attachment 已创建并父级设置为子弹。")

	-- 添加 LinearVelocity 来推动子弹
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.VectorVelocity = Direction * BULLET_SPEED -- 设置速度向量
	linearVelocity.MaxForce = math.huge -- 确保有足够的力来推动
	linearVelocity.Parent = bullet
	print("GunServerScript: LinearVelocity 已创建并父级设置为子弹。VectorVelocity: " .. tostring(linearVelocity.VectorVelocity))

	-- <<<<<< 子弹生命周期管理 (防止子弹无限飞行) >>>>>>
	task.delay(BULLET_LIFETIME, function()
		if bullet and bullet.Parent then
			bullet:Destroy()
			print("--- 子弹因超时已销毁。---")
			if touchedConnection then touchedConnection:Disconnect() end -- 销毁时断开连接
		end
	end)
end)

print("GunServerScript 服务器脚本已加载。")
