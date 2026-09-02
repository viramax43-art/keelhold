local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("Commission_place (1).rbxl"))
local ws = game:GetService("Workspace")

local function dumpModel(name, depthLimit)
	local inst = ws:FindFirstChild(name)
	if not inst then print(name, "missing"); return end
	print("===", name, inst.ClassName, "children", #inst:GetChildren(), "desc", #inst:GetDescendants())
	local counts = {}
	for _, d in inst:GetDescendants() do
		counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
	end
	for cls, n in counts do
		print(" ", cls, n)
	end
	-- first 20 descendants with any Position-like
	local shown = 0
	for _, d in inst:GetDescendants() do
		local ok, pos = pcall(function() return d.Position end)
		local ok2, cf = pcall(function() return d.CFrame end)
		if (ok and pos) or (ok2 and cf) then
			print(" POS", d.ClassName, d.Name, ok and pos or cf.Position)
			shown += 1
			if shown >= 8 then break end
		end
	end
end

dumpModel("Road Bridge")
dumpModel("BackShop")
dumpModel("WoodenLeaderboard")
dumpModel("Teleports")

-- Workspace.Model (spawn parent)
print("\n=== Workspace.Model overview ===")
local m = ws:FindFirstChild("Model")
if m then
	print("children", #m:GetChildren())
	for _, c in m:GetChildren() do
		print(" ", c.ClassName, c.Name)
	end
end

-- try CFrame property raw
local mt = ws.Teleports.MainTeleport
print("\nMainTeleport class", mt.ClassName)
for _, prop in {"Position", "CFrame", "Size", "Anchored"} do
	local ok, v = pcall(function() return mt[prop] end)
	print(prop, ok, v)
end