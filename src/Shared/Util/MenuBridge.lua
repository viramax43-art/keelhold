--[[
	MenuBridge — клиентский мост открытия вкладок меню.
]]

local MenuBridge = {}
local handler = nil
local queue = {}

function MenuBridge.SetHandler(fn)
	handler = fn
	if handler then
		for _, tab in ipairs(queue) do
			handler(tab)
		end
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
