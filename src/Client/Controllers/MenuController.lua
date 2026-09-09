local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared.Remotes.RemoteNames)
local WeaponsConfig = require(Shared.Config.WeaponsConfig)
local ArmorConfig = require(Shared.Config.ArmorConfig)
local UpgradesConfig = require(Shared.Config.UpgradesConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Util = require(Shared.Util.Util)
local Format = require(Shared.Util.Format)
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
local activeTab: string? = nil
local shopWeaponTab: string = "Pistol"
local inited = false
local dailyResult = nil

local WEAPON_TAB_LABELS = {
	Pistol = "Пистолет",
	Revolver = "Револьвер",
	SMG = "ПП",
	Rifle = "Автомат",
	Shotgun = "Дробовик",
	LMG = "Пулемёт",
	Sniper = "Снайпер",
	Crossbow = "Арбалет",
}

local function getWeaponCopies(p, wType, tier): number
	local byType = p and p.WeaponCopies and p.WeaponCopies[wType]
	if not byType then
		return 0
	end
	return tonumber(byType[tier]) or tonumber(byType[tostring(tier)]) or 0
end

local function getArmorCopies(p, tier): number
	local ac = p and p.ArmorCopies
	if not ac then
		return 0
	end
	return tonumber(ac[tier]) or tonumber(ac[tostring(tier)]) or 0
end

local function countEquippedWeaponUI(p, wType, tier): number
	local n = 0
	for _, load in pairs((p and p.SquadLoadout) or {}) do
		if type(load) == "table" and load.WeaponType == wType and (load.Tier or 1) == tier then
			n += 1
		end
	end
	return n
end

local function countEquippedArmorUI(p, tier): number
	local n = 0
	for _, t in pairs((p and p.SquadArmor) or {}) do
		if (tonumber(t) or 0) == tier then
			n += 1
		end
	end
	return n
end

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
	if not content or not content.Parent then
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

local function refreshProfileAndHUD(forcedProfile)
	if forcedProfile then
		profile = forcedProfile
	else
		profile = invoke(RemoteNames.GetProfile) or profile
	end
	if profile then
		UIController.UpdateHUD(profile, true)
	end
	return profile
end

-- Перерисовать открытую вкладку. Важно: НЕ из потока клика по кнопке,
-- которую clearContent уничтожит (Roblox отменяет такой поток).
local function bindContentFromModal()
	local scroll = ModalManager.GetScroll()
	if scroll then
		content = scroll
		return true
	end
	return content ~= nil and content.Parent ~= nil
end

local refreshOpenTab -- forward decl for mutual refs with show*

local function afterShopAction(res)
	if res and res.profile then
		refreshProfileAndHUD(res.profile)
	else
		refreshProfileAndHUD()
	end
	refreshOpenTab()
end

-- Запуск действия вне Click-потока кнопки
local function runMenuAction(fn)
	task.spawn(function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[MenuController] action failed:", err)
		end
	end)
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

local WeaponBuilder = require(Shared.Builders.WeaponBuilder)

-- Live tactical weapon render. This avoids placeholder emoji and does not
-- require separately uploaded Roblox image asset IDs.
local function makeItemIcon(parent, opts)
	local box = Instance.new("Frame")
	box.Size = opts.Size or UDim2.new(0, 64, 0, 64)
	box.Position = opts.Position or UDim2.new(0, 10, 0.5, -32)
	box.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	box.BorderSizePixel = 0
	box.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = box
	local s = Instance.new("UIStroke")
	s.Color = opts.StrokeColor or Color3.fromRGB(60, 70, 100)
	s.Thickness = 2
	s.Parent = box

	if opts.Use3D and opts.WeaponType and WeaponBuilder and WeaponBuilder.Create then
		local ok, model = pcall(function()
			return WeaponBuilder.Create(opts.WeaponType, opts.Tier)
		end)
		if ok and model and model:IsA("Model") then
			local vp = Instance.new("ViewportFrame")
			vp.Size = UDim2.new(1, -6, 1, -6)
			vp.Position = UDim2.new(0, 3, 0, 3)
			vp.BackgroundTransparency = 1
			vp.Ambient = Color3.new(1, 1, 1)
			vp.LightColor = Color3.new(1, 1, 1)
			vp.Parent = box
			local cam = Instance.new("Camera")
			cam.Parent = vp
			vp.CurrentCamera = cam
			model.Parent = vp
			local cf, size = model:GetBoundingBox()
			local dist = math.max(size.Magnitude * 0.82, 2)
			-- Fixed three-quarter side view, like a survival-shooter inventory icon.
			cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist, dist * 0.28, dist * 0.12), cf.Position)
			return box
		end
	end

	if opts.Image and opts.Image ~= "rbxassetid://0" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(1, -8, 1, -8)
		img.Position = UDim2.new(0, 4, 0, 4)
		img.BackgroundTransparency = 1
		img.Image = opts.Image
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = box
		return box
	end

	local em = Instance.new("TextLabel")
	em.Size = UDim2.new(1, 0, 1, 0)
	em.BackgroundTransparency = 1
	em.Text = opts.Emoji or "?"
	em.TextSize = 34
	em.Font = Enum.Font.Gotham
	em.Parent = box
	return box
end

