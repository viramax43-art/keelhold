local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponsConfig = require(ReplicatedStorage.Shared.Config.WeaponsConfig)
local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Util = require(ReplicatedStorage.Shared.Util.Util)

local ShopService = {}
local DataService, RemoteService

local function profilePayload(profile)
	return Util.DeepCopy(profile)
end

local function ensureInventory(profile)
	profile.WeaponCopies = profile.WeaponCopies or {}
	profile.ArmorCopies = profile.ArmorCopies or {}
	profile.SquadArmor = profile.SquadArmor or { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
	profile.SquadLoadout = profile.SquadLoadout or {}
	profile.OwnedWeapons = profile.OwnedWeapons or {}

	-- Миграция со старого формата (OwnedWeapons = max tier на всех)
	local hasCopies = false
	for _, tiers in pairs(profile.WeaponCopies) do
		if type(tiers) == "table" then
			for _, n in pairs(tiers) do
				if (tonumber(n) or 0) > 0 then
					hasCopies = true
					break
				end
			end
		end
		if hasCopies then
			break
		end
	end
	if not hasCopies then
		for wType, maxTier in pairs(profile.OwnedWeapons) do
			local t = tonumber(maxTier) or 0
			if t > 0 then
				profile.WeaponCopies[wType] = profile.WeaponCopies[wType] or {}
				-- Одна копия макс. тира + 4 пистолета T1 если пусто
				profile.WeaponCopies[wType][t] = (profile.WeaponCopies[wType][t] or 0) + 1
			end
		end
		profile.WeaponCopies.Pistol = profile.WeaponCopies.Pistol or {}
		if (profile.WeaponCopies.Pistol[1] or 0) < 4 then
			profile.WeaponCopies.Pistol[1] = 4
		end
	end

	local armorStock = 0
	for _, n in pairs(profile.ArmorCopies) do
		armorStock += tonumber(n) or 0
	end
	if armorStock == 0 and (profile.OwnedArmorTier or 0) > 0 then
		local t = profile.OwnedArmorTier
		profile.ArmorCopies[t] = 1
		if (profile.EquippedArmorTier or 0) > 0 then
			profile.SquadArmor[1] = profile.EquippedArmorTier
		end
	end
end

local function countEquippedWeapon(profile, weaponType, tier): number
	local n = 0
	for _, load in pairs(profile.SquadLoadout or {}) do
		if type(load) == "table" and load.WeaponType == weaponType and (load.Tier or 1) == tier then
			n += 1
		end
	end
	return n
end

local function countEquippedArmor(profile, tier): number
	local n = 0
	for _, t in pairs(profile.SquadArmor or {}) do
		if (tonumber(t) or 0) == tier then
			n += 1
		end
	end
	return n
end

local function getCopyCount(profile, weaponType, tier): number
	local byType = profile.WeaponCopies and profile.WeaponCopies[weaponType]
	if not byType then
		return 0
	end
	return tonumber(byType[tier]) or tonumber(byType[tostring(tier)]) or 0
end

local function addWeaponCopy(profile, weaponType, tier)
	profile.WeaponCopies[weaponType] = profile.WeaponCopies[weaponType] or {}
	profile.WeaponCopies[weaponType][tier] = (profile.WeaponCopies[weaponType][tier] or 0) + 1
end

local function findEquipSlot(profile, botCount): number?
	for slot = 1, botCount do
		local load = profile.SquadLoadout[slot]
		if type(load) ~= "table" then
			return slot
		end
		if load.WeaponType == "Pistol" and (load.Tier or 1) <= 1 then
			return slot
		end
	end
	return nil
end

function ShopService:Init(services)
	DataService = services.DataService
	RemoteService = services.RemoteService

	local buyWeapon = RemoteService.GetRemote(RemoteNames.BuyWeapon)
	if buyWeapon then
		buyWeapon.OnServerInvoke = function(player, weaponType, tier, slotIndex)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false, error = "No profile" }
			end
			ensureInventory(profile)
			weaponType = tostring(weaponType)
			tier = tonumber(tier) or 0
			slotIndex = tonumber(slotIndex)
			local maxTier = WeaponsConfig.MaxTier or 5
			local botCount = GameConfig.DefenseBotCount or 4
			if tier % 1 ~= 0 or tier < 1 or tier > maxTier then
				return { success = false, error = "Bad tier" }
			end
			local stats = WeaponsConfig.Weapons[weaponType] and WeaponsConfig.Weapons[weaponType][tier]
			if not stats then
				return { success = false, error = "Unknown weapon" }
			end
			local prestigeReq = WeaponsConfig.GetPrestigeRequired(tier)
			if (profile.PrestigePoints or 0) < prestigeReq then
				return { success = false, error = string.format("Нужен престиж %d", prestigeReq), profile = profilePayload(profile) }
			end
			local unlocked = profile.OwnedWeapons[weaponType] or 0
			if unlocked < tier - 1 then
				return { success = false, error = "Need previous tier" }
			end
			if (profile.Gold or 0) < (stats.GoldCost or 0) then
				return { success = false, error = "Not enough gold", profile = profilePayload(profile) }
			end
			profile.Gold -= stats.GoldCost
			if unlocked < tier then
				profile.OwnedWeapons[weaponType] = tier
			end
			addWeaponCopy(profile, weaponType, tier)

			local equipSlot = slotIndex
			if not equipSlot or equipSlot < 1 or equipSlot > botCount then
				equipSlot = findEquipSlot(profile, botCount) or 1
			end
			-- Экипируем только один слот (1 покупка = 1 единица)
			profile.SquadLoadout[equipSlot] = { WeaponType = weaponType, Tier = tier }

			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, true)
			return { success = true, equippedSlot = equipSlot, profile = profilePayload(profile) }
		end
	end

	local buyArmor = RemoteService.GetRemote(RemoteNames.BuyArmor)
	if buyArmor then
		buyArmor.OnServerInvoke = function(player, tier, slotIndex)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false }
			end
			ensureInventory(profile)
			tier = tonumber(tier) or 0
			slotIndex = tonumber(slotIndex)
			local botCount = GameConfig.DefenseBotCount or 4
			if tier % 1 ~= 0 then
				return { success = false, error = "Bad tier" }
			end
			local data = ArmorConfig.Tiers[tier]
			if not data then
				return { success = false, error = "Unknown armor" }
			end
			local ownedMax = profile.OwnedArmorTier or 0
			if ownedMax < tier - 1 then
				return { success = false, error = "Need previous tier" }
			end
			if (profile.Gold or 0) < data.GoldCost then
				return { success = false, error = "Not enough gold", profile = profilePayload(profile) }
			end
			profile.Gold -= data.GoldCost
			if ownedMax < tier then
				profile.OwnedArmorTier = tier
			end
			profile.ArmorCopies[tier] = (profile.ArmorCopies[tier] or 0) + 1

			local equipSlot = slotIndex
			if not equipSlot or equipSlot < 1 or equipSlot > botCount then
				equipSlot = nil
				for s = 1, botCount do
					if (profile.SquadArmor[s] or 0) == 0 then
						equipSlot = s
						break
					end
				end
				equipSlot = equipSlot or 1
			end
			profile.SquadArmor[equipSlot] = tier
			profile.EquippedArmorTier = tier

			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, true)
			return { success = true, equippedSlot = equipSlot, profile = profilePayload(profile) }
		end
	end

	local setArmor = RemoteService.GetRemote(RemoteNames.SetSquadArmor)
	if setArmor then
		setArmor.OnServerInvoke = function(player, slotIndex, tier)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false }
			end
			ensureInventory(profile)
			slotIndex = tonumber(slotIndex) or 1
			tier = tonumber(tier) or 0
			local botCount = GameConfig.DefenseBotCount or 4
			if slotIndex % 1 ~= 0 or slotIndex < 1 or slotIndex > botCount then
				return { success = false, error = "Bad slot" }
			end
			if tier == 0 then
				profile.SquadArmor[slotIndex] = 0
				DataService.NotifyProfile(player)
				DataService.SaveProfile(player, false)
				return { success = true, profile = profilePayload(profile) }
			end
			local copies = tonumber(profile.ArmorCopies[tier]) or 0
			local equipped = countEquippedArmor(profile, tier)
			local current = profile.SquadArmor[slotIndex] or 0
			local freeing = current == tier and 1 or 0
			if equipped - freeing >= copies then
				return { success = false, error = "Нет свободной копии брони" }
			end
			profile.SquadArmor[slotIndex] = tier
			profile.EquippedArmorTier = tier
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, false)
			return { success = true, profile = profilePayload(profile) }
		end
	end

	local setLoadout = RemoteService.GetRemote(RemoteNames.SetSquadLoadout)
	if setLoadout then
		setLoadout.OnServerInvoke = function(player, slotIndex, weaponType, tier)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false }
			end
			ensureInventory(profile)
			slotIndex = tonumber(slotIndex) or 1
			weaponType = tostring(weaponType)
			tier = tonumber(tier) or 1
			local botCount = GameConfig.DefenseBotCount or 4
			if slotIndex % 1 ~= 0
				or slotIndex < 1
				or slotIndex > botCount
				or tier % 1 ~= 0
				or tier < 1
				or tier > (WeaponsConfig.MaxTier or 5)
			then
				return { success = false, error = "Bad loadout" }
			end
			local copies = getCopyCount(profile, weaponType, tier)
			local equipped = countEquippedWeapon(profile, weaponType, tier)
			local current = profile.SquadLoadout[slotIndex]
			local freeing = 0
			if type(current) == "table" and current.WeaponType == weaponType and (current.Tier or 1) == tier then
				freeing = 1
			end
			if equipped - freeing >= copies then
				return { success = false, error = "Нет свободной копии оружия" }
			end
			profile.SquadLoadout[slotIndex] = { WeaponType = weaponType, Tier = tier }
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, false)
			return { success = true, profile = profilePayload(profile) }
		end
	end
end

return ShopService
