--[[
	StudioBattleService — бой на том же place в Studio (PlaceIds.Battle == 0).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapBind = require(ReplicatedStorage.Shared.Map.MapBind)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local StudioBattleService = {}
local WaveService = nil
local RemoteService = nil

function StudioBattleService.CanUseLocalBattle(): boolean
	return RunService:IsStudio() and (GameConfig.PlaceIds.Battle or 0) == 0
end

function StudioBattleService.HoverSpawn(player: Player)
	MapBind.EnsureBattlePoints()
	local stand = MapBind.GetSpectatorStandCFrame()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and stand then
		hrp.Anchored = false
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		hrp.CFrame = stand
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
		end
		Log.Write("StudioBattle", "Bridge stand spawn " .. player.Name)
	end
end

function StudioBattleService.StartLocalBattle(teleportData)
	Log.Write("StudioBattle", "Battle on commission Road Bridge")
	MapBind.EnsureBattlePoints()
	if WaveService and WaveService.StartBattle then
		WaveService.StartBattle(teleportData)
	end
	task.delay(0.5, function()
		for _, p in ipairs(Players:GetPlayers()) do
			StudioBattleService.HoverSpawn(p)
		end
	end)
	return { success = true, message = "Перемещение на мост..." }
end

function StudioBattleService.ReturnToLobbyLocal(players: { Player })
	for _, name in ipairs({ "Enemies", "Squad" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			f:ClearAllChildren()
		end
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	for _, player in ipairs(players) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char then
			char:SetAttribute("Spectator", false)
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanQuery = true
					-- The battle explicitly enabled HRP collision for flight.
					-- Roblox characters normally keep it non-collidable in lobby.
					if d.Name == "HumanoidRootPart" then
						d.CanCollide = false
					end
				end
			end
		end
		if hum then
			hum.PlatformStand = false
			hum.AutoRotate = true
			hum.MaxHealth = 100
			hum.Health = 100
		end
		if hrp then
			hrp.Anchored = false
			if spawn then
				hrp.CFrame = spawn.CFrame + Vector3.new(0, 4, 0)
			end
		end
		Log.Write("Teleport", "Returned " .. player.Name .. " to lobby spawn")
	end
end

function StudioBattleService:Init(services)
	WaveService = services.WaveService
	RemoteService = services.RemoteService
end

return StudioBattleService
