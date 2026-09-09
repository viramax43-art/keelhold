--[[
	MenuBridge — клиентский мост открытия вкладок меню.
]]

local MenuBridge = {}
local handler = nil
local queue = {}

function MenuBridge.SetHandler(fn)
	handler = fn
	if handler and #queue > 0 then
		-- Only the latest requested modal can remain visible.
		handler(queue[#queue])
		table.clear(queue)
	end
end

function MenuBridge.OpenTab(tabName: string)
	if handler then
		handler(tabName)
	else
		table.insert(queue, tabName)
	end
end

function MenuBridge.IsReady(): boolean
	return handler ~= nil
end

return MenuBridge
