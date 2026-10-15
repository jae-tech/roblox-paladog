--!strict
-- P0 client boot oracle only; no gameplay/input suite exists yet.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

return {
	inspectBoot = function()
		assert(RunService:IsStudio(), "test harness requires Studio")
		assert(ReplicatedStorage:GetAttribute("P0TestBuild") == true, "missing test build marker")
		-- ServerHarness must first authorize this universe; no client debug remote exists.
		assert(
			ReplicatedStorage:GetAttribute("P0AuthorizedTestUniverse") == game.GameId,
			"universe not approved"
		)
		local bootstrap = Players.LocalPlayer.PlayerScripts.GameClient.Bootstrap
		return {
			ready = bootstrap:GetAttribute("BootReady"),
			marker = bootstrap:GetAttribute("BootMarker"),
		}
	end,
}
