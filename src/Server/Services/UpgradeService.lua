local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UpgradesConfig = require(ReplicatedStorage.Shared.Config.UpgradesConfig)
local StatCalculator = require(ReplicatedStorage.Shared.Util.StatCalculator)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local ProfileTemplate = require(ReplicatedStorage.Shared.Util.ProfileTemplate)

local UpgradeService = {}

local function totalUpgradeLevels(profile): number
	local sum = 0
	for statKey, _ in pairs(UpgradesConfig.Stats) do
		sum += profile.Upgrades[statKey] or 0
	end
	return sum
end

function UpgradeService:Init(services)
	local DataService = services.DataService
	local RemoteService = services.RemoteService
	local upgrade = RemoteService.GetRemote(RemoteNames.UpgradeStat)
	if upgrade then
		upgrade.OnServerInvoke = function(player, statName, amount)
			local profile = DataService.GetProfile(player)
			if not profile or not UpgradesConfig.Stats[statName] then
				return { success = false }
			end
			-- Стата должна быть открыта текущим престижем
			if not UpgradesConfig.IsStatUnlocked(statName, profile.PrestigePoints or 0) then
				return { success = false, error = "Locked" }
			end
			local level = profile.Upgrades[statName] or 0

			-- Мульти-покупка: 1 / 10 / 100 / "max"
			local count = 1
			if amount == "max" then
				count = StatCalculator.GetAffordableUpgradeCount(statName, level, profile.XP or 0)
				if count <= 0 then
					return { success = false, error = "Not enough XP" }
				end
			else
				count = math.clamp(math.floor(tonumber(amount) or 1), 1, 10000)
			end

			local cost = StatCalculator.GetBulkUpgradeCost(statName, level, count)
			if cost == math.huge then
				return { success = false, error = "Max level" }
			end
			if (profile.XP or 0) < cost then
				-- Пытаемся купить меньше уровней, если хватает хотя бы на один
				count = StatCalculator.GetAffordableUpgradeCount(statName, level, profile.XP or 0)
				if count <= 0 then
					return { success = false, error = "Not enough XP" }
				end
				cost = StatCalculator.GetBulkUpgradeCost(statName, level, count)
			end
			profile.XP -= cost
			profile.Upgrades[statName] = level + count
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, true)
			return { success = true, level = level + count, bought = count, spent = cost, profile = Util.DeepCopy(profile) }
		end
	end

	local prestige = RemoteService.GetRemote(RemoteNames.PrestigeReset)
	if prestige then
		prestige.OnServerInvoke = function(player)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false, error = "No profile" }
			end
			if not UpgradesConfig.Prestige.Enabled then
				return { success = false, error = "Prestige disabled" }
			end
			local totalLevels = totalUpgradeLevels(profile)
			local threshold = UpgradesConfig.GetPrestigeThreshold(profile.PrestigePoints or 0)
			if totalLevels < threshold then
				return { success = false, error = string.format("Нужно %d уровней, сейчас %d", threshold, totalLevels) }
			end
			-- Сбрасываем прокачку, начисляем престиж.
			profile.Upgrades = Util.DeepCopy(ProfileTemplate.Upgrades)
			profile.PrestigePoints = (profile.PrestigePoints or 0) + UpgradesConfig.Prestige.PointsPerReset
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, true)
			return {
				success = true,
				points = profile.PrestigePoints,
				profile = Util.DeepCopy(profile),
			}
		end
	end

	local ascend = RemoteService.GetRemote(RemoteNames.Ascend)
	if ascend then
		ascend.OnServerInvoke = function(player)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false, error = "No profile" }
			end
			if not UpgradesConfig.Ascension.Enabled then
				return { success = false, error = "Ascension disabled" }
			end
			local cost = UpgradesConfig.GetAscensionCost(profile.Ascensions or 0)
			if (profile.PrestigePoints or 0) < cost then
				return { success = false, error = string.format("Нужно %d очков престижа, есть %d", cost, profile.PrestigePoints or 0) }
			end
			-- Вознесение: сжигаем очки престижа и уровни, получаем постоянный множитель.
			profile.PrestigePoints = 0
			profile.Upgrades = Util.DeepCopy(ProfileTemplate.Upgrades)
			profile.Ascensions = (profile.Ascensions or 0) + 1
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, true)
			return {
				success = true,
				ascensions = profile.Ascensions,
				profile = Util.DeepCopy(profile),
			}
		end
	end
end

return UpgradeService
