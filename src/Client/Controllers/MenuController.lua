local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared.Remotes.RemoteNames)
local WeaponsConfig = require(Shared.Config.WeaponsConfig)
local ArmorConfig = require(Shared.Config.ArmorConfig)
local UpgradesConfig = require(Shared.Config.UpgradesConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Util = require(Shared.Util.Util)
local StatCalculator = require(Shared.Util.StatCalculator)
local MenuBridge = require(Shared.Util.MenuBridge)
local ModalManager = require(script.Parent.ModalManager)
local UIController = require(script.Parent.UIController)

local MenuController = {}
local player = Players.LocalPlayer
local remotes
local profile
local ui
local content

local function invoke(name, ...)
	local r = remotes and remotes:FindFirstChild(name)
	if r and r:IsA("RemoteFunction") then
		local ok, res = pcall(function(...)
			return r:InvokeServer(...)
		end, ...)
		if ok then
			return res
		end
	end
	return nil
end

local function clearContent()
	if not content then
		return
	end
	for _, c in ipairs(content:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function updateCanvasSize()
	if not content or not content:IsA("ScrollingFrame") then
		return
	end
	local layout = content:FindFirstChildOfClass("UIListLayout")
	if layout then
		content.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
	end
end

local function addLabel(text, order, color)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 28)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or Color3.fromRGB(230, 230, 240)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.LayoutOrder = order
	l.Parent = content
	return l
end

local function showShop()
	clearContent()
	addLabel("МАГАЗИН ОРУЖИЯ", 1, Color3.fromRGB(255, 215, 80))
	addLabel("Золото: " .. tostring(profile and profile.Gold or 0), 2, Color3.fromRGB(255, 215, 80))

	local order = 3
	local playerGold = profile and profile.Gold or 0
	local currentWeapon = profile and profile.SquadLoadout and profile.SquadLoadout[1]
	local currentWeaponType = currentWeapon and currentWeapon.WeaponType or "Pistol"
	local currentWeaponTier = currentWeapon and currentWeapon.Tier or 1

	for _, wType in ipairs(WeaponsConfig.Types) do
		local typeLabel = Instance.new("TextLabel")
		typeLabel.Size = UDim2.new(1, 0, 0, 24)
		typeLabel.BackgroundColor3 = Color3.fromRGB(35, 38, 55)
		typeLabel.Text = "  " .. wType
		typeLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
		typeLabel.Font = Enum.Font.GothamBold
		typeLabel.TextSize = 14
		typeLabel.TextXAlignment = Enum.TextXAlignment.Left
		typeLabel.LayoutOrder = order
		typeLabel.Parent = content
		local tlCorner = Instance.new("UICorner")
		tlCorner.CornerRadius = UDim.new(0, 6)
		tlCorner.Parent = typeLabel
		order += 1

		for tier = 1, 5 do
			local w = WeaponsConfig.Weapons[wType] and WeaponsConfig.Weapons[wType][tier]
			if w then
				local owned = profile and profile.OwnedWeapons and (profile.OwnedWeapons[wType] or 0) or 0
				local isOwned = owned >= tier
				local isEquipped = currentWeaponType == wType and currentWeaponTier == tier
				local canAfford = playerGold >= (w.GoldCost or 0)
				local dps = math.floor(w.Damage / math.max(w.FireRate, 0.01))

				local card = Instance.new("Frame")
				card.Size = UDim2.new(1, 0, 0, 68)
				card.BackgroundColor3 = isEquipped and Color3.fromRGB(25, 50, 80) or Color3.fromRGB(28, 30, 42)
				card.BorderSizePixel = 0
				card.LayoutOrder = order
				card.Parent = content
				local cardCorner = Instance.new("UICorner")
				cardCorner.CornerRadius = UDim.new(0, 8)
				cardCorner.Parent = card
				local cardStroke = Instance.new("UIStroke")
				cardStroke.Color = isEquipped and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(50, 55, 70)
				cardStroke.Thickness = isEquipped and 2 or 1
				cardStroke.Parent = card

				local stars = string.rep("*", tier) .. string.rep("-", 5 - tier)
				local starsLabel = Instance.new("TextLabel")
				starsLabel.Size = UDim2.new(0, 120, 0, 16)
				starsLabel.Position = UDim2.new(0, 8, 0, 4)
				starsLabel.BackgroundTransparency = 1
				starsLabel.Text = stars
				starsLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
				starsLabel.Font = Enum.Font.Gotham
				starsLabel.TextSize = 12
				starsLabel.TextXAlignment = Enum.TextXAlignment.Left
				starsLabel.Parent = card

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Size = UDim2.new(0.5, 0, 0, 20)
				nameLabel.Position = UDim2.new(0, 8, 0, 20)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Text = w.Name
				nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextSize = 14
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.Parent = card

				local statsLabel = Instance.new("TextLabel")
				statsLabel.Size = UDim2.new(0.65, 0, 0, 16)
				statsLabel.Position = UDim2.new(0, 8, 0, 42)
				statsLabel.BackgroundTransparency = 1
				statsLabel.Text = string.format("DMG:%d | RPM:%.0f | DPS:%d | ACC:%.0f%%", w.Damage, 60 / w.FireRate, dps, w.Accuracy * 100)
				statsLabel.TextColor3 = Color3.fromRGB(160, 165, 180)
				statsLabel.Font = Enum.Font.Gotham
				statsLabel.TextSize = 11
				statsLabel.TextXAlignment = Enum.TextXAlignment.Left
				statsLabel.Parent = card

				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(0, 110, 0, 30)
				btn.Position = UDim2.new(1, -120, 1, -38)
				btn.BorderSizePixel = 0
				btn.Font = Enum.Font.GothamBold
				btn.TextSize = 12
				btn.Parent = card
				local btnCorner = Instance.new("UICorner")
				btnCorner.CornerRadius = UDim.new(0, 6)
				btnCorner.Parent = btn

				if isEquipped then
					btn.BackgroundColor3 = Color3.fromRGB(60, 200, 120)
					btn.Text = "Equipped"
					btn.TextColor3 = Color3.new(1, 1, 1)
				elseif isOwned then
					btn.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
					btn.Text = "Equip"
					btn.TextColor3 = Color3.new(1, 1, 1)
					btn.MouseButton1Click:Connect(function()
						invoke(RemoteNames.SetSquadLoadout, 1, wType, tier)
						task.wait(0.25)
						profile = invoke(RemoteNames.GetProfile)
						showShop()
						task.defer(updateCanvasSize)
					end)
				elseif canAfford then
					btn.BackgroundColor3 = Color3.fromRGB(255, 180, 50)
					btn.Text = tostring(w.GoldCost) .. "G"
					btn.TextColor3 = Color3.fromRGB(30, 30, 30)
					btn.MouseButton1Click:Connect(function()
						invoke(RemoteNames.BuyWeapon, wType, tier)
						task.wait(0.25)
						profile = invoke(RemoteNames.GetProfile)
						showShop()
						task.defer(updateCanvasSize)
					end)
				else
					btn.BackgroundColor3 = Color3.fromRGB(50, 52, 60)
					btn.Text = tostring(w.GoldCost) .. "G"
					btn.TextColor3 = Color3.fromRGB(120, 120, 130)
				end
				order += 1
			end
		end
	end
	task.defer(updateCanvasSize)
end

local function showArmor()
	clearContent()
	addLabel("БРОНЯ", 1, Color3.fromRGB(180, 200, 255))
	local order = 2
	for _, a in ipairs(ArmorConfig.List) do
		local owned = profile and profile.OwnedArmor and profile.OwnedArmor[a.Id]
		local equipped = profile and profile.EquippedArmor == a.Id
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 56)
		card.BackgroundColor3 = equipped and Color3.fromRGB(25, 50, 80) or Color3.fromRGB(28, 30, 42)
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = content
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 8)
		cc.Parent = card

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.55, 0, 1, 0)
		name.Position = UDim2.new(0, 10, 0, 0)
		name.BackgroundTransparency = 1
		name.Text = string.format("%s (Armor %d)", a.Name, a.Armor)
		name.TextColor3 = Color3.fromRGB(230, 230, 240)
		name.Font = Enum.Font.Gotham
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = card

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 100, 0, 28)
		btn.Position = UDim2.new(1, -110, 0.5, -14)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.Parent = card
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 6)
		bc.Parent = btn

		if equipped then
			btn.Text = "Equipped"
			btn.BackgroundColor3 = Color3.fromRGB(60, 200, 120)
		elseif owned then
			btn.Text = "Equip"
			btn.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
			btn.MouseButton1Click:Connect(function()
				invoke(RemoteNames.EquipArmor, a.Id)
				task.wait(0.2)
				profile = invoke(RemoteNames.GetProfile)
				showArmor()
			end)
		else
			btn.Text = tostring(a.GoldCost) .. "G"
			btn.BackgroundColor3 = Color3.fromRGB(255, 180, 50)
			btn.MouseButton1Click:Connect(function()
				invoke(RemoteNames.BuyArmor, a.Id)
				task.wait(0.2)
				profile = invoke(RemoteNames.GetProfile)
				showArmor()
			end)
		end
		order += 1
	end
	task.defer(updateCanvasSize)
