--[[
	PartyService — пати до PartySize.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local PartyService = {}
local parties = {} -- leaderUserId -> party
local memberToParty = {} -- userId -> party
local friendCache = {}
local RemoteService = nil

local function makePayload(party)
	if not party then
		return nil
	end
	local members = {}
	for _, m in ipairs(party.Members) do
		if m and m.Parent then
			table.insert(members, { UserId = m.UserId, Name = m.Name, DisplayName = m.DisplayName })
		end
	end
	return {
		Id = party.Id,
		Difficulty = party.Difficulty,
		LeaderUserId = party.Leader and party.Leader.UserId,
		Members = members,
	}
end

local function broadcast(party)
	if not RemoteService or not party then
		return
	end
	local payload = makePayload(party)
	for _, m in ipairs(party.Members) do
		if m and m.Parent then
			RemoteService.FireClient(m, RemoteNames.PartyUpdated, payload)
		end
	end
end

function PartyService.GetParty(player: Player)
	return memberToParty[player.UserId]
end

function PartyService.CreateParty(player: Player)
	if memberToParty[player.UserId] then
		return { success = false, error = "Already in party" }
	end
	local party = {
		Id = "P_" .. player.UserId .. "_" .. tostring(math.floor(os.clock() * 1000)),
		Leader = player,
		Members = { player },
		Difficulty = "Normal",
	}
	parties[player.UserId] = party
	memberToParty[player.UserId] = party
	broadcast(party)
	return { success = true, party = makePayload(party) }
end

function PartyService.SetDifficulty(player: Player, difficulty: string)
	local party = PartyService.GetParty(player)
	if not party or party.Leader ~= player then
		return { success = false, error = "Not leader" }
	end
	if not GameConfig.Difficulties[difficulty] then
		return { success = false, error = "Bad difficulty" }
	end
	party.Difficulty = difficulty
	broadcast(party)
	return { success = true }
end

function PartyService.GetFriendCountInParty(party): number
	if not party or not party.Leader then
		return 0
	end
	local leader = party.Leader
	local cached = friendCache[leader.UserId]
	if cached and tick() - cached.at < 30 then
		return cached.n
	end
	local n = 0
	for _, m in ipairs(party.Members) do
		if m ~= leader and m.Parent then
			local ok, isFriend = pcall(function()
				return leader:IsFriendsWith(m.UserId)
			end)
			if ok and isFriend then
				n += 1
			end
		end
	end
	friendCache[leader.UserId] = { at = tick(), n = n }
	return n
end

function PartyService:Init(services)
	RemoteService = services.RemoteService
	local action = RemoteService.GetRemote(RemoteNames.PartyAction)
	if action and action:IsA("RemoteFunction") then
		action.OnServerInvoke = function(player, actionName, payload)
			if actionName == "Create" then
				return PartyService.CreateParty(player)
			elseif actionName == "SetDifficulty" then
				return PartyService.SetDifficulty(player, tostring(payload or "Normal"))
			elseif actionName == "Leave" then
				local party = PartyService.GetParty(player)
				if party then
					for i = #party.Members, 1, -1 do
						if party.Members[i] == player then
							table.remove(party.Members, i)
						end
					end
					memberToParty[player.UserId] = nil
					if party.Leader == player then
						parties[player.UserId] = nil
						for _, m in ipairs(party.Members) do
							memberToParty[m.UserId] = nil
						end
					else
						broadcast(party)
					end
				end
				return { success = true }
			end
			return { success = false, error = "Unknown" }
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		local party = PartyService.GetParty(player)
		if party then
			for i = #party.Members, 1, -1 do
				if party.Members[i] == player then
					table.remove(party.Members, i)
				end
			end
			memberToParty[player.UserId] = nil
			if party.Leader == player then
				parties[player.UserId] = nil
				for _, m in ipairs(party.Members) do
					memberToParty[m.UserId] = nil
				end
			else
				broadcast(party)
			end
		end
		friendCache[player.UserId] = nil
	end)
end

return PartyService
