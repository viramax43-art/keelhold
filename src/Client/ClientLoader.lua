--[[
	ClientLoader — UI + Menu + Flight/Chat init.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientLoader = {}
local ready = false
local loading = false
local readyEvent = Instance.new("BindableEvent")

function ClientLoader.EnsureReady()
	if ready then
		return true
	end
	if loading then
		while loading and not ready do
			readyEvent.Event:Wait()
		end
		return ready
	end
	loading = true
	local player = Players.LocalPlayer
	local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")

	local UIController = require(controllers:WaitForChild("UIController"))
	if not UIController.ScreenGui then
		UIController:Init()
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	if not remotes then
		loading = false
		readyEvent:Fire()
		warn("[BridgeDefense] Remotes unavailable; client initialization will retry")
		return false
	end
	local MenuController = require(controllers:WaitForChild("MenuController"))
	if MenuController.Init then
		MenuController:Init({
			Remotes = remotes,
			UI = UIController.ScreenGui,
		})
	end

	local function safeInit(name)
		local mod = controllers:FindFirstChild(name)
		if not mod then
			return
		end
		local ok, ctrl = pcall(require, mod)
		if ok and ctrl and ctrl.Init then
			local initOk, initError = pcall(function()
				ctrl:Init()
			end)
			if not initOk then
				warn(string.format("[BridgeDefense] %s init failed: %s", name, tostring(initError)))
			end
		elseif not ok then
			warn(string.format("[BridgeDefense] %s require failed: %s", name, tostring(ctrl)))
		end
	end

	safeInit("CombatController")
	safeInit("FlightController")
	safeInit("ChatController")

	ready = true
	loading = false
	readyEvent:Fire()
	return true
end

return ClientLoader
