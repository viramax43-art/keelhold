--[[
	CharacterRigBuilder
	Creates humanoid R15 NPCs with distinct ally/enemy outfits.
	Stationary defenders keep only HumanoidRootPart anchored; standard Motor6D
	joints stay intact. Fire poses use shoulder C0, never detach body parts.
]]

local Players = game:GetService("Players")

local WeaponBuilder = require(script.Parent.WeaponBuilder)

local CharacterRigBuilder = {}
local r15Template: Model? = nil

local ALLY_STYLES = {
	{
		Skin = Color3.fromRGB(196, 151, 111),
		Uniform = Color3.fromRGB(42, 68, 92),
		Vest = Color3.fromRGB(29, 42, 52),
		Helmet = Color3.fromRGB(55, 75, 85),
		Accent = Color3.fromRGB(70, 155, 220),
	},
	{
		Skin = Color3.fromRGB(151, 105, 79),
		Uniform = Color3.fromRGB(51, 76, 61),
		Vest = Color3.fromRGB(32, 48, 38),
		Helmet = Color3.fromRGB(65, 82, 59),
		Accent = Color3.fromRGB(80, 190, 140),
	},
	{
		Skin = Color3.fromRGB(226, 184, 145),
		Uniform = Color3.fromRGB(58, 62, 78),
		Vest = Color3.fromRGB(34, 36, 48),
		Helmet = Color3.fromRGB(66, 68, 82),
		Accent = Color3.fromRGB(125, 150, 240),
	},
	{
		Skin = Color3.fromRGB(119, 82, 64),
		Uniform = Color3.fromRGB(77, 69, 48),
		Vest = Color3.fromRGB(48, 43, 30),
		Helmet = Color3.fromRGB(81, 75, 52),
		Accent = Color3.fromRGB(200, 170, 75),
	},
}

local ENEMY_STYLES = {
	{
		Skin = Color3.fromRGB(174, 126, 96),
		Uniform = Color3.fromRGB(83, 38, 40),
		Vest = Color3.fromRGB(46, 25, 27),
		Helmet = Color3.fromRGB(68, 34, 35),
		Accent = Color3.fromRGB(225, 72, 72),
	},
	{
		Skin = Color3.fromRGB(208, 164, 126),
		Uniform = Color3.fromRGB(68, 48, 45),
		Vest = Color3.fromRGB(39, 31, 30),
		Helmet = Color3.fromRGB(76, 48, 43),
		Accent = Color3.fromRGB(225, 106, 55),
	},
	{
		Skin = Color3.fromRGB(126, 87, 69),
		Uniform = Color3.fromRGB(62, 38, 55),
		Vest = Color3.fromRGB(37, 25, 34),
		Helmet = Color3.fromRGB(70, 42, 57),
		Accent = Color3.fromRGB(205, 65, 125),
	},
	{
		Skin = Color3.fromRGB(220, 179, 141),
		Uniform = Color3.fromRGB(73, 57, 44),
		Vest = Color3.fromRGB(42, 34, 28),
		Helmet = Color3.fromRGB(83, 57, 43),
		Accent = Color3.fromRGB(210, 85, 45),
	},
}

