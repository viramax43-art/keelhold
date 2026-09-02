local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local place = "Commission_place (1).rbxl"
local game = roblox.deserializePlace(fs.readFile(place))
local ws = game:GetService("Workspace")

local function interesting(name)
	local n = string.lower(name)
	local keys = {"shop","upgrade","train","promo","daily","reward","leader","board","battle","mission","teleport","spawn","bridge","road","gun","weapon","armor","buy","click","prompt","lobby","table","zone","interact","door","bench","point","path","enemy","defense"}
	for _, k in keys do
		if string.find(n, k, 1, true) then return true end
	end
	return false
end

print("=== TOP ===")
for _, c in ws:GetChildren() do
	print(c.ClassName, c.Name)
end

print("\n=== INTERESTING DESCENDANTS ===")
for _, d in ws:GetDescendants() do
	if interesting(d.Name) or d.ClassName == "ProximityPrompt" or d.ClassName == "ClickDetector" or d.ClassName == "SpawnLocation" then
		print(d.ClassName, d:GetFullName())
	end
end

print("\n=== TELEPORTS FOLDER ===")
local t = ws:FindFirstChild("Teleports", true)
if t then
	for _, c in t:GetDescendants() do
		print(c.ClassName, c:GetFullName())
	end
end

print("\n=== SCRIPTS IN WORKSPACE ===")
for _, d in ws:GetDescendants() do
	if d.ClassName == "Script" or d.ClassName == "LocalScript" then
		print(d.ClassName, d:GetFullName())
	end
end