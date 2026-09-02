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
		pcall(function()
			ctrl:Init()
		end)
	end
end

safeInit("CombatController")
safeInit("MobileController")
safeInit("WaveResultController")
safeInit("AdminController")

print("[BridgeDefense] Client controllers loaded")
