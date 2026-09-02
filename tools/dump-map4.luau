local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("Commission_place (1).rbxl"))
local ws = game:GetService("Workspace")

local function avgPos(inst)
	local sx, sy, sz, n = 0, 0, 0, 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			local ok, pos = pcall(function() return d.Position end)
			if ok and pos then
				sx += pos.X; sy += pos.Y; sz += pos.Z; n += 1
			end
		end
	end
	if n == 0 then return nil, 0 end
	return Vector3.new(sx/n, sy/n, sz/n), n
end

for _, name in {"BackShop", "Road Bridge", "WoodenLeaderboard", "Pubg Air Drop", "base_model_of_gun"} do
	local inst = ws:FindFirstChild(name)
	if inst then
		local avg, n = avgPos(inst)
		print(name, "parts", n, "avg", avg)
	else
		print(name, "NOT FOUND at top")
	end
end

print("\n=== Shop BaseParts ===")
for _, d in ws:GetDescendants() do
	if d.Name == "Shop" and d:IsA("BasePart") then
		local ok, pos = pcall(function() return d.Position end)
		print(d:GetFullName(), ok and pos)
	end
end

print("\n=== Near spawn ===")
local spawnPos = Vector3.new(-2406.4126, 1799.9209, -5263.0303)
local near = {}
for _, c in ws:GetChildren() do
	local avg, n = avgPos(c)
	if avg and n > 0 then
		local dist = (avg - spawnPos).Magnitude
		if dist < 600 then
			table.insert(near, {name=c.Name, class=c.ClassName, dist=dist, pos=avg, n=n})
		end
	end
end
table.sort(near, function(a,b) return a.dist < b.dist end)
for i, item in near do
	if i <= 50 then
		print(string.format("%4.0f n=%d %s %s %s", item.dist, item.n, item.class, item.name, tostring(item.pos)))
	end
end

print("\n=== Road Bridge span ===")
local bridge = ws:FindFirstChild("Road Bridge")
if bridge then
	local minx,miny,minz = 1e9,1e9,1e9
	local maxx,maxy,maxz = -1e9,-1e9,-1e9
	local i = 0
	for _, d in bridge:GetDescendants() do
		if d:IsA("BasePart") then
			local ok, pos = pcall(function() return d.Position end)
			if ok and pos then
				minx=math.min(minx,pos.X); miny=math.min(miny,pos.Y); minz=math.min(minz,pos.Z)
				maxx=math.max(maxx,pos.X); maxy=math.max(maxy,pos.Y); maxz=math.max(maxz,pos.Z)
				i += 1
			end
		end
	end
	print("parts", i)
	print("min", minx, miny, minz)
	print("max", maxx, maxy, maxz)
	print("center", (minx+maxx)/2, (miny+maxy)/2, (minz+maxz)/2)
	print("span", maxx-minx, maxy-miny, maxz-minz)
end

print("\n=== MainTeleport ===")
local mt = ws.Teleports and ws.Teleports:FindFirstChild("MainTeleport")
if mt then
	print(mt.Position)
end