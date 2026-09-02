local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("Commission_place (1).rbxl"))
local ws = game:GetService("Workspace")

print("=== ClickDetector / ProximityPrompt / SpawnLocation ===")
for _, d in ws:GetDescendants() do
	if d.ClassName == "ClickDetector" or d.ClassName == "ProximityPrompt" or d.ClassName == "SpawnLocation" then
		local parent = d.Parent
		print(d.ClassName, d:GetFullName(), "parentPart=", parent and parent.ClassName)
		if d.ClassName == "ProximityPrompt" then
			print("  ActionText=", d.ActionText, "ObjectText=", d.ObjectText, "MaxDist=", d.MaxActivationDistance)
		end
		if d.ClassName == "ClickDetector" then
			print("  MaxDist=", d.MaxActivationDistance)
		end
	end
end

print("\n=== Teleports ===")
local t = ws:FindFirstChild("Teleports")
if t then
	for _, c in t:GetChildren() do
		print(c.ClassName, c.Name)
		if c:IsA("BasePart") then
			print("  pos", c.Position)
		elseif c:IsA("Model") and c.PrimaryPart then
			print("  pp", c.PrimaryPart.Position)
		end
		for _, d in c:GetDescendants() do
			print("  ", d.ClassName, d.Name)
		end
	end
end

print("\n=== BackShop tree (depth2) ===")
local shop = ws:FindFirstChild("BackShop")
if shop then
	for _, c in shop:GetChildren() do
		print(c.ClassName, c.Name)
		for _, d in c:GetChildren() do
			print("  ", d.ClassName, d.Name)
		end
	end
	local ok, cf, size = pcall(function() return shop:GetBoundingBox() end)
	if ok then print("bbox", cf.Position, size) end
end

print("\n=== Road Bridge bbox ===")
local bridge = ws:FindFirstChild("Road Bridge")
if bridge then
	local ok, cf, size = pcall(function() return bridge:GetBoundingBox() end)
	if ok then print("bbox", cf.Position, size) end
	for _, c in bridge:GetChildren() do
		print(c.ClassName, c.Name)
	end
end

print("\n=== WoodenLeaderboard ===")
for _, lb in ws:GetChildren() do
	if lb.Name == "WoodenLeaderboard" then
		local ok, cf, size = pcall(function() return lb:GetBoundingBox() end)
		if ok then print("pos", cf.Position, size) end
	end
end

print("\n=== TextLabels with Shop/Mission/etc ===")
for _, d in ws:GetDescendants() do
	if d.ClassName == "TextLabel" or d.ClassName == "BillboardGui" then
		local text = d.Text
		if text and #text > 0 and #text < 40 then
			local tl = string.lower(text)
			if string.find(tl,"shop") or string.find(tl,"gun") or string.find(tl,"train") or string.find(tl,"mission") or string.find(tl,"promo") or string.find(tl,"daily") or string.find(tl,"top") or string.find(tl,"battle") or string.find(tl,"upgrade") or string.find(tl,"lobby") then
				print(text, "at", d:GetFullName())
			end
		end
	end
end

print("\n=== Letters / ThreeDText ===")
local letters = ws:FindFirstChild("Letters")
if letters then
	for _, c in letters:GetChildren() do
		print(c.ClassName, c.Name)
	end
end
for _, d in ws:GetDescendants() do
	if string.find(string.lower(d.Name), "threed") or d.Name == "GShop" or d.Name == "@Shop" or d.Name == "Shop" then
		print(d.ClassName, d:GetFullName())
	end
end

print("\n=== Folder named Folder ===")
local f = ws:FindFirstChild("Folder")
if f then
	for _, c in f:GetChildren() do print(c.ClassName, c.Name) end
end