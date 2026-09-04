local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local treeEffectEvent = ReplicatedStorage:WaitForChild("TreeEffectEvent")
local treeCache = {}

treeEffectEvent.OnClientEvent:Connect(function(action, treeModel, arg1, arg2)
	if not treeModel or not treeModel.Parent then return end

	if not treeCache[treeModel] then
		treeCache[treeModel] = {
			OriginalCFrame = treeModel:GetPivot(),
			OriginalScale = treeModel:GetScale(),
			IsShaking = false
		}

		treeModel.AncestryChanged:Connect(function(_, parent)
			if not parent then
				treeCache[treeModel] = nil
			end
		end)
	end

	local cachedData = treeCache[treeModel]

	-- Titreme (Çakışma Korumalı)
	if action == "Shake" then
		if cachedData.IsShaking then return end
		cachedData.IsShaking = true

		local isLowHealth = arg1
		local duration = 0.1
		local elapsed = 0
		local intensity = isLowHealth and 3 or 1.5

		while elapsed < duration do
			elapsed = elapsed + RunService.Heartbeat:Wait()
			local rx = math.rad(math.random(-intensity, intensity))
			local rz = math.rad(math.random(-intensity, intensity))
			treeModel:PivotTo(cachedData.OriginalCFrame * CFrame.Angles(rx, 0, rz))
		end
		treeModel:PivotTo(cachedData.OriginalCFrame)
		cachedData.IsShaking = false

		-- Kırılma (Yerinde Pürüzsüz Küçülme)
	elseif action == "Destroy" then
		cachedData.IsShaking = false
		local duration = 0.35
		local elapsed = 0

		while elapsed < duration do
			elapsed = elapsed + RunService.Heartbeat:Wait()
			local alpha = elapsed / duration
			local currentScale = cachedData.OriginalScale * (1 - alpha)
			local rotAngle = alpha * math.rad(180)

			treeModel:ScaleTo(math.max(currentScale, 0.01))
			treeModel:PivotTo(cachedData.OriginalCFrame * CFrame.Angles(0, rotAngle, 0))
		end

		for _, part in ipairs(treeModel:GetDescendants()) do
			if part:IsA("BasePart") then 
				part.LocalTransparencyModifier = 1 
			end
		end

		-- Yeniden Doğma (Hitbox Filtresi Eklendi)
	elseif action == "Respawn" then
		local duration = 0.45
		local elapsed = 0

		for _, part in ipairs(treeModel:GetDescendants()) do
			-- Hitbox ve sayaç kutusu asla görünür yapılmaz
			if part:IsA("BasePart") and part.Name ~= "Hitbox" and part.Name ~= "RespawnTimerPart" then 
				part.LocalTransparencyModifier = 0 
			end
		end

		while elapsed < duration do
			elapsed = elapsed + RunService.Heartbeat:Wait()
			local alpha = elapsed / duration
			local scaleFactor = cachedData.OriginalScale * math.min(alpha * 1.3, 1) * (1 + math.sin(alpha * math.pi) * 0.08)
			local rotAngle = (1 - alpha) * math.rad(180)

			treeModel:ScaleTo(math.max(scaleFactor, 0.01))
			treeModel:PivotTo(cachedData.OriginalCFrame * CFrame.Angles(0, rotAngle, 0))
		end

		treeModel:ScaleTo(cachedData.OriginalScale)
		treeModel:PivotTo(cachedData.OriginalCFrame)

		-- Manyetik Odunlar (Karakter Ölümü / Düşme Korumalı)
	elseif action == "SpawnDrops" then
		local playerToMagnet = arg1
		local dropCount = arg2
		local trunkPos = cachedData.OriginalCFrame.Position

		for i = 1, dropCount do
			local log = Instance.new("Part")
			log.Size = Vector3.new(0.8, 0.8, 1.4)
			log.Color = Color3.fromRGB(110, 75, 38)
			log.Material = Enum.Material.Wood
			log.CanCollide = false
			log.Anchored = true
			log.Position = trunkPos + Vector3.new(math.random(-2, 2), 2.5, math.random(-2, 2))
			log.Parent = workspace

			task.spawn(function()
				task.wait((i - 1) * 0.08)

				local char = playerToMagnet and playerToMagnet.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")

				if root and log.Parent then
					local tween = TweenService:Create(
						log, 
						TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), 
						{Position = root.Position}
					)
					tween:Play()

					-- Tween sürerken karakter ölürse güvenli çıkış
					local conn
					conn = RunService.Heartbeat:Connect(function()
						if not root.Parent or not log.Parent then
							if conn then conn:Disconnect() end
							if log and log.Parent then log:Destroy() end
						end
					end)

					tween.Completed:Wait()
					if conn then conn:Disconnect() end
				end

				if log and log.Parent then
					log:Destroy()
				end
			end)
		end
	end
end)
