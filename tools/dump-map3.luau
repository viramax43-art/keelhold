local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("Commission_place (1).rbxl"))
local ws = game:GetService("Workspace")

local function pivotOf(inst)
	local ok, cf = pcall(function()
		if inst:IsA("Model") then
			return inst:GetPivot()
		elseif inst:IsA("BasePart") then
			return inst.CFrame
		end
		return nil
	end)
	return ok and cf or nil
end

local function bboxOf(inst)
	if not inst:IsA("Model") then return end
	local ok, cf, size = pcall(function() return inst:GetBoundingBox() end)
	if ok then return cf, size end
end

print("=== Teleports children ===")
local t = ws:FindFirstChild("Teleports")
if t then
	for _, c in t:GetChildren() do
		print(c.ClassName, c.Name)
		local cf = pivotOf(c)
		if cf then print("  pivot", cf.Position) end
		for _, d in c:GetDescendants() do
			print("  desc", d.ClassName, d.Name)
		end
	end
end

print("\n=== Named landmarks ===")
for _, name in {"BackShop", "Road Bridge", "WoodenLeaderboard", "Pubg Air Drop", "Stone Path (Long)", "base_model_of_gun", "base_model_of_unit"} do
	local inst = ws:FindFirstChild(name)
	if inst then
		local cf, size = bboxOf(inst)
		if cf then
			print(name, "pos", cf.Position, "size", size)
		else
			local p = pivotOf(inst)
			print(name, "pivot", p and p.Position)
		end
	else
		print(name, "MISSING")
	end
end

print("\n=== All WoodenLeaderboard ===")
for _, c in ws:GetChildren() do
	if c.Name == "WoodenLeaderboard" then
		local cf, size = bboxOf(c)
		print("LB", cf and cf.Position, size)
	end
end

print("\n=== SpawnLocation ===")
for _, d in ws:GetDescendants() do
	if d.ClassName == "SpawnLocation" then
		local cf = pivotOf(d)
		print(d:GetFullName(), cf and cf.Position)
	end
end

print("\n=== StringValues / IntValues near teleports ===")
for _, d in ws:GetDescendants() do
	if d.ClassName == "StringValue" or d.ClassName == "ObjectValue" or d.ClassName == "IntValue" then
		if string.find(string.lower(d:GetFullName()), "teleport") or string.find(string.lower(d.Name), "island") or string.find(string.lower(d.Name), "lobby") or string.find(string.lower(d.Name), "target") then
			print(d.ClassName, d:GetFullName(), "Value=", tostring(d.Value))
		end
	end
end

print("\n=== Models containing Shop in name path ===")
for _, d in ws:GetDescendants() do
	local n = string.lower(d.Name)
	if n == "shop" or n == "gshop" or n == "@shop" or string.find(n, "weapon") or string.find(n, "armory") or string.find(n, "train") then
		print(d.ClassName, d:GetFullName())
	end
end

print("\n=== Billboard / SurfaceGui texts ===")
for _, d in ws:GetDescendants() do
	if d.ClassName == "TextLabel" then
		local ok, text = pcall(function() return d.Text end)
		if ok and text and #text > 1 and #text < 30 then
			print(string.format("%q", text), d.Parent and d.Parent.Name)
		end
	end
end