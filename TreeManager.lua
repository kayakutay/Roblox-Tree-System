local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

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

-- Balta verisi kontrolü
local AxeData = nil
pcall(function()
	AxeData = require(ReplicatedStorage:WaitForChild("AxeData", 2))
end)

-- 🌲 YENİ DENGELENMİŞ AĞAÇ AYARLARI
-- 🌲 TERS EŞLEŞEN İSİMLER DÜZELTİLDİ (Görsel boyutlara göre)
-- 🌲 KISILMIŞ GERÇEKÇİ VURUŞ MENZİLLERİ
local TREE_CONFIG = {
	-- Sahnedeki EN KÜÇÜK ağaç (4 Odun, 6 Can)
	["Tree1-3"] = { 
		MaxHealth = 6, 
		DropCount = 2, 
		RewardPerDrop = 2, 
		MaxDistance = 12 
	},

	-- Sahnedeki ORTA ağaç (9 Odun, 9 Can)
	["Tree1-2"] = { 
		MaxHealth = 9, 
		DropCount = 3, 
		RewardPerDrop = 3, 
		MaxDistance = 15 
	},

	-- Sahnedeki EN BÜYÜK ağaç (15 Odun, 20 Can)
	["Tree1-1"] = { 
		MaxHealth = 20, 
		DropCount = 3, 
		RewardPerDrop = 5, 
		MaxDistance = 19 
	},
}
local DEFAULT_CONFIG = { MaxHealth = 10, DropCount = 3, RewardPerDrop = 2, MaxDistance = 20, RespawnTime = 15 }

local treeStates = {}

-- Ağaç modelini bulan yardımcı fonksiyon
local function getCuttableTree(part)
	local current = part
	while current and current ~= workspace do
		if CollectionService:HasTag(current, "TreeCuttable") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Ağaç ilk yüklendiğinde ayarlarını bağla
local function setupTree(treeModel)
	if treeStates[treeModel] then return end

	local trunk = treeModel:FindFirstChild("Trunk") or treeModel.PrimaryPart or treeModel:FindFirstChildWhichIsA("BasePart")
	local config = TREE_CONFIG[treeModel.Name] or DEFAULT_CONFIG
	local modelCF, modelSize = treeModel:GetBoundingBox()
	local groundLevelY = modelCF.Position.Y - (modelSize.Y / 2)

	-- WoodChips Partikülü
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

	-- Zemin Sayacı (BillboardGui)
	local timerPart = Instance.new("Part")
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
end

for _, tree in ipairs(CollectionService:GetTagged("TreeCuttable")) do
	setupTree(tree)
end
CollectionService:GetInstanceAddedSignal("TreeCuttable"):Connect(setupTree)

-- Model Parçalarının Görünürlüğü
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

