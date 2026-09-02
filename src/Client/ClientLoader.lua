--[[
	ClientLoader — UI + Menu init (без серверного FileLog).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	local MenuController = require(controllers:WaitForChild("MenuController"))
	if MenuController.Init then
		MenuController:Init({
			Remotes = remotes,
			UI = UIController.ScreenGui,
		})
	end

	ready = true
	return true
end

return ClientLoader
