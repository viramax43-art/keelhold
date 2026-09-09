--[[
	CombatService — FireWeapon отключён: игрок в бою только наблюдатель.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local CombatService = {}
local WaveService
local lastFire = {}
local lastWeaponType = {}

function CombatService:Init(services)
	WaveService = services.WaveService

	Players.PlayerRemoving:Connect(function(player)
		lastFire[player.UserId] = nil
		lastWeaponType[player.UserId] = nil
	end)

	local fire = services.RemoteService.GetRemote(RemoteNames.FireWeapon)
	if fire and fire:IsA("RemoteFunction") then
		fire.OnServerInvoke = function(player, _targetId, _origin)
			if WaveService and WaveService.IsBattleActive and not WaveService.IsBattleActive() then
				return { hit = false, reason = "inactive" }
			end
			local char = player.Character
			if char and char:GetAttribute("Spectator") then
				return { hit = false, reason = "spectator" }
			end
			return { hit = false, reason = "player_cannot_fire" }
		end
	end
end

return CombatService
