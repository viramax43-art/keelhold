--[[
	RemoteService — создаёт Remotes в ReplicatedStorage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local RemoteService = {}
local folder = nil

local FUNCTIONS = {
	RemoteNames.GetProfile,
	RemoteNames.BuyWeapon,
	RemoteNames.BuyArmor,
	RemoteNames.UpgradeStat,
	RemoteNames.SetSquadLoadout,
	RemoteNames.RedeemPromocode,
	RemoteNames.ClaimDailyReward,
	RemoteNames.GetLeaderboard,
	RemoteNames.AdminAction,
	RemoteNames.AdminGetConfig,
	RemoteNames.PartyAction,
	RemoteNames.StartBattle,
	RemoteNames.ReturnToLobby,
	RemoteNames.GetDebugLogs,
	RemoteNames.FireWeapon,
}

local EVENTS = {
	RemoteNames.ProfileUpdated,
	RemoteNames.PartyUpdated,
	RemoteNames.OpenMenuTab,
	RemoteNames.BattleStarted,
	RemoteNames.SubmitClientLog,
	RemoteNames.WaveUpdated,
	RemoteNames.WaveResult,
	RemoteNames.BattleEnded,
	RemoteNames.CombatHit,
	RemoteNames.SquadUpdated,
	RemoteNames.CombatVFX,
}

function RemoteService:Init()
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(FUNCTIONS) do
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in ipairs(EVENTS) do
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	print("[BridgeDefense] Remotes ready:", #FUNCTIONS + #EVENTS)
end

function RemoteService.GetRemote(name: string): Instance?
	if not folder then
		folder = ReplicatedStorage:WaitForChild("Remotes", 10)
	end
	return folder and folder:FindFirstChild(name)
end

function RemoteService.FireAll(name: string, ...)
	local r = RemoteService.GetRemote(name)
	if r and r:IsA("RemoteEvent") then
		r:FireAllClients(...)
	end
end

function RemoteService.FireClient(player: Player, name: string, ...)
	local r = RemoteService.GetRemote(name)
	if r and r:IsA("RemoteEvent") then
		r:FireClient(player, ...)
	end
end

return RemoteService