local function showShop()
	clearContent()
	addLabel("МАГАЗИН ОРУЖИЯ", 1, Color3.fromRGB(255, 215, 80))
	addLabel("1 покупка = 1 единица на 1 слот. Золото: " .. Format.Number(profile and profile.Gold or 0), 2, Color3.fromRGB(255, 215, 80))

	local order = 3
	local playerGold = profile and profile.Gold or 0

	-- Вкладки по типу оружия
	local tabRow = Instance.new("Frame")
	tabRow.Size = UDim2.new(1, 0, 0, 34)
	tabRow.BackgroundTransparency = 1
	tabRow.LayoutOrder = order
	tabRow.Parent = content
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.Parent = tabRow
	order += 1

	if not table.find(WeaponsConfig.Types, shopWeaponTab) then
		shopWeaponTab = WeaponsConfig.Types[1] or "Pistol"
	end

	for _, wType in ipairs(WeaponsConfig.Types) do
		local tab = Instance.new("TextButton")
		tab.Size = UDim2.new(0, 72, 1, 0)
		tab.BackgroundColor3 = shopWeaponTab == wType and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(40, 44, 58)
		tab.Text = WEAPON_TAB_LABELS[wType] or wType
		tab.TextColor3 = Color3.new(1, 1, 1)
		tab.Font = Enum.Font.GothamBold
		tab.TextSize = 11
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = true
		tab.Parent = tabRow
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(0, 6)
		tc.Parent = tab
		tab.MouseButton1Click:Connect(function()
			local wt = wType
			runMenuAction(function()
				shopWeaponTab = wt
				showShop()
			end)
		end)
	end

	local wType = shopWeaponTab
	for tier = 1, (WeaponsConfig.MaxTier or 5) do
		local w = WeaponsConfig.Weapons[wType] and WeaponsConfig.Weapons[wType][tier]
		if w then
			local unlockedMax = profile and profile.OwnedWeapons and (profile.OwnedWeapons[wType] or 0) or 0
			local copies = getWeaponCopies(profile, wType, tier)
			local equippedN = countEquippedWeaponUI(profile, wType, tier)
			local freeCopies = copies - equippedN
			local canBuyNext = unlockedMax >= tier - 1
			local canAfford = playerGold >= (w.GoldCost or 0)
			local prestigeReq = WeaponsConfig.GetPrestigeRequired(tier)
			local prestigePoints = profile and profile.PrestigePoints or 0
			local prestigeLocked = prestigePoints < prestigeReq
			local dps = math.floor(w.Damage / math.max(w.FireRate, 0.01))

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 84)
			card.BackgroundColor3 = freeCopies > 0 and Color3.fromRGB(25, 50, 80) or Color3.fromRGB(28, 30, 42)
			card.BorderSizePixel = 0
			card.LayoutOrder = order
			card.Parent = content
			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 6)
			cardCorner.Parent = card
			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = freeCopies > 0 and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(50, 55, 70)
			cardStroke.Thickness = freeCopies > 0 and 2 or 1
			cardStroke.Parent = card

			local iconCfg = WeaponsConfig.Icons and WeaponsConfig.Icons[wType] or {}
			makeItemIcon(card, {
				WeaponType = wType,
				Tier = tier,
				Use3D = true,
				Image = iconCfg.Image,
				Emoji = iconCfg.Emoji,
				StrokeColor = (WeaponsConfig.TierColors and WeaponsConfig.TierColors[tier]) or iconCfg.Color,
			})

			local stars = string.rep("*", math.min(tier, 5))
			if tier > 5 then
				stars = stars .. "+" .. (tier - 5)
			end
			local starsLabel = Instance.new("TextLabel")
			starsLabel.Size = UDim2.new(0, 120, 0, 16)
			starsLabel.Position = UDim2.new(0, 84, 0, 4)
			starsLabel.BackgroundTransparency = 1
			starsLabel.Text = stars .. string.format("  (x%d, свободно %d)", copies, math.max(0, freeCopies))
			starsLabel.TextColor3 = (WeaponsConfig.TierColors and WeaponsConfig.TierColors[tier])
				or Color3.fromRGB(255, 200, 50)
			starsLabel.Font = Enum.Font.Gotham
			starsLabel.TextSize = 12
			starsLabel.TextXAlignment = Enum.TextXAlignment.Left
			starsLabel.Parent = card

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.45, 0, 0, 20)
			nameLabel.Position = UDim2.new(0, 84, 0, 22)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = w.Name
			nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 14
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = card

			local statsLabel = Instance.new("TextLabel")
			statsLabel.Size = UDim2.new(0.55, 0, 0, 16)
			statsLabel.Position = UDim2.new(0, 84, 0, 48)
			statsLabel.BackgroundTransparency = 1
			statsLabel.Text = string.format("Урон:%d | Выстр/мин:%.0f | DPS:%d | Точн:%.0f%%", w.Damage, 60 / w.FireRate, dps, w.Accuracy * 100)
			statsLabel.TextColor3 = Color3.fromRGB(160, 165, 180)
			statsLabel.Font = Enum.Font.Gotham
			statsLabel.TextSize = 11
			statsLabel.TextXAlignment = Enum.TextXAlignment.Left
			statsLabel.Parent = card

			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 110, 0, 30)
			btn.Position = UDim2.new(1, -120, 0.5, -15)
			btn.BorderSizePixel = 0
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 12
			btn.Parent = card
			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 4)
			btnCorner.Parent = btn

			if prestigeLocked then
				btn.BackgroundColor3 = Color3.fromRGB(55, 35, 75)
				btn.Text = string.format("Престиж %d", prestigeReq)
				btn.TextColor3 = Color3.fromRGB(200, 160, 255)
			elseif not canBuyNext then
				btn.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
				btn.Text = "Тир " .. (tier - 1)
				btn.TextColor3 = Color3.fromRGB(120, 120, 130)
			elseif canAfford then
				btn.BackgroundColor3 = Color3.fromRGB(200, 150, 40)
				btn.Text = "Купить " .. Format.Number(w.GoldCost)
				btn.TextColor3 = Color3.fromRGB(30, 30, 30)
				btn.MouseButton1Click:Connect(function()
					local wt, t = wType, tier
					runMenuAction(function()
						local res = invoke(RemoteNames.BuyWeapon, wt, t)
						afterShopAction(res)
					end)
				end)
			else
				btn.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
				btn.Text = Format.Number(w.GoldCost) .. " зол."
				btn.TextColor3 = Color3.fromRGB(120, 120, 130)
			end

			if freeCopies > 0 then
				local eqBtn = Instance.new("TextButton")
				eqBtn.Size = UDim2.new(0, 90, 0, 24)
				eqBtn.Position = UDim2.new(1, -120, 1, -28)
				eqBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 220)
				eqBtn.Text = "В слот 1"
				eqBtn.TextColor3 = Color3.new(1, 1, 1)
				eqBtn.Font = Enum.Font.Gotham
				eqBtn.TextSize = 11
				eqBtn.BorderSizePixel = 0
				eqBtn.Parent = card
				local ec = Instance.new("UICorner")
				ec.CornerRadius = UDim.new(0, 4)
				ec.Parent = eqBtn
				eqBtn.MouseButton1Click:Connect(function()
					local wt, t = wType, tier
					runMenuAction(function()
						local res = invoke(RemoteNames.SetSquadLoadout, 1, wt, t)
						afterShopAction(res)
					end)
				end)
			end
			order += 1
		end
	end
	task.defer(updateCanvasSize)
end

local function showArmor()
	clearContent()
	local gold = profile and profile.Gold or 0
	local ownedTier = profile and profile.OwnedArmorTier or 0
	local squadArmor = profile and profile.SquadArmor or {}

	addLabel("БРОНЯ", 1, Color3.fromRGB(180, 200, 255))
	addLabel("1 покупка = 1 боец. Золото: " .. Format.Number(gold), 2, Color3.fromRGB(255, 215, 80))
	local slotTxt = {}
	for s = 1, 4 do
		local t = squadArmor[s] or 0
		local nm = (t > 0 and ArmorConfig.Tiers[t] and ArmorConfig.Tiers[t].Name) or "—"
		table.insert(slotTxt, string.format("%d:%s", s, nm))
	end
	addLabel("Слоты: " .. table.concat(slotTxt, " | "), 3, Color3.fromRGB(180, 190, 210))

	local order = 4
	for tier, a in ipairs(ArmorConfig.Tiers) do
		local copies = getArmorCopies(profile, tier)
		local equippedN = countEquippedArmorUI(profile, tier)
		local freeCopies = copies - equippedN
		local unlocked = ownedTier >= tier - 1
		local canAfford = gold >= a.GoldCost
		local classColor = (ArmorConfig.ClassColors and ArmorConfig.ClassColors[a.Class])
			or Color3.fromRGB(150, 150, 170)

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 84)
		card.BackgroundColor3 = freeCopies > 0 and Color3.fromRGB(25, 50, 80) or Color3.fromRGB(28, 30, 42)
		card.BackgroundTransparency = unlocked and 0 or 0.4
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = content
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 6)
		cc.Parent = card
		local cs = Instance.new("UIStroke")
		cs.Thickness = freeCopies > 0 and 2 or 1
		cs.Color = freeCopies > 0 and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(50, 55, 70)
		cs.Parent = card

		makeItemIcon(card, {
			Image = a.Icon,
			Emoji = a.Emoji or "🛡",
			StrokeColor = classColor,
		})

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.55, 0, 0, 22)
		name.Position = UDim2.new(0, 84, 0, 8)
		name.BackgroundTransparency = 1
		name.Text = a.Name .. "  [" .. tostring(a.Class or "") .. "]"
		name.TextColor3 = Color3.fromRGB(240, 240, 245)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = card

		local stat = Instance.new("TextLabel")
		stat.Size = UDim2.new(0.55, 0, 0, 18)
		stat.Position = UDim2.new(0, 84, 0, 32)
		stat.BackgroundTransparency = 1
		stat.Text = string.format("Броня %d  •  копии x%d (своб. %d)", a.Armor, copies, math.max(0, freeCopies))
		stat.TextColor3 = Color3.fromRGB(120, 200, 255)
		stat.Font = Enum.Font.Gotham
		stat.TextSize = 12
		stat.TextXAlignment = Enum.TextXAlignment.Left
		stat.Parent = card

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(0.55, 0, 0, 6)
		barBg.Position = UDim2.new(0, 84, 0, 56)
		barBg.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
		barBg.BorderSizePixel = 0
		barBg.Parent = card
		local bbc = Instance.new("UICorner")
		bbc.CornerRadius = UDim.new(0, 2)
		bbc.Parent = barBg
		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(a.Armor / 70, 0, 1, 0)
		fill.BackgroundColor3 = classColor
		fill.BorderSizePixel = 0
		fill.Parent = barBg
		local fc = Instance.new("UICorner")
		fc.CornerRadius = UDim.new(0, 2)
		fc.Parent = fill

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 110, 0, 32)
		btn.Position = UDim2.new(1, -120, 0.5, -16)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.BorderSizePixel = 0
		btn.Parent = card
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 4)
		bc.Parent = btn

		if not unlocked then
			btn.Text = "Тир " .. (tier - 1)
			btn.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
			btn.TextColor3 = Color3.fromRGB(120, 120, 130)
		elseif canAfford then
			btn.Text = "Купить " .. Format.Number(a.GoldCost)
			btn.BackgroundColor3 = Color3.fromRGB(200, 150, 40)
			btn.TextColor3 = Color3.fromRGB(30, 30, 30)
			btn.MouseButton1Click:Connect(function()
				local t = tier
				runMenuAction(function()
					local res = invoke(RemoteNames.BuyArmor, t)
					afterShopAction(res)
				end)
			end)
		else
			btn.Text = Format.Number(a.GoldCost) .. " зол."
			btn.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
			btn.TextColor3 = Color3.fromRGB(120, 120, 130)
		end

		if freeCopies > 0 then
			local eqBtn = Instance.new("TextButton")
			eqBtn.Size = UDim2.new(0, 90, 0, 22)
			eqBtn.Position = UDim2.new(1, -120, 1, -26)
			eqBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 220)
			eqBtn.Text = "На слот"
			eqBtn.TextColor3 = Color3.new(1, 1, 1)
			eqBtn.Font = Enum.Font.Gotham
			eqBtn.TextSize = 11
			eqBtn.BorderSizePixel = 0
			eqBtn.Parent = card
			local ec = Instance.new("UICorner")
			ec.CornerRadius = UDim.new(0, 4)
			ec.Parent = eqBtn
			eqBtn.MouseButton1Click:Connect(function()
				local t = tier
				runMenuAction(function()
					local empty = 1
					for s = 1, 4 do
						if (squadArmor[s] or 0) == 0 then
							empty = s
							break
						end
					end
					local res = invoke(RemoteNames.SetSquadArmor, empty, t)
					afterShopAction(res)
				end)
			end)
		end
		order += 1
	end
	task.defer(updateCanvasSize)
