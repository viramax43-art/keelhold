--[[
	BotWeaponAnimation — клиентская отдача через Motor6D.Transform.
	baseTransform = только прицел (из нейтральной позы C0/C1, БЕЗ текущего Transform)
	recoilTransform = только kick/pitch/roll
	final = baseTransform * recoilTransform
]]

local RunService = game:GetService("RunService")

local BotWeaponAnimation = {}

local DEBUG_RECOIL = false
local RENDER_STEP_NAME = "BotWeaponRecoil"

local active = {}
local bound = false

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
	if next(active) == nil and bound then
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		end)
		bound = false
	end
end

--[[
	Aim Transform из нейтральной позы Motor6D (Transform = identity):
	Part1 = Part0 * C0 * C1:Inverse()
	Нельзя использовать handle.Position / handle.CFrame — они уже с отдачей.
]]
local function computeAimTransform(motor: Motor6D, targetPosition: Vector3): CFrame?
	if not motor or not motor:IsA("Motor6D") then
		return nil
	end
	local hand = motor.Part0
	local handle = motor.Part1
	if not hand or not handle then
		return nil
	end
	if typeof(targetPosition) ~= "Vector3" then
		return nil
	end

	local handWorldCFrame = hand.CFrame
	local neutralHandleCFrame = handWorldCFrame * motor.C0 * motor.C1:Inverse()
	local neutralHandlePosition = neutralHandleCFrame.Position

	local toTarget = targetPosition - neutralHandlePosition
	if toTarget.Magnitude < 0.05 then
		return CFrame.identity
	end

	local up = Vector3.yAxis
	if math.abs(toTarget.Unit:Dot(up)) > 0.92 then
		up = handWorldCFrame.RightVector
	end

	local desiredHandleCFrame = CFrame.lookAt(neutralHandlePosition, targetPosition, up)

	local ok, aimTransform = pcall(function()
		return motor.C0:Inverse() * handWorldCFrame:ToObjectSpace(desiredHandleCFrame) * motor.C1
	end)
	if ok and typeof(aimTransform) == "CFrame" then
		return aimTransform
	end
	return nil
end

local function update(dt)
	for bot, state in pairs(active) do
		if
			not bot.Parent
			or not state.motor
			or not state.motor.Parent
			or not state.motor.Part0
			or not state.motor.Part1
		then
			active[bot] = nil
			continue
		end

		-- База: только прицел из нейтральной позы (без отдачи в формуле)
		if bot:GetAttribute("CombatAiming") == true then
			local ax = bot:GetAttribute("BD_AimX")
			local ay = bot:GetAttribute("BD_AimY")
			local az = bot:GetAttribute("BD_AimZ")
			if typeof(ax) == "number" and typeof(ay) == "number" and typeof(az) == "number" then
				local aimTransform = computeAimTransform(state.motor, Vector3.new(ax, ay, az))
				if aimTransform then
					state.baseTransform = aimTransform
				end
			end
		else
			state.baseTransform = CFrame.identity
		end

		local settings = getConfig(state.weaponId)
		local kickAlpha = math.exp(-settings.Recovery * dt)
		local rotationAlpha = math.exp(-settings.RotationRecovery * dt)

		state.kick *= kickAlpha
		state.pitch *= rotationAlpha
		state.roll *= rotationAlpha

		if state.kick < 1e-5 then
			state.kick = 0
		end
		if math.abs(state.pitch) < 1e-5 then
			state.pitch = 0
		end
		if math.abs(state.roll) < 1e-5 then
			state.roll = 0
		end

		-- Только временная локальная отдача — никогда не пишется в baseTransform
		local recoilTransform = CFrame.new(0, 0, state.kick) * CFrame.Angles(-state.pitch, 0, state.roll)
		state.motor.Transform = state.baseTransform * recoilTransform

		if DEBUG_RECOIL and state.kick > 0.001 then
			local hand = state.motor.Part0
			local handle = state.motor.Part1
			print(
				string.format(
					"[RecoilDebug] kick=%.4f pitch=%.4f hand=%s handle=%s",
					state.kick,
					state.pitch,
					tostring(hand and hand.Position),
					tostring(handle and handle.Position)
				)
			)
		end
	end

	stopConnectionIfEmpty()
end

local function ensureConnection()
	if bound then
		return
	end
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Character.Value + 1, update)
	bound = true
end

function BotWeaponAnimation.Register(bot, motor, weaponId)
	if not bot or not motor or not motor:IsA("Motor6D") then
		return
	end

	local state = active[bot]
	if not state then
		state = {
			bot = bot,
			motor = motor,
			weaponId = weaponId or "Rifle",
			baseTransform = CFrame.identity,
			kick = 0,
			pitch = 0,
			roll = 0,
		}
		active[bot] = state
	else
		state.motor = motor
		state.weaponId = weaponId or state.weaponId or "Rifle"
	end

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
	if not state or typeof(baseTransform) ~= "CFrame" then
		return
	end
	-- Только базовая поза, без отдачи
	state.baseTransform = baseTransform
end

function BotWeaponAnimation.ResetBaseTransform(bot)
	local state = active[bot]
	if not state then
		return
	end
	state.baseTransform = CFrame.identity
	state.kick = 0
	state.pitch = 0
	state.roll = 0
	if state.motor and state.motor.Parent then
		state.motor.Transform = CFrame.identity
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
	state.kick = math.min(state.kick + settings.Kick, settings.Kick * 2.5)
	state.pitch = math.min(state.pitch + settings.Pitch, settings.Pitch * 3)
	state.roll = math.clamp(state.roll + math.rad(math.random(-10, 10) / 10), math.rad(-2), math.rad(2))
	ensureConnection()
end

function BotWeaponAnimation.Unregister(bot)
	local state = active[bot]
	if state and state.motor and state.motor.Parent then
		state.motor.Transform = CFrame.identity
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

function BotWeaponAnimation.ComputeAimTransform(motor, targetPosition)
	return computeAimTransform(motor, targetPosition)
end

return BotWeaponAnimation
