local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local chopEvent = ReplicatedStorage:WaitForChild("ChopTree")
local popupEvent = ReplicatedStorage:FindFirstChild("ShowWoodPopup")
if not popupEvent then
	popupEvent = Instance.new("RemoteEvent")
	popupEvent.Name = "ShowWoodPopup"
	popupEvent.Parent = ReplicatedStorage
end

local healthEvent = ReplicatedStorage:FindFirstChild("UpdateHealthBar")
if not healthEvent then
	healthEvent = Instance.new("RemoteEvent")
	healthEvent.Name = "UpdateHealthBar"
	healthEvent.Parent = ReplicatedStorage
end

local treeEffectEvent = ReplicatedStorage:FindFirstChild("TreeEffectEvent")
if not treeEffectEvent then
	treeEffectEvent = Instance.new("RemoteEvent")
	treeEffectEvent.Name = "TreeEffectEvent"
	treeEffectEvent.Parent = ReplicatedStorage
end

local AxeData = nil
pcall(function()
	AxeData = require(ReplicatedStorage:WaitForChild("AxeData", 2))
end)

local TREE_CONFIG = {
	["Tree1-3"] = { MaxHealth = 6, DropCount = 2, RewardPerDrop = 2, MaxDistance = 12 },
	["Tree1-2"] = { MaxHealth = 9, DropCount = 3, RewardPerDrop = 3, MaxDistance = 15 },
	["Tree1-1"] = { MaxHealth = 20, DropCount = 3, RewardPerDrop = 5, MaxDistance = 19 },
}
local DEFAULT_CONFIG = { MaxHealth = 10, DropCount = 3, RewardPerDrop = 2, MaxDistance = 20, RespawnTime = 15 }

local treeStates = {}
local playerCooldowns = {}
local HIT_COOLDOWN = 0.35

Players.PlayerRemoving:Connect(function(player)
	playerCooldowns[player] = nil
end)

local function getCuttableTree(part)
	local current = part
	while current and current ~= workspace do
		if CollectionService:HasTag(current, "TreeCuttable") then return current end
		current = current.Parent
	end
	return nil
end

local function setupTree(treeModel)
	if treeStates[treeModel] then return end

	local trunk = treeModel:FindFirstChild("Trunk") or treeModel.PrimaryPart or treeModel:FindFirstChildWhichIsA("BasePart")
	local config = TREE_CONFIG[treeModel.Name] or DEFAULT_CONFIG
	local modelCF, modelSize = treeModel:GetBoundingBox()
	local groundLevelY = modelCF.Position.Y - (modelSize.Y / 2)

	local hitParticles = trunk and trunk:FindFirstChild("WoodChips")
	if trunk and not hitParticles then
		hitParticles = Instance.new("ParticleEmitter")
		hitParticles.Name = "WoodChips"
		hitParticles.Color = ColorSequence.new(Color3.fromRGB(150, 100, 50))
		hitParticles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0)})
		hitParticles.Speed = NumberRange.new(15, 25)
		hitParticles.SpreadAngle = Vector2.new(45, 45)
		hitParticles.Drag = 4
		hitParticles.Lifetime = NumberRange.new(0.3, 0.6)
		hitParticles.Rate = 0
		hitParticles.Parent = trunk
	end

	-- Sayaç zemin hizasında bağımsız parça olarak tutulur
	local timerPart = Instance.new("Part")
	timerPart.Name = "RespawnTimerPart"
	timerPart.Size = Vector3.new(1, 1, 1)
	timerPart.Transparency = 1
	timerPart.Anchored = true
	timerPart.CanCollide = false
	timerPart.Position = Vector3.new(modelCF.Position.X, groundLevelY + 0.2, modelCF.Position.Z)
	timerPart.Parent = workspace

	local timerBillboard = Instance.new("BillboardGui")
	timerBillboard.Name = "RespawnTimerHUD"
	timerBillboard.Size = UDim2.new(0, 90, 0, 45)
	timerBillboard.AlwaysOnTop = true
	timerBillboard.Enabled = false
	timerBillboard.Parent = timerPart

	local timerText = Instance.new("TextLabel")
	timerText.Size = UDim2.new(1, 0, 1, 0)
	timerText.BackgroundTransparency = 1
	timerText.TextColor3 = Color3.fromRGB(255, 220, 50)
	timerText.Font = Enum.Font.GothamBlack
	timerText.TextScaled = true
	timerText.Text = "15"
	timerText.Parent = timerBillboard

	local timerStroke = Instance.new("UIStroke")
	timerStroke.Thickness = 3.5
	timerStroke.Color = Color3.fromRGB(0, 0, 0)
	timerStroke.Parent = timerText

	treeStates[treeModel] = {
		Trunk = trunk,
		MaxHealth = config.MaxHealth,
		CurrentHealth = config.MaxHealth,
		DropCount = config.DropCount,
		RewardPerDrop = config.RewardPerDrop,
		MaxDistance = config.MaxDistance,
		RespawnTime = DEFAULT_CONFIG.RespawnTime,
		IsDestroyed = false,
		OriginalCFrame = treeModel:GetPivot(),
		OriginalScale = treeModel:GetScale(),
		HitParticles = hitParticles,
		TimerBillboard = timerBillboard,
		TimerText = timerText,
		BreakSound = treeModel:FindFirstChild("BreakSound"),
	}

	-- Ağaç silinirse sayacı da dünyadan kaldırır
	treeModel.AncestryChanged:Connect(function(_, parent)
		if not parent then
			timerPart:Destroy()
			treeStates[treeModel] = nil
		end
	end)