end

-- Порядок отображения статов (pairs не гарантирует порядок)
local STAT_ORDER = { "HP", "Accuracy", "ReloadSpeed", "CritChance", "CritDamage", "GoldGain", "XPGain", "BotDamage" }

local function formatStatValue(statName: string, value: number): string
	local cfg = UpgradesConfig.Stats[statName]
	if cfg and cfg.Format == "percent" then
		return string.format("%.1f%%", value * 100)
	elseif cfg and cfg.Format == "multiplier" then
		return string.format("x%.2f", value)
	end
	return Format.Number(value)
end

local function showUpgrade()
	clearContent()
	addLabel("ПРОКАЧКА", 1, Color3.fromRGB(120, 200, 255))
	local currentXP = profile and profile.XP or 0
	local totalXP = profile and profile.TotalXP or 0
	local level, intoXP, needXP =
		Util.XPProgressInLevel(totalXP, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	addLabel(string.format("Уровень %d (%s/%s XP)", level, Format.Number(intoXP), Format.Number(needXP)), 2, Color3.fromRGB(180, 180, 200))
	addLabel("Доступно для улучшений: " .. Format.Number(currentXP) .. " XP", 3, Color3.fromRGB(120, 200, 255))

	local xpBarBg = Instance.new("Frame")
	xpBarBg.Size = UDim2.new(1, 0, 0, 10)
	xpBarBg.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
	xpBarBg.BorderSizePixel = 0
	xpBarBg.LayoutOrder = 4
	xpBarBg.Parent = content
	local xpBarCorner = Instance.new("UICorner")
	xpBarCorner.CornerRadius = UDim.new(0, 3)
	xpBarCorner.Parent = xpBarBg
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(math.clamp(intoXP / math.max(needXP, 1), 0, 1), 0, 1, 0)
	xpFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBarBg
	local xpFillCorner = Instance.new("UICorner")
	xpFillCorner.CornerRadius = UDim.new(0, 3)
	xpFillCorner.Parent = xpFill

	local order = 5
	local upgrades = profile and profile.Upgrades or {}
	local prestigePoints = profile and profile.PrestigePoints or 0
	local ascensions = profile and profile.Ascensions or 0
	local totalUpgradeLevels = 0
	for statName, _cfg in pairs(UpgradesConfig.Stats) do
		totalUpgradeLevels += upgrades[statName] or 0
	end

	-- Карточка ВОЗНЕСЕНИЯ (второй слой сброса)
	if UpgradesConfig.Ascension.Enabled then
		local ascCost = UpgradesConfig.GetAscensionCost(ascensions)
		local canAscend = prestigePoints >= ascCost
		local ascCard = Instance.new("Frame")
		ascCard.Size = UDim2.new(1, 0, 0, 104)
		ascCard.BackgroundColor3 = Color3.fromRGB(35, 28, 15)
		ascCard.BorderSizePixel = 0
		ascCard.LayoutOrder = order
		ascCard.Parent = content
		local ac = Instance.new("UICorner")
		ac.CornerRadius = UDim.new(0, 6)
		ac.Parent = ascCard

		local al = Instance.new("TextLabel")
		al.Size = UDim2.new(1, -24, 0, 20)
		al.Position = UDim2.new(0, 12, 0, 8)
		al.BackgroundTransparency = 1
		al.Text = string.format("ВОЗНЕСЕНИЕ: %d ур.", ascensions)
		al.TextColor3 = Color3.fromRGB(255, 220, 130)
		al.Font = Enum.Font.GothamBold
		al.TextSize = 14
		al.TextXAlignment = Enum.TextXAlignment.Left
		al.Parent = ascCard

		local al2 = Instance.new("TextLabel")
		al2.Size = UDim2.new(1, -24, 0, 16)
		al2.Position = UDim2.new(0, 12, 0, 28)
		al2.BackgroundTransparency = 1
		al2.Text = string.format("Постоянный бонус: +%d%% к статам и доходу", math.floor(ascensions * UpgradesConfig.Ascension.StatBonusPerAscension * 100))
		al2.TextColor3 = Color3.fromRGB(240, 210, 160)
		al2.Font = Enum.Font.Gotham
		al2.TextSize = 12
		al2.TextXAlignment = Enum.TextXAlignment.Left
		al2.Parent = ascCard

		local ab = Instance.new("TextButton")
		ab.Size = UDim2.new(1, -24, 0, 34)
		ab.Position = UDim2.new(0, 12, 1, -42)
		ab.BorderSizePixel = 0
		ab.Font = Enum.Font.GothamBold
		ab.TextSize = 13
		ab.Parent = ascCard
		local abc = Instance.new("UICorner")
		abc.CornerRadius = UDim.new(0, 4)
		abc.Parent = ab
		if canAscend then
			ab.BackgroundColor3 = Color3.fromRGB(180, 130, 40)
			ab.Text = string.format("Вознестись: сжечь %d престижа → +25%% навсегда", ascCost)
			ab.TextColor3 = Color3.fromRGB(30, 20, 10)
			ab.MouseButton1Click:Connect(function()
				runMenuAction(function()
					local res = invoke(RemoteNames.Ascend)
					afterShopAction(res)
				end)
			end)
		else
			ab.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
			ab.Text = string.format("Нужно %d очков престижа (%d/%d)", ascCost, prestigePoints, ascCost)
			ab.TextColor3 = Color3.fromRGB(150, 150, 160)
		end
		order += 1
	end

	-- Тайкун-престиж: показываем, когда включено.
	if UpgradesConfig.Prestige.Enabled then
		local threshold = UpgradesConfig.GetPrestigeThreshold(prestigePoints)
		local canPrestige = totalUpgradeLevels >= threshold
		local statBonusPct = math.floor(prestigePoints * UpgradesConfig.Prestige.StatBonusPerPoint * 100)
		local incomeBonusPct = math.floor(prestigePoints * (UpgradesConfig.Prestige.IncomeBonusPerPoint or 0.05) * 100)
		local prestigeCard = Instance.new("Frame")
		prestigeCard.Size = UDim2.new(1, 0, 0, 104)
		prestigeCard.BackgroundColor3 = Color3.fromRGB(30, 22, 38)
		prestigeCard.BorderSizePixel = 0
		prestigeCard.LayoutOrder = order
		prestigeCard.Parent = content
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(0, 6)
		pc.Parent = prestigeCard

		local pl = Instance.new("TextLabel")
		pl.Size = UDim2.new(1, -24, 0, 20)
		pl.Position = UDim2.new(0, 12, 0, 8)
		pl.BackgroundTransparency = 1
		pl.Text = string.format("ПРЕСТИЖ: %d очков", prestigePoints)
		pl.TextColor3 = Color3.fromRGB(255, 200, 120)
		pl.Font = Enum.Font.GothamBold
		pl.TextSize = 14
		pl.TextXAlignment = Enum.TextXAlignment.Left
		pl.Parent = prestigeCard

		local pl2 = Instance.new("TextLabel")
		pl2.Size = UDim2.new(1, -24, 0, 16)
		pl2.Position = UDim2.new(0, 12, 0, 28)
		pl2.BackgroundTransparency = 1
		pl2.Text = string.format("Бонус: +%d%% к статам, +%d%% к доходу", statBonusPct, incomeBonusPct)
		pl2.TextColor3 = Color3.fromRGB(220, 180, 240)
		pl2.Font = Enum.Font.Gotham
		pl2.TextSize = 12
		pl2.TextXAlignment = Enum.TextXAlignment.Left
		pl2.Parent = prestigeCard

		local pb = Instance.new("TextButton")
		pb.Size = UDim2.new(1, -24, 0, 34)
		pb.Position = UDim2.new(0, 12, 1, -42)
		pb.BorderSizePixel = 0
		pb.Font = Enum.Font.GothamBold
		pb.TextSize = 13
		pb.Parent = prestigeCard
		local pbc = Instance.new("UICorner")
		pbc.CornerRadius = UDim.new(0, 4)
		pbc.Parent = pb
		if canPrestige then
			pb.BackgroundColor3 = Color3.fromRGB(130, 80, 180)
			pb.Text = string.format("Сбросить %d уровней → +%d престиж", totalUpgradeLevels, UpgradesConfig.Prestige.PointsPerReset)
			pb.MouseButton1Click:Connect(function()
				runMenuAction(function()
					local res = invoke(RemoteNames.PrestigeReset)
					afterShopAction(res)
				end)
			end)
		else
			pb.BackgroundColor3 = Color3.fromRGB(50, 52, 60)
			pb.Text = string.format("Нужно суммарно %d уровней (%d/%d)", threshold, totalUpgradeLevels, threshold)
			pb.TextColor3 = Color3.fromRGB(150, 150, 160)
		end
		order += 1
	end

	-- Статы: фиксированный порядок, замки по престижу, милстоуны, мульти-покупка
	for _, statName in ipairs(STAT_ORDER) do
		local cfg = UpgradesConfig.Stats[statName]
		if cfg then
			local levelStat = upgrades[statName] or 0
			local unlocked = UpgradesConfig.IsStatUnlocked(statName, prestigePoints)
			local nextCost = StatCalculator.GetUpgradeCost(statName, levelStat)
			local canAfford = currentXP >= nextCost and nextCost < math.huge
			local milestoneEvery = (UpgradesConfig.Milestones and UpgradesConfig.Milestones.Every) or 25
			local nextMilestone = (math.floor(levelStat / milestoneEvery) + 1) * milestoneEvery
			local toMilestone = nextMilestone - levelStat
			local milestoneProgress = (levelStat % milestoneEvery) / milestoneEvery
			local currentValue = StatCalculator.GetUpgradeStat(statName, levelStat, prestigePoints, ascensions)

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, -4, 0, unlocked and 112 or 58)
			card.BackgroundColor3 = unlocked and Color3.fromRGB(28, 30, 42) or Color3.fromRGB(22, 22, 30)
			card.BorderSizePixel = 0
			card.ClipsDescendants = true
			card.LayoutOrder = order
			card.Parent = content
			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 8)
			cardCorner.Parent = card

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.7, 0, 0, 20)
			nameLabel.Position = UDim2.new(0, 12, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = (cfg.Name or statName) .. "  Lv." .. levelStat
			nameLabel.TextColor3 = unlocked and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(110, 110, 125)
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 14
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = card

			if not unlocked then
				local lockLabel = Instance.new("TextLabel")
				lockLabel.Size = UDim2.new(1, -24, 0, 18)
				lockLabel.Position = UDim2.new(0, 12, 0, 32)
				lockLabel.BackgroundTransparency = 1
				lockLabel.Text = string.format("🔒 Откроется при престиже %d", cfg.UnlockPrestige or 0)
				lockLabel.TextColor3 = Color3.fromRGB(200, 160, 255)
				lockLabel.Font = Enum.Font.Gotham
				lockLabel.TextSize = 12
				lockLabel.TextXAlignment = Enum.TextXAlignment.Left
				lockLabel.Parent = card
			else
				-- Текущее значение эффекта
				local valueLabel = Instance.new("TextLabel")
				valueLabel.Size = UDim2.new(0.3, 0, 0, 20)
				valueLabel.Position = UDim2.new(0.7, 0, 0, 8)
				valueLabel.BackgroundTransparency = 1
				valueLabel.Text = formatStatValue(statName, currentValue)
				valueLabel.TextColor3 = Color3.fromRGB(140, 220, 160)
				valueLabel.Font = Enum.Font.GothamBold
				valueLabel.TextSize = 13
				valueLabel.TextXAlignment = Enum.TextXAlignment.Right
				valueLabel.Parent = card

				-- Полоска милстоуна: каждые 25 ур. эффект x2
				local barBg = Instance.new("Frame")
				barBg.Size = UDim2.new(1, -24, 0, 8)
				barBg.Position = UDim2.new(0, 12, 0, 34)
				barBg.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
				barBg.BorderSizePixel = 0
				barBg.Parent = card
				local bbCorner = Instance.new("UICorner")
				bbCorner.CornerRadius = UDim.new(0, 4)
				bbCorner.Parent = barBg
				local barFill = Instance.new("Frame")
				barFill.Size = UDim2.new(milestoneProgress, 0, 1, 0)
				barFill.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
				barFill.BorderSizePixel = 0
				barFill.Parent = barBg
				local bfCorner = Instance.new("UICorner")
				bfCorner.CornerRadius = UDim.new(0, 4)
				bfCorner.Parent = barFill

				local milestoneLabel = Instance.new("TextLabel")
				milestoneLabel.Size = UDim2.new(1, -24, 0, 14)
				milestoneLabel.Position = UDim2.new(0, 12, 0, 46)
				milestoneLabel.BackgroundTransparency = 1
				milestoneLabel.Text = string.format("До x2 эффекта: %d ур. (милстоун %d)", toMilestone, nextMilestone)
				milestoneLabel.TextColor3 = Color3.fromRGB(200, 180, 120)
				milestoneLabel.Font = Enum.Font.Gotham
				milestoneLabel.TextSize = 11
				milestoneLabel.TextXAlignment = Enum.TextXAlignment.Left
				milestoneLabel.Parent = card

				-- Кнопки мульти-покупки: узкие x1 / x10 / Max
				local btnRow = Instance.new("Frame")
				btnRow.Size = UDim2.new(1, -16, 0, 34)
				btnRow.Position = UDim2.new(0, 8, 1, -40)
				btnRow.BackgroundTransparency = 1
				btnRow.Parent = card
				local btnLayout = Instance.new("UIListLayout")
				btnLayout.FillDirection = Enum.FillDirection.Horizontal
				btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
				btnLayout.Padding = UDim.new(0, 4)
				btnLayout.Parent = btnRow

				local function buyBtn(label, amount, costForAmount, width)
					local b = Instance.new("TextButton")
					b.Size = UDim2.new(0, width or 54, 1, 0)
					b.BorderSizePixel = 0
					b.Font = Enum.Font.GothamBold
					b.TextSize = 10
					b.TextWrapped = true
					b.Parent = btnRow
					local bc = Instance.new("UICorner")
					bc.CornerRadius = UDim.new(0, 4)
					bc.Parent = b
					local costTxt = Format.Number(costForAmount)
					local affordable = currentXP >= costForAmount and costForAmount < math.huge
					b.Text = label .. "\n" .. costTxt
					if affordable then
						b.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
						b.TextColor3 = Color3.new(1, 1, 1)
						b.MouseButton1Click:Connect(function()
							local sn, amt = statName, amount
							runMenuAction(function()
								local res = invoke(RemoteNames.UpgradeStat, sn, amt)
								afterShopAction(res)
							end)
						end)
					else
						b.BackgroundColor3 = Color3.fromRGB(50, 52, 60)
						b.TextColor3 = Color3.fromRGB(120, 120, 130)
					end
				end

				buyBtn("x1", 1, StatCalculator.GetBulkUpgradeCost(statName, levelStat, 1), 48)
				buyBtn("x10", 10, StatCalculator.GetBulkUpgradeCost(statName, levelStat, 10), 52)
				local maxCount = StatCalculator.GetAffordableUpgradeCount(statName, levelStat, currentXP)
				local maxCost = maxCount > 0 and StatCalculator.GetBulkUpgradeCost(statName, levelStat, maxCount) or nextCost
				local maxLabel = maxCount > 0 and ("M+" .. tostring(maxCount)) or "Max"
				buyBtn(maxLabel, "max", maxCost, 58)
			end
			order += 1
		end
	end
	task.defer(updateCanvasSize)
end

local function showUnits()
	clearContent()
	addLabel("ОТРЯД", 1)
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 36)
	hint.BackgroundTransparency = 1
	hint.Text = "Синий = надето на слот. Цифры: свободно / всего. Надеть можно только свободную копию."
	hint.TextColor3 = Color3.fromRGB(170, 175, 195)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.LayoutOrder = 2
	hint.Parent = content

	local order = 3

	local function weaponDisplayName(wType, tier): string
		local cfg = WeaponsConfig.Weapons[wType] and WeaponsConfig.Weapons[wType][tier]
		if cfg and cfg.Name then
			return cfg.Name
		end
		local label = WEAPON_TAB_LABELS[wType] or wType
		return string.format("%s T%d", label, tier)
	end

	local function makeSection(title: string, bg: Color3)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.BackgroundColor3 = bg
		frame.BorderSizePixel = 0
		frame.LayoutOrder = order
		frame.Parent = content
		order += 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = frame
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 4)
		list.Parent = frame
		local titleL = Instance.new("TextLabel")
		titleL.Size = UDim2.new(1, 0, 0, 20)
		titleL.BackgroundTransparency = 1
		titleL.Text = title
		titleL.TextColor3 = Color3.fromRGB(255, 220, 120)
		titleL.Font = Enum.Font.GothamBold
		titleL.TextSize = 13
		titleL.TextXAlignment = Enum.TextXAlignment.Left
		titleL.LayoutOrder = 0
		titleL.Parent = frame
		return frame
	end

	local function addStockLine(parent: Frame, text: string, free: number, layoutOrder: number)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, 0, 0, 18)
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextColor3 = free > 0 and Color3.fromRGB(160, 230, 170) or Color3.fromRGB(200, 160, 120)
		l.Font = Enum.Font.Gotham
		l.TextSize = 12
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = layoutOrder
		l.Parent = parent
	end

	-- Склад оружия
	local weaponStock = makeSection("СКЛАД ОРУЖИЯ (в наличии)", Color3.fromRGB(24, 28, 38))
	local weaponLines = 0
	for _, wt in ipairs(WeaponsConfig.Types) do
		local byType = profile and profile.WeaponCopies and profile.WeaponCopies[wt]
		if type(byType) == "table" then
			local tiers = {}
			for tierKey, count in pairs(byType) do
				local tier = tonumber(tierKey)
				local n = tonumber(count) or 0
				if tier and n > 0 then
					table.insert(tiers, tier)
				end
			end
			table.sort(tiers)
			for _, tier in ipairs(tiers) do
				local total = getWeaponCopies(profile, wt, tier)
				local eq = countEquippedWeaponUI(profile, wt, tier)
				local free = math.max(0, total - eq)
				weaponLines += 1
				addStockLine(
					weaponStock,
					string.format(
						"• %s  —  всего %d  |  на отряде %d  |  свободно %d",
						weaponDisplayName(wt, tier),
						total,
						eq,
						free
					),
					free,
					weaponLines
				)
			end
		end
	end
	if weaponLines == 0 then
		addStockLine(weaponStock, "Пока нет купленного оружия — зайди в Магазин.", 0, 1)
	end

	-- Склад брони
	local armorStock = makeSection("СКЛАД БРОНИ (в наличии)", Color3.fromRGB(24, 28, 38))
	local armorLines = 0
	local armorTiers = {}
	for tierKey, count in pairs((profile and profile.ArmorCopies) or {}) do
		local tier = tonumber(tierKey)
		local n = tonumber(count) or 0
		if tier and n > 0 then
			table.insert(armorTiers, tier)
		end
	end
	table.sort(armorTiers)
	for _, tier in ipairs(armorTiers) do
		local total = getArmorCopies(profile, tier)
		local eq = countEquippedArmorUI(profile, tier)
		local free = math.max(0, total - eq)
		local aName = (ArmorConfig.Tiers[tier] and ArmorConfig.Tiers[tier].Name) or ("Броня T" .. tier)
		armorLines += 1
		addStockLine(
			armorStock,
			string.format("• %s  —  всего %d  |  на отряде %d  |  свободно %d", aName, total, eq, free),
			free,
			armorLines
		)
	end
	if armorLines == 0 then
		addStockLine(armorStock, "Броня не куплена — зайди во вкладку Броня.", 0, 1)
	end

	addLabel("СЛОТЫ 1–4 (что надето сейчас)", order, Color3.fromRGB(200, 210, 230))
	order += 1

	for slot = 1, 4 do
		local load = profile and profile.SquadLoadout and (profile.SquadLoadout[slot] or profile.SquadLoadout[tostring(slot)])
		local wType = load and load.WeaponType or "Pistol"
		local tier = load and (tonumber(load.Tier) or 1) or 1
		local armorRaw = profile and profile.SquadArmor and (profile.SquadArmor[slot] or profile.SquadArmor[tostring(slot)])
		local armorT = tonumber(armorRaw) or 0
		local armorName = (armorT > 0 and ArmorConfig.Tiers[armorT] and ArmorConfig.Tiers[armorT].Name) or "без брони"
		local wName = weaponDisplayName(wType, tier)
		local wTotal = getWeaponCopies(profile, wType, tier)
		local wEq = countEquippedWeaponUI(profile, wType, tier)

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = content
		order += 1
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 8)
		cc.Parent = card
		local cpad = Instance.new("UIPadding")
		cpad.PaddingTop = UDim.new(0, 8)
		cpad.PaddingBottom = UDim.new(0, 8)
		cpad.PaddingLeft = UDim.new(0, 10)
		cpad.PaddingRight = UDim.new(0, 10)
		cpad.Parent = card
		local clist = Instance.new("UIListLayout")
		clist.SortOrder = Enum.SortOrder.LayoutOrder
		clist.Padding = UDim.new(0, 6)
		clist.Parent = card

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 22)
		title.BackgroundTransparency = 1
		title.Text = string.format("Слот %d%s", slot, slot == 1 and " (ты)" or "")
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 15
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.LayoutOrder = 1
		title.Parent = card

		local equipped = Instance.new("TextLabel")
		equipped.Size = UDim2.new(1, 0, 0, 36)
		equipped.BackgroundColor3 = Color3.fromRGB(36, 48, 70)
		equipped.BorderSizePixel = 0
		equipped.Text = string.format(
			"  Надето:  %s   +   %s\n  (оружие: %d/%d копий этого тира на отряде)",
			wName,
			armorName,
			wEq,
			wTotal
		)
		equipped.TextColor3 = Color3.fromRGB(180, 220, 255)
		equipped.Font = Enum.Font.Gotham
		equipped.TextSize = 12
		equipped.TextXAlignment = Enum.TextXAlignment.Left
		equipped.LayoutOrder = 2
		equipped.Parent = card
		local ec = Instance.new("UICorner")
		ec.CornerRadius = UDim.new(0, 6)
		ec.Parent = equipped

		local wHeader = Instance.new("TextLabel")
		wHeader.Size = UDim2.new(1, 0, 0, 16)
		wHeader.BackgroundTransparency = 1
		wHeader.Text = "Сменить оружие:"
		wHeader.TextColor3 = Color3.fromRGB(160, 165, 180)
		wHeader.Font = Enum.Font.Gotham
		wHeader.TextSize = 11
		wHeader.TextXAlignment = Enum.TextXAlignment.Left
		wHeader.LayoutOrder = 3
		wHeader.Parent = card

		local wRow = Instance.new("Frame")
		wRow.Size = UDim2.new(1, 0, 0, 0)
		wRow.AutomaticSize = Enum.AutomaticSize.Y
		wRow.BackgroundTransparency = 1
		wRow.LayoutOrder = 4
		wRow.Parent = card
		local wLayout = Instance.new("UIGridLayout")
		wLayout.CellSize = UDim2.new(0, 118, 0, 36)
		wLayout.CellPadding = UDim2.new(0, 4, 0, 4)
		wLayout.SortOrder = Enum.SortOrder.LayoutOrder
		wLayout.Parent = wRow

		local btnOrder = 0
		for _, wt in ipairs(WeaponsConfig.Types) do
			local byType = profile and profile.WeaponCopies and profile.WeaponCopies[wt]
			if type(byType) == "table" then
				local tiers = {}
				for tierKey, count in pairs(byType) do
					local t = tonumber(tierKey)
					local n = tonumber(count) or 0
					if t and n > 0 then
						table.insert(tiers, t)
					end
				end
				table.sort(tiers)
				for _, t in ipairs(tiers) do
					local total = getWeaponCopies(profile, wt, t)
					local eq = countEquippedWeaponUI(profile, wt, t)
					local free = math.max(0, total - eq)
					local isOn = wType == wt and tier == t
					-- Свободна, если есть free ИЛИ уже на этом слоте (можно «оставить»)
					local canEquip = isOn or free > 0
					btnOrder += 1
					local b = Instance.new("TextButton")
					b.LayoutOrder = btnOrder
					b.Text = string.format(
						"%s%s\n%s",
						isOn and "✓ " or "",
						weaponDisplayName(wt, t),
						isOn and string.format("надето · всего %d", total) or string.format("%d своб. / %d", free, total)
					)
					b.Font = Enum.Font.GothamBold
					b.TextSize = 10
					b.TextWrapped = true
					b.AutoButtonColor = canEquip
					if isOn then
						b.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
						b.TextColor3 = Color3.new(1, 1, 1)
					elseif canEquip then
						b.BackgroundColor3 = Color3.fromRGB(45, 55, 70)
						b.TextColor3 = Color3.fromRGB(230, 230, 240)
					else
						b.BackgroundColor3 = Color3.fromRGB(35, 36, 42)
						b.TextColor3 = Color3.fromRGB(120, 120, 130)
					end
					b.Parent = wRow
					local bc = Instance.new("UICorner")
					bc.CornerRadius = UDim.new(0, 5)
					bc.Parent = b
					if canEquip and not isOn then
						b.MouseButton1Click:Connect(function()
							local s, w, ti = slot, wt, t
							runMenuAction(function()
								local res = invoke(RemoteNames.SetSquadLoadout, s, w, ti)
								afterShopAction(res)
							end)
						end)
					end
				end
			end
		end
		if btnOrder == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, 0, 0, 20)
			empty.BackgroundTransparency = 1
			empty.Text = "Нет копий оружия для экипировки"
			empty.TextColor3 = Color3.fromRGB(180, 120, 120)
			empty.Font = Enum.Font.Gotham
			empty.TextSize = 11
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.LayoutOrder = 4
			empty.Parent = card
		end

		local aHeader = Instance.new("TextLabel")
		aHeader.Size = UDim2.new(1, 0, 0, 16)
		aHeader.BackgroundTransparency = 1
		aHeader.Text = "Сменить броню:"
		aHeader.TextColor3 = Color3.fromRGB(160, 165, 180)
		aHeader.Font = Enum.Font.Gotham
		aHeader.TextSize = 11
		aHeader.TextXAlignment = Enum.TextXAlignment.Left
		aHeader.LayoutOrder = 5
		aHeader.Parent = card

		local aRow = Instance.new("Frame")
		aRow.Size = UDim2.new(1, 0, 0, 0)
		aRow.AutomaticSize = Enum.AutomaticSize.Y
		aRow.BackgroundTransparency = 1
		aRow.LayoutOrder = 6
		aRow.Parent = card
		local aLayout = Instance.new("UIGridLayout")
		aLayout.CellSize = UDim2.new(0, 118, 0, 36)
		aLayout.CellPadding = UDim2.new(0, 4, 0, 4)
		aLayout.SortOrder = Enum.SortOrder.LayoutOrder
		aLayout.Parent = aRow

		-- Снять броню
		do
			local off = Instance.new("TextButton")
			off.LayoutOrder = 0
			off.Text = armorT == 0 and "✓ Без брони" or "Снять броню"
			off.Font = Enum.Font.GothamBold
			off.TextSize = 10
			off.BackgroundColor3 = armorT == 0 and Color3.fromRGB(50, 120, 220) or Color3.fromRGB(55, 50, 45)
			off.TextColor3 = Color3.new(1, 1, 1)
			off.Parent = aRow
			local oc = Instance.new("UICorner")
			oc.CornerRadius = UDim.new(0, 5)
			oc.Parent = off
			if armorT ~= 0 then
				off.MouseButton1Click:Connect(function()
					local s = slot
					runMenuAction(function()
						local res = invoke(RemoteNames.SetSquadArmor, s, 0)
						afterShopAction(res)
					end)
				end)
			end
		end

		local aBtn = 0
		for _, t in ipairs(armorTiers) do
			local total = getArmorCopies(profile, t)
			local eq = countEquippedArmorUI(profile, t)
			local free = math.max(0, total - eq)
			local isOn = armorT == t
			local canEquip = isOn or free > 0
			local aName = (ArmorConfig.Tiers[t] and ArmorConfig.Tiers[t].Name) or ("T" .. t)
			aBtn += 1
			local b = Instance.new("TextButton")
			b.LayoutOrder = aBtn
			b.Text = string.format(
				"%s%s\n%s",
				isOn and "✓ " or "",
				aName,
				isOn and string.format("надето · всего %d", total) or string.format("%d своб. / %d", free, total)
			)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 10
			b.TextWrapped = true
			b.AutoButtonColor = canEquip
			if isOn then
				b.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
				b.TextColor3 = Color3.new(1, 1, 1)
			elseif canEquip then
				b.BackgroundColor3 = Color3.fromRGB(45, 55, 70)
				b.TextColor3 = Color3.fromRGB(230, 230, 240)
			else
				b.BackgroundColor3 = Color3.fromRGB(35, 36, 42)
				b.TextColor3 = Color3.fromRGB(120, 120, 130)
			end
			b.Parent = aRow
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 5)
			bc.Parent = b
			if canEquip and not isOn then
				b.MouseButton1Click:Connect(function()
					local s, ti = slot, t
					runMenuAction(function()
						local res = invoke(RemoteNames.SetSquadArmor, s, ti)
						afterShopAction(res)
					end)
				end)
			end
		end
	end
	task.defer(updateCanvasSize)
