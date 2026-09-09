--[[
	WeaponBuilder — процедурное оружие + Motor6D-хват к правой руке.
	Handle: +Y = рукоять вверх, -Z = ствол вперёд. Attachment Muzzle на дуле.
]]

local WeaponBuilder = {}

local COLORS = {
	Receiver = Color3.fromRGB(45, 47, 50),
	Metal = Color3.fromRGB(90, 92, 95),
	Black = Color3.fromRGB(20, 21, 22),
	Grip = Color3.fromRGB(28, 30, 32),
	Magazine = Color3.fromRGB(35, 36, 38),
	Accent = Color3.fromRGB(70, 72, 75),
	Wood = Color3.fromRGB(110, 75, 45),
}

-- GripC0: локаль руки → ствол вперёд при поднятой кисти (-Y руки ≈ вперёд)
local GRIP_C0 = {
	Pistol = CFrame.new(0, -0.12, -0.1) * CFrame.Angles(math.rad(-90), math.rad(0), math.rad(0)),
	Revolver = CFrame.new(0, -0.12, -0.1) * CFrame.Angles(math.rad(-90), 0, 0),
	SMG = CFrame.new(0, -0.45, -0.12) * CFrame.Angles(math.rad(-90), 0, 0),
	Rifle = CFrame.new(0, -0.55, -0.15) * CFrame.Angles(math.rad(-90), 0, 0),
	Shotgun = CFrame.new(0, -0.52, -0.14) * CFrame.Angles(math.rad(-90), 0, 0),
	LMG = CFrame.new(0, -0.58, -0.18) * CFrame.Angles(math.rad(-90), 0, 0),
	Sniper = CFrame.new(0, -0.55, -0.16) * CFrame.Angles(math.rad(-90), 0, 0),
	Crossbow = CFrame.new(0, -0.4, -0.12) * CFrame.Angles(math.rad(-90), 0, 0),
}

local RIFLE_PARTS = {
	{ Name = "Receiver", Size = Vector3.new(0.72, 0.48, 1.45), CFrame = CFrame.new(0, 0.32, -0.10), Color = COLORS.Receiver },
	{ Name = "UpperReceiver", Size = Vector3.new(0.55, 0.18, 1.35), CFrame = CFrame.new(0, 0.61, -0.15), Color = COLORS.Black },
	{ Name = "Barrel", Size = Vector3.new(0.13, 0.13, 2.35), CFrame = CFrame.new(0, 0.39, -1.88), Color = COLORS.Metal },
	{ Name = "MuzzleBrake", Size = Vector3.new(0.22, 0.22, 0.34), CFrame = CFrame.new(0, 0.39, -3.20), Color = COLORS.Black },
	{ Name = "Stock", Size = Vector3.new(0.46, 0.36, 0.85), CFrame = CFrame.new(0, 0.37, 0.98), Color = COLORS.Black },
	{
		Name = "PistolGrip",
		Size = Vector3.new(0.27, 0.82, 0.28),
		CFrame = CFrame.new(0, -0.25, 0.22) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = COLORS.Grip,
		Material = Enum.Material.SmoothPlastic,
	},
	{
		Name = "Magazine",
		Size = Vector3.new(0.36, 0.78, 0.42),
		CFrame = CFrame.new(0, -0.40, -0.12) * CFrame.Angles(math.rad(-10), 0, 0),
		Color = COLORS.Magazine,
	},
	{
		Name = "Handguard",
		Size = Vector3.new(0.45, 0.36, 1.20),
		CFrame = CFrame.new(0, 0.30, -1.25),
		Color = COLORS.Black,
		Material = Enum.Material.SmoothPlastic,
	},
	{ Name = "TopRail", Size = Vector3.new(0.24, 0.08, 0.95), CFrame = CFrame.new(0, 0.74, -0.85), Color = COLORS.Accent },
	{ Name = "RearSight", Size = Vector3.new(0.16, 0.18, 0.16), CFrame = CFrame.new(0, 0.84, 0.05), Color = COLORS.Black },
	{ Name = "FrontSight", Size = Vector3.new(0.12, 0.20, 0.12), CFrame = CFrame.new(0, 0.81, -1.85), Color = COLORS.Black },
	{ Name = "TriggerGuard", Size = Vector3.new(0.26, 0.08, 0.42), CFrame = CFrame.new(0, -0.05, 0.02), Color = COLORS.Black },
}