function CharacterRigBuilder.GetKitVariant(index: number, team: string?)
	local styles = if team == "Enemy" then ENEMY_STYLES else ALLY_STYLES
	return styles[((index - 1) % #styles) + 1]
end

local function getRoot(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function newPart(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
	p.Parent = parent
	return p
end

local function weldTo(part0: BasePart, part1: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
	return weld
end

local function addTacticalOutfit(model: Model, style, team: string)
	local old = model:FindFirstChild("TacticalOutfit")
	if old then
		old:Destroy()
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	local head = model:FindFirstChild("Head")
	if not torso or not torso:IsA("BasePart") then
		return
	end

	local outfit = Instance.new("Folder")
	outfit.Name = "TacticalOutfit"
	outfit.Parent = model

	-- Rounded vest shell: thin enough to preserve the R15 silhouette.
	local vest = newPart(
		"TacticalVest",
		Vector3.new(torso.Size.X + 0.22, torso.Size.Y * 0.8, torso.Size.Z + 0.24),
		style.Vest,
		Enum.Material.Fabric,
		outfit
	)
	vest.CFrame = torso.CFrame * CFrame.new(0, -0.05, 0.03)
	weldTo(torso, vest)

	local vestMesh = Instance.new("SpecialMesh")
	vestMesh.MeshType = Enum.MeshType.Brick
	vestMesh.Scale = Vector3.new(1, 1, 0.92)
	vestMesh.Parent = vest

	local chestPlate = newPart(
		"ChestPlate",
		Vector3.new(math.max(0.75, torso.Size.X * 0.62), math.max(0.55, torso.Size.Y * 0.43), 0.12),
		style.Uniform,
		Enum.Material.SmoothPlastic,
		outfit
	)
	chestPlate.CFrame = torso.CFrame * CFrame.new(0, 0.02, -(torso.Size.Z * 0.5 + 0.1))
	weldTo(torso, chestPlate)

	local teamStripe = newPart(
		"TeamStripe",
		Vector3.new(chestPlate.Size.X * 0.72, 0.09, 0.03),
		style.Accent,
		Enum.Material.Neon,
		outfit
	)
	teamStripe.CFrame = chestPlate.CFrame * CFrame.new(0, 0.05, -0.08)
	weldTo(chestPlate, teamStripe)

	if head and head:IsA("BasePart") then
		local helmet = newPart(
			"CombatHelmet",
			Vector3.new(head.Size.X * 1.08, head.Size.Y * 0.62, head.Size.Z * 1.08),
			style.Helmet,
			Enum.Material.SmoothPlastic,
			outfit
		)
		helmet.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.3, 0)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 0.72, 1)
		mesh.Parent = helmet
		weldTo(head, helmet)

		local visor = newPart(
			"Visor",
			Vector3.new(head.Size.X * 0.78, 0.17, 0.09),
			if team == "Enemy" then Color3.fromRGB(145, 35, 35) else Color3.fromRGB(35, 95, 135),
			Enum.Material.Glass,
			outfit
		)
		visor.Transparency = 0.2
		visor.CFrame = head.CFrame * CFrame.new(0, 0.13, -(head.Size.Z * 0.5 + 0.07))
		weldTo(head, visor)
	end
end

function CharacterRigBuilder.AddTeamOutfit(model: Model, team: string?, index: number?)
	local role = if team == "Enemy" then "Enemy" else "Ally"
	local style = CharacterRigBuilder.GetKitVariant(index or 1, role)
	model:SetAttribute("TeamRole", role)
	addTacticalOutfit(model, style, role)
end

local function applyBodyStyle(model: Model, style)
	local skinNames = {
		Head = true,
		LeftHand = true,
		RightHand = true,
	}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			child.CanCollide = false
			child.CanTouch = false
			child.Massless = child.Name ~= "HumanoidRootPart"
			if skinNames[child.Name] then
				child.Color = style.Skin
			elseif child.Name ~= "HumanoidRootPart" then
				child.Color = style.Uniform
				child.Material = Enum.Material.Fabric
			end
		end
	end
end

local function createR15(style): Model?
	if r15Template then
		return r15Template:Clone()
	end
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = style.Skin
	description.LeftArmColor = style.Uniform
	description.RightArmColor = style.Uniform
	description.LeftLegColor = style.Uniform
	description.RightLegColor = style.Uniform
	description.TorsoColor = style.Uniform
	description.HeightScale = 1
	description.WidthScale = 0.92
	description.DepthScale = 0.95
	description.HeadScale = 0.95
	description.BodyTypeScale = 0.45
	description.ProportionScale = 0.55

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if ok and model then
		model.Archivable = true
		r15Template = model
		return model:Clone()
	end
	return nil
end

-- Minimal fallback only if Roblox cannot create the standard R15 model.
local function createFallback(style): Model
	local model = Instance.new("Model")
	local root = newPart(
		"HumanoidRootPart",
		Vector3.new(2, 2, 1),
		style.Uniform,
		Enum.Material.SmoothPlastic,
		model
	)
	root.Transparency = 1
	root.Anchored = true
	model.PrimaryPart = root

	local torso = newPart("Torso", Vector3.new(2, 2, 1), style.Uniform, Enum.Material.Fabric, model)
	local head = newPart("Head", Vector3.new(1.2, 1.2, 1.2), style.Skin, Enum.Material.SmoothPlastic, model)
	local leftArm = newPart("Left Arm", Vector3.new(0.85, 2, 0.85), style.Uniform, Enum.Material.Fabric, model)
	local rightArm = newPart("Right Arm", Vector3.new(0.85, 2, 0.85), style.Uniform, Enum.Material.Fabric, model)
	local leftLeg = newPart("Left Leg", Vector3.new(0.9, 2, 0.9), style.Uniform, Enum.Material.Fabric, model)
	local rightLeg = newPart("Right Leg", Vector3.new(0.9, 2, 0.9), style.Uniform, Enum.Material.Fabric, model)

	local function joint(name, part0, part1, c0)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = c0
		m.C1 = CFrame.new()
		m.Parent = part0
		return m
	end

	joint("RootJoint", root, torso, CFrame.new())
	joint("Neck", torso, head, CFrame.new(0, 1.05, 0))
	joint("Left Shoulder", torso, leftArm, CFrame.new(-1.45, 0.35, 0))
	joint("Right Shoulder", torso, rightArm, CFrame.new(1.45, 0.35, 0))
	joint("Left Hip", torso, leftLeg, CFrame.new(-0.5, -1.05, 0))
	joint("Right Hip", torso, rightLeg, CFrame.new(0.5, -1.05, 0))

	root.CFrame = CFrame.new()
	torso.CFrame = root.CFrame
	head.CFrame = torso.CFrame * CFrame.new(0, 1.55, 0)
	leftArm.CFrame = torso.CFrame * CFrame.new(-1.45, 0, 0)
	rightArm.CFrame = torso.CFrame * CFrame.new(1.45, 0, 0)
	leftLeg.CFrame = torso.CFrame * CFrame.new(-0.5, -2, 0)
	rightLeg.CFrame = torso.CFrame * CFrame.new(0.5, -2, 0)

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	return model
end

function CharacterRigBuilder.CreateNPC(opts)
	local team = opts.Team == "Enemy" and "Enemy" or "Ally"
	local style = opts.Style or CharacterRigBuilder.GetKitVariant(opts.SlotIndex or 1, team)
	local model = createR15(style) or createFallback(style)
	model.Name = opts.ModelName or (team == "Enemy" and "Enemy" or "Defender")
	model:SetAttribute("TeamRole", team)
	model:SetAttribute("IsBot", opts.IsBot == true)
	if opts.SlotIndex then
		model:SetAttribute("SlotIndex", opts.SlotIndex)
	end

	local root = getRoot(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = root
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = opts.MaxHP or 100
	humanoid.Health = opts.CurrentHP or humanoid.MaxHealth
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	-- Убираем Animator, иначе поза руки при стрельбе сбрасывается
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		animator:Destroy()
	end

	applyBodyStyle(model, style)
	addTacticalOutfit(model, style, team)

	if opts.FacingCFrame then
		model:PivotTo(opts.FacingCFrame)
	elseif opts.Position then
		model:PivotTo(CFrame.new(opts.Position))
	end

	model.Parent = opts.Parent or workspace
	root.Anchored = true
	CharacterRigBuilder.AttachWeapon(model, opts.WeaponType or "Rifle", opts.WeaponTier)
	CharacterRigBuilder.CreateHealthBar(
		model,
		opts.DisplayName or model.Name,
		humanoid.Health,
		humanoid.MaxHealth,
		team
	)

	if opts.IsBot then
		CharacterRigBuilder.LockStanding(model, opts.FacingCFrame)
	end
	return model
end

-- Compatibility for existing callers.
function CharacterRigBuilder.CreateR6Kit(opts)
	return CharacterRigBuilder.CreateNPC(opts)
end

function CharacterRigBuilder.LockStanding(model: Model, facingCF: CFrame?)
	local root = getRoot(model)
	if not root then
		return
	end
	if facingCF and not model:GetAttribute("PoseLocked") then
		model:PivotTo(facingCF)
	end
	root.Anchored = true
	root.CanCollide = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= root then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		humanoid.PlatformStand = false
	end
	model:SetAttribute("PoseLocked", true)
end

function CharacterRigBuilder.FaceInPlace(model: Model, facingCF: CFrame)
	local root = getRoot(model)
	if not root then
		return
	end
	local rotation = facingCF - facingCF.Position
	root.CFrame = CFrame.new(root.Position) * rotation
end

local function findGripPart(model: Model): BasePart?
	local hand = model:FindFirstChild("RightHand")
		or model:FindFirstChild("Right Arm")
		or model:FindFirstChild("RightLowerArm")
	if hand and hand:IsA("BasePart") then
		return hand
	end
	return getRoot(model)
end

function CharacterRigBuilder.AttachWeapon(model: Model, weaponType: string, tier: number?)
	local old = model:FindFirstChild("WeaponVisual")
	if old then
		old:Destroy()
	end

	local hand = findGripPart(model)
	if not hand then
		return
	end
	local weapon = WeaponBuilder.Create(weaponType, tier)
	weapon.Name = "WeaponVisual"
	local handle = weapon.PrimaryPart
	if not handle then
		weapon:Destroy()
		return
	end

	weapon.Parent = model
	for _, descendant in ipairs(weapon:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	-- WeaponBuilder barrels point along local -Z. The grip maps that axis to
	-- the arm's -Y axis; raising the shoulder then maps both to world forward.
	local gripOffset
	if hand.Name == "Right Arm" then
		gripOffset = CFrame.new(0, -0.72, -0.28) * CFrame.Angles(math.rad(-90), 0, 0)
	else
		gripOffset = CFrame.new(0, -0.12, -0.3) * CFrame.Angles(math.rad(-90), 0, 0)
	end
	handle.CFrame = hand.CFrame * gripOffset
	weldTo(hand, handle)
	model:SetAttribute("WeaponType", weaponType)
	model:SetAttribute("WeaponTier", tier or 1)
end

local function findShoulder(model: Model): Motor6D?
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if not torso then
		return nil
	end
	local shoulder = torso:FindFirstChild("RightShoulder") or torso:FindFirstChild("Right Shoulder")
	if shoulder and shoulder:IsA("Motor6D") then
		return shoulder
	end
	for _, descendant in ipairs(torso:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part1 then
			local name = descendant.Part1.Name
			if name == "RightUpperArm" or name == "Right Arm" then
				return descendant
			end
		end
	end
	return nil
end

function CharacterRigBuilder.PlayFireAnimation(model: Model, aimPos: Vector3?)
	if not model or not model.Parent then
		return
	end
	local root = getRoot(model)
	local shoulder = findShoulder(model)
	if not root or not shoulder then
		return
	end

	-- Animator перезаписывает Transform каждый кадр — у NPC отключаем
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			animator:Destroy()
		end
	end

	local baseC0 = shoulder:GetAttribute("FireBaseC0")
	if typeof(baseC0) ~= "CFrame" then
		baseC0 = shoulder.C0
		shoulder:SetAttribute("FireBaseC0", baseC0)
	end

	local aim = if typeof(aimPos) == "Vector3"
		then aimPos
		else (root.CFrame * CFrame.new(0, 1.5, -30)).Position
	local shoulderPosition = (root.CFrame * CFrame.new(1.05, 1.25, 0)).Position
	local toAim = aim - shoulderPosition
	if toAim.Magnitude < 0.05 then
		toAim = -root.CFrame.LookVector
	end
	local localDirection = root.CFrame:VectorToObjectSpace(toAim.Unit)
	local pitch = math.atan2(localDirection.Y, math.max(0.01, -localDirection.Z))
	local raise = math.rad(88) + pitch

	local token = (model:GetAttribute("FireAnimToken") or 0) + 1
	model:SetAttribute("FireAnimToken", token)
	local raiseCF = CFrame.Angles(raise, 0, math.rad(4))
	shoulder.C0 = baseC0 * raiseCF
	pcall(function()
		shoulder.Transform = raiseCF
	end)

	task.delay(0.32, function()
		if model.Parent and model:GetAttribute("FireAnimToken") == token and shoulder.Parent then
			shoulder.C0 = baseC0
			pcall(function()
				shoulder.Transform = CFrame.new()
			end)
		end
	end)
end

function CharacterRigBuilder.CreateHealthBar(
	model: Model,
	displayName: string,
	hp: number,
	maxHp: number,
	team: string?
)
	local adornee = model:FindFirstChild("Head") or model.PrimaryPart
	if not adornee or not adornee:IsA("BasePart") then
		return
	end
	local old = model:FindFirstChild("HealthBar")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.new(0, 72, 0, 16)
	gui.StudsOffset = Vector3.new(0, 2.15, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.Adornee = adornee
	gui.Parent = model

	local isEnemy = team == "Enemy"
	local accent = if isEnemy then Color3.fromRGB(230, 60, 70) else Color3.fromRGB(0, 170, 255)

	local shortName = displayName
	if #shortName > 14 then
		shortName = string.sub(shortName, 1, 12) .. "…"
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = shortName
	nameLabel.TextColor3 = if isEnemy then Color3.fromRGB(255, 150, 140) else Color3.fromRGB(200, 230, 255)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = gui
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.new(0, 0, 0)
	nameStroke.Thickness = 1
	nameStroke.Transparency = 0.5
	nameStroke.Parent = nameLabel

	local background = Instance.new("Frame")
	background.Name = "BarBg"
	background.Size = UDim2.new(1, 0, 0.28, 0)
	background.Position = UDim2.new(0, 0, 0.62, 0)
	background.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	background.BorderSizePixel = 0
	background.Parent = gui
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 1)
	bgCorner.Parent = background

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(math.clamp(hp / math.max(maxHp, 1), 0, 1), 0, 1, 0)
	bar.BackgroundColor3 = accent
	bar.BorderSizePixel = 0
	bar.Parent = background
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 1)
	barCorner.Parent = bar
end

function CharacterRigBuilder.UpdateHealthBar(model: Model, hp: number, maxHp: number)
	local gui = model:FindFirstChild("HealthBar")
	local background = gui and gui:FindFirstChild("BarBg")
	local bar = background and background:FindFirstChild("Bar")
	if bar and bar:IsA("Frame") then
		bar.Size = UDim2.new(math.clamp(hp / math.max(maxHp, 1), 0, 1), 0, 1, 0)
	end
end

return CharacterRigBuilder
