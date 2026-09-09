--[[
	MapBind — backend ↔ заказная карта.
	ProximityPrompt на существующих Part; MapPoints полностью невидимы.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CommissionMapConfig = require(ReplicatedStorage.Shared.Config.CommissionMapConfig)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local MapBind = {}

local BOUND_ATTR = "BridgeDefenseZone"
local PROMPT_NAME = "BridgeDefensePrompt"
local PROMPT_ANCHOR_NAME = "BridgeDefensePromptAnchor"

-- Кэш ориентации обороны на мосту (look = к врагам)
local defenseLook = Vector3.new(1, 0, 0)
local bridgeLateral = Vector3.new(0, 0, 1)

local ANCHOR_ORDER = {
	"BattleTeleport",
	"Shop",
	"ArmorShop",
	"UnitShop",
	"Upgrade",
	"Leaderboard",
	"DailyReward",
	"Promocode",
}

local function getCFrame(inst: Instance): CFrame?
	if inst:IsA("BasePart") then
		return inst.CFrame
	end
	if inst:IsA("Model") then
		local ok, cf = pcall(function()
			return inst:GetPivot()
		end)
		if ok and cf then
			return cf
		end
		local part = inst:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part.CFrame
		end
	end
	return nil
end

local function getAnchorPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		if inst.PrimaryPart then
			return inst.PrimaryPart
		end
		local best: BasePart? = nil
		local bestVol = -1
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				local vol = d.Size.X * d.Size.Y * d.Size.Z
				if vol > bestVol then
					bestVol = vol
					best = d
				end
			end
		end
		return best
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function findSpawnPosition(): Vector3
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.Position
	end
	local teleports = workspace:FindFirstChild("Teleports", true)
	local mt = teleports and teleports:FindFirstChild("MainTeleport")
	if mt and mt:IsA("BasePart") then
		return mt.Position
	end
	return Vector3.zero
end

local function collectByName(name: string, requireClass: string?): { Instance }
	local list = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == name then
			if (not requireClass) or d:IsA(requireClass) then
				table.insert(list, d)
			end
		end
	end
	return list
end

local function sortByDist(candidates: { Instance }, spawnPos: Vector3)
	table.sort(candidates, function(a, b)
		local ca, cb = getCFrame(a), getCFrame(b)
		local da = ca and (ca.Position - spawnPos).Magnitude or math.huge
		local db = cb and (cb.Position - spawnPos).Magnitude or math.huge
		return da < db
	end)
end

local function pickInstance(cfg, spawnPos: Vector3, used: { [Instance]: boolean }): Instance?
	local requireClass = cfg.RequireClass
	local allowReuse = cfg.AllowReuse == true
	local candidates = {}

	local function addNamed(names)
		for _, name in ipairs(names or {}) do
			for _, inst in ipairs(collectByName(name, requireClass)) do
				if allowReuse or not used[inst] then
					local part = getAnchorPart(inst)
					if part and (allowReuse or not used[part]) then
						table.insert(candidates, inst)
					end
				end
			end
		end
	end

	addNamed(cfg.Prefer)
	if #candidates == 0 then
		addNamed(cfg.FallbackNames)
	end
	if #candidates == 0 then
		return nil
	end

	sortByDist(candidates, spawnPos)
	local pick = cfg.Pick or "First"
	if pick == "ClosestToSpawn" or pick == "First" then
		return candidates[1]
	end
	if pick == "SecondClosestToSpawn" then
		return candidates[2] or candidates[1]
	end
	if pick == "ThirdClosestToSpawn" then
		return candidates[3] or candidates[2] or candidates[1]
	end
	if pick == "FarthestOfPrefer" then
		return candidates[#candidates]
	end
	return candidates[1]
end

-- WoodSign сидит наверху WoodenLeaderboard — поднимаемся к именной модели-пропу
local function getPropRoot(inst: Instance): Instance
	local current = inst
	for _ = 1, 4 do
		local parent = current.Parent
		if not (parent and parent:IsA("Model")) then
			break
		end
		if parent.Name == "Model" or parent.Name == "CommissionMap" then
			break
		end
		current = parent
	end
	return current
end

local function partWorldMinY(p: BasePart): number
	local cf = p.CFrame
	local half = p.Size * 0.5
	local minY = math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local world = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
				minY = math.min(minY, world.Y)
			end
		end
	end
	return minY
end

local function worldBottomCenter(source: Instance): Vector3
	local minY = math.huge
	local sumX, sumZ, n = 0, 0, 0
	local function consider(p: BasePart)
		if string.find(p.Name, "BridgeDefensePromptAnchor", 1, true) == 1 then
			return
		end
		minY = math.min(minY, partWorldMinY(p))
		sumX += p.Position.X
		sumZ += p.Position.Z
		n += 1
	end
	if source:IsA("BasePart") then
		consider(source)
	end
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") then
			consider(d)
		end
	end
	if n == 0 then
		local cf = getCFrame(source)
		return cf and cf.Position or Vector3.zero
	end
	local pos = Vector3.new(sumX / n, minY + 1.4, sumZ / n)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { source }
	local hit = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -80, 0), params)
	if hit then
		return Vector3.new(pos.X, hit.Position.Y + 1.5, pos.Z)
	end
	return pos
end

local function cleanupDetachedPromptHosts()
	local folder = workspace:FindFirstChild("BridgeDefensePromptHosts")
	if folder then
		folder:Destroy()
	end
end

-- Якорь у низа модели (Streaming: внутри той же Model, Atomic)
local function ensurePromptHost(part: BasePart, source: Instance, cfg): BasePart
	if not cfg.PromptAtBase then
		return part
	end

	local leftover = part:FindFirstChild(PROMPT_NAME, true)
	if leftover then
		leftover:Destroy()
	end
	part:SetAttribute("ZoneType", nil)
	part:SetAttribute(BOUND_ATTR, nil)

	local root = getPropRoot(source)
	if root:IsA("Model") then
		pcall(function()
			root.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		end)
	end

	local anchorName = cfg.PromptAnchorName or PROMPT_ANCHOR_NAME
	local parent: Instance = if root:IsA("Model") then root else part
	local host = parent:FindFirstChild(anchorName)
	if not (host and host:IsA("BasePart")) then
		if host then
			host:Destroy()
		end
		host = Instance.new("Part")
		host.Name = anchorName
		host.Size = Vector3.new(6, 1, 6)
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = true
		host.CanTouch = false
		host.CastShadow = false
		host.Massless = true
		host.Transparency = 1
		host.Parent = parent
	else
		host.CanQuery = true
		host.CanCollide = false
		host.Anchored = true
		host.Size = Vector3.new(6, 1, 6)
		host.Transparency = 1
	end

	local base = worldBottomCenter(root)
	if cfg.PromptWorldOffset then
		base += cfg.PromptWorldOffset
	end
	-- Чуть выше земли — как у Shop-падов (~Y+1)
	host.CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0))
	return host
