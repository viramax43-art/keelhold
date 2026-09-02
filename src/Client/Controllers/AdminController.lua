local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Players = game:GetService("Players")

local AdminController = {}

function AdminController:Init()
	local isAdmin = false
	for _, id in ipairs(AdminConfig.AdminUserIds or {}) do
		if Players.LocalPlayer.UserId == id then
			isAdmin = true
			break
		end
	end
	if not isAdmin then
		return
	end
	-- Minimal: no UI unless admin ids set
end

return AdminController
