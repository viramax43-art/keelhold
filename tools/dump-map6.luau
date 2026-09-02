local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("Commission_place (1).rbxl"))
local ws = game:GetService("Workspace")

local function cfOf(d)
	local ok, cf = pcall(function() return d.CFrame end)
	if ok and cf then return cf end
end

print("=== Shop-related ===")
for _, d in ws:GetDescendants() do
	if d.Name == "Shop" or d.Name == "GShop" or d.Name == "BackShop" then
		local cf = cfOf(d)
		print(d.ClassName, d:GetFullName(), cf and cf.Position)
	end
end

print("\n=== Billboard texts near lobby (x>-3000 x<-1500) ===")
for _, d in ws:GetDescendants() do
	if d.ClassName == "TextLabel" then
		local ok, text = pcall(function() return d.Text end)
		if ok and text and #text > 0 and #text < 40 then
			local adornee = d.Parent and d.Parent.Parent
			local part = d:FindFirstAncestorWhichIsA("BasePart")
			local cf = part and cfOf(part)
			if cf then
				local p = cf.Position
				if p.X > -3000 and p.X < -1500 and p.Z > -6000 and p.Z < -4500 then
					print(string.format("%q @ %.0f,%.0f,%.0f (%s)", text, p.X, p.Y, p.Z, part:GetFullName()))
				end
			end
		end
	end
end

print("\n=== Parts named meaningfully near lobby ===")
local keys = {"gun","weapon","train","upgrade","promo","daily","reward","mission","battle","table","bench","armor","crate","chest","box","npc","board","sign"}
for _, d in ws:GetDescendants() do
	if d:IsA("BasePart") or d:IsA("Model") then
		local n = string.lower(d.Name)
		for _, k in keys do
			if string.find(n, k, 1, true) then
				local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
				local cf = part and cfOf(part)
				if cf then
					local p = cf.Position
					if p.X > -3000 and p.X < -1500 and p.Z > -6000 and p.Z < -4500 then
						print(d.ClassName, d.Name, p)
					end
				end
				break
			end
		end
	end
end

print("\n=== base_model_of_gun / unit ===")
for _, name in {"base_model_of_gun", "base_model_of_unit"} do
	local m = ws:FindFirstChild(name)
	if m then
		print(name, "desc", #m:GetDescendants())
		local part = m:FindFirstChildWhichIsA("BasePart", true)
		if part then print(" ", cfOf(part) and cfOf(part).Position) end
	end
end