local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local MenuBridge = require(ReplicatedStorage.Shared.Util.MenuBridge)

local ChatController = {}
local inited = false

function ChatController.System(text, hexColor)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")
	if general then
		pcall(function()
			general:DisplaySystemMessage(string.format('<font color="#%s">%s</font>', hexColor or "7FD0FF", text))
		end)
	end
end

local COMMANDS = {
	shop = "Shop",
	armor = "Armor",
	upgrade = "Upgrade",
	promo = "Promo",
	party = "Party",
	top = "Leaderboard",
	daily = "Daily",
}

-- Cyrillic aliases (separate keys; Luau identifiers can't be Cyrillic in table shorthand above)
COMMANDS["магазин"] = "Shop"
COMMANDS["броня"] = "Armor"
COMMANDS["прокачка"] = "Upgrade"
COMMANDS["промокод"] = "Promo"
COMMANDS["пати"] = "Party"
COMMANDS["топ"] = "Leaderboard"
COMMANDS["награда"] = "Daily"

function ChatController:Init()
	if inited then
		return
	end
	inited = true
	for alias, tab in pairs(COMMANDS) do
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "Cmd_" .. tostring(alias)
		cmd.PrimaryAlias = "/" .. tostring(alias)
		cmd.Parent = TextChatService
		cmd.Triggered:Connect(function()
			MenuBridge.OpenTab(tab)
		end)
	end

	local help = Instance.new("TextChatCommand")
	help.Name = "Cmd_help"
	help.PrimaryAlias = "/help"
	help.SecondaryAlias = "/помощь"
	help.Parent = TextChatService
	help.Triggered:Connect(function()
		ChatController.System("Команды: /shop /armor /upgrade /promo /party /top /daily", "FFD750")
	end)

	Players.LocalPlayer.Chatted:Connect(function(msg)
		local c = string.lower(msg):match("^/(%S+)")
		if c and COMMANDS[c] then
			MenuBridge.OpenTab(COMMANDS[c])
		end
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		return
	end
	local function on(name, fn)
		local r = remotes:FindFirstChild(name)
		if r and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(fn)
		end
	end
	on(RemoteNames.WaveResult, function(d)
		if d and d.success then
			ChatController.System("✅ Волна " .. tostring(d.wave) .. " пройдена!", "64E08C")
		elseif d then
			ChatController.System("💀 Отряд пал на волне " .. tostring(d.wave), "E05050")
		end
	end)
	on(RemoteNames.PartyUpdated, function(p)
		if p and p.Members then
			ChatController.System(string.format("👥 Пати: %d/4 игроков", #p.Members), "7FD0FF")
		end
	end)
	on(RemoteNames.BattleStarted, function()
		ChatController.System("⚔️ Бой начался! ЛКМ — стрелять, WASD/Space/Ctrl — летать", "FFD750")
	end)
end

return ChatController
