--[[
	ClientLoader — UI + Menu init (без серверного FileLog).
]]

local Players = game:GetService("Players")

local ClientLoader = {}
local ready = false

function ClientLoader.EnsureReady()
	if ready then
		return true
	end
	local player = Players.LocalPlayer
	local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")

	local UIController = require(controllers:WaitForChild("UIController"))
	if not UIController.ScreenGui then
		UIController:Init()
	end

	local MenuController = require(controllers:WaitForChild("MenuController"))
	if MenuController.Init then
		MenuController:Init()
	end

	ready = true
	return true
end

return ClientLoader
