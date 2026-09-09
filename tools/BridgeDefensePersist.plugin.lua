--[[
	Studio plugin: Bridge Defense Persist
	- Включает HttpService.HttpEnabled (без Game Settings)
	- Ловит __BD_PROFILE_SAVE__ / __BD_PROFILE_META__ из Output
	- Пишет профиль на LogServer :8765 (даже если у place HTTP выключен)
	Установка: open-studio.ps1 копирует в %LOCALAPPDATA%\Roblox\Plugins\
]]

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local LOG_HOST = "http://127.0.0.1:8765"

local function enableHttp()
	pcall(function()
		HttpService.HttpEnabled = true
	end)
end

enableHttp()

local toolbar = plugin:CreateToolbar("Bridge Defense")
local btn = toolbar:CreateButton(
	"Enable HTTP",
	"Включить HttpService для сохранения Gold/XP на LogServer",
	"rbxassetid://6031075931"
)
btn.Click:Connect(function()
	enableHttp()
	print("[BridgeDefense][Plugin] HttpEnabled = true")
end)

task.spawn(function()
	while true do
		enableHttp()
		task.wait(3)
	end
end)

local function postJson(userId: string, json: string, force: boolean?)
	local url = string.format("%s/profile/%s%s", LOG_HOST, userId, force and "?force=1" or "")
	local ok, err = pcall(function()
		HttpService:PostAsync(url, json, Enum.HttpContentType.ApplicationJson)
	end)
	if ok then
		print(string.format("[BridgeDefense][Plugin] profile saved userId=%s", userId))
	else
		warn("[BridgeDefense][Plugin] LogServer POST fail: " .. tostring(err))
	end
end

local function postMeta(userId: string, gold: string, xp: string, totalXp: string, wave: string)
	-- Только патч существующего файла. Полный профиль — через __BD_PROFILE_SAVE__.
	local url = string.format("%s/profile/%s", LOG_HOST, userId)
	pcall(function()
		local existing = HttpService:GetAsync(url)
		if not existing or existing == "" or existing == "missing" then
			return
		end
		local data = HttpService:JSONDecode(existing)
		local newXp = tonumber(totalXp) or 0
		local oldXp = tonumber(data.TotalXP) or 0
		if newXp < oldXp then
			return
		end
		data.Gold = tonumber(gold) or data.Gold
		data.XP = tonumber(xp) or data.XP
		data.TotalXP = newXp
		data.HighestWave = tonumber(wave) or data.HighestWave
		postJson(userId, HttpService:JSONEncode(data), false)
	end)
end

local function handleLine(message: string)
	if not string.find(message, "BridgeDefense", 1, true) then
		return
	end

	local uid, json = string.match(message, "__BD_PROFILE_SAVE__|(%d+)|({.*})")
	if uid and json and string.sub(json, -1) == "}" then
		postJson(uid, json, false)
		return
	end

	local mUid, gold, xp, totalXp, wave =
		string.match(message, "__BD_PROFILE_META__|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)")
	if mUid then
		postMeta(mUid, gold, xp, totalXp, wave)
	end
end

LogService.MessageOut:Connect(function(message, _messageType)
	if RunService:IsEdit() then
		-- Во время Play серверные print тоже попадают в MessageOut
	end
	handleLine(tostring(message))
end)

print("[BridgeDefense][Plugin] Persist plugin loaded (HTTP auto-enable + profile forward)")
