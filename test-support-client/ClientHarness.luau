--!strict
-- Client test oracle: boot inspection (P0) and remote recording for T-ISOLATION (P2). Test build only.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function guard()
	assert(RunService:IsStudio(), "test harness requires Studio")
	assert(ReplicatedStorage:GetAttribute("P0TestBuild") == true, "missing test build marker")
	-- ServerHarness must first authorize this universe; no client debug remote exists.
	assert(
		ReplicatedStorage:GetAttribute("P0AuthorizedTestUniverse") == game.GameId,
		"universe not approved"
	)
end

local received: { { channel: string, payload: any } } = {}
local connections: { RBXScriptConnection } = {}

local function remotes(): Instance
	guard()
	return ReplicatedStorage:WaitForChild("Remotes", 5) :: Instance
end

return {
	runSuite = function(suiteId: string, seed: number)
		guard()
		assert(suiteId == "T-R4" or suiteId == "T-3D-RENDER", "unsupported client suite")
		local client = Players.LocalPlayer.PlayerScripts.GameClient
		local tests = script.Parent.Tests
		local Runner = require(tests.Runner)
		return Runner.run("StudioClient", "studio-client-r4", seed, function(check)
			if suiteId == "T-3D-RENDER" then
				require(script.Parent.SpatialRender)({
					WorldView = require(client.Presentation.WorldView),
					catalog = require(ReplicatedStorage.Shared.RemakeCatalog),
				}, check)
				return
			end
			require(tests.unit.R4)({
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				ClientController = require(client.Net.ClientController),
				SnapshotBuffer = require(client.Net.SnapshotBuffer),
				ActionRouter = require(client.Input.ActionRouter),
				Text = require(client.Presentation.Text),
				HudLayout = require(client.Presentation.HudLayout),
				catalog = require(ReplicatedStorage.Shared.RemakeCatalog),
			}, check)
		end, suiteId)
	end,
	inspectRuntime = function(): any
		guard()
		return require(Players.LocalPlayer.PlayerScripts.GameClient.Runtime).inspect()
	end,
	inspectHUD = function(): any
		guard()
		return require(Players.LocalPlayer.PlayerScripts.GameClient.Runtime).inspect().ui
	end,
	inspectInputState = function(): any
		guard()
		return require(Players.LocalPlayer.PlayerScripts.GameClient.Runtime).inspect().input
	end,
	inspectBoot = function()
		guard()
		local bootstrap = Players.LocalPlayer.PlayerScripts.GameClient.Bootstrap
		return {
			ready = bootstrap:GetAttribute("BootReady"),
			marker = bootstrap:GetAttribute("BootMarker"),
		}
	end,
	record = function()
		local folder = remotes()
		for _, name in { "ServerMessage", "MatchSnapshot" } do
			local event = folder:WaitForChild(name, 5) :: RemoteEvent
			table.insert(
				connections,
				event.OnClientEvent:Connect(function(payload)
					table.insert(received, { channel = name, payload = payload })
				end)
			)
		end
		return #connections
	end,
	received = function()
		guard()
		return table.clone(received)
	end,
	fire = function(name: string, payload: any)
		local event = remotes():WaitForChild(name, 5) :: RemoteEvent
		event:FireServer(payload)
	end,
	bootstrap = function(payload: any)
		local remote = remotes():WaitForChild("GetBootstrap", 5) :: RemoteFunction
		return remote:InvokeServer(payload)
	end,
}
