-- Extract Commission map for Rojo (single top-level instances only)
-- Prefer wider-bridge place (2); fall back to (1).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local projectRoot = process.cwd
local candidates = {
	projectRoot .. "/Commission_place (2).rbxl",
	projectRoot .. "/Commission_place (1).rbxl",
}
local placePath = nil
for _, p in ipairs(candidates) do
	if fs.isFile(p) then
		placePath = p
		break
	end
end
if not placePath then
	error("No Commission_place (2)/(1).rbxl in project root")
end
print("Using place:", placePath)
local outDir = projectRoot .. "/map"
fs.writeDir(outDir)

local game = roblox.deserializePlace(fs.readFile(placePath))
local workspace = game:GetService("Workspace")

local mapArt = roblox.Instance.new("Folder")
mapArt.Name = "CommissionMap"

local terrain = nil
local count = 0
for _, child in workspace:GetChildren() do
	if child.ClassName == "Camera" then
		-- skip
	elseif child.ClassName == "Terrain" then
		terrain = child
	else
		child.Parent = mapArt
		count += 1
	end
end

print("MapArt children:", count)
fs.writeFile(outDir .. "/CommissionMap.rbxm", roblox.serializeModel({ mapArt }))
print("Wrote CommissionMap.rbxm")

if terrain then
	fs.writeFile(outDir .. "/Terrain.rbxm", roblox.serializeModel({ terrain }))
	print("Wrote Terrain.rbxm")
else
	print("WARN: no Terrain")
end

-- Lighting: single Folder wrapper
local lighting = game:GetService("Lighting")
local lightFolder = roblox.Instance.new("Folder")
lightFolder.Name = "CommissionLighting"
for _, child in lighting:GetChildren() do
	child.Parent = lightFolder
end
fs.writeFile(outDir .. "/CommissionLighting.rbxm", roblox.serializeModel({ lightFolder }))
print("Wrote CommissionLighting.rbxm")
print("OK")
