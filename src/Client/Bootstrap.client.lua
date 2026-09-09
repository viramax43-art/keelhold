local ClientLoader = require(script.Parent.ClientLoader)
ClientLoader.EnsureReady()

local player = game:GetService("Players").LocalPlayer
local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")

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

-- Combat/Flight/Chat already initialized in ClientLoader
safeInit("MobileController")
safeInit("WaveResultController")
safeInit("AdminController")

print("[BridgeDefense] Client controllers loaded")
