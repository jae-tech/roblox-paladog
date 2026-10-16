--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local policy = require(script.Parent.TestPolicy)
local isAllowed = require(script.Parent.Guard)

local function guard()
	assert(
		isAllowed(
			RunService:IsStudio(),
			ReplicatedStorage:GetAttribute("P0TestBuild") == true,
			game.GameId,
			policy.allowedUniverseIds
		),
		"test harness requires Studio, test build marker, and approved universe"
	)
end

guard()
ReplicatedStorage:SetAttribute("P0AuthorizedTestUniverse", game.GameId)
local tests = script.Parent.Tests
local Runner = require(tests.Runner)
local suite = require(tests.unit.P0)
local fixtures = {
	clock = require(tests.fixtures.FakeClock),
	rng = require(tests.fixtures.FakeRng),
	store = require(tests.fixtures.InMemoryProfileStore),
}
local GameServer = ServerScriptService.GameServer
local GameClient = game:GetService("StarterPlayer").StarterPlayerScripts.GameClient
local function p2Env()
	return {
		Protocol = require(ReplicatedStorage.Shared.Protocol),
		Catalog = { version = "remake-db-1" },
		Economy = require(GameServer.Services.Economy),
		RemoteGateway = require(GameServer.Net.RemoteGateway),
		MatchService = require(GameServer.Services.MatchService),
		ProfileService = require(GameServer.Services.ProfileService),
		ProfileSchema = require(GameServer.Services.ProfileSchema),
		newStore = require(tests.fixtures.InMemoryStoreAdapter),
	}
end
local SUITES = {
	["T-TOOL"] = true,
	["T-TOOL-INTENTIONAL-FAIL"] = true,
	["T-P2"] = true,
	["T-P8"] = true,
	["T-R1"] = true,
	["T-R2"] = true,
	["T-R3"] = true,
	["T-R5"] = true,
	["T-R6"] = true,
	["T-3D"] = true,
}

local Harness = {}
function Harness.runSuite(suiteId: string, seed: number)
	guard()
	assert(SUITES[suiteId], "unsupported suite")
	return Runner.run("StudioServer", HttpService:GenerateGUID(false), seed, function(check)
		local battle = {
			Battle = require(GameServer.Battle.Battle),
			Rules = require(GameServer.Battle.Rules),
		}
		if suiteId == "T-3D" then
			require(tests.unit.Spatial3D)({
				ClientController = require(GameClient.Net.ClientController),
				ProfileService = require(GameServer.Services.ProfileService),
				MatchService = require(GameServer.Services.MatchService),
				SessionStore = require(GameServer.Services.SessionStore),
				Battle = battle.Battle,
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				ActionRouter = require(GameClient.Input.ActionRouter),
				SnapshotBuffer = require(GameClient.Net.SnapshotBuffer),
			}, check)
			return
		elseif suiteId == "T-R1" then
			require(tests.unit.R1)(battle, check)
			return
		elseif suiteId == "T-R2" then
			require(tests.unit.R2)(battle, check)
			return
		elseif suiteId == "T-R3" then
			require(tests.unit.R3)({
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				Schema = require(GameServer.Services.ProfileSchema),
				Economy = require(GameServer.Services.Economy),
				Settlement = require(GameServer.Services.Settlement),
				Battle = battle.Battle,
				Db = require(GameServer.Config.Remake.Db),
				ProfileService = require(GameServer.Services.ProfileService),
				MatchService = require(GameServer.Services.MatchService),
				RemoteGateway = require(GameServer.Net.RemoteGateway),
				SessionStore = require(GameServer.Services.SessionStore),
			}, check)
			return
		elseif suiteId == "T-R5" then
			require(tests.unit.R5)({
				Battle = battle.Battle,
				Rules = battle.Rules,
				Db = require(GameServer.Config.Remake.Db),
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				Schema = require(GameServer.Services.ProfileSchema),
				Quests = require(GameServer.Services.Quests),
				Settlement = require(GameServer.Services.Settlement),
				ProfileService = require(GameServer.Services.ProfileService),
				MatchService = require(GameServer.Services.MatchService),
				SessionStore = require(GameServer.Services.SessionStore),
				Text = require(GameClient.Presentation.Text),
				catalog = require(ReplicatedStorage.Shared.RemakeCatalog),
				ActionRouter = require(GameClient.Input.ActionRouter),
				SnapshotBuffer = require(GameClient.Net.SnapshotBuffer),
			}, check)
			return
		elseif suiteId == "T-R6" then
			require(tests.unit.R6)({
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				Schema = require(GameServer.Services.ProfileSchema),
				Settlement = require(GameServer.Services.Settlement),
				Battle = battle.Battle,
				Db = require(GameServer.Config.Remake.Db),
				ProfileService = require(GameServer.Services.ProfileService),
				MatchService = require(GameServer.Services.MatchService),
				RemoteGateway = require(GameServer.Net.RemoteGateway),
				SessionStore = require(GameServer.Services.SessionStore),
			}, check)
			return
		elseif suiteId == "T-P8" then
			require(tests.unit.P8)({
				Adapter = require(GameServer.Persistence.DataStoreAdapter),
				Policy = require(GameServer.Persistence.PersistencePolicy),
				Validator = require(GameServer.Persistence.ProfileValidator),
				Schema = require(GameServer.Services.ProfileSchema),
				ProfileService = require(GameServer.Services.ProfileService),
				MatchService = require(GameServer.Services.MatchService),
				Economy = require(GameServer.Services.Economy),
				Db = require(GameServer.Config.Remake.Db),
				newBackend = require(tests.fixtures.FakeDataStore),
			}, check)
			return
		elseif suiteId == "T-P2" then
			require(tests.unit.P2)(p2Env(), check)
			return
		end
		suite(fixtures, check)
		if suiteId == "T-TOOL-INTENTIONAL-FAIL" then
			check("intentional-failure", 1, 2, 0)
		end
	end, suiteId)