local LMG_PARTS = {
	{ Name = "Receiver", Size = Vector3.new(0.85, 0.62, 1.70), CFrame = CFrame.new(0, 0.34, -0.05), Color = COLORS.Receiver },
	{ Name = "Barrel", Size = Vector3.new(0.17, 0.17, 2.65), CFrame = CFrame.new(0, 0.40, -2.05), Color = COLORS.Metal },
	{ Name = "MuzzleBrake", Size = Vector3.new(0.28, 0.28, 0.42), CFrame = CFrame.new(0, 0.40, -3.58), Color = COLORS.Black },
	{ Name = "Stock", Size = Vector3.new(0.56, 0.45, 1.00), CFrame = CFrame.new(0, 0.38, 1.13), Color = COLORS.Black },
	{
		Name = "PistolGrip",
		Size = Vector3.new(0.31, 0.90, 0.34),
		CFrame = CFrame.new(0, -0.28, 0.25) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = COLORS.Grip,
		Material = Enum.Material.SmoothPlastic,
	},
	{ Name = "AmmoBox", Size = Vector3.new(0.56, 0.82, 0.62), CFrame = CFrame.new(0, -0.23, -0.34), Color = COLORS.Magazine },
	{
		Name = "Handguard",
		Size = Vector3.new(0.58, 0.44, 1.45),
		CFrame = CFrame.new(0, 0.30, -1.48),
		Color = COLORS.Black,
		Material = Enum.Material.SmoothPlastic,
	},
	{ Name = "TopRail", Size = Vector3.new(0.27, 0.09, 1.10), CFrame = CFrame.new(0, 0.70, -0.70), Color = COLORS.Accent },
	{ Name = "FrontSight", Size = Vector3.new(0.15, 0.22, 0.15), CFrame = CFrame.new(0, 0.82, -2.10), Color = COLORS.Black },
	{ Name = "BipodMount", Size = Vector3.new(0.34, 0.10, 0.30), CFrame = CFrame.new(0, 0.02, -1.55), Color = COLORS.Metal },
}

local MUZZLE_CF = {
	Rifle = CFrame.new(0, 0.39, -3.38),
	LMG = CFrame.new(0, 0.40, -3.80),
	SMG = CFrame.new(0, 0.28, -1.35),
	Sniper = CFrame.new(0, 0.3, -2.3),
	Shotgun = CFrame.new(0, 0.3, -1.7),
	Pistol = CFrame.new(0, 0.3, -0.95),
	Revolver = CFrame.new(0, 0.3, -1.15),
	Crossbow = CFrame.new(0, 0.32, -1.2),
}

local SUPPORT_CF = {
	Rifle = CFrame.new(0, 0.08, -1.05),
	LMG = CFrame.new(0, 0.08, -1.30),
}

local function createPart(parent, data, tierTint: Color3?)
	local part = Instance.new("Part")
	part.Name = data.Name
	part.Size = data.Size
	part.CFrame = data.CFrame
	local col = data.Color
	if tierTint and data.Name ~= "PistolGrip" then
		col = col:Lerp(tierTint, 0.12)
	end
	part.Color = col
	part.Material = data.Material or Enum.Material.Metal
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function weldTo(root, part)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "WeaponWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = root
end