end

local function showUpgrade()
	clearContent()
	addLabel("ПРОКАЧКА", 1, Color3.fromRGB(120, 200, 255))
	local currentXP = profile and profile.XP or 0
	local level, intoXP, needXP = Util.XPProgressInLevel(currentXP, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	addLabel(string.format("Уровень %d (%d/%d XP)", level, intoXP, needXP), 2, Color3.fromRGB(180, 180, 200))
	addLabel("XP: " .. tostring(currentXP), 3, Color3.fromRGB(120, 200, 255))

	local xpBarBg = Instance.new("Frame")
	xpBarBg.Size = UDim2.new(1, 0, 0, 10)
	xpBarBg.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
	xpBarBg.BorderSizePixel = 0
	xpBarBg.LayoutOrder = 4
	xpBarBg.Parent = content
	local xpBarCorner = Instance.new("UICorner")
	xpBarCorner.CornerRadius = UDim.new(0, 5)
	xpBarCorner.Parent = xpBarBg
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(math.clamp(intoXP / math.max(needXP, 1), 0, 1), 0, 1, 0)
	xpFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBarBg
	local xpFillCorner = Instance.new("UICorner")
	xpFillCorner.CornerRadius = UDim.new(0, 5)
	xpFillCorner.Parent = xpFill

	local order = 5
	local upgrades = profile and profile.Upgrades or {}
	for statName, cfg in pairs(UpgradesConfig.Stats) do
		local levelStat = upgrades[statName] or 0
		local nextCost = StatCalculator.GetUpgradeCost(statName, levelStat)
		local isMaxed = levelStat >= (cfg.MaxLevel or 50)
		local canAfford = currentXP >= nextCost and nextCost < math.huge

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 90)
		card.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = content
		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 8)
		cardCorner.Parent = card

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.7, 0, 0, 20)
		nameLabel.Position = UDim2.new(0, 12, 0, 8)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = (cfg.Name or statName) .. "  Lv." .. levelStat .. "/" .. tostring(cfg.MaxLevel or 50)
		nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 14
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -24, 0, 8)
		barBg.Position = UDim2.new(0, 12, 0, 34)
		barBg.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
		barBg.BorderSizePixel = 0
		barBg.Parent = card
		local bbCorner = Instance.new("UICorner")
		bbCorner.CornerRadius = UDim.new(0, 4)
		bbCorner.Parent = barBg
		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(math.clamp(levelStat / math.max(cfg.MaxLevel or 50, 1), 0, 1), 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		local bfCorner = Instance.new("UICorner")
		bfCorner.CornerRadius = UDim.new(0, 4)
		bfCorner.Parent = barFill

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -24, 0, 30)
		btn.Position = UDim2.new(0, 12, 1, -36)
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.Parent = card
		local btnCorner2 = Instance.new("UICorner")
		btnCorner2.CornerRadius = UDim.new(0, 6)
		btnCorner2.Parent = btn

		if isMaxed then
			btn.BackgroundColor3 = Color3.fromRGB(60, 200, 120)
			btn.Text = "MAX"
			btn.TextColor3 = Color3.new(1, 1, 1)
		elseif canAfford then
			btn.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
			btn.Text = "Upgrade " .. tostring(nextCost) .. " XP"
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.MouseButton1Click:Connect(function()
				invoke(RemoteNames.UpgradeStat, statName)
				task.wait(0.25)
				profile = invoke(RemoteNames.GetProfile)
				showUpgrade()
			end)
		else
			btn.BackgroundColor3 = Color3.fromRGB(50, 52, 60)
			btn.Text = "Need " .. tostring(nextCost) .. " XP"
			btn.TextColor3 = Color3.fromRGB(120, 120, 130)
		end
		order += 1
	end
	task.defer(updateCanvasSize)
