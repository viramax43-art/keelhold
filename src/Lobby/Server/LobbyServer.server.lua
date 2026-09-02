local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapBind = require(ReplicatedStorage.Shared.Map.MapBind)
local Log = require(ReplicatedStorage.Shared.Util.Log)

Log.Write("Lobby", "Commission map — binding backend")
MapBind.BindAll()
print("[BridgeDefense] Lobby server started (commission only)")
