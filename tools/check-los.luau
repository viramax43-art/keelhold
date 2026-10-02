--[[
	check-los.luau — офлайн-проверка LOS на заказной карте (без Studio).

	Повторяет MapBind.computeBridgeDeck/BindBattlePoints и трассирует выстрел
	"бот обороны -> враг на пути" по реальным партам карты, чтобы понять, что
	именно блокировало огонь (los=false на 100% выстрелов).

	Запуск: lune run tools/check-los.luau
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local PLACE = "BridgeDefense_Commission.rbxl"
local BRIDGE_NAME = "Road Bridge"
local DECK_Y_BAND = 10
local CHARACTER_STAND_OFFSET = 3.2

local game = roblox.deserializePlace(fs.readFile(PLACE))
local ws = game:GetService("Workspace")

local bridge = ws:FindFirstChild(BRIDGE_NAME, true)
assert(bridge, "Road Bridge not found")
print(("bridge: %s"):format(bridge:GetFullName()))

-- 1) настил (копия MapBind.computeBridgeDeck)
-- ВНИМАНИЕ: Lune не всегда отдаёт Position/Size (нет дефолта у свойства) —
-- читаем через pcall, Terrain пропускаем.
local function partInfo(d)
	if not d:IsA("BasePart") or d:IsA("Terrain") then
		return nil
	end
	local okCf, cf = pcall(function()
		return d.CFrame
	end)
	local okSz, size = pcall(function()
		return d.Size
	end)
	if not (okCf and okSz) then
		return nil
	end
	return { part = d, cf = cf, size = size, pos = cf.Position }
end

local infos = {}
for _, d in bridge:GetDescendants() do
	local info = partInfo(d)
	if info then
		table.insert(infos, info)
	end
end

local flatTopYs = {}
for _, info in ipairs(infos) do
	local s = info.size
	if math.max(s.X, s.Z) >= 6 and s.Y <= 8 then
		table.insert(flatTopYs, info.pos.Y + s.Y * 0.5)
	end
end

local function median(values)
	table.sort(values)
	return values[math.clamp(math.ceil(#values / 2), 1, #values)]
end

local deckSurfaceY
if #flatTopYs >= 10 then
	deckSurfaceY = median(flatTopYs)
else
	local ys = {}
	for _, info in ipairs(infos) do
		table.insert(ys, info.pos.Y)
	end
	deckSurfaceY = median(ys)
end

local function boundsOf(list)
	local minX, maxX, minZ, maxZ, used = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, info in ipairs(list) do
		local p = info.pos
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		used += 1
	end
	return minX, maxX, minZ, maxZ, used
end

local nearDeck = {}
for _, info in ipairs(infos) do
	if math.abs(info.pos.Y - deckSurfaceY) <= DECK_Y_BAND + 2 then
		table.insert(nearDeck, info)
	end
end
local minX, maxX, minZ, maxZ, used = boundsOf(nearDeck)
if used < 5 then
	minX, maxX, minZ, maxZ, used = boundsOf(infos)
end

local center = Vector3.new((minX + maxX) * 0.5, deckSurfaceY, (minZ + maxZ) * 0.5)
local span = Vector3.new(maxX - minX, 0, maxZ - minZ)
local useX = span.X >= span.Z
local standY = deckSurfaceY + CHARACTER_STAND_OFFSET
print(
	("deckY=%.1f standY=%.1f center=(%.1f,%.1f) span=(%.0f,%.0f) useX=%s parts=%d flatYs=%d"):format(
		deckSurfaceY, standY, center.X, center.Z, span.X, span.Z, tostring(useX), used, #flatTopYs
	)
)

local half = math.max((useX and span.X or span.Z) * 0.5, 24)
local width = math.clamp(useX and span.Z or span.X, 16, 80)
print(("half=%.1f width=%.1f  walk(enemySpawn->defense)=%.1f studs"):format(half, width, 0.14 * (half - 6)))

local spawn = ws:FindFirstChildWhichIsA("SpawnLocation", true)
print("lobby SpawnLocation: " .. (spawn and tostring(spawn.Position) or "none"))
local defenseSign
if useX then
	defenseSign = (spawn.Position.X <= center.X) and -1 or 1
else
	defenseSign = (spawn.Position.Z <= center.Z) and -1 or 1
end
local enemySign = -defenseSign
print(("defenseSign=%d enemySign=%d"):format(defenseSign, enemySign))


-- 2) трассировка по реальным партам карты
local skipFolders = { MapPoints = true, Enemies = true, Squad = true, CombatVFX = true, LobbyMap = true }
local function inSkippedFolder(d)
	local node = d
	while node and node ~= ws do
		if node.Parent == ws and skipFolders[node.Name] then
			return true
		end
		node = node.Parent
	end
	return false
end

local parts = {}
for _, d in ws:GetDescendants() do
	local info = partInfo(d)
	if info and not inSkippedFolder(d) then
		local okCC, cc = pcall(function()
			return d.CanCollide
		end)
		local okTr, tr = pcall(function()
			return d.Transparency
		end)
		info.canCollide = (not okCC) or cc
		info.transparency = okTr and tr or 0
		table.insert(parts, info)
	end
end
print(("BaseParts for traces: %d"):format(#parts))

local function rayBox(origin, dirUnit, maxDist, info)
	local inv = info.cf:Inverse()
	local o = inv * origin
	local d = (inv * (origin + dirUnit * maxDist)) - o
	local hs = info.size * 0.5
	local axes = { { o.X, d.X, hs.X, "X" }, { o.Y, d.Y, hs.Y, "Y" }, { o.Z, d.Z, hs.Z, "Z" } }
	local tmin, tmax, hitAxis, hitSign = 0, 1, nil, 0
	for _, ax in ipairs(axes) do
		local oo, dd, hh = ax[1], ax[2], ax[3]
		if math.abs(dd) < 1e-6 then
			if oo < -hh or oo > hh then
				return nil
			end
		else
			local t1, t2 = (-hh - oo) / dd, (hh - oo) / dd
			local sign = (dd > 0) and -1 or 1
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			if t1 > tmin then
				tmin, hitAxis, hitSign = t1, ax[4], sign
			end
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if not hitAxis then
		return nil
	end
	return tmin * maxDist, hitAxis, hitSign
end

local function localNormal(axis, sign)
	if axis == "X" then
		return Vector3.new(sign, 0, 0)
	elseif axis == "Y" then
		return Vector3.new(0, sign, 0)
	end
	return Vector3.new(0, 0, sign)
end

local function worldNormalOf(info, axis, sign)
	local rotOnly = info.cf - info.cf.Position
	return rotOnly * localNormal(axis, sign)
end

local function describe(info)
	return ("%s[%s] size=(%.1f,%.1f,%.1f)"):format(
		info.part.Name,
		info.part.ClassName,
		info.size.X,
		info.size.Y,
		info.size.Z
	)
end

-- mode: "old" = до правки (Normal.Y > 0.55); "new" = |Normal.Y| > 0.55 + CanCollide/Transparency
local function traceLos(origin, aim, mode)
	local delta = aim - origin
	local range = delta.Magnitude
	if range < 0.05 then
		return true, nil, {}
	end
	local dirUnit = delta.Unit
	local from, remaining, ignore = origin, range, {}
	local skipped = {}
	for _ = 1, 6 do
		local bestT, bestInfo, bestAxis, bestSign = math.huge, nil, nil, nil
		for _, info in ipairs(parts) do
			if not ignore[info] then
				local t, axis, sign = rayBox(from, dirUnit, remaining, info)
				if t and t < bestT then
					bestT, bestInfo, bestAxis, bestSign = t, info, axis, sign
				end
			end
		end
		if not bestInfo then
			return true, nil, skipped
		end
		local n = worldNormalOf(bestInfo, bestAxis, bestSign)
		local isFlat = (mode == "new" and math.abs(n.Y) > 0.55) or (mode == "old" and n.Y > 0.55)
		local isGhost = (mode == "new") and ((not bestInfo.canCollide) or bestInfo.transparency >= 0.9)
		if isFlat or isGhost then
			table.insert(
				skipped,
				("%s n=(%.2f,%.2f,%.2f)%s"):format(bestInfo.part.Name, n.X, n.Y, n.Z, isGhost and " ghost" or "")
			)
			ignore[bestInfo] = true
			local hitPos = from + dirUnit * bestT
			local traveled = (hitPos - from).Magnitude
			from = hitPos + dirUnit * 0.15
			remaining = math.max(0, remaining - traveled - 0.15)
			if remaining < 0.5 then
				return true, nil, skipped
			end
			continue
		end
		return false, ("%s n=(%.2f,%.2f,%.2f) at %.0f studs"):format(describe(bestInfo), n.X, n.Y, n.Z, bestT), skipped
	end
	return true, nil, skipped
end

-- 3) прогон: полосы обороны x точки пути врага
local laterals = { -width * 0.38, -width * 0.14, width * 0.14, width * 0.38 }
local defenderT = defenseSign * 0.72
local enemyT = enemySign * 0.58
local pathEndT = defenseSign * 0.70

print("\n=== выстрел бота обороны по врагу (+1.35 над root) ===")
for i, lateral in ipairs(laterals) do
	local dx, dz = alongXZ(defenderT, lateral)
	local origin = Vector3.new(dx, standY + 1.35, dz)
	for _, frac in ipairs({ 0.0, 0.25, 0.5, 0.75, 1.0 }) do
		local t = enemyT * (1 - frac) + pathEndT * frac
		local ex, ez = alongXZ(t, 0)
		local aim = Vector3.new(ex, standY + 1.0, ez)
		local dist = (aim - origin).Magnitude
		local clearOld, blockerOld, skipsOld = traceLos(origin, aim, "old")
		local clearNew, blockerNew, skipsNew = traceLos(origin, aim, "new")
		print(("lane%d t=%.2f d=%.0f | OLD=%s %s | NEW=%s %s | skips=%d->%d"):format(
			i - 3,
			t,
			dist,
			clearOld and "clear" or "BLOCKED",
			clearOld and "" or ("by " .. blockerOld),
			clearNew and "clear" or "BLOCKED",
			clearNew and "" or ("by " .. blockerNew),
			#skipsOld,
			#skipsNew
		))
		for _, s in ipairs(skipsNew) do
			print("        skip: " .. s)
		end
	end
end

local function alongXZ(t, lateral)
	if useX then
		return center.X + t * (half - 6), center.Z + lateral
	end
	return center.X + lateral, center.Z + t * (half - 6)
end
