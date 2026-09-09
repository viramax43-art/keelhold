--[[
	WeaponBuilder — детализированное процедурное оружие для юнитов.
]]

local WeaponBuilder = {}

local COLORS = {
	Pistol = Color3.fromRGB(55, 58, 65),
	Revolver = Color3.fromRGB(95, 72, 48),
	SMG = Color3.fromRGB(48, 52, 58),
	Rifle = Color3.fromRGB(42, 48, 42),
	Shotgun = Color3.fromRGB(78, 58, 40),
	LMG = Color3.fromRGB(38, 42, 48),
	Sniper = Color3.fromRGB(32, 38, 52),
	Crossbow = Color3.fromRGB(88, 58, 36),
}

local function part(model, name, size, color, cf, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Metal
	p.CanCollide = false
	p.Massless = true
	p.CastShadow = true
	p.Anchored = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p.Parent = model
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function accent(model, handle, offset, size, color)
	local p = part(model, "Accent", size, color, handle.CFrame * offset)
	weld(handle, p)
	return p
end

function WeaponBuilder.Create(weaponType: string, tier: number?): Model
	weaponType = weaponType or "Pistol"
	tier = math.clamp(tonumber(tier) or 1, 1, 10)
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. weaponType
	local tierTints = {
		Color3.fromRGB(115, 120, 126),
		Color3.fromRGB(72, 116, 82),
		Color3.fromRGB(61, 88, 124),
		Color3.fromRGB(100, 65, 120),
		Color3.fromRGB(126, 101, 51),
		-- Элитные (престиж) тиры
		Color3.fromRGB(140, 60, 60),
		Color3.fromRGB(140, 50, 90),
		Color3.fromRGB(80, 130, 140),
		Color3.fromRGB(70, 140, 85),
		Color3.fromRGB(150, 150, 150),
	}
	local base = (COLORS[weaponType] or COLORS.Pistol):Lerp(tierTints[tier], 0.16)
	local dark = base:Lerp(Color3.new(0, 0, 0), 0.35)
	local light = base:Lerp(Color3.new(1, 1, 1), 0.2)
	local wood = Color3.fromRGB(110, 75, 45)
	local origin = CFrame.new()

	local handle = part(model, "Handle", Vector3.new(0.28, 0.55, 0.28), dark, origin)
	model.PrimaryPart = handle

	if weaponType == "Pistol" or weaponType == "Revolver" then
		local body = part(model, "Body", Vector3.new(0.35, 0.32, 0.7), base, origin * CFrame.new(0, 0.22, -0.15))
		weld(handle, body)
		local barrelLen = weaponType == "Revolver" and 0.85 or 0.55
		local slide = part(
			model,
			"Slide",
			Vector3.new(0.38, 0.18, if weaponType == "Revolver" then 0.55 else 0.78),
			dark,
			origin * CFrame.new(0, 0.4, -0.18)
		)
		weld(handle, slide)
		local barrel = part(model, "Barrel", Vector3.new(barrelLen, 0.14, 0.14), light, origin, Enum.PartType.Cylinder)
		barrel.CFrame = origin
			* CFrame.new(0, 0.3, -0.35 - barrelLen / 2)
			* CFrame.Angles(0, math.rad(90), 0)
		weld(handle, barrel)
		if weaponType == "Revolver" then
			local cyl = part(model, "Cylinder", Vector3.new(0.38, 0.28, 0.38), dark, origin * CFrame.new(0, 0.28, -0.05), Enum.PartType.Cylinder)
			cyl.CFrame = origin * CFrame.new(0, 0.28, -0.05) * CFrame.Angles(0, math.rad(90), 0)
			weld(handle, cyl)
		end
		accent(model, handle, CFrame.new(0, 0.05, 0.12), Vector3.new(0.22, 0.2, 0.18), wood)
		local sight = part(model, "Sight", Vector3.new(0.06, 0.1, 0.08), Color3.fromRGB(20, 20, 25), origin * CFrame.new(0, 0.42, -0.35))
		weld(handle, sight)
	elseif weaponType == "SMG" then
		local body = part(model, "Body", Vector3.new(0.32, 0.28, 1.1), base, origin * CFrame.new(0, 0.25, -0.35))
		weld(handle, body)
		local barrel = part(model, "Barrel", Vector3.new(0.12, 0.12, 0.55), light, origin * CFrame.new(0, 0.28, -1.05))
		weld(handle, barrel)
		local stock = part(model, "Stock", Vector3.new(0.22, 0.2, 0.45), dark, origin * CFrame.new(0, 0.2, 0.35))
		weld(handle, stock)
		local mag = part(model, "Mag", Vector3.new(0.18, 0.45, 0.28), dark, origin * CFrame.new(0, -0.05, -0.25))
		weld(handle, mag)
		accent(model, handle, CFrame.new(0, 0.42, -0.5), Vector3.new(0.08, 0.12, 0.35), Color3.fromRGB(30, 30, 35))
	elseif weaponType == "Rifle" then
		local body = part(model, "Body", Vector3.new(0.3, 0.26, 1.4), base, origin * CFrame.new(0, 0.28, -0.45))
		weld(handle, body)
		local barrel = part(model, "Barrel", Vector3.new(0.11, 0.11, 0.9), light, origin * CFrame.new(0, 0.3, -1.35))
		weld(handle, barrel)
		local stock = part(model, "Stock", Vector3.new(0.24, 0.22, 0.55), wood, origin * CFrame.new(0, 0.22, 0.45))
		weld(handle, stock)
		local mag = part(model, "Mag", Vector3.new(0.16, 0.5, 0.28), dark, origin * CFrame.new(0, -0.08, -0.2))
		weld(handle, mag)
		local handguard = part(model, "Guard", Vector3.new(0.34, 0.2, 0.55), dark, origin * CFrame.new(0, 0.22, -0.85))
		weld(handle, handguard)
		local sight = part(model, "Sight", Vector3.new(0.08, 0.14, 0.4), Color3.fromRGB(25, 25, 30), origin * CFrame.new(0, 0.45, -0.4))
		weld(handle, sight)
	elseif weaponType == "Shotgun" then
		local body = part(model, "Body", Vector3.new(0.34, 0.3, 1.2), base, origin * CFrame.new(0, 0.26, -0.4))
		weld(handle, body)
		local b1 = part(model, "Barrel1", Vector3.new(0.12, 0.12, 1.0), light, origin * CFrame.new(-0.08, 0.3, -1.15))
		local b2 = part(model, "Barrel2", Vector3.new(0.12, 0.12, 1.0), light, origin * CFrame.new(0.08, 0.3, -1.15))
		weld(handle, b1)
		weld(handle, b2)
		local stock = part(model, "Stock", Vector3.new(0.28, 0.28, 0.65), wood, origin * CFrame.new(0, 0.2, 0.5))
		weld(handle, stock)
		local pump = part(model, "Pump", Vector3.new(0.36, 0.22, 0.35), dark, origin * CFrame.new(0, 0.18, -0.7))
		weld(handle, pump)
	elseif weaponType == "LMG" then
		local body = part(model, "Body", Vector3.new(0.4, 0.32, 1.5), base, origin * CFrame.new(0, 0.3, -0.45))
		weld(handle, body)
		local barrel = part(model, "Barrel", Vector3.new(0.16, 0.16, 1.1), light, origin * CFrame.new(0, 0.34, -1.4))
		weld(handle, barrel)
		local bipod = part(model, "Bipod", Vector3.new(0.5, 0.08, 0.08), dark, origin * CFrame.new(0, 0.05, -1.0))
		weld(handle, bipod)
		local box = part(model, "AmmoBox", Vector3.new(0.45, 0.35, 0.55), Color3.fromRGB(60, 70, 40), origin * CFrame.new(0.35, 0.15, -0.15))
		weld(handle, box)
		local stock = part(model, "Stock", Vector3.new(0.28, 0.24, 0.5), dark, origin * CFrame.new(0, 0.25, 0.5))
		weld(handle, stock)
	elseif weaponType == "Sniper" then
		local body = part(model, "Body", Vector3.new(0.28, 0.24, 1.6), base, origin * CFrame.new(0, 0.28, -0.5))
		weld(handle, body)
		local barrel = part(model, "Barrel", Vector3.new(0.1, 0.1, 1.4), light, origin * CFrame.new(0, 0.3, -1.55))
		weld(handle, barrel)
		local stock = part(model, "Stock", Vector3.new(0.26, 0.28, 0.7), wood, origin * CFrame.new(0, 0.2, 0.55))
		weld(handle, stock)
		local scope = part(model, "Scope", Vector3.new(0.7, 0.16, 0.16), Color3.fromRGB(25, 28, 35), origin * CFrame.new(0, 0.48, -0.35), Enum.PartType.Cylinder)
		scope.CFrame = origin * CFrame.new(0, 0.48, -0.35) * CFrame.Angles(0, math.rad(90), 0)
		weld(handle, scope)
		local lens = part(model, "Lens", Vector3.new(0.05, 0.14, 0.14), Color3.fromRGB(80, 140, 200), origin * CFrame.new(0, 0.48, -0.7), Enum.PartType.Cylinder)
		lens.CFrame = origin * CFrame.new(0, 0.48, -0.7) * CFrame.Angles(0, math.rad(90), 0)
		weld(handle, lens)
	else -- Crossbow / default
		local body = part(model, "Body", Vector3.new(0.22, 0.2, 1.0), wood, origin * CFrame.new(0, 0.25, -0.25))
		weld(handle, body)
		local bowL = part(model, "BowL", Vector3.new(0.1, 0.12, 0.9), dark, origin * CFrame.new(-0.45, 0.3, -0.7) * CFrame.Angles(0, math.rad(25), 0))
		local bowR = part(model, "BowR", Vector3.new(0.1, 0.12, 0.9), dark, origin * CFrame.new(0.45, 0.3, -0.7) * CFrame.Angles(0, math.rad(-25), 0))
		weld(handle, bowL)
		weld(handle, bowR)
		local bolt = part(model, "Bolt", Vector3.new(0.06, 0.06, 1.1), light, origin * CFrame.new(0, 0.32, -0.55))
		weld(handle, bolt)
		local string = part(model, "String", Vector3.new(0.9, 0.03, 0.03), Color3.fromRGB(220, 220, 220), origin * CFrame.new(0, 0.35, -0.35))
		weld(handle, string)
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	local minZ = -0.8
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child ~= handle then
			local relative = handle.CFrame:PointToObjectSpace(child.Position)
			minZ = math.min(minZ, relative.Z - child.Size.Magnitude * 0.28)
		end
	end
	muzzle.Position = Vector3.new(0, 0.3, minZ)
	muzzle.Parent = handle
	model:SetAttribute("WeaponType", weaponType)
	model:SetAttribute("Tier", tier)
	return model
end

-- Alias used by some callers
function WeaponBuilder.Build(opts)
	local wType = typeof(opts) == "table" and opts.WeaponType or opts
	local tier = typeof(opts) == "table" and opts.Tier or 1
	return WeaponBuilder.Create(tostring(wType or "Pistol"), tier)
end

return WeaponBuilder