end

local function showDaily()
	clearContent()
	addLabel("ЕЖЕДНЕВНАЯ НАГРАДА", 1)
	if dailyResult and dailyResult.success then
		local reward = dailyResult.reward or {}
		addLabel(
			string.format(
				"День %d: +%d золота, +%d XP",
				dailyResult.streak or 1,
				reward.Gold or 0,
				reward.XP or 0
			),
			2,
			Color3.fromRGB(60, 200, 120)
		)
	elseif dailyResult and dailyResult.error then
		addLabel(tostring(dailyResult.error), 2, Color3.fromRGB(255, 180, 50))
	else
		addLabel("Награду можно получать один раз в день", 2, Color3.fromRGB(180, 180, 200))
	end

	local claim = Instance.new("TextButton")
	claim.Size = UDim2.new(1, 0, 0, 40)
	claim.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
	claim.Text = "Получить награду"
	claim.TextColor3 = Color3.new(1, 1, 1)
	claim.Font = Enum.Font.GothamBold
	claim.TextSize = 15
	claim.LayoutOrder = 3
	claim.Parent = content
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = claim
	claim.MouseButton1Click:Connect(function()
		claim.Active = false
		claim.Text = "Проверяем..."
		runMenuAction(function()
			dailyResult = invoke(RemoteNames.ClaimDailyReward)
			refreshProfileAndHUD()
			refreshOpenTab()
		end)
	end)
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
	btn.Text = "Активировать"
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
			resultLabel.Text = "Введите код"
			resultLabel.TextColor3 = Color3.fromRGB(255, 180, 50)
			return
		end
		btn.Text = "Проверка..."
		local r = invoke(RemoteNames.RedeemPromocode, code)
		if r and (r.ok or r.success) then
			resultLabel.Text = r.message or "Промокод активирован"
			resultLabel.TextColor3 = Color3.fromRGB(60, 200, 120)
			profile = invoke(RemoteNames.GetProfile)
		else
			resultLabel.Text = (r and (r.error or r.message)) or "Неверный код"
			resultLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
		end
		btn.Text = "Активировать"
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
	colHeader.Text = "  #   Имя              Опыт         Волна"
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
	local entries = r and r.entries
	if type(entries) == "table" and #entries > 0 then
		for rank, e in ipairs(entries) do
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
			local displayName = e.Name
			if not displayName or displayName == "" or displayName == tostring(e.UserId) then
				displayName = (e.UserId == player.UserId) and player.DisplayName or ("ID " .. tostring(e.UserId))
			end
			-- укоротить длинные имена
			if #tostring(displayName) > 14 then
				displayName = string.sub(displayName, 1, 13) .. "…"
			end
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundColor3 = rowColor
			row.Text = string.format(
				"  %s%-2d  %-14s  %6d XP   W%d",
				prefix,
				rank,
				tostring(displayName),
				tonumber(e.Value or e.XP) or 0,
				tonumber(e.Wave) or 0
			)
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
		addLabel("Пока пусто — сыграй бой, XP попадёт в топ сразу после миссии.", 3, Color3.fromRGB(100, 105, 120))
	end
	task.defer(updateCanvasSize)
