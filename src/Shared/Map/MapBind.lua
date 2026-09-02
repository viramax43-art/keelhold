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
	local candidates = {}

	local function addNamed(names)
		for _, name in ipairs(names or {}) do
			for _, inst in ipairs(collectByName(name, requireClass)) do
				if not used[inst] then
					local part = getAnchorPart(inst)
					if part and not used[part] then
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

local function attachPrompt(part: BasePart, zoneType: string, cfg)
	local old = part:FindFirstChild(PROMPT_NAME)
	if old then
		old:Destroy()
	end
	part:SetAttribute("ZoneType", zoneType)
	part:SetAttribute(BOUND_ATTR, true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = cfg.ActionText or "Открыть"
	prompt.ObjectText = cfg.ObjectText or zoneType
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = cfg.MaxDistance or 20
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = part
	return prompt
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
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Script") and inst.Enabled then
			inst.Enabled = false
			n += 1
		end
	end
	if n > 0 then
		Log.Write("Map", "Disabled " .. n .. " embedded Workspace scripts")
	end
end

function MapBind.BindLobbyAnchors(): { BasePart }
	local spawnPos = findSpawnPosition()
	local boundParts = {}
	local used: { [Instance]: boolean } = {}

	-- Три Shop-пада на земле: 1=оружие, 2=броня, 3=юниты (явный порядок)
	local shopPads = collectByName("Shop", "BasePart")
	sortByDist(shopPads, spawnPos)
	local shopBindings = {
		{ zoneType = "Shop", cfg = CommissionMapConfig.Anchors.Shop, inst = shopPads[1] },
		{ zoneType = "ArmorShop", cfg = CommissionMapConfig.Anchors.ArmorShop, inst = shopPads[2] or shopPads[1] },
		{ zoneType = "UnitShop", cfg = CommissionMapConfig.Anchors.UnitShop, inst = shopPads[3] or shopPads[2] or shopPads[1] },
	}
	for _, bind in ipairs(shopBindings) do
		local part = bind.inst and getAnchorPart(bind.inst)
		if part and bind.cfg and not used[part] then
			used[bind.inst] = true
			used[part] = true
			attachPrompt(part, bind.zoneType, bind.cfg)
			table.insert(boundParts, part)
			local cf = getCFrame(part)
			Log.Write(
				"Map",
				string.format(
					"Anchor %s -> %s @ %s",
					bind.zoneType,
					part:GetFullName(),
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
				attachPrompt(part, zoneType, cfg)
				table.insert(boundParts, part)
				local cf = getCFrame(part)
				Log.Write(
					"Map",
					string.format("Anchor %s -> %s @ %s", zoneType, part:GetFullName(), cf and tostring(cf.Position) or "?")
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

	-- Оборона ближе к «своему» краю, враги — с дальнего; строй пошире по настилу
	local defenseT = defenseSign * 0.72
	local enemyT = enemySign * 0.90
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
