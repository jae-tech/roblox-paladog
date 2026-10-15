--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false
local info = require(ReplicatedStorage.Shared.BootstrapInfo)
script:SetAttribute("BootMarker", info.buildMarker)
script:SetAttribute("BootReady", true)
print("P0 server bootstrap ready", info.buildMarker)