-- Fiziksel Kütük Fırlatma ve Manyetik Çekim
local function spawnVisualDrops(treeModel, player, dropCount, rewardPerDrop)
	local state = treeStates[treeModel]
	local trunkPos = state.Trunk and state.Trunk.Position or treeModel:GetPivot().Position
	local magnetRange = 8
	local logTemplate = ReplicatedStorage:FindFirstChild("LogModel")

	for i = 1, dropCount do
		local log
		if logTemplate then
			log = logTemplate:Clone()
		else
			log = Instance.new("Part")
			log.Size = Vector3.new(1, 1, 2)
			log.Color = Color3.fromRGB(101, 67, 33)
		end

		local spawnPos = trunkPos + Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))

		if log:IsA("Model") then
			local primary = log.PrimaryPart or log:FindFirstChildWhichIsA("BasePart")
			if primary then
				log.PrimaryPart = primary
				for _, part in ipairs(log:GetDescendants()) do
					if part:IsA("BasePart") and part ~= primary then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = primary
						weld.Part1 = part
						weld.Parent = primary
					end
				end
			end
			for _, p in ipairs(log:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = false
					p.CanCollide = true
				end
			end
			log:PivotTo(CFrame.new(spawnPos))
			log.Parent = workspace
			if log.PrimaryPart then
				log.PrimaryPart.AssemblyLinearVelocity = Vector3.new(math.random(-12, 12), math.random(35, 45), math.random(-12, 12))
			end
		else
			log.Position = spawnPos
			log.Anchored = false
			log.CanCollide = true
			log.Parent = workspace
			log.AssemblyLinearVelocity = Vector3.new(math.random(-12, 12), math.random(35, 45), math.random(-12, 12))
		end

		task.spawn(function()
			task.wait(1.0 + (i * 0.15))
			if not log or not log.Parent then return end

			for _, p in ipairs(log:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CanCollide = false
					p.Anchored = true
				end
			end
			if log:IsA("BasePart") then
				log.CanCollide = false
				log.Anchored = true
			end

			local collected = false
			while log and log.Parent and not collected do
				task.wait(0.05)
				if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
					local root = player.Character.HumanoidRootPart
					local currentPos = log:IsA("Model") and log:GetPivot().Position or log.Position

					if (currentPos - root.Position).Magnitude <= magnetRange then
						collected = true

						if log:IsA("Model") then
							local startTime = tick()
							local duration = 0.2
							local startPivot = log:GetPivot()
							while tick() - startTime < duration do
								if not log or not log.Parent then break end
								local alpha = (tick() - startTime) / duration
								local targetCF = CFrame.new(root.Position)
								log:PivotTo(startPivot:Lerp(targetCF, alpha))
								task.wait()
							end
						else
							local tween = TweenService:Create(log, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = root.Position})
							tween:Play()
							task.wait(0.2)
						end

						if log and log.Parent then
							log:Destroy()
						end

						local ls = player:FindFirstChild("leaderstats")
						if ls and ls:FindFirstChild("Wood") then
							ls.Wood.Value = ls.Wood.Value + rewardPerDrop
						end
						popupEvent:FireClient(player, rewardPerDrop)
					end
				end
			end
		end)
	end
end

-- Vuruş Olayı
chopEvent.OnServerEvent:Connect(function(player, targetPart)
	if not targetPart then return end
	local treeModel = getCuttableTree(targetPart)
	if not treeModel then return end

	local state = treeStates[treeModel]
	if not state or state.IsDestroyed then return end

	-- Mesafe Kontrolü (Hitbox veya Trunk referans alınır)
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local targetHitbox = treeModel:FindFirstChild("Hitbox")
	local refPart = targetHitbox or state.Trunk or targetPart
	local playerPos = char.HumanoidRootPart.Position
	local distance = (playerPos - refPart.Position).Magnitude

	if distance > state.MaxDistance then
		return
	end

	-- Balta Gücü
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

	state.CurrentHealth = state.CurrentHealth - axePower
	if state.HitParticles then
		state.HitParticles:Emit(8)
	end

	healthEvent:FireClient(player, state.CurrentHealth, state.MaxHealth, false)

	-- Titreme Animasyonu
	task.spawn(function()
		local shakeDuration = 0.1
		local elapsed = 0
		local intensity = (state.CurrentHealth <= 3) and 3 or 1.5

		while elapsed < shakeDuration do
			elapsed = elapsed + RunService.Heartbeat:Wait()
			local rx = math.rad(math.random(-intensity, intensity))
			local rz = math.rad(math.random(-intensity, intensity))
			treeModel:PivotTo(state.OriginalCFrame * CFrame.Angles(rx, 0, rz))
		end
		treeModel:PivotTo(state.OriginalCFrame)
	end)

	-- Kırılma ve Yenilenme
	if state.CurrentHealth <= 0 then
		state.IsDestroyed = true
		healthEvent:FireClient(player, 0, state.MaxHealth, true)
		if state.BreakSound then
			state.BreakSound:Play()
		end

		spawnVisualDrops(treeModel, player, state.DropCount, state.RewardPerDrop)

		-- Dönerek Küçülme
		task.spawn(function()
			local destroyDuration = 0.4
			local elapsed = 0
			local startCFrame = treeModel:GetPivot()

			while elapsed < destroyDuration do
				elapsed = elapsed + RunService.Heartbeat:Wait()
				local alpha = elapsed / destroyDuration
				local currentScale = state.OriginalScale * (1 - alpha)
				local currentHeight = startCFrame.Position.Y + (alpha * 3)
				local rotAngle = alpha * math.rad(360)

				treeModel:ScaleTo(math.max(currentScale, 0.01))
				treeModel:PivotTo(CFrame.new(startCFrame.Position.X, currentHeight, startCFrame.Position.Z) * CFrame.Angles(0, rotAngle, 0))
			end

			setTreeVisibility(treeModel, false)

			-- Zemin Sayacı
			state.TimerBillboard.Enabled = true
			for i = state.RespawnTime, 1, -1 do
				state.TimerText.Text = tostring(i)
				task.wait(1)
			end
			state.TimerBillboard.Enabled = false

			state.CurrentHealth = state.MaxHealth
			setTreeVisibility(treeModel, true)

			-- Dönerek Büyüme (Respawn)
			local growDuration = 0.5
			elapsed = 0

			while elapsed < growDuration do
				elapsed = elapsed + RunService.Heartbeat:Wait()
				local alpha = elapsed / growDuration
				local scaleFactor = state.OriginalScale * math.min(alpha * 1.5, 1) * (1 + math.sin(alpha * math.pi * 1.5) * 0.1)
				local rotAngle = (1 - alpha) * math.rad(360)

				treeModel:ScaleTo(math.max(scaleFactor, 0.01))
				treeModel:PivotTo(state.OriginalCFrame * CFrame.Angles(0, rotAngle, 0))
			end

			treeModel:ScaleTo(state.OriginalScale)
			treeModel:PivotTo(state.OriginalCFrame)
			state.IsDestroyed = false
		end)
	end
end)