end

local function showUnits()
	clearContent()
	addLabel("ОТРЯД (слоты 1-4)", 1)
	local order = 2
	for slot = 1, 4 do
		local load = profile and profile.SquadLoadout and profile.SquadLoadout[slot]
		local wType = load and load.WeaponType or "Pistol"
		local tier = load and load.Tier or 1
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 70)
		card.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = content
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 8)
		cc.Parent = card
		local info = Instance.new("TextLabel")
		info.Size = UDim2.new(1, -16, 0, 22)
		info.Position = UDim2.new(0, 8, 0, 6)
		info.BackgroundTransparency = 1
		info.Text = string.format("Слот %d: %s T%d", slot, wType, tier)
		info.TextColor3 = Color3.fromRGB(230, 230, 240)
		info.Font = Enum.Font.GothamBold
		info.TextSize = 14
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.Parent = card

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -16, 0, 28)
		row.Position = UDim2.new(0, 8, 0, 34)
		row.BackgroundTransparency = 1
		row.Parent = card
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 4)
		layout.Parent = row
		for _, wt in ipairs(WeaponsConfig.Types) do
			local owned = profile and profile.OwnedWeapons and (profile.OwnedWeapons[wt] or 0) or 0
			if owned > 0 then
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(0, 70, 1, 0)
				b.Text = wt
				b.Font = Enum.Font.Gotham
				b.TextSize = 11
				b.BackgroundColor3 = wType == wt and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(45, 48, 60)
				b.TextColor3 = Color3.new(1, 1, 1)
				b.Parent = row
				local bc = Instance.new("UICorner")
				bc.CornerRadius = UDim.new(0, 4)
				bc.Parent = b
				b.MouseButton1Click:Connect(function()
					invoke(RemoteNames.SetSquadLoadout, slot, wt, math.min(owned, 5))
					task.wait(0.2)
					profile = invoke(RemoteNames.GetProfile)
					showUnits()
				end)
			end
		end
		order += 1
	end
	task.defer(updateCanvasSize)