end

for _, tree in ipairs(CollectionService:GetTagged("TreeCuttable")) do
	setupTree(tree)
end
CollectionService:GetInstanceAddedSignal("TreeCuttable"):Connect(setupTree)

local function setTreeVisibility(treeModel, visible)
	for _, part in ipairs(treeModel:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Name == "Hitbox" then
				part.Transparency = 1
				part.CanCollide = false
			else
				part.Transparency = visible and 0 or 1
				part.CanCollide = visible
			end
		end
	end
end

-- Vuruş Olayı
chopEvent.OnServerEvent:Connect(function(player, targetPart)
	if not targetPart then return end

	local now = os.clock()
	if playerCooldowns[player] and (now - playerCooldowns[player] < HIT_COOLDOWN) then
		return
	end
	playerCooldowns[player] = now

	local treeModel = getCuttableTree(targetPart)
	if not treeModel then return end

	local state = treeStates[treeModel]
	if not state or state.IsDestroyed then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local targetHitbox = treeModel:FindFirstChild("Hitbox")
	local refPart = targetHitbox or state.Trunk or targetPart
	local playerPos = char.HumanoidRootPart.Position
	local distance = (playerPos - refPart.Position).Magnitude

	if distance > state.MaxDistance then return end

	local equippedAxeName = player:GetAttribute("EquippedAxe") or "WoodenAxe"
	local axePower = 1
	if AxeData then
		for _, data in ipairs(AxeData) do
			if data.Name == equippedAxeName then
				axePower = data.Power or 1
				break
			end
		end
	end

	state.CurrentHealth = math.max(0, state.CurrentHealth - axePower)
	if state.HitParticles then state.HitParticles:Emit(8) end

	healthEvent:FireClient(player, state.CurrentHealth, state.MaxHealth, false)
	treeEffectEvent:FireAllClients("Shake", treeModel, state.CurrentHealth <= 3)

	if state.CurrentHealth <= 0 then
		state.IsDestroyed = true
		healthEvent:FireClient(player, 0, state.MaxHealth, true)
		if state.BreakSound then state.BreakSound:Play() end

		treeEffectEvent:FireAllClients("Destroy", treeModel)

		local totalReward = state.DropCount * state.RewardPerDrop
		local ls = player:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Wood") then
			ls.Wood.Value = ls.Wood.Value + totalReward
		end
		popupEvent:FireClient(player, totalReward)

		treeEffectEvent:FireClient(player, "SpawnDrops", treeModel, player, state.DropCount)

		task.spawn(function()
			task.wait(0.35)
			setTreeVisibility(treeModel, false)

			state.TimerBillboard.Enabled = true
			for i = state.RespawnTime, 1, -1 do
				state.TimerText.Text = tostring(i)
				task.wait(1)
			end
			state.TimerBillboard.Enabled = false

			state.CurrentHealth = state.MaxHealth
			setTreeVisibility(treeModel, true)

			treeEffectEvent:FireAllClients("Respawn", treeModel)
			state.IsDestroyed = false
		end)
	end
end)
