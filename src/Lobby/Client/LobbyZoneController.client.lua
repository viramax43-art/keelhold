--[[
	LobbyZoneController — зоны лобби + локальные E у лидерборда/промо.
	Без BillboardGui. Промпт на Part (как у Shop), AlwaysShow.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SCRIPT_REV = "lb-promo-local-v10"
print("[BridgeDefense] LobbyZoneController " .. SCRIPT_REV)

local MenuBridge = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("MenuBridge"))
local BattleClient = require(ReplicatedStorage.Shared.Util.BattleClient)
local ClientLog = require(ReplicatedStorage.Shared.Util.ClientLog)

task.spawn(function()
	pcall(function()
		require(script.Parent.Parent.Client.ClientLoader).EnsureReady()
	end)
end)

local ZONE_TABS = {
	Shop = "Shop",
	ArmorShop = "Armor",
	UnitShop = "Units",
	Upgrade = "Upgrade",
	DailyReward = "Daily",
	Promocode = "Promo",
	Leaderboard = "Leaderboard",
}

-- На карте ДВЕ доски WoodenLeaderboard (~Z -5270 и -5247).
-- Лидерборд → ближайшая к спавну, промокод → вторая.
local FALLBACK_LB = Vector3.new(-2250, 1802, -5270)
local FALLBACK_PROMO = Vector3.new(-2250, 1802, -5248)

local lastBattle = 0
local lastZoneAt = 0
local connected = {}
local localHosts = {}

local function handleZone(zoneType: string)
	-- Антидребезг: один E не должен открыть два окна подряд
	local now = tick()
	if now - lastZoneAt < 0.5 then
		return
	end
	lastZoneAt = now

	if zoneType == "BattleTeleport" then
		if now - lastBattle < 2 then
			return
		end
		lastBattle = now
		local ok, err = BattleClient.StartBattle()
		ClientLog.Write("Zone", ok and "Battle start" or tostring(err))
		return
	end
	local tab = ZONE_TABS[zoneType]
	if tab then
		MenuBridge.OpenTab(tab)
	end
end

local function findPrompt(part: BasePart): ProximityPrompt?
	local nested = part:FindFirstChild("BridgeDefensePrompt", true)
	if nested and nested:IsA("ProximityPrompt") then
		return nested
	end
	return nil
end

local function hookPrompt(part: BasePart)
	if connected[part] then
		return
	end
	local zoneType = part:GetAttribute("ZoneType")
	if type(zoneType) ~= "string" then
		return
	end
	local prompt = findPrompt(part)
	if not prompt then
		return
	end
	connected[part] = true
	prompt.Enabled = true
	prompt.RequiresLineOfSight = false
	-- Triggered обрабатывается только через ProximityPromptService (без двойного OpenTab)
end

local function ensureLocalFolder(): Folder
	local folder = workspace:FindFirstChild("BD_LocalPrompts")
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "BD_LocalPrompts"
	folder.Parent = workspace
	return folder
end

local function findBoardModels(): { Model }
	local list = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "WoodenLeaderboard" and d:IsA("Model") then
			table.insert(list, d)
		end
	end
	return list
end

local function boardBottomCenter(model: Model?): Vector3
	if not model then
		return FALLBACK_LB
	end
	local minY = math.huge
	local sumX, sumZ, n = 0, 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = d.Position
			minY = math.min(minY, p.Y - d.Size.Y * 0.5)
			sumX += p.X
			sumZ += p.Z
			n += 1
		end
	end
	if n == 0 then
		return FALLBACK_LB
	end
	return Vector3.new(sumX / n, minY + 2.0, sumZ / n)
end

local function spawnPosition(): Vector3
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.Position
	end
	return Vector3.new(-2406, 1800, -5263)
end

-- [1]=лидерборд (ближе к спавну), [2]=промокод (вторая доска)
local function pickBoardCenters(): (Vector3, Vector3)
	local boards = findBoardModels()
	if #boards == 0 then
		return FALLBACK_LB, FALLBACK_PROMO
	end
	local spawnPos = spawnPosition()
	table.sort(boards, function(a, b)
		local ca, cb = boardBottomCenter(a), boardBottomCenter(b)
		return (ca - spawnPos).Magnitude < (cb - spawnPos).Magnitude
	end)
	local lbCenter = boardBottomCenter(boards[1])
	local promoCenter = boardBottomCenter(boards[2] or boards[1])
	-- Если нашли только одну доску — сдвиг промокода в сторону, не на ту же точку
	if #boards < 2 then
		promoCenter = lbCenter + Vector3.new(0, 0, 22)
	end
	-- Немного вперёд от лица доски (+X)
	return lbCenter + Vector3.new(7, 0, 0), promoCenter + Vector3.new(7, 0, 0)
end

local function makeLocalZone(folder: Folder, zoneType: string, worldPos: Vector3, actionText: string, objectText: string)
	local name = "BD_Local_" .. zoneType
	local existing = folder:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local host = Instance.new("Part")
	host.Name = name
	host.Size = Vector3.new(2.5, 1, 2.5)
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = true
	host.CanTouch = false
	host.CastShadow = false
	host.Massless = true
	host.Transparency = 1
	host.CFrame = CFrame.new(worldPos)
	host:SetAttribute("ZoneType", zoneType)
	host:SetAttribute("BridgeDefenseZone", true)
	host.Parent = folder

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BridgeDefensePrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	-- Доски ~22 studs; дистанция 10 — зоны не пересекаются
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Enabled = true
	prompt.Parent = host

	table.insert(localHosts, host)
	hookPrompt(host)
	print(string.format("[BridgeDefense] %s @ (%.1f, %.1f, %.1f)", zoneType, worldPos.X, worldPos.Y, worldPos.Z))
	return host
end

local function installBoardPrompts(forceRecreate: boolean?)
	local folder = ensureLocalFolder()
	local lbPos, promoPos = pickBoardCenters()

	if forceRecreate then
		for _, name in ipairs({ "BD_Local_Leaderboard", "BD_Local_Promocode" }) do
			local old = folder:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
		table.clear(localHosts)
	end

	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BillboardGui") then
			d:Destroy()
		end
	end

	if not folder:FindFirstChild("BD_Local_Leaderboard") then
		makeLocalZone(folder, "Leaderboard", lbPos, "Открыть", "Лидерборд")
	else
		local lb = folder:FindFirstChild("BD_Local_Leaderboard") :: BasePart
		lb.CFrame = CFrame.new(lbPos)
		lb.Size = Vector3.new(2.5, 1, 2.5)
		local p = findPrompt(lb)
		if p then
			p.Enabled = true
			p.MaxActivationDistance = 10
			p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
			p.ActionText = "Открыть"
			p.ObjectText = "Лидерборд"
		end
		hookPrompt(lb)
	end

	if not folder:FindFirstChild("BD_Local_Promocode") then
		makeLocalZone(folder, "Promocode", promoPos, "Ввести код", "Промокод")
	else
		local promo = folder:FindFirstChild("BD_Local_Promocode") :: BasePart
		promo.CFrame = CFrame.new(promoPos)
		promo.Size = Vector3.new(2.5, 1, 2.5)
		local p = findPrompt(promo)
		if p then
			p.Enabled = true
			p.MaxActivationDistance = 10
			p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
			p.ActionText = "Ввести код"
			p.ObjectText = "Промокод"
		end
		hookPrompt(promo)
	end

	print(string.format(
		"[BridgeDefense] LB/Promo OK %s lb=(%.0f,%.0f,%.0f) promo=(%.0f,%.0f,%.0f) boards=%d",
		SCRIPT_REV,
		lbPos.X,
		lbPos.Y,
		lbPos.Z,
		promoPos.X,
		promoPos.Y,
		promoPos.Z,
		#findBoardModels()
	))
end

local function requestBoardStream()
	local player = Players.LocalPlayer
	if not (player and player.RequestStreamAroundAsync) then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(FALLBACK_LB)
	end)
	pcall(function()
		player:RequestStreamAroundAsync(FALLBACK_PROMO)
	end)
