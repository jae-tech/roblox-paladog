--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local info = require(ReplicatedStorage.Shared.BootstrapInfo)
script:SetAttribute("BootMarker", info.buildMarker)
script:SetAttribute("BootReady", true)
print("P0 client bootstrap ready", info.buildMarker)
