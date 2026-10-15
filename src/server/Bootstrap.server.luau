--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false
local info = require(ReplicatedStorage.Shared.BootstrapInfo)
script:SetAttribute("BootMarker", info.buildMarker)
if ReplicatedStorage:GetAttribute("StageGameplay") == true then
	require(script.Parent.Runtime).start()
end
script:SetAttribute("BootReady", true)
print("Server bootstrap ready", info.buildMarker)
