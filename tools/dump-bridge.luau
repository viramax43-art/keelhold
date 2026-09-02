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
if not bridge then
	print("NO BRIDGE FOUND")
	print("Top-level instances:")
	for _, c in instances do
		print(" -", c.ClassName, c.Name)
	end
	os.exit()
end

print("BRIDGE:", bridge.ClassName, bridge.Name, bridge:GetFullName())
local parts = {}
for _, d in bridge:GetDescendants() do
	if d.ClassName == "Part" or d.ClassName == "MeshPart" then
		table.insert(parts, d)
	end
end
print("part count:", #parts)

local rows = {}
for _, p in parts do
	local okSz, sz = pcall(function() return p.Size end)
	local okCf, cf = pcall(function() return p.CFrame end)
	if okSz and okCf and sz and cf and cf.Position then
		local pos = cf.Position
		local top = pos.Y + sz.Y * 0.5
		local flat = math.max(sz.X, sz.Z)
		table.insert(rows, {
			name = p.Name,
			size = string.format("%.1f,%.1f,%.1f", sz.X, sz.Y, sz.Z),
			pos = string.format("%.0f,%.0f,%.0f", pos.X, pos.Y, pos.Z),
			top = top,
			flat = flat,
			thick = sz.Y,
		})
	end
end

-- Sort by top surface Y ascending
table.sort(rows, function(a, b) return a.top < b.top end)

-- Bucket by top-Y (round to nearest 1 stud)
local buckets = {}
for _, r in rows do
	local k = math.floor(r.top + 0.5)
	buckets[k] = (buckets[k] or 0) + 1
end
print("\n=== TOP-Y DISTRIBUTION (rounded, count) ===")
local keys = {}
for k in pairs(buckets) do table.insert(keys, k) end
table.sort(keys)
for _, k in keys do
	print(string.format("topY~%d : %d parts", k, buckets[k]))
end

-- The "wide flat" parts (deck): flat >= 6, thick <= 8
local wideFlat = {}
for _, r in rows do
	if r.flat >= 6 and r.thick <= 8 then
		table.insert(wideFlat, r)
	end
end
print("\n=== WIDE FLAT PARTS (flat>=6, thick<=8):", #wideFlat, "===")
table.sort(wideFlat, function(a, b) return a.top < b.top end)
for _, r in wideFlat do
	print(string.format("top=%.1f  flat=%.1f thick=%.1f  %s  size(%s) pos(%s)", r.top, r.flat, r.thick, r.name, r.size, r.pos))
end
