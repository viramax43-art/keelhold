--[[
	CharacterRigBuilder — R6 kit-юниты, HP bar, оружие.
]]

local WeaponBuilder = require(script.Parent.WeaponBuilder)

local CharacterRigBuilder = {}

local KITS = {
	{ Uniform = Color3.fromRGB(45, 55, 40), Vest = Color3.fromRGB(35, 40, 30), Helmet = Color3.fromRGB(50, 55, 45) },
	{ Uniform = Color3.fromRGB(50, 50, 55), Vest = Color3.fromRGB(40, 40, 45), Helmet = Color3.fromRGB(55, 55, 60) },
	{ Uniform = Color3.fromRGB(55, 45, 35), Vest = Color3.fromRGB(45, 35, 25), Helmet = Color3.fromRGB(60, 50, 40) },
	{ Uniform = Color3.fromRGB(40, 50, 55), Vest = Color3.fromRGB(30, 40, 45), Helmet = Color3.fromRGB(45, 55, 60) },
}

function CharacterRigBuilder.GetKitVariant(index: number)
	return KITS[((index - 1) % #KITS) + 1]
end

local function part(name, size, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = name == "HumanoidRootPart" or name == "Torso" or string.find(name, "Leg") ~= nil
	p.Anchored = false
	p.Parent = parent
	return p
end

function CharacterRigBuilder.CreateR6Kit(opts)
	local model = Instance.new("Model")
	model.Name = opts.ModelName or "Unit"

	local kit = opts.Kit or CharacterRigBuilder.GetKitVariant(opts.SlotIndex or 1)
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), kit.Uniform, model)
	root.Transparency = 1
	root.CanCollide = false
	model.PrimaryPart = root

	local torso = part("Torso", Vector3.new(2, 2, 1), kit.Vest, model)
	local head = part("Head", Vector3.new(1.2, 1.2, 1.2), kit.Helmet, model)
	local la = part("Left Arm", Vector3.new(1, 2, 1), kit.Uniform, model)
	local ra = part("Right Arm", Vector3.new(1, 2, 1), kit.Uniform, model)
	local ll = part("Left Leg", Vector3.new(1, 2, 1), kit.Uniform, model)
	local rl = part("Right Leg", Vector3.new(1, 2, 1), kit.Uniform, model)

	local function weld(a, b, offset)
		b.CFrame = a.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = b
		w.Parent = a
	end

	weld(root, torso, CFrame.new())
	weld(torso, head, CFrame.new(0, 1.5, 0))
	weld(torso, la, CFrame.new(-1.5, 0, 0))
	weld(torso, ra, CFrame.new(1.5, 0, 0))
	weld(torso, ll, CFrame.new(-0.5, -2, 0))
	weld(torso, rl, CFrame.new(0.5, -2, 0))

	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.MaxHealth = opts.MaxHP or 100
	hum.Health = opts.CurrentHP or hum.MaxHealth
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.Parent = model

	if opts.FacingCFrame then
		model:PivotTo(opts.FacingCFrame)
	elseif opts.Position then
		model:PivotTo(CFrame.new(opts.Position))
	end

	CharacterRigBuilder.AttachWeapon(model, opts.WeaponType or "Rifle")
	CharacterRigBuilder.CreateHealthBar(model, opts.DisplayName or model.Name, hum.Health, hum.MaxHealth)

	if opts.IsBot then
		model:SetAttribute("IsBot", true)
	end
	if opts.SlotIndex then
		model:SetAttribute("SlotIndex", opts.SlotIndex)
	end

	model.Parent = opts.Parent or workspace
	return model
end

function CharacterRigBuilder.AttachWeapon(model: Model, weaponType: string)
	local old = model:FindFirstChild("WeaponVisual")
	if old then
		old:Destroy()
	end
	local weapon = WeaponBuilder.Create(weaponType)
	weapon.Name = "WeaponVisual"
	local handle = weapon.PrimaryPart
	local hand = model:FindFirstChild("Right Arm") or model:FindFirstChild("RightHand") or model.PrimaryPart
	if handle and hand and hand:IsA("BasePart") then
		weapon.Parent = model
		handle.CFrame = hand.CFrame * CFrame.new(0, -0.8, -0.6)
		local w = Instance.new("WeldConstraint")
		w.Part0 = hand
		w.Part1 = handle
		w.Parent = handle
	else
		weapon:Destroy()
	end
end

function CharacterRigBuilder.CreateHealthBar(model: Model, displayName: string, hp: number, maxHp: number)
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	if not head then
		return
	end
	local old = model:FindFirstChild("HealthBar")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.new(0, 140, 0, 40)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = model
	gui.Adornee = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = gui

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, 0, 0.35, 0)
	barBg.Position = UDim2.new(0, 0, 0.55, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	barBg.BorderSizePixel = 0
	barBg.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(math.clamp(hp / math.max(maxHp, 1), 0, 1), 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	bar.BorderSizePixel = 0
	bar.Parent = barBg
end

function CharacterRigBuilder.UpdateHealthBar(model: Model, hp: number, maxHp: number)
	local gui = model:FindFirstChild("HealthBar")
	local bar = gui and gui:FindFirstChild("BarBg") and gui.BarBg:FindFirstChild("Bar")
	if bar then
		bar.Size = UDim2.new(math.clamp(hp / math.max(maxHp, 1), 0, 1), 0, 1, 0)
	end
end

return CharacterRigBuilder