end

local function scanServerZones()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and (d:GetAttribute("BridgeDefenseZone") or d:GetAttribute("ZoneType")) then
			if string.sub(d.Name, 1, 9) == "BD_Local_" then
				hookPrompt(d)
			else
				local zt = d:GetAttribute("ZoneType")
				if zt == "Leaderboard" or zt == "Promocode" then
					-- Серверные дубли глушим, локальные оставляем
					local p = findPrompt(d)
					if p then
						p.Enabled = false
					end
				else
					hookPrompt(d)
				end
			end
		end
	end
end

task.spawn(function()
	requestBoardStream()
	installBoardPrompts(true)
	for i = 1, 90 do
		if i == 3 or i == 8 or i == 16 then
			requestBoardStream()
		end
		if #findBoardModels() > 0 then
			installBoardPrompts(false)
		end
		scanServerZones()
		local folder = workspace:FindFirstChild("BD_LocalPrompts")
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("BasePart") then
					local p = findPrompt(child)
					if p then
						p.Enabled = true
					end
				end
			end
		end
		task.wait(0.5)
	end
end)

workspace.DescendantAdded:Connect(function(inst)
	if inst.Name == "WoodenLeaderboard" and inst:IsA("Model") then
		task.defer(function()
			installBoardPrompts(false)
		end)
	elseif inst:IsA("ProximityPrompt") and inst.Name == "BridgeDefensePrompt" then
		local part = inst:FindFirstAncestorWhichIsA("BasePart")
		if part and string.sub(part.Name, 1, 9) == "BD_Local_" then
			task.defer(hookPrompt, part)
		elseif part then
			local zt = part:GetAttribute("ZoneType")
			if zt ~= "Leaderboard" and zt ~= "Promocode" then
				task.defer(hookPrompt, part)
			end
		end
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if player ~= Players.LocalPlayer then
		return
	end
	if prompt.Name ~= "BridgeDefensePrompt" then
		return
	end
	-- Единая точка входа (без дубля с prompt.Triggered)
	local part = prompt:FindFirstAncestorWhichIsA("BasePart")
	local zoneType = part and part:GetAttribute("ZoneType")
	if type(zoneType) == "string" then
		handleZone(zoneType)
	end
end)

-- E-fallback только для шопов и т.п.; LB/Promo — строго через ProximityPrompt (без пересечения зон)
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or input.KeyCode ~= Enum.KeyCode.E then
		return
	end
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local best, bestD = nil, 12
	local function consider(part: BasePart)
		if not part.Parent then
			return
		end
		local zt = part:GetAttribute("ZoneType")
		if zt == "Leaderboard" or zt == "Promocode" then
			return
		end
		if string.sub(part.Name, 1, 9) == "BD_Local_" then
			return
		end
		local d = (part.Position - hrp.Position).Magnitude
		if d < bestD then
			bestD = d
			best = part
		end
	end
	for part in pairs(connected) do
		consider(part)
	end
	if best then
		handleZone(best:GetAttribute("ZoneType"))
	end
end)
