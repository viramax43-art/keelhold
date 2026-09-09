--[[
	BotWeaponAnimation — клиентская отдача через Motor6D.Transform (один RenderStepped).
	finalTransform = aimTransform * recoilTransform
]]

local RunService = game:GetService("RunService")

local BotWeaponAnimation = {}

local active = {}
local connection

local CONFIG = {
	Rifle = { Kick = 0.075, Pitch = math.rad(2.2), Recovery = 18, RotationRecovery = 20 },
	AssaultRifle = { Kick = 0.075, Pitch = math.rad(2.2), Recovery = 18, RotationRecovery = 20 },
	LMG = { Kick = 0.045, Pitch = math.rad(1.25), Recovery = 13, RotationRecovery = 16 },
	MachineGun = { Kick = 0.045, Pitch = math.rad(1.25), Recovery = 13, RotationRecovery = 16 },
	SMG = { Kick = 0.055, Pitch = math.rad(1.6), Recovery = 16, RotationRecovery = 18 },
	Pistol = { Kick = 0.09, Pitch = math.rad(2.8), Recovery = 20, RotationRecovery = 22 },
	Revolver = { Kick = 0.11, Pitch = math.rad(3.2), Recovery = 16, RotationRecovery = 18 },
	Shotgun = { Kick = 0.12, Pitch = math.rad(3.5), Recovery = 12, RotationRecovery = 14 },
	Sniper = { Kick = 0.1, Pitch = math.rad(2.5), Recovery = 10, RotationRecovery = 12 },
	Crossbow = { Kick = 0.06, Pitch = math.rad(1.5), Recovery = 14, RotationRecovery = 16 },
}

local function getConfig(weaponId)
	return CONFIG[weaponId] or CONFIG.Rifle
end

local function stopConnectionIfEmpty()
	if next(active) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function computeAimTransform(motor: Motor6D, aimPos: Vector3): CFrame?
	local hand = motor.Part0
	local handle = motor.Part1
	if not hand or not handle then
		return nil
	end
	-- Handle -Z смотрит на цель
	local desiredHandleCFrame = CFrame.lookAt(handle.Position, aimPos, Vector3.yAxis)
	local ok, result = pcall(function()
		return motor.C0:Inverse() * hand.CFrame:ToObjectSpace(desiredHandleCFrame) * motor.C1
	end)
	if ok and typeof(result) == "CFrame" then
		return result
	end
	return nil
end

local function update(dt)
	for bot, state in pairs(active) do
		if not bot.Parent or not state.motor or not state.motor.Parent then
			active[bot] = nil
			continue
		end

		if bot:GetAttribute("CombatAiming") == true then
			local ax = bot:GetAttribute("BD_AimX")
			local ay = bot:GetAttribute("BD_AimY")
			local az = bot:GetAttribute("BD_AimZ")
			if typeof(ax) == "number" and typeof(ay) == "number" and typeof(az) == "number" then
				local aimTF = computeAimTransform(state.motor, Vector3.new(ax, ay, az))
				if aimTF then
					state.baseTransform = aimTF
				end
			end
		elseif state.recoverToIdentity then
			-- плавно к нулю базы не нужно — identity + fading recoil
			state.baseTransform = CFrame.identity
		end

		local settings = getConfig(state.weaponId)
		local kickRecovery = math.exp(-settings.Recovery * dt)
		local rotationRecovery = math.exp(-settings.RotationRecovery * dt)

		state.kick *= kickRecovery
		state.pitch *= rotationRecovery
		state.roll *= rotationRecovery

		local recoilTransform = CFrame.new(0, 0, state.kick) * CFrame.Angles(-state.pitch, 0, state.roll)
		state.motor.Transform = state.baseTransform * recoilTransform
	end

	stopConnectionIfEmpty()
end

local function ensureConnection()
	if connection then
		return
	end
	connection = RunService.RenderStepped:Connect(update)
end

function BotWeaponAnimation.Register(bot, motor, weaponId)
	if not bot or not motor or not motor:IsA("Motor6D") then
		return
	end

	active[bot] = active[bot]
		or {
			motor = motor,
			weaponId = weaponId or "Rifle",
			baseTransform = CFrame.identity,
			kick = 0,
			pitch = 0,
			roll = 0,
			recoverToIdentity = true,
		}

	local state = active[bot]
	state.motor = motor
	state.weaponId = weaponId or state.weaponId or "Rifle"
	ensureConnection()
end

function BotWeaponAnimation.SetWeapon(bot, weaponId)
	local state = active[bot]
	if state then
		state.weaponId = weaponId or "Rifle"
	end
end

function BotWeaponAnimation.SetBaseTransform(bot, baseTransform)
	local state = active[bot]
	if state and typeof(baseTransform) == "CFrame" then
		state.baseTransform = baseTransform
	end
end

function BotWeaponAnimation.Pulse(bot, weaponId)
	local state = active[bot]
	if not state then
		return
	end
	if weaponId then
		state.weaponId = weaponId
	end
	local settings = getConfig(state.weaponId)
	state.kick = math.min(state.kick + settings.Kick, 0.18)
	state.pitch = math.min(state.pitch + settings.Pitch, math.rad(7))
	state.roll = math.clamp(state.roll + math.rad(math.random(-18, 18) / 10), math.rad(-3), math.rad(3))
end

function BotWeaponAnimation.Unregister(bot)
	local state = active[bot]
	if state and state.motor and state.motor.Parent then
		pcall(function()
			state.motor.Transform = CFrame.identity
		end)
	end
	active[bot] = nil
	stopConnectionIfEmpty()
end

function BotWeaponAnimation.GetRecoilOffset(bot)
	local state = active[bot]
	if not state then
		return CFrame.identity
	end
	return CFrame.new(0, 0, state.kick) * CFrame.Angles(-state.pitch, 0, state.roll)
end

return BotWeaponAnimation
