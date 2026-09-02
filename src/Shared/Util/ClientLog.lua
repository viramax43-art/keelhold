--[[
	ClientLog — только Output, без HTTP / BindToClose.
]]

local ClientLog = {}

function ClientLog.Write(tag: string, message: string, level: string?)
	level = level or "INFO"
	local line = string.format("[%s][BridgeDefense][Client][%s] %s", os.date("%H:%M:%S"), tag, tostring(message))
	if level == "ERROR" or level == "WARN" then
		warn(line)
	else
		print(line)
	end
end

return ClientLog