local function simplePart(model, name, size, color, cf, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Metal
	p.CanCollide = false
	p.Massless = true
	p.CastShadow = true
	p.Anchored = false
	p.CanTouch = false
	p.CanQuery = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p.Parent = model
	return p
end

local function buildDetailed(model, handle, parts, muzzleCF, supportCF, tierTint)
	for _, data in ipairs(parts) do
		local p = createPart(model, data, tierTint)
		weldTo(handle, p)
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = muzzleCF
	muzzle.Parent = handle
	if supportCF then
		local support = Instance.new("Attachment")
		support.Name = "SupportGrip"
		support.CFrame = supportCF
		support.Parent = handle
	end
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.CFrame = CFrame.new(0, 0.15, 0)
	grip.Parent = handle
end

local function buildLegacy(model, handle, weaponType, base, dark, light, wood)
	local origin = CFrame.new()
	if weaponType == "Pistol" or weaponType == "Revolver" then
		local body = simplePart(model, "Body", Vector3.new(0.35, 0.32, 0.7), base, origin * CFrame.new(0, 0.22, -0.15))
		weldTo(handle, body)
		local barrelLen = weaponType == "Revolver" and 0.85 or 0.55
		local slide = simplePart(
			model,
			"Slide",
			Vector3.new(0.38, 0.18, if weaponType == "Revolver" then 0.55 else 0.78),
			dark,
			origin * CFrame.new(0, 0.4, -0.18)
		)
		weldTo(handle, slide)
		local barrel = simplePart(model, "Barrel", Vector3.new(barrelLen, 0.14, 0.14), light, origin, Enum.PartType.Cylinder)
		barrel.CFrame = origin * CFrame.new(0, 0.3, -0.35 - barrelLen / 2) * CFrame.Angles(0, math.rad(90), 0)
		weldTo(handle, barrel)
		if weaponType == "Revolver" then
			local cyl = simplePart(model, "Cylinder", Vector3.new(0.38, 0.28, 0.38), dark, origin, Enum.PartType.Cylinder)
			cyl.CFrame = origin * CFrame.new(0, 0.28, -0.05) * CFrame.Angles(0, math.rad(90), 0)
			weldTo(handle, cyl)
		end
	elseif weaponType == "SMG" then
		local body = simplePart(model, "Body", Vector3.new(0.32, 0.28, 1.1), base, origin * CFrame.new(0, 0.25, -0.35))
		weldTo(handle, body)
		local barrel = simplePart(model, "Barrel", Vector3.new(0.12, 0.12, 0.55), light, origin * CFrame.new(0, 0.28, -1.05))
		weldTo(handle, barrel)
		local stock = simplePart(model, "Stock", Vector3.new(0.22, 0.2, 0.45), dark, origin * CFrame.new(0, 0.2, 0.35))
		weldTo(handle, stock)
		local mag = simplePart(model, "Mag", Vector3.new(0.18, 0.45, 0.28), dark, origin * CFrame.new(0, -0.05, -0.25))
		weldTo(handle, mag)
	elseif weaponType == "Shotgun" then
		local body = simplePart(model, "Body", Vector3.new(0.34, 0.3, 1.2), base, origin * CFrame.new(0, 0.26, -0.4))
		weldTo(handle, body)
		local b1 = simplePart(model, "Barrel1", Vector3.new(0.12, 0.12, 1.0), light, origin * CFrame.new(-0.08, 0.3, -1.15))
		local b2 = simplePart(model, "Barrel2", Vector3.new(0.12, 0.12, 1.0), light, origin * CFrame.new(0.08, 0.3, -1.15))
		weldTo(handle, b1)
		weldTo(handle, b2)
		local stock = simplePart(model, "Stock", Vector3.new(0.28, 0.28, 0.65), wood, origin * CFrame.new(0, 0.2, 0.5))
		weldTo(handle, stock)
	elseif weaponType == "Sniper" then
		local body = simplePart(model, "Body", Vector3.new(0.28, 0.24, 1.6), base, origin * CFrame.new(0, 0.28, -0.5))
		weldTo(handle, body)
		local barrel = simplePart(model, "Barrel", Vector3.new(0.1, 0.1, 1.4), light, origin * CFrame.new(0, 0.3, -1.55))
		weldTo(handle, barrel)
		local stock = simplePart(model, "Stock", Vector3.new(0.26, 0.28, 0.7), wood, origin * CFrame.new(0, 0.2, 0.55))
		weldTo(handle, stock)
		local scope = simplePart(model, "Scope", Vector3.new(0.7, 0.16, 0.16), Color3.fromRGB(25, 28, 35), origin, Enum.PartType.Cylinder)
		scope.CFrame = origin * CFrame.new(0, 0.48, -0.35) * CFrame.Angles(0, math.rad(90), 0)
		weldTo(handle, scope)
	else
		local body = simplePart(model, "Body", Vector3.new(0.22, 0.2, 1.0), wood, origin * CFrame.new(0, 0.25, -0.25))
		weldTo(handle, body)
		local bowL = simplePart(model, "BowL", Vector3.new(0.1, 0.12, 0.9), dark, origin * CFrame.new(-0.45, 0.3, -0.7) * CFrame.Angles(0, math.rad(25), 0))
		local bowR = simplePart(model, "BowR", Vector3.new(0.1, 0.12, 0.9), dark, origin * CFrame.new(0.45, 0.3, -0.7) * CFrame.Angles(0, math.rad(-25), 0))
		weldTo(handle, bowL)
		weldTo(handle, bowR)
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = MUZZLE_CF[weaponType] or CFrame.new(0, 0.3, -1.0)
	muzzle.Parent = handle
end

function WeaponBuilder.GetGripC0(weaponType: string?, handName: string?): CFrame
	local c0 = GRIP_C0[weaponType or "Rifle"] or GRIP_C0.Rifle
	if handName == "Right Arm" then
		-- R6: чуть ниже по кости
		return CFrame.new(0, -1.0, -0.12) * CFrame.Angles(math.rad(-90), 0, 0)
	end
	return c0
end

function WeaponBuilder.Create(weaponType: string, tier: number?): Model
	weaponType = weaponType or "Rifle"
	if weaponType == "AssaultRifle" then
		weaponType = "Rifle"
	elseif weaponType == "MachineGun" then
		weaponType = "LMG"
	end
	tier = math.clamp(tonumber(tier) or 1, 1, 10)

	local tierTints = {
		Color3.fromRGB(115, 120, 126),
		Color3.fromRGB(72, 116, 82),
		Color3.fromRGB(61, 88, 124),
		Color3.fromRGB(100, 65, 120),
		Color3.fromRGB(126, 101, 51),
		Color3.fromRGB(140, 60, 60),
		Color3.fromRGB(140, 50, 90),
		Color3.fromRGB(80, 130, 140),
		Color3.fromRGB(70, 140, 85),
		Color3.fromRGB(150, 150, 150),
	}
	local typeColor = ({
		Pistol = Color3.fromRGB(55, 58, 65),
		Revolver = Color3.fromRGB(95, 72, 48),
		SMG = Color3.fromRGB(48, 52, 58),
		Rifle = COLORS.Receiver,
		Shotgun = Color3.fromRGB(78, 58, 40),
		LMG = COLORS.Receiver,
		Sniper = Color3.fromRGB(32, 38, 52),
		Crossbow = Color3.fromRGB(88, 58, 36),
	})[weaponType] or COLORS.Receiver
	local base = typeColor:Lerp(tierTints[tier], 0.16)
	local dark = base:Lerp(Color3.new(0, 0, 0), 0.35)
	local light = base:Lerp(Color3.new(1, 1, 1), 0.2)

	local model = Instance.new("Model")
	model.Name = "WeaponVisual"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.28, 0.82, 0.30)
	handle.CFrame = CFrame.identity
	handle.Color = COLORS.Grip
	handle.Material = Enum.Material.SmoothPlastic
	handle.Anchored = false
	handle.Massless = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.CastShadow = true
	handle.Parent = model
	model.PrimaryPart = handle

	if weaponType == "Rifle" then
		buildDetailed(model, handle, RIFLE_PARTS, MUZZLE_CF.Rifle, SUPPORT_CF.Rifle, tierTints[tier])
	elseif weaponType == "LMG" then
		buildDetailed(model, handle, LMG_PARTS, MUZZLE_CF.LMG, SUPPORT_CF.LMG, tierTints[tier])
	else
		-- компактный Handle для пистолетов
		handle.Size = Vector3.new(0.28, 0.55, 0.28)
		handle.Color = dark
		buildLegacy(model, handle, weaponType, base, dark, light, COLORS.Wood)
	end

	model:SetAttribute("WeaponType", weaponType)
	model:SetAttribute("WeaponId", weaponType)
	model:SetAttribute("Tier", tier)
	return model
