--[[
	TeleportService — единственный вход StartBattle (RemoteFunction).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportServiceRoblox = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local TeleportService = {}
local battleCooldown = {}
local RemoteService, PartyService, DataService, StudioBattleService, WaveService

function TeleportService.BuildTeleportData(party)
	local teleportData = {
		PartyId = party.Id,
		Difficulty = party.Difficulty or "Normal",
		Members = {},
		LeaderUserId = party.Leader.UserId,
		FriendCount = PartyService.GetFriendCountInParty(party),
	}
	for _, member in ipairs(party.Members) do
		local profile = DataService.GetProfile(member)
		table.insert(teleportData.Members, {
			UserId = member.UserId,
			Name = member.Name,
			LastCheckpoint = profile and profile.LastCheckpoint or 0,
		})
	end
	return teleportData
end

function TeleportService.StartBattle(player: Player)
	Log.Write("Battle", "StartBattle called by " .. player.Name)
	if not DataService or not DataService.IsProfileLoaded(player) then
		return { success = false, error = "Профиль ещё не загружен" }
	end
	if WaveService and WaveService.IsBattleBusy and WaveService.IsBattleBusy() then
		return { success = false, error = "Предыдущий бой ещё завершается" }
	end
	if battleCooldown[player.UserId] and tick() - battleCooldown[player.UserId] < 5 then
		return { success = true, silent = true }
	end
	battleCooldown[player.UserId] = tick()

	local party = PartyService.GetParty(player)
	if not party then
		Log.Write("Battle", "Creating party for " .. player.Name)
		local created = PartyService.CreateParty(player)
		if not created.success and created.error ~= "Already in party" then
			return { success = false, error = created.error or "Не удалось создать пати" }
		end
		party = PartyService.GetParty(player)
	end
	if not party then
		return { success = false, error = "Не удалось создать пати" }
	end
	if party.Leader ~= player then
		return { success = false, error = "Только лидер может начать бой" }
	end

	local teleportData = TeleportService.BuildTeleportData(party)

	if StudioBattleService.CanUseLocalBattle() then
		Log.Write("Battle", "Studio local battle mode")
		return StudioBattleService.StartLocalBattle(teleportData)
	end

	local battlePlaceId = GameConfig.PlaceIds.Battle
	if not battlePlaceId or battlePlaceId == 0 then
		return { success = false, error = "Battle PlaceId не задан" }
	end

	local ok, code = pcall(function()
		return TeleportServiceRoblox:ReserveServer(battlePlaceId)
	end)
	if not ok then
		Log.Write("Battle", "ReserveServer failed: " .. tostring(code), "ERROR")
		return { success = false, error = "Не удалось создать сервер боя" }
	end

	local players = {}
	local released = {}
	for _, m in ipairs(party.Members) do
		if m.Parent then
			if not DataService.IsProfileLoaded(m) then
				for _, r in ipairs(released) do
					DataService.ReacquireProfile(r)
				end
				return { success = false, error = "Профиль участника не загружен" }
			end
			local flushOk, flushErr = DataService.FlushAndReleaseProfile(m, "Teleport")
			if not flushOk then
				Log.Write("Battle", "FlushAndRelease failed for " .. m.Name .. ": " .. tostring(flushErr), "ERROR")
				for _, r in ipairs(released) do
					local reOk = DataService.ReacquireProfile(r)
					if not reOk and r.Parent then
						r:Kick("Не удалось восстановить профиль после отмены телепорта. Переподключитесь.")
					end
				end
				return {
					success = false,
					error = "Не удалось сохранить профиль перед телепортацией",
				}
			end
			table.insert(released, m)
			table.insert(players, m)
		end
	end

	local teleportOk, teleportError = pcall(function()
		TeleportServiceRoblox:TeleportToPrivateServer(battlePlaceId, code, players, nil, teleportData)
	end)
	if not teleportOk then
		Log.Write("Battle", "Teleport failed: " .. tostring(teleportError), "ERROR")
		for _, m in ipairs(released) do
			local reOk = DataService.ReacquireProfile(m)
			if not reOk and m.Parent then
				m:Kick("Телепорт не удался, профиль освобождён. Пожалуйста, переподключитесь.")
			end
		end
		return { success = false, error = "Телепорт не удался" }
	end
	return { success = true, message = "Телепорт..." }
end

function TeleportService.ReturnToLobby(player: Player)
	-- В активном бою EndBattle сам чистит врагов/ботов и возвращает в лобби
	if WaveService and WaveService.IsBattleBusy and WaveService.IsBattleBusy() then
		pcall(function()
			WaveService.EndBattle(false)
		end)
		return { success = true }
	end
	if StudioBattleService.CanUseLocalBattle() or (GameConfig.PlaceIds.Lobby or 0) == 0 then
		StudioBattleService.ReturnToLobbyLocal({ player })
		return { success = true }
	end
	local lobbyId = GameConfig.PlaceIds.Lobby
	local ok, err = pcall(function()
		TeleportServiceRoblox:Teleport(lobbyId, player)
	end)
	if not ok then
		Log.Write("Battle", "Return teleport failed: " .. tostring(err), "ERROR")
		return { success = false, error = "Не удалось вернуться в лобби" }
	end
	return { success = true }
end

function TeleportService.ReturnPlayers(players: { Player })
	if StudioBattleService.CanUseLocalBattle() or (GameConfig.PlaceIds.Lobby or 0) == 0 then
		StudioBattleService.ReturnToLobbyLocal(players)
		return
	end
	local lobbyId = GameConfig.PlaceIds.Lobby
	for _, p in ipairs(players) do
		pcall(function()
			TeleportServiceRoblox:Teleport(lobbyId, p)
		end)
	end
end

function TeleportService:Init(services)
	RemoteService = services.RemoteService
	PartyService = services.PartyService
	DataService = services.DataService
	StudioBattleService = services.StudioBattleService
	WaveService = services.WaveService

	if WaveService and WaveService.BindTeleportService then
		WaveService.BindTeleportService(TeleportService)
	end

	local startBattle = RemoteService.GetRemote(RemoteNames.StartBattle)
	if startBattle and startBattle:IsA("RemoteFunction") then
		startBattle.OnServerInvoke = function(player)
			local ok, result = pcall(function()
				return TeleportService.StartBattle(player)
			end)
			if not ok then
				warn("[BridgeDefense] StartBattle:", result)
				return { success = false, error = tostring(result) }
			end
			return result
		end
	end

	local returnLobby = RemoteService.GetRemote(RemoteNames.ReturnToLobby)
	if returnLobby and returnLobby:IsA("RemoteFunction") then
		returnLobby.OnServerInvoke = function(player)
			return TeleportService.ReturnToLobby(player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		battleCooldown[player.UserId] = nil
	end)
end

return TeleportService
