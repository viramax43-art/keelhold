--[[
	WeaponBuilder — простое визуальное оружие для юнитов.
]]

local WeaponBuilder = {}

local COLORS = {
	Pistol = Color3.fromRGB(60, 60, 70),
	Revolver = Color3.fromRGB(90, 70, 50),
	SMG = Color3.fromRGB(50, 55, 60),
	Rifle = Color3.fromRGB(45, 50, 45),
	Shotgun = Color3.fromRGB(70, 55, 40),
	LMG = Color3.fromRGB(40, 45, 50),
	Sniper = Color3.fromRGB(35, 40, 55),
	Crossbow = Color3.fromRGB(80, 55, 35),
}

function WeaponBuilder.Create(weaponType: string): Model
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. (weaponType or "Pistol")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 1.4)
	handle.Color = COLORS[weaponType] or COLORS.Pistol
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = model
	model.PrimaryPart = handle

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.15, 0.15, 0.8)
	barrel.Color = handle.Color
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide = false
	barrel.Massless = true
	barrel.CFrame = handle.CFrame * CFrame.new(0, 0.05, -0.9)
	barrel.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = barrel
	weld.Parent = handle

	return model
end

return WeaponBuilder