end

local function exclusivityFromCfg(cfg)
	local v = cfg and cfg.PromptExclusivity
	if v == "AlwaysShow" then
		return Enum.ProximityPromptExclusivity.AlwaysShow
	end
	if v == "OnePerHost" then
		return Enum.ProximityPromptExclusivity.OnePerHost
	end
	return Enum.ProximityPromptExclusivity.OnePerButton
end

local function attachPrompt(part: BasePart, zoneType: string, cfg, source: Instance?)
	local origin = source or part
	local host = ensurePromptHost(part, origin, cfg)
	for _, old in ipairs(host:GetDescendants()) do
		if old:IsA("ProximityPrompt") or (old:IsA("Attachment") and old.Name == "BridgeDefensePromptAtt") then
			old:Destroy()
		end
	end
	local directOld = host:FindFirstChild(PROMPT_NAME)
	if directOld then
		directOld:Destroy()
	end
	if part ~= host then
		local leftover = part:FindFirstChild(PROMPT_NAME, true)
		if leftover then
			leftover:Destroy()
		end
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("ProximityPrompt") then
				child.Enabled = false
			end
		end
	end
	host:SetAttribute("ZoneType", zoneType)
	host:SetAttribute(BOUND_ATTR, true)

	-- Attachment: стабильнее для ProximityPrompt UI (центр хоста)
	local att = Instance.new("Attachment")
	att.Name = "BridgeDefensePromptAtt"
	att.Position = Vector3.new(0, 1.2, 0)
	att.Parent = host

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = cfg.ActionText or "Открыть"
	prompt.ObjectText = cfg.ObjectText or zoneType
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = cfg.MaxDistance or 20
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = exclusivityFromCfg(cfg)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Enabled = true
	prompt.Parent = att
	return prompt, host
