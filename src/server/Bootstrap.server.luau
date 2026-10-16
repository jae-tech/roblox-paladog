--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Avatars spawn only in the gameplay build (R8 plaza); the P0 harness boots without characters.
Players.CharacterAutoLoads = ReplicatedStorage:GetAttribute("StageGameplay") == true
local info = require(ReplicatedStorage.Shared.BootstrapInfo)
script:SetAttribute("BootMarker", info.buildMarker)
if ReplicatedStorage:GetAttribute("StageGameplay") == true then
	require(script.Parent.Runtime).start()
end
script:SetAttribute("BootReady", true)
print("Server bootstrap ready", info.buildMarker)
