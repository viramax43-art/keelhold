-- Creates the first defender from the host's avatar description.
-- The generated rig is positioned once, then only its root is anchored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRigBuilder = require(ReplicatedStorage.Shared.Builders.CharacterRigBuilder)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local AvatarClone = {}

local function getDescription(host: Player): (HumanoidDescription?, Enum.HumanoidRigType)
	local character = host.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rigType = (humanoid and humanoid.RigType) or Enum.HumanoidRigType.R15

	if humanoid then
		local ok, applied = pcall(function()
			return humanoid:GetAppliedDescription()
		end)
		if ok and applied then
			return applied, rigType
		end
	end

	local ok, catalog = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(host.UserId)
	end)
	if ok and catalog then
		return catalog, Enum.HumanoidRigType.R15
	end
	return nil, rigType
end

function AvatarClone.Create(hostPlayer: Player, slotIndex: number, facingCF: CFrame, stats): Model?
	local description, rigType = getDescription(hostPlayer)
	if not description then
		Log.Write("Bot", "Avatar description unavailable for " .. hostPlayer.Name, "WARN")
		return nil
	end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, rigType)
	end)
	if not ok or not model then
		ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
	end
	if not ok or not model then
		Log.Write("Bot", "Avatar model creation failed for " .. hostPlayer.Name, "ERROR")
		return nil
	end

	local squad = workspace:FindFirstChild("Squad")
	if not squad then
		squad = Instance.new("Folder")
		squad.Name = "Squad"
		squad.Parent = workspace
	end

	model.Name = "Bot_Slot" .. slotIndex
	model:SetAttribute("SlotIndex", slotIndex)
	model:SetAttribute("IsBot", true)
	model:SetAttribute("UsesPlayerSkin", true)
	model:SetAttribute("TeamRole", "Ally")

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end

	model.PrimaryPart = root
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = stats.MaxHP
	humanoid.Health = stats.MaxHP
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	-- Parent before PivotTo so accessories finish attaching in their proper positions.
	model.Parent = squad
	model:PivotTo(facingCF)
	CharacterRigBuilder.AddTeamOutfit(model, "Ally", slotIndex)
	CharacterRigBuilder.AttachWeapon(model, stats.WeaponType or "Rifle", stats.WeaponTier or stats.Tier)
	CharacterRigBuilder.LockStanding(model, nil)
	CharacterRigBuilder.CreateHealthBar(
		model,
		string.format("%s | %s", hostPlayer.DisplayName, stats.WeaponType or "Rifle"),
		stats.MaxHP,
		stats.MaxHP,
		"Ally"
	)

	Log.Write("Bot", string.format("Avatar defender created: slot=%d rig=%s", slotIndex, humanoid.RigType.Name))
	return model
end

return AvatarClone
