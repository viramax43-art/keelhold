local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("BridgeDefense_Commission.rbxl"))
local ws = game:GetService("Workspace")
print("Workspace children:")
for _, c in ws:GetChildren() do
	print(" -", c.ClassName, c.Name)
end
local sss = game:GetService("ServerScriptService")
print("SSS children:")
for _, c in sss:GetChildren() do
	print(" -", c.ClassName, c.Name)
end
for _, d in ws:GetDescendants() do
	if d.Name == "Road Bridge" or d.Name == "BackShop" then
		print("FOUND", d.Name, d:GetFullName())
	end
end
local spawn = ws:FindFirstChildWhichIsA("SpawnLocation", true)
print("SpawnLocation", spawn and spawn:GetFullName() or "NONE")