end

local function partyAction(action, payload)
	return invoke(RemoteNames.PartyAction, action, payload)
end

local showInvitePicker

local function showParty()
	clearContent()
	local me = Players.LocalPlayer
	local info = partyAction("Get") or {}
	local party = info.party
	local members = party and party.Members
		or { { UserId = me.UserId, Name = me.Name, DisplayName = me.DisplayName } }
	local isLeader = not party or party.LeaderUserId == me.UserId or party.LeaderUserId == nil
	local mult = info.multiplier or 1.0

	addLabel("КОМАНДА", 1, Color3.fromRGB(100, 255, 140))

	local multCard = Instance.new("Frame")
	multCard.Size = UDim2.new(1, 0, 0, 54)
	multCard.BackgroundColor3 = Color3.fromRGB(25, 45, 35)
	multCard.BorderSizePixel = 0
	multCard.LayoutOrder = 2
	multCard.Parent = content
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0, 8)
	mc.Parent = multCard
	local mt = Instance.new("TextLabel")
	mt.Size = UDim2.new(1, -16, 0, 26)
	mt.Position = UDim2.new(0, 8, 0, 4)
	mt.BackgroundTransparency = 1
	mt.Text = string.format("Множитель наград: x%.1f", mult)
	mt.TextColor3 = Color3.fromRGB(100, 255, 140)
	mt.Font = Enum.Font.GothamBold
	mt.TextSize = 18
	mt.TextXAlignment = Enum.TextXAlignment.Left
	mt.Parent = multCard
	local ms = Instance.new("TextLabel")
	ms.Size = UDim2.new(1, -16, 0, 18)
	ms.Position = UDim2.new(0, 8, 0, 30)
	ms.BackgroundTransparency = 1
	ms.Text = "Соло x1.0  •  +1 x1.2  •  +2 x1.3  •  полный отряд x1.5"
	ms.TextColor3 = Color3.fromRGB(160, 165, 180)
	ms.Font = Enum.Font.Gotham
	ms.TextSize = 11
	ms.TextXAlignment = Enum.TextXAlignment.Left
	ms.Parent = multCard

	local order = 3
	for slot = 1, (GameConfig.PartySize or 4) do
		local m = members[slot]
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 64)
		card.BackgroundColor3 = m and Color3.fromRGB(28, 30, 42) or Color3.fromRGB(22, 24, 32)
		card.BackgroundTransparency = m and 0 or 0.3
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = content
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 6)
		cc.Parent = card
		local cs = Instance.new("UIStroke")
		cs.Thickness = 1
		cs.Color = (m and slot == 1) and Color3.fromRGB(255, 215, 80) or Color3.fromRGB(50, 55, 70)
		cs.Parent = card

		local av = Instance.new("ImageLabel")
		av.Size = UDim2.new(0, 48, 0, 48)
		av.Position = UDim2.new(0, 8, 0.5, -24)
		av.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
		av.BorderSizePixel = 0
		av.Parent = card
		local ac = Instance.new("UICorner")
		ac.CornerRadius = UDim.new(1, 0)
		ac.Parent = av
		if m then
			av.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", m.UserId)
		end

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.5, 0, 0, 22)
		name.Position = UDim2.new(0, 66, 0, 10)
		name.BackgroundTransparency = 1
		name.Text = m and ((slot == 1 and "* " or "") .. (m.DisplayName or m.Name)) or "Свободный слот (бот)"
		name.TextColor3 = m and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(110, 115, 130)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 14
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = card
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(0.5, 0, 0, 16)
		sub.Position = UDim2.new(0, 66, 0, 34)
		sub.BackgroundTransparency = 1
		sub.Text = m and (slot == 1 and "Лидер" or "В команде") or "Пригласи — бонус к наградам"
		sub.TextColor3 = Color3.fromRGB(160, 165, 180)
		sub.Font = Enum.Font.Gotham
		sub.TextSize = 11
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Parent = card

		if isLeader then
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 110, 0, 30)
			btn.Position = UDim2.new(1, -120, 0.5, -15)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 12
			btn.BorderSizePixel = 0
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Parent = card
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 4)
			bc.Parent = btn
			if m and slot > 1 then
				btn.Text = "Кик"
				btn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
				btn.MouseButton1Click:Connect(function()
					partyAction("Kick", m.UserId)
					task.wait(0.2)
					showParty()
				end)
			elseif not m then
				btn.Text = "Пригласить"
				btn.BackgroundColor3 = Color3.fromRGB(0, 140, 220)
				btn.MouseButton1Click:Connect(function()
					showInvitePicker()
				end)
			else
				btn.Visible = false
			end
		end
		order += 1
	end

	if isLeader then
		local diff = party and party.Difficulty or "Normal"
		local names = { Easy = "Лёгкий", Normal = "Нормальный", Hard = "Сложный" }
		local diffBtn = Instance.new("TextButton")
		diffBtn.Size = UDim2.new(1, 0, 0, 36)
		diffBtn.BackgroundColor3 = Color3.fromRGB(35, 38, 55)
		diffBtn.Text = "Сложность: " .. (names[diff] or diff)
		diffBtn.TextColor3 = Color3.new(1, 1, 1)
		diffBtn.Font = Enum.Font.GothamBold
		diffBtn.TextSize = 13
		diffBtn.BorderSizePixel = 0
		diffBtn.LayoutOrder = order
		diffBtn.Parent = content
		local dc = Instance.new("UICorner")
		dc.CornerRadius = UDim.new(0, 8)
		dc.Parent = diffBtn
		diffBtn.MouseButton1Click:Connect(function()
			local nxt = diff == "Normal" and "Hard" or (diff == "Hard" and "Easy" or "Normal")
			partyAction("Create")
			partyAction("SetDifficulty", nxt)
			task.wait(0.2)
			showParty()
		end)
		order += 1

		local go = Instance.new("TextButton")
		go.Size = UDim2.new(1, 0, 0, 48)
		go.BackgroundColor3 = Color3.fromRGB(60, 200, 120)
		go.Text = "В БОЙ"
		go.TextColor3 = Color3.new(1, 1, 1)
		go.Font = Enum.Font.GothamBold
		go.TextSize = 18
		go.BorderSizePixel = 0
		go.LayoutOrder = order
		go.Parent = content
		local gc = Instance.new("UICorner")
		gc.CornerRadius = UDim.new(0, 8)
		gc.Parent = go
		go.MouseButton1Click:Connect(function()
			go.Text = "Телепорт..."
			go.BackgroundColor3 = Color3.fromRGB(100, 100, 110)
			partyAction("Create")
			local BattleClient = require(Shared.Util.BattleClient)
			local ok, err = BattleClient.StartBattle()
			if not ok then
				go.Text = tostring(err)
				go.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
				task.wait(1.5)
				showParty()
			end
		end)
	else
		local leave = Instance.new("TextButton")
		leave.Size = UDim2.new(1, 0, 0, 40)
		leave.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
		leave.Text = "Покинуть пати"
		leave.TextColor3 = Color3.new(1, 1, 1)
		leave.Font = Enum.Font.GothamBold
		leave.TextSize = 14
		leave.BorderSizePixel = 0
		leave.LayoutOrder = order
		leave.Parent = content
		local lc = Instance.new("UICorner")
		lc.CornerRadius = UDim.new(0, 8)
		lc.Parent = leave
		leave.MouseButton1Click:Connect(function()
			partyAction("Leave")
			task.wait(0.2)
			showParty()
		end)
	end
	task.defer(updateCanvasSize)
