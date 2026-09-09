--[[
	BotShootFX — дульная вспышка + трассер из Attachment Muzzle (клиент).
]]

local Debris = game:GetService("Debris")

local BotShootFX = {}

local MAX_ACTIVE_TRACERS = 100
local activeTracers = 0
local flashTokens = {}

local COLORS = {
	Rifle = Color3.fromRGB(255, 214, 110),
	AssaultRifle = Color3.fromRGB(255, 214, 110),
	LMG = Color3.fromRGB(255, 170, 55),
	MachineGun = Color3.fromRGB(255, 170, 55),
	SMG = Color3.fromRGB(255, 200, 90),
	Pistol = Color3.fromRGB(255, 230, 140),
	Revolver = Color3.fromRGB(255, 190, 100),
	Shotgun = Color3.fromRGB(255, 160, 70),
	Sniper = Color3.fromRGB(200, 230, 255),
	Crossbow = Color3.fromRGB(220, 200, 160),
}

local function getColor(weaponId)
	return COLORS[weaponId] or COLORS.Rifle
end

local function getCamera()
	return workspace.CurrentCamera
end

local function playMuzzleFlash(muzzle, weaponId)
	if not muzzle or not muzzle.Parent then
		return
	end

	local color = getColor(weaponId)
	local light = muzzle:FindFirstChild("BotMuzzleLight")
	if not light then
		light = Instance.new("PointLight")
		light.Name = "BotMuzzleLight"
		light.Color = color
		light.Range = 8
		light.Brightness = 0
		light.Shadows = false
		light.Enabled = false
		light.Parent = muzzle
	end

	local token = (flashTokens[muzzle] or 0) + 1
	flashTokens[muzzle] = token

	light.Color = color
	light.Brightness = 5
	light.Enabled = true

	local camera = getCamera()
	if camera then
		local flash = Instance.new("Part")
		flash.Name = "BotMuzzleFlash"
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(0.30, 0.30, 0.55)
		flash.Material = Enum.Material.Neon
		flash.Color = color
		flash.Transparency = 0.05
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanTouch = false
		flash.CanQuery = false
		flash.CFrame = muzzle.WorldCFrame * CFrame.new(0, 0, -0.22)
		flash.Parent = camera
		Debris:AddItem(flash, 0.035)
	end

	task.delay(0.045, function()
		if muzzle.Parent and flashTokens[muzzle] == token and light.Parent then
			light.Brightness = 0
			light.Enabled = false
		end
	end)
end

local function createTracer(startPosition, endPosition, weaponId)
	if typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return
	end

	local offset = endPosition - startPosition
	local length = offset.Magnitude
	if length < 0.05 or activeTracers >= MAX_ACTIVE_TRACERS then
		return
	end

	local camera = getCamera()
	if not camera then
		return
	end

	activeTracers += 1

	local tracer = Instance.new("Part")
	tracer.Name = "BotTracer"
	tracer.Size = Vector3.new(0.045, 0.045, length)
	tracer.Material = Enum.Material.Neon
	tracer.Color = getColor(weaponId)
	tracer.Transparency = 0.12
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanTouch = false
	tracer.CanQuery = false
	tracer.CastShadow = false
	local middle = startPosition + offset * 0.5
	tracer.CFrame = CFrame.lookAt(middle, endPosition)
	tracer.Parent = camera
	Debris:AddItem(tracer, 0.055)

	task.delay(0.07, function()
		activeTracers = math.max(0, activeTracers - 1)
	end)
end

local function playFireSound(bot)
	local weapon = bot and (bot:FindFirstChild("WeaponVisual") or bot:FindFirstChild("BotWeapon"))
	if not weapon then
		return
	end
	local sound = weapon:FindFirstChild("FireSound", true)
	if sound and sound:IsA("Sound") and sound.SoundId ~= "" then
		sound:Play()
	end
end

function BotShootFX.Play(bot, weaponId, hitPosition)
	if not bot or not bot.Parent then
		return
	end

	local muzzle = bot:FindFirstChild("Muzzle", true)
	if not muzzle or not muzzle:IsA("Attachment") then
		return
	end

	local startPosition = muzzle.WorldPosition
	if typeof(hitPosition) ~= "Vector3" then
		hitPosition = startPosition + muzzle.WorldCFrame.LookVector * 40
	end

	playMuzzleFlash(muzzle, weaponId)
	createTracer(startPosition, hitPosition, weaponId)
	playFireSound(bot)
end

return BotShootFX