end

function MapBind.IsCommissionMap(): boolean
	if workspace:GetAttribute("CommissionMap") == true then
		return true
	end
	for _, name in ipairs(CommissionMapConfig.DetectNames) do
		if workspace:FindFirstChild(name, true) then
			return true
		end
	end
	return false
end

function MapBind.DisableEmbeddedMapScripts()
	local n = 0

	-- Карта заказчика: Teleports/MainTeleport ↔ Island* — петля Touched → Gameplay Paused.
	-- CanTouch=false гасит уже подключённые Touched; скрипты уничтожаем.
	local teleports = workspace:FindFirstChild("Teleports")
	if teleports then
		for _, inst in ipairs(teleports:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.CanTouch = false
			elseif inst:IsA("Script") or inst:IsA("LocalScript") then
				inst:Destroy()
				n += 1
			end
		end
		Log.Write("Map", "Neutralized commission Teleports pads (" .. n .. " scripts removed)")
	end

	-- Legacy SSS.Script: PlayerData.Island для тех падов (не Rojo)
	local sss = game:GetService("ServerScriptService")
	for _, child in ipairs(sss:GetChildren()) do
		if child:IsA("Script") and child.Name == "Script" and child.Parent == sss then
			child:Destroy()
			n += 1
			Log.Write("Map", "Removed legacy SSS island assigner")
		end
	end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Script") and inst.Enabled and inst:GetAttribute("BridgeDefenseDisable") == true then
			inst.Enabled = false
			n += 1
		end
	end
	if n > 0 then
		Log.Write("Map", "Embedded cleanup done, touched=" .. tostring(n))
	end
end

function MapBind.BindLobbyAnchors(): { BasePart }
	local spawnPos = findSpawnPosition()
	local boundParts = {}
	local used: { [Instance]: boolean } = {}
	cleanupDetachedPromptHosts()

	-- Три Shop-пада на земле: 1=оружие, 2=броня, 3=юниты (явный порядок)
	local shopPads = collectByName("Shop", "BasePart")
	sortByDist(shopPads, spawnPos)
	local shopBindings = {
		{ zoneType = "Shop", cfg = CommissionMapConfig.Anchors.Shop, inst = shopPads[1] },
		{ zoneType = "ArmorShop", cfg = CommissionMapConfig.Anchors.ArmorShop, inst = shopPads[2] or shopPads[1] },
		{ zoneType = "UnitShop", cfg = CommissionMapConfig.Anchors.UnitShop, inst = shopPads[3] or shopPads[2] or shopPads[1] },
	}
	for _, bind in ipairs(shopBindings) do
		local inst = bind.inst
		local part = inst and getAnchorPart(inst)
		if not part or (inst and used[inst]) or (part and used[part]) then
			inst = pickInstance(bind.cfg, spawnPos, used)
			part = inst and getAnchorPart(inst)
		end
		if part and bind.cfg and not used[part] then
			used[inst] = true
			used[part] = true
			local _prompt, host = attachPrompt(part, bind.zoneType, bind.cfg, inst)
			table.insert(boundParts, host or part)
			local cf = getCFrame(host or part)
			Log.Write(
				"Map",
				string.format(
					"Anchor %s -> %s @ %s",
					bind.zoneType,
					(host or part):GetFullName(),
					cf and tostring(cf.Position) or "?"
				)
			)
		elseif bind.cfg then
			Log.Write("Map", "Anchor missing for " .. bind.zoneType, "WARN")
		end
	end

	for _, zoneType in ipairs(ANCHOR_ORDER) do
		if zoneType == "Shop" or zoneType == "ArmorShop" or zoneType == "UnitShop" then
			continue
		end
		local cfg = CommissionMapConfig.Anchors[zoneType]
		if cfg then
			local inst = pickInstance(cfg, spawnPos, used)
			local part = inst and getAnchorPart(inst)
			if part then
				used[inst] = true
				used[part] = true
				local _prompt, host = attachPrompt(part, zoneType, cfg, inst)
				table.insert(boundParts, host or part)
				local cf = getCFrame(host or part)
				Log.Write(
					"Map",
					string.format(
						"Anchor %s -> %s @ %s",
						zoneType,
						(host or part):GetFullName(),
						cf and tostring(cf.Position) or "?"
					)
				)
			else
				Log.Write("Map", "Anchor missing for " .. zoneType, "WARN")
			end
		end
	end

	return boundParts
end

local function ensureMapPoints(): Folder
	local folder = workspace:FindFirstChild("MapPoints")
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "MapPoints"
	folder.Parent = workspace
	return folder
end

local function setInvisiblePoint(folder: Folder, name: string, position: Vector3)
	local p = folder:FindFirstChild(name)
	if not (p and p:IsA("BasePart")) then
		if p then
			p:Destroy()
		end
		p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(1, 0.2, 1)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
	end
	p.Transparency = 1
	p.CFrame = CFrame.new(position)
	for _, child in ipairs(p:GetChildren()) do
		if child:IsA("BillboardGui") then
			child:Destroy()
		end
	end
	return p
end

local function computeBridgeDeck(bridge: Instance)
	local battleCfg = CommissionMapConfig.Battle
	local band = battleCfg.DeckYBand or 10
	local stand = battleCfg.CharacterStandOffset or 3.2

	-- 1) Собираем Y плоских частей (настил). Берём ВЕРХ детали (Position.Y — центр!),
	-- и топ-квантиль Y: детали под/над настилом тянули медиану вниз → боты «по пояс»
	local flatTopYs = {}
	local allParts = {}
	for _, d in ipairs(bridge:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(allParts, d)
			local flat = math.max(d.Size.X, d.Size.Z)
			local thick = d.Size.Y
			if flat >= 6 and thick <= 8 then
				table.insert(flatTopYs, d.Position.Y + d.Size.Y * 0.5)
			end
		end
	end
	if #allParts == 0 then
		return nil
	end

	local function median(values: { number }): number
		table.sort(values)
		return values[math.clamp(math.ceil(#values / 2), 1, #values)]
	end

	local deckSurfaceY
	if #flatTopYs >= 10 then
		-- Медиана верха плоских частей настила. Настил дороги ~1802.5, опоры/балки
		-- моста выше (1834+). Процентиль задирал Y до башен → неверный центр пролёта.
		deckSurfaceY = median(flatTopYs)
	else
		local ys = {}
		for _, d in ipairs(allParts) do
			table.insert(ys, d.Position.Y)
		end
		deckSurfaceY = median(ys)
	end

	-- 2) Только части около поверхности настила → реальный XZ пролёт
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local used = 0
	for _, d in ipairs(allParts) do
		if math.abs(d.Position.Y - deckSurfaceY) <= band + 2 then
			local p = d.Position
			minX = math.min(minX, p.X)
			maxX = math.max(maxX, p.X)
			minZ = math.min(minZ, p.Z)
			maxZ = math.max(maxZ, p.Z)
			used += 1
		end
	end
	if used < 5 then
		for _, d in ipairs(allParts) do
			local p = d.Position
			minX = math.min(minX, p.X)
			maxX = math.max(maxX, p.X)
			minZ = math.min(minZ, p.Z)
			maxZ = math.max(maxZ, p.Z)
		end
		used = #allParts
	end

	local center = Vector3.new((minX + maxX) * 0.5, deckSurfaceY, (minZ + maxZ) * 0.5)
	local span = Vector3.new(maxX - minX, 0, maxZ - minZ)
	local useX = span.X >= span.Z
	local standY = deckSurfaceY + stand

	return {
		Center = center,
		Span = span,
		UseX = useX,
		StandY = standY,
		DeckY = deckSurfaceY,
		PartCount = used,
	}
end

function MapBind.GetDefenseCFrame(position: Vector3): CFrame
	local look = defenseLook
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

-- Смещение вдоль моста (к врагам) и поперёк (ширина настила)
function MapBind.OffsetOnBridge(base: Vector3, alongStuds: number, lateralStuds: number): Vector3
	local along = defenseLook
	if along.Magnitude < 0.1 then
		along = Vector3.new(1, 0, 0)
	else
		along = Vector3.new(along.X, 0, along.Z).Unit
	end
	local lat = bridgeLateral
	if lat.Magnitude < 0.1 then
		lat = Vector3.new(-along.Z, 0, along.X)
	else
		lat = Vector3.new(lat.X, 0, lat.Z).Unit
	end
	return base + along * alongStuds + lat * lateralStuds
end

function MapBind.GetDefenseLook(): Vector3
	return defenseLook
end

local battlePointsReady = false

-- Повторный BindBattlePoints на каждый бой — тяжёлый GetDescendants по мосту (лаги входа).
-- Кэшируем: достаточно один раз за сессию сервера.
function MapBind.EnsureBattlePoints(): boolean
	if battlePointsReady and workspace:GetAttribute("CommissionMap") == true then
		local folder = workspace:FindFirstChild("MapPoints")
		if folder and folder:FindFirstChild("DefenseSpawn1") and folder:FindFirstChild("EnemySpawn") then
			return true
		end
	end
	local ok = MapBind.BindBattlePoints()
	battlePointsReady = ok == true
	return battlePointsReady
end

function MapBind.BindBattlePoints(): boolean
	local bridge = workspace:FindFirstChild(CommissionMapConfig.Battle.BridgeName, true)
	if not bridge then
		Log.Write("Map", "Road Bridge not found", "ERROR")
		return false
	end

	local deck = computeBridgeDeck(bridge)
	if not deck then
		Log.Write("Map", "Road Bridge has no parts", "ERROR")
		return false
	end

	local spawnPos = findSpawnPosition()
	local names = GameConfig.MapPointNames
	local folder = ensureMapPoints()

	local half = (deck.UseX and deck.Span.X or deck.Span.Z) * 0.5
	local width = deck.UseX and deck.Span.Z or deck.Span.X
	half = math.max(half, 20)
	width = math.clamp(width, 12, 52)

	local defenseSign
	if deck.UseX then
		defenseSign = (spawnPos.X <= deck.Center.X) and -1 or 1
	else
		defenseSign = (spawnPos.Z <= deck.Center.Z) and -1 or 1
	end
	local enemySign = -defenseSign

	-- Высота настила через raycast: медиана по всем деталям занижает Y → боты «по пояс»
	local function buildRayExclude(): { Instance }
		local exclude = {}
		for _, name in ipairs({ "MapPoints", "Enemies", "Squad", "CombatVFX", "LobbyMap" }) do
			local f = workspace:FindFirstChild(name)
			if f then
				table.insert(exclude, f)
			end
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then
				table.insert(exclude, plr.Character)
			end
		end
		return exclude
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = buildRayExclude()
	rayParams.RespectCanCollide = true

	local function surfaceY(x: number, z: number): number
		local hit = workspace:Raycast(Vector3.new(x, deck.Center.Y + 40, z), Vector3.new(0, -300, 0), rayParams)
		if hit and hit.Position.Y <= deck.DeckY + 8 then
			return hit.Position.Y
		end
		return deck.DeckY
	end

	local function alongXZ(t: number, lateral: number): (number, number)
		if deck.UseX then
			return deck.Center.X + t * (half - 6), deck.Center.Z + lateral
		end
		return deck.Center.X + lateral, deck.Center.Z + t * (half - 6)
	end

	-- 3.05 = высота root R6-рига над ступнями
	local function along(t: number, lateral: number): Vector3
		local x, z = alongXZ(t, lateral)
		return Vector3.new(x, surfaceY(x, z) + 3.05, z)
	end

	-- Оборона ближе к «своему» краю; враги ближе, чтобы сразу вступали в перестрелку
	local defenseT = defenseSign * 0.72
	local enemyT = enemySign * 0.58
	local dX, dZ = alongXZ(defenseT, 0)
	local eX, eZ = alongXZ(enemyT, 0)
	local flatDelta = Vector3.new(eX - dX, 0, eZ - dZ)
	if flatDelta.Magnitude > 0.1 then
		defenseLook = flatDelta.Unit
	else
		defenseLook = deck.UseX and Vector3.new(-defenseSign, 0, 0) or Vector3.new(0, 0, -defenseSign)
	end
	bridgeLateral = deck.UseX and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)

	workspace:SetAttribute("CommissionDefenseYaw", math.atan2(-defenseLook.X, -defenseLook.Z))
	workspace:SetAttribute("CommissionAlongX", defenseLook.X)
	workspace:SetAttribute("CommissionAlongZ", defenseLook.Z)
	workspace:SetAttribute("CommissionLateralX", bridgeLateral.X)
	workspace:SetAttribute("CommissionLateralZ", bridgeLateral.Z)
	workspace:SetAttribute("CommissionBridgeHalfWidth", math.max(8, (width or 20) * 0.45))

	local laterals = { -width * 0.32, -width * 0.12, width * 0.12, width * 0.32 }
	for i, spawnName in ipairs(names.DefenseSpawns) do
		setInvisiblePoint(folder, spawnName, along(defenseT, laterals[i] or 0))
	end
	setInvisiblePoint(folder, names.EnemySpawn, Vector3.new(eX, surfaceY(eX, eZ) + 3.5, eZ))

	-- Waypoints: от спавна врагов → почти к линии обороны
	local wpCount = #names.BridgePathWaypoints
	local pathEndT = defenseSign * 0.68
	for i, wpName in ipairs(names.BridgePathWaypoints) do
		local alpha = (i - 1) / math.max(wpCount - 1, 1)
		local t = enemyT * (1 - alpha) + pathEndT * alpha
		setInvisiblePoint(folder, wpName, along(t, 0))
	end
	setInvisiblePoint(folder, names.BridgePath, along(pathEndT, 0))

	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		setInvisiblePoint(folder, "LobbySpawnRef", spawn.Position + Vector3.new(0, 2, 0))
	end

	if not workspace:FindFirstChild("Enemies") then
		local enemies = Instance.new("Folder")
		enemies.Name = "Enemies"
		enemies.Parent = workspace
	end
	if not workspace:FindFirstChild("Squad") then
		local squad = Instance.new("Folder")
		squad.Name = "Squad"
		squad.Parent = workspace
	end

	workspace:SetAttribute("CommissionMap", true)
	workspace:SetAttribute("CommissionBridgeAxis", deck.UseX and "X" or "Z")
	battlePointsReady = true
	Log.Write(
		"Map",
		string.format(
			"Battle deckY=%.1f standY=%.1f spanXZ=(%.0f,%.0f) parts=%d axis=%s look=%s",
			deck.DeckY,
			deck.StandY,
			deck.Span.X,
			deck.Span.Z,
			deck.PartCount,
			deck.UseX and "X" or "Z",
			tostring(defenseLook)
		)
	)
	return true
end

function MapBind.EnsureLobbyFolder(): Folder
	local folder = workspace:FindFirstChild("LobbyMap")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LobbyMap"
		folder.Parent = workspace
	end
	folder:SetAttribute("CommissionBound", true)
	local zones = folder:FindFirstChild("InteractionZones")
	if zones then
		zones:Destroy()
	end
	return folder
end

function MapBind.BindAll(): Folder
	workspace:SetAttribute("CommissionMap", true)
	MapBind.DisableEmbeddedMapScripts()
	local lobby = MapBind.EnsureLobbyFolder()
	MapBind.BindLobbyAnchors()
	MapBind.BindBattlePoints()
	ReplicatedStorage:SetAttribute("LobbyMapReady", os.clock())
	Log.Write("Map", "Commission integration ready")
	return lobby
end

return MapBind