end

showInvitePicker = function()
	clearContent()
	addLabel("ПРИГЛАСИТЬ В КОМАНДУ", 1, Color3.fromRGB(120, 200, 255))
	local back = Instance.new("TextButton")
	back.Size = UDim2.new(1, 0, 0, 30)
	back.BackgroundColor3 = Color3.fromRGB(35, 38, 55)
	back.Text = "← Назад"
	back.TextColor3 = Color3.new(1, 1, 1)
	back.Font = Enum.Font.GothamBold
	back.TextSize = 12
	back.BorderSizePixel = 0
	back.LayoutOrder = 2
	back.Parent = content
	local bkc = Instance.new("UICorner")
	bkc.CornerRadius = UDim.new(0, 6)
	bkc.Parent = back
	back.MouseButton1Click:Connect(showParty)

	local r = partyAction("LobbyPlayers")
	local list = r and r.players or {}
	if #list == 0 then
		addLabel("В лобби никого нет", 3, Color3.fromRGB(110, 115, 130))
	end
	local order = 3
	for _, p in ipairs(list) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 52)
		card.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = content
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 6)
		cc.Parent = card
		local av = Instance.new("ImageLabel")
		av.Size = UDim2.new(0, 40, 0, 40)
		av.Position = UDim2.new(0, 6, 0.5, -20)
		av.BackgroundTransparency = 1
		av.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", p.UserId)
		av.Parent = card
		local ac = Instance.new("UICorner")
		ac.CornerRadius = UDim.new(1, 0)
		ac.Parent = av
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(0.55, 0, 1, 0)
		nm.Position = UDim2.new(0, 54, 0, 0)
		nm.BackgroundTransparency = 1
		nm.Text = (p.IsFriend and "* " or "") .. p.DisplayName .. "  @" .. p.Name
		nm.TextColor3 = Color3.fromRGB(240, 240, 245)
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = 13
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.Parent = card
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 110, 0, 30)
		btn.Position = UDim2.new(1, -120, 0.5, -15)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.BorderSizePixel = 0
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Parent = card
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 4)
		bc.Parent = btn
		if p.InParty then
			btn.Text = "Уже в пати"
			btn.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
		else
			btn.Text = "Пригласить"
			btn.BackgroundColor3 = Color3.fromRGB(0, 140, 220)
			btn.MouseButton1Click:Connect(function()
				local res = partyAction("Invite", p.UserId)
				btn.Text = res and res.success and "Отправлено" or tostring(res and res.error or "Ошибка")
				btn.BackgroundColor3 = res and res.success and Color3.fromRGB(60, 200, 120) or Color3.fromRGB(220, 60, 60)
			end)
		end
		order += 1
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
	Party = "Пати",
	Guide = "Гайд",
}

