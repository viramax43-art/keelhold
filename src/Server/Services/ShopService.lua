local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponsConfig = require(ReplicatedStorage.Shared.Config.WeaponsConfig)
local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local ShopService = {}
local DataService, RemoteService

function ShopService:Init(services)
	DataService = services.DataService
	RemoteService = services.RemoteService

	local buyWeapon = RemoteService.GetRemote(RemoteNames.BuyWeapon)
	if buyWeapon then
		buyWeapon.OnServerInvoke = function(player, weaponType, tier)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false, error = "No profile" }
			end
			weaponType = tostring(weaponType)
			tier = tonumber(tier) or 0
			local stats = WeaponsConfig.Weapons[weaponType] and WeaponsConfig.Weapons[weaponType][tier]
			if not stats then
				return { success = false, error = "Unknown weapon" }
			end
			local owned = profile.OwnedWeapons[weaponType] or 0
			if owned >= tier then
				return { success = false, error = "Already owned" }
			end
			if owned < tier - 1 then
				return { success = false, error = "Need previous tier" }
			end
			if (profile.Gold or 0) < (stats.GoldCost or 0) then
				return { success = false, error = "Not enough gold" }
			end
			profile.Gold -= stats.GoldCost
			profile.OwnedWeapons[weaponType] = tier
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, true)
			return { success = true }
		end
	end

	local buyArmor = RemoteService.GetRemote(RemoteNames.BuyArmor)
	if buyArmor then
		buyArmor.OnServerInvoke = function(player, tier)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false }
			end
			tier = tonumber(tier) or 0
			local data = ArmorConfig.Tiers[tier]
			if not data then
				return { success = false, error = "Unknown armor" }
			end
			if (profile.OwnedArmorTier or 0) >= tier then
				profile.EquippedArmorTier = tier
				DataService.NotifyProfile(player)
				return { success = true, equipped = true }
			end
			if (profile.OwnedArmorTier or 0) < tier - 1 then
				return { success = false, error = "Need previous tier" }
			end
			if (profile.Gold or 0) < data.GoldCost then
				return { success = false, error = "Not enough gold" }
			end
			profile.Gold -= data.GoldCost
			profile.OwnedArmorTier = tier
			profile.EquippedArmorTier = tier
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, true)
			return { success = true }
		end
	end

	local setLoadout = RemoteService.GetRemote(RemoteNames.SetSquadLoadout)
	if setLoadout then
		setLoadout.OnServerInvoke = function(player, slotIndex, weaponType, tier)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false }
			end
			slotIndex = tonumber(slotIndex) or 1
			weaponType = tostring(weaponType)
			tier = tonumber(tier) or 1
			local owned = profile.OwnedWeapons[weaponType] or 0
			if owned < tier then
				return { success = false, error = "Not owned" }
			end
			profile.SquadLoadout[slotIndex] = { WeaponType = weaponType, Tier = tier }
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, false)
			return { success = true }
		end
	end
end

return ShopService
