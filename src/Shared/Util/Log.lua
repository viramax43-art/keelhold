--[[
	Log — серверный лог (+ опционально HTTP в LogServer). Клиент использует ClientLog.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Log = {}
local MAX = 400
local lines = {}
local LOG_URL = "http://127.0.0.1:8765/log"
local queue = {}
local flushStarted = false

local function flushHttp()
	if #queue == 0 or not RunService:IsStudio() then
		return
	end
	local batch = table.concat(queue, "\n")
	table.clear(queue)
	task.spawn(function()
		pcall(function()
			HttpService:PostAsync(LOG_URL, batch, Enum.HttpContentType.TextPlain)
		end)
	end)
end

local function ensureFlush()
	if flushStarted or not RunService:IsServer() or not RunService:IsStudio() then
		return
	end
	flushStarted = true
	task.spawn(function()
		while true do
			task.wait(2)
			flushHttp()
		end
	end)
	if RunService:IsServer() then
		game:BindToClose(function()
			flushHttp()
		end)
	end
end

function Log.Write(tag: string, message: string, level: string?)
	level = level or "INFO"
	local side = RunService:IsServer() and "Server" or "Client"
	local line = string.format("[%s][BridgeDefense][%s][%s] %s", os.date("%H:%M:%S"), side, tag, tostring(message))
	table.insert(lines, line)
	if #lines > MAX then
		table.remove(lines, 1)
	end
	if level == "ERROR" or level == "WARN" then
		warn(line)
	else
		print(line)
	end
	if RunService:IsServer() and RunService:IsStudio() then
		table.insert(queue, line)
		ensureFlush()
		-- Профиль / ошибки — сразу на диск, не ждать батч 2с
		if #queue >= 20 or string.find(message, "__BD_PROFILE_", 1, true) or level == "ERROR" then
			flushHttp()
		end
	end
	return line
end

function Log.GetLines(): { string }
	return lines
end

return Log
