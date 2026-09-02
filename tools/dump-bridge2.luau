local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local projectRoot = process.cwd
local instances = roblox.deserializeModel(fs.readFile(projectRoot .. "/map/CommissionMap.rbxm"))

local function findBridge(node)
	if node.Name == "Road Bridge" or node.Name == "RoadBridge" then
		return node
	end
	for _, c in node:GetChildren() do
		local r = findBridge(c)
		if r then return r end
	end
	return nil
end

local bridge = nil
for _, inst in instances do
	bridge = findBridge(inst)
	if bridge then break end
end

local parts = {}
for _, d in bridge:GetDescendants() do
	if d.ClassName == "Part" or d.ClassName == "MeshPart" then
		table.insert(parts, d)
	end
end

local rows = {}
for _, p in parts do
	local okSz, sz = pcall(function() return p.Size end)
	local okCf, cf = pcall(function() return p.CFrame end)
	if okSz and okCf and sz and cf and cf.Position then
		local pos = cf.Position
		local top = pos.Y + sz.Y * 0.5
		local bot = pos.Y - sz.Y * 0.5
		local flat = math.max(sz.X, sz.Z)
		local area = sz.X * sz.Z
		table.insert(rows, {
			name = p.Name,
			sx = sz.X, sy = sz.Y, szz = sz.Z,
			top = top, bot = bot, flat = flat, area = area,
		})
	end
end

print("Total parts:", #rows)

-- Histogram of top-Y for thin horizontal plates (deck surface): sy<=2 and flat>=6
local hist = {}
local function bucket(y) return math.floor(y * 2 + 0.5) / 2 end
for _, r in rows do
	if r.sy <= 2 and r.flat >= 6 then
		local k = bucket(r.top)
		hist[k] = (hist[k] or 0) + 1
	end
end
local keys = {}
for k in pairs(hist) do table.insert(keys, k) end
table.sort(keys)
print("\n=== THIN (sy<=2) FLAT(>=6) parts top-Y histogram (0.5 precision) ===")
for _, k in keys do
	print(string.format("topY=%7.1f : %d parts", k, hist[k]))
end

-- The deck walkable surface = top-Y of the biggest-area horizontal plates (area >= 20)
local bigPlates = {}
for _, r in rows do
	if r.sy <= 2 and r.flat >= 10 and r.area >= 20 then
		table.insert(bigPlates, r)
	end
end
print("\n=== BIG PLATES (sy<=2, flat>=10, area>=20):", #bigPlates, "===")
table.sort(bigPlates, function(a,b) return a.top < b.top end)
for _, r in bigPlates do
	print(string.format("top=%7.1f bot=%7.1f size(%.1f x %.1f x %.1f) flat=%.0f area=%.0f %s",
		r.top, r.bot, r.sx, r.sy, r.szz, r.flat, r.area, r.name))
end
