--[[
	MenuController — вкладки магазина / прокачки / и т.д.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local MenuBridge = require(ReplicatedStorage.Shared.Util.MenuBridge)
local WeaponsConfig = require(ReplicatedStorage.Shared.Config.WeaponsConfig)
local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local UpgradesConfig = require(ReplicatedStorage.Shared.Config.UpgradesConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local StatCalculator = require(ReplicatedStorage.Shared.Util.StatCalculator)
local UIController = require(script.Parent.UIController)

local MenuController = {}
local profile = nil
local overlay = nil
local content = nil

local function remotes()
	return ReplicatedStorage:WaitForChild("Remotes", 10)
end

local function invoke(name, ...)
	local args = table.pack(...)
	local r = remotes()
	local fn = r and r:FindFirstChild(name)
	if fn and fn:IsA("RemoteFunction") then
		local ok, result = pcall(function()
			return fn:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if ok then
			return result
		end
	end
	return nil
end

local function clearContent()
	if not content then
		return
	end
	for _, c in ipairs(content:GetChildren()) do
		c:Destroy()
	end
end

local function addLabel(text, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, 28)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.Gotham
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = order or 0
	l.Parent = content
	return l
end

local function addBtn(text, order, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -8, 0, 36)
	b.BackgroundColor3 = Color3.fromRGB(55, 90, 140)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.LayoutOrder = order or 0
	b.Parent = content
	b.MouseButton1Click:Connect(cb)
	return b
end

local function showShop()
	clearContent()
	addLabel("Оружие", 1)
	local i = 2
	for _, wType in ipairs(WeaponsConfig.Types) do
		for tier = 1, 5 do
			local w = WeaponsConfig.Weapons[wType][tier]
			local owned = profile and profile.OwnedWeapons and (profile.OwnedWeapons[wType] or 0) or 0
			local label = string.format("%s — %dg %s", w.Name, w.GoldCost, owned >= tier and "[есть]" or "")
			addBtn(label, i, function()
				invoke(RemoteNames.BuyWeapon, wType, tier)
			end)
			i += 1
		end
	end
end

local function showArmor()
	clearContent()
	addLabel("Броня", 1)
	for tier, data in ipairs(ArmorConfig.Tiers) do
		addBtn(string.format("%s — %dg", data.Name, data.GoldCost), tier + 1, function()
			invoke(RemoteNames.BuyArmor, tier)
		end)
	end
end

local function showUnits()
	clearContent()
	addLabel("Отряд — экипировка слотов", 1)
	for slot = 1, 4 do
		local loadout = profile and profile.SquadLoadout and profile.SquadLoadout[slot]
		local cur = loadout and string.format("%s T%d", loadout.WeaponType, loadout.Tier) or "Pistol T1"
		addLabel("Слот " .. slot .. ": " .. cur, slot * 2)
		addBtn("Поставить Pistol T1 на слот " .. slot, slot * 2 + 1, function()
			invoke(RemoteNames.SetSquadLoadout, slot, "Pistol", 1)
		end)
	end
end

local function showUpgrade()
	clearContent()
	addLabel("Прокачка (за XP)", 1)
	local order = 2
	for statName, cfg in pairs(UpgradesConfig.Stats) do
		local level = profile and profile.Upgrades and (profile.Upgrades[statName] or 0) or 0
		local cost = StatCalculator.GetUpgradeCost(statName, level)
		addBtn(string.format("%s Lv%d — %d XP", cfg.Name, level, cost), order, function()
			invoke(RemoteNames.UpgradeStat, statName)
		end)
		order += 1
	end
end

local function showDaily()
	clearContent()
	addLabel("Ежедневная награда", 1)
	addBtn("Забрать", 2, function()
		local r = invoke(RemoteNames.ClaimDailyReward)
		if r and r.success then
			addLabel("Получено! День " .. tostring(r.streak), 3)
		elseif r then
			addLabel(tostring(r.error), 3)
		end
	end)
end

local function showPromo()
	clearContent()
	addLabel("Промокод", 1)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -8, 0, 36)
	box.PlaceholderText = "Введите код"
	box.Text = ""
	box.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	box.TextColor3 = Color3.new(1, 1, 1)
	box.LayoutOrder = 2
	box.Parent = content
	addBtn("Активировать", 3, function()
		local r = invoke(RemoteNames.RedeemPromocode, box.Text)
		addLabel(r and (r.success and "OK" or tostring(r.error)) or "fail", 4)
	end)
end

local function showLeaderboard()
	clearContent()
	addLabel("Топ по XP", 1)
	local r = invoke(RemoteNames.GetLeaderboard, "XP")
	local order = 2
	if r and r.entries then
		for _, e in ipairs(r.entries) do
			addLabel(string.format("%d — %s", e.Value, tostring(e.UserId)), order)
			order += 1
		end
	end
end

local TABS = {
	["Магазин"] = showShop,
	["Броня"] = showArmor,
	["Юниты"] = showUnits,
	["Прокачка"] = showUpgrade,
	["Награды"] = showDaily,
	["Промокод"] = showPromo,
	["Топ"] = showLeaderboard,
	["Лидерборд"] = showLeaderboard,
}

function MenuController.OpenTab(tabName: string)
	if not overlay then
		return
	end
	overlay.Visible = true
	local title = overlay:FindFirstChild("Title")
	if title then
		title.Text = tabName
	end
	local fn = TABS[tabName]
	if fn then
		fn()
	else
		clearContent()
		addLabel("Вкладка: " .. tabName, 1)
	end
end

function MenuController:Init()
	UIController.WaitForReady()
	local gui = UIController.ScreenGui
	overlay = Instance.new("Frame")
	overlay.Name = "MenuOverlay"
	overlay.Size = UDim2.new(0.42, 0, 0.7, 0)
	overlay.Position = UDim2.new(0.55, 0, 0.15, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -50, 0, 36)
	title.BackgroundTransparency = 1
	title.Text = "Меню"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = overlay

	local close = Instance.new("TextButton")
	close.Size = UDim2.new(0, 36, 0, 36)
	close.Position = UDim2.new(1, -40, 0, 4)
	close.Text = "X"
	close.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Parent = overlay
	close.MouseButton1Click:Connect(function()
		overlay.Visible = false
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -12, 1, -48)
	scroll.Position = UDim2.new(0, 6, 0, 42)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 800)
	scroll.Parent = overlay

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll
	content = scroll

	MenuBridge.SetHandler(function(tab)
		MenuController.OpenTab(tab)
	end)

	local r = remotes()
	local updated = r and r:FindFirstChild(RemoteNames.ProfileUpdated)
	if updated then
		updated.OnClientEvent:Connect(function(p)
			profile = p
			UIController.UpdateHUD(p)
		end)
	end
	task.spawn(function()
		profile = invoke(RemoteNames.GetProfile)
		UIController.UpdateHUD(profile)
	end)
end

return MenuController
