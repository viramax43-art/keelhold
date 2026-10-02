--[[
	check-los.luau вЂ” РѕС„Р»Р°Р№РЅ-РїСЂРѕРІРµСЂРєР° LOS РЅР° Р·Р°РєР°Р·РЅРѕР№ РєР°СЂС‚Рµ (Р±РµР· Studio).

	РџРѕРІС‚РѕСЂСЏРµС‚ MapBind.computeBridgeDeck/BindBattlePoints Рё С‚СЂР°СЃСЃРёСЂСѓРµС‚ РІС‹СЃС‚СЂРµР»
	"Р±РѕС‚ РѕР±РѕСЂРѕРЅС‹ -> РІСЂР°Рі РЅР° РїСѓС‚Рё" РїРѕ СЂРµР°Р»СЊРЅС‹Рј РїР°СЂС‚Р°Рј РєР°СЂС‚С‹: С‡С‚Рѕ РёРјРµРЅРЅРѕ СѓРїРёСЂР°РµС‚СЃСЏ
	РІ СЃС‚РІРѕР» Рё РјРµС€Р°РµС‚ РѕРіРЅСЋ (los=false).

	Р’РђР–РќРћ: Lune 0.10 РЅРµ РґР°С‘С‚ РіР»РѕР±Р°Р»СЊРЅС‹Р№ Vector3 вЂ” СЃС‡РёС‚Р°РµРј С‡РёСЃС‚С‹РјРё С‡РёСЃР»Р°РјРё,
	РёР· РїР°СЂС‚РѕРІ Р±РµСЂС‘Рј С‚РѕР»СЊРєРѕ CFrame (Position/RightVector/UpVector/LookVector) Рё Size.

	Р—Р°РїСѓСЃРє: lune run tools/check-los.luau
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local process = require("@lune/process")
local PLACE = (process.env and process.env.CHECK_PLACE) or "BridgeDefense_Commission.rbxl"
local BRIDGE_NAME = "Road Bridge"
local DECK_Y_BAND = 10

local game = roblox.deserializePlace(fs.readFile(PLACE))
local ws = game:GetService("Workspace")

local bridge = ws:FindFirstChild(BRIDGE_NAME, true)
assert(bridge, "Road Bridge not found")
print(("bridge: %s"):format(bridge:GetFullName()))

-- РЎРѕР±РёСЂР°РµРј РїР°СЂС‚С‹ РІ РїР»РѕСЃРєРёРµ С‡РёСЃР»Р° (Lune РјРѕР¶РµС‚ РЅРµ РѕС‚РґР°С‚СЊ Position/Size -> pcall)
local function partInfo(d)
	if not d:IsA("BasePart") or d:IsA("Terrain") then
		return nil
	end
	local ok, info = pcall(function()
		local cf = d.CFrame
		local size = d.Size
		local cc = d.CanCollide
		local tr = d.Transparency
		return {
			part = d,
			px = cf.Position.X,
			py = cf.Position.Y,
			pz = cf.Position.Z,
			rx = cf.RightVector.X,
			ry = cf.RightVector.Y,
			rz = cf.RightVector.Z,
			ux = cf.UpVector.X,
			uy = cf.UpVector.Y,
			uz = cf.UpVector.Z,
			fx = cf.LookVector.X,
			fy = cf.LookVector.Y,
			fz = cf.LookVector.Z,
			sx = size.X,
			sy = size.Y,
			sz = size.Z,
			canCollide = cc,
			transparency = tr,
		}
	end)
	if not ok then
		return nil
	end
	return info
end

local infos = {}
for _, d in bridge:GetDescendants() do
	local info = partInfo(d)
	if info then
		table.insert(infos, info)
	end
end

-- РќР°СЃС‚РёР» (РєРѕРїРёСЏ MapBind.computeBridgeDeck)
local flatTopYs = {}
for _, info in ipairs(infos) do
	if math.max(info.sx, info.sz) >= 6 and info.sy <= 8 then
		table.insert(flatTopYs, info.py + info.sy * 0.5)
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
		table.insert(ys, info.py)
	end
	deckSurfaceY = median(ys)
end

local function boundsOf(list)
	local minX, maxX, minZ, maxZ, used = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, info in ipairs(list) do
		minX, maxX = math.min(minX, info.px), math.max(maxX, info.px)
		minZ, maxZ = math.min(minZ, info.pz), math.max(maxZ, info.pz)
		used += 1
	end
	return minX, maxX, minZ, maxZ, used
end

local nearDeck = {}
for _, info in ipairs(infos) do
	if math.abs(info.py - deckSurfaceY) <= DECK_Y_BAND + 2 then
		table.insert(nearDeck, info)
	end
end
local minX, maxX, minZ, maxZ, used = boundsOf(nearDeck)
if used < 5 then
	minX, maxX, minZ, maxZ, used = boundsOf(infos)
end

local cx, cz = (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
local spanX, spanZ = maxX - minX, maxZ - minZ
local useX = spanX >= spanZ
print(
	("deckY=%.1f center=(%.1f,%.1f) span=(%.0f,%.0f) useX=%s parts=%d flatYs=%d"):format(
		deckSurfaceY, cx, cz, spanX, spanZ, tostring(useX), used, #flatTopYs
	)
)

local half = math.max((useX and spanX or spanZ) * 0.5, 24)
local width = math.clamp(useX and spanZ or spanX, 16, 80)
print(("half=%.1f width=%.1f walk(enemySpawn->defense)=%.1f studs"):format(half, width, 0.14 * (half - 6)))

local spawn = ws:FindFirstChildWhichIsA("SpawnLocation", true)
if spawn then
	local okSp, sp = pcall(function()
		return spawn.CFrame.Position
	end)
	if okSp then
		print(("lobby SpawnLocation: (%.1f,%.1f,%.1f)"):format(sp.X, sp.Y, sp.Z))
	end
end

local function alongXZ(t, lateral)
	if useX then
		return cx + t * (half - 6), cz + lateral
	end
	return cx + lateral, cz + t * (half - 6)
end

-- 2) С‚СЂР°СЃСЃРёСЂРѕРІРєР° РїРѕ СЂРµР°Р»СЊРЅС‹Рј РїР°СЂС‚Р°Рј Workspace (РєСЂРѕРјРµ СЃР»СѓР¶РµР±РЅС‹С… РїР°РїРѕРє)
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
		table.insert(parts, info)
	end
end
print(("BaseParts for traces: %d"):format(#parts))

-- Р›СѓС‡ o + t*dir (dir РµРґРёРЅРёС‡РЅС‹Р№), t in [0, maxDist]; Р±РѕРєСЃ РїРѕ Р»РѕРєР°Р»СЊРЅС‹Рј РѕСЃСЏРј РїР°СЂС‚Р°
local function rayBox(ox, oy, oz, dx, dy, dz, maxDist, info)
	local px, py, pz = ox - info.px, oy - info.py, oz - info.pz
	local tmin, tmax, axisIndex, axisSign = 0, maxDist, nil, 0
	local axes = {
		{ info.rx, info.ry, info.rz, info.sx * 0.5, 1 },
		{ info.ux, info.uy, info.uz, info.sy * 0.5, 2 },
		{ info.fx, info.fy, info.fz, info.sz * 0.5, 3 },
	}
	for _, a in ipairs(axes) do
		local oa = px * a[1] + py * a[2] + pz * a[3]
		local da = dx * a[1] + dy * a[2] + dz * a[3]
		local h = a[4]
		if math.abs(da) < 1e-9 then
			if oa < -h or oa > h then
				return nil
			end
		else
			local t1, t2 = (-h - oa) / da, (h - oa) / da
			local sign = (da > 0) and -1 or 1
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			if t1 > tmin then
				tmin, axisIndex, axisSign = t1, a[5], sign
			end
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if not axisIndex then
		return nil
	end
	return tmin, axisIndex, axisSign
end

local function axisNormal(info, idx, sign)
	if idx == 1 then
		return info.rx * sign, info.ry * sign, info.rz * sign
	elseif idx == 2 then
		return info.ux * sign, info.uy * sign, info.uz * sign
	end
	return info.fx * sign, info.fy * sign, info.fz * sign
end

local function nearest(ox, oy, oz, dx, dy, dz, maxDist, opts)
	local ignore = opts and opts.ignore
	local skipCollideLess = opts and opts.skipCollideLess
	local bestT, bestInfo, bestAxis, bestSign = math.huge, nil, nil, nil
	for _, info in ipairs(parts) do
		if not (ignore and ignore[info]) and not (skipCollideLess and not info.canCollide) then
			local t, axis, sign = rayBox(ox, oy, oz, dx, dy, dz, maxDist, info)
			if t and t < bestT then
				bestT, bestInfo, bestAxis, bestSign = t, info, axis, sign
			end
		end
	end
	return bestT, bestInfo, bestAxis, bestSign
end

-- РїР°РґРµРЅРёРµ РЅР° РЅР°СЃС‚РёР» (РєР°Рє MapBind.surfaceY: RespectCanCollide = true)
local function surfaceY(x, z)
	local t, info = nearest(x, deckSurfaceY + 40, z, 0, -1, 0, 300, { skipCollideLess = true })
	if t and info then
		local y = deckSurfaceY + 40 - t
		if y <= deckSurfaceY + 8 then
			return y
		end
	end
	return deckSurfaceY
end

local function describe(info)
	return ("%s[%s] size=(%.1f,%.1f,%.1f)"):format(info.part.Name, info.part.ClassName, info.sx, info.sy, info.sz)
end

-- mode: "old" = РґРѕ РїСЂР°РІРєРё (Normal.Y > 0.55); "new" = |Normal.Y| > 0.55 + CanCollide/Transparency
local function traceLos(ox, oy, oz, tx, ty, tz, mode)
	local dx, dy, dz = tx - ox, ty - oy, tz - oz
	local range = math.sqrt(dx * dx + dy * dy + dz * dz)
	if range < 0.05 then
		return true, nil, {}
	end
	dx, dy, dz = dx / range, dy / range, dz / range
	local ignore, skipped = {}, {}
	local remaining = range
	for _ = 1, 6 do
		local t, info, axis, sign = nearest(ox, oy, oz, dx, dy, dz, remaining, { ignore = ignore })
		if not info then
			return true, nil, skipped
		end
		local nx, ny, nz = axisNormal(info, axis, sign)
		local isFlat = (mode == "new" and math.abs(ny) > 0.55) or (mode == "old" and ny > 0.55)
		local isGhost = (mode == "new" and ((not info.canCollide) or info.transparency >= 0.9))
			or (mode == "final" and ((not info.canCollide) or info.transparency >= 0.7))
		if isFlat or isGhost then
			table.insert(
				skipped,
				("%s n=(%.2f,%.2f,%.2f)%s"):format(info.part.Name, nx, ny, nz, isGhost and " ghost" or "")
			)
			ignore[info] = true
			ox, oy, oz = ox + dx * (t + 0.15), oy + dy * (t + 0.15), oz + dz * (t + 0.15)
			remaining = remaining - t - 0.15
			if remaining < 0.5 then
				return true, nil, skipped
			end
			continue
		end
		return false, ("%s n=(%.2f,%.2f,%.2f) at %.0f studs"):format(describe(info), nx, ny, nz, t), skipped
	end
	return true, nil, skipped
end


-- 3) РїСЂРѕРіРѕРЅ: РїРѕР»РѕСЃС‹ РѕР±РѕСЂРѕРЅС‹ x С‚РѕС‡РєРё РїСѓС‚Рё РІСЂР°РіР°
local loc = ws:FindFirstChildWhichIsA("SpawnLocation", true)
local sx, sz = 0, 0
if loc then
	local ok, cf = pcall(function()
		return loc.CFrame
	end)
	if ok then
		sx, sz = cf.Position.X, cf.Position.Z
	end
end
local defenseSign = (useX and (sx <= cx) or (sz <= cz)) and -1 or 1
local enemySign = -defenseSign
local defenderT = defenseSign * 0.72
local enemyT = enemySign * 0.58
local pathEndT = defenseSign * 0.70
print(("defenseSign=%d enemySign=%d"):format(defenseSign, enemySign))

local ex, ez = alongXZ(enemyT, 0)
local dx0, dz0 = alongXZ(defenderT, 0)
local lookX, lookZ = ex - dx0, ez - dz0
local lookLen = math.sqrt(lookX * lookX + lookZ * lookZ)
if lookLen > 0.1 then
	lookX, lookZ = lookX / lookLen, lookZ / lookLen
else
	lookX, lookZ = 0, 0
end

local laterals = { -width * 0.38, -width * 0.14, width * 0.14, width * 0.38 }
print("\n=== РІС‹СЃС‚СЂРµР» Р±РѕС‚Р° РѕР±РѕСЂРѕРЅС‹ РїРѕ РІСЂР°РіСѓ (СЃС‚РІРѕР» +1.35 РЅР°Рґ root) ===")
for i, lateral in ipairs(laterals) do
	local px, pz = alongXZ(defenderT, lateral)
	local oy = surfaceY(px, pz) + 3.05 + 1.35
	local ox, oz = px + lookX * 0.6, pz + lookZ * 0.6
	for _, frac in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
		local t = enemyT * (1 - frac) + pathEndT * frac
		local tx, tz = alongXZ(t, 0)
		local ty = surfaceY(tx, tz) + 3.05 + 1.0
		local dist = math.sqrt((tx - ox) ^ 2 + (ty - oy) ^ 2 + (tz - oz) ^ 2)
		local clearOld, blockerOld = traceLos(ox, oy, oz, tx, ty, tz, "old")
		local clearNew, blockerNew, skips = traceLos(ox, oy, oz, tx, ty, tz, "new")
		print(("lane%d t=%.2f d=%.0f | OLD=%s %s | NEW=%s %s | skips=%d"):format(
			i - 3,
			t,
			dist,
			clearOld and "clear" or "BLOCKED",
			clearOld and "" or ("by " .. blockerOld),
			clearNew and "clear" or "BLOCKED",
			clearNew and "" or ("by " .. blockerNew),
			#skips
		))
		for _, s in ipairs(skips) do
			print("        skip: " .. s)
		end
	end
end

-- 4) КТО блокирует: детали вокруг линии обороны (полные пути, размеры, свойства)
print("\n=== детали вокруг линии обороны ===")
local probeX, probeZ = alongXZ(defenderT, 0)
print(("probe: X=%.1f Z=%.1f (deckY=%.1f, muzzleY~%.1f)"):format(probeX, probeZ, deckSurfaceY, deckSurfaceY + 4.4))
local near = {}
for _, info in ipairs(parts) do
	if math.abs(info.px - probeX) <= 12 and math.abs(info.pz - probeZ) <= 90 then
		if info.py >= deckSurfaceY - 2 and info.py <= deckSurfaceY + 32 then
			table.insert(near, info)
		end
	end
end
table.sort(near, function(a, b)
	return a.px < b.px
end)
print(("parts near defense line: %d"):format(#near))
for _, info in ipairs(near) do
	local okFull, full = pcall(function()
		return info.part:GetFullName()
	end)
	local okMat, mat = pcall(function()
		return info.part.Material.Name
	end)
	print(("  %-52s size=(%7.1f,%6.1f,%6.1f) pos=(%9.1f,%8.1f,%9.1f) coll=%-5s tr=%.2f mat=%s"):format(
		okFull and full or ("?" .. info.part.Name),
		info.sx,
		info.sy,
		info.sz,
		info.px,
		info.py,
		info.pz,
		tostring(info.canCollide),
		info.transparency,
		okMat and mat or "?"
	))
end

-- 5) сколько партов вообще попадает в луч по мосту (все подряд, без правил)
print("\n=== что стоит на пути выстрела (по 1-й полосе, t=0.58) ===")
local oxx, ozz = alongXZ(defenderT, laterals[1])
local oyy = surfaceY(oxx, ozz) + 3.05 + 1.35
local txx, tzz = alongXZ(enemyT, 0)
local tyy = surfaceY(txx, tzz) + 3.05 + 1.0
local ddx, ddy, ddz = txx - oxx, tyy - oyy, tzz - ozz
local rng = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
ddx, ddy, ddz = ddx / rng, ddy / rng, ddz / rng
local hits = {}
for _, info in ipairs(parts) do
	local t, axis, sign = rayBox(oxx, oyy, ozz, ddx, ddy, ddz, rng, info)
	if t then
		local nx, ny, nz = axisNormal(info, axis, sign)
		local okFull, full = pcall(function()
			return info.part:GetFullName()
		end)
		table.insert(hits, {
			t = t,
			text = ("  t=%7.1f n=(%5.2f,%5.2f,%5.2f) %-46s size=(%7.1f,%6.1f,%6.1f) coll=%-5s tr=%.2f"):format(
				t,
				nx,
				ny,
				nz,
				okFull and full or ("?" .. info.part.Name),
				info.sx,
				info.sy,
				info.sz,
				tostring(info.canCollide),
				info.transparency
			),
		})
	end
end
table.sort(hits, function(a, b)
	return a.t < b.t
end)
print(("hits along shot: %d (range %.0f)"):format(#hits, rng))
for i, h in ipairs(hits) do
	if i <= 20 then
		print(h.text)
	end
end




-- 6) Проверка будущего фикса: невидимые (tr>=0.7) детали с коллизией в боевом
--    коридоре — считаем их и смотрим AABB-перекрытие с коридором
local samples = {}
local function pushSample(x, y, z)
	table.insert(samples, { x = x, y = y, z = z })
end
local eSpawnX, eSpawnZ = alongXZ(enemyT, 0)
pushSample(eSpawnX, surfaceY(eSpawnX, eSpawnZ) + 3.05, eSpawnZ)
for i = 0, 20 do
	local t = enemyT * (1 - i / 20) + pathEndT * (i / 20)
	local x, z = alongXZ(t, 0)
	pushSample(x, surfaceY(x, z) + 3.05, z)
end
for _, lateral in ipairs(laterals) do
	local x, z = alongXZ(defenderT, lateral)
	pushSample(x, surfaceY(x, z) + 3.05, z)
end

local minSx, maxSx, minSy, maxSy, minSz, maxSz = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
for _, s in ipairs(samples) do
	minSx, maxSx = math.min(minSx, s.x), math.max(maxSx, s.x)
	minSy, maxSy = math.min(minSy, s.y), math.max(maxSy, s.y)
	minSz, maxSz = math.min(minSz, s.z), math.max(maxSz, s.z)
end
-- запас: вдоль оси моста 12, поперёк (полуширина моста + 2), по высоте -3..+9
-- (зеркало GameConfig.Battle.CorridorClear: AlongPad / LateralPad / Below / Above)
local alongPad, lateralPad = 12, width * 0.5 + 2
local boxMinX, boxMaxX, boxMinZ, boxMaxZ = minSx - alongPad, maxSx + alongPad, minSz - lateralPad, maxSz + lateralPad
if not useX then
	boxMinX, boxMaxX = minSx - lateralPad, maxSx + lateralPad
	boxMinZ, boxMaxZ = minSz - alongPad, maxSz + alongPad
end
local boxMinY, boxMaxY = deckSurfaceY - 3, deckSurfaceY + 9
print(
	("\n=== боевой коридор AABB: X[%.1f..%.1f] Y[%.1f..%.1f] Z[%.1f..%.1f] ==="):format(
		boxMinX,
		boxMaxX,
		boxMinY,
		boxMaxY,
		boxMinZ,
		boxMaxZ
	)
)

local function partAabb(info)
	local mnx, mxx, mny, mxy, mnz, mxz = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local ex, ey, ez = info.sx * 0.5 * sx, info.sy * 0.5 * sy, info.sz * 0.5 * sz
				local x = info.px + info.rx * ex + info.ux * ey + info.fx * ez
				local y = info.py + info.ry * ex + info.uy * ey + info.fy * ez
				local z = info.pz + info.rz * ex + info.uz * ey + info.fz * ez
				mnx, mxx = math.min(mnx, x), math.max(mxx, x)
				mny, mxy = math.min(mny, y), math.max(mxy, y)
				mnz, mxz = math.min(mnz, z), math.max(mxz, z)
			end
		end
	end
	return mnx, mxx, mny, mxy, mnz, mxz
end

local inCorridor, invisibleInCorridor = 0, {}
for _, info in ipairs(parts) do
	local mnx, mxx, mny, mxy, mnz, mxz = partAabb(info)
	local overlap = mxx >= boxMinX
		and mnx <= boxMaxX
		and mxy >= boxMinY
		and mny <= boxMaxY
		and mxz >= boxMinZ
		and mnz <= boxMaxZ
	if overlap then
		inCorridor += 1
		if info.canCollide and info.transparency >= 0.7 then
			local okFull, full = pcall(function()
				return info.part:GetFullName()
			end)
			table.insert(
				invisibleInCorridor,
				("  %-52s size=(%7.1f,%6.1f,%6.1f) pos=(%9.1f,%8.1f,%9.1f) tr=%.2f"):format(
					okFull and full or ("?" .. info.part.Name),
					info.sx,
					info.sy,
					info.sz,
					info.px,
					info.py,
					info.pz,
					info.transparency
				)
			)
		end
	end
end
print(("партов в коридоре: %d, из них невидимых с коллизией: %d"):format(inCorridor, #invisibleInCorridor))
for _, line in ipairs(invisibleInCorridor) do
	print(line)
end

-- 7) Симуляция фикса MapBind.clearInvisibleObstructions: гасим коллизию у
--    невидимых частей в коридоре и повторяем прогон выстрелов ботов.
local function overlapsCorridor(info)
	local mnx, mxx, mny, mxy, mnz, mxz = partAabb(info)
	local boxHit = mxx >= boxMinX
		and mnx <= boxMaxX
		and mxy >= boxMinY
		and mny <= boxMaxY
		and mxz >= boxMinZ
		and mnz <= boxMaxZ
	if not boxHit then
		return false
	end
	-- как в рантайме: GetPartBoundsInBox (AABB) + центр детали внутри коридора по X/Z
	return info.px >= boxMinX and info.px <= boxMaxX and info.pz >= boxMinZ and info.pz <= boxMaxZ
end

-- прогон ДО фикса: OLD / NEW(0.9) / FINAL(0.7) — FINAL = как в CombatVFX после правки
local function summarize(label, rows, old, new, final)
	print(("%s: OLD=%d/%d  NEW(0.9)=%d/%d  FINAL(0.7)=%d/%d"):format(label, old, rows, new, rows, final, rows))
end

local beforeRows, beforeOld, beforeNew, beforeFinal = 0, 0, 0, 0
for i, lateral in ipairs(laterals) do
	local px, pz = alongXZ(defenderT, lateral)
	local oy = surfaceY(px, pz) + 3.05 + 1.35
	local ox, oz = px + lookX * 0.6, pz + lookZ * 0.6
	for _, frac in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
		local t = enemyT * (1 - frac) + pathEndT * frac
		local tx, tz = alongXZ(t, 0)
		local ty = surfaceY(tx, tz) + 3.05 + 1.0
		beforeRows += 1
		if (traceLos(ox, oy, oz, tx, ty, tz, "old")) then
			beforeOld += 1
		end
		if (traceLos(ox, oy, oz, tx, ty, tz, "new")) then
			beforeNew += 1
		end
		if (traceLos(ox, oy, oz, tx, ty, tz, "final")) then
			beforeFinal += 1
		end
	end
end
summarize("\n=== ДО фикса", beforeRows, beforeOld, beforeNew, beforeFinal)

local clearedCount = 0
for _, info in ipairs(parts) do
	if overlapsCorridor(info) and info.canCollide and info.transparency >= 0.7 then
		info.canCollide = false
		clearedCount += 1
	end
end
print(("\n=== после выключения коллизии у невидимых в коридоре: %d частей ==="):format(clearedCount))

local rows, clearOld, clearNew, clearFinal = 0, 0, 0, 0
local leftovers = {}
for i, lateral in ipairs(laterals) do
	local px, pz = alongXZ(defenderT, lateral)
	local oy = surfaceY(px, pz) + 3.05 + 1.35
	local ox, oz = px + lookX * 0.6, pz + lookZ * 0.6
	for _, frac in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
		local t = enemyT * (1 - frac) + pathEndT * frac
		local tx, tz = alongXZ(t, 0)
		local ty = surfaceY(tx, tz) + 3.05 + 1.0
		rows += 1
		if (traceLos(ox, oy, oz, tx, ty, tz, "old")) then
			clearOld += 1
		end
		if (traceLos(ox, oy, oz, tx, ty, tz, "new")) then
			clearNew += 1
		end
		local clear, blocker, skips = traceLos(ox, oy, oz, tx, ty, tz, "final")
		if clear then
			clearFinal += 1
		else
			table.insert(leftovers, ("lane%d t=%.2f FINAL=%s skips=%d"):format(i - 3, t, blocker, #skips))
		end
	end
end
summarize("=== ПОСЛЕ фикса (снята коллизия)", rows, clearOld, clearNew, clearFinal)
for _, line in ipairs(leftovers) do
	print("  ОСТАЛОСЬ ЗАБЛОКИРОВАНО: " .. line)
end

