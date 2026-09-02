--[[
	AvatarClone — клон аватара хоста для бота слота 1.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterRigBuilder = require(ReplicatedStorage.Shared.Builders.CharacterRigBuilder)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local AvatarClone = {}

local DESC_FIELDS = {
	"Pants",
	"Shirt",
	"GraphicTShirt",
	"Face",
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
	"HairAccessory",
	"HatAccessory",
	"FaceAccessory",
	"NeckAccessory",
	"ShouldersAccessory",
	"FrontAccessory",
	"BackAccessory",
	"WaistAccessory",
}

local function mergeDescriptions(base: HumanoidDescription, extra: HumanoidDescription)
	for _, field in ipairs(DESC_FIELDS) do
		local okE, extraVal = pcall(function()
			return (extra :: any)[field]
		end)
		if not okE then
			continue
		end
		local okB, baseVal = pcall(function()
			return (base :: any)[field]
		end)
		if not okB then
			baseVal = nil
		end
		if typeof(extraVal) == "number" and extraVal ~= 0 then
			pcall(function()
				(base :: any)[field] = extraVal
			end)
		elseif typeof(extraVal) == "string" and extraVal ~= "" then
			pcall(function()
				(base :: any)[field] = extraVal
			end)
		elseif (baseVal == 0 or baseVal == "" or baseVal == nil) and extraVal ~= nil then
			pcall(function()
				(base :: any)[field] = extraVal
			end)
		end
	end
	pcall(function()
		local layered = extra:GetAccessories(true)
		if type(layered) == "table" and #layered > 0 then
			base:SetAccessories(layered, true)
		end
	end)
	return base
end

local function transferLiveAppearance(source: Model, target: Model)
	local function copyClass(className: string)
		local existing = target:FindFirstChildOfClass(className)
		if existing then
			existing:Destroy()
		end
		local src = source:FindFirstChildOfClass(className)
		if src then
			src:Clone().Parent = target
		end
	end
	copyClass("Shirt")
	copyClass("Pants")
	copyClass("ShirtGraphic")
	copyClass("BodyColors")

	for _, c in ipairs(target:GetChildren()) do
		if c:IsA("Accessory") or c:IsA("Hat") then
			c:Destroy()
		end
	end
	for _, c in ipairs(source:GetChildren()) do
		if c:IsA("Accessory") or c:IsA("Hat") then
			pcall(function()
				c:Clone().Parent = target
			end)
		end
	end
end

local function freezeModel(model: Model)
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	root.Anchored = true
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			local hasWeld = false
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("WeldConstraint") and (c.Part0 == root or c.Part1 == root) then
					hasWeld = true
					break
				end
			end
			if not hasWeld then
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
	model:SetAttribute("HomeCFrame", root.CFrame)
end

local function getBestDescription(host: Player): (HumanoidDescription?, Enum.HumanoidRigType)
	local char = host.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local rigType = (hum and hum.RigType) or Enum.HumanoidRigType.R15

	local fromCatalog = nil
	local okC, catalog = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(host.UserId)
	end)
	if okC then
		fromCatalog = catalog
	end

	local fromApplied = nil
	if hum then
		local okA, applied = pcall(function()
			return hum:GetAppliedDescription()
		end)
		if okA then
			fromApplied = applied
		end
	end

	if fromCatalog and fromApplied then
		return mergeDescriptions(fromCatalog, fromApplied), rigType
	end
	return fromCatalog or fromApplied, rigType
end

function AvatarClone.Create(hostPlayer: Player, slotIndex: number, facingCF: CFrame, stats): Model?
	local desc, rigType = getBestDescription(hostPlayer)
	if not desc then
		Log.Write("Bot", "Avatar clone FAILED: no description for " .. hostPlayer.Name, "ERROR")
		return nil
	end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, rigType)
	end)
	if not ok or not model then
		local other = if rigType == Enum.HumanoidRigType.R15 then Enum.HumanoidRigType.R6 else Enum.HumanoidRigType.R15
		ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, other)
		end)
	end
	if not ok or not model then
		Log.Write("Bot", "Avatar CreateHumanoidModel failed", "ERROR")
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
	model.Parent = squad

	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = root

	if hum then
		pcall(function()
			hum:ApplyDescription(desc)
		end)
		task.wait(0.15)
		pcall(function()
			hum:ApplyDescription(desc)
		end)
	end

	if hostPlayer.Character then
		transferLiveAppearance(hostPlayer.Character, model)
	end

	local spawnCF = facingCF
	if hum and hum.RigType == Enum.HumanoidRigType.R15 then
		spawnCF = facingCF + Vector3.new(0, math.max(0, (hum.HipHeight or 2) - 1.65), 0)
	end
	model:PivotTo(spawnCF)

	CharacterRigBuilder.AttachWeapon(model, stats.WeaponType or "Rifle")
	freezeModel(model)

	local displayName = string.format("%s | %s", hostPlayer.DisplayName, stats.WeaponType or "Rifle")
	CharacterRigBuilder.CreateHealthBar(model, displayName, stats.MaxHP, stats.MaxHP)

	task.delay(0.6, function()
		if model.Parent and hostPlayer.Character then
			transferLiveAppearance(hostPlayer.Character, model)
			freezeModel(model)
		end
	end)

	local accessories = 0
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Accessory") or c:IsA("Hat") then
			accessories += 1
		end
	end
	Log.Write(
		"Bot",
		string.format(
			"Avatar bot slot %d pants=%s shirt=%s accessories=%d",
			slotIndex,
			tostring(model:FindFirstChildOfClass("Pants") ~= nil),
			tostring(model:FindFirstChildOfClass("Shirt") ~= nil),
			accessories
		)
	)
	return model
end

return AvatarClone