local function showGuide()
	clearContent()
	local sections = {
		{
			title = "КАК ИГРАТЬ",
			lines = {
				"1. В лобби подойди к зоне «В бой» (или нажми вход в команду).",
				"2. На мосту ты летаешь и стреляешь — умереть нельзя.",
				"3. Боты-защитники стоят на мосту. Если все боты погибнут — поражение.",
				"4. Убей всех врагов волны → следующая волна. Цель — зайти как можно дальше.",
			},
		},
		{
			title = "ЗОЛОТО (Gold)",
			lines = {
				"• За урон по врагам и за зачистку волны.",
				"• Чем выше номер волны — тем больше золота (до x6).",
				"• Каждая 5-я волна (чекпоинт) даёт x3 бонус за зачистку.",
				"• Потрать в магазине на оружие и броню.",
			},
		},
		{
			title = "ОПЫТ (XP)",
			lines = {
				"• Тоже за урон и за волны.",
				"• XP в HUD — уровень аккаунта.",
				"• «Доступно для улучшений» в Прокачке — тратится на Жизнь / Точность / Скорострельность.",
				"• Прокачка бесконечная: уровни без потолка, цена растёт.",
			},
		},
		{
			title = "ПРЕСТИЖ (самое важное)",
			lines = {
				"Престиж = «ребёрс» как в тайкунах.",
				"",
				"Как получить:",
				"1. Открой вкладку Прокачка.",
				"2. Прокачай статы, пока сумма уровней не дойдёт до порога (сначала 120).",
				"3. Нажми кнопку престижа.",
				"",
				"Что происходит:",
				"• Уровни статов сбрасываются в 0.",
				"• Получаешь +1 очко престижа.",
				"• За каждое очко: +2% к статам и +5% к золоту/XP навсегда.",
				"• Следующий престиж требует больше уровней (+60 к порогу).",
				"",
				"Зачем нужно:",
				"• После ~20 волны враги резко сильнее.",
				"• Престиж открывает элитное оружие T6–T10 в магазине.",
				"• Престиж 1/2/3 открывает новые статы: криты, добычу золота/XP, урон отряда.",
			},
		},
		{
			title = "МИЛСТОУНЫ И МУЛЬТИ-ПОКУПКА",
			lines = {
				"• Каждые 25 уровней одной статы её эффект УДВАИВАЕТСЯ (x2, x4, x8...).",
				"• Полоска под статой показывает прогресс до следующего x2.",
				"• Кнопки x1 / x10 / Max покупают сразу несколько уровней.",
			},
		},
		{
			title = "ВОЗНЕСЕНИЕ (эндгейм)",
			lines = {
				"Когда престижей много — можно Вознестись:",
				"• Сжигает ВСЕ очки престижа и уровни.",
				"• Даёт постоянные +25% к статам и доходу за каждый уровень вознесения.",
				"• Цена растёт: 10, 15, 20... очков престижа.",
				"• Это бесконечный слой прогрессии поверх престижа.",
			},
		},
		{
			title = "ОРУЖИЕ И БРОНЯ",
			lines = {
				"• Магазин: тиры T1–T5 доступны сразу за золото.",
				"• Элита T6–T10: нужна престиж (T6 = 1 очко … T10 = 5 очков).",
				"• Броня снижает получаемый урон ботов.",
				"• Вкладка Отряд — раздай оружие по слотам 1–4.",
			},
		},
		{
			title = "ЕЖЕДНЕВКА И ПРОМОКОДЫ",
			lines = {
				"• Ежедневка: зайди во вкладку и нажми «Получить» (раз в сутки).",
				"• Промокод: введи код во вкладке Промокод.",
			},
		},
		{
			title = "КОРОТКИЙ ЦИКЛ",
			lines = {
				"Бой → золото/XP → магазин + прокачка → дальше волны →",
				"стена сложности → престиж → элитное оружие → ещё дальше.",
			},
		},
	}

	local order = 1
	for _, section in ipairs(sections) do
		addLabel(section.title, order, Color3.fromRGB(255, 200, 100))
		order += 1
		for _, line in ipairs(section.lines) do
			local text = line
			if text == "" then
				text = " "
			end
			local l = Instance.new("TextLabel")
			l.Size = UDim2.new(1, 0, 0, 0)
			l.AutomaticSize = Enum.AutomaticSize.Y
			l.BackgroundTransparency = 1
			l.Text = text
			l.TextColor3 = Color3.fromRGB(200, 205, 220)
			l.Font = Enum.Font.Gotham
			l.TextSize = 13
			l.TextWrapped = true
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.LayoutOrder = order
			l.Parent = content
			order += 1
		end
	end
	task.defer(updateCanvasSize)