end

local function showDaily()
	clearContent()
	addLabel("ЕЖЕДНЕВНАЯ НАГРАДА", 1)
	local r = invoke(RemoteNames.ClaimDailyReward)
	if r and r.ok then
		addLabel("+" .. tostring(r.gold or 0) .. " золота", 2, Color3.fromRGB(60, 200, 120))
	else
		addLabel(r and r.error or "Уже получено / ошибка", 2, Color3.fromRGB(255, 180, 50))
	end
	profile = invoke(RemoteNames.GetProfile)
	task.defer(updateCanvasSize)
end

local function showPromo()
	clearContent()
	addLabel("ПРОМОКОД", 1, Color3.fromRGB(255, 180, 50))
	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, 0, 0, 36)
	desc.BackgroundTransparency = 1
	desc.Text = "Введите промокод со стрима"
	desc.TextColor3 = Color3.fromRGB(160, 165, 180)
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 13
	desc.TextWrapped = true
	desc.LayoutOrder = 2
	desc.Parent = content

	local inputBg = Instance.new("Frame")
	inputBg.Size = UDim2.new(1, 0, 0, 40)
	inputBg.BackgroundColor3 = Color3.fromRGB(40, 42, 55)
	inputBg.BorderSizePixel = 0
	inputBg.LayoutOrder = 3
	inputBg.Parent = content
	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 8)
	inputCorner.Parent = inputBg
	local inputStroke = Instance.new("UIStroke")
	inputStroke.Color = Color3.fromRGB(60, 65, 85)
	inputStroke.Thickness = 1
	inputStroke.Parent = inputBg

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -20, 1, 0)
	box.Position = UDim2.new(0, 10, 0, 0)
	box.BackgroundTransparency = 1
	box.PlaceholderText = "CODE..."
	box.PlaceholderColor3 = Color3.fromRGB(100, 105, 120)
	box.Text = ""
	box.TextColor3 = Color3.new(1, 1, 1)
	box.Font = Enum.Font.GothamBold
	box.TextSize = 16
	box.ClearTextOnFocus = false
	box.Parent = inputBg

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Size = UDim2.new(1, 0, 0, 24)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Text = ""
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.TextSize = 14
	resultLabel.LayoutOrder = 5
	resultLabel.Parent = content

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 40)
	btn.BackgroundColor3 = Color3.fromRGB(255, 180, 50)
	btn.Text = "Activate"
	btn.TextColor3 = Color3.fromRGB(30, 30, 30)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.BorderSizePixel = 0
	btn.LayoutOrder = 4
	btn.Parent = content
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		local code = string.match(box.Text, "^%s*(.-)%s*$") or ""
		if code == "" then
			resultLabel.Text = "Enter a code"
			resultLabel.TextColor3 = Color3.fromRGB(255, 180, 50)
			return
		end
		btn.Text = "..."
		local r = invoke(RemoteNames.RedeemPromocode, code)
		if r and (r.ok or r.success) then
			resultLabel.Text = r.message or "OK"
			resultLabel.TextColor3 = Color3.fromRGB(60, 200, 120)
			profile = invoke(RemoteNames.GetProfile)
		else
			resultLabel.Text = (r and (r.error or r.message)) or "Invalid"
			resultLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
		end
		btn.Text = "Activate"
	end)
	box.Focused:Connect(function()
		inputStroke.Color = Color3.fromRGB(255, 180, 50)
	end)
	box.FocusLost:Connect(function()
		inputStroke.Color = Color3.fromRGB(60, 65, 85)
	end)
	task.defer(updateCanvasSize)
