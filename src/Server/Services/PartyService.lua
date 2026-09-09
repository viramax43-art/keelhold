--[[
	PartyService — пати до PartySize + Invite/Accept/Kick.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local CoopMultiplier = require(ReplicatedStorage.Shared.Util.CoopMultiplier)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local PartyService = {}
local parties = {} -- leaderUserId -> party
local memberToParty = {} -- userId -> party
local friendCache = {}
local pendingInvites = {} -- targetUserId -> { leaderUserId, at }
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
		return { success = true, party = makePayload(memberToParty[player.UserId]) }
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

-- Для стримера: любой участник пати даёт бонус (не только Roblox-друзья)
function PartyService.GetFriendCountInParty(party): number
	if not party or not party.Members then
		return 0
	end
	local n = 0
	for _, m in ipairs(party.Members) do
		if m and m.Parent then
			n += 1
		end
	end
	return math.max(0, n - 1)
end

function PartyService.Invite(leader: Player, targetUserId: number)
	local party = PartyService.GetParty(leader)
	if not party then
		PartyService.CreateParty(leader)
		party = PartyService.GetParty(leader)
	end
	if not party or party.Leader ~= leader then
		return { success = false, error = "Только лидер приглашает" }
	end
	if #party.Members >= (GameConfig.PartySize or 4) then
		return { success = false, error = "Пати заполнена" }
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return { success = false, error = "Игрок не в лобби" }
	end
	if memberToParty[target.UserId] then
		return { success = false, error = "Игрок уже в пати" }
	end
	pendingInvites[target.UserId] = { leaderUserId = leader.UserId, at = os.clock() }
	RemoteService.FireClient(target, RemoteNames.PartyInvite, {
		LeaderUserId = leader.UserId,
		LeaderName = leader.DisplayName,
		Difficulty = party.Difficulty,
	})
	Log.Write("Party", leader.Name .. " invited " .. target.Name)
	return { success = true }
end

function PartyService.Accept(player: Player)
	local inv = pendingInvites[player.UserId]
	if not inv or os.clock() - inv.at > 60 then
		pendingInvites[player.UserId] = nil
		return { success = false, error = "Приглашение истекло" }
	end
	pendingInvites[player.UserId] = nil
	local party = parties[inv.leaderUserId]
	if not party then
		return { success = false, error = "Пати распущена" }
	end
	if #party.Members >= (GameConfig.PartySize or 4) then
		return { success = false, error = "Пати заполнена" }
	end
	if memberToParty[player.UserId] then
		return { success = false, error = "Ты уже в пати" }
	end
	table.insert(party.Members, player)
	memberToParty[player.UserId] = party
	friendCache[party.Leader.UserId] = nil
	broadcast(party)
	return { success = true, party = makePayload(party) }
end

function PartyService.Kick(leader: Player, targetUserId: number)
	local party = PartyService.GetParty(leader)
	if not party or party.Leader ~= leader then
		return { success = false, error = "Не лидер" }
	end
	for i = #party.Members, 1, -1 do
		local m = party.Members[i]
		if m.UserId == targetUserId and m ~= leader then
			table.remove(party.Members, i)
			memberToParty[targetUserId] = nil
			if m.Parent then
				RemoteService.FireClient(m, RemoteNames.PartyUpdated, nil)
			end
		end
	end
	friendCache[leader.UserId] = nil
	broadcast(party)
	return { success = true }
end

function PartyService.GetLobbyPlayers(player: Player)
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(p.UserId)
			end)
			table.insert(out, {
				UserId = p.UserId,
				Name = p.Name,
				DisplayName = p.DisplayName,
				InParty = memberToParty[p.UserId] ~= nil,
				IsFriend = ok and isFriend or false,
			})
		end
	end
	table.sort(out, function(a, b)
		if a.IsFriend ~= b.IsFriend then
			return a.IsFriend
		end
		return a.DisplayName < b.DisplayName
	end)
	return out
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
			elseif actionName == "Get" then
				local party = PartyService.GetParty(player)
				return {
					success = true,
					party = makePayload(party),
					multiplier = CoopMultiplier.Compute(PartyService.GetFriendCountInParty(party)),
				}
			elseif actionName == "Invite" then
				return PartyService.Invite(player, tonumber(payload) or 0)
			elseif actionName == "Accept" then
				return PartyService.Accept(player)
			elseif actionName == "Decline" then
				pendingInvites[player.UserId] = nil
				return { success = true }
			elseif actionName == "Kick" then
				return PartyService.Kick(player, tonumber(payload) or 0)
			elseif actionName == "LobbyPlayers" then
				return { success = true, players = PartyService.GetLobbyPlayers(player) }
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
							if m.Parent then
								RemoteService.FireClient(m, RemoteNames.PartyUpdated, nil)
							end
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
		pendingInvites[player.UserId] = nil
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
					if m.Parent then
						RemoteService.FireClient(m, RemoteNames.PartyUpdated, nil)
					end
				end
			else
				broadcast(party)
			end
		end
		friendCache[player.UserId] = nil
	end)
end

return PartyService
