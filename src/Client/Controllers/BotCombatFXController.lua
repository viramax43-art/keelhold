--[[
	BotCombatFXController — слушает Remotes.CombatVFX (серверный выстрел бота).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local BotWeaponAnimation = require(ReplicatedStorage.Shared.Util.BotWeaponAnimation)
local BotShootFX = require(ReplicatedStorage.Shared.Util.BotShootFX)

local BotCombatFXController = {}

local function ensureRegistered(botModel, weaponId)
	local grip = botModel:FindFirstChild("BotWeaponGrip", true)
	if grip and grip:IsA("Motor6D") then
		BotWeaponAnimation.Register(botModel, grip, weaponId or botModel:GetAttribute("WeaponType") or "Rifle")
		return grip
	end
	return nil
end

local function onBotRemoved(botModel)
	BotWeaponAnimation.Unregister(botModel)
end

local function handlePayload(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Kind ~= "BotShot" and payload.Kind ~= "EnemyShot" then
		return
	end

	local botModel = payload.Bot
	if not botModel or not botModel.Parent then
		return
	end

	local weaponId = payload.WeaponType or payload.WeaponId or botModel:GetAttribute("WeaponType") or "Rifle"
	local hitPosition = payload.HitPosition

	ensureRegistered(botModel, weaponId)
	BotWeaponAnimation.Pulse(botModel, weaponId)
	BotShootFX.Play(botModel, weaponId, hitPosition)

	if not botModel:GetAttribute("BD_FXHooked") then
		botModel:SetAttribute("BD_FXHooked", true)
		botModel.AncestryChanged:Connect(function(_, parent)
			if not parent then
				onBotRemoved(botModel)
			end
		end)
		local hum = botModel:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				onBotRemoved(botModel)
			end)
		end
	end
end

function BotCombatFXController:Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	if not remotes then
		return
	end
	local evt = remotes:WaitForChild(RemoteNames.CombatVFX, 20)
	if not evt or not evt:IsA("RemoteEvent") then
		return
	end
	evt.OnClientEvent:Connect(handlePayload)

	-- Подхватить уже заспавненных защитников
	local squad = workspace:FindFirstChild("Squad")
	if squad then
		for _, child in ipairs(squad:GetChildren()) do
			if child:IsA("Model") then
				ensureRegistered(child, child:GetAttribute("WeaponType"))
			end
		end
		squad.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				task.defer(function()
					ensureRegistered(child, child:GetAttribute("WeaponType"))
				end)
			end
		end)
	end
end

return BotCombatFXController