end

-- T-ISOLATION rig: production gateway/services + Mock/InMemory store + real Remotes, test build only.
local rig: { [string]: any }? = nil

function Harness.startNetRig()
	guard()
	if rig then
		return "already running"
	end
	local env = p2Env()
	local Protocol = env.Protocol
	local RemoteBinding = require(GameServer.Net.RemoteBinding)
	local store = env.newStore()
	local state = { tick = 0 }
	local forward: ((number, string, any) -> ())? = nil
	local profiles = env.ProfileService.new({
		store = store,
		clock = os.time,
		spawn = function(fn)
			task.spawn(fn)
		end,
		sessionId = HttpService:GenerateGUID(false),
		jobId = game.JobId,
		receiptCap = Protocol.LIMITS.receiptCap,
		queueCap = Protocol.LIMITS.profileQueueCap,
		log = function(message)
			warn(message)
		end,
	})
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return state.tick
		end,
		newMatchId = function()
			return HttpService:GenerateGUID(false)
		end,
		balanceHash = "remake-db-1",
		send = function(userId, message)
			if forward then
				forward(userId, "ServerMessage", message)
			end
		end,
		maxMatches = Protocol.LIMITS.maxMatches,
		ackCacheSize = Protocol.LIMITS.ackCacheSize,
		moveTtlTicks = Protocol.LIMITS.moveTtlTicks,
	})
	local core = env.RemoteGateway.newCore({
		protocol = Protocol,
		publicCatalog = env.Catalog,
		match = match,
		profiles = profiles,
		clock = os.clock,
		tick = function()
			return state.tick
		end,
		balanceHash = "remake-db-1",
		send = function(userId, channel, payload)
			if forward then
				forward(userId, channel, payload)
			end
		end,
	})
	local _, send, disconnect = RemoteBinding.bind(core, ReplicatedStorage, Players)
	forward = send
	local FixedStep = require(GameServer.Simulation.FixedStep)
	local driver = FixedStep.new()
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		FixedStep.advance(driver, dt, function()
			state.tick += 1
			core.drain()
			match.stepAll()
			if state.tick % 3 == 0 then
				core.publishSnapshots() -- 10 Hz full snapshots at the 30 Hz tick
			end
		end)
	end)
	rig = {
		core = core,
		match = match,
		profiles = profiles,
		store = store,
		disconnect = disconnect,
		heartbeat = heartbeat,
	}
	return "started"
end

function Harness.netRig()
	guard()
	return rig
end

function Harness.stopNetRig()
	guard()
	if rig then
		rig.heartbeat:Disconnect()
		rig.disconnect()
		rig = nil
	end
end

return Harness