end

function WeaponBuilder.Equip(character: Model, weaponType: string, tier: number?): (Model?, Motor6D?)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		warn("[WeaponBuilder] Missing right hand on", character:GetFullName())
		return nil, nil
	end

	local oldWeapon = character:FindFirstChild("WeaponVisual") or character:FindFirstChild("BotWeapon")
	if oldWeapon then
		oldWeapon:Destroy()
	end
	local oldGrip = hand:FindFirstChild("BotWeaponGrip")
	if oldGrip then
		oldGrip:Destroy()
	end

	local weapon = WeaponBuilder.Create(weaponType, tier)
	weapon.Name = "WeaponVisual"
	weapon.Parent = character

	local handle = weapon.PrimaryPart
	if not handle then
		weapon:Destroy()
		return nil, nil
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "BotWeaponGrip"
	motor.Part0 = hand
	motor.Part1 = handle
	motor.C0 = WeaponBuilder.GetGripC0(weapon:GetAttribute("WeaponType"), hand.Name)
	motor.C1 = CFrame.identity
	motor.Parent = hand

	character:SetAttribute("WeaponType", weapon:GetAttribute("WeaponType"))
	character:SetAttribute("WeaponTier", tier or 1)
	return weapon, motor
end

function WeaponBuilder.Build(opts)
	local wType = typeof(opts) == "table" and opts.WeaponType or opts
	local tier = typeof(opts) == "table" and opts.Tier or 1
	return WeaponBuilder.Create(tostring(wType or "Pistol"), tier)
end

return WeaponBuilder