end

refreshOpenTab = function()
	if not ModalManager.IsOpen() then
		return
	end
	if not bindContentFromModal() then
		return
	end
	local tab = activeTab or "Shop"
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
	elseif tab == "Party" then
		showParty()
	elseif tab == "Guide" then
		showGuide()
	end
end

function MenuController.OpenTab(tab)
	activeTab = tab
	-- Свежий профиль перед отрисовкой (лидерборд / склад)
	profile = invoke(RemoteNames.GetProfile) or profile
	ModalManager.Open({
		Title = TAB_TITLES[tab] or tab,
		Size = if tab == "Upgrade" then UDim2.new(0.52, 0, 0.78, 0) else UDim2.new(0.5, 0, 0.7, 0),
		Content = function(scroll)
			content = scroll
			if not scroll:FindFirstChildOfClass("UIListLayout") then
				local layout = Instance.new("UIListLayout")
				layout.Padding = UDim.new(0, 6)
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Parent = scroll
			end
			-- Контент всегда с нуля (важно для лидерборда в одной сессии)
			clearContent()
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
			elseif tab == "Party" then
				showParty()
			elseif tab == "Guide" then
				showGuide()
			else
				showShop()
			end
		end,
	})
end

function MenuController:Init(deps)
	if inited then
		return
	end
	deps = deps or {}
	remotes = deps.Remotes or ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		return
	end
	ui = deps.UI or UIController.ScreenGui
	if not ui then
		UIController:Init()
		ui = UIController.ScreenGui
	end
	if not ui then
		return
	end
	inited = true
	ModalManager.Init(ui)
	MenuBridge.SetHandler(function(tab)
		MenuController.OpenTab(tab)
	end)

	local profileEvt = remotes and remotes:FindFirstChild(RemoteNames.ProfileUpdated)
	if profileEvt then
		profileEvt.OnClientEvent:Connect(function(p)
			profile = p
			UIController.UpdateHUD(p, true)
			if ModalManager.IsOpen() and activeTab then
				task.defer(refreshOpenTab)
			end
		end)
	end

	-- HUD из атрибутов БД (не зависит от пропущенного ProfileUpdated)
	local function hudFromAttrs()
		local gold = player:GetAttribute("BD_Gold")
		if gold == nil then
			return
		end
		UIController.UpdateHUD({
			Gold = gold,
			XP = player:GetAttribute("BD_XP") or 0,
			TotalXP = player:GetAttribute("BD_TotalXP") or 0,
			Level = player:GetAttribute("BD_Level") or 1,
		}, true)
	end
	player:GetAttributeChangedSignal("BD_Gold"):Connect(hudFromAttrs)
	player:GetAttributeChangedSignal("BD_XP"):Connect(hudFromAttrs)
	player:GetAttributeChangedSignal("BD_TotalXP"):Connect(hudFromAttrs)
	player:GetAttributeChangedSignal("BD_ProfileReady"):Connect(hudFromAttrs)
	hudFromAttrs()

	local openTabEvent = remotes:FindFirstChild(RemoteNames.OpenMenuTab)
	if openTabEvent and openTabEvent:IsA("RemoteEvent") then
		openTabEvent.OnClientEvent:Connect(function(tab)
			if type(tab) == "string" and TAB_TITLES[tab] then
				MenuController.OpenTab(tab)
			end
		end)
	end
	task.spawn(function()
		for _ = 1, 60 do
			profile = invoke(RemoteNames.GetProfile)
			if profile then
				UIController.UpdateHUD(profile, true)
				return
			end
			hudFromAttrs()
			task.wait(0.25)
		end
	end)
end

return MenuController