end

local function showLeaderboard()
	clearContent()
	addLabel("ЛИДЕРБОРД", 1, Color3.fromRGB(255, 215, 80))
	local colHeader = Instance.new("TextLabel")
	colHeader.Size = UDim2.new(1, 0, 0, 22)
	colHeader.BackgroundColor3 = Color3.fromRGB(35, 38, 55)
	colHeader.Text = "  #   Name              XP         Wave"
	colHeader.TextColor3 = Color3.fromRGB(160, 165, 180)
	colHeader.Font = Enum.Font.Gotham
	colHeader.TextSize = 12
	colHeader.TextXAlignment = Enum.TextXAlignment.Left
	colHeader.LayoutOrder = 2
	colHeader.Parent = content
	local colCorner = Instance.new("UICorner")
	colCorner.CornerRadius = UDim.new(0, 6)
	colCorner.Parent = colHeader

	local r = invoke(RemoteNames.GetLeaderboard, "XP")
	local order = 3
	if r and r.entries then
		for rank, e in ipairs(r.entries) do
			local rowColor = Color3.fromRGB(28, 30, 42)
			local prefix = ""
			if rank == 1 then
				rowColor = Color3.fromRGB(50, 42, 20)
				prefix = "#1 "
			elseif rank == 2 then
				rowColor = Color3.fromRGB(40, 40, 45)
				prefix = "#2 "
			elseif rank == 3 then
				rowColor = Color3.fromRGB(42, 35, 28)
				prefix = "#3 "
			end
			if e.UserId == player.UserId then
				rowColor = Color3.fromRGB(25, 40, 70)
				prefix = prefix .. "> "
			end
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundColor3 = rowColor
			row.Text = string.format("  %s%d  %s  %d  W%d", prefix, rank, tostring(e.Name or e.UserId), e.Value or 0, e.Wave or 0)
			row.TextColor3 = Color3.fromRGB(230, 230, 240)
			row.Font = Enum.Font.Gotham
			row.TextSize = 12
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.LayoutOrder = order
			row.Parent = content
			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 4)
			rowCorner.Parent = row
			order += 1
		end
	else
		addLabel("Пока нет данных", 3, Color3.fromRGB(100, 105, 120))
	end
	task.defer(updateCanvasSize)
end

local TAB_TITLES = {
	Shop = "Магазин",
	Armor = "Броня",
	Upgrade = "Прокачка",
	Units = "Отряд",
	Daily = "Ежедневка",
	Promo = "Промокод",
	Leaderboard = "Лидерборд",
}

function MenuController.OpenTab(tab)
	profile = invoke(RemoteNames.GetProfile) or profile
	ModalManager.Open({
		Title = TAB_TITLES[tab] or tab,
		Size = UDim2.new(0.5, 0, 0.7, 0),
		Content = function(scroll)
			content = scroll
			if not scroll:FindFirstChildOfClass("UIListLayout") then
				local layout = Instance.new("UIListLayout")
				layout.Padding = UDim.new(0, 6)
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Parent = scroll
			end
			if tab == "Shop" then
				showShop()
			elseif tab == "Armor" then
				showArmor()
			elseif tab == "Upgrade" then
				showUpgrade()
			elseif tab == "Units" then
				showUnits()
			elseif tab == "Daily" then
				showDaily()
			elseif tab == "Promo" then
				showPromo()
			elseif tab == "Leaderboard" then
				showLeaderboard()
			else
				showShop()
			end
		end,
	})
end

function MenuController:Init(deps)
	deps = deps or {}
	remotes = deps.Remotes or ReplicatedStorage:WaitForChild("Remotes", 15)
	ui = deps.UI or UIController.ScreenGui
	if not ui then
		UIController:Init()
		ui = UIController.ScreenGui
	end
	ModalManager.Init(ui)
	MenuBridge.SetHandler(function(tab)
		MenuController.OpenTab(tab)
	end)

	local profileEvt = remotes and remotes:FindFirstChild(RemoteNames.ProfileUpdated)
	if profileEvt then
		profileEvt.OnClientEvent:Connect(function(p)
			profile = p
			UIController.UpdateHUD(p)
		end)
	end
	task.spawn(function()
		profile = invoke(RemoteNames.GetProfile)
		if profile then
			UIController.UpdateHUD(profile)
		end
	end)
end

return MenuController
