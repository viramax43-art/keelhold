--[[
	Bootstrap — HttpEnabled сразу (Studio DB через LogServer), затем сервисы.
]]

local HttpService = game:GetService("HttpService")
pcall(function()
	HttpService.HttpEnabled = true
end)

-- Сразу гасим legacy Teleports до того, как игрок успеет наступить на линию
do
	local teleports = workspace:FindFirstChild("Teleports")
	if teleports then
		for _, inst in ipairs(teleports:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.CanTouch = false
			elseif inst:IsA("Script") or inst:IsA("LocalScript") then
				inst:Destroy()
			end
		end
	end
	local sss = game:GetService("ServerScriptService")
	local legacy = sss:FindFirstChild("Script")
	if legacy and legacy:IsA("Script") and legacy.Parent == sss then
		legacy:Destroy()
	end
end

local ServerLoader = require(script.Parent.ServerLoader)
ServerLoader.Load()
game:SetAttribute("BridgeDefenseServerReady", true)